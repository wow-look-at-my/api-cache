# rustc

Sources: sccache `src/compiler/rust.rs` (**Apache-2.0**, 4101 lines — adaptable);
buildcache `src/wrappers/rust_wrapper.cpp` (**zlib**, 893 lines, whose header comment says
it "is inspired heavily by the rules that sccache follows"); probes `out/05-rustc.txt` and
`out/06-rustc-wrapper.txt` against `rustc 1.94.1` / `cargo` on this machine.

The headline difference from C: **the unit of caching is a whole crate, not a
translation unit.** There is no preprocessor, so there is no preprocessor mode. rustc
caching is *direct mode only* — buildcache literally declares the capability
`force_direct_mode` for its rust wrapper, with the comment "we require direct mode,
because of how rustc is invoked".

## 1. How the wrapper is invoked

Cargo's protocol (probe `out/06-rustc-wrapper.txt`):

- `RUSTC_WRAPPER=<prog>` → cargo runs `<prog> <path-to-rustc> <args…>`.
- `RUSTC_WORKSPACE_WRAPPER=<prog>` → same, but **only for crates that are workspace
  members** (path dependencies you are editing), not for registry dependencies.
- **Both set** → cargo nests them: `$RUSTC_WRAPPER $RUSTC_WORKSPACE_WRAPPER $rustc <args…>`.
  Measured, not inferred.
- The wrapper is also invoked for cargo's **probe** calls, which are not compiles:
  - `<rustc> -vV`
  - `<rustc> - --crate-name ___ --print=file-names --crate-type bin --crate-type rlib …`
    (note the `-`: source from stdin).
  A wrapper must pass these through untouched and fast. sccache detects them as
  non-cacheable and execs.

A real compile as cargo emits it:

```
rustc --crate-name wraptest --edition=2021 src/main.rs \
  --error-format=json --json=diagnostic-rendered-ansi,artifacts,future-incompat \
  --crate-type bin --emit=dep-info,link \
  -C embed-bitcode=no -C debuginfo=2 \
  --check-cfg 'cfg(docsrs,test)' --check-cfg 'cfg(feature, values())' \
  -C metadata=86bbc085d2c2961a -C extra-filename=-912fa8033c7dbe6d \
  --out-dir /tmp/wraptest/target/debug/deps \
  -C incremental=/tmp/wraptest/target/debug/incremental \
  -L dependency=/tmp/wraptest/target/debug/deps
```

Two things jump out: `--emit=dep-info,link` (no `metadata`) and
`-C incremental=…` — a default `cargo build` is **not cacheable** by either
sccache or buildcache without configuration. `cargo` only drops `-C incremental` for
release profiles or when `CARGO_INCREMENTAL=0`/`[profile.dev] incremental = false`. This is
the single most common reason a user reports "sccache never hits".

## 2. Cacheability rules

sccache (`parse_arguments`, rust.rs ~1138) and buildcache (`parse_options`) agree on
almost all of these. `cannot_cache!` in sccache and `panic()` in buildcache both mean
"decline, run the real rustc".

**Required:**

| Requirement | sccache | buildcache |
|---|---|---|
| exactly one input source path | yes | yes ("Cannot handle multiple inputs") |
| `--emit` present, exactly once | yes ("more than one --emit") | yes |
| `--emit` ⊆ {`link`, `metadata`, `dep-info`} | yes ("unsupported --emit"), and not *just* `dep-info` | yes, **and** requires both `link` **and** `metadata` |
| `--crate-name` | yes | yes |
| `--crate-type` | yes; restricted set | yes; only `lib`/`rlib`/`staticlib` |
| `--out-dir` | yes | yes |

**Refused outright:**

| Thing | Reason |
|---|---|
| `-C incremental=<dir>` | rustc writes an opaque, self-referential artifact tree into that directory which the cache neither enumerates nor restores. buildcache's comment adds the sharper point: *dropping* the flag instead would make an incremental and a non-incremental compile share a key. |
| `-o <file>` | buildcache: `UNSUPPORTED`. Cargo never uses it; `--out-dir` plus the derived names is the model. |
| `--sysroot` | buildcache: `UNSUPPORTED` (changes which std is linked without changing anything hashed). |
| `-` (stdin source) | buildcache: `UNSUPPORTED`. |
| `--remap-path-prefix` | buildcache: `UNSUPPORTED`. (sccache hashes it as an ordinary argument.) |
| `--target <x>.json` | A custom target spec file. buildcache refuses; **sccache hashes the file's content** and then excludes `--target` from the argument hash. sccache's is the better answer. |
| a `-l static=NAME` whose archive cannot be resolved along the `-L` paths | buildcache declines rather than cache a result that a change to that library would not invalidate. |
| `@response` files | buildcache has a TODO and refuses. sccache supports them. |
| any **unrecognised** option | buildcache treats it as `UNSUPPORTED`, with an explicit rationale: an unknown option cannot be hashed (it may take a separate argument that would then be mistaken for the input file) and cannot be ignored (it may change output). **This is the right default and worth copying.** |

