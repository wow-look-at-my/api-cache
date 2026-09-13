# 01 — Architecture

This file names the components, the process model, and the data flow of one wrapped invocation. It also draws the engine/spec line: what is mechanism in Go, and what is vocabulary in a rule file. Every claim with a number cites `plan/research/`.

## The components

```
                    rule files (XML, api-dsl)          shipped rules + user overlays
                              |
                         [loader + cook]  ----------->  cooked form (binpazer)  --> sidecar cache, or a trailer on the binary
                              |
   build system --exec--> [wrapper]  --------------------------------------------------------------+
   (make, ninja,           | classify | key | discover | lookup | run | capture | restore | report |
    cargo, cmake ...)      +---------+-----+----------+--------+-----+---------+---------+--------+
                              |                    |                        |
                         [local store]        [remote client]          [stats + log]
                         one dir, entries      HTTP, batch, probe       per-cache-dir
                              |                    |
                              |               [remote server]  <---- also: stock ccache, Bazel HTTP, Gradle, Turborepo clients
                              |               blob store + index + batch + eviction + metrics
                              |
   go build --GOCACHEPROG--> [gocacheprog host]   store-only mode over the same local store and remote client
```

Five deliverables share one engine:

| Deliverable | Role | Process shape |
|---|---|---|
| `api-cache` (wrapper) | Stands in for a tool. One exec per invocation. | Short-lived. The whole hot-path budget lives here (`06-hot-path.md`). |
| Loader and cook | Reads rule files, validates, compiles templates, emits the cooked form. | Runs once per config change, never per compile (`07-cook.md`). |
| Local store | The on-disk cache: entries, manifests, stats, eviction. | A library inside the wrapper. No daemon. |
| Remote client | Talks to a remote tier: probe, get, put, batch, spool. | A library inside the wrapper, plus the spool drained opportunistically. |
| Remote server | `api-cache serve`: the remote tier. | Long-lived. Reuses go-s3-server's operational core by lifting files, and speaks several dialects on one blob store (`05-remote-tier.md`). |
| GOCACHEPROG host | `api-cache gocacheprog`: serves a stock `go`. | One process per `go` invocation, store-only: `go` derives the keys. |

The wrapper, the loader, the local store, the remote client and the GOCACHEPROG host are one Go module and, ideally, one binary. The server is a second binary in the same repository, because it links a metrics stack the wrapper must never pay for at startup (`plan/research/startup-perf/README.md`: net/http + encoding/xml + text/template cost 2.2 ms per exec on Windows and 2.7 ms on macOS).

## No daemon, by measurement

sccache's daemon exists to amortize remote connections and in-memory state. The measurements say the daemon buys nothing unless the client is native: a Go client talking to a Go daemon costs ~1,290 µs per exec against ~1,337 µs for a cooked Go binary that does all the work itself (`plan/research/startup-perf/results/daemon.md`). A static C client would cost ~608 µs, which is the one configuration that pays, at the price of a second language and a two-implementation protocol.

The plan therefore has no daemon in the first release. The engine is written so one could be added later without touching the rule language: the wrapper's pipeline is a function from (argv, env, cwd, rules) to (verdict, key, outputs), and a daemon would host that function behind a socket. `12-decisions.md` records the C-client option and the numbers that would justify it.

What replaces the daemon's two jobs:

- **Config state** is precomputed by the cook and read in ~17 µs from a binpazer container (`plan/research/startup-perf/results/trailer.md`).
- **Remote connections** are per-invocation, with a spool for uploads so a compile never waits on a slow PUT (`05-remote-tier.md`, "Upload policy").

## The data flow of one invocation

The pipeline, with the engine primitive each stage uses. The names are the ones in `plan/research/compile-semantics/key-derivation-model.md` §2, which is the inventory this plan implements.

1. **Load.** Find the cooked config (`07-cook.md`). If it is stale or absent, cook it now and continue. Select the tool rule by the invoked name and the resolved real tool (`invocation-modes.md` §2: basename-only matching under masquerade, skip the canonicalised argv[0], reject the wrapper binary, set the recursion-guard variable).
2. **Expand.** Response files, recursively for GNU and until fixpoint with a depth cap for MSVC (nested `@` does expand on cl 19.51, `plan/research/msvc-probes/corrections.md` §2). The `CL` and `_CL_` variables are a third expansion site.
3. **Parse and classify.** The named argument syntax parser (`gnu`, `msvc`, `rustc`) produces `(flag, value, spelling)` triples. Each is looked up in the rule's table and given a role. Forwarded payloads (`-Wp,`, `-Xclang`, `/clang:`) re-dispatch through the same table.
4. **Verdict.** A small predicate over mode flags and counts. The outcome is either "cacheable" or a code from the closed reason vocabulary, with the triggering argument attached (`03-key-derivation.md`, "Verdicts"). A bypass execs the tool and reports, per the loud-and-fixable contract in `00-goals.md`.
5. **Common key.** Format version (engine + rule), tool identity, invoked name, environment allowlist, filtered argv, expanded native flags, and the cwd only when the rule says it leaks into the output.
6. **Direct lookup** (when the rule declares direct mode). Fork the hash with the direct-only inputs, look up the manifest, validate candidates against the filesystem, and take the first full match to a result key.
7. **Discover** (on a direct miss, or when direct mode is off). Run the rule's preprocess step, hash its output and stderr, and build the include set from the report the rule named (linemarkers, `-H`, `/showIncludes`, `/sourceDependencies`, a dep file). Depend mode skips this and runs the tool first.
8. **Result lookup.** Local store first. On a local miss, the remote client asks the remote, if one is configured and the policy allows reads.
9. **Hit.** Restore every output by the platform's restore method, replay stdout and stderr verbatim with colour stripped when the caller's stream is not a terminal, rewrite the dependency target if the invocation asked for a different one, regenerate `/showIncludes` lines with depth, and exit with the stored code.
10. **Miss.** Run the tool with the recursion guard set, colour forced on, and the rule's unset-around-child list applied. Check inputs for the "too new" race. Capture the declared outputs, derived siblings, both streams and the exit code. A non-zero exit stores nothing and exits with that code.
11. **Store.** Assemble the entry in the scratch directory, CRC each block, rename into the local store, add the manifest candidate, and hand the entry to the remote client (spooled or synchronous per policy).
12. **Report.** One line in the per-cache-dir log with the outcome, the reason, and the timings of each stage. The stats counters move. A bypass with an unclassified argument prints the loud warning on first occurrence.

