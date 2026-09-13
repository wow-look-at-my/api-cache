# Worker: msvc-probes

MSVC `cl.exe` and `clang-cl` behaviour **measured** on a GitHub `windows-latest`
runner, against the documentation-only claims in
`plan/research/compile-semantics/msvc.md`.

Authoritative run: <https://github.com/wow-look-at-my/api-cache/actions/runs/34731635556>
Runner image `win25-vs2026 / 20260907.229.1`, Windows Server 2025 (10.0.26100).
`cl.exe` 19.51.36256 x64 (MSVC toolset 14.51.36231, VS 18 Enterprise);
`clang-cl` 20.1.8; Windows SDK 10.0.26100.0; `VSLANG` unset, culture `en-US`,
ANSI code page 1252.

Every probe captured stdout, stderr and the exit code **separately and
verbatim** to its own file. `results/*.md` quote those captures; the raw
per-probe files are in the run's `msvc-probes-results` artifact.

## Index

| file | what it measures |
|---|---|
| `results/environment.md` | the runner, toolset and code pages every other file is read against |
| `results/p01-identity.md` | bare `cl`, `/Bv`, `/nologo`, the source-name line, which stream the banner uses |
| `results/p02-showincludes.md` | `/showIncludes` prefix, depth, stream, `/external:*`; `/sourceDependencies` JSON shape |
| `results/p03-localization.md` | installed message locales, `VSLANG`, sccache's runtime prefix detection executed for real |
| `results/p04-output-naming.md` | every `/Fo` spelling, the sibling `/F*` outputs, `/MP`, `/Tc`, `/Zs` |
| `results/p05-debug-info.md` | `/Z7` vs `/Zi` vs `/ZI`, the shared PDB, `/Fd` naming, last-`/Z`-wins |
| `results/p06-pch.md` | `/Yc`, `/Yu`, `/Fp`, the missing and the stale `.pch` |
| `results/p07-response-files.md` | `@file` quoting, nesting, UTF-16/UTF-8 BOMs; `CL` and `_CL_` |
| `results/p08-environment.md` | `INCLUDE`, `EXTERNAL_INCLUDE`, `/external:env:`, `LIB`, `TMP`, `VS_UNICODE_OUTPUT` |
| `results/p09-diagnostics.md` | warning/error format, which stream, `/FC`, `/WX`, `/diagnostics:*`, colour |
| `results/p10-clang-cl.md` | clang-cl: `/showIncludes`, `/Fo`, `/Zi`, `/sourceDependencies`, colour |
| `results/p11-determinism.md` | object reproducibility, `/Brepro`, `/d1trimfile:`, `__DATE__`/`__TIME__` |
| `corrections.md` | the exact edits `msvc.md` needs, wrong sentence quoted beside the right one |
| `STATUS.md` | what each CI run did, including the two harness bugs and their fixes |

## Summary

1. The **version banner is on stderr**; the **source-filename line is on stdout**
   and `/nologo` does not suppress it. Both confirm `msvc.md` §9.
2. That stdout line is always the **basename**, even when argv names the source
   by absolute path. Replayed stdout therefore leaks no paths.
3. **Compile** diagnostics are on stdout. **Command-line** diagnostics
   (`D8021`, `D8036`, `D9002`, `D9024`, `D9027`) are on **stderr**. `msvc.md`
   does not draw that line.
4. `/showIncludes` notes are on **stdout** for a normal compile but move to
   **stderr** under `/E`. That is why sccache's stderr-only detection works.
5. The prefix is `Note: including file: ` (22 bytes, trailing space included).
   Depth is one further space per level. Duplicate includes are reported twice,
   and the path keeps whatever separator the `#include` used.
6. Only locale `1033` ships on this runner, so `VSLANG` changes nothing here and
   the localized-prefix hazard could **not** be reproduced. sccache's detection
   algorithm, executed for real, returns the right prefix.
7. `/Fo` with an **existing directory and no trailing backslash** writes a FILE
   (`out.obj`), not `out\foo.obj`. `msvc.md` §2 says otherwise.
8. `/Fo <name>` separated is **silently ignored**: exit 0, object at the default
   name. `/Fo` twice: last wins. A missing `/Fo` directory is a hard `C1083`.
9. The default PDB is **`vc140.pdb`**, not `vc143.pdb`. It is a genuine
   accumulator: an unrelated second `/Zi` compile changes its bytes.
10. Last `/Z` wins, measured both ways: `/Zi /Z7` writes no PDB, `/Z7 /Zi` does.
11. A **stale `.pch` is not detected**. Editing the header after building the
    `.pch` still compiles clean at exit 0, with the old contents. Hashing the
    `.pch` content is therefore mandatory, not merely safer.
12. **Nested `@` response files DO expand.** Microsoft's "not possible" line,
    which `msvc.md` §11 repeats, is wrong for this toolset.
