# 00 — Goals and non-goals

## What api-cache is

One XML document turns a build tool invocation into a cache lookup. api-cache is the wrapper that sits in front of a compiler (or any deterministic tool), derives a key from the invocation, and answers from a local store, a remote store, or the tool itself. It is also the remote store. The mechanism lives in an engine. The knowledge of each tool (which argument is an input, which output the tool produces, which environment variable matters, when to step aside) lives in a rule file written in the org's api-dsl language, the language api-cli and api-mirror already speak.

The engine/spec split is the same one api-mirror drew: the engine holds every mechanism, and the spec holds only vocabulary. A tool rule cannot express an unsafe key, because the engine derives the key from declared inputs and refuses an invocation it cannot classify.

## The predecessors and what each got wrong

| Tool | Speed | Defaults | Flexibility | Usable in practice | License |
|------|-------|----------|-------------|--------------------|---------|
| ccache | fast | poor | low | often | GPL-3.0 |
| sccache | fast | good | lower | rarely | Apache-2.0 |
| buildcache | a bit slower | good, simple, documented | high (Lua wrappers) | most scenarios | MIT |
| go-s3-server | fast | n/a (server) | one client, one protocol | Go only | MIT |

buildcache is the reference point. Its Lua wrapper contract shows that a small set of per-tool hooks is enough to cover most real tools. Its weaknesses are a small test surface, a small contributor base, and a per-invocation cost above ccache's. api-cache keeps the flexibility, moves the hooks into a declarative language with a validating loader, and takes the hot path seriously enough to match or beat ccache.

Codebase size is not a metric. The constraint that kept buildcache small no longer applies.

## Requirements, in priority order

1. **Correctness before hits.** A wrong hit is a corrupted build. Every bypass has a stated reason from a closed vocabulary. An invocation the rule file does not classify is passed through, never guessed at.
2. **Absolute performance on the hot path.** A hit must cost close to the process-startup floor of a C program. The budget and the measured basis are in `06-hot-path.md`. Config load must not be paid per invocation once a cooked or cached form exists.
3. **Configurability without recompiling.** A new tool, a new flag family, a new key policy, a new remote is a rule-file change. The rule file uses `<vars>`, `<steps>`, `<if>`, `<for>`, templates and program hooks exactly as api-cli does, so anything a shell script could compute, a rule can compute, at a cost the author can see.
4. **One engine, many tools.** C and C++ (gcc, clang, MSVC, clang-cl), Rust (rustc under cargo), Go (the GOCACHEPROG protocol), CUDA (nvcc), and a generic action mode (declared inputs and outputs, Bazel-style) all run on the same primitives.
5. **Local and remote are one design.** The local store and the remote tier share the entry format and the key space. go-s3-server is prior art for the remote tier, and its storage, index, batch and eviction designs are candidates for reuse where they generalize, never a requirement.
6. **Observable.** Stats, an `explain` for any invocation that says why it hit, missed, or bypassed, structured logs, and metrics on the server. A miss the operator cannot explain is a bug.
7. **Portable.** Linux, macOS and Windows, on x86-64 and arm64. Windows needs MSVC support and a metadata strategy that does not depend on xattrs.

## Non-goals for the first release

- Distributed compilation (distcc, icecc, sccache-dist). The rule language may later express a remote executor, and nothing in the key design blocks it, but it is not built first.
- Caching links. Nothing in the engine forbids it (the generic action mode can), but no shipped rule does it.
- A GUI. The operator surface is the CLI and the server's existing dashboard pattern.
- Replacing any existing in-process Go cache client. api-cache speaks GOCACHEPROG for a stock `go` and nothing more.

## Success criteria

- On a warm local cache, a gcc hit through api-cache costs no more than ccache's hit on the same machine, measured with the harness in `plan/research/startup-perf/`.
- The shipped gcc/clang rule matches ccache's bypass decisions on a corpus of real argv lines (`10-testing-and-ci.md`), with every difference documented.
- A rule file author can add a new tool without touching Go code, and the loader rejects a rule file that would produce an unsafe key.
- The remote tier serves a CI fleet with batch and index features of the kind go-s3-server proved, and a cache poisoned by one client cannot poison another's build silently (integrity checks on read).

## Constraints that do NOT apply

This project starts from a clean slate. The conventions of the org's other repositories (a shared build wrapper, a fat portable executable as the only output, a particular lint gate, a particular test harness, a particular CI action) are not requirements here. Any of them may be adopted later on its own merits, and the plan evaluates each choice on measured cost, never on precedent. The prior repositories are reference material for design and code reuse only.