Hit and miss share every step except 9 and 10, which is api-mirror's "hit and miss share one path" rule (`plan/research/dsl-survey/api-mirror-language.md` §8, pattern 9): the observable result never depends on cache state.

## The engine/spec line

The line follows `plan/research/compile-semantics/key-derivation-model.md` §5, with one change: the engine owns more than that table gives it, because the user's steer is that a rule must be understandable by reading it (`00-goals.md`, "Design input").

**Engine (Go, no per-tool knowledge):**

- Response-file expansion, all three dialects.
- The argument syntax parsers, selected by name.
- Forwarding re-dispatch.
- The closed verdict vocabulary and the aggregation of reasons.
- Hashing: algorithm, framing, tagging, the format-version salt, the inode memo, archive-aware digests, tool-identity policies and their memo, the tool-expansion query runner.
- Input discovery parsers: dep files (parse, escape, target rewrite, relativise), `/showIncludes` with runtime prefix detection, linemarkers, `-H` reports, `/sourceDependencies` JSON, rustc dep-info with `# env-dep:` records.
- Manifests: multi-candidate structure, interning, validation order, bounds.
- Outputs: derivation from argv, sibling derivation by extension, tool-query derivation (`--print file-names`), capture, restore, streams, colour handling, scratch directories.
- Process: tool resolution, recursion guard, signals, umask, temp-and-rename, the too-new check.
- The local store, the remote client, the server, stats, logs, `explain`.

**Spec (a rule file):**

- Which programs the rule handles, and the tie-break between the invoked name and the real path.
- The argument dialect and the response-file dialect.
- The table of flag families: pattern, value form, role, mode, gate.
- The verdict conditions (which combinations decline, with which code).
- The primary output derivation when it is not stated, and the derived siblings per mode.
- The tool-identity policy and any expansion query.
- The environment allowlist, the bypass-on-presence list, the unset-around-child list.
- The preprocess step: how to build its argv from the compile argv, and which include report to read.
- Whether direct mode exists and what the direct key adds.
- Which sloppiness knobs apply.
- Whether outputs are safe to hard-link.
- A rule format version.

That is the 13-item completeness list from `key-derivation-model.md` §6, and `02-language.md` gives each item a home in the grammar.

## Invocation modes

All four from `plan/research/compile-semantics/invocation-modes.md` are supported, because each catches a build the others miss:

| Mode | Example | Notes |
|---|---|---|
| Prefix | `api-cache gcc -c foo.c` | What `CMAKE_<LANG>_COMPILER_LAUNCHER` and `RUSTC_WRAPPER` produce. The only mode where the wrapper's own flags are accepted, terminated by `--`. |
| Masquerade | `~/bin/gcc -> api-cache` | Basename-only tool resolution. `api-cache install-masquerade <dir>` writes the symlinks the rules declare. |
| Impersonate | `API_CACHE_IMPERSONATE=cl.exe api-cache /c foo.c` | For build systems that want one fixed program path. The wrapper's own flags are unavailable, as buildcache documents. |
| Protocol | `GOCACHEPROG=api-cache gocacheprog` | Go. No argv parsing. |

The three recursion guards are all implemented, because each closes a case the others miss (`invocation-modes.md` §2): skip the canonicalised argv[0] on PATH, reject any candidate that is the wrapper binary by content identity rather than name, and set `API_CACHE_DISABLE=1` for the child's subtree.

## Platform strategy

The measured floors differ by an order of magnitude across platforms (`plan/research/startup-perf/results/ci-platforms.md`): the cheapest possible exec is ~451 µs on Linux, ~2.2 ms on macOS, ~5.2 ms on Windows. Three consequences shape the design:

- **The import set is a per-binary decision.** The wrapper binary must not link net/http, encoding/xml or text/template's parser at runtime on the hot path. The cook does the XML and template work; the wrapper reads the cooked form. The remote client's HTTP layer is a separate concern in `12-decisions.md` (decision 6).
- **File operations cost ~10x on NTFS** (`plan/research/storage-protocol/local-layout.md`): a stat is 22 µs, an open 24 µs. The local store is therefore one container per result, fixed two-level sharding, one stat per miss, and metadata inside the container rather than in sidecars or xattrs.
- **Rename-over-open and unlink-of-open fail on NTFS** and succeed on ext4 and APFS (measured). The store renames the old entry aside on Windows, and the evictor skips an entry a reader holds.

`04-local-store.md` carries the per-platform restore table. The short version: clone on APFS, copy on ext4, copy on NTFS unless ReFS, and hard links only when the rule says the tool's outputs are never written in place.

## What the first release does not build

- A daemon or a C client (measured as not worth it without the C client; deferred).
- Distributed compilation.
- Link caching in the shipped rules (the generic action mode can express it later).
- C++20 modules beyond a bypass with a stated reason.
- An MCP server. api-cli's experience is that a second execution host is a second copy of the runner (`plan/research/dsl-survey/gaps.md` §15); if one is ever wanted, the leaf runner is factored with an injected I/O policy first.
