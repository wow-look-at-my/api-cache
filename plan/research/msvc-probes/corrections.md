# Corrections for `plan/research/compile-semantics/msvc.md`

Every entry quotes the sentence as it stands, gives the measured replacement,
and cites the capture. Measurements are from
<https://github.com/wow-look-at-my/api-cache/actions/runs/34731635556>
(`win25-vs2026 / 20260907.229.1`, cl 19.51.36256, MSVC 14.51.36231, clang-cl 20.1.8).

**This file does not edit `msvc.md`.** Its author applies these.

The header at `msvc.md:6-7` should stop saying nothing is probe-verified:

> No Windows machine was available, so nothing here is probe-verified; every
> statement is cited to code I read.

becomes

> Written from code and documentation, then checked against a real `cl.exe` on a
> GitHub `windows-latest` runner. Statements marked *(measured)* carry a probe in
> `plan/research/msvc-probes/`; the rest are still code-citation only.

---

## 1. `/Fo` naming an existing directory — `msvc.md:36-38` and `:314`

> Output: `/Fo<path>`. If `/Fo` names a **directory** (trailing `\` or an existing
> directory), the object name is derived from the source basename

and the table cell at `:314`:

> A trailing `\` or an existing directory → derive the name from the source basename.

**Wrong about the existing-directory half.** Only a trailing backslash makes cl
treat the value as a directory. With a directory `out\` present in the cwd,
`cl /nologo /c /Foout foo.c` wrote the **file** `out.obj`, exit 0.

Replace with:

> Output: `/Fo<path>`. A value ending in `\` is a directory and the object name
> is derived from the source basename. A value **without** a trailing backslash
> is always a file name, even when a directory of that name exists *(measured)*.
> A directory that does not exist is not created: `/Fomissing\` fails with
> `fatal error C1083: Cannot open compiler generated file`, exit 1 *(measured)*.

Add, because a cache that accepts the separated spelling writes the wrong file:

> `/Fo` does **not** take a separated value. `cl /c /Fo name.obj foo.c` exits 0
> and writes `foo.obj`; `name.obj` is neither the output nor an input, and there
> is no diagnostic *(measured)*. Repeated `/Fo` — last one wins. `/Foname` with
> no extension gains `.obj`; `/Foname.o` keeps `.o` *(measured)*.

Source: `results/p04-output-naming.md`.

## 2. Nested response files — `msvc.md:235-238` and `:303-304`

> **They are not recursive.** sccache's `ExpandIncludeFile` iterator documents this
> from Microsoft's own reference: "It is not possible to specify the @ option from
> within a response file." So a wrapper should expand exactly one level for MSVC

and `:303-304`:

> `@file` response files: **one level only** (Microsoft: "It is not possible to
> specify the @ option from within a response file")

**Wrong on this toolset.** A response file containing `@inner.rsp` had the inner
file expanded: the define it carried reached the compile
(`#pragma message` printed `SEEN FROMINNER=1`), exit 0.

Replace with:

> Microsoft's reference says "It is not possible to specify the @ option from
> within a response file", and sccache's `ExpandIncludeFile` implements exactly
> one level on that basis. **cl.exe 19.51 does expand a nested `@`** *(measured)*.
> A wrapper that stops at one level therefore hashes a command line that is not
> the one the compiler saw, which is a correctness bug, not a conservatism.
> Expand until fixpoint, with a depth cap against a cycle.

Source: `results/p07-response-files.md`, probe `rsp-nested-at`.

## 3. Response-file byte order — `msvc.md:231-234`

> **They may be UTF-16** with a BOM. buildcache's `resolve_args` reads the first
> two bytes, and on `FF FE` / `FE FF` re-opens the file as `wifstream`

Add the measured limit:

> cl.exe itself accepts UTF-16**LE** (`FF FE`) and UTF-8-with-BOM. A UTF-16**BE**
> (`FE FF`) response file is rejected outright with
> `cl : Command line error D8022 : cannot open 'args.rsp'` *(measured)*, so
> buildcache's `FE FF` branch accepts a file cl would refuse. A wrapper should
> refuse it too rather than expand something the compiler cannot read.
> An unopenable `@file` is `D8022` at exit 2 — unlike gcc, it is **not** left as
> a verbatim argument *(measured)*.

Source: `results/p07-response-files.md`.

## 4. The default PDB name — `msvc.md:268`

> | `cl /nologo /c /Zi /Fdvc143.pdb /Fofoo.obj foo.cpp` | **Bypass** — shared PDB. |

The default PDB on MSVC 14.51 is **`vc140.pdb`**, not `vc143.pdb`. Use
`/Fdvc140.pdb`, or better, drop the number:

> | `cl /nologo /c /Zi /Fofoo.obj foo.cpp` | **Bypass** — shared PDB (`vc140.pdb` by default on 14.51 *(measured)*; the digits track the toolset, so never hard-code them). |

Also worth stating in §3, because it is the bypass's whole justification:

> Measured: a second, unrelated `/Zi` compile into the same directory changes the
> PDB's bytes, so it is an accumulator in fact and not only in principle
> *(measured)*. `/Fd<name>` with no extension gains `.pdb`; `/Fd<dir>\` writes
> `<dir>\vc140.pdb`; `/Fd:` is accepted; under `/Z7` no PDB is written at all
> *(measured)*. ccache's last-seen-`/Z`-wins rule is correct: `/Zi /Z7` writes no
> PDB and `/Z7 /Zi` does *(measured)*.

Source: `results/p05-debug-info.md`.

## 5. `/showIncludes` and the stream — `msvc.md:79-80`

> `cl.exe /showIncludes` writes one line **per included file to stdout** (not stderr —
> this differs from gcc's `-H`)

True for a compile, but not universally, and the exception is the one sccache
depends on. Replace with:

> `cl.exe /showIncludes` writes one line per included file to **stdout** during a
> compile (unlike gcc's `-H`, which uses stderr). Under **`/E`** the preprocessed
> text takes stdout and the notes — and the source-name line — move to **stderr**
> *(measured)*. That is why sccache's `detect_showincludes_prefix`, which runs
> `-showIncludes -c -E` and reads **stderr only**, finds anything at all; a
> wrapper must read the stream that matches the mode it invoked.

Add the measured format, since the engine owns the parser:

> The prefix is exactly `Note: including file: ` — 22 bytes, trailing space
> included. Nesting is **one additional space per level** after that prefix. The
> path is absolute, but keeps whichever separator the `#include` used, so
> `#include "inc/lvl1.h"` reports `C:\p\p02\inc/lvl1.h` with a forward slash
> mid-path. A file included twice is reported **twice** — there is no dedup
> *(measured)*.

Source: `results/p02-showincludes.md`, `results/p03-localization.md`.

## 6. Where diagnostics go — `msvc.md:211-213`

> Diagnostics go to **stdout too** for `cl.exe` (warnings/errors are on stdout,
> unlike gcc's stderr). The version banner, however, appears on **stderr**

Correct as far as it goes; it misses a second split that decides what a wrapper
captures. Replace with:

> `cl.exe` splits its output three ways *(measured)*: the **version banner** on
> stderr; the **source-name line and every compile diagnostic** (`warning C…`,
> `error C…`) on stdout; and every **command-line** diagnostic on stderr —
> `D8021` invalid argument, `D8022` unopenable response file, `D8036` `/Fo` with
> multiple sources, `D9002` unknown option, `D9024`/`D9027` unusable source.
> A wrapper that stores only stdout loses the reason a bad command line failed.

Add the format detail:

> The location in a diagnostic is the **argv spelling** (`sub\deep.c(3): error …`)
> while the source-name line on stdout is always the **basename** (`deep.c`) —
> the same run prints both spellings. `/FC` makes the diagnostic absolute. A
> diagnostic raised inside a header already names that header by **absolute**
> path, with or without `/FC` *(measured)*, so replayed stdout can leak a path
> even when the user never asked for `/FC`.
> `/diagnostics:column` and `:caret` add `(line,col)`, and `:caret` adds the
> source line and a caret — so the cached stdout is a function of that flag.

Source: `results/p09-diagnostics.md`.

## 7. Unknown options — `msvc.md:350`

> | unknown `/x` or `-x` | — | `hash-verbatim` | Same separate-argument hazard as gcc. |

An unknown option is not reliably inert. `/ZzNotAnOption` produced
`cl : Command line error D8021 : invalid numeric argument '/Zption'` and **exit
2** — the compile did not happen. Replace the note with:

> `hash-verbatim`, but an unknown option is not always a passthrough: cl may
> parse a prefix of it and fail hard (`/ZzNotAnOption` → `D8021`, exit 2), while
> a genuinely unrecognised one is only `D9002` on stderr and the compile proceeds
> *(measured)*. Hashing it verbatim is right either way; assuming the compile
> still runs is not.

Source: `results/p09-diagnostics.md`.

## 8. The stale PCH — `msvc.md:144-157` (§6)

§6 describes `/Yu` and cites `LNK4206` for mixing objects built against
different PCHs, but leaves the impression that cl notices a `.pch` that no
longer matches its header. It does not. Add:

> **cl does not detect a stale `.pch`** *(measured)*. A `.pch` was built from
> `pch.h`, `pch.h` was then edited, and `cl /Yupch.h /Fppch.pch` compiled a user
> of it at **exit 0**, silently using the old contents. Only a *missing* `.pch`
> is caught, as `fatal error C1083: Cannot open precompiled header file`, exit 2.
> So the `.pch` content is not merely "safer in the key" (as §6 concludes from
> buildcache): without it the cache and the compiler are wrong in the same
> direction, and neither reports it. Measured too: two objects compiled from
> identical source and identical argv, differing only in which `.pch` `/Fp`
> named, have different bytes — the PCH identity really is baked into the object.

Source: `results/p06-pch.md`.

## 9. clang-cl and dependency output — `msvc.md:257-258` and `:132-137`

> clang-cl has no `/sourceDependencies` (use `-showIncludes` and synthesise the `.d`)

and §5's account of sccache synthesising a `.d` by hand, "skipping any dependency
whose path contains a space".

Correct that clang-cl lacks `/sourceDependencies`, but the conclusion does not
follow. Add:

> clang-cl does not implement `/sourceDependencies`, and — worse than an error —
> **ignores it silently**: `clang-cl /sourceDependencies deps.json …` exits 0 with
> only `warning: argument unused during compilation`, and writes no JSON
> *(measured)*. A wrapper that passes it and then reads the file gets a missing
> file, not a diagnostic.
> Synthesising the `.d` by hand is nevertheless avoidable: clang-cl forwards
> gcc-style flags, and `/clang:-MD /clang:-MF /clang:<file>` writes a real
> GNU-make dependency file *(measured)*. That path has a proper escaper, so it
> does not inherit sccache's "skip any dependency containing a space" limitation.

Also add, for the parser:

> clang-cl's `/showIncludes` uses the identical `Note: including file: ` prefix
> and the same one-space-per-level nesting, but reports paths **relative** to the
> working directory (`.\inc/lvl1.h`) where cl reports absolute ones *(measured)*.
> `/showIncludes:user` works and drops the system headers. Unlike cl, clang-cl
> prints **no banner and no source-name line**, and puts its diagnostics on
> **stderr**, in the form `err.c(1,27): error: …` with a caret.

Source: `results/p10-clang-cl.md`.

## 10. `/Zi` for clang-cl — `msvc.md:319` and §12

> | `/Zi` `/ZI` | `flag` | `bypass:unsupported_compiler_option` | Shared PDB; an accumulator …

Right for `cl.exe`, wrong if applied to the whole family. Add to the note:

> This is a **real cl.exe** rule. Under clang-cl, `/Zi` writes **no `.pdb` at all**
> and produces the same object as `/Z7`; `/ZI` is reported as unused
> *(measured)*. ccache's `is_compiler_group_msvc() && !is_compiler_group_clang()`
> gate is therefore load-bearing: a blanket `/Zi` bypass costs every clang-cl
> user every hit and buys nothing.

Source: `results/p10-clang-cl.md`.

## 11. `VS_UNICODE_OUTPUT` — `msvc.md:193` and `:359`

> **Must be unset around every child run**, or the wrapper captures nothing.

Confirmed exactly — and the word *unset* needs teeth. Add:

> Measured: under `VS_UNICODE_OUTPUT` cl produces **zero bytes on both streams** —
> no diagnostics and not even the source-name line — while still returning a
> truthful exit code, so a cache would store a failure with no message.
> `unset` must mean **removed from the child's environment**. cl tests the
> variable's **presence, not its value**, so setting it to `""` does not disable
> it. This is not hypothetical: this worker's own harness set it to the empty
> string while "restoring" it and silenced two whole probe families before the
> cause was found (`STATUS.md`, run 3 and run 4).

Source: `results/p08-environment.md`, `STATUS.md`.

## 12. Determinism and `/Brepro` — new material for §3 or a new section

`msvc.md` never states whether an MSVC object is reproducible, and §14 does not
list `/Brepro` at all, though sccache carries `msvc_flag!("Brepro", PassThrough)`.
The plan's whole replay model rests on this, so add:

> **An MSVC object is not byte-reproducible.** The same source compiled twice in
> the same directory, seconds apart, differs — with `/Z7`, with `/Zi`, and with
> no debug flag at all. The first differing byte is at offset 4, the COFF
> header's `TimeDateStamp`. **`/Brepro` does not fix it** *(measured)*: objects
> built with it still differ at offset 4.
> Worse for a shared cache, an object **embeds its own absolute directory** as a
> literal string even with no debug flag, so the same source in two different
> directories yields different bytes. `/d1trimfile:<dir>\` did **not** remove
> that prefix in the measured invocation.
> Consequence: a cache must treat the stored object as authoritative output to be
> replayed, never as something re-derivable or verifiable by recompiling — and a
> cross-machine cache must key on, or normalise, the build directory.
> `__DATE__`/`__TIME__` do move between runs as expected, and `/Brepro` does not
> freeze them, so the temporal-macro hazard stands on its own.

Add `/Brepro` to the §14 table as `hash-verbatim` with the note "does **not**
make the object reproducible *(measured)*".

Source: `results/p11-determinism.md`.

## 13. Smaller corrections and additions

- `msvc.md:24-26` — `--` before the source is accepted: confirmed, exit 0
  *(measured)*. `results/p04-output-naming.md`.
- `msvc.md:311` — `/Tc<f>`/`/Tp<f>` are listed as `concat` only. The **separated**
  spelling `/Tc plain.txt` is also accepted and compiles the file *(measured)*.
- `msvc.md:336` — `/Zs` writes no output file: confirmed, exit 0 *(measured)*.
- `msvc.md:317` — `/Fe` and `/Fm` are listed with the bypass group. Under `/c`
  both are **silently ignored** (no file, no diagnostic, exit 0), while `/Fa`,
  `/FA<x>` and `/FR` really do write a sibling (`foo.asm`, `foo.cod`, `foo.sbr`)
  *(measured)*. The bypass is right for the latter three; for `/Fe`/`/Fm` under
  `/c` it is merely harmless.
- `msvc.md:274` — `cl /c /MP /Fo. a.cpp b.cpp` is a multiple-source bypass:
  confirmed useful, and measured, `/Fo<file>` with two sources is
  `D8036` on **stderr** at exit 2, with no object written. With `/Fo<dir>\` the
  three objects are written and the three stdout name lines came out in argv
  order *(measured)*.
- `msvc.md:188-191` — `INCLUDE` must be in the key: confirmed by construction.
  Two runs with byte-identical argv and only `INCLUDE` differing produced
  different objects *(measured)*. `/I` beats `INCLUDE`. `EXTERNAL_INCLUDE`
  resolves headers on its own, and **`/external:env:<var>` lets argv name a
  *third* environment variable that feeds the include search** — so a fixed
  allowlist of include-bearing variables is not sufficient; the rule engine must
  read that variable name out of argv *(measured)*.
- `msvc.md:191` — `CL` prepended / `_CL_` appended: confirmed, including the
  precedence (`_CL_` beats argv, argv beats `CL`) and that `CL=/Zi` really does
  produce a PDB the argv never asked for. Add that **`CL` may itself contain
  `@file`**, which is a third response-file expansion site *(measured)*.
- `msvc.md:9-13` — bare `cl.exe` with no arguments exits **0**, printing usage on
  stdout and the banner on stderr; `cl /nologo` with no input exits **2**
  *(measured)*. buildcache's `get_program_id`, which runs bare `cl` and reads
  stderr, therefore gets the banner it expects.
