# 05 — The remote tier

The protocol, the server, the client, the upload policy, interop with the caches people already run, and safety. Evidence: `plan/research/cache-server/` and `plan/research/storage-protocol/remote-protocols.md`, `consistency-and-safety.md`.

## The shape

The remote tier is a keyed blob store whose values are the same binpazer entries the local store holds. A hit is one round trip. There is no AC/CAS split (`remote-protocols.md`, "AC/CAS"): it would buy dedupe of the `.d` and stderr, which are small, at the cost of two round trips per hit and a dangling-reference eviction problem no compiler cache needs. The two properties that matter, "one round trip per hit" and "never upload what the server has", come from a container value plus batching plus an existence probe.

```
GET|PUT|HEAD|DELETE  /<namespace>/<hex digest>        one entry
POST                 /_batch/exists                  JSON keys in, bitmap out
POST                 /_batch/get                     JSON keys in, tar of entries out
PUT                  /_batch/put                     tar of entries in, per-key JSON results out
GET                  /_health  /_version             unauthenticated probes
```

Namespaces are `r` (results) and `m` (manifests), plus the interop prefixes below. The path shape `METHOD /<namespace>/<digest>` is deliberate: a stock Bazel HTTP client, a stock ccache with `layout=bazel`, a Gradle client and a Turborepo client are each a prefix and a header convention away (`generalization.md` §5).

**Errors** are go-s3-server's: `Content-Type: text/plain`, a `<code>: <message>` body, and an `X-Cache-Error-Code` header from a closed set (`not_found`, `access_denied`, `overloaded`, `conflict`, `too_large`, `method_not_allowed`, `invalid_request`, `internal_error`, `read_only`). Every code is generic already.

**Auth** is bearer token first, HTTP Basic second, and each credential carries a `read`, `write` or `admin` class. A read-only credential is what a developer gets; CI gets write. go-s3-server has no read-only class and the survey names that as its one gap for this use.

**Batch endpoints** are negotiated: a client that gets 404 or 405 from `/_batch/*` downgrades to single requests and remembers, which is `cacheclient`'s sticky-downgrade pattern.

## What replaces the known-key index

go-s3-server's `/_index` is its most valuable idea for a Go build and probably not worth it here (`plan/research/cache-server/index-and-prefetch.md` §5): a C++ build computes every key independently and up front, so the dependency-ordered critical path the index hides does not exist, and a two-namespace compiler cache would double a blob that is already tens of megabytes. The replacement:

- **`POST /_batch/exists`**: up to 4,096 keys in, a bitmap out. A build offering 5,000 entries issues ~40 such requests of a few kilobytes each instead of downloading 32 MB.
- **A Bloom filter as a later optimisation**: ~1.2 MB per million keys at 1% false positives, where a false positive costs one wasted probe. Recorded in `12-decisions.md`, not built first.

The prefetch-by-mtime heuristic is kept as a server option because it helps a serial build and the cold-start window, but the client prefers a build-graph-derived key list when one exists (`compile_commands.json`, a ninja graph): the wrapper can compute every key of a build at once and issue one probe and one batch fetch. That is `api-cache warm` in `08-cli-and-ops.md`.

## Upload policy: a spool, not a daemon

A wrapper is one short process, and a synchronous PUT on every miss puts the network on the compile's critical path. sccache solves it with a daemon; ccache pays synchronously. The plan's answer needs no long-lived process:

1. On a miss, after the local store has the entry, the wrapper appends the result key to `<dir>/spool/` as a tiny file.
2. Every wrapper invocation, hit or miss, drains up to N spooled uploads after its own work is done and its exit code is decided, with a short time budget, as a `/_batch/put` of the entries the spool names. The compile's own latency is unaffected because the drain happens after the outputs are restored and the streams replayed; the process simply exits a little later. `N` and the budget are store settings, defaulting to 8 entries and 200 ms.
3. `api-cache flush` drains everything, and is what a CI job runs at the end. A CMake or ninja build does not need it; the opportunistic drain keeps the spool short.
4. A spool entry older than the store's `max-age` or whose result was evicted is dropped.

The remote's `write="ci-only"` setting makes the spool a no-op for a developer with a read credential, which is the "CI writes, developers read" pattern every surveyed tool converges on.

Reads stay synchronous with a tight budget: `probe` then `get`, 50 ms connect, 2 s operation, both configurable, and any failure is a miss. The remote is never load-bearing.

## The server

`api-cache serve --config <xml>`: a new server in this repository that lifts go-s3-server's operational core file by file and writes the protocol fresh, which is option (c) in `generalization.md` §4. Lifted: admission control with `503` and `Retry-After` instead of queueing; the stall guard (an inactivity watchdog instead of whole-request deadlines); `PutStream` with `.tmp-*` sweep; the two-walk LRU eviction and atime probe; the byte-bounded sharded LRU and the memory controller; the per-second aggregated access log; the health, version and pre-update probes; the drain on shutdown. Reimplemented: the entry model (a binpazer entry with metadata inside it, so no xattrs), the namespaces, auth classes, the exists probe, and the interop mux. Not carried: the GBCI index, `compactKey`, the module-index guard (a Go poison guard that decompress-probes every PUT and can silently drop a non-Go blob with a 200), the outputid self-heal, the S3 shims.