**Not refused but notable:**

- `-C extra-filename=<s>` — part of the output filenames. buildcache refuses an *empty*
  value.
- `--diagnostic-width` — **deliberately ignored** by both. Cargo derives it from the
  terminal width, so hashing it would invalidate the entire cache on every terminal
  resize. The stated cost: replayed stderr may be wrapped for a different width.
- `RUSTC_COLOR` — filtered out of the env hash by both; colour is controlled by the
  `--color` flag, and rustc errors when both are set.
- `proc-macro` crates — nothing special in either implementation; a proc-macro crate is
  a `--crate-type proc-macro` cdylib and is cacheable *as a compile*. What is **not**
  cacheable is its *effect*: a proc macro that reads a file or the clock at expansion time
  produces output the cache cannot key. rustc reports files read via `include!` and env
  vars read via `env!`/`option_env!` in dep-info (§4), but a proc macro using
  `std::fs::read` directly is invisible. Same for **build scripts** (`build.rs`): cargo
  runs the compiled `build.rs` binary itself, outside any `RUSTC_WRAPPER`, so its
  *execution* is never cached — only the compilation of `build.rs` is.

## 3. Outputs

rustc's output filenames are derived, not stated. Both wrappers ask rustc:

```
$ rustc --crate-name demo --crate-type lib -C extra-filename=-abc123 --print file-names lib.rs
libdemo-abc123.rlib
```

(probe `out/05-rustc.txt`). buildcache then patches the list up:

- if `metadata` is in `--emit`, add a `.rmeta` sibling for every `.rlib`
  (`--print file-names` does not list rmeta);
- if `dep-info` is in `--emit`, add `<crate_name><extra_filename>.d`;
- resolve each against `--out-dir`.

sccache does the same and additionally *removes* binaries from the list when `link` is
absent, because rustc still prints them for a `--emit=metadata` (`cargo check`) run —
citing rust-lang/rust#68799.

So the output set is: `.rlib` / `.rmeta` / the binary / `.d`, plus, under `-Zprofile`, a
`.gcno`, and under `-Cprofile-use`, sccache also tracks the profile file so that
distributed compilation can ship it.

## 4. The key

sccache's composition (`generate_hash_key`, rust.rs ~1493), in order:

1. `CACHE_VERSION` — a constant bumped whenever the hashing rules change. (buildcache's
   `HASH_VERSION = "5"` is the same idea, per-wrapper.)
2. **The digests of every shared library in the compiler's sysroot** — see §5.
3. **The full command line**, with these exclusions and normalisations:
   - dropped: `--extern`, `-L`, `--check-cfg`, `--out-dir`, `--diagnostic-width`; and
     `--target` when it names a `.json` (whose content is hashed instead). `--extern` and
     `-L` are dropped because they are paths; what they point at is hashed by content.
   - `--cfg` arguments are **partitioned out, sorted, and appended** — older cargo did not
     emit them in a deterministic order.
