# Comparison table

Scored qualitatively from each project's own primary docs (see per-tool files
for citations). "Permissive" = MIT/BSD/Apache-2.0/zlib-class, safe to draw code
from; "Copyleft" = GPL-class, study behavior only, never copy implementation.

| | ccache | sccache | buildcache | bazel-remote / REAPI | Gradle build cache | Nx remote cache | Turborepo remote cache | GOCACHEPROG (Go) | go-s3-server |
|---|---|---|---|---|---|---|---|---|---|
| **License** | GPL-3.0-or-later (copyleft) | Apache-2.0 (permissive) | zlib (permissive) | Apache-2.0 (permissive) | protocol is open; Gradle itself Apache-2.0 | protocol open (OpenAPI spec); Nx core MIT | protocol open; Turborepo MPL-2.0 | protocol is part of Go's own BSD-3-Clause tree | this org's own, permissive |
| **Invocation model** | prefix or masquerade (symlink) | daemon: lightweight client auto-spawns/talks to a background server; also `RUSTC_WRAPPER` env-hook | prefix, masquerade, or `BUILDCACHE_IMPERSONATE` env-hook (mutually exclusive with its own CLI args) | N/A — a server behind a client (Bazel/Buck2) speaking REAPI, not a wrapper at all | N/A — a server behind Gradle's own task graph | N/A — a server behind the Nx CLI's own task hashing | N/A — a server behind the `turbo` CLI | subprocess spawned once per `go` invocation, held open via stdin/stdout | N/A — server behind go-toolchain's client (`cacheclient`), driven via `GOCACHEPROG`-style subprocess handoff |
| **Key derivation** | 3 modes: direct (manifest of include hashes), preprocessor (hash of `-E` output), depend (hash `-MD`/`-MMD` dep info) | argv + relevant env vars + dep-info-tracked env; per-language frontend | wrapper-declared: `get_program_id` + `get_relevant_arguments` + `get_relevant_env_vars` + `get_hash_extra_content`, plus direct-mode include list | canonical, sorted `Command` + Merkle-tree `input_root_digest`, digest of the whole `Action` message is the key | opaque key computed entirely client-side by Gradle's task model; wire protocol never sees how | opaque task hash computed client-side by Nx from declared task inputs | opaque hash computed client-side by `turbo` from task inputs | `ActionID` computed client-side by `go`, separate from `OutputID` (content hash of output) | mirrors whatever key scheme its client (go-toolchain via cacheprog) computes; server is key-agnostic |
| **Local storage layout** | sharded dir tree (`cache_dir_levels`), manifest + object files, zstd-compressed | local disk backend available, sharded; primarily reroutes to remote backends | 2-level hex-sharded dirs, `.entry` metadata + up to 4 `.manifest`s + named output files per entry | `cas/` (content, hash-keyed) + `ac/`/`ac.v2/` (action results, digest-keyed), both sharded | none (pure client-computed key over HTTP; server-side layout is an implementation detail, e.g. `build-cache-node`'s own store) | none prescribed — server-implementation-defined, keyed by task hash | none prescribed — server-implementation-defined, keyed by artifact hash | files staged at `DiskPath` under `$GOCACHE`; the subprocess owns however it persists things remotely | two-level hex shard `prefix/v1/aa/bbccdd`, GBCI v1 binary key index for the whole set |
| **Remote protocol** | `remote_storage=` chained string: `file:`, `http:` (GET/PUT/DELETE), `redis:`, `crsh:` (external helper) | pluggable backends compiled in: S3, GCS, Azure, Redis, Memcached, GHA cache, WebDAV, OSS, COS | `BUILDCACHE_REMOTE=` URL: `redis://`, `http://` (per-file GET/PUT, one file = one request), `s3://` | HTTP/1.1 REST (`/cas/`, `/ac/`) **and** full gRPC REAPI (ActionCache, CAS, Capabilities, partial ByteStream) | plain HTTP GET (200/404)/PUT (2xx/413), 307/308-only redirects | HTTP, OpenAPI-specified: GET/PUT per hash, bearer token auth | HTTP `/v8/artifacts/:hash` GET/PUT/HEAD + batch-existence POST + analytics POST, bearer token, optional HMAC-SHA256 artifact signing | JSON-Lines over stdin/stdout to a local subprocess; that subprocess is free to implement its own remote protocol underneath (as go-s3-server's `cacheclient` does) | native protocol: object GET/PUT/HEAD/DELETE, `/_index` binary key index, `/_batch/get` tar+prefetch, `/_batch/put` tar bulk upload |
| **Compression** | zstd, level configurable, disabled when `file_clone`/`hard_link` used | backend-dependent; several backends do their own | LZ4 (default, fast) or ZSTD (opt-in, smaller), configurable level | zstd on CAS blobs, negotiated with client support | none mandated by protocol | server-implementation-defined | server-implementation-defined | none at the protocol level (DiskPath is raw bytes; program may compress its own remote leg) | none server-side — bodies arrive **pre-compressed (lz4)** from the go-toolchain client and are stored byte-for-byte |
| **Multi-output handling** (.o + .d + .dwo + .gcno + stderr, etc.) | stderr cached alongside object; other side files (`.d`, `.dwo`, `.gcno`) handled ad hoc per compiler-flag special-case | per-language frontend knows its own output set (e.g. rustc's `--emit`) | `get_build_files()` returns an arbitrary named map of expected output files — the most general answer in the wrapper-tool tier | `ActionResult.output_files`/`output_directories`, each independently digest-addressed, stdout/stderr as raw-or-digest — the most general answer overall | one opaque blob per cache key; a task's "multi-output" problem is Gradle's own to flatten before the protocol sees it | one artifact archive (implementation-defined bundling) per task hash | one artifact archive per hash | one `(ActionID, OutputID, bytes)` triple per `put`; a build action's several output files are presumably several `put`s under related ActionIDs (protocol doesn't bundle) | protocol-agnostic: server stores whatever keys the client sends; go-toolchain's own action model decides how many keys one build step needs |
| **Platform support** | Linux/macOS/Windows (MSVC too) | Linux/macOS (well-tested) + Windows (less tested); dist-server Linux-only | Linux/macOS/Windows/BSD (per its own doc claims) | server: any Go-supported OS; clients: Bazel/Buck2's own platform matrix | wherever a JVM + Gradle run | wherever Node + Nx run | wherever Node + turbo run | wherever the Go toolchain runs | wherever this org's Go binaries run |
| **Startup overhead per invocation** | none beyond the wrapper binary itself (stateless, no daemon) | client is thin but must reach/spawn a daemon (first call pays spawn cost; subsequent calls amortize it) | none beyond the wrapper binary; Lua-wrapper path additionally parses+interprets a script per invocation | N/A (server persists; client-side cost is Bazel/Buck2's own, not this protocol's) | N/A (server persists) | N/A (server persists) | N/A (server persists) | one subprocess spawned per `go` invocation (not per compile — one cacheprog process serves the whole build) | N/A (server persists; client startup cost is `cacheclient`'s, amortized: key index loads lazily, cached locally with a max-age) |
| **Per-language/tool extensibility model** | none — hard-coded to the C/C++-preprocessor family of compilers (GCC/Clang/MSVC), each compiler variant special-cased in ccache's own source | hard-coded per-language frontend implementations compiled into the one binary (adding a language means patching sccache itself) | **the only tool here with a true plugin model**: Lua scripts implementing a documented function contract, loaded by naming convention/regex, no core recompile needed | N/A — REAPI is a wire protocol; "extensibility" is "any client that can produce a valid `Action`," language-agnostic by construction | N/A — Gradle's own task-type system is the extensibility point, entirely client-side | N/A — Nx's own plugin/executor system is the extensibility point | N/A — Turborepo's own task-pipeline config is the extensibility point | N/A — one protocol serves exactly one client (`cmd/go`); "extensibility" is which cache *backend* the subprocess implements, not which build tool | N/A — one protocol serves exactly one client family (go-toolchain); vocabulary-free by design (api-dsl's own invariant) |
| **Configuration mechanism** | 6-tier precedence: CLI `KEY=VALUE` > `CCACHE_*` env > directory `ccache.conf` (upward search) > `$CCACHE_DIR/ccache.conf` > `/etc/ccache.conf` > compiled defaults | `SCCACHE_*` env vars + `sccache.conf`-style file; simpler precedence than ccache's | `BUILDCACHE_*` env vars, 1:1 mirrored into a JSON config file key; env wins | N/A (protocol has no config layer; a server like bazel-remote has its own flags/YAML) | Gradle's own `settings.gradle`/`gradle.properties`, protocol-external | env vars only (`NX_SELF_HOSTED_REMOTE_CACHE_*`) | `turbo.json` + env vars (`TURBO_REMOTE_CACHE_SIGNATURE_KEY`, etc.) | `GOCACHEPROG` env var names the subprocess; the subprocess's own config is its business | JSON config file + `--config`/flag overrides + a handful of env vars (`CACHE_MAX_BYTES`, `GOMEMLIMIT`) |

## Reading the table

- **Only three of these are "wrapper" tools in the ccache/sccache/buildcache
  sense** (a program standing in for the compiler); everything else is a
  **server protocol** a client speaks. api-cache, per its brief, needs both
  halves: a wrapper/invocation layer that decides *what to hash and when to
  bypass caching*, and a storage protocol that a server implements. No single
  existing project owns both halves the way api-cache is meant to.
- **buildcache is the only wrapper tool with genuine pluggable, no-recompile
  extensibility** (Lua). ccache and sccache both require patching the tool's
  own source to add a compiler/language. This is the single most important
  data point favoring a declarative-XML-with-a-DSL approach over "hard-code
  every supported tool," and directly informs why buildcache gets its own
  deep-dive file.
- **REAPI is the only protocol with a genuinely structured (Merkle-tree)
  input model**; every wrapper tool instead reduces "the inputs" to a flat
  hash. If api-cache's declarative spec ever needs to express "this action's
  inputs overlap heavily with that one's," REAPI's approach — not any wrapper
  tool's — is the model to borrow.
- **Turborepo's signed-artifact model and REAPI's "upload the Action before
  the ActionResult" rule are the only two protocols in this survey that treat
  cache-poisoning/tampering as a first-class protocol concern** rather than an
  assumed-safe transport property. Worth carrying forward explicitly.
- **GOCACHEPROG's ActionID/OutputID split is the cleanest idea from the
  "protocol between a build tool and an external cache" category** (as
  opposed to protocols between a cache client and a remote store) — it is the
  layer api-cache's own wrapper-to-server boundary most directly resembles,
  and go-s3-server already implements the server side of exactly this
  relationship for one concrete client (go-toolchain).
- **go-s3-server's own protocol design choices** — a precomputed binary key
  index instead of per-key existence probing, tar-bundled batch transfer
  instead of one-request-per-object, module-index-specific poisoning defense,
  self-healing repair of a recoverable corruption rather than a silent
  permanent miss — are all responses to scale problems this survey's other
  tools hit in smaller form (buildcache's HTTP backend is one request per
  file; ccache's `http:` backend is likewise per-object). api-cache's own
  remote protocol should assume it needs the same batching/index answers from
  day one rather than rediscovering them under load the way each predecessor
  did.

## Sources

Per-tool citations are in `ccache.md`, `sccache.md`, `buildcache.md`, and
`other-wrappers.md`. go-s3-server's own claims are drawn from
`/home/user/go-s3-server/README.md` and `/home/user/go-s3-server/CLAUDE.md`.
