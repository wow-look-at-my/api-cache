# 10 — Testing and CI

What proves the engine correct, what proves it fast, and how CI runs both on every platform. The rules the research established for itself carry over: no silent failure anywhere, benchmarks only on dedicated runners, one workflow per concern with scoped triggers and a per-workflow concurrency group.

## The conformance corpus

The corpus is the measure of "practically usable" (`00-goals.md`). It is a directory of cases, each a real argv line with its expected verdict and classification:

```
corpus/gcc/0142.case
  argv: gcc -c -O2 -g -MD -MF dep/foo.d -fdebug-prefix-map=/src=. foo.c -o obj/foo.o
  tool: gcc
  verdict: cacheable
  mode: compiling debug-info generating-deps
  roles: source-input=foo.c primary-output=obj/foo.o dep-output=dep/foo.d prefix-map=/src=.
  key-excludes: -o dep/foo.d
  outputs: obj/foo.o dep/foo.d
  cwd-in-key: false          # the prefix map covers the cwd
```

- Sources: the worked examples in `plan/research/compile-semantics/*.md` §9 and §6, the argv shapes CMake, autotools, ninja, cargo, Chromium's GN, the Linux kernel and Unreal produce (captured once with `explain --record` against real builds and checked in), and every bug report that adds a row to a rule.
- The test runs `explain --json` over every case and compares. A case that changes classification without a rule change fails the build. A new rule row without a case fails review.
- Coverage is reported as a number per rule: cases passing over cases present, and the count of flags in the rule's table without a case. The number is in the README.
- ccache parity: for the gcc corpus, ccache's verdict on the same line (recorded once from a ccache run with `CCACHE_DEBUG`) sits beside api-cache's, and every difference carries a comment saying why. ccache is GPL; its verdicts are observed behaviour, not copied code.

## Unit and integration tests

By package, Go tests with testify:

- **Parsers**: response files in all three dialects with the measured edge cases (nested `@` on MSVC, UTF-16LE accepted and UTF-16BE refused, gcc leaving an unopenable file verbatim); dep files with the measured escaping table; `/showIncludes` depth and duplicate lines; rustc dep-info with unset versus empty `env-dep`.
- **Hashing**: framing (`-I -O2` versus `-I-O2` differ), fork isolation, format-version salt, prefix-map order, the cwd rule under debug info and MSVC.
- **Manifest**: multi-candidate order, bounds and reset, the `#pragma once` guard, the too-new check with a fixture that backdates and forward-dates files.
- **Store**: temp-and-rename atomicity under concurrent writers (a race test with 32 goroutines storing one key), CRC rejection, rename-aside on Windows, the raw-file escape for clone and link restore, eviction ordering and the reader-holds-file case, the format fingerprint purge.
- **Restore**: per-method tests that run on every platform and report the platform's verdict (`clonefile` on APFS, `FICLONE` on Linux with an explicit "unsupported on ext4" verdict, `link` everywhere) rather than skipping.
- **Process**: tool resolution with a symlink through the wrapper, a second wrapper on PATH, a shell script that re-invokes the wrapper; signal forwarding with a child that traps TERM; exit-code passthrough; umask and the executable bit.
- **Remote**: an in-process server for the client's probe, batch, downgrade, spool drain, read-only credential, and content-equal conflict paths; interop tests that drive the mux with recorded requests from bazel-remote's and ccache's clients.
- **Loader and cook**: every validation error in `02-language.md` has a test with the exact message; overlay merge; the sidecar index invalidation on each of (document edit, engine version change, overlay added); the trailer round trip.
- **GOCACHEPROG**: a stock `go` from actions/setup-go building a small module twice with `GOCACHEPROG` set, asserting zero compiles on the second build and a verified `OutputID`.

Every test that swaps a package-level seam calls `t.Setenv` or a serial marker; every temp directory is on the same filesystem as the store under test.

## End-to-end tests with real compilers

A matrix job per platform builds three small real projects (a C project with `-MD` and `-g`, a C++ project with a PCH and `-gsplit-dwarf`, a Rust crate with two dependencies) twice with api-cache wrapped and asserts: second build performs zero compiles, every restored file is byte-identical to the first build's, stderr replay is byte-identical, dep files are usable by the build system (ninja's `-d explain` reports nothing dirty), and `stats` shows only hits. Then it edits one header and asserts exactly the right compiles rerun. Windows runs the MSVC project under both `cl` and `clang-cl`. macOS asserts the clone restore was used. The msvc-probes worker's harness lessons apply: every child gets stdin from NUL and a per-step timeout, and `vctip.exe` inheriting a pipe is why output goes to files.

## Benchmarks

The startup-perf and storage-protocol probe suites move into the repository's `bench/` directory as the regression suite for the budget in `06-hot-path.md`. A dedicated workflow, `bench.yml`, runs on push to a `bench/**` path or a TRIGGER file, on ubuntu, macos and windows runners, with hyperfine (`--shell=none --warmup 20 --runs 300`, markdown and JSON export) for whole-process timings and Go benchmarks for stages. It asserts:

- the wrapper's exec cost for a `--version` call against the Go hello floor of the same run, within a stated margin;
- the direct-hit cost against the budget table;
- the direct-hit cost against ccache's hit on the same file and runner (ccache installed from the distribution package), with the phase-1 exit criterion being parity within the Go floor difference.

Each job uploads its results as an artifact and fails when a table is missing or has fewer rows than expected, the bug the research found in its own Windows job where hyperfine pre-created an empty export file and the job went green.

## Fuzzing

Fuzz targets, run in CI for a bounded time: the three argv parsers with response-file expansion, the dep-file parser, the `/showIncludes` parser, the binpazer entry reader on hostile bytes (binpazer's own reader is fuzzed; ours wraps it with role validation), and the manifest reader.

## Workflows

- `test.yml`: lint, vet, unit and integration tests on the three platforms, the conformance corpus, the fuzz smoke. Triggered on every push.
- `e2e.yml`: the real-compiler matrix. Triggered on push to `main` and by TRIGGER.
- `bench.yml`: as above.
- `server.yml`: the server's tests plus a soak that drives it with 5,000 batch puts and asserts admission control and eviction behaved.

Every workflow: `concurrency: { group: <filename>, cancel-in-progress: true }`, public actions only, `submodules: true`, no `continue-on-error`, no `|| true`, no skip-when-unavailable branch. A missing prerequisite fails red.

## Release

A release builds the wrapper for linux/amd64, linux/arm64, darwin/arm64, windows/amd64 with `CGO_ENABLED=0`, the server for linux/amd64 and linux/arm64, runs the e2e matrix against the built binaries, and publishes them with checksums. The rule directory ships beside the binary and embedded in it. A cooked variant is not published; `api-cache cook --into` is for the user's own images.
