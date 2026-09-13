# MSVC `cl.exe` (and `clang-cl`)

Sources: ccache `src/ccache/argprocessing.cpp`, `src/ccache/ccache.cpp`,
`src/ccache/compiler/msvc.cpp` (**GPL-3.0**, behaviour only); sccache
`src/compiler/msvc.rs` (**Apache-2.0**); buildcache `src/wrappers/msvc_wrapper.cpp` and
`clang_cl_wrapper.cpp` (**zlib**). No Windows machine was available, so nothing here is
probe-verified; every statement is cited to code I read.

## 1. Flag syntax: the parsing model

`cl.exe` accepts a flag with either leader — `/c` and `-c` are the same. Values are
usually **concatenated** (`/Fofoo.obj`), and several also accept an optional colon
(`/Fo:foo.obj`). buildcache's helpers make this explicit:

- `arg_starts_with(s, "Fo")` — true when `s[0]` is `/` or `-` and `s[1..]` starts with
  `Fo`.
- `drop_leading_colon(v)` — strips one leading `:` from the extracted value.

sccache encodes the same thing declaratively, per flag, with a
`(name, value-type, Concatenated | Separated | CanBeSeparated, semantic-class)` tuple —
this is the shape an XML rule language should mirror. `CanBeSeparated` exists because a
few flags (`/external:I`, `/sourceDependencies`, `/ifcOutput`) accept both spellings.

