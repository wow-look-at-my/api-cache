# C / C++ with gcc and clang: the complete decision procedure

Scope: what a correct compiler-cache wrapper must do for a `gcc`/`g++`/`clang`/`clang++`
invocation. Every claim is either (a) cited to a source I read, or (b) measured by a probe
under `probes/`, named inline.

## Sources and their licences

| Source | Licence | How it may be used |
|---|---|---|
| [ccache](https://github.com/ccache/ccache) `src/ccache/{argprocessing,compopt,hashutil,depfile,ccache}.cpp`, `src/ccache/core/{manifest,statistics,resultretriever}.cpp` | **GPL-3.0-or-later** | Read for **behaviour only**. No code, no structure-for-structure transcription. Everything below is a prose description of observable behaviour. |
| [ccache manual](https://ccache.dev/manual/latest.html) | GPL docs | Behaviour reference. |
| [sccache](https://github.com/mozilla/sccache) `src/compiler/{gcc,clang,c,msvc,rust}.rs` | **Apache-2.0** | Code may be adapted with attribution. |
| [buildcache](https://gitlab.com/bits-n-bites/buildcache) `src/wrappers/*.cpp`, `doc/lua.md` | **zlib/libpng** (permissive; the task brief said MIT — the actual file is the zlib licence: use freely, do not misrepresent origin, keep the notice) | Code may be adapted. |

Reference clones live at `/home/user/refs/{ccache,sccache,buildcache}` — **outside** the
api-cache repo, per the housekeeping rule.

---

## 1. Classify the invocation: is it cacheable at all?

The wrapper scans argv once, accumulating state, and then applies a verdict. ccache's
verdicts come from a closed vocabulary (full list in `key-derivation-model.md`); the
gcc-relevant ones are named below in `code font`.

### 1.1 The single-compile shape

A cacheable invocation is exactly: **one input source file, compiled to one object file,
without linking.**

ccache computes `is_link = !(found -c || found -dc || found -S || found -fsyntax-only ||
found -analyze)` (argprocessing.cpp ~1702). Note what this means:

- `-c` — cacheable.
- `-S` (assembly output) — **cacheable**, and the default output extension becomes `.s`
  (argprocessing.cpp ~1800: `extension = ".s"` when `found_S_opt`). The task brief asked
  "does ccache cache `-S`?" — **yes**, `-S` is not a bypass; it is treated as a compile
  whose product happens to be assembly.
- `-fsyntax-only` — treated as a compile with `expect_output_obj = false`. Probe
  `out/04-flags.txt` confirms `gcc -fsyntax-only -c x.c -o syn.o` exits 0 and writes
  **nothing**; a wrapper that insists on capturing `-o` here will report
  `compiler_produced_no_output` forever.
- `-dc` (nvcc device compile) and `-analyze` (clang static analyzer, output `.plist`) —
  also counted as compiles.
- Nothing of the above present → `called_for_link`, with the special case that if the
  input filename contains `conftest.` the reason becomes `autoconf_test` instead. That
  split exists because autoconf feature probes dominate the "called for link" count in a
  typical `./configure` run and would otherwise swamp the statistics.

Counts of input files:
- zero → `no_input_file`
- more than one **and** linking → `called_for_link` / `autoconf_test`
- more than one **and** compiling → `multiple_source_files`

### 1.2 Hard bypasses on individual options

ccache keeps a sorted option table (`compopt.cpp`) whose entries carry bit flags. The
flags are the whole classification vocabulary and map almost one-to-one onto what a
configurable engine needs:

| ccache flag | Meaning |
|---|---|
| `TOO_HARD` | Bypass the cache entirely. |
| `TOO_HARD_DIRECT` | Direct mode is unusable; preprocessor mode still is. |
| `TAKES_ARG` | Value is the next argv element (`-D FOO`). |
| `TAKES_CONCAT_ARG` | Value is glued on (`-DFOO`). |
| `TAKES_PATH` | The value is a path, and is subject to `base_dir` rewriting. |
| `AFFECTS_CPP` | Affects only preprocessing → **excluded** from the hash in preprocessor mode (its effect is already baked into the preprocessed text). |
| `AFFECTS_COMP` | Affects only compilation → not passed to the preprocessor run. |

`TOO_HARD` entries relevant to gcc/clang (verbatim from `compopt.cpp`):

```
--analyzer-output  --save-temps  --save-temps=cwd  --save-temps=obj
-E  -M  -MM  -MJ  -analyze  -ast-merge  -ast-view
-fmodule-header  -fmodules-ts  -fplugin=libcc1plugin  -frepo  -ftime-trace
-gen-cdb-fragment-path  -gtoggle  -save-temps  -save-temps=cwd  -save-temps=obj
-wrapper
```

MSVC-only `TOO_HARD`: `-EP`, `-Tc`, `-Tp`, `-link`.

Reading of the interesting ones:

- **`-E` / `-M` / `-MM`** → `called_for_preprocessing`. These *write the dependency or
  preprocessed text to stdout and produce no object*, so there is nothing to key a
  compile on. `-MD`/`-MMD` are the opposite: they are **fine**, because they are
  side-effects of a real compile (argprocessing.cpp ~1160). So the brief's question
  "`-M` without `-MD`?" resolves as: `-M`/`-MM` bypass, `-MD`/`-MMD` do not.
- **`-save-temps`** → the compiler writes `.i`/`.s` siblings the cache does not know
  about, and (worse) changes how it drives its own pipeline. Bypass.
- **`-ftime-trace`** → emits a `.json` trace whose content includes wall-clock durations.
  Not reproducible. Bypass.
- **`-fplugin=libcc1plugin`** → the GDB plugin; interacts with an external process.
  Plain `-fplugin=` is **not** in the table, so ccache hashes it as an ordinary argument
  and does **not** hash the plugin `.so`'s content. That is a real correctness hole a new
  engine should close by classifying `-fplugin=<path>` as *hash-file-content*.
- **`-frepo`**, **`-gtoggle`**, **`-wrapper`** — change the compilation model itself.
- **`-MJ`** — compilation-database fragment, append-only to a shared file. Bypass.

### 1.3 Options with dedicated handling (not a flat table entry)

These are the cases a configurable engine must be able to express, because a flat
"pattern → class" table is not enough for any of them.

**`-fmodules`** (clang header modules). ccache refuses unless *both* depend mode and
direct mode are on, **and** the `modules` sloppiness is set (argprocessing.cpp ~760).
Otherwise `could_not_use_modules`. The stated reason: the preprocessed output does not
list `module.modulemap` files, so only the depend-mode dependency output sees them; and
even then the module binaries themselves are not hashed, so the object could differ.

**`-fmodule-file=[<name>=]<path>`** (C++20 named modules). ccache records the path in
`args_info.module_files` and hashes the argument. Importantly the BMI at that path is a
*compiler-version-and-flag-specific binary* — a C++20 modules build is effectively a
second dependency graph that the preprocessor cannot see at all. **Why C++20 modules
defeat caching in general:** (a) the BMI is not reproducible across compiler patch
levels; (b) `import foo;` names no file, so there is no `-I`-style search the wrapper can
replay; (c) building the BMI is itself an action whose output must be cached, and its
consumers must key on the BMI's content, which makes the dependency order dynamic. A
wrapper that only sees one `cc1` invocation at a time cannot discover that order. The
practical answer both ccache and sccache take: hash the named BMI files as content
inputs, or bypass.

**`-fprofile-*`** (argprocessing.cpp ~294). Split into three behaviours:
- *no-ops for caching*: `-fprofile-correction`, `-fprofile-reorder-functions`,
  `-fprofile-sample-accurate`, `-fprofile-values`, `-fprofile-update*`. Hashed as text.
- *`-fprofile-generate[=dir]`, `-fprofile-instr-generate[=dir]`, `-fprofile-dir=`*: record
  a profile path. gcc's default path is `$PWD` and clang's is `.`. The path participates
  in the key because it is baked into the instrumented object.
- *`-fprofile-use[=path]`, `-fprofile-instr-use`, `-fprofile-sample-use`,
  `-fbranch-probabilities`, `-fauto-profile`*: the **profile data file is an input** and
  must be hashed by content. More than one profiling option of this kind →
  `unsupported_compiler_option`. This is the real reason PGO "usually bypasses": the
  profile file is discovered by convention (a directory plus the object's basename), not
  named on the command line, so its identity is guessable but not stated. ccache handles
  `-fprofile-use=<file>` and gives up on the directory-convention forms.
- `-fprofile-abs-path` sets `hash_actual_cwd` unless the `gcno_cwd` sloppiness is on,
  because it makes the compiler write the *real* cwd into the `.gcno`.

**`-fsanitize-ignorelist=` / `-fsanitize-blacklist=`** — the path is recorded as an
extra input to hash by content, and the argument is rewritten relative to `base_dir`.

**`-march=native` / `-mcpu=native` / `-mtune=native`** — **neither bypass nor cpuinfo**.
ccache asks the compiler what `native` expanded to, by running
`<compiler> -### -E - <the native args>` and hashing the single line of output that
contains `/cc1 -E` (gcc) or `"-cc1"` (clang) (`hash_native_args`, ccache.cpp ~1948).
Probe `out/04-flags.txt` reproduces this: on this machine gcc expands `-march=native` to
`-march=cascadelake -mmmx -mpopcnt … -mavx512vnni …` (≈900 chars) and clang to
`-target-cpu cascadelake -target-feature +prfchw …`. For clang, ccache filters that line
down to only architecture-related options, because the clang `-cc1` line also carries
`-fdebug-compilation-dir` and `-fcoverage-compilation-dir`, which are cwd-dependent and
would destroy cross-directory sharing.

**`-frecord-gcc-switches`** — sets `hash_full_command_line`: the *original, unfiltered*
argv goes into the hash, because the switches themselves land in the object's
`.GCC.command.line` section.

**`-gsplit-dwarf`** — a second output. ccache derives `<object>.dwo` from the object path
(argprocessing.cpp ~1936) and captures it as an extra cached artifact, except when the
object is `/dev/null`, in which case the compiler writes no `.dwo` and the flag is
forgotten. Probe: `gcc -g -gsplit-dwarf -c hello.c -o sd.o` produces `sd.o` **and**
`sd.dwo` (out/04-flags.txt).

**`--coverage` / `-ftest-coverage` / `-fprofile-arcs`** — produces `<object>.gcno`
alongside. Probe: `gcc --coverage -c hello.c -o cov.o` produces `cov.o` and `cov.gcno`.
buildcache models this as a second required build file named by changing the object's
extension (`gcc_wrapper.cpp::get_build_files`). The `.gcno` embeds the compilation
directory, hence ccache's `gcno_cwd` sloppiness.

**`-fstack-usage`** (`.su`), **`-fcallgraph-info`** (`.ci`), **`--serialize-diagnostics`**
(`.dia`), **clang `-fprofile-instr-generate`** — each adds a derived sibling output. A
generalized engine needs *derived output paths* as a first-class primitive, not just
"whatever `-o` says".

**PCH.** Two directions:
- *Creating* a PCH (`-x c-header`, or an output path ending `.gch`/`.pch`): requires the
  `pch_defines` **and** `time_macros` sloppiness, else `could_not_use_precompiled_header`.
  Reason: a PCH bakes in the full macro state, including the temporal macros, and ccache
  cannot see through it.
- *Using* a PCH (`-include-pch`, an implicit `.gch` next to a header, or
  `-fpch-preprocess`): requires `time_macros` sloppiness, else
  `could_not_use_precompiled_header` and direct mode is off.
- ccache adds `-fpch-preprocess` to the compiler args when it saw a PCH and the compiler
  is not MSVC, so that the preprocessed text carries the marker. Probe: `gcc -E
  -fpch-preprocess u.c` emits `#pragma GCC pch_preprocess "local.h.gch"` (out/04-flags.txt) —
  that pragma is how the PCH's identity reaches the preprocessed text, and therefore the
  preprocessor-mode key. A wrapper that strips line markers with `-P` **keeps** the pragma
  (it is content, not a marker), so this still works under `-P`.
- The manifest additionally refuses a PCH-producing hit for clang when an included file's
  **mtime** changed, even if its content did not, because clang stores include mtimes in
  the PCH and errors at use time otherwise (manifest.cpp ~405). `-fno-pch-timestamp`
  disables that check.

**`-Wp,-MD,<file>` / `-Wp,-MMD,<file>`** combined with `-MF` → `unsupported_compiler_option`
(argprocessing.cpp ~1729). The stated reason is a real divergence: **gcc writes to the
`-Wp` file and clang writes to the `-MF` file.** A wrapper cannot pick one without
knowing which compiler it is. Probe `out/01-depfiles.txt` shows `-Wp,-MD,objs/wp.d`
working standalone on gcc.

**`-o -`** → `output_to_stdout`. Probe: on Linux gcc, `gcc -c hello.c -o -` does not even
work — the assembler fails with `Fatal error` (out/04-flags.txt). Either way, bypass.

**stdin as source (`-x c -`)**. gcc accepts it (probe: produces a 1224-byte object). But
the source has no path to hash and no stable identity, and `-MD` then writes a dep file
whose prerequisite list omits the source entirely
(`/tmp/…/stdin.o: /usr/include/stdc-predef.h`). Bypass. sccache's gcc parser likewise
treats `-` as not-a-source.

**`-x <language>`**. ccache resolves the explicit language, maps it through a language
table, and rejects an unknown one with `unsupported_source_language`. `-x none` clears
the setting. If the language is already-preprocessed (`cpp-output`, `c++-cpp-output`),
`preprocess_input_file` is false and the preprocessor run is skipped. Assembler and
`ir` (LLVM IR) inputs additionally force `generating_dependencies = false`, because
`-MD` produces no dep file for them.

**`-fcolor-diagnostics` / `-fdiagnostics-color=auto`** — see §5.

**LTO (`-flto`)** — ccache records `using_lto` and **still caches**. The `.o` is
bitcode, but it is still a deterministic function of the inputs for a fixed compiler. The
caveat the probe found: `gcc -c -flto r.c -o r1.o` twice produces **different** bytes
(out/03-debug-and-paths.txt, section 10), and `-frandom-seed=0` did *not* make them
identical on gcc 13. LTO bitcode embeds a per-TU random identifier. This does not break
correctness of a cache (the cached copy is *a* valid object), but it does mean
byte-identity checks against a fresh compile will fail, and any downstream tool that
compares objects will see churn. `-frandom-seed=<string>` is gcc's documented lever for
making symbol names in LTO/`-fprofile` deterministic; ccache has **no** special handling
for it (grep found nothing), so it is hashed as an ordinary argument, and the ccache
`random_seed` sloppiness exists to *ignore* `-frandom-seed` when a build system stamps it
per-invocation.

**`-specs=<file>`** — `TAKES_ARG` only: ccache hashes the *argument string*, not the
spec file's content. Another content-hash hole worth closing.

**`-pipe`** — not in the table at all: hashed as an ordinary argument, harmless.

### 1.4 Environment-variable verdicts

Before anything else (ccache.cpp ~3000):

- `DEPENDENCIES_OUTPUT` or `SUNPRO_DEPENDENCIES` set → `unsupported_environment_variable`
  (they redirect dep output in a way argv does not show).
- MSVC only: `CL` or `_CL_` set → `unsupported_environment_variable`.

Also `VS_UNICODE_OUTPUT` is *unset* for MSVC so that stdout/stderr can be captured at all
(buildcache does the same, `msvc_wrapper.cpp`).

---

## 2. Preprocessor mode: the key

The preprocessor-mode key is a hash over, in order (ccache.cpp `hash_common_info` and
`get_result_key_from_cpp`):

1. **Compiler identity** — see §6.
2. **`cc_name`**: the basename of argv[0]. gcc behaves differently depending on the name
   it was invoked under (`gcc` vs `g++` vs `cc`), so the *name*, not just the binary, is
   hashed.
3. **Always-hashed env vars**: `COMPILER_PATH`, `GCC_COMPARE_DEBUG`, `GCC_EXEC_PREFIX`,
   `I_MPI_CC`, `I_MPI_CXX`; on macOS also `DEVELOPER_DIR`, `MACOSX_DEPLOYMENT_TARGET`;
   on Windows with MSVC also `VCToolsVersion`, `VCToolsInstallDir`.
   `COMPILER_PATH`/`GCC_EXEC_PREFIX` matter because they change which `cc1`/`as`/`ld` the
   driver finds — i.e. they change the compiler identity without changing argv[0].
4. **Locale**: `LANG`, `LC_ALL`, `LC_CTYPE`, `LC_MESSAGES`, unless the `locale`
   sloppiness is set. These change the *text of diagnostics*, which the cache replays
   verbatim, so a hit keyed without them would replay the wrong language.
5. **cwd**, but only when `generating_debuginfo && hash_dir` — and then the cwd is first
   passed through the `-fdebug-prefix-map` rewrites, or replaced by
   `-fdebug-compilation-dir` if given. (See `hashing-and-normalization.md`.)
6. **The filtered argv**: every argument *except* those marked `AFFECTS_CPP` (since their
   effect is already inside the preprocessed text) and except the source and output
   paths. `-I`, `-D`, `-U`, `-isystem`, `-idirafter`, `-iquote`, `-include`, `-imacros`,
   `-nostdinc`, `-stdlib=`, `-trigraphs` are all `AFFECTS_CPP` and are therefore dropped
   in this mode. **`-I` ordering is thus irrelevant to the preprocessor-mode key** — it
   is captured only through which headers actually got pulled into the text.
7. **Native-arch expansion**, if `-march=native` &c. were present (§1.3).
8. **The preprocessed output**, with the compiler's stderr from the preprocessing run
   appended (a `#warning` in a header must invalidate).

### The line-marker problem

`gcc -E` emits linemarkers of the form `# <line> "<file>" [flags]`. Probe
`out/02-preproc.txt`:

```
# 0 "hello.c"                          <- source path AS WRITTEN on the command line
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 1 "hello.c"
# 1 "/usr/include/stdio.h" 1 3 4
```

Compiling the same file as `src/hello.c` from the parent directory yields
`# 0 "src/hello.c"`; with an absolute path it yields the absolute path. So the raw
preprocessed text is **not** location-independent. Two options:

- **`-P`** suppresses all linemarkers. Probe confirms `gcc -E -P` output contains no
  `#` lines at all. This makes the key location-independent — but it also destroys the
  line/file information that `-g` and `--coverage` bake into the object. buildcache's
  rule (`gcc_wrapper.cpp::make_preprocessor_cmd`) is exactly this: add `-P` **unless**
  (`-g`-family present and accuracy ≥ STRICT) or (coverage present and accuracy ≥
  DEFAULT). That is a clean, expressible rule.
- **Keep the markers and normalise the paths** (ccache's `base_dir` approach): rewrite
  any absolute path under `base_dir` to a path relative to cwd, both in argv and in the
  preprocessed text's markers. This keeps debug info correct while still sharing.

Also observed: clang's marker preamble differs from gcc's (`<built-in>` blocks appear in a
different order, `stdc-predef.h` appears at a different depth), so preprocessed output is
not comparable across compilers — which is fine, because the compiler identity is in the
key anyway.

### `run_second_cpp`

On a **miss** in preprocessor mode the wrapper has already produced the `.i`. It may
either (a) re-run the real compiler on the **original source** (ccache default,
`run_second_cpp=true`), costing a second preprocessing pass, or (b) feed the `.i` to the
compiler. (b) is faster but changes what the compiler sees: macros are already expanded,
so `-Wunused-macros`, `__FILE__`-in-warning text and some diagnostics differ. Keep (a) as
the default.

---

## 3. Direct mode: key + include manifest

Direct mode skips the preprocessor on a hit.

**The direct key** is a hash of (compiler identity, filtered argv **plus** the
`AFFECTS_CPP` args that preprocessor mode drops — `-I`, `-D` etc. are back in — plus the
env vars that affect the preprocessor: `CPATH`, `C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`,
`OBJC_INCLUDE_PATH`, `OBJCPLUS_INCLUDE_PATH`, `CLANG_CONFIG_FILE_SYSTEM_DIR`,
`CLANG_CONFIG_FILE_USER_DIR`, `INCLUDE`, `EXTERNAL_INCLUDE` — plus **the source file's
path** and **the source file's content**) (ccache.cpp `get_manifest_key` ~2367).

The source *path* is in the key deliberately. ccache's comment gives the reason: with
`a/r.h` existing, `a/x.c` containing `#include "r.h"`, and `b/x.c` being a copy, hashing
only the content would let `a/x.c` and `b/x.c` collide even though `"r.h"` resolves
differently for each (quote-includes search the *including file's* directory first).
buildcache hashes the resolved source path for the same reason plus a second one: it
keeps CI executors in different work directories from thrashing one entry
(`program_wrapper.cpp`).

**The manifest** is what the direct key maps to. Structurally (manifest.hpp):

```
Manifest
  m_files      : [path]                                   -- interned include paths
  m_file_infos : [(file_index, digest, size, mtime, ctime)]
  m_results    : [(file_info_indexes[], result_key)]       -- MULTIPLE candidates
```

**Why multiple candidates.** One command line can legitimately read *different* include
sets on different runs: a conditional `#include` behind a macro the build sets from the
environment; an `-I` path where a header appears or disappears; two checkouts where one
has an optional header. Each distinct include-set-plus-content produces its own
`ResultEntry`. On lookup the manifest walks its result entries in order and returns the
first whose every recorded file still matches (`result_matches`, manifest.cpp ~373). So
the manifest is *a list of "if these exact files have these exact digests, the answer is
X"* rules. Bounds: `k_max_manifest_entries = 100` result entries and
`k_max_manifest_file_info_entries = 10000` file infos; past either, the manifest is
reset rather than grown.

**Validation per file** (manifest.cpp ~373), in order:
1. stat the path; unreadable → miss (the include vanished).
2. size differs → miss (cheap reject).
3. If producing a PCH with clang and `-fno-pch-timestamp` is absent, an mtime change
   alone → miss.
4. If `file_stat_matches` sloppiness: mtime **and** ctime both equal → accept without
   hashing (`file_stat_matches_ctime` narrows this to mtime only).
5. Otherwise hash the file's content and compare digests.

**Populating the include set.** Two sources:
- The preprocessor's own report. buildcache uses `-H`, whose stderr lines are
  `<dots> <path>` with the dot count giving nesting depth (probe: `. sp ace.h`). ccache
  instead reads the linemarkers out of the `-E` output it already produced.
- Depend mode uses the compiler's `-MD`/`-MMD` output.

**A correctness trap I found by probe** (`probes/`, reproduced in `/tmp/oncetest`): GCC
implements `#pragma once` with a **content comparison**, not just an inode comparison. Two
*distinct* files with byte-identical contents, both using `#pragma once`, both `#include`d
— GCC opens only the first, and `-H`, `-MM` and the linemarkers list only the first:

```
$ printf '#pragma once\nint q(void);\n' > a.h; cp a.h b.h
$ printf '#include "a.h"\n#include "b.h"\nint main(void){return 0;}\n' > m.c
$ gcc   -MM m.c     ->  m.o: m.c a.h        # b.h absent!
$ clang -MM m.c     ->  m.o: m.c a.h b.h    # clang lists both
```

Consequence: a manifest built from gcc's include report can be **missing an entry**. If
`b.h` is later edited so that it no longer matches `a.h`, gcc *will* read it and produce
different output — but the manifest has no rule mentioning `b.h`, so direct mode serves a
**false hit**. Include guards (`#ifndef`) do not trigger it; only `#pragma once` with
identical content does. This is a latent bug in every dep-derived manifest, ccache's
included. The cheap mitigation: when the compiler is gcc and the source tree uses
`#pragma once`, treat two same-size headers in the include set as a reason to fall back
to preprocessor mode; the honest mitigation is to accept it as a documented sloppiness.

**Conditions that disable direct mode** (hashutil.cpp ~360): the source or any include
contains `__TIME__`, `#embed`, or `.incbin`. Each is unpredictable content the digest
cannot represent. `__DATE__` and `__TIMESTAMP__` do **not** disable it; see §4.

---

## 4. Depend mode

Depend mode (`depend_mode=true`, off by default) skips *both* the preprocessor run and
the direct-mode manifest lookup on a miss. It runs the real compiler immediately, then
derives the result key from the dependency information the compiler already emitted
(`result_key_from_depfile` / `result_key_from_includes`, ccache.cpp ~1344). Requirements:
`-MD`/`-MMD` (dep file) or `/showIncludes` (include list on stdout) must be present; if
neither, ccache silently turns depend mode off (ccache.cpp ~3016).

Trade: a miss costs exactly one compile instead of one preprocess plus one compile. Cost:
the key is only as complete as the compiler's dep output — which, per the `#pragma once`
finding above, is not complete on gcc. It is also the only mode that can see
`module.modulemap` files (§1.3).

---

## 5. Temporal macros and other sloppiness

ccache scans the source (and every include, via `hash_source_code_file`) for
`__DATE__`, `__TIME__`, `__TIMESTAMP__`, `#embed`, `.incbin`, using a word-boundary check
so `MY__DATE__X` does not trip it (hashutil.cpp ~90).

| Found | Default behaviour | Under `time_macros` sloppiness |
|---|---|---|
| `__TIME__` | **Direct mode disabled.** Preprocessor mode still works (the expanded time is in the `.i`, so the key changes every second — effectively no hits). | Ignored entirely. |
| `__DATE__` | Direct mode stays on, but the file's digest is **replaced** by `hash(digest, year, month, day, $SOURCE_DATE_EPOCH)`. So a hit is valid for the rest of the calendar day. | Ignored. |
| `__TIMESTAMP__` | Digest replaced by `hash(digest, strftime("%c", mtime_of_that_file))`. | Ignored. |
| `#embed` | Direct mode disabled (the embedded file is invisible to the digest). | `incbin` sloppiness covers `.incbin` only; `#embed` has no opt-out. |
| `.incbin` | Direct mode disabled. | `incbin` → ignored. |

`SOURCE_DATE_EPOCH` is hashed **in addition to** the real date, because ccache cannot know
whether the compiler honours it.

`__FILE__` is not scanned for. Probe `out/03-debug-and-paths.txt` §11 shows `__FILE__`
expands to *the path exactly as written on the command line* — `fi.c` when invoked
relatively, `/tmp/.../fi.c` when absolutely — and `-ffile-prefix-map` rewrites it only if
the written path starts with the mapped prefix. Since the source path is in the direct
key and the preprocessed text in the cpp key, `__FILE__` is covered implicitly.

Full sloppiness list (config.cpp): `clang_index_store`, `file_stat_matches`,
`file_stat_matches_ctime`, `gcno_cwd`, `incbin`, `include_file_ctime`,
`include_file_mtime`, `ivfsoverlay`, `locale`, `modules`, `pch_defines`, `random_seed`,
`system_headers`, `time_macros`.

---

## 6. Compiler identity

ccache's `compiler_check` (default `mtime`) is a choice between:

| Value | What is hashed |
|---|---|
| `mtime` (default) | The compiler binary's **size and mtime** — no read of the file. Fast; wrong if a binary is replaced in place with the same size and a preserved mtime, or if the mtime is normalised by a container image build. |
| `content` | The binary's full content. Correct; costs a read of a 100 MB+ file per invocation unless memoised. |
| `none` | Nothing. For a fixed toolchain image. |
| `string:<value>` | A caller-supplied identity (e.g. the toolchain image digest). The right answer in CI. |
| `<command>` | Run a command and hash its stdout; `%compiler%` is substituted. E.g. `%compiler% -v`. |

buildcache's default is the **hash of the binary's content**, but with a two-layer memo:
a small data store keyed by `path:size:mtime` caches the computed program id for 300
seconds (`program_wrapper.cpp::get_program_id_cached`). Its gcc wrapper overrides the
default to hash `<compiler> --version` output prefixed by a `HASH_VERSION` constant
(bumped when the wrapper's own format changes). Its rust wrapper goes much further: it
hashes `rustc -vV`, `rustc --print=sysroot`, **and the content of every shared library in
`$sysroot/lib`**, sorted.

`--version` alone is a weak identity: two builds of gcc 13.3.0 with different patches
report the same string. The `HASH_VERSION` prefix is a good pattern regardless — it lets a
wrapper change its own hashing rules without a stale-cache incident.

A separate identity input a wrapper must not forget: **the name it was invoked under**
(§2 item 2), and `COMPILER_PATH`/`GCC_EXEC_PREFIX`, which change which `cc1` runs.

---

## 7. Outputs, diagnostics, exit code

**What is cached for one compile:**
- the object (`-o`, or derived from the source basename if `-o` is absent, with the
  extension chosen by mode: `.o`, `.s` under `-S`, `.plist` under `-analyze`);
- the dependency file, if `-MD`/`-MMD`/`-MF`;
- `<object>.dwo` under `-gsplit-dwarf` (unless the object is `/dev/null`);
- `<object>.gcno` under coverage;
- `.su` (`-fstack-usage`), `.ci` (`-fcallgraph-info`), `.dia`
  (`--serialize-diagnostics`), `.sarif` where requested;
- **stderr, verbatim**;
- **stdout** (modern ccache caches it too; the historical
  `compiler_produced_stdout` bypass is marked obsolete in `statistics.cpp`);
- **the exit status**.

**Exit code.** A non-zero compile is **not** cached by ccache (the result is only stored
on success) nor by buildcache, whose comment is explicit: "we do not want to cache
intermittent faults". buildcache exposes `cache_on_failure` as an opt-in. Note the
subtlety: buildcache still *returns* the failing exit code and does not re-run, because
re-running would just take twice as long for the same errors.

**Diagnostics must be replayed byte-for-byte**, because a `-Werror` build's whole
observable output is its diagnostics, and because IDEs parse them. Two normalisation
problems:

1. **Colour depends on the TTY.** Probe `out/04-flags.txt`: with stderr a pipe, gcc emits
   plain text; with `-fdiagnostics-color=always` it emits
   `^[[01m^[[K…^[[m^[[K` sequences. Because the wrapper *always* captures the compiler's
   stderr through a pipe, the compiler would never colour — so the cached copy would be
   colourless even for a user on a terminal. ccache's answer (argprocessing.cpp ~1980):
   **force colour on** when running the compiler (`-fdiagnostics-color` for gcc,
   `-fcolor-diagnostics` for clang), cache the coloured text, and **strip the escapes on
   replay** when the user's own stderr is not a terminal or `…-color=never` was given
   (`strip_diagnostics_colors`). It skips `-fcolor-diagnostics` for assembler inputs to
   avoid clang's "argument unused" warning. `GCC_COLORS` is also read, so the palette is
   part of the picture.
2. **Locale.** Covered by hashing `LANG`/`LC_*` (§2 item 4).

**`-Werror` interplay.** `-Werror` is `AFFECTS_COMP` in ccache's table — deliberately
*not* passed to the preprocessor run, with the comment "don't exit with error when
preprocessing". A `#warning` in a header would otherwise make the preprocessing step fail
and force `preprocessor_error`. It is still hashed (it changes the compile's outcome).

---

## 8. Dependency files: exact format, escaping, and rewriting

### The format gcc and clang emit

From `out/01-depfiles.txt`:

```
objs/hello.o: hello.c /usr/include/stdc-predef.h /usr/include/stdio.h \
 /usr/include/x86_64-linux-gnu/bits/libc-header-start.h \
 /usr/include/features.h \
 …
```

Rules observed:
- One logical line: `<target>: <prereq> <prereq> …`, wrapped with ` \` + newline.
  Continuation lines are indented by one space.
- `-MP` adds, after the main rule, a **phony target per prerequisite** so that a deleted
  header does not break `make`:
  ```
  /usr/include/stdio.h:
  ```
- `-MT <text>` replaces the target with `<text>` **unquoted**; `-MQ <text>` replaces it
  **quoted for make**. Probe: `-MT 'a b.o'` → `a b.o: …` (ambiguous to make);
  `-MQ 'a b.o'` → `a\ b.o: …`.

### Escaping of prerequisite paths

Probed with files literally named `sp ace.h`, `dol$lar.h`, `hash#mark.h`,
`back\slash.h`, `colon:c.h`:

| char | gcc emits | clang emits |
|---|---|---|
| space | `sp\ ace.h` | `sp\ ace.h` |
| `$` | `dol$$lar.h` | `dol$$lar.h` |
| `#` | `hash\#mark.h` | `hash\#mark.h` |
| `\` | `back\slash.h` (**not** escaped) | `back/slash.h` (**rewritten to `/`**) |
| `:` | `colon:c.h` (**not** escaped) | `colon:c.h` |

ccache's own escaper (`depfile.cpp::escape_filename`) escapes `\`, `#`, `:`, space and
tab with a backslash, and doubles `$`. So ccache escapes **more** than gcc does (`\` and
`:`). A wrapper that round-trips a dep file through parse-and-re-emit will therefore not
be byte-identical to the compiler's own output. Prefer storing the dep file **verbatim**
and rewriting only what must change.

Tokenising a dep file correctly is genuinely hard on Windows because `c:/meow` is a drive
letter, not target-colon-prerequisite. ccache documents its GNU Make 4.3 experiments in a
comment block in `depfile.cpp`; the summary is that make treats `cat:c:/meow` as target
`cat` + prereq `c:/meow`, but `cat:c:meow` as an error.

### Where the `.d` lands

Probed:
- `-MD` with `-o <path>` → the dep file is `<path>` with the extension replaced by `.d`,
  **in the same directory as the object** (`-o /tmp/h1.o` → `/tmp/h1.d`;
  `-o objs/hello.o` → `objs/hello.d`). Same for clang.
- `-MD` with no `-o` → `<source-basename>.d` in the **cwd**.
- `-MF <path>` overrides both.
- `-E -MD -o /dev/null` wrote no `.d` at all — another reason `-E` is a bypass.

### What must be rewritten, and when

- **On a MISS**, before storing: if `base_dir` is configured, rewrite every absolute
  prerequisite path under `base_dir` into a cwd-relative path, leaving the **target**
  (first token) alone (`depfile.cpp::rewrite_source_paths` — "Don't rewrite object file
  path"). This is what makes the stored dep file reusable from another checkout.
- **On a HIT**, while restoring: if the invocation named a different `-MT`/`-MQ` target
  than the one recorded, replace everything up to the first `": "` with the requested
  target and write the rest unchanged (`resultretriever.cpp` ~240). ccache stores
  `dependency_target` for exactly this. So: **ccache rewrites the target on a hit.**
  sccache stores the dep file as one of the compiler's outputs and writes it back
  unmodified — it has no target-rewrite step, which is safe only because sccache's key
  includes the full argv (including `-MT`), so a different target is a different key
  rather than a rewritten hit.
- buildcache takes a third approach for gcc: it does **not** cache the dep file at all.
  On a hit it *regenerates* one from the include list it recorded
  (`gcc_wrapper.cpp::maybe_generate_dependency_file`), writing `target: srcfile \`
  followed by one indented include per line. Two bugs are visible in that code and worth
  learning from: it does not escape spaces in paths, and its include list comes from
  `-H` stderr, which (its own TODO admits) omits implicit includes such as
  `/usr/include/stdc-predef.h` — which gcc's real `-MD` output *does* list (probe
  confirms). `-MQ` is an outright `throw`.

### Response files

gcc and clang accept `@file`, recursively. Probe: a response file containing `@other.rsp`
is expanded (out/04-flags.txt). Quoting inside follows shell-like rules
(`-DSTR="a b"` works). buildcache expands them in `resolve_args()` **before** any other
step and falls back to leaving `@name` verbatim if the file cannot be opened — which is
what gcc itself does. MSVC additionally allows UTF-16 with a BOM (buildcache's
`msvc_wrapper.cpp::resolve_args` sniffs for `FF FE`/`FE FF`). A wrapper must expand
response files before classification, because the real argv is inside them; and it must
decide whether the response file's *content* is hashed (it is, transitively, since the
expanded args are hashed) or its *path* (it must not be).

---

## 9. Worked examples

| argv | Verdict |
|---|---|
| `gcc -c -O2 foo.c -o foo.o` | Cacheable. object=`foo.o`. |
| `gcc -c -O2 -MD -MF dep/foo.d foo.c -o obj/foo.o` | Cacheable. outputs: `obj/foo.o`, `dep/foo.d`. |
| `gcc -O2 foo.c -o foo` | `called_for_link` (no `-c`). |
| `gcc -O2 conftest.c -o conftest` | `autoconf_test`. |
| `gcc -c a.c b.c` | `multiple_source_files`. |
| `gcc -E foo.c` | `called_for_preprocessing` (`-E` is TOO_HARD). |
| `gcc -M foo.c` | `called_for_preprocessing`. |
| `gcc -c -MMD foo.c -o foo.o` | Cacheable (`-MMD` is not `-MM`). |
| `gcc -S -O2 foo.c -o foo.s` | **Cacheable**; output `foo.s`. |
| `gcc -fsyntax-only foo.c` | Cacheable; **no** output file, only stderr + exit code. |
| `gcc -c foo.c -o -` | `output_to_stdout`. |
| `echo 'int m;' \| gcc -x c -c - -o m.o` | Bypass (stdin source, no identity). |
| `gcc -c -save-temps foo.c -o foo.o` | `unsupported_compiler_option`. |
| `gcc -c -march=native -O3 foo.c -o foo.o` | Cacheable; key includes the `-###`-expanded cc1 arch line. |
| `gcc -c -g -gsplit-dwarf foo.c -o foo.o` | Cacheable; outputs `foo.o` + `foo.dwo`. |
| `gcc -c --coverage foo.c -o foo.o` | Cacheable; outputs `foo.o` + `foo.gcno`; cwd matters unless `gcno_cwd`. |
| `gcc -c -flto foo.c -o foo.o` | Cacheable; object is bitcode and is not byte-reproducible run-to-run. |
| `gcc -c -fprofile-use=p.gcda foo.c -o foo.o` | Cacheable **iff** `p.gcda` is hashed by content. |
| `gcc -c -fprofile-generate foo.c -o foo.o` | Cacheable; profile path (`$PWD`) is in the key. |
| `clang -c -fmodules foo.c -o foo.o` | `could_not_use_modules` unless depend+direct mode **and** `modules` sloppiness. |
| `gcc -c -Wp,-MD,a.d -MF b.d foo.c -o foo.o` | `unsupported_compiler_option` (gcc/clang disagree on which file wins). |
| `g++ -c -include pch.h foo.cc -o foo.o` with `pch.h.gch` present | Needs `time_macros` sloppiness, else `could_not_use_precompiled_header`. |
| `gcc @resp.rsp foo.c` | Expand `resp.rsp` (recursively) first, then classify the expanded argv. |

---

## 10. The rule table for gcc/clang

This is the per-flag knowledge a gcc rule needs, written down as a table. **The table is a
way of recording the findings, not a proposal for the rule surface** — the planner decides
what the surface looks like. Whatever shape it takes, this content has to be expressed
somewhere: each flag family needs a way to say how its value is spelled (the `value`
column) and what the value means to the cache (the `role` column). Where a column names
work I think the engine should do rather than a rule author (argument-syntax parsing,
sibling derivation, prefix mapping), that is flagged as my opinion in §10.4 and in
`key-derivation-model.md`, not as a decision.

### 10.1 The `value` vocabulary (engine-owned GNU argument syntax)

| `value` | Shape | Example |
|---|---|---|
| `none` | a bare flag | `-c`, `-O2`, `-fPIC` |
| `sep` | value is the next argv element | `-o foo.o`, `-MF dep.d` |
| `concat` | value is glued to the flag | `-DFOO=1`, `-Ifoo` |
| `either` | both spellings accepted | `-I` (gcc accepts `-Ifoo` and `-I foo`) |
| `eq` | `--flag=value` | `-fdebug-prefix-map=a=b`, `--sysroot=/x` |
| `eq-or-sep` | `--flag=v` or `--flag v` | `--param x=1` |
| `comma-list` | value is a comma-separated list after the prefix | `-Wp,-MD,file`, `-Wl,-x,-y` |
| `prefix-rest` | the whole tail is the value; matched by prefix | `-fprofile-use=…`, `-std=…` |
| `positional` | not a flag; classified by extension / `-x` state | `foo.c` |

Two syntaxes the engine must own outright, because no table entry can express them:

- **`@file` response files** — expanded **recursively** before the table is consulted,
  with shell-like quoting; an unopenable file is left verbatim as `@name` (gcc's own
  behaviour). The *path* is never hashed; the expanded arguments are.
- **`-Wp,<a>,<b>` / `-Xpreprocessor <a>` / `-Xassembler` / `-Xlinker` / `-Xclang <a>`
  forwarding** — the engine splits the payload and re-runs the table over it, so that
  `-Wp,-MD,x.d` is classified as a dep-output and `-Xclang -ast-dump` as a bypass, without
  either needing a bespoke entry.

### 10.2 The `role` vocabulary

| `role` | Meaning for the engine |
|---|---|
| `source-input` | The compiled file. Exactly one; content + path both hashed. |
| `primary-output` | Where the main artifact goes. Captured and restored; the *path* is never hashed. |
| `dep-output` | Where a Makefile-format dep file goes. Captured, **and** rewritten on hit/miss (§8). |
| `dep-target` | The text to use as the dep file's target (`-MT`/`-MQ`). Drives the on-hit rewrite. |
| `derived-output:<ext>` | The engine computes `<primary-output> with extension <ext>` and captures it too. |
| `path-read` | The value is a file whose **content** is a hash input. |
| `dir-read` | The value is a search directory. Affects *discovery*, not content: hashed in direct mode, dropped in preprocessor mode, subject to prefix mapping. |
| `path-write-untracked` | A path the tool writes that is **not** cached (MSVC `/Fd`). Passed through, never hashed. |
| `hash-verbatim` | The argument text goes into the key unchanged. The default for anything not otherwise classified. |
| `hash-expanded` | The engine asks the tool what it expanded to and hashes *that* (`-march=native`). |
| `hash-normalized-path` | The argument is a path: apply prefix mapping / base-dir relativisation, then hash the result. |
| `ignore` | Passed to the tool, absent from the key. |
| `cpp-only` | Affects preprocessing only → excluded from the preprocessor-mode key, included in the direct-mode key. |
| `comp-only` | Affects compilation only → **not passed** to the preprocessor run. |
| `bypass:<reason>` | Decline, logging one of the closed reason codes. |
| `mode:<name>` | Sets an engine mode flag the verdict logic reads (`compiling`, `linking`, `generating-deps`, `debug-info`, `coverage`, `pch-create`, `pch-use`, `lto`, …). |

A cell may carry more than one role (`cpp-only + dir-read`), and any row may be
`gated:<sloppiness>`.

### 10.3 The table

| pattern | value | role | notes |
|---|---|---|---|
| `*.c *.cc *.cpp *.cxx *.C *.m *.mm *.s *.S *.i *.ii` | `positional` | `source-input` | Extension → language; `-x` overrides. More than one → `bypass:multiple_source_files` when compiling, `bypass:called_for_link` when linking. |
| `-o` | `either` | `primary-output` | `-o -` → `bypass:output_to_stdout`. `/dev/null` suppresses derived outputs. Absent → derive from source basename + mode extension. |
| `-c` `--compile` | `none` | `mode:compiling` | |
| `-S` | `none` | `mode:compiling` | Output extension becomes `.s`. **Not** a bypass. |
| `-E` `-EP` | `none` | `bypass:called_for_preprocessing` | |
| `-fsyntax-only` `-Zs` | `none` | `mode:compiling` + `no-primary-output` | Exit code + stderr are the whole result. |
| `-analyze` | `none` | `bypass:unsupported_compiler_option` | ccache: TOO_HARD. (Its output extension `.plist` is handled only because `-analyze` also sets `found_analyze_opt`.) |
| `-M` `-MM` | `none` | `bypass:called_for_preprocessing` | Writes deps to stdout, no object. |
| `-MD` `-MMD` | `none` | `mode:generating-deps` + `comp-only` | Dep path defaults to `<-o path>` with `.d`, else `<source>.d` in cwd (**measured**). |
| `-MF` | `either` | `dep-output` | Overrides the default. `/dev/null` → drop dep generation. |
| `-MT` | `sep` | `dep-target` (raw) | |
| `-MQ` | `sep` | `dep-target` (make-quoted) | buildcache throws on this; do not. |
| `-MP` | `none` | `hash-verbatim` | Adds phony targets; affects the dep file's bytes, so it is in the key. |
| `-MG` `-MD -MP` combos | `none` | `hash-verbatim` | |
| `-MJ` | `either` | `bypass:unsupported_compiler_option` | Appends to a shared compilation DB. |
| `-Wp,…` | `comma-list` | *re-dispatch* | `-Wp,-MD,f` = `-MD` + dep-output `f`. **`-Wp,-M[M]D` together with `-MF` → `bypass:unsupported_compiler_option`**: gcc honours the `-Wp` path, clang the `-MF` path. |
| `-Xpreprocessor` | `sep` | *re-dispatch*, `cpp-only` | |
| `-Xassembler` `-Xlinker` | `either` | `hash-verbatim`, `comp-only` | |
| `-Xclang` | `sep` | *re-dispatch* | The payload may itself be TOO_HARD (`-ast-dump`). |
| `-I` `-iquote` `-isystem` `-idirafter` `-iprefix` `-iwithprefix` `-iwithprefixbefore` `-imultilib` `-iframework` `-imsvc` | `either` | `dir-read` + `cpp-only` | Order matters for *discovery*, which the include manifest records; it does not enter the preprocessor-mode key. |
| `-isysroot` `--sysroot=` `--gcc-toolchain=` `-gcc-toolchain` `-B` | `either`/`eq` | `dir-read` | Not `cpp-only` for `-B` (it changes which `as`/`ld` run). |
| `-nostdinc` `-nostdinc++` `-stdlib=` `-trigraphs` `-remap` `-fworking-directory` `-fno-working-directory` | `none`/`eq` | `cpp-only` | |
| `-D` `-U` | `either` | `cpp-only` | Present in the direct-mode key, absent from the cpp-mode key. |
| `-include` `-imacros` `-include-pch` `-include-pth` `--include` | `either` | `path-read` + `cpp-only` | |
| `-x` | `sep` | `mode:language` | Unknown language → `bypass:unsupported_source_language`. `-x none` clears. Must be re-passed to the compiler when feeding it preprocessed text. |
| `-finput-charset=` | `eq` | `hash-verbatim`, `comp-only` | Must be re-passed with preprocessed input, or conversion happens twice. |
| `-g -ggdb -gdwarf-N -gstabs …` | `none` | `mode:debug-info` | `-g0`/`-ggdb0` clears it. `-gz[=t]` is neutral. Sets whether cwd enters the key. |
| `-gsplit-dwarf` | `none` | `derived-output:.dwo` | Suppressed when the object is `/dev/null` (**ccache**). Object path enters the key because the `.o` links to the `.dwo` by name. |
| `--coverage` `-coverage` `-ftest-coverage` `-fprofile-arcs` | `none` | `mode:coverage` + `derived-output:.gcno` | **Measured**: `gcc --coverage -c x.c -o cov.o` → `cov.o` + `cov.gcno`. |
| `-fprofile-instr-generate` | `none`/`eq` | `mode:coverage` (clang) | |
| `-fstack-usage` | `none` | `derived-output:.su` | |
| `-fcallgraph-info*` | `prefix-rest` | `derived-output:.ci` | |
| `--serialize-diagnostics` | `sep` | `primary-output` (secondary) | `TAKES_PATH`. |
| `-fprofile-use[=p]` `-fprofile-instr-use[=p]` `-fprofile-sample-use[=p]` `-fauto-profile[=p]` `-fbranch-probabilities` | `prefix-rest` | `path-read` + `hash-normalized-path` | The profile data is a real input. More than one → `bypass:unsupported_compiler_option`. The bare forms imply `.` / the object's basename — a path the engine cannot resolve, so treat bare-form as `bypass` unless the rule states a resolution. |
| `-fprofile-generate[=p]` `-fprofile-instr-generate=p` `-fprofile-dir=p` | `prefix-rest` | `hash-normalized-path` | The path is baked into the instrumented object. gcc defaults to `$PWD`, clang to `.`. |
| `-fprofile-abs-path` | `none` | `hash-verbatim` + `force-hash-cwd` | `gated:gcno_cwd` to skip the cwd hash. |
| `-fprofile-prefix-path=` | `eq` | `hash-normalized-path` | |
| `-fprofile-correction -fprofile-values -fprofile-update* …` | `none`/`prefix-rest` | `hash-verbatim` | Inert for caching. |
| `-fsanitize-ignorelist=` `-fsanitize-blacklist=` | `eq` | `path-read` + `hash-normalized-path` | |
| `-fplugin=<path>` | `eq` | **`path-read`** (ccache only hashes the string — close this hole) | `-fplugin=libcc1plugin` → `bypass:unsupported_compiler_option`. |
| `-specs=<file>` `-specs <file>` | `either` | **`path-read`** (ccache only hashes the string — close this hole) | |
| `--config <file>` (clang) | `sep` | **`path-read`** | Same hole. |
| `-fmodules` | `none` | `bypass:could_not_use_modules` unless depend+direct mode, then `gated:modules` | |
| `-fmodule-file=[n=]<path>` | `eq` | `path-read` | The BMI's content is the input. |
| `-fmodule-map-file=` `-fmodules-cache-path=` | `eq` | `hash-normalized-path` | |
| `-fmodule-header` `-fmodules-ts` | `none` | `bypass:could_not_use_modules` | |
| `-fpch-preprocess` | `none` | `mode:pch-use` | Engine **adds** it to the compiler args when a PCH is in play, so the `#pragma GCC pch_preprocess "x.gch"` marker reaches the preprocessed text (**measured**). |
| output ends `.gch`/`.pch`, or `-x *-header` | — | `mode:pch-create` | `gated:pch_defines,time_macros`, else `bypass:could_not_use_precompiled_header`. |
| `-fno-pch-timestamp` | `none` | `hash-verbatim` + relax the clang PCH mtime check | |
| `-march=native` `-mcpu=native` `-mtune=native` | `none` | `hash-expanded` | Engine runs `<cc> -### -E - <flag>`, takes the `/cc1 -E` (gcc) or `"-cc1"` (clang) line; for clang, keep only arch-related options (drop `-fdebug-compilation-dir`, `-fcoverage-compilation-dir`). **Measured**. |
| `-frecord-gcc-switches` | `none` | `hash-full-argv` | The switches land in `.GCC.command.line`. |
| `-frandom-seed=` | `eq` | `hash-verbatim`, `gated:random_seed` to ignore | |
| `-flto[=n]` / `-fno-lto` | `none`/`eq` | `mode:lto` + `hash-verbatim` | Still cacheable. The object is bitcode and is **not** byte-reproducible run to run (**measured**). |
| `-fdebug-prefix-map=a=b` `-ffile-prefix-map=` `-fmacro-prefix-map=` `-fcoverage-prefix-map=` | `eq` | `prefix-map` | Engine-owned: applies to the cwd before hashing it, and to paths under `hash-normalized-path`. Order matters — **applied in reverse argv order** (ccache reverses the list). |
| `-fdebug-compilation-dir=` `-fcoverage-compilation-dir=` (clang) | `eq` | `set-compilation-dir` | Replaces the cwd in the key outright. |
| `-fdiagnostics-color[=auto\|always\|never]` `-fcolor-diagnostics` `-fno-…` | `none`/`eq` | `diagnostics-color` | Engine-owned: **force colour on** for the child, cache the coloured stderr, strip on replay when the user's stderr is not a TTY. |
| `-Werror` `-Wno-error` `-Werror=*` | `none`/`eq` | `hash-verbatim` + `comp-only` | Withheld from the preprocessor run so a `#warning` does not fail it. |
| `-save-temps[=cwd\|obj]` `--save-temps*` | `none`/`eq` | `bypass:unsupported_compiler_option` | Writes unknown siblings. |
| `-ftime-trace` | `none` | `bypass:unsupported_compiler_option` | Output contains wall-clock durations. |
| `-gen-cdb-fragment-path` | `sep` | `bypass:unsupported_compiler_option` | |
| `-frepo` `-gtoggle` `-wrapper` `-ast-view` `-ast-merge` `--analyzer-output` | — | `bypass:unsupported_compiler_option` | |
| `-ivfsoverlay` `-ivfsstatcache` | `sep` | `path-read`, `gated:ivfsoverlay` | |
| `-fbuild-session-file=` | `eq` | `hash-normalized-path` | |
| `-L` `-l` `-Wl,…` `-shared` `-pie` `-rdynamic` `-bundle` `-all_load` `-install_name` | various | `comp-only` + `hash-verbatim` | Meaningful only when linking, which is already a bypass; hashed so they cannot silently differ. |
| `@<file>` | — | *expand recursively, then re-dispatch* | Never hashed as a path. |
| anything else starting `-` | `none` | `hash-verbatim` | **Note the risk**: an unknown flag that takes a *separate* argument will have its value mis-read as a source file. buildcache's rust wrapper refuses unknown flags for exactly this reason; a C rule should at minimum log it. |

### 10.4 Engine primitives this table assumes exist

`gnu-argv-parse` (the `value` column) · `response-file-expand` (recursive, quoted) ·
`comma-forward-split` (`-Wp,`/`-Xclang`) · `derive-sibling-path(ext)` ·
`depfile-parse` / `depfile-escape` / `depfile-rewrite-target` /
`depfile-relativise-prerequisites` · `linemarker-scan` (build the include set from `-E`
output) · `include-report-scan` (`-H` stderr: dots = depth) · `prefix-map-apply`
(reverse-ordered) · `base-dir-relativise` · `tool-expansion-query` (`-### -E -`) ·
`diagnostics-color-force-and-strip` · `temporal-macro-scan` (`__DATE__`/`__TIME__`/
`__TIMESTAMP__`/`#embed`/`.incbin`, word-boundary aware) · `source-too-new-check`.
