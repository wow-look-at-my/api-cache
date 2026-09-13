# Other wrappers, remote-cache protocols, and adjacent systems

buildcache gets its own deep-dive in `buildcache.md` (the user's flagged closest
prior art). This file covers the rest of the landscape: other compiler wrappers,
distributed-compilation systems, and the remote-cache protocols of Bazel, Gradle,
Nx/Turborepo, and Go's `GOCACHEPROG`.

## clcache

MSVC-specific compiler cache, Python, prefixed or masquerading as `cl.exe`.
**License: BSD 3-Clause** (permissive). Original repo `frerich/clcache` is
archived (last active ~Feb 2020); several community forks continue it
(`Nuitka/clcache` is the most actively maintained fork per search results).
Mechanically: parses the MSVC command line to determine whether it's a
single-source compile, and if so looks up a hash in a local cache before
invoking the real `cl.exe`. Being MSVC-only and Python-based (interpreter
startup cost per invocation), it's a useful data point for "per-language,
single-purpose wrapper" as the opposite extreme from buildcache's
pluggable-wrapper-contract design — clcache has no analogue of a scriptable
wrapper API, because it only ever needs to know MSVC's own argument shape.

## cachepot (Parity Technologies fork of sccache)

**License: Apache-2.0** (inherited from sccache; no relicense). Started by
Parity Technologies (Igor Matuszewski, Bernhard Schuster) around April 2021 as
"`sccache` with extra sec[urity]." Same language/compiler coverage as sccache
(C/C++, Rust, CUDA), plus a stated goal of upstreaming improvements back to
Mozilla's sccache rather than diverging permanently. Its distinguishing feature
claim over sccache's own dist mode: icecream-style distributed compilation
**with** authentication, transport encryption, and sandboxed compiler execution
on build servers — i.e. cachepot productized exactly the security gaps its own
README calls out in plain icecream (see below). This is useful evidence that
"add auth+encryption+sandboxing to a distcc-style dist model" is a well-trodden,
independently-arrived-at feature, not a novel idea api-cache would be
inventing from scratch.

## distcc

**License: GPL-2.0-or-later.** Copyleft — same posture as ccache: fine to study
behavior, not to copy code, given the org's stance on viral licenses.
Distributed C/C++/Objective-C compilation: a client-side wrapper sends
preprocessed source (or, in "pump mode," source plus a computed dependency
closure) to any of several statically-configured `distccd` hosts for compilation,
then gets the object file back. No result caching of its own historically — it
is pure distributed *execution*, which is why ccache-in-distcc and
distcc-in-ccache pairings are both real deployment patterns (ccache caches
results, distcc distributes the cache-miss compiles across a farm).

## icecream / icecc (SUSE's fork/rework of distcc)

