# Hashing, normalization, and the correctness hazards

## 1. Which hash

Measured by reading each project's source, not by reputation:

| Project | Algorithm | Digest kept | Where |
|---|---|---|---|
| **ccache** | **BLAKE3** | **20 bytes** (160 bits, truncated) | `src/ccache/hash.hpp`: `#include <blake3.h>`, `using Digest = std::array<uint8_t, 20>` |
| **sccache** | **BLAKE3** | 32 bytes, hex (64 chars) | `src/util.rs`: `use blake3::Hasher as blake3_Hasher`; a test asserts `hash.len() == 64` |
| **buildcache** | **XXH3** | **16 bytes** (128 bits) | `src/base/hasher.hpp`: `static const size_t SIZE = 16U`, with a comment that the opaque member "is in fact an `XXH3_state_t` pointer" |
| **Bazel REAPI** | **SHA-256** (the digest function is negotiable, but SHA-256 is the default and near-universal) | 32 bytes | `remote_execution.proto` |
| **Go build cache** | **SHA-256** | 32 bytes (`HashSize = 32`) | `cmd/go/internal/cache/hash.go` |

**Correcting the brief:** ccache does *not* use XXH3 for cache keys — it used MD4 through
3.x and switched to BLAKE3 in 4.0. It is **buildcache** that uses XXH3-128. (ccache does use
a non-cryptographic hash internally for its inode cache lookup, which is not a cache key.)

### Choosing for api-cache

The decision axes:

- **Collision tolerance.** A cache key collision silently serves the wrong object. At 128
  bits with birthday bound, 2^64 entries; at 160 bits, 2^80. Both are fine in absolute
  terms. The real argument for a cryptographic hash is different: **a shared cache is
  reachable by anyone who can write to it**, so a non-cryptographic hash lets a hostile
  actor *construct* a collision and poison a key. ccache and sccache both chose a
  cryptographic hash; buildcache, which is local-first, did not. api-cache is explicitly
  aimed at a shared remote store, which argues for BLAKE3 or SHA-256.
- **Throughput.** BLAKE3 is several GB/s single-threaded and parallelises over a file;
  SHA-256 is ~1–2 GB/s with SHA-NI, far less without. XXH3 is ~30 GB/s. On a direct-mode
  lookup the wrapper hashes the source plus every header — tens of megabytes for a
  C++ TU — so this is on the critical path of every *hit*, not just every miss.
- **Interoperability.** If api-cache is ever to serve a stock `go` over GOCACHEPROG, the
  **OutputID is fixed at SHA-256 by the go command** (`OutputID == sha256(body)`), so
  SHA-256 must exist in the implementation regardless of what the *action key* uses. This
  is exactly the constraint go-s3-server's `selfheal.go` is built around.

Recommendation to the planner: **BLAKE3 for action keys**, SHA-256 where an external
protocol demands it. Keep the digest at its full width in the protocol and truncate only
for on-disk path sharding.

### Framing, not just hashing

ccache's `hash_delimiter(type)` exists for two reasons it states outright:

> - Delimit things like arguments from each other (e.g., so that `-I -O2` and `-I-O2` hash
>   differently).
> - Tag different types of hashed information so that it's possible to do conditional
>   hashing of information in a safe way.

Both matter. Without framing, `hash("ab") + hash("c")` and `hash("a") + hash("bc")` collide
trivially. Without tagging, "hash the cwd if generating debug info" changes the *meaning* of
the byte stream depending on a condition, so two different conditions can produce the same
stream. buildcache has the same primitive, `inject_separator()`, and uses it to keep
direct-mode and preprocessor-mode hashes from ever colliding
(`program_wrapper.cpp`: a copy of the common hasher with a separator injected).

**Also version the format.** buildcache prefixes a per-wrapper `HASH_VERSION` constant
("4" for gcc, "2" for msvc, "5" for rust) and sccache has a global `CACHE_VERSION` with the
comment "If you change any of the inputs to the hash, you should change `CACHE_VERSION`".
Go salts every hash with `runtime.Version()`. Without this, changing a hashing rule serves
stale results forever.