Storage on the server is the same local-store package, so the server and the wrapper share one entry reader and one eviction sweeper.

**Content-equal check on PUT** (`write_once` with `notification=content_differs`, `action=allow`): a PUT to an existing key streams-compares the bodies; equal is idempotent, different is stored and logged with both provenances. At 26 to 53 µs per duplicate it is the cheapest key-bug detector available and it is on by default. A deployment can set `action=deny` to make the second writer lose.

**Provenance** is written server-side into the entry's directory block on receipt (uploader, IP, time, user agent) in a field the GET path strips before serving, so an uploader's identity never reaches a downloader.

**Metrics**: Prometheus, the go-s3-server set with the `s3_` prefix dropped: requests by route and outcome, in-flight and rejected, batch keys by kind, cache bytes and entries per namespace, evictions, conflicts, exists-probe hit rate, memory.

## Interop mux

Served on the same blob store, each dialect a prefix and a few header rules (`remote-protocols.md`, "Can one server speak several"):

| Client | Prefix | Notes |
|---|---|---|
| Bazel, Buck2 HTTP cache | `/ac/<sha256>`, `/cas/<sha256>` | `/cas/` bodies are verified against their digest on PUT; `/ac/` bodies are opaque. `Accept-Encoding: zstd` honoured. |
| ccache `layout=bazel` | same as Bazel | bearer token from the `bearer-token=` attribute |
| ccache `layout=flat`, `layout=subdirs` | `/ccache/<key>` and `/ccache/<2hex>/<rest>` | `DELETE` supported for its cleanup |
| Gradle | `/gradle/<key>` | `413` is a non-error for the client; the server sends it above the size cap |
| Turborepo | `/v8/artifacts/<hash>` | `HEAD` exists; `x-artifact-*` headers stored as metadata; `teamId`/`slug` ignored |
| REAPI gRPC | not a prefix | a second front end; deferred to a later phase and listed in `12-decisions.md` |

The point is not that api-cache's wrapper will use these; it is that a team can point the tools it already runs at one server, and migrate one tool at a time.

A `ccache-storage-apicache` helper (ccache's out-of-process storage-helper protocol over a Unix socket, ~200 lines) is a cheap extra that reaches stock ccache with connection reuse across a build. Deferred, listed.

## Safety

The surveyed tools are unanimous: a remote cache is trusted, and anyone who can write to it can execute code on every machine that reads from it (`consistency-and-safety.md`, "Poisoning"). The controls, in the order they matter:

1. Read and write credential classes, with write reserved for CI. This is the control.
2. A namespace and format version in every key, so a bad generation can be evicted wholesale with `api-cache serve evict --namespace`.
3. Integrity on every read: CRC-32C per block before decode, on the server and in the client.
4. Provenance written server-side, unreadable client-side.
5. The content-equal diagnostic above.
6. Roles, not paths, in the entry directory, so a hostile entry cannot direct a restore outside the invocation's own output paths.

Signing (Turborepo's HMAC tag) is listed as a later option; with one shared secret it authenticates little.

A stale existence answer must only ever cost work: a 404 on a key the probe said existed is an ordinary miss, and a PUT of something already present is idempotent.

## Client

The wrapper's remote client lifts from `cacheclient` what is generic (`plan/research/cache-server/cacheclient.md` §10): the retry policy with full-jitter backoff and `Retry-After`, the stall watchdog, error coalescing, the tar batch builder and reader, the sticky batch downgrade, the claim-and-rollback bookkeeping for uploads, and the magic-byte codec dispatch. Not lifted: the GBCI index client, the build-id and module-index guards, the Go export-data parser, the `GO_BUILDCACHE_CONFIG` contract.

The HTTP layer itself is decision 6 in `12-decisions.md`: net/http's package init is a measured 2.2 to 2.7 ms per exec on Windows and macOS, which is more than the whole Linux hit path, so the wrapper either hand-rolls HTTP/1.1 over `net` (if `net` alone is cheap, to be measured) or moves remote I/O into the spool drain and a companion process.

## Settings

```xml
<remote name= url= read="true|false" write="always|ci-only|never" token-env= basic-env=
        connect-timeout="50ms" operation-timeout="2s" batch="auto|off" probe="auto|off"
        compress="zstd:1" spool-drain="8" spool-budget="200ms"/>
```

Several `<remote>` elements form a chain read in order and written to all with `write` set; the ccache `shards=` rendezvous idea is listed as later.
