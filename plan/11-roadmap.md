# 11 — Roadmap

Phases, what each delivers, its exit criterion, and what it deliberately leaves out. Each phase ends with something a user can run. Sizes are relative, not dates: codebase size is not a metric here, and the research already did most of the design work.

## Phase 0 — Foundation: loader, cook, explain, no cache

Deliverables: the Go module; `dsl.go` over api-dsl; the builders and `validate` with every error in `02-language.md`; the three argument-syntax parsers and response-file dialects; the args table, roles, modes, verdict predicate; the closed reason enum; the cook to a binpazer container with the sidecar index; the trailer reader; `explain`, `explain --rules`, `check`, `docs`, `version`; the shipped gcc, cl, clang-cl and rustc rules as text; the conformance corpus runner with the first ~200 cases from the research's worked examples.

Exit: every case in the corpus classifies as expected on all three platforms; `explain` on any unclassified argument prints a pasteable row; the cooked read of the shipped rule set is under 30 µs on the Linux runner; the wrapper binary links neither net/http nor encoding/xml (asserted by a test over `go list -deps`).

Out: executing anything. Phase 0 never runs a compiler.

## Phase 1 — Local cache for gcc and clang, preprocessor mode

Deliverables: the local store (layout, binpazer entries, CRC, temp-and-rename, per-platform restore with the raw-file escape, compression policy, stats, eviction lifted from go-s3-server); the process layer (tool resolution, the three recursion guards, signals, umask, exit codes, stdin passthrough); the preprocess step, key derivation with framing and salt, output capture and restore, dep-file target rewrite, colour forcing and stripping, the too-new check; the per-build log, deduplicated warnings, strict mode.

Exit: the C and C++ end-to-end projects build twice with zero compiles the second time on all three platforms; the direct-hit budget is not yet in scope, but the preprocessor-mode hit is within the Go floor difference of ccache's preprocessor-mode hit on the Linux runner; the loud warning fires once per distinct cause per build.

## Phase 2 — Direct mode and depend mode

Deliverables: manifests as entries, multi-candidate validation, the `#pragma once` guard, the temporal-macro scan, the sloppiness registry with all fifteen knobs, depend mode, `-march=native` expansion, prefix maps and base dir, `hash-output-path` for split DWARF.

Exit: the direct-hit budget in `06-hot-path.md` holds on the Linux runner; parity with ccache's direct hit within the Go floor difference; a mutation test that edits each header in the include set of a fixture and asserts a miss.

## Phase 3 — MSVC and rustc

Deliverables: the cl rule live with `/showIncludes` parsing, `/E` stderr handling, the `/Yu` step, `VS_UNICODE_OUTPUT` deletion, `CL`/`_CL_` bypass, the `/Zi` remedy message; the clang-cl variant; the rustc rule with dep-info discovery, `env-dep`, sysroot identity, `--print file-names` outputs, the static-archive resolution and archive-aware digest.

Exit: the Windows e2e project under cl and clang-cl and the Rust e2e crate build twice with zero compiles; the msvc-probes corrections are all reflected in the cl rule and the corpus.

## Phase 4 — Remote tier

Deliverables: the server binary with the operational core lifted from go-s3-server, the native protocol, namespaces, credential classes, the exists probe, batch get and put, content-equal conflict handling, provenance, metrics; the client with resilience, batching, downgrade, the spool and its opportunistic drain, `flush`, `warm`; the Bazel and ccache HTTP dialects on the mux.

Exit: a two-machine e2e (two runners sharing one server) where the second machine's build is all remote hits; a soak of 5,000 batch puts under admission control; a stock ccache and a stock Bazel client each round-trip an entry through the server.

## Phase 5 — Go

Deliverables: `api-cache gocacheprog` over the same store and client, with SHA-256 output ids and the `DiskPath` contract.

Exit: a stock `go` builds a module twice with zero compiles and, against the remote, a second machine gets remote hits.

## Phase 6 — Generic actions and polish

Deliverables: the generic rule shape with `<inputs>`, `<glob>` and `<extra-file>`; protoc and clang-tidy rules; `shapes`; `install-masquerade`; the Gradle and Turborepo dialects; the server dashboard; the docs site from the embedded README.

Exit: the corpus coverage number is published and every shipped rule has a case for every row.

## Deferred, with the condition that reopens each

| Item | Reopens when |
|---|---|
| A daemon with a static C client | a Linux-heavy deployment measures its hit path dominated by the Go floor after everything else is at budget (`12-decisions.md` decision 5) |
| REAPI gRPC front end | a Bazel, Buck2 or Pants user wants the api-cache server as their remote cache rather than pointing api-cache at theirs |
| ccache storage helper | a team wants stock ccache to reach the server with connection reuse |
| Bloom filter for the existence probe | probe traffic measured as a cost on a real CI fleet |
| Entry signing | a deployment with per-writer keys and a verifying reader |
| nvcc via `--dryrun` decomposition | someone needs it |
| C++20 modules | a compiler ships a dependency report that names BMIs as inputs |
| Distributed compilation | a rule wants to hand a miss to an executor; the `<prefix>` command from buildcache is the cheap first step |