## 2. What must be normalized before hashing

### 2.1 The source path in preprocessed output

`gcc -E` embeds the source path **exactly as written on the command line** into its
linemarkers. Measured (`probes/out/02-preproc.txt`):

| invocation | first linemarker |
|---|---|
| `cd src && gcc -E hello.c` | `# 0 "hello.c"` |
| `cd .. && gcc -E -Isrc src/hello.c` | `# 0 "src/hello.c"` |
| `gcc -E /abs/path/src/hello.c` | `# 0 "/abs/path/src/hello.c"` |

Three responses:

1. **`-P`** — suppress linemarkers entirely. Measured: `gcc -E -P` emits no `#` lines.
   Makes the preprocessed text location-independent at the cost of destroying the file/line
   information that `-g` and `--coverage` need. buildcache's rule: add `-P` **unless**
   (`-g` present and accuracy ≥ STRICT) or (coverage present and accuracy ≥ DEFAULT).
2. **`base_dir`** — rewrite absolute paths under a configured prefix to cwd-relative ones,
   in argv and in the text. ccache's approach.
3. **Neither** — accept that two build roots do not share.

Note what `-P` does *not* remove: `#pragma GCC pch_preprocess "x.gch"` survives (it is
content, not a marker), so PCH identity still reaches the key under `-P`. Measured.

### 2.2 `base_dir`: exactly what it does and where it breaks

From ccache's manual (§`base_dir`), with its own worked example:

```
# Alice, cwd /home/alice/project1/build
ccache gcc -I/usr/include/example -I/home/alice/project2/include -c /home/alice/project1/src/example.c
# Bob,   cwd /home/bob/stuff/project1/build
# with base_dir=/home (or /home/$USER), BOTH rewrite to:
gcc -I/usr/include/example -I../../project2/include -c ../src/example.c
```

The manual's own cautions are the important part:

- **`base_dir = /` is wrong**: it rewrites `/usr/include/example` too, and the relative
  path to a system header differs per build root, so you get a *guaranteed* miss instead of
  a hit.
- **`base_dir` too narrow is also wrong**: `/home/bob/stuff/project1` leaves the path to
  `project2` absolute, so it still differs.
- The manual labels it *"kind of a brittle hack"* and names the known breakage:
  **absolute paths are not reproduced in dependency files**, which confuses Make and Ninja
  dependency detection. Its own recommendation: *"If possible, use relative paths in the
  first place instead of using base_dir."*

So `base_dir` is a **prefix window**, not a boolean, and choosing it wrongly in either
direction costs hits.

### 2.3 `hash_dir` and the debug-info trap

This is the sharpest correctness issue in the whole area, so it is worth stating as a
scenario.

Measured (`probes/out/03-debug-and-paths.txt`): with `-g`, the object carries

```
DW_AT_name     : hello.c        <- the path as written
DW_AT_comp_dir : /home/user/.../probes/src    <- the ACTUAL cwd
```

Compiling the identical source from the parent directory as `src/hello.c` gives
`DW_AT_name: src/hello.c` and `DW_AT_comp_dir: <parent>`, and the objects are **not
byte-identical**.

So: if the key does *not* include the cwd, a developer in `/home/bob/proj` gets a hit on an
object Alice built in `/home/alice/proj`, and their debugger then looks for sources under
`/home/alice/proj`. The build succeeds and the debugger is silently wrong.

ccache's `hash_dir` (default **true**) hashes the cwd **only when generating debug info**,
with the documented exception that it is skipped when `-fdebug-prefix-map` or
`-fdebug-compilation-dir` make the embedded path independent of the cwd. The exact rule as
implemented (ccache.cpp ~1786):

```
if (generating_debuginfo && hash_dir):
    dir = compilation_dir           # from -fdebug-compilation-dir / -fcoverage-compilation-dir
          if set, else apply_prefix_remapping(debug_prefix_maps, actual_cwd)
    hash_delimiter("cwd"); hash(dir)
```

