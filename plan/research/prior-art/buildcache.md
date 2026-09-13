# buildcache (mbitsnbites)

The user's flagged closest prior art. Deep-dived from the project's own repo
(now hosted at GitLab; the old GitHub mirror is archived and just redirects).

- Canonical repo: https://gitlab.com/bits-n-bites/buildcache
- Archived GitHub mirror (redirect only): https://github.com/mbitsnbites/buildcache
- Stars/forks at time of writing: 28 stars, 14 forks (`GET /api/v4/projects/bits-n-bites%2Fbuildcache`)
  — a small, low-traffic project. This is the evidentiary basis for "low
  testing/contributors": issue volume and fix velocity below are also small.

## License

**zlib License**, verified by fetching the repo's own `LICENSE` file directly:

> Copyright (c) 2018-2024 Marcus Geelnard
>
> This software is provided 'as-is', without any express or implied warranty.
> [...] Permission is granted to anyone to use this software for any purpose,
> including commercial applications, and to alter it and redistribute it
> freely [...] The origin of this software must not be misrepresented; you
> must not claim that you wrote the original software.

**Correction / discrepancy note**: the task briefing described this project as
MIT-licensed. The actual `LICENSE` file at
`https://gitlab.com/bits-n-bites/buildcache/-/raw/master/LICENSE` is the **zlib
license**, not MIT — distinguishable from MIT by its "must not be misrepresented as
original" / "altered versions must be plainly marked" language, which MIT does not
have, and by its lowercase "as-is" disclaimer phrasing vs. MIT's all-caps "AS IS."
Both are short, permissive, non-copyleft licenses with no material practical
difference for this org's "no viral license" screening — zlib is if anything even
more permissive than MIT (no requirement to reproduce the license text in binary
distributions, only in source). Either way: **safe to study and take design
inspiration from freely.**

## Why this is the closest prior art to api-cache's own plan

