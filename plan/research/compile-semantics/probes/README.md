# Probes: compile-semantics

Run everything with `./run-all.sh`. It exits non-zero if **any** step failed, and prints
which probe file to look at.

## No silent failure

Every step goes through `probe-lib.sh`:

- `step "<what>" <cmd…>` runs the command and records `PASS (exit 0)` or
  `**FAIL** (exit N)  <-- RECORDED, NOT IGNORED`.
- `xstep "<what>" nonzero <cmd…>` is for a step whose **non-zero exit is itself the
  finding** (`gcc -c foo.c -o -`, a rustc compile that must fail). Stating the expectation
  means a behaviour change still shows up as a FAIL rather than passing quietly.
- Each run ends with `PROBE SUMMARY: N steps, M FAILURES` and the script exits non-zero
  when `M > 0`.
- **There is no `|| true` anywhere.** A missing tool is a FAIL (`command -v readelf`,
  `command -v cargo` are explicit steps), not a skipped section.

This caught a real defect while the probes were being written: three steps in
`run-04-flags.sh` piped gcc through `head`, so the recorded exit status was `head`'s (0)
rather than gcc's. The harness reported three FAILures; the steps were rewritten to
capture the compiler's own status. Had the harness ignored exit codes, those three
findings would have been recorded from output that happened to look right.

## Committed path names

No committed path contains `\ : * ? " < > |` — Windows git refuses them, and two earlier
files here broke other workers' `windows-latest` checkout. The dependency-escaping probe
needs files literally named `sp ace.h`, `dol$lar.h`, `hash#mark.h`, `back\slash.h` and
`colon:c.h`, so **`run-01-depfiles.sh` creates them at run time inside a `mktemp -d`
directory** and the trap removes them. Nothing weird is ever committed.

## Environment these results came from

| Tool | Version |
|---|---|
| gcc | 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) |
| clang | 18.1.3 (Ubuntu 1ubuntu1), target x86_64-pc-linux-gnu |
| rustc | 1.94.1 (e408947bf 2026-03-25), LLVM 21.1.8, host x86_64-unknown-linux-gnu |
| cargo | ships with the above toolchain |
| go | 1.24.7 linux/amd64 (read only — the GOCACHEPROG protocol was read from `/usr/local/go/src`, not probed) |
| kernel | Linux 6.18.44, x86_64, 4 CPUs, `-march=native` resolves to `cascadelake` |

## What was NOT probed, and why

Stated explicitly so nothing in the findings reads as measured when it is not:

- **MSVC / `cl.exe` / `clang-cl`.** No Windows machine. Everything in `msvc.md` is cited to
  ccache, sccache or buildcache source, and is labelled as such at the top of that file.
- **Distributed / remote storage paths.** Out of scope for this worker.
- **Go's GOCACHEPROG end to end.** The protocol in `go-and-others.md` is read from the Go
  1.24.7 source on this machine (`cmd/go/internal/cacheprog/cacheprog.go`), not exercised.
- **nvcc / CUDA.** No CUDA toolkit. `go-and-others.md` §2 is read from sccache's source.

## The probes

| Script | Output | What it establishes |
|---|---|---|
| `run-01-depfiles.sh` | `out/01-depfiles.txt` | Where `-MD` puts the `.d` (derived from `-o`, else the source basename in the cwd); `-MP` phony targets; `-MT` vs `-MQ`; `-M`/`-MM` on stdout; `-Wp,-MD,f`; `-E -MD` writes nothing; the full **escaping table** for space/`$`/`#`/`\`/`:` in gcc and clang; and the **gcc `#pragma once` content-dedup hazard** — two distinct byte-identical headers, only the first of which appears in the dep list. |
| `run-02-preproc.sh` | `out/02-preproc.txt` | The linemarker preamble and how the source path is embedded **as written**; `-P` removing every marker; clang's differently-shaped preamble; `__DATE__`/`__TIME__`/`__FILE__`/`__TIMESTAMP__` expansion; run-to-run stability of `-E`; that the `#pragma GCC pch_preprocess` marker **survives `-P`**. |
| `run-03-debug.sh` | `out/03-debug-and-paths.txt` | `DW_AT_name`/`DW_AT_comp_dir` for four invocation shapes; what `-fdebug-prefix-map`, `-ffile-prefix-map` and clang's `-fdebug-compilation-dir` change; that ordinary `-O2 -g` compiles **are** byte-reproducible; that the `-o` name does **not** leak into the object; that `-flto` objects are **not** reproducible and `-frandom-seed=0` does not fix it on gcc 13; `__FILE__` taking the path as written. |
| `run-04-flags.sh` | `out/04-flags.txt` | `-march=native` expanded through `-### -E -` for both compilers; diagnostics with and without colour; `-gsplit-dwarf` → `.dwo`; `--coverage` → `.gcno`; `-fsyntax-only` writing nothing; `gcc -c -o -` failing outright; nested and quoted `@response` files; a `.gch` PCH being picked up; stdin-as-source and its degenerate dep file. |
| `run-05-rustc.sh` | `out/05-rustc.txt` | `rustc -vV` and `--print=sysroot`; the `--emit=dep-info` file format including `# env-dep:` records; **unset vs set** env-dep spelling; `--print file-names` and the fact that it omits the `.rmeta`; what `-C incremental` writes; space escaping in dep-info. |
| `run-06-rustc-wrapper.sh` | `out/06-rustc-wrapper.txt` | That cargo composes `RUSTC_WRAPPER` and `RUSTC_WORKSPACE_WRAPPER` as `$WRAPPER $WORKSPACE_WRAPPER $rustc <args>`; that cargo's own `-vV` and `--print=file-names` probes go through the wrapper; the full argv of a real `cargo build` compile, showing `-C incremental` present by default. |

## Reference sources

Read, not vendored: ccache (GPL-3.0 — **behaviour only**, no code reuse), sccache
(Apache-2.0), buildcache (zlib). Clones live outside this repo at
`/home/user/refs/{ccache,sccache,buildcache}`. If the plan needs them pinned, they should
be added as git submodules under `refs/` by whoever owns that; this worker only read them.