13. Response files accept UTF-16**LE** and UTF-8 BOMs; UTF-16**BE** fails with
    `D8022`. A missing `@file` is an error, not a verbatim argument.
14. `CL` is prepended and loses to argv; `_CL_` is appended and beats argv.
    `CL` can itself name a response file. `CL=/Zi` really does produce a PDB.
15. `VS_UNICODE_OUTPUT` silences cl completely — no diagnostics, not even the
    source-name line. **Setting it to the empty string does not unset it**: cl
    tests presence, so a wrapper must delete it.
16. No cl object is byte-reproducible — not with `/Z7`, not with `/Zi`, not with
    no debug flag at all, and **`/Brepro` does not fix it**. Objects also embed
    their own absolute directory, and `/d1trimfile:` did not strip it.
17. clang-cl prints no banner and no source-name line, puts its diagnostics on
    **stderr**, and emits `/showIncludes` paths **relative** where cl emits
    absolute.
18. clang-cl's `/Zi` produces **no PDB** and the same object as `/Z7`, so a
    blanket `/Zi` bypass costs clang-cl every hit for nothing.
19. clang-cl **silently ignores** `/sourceDependencies` at exit 0, but
    `/clang:-MD /clang:-MF /clang:<f>` writes a real `.d` — so a wrapper need
    not synthesise one.
20. Neither compiler emits ANSI colour to a redirected stream or through a pipe;
    clang-cl does only when `-fcolor-diagnostics -fansi-escape-codes` are both
    given. Cached stdout can be stored verbatim.

## Contradictions with `msvc.md`

Each is written out, with the wrong sentence quoted, in `corrections.md`.

| `msvc.md` | claim | measured |
|---|---|---|
| `msvc.md:36-38`, `:314` | `/Fo` naming an **existing directory** derives the object name from the source basename | only a trailing `\` does; `/Foout` with `out\` present writes the file `out.obj` — `results/p04-output-naming.md` |
| `msvc.md:235-238`, `:303-304` | response files "are not recursive"; `@` cannot appear inside one | `@inner.rsp` inside a response file **is** expanded — `results/p07-response-files.md` |
| `msvc.md:231-234` | UTF-16 response files, `FF FE` / `FE FF` | only `FF FE` (LE) works; BE fails `D8022` — `results/p07-response-files.md` |
| `msvc.md:268` | worked example `/Fdvc143.pdb` | the default is `vc140.pdb` — `results/p05-debug-info.md` |
| `msvc.md:79-80` | `/showIncludes` writes to stdout, "not stderr" | true for a compile, **false under `/E`**, where the notes are on stderr — `results/p02-showincludes.md` |
| `msvc.md:211-213` | "Diagnostics go to stdout too for `cl.exe`" | compile diagnostics yes; command-line diagnostics are on stderr — `results/p09-diagnostics.md` |
| `msvc.md:350` | unknown `/x` → `hash-verbatim` | `/ZzNotAnOption` is `D8021`, a hard error at exit 2 — `results/p09-diagnostics.md` |
| `msvc.md:68-69` | the PDB path "does not change the object under `/Z7`" | the two objects differ, but the probe varied `/Fo` as well, so this is **not established either way** — `results/p05-debug-info.md` |
| `msvc.md:144-157` (§6) | implies cl detects a stale `.pch` (`C1859`/`C4652`) | no detection at all: exit 0, old contents used — `results/p06-pch.md` |
| `msvc.md:257-258`, `:132-137` | clang-cl needs a synthesised `.d` | `/clang:-MD /clang:-MF` writes a real one — `results/p10-clang-cl.md` |
| `msvc.md:319` | `/Zi` `/ZI` → bypass (stated for the MSVC family) | correct for cl; for clang-cl `/Zi` writes no PDB, so the bypass must be gated to real cl — `results/p10-clang-cl.md` |
| `msvc.md:193`, `:359` | `VS_UNICODE_OUTPUT` "must be unset" | and *unset* must mean **deleted**: an empty value still silences cl — `results/p08-environment.md` |
| `msvc.md` §14 (absent) | `/Brepro` is not in the table | it is also not sufficient: objects stay irreproducible with it — `results/p11-determinism.md` |

## Not established on this runner

- **The localized `/showIncludes` prefix.** Only the `1033` (English) message
  DLL is installed, so `VSLANG=1041/1031/1036/2052` all still print
  `Note: including file: `. The hazard is real but a language pack is needed to
  reproduce it; sccache's runtime detection was verified to work, which is the
  part the engine depends on.
- **Whether `/Fd` alone changes a `/Z7` object.** The probe varied `/Fo` at the
  same time. A follow-up holding `/Fo` constant is needed before `msvc.md`'s
  "never hashed" line can be confirmed or refuted.
