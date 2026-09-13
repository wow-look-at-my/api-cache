# Worker: compile-semantics

What a correct compiler-cache wrapper must do, per tool, in operational detail — so the
planner can decide what is an engine primitive and what a per-tool rule expresses.

## Summary (25 lines)

A wrapper's job splits into five stages, and every hard problem lives in one of them.
**Classify**: expand response files, parse argv with a per-family syntax, and reach a
verdict — cacheable, or decline with a code from a *closed* vocabulary (ccache's ~30 named
reasons; the full list is in `key-derivation-model.md` §4). **Key**: hash the tool's
identity, the name it was invoked under, a filtered argv, an env *allowlist*, and — only
when debug info is generated — the cwd. **Discover inputs**: C has no declared input set,
so it must be learned, either by running the preprocessor (correct, slow) or by trusting a
dep file (fast, incomplete). That gap is why a direct-mode manifest holds *multiple*
candidate include-sets rather than one. **Capture**: the object, every derived sibling
(`.d`, `.dwo`, `.gcno`, `.su`), stdout, stderr **verbatim**, and the exit code. **Restore**:
temp-plus-rename, replay the streams, exit with the stored code. Two findings cut across
all of it. First, the cwd leaks into the object through `DW_AT_comp_dir` whenever `-g` is
on (measured), so a cache that ignores it silently hands a developer another machine's
source paths; the real fix is `-ffile-prefix-map` in the build, not a knob in the cache.
Second, **gcc implements `#pragma once` by comparing file content**, so two distinct
byte-identical headers produce a dep list naming only the first (measured; clang does not
do this) — every dep-derived include manifest, ccache's included, can therefore serve a
false hit. Per tool: gcc/clang need the largest flag table and the preprocessor machinery;
MSVC needs a runtime-detected localized `/showIncludes` prefix, a `/Zi`→`/Z7` bypass for
the shared PDB, and `.pch` content in the key; rustc needs none of that but does need
`--emit=dep-info` first-pass, `-C incremental` declined, and the `# env-dep:` records that
tell you exactly which environment variables the compile read. Go needs no wrapper at all —
`GOCACHEPROG` hands the whole cache to an external process over JSON lines. buildcache is
the closest prior art and its hook contract is transcribed in full, along with twelve
places it is too coarse (including a live bug: its gcc wrapper hashes **no** environment
variables, so `CPATH` and `LANG` are absent from the key). The generic end of the space is
Bazel's Action — command + env + input Merkle tree + declared outputs — which is what a
"generic mode" would approximate for protoc, clang-tidy and codegen.

## Files

| File | What is in it |
|---|---|
| `c-cxx-gcc-clang.md` | The full decision procedure. Which argv shapes are cacheable (`-S` **is**, `-fsyntax-only` **is**, `-E`/`-M`/`-MM` are not); preprocessor mode and the linemarker problem; direct mode, the manifest, and why it holds multiple candidates; depend mode; temporal macros and sloppiness; compiler identity; diagnostics; the exact `-MD` format with a measured escaping table; and **§10, the flag-family table** (pattern, value form, role, notes). |
| `msvc.md` | `cl.exe` and `clang-cl`: the `/Zi` vs `/Z7` PDB problem, the runtime detection of the localized `/showIncludes` prefix, `/sourceDependencies` JSON, `/Yc`/`/Yu` and why the `.pch` content must be in the key, `/FI`'s resolve-against-the-source-directory rule, `CL`/`_CL_`/`VS_UNICODE_OUTPUT`, MSVC writing the source name to **stdout**, UTF-16 response files — and **§14, the flag-family table**. Cited, not probed: no Windows machine. |
| `rustc.md` | The crate-not-TU model; the measured `RUSTC_WRAPPER`/`RUSTC_WORKSPACE_WRAPPER` composition; what makes an invocation cacheable and why plain `cargo build` is not; the output set via `--print file-names`; the full key composition from sccache; the `--emit=dep-info` format including `# env-dep:`; compiler identity via `-vV` plus the sysroot shared libraries — and **§7, the flag-family table**. |
| `go-and-others.md` | The `GOCACHEPROG` protocol in full (JSON lines, the `ID==0` handshake, `get`/`put`/`close`, the body on a separate base64 line, `DiskPath`, `ActionID`/`OutputID`) and how it relates to go-s3-server's `cacheclient`; nvcc via `--dryrun` decomposition; why Swift and javac are not wrapped; protoc and clang-tidy as the generic cases; why link caching is skipped by wrappers but free for Bazel; the Bazel REAPI Action model; and a dep-file-versus-Merkle-tree comparison. |
| `invocation-modes.md` | Masquerade, prefix, impersonation, protocol. Finding the real tool without finding yourself (three guards, all needed, including the env-var recursion guard). Build-system wiring. Exit codes, signals (forward TERM, unlink temps signal-safely, `waitpid`, re-raise), stdin. Temp files, atomic rename, the concurrency argument, the hard-link hazard, umask. |
| `key-derivation-model.md` | **buildcache's hook contract transcribed function by function**, its driver flow, and twelve places it is too coarse or wrong. Then the primitive inventory in seven groups, a text data-flow diagram, the closed reason vocabulary with five proposed additions, and the engine-vs-config table below. |
| `hashing-and-normalization.md` | Which hash each project actually uses (**correcting the brief: ccache uses BLAKE3/20 bytes, not XXH3 — buildcache is the XXH3 one**), framing and format versioning, what must be normalized, `base_dir` and `hash_dir` with a trade-off table, the full sloppiness list, and the correctness hazards: the "too new" race, hard-linked outputs, the `#pragma once` dedup, partial restores, empty outputs, and the non-determinism that is *not* a problem. |
| `probes/` | Every measurement, re-runnable. `./probes/run-all.sh` exits non-zero if any step fails. See `probes/README.md` for the no-silent-failure harness, the environment, and **what was not probed**. |