The prefix maps are **applied in reverse argv order** (ccache reverses both
`debug_prefix_maps` and `coverage_prefix_maps` after the scan), matching gcc's
last-map-wins semantics.

Measured prefix-map effects:

| flags | `DW_AT_name` | `DW_AT_comp_dir` |
|---|---|---|
| `-g` (abs source) | `/abs/.../src/hello.c` | `/abs/.../src` |
| `-g -fdebug-prefix-map=$PWD=/proj` | `/proj/hello.c` | `/proj` |
| `-g -ffile-prefix-map=$PWD=/proj` | `/proj/hello.c` | `/proj` |
| clang `-g -fdebug-compilation-dir=/proj` | `hello.c` | `/proj` |

`-ffile-prefix-map` = `-fdebug-prefix-map` + `-fmacro-prefix-map`, i.e. it also rewrites
`__FILE__`. Measured caveat: it only fires when the written path *starts with* the mapped
prefix, so `-ffile-prefix-map=$PWD=/X` does nothing to a relatively-invoked `__FILE__`
(which is already `fi.c`).

**Three other places the cwd leaks in without `-g`:**

- **MSVC** embeds the full source path in the `.obj` even without debug flags. ccache
  therefore hashes the object file's directory (or the cwd, when `/Fo` is relative)
  for every MSVC compile when `hash_dir` is on, not only for debug builds
  (ccache.cpp ~1800).
- **`--coverage`**: the `.gcno` records the compilation directory. Hence the `gcno_cwd`
  sloppiness, and `-fprofile-abs-path` forcing the cwd into the hash outright.
