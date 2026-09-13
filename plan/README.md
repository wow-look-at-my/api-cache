# api-cache — implementation plan

api-cache is a generalized build cache: a configurable compiler wrapper (the ccache / sccache / buildcache role) and its remote tier (the go-s3-server role), driven by one declarative XML document in the org's api-dsl language, the same language that api-cli and api-mirror speak.

This directory is the plan, not the code. Nothing under `plan/` is implemented. Each file is one decision area, written so it can be reviewed, revised and committed on its own before implementation starts. `plan/research/` holds the raw evidence the workers gathered (measurements, prior-art notes, code surveys). The plan files cite it; they do not repeat it.

## How to read this

Read in order the first time. After that each file stands alone for its area.

| File | Decision area |
|------|---------------|
| `00-goals.md` | What api-cache is for, what it is not for, and the bar it must clear. |
| `01-architecture.md` | The components, the process model, the data flow of one wrapped invocation, and the engine/spec split. |
| `02-language.md` | The XML vocabulary: what a rule file says, what the engine owns, and how api-dsl is reused unchanged. |
| `03-key-derivation.md` | How an invocation becomes a cache key: argv classification, env, inputs, preprocessor and direct modes, manifests, normalization. |
| `04-local-store.md` | The on-disk layout, the result container, atomicity, integrity, eviction, stats. |
| `05-remote-tier.md` | The remote protocol, what is reused from go-s3-server, interop with other cache protocols, auth, upload policy. |
| `06-hot-path.md` | The startup and per-invocation budget, the language decision, and the measured basis for it. |
| `07-cook.md` | The `cook` action: serializing a rule set into a binary form appended to the client, and the sidecar cache that gets most of the benefit for free. |
| `08-cli-and-ops.md` | The command surface, config discovery, diagnostics, `explain`, stats, logs, metrics. |
| `09-tool-rules.md` | The shipped rule files: gcc/clang, MSVC, rustc, Go (GOCACHEPROG), nvcc, generic actions. |
| `10-testing-and-ci.md` | Conformance tests, cross-platform CI, benchmarks, the release path. |
| `11-roadmap.md` | Phases, what each delivers, and what is deferred. |
| `12-decisions.md` | Every open decision the reviewer must make, with options and a recommendation. |
| `13-risks.md` | What can sink the project and what mitigates each. |

## Research

The evidence lives in `plan/research/<worker>/`, one directory per worker, each with a README that indexes it and a summary. The workers were: `prior-art` (ccache, sccache, buildcache, the server protocols), `dsl-survey` (api-dsl, api-cli, api-mirror, api-cli-spec), `compile-semantics` (what a correct wrapper must do per tool), `msvc-probes` (cl.exe and clang-cl measured on windows-latest), `cache-server` (go-s3-server and its client), `storage-protocol` (local layout, container formats, compression, remote protocols, safety, measured on three platforms), `startup-perf` (process startup, config load, trailer, daemon and hashing costs, measured on four runners). Reference repositories are submodules under `refs/`.

## Conventions

- A plan file states a recommendation and its alternatives. A recommendation is marked **Recommended**; it is not a decision until `12-decisions.md` records one.
- A claim with a number cites the research file that measured it.
- Licenses are stated for every third-party component named.