## Engine primitive vs. expressible in config — my best guess

**Not a decision.** The planner owns the surface. The one firm input from the user is that
buildcache's hook surface, where each rule hand-parses argv, is too hard to reason about;
that defect is diagnosed concretely in `key-derivation-model.md` §1. The fuller table with
alternatives noted is `key-derivation-model.md` §5.

| Concern | Guess | One-line reason |
|---|---|---|
| Response-file expansion (`@file`) | **engine** | Three dialects, zero per-project variation; MSVC is one-level and BOM-aware, GNU is recursive. |
| Argument syntax (`-ox` / `-o x` / `--opt=x` / `/Fo:x`) | **engine**, per named dialect | This is exactly where buildcache's five disagreeing loops come from; one of them misreads `-isystem dir` as a source file. |
| Which flag means what | **config** | Large, flat, tool-specific, changes every compiler release. This is the content of the three flag tables. |
| Flag forwarding (`-Wp,`, `-Xclang`, `-Xcompiler`) | **engine** | It is a re-dispatch through the same table; config only marks which flags forward. |
| Verdict *reasons* | **engine** (closed set) | A free-form string cannot be counted, logged consistently, or acted on by a user. |
| Verdict *conditions* | **config** | "two sources means link, unless `-c`" is tool knowledge and does not generalise to rustc. |
| `.d` parse / escape / target-rewrite / relativise | **engine** | Every hand-rolled version I read is subtly wrong; buildcache's does not escape spaces, sccache's clang-cl path drops any path containing one. |
| `/showIncludes` parse + localized-prefix detection | **engine** | The runtime probe is 40 lines of careful logic nobody should write twice. |
| Derived sibling outputs (`.dwo`, `.gcno`, `.su`, `.rmeta`) | **engine** mechanism, **config** states which | The derivation is "swap the extension"; which extension under which flag is tool knowledge. |
| Include set → manifest (multi-candidate, interning, validation order, bounds) | **engine** | Pure mechanism, and the part buildcache lacks entirely. |
| Prefix mapping, `base_dir`, cwd-in-key policy | **engine** | Reverse-order application and the `hash_dir`/debug-info interaction are uniform and subtle. Config names which flags are prefix maps. |
| stderr colour force + strip | **engine** | Needs the user's TTY state, which a rule cannot see. Config supplies the per-compiler flag spelling. |
| Temporal-macro scan | **engine** | One word-boundary-aware scanner shared by every C-like rule. |
| Tool identity policy | **engine** mechanism, **config** choice | Four policies plus a `path:size:mtime` memo; the rule picks one and supplies any command. |
| Tool-expansion query (`-### -E -` for `-march=native`) | **engine** mechanism, **config** query + extractor | The extraction line differs per compiler, and clang needs an arch-only filter. |
| Environment allowlist / bypass-on-presence / unset-around-child | **config** | Purely per-tool, and the place buildcache's gcc wrapper has a real bug by omission. |
| The preprocessing argv transform | **config**, engine runs it | "drop `-c`/`-o`/`-M*`, add `-E` (± `-P`), add the include-report flag" is tool knowledge. |
| Sloppiness knobs | **engine** registry, **config** applies them | Named, individually loggable, off by default — ccache's fourteen beat buildcache's single three-level `accuracy`. |
| Cache layout, eviction, atomic restore, umask, signals, recursion guard | **engine** | Nothing per-tool. |
| Hard-link safety | **config**, one boolean | Only the rule knows whether that tool's outputs are ever written in place. |
| The genuinely irregular | **config escape hatch** (template or small script) | `/FI`'s resolve-against-source-dir second pass, `/Yu`'s three-step `.pch` resolution, rustc's `-l static=` search along `-L`, nvcc's `--dryrun` decomposition. None of these is a table cell. |

## Licences of the sources read

| Source | Licence | Constraint |
|---|---|---|
| ccache | **GPL-3.0-or-later** | **Behaviour may be described; code may not be copied or adapted.** Everything cited from it here is prose. |
| sccache | Apache-2.0 | Code may be adapted with attribution. |
| buildcache | **zlib/libpng** (the task brief said MIT; the actual `LICENSE` file is the zlib licence: any use including commercial, may be altered freely, do not misrepresent origin, keep the notice) | Code may be adapted. |
| Bazel REAPI | Apache-2.0 | Protocol may be implemented. |
| Go (`cmd/go/internal/cacheprog`) | BSD-3-Clause | Protocol may be implemented. |
