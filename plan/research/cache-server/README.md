# Research: go-s3-server as api-cache's remote tier

Findings on `/home/user/go-s3-server` — the org's Go build-cache server and its
`cacheclient/` module — read as reference material for api-cache's remote tier.
Everything is cited `file:line` against that tree. go-s3-server is evaluated on
merit, not as a mandate; api-cache is clean-slate and owes its conventions
nothing.

## Files

| File | Contents |
|---|---|
| [wire-protocol.md](wire-protocol.md) | Every endpoint: routing, auth, error codes, the GBCI v1 blob byte layout, `/_batch/get` JSON + tar, `/_batch/put` tar + JSON results, headers, admission control, the stall guard. Per-item verdict: generic vs Go-shaped. Plus what the protocol lacks. |
| [cacheclient.md](cacheclient.md) | The client module's public API, the index-driven known-key / skip-re-upload protocol, the GET and PUT coalescers, the look-ahead pool and its byte budget, resilience and backoff, the Logger seam, dependency licences, and a reuse verdict per file. |
| [storage.md](storage.md) | Two-level sharding, the `user.s3.*` / `user.s3audit.*` xattr split and the ext4 EA-block limit, `PutStream`, write_once, the four openers, `compactKey`, the two memo caches, atime probing, two-walk LRU eviction, cache-version purge, Windows sidecars — and what is missing for a **multi-output** compile entry. |
| [index-and-prefetch.md](index-and-prefetch.md) | The in-memory index, ETag purity, pending buffers, `NearbyKeys` by mtime, the build-scoped prefetch tracker — and a direct answer on whether a downloadable key index or mtime prefetch is worth anything to a ccache-style build. |
| [ops.md](ops.md) | Config JSON schema and defaults, every `s3_*`/`cache_*` metric, the two log modes, the memory controller, the dashboard, deployment and drain, dats suites and CI. |
| [generalization.md](generalization.md) | The candid assessment: options (a) reuse as-is, (b) extend with a namespace, (c) new server sharing code; the exact functions that assume Go; and whether the remote tier could also speak Bazel's and ccache's HTTP protocols. |

## Summary (25 lines)

go-s3-server serves a native, non-S3 HTTP protocol on `/{bucket}/{key}` with
Basic auth and plain-text errors (`X-Cache-Error-Code`). Four things make it
more than a blob store: `/_index` (a 24-byte-header + sorted-32-byte-hashes +
SHA-256-trailer blob listing every key), `/_batch/get` (JSON key list in, tar of
`manifest.json` + `data/<key>` out, with optional mtime-proximity prefetch),
`/_batch/put` (the same tar shape inbound, JSON per-key results back), and a
client module that coalesces both directions.

Its operational core is strong and protocol-agnostic: admission control that
sheds with 503 + Retry-After rather than queueing to an OOM; an inactivity stall
guard instead of whole-request deadlines (a total cap measures size, not
health); a streaming store with an 8 MiB fsync threshold and
metadata-onto-the-temp-inode-before-rename; a two-walk LRU eviction sweep that
never lists the cache and probes the real data_dir for atime support; byte-
bounded caches under a shrink/grow memory controller that "holds less, never
serves less"; and an access log that prints one aggregated line per active
second rather than one per request. The client's retry policy, full-jitter
backoff, Retry-After handling, stall watchdog and graceful downgrade on a
404/405 from a batch endpoint are equally reusable.

The Go-specific parts are small and localized: the key grammar
`go-buildcache/v1<64 hex>` (which the GBCI index format hard-codes), the
`outputid` metadata meaning `sha256(decompressed body)`, the Go module-index
guard, and the client's `ar`/`__.PKGDEF` build-id guard. Two hazards for a
generalized namespace: the module-index **PUT** guard is unscoped, so it
decompress-probes every upload on any key and can silently drop one with a 200;
and a non-conforming key is never advertised in `/_index`, so a client trusting
an authoritative index misses every time.

The biggest structural gap is the entry model: one key, one opaque blob, one
flat metadata map — with metadata living in xattrs that share a ~4 KiB ext4 EA
block. A compile produces `.o` + `.d` + stderr + exit status. Packing them
client-side (ccache's result file) needs **no server change at all**; splitting
them across keys needs an atomic grouping primitive the store does not have.

Recommendation: take the infrastructure, leave the protocol. Shape api-cache's
wire surface as `METHOD /<namespace>/<digest>` so a stock Bazel HTTP cache
client or a stock ccache HTTP backend can point at it for near-zero cost (they
need only bearer auth added), and layer the batch endpoints on as a negotiated
extension. Treat a downloadable key index as optional: a ccache-style build
computes every key independently and up front, so the dependency-ordered
critical path the index and look-ahead pool exist to hide does not exist here.

**Licence note:** go-s3-server ships no LICENSE file. api-cache's is MIT.