`--` before the source file is accepted (`parsed_args.double_dash_input` in sccache;
buildcache's `make_preprocessor_cmd` appends `--` before the source unconditionally) and
is how a filename starting with `/` or `-` is disambiguated.

## 2. Cacheable shape

Same single-compile rule as gcc:

- `/c` must be present.
- Exactly one source file (`.c`, `.cpp`, `.cc`, `.cxx`; also `/Tc<file>` and `/Tp<file>`,
  which force the language — ccache marks both **TOO_HARD** in `compopt.cpp`, sccache
  parses them).
- Output: `/Fo<path>`. If `/Fo` names a **directory** (trailing `\` or an existing
  directory), the object name is derived from the source basename — ccache handles both
  cases (`argprocessing.cpp` ~1790); sccache has a test for `/Fomyrelease\folder\`.
- `/link` → bypass (`TOO_HARD` in ccache): everything after it is linker argv.

## 3. Debug information: the PDB problem

This is the single biggest MSVC-specific hazard.

| Flag | Meaning | Treatment |
|---|---|---|
| `/Z7` | Debug info **inside the `.obj`** (CodeView). | **Cacheable.** The object is self-contained. |
| `/Zi` | Debug info in a **separate shared `.pdb`**. | Bypass. |
| `/ZI` | `/Zi` plus edit-and-continue; implies `/FC` (absolute paths in messages). | Bypass. |

ccache: "`/Zi` and `/ZI` are unsupported, but `/Z7` is fine" — it records the last-seen
`/Z…` debug option and returns `unsupported_compiler_option` if it is not `/Z7`
(`argprocessing.cpp` ~1738). buildcache's `msvc_wrapper.cpp::preprocess_source` throws
`"PDB generation is not supported."` on `/Zi` or `/ZI`.

Why: a `.pdb` is **shared across every `.obj` in the project** and is written by *several*
compiler processes serially (that is what `/FS` exists for). It is not a function of one
compile's inputs, it is an accumulator. Restoring one compile's contribution to a shared
PDB from a cache is not expressible as "write these files".

The practical remedy the ecosystem has settled on is **conversion, not bypass**: tell the
build system to emit embedded debug info instead. CMake exposes this as
`CMAKE_MSVC_DEBUG_INFORMATION_FORMAT` — buildcache's own `doc/usage.md` instructs users to
set `"$<$<CONFIG:Debug,RelWithDebInfo>:Embedded>"` (i.e. `/Z7`) when using buildcache.
A wrapper cannot do this rewrite itself: silently turning `/Zi` into `/Z7` changes the
artifacts the linker expects.

**`/Fd<path>`** names the PDB. ccache adds it to the compiler args **without hashing it**
(`add_compiler_only_arg_no_hash`) — the PDB path does not change the object under `/Z7`.
sccache appends `.pdb` if the `/Fd` value has no extension (it has a test for this).

**`/FS`** (force synchronous PDB writes) and **`/MP`** (multi-process compile) are also
added-but-not-hashed by ccache. `/MP` is doubly interesting: with several sources it
implies the multiple-source-file bypass anyway, and with one source it is a no-op for the
key.

## 4. `/showIncludes`: the include list, and its localized prefix

`cl.exe /showIncludes` writes one line **per included file to stdout** (not stderr —
this differs from gcc's `-H`), of the form:

```
Note: including file: C:\Program Files\...\include\stdio.h
Note: including file:  C:\Program Files\...\include\corecrt.h
```

The indentation after the prefix encodes nesting depth. Three hazards:

1. **The prefix is localized.** On a Japanese or German Visual Studio the string is not
   `Note: including file:`. ccache exposes it as a config value (`msvc_dep_prefix`).
   **sccache detects it at runtime** (`detect_showincludes_prefix`, `msvc.rs` ~169):
   it writes a temp `test.c` containing `#include "test.h"` plus an empty `test.h`, runs
   `cl -nologo -showIncludes -c -Fonul -I. -E test.c` in that temp directory, then finds
   the stderr/stdout line ending in `test.h` and walks **backwards** from the end of the
   line looking for a space such that the remainder is an existing path. Everything before
   that space is the prefix. This is the robust answer and needs no locale table.
   (For `clang.exe` on Windows it first adds `--driver-mode=cl`, since plain clang reports
   MSVC's predefines but rejects MSVC argv.)
2. **The lines are interleaved with real diagnostics on stdout.** They must be *stripped*
   before the stdout is cached, and *regenerated* on a hit — otherwise the replayed output
   contains another workspace's absolute paths. ccache does this with
   `strip_includes_from_msvc_show_includes` (only when it turned `/showIncludes` on itself,
   `ctx.auto_depend_mode`) and buildcache does it unconditionally when the *user* asked for
   `/showIncludes` (`run_for_miss` strips, `finalize_after_hit` re-emits
   `"Note: including file: " + path` for each recorded include, in sorted order).
   Note buildcache's regeneration loses the **indentation** and therefore the nesting
   depth, and sorts the paths — tools that parse depth will see different output on a hit
   than on a miss. A correct implementation must keep the depth prefix.
3. ccache's comment: with `/showIncludes` you **cannot distinguish system headers from
   project headers**, so there is no `-MMD` equivalent.

`clang-cl` supports `/showIncludes:user` (project headers only); ccache's extractor
handles both.

## 5. `/sourceDependencies`: the JSON alternative

Modern `cl.exe` (VS 2019 16.7+) offers `/sourceDependencies <file>` (or
`/sourceDependencies<file>`), which writes a JSON document instead of interleaving stdout
lines. sccache classifies it as `DepFile` and, when it preprocesses a **non-clang** MSVC
invocation, passes `/sourceDependencies <depfile>` itself (`msvc.rs` ~1012). Shape:

```json
{ "Version": "1.2",
  "Data": { "Source": "c:\\proj\\foo.cpp",
            "ProvidedModule": "",
            "Includes": [ "c:\\...\\stdio.h", "c:\\...\\corecrt.h" ],
            "Modules": [], "ImportedModules": [], "ImportedHeaderUnits": [] } }
```

It is strictly better than `/showIncludes` for a cache: it is a separate file (no stdout
interleaving), it is not localized, and it names modules and header units. Its downside is
that it is *only* MSVC — `clang-cl` does not implement it, which is exactly why sccache
branches: clang-cl gets `-showIncludes` and sccache then **synthesises a GNU-make-style
`.d` file itself** from the `showIncludes` lines (`msvc.rs` ~1073): it writes
`<obj>: <src> <dep> <dep> …`, then a `<src>:` line and one `<dep>:` phony line per
dependency (the `-MP` equivalent), skipping any dependency whose path **contains a
space** — a documented limitation, since it has no escaper.

sccache also adds **`/WX-`** to the preprocessing run for real MSVC, because the Windows
SDK emits `C4668` during preprocessing that does not appear in a real compile
(sccache issues #1725, #2250). This is the MSVC analogue of ccache dropping `-Werror`
from the preprocessor run.

## 6. Precompiled headers: `/Yc` and `/Yu`

- **`/Yc[header]`** — *create* a PCH. Output is the `.pch` named by `/Fp`, else derived
  from the `/Yc` header name, else the source basename + `.pch` (buildcache's
  `get_pch_file`). buildcache caches it as a second required build file. **sccache
  refuses**: `/Yc` is `TooHardPath` with the comment "Compile PCH - not yet supported",
  and so is `/Fp`.
- **`/Yu[header]`** — *use* a PCH. The `.pch` is an **input whose content must be in the
  key**. buildcache implements exactly this in `get_hash_extra_content()`: if `/Yu` is
  present, resolve the pch path (`/Fp` → `/Yu` name with `.pch` → source basename) and
  mix its **content hash** into the key, memoised in a data store by `path:size:mtime`
  for 300 s because a `.pch` is routinely 100–400 MB. Its stated reason is concrete: under
  `/Z7`, objects carry PCH-derived type-info signatures, and mixing objects built against
  different PCHs produces `LNK4206` at link time.
- `/YI` (inject an `#include` into the PCH) has no effect without `/Yc`; sccache passes it
  through with its suffix.
- ccache's table marks `-Yc` and `-Yu` as `AFFECTS_CPP | TAKES_CONCAT_ARG | TAKES_PATH`,
  and `-Fp` likewise — i.e. ccache treats them as preprocessor-affecting path arguments
  and relies on the preprocessed text; it does **not** hash the `.pch` content. buildcache's
  approach is the safer of the two.

## 7. Include paths and forced includes

| Flag | Class |
|---|---|
| `/I <dir>` or `/I<dir>` | preprocessor path; dropped from the preprocessor-mode hash, present in the direct-mode hash |
| `/external:I <dir>` | same, but marks the tree as "external" (warnings suppressed). sccache parses it as `ExternalIncludePath`, and notes it **only parses after `/experimental:external` has been seen** on older toolsets |
| `/FI <file>` | **forced include**, resolved relative to the **source file's directory**, not the cwd |
| `/FU <file>` | forced `#using` (managed) — sccache `TooHardPath` |
| `/D`, `/U` | preprocessor defines |

**`/FI` is the special case worth calling out.** ccache cannot rewrite it to a
`base_dir`-relative path in the ordinary argv pass, because the base for that path is the
*source file's* directory, which is only known once all arguments are parsed. So it sets a
`rewrite_FI_args` flag during the scan and performs a second pass at the end
(`argprocessing.cpp` ~1748), canonicalising the input file, taking its parent directory,
and rewriting every `/FI`/`-FI` value relative to that. sccache's comment at ~1195 says the
same thing from the other side: "It's important to avoid preprocessor_args because of
things like /FI".

## 8. Environment variables

| Variable | Effect | Treatment |
|---|---|---|
| `INCLUDE` | The system include search path. | **Must be in the key.** ccache hashes it in the direct-mode/manifest key alongside `CPATH` &c. |
| `EXTERNAL_INCLUDE` | `/external:I` equivalent. | Same. |
| `LIB` | Link-time only. | Irrelevant to a `-c` compile. |
| `CL`, `_CL_` | Arguments **prepended / appended** to every `cl.exe` command line. | ccache: **bypass** with `unsupported_environment_variable`, because argv alone no longer describes the compile. buildcache instead *hashes their values* (`get_relevant_env_vars`) — cheaper, but it then hashes the strings rather than parsing them, so an `_CL_` carrying `/Zi` would be hashed but not detected as a PDB bypass. Prefer ccache's refusal, or parse-then-classify. |
| `VCToolsVersion`, `VCToolsInstallDir` | Determine the target triple that MSVC and clang-cl bake into a PCH. | ccache hashes both on Windows. |
| `VS_UNICODE_OUTPUT` | When set (cl.exe launched from the VS IDE), cl sends its output **to the IDE process** rather than to stdout/stderr. | **Must be unset around every child run**, or the wrapper captures nothing. Both ccache and buildcache do this; buildcache wraps it in a `scoped_unset_env_t` around `get_program_id`, `preprocess_source` and `run_for_miss`. |

## 9. stdout, stderr and `/nologo`

Unlike gcc, **`cl.exe` writes the source filename to stdout on every compile**:

```
foo.cpp
```

plus the banner unless `/nologo` is given. Consequences:

- stdout is **not** empty on success, so a cache that treats "compiler produced stdout" as
  a bypass will never cache MSVC at all. (ccache's `compiler_produced_stdout` statistic is
  explicitly marked obsolete for this reason.)
- That stdout line **must be captured and replayed**, because build logs and IDEs expect
  it. buildcache's `run_for_miss` captures stdout into the cache entry specifically to
  preserve it.
- Diagnostics go to **stdout too** for `cl.exe` (warnings/errors are on stdout, unlike
  gcc's stderr). The version banner, however, appears on **stderr**: buildcache's
  `get_program_id` runs bare `cl.exe` and reads `result.std_err`, throwing if it is empty.

## 10. Source encoding

ccache adds **`-utf-8`** to the preprocessor run when `msvc_utf8` is enabled, to stop
MSVC garbling non-ASCII filenames in its output. It then inspects the preprocessing stderr
for `warning C4828: The file contains a character starting at offset` and, if present,
returns `unsupported_source_encoding` — i.e. **MSVC caching requires UTF-8 source**. This
is the only compiler where ccache has an encoding verdict.

Related: `from_local_codepage()` appears throughout sccache's msvc.rs — every byte string
coming back from `cl.exe` must be decoded from the *active ANSI code page*, not assumed
UTF-8.

## 11. Response files

MSVC response files differ from gcc's in two ways that matter:

1. **They may be UTF-16** with a BOM. buildcache's `resolve_args` reads the first two
   bytes, and on `FF FE` / `FE FF` re-opens the file as `wifstream` with a
   `codecvt_utf16<wchar_t, 0x10ffff, consume_header>` and converts each line to UTF-8;
   otherwise it assumes UTF-8.
2. **They are not recursive.** sccache's `ExpandIncludeFile` iterator documents this from
   Microsoft's own reference: "It is not possible to specify the @ option from within a
   response file." So a wrapper should expand exactly one level for MSVC and any number of
   levels for gcc. (MSBuild's `@` is a different, MSBuild-level mechanism.)
   sccache classifies `@` as `TooHardPath` in the *flag table* and handles expansion in
   the iterator that feeds the table, which is the right layering.
   Relative response-file paths are legal (sccache has a test), so they resolve against
   the cwd.

## 12. `clang-cl`

`clang-cl` accepts MSVC argv but is clang underneath. The discriminator matters:

- buildcache routes by **name**: its gcc wrapper explicitly returns false when the
  *virtual* path's basename is `clang-cl` ("we can't handle clang-cl style arguments"),
  because `clang-cl` is often a symlink to `clang` and the real path would say `clang`.
  A separate `clang_cl_wrapper.cpp` handles it. **Lesson: dispatch on the name the user
  typed, not on the resolved binary.**
- ccache has `is_compiler_group_msvc()` and `is_compiler_group_clang()` as *independent*
  predicates, and clang-cl satisfies both. Several code paths check
  `is_compiler_group_msvc() && !is_compiler_group_clang()` to mean "real cl.exe only"
  (e.g. the `/Z…` debug check).
- Differences a wrapper must encode: clang-cl has no `/sourceDependencies` (use
  `-showIncludes` and synthesise the `.d`); it accepts `-clang:<arg>` to pass a
  gcc-style flag through; it knows `.incbin` (so ccache's incbin scan applies to
  clang-cl but is skipped for real MSVC); it supports `/showIncludes:user`.

## 13. Worked examples

| argv | Verdict |
|---|---|
| `cl /nologo /c /O2 /Fofoo.obj foo.cpp` | Cacheable. output `foo.obj`, plus the `foo.cpp` stdout line. |
| `cl /nologo /c /Z7 /Fofoo.obj foo.cpp` | Cacheable (embedded debug info). |
| `cl /nologo /c /Zi /Fdvc143.pdb /Fofoo.obj foo.cpp` | **Bypass** — shared PDB. |
| `cl /c /Fo:out\ foo.cpp` | Cacheable; object name derived → `out\foo.obj`. |
| `cl /c /showIncludes /Fofoo.obj foo.cpp` | Cacheable; strip the `Note: including file:` lines before storing stdout, regenerate them (with depth) on a hit. |
| `cl /c /sourceDependencies deps.json /Fofoo.obj foo.cpp` | Cacheable; `deps.json` is a second captured output and the include manifest source. |
| `cl /c /Ycstdafx.h /Fpstdafx.pch /Fostdafx.obj stdafx.cpp` | buildcache: cacheable, `.pch` is a second output. sccache: bypass. |
| `cl /c /Yustdafx.h /Fpstdafx.pch /Fofoo.obj foo.cpp` | Cacheable **only if** `stdafx.pch`'s content is in the key. |
| `cl /c /MP /Fo. a.cpp b.cpp` | Bypass (multiple sources). |
| `cl /c foo.cpp /link /OUT:x.exe` | Bypass (`/link`). |
| `cl @rsp.txt` with UTF-16 `rsp.txt` | Decode BOM, expand **one** level, then classify. |
| `clang-cl /c -showIncludes /Fofoo.obj foo.cpp` | Cacheable; synthesise the `.d` from showIncludes; do not attempt `/sourceDependencies`. |
| any of the above with `CL=/Zi` in the environment | ccache: bypass (`unsupported_environment_variable`). |