- **`-gsplit-dwarf`**: the `.o` links to the `.dwo` **by name**, so the object *path*
  enters the key (ccache's comment: "hashing the object file path will do it, although
  just hashing the object file base name would be enough").

### 2.4 What does *not* need normalizing

- **The `-o` value.** Measured: two compiles differing only in `-o` name produce
  byte-identical objects (`out/03-debug-and-paths.txt` §9). So the output path is a
  *destination*, not an input — except in the `-gsplit-dwarf` and MSVC cases above.
- **CRLF.** No tool in this survey normalizes line endings before hashing, and it would be
  wrong to: a source with CRLF and one with LF are different inputs (raw string literals,
  `__LINE__` behaviour in edge cases, and the compiler's own byte-for-byte handling). The
  *dep file* is a different matter — a `.d` written on Windows uses CRLF and ccache's
  tokenizer splits on both.
- **`-I` order, in preprocessor mode.** It affects only which files are found, and the
  found files are already in the preprocessed text. In direct mode it must be hashed.

### 2.5 The compiler's own path

Hashed as *three separate things*, and all three are needed:

1. the **binary identity** (`compiler_check`: mtime+size / content / `--version` output /
   a user string — see `c-cxx-gcc-clang.md` §6);
2. the **name it was invoked under** — `hash_delimiter("cc_name"); hash(basename(argv[0]))`,
   because gcc behaves differently as `gcc` vs `g++` vs `cc` even when they are hard links
   to one file;
3. **`COMPILER_PATH` and `GCC_EXEC_PREFIX`**, which change which `cc1`/`as`/`ld` the driver
   finds without changing either of the above.

The full *path* is deliberately not hashed, so that `/usr/bin/gcc` and
`/opt/toolchain/bin/gcc` with identical content share entries.

## 3. Sloppiness: the named-relaxation pattern

ccache's complete list (`src/ccache/config.cpp`), each an opt-in that trades a specific
correctness property for hits:

| name | What it relaxes | What it risks |
|---|---|---|
| `clang_index_store` | Do not hash the `-index-store-path` output | A stale index |
| `file_stat_matches` | Accept an include as unchanged when **mtime and ctime** both match, without hashing it | A file restored with preserved timestamps but changed content |
| `file_stat_matches_ctime` | Narrows the above to **mtime only** | Also misses a content change made without an mtime change |
| `gcno_cwd` | Do not hash the cwd for coverage builds | Wrong paths in `.gcno` |
| `incbin` | Ignore a `.incbin` directive instead of disabling direct mode | The binary blob is not an input |
| `include_file_ctime` | Do not treat a too-new **ctime** as a modified input | A file changed during the compile is cached |
| `include_file_mtime` | Same for **mtime** | Same |
| `ivfsoverlay` | Do not hash the `-ivfsoverlay` file | The virtual filesystem map is not an input |
| `locale` | Do not hash `LANG`/`LC_*` | Replayed diagnostics in the wrong language |
| `modules` | Allow `-fmodules` | The module binaries are not hashed |
| `pch_defines` | Allow creating a PCH without seeing its macro state | Wrong macros baked into the PCH |
| `random_seed` | Ignore `-frandom-seed` | Symbol names differ from what the build expected |
| `system_headers` | Do not hash headers ccache believes are system headers | A toolchain update goes unnoticed |
| `time_macros` | Ignore `__DATE__`/`__TIME__`/`__TIMESTAMP__` | Stale dates baked into the binary |

**The pattern is the lesson, not the list.** Each relaxation is (a) individually named,
(b) individually loggable, (c) off by default, and (d) attached to a *stated* risk. That is
strictly better than one "fast mode" switch, and it is directly expressible in a rule file.
buildcache's equivalent is coarser — a single three-level `accuracy` knob
(`SLOPPY < DEFAULT < STRICT`) that gates two decisions (whether to keep line info for debug
builds, whether to keep it for coverage builds) — which is exactly the loss of resolution
to avoid.

## 4. `hash_dir` versus `base_dir`: the trade-off table

| Configuration | Cross-directory hits | Debug info correct | Dep files correct |
|---|---|---|---|
| neither (default-ish, `hash_dir=true`) | **no** (with `-g`); yes without `-g` | yes | yes |
| `hash_dir=false`, no `base_dir` | yes | **no** — `DW_AT_comp_dir` points at the builder's directory | yes |
| `base_dir=<repo root>`, `hash_dir=true` | **yes** — paths rewrite to identical relative forms, so the cwd hashes the same | yes, *if* every consumer resolves relative to the same cwd | **partly** — "absolute paths are not reproduced in dependency files" (ccache's own warning) |
| `-fdebug-prefix-map` / `-ffile-prefix-map` in the build itself | **yes** — and `hash_dir` then skips the cwd automatically | **yes**, and correctly so: the object is genuinely location-independent | yes |

**The last row is the right answer** and the one to steer users toward: make the *build*
reproducible rather than making the *cache* lie about it. It is also what
`SOURCE_DATE_EPOCH` + `-ffile-prefix-map` give a reproducible-builds project for free.

## 5. Correctness hazards

### 5.1 The "too new" input race

The scenario: a build writes `foo.h`, then compiles `foo.c` which includes it, within the
same filesystem timestamp granularity. The wrapper hashes `foo.h`, caches the result, and
records `foo.h`'s mtime. A moment later — still in the same second, or the same
nanosecond-truncated tick — the build writes a *different* `foo.h`. A later direct-mode
lookup stats `foo.h`, sees the recorded mtime, and (under `file_stat_matches`) serves the
stale object.

ccache's guard (`source_file_is_too_new`, ccache.cpp ~1218), applied to the source **and
every recorded include** *after* the compile:

```
deadline = time_of_invocation + 100ms
if (!sloppy_mtime && mtime(path) >= deadline) -> Statistic::modified_input_file
if (!sloppy_ctime && ctime(path) >= deadline) -> Statistic::modified_input_file
```

Note the details:
- the comparison is against the **invocation** time, not the completion time;
- the **100 ms safety margin** exists because filesystem timestamps are granular — the
  comment says so explicitly — and is deliberately small "to make things safe on common
  filesystems while also not bailing out when creating a source file reasonably close in
  time before the compilation";
- **ctime as well as mtime**, because a `chmod`, a hard-link count change, or a restore
  that preserves mtime still moves ctime;
- `/dev/null` is exempt;
- the verdict is `modified_input_file`, flagged `FLAG_ERROR` — this is treated as a bug in
  the build, not as an ordinary uncacheable case.

This same rule is what covers **the compiler modifying its own input**: a code generator
that rewrites its input file moves its mtime past the invocation time, and the result is
discarded.

### 5.2 Hard-linking outputs

Both ccache (`hard_link`, default **false**) and buildcache (a per-wrapper `hard_links`
capability, also gated by user config) can hard-link a cache entry into place instead of
copying it. Enormous saving; a sharp edge.

buildcache's justification is the exact statement of the precondition:

> `hard_links` — We can use hard links since GCC will never overwrite already existing
> files.

The failure it guards against: if **anything** later opens the output file for writing
in place, the write lands on the cache entry's inode and corrupts it **for every future
user of that key**. Concretely dangerous steps:

- `strip foo.o` (in place), `objcopy --strip-debug foo.o foo.o`
- a build script that appends to or post-processes an object
- an `ar` that updates a member in place
- a user's editor or `sed -i` on a restored non-object artifact
- a second compile writing to the same `-o` path *without* unlinking first (gcc does
  `O_TRUNC` on an existing file rather than unlinking — which is exactly why the
  precondition above is about *the consumers*, not about gcc)

Recommendation: keep hard-linking off by default, and if it is offered, make it a
*per-output-kind* decision (an object is usually safe; a script or a data file is not),
not a global one. ccache mitigates partially by making the cached file read-only.

### 5.3 Identical-content `#pragma once` headers (gcc only)

Fully described in `c-cxx-gcc-clang.md` §3 with a reproduction. Summary: GCC implements
`#pragma once` with a **content** comparison, so a second distinct header with byte-identical
content is never opened and never appears in `-H`, `-MM`, or the linemarkers. A manifest
built from any of those is therefore incomplete, and a later edit to the omitted file
produces a **false hit**. Clang does not do this. There is no sloppiness knob for it in
ccache because it is not known to be handled at all.

### 5.4 Restoring a partially-written entry

Two disciplines, both required:

- **Store**: assemble the entry completely, then publish it with a single atomic rename.
  A reader must never observe a half-written entry.
- **Restore**: write each output to a temp in the *destination's* directory and rename.
  A concurrent reader of a restored object then sees either the old file or the new one.

Combined with the signal handling in `invocation-modes.md` §4, the invariant is: **a
wrapper that dies at any point leaves either the pre-existing state or the complete new
state, and never a cache entry describing a compile that did not finish.**

### 5.5 Empty and missing outputs

ccache has two distinct statistics here, and the distinction is worth keeping:

- `compiler_produced_no_output` — an expected output file does not exist after the compile.
- `compiler_produced_empty_output` — it exists but is zero bytes.

Both are uncacheable rather than errors: a compiler that exits 0 and writes nothing is
either doing something the wrapper did not model (`-fsyntax-only` — which is why that flag
sets `expect_output_obj = false`) or has failed in a way its exit code did not report.
Storing a zero-byte object would be a permanent, silent build break.

### 5.6 Non-determinism that is *not* a correctness problem

Worth separating, because it looks alarming and is not:

- **LTO bitcode is not byte-reproducible.** Measured: `gcc -c -flto r.c -o r.o` twice gives
  different bytes, and `-frandom-seed=0` did not fix it on gcc 13. The cached object is
  still *a* valid object for those inputs. It only matters if something downstream compares
  objects byte-for-byte (a reproducible-build check, a content-addressed artifact store
  keyed on the object).
- **Ordinary `-O2 -g` compiles *are* byte-reproducible.** Measured: identical bytes across
  runs, with and without `-g`, given identical cwd and argv. So the general assumption
  holds; LTO is the exception.
