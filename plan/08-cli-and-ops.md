# 08 — CLI and operations

The command surface, configuration discovery and precedence, diagnostics, and the loud-and-fixable contract made concrete.

## Commands

| Command | What it does |
|---|---|
| `api-cache <tool> <args...>` | Prefix mode. The wrapper's own flags come before `<tool>` and end at `--`. |
| `<masquerade name> <args...>` | Masquerade. `api-cache install-masquerade <dir>` writes the symlinks every shipped and user rule declares in `match=`; `--remove` undoes it. |
| `api-cache run -- <tool> <args...>` | Prefix with an explicit separator, for build systems that cannot avoid a flag collision. |
| `api-cache explain [--rules] -- <tool> <args...>` | Classify without executing. Prints, per argument, the row that matched, its source document, the role and mode it gave; then the verdict; then for every unclassified argument a proposed `<arg>` row ready to paste. `--rules` prints the effective merged rule for the tool (the resolved form). `--json` for tools. |
| `api-cache shapes [--since <build-id>]` | Group every bypass in the log by argument shape, count them, and print the proposed row per shape. api-mirror's leak dashboard on the command line. |
| `api-cache stats [--timing] [--zero] [--json]` | Counters per outcome and reason, the loud-warning summary, and per-stage timings. |
| `api-cache check [--config <path>]` | Load and validate the config set, resolve every tool, run each identity query, report every problem, exit non-zero on any. |
| `api-cache cook [--into <binary>] [--strip]` | `07-cook.md`. |
| `api-cache flush` | Drain the upload spool. |
| `api-cache warm [--compile-commands <path>]` | Compute every key a build will ask for and issue one existence probe and one batch fetch. |
| `api-cache evict [--max-size] [--max-age] [--namespace]` | Run the sweep now. |
| `api-cache gocacheprog` | The GOCACHEPROG host (`09-tool-rules.md`, "Go"). |
| `api-cache serve --config <xml>` | The remote server. A separate binary, `api-cache-server`, with `api-cache serve` execing it, so the wrapper never links the metrics stack. |
| `api-cache docs [readme|config|schema|reasons]` | Embedded documentation, the effective config, the XSD, and the verdict vocabulary with each reason's meaning and fix. |
| `api-cache version` | Engine version, hash-format version, rule versions, and whether the binary carries a trailer. |

## Configuration discovery and precedence

Highest to lowest, ccache's six-tier shape (`plan/research/prior-art/ccache.md`, "Config precedence") because a flatter model is what every "why is my setting ignored" report comes from:

1. The wrapper's own flags in prefix mode (`api-cache --store-dir=... gcc ...`).
2. `API_CACHE_*` environment variables, one per `<store>` and `<remote>` attribute (`API_CACHE_DIR`, `API_CACHE_MAX_SIZE`, `API_CACHE_RESTORE`, `API_CACHE_COMPRESS`, `API_CACHE_SLOPPINESS`, `API_CACHE_REMOTE_URL`, `API_CACHE_REMOTE_WRITE`, `API_CACHE_READ_ONLY`, `API_CACHE_DISABLE`, `API_CACHE_RECACHE`, `API_CACHE_LOG_LEVEL`, `API_CACHE_STRICT`).
3. The project overlay, `.api-cache.xml`, found by searching upward from the cwd and stopping at a `.git` or `.hg` marker or `$HOME`. It may not set `umask` or `dir`, the settings a hostile checkout could use to widen a shared cache's permissions (ccache marks these as unsafe for a directory config).
4. The user config, `~/.config/api-cache/cache.xml` and `*.xml` overlays beside it.
5. The system config, `/etc/api-cache/cache.xml`.
6. The shipped rules and the compiled-in defaults.

`API_CACHE_CONFIG=<path>` names an exact document and disables the search. A trailer-bearing binary disables 1 through 5 except `API_CACHE_DISABLE` and the log level, and says so.

Rule documents merge per `02-language.md`, "Overlays"; settings override attribute by attribute; and `explain --rules` shows where every effective value came from.

## The loud-and-fixable contract, made concrete

`00-goals.md` requires that a bypass is loud and its fix is small. The mechanisms:

**A build identity.** Every invocation belongs to a build. The wrapper derives a build id from the parent process tree's root of the build (the nearest ancestor whose name is `make`, `ninja`, `cargo`, `cmake`, `msbuild`, `xcodebuild`, or the one named by `API_CACHE_BUILD_ID`), falling back to the cwd and the hour. The id keys the per-build log and the deduplication.

**Deduplicated warnings.** The first occurrence of a `(reason, argument)` pair per build prints one line to stderr:

```
api-cache: not cached: unclassified argument `-fweird-flag` (rule gcc, from rules/gcc.xml). Run `api-cache explain -- gcc ...` for a proposed rule. Further occurrences this build are counted, not printed.
```

Later occurrences increment a counter in the build's log. At the end of the build there is no process to print a summary, so `api-cache stats` prints the last build's summary first, and `shapes` groups the whole log.

**Strict mode.** `API_CACHE_STRICT=1` or `<store strict="true">` makes any bypass of a compile-shaped invocation a hard error (exit code 100, the compile not run). This is how CI proves a rule set is complete, buildcache's `terminate_on_miss` narrowed to bypasses rather than misses.

**Per-tool unknown policy.** `unknown="bypass"` and `unknown="hash"` are in `02-language.md`. Under `hash`, an unclassified argument is still logged at a lower severity and appears in `shapes`, so a team running the practical default still sees what its rules do not know.

**`explain` output shape.** For each argument, one line: the argument, the row's `match=`, the roles, the source document and position. Then the verdict with its reason and trigger. Then, for each unclassified argument, a proposed row with the value form guessed from the syntax parser (`sep` if the next argument does not start with a dash and is not a source, else `none`) and `role="hash-verbatim"`, followed by a comment saying which roles to consider if the flag reads or writes a path. The proposal is copy-pasteable into an overlay.

## Logging

- **Per-invocation line** in `<dir>/log/<build-id>.log`: outcome, reason, trigger, key prefix, tool, source, stage timings, bytes restored, and whether the remote was consulted. Plain text, one line, no per-invocation stderr unless the level is `debug`.
- **`API_CACHE_LOG_LEVEL`**: `error` (default), `warn` (the deduplicated warnings), `info` (one line per invocation to stderr too), `debug` (every stage with its inputs).
- Logs are bounded: a log older than seven days or a log directory over a size cap is swept by the evictor.
- `API_CACHE_DEBUG_DUMP=<dir>` writes, per invocation, the classified argv, the key stream in its tagged form, the include set and the manifest decision, for a bug report. It is the equivalent of ccache's `CCACHE_DEBUG`.

## Exit codes

The child's exit code is passed through unchanged on a miss. On a hit the stored code is replayed. The wrapper's own failures use codes above 100 so they cannot be confused with a compiler's: 100 strict-mode bypass, 101 config error, 102 tool not found, 103 recursive invocation, 104 internal error. A cache I/O failure is never an exit code; it is a miss with a logged error.

## Server operations

`api-cache-server` reads one `<cache>` document with a `<serve>` element (listen address, data dir, credentials by class, namespaces, size budgets, eviction schedule, metrics address, the interop prefixes to enable). It logs one aggregated line per active second, exposes `/_health` and `/_version`, drains on SIGTERM within a configurable grace, and warns loudly at startup when no size budget is set. Its dashboard is a later phase; the metrics endpoint is day one.