buildcache is the one existing tool in this space that already separates a fixed
C++ **engine** (hashing, storage, compression, remote backends, stats) from a
**per-tool wrapper contract** implemented in an embedded scripting language (Lua) —
architecturally the same split api-dsl documents for api-cli/api-mirror: a shared
mechanism layer with no vocabulary of its own, and per-consumer vocabulary layered
on top through a declarative/scriptable surface. The built-in C++ wrappers
(gcc, msvc, clang-cl, ghs, ti-*, rust, cppcheck, ccc-analyzer) are themselves just
implementations of that same contract, compiled in rather than scripted — so the
Lua API doubles as the de facto spec for "what must a wrapper module of api-cache
be able to declare" regardless of whether api-cache expresses it as Lua, as XML
(matching the org's existing api-dsl convention), or as something else.

## The Lua wrapper contract

Source: `doc/lua.md`, `src/wrappers/lua_wrapper.cpp`.

### Discovery and identification

- Buildcache looks for `.lua` wrapper scripts in `$BUILDCACHE_LUA_PATH` (colon- on
  POSIX, semicolon- on Windows-separated list of directories), then
  `$BUILDCACHE_DIR/lua`, before falling back to the compiled-in wrappers.
- **The very first line of a wrapper script must be a comment holding a regex
  match directive**, e.g. `-- match(gcc.*)`. Buildcache reads just that line to
  decide which invoked-program names (by basename, matched against the compiler
  name buildcache was invoked as / asked to wrap) this script is even a candidate
  for, without loading/executing the whole script for every candidate on every
  invocation — a cheap pre-filter before the expensive step.
- After the regex pre-filter, an optional `can_handle_command()` function lets the
  script inspect the full argument list and refuse further (return false) even
  though the name matched — e.g. a `gcc.*`-matching script declining because the
  actual invocation is `gcc -E` (preprocess-only, nothing cacheable) or some other
  argument shape the script doesn't support.

### The full function contract (called by the C++ core, in this order)

| Function | Returns | Default if undefined | Called when |
|---|---|---|---|
| `can_handle_command()` | bool | `true` | First — gate before anything else runs |
| `resolve_args()` | (mutates `m_args` in place) | no-op | Immediately after acceptance — expands response files (`@file` args) etc. into `m_args`, keeping `m_unresolved_args` as the pre-expansion original |
| `get_capabilities()` | table of capability strings | empty (opts out of everything) | Once, to learn what optional engine behaviors this wrapper supports |
| `get_program_id()` | string | an MD4 hash (of what, unspecified beyond "identifies the program") | Folded into the cache key — buildcache's analogue of ccache's `compiler_check` |
| `get_relevant_arguments()` | table of strings | all arguments | Filters `m_args` down to just the ones that affect the *output*, e.g. dropping `-o <path>` itself from the hash while still tracking output path separately |
| `get_relevant_env_vars()` | table of `name -> value` | none | Environment variables folded into the hash (e.g. a target-arch env var a cross-compiler reads) |
| `get_hash_extra_content()` | string | `""` | An arbitrary extra string a wrapper can inject into the hash for anything the above can't express |
| `preprocess_source()` | string (preprocessed source) | — | Only for wrappers claiming preprocessor-based caching; also expected to populate `m_implicit_input_files` as a side effect, for direct mode |
| `get_input_files()` | table of paths | — | **Direct-mode only.** Named input files (the equivalent of ccache's manifest include list) instead of relying on a preprocessor run |
| `get_build_files()` | table of `logical-name -> expected_file_t` | empty | The set of output files the invocation is expected to produce — the multi-output equivalent of ccache's ".o (+ .d, + stderr)" problem, generalized to an arbitrary named set per wrapper |
| `run_for_miss()` | table `{std_out, std_err, return_code}` | — | Actually runs the real tool on a miss |
| `finalize_after_hit()` | (side effects only) | no-op | Runs after a cache **hit**, for work a hit still needs done that isn't "restore the cached files" — the documented example is regenerating a `.d` dependency file so downstream build-system dependency tracking still works even though the compiler itself never ran |

### Globals available to a wrapper script

- **`m_args`** — the full argument array, `m_args[1]` is the program path itself
  (Lua 1-indexing).
- **`m_unresolved_args`** — read-only, the arguments *before* `resolve_args()`
  ran — lets a wrapper compare pre/post response-file expansion if needed.
- **`m_implicit_input_files`** — populated by `preprocess_source()`, read back by
  the engine for direct-mode manifest construction (buildcache's equivalent of
  ccache's manifest include list, but sourced from the wrapper's own preprocessing
  step rather than the engine parsing preprocessor output itself).

### Support library exposed to scripts (`require_std("bcache")`)

`dir_exists`/`file_exists`, `get_dir_part`/`get_file_part`/`get_extension`,
`get_file_info`, `log_debug/info/warning/error/fatal`, `parse_json`, `run` (execute
a subprocess) and `split_args`. Standard Lua libraries (`coroutine`, `debug`, `io`,
`math`, `os`, `package`, `string`, `table`, `utf8`) are available individually or
all at once via `require_std("*")` — a deliberately explicit opt-in rather than a
full unrestricted Lua environment, i.e. a sandboxing gesture (though not a hard
security boundary — nothing here claims to sandbox against a malicious script,
just to keep the default surface small and legible).

### Data flow of one invocation (synthesized from the table above + `program_wrapper.hpp`)

1. Engine matches `argv[0]`/first arg against every wrapper's regex; for each match,
   calls `can_handle_command()`.
2. On accept: `resolve_args()` (response-file expansion), then
   `get_capabilities()` once (informs engine which optional fast paths to try —
   `direct_mode`, `force_direct_mode`, `hard_links`, `create_target_dirs`).
3. Engine computes the cache key from `get_program_id()` +
   `get_relevant_arguments()` + `get_relevant_env_vars()` +
   `get_hash_extra_content()`, plus — in direct mode — `get_input_files()` (or the
   files gathered via `preprocess_source()`'s `m_implicit_input_files` side
   channel) hashed the way ccache's manifest hashes includes.
4. Cache hit → restore `get_build_files()`'s declared outputs from the store, then
   call `finalize_after_hit()` for any hit-path-only side work.
5. Cache miss → `run_for_miss()` actually executes the real tool; its captured
   stdout/stderr/return code plus the resulting `get_build_files()` outputs are
   what gets stored under the computed key.

## Built-in (compiled) wrappers, `src/wrappers/`

`gcc_wrapper`, `clang_cl_wrapper`, `msvc_wrapper`, `ghs_wrapper` (Green Hills),
`ti_arm_cgt_wrapper`, `ti_arp32_wrapper`, `ti_c6x_wrapper`, `ti_c7x_wrapper` +
`ti_common_wrapper` (shared TI logic), `qcc_wrapper` (QNX), `rust_wrapper`,
`cppcheck_wrapper`, `ccc_analyzer_wrapper` (clang static analyzer), plus
`lua_wrapper` (the dispatcher that hosts the scripting contract above) and
`program_wrapper` (the abstract base every one of these — Lua or C++ — actually
implements). Plain `clang`/`gcc` share one wrapper by CLI-shape compatibility;
MSVC's `cl.exe` gets its own because of `/showIncludes`, `/Zi` PDB handling, and
its wholly different flag syntax (see lessons.md for the concrete gotchas).

## Capabilities system

`get_capabilities()` returns a table of opt-in strings the engine only acts on if
present — the same "don't assume, ask" posture as ccache's per-feature sloppiness
flags, but for engine behavior rather than correctness relaxations:

- **`direct_mode`** — this wrapper supports direct-mode keying at all (via
  `get_input_files()` or `preprocess_source()`'s implicit-input side channel).
- **`force_direct_mode`** — go further: always use direct mode for this wrapper
  even when the engine's global setting would otherwise fall back to
  preprocessor-based keying.
- **`hard_links`** — this wrapper's outputs are safe to hard-link into place on a
  hit rather than copied (same tradeoff ccache names explicitly — see ccache.md).
- **`create_target_dirs`** — ask the engine to create missing output directories
  before restoring files, rather than assuming the invoking build already did.

## Direct mode / implicit input tracking

Direct mode in buildcache is keyed off exactly the same idea as ccache's: skip
running the real preprocessor for the *hash*, and instead validate a manifest of
"the last time this exact command+args ran, it read these include files with these
content hashes." The wrapper contract exposes two ways to feed that manifest:
`get_input_files()` (an explicit, engine-agnostic list a wrapper can compute any
way it likes — e.g. by parsing a `.d` file itself) or the `preprocess_source()` +
`m_implicit_input_files` side-channel pattern (used when the wrapper legitimately
must run something preprocessor-like anyway and can harvest the include list as a
byproduct). This is strictly more flexible than ccache's single built-in
"run cpp -E to discover includes" path, at the cost of pushing correctness onto
each wrapper's own implementation — which is exactly the class of bug the GitLab
issue tracker shows recurring (see "Known weaknesses" below: a Linux-kernel build
failing under direct mode, a false-positive cache hit for Rust, and cppcheck's
inline-suppression comments not affecting the hash while affecting output).

## Config: environment variables and config-file keys

Source: `doc/configuration.md`, `src/config/configuration.cpp`. Every
`BUILDCACHE_*` env var has a matching lowercase key in the JSON config file
(`$BUILDCACHE_DIR/buildcache.conf`); env var wins over config file when both are
set (standard precedence, not spelled out in more granular tiers the way ccache's
manual documents its four-tier stack).

| Env var | Config key | Meaning | Default |
|---|---|---|---|
| `BUILDCACHE_DIR` | — (this *is* the config root) | Cache root directory | `$HOME/.buildcache` |
| `BUILDCACHE_ACCURACY` | `accuracy` | `STRICT` / `DEFAULT` / `SLOPPY` — see below | `DEFAULT` |
| `BUILDCACHE_CACHE_LINK_COMMANDS` | `cache_link_commands` | Cache the link step too, not just compiles | `false` |
| `BUILDCACHE_CACHE_ON_FAILURE` | `cache_on_failure` | Cache a run even if it exited non-zero | `false` |
| `BUILDCACHE_COMPRESS` | `compress` | Compress stored entries | `true` |
| `BUILDCACHE_COMPRESS_FORMAT` | `compress_format` | `LZ4` (fast, bigger) or `ZSTD` (slower, smaller); default resolves to LZ4 | `DEFAULT` (=LZ4) |
| `BUILDCACHE_COMPRESS_LEVEL` | `compress_level` | Compression level | `-1` (codec default) |
| `BUILDCACHE_DEBUG` | `debug` | Debug verbosity, 1 (DEBUG, max) .. 5 (FATAL only), `-1` disables | off |
| `BUILDCACHE_DIRECT_MODE` | `direct_mode` | Enable direct-mode keying | `true` |
| `BUILDCACHE_DISABLE` | `disable` | Global kill switch, bypass entirely | `false` |
| `BUILDCACHE_HARD_LINKS` | `hard_links` | Permit hard-linking cached files into place (only for wrappers whose capability list allows it) | `false` |
| `BUILDCACHE_HASH_EXTRA_FILES` | `hash_extra_files` | Extra file(s) whose *content* is folded into the hash, regardless of wrapper | none |
| `BUILDCACHE_IMPERSONATE` | `impersonate` | Explicit "the real tool I'm wrapping is X" override, for masquerade-by-invocation instead of by symlink name; **when set, buildcache's own CLI args become unavailable** (the whole argv is assumed to be for the wrapped tool) | none |
| `BUILDCACHE_LOG_FILE` | `log_file` | Log destination (empty = stdout) | none |
| `BUILDCACHE_LUA_PATH` | `lua_paths` | Extra search paths for Lua wrapper scripts | none |
| `BUILDCACHE_MAX_CACHE_SIZE` | `max_cache_size` | Total local cache size budget (bytes) | 5368709120 (5 GiB) |
| `BUILDCACHE_MAX_LOCAL_ENTRY_SIZE` | `max_local_entry_size` | Per-entry size cap, local (uncompressed) | 134217728 (128 MiB) |
| `BUILDCACHE_MAX_REMOTE_ENTRY_SIZE` | `max_remote_entry_size` | Per-entry size cap, remote (uncompressed) | 134217728 (128 MiB) |
| `BUILDCACHE_PERF` | `perf` | Enable per-invocation performance logging | `false` |
| `BUILDCACHE_PREFIX` | `prefix` | A command to prefix onto the real tool invocation on a miss (e.g. inject `nice`/`distcc`) | none |
| `BUILDCACHE_READ_ONLY` | `read_only` | Read/use but never write the cache (any tier) | `false` |
| `BUILDCACHE_READ_ONLY_REMOTE` | `read_only_remote` | Read/use but never write specifically the *remote* tier | `false` |
| `BUILDCACHE_STAT_ID` | `stat_id` | A free-form session/group ID for partitioning stats (see `--show-stats PATTERN`) | none |
| `BUILDCACHE_TERMINATE_ON_MISS` | `terminate_on_miss` | Abort the build outright on any cache miss — a CI-lockdown mode: "prove every action is cached" | `false` |
| `BUILDCACHE_REMOTE` | `remote` | Remote cache URL: `redis://`, `http://`, or `s3://host:port/path` | none (local only) |
| `BUILDCACHE_REMOTE_LOCKS` | `remote_locks` | Use a slower, more correct file-locking discipline against the remote | `false` |
| `BUILDCACHE_REDIS_USERNAME` / `_PASSWORD` | `redis_username`/`redis_password` | Redis auth | none |
| `BUILDCACHE_S3_ACCESS` / `_SECRET` | `s3_access`/`s3_secret` | S3 credentials, falling back to standard `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` | env fallback |
| `BUILDCACHE_S3_SIGNATURE_VERSION` | `s3_signature_version` | S3 signing scheme, v2 or v4 | `4` |

**`accuracy` modes** — the direct analogue of ccache's `sloppiness=`, but
collapsed to three named presets instead of a fine-grained comma list:
- `STRICT` — maximum correctness, considers full paths and line numbers.
- `DEFAULT` — "a balance between performance and correctness," notably *ignores
  debug paths* (i.e. behaves roughly like ccache's `base_dir`/relative-path
  normalization, on by default rather than opt-in).
- `SLOPPY` — "optimize for maximum cache hit ratio," ignores all path information
  outright.

This preset-based framing (three tiers) vs. ccache's ~14 independently-named
sloppiness flags is a genuine design fork worth flagging in lessons.md: presets
are easier to reason about and document, but coarser — a user who wants
`system_headers`-sloppy but not `time_macros`-sloppy has no equivalent knob here.

## Local cache on-disk layout

Source: `src/cache/local_cache.cpp`. Two-level hex sharding under `.buildcache/c/`:

```
$BUILDCACHE_DIR/
├── buildcache.conf
├── tmp/
└── c/
    └── <2 hex chars>/            # first byte of the key hash
        └── <30 hex chars>/       # remaining hash, one dir per cache entry
            ├── .entry            # metadata: stdout, stderr, return code, file-id list
            ├── .manifest         # direct-mode manifest(s) — up to NUM_MANIFESTS_PER_ENTRY = 4
            └── <cached files>    # named by logical file id from get_build_files()
```

Up to **4 manifests can coexist per entry** in direct mode — the documented reason
is retaining cache validity "across branch switches" (two different include sets
that happen to hash to the same command+args key) without unbounded lookup cost;
this is buildcache's answer to the same problem ccache's multi-manifest-per-key
design solves. Compression is applied per stored file when
`compression_mode() == ALL`. Per-shard `stats.json` files track hits/misses etc.,
and eviction is a straightforward "sum entry sizes, and once over
`max_cache_size`, sort candidate entries by access time and delete oldest first,
holding a lock file during deletion" — same "approximate bounded LRU sweep" shape
as ccache's cleanup and go-s3-server's own two-walk eviction design
(`/home/user/go-s3-server/CLAUDE.md`, `eviction.go`).

## Remote backends: wire shape

- **HTTP** (`src/cache/http_cache_provider.cpp`): plain `GET`/`PUT` at
  `http://<host>:<port><path>/<key>`, where `<key>` is literally
  `buildcache_<hash>_<file>` (the per-file name inside an entry, including the
  special `.entry` metadata file, each becomes its own HTTP object — i.e. an
  entry with N output files is N+1 separate HTTP requests, not one bundled
  transfer; contrast go-s3-server's `/_batch/put` tar-bundling design, which
  exists precisely to avoid this "one HTTP request per stored file" cost under
  CI load). Single fixed header `Content-Type: application/octet-stream`
  regardless of method. A non-2xx/201/204 response raises with the status code
  and body inlined into the error; 404 specifically is mapped to a clean
  "not found" cache-miss path (caught and logged at DEBUG, not surfaced as a
  build error) rather than an exception. No explicit timeout handling visible in
  this file.
- **Redis** (`redis_cache_provider.cpp`): standard Redis key/value semantics,
  optional username/password auth (`BUILDCACHE_REDIS_USERNAME/PASSWORD`).
- **S3** (`s3_cache_provider.cpp`): standard S3 object PUT/GET, credentials from
  `BUILDCACHE_S3_ACCESS/SECRET` (falling back to the AWS-standard env var names),
  signature version 2 or 4 selectable.

All three are alternatives behind one `BUILDCACHE_REMOTE=<scheme>://...` URL,
functionally the same shape as ccache's `remote_storage=` chained-backend string,
just without ccache's explicit multi-backend chaining/fallback-order syntax or
sharding-across-endpoints (`shards=` + rendezvous hashing) support.

## Invocation model

Three documented ways in (`doc/usage.md`):

1. **Prefix**: `buildcache g++ -c -O2 hello.cpp -o hello.o` — no PATH tricks
   needed, but every build rule must name buildcache explicitly.
2. **Symlink/masquerade**: symlink `buildcache` under the compiler's own name
   (`gcc`, `g++`, `cc`, ...) earlier in `PATH`; buildcache infers which real tool
   it's standing in for from the symlink name it was invoked as — same mechanism
   ccache calls masquerading.
3. **`BUILDCACHE_IMPERSONATE=<real-tool-path>`**: point the build system straight
   at the `buildcache` binary (no symlink needed at all) and let this env var name
   the real tool to wrap. Documented tradeoff: "when this setting has a
   non-default value, BuildCache command line arguments cannot be used" — i.e.
   opting into env-var impersonation trades away buildcache's own CLI surface
   (its `--show-stats` etc.) for that invocation, since the whole argv is now
   assumed to belong to the wrapped tool.

Stats: `buildcache --show-stats [ERE-pattern]` (optionally filtered by
`BUILDCACHE_STAT_ID`-style session/group pattern), `buildcache --zero-stats
[pattern]` to reset.

## Known weaknesses (from the project's own issue tracker, GitLab API,
`state=all`, fetched directly — not secondhand)

Substantiating the "usable in most scenarios, but rough edges, low
testing/contributors" characterization with primary evidence:

**Open, unresolved at time of writing:**
- *False cache hit with cppcheck inline suppressions* — the cppcheck wrapper's
  hash doesn't account for inline suppression comments in source, so two source
  files differing only in a suppression comment can collide on the same cache
  key and produce a stale/wrong lint result. A direct instance of the
  "hashing precision vs. cost" tradeoff producing an actual correctness bug, not
  just a theoretical risk.
- *Direct mode fails with Linux kernel* — a real-world large-build correctness
  failure specifically in direct mode, unresolved.
- *Using stale precompiled headers leads to linker errors* — buildcache's PCH
  handling has the same sharp-edge class of bug ccache documents needing
  `sloppiness=pch_defines,time_macros` + `-fno-pch-timestamp` for; here it's not
  even fully solved by config, per the open issue.
- *Objc (.m/.mm) files not recognized* — a language-detection gap in the
  compiler-wrapper dispatch.
- *The GCC wrapper does not handle `-save-temps` properly* and *the GCC wrapper
  doesn't handle compact arguments* (e.g. `-Ipath` vs `-I path` argument-joining
  variants) — both are argument-parsing completeness gaps in the built-in gcc
  wrapper specifically, the same category of bug ccache's own flag-handling
  gotchas fall into (see lessons.md).
- *Significant slowdown when building with ARM GCC* — an open perf regression
  specific to one compiler wrapper, evidence the per-wrapper C++ implementations
  are not uniformly optimized/maintained.
- *"Unnecessarily alarming ERROR" for partially pruned remote cache entries* —
  a rough-edges/logging-quality issue on the remote-eviction path.
- Feature requests still open and unimplemented: memcached backend, Azure Blob
  Storage backend, HTTPS for Cloudflare R2, winget packaging, invalidate-by-
  wrapper-type — i.e. several of the backend/platform breadths this doc lists as
  "supported" are aspirational/partial rather than fully mature.

**Closed (fixed), still evidence of past correctness bugs in the same areas:**
- *Rust false-positive cache hit* and *`rust_wrapper_t::get_program_id()` isn't
  stable* — both are the Rust wrapper's own version of ccache/sccache's
  compiler-identity problem (`compiler_check`), independently rediscovered and
  independently buggy here before being fixed.
- *Rust wrapper doesn't handle `--check-cfg`* and *doesn't handle clang coverage
  flags* — more argument-completeness gaps, since fixed.
- *Custom Lua wrapper never gets picked up even when `can_handle_command` is
  true* — a bug in the wrapper-discovery/dispatch mechanism itself, i.e. the
  Lua contract's own plumbing had a real defect, not just individual wrapper
  scripts.
- *Ninja recompiling a `.cpp` unit even when already compiled* — a
  build-system-integration correctness bug (stale mtime/signal to Ninja that a
  "hit" restore didn't actually happen), the same class of hazard ccache's
  `hard_link` warning exists for.

**Repo-level signal**: 28 stars / 14 forks total (GitLab API,
`projects/bits-n-bites%2Fbuildcache`) is genuinely small for a build tool with
this feature breadth, supporting the "low testing/contributors" characterization
directly — most compiler-specific wrapper bugs above look like they were found by
individual users hitting them in production rather than by a test suite.

## On the "buildcache is a bit slower" claim — evidence check

The project's own benchmark doc (`doc/benchmarks.md`), an LLVM full-rebuild
comparison against ccache 3.7.7, does **not** support "buildcache is slower" at
the warm-cache steady state that matters most in practice:

| | No cache | Cold cache | **Warm cache** | Cache size |
|---|---|---|---|---|
| No cache | 19m50.9s (1.0x) | — | — | — |
| **buildcache** (local, direct mode, ZSTD) | — | 20m56.7s (0.95x) | **0m31.9s (37.3x)** | **86.9 MiB** |
| **ccache** 3.7.7 | — | 20m55.7s (0.95x) | 0m36.0s (33.1x) | 354.8 MiB |

On this one benchmark, buildcache is marginally *faster* on warm-cache hits than
ccache and uses roughly a quarter of the disk space (ZSTD vs. ccache's zstd-1
default plus buildcache's more compact manifest/entry format). Two caveats worth
stating plainly: (1) this is the project's own benchmark, on one codebase
(LLVM), so it is not neutral evidence and could reflect a benchmark chosen to
flatter buildcache; (2) it says nothing about **process/startup overhead**,
which is where "a bit slower" claims about tools like this usually originate —
buildcache is a stateless per-invocation C++ binary like ccache (no daemon), so
the two should have comparable startup cost, and the open "significant slowdown
when building with ARM GCC" issue suggests the real per-wrapper cost is
uneven rather than uniformly worse. **Verdict: the "a bit slower" framing is not
substantiated by buildcache's own published numbers; if it holds at all, it likely
applies unevenly, per-wrapper, rather than as a blanket architectural cost** — the
Lua indirection (script parse + interpret per invocation, for Lua-based wrappers
specifically, not the built-in C++ ones) is the most plausible mechanical source
of any such difference, and is worth an api-cache team benchmark of its own
before assuming it as fact.

## Sources

- License: https://gitlab.com/bits-n-bites/buildcache/-/raw/master/LICENSE
- Lua contract: https://gitlab.com/bits-n-bites/buildcache/-/raw/master/doc/lua.md
- Usage/invocation: https://gitlab.com/bits-n-bites/buildcache/-/raw/master/doc/usage.md
- Config reference: https://gitlab.com/bits-n-bites/buildcache/-/raw/master/doc/configuration.md
- Benchmarks: https://gitlab.com/bits-n-bites/buildcache/-/raw/master/doc/benchmarks.md
- `src/wrappers/program_wrapper.hpp` (base contract + capability strings)
- `src/cache/local_cache.cpp` (on-disk layout, eviction)
- `src/cache/http_cache_provider.cpp` (HTTP wire shape)
- Repo metadata + issues: GitLab API,
  `https://gitlab.com/api/v4/projects/bits-n-bites%2Fbuildcache` and
  `.../issues?state=all`
