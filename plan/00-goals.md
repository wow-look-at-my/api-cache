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

1. **Correctness before hits, and silence is a bug.** A wrong hit is a corrupted build. Every bypass has a stated reason from a closed vocabulary. An invocation the rule file does not classify is passed through, never guessed at. That route is only acceptable with two guarantees, and both are harder than the bypass itself. First, the bypass is LOUD: the user sees what was not understood, once per distinct cause per build rather than once per invocation, with the exact argument or condition named. Second, the fix is SMALL: what was not understood maps to one rule-file addition, and the tool prints the rule it thinks is missing, the way api-mirror hands the operator the `<route>` that would stop a passthrough. See "The loud-and-fixable contract" below.
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

## The loud-and-fixable contract

Requirement 1 is cheap to state and expensive to honor. A cache that bypasses quietly is a cache that silently stops working, and a cache that bypasses loudly but needs a Go change to fix is a support burden. The plan therefore treats the following as first-class deliverables, not polish:

- **A closed reason vocabulary.** Every non-hit outcome is one of a fixed list (unclassified argument, unsupported argument, no source file, several source files, output to stdout, preprocessor failed, compiler wrote to stdout, source on stdin, input file unreadable, ...). The list is an enum in the engine and a table in the docs. A rule file cannot invent a reason, and the engine cannot report one that is not in the table.
- **Aggregated loud warnings.** A build runs thousands of invocations. The wrapper writes each reason to a per-build log keyed by the parent build's identity (session id, or the cache directory's stats bucket), and the user-facing warning is deduplicated: the first occurrence prints to stderr with the offending argument, later ones increment a counter, and `api-cache stats` and the end-of-build summary show counts per reason and per distinct argument. A CI mode can fail the build on any bypass, which is how a team keeps its rule file complete.
- **`explain` hands you the fix.** `api-cache explain -- <argv>` runs the classifier without executing anything and prints, for every argument, which rule matched or that none did, the resulting verdict, and for each unclassified argument a proposed rule element ready to paste. `api-cache shapes` (the api-mirror dashboard idea, on the command line) groups every bypass seen in the log by argument shape, counts them, and prints the proposed rule per shape.
- **Rules are data, so the fix is one small PR.** Per-tool knowledge lives in shipped rule files and in the user's own overlay. Adding a flag classification is one line of XML plus one line in the conformance corpus. Nothing about a flag lives in Go. If a fix ever needs Go, that is a missing engine primitive and gets logged as such in `12-decisions.md`.
- **Two strictness policies, declared per tool.** `unknown="bypass"` (the correctness default: an argument no rule matches passes the invocation through, loudly) and `unknown="hash"` (the ccache and buildcache default: an unmatched argument is hashed verbatim and the invocation is cached, with a lower-severity notice). The second is wrong for an argument that names an input or an output the rule did not see, so the shipped rules for gcc, clang and MSVC classify every flag family that takes a path, and the corpus test proves it. A team chooses the policy per tool with eyes open.
- **A corpus, not a hope.** The conformance corpus (`10-testing-and-ci.md`) holds real argv lines from real builds (CMake, autotools, Bazel, cargo, Unreal, Chromium, the kernel), with the expected verdict for each. Every unclassified-argument report that gets fixed adds its line to the corpus. Coverage of the corpus is the measure of "practically usable", and it is tracked as a number.

## Design steer: declarative, not hooks

buildcache's flexibility goal is right: a user's rule for a new tool, a shipped rule for gcc, and the engine's own handling are one surface. Its implementation is wrong for us: a Lua wrapper is a set of hook functions (`get_relevant_arguments`, `get_build_files`, `preprocess_source`, ...) that each hand-parse argv, and the author re-does the same flag walking in every wrapper. The result is hard to read and hard to reason about.

api-cache takes the goal and drops the mechanism:

- **A rule file is a table of meanings, not a program.** The core of a tool rule is a list of argument patterns, each with a role: source input, primary output, dependency output, a path the tool reads, a path the tool writes, hash verbatim, ignore, bypass with a reason. The engine walks argv against that table. The author never writes a loop.
- **Tool argument syntax is an engine primitive.** GNU style (`-o x`, `-ox`, `--opt=x`, `-Wp,` and `-Xlinker` forwarding, `@response` files, `--`), MSVC style (`/Fo`, `/Fo:`, `-Fo`, `/D`, `@rsp` with its own quoting, `/link`), and rustc style are parsers the engine ships. A rule names the syntax and adds the meanings.
- **Derived outputs, dependency parsing and normalization are engine primitives.** `.d` reading and rewriting, `/showIncludes` parsing with its localized prefix, `.dwo` and `.gcno` sibling derivation, stderr color normalization, path prefix mapping: each is a named engine behavior a rule switches on with one attribute, never something a rule implements.
- **Templates and steps are the escape hatch.** When a table entry is not enough, a rule reaches for the same `<vars>`, `<steps>`, `<if>`, `<for>` and program hooks api-cli has, with the cost visible. A shipped rule that needs the escape hatch is a signal that an engine primitive is missing, and that goes into `12-decisions.md`.
- **Shipped rules and user rules are the same files.** There is no compiled-in gcc handler that a user rule cannot read, copy and override. A user overlay can add one flag to the shipped gcc rule without copying the rule.
- **Every rule is explainable.** `api-cache explain` shows, for each argument, the table row that matched and the role it gave. If a rule cannot be explained that way, it is written wrong.