4. digests of **every source file** from dep-info (§4a);
5. digests of **every `--extern` artifact**;
6. digests of **every static library** named by `-l static=` (hashed as archives —
   `hash_all_archives`, which normalises away an `.a`'s embedded timestamps);
7. the digest of the `--target` json, if any;
8. **environment variables**: every `env-dep` rustc reported (§4b), sorted; **plus** every
   `CARGO_*` variable in the environment, sorted, minus `CARGO_MAKEFLAGS` (contains
   jobserver fds), `CARGO_REGISTRIES_*` (secrets), `CARGO_BUILD_JOBS` (parallelism only)
   and `CARGO_ENCODED_RUSTFLAGS` (already in the argv);
9. **the cwd** — unconditionally, with the comment "This will wind up in the rlib";
10. the compiler version string.

buildcache's variant differs in two interesting ways:
- `--extern` paths are dropped from the key, but the **binding name paired with the
  artifact's basename** (`name=libfoo-abc.rlib`) is added as a synthetic
  `--extern-binding=` argument, both lists sorted. Its reasoning is exact: "the same set
  of artifacts bound to different names compiles differently", so if you only sort the
  paths, a swap of two names is invisible.
- it hashes static-library **content** through `get_hash_extra_content()` rather than as
  a command-line argument, with the same "don't tie the key to a build root" reasoning.

RUSTFLAGS never appears directly: cargo folds it into the argv (and into
`CARGO_ENCODED_RUSTFLAGS`, which sccache therefore skips as a duplicate).

### 4a. `--emit=dep-info`: the first pass

Both wrappers run rustc **twice on a miss**: once with `--emit=dep-info` to a temp file to
learn the inputs, and once for real. The first-pass argv is the real argv with `--emit`
and `--out-dir` **removed** and `-o <tmp> --emit=dep-info` appended. (buildcache's removal
loop is a two-state filter over `--emit`/`--out-dir` and their values.)

Format, measured:

```
/tmp/xxx/demo.d: lib.rs helper.rs inc.txt

lib.rs:
helper.rs:
inc.txt:

# env-dep:PATH_LIKE_VAR=hello
```

- Line 1 is `target: dep dep dep` — Makefile syntax, one line.
- Then a **phony line per dependency** (the `-MP` equivalent).
- Then `# env-dep:` comment lines.
- **Escaping**: rustc escapes a space as `\ ` and leaves everything else alone. Measured
  with a directory literally named `sp ace`:
  `/tmp/xxx/sp\ ace/lib.rs`. buildcache's `parse_dep_info_line` implements exactly this —
  split on spaces, and a part ending in `\` continues into the next. It **returns false**
  (and the wrapper declines the invocation) for any line it does not understand, with the
  comment: "a shorter but well formed dependency list would pass direct mode validation
  unnoticed". That refusal discipline is the correct posture for any dep parser.
- The dependency list includes files reached by `include!`/`include_str!` (`inc.txt`
  above), not just `mod` files.

### 4b. `# env-dep:` — rustc tells you which env vars it read

rustc records every variable consulted by `env!` / `option_env!` during the compile:

- set: `# env-dep:NAME=VALUE`
- **unset: `# env-dep:NAME`** (no `=`) — measured. This distinction is load-bearing:
  `option_env!("X")` is `None` when unset and `Some("")` when empty, and those compile
  differently. buildcache represents "unset" with a single NUL byte, chosen because it
  cannot occur in a dep-info record.
- Both wrappers filter `RUSTC_COLOR` out; buildcache also filters `CARGO_MAKEFLAGS`.

This is a facility gcc has no equivalent of, and it is the reason rustc caching can be
*more* precise about the environment than C caching can.

## 5. Compiler identity

buildcache's rust wrapper (`get_program_id`) hashes:

1. `HASH_VERSION` (a wrapper-format constant),
2. the stdout of `rustc -vV`,
3. and the content of **every `.so` (or `.dll`) in `$(rustc --print=sysroot)/lib`**,
   sorted by path, hashed deterministically.

`rustc -vV` on this machine:

```
rustc 1.94.1 (e408947bf 2026-03-25)
binary: rustc
commit-hash: e408947bfd200af42db322daf0fadfe7e26d3bd1
commit-date: 2026-03-25
host: x86_64-unknown-linux-gnu
release: 1.94.1
LLVM version: 21.1.8
```

`-vV` alone would be a decent identity (it carries the commit hash and the LLVM version),
but the sysroot shared libraries are where `librustc_driver-*.so` and the standard library
actually live, and a `rustup` toolchain can be patched in place. sccache does the same:
`compiler_shlibs_digests` is hash input #2, and the digest of those alone forms its
"weak toolchain key".

Both wrappers also **scrub the environment** around every rustc child process. buildcache
unsets `LD_PRELOAD`, `RUNNING_UNDER_RR`, `HOSTNAME`, `PWD`, `HOST`, `RPM_BUILD_ROOT`,
`SOURCE_DATE_EPOCH`, `RPM_PACKAGE_RELEASE`, `MINICOM`, `RPM_PACKAGE_VERSION` before
running it — a list evidently accumulated from distro build environments that leaked into
outputs.

## 6. Worked examples

| argv (after the wrapper strips its own name) | Verdict |
|---|---|
| `rustc -vV` | Pass through (cargo probe). |
| `rustc - --crate-name ___ --print=file-names …` | Pass through (cargo probe; stdin source). |
| `rustc --crate-name x --edition=2021 src/lib.rs --crate-type lib --emit=dep-info,link -C extra-filename=-abc --out-dir target/debug/deps -L dependency=target/debug/deps --extern foo=…/libfoo-1.rlib` | Cacheable (sccache). buildcache declines: `metadata` missing from `--emit`. |
| the same plus `-C incremental=target/debug/incremental` | **Not cacheable** — this is what plain `cargo build` emits. |
| `… --emit=metadata …` (`cargo check`) | Cacheable by sccache; outputs are `.rmeta` + `.d`, binaries pruned from `--print file-names`. |
| `… --emit=dep-info` alone | Not cacheable (sccache: "don't support *just* dep-info"). |
| `… --target aarch64-unknown-none.json …` | sccache: cacheable, the json's content is hashed. buildcache: declines. |
| `… -l static=z -L native=/opt/lib …` | Cacheable iff `/opt/lib/libz.a` resolves; its content is hashed, the `-L` path is not. |
| `… --extern a=libfoo.rlib --extern b=libbar.rlib` | Cacheable; the rlib contents are hashed, and the `name=basename` bindings are hashed sorted (buildcache) so that swapping `a` and `b` changes the key. |
| `build.rs` itself | Its *compilation* goes through the wrapper and is cacheable. Its *execution* by cargo does not go through the wrapper at all. |