**License: GPL-2.0-or-later AND LGPL-2.1-or-later** (dual-component licensing —
the daemon/scheduler under GPL, at least one shared library under LGPL,
per the repo's own `COPYING`). Repo: `github.com/icecc/icecream`. Adds exactly
the piece distcc lacks: a **central scheduler** daemon that build hosts
(`iceccd`) register/deregister with dynamically, so job placement follows
current host load/speed instead of a static, manually-maintained host list.
Three roles: **scheduler** (one, load-balances jobs across registered daemons),
**daemon** (`iceccd`, runs on every build host, either compiles locally or
forwards to a peer per the scheduler's advice), **client** (`icecc`, the
compiler-wrapper end users actually invoke). This scheduler/worker/client
three-way split is architecturally the same shape as sccache-dist's
scheduler/build-server/client model (sccache's own docs cite icecream as its
model, adding auth/encryption/sandboxing on top — see sccache.md).

## Mozilla's ccache-in-CI patterns

Mozilla's own build documentation (the same organization that built sccache)
historically ran **both** ccache and sccache in different CI configurations
depending on platform/toolchain maturity, with sccache favored specifically once
Rust and cross-machine sharing mattered, and ccache retained longer for C/C++-only
legacy configurations where its wider battle-testing outweighed sccache's
broader storage-backend menu. The practical lesson generalizes: an org rarely
picks one tool timelessly — the two systems' actual selection criteria were
"does this tool understand our language mix" and "do we need a shared/remote
cache across many CI machines," which map directly onto two of api-cache's own
design axes (per-language extensibility, remote-store pluggability).

## Bazel / Buck2 Remote Execution API v2 (REAPI) — ActionCache + CAS

**License of the spec itself: Apache-2.0** (`bazelbuild/remote-apis`, protobuf
IDL — a specification, not an implementation, but its license still governs
copying the `.proto` files). This is the most rigorously specified remote-cache
protocol in this survey, and worth treating as the reference design for how a
generalized action-cache-plus-blob-store split should look.

**Core message shapes** (from `remote_execution.proto`):

- **`Digest { hash: string, size_bytes: int64 }`** — a blob identifier: lowercase
  hex hash (algorithm negotiated via the Capabilities service, historically
  SHA-256) plus size. Every blob in the system — file contents, serialized
  proto messages, directory listings — is addressed purely by its `Digest`.
- **`Directory { files: [FileNode], directories: [DirectoryNode], symlinks:
  [SymlinkNode], node_properties }`** — one directory level of an input tree.
  The spec is explicit that children must be in **canonical, sorted order** so
  that two logically-identical trees always hash to the same `Digest` — this
  canonicalization requirement is what makes a whole input tree Merkle-hashable
  by recursively hashing `Directory` messages bottom-up (a subdirectory's own
  `Digest` is what its parent `DirectoryNode` references), giving structural
  sharing: two actions with 99% identical input trees share almost every
  `Directory`/`FileNode` blob in the CAS, and re-verifying "did anything change"
  is an `O(depth)` digest comparison rather than a full tree walk.
- **`Command { arguments, environment_variables (must be lexicographically
  sorted by name — canonical form again), output_paths, working_directory,
  platform }`** — literally "argv plus env plus declared outputs," the same
  three ingredients ccache/buildcache/sccache all hash, just formalized as a
  first-class addressable message rather than an ad hoc string concatenation.
- **`Action { command_digest, input_root_digest, timeout, do_not_cache, salt }`**
  — the actual cache **key** is the `Digest` of this message. `do_not_cache`
  (bool) is REAPI's direct analogue of ccache's uncacheable-invocation bypass
  list — a first-class, protocol-level "this one must not be memoized" bit
  rather than an implicit convention. `salt` is a clean, protocol-native
  namespace-separator for "same inputs, but a caller wants a distinct cache
  partition" — arguably cleaner than ccache's directory-based
  `$CCACHE_DIR`-per-namespace convention.
- **`ActionResult { output_files, output_directories, exit_code, stdout_raw /
  stdout_digest, stderr_raw / stderr_digest }`** — the cached *value*. Note
  stdout/stderr get the same "small enough, inline the bytes; otherwise, store
  as its own CAS blob and reference by digest" treatment as any other output —
  a clean, uniform answer to the "cache stdout/stderr alongside the object"
  problem every one of ccache/sccache/buildcache solves with bespoke,
  tool-specific logic (a `.entry` metadata file, a manifest field, etc).
- **`ActionCache` service**: `GetActionResult(action_digest) -> ActionResult`
  (NOT_FOUND on miss) and `UpdateActionResult(action_digest, ActionResult)`.
  The spec requires the client to have **already uploaded the `Action` message
  itself to CAS** before calling `UpdateActionResult`, specifically so a server
  can do access control / provenance checks based on what was actually run,
  not just trust a bare result blob — a deliberate anti-cache-poisoning design
  choice worth naming explicitly for api-cache's own remote-write path.

**Design takeaway**: REAPI's genuinely novel contribution over every wrapper
tool in this survey is making the **input tree itself** a first-class,
structurally-shared, digest-addressed Merkle structure, rather than a flat hash
folded from a file list. That is what lets REAPI-based systems (Bazel, Buck2,
and REAPI-speaking remote caches generally) reuse CAS blobs across wildly
different actions with overlapping inputs, at a granularity none of
ccache/sccache/buildcache attempt (they hash "the manifest of includes for
this one compile," not "a canonical shared tree every action's input root is a
pointer into").

## bazel-remote (the reference REAPI cache server implementation)

**License: Apache-2.0.** Repo: `buchgr/bazel-remote`. Speaks **both** HTTP/1.1
(a simpler REST-shaped subset) and gRPC (the full REAPI ActionCache + CAS +
Capabilities services, plus partial Byte Stream and an experimental Remote
Asset API).

- **On-disk layout**: separate `cas/` (content-addressed blobs, keyed by their
  hash) and `ac/`/`ac.v2/` (action-cache entries, keyed by the 64-hex-char
  action digest) trees, each internally sharded for the same "don't put a
  million files in one flat directory" reason every tool in this survey
  arrives at independently.
- **HTTP endpoints**: `GET`/`PUT`/`HEAD` on `/cas/<hash>` and `/ac/<key>` (each
  optionally prefixed with an `<instance>` name for multi-tenant namespacing),
  `GET /status` for size/count/uptime metrics. GET/PUT/HEAD-on-a-flat-key-space
  is the same minimal REST shape ccache's own `http://` remote-storage backend
  and buildcache's HTTP provider both independently converge on.
- **Eviction**: pure size-bounded LRU, "delete least recently used" once over
  budget — the same posture as ccache's cleanup, buildcache's local-cache
  eviction, and go-s3-server's own eviction design.
- **Compression**: zstd on CAS blobs by default, negotiated with clients that
  support compressed transfer — again, the same codec choice ccache defaults to.
- **Multi-backend / proxying**: bazel-remote can itself proxy through to S3 or
  S3-compatible (MinIO), GCS, experimental Azure Blob, a generic HTTP backend,
  or another gRPC cache — the same "local cache in front of pluggable remote
  backend(s)" layering every tool in this survey lands on.

## Gradle Build Cache (HTTP protocol)

Gradle's own build-cache protocol is the simplest of the bunch:
`GET <url>/<cache-key>` returns the cached entry body with any 2xx status, or
`404` on a miss; `PUT <url>/<cache-key>` stores it, any 2xx on success, `413` if
the payload is rejected as too large. Redirects on a PUT must be `307`/`308`
specifically (the only codes that preserve the request method+body on
redirect — `301`/`302`/`303` would silently turn a PUT into a GET at the
redirect target, corrupting the protocol). Gradle ships an official
containerized reference implementation, `gradle/build-cache-node`
(`docker run ... gradle/build-cache-node`), i.e. a batteries-included server a
team can stand up without writing one, the same role go-s3-server plays for
go-toolchain's own protocol.

**Design takeaway**: Gradle's protocol is deliberately as close to "a plain
HTTP key-value blob store" as a remote cache protocol can get — no batching, no
Merkle tree, no manifest of secondary files. It works because Gradle's own task
model has already flattened "what varies for this task" into one opaque cache
key *before* the network protocol ever gets involved; all the hashing
complexity lives client-side in Gradle itself, not in the wire protocol. This
is the opposite end of the spectrum from REAPI (protocol carries structure) and
worth naming as a real, viable design point: push all cache-key complexity into
the client/spec layer, keep the wire protocol to bare GET/PUT.

## Nx remote cache (self-hosted protocol, since Nx 19.8)

An openly specified HTTP protocol (an OpenAPI spec Nx publishes), activated
client-side via two env vars: `NX_SELF_HOSTED_REMOTE_CACHE_SERVER` (the
server's own URL) and `NX_SELF_HOSTED_REMOTE_CACHE_ACCESS_TOKEN` (a bearer
token). Nx computes a task hash locally from a task's declared inputs; on a
local miss it asks the configured server for that hash, downloads and replays a
tar of the stored outputs on a hit, uploads a fresh tar on a miss. Content-
addressed by the task hash, so nothing is ever overwritten — matching the
"write-once" posture go-s3-server's own `write_once` config option encodes as a
first-class server behavior rather than an implicit convention. Independent
open-source self-hosted implementations exist
(`IKatsuba/nx-cache-server`, a Deno-based server implementing this same spec) —
evidence the protocol is genuinely simple enough to reimplement from the public
OpenAPI document alone, the same bar api-cache's own remote protocol should
probably clear.

## Turborepo remote cache (Vercel's open protocol, "v8" endpoints)

CLI issues `GET`/`PUT`/`HEAD /v8/artifacts/:hash` with a bearer token, plus a
`POST` "artifact existence" batch-query endpoint (check many hashes in one
round trip rather than one HEAD per hash — the same batching motivation behind
go-s3-server's own `/_batch/get`), and a `POST /v8/artifacts/events` analytics
endpoint. All Turborepo versions stay compatible with the same `v8` surface
(the version number in the path is protocol-generation, not tied to the CLI's
own release number). **Signing**: when `remoteCache.signature: true` is set
(`turbo.json`) plus `TURBO_REMOTE_CACHE_SIGNATURE_KEY` is exported, the client
computes an HMAC-SHA256 over the artifact bytes with that shared secret and
sends it as an `x-artifact-tag` header on upload; on download it recomputes the
HMAC and refuses any artifact whose tag doesn't verify. This is a clean,
protocol-level answer to "how does a client trust a remote cache wasn't
tampered with / didn't silently corrupt an entry" that none of
ccache/sccache/buildcache implement natively (they rely on transport-level TLS
plus, at best, the stored content's own build-determinism to self-check) —
worth strongly considering for api-cache's own remote protocol, especially
combined with REAPI's "must upload the Action before the ActionResult"
provenance-binding idea.

## Cargo's own build cache — no native remote cache (deliberate)

Cargo (the tool, not any of the wrappers above) has **no built-in remote build
cache**. `target/` is Cargo's own local incremental-build cache, and every
remote-caching story for Rust (sccache, cachepot) exists entirely *outside*
Cargo, wired in via `RUSTC_WRAPPER`/`build.rustc-wrapper`. This is a deliberate
scope boundary worth naming: Cargo treats "cache my own incremental build
state" and "share compiled-artifact cache across machines" as two different
concerns solved by two different layers (Cargo itself vs. a wrapper it
delegates to) — directly mirroring api-dsl's own "engine mechanism has no
consumer vocabulary" split, and the same shape api-cache should probably keep:
a generalized cache **engine**, invoked via a wrapper hook, never itself a
build system with opinions about incremental state.

## `GOCACHEPROG` (Go 1.24+, `cmd/go/internal/cacheprog`)

Go's own build cache is normally a purely local, content-addressed disk cache
under `$GOCACHE` (default `$HOME/.cache/go-build` or the OS equivalent) —
before 1.24 there was no protocol at all, a CI runner wanting a *shared* Go
build cache had to save/restore that whole directory as one opaque tarball
(what depot.dev's own writeup calls "coarse-grained": "the restore and save
could take longer than the build itself," because every file, changed or not,
round-trips). `GOCACHEPROG=<program>` names an external program the `go`
command spawns as a long-lived subprocess and speaks a **newline-delimited
JSON ("JSON Lines") protocol** to over its stdin/stdout — the same
one-object-per-line shape REAPI's Byte Stream API and Nx's tar-based protocol
both avoid needing, because Go's objects here are small enough that a JSON
line per request/response is cheap enough.

**Protocol shape** (`Request`/`Response`, both carry an `ID` that the response
must echo back for correlation, matching whichever in-flight request it
answers — Go can pipeline multiple outstanding requests over the one
subprocess):

- Handshake: the subprocess's very first `Response` has `ID: 0` and a
  `KnownCommands` array (e.g. `["get","put","close"]`) — this is how the
  protocol evolves without breaking older cache programs: the `go` command
  only issues commands the subprocess actually declared support for.
- **`get`**: `Request{ID, Command:"get", ActionID}` → either
  `Response{ID, Miss:true}` on a miss, or `Response{ID, OutputID, Size,
  Time, DiskPath}` on a hit — critically, **the cache program does not stream
  bytes back over the JSON channel itself**; it hands back a `DiskPath`, a
  path to a local file the `go` command then reads directly. The actual bytes
  therefore never have to be base64'd through JSON at all on the read side —
  only staged onto local disk by whatever mechanism the cache program prefers
  (itself fetched from a remote store, decompressed, whatever), which is a
  materially different design from every HTTP-based protocol in this survey.
- **`put`**: `Request{ID, Command:"put", ActionID, OutputID, BodySize}`
  followed by the raw body bytes on the following protocol lines (the actual
  wire format streams the body immediately after the JSON header line, not
  base64-inline within the JSON) — Go asks the program to persist both
  `ActionID` (the lookup key) **and** `OutputID` (content hash of the bytes) so
  future `get`s can be served without recomputing anything.
- **`close`**: a clean-shutdown signal; the subprocess should flush/finish any
  outstanding writes before exiting.

**ActionID vs OutputID, explicitly**: `ActionID` is computed by the `go`
command itself from "the inputs to a build action" (Go version, GOOS/GOARCH,
compiler flags, source file hashes, etc) — it is the *lookup key*. `OutputID`
is separately the SHA-256 of the actual produced bytes — the *content hash*.
This split is the same idea REAPI expresses as `Action` (→ digest = cache key)
vs. the content each `Digest` in an `ActionResult` addresses, and the same idea
every wrapper tool in this survey conflates informally (ccache's "hash" is
functionally an ActionID; the object file bytes on disk are an implicit,
unnamed OutputID). Making the two **explicitly named, separately-typed
protocol fields** — rather than one opaque "the hash" — is the single cleanest
idea in the whole GOCACHEPROG design and directly worth adopting: it is what
lets a cache implementation deduplicate identical *content* produced by two
different (ActionID) invocations, something none of ccache/sccache/buildcache's
single-hash models can express.

**Supplement, not replacement**: `GOCACHEPROG` sits in front of, not instead
of, the local on-disk cache — a hit still lands as a real file at `DiskPath` on
local disk that the toolchain reads normally; the external program's job is
just deciding *what's in the cache* and staging bytes onto disk when asked, with
freedom to also mirror to/from a remote store in the background (exactly what
this org's own `go-s3-server` + `cacheclient` pairing implements: the client
module is consumed in-process by "gosmopolitan's `cmd/go`," per
`go-s3-server/CLAUDE.md`, precisely playing the GOCACHEPROG-subprocess role
this protocol defines, batching/prefetching over HTTP behind that one local
`DiskPath` handoff). **Failure posture**: a cache-program error does not fail
the build — the `go` command logs it and falls through to executing the action
uncached, the same "cache is best-effort, never load-bearing for correctness"
posture sccache's `SCCACHE_IGNORE_SERVER_IO_ERROR` opts into explicitly and
ccache/buildcache both implicitly share (a cache miss is always safe; a cache
*outage* must never be a build failure).

## `nocache` — not actually build-cache prior art

Flagged in the brief by name, but `Feh/nocache` (and its forks) is an unrelated
Linux utility: it wraps a command and calls `posix_fadvise(POSIX_FADV_DONTNEED)`
around its `open`/`close` syscalls purely to keep that command's I/O from
evicting *other* processes' pages from the OS page cache (a backup-job-friendly
tool, not a build cache). No design lessons apply here beyond noting the name
collision so nobody chases it further.

## Sources

- clcache: https://github.com/frerich/clcache , https://github.com/Nuitka/clcache
- cachepot: https://github.com/paritytech/cachepot , https://blog.mozilla.org/ted/2016/11/21/sccache-mozillas-distributed-compiler-cache-now-written-in-rust/
- distcc: https://github.com/distcc/distcc
- icecream: https://github.com/icecc/icecream , https://linux.die.net/man/7/icecream
- REAPI proto: https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/execution/v2/remote_execution.proto
- bazel-remote: https://github.com/buchgr/bazel-remote
- Gradle build cache: https://docs.gradle.org/current/userguide/build_cache.html , https://docs.gradle.org/current/dsl/org.gradle.caching.http.HttpBuildCache.html
- Nx self-hosted cache: https://nx.dev/docs/kb/self-hosted-caching , https://github.com/IKatsuba/nx-cache-server
- Turborepo remote cache: https://turborepo.dev/docs/core-concepts/remote-caching
- GOCACHEPROG: https://pkg.go.dev/cmd/go/internal/cacheprog , https://depot.dev/blog/go-remote-cache
- nocache: https://github.com/Feh/nocache
