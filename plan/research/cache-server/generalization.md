# Candid assessment: how much of go-s3-server can api-cache's remote tier be?

api-cache is clean-slate. go-s3-server is **reference material and a reuse
candidate**, nothing more — no org convention (go-toolchain, fat-APE
autorelease, buildhost, dats, the `s3_` metric prefix) is a requirement here.
What follows judges it on merit only.

## Summary judgment

The **operational core is excellent and mostly generic**; the **protocol is
half-generic**; the **Go-specific parts are small, sharply localized, and one of
them is actively dangerous for non-Go blobs**.

Concretely:
- ~25 files and ~5,000 lines are protocol-agnostic infrastructure (admission
  control, stall guard, streaming store, LRU eviction, memory controller,
  metrics, log aggregation, batch framing).
- ~6 files and ~1,200 lines encode GOCACHEPROG semantics.
- The batch endpoints and the client's coalescers/resilience are the most
  valuable things in the repo and would take real effort to re-derive.
- The GBCI index, the module-index guard, and the build-id guard are the parts
  api-cache should **not** inherit.

The single biggest structural gap is that this store is **one key → one opaque
blob**, and a compile is a multi-output action. That is solvable client-side
(pack into one blob, ccache-style), but it is a decision, not a detail.

## 1. The exact Go-cache assumptions, by file and line

### Server

| File:line | Symbol | What it assumes |
|---|---|---|
| `index.go:20` | `gbciKeyPrefix = "go-buildcache/v1"` | the literal key prefix |
| `index.go:27` | `gbciHashSize = 32` | fixed 32-byte keys, baked into the wire format |
| `index.go:117-131` | `extractActionHash` | `^go-buildcache/v1[0-9a-f]{64}$` |
| `index.go` `Blob()` | GBCI serialization | fixed-width entries, no key strings |
| `compactkey.go:355-379` | `compactKey` | hash inline, `raw` fallback; the memory win is 32-byte-key-only |
| `cleanmemo.go:31,63-70` | `cleanKey`, `forgetClean` | keyed by action hash |
| `selfheal.go:17` | `outputIDMetaKey = "outputid"` | GOCACHEPROG naming |
| `selfheal.go:56-96` | `ensureOutputID` | scoped at `:67` via `extractActionHash` |
| `selfheal.go:98-183` | `reconstructOutputID` | `outputID == sha256(decompressed body)`; refuses a body with no codec frame (`:143-149`) |
| `modindex.go:17` | `goModuleIndexMagic = "go index v"` | pure Go |
| `modindex.go:87` | `looksLikeGoModuleIndex` | **called UNSCOPED on every PUT** |
| `modindex.go:146` | `readIsModuleIndex` | |
| `modindex.go:268,316` | `evictModuleIndexOnRead{,ByKey}` | scoped to cacheprog keys |
| `lz4head.go` | whole file (148 lines) | an lz4-frame literal-run walk existing only to make the module-index probe cheap |
| `handlers.go:36-41` | `absentKeyOutcome` | uses `extractActionHash` |
| `handlers.go:279-299` | the PUT peek + refusal inside `storeOneObject` | see §2 |
| `handlers.go:343-364` | `objectLabel` | `object-type`/`pkg`/`src`/`go-version`/`target` |
| `logagg.go:332-347` | `projectOf` | Go module paths |
| `logagg.go:349-365` | `rawSizeOf` | `body-size` metadata key |
| `storage_unix.go:32` | `metadataProtectedKeys = {"outputid","compression"}` | protocol-load-bearing keys |
| `cacheversion.go` | v3 purge | existed to remove module-index poison |
| `server.go:280` | `bucket != s.config.Bucket` | one fixed namespace, equality-checked |

### Client

| File:line | Symbol |
|---|---|
| `web_index.go:32,36,45,59,279,342` | `gbciKeyPrefix`, `hashSize=32`, `actionHash`, `parseActionHash`, `parseIndexBlob`, `decodeActionHash` |
| `web.go:211-214,338-344` | prefix default `"go-buildcache/"`, `key()`, `KeyPrefix()` |
| `buildid.go` | whole file — `ar`/`__.PKGDEF`/`build id "ACTION/CONTENT"` |
| `modindex.go` | whole file |
| `archive.go` | whole file, 337 lines — Go export-data / pkgbits parsing, purely for log-label metadata |
| `webput.go:105-122` | the two publish guards |
| `webput.go:139-161` | the Go metadata map |
| `batch.go:371-415` | `verify` — build-id and module-index gates |
| `config.go` | the `GO_BUILDCACHE_CONFIG` env contract |

Everything **not** in those two tables is generic.

## 2. Option (a): use go-s3-server as-is with a key-namespace prefix

Put api-cache's keys under e.g. `api-cache/v1/<hash>` in the same bucket, or a
second bucket on a second process.

**What works unchanged:**
- Routing, auth, admission control, stall guard, drain, health/version probes.
- `keyToPath` — `api-cache/v1/<hex>` is all safe characters, so it shards to
  `{dataDir}/api-cache/v1/<ab>/<cd>/<rest>` naturally.
- `PutStream`, `Open`, `Stat`, `Delete`, `Walk`, write_once, audit xattrs.
- Eviction (LRU by last use) — it walks the whole data_dir and does not care
  about key shape.
- `/_batch/put` and `/_batch/get` — both are key-agnostic in their framing.
- All metrics and the dashboard.

**What silently degrades:**

1. **`/_index` advertises nothing.** `extractActionHash` fails, so the key never
   reaches `hashes` (`index.go:167-170`). A client asking for the index gets a
   valid blob that omits every api-cache key. If the client then treats an
   authoritative index as proof of absence — which `cacheclient` does
   (`web.go:383-391`) — **every lookup is a fast miss and the cache never
   hits.** This is not a degradation, it is a total failure, and it is silent.
   Mitigation: the client must not consult the index for non-Go keys.

2. **The outputid self-heal never fires.** Also scoped (`selfheal.go:67`). Not a
   problem — it is a repair for a Go-specific wedge — but it means
   `s3_self_heal_*` are dead metrics in this mode.

3. **The module-index *read* guards never fire.** Scoped (`modindex.go:268,316`).
   Good: a non-Go blob is never inspected or evicted on read.

4. **The module-index *PUT* guard DOES fire, on every PUT, unscoped.**
   `storeOneObject` (`handlers.go:279-299`) reads up to 1 MiB of the body,
   decompresses the first frame, and prefix-matches `go index v` — **for any key
   whatsoever**. `docs/module-index-guard.md` confirms: "the unscoped
   peek-and-refuse — any upload whose first block decodes to the magic is
   dropped (200, stored nothing) on any key."

   Two consequences:
   - **A correctness hazard.** Any api-cache blob whose decompressed bytes begin
     `go index v` is accepted with **200** and stored **nowhere**. The client
     believes it uploaded. Every later fetch misses. Probability is low (a
     result file starts with its own magic), but the failure mode is a silent
     permanent miss, which is the worst kind.
   - **A cost.** The peek + decompress runs on **every** PUT. The known-clean
     memo only helps *read* paths and only for cacheprog keys
     (`cleanmemo.go:63-70`), so a non-Go PUT pays it in full, forever. The repo's
     own history says this path has twice caused GC thrash that saturated
     admission control (`handlers.go:262-270`, `modindex.go:100-115`).

5. **The bucket is not a namespace.** `server.go:280` is a string equality check
   against one configured value. Sharing a process means sharing the bucket
   string; separating means a second process and a second data_dir. There is no
   per-namespace policy (eviction budget, write_once, auth).

6. **`compactKey` degenerates.** A non-conforming key keeps its `raw string`
   (`compactkey.go:360-365`), so the index's whole memory argument evaporates —
   back to one heap string per object.

**Verdict on (a): workable only as a stopgap, and only with the client never
touching `/_index` and a deliberate acceptance of the unscoped PUT guard.** It
would prove the shape quickly; it is not a destination.

## 3. Option (b): extend go-s3-server with a generic namespace

The changes, in rough order of effort:

1. **Make the key grammar configurable.** Replace `gbciKeyPrefix` +
   `extractActionHash` with a small per-namespace descriptor: `{prefix, hashHex
   bool, hashBytes int}`. `compactKey`, `cleanmemo`, `selfheal` and
   `absentKeyOutcome` all route through `extractActionHash`, so this is one
   chokepoint — genuinely small.
2. **Scope the PUT module-index guard** to the Go namespace. One `if` in
   `storeOneObject`. This is a bug fix regardless of api-cache.
3. **Generalize the index.** Either per-namespace GBCI blobs (each still
   fixed-width, so the format survives) or accept that non-Go namespaces have
   no index and give them a cheap **existence-probe endpoint** instead (see
   index-and-prefetch.md §5 — this is probably better anyway).
4. **Rename `outputid` → a namespace-declared content-address field.** The
   *semantics* (sha256 of the decompressed body) are already generic; only the
   name and the `metadataProtectedKeys` set are Go-flavoured.
5. **Per-namespace config**: eviction share, write_once, max_object_bytes.
   Currently all global.
6. **Bearer auth** alongside basic (needed for interop, §5).

**Cost estimate:** 1–3 is a few hundred lines. 4 is a rename plus a config field.
5 is the real work — `Evict` derives one global cutoff from one global histogram,
so per-namespace budgets mean per-namespace scans, or a weighted single scan.

**Verdict on (b): the best value-for-effort path *if* go-s3-server is a repo
api-cache is willing to depend on and co-evolve with.** It keeps the batch
endpoints, the eviction sweeper, the memory controller and the ops surface —
all of which are expensive to rebuild and boring to get right.

**The honest counter-argument:** the repo carries a lot of history api-cache does
not need — an S3 compatibility shim, a `s3_`/`cache_` metric-prefix split, four
cache-version generations, and two guards for a poison that has nothing to do
with C++. Its CLAUDE.md is 38 KB. Adopting it means adopting that. And it is
slated for a rename it has not had.

## 4. Option (c): a new server in api-cache, sharing code

Extract the generic half into a library (or vendor it file-by-file) and write
the protocol fresh.

**Worth lifting nearly verbatim:**
- `stallguard.go` (78 lines) — inactivity watchdog instead of whole-request
  deadlines. Small, subtle, and exactly right for bulk transfers.
- `lrucache.go` (211) — byte-bounded sharded LRU with a runtime-settable budget.
- `memlimit.go` (368) — the shrink/grow controller, hysteresis and all.
- `eviction.go` (494) + `atime.go` (85) — two-walk LRU sweep, the `.last_sweep`
  marker, the atime **probe**, `evictOne`'s re-stat.
- `metacache.go` (99) — self-validating metadata cache.
- `logagg.go` (362) — the per-second aggregated access log.
- `storage.go`'s `PutStream`/`Open`/`OpenBody`/`openRaw`/`Walk` shape, including
  the fsync threshold and the metadata-before-rename ordering.
- Admission control (`server.go:246-255`) and the health/version/pre-update
  pre-gate (`server.go:165-203`).
- Client side: `web_resilience.go`, `httperrlog.go`, `counter.go`, `prep.go`,
  the coalescer loops, `compress.go`'s frame-magic codec dispatch.

**Worth reimplementing, not lifting:**
- The index. api-cache should decide between "no index + existence probe",
  "Bloom filter", and "per-namespace GBCI". The current one is over-fitted to
  `cmd/go`'s constraints.
- The guards. api-cache's equivalent question is "does this `.o` belong under
  this key?", and the honest answer for C/C++ is **nothing enforces it** — there
  is no build-id analogue. The content hash is the whole guarantee, which is
  also what ccache and Bazel rely on.
- The entry model, because of multi-output (storage.md §10).

**Verdict on (c): the cleanest result and the most work.** Roughly: reuse ~2,000
lines of infrastructure, write ~1,500 lines of new protocol and store logic.
Given api-cache is clean-slate and will want a declarative-XML config surface
that go-s3-server's JSON config does not have, **(c) is probably the right
answer, with (b) as the fallback if schedule pressure bites.**

A concrete middle path worth putting in front of the planner: **(c) for the
server, but import `cacheclient` unmodified as a *second*, Go-build-cache-only
backend** if api-cache ever wants to also serve go-toolchain. The client module
is already independent, already has its own `go.mod`, and already has a minimal
dependency list.

## 5. Interop: could api-cache's remote tier speak Bazel and ccache HTTP?

**Yes, and cheaply.** Both protocols are strictly simpler than this one.

### Bazel HTTP cache
- `GET|PUT|HEAD /ac/<64 lowercase hex>` — an `ActionResult` protobuf.
- `GET|PUT|HEAD /cas/<64 lowercase hex>` — a raw blob.
- Optional, ignored instance name: `/<instance>/ac/<key>`, `/<instance>/cas/<key>`.
- 200 hit, 404 miss, 2xx on PUT. Auth: basic, or `--remote_header: Authorization: Bearer …`.
- No batching over HTTP (batching lives in the gRPC REAPI:
  `FindMissingBlobs`, `BatchReadBlobs`, `BatchUpdateBlobs`).

### ccache HTTP storage
- `remote_storage = http://HOST[:PORT][/PATH]|<attrs>`.
- Methods: `GET`, `PUT`, `DELETE` (DELETE is used during cleanup).
- Layouts: `subdirs` (default) — `<url>/<key[:2]>/<key[2:]>`, 256 buckets;
  `flat` — `<url>/<key>`; **`bazel`** — Bazel's own `/ac/<64 hex>` layout, so a
  Bazel HTTP cache and a ccache can share one server.
- Auth: basic in the URL, or a `bearer-token=` attribute.
- Attributes: `connect-timeout` (100 ms default), `operation-timeout` (10 s),
  `keep-alive`, `read-only`, `layout`.
- The stored value is ccache's own **result** or **manifest** file, opaque to the
  backend.

### What go-s3-server already satisfies

Its routing is already `GET|PUT|HEAD|DELETE /{bucket}/{key…}` with the key being
everything after the first segment (`server.go:276-315`). So with `bucket` set to
whatever path segment the client is pointed at:

- ccache `layout=flat` → key `<40hex>R`. Safe characters, shards fine. ✅
- ccache `layout=subdirs` → key `ab/cdef…`. Slashes are safe; `shardPath` splits
  on the basename, so it lands at `{dataDir}/ab/cd/ef/…`. ✅
- ccache `layout=bazel` / Bazel → key `ac/<64hex>` or `cas/<64hex>`. ✅
- `HEAD` for existence — already implemented, Stat-only, non-mutating
  (`handlers.go:150-162`). ✅
- `DELETE` idempotent 204 — ccache cleanup works. ✅
- 404 on miss, 200 on hit, 200 on PUT. ✅

### What would have to change

| Gap | Effort |
|---|---|
| **Bearer token auth.** `authenticate` (`auth.go:118-160`) accepts `Basic ` only; anything else is 403. Bazel's `--remote_header` and ccache's `bearer-token` need it. | ~20 lines |
| **The unscoped PUT module-index guard** would decompress-probe every Bazel CAS blob and every ccache result file, and could silently drop one. Must be namespace-scoped. | ~5 lines |
| **Multi-namespace routing.** `ac/` and `cas/` are two namespaces with different semantics (one small and mutable-ish, one immutable and large). The bucket equality check has no room for that. | small, but see §3.5 |
| **PUT status codes.** ccache accepts 2xx; Bazel accepts 2xx. Server returns 200. Fine as-is. | none |
| **Content verification on `/cas/`.** Bazel's CAS key *is* the blob's digest, so the server could verify on PUT — a genuine safety win the current server does not do for arbitrary keys (it only self-heals cacheprog keys). | optional |
| **`Content-Type`.** Neither protocol requires one. | none |

**Verdict: speaking Bazel's HTTP cache protocol is nearly free** — it is a
strict subset of what this server already routes, plus bearer auth. Speaking
ccache's HTTP backend is the same work, since ccache's `layout=bazel` *is* the
Bazel layout and its other layouts are simpler still.

**This is a strong argument for keeping api-cache's native protocol close to
`METHOD /<namespace>/<hex digest>`** and layering the batch endpoints on top as
an *extension* that a capable client negotiates (the `cacheclient` already
downgrades to single GET/PUT on a 404 or 405 from a batch endpoint —
`batch.go:285-290`, `batchput.go`'s sticky `batchPutUnsupported`). That
downgrade pattern is exactly what lets one server serve a native api-cache
client, a stock ccache, and a stock Bazel at once.

## 6. What I would tell the planner, in one paragraph

Take the infrastructure and leave the protocol. go-s3-server's admission
control, stall guard, streaming store, two-walk LRU eviction with an atime probe,
byte-bounded caches under a memory controller, per-second aggregated access log,
and — above all — its **batch GET/PUT endpoints with client-side coalescing,
optimistic claim-and-rollback, and graceful downgrade** are hard-won and
directly applicable. Its **key model is not**: a 32-byte-hash-only index, an
unscoped Go-poison PUT guard, a one-key-one-blob entry, and a single fixed
bucket are all things a compiler-wrapper cache would have to work around rather
than build on. Design api-cache's wire surface as
`METHOD /<namespace>/<digest>` so a stock Bazel or ccache can point at it for
free, add the batch endpoints as a negotiated extension, decide **early**
whether a multi-output entry is packed client-side (ccache's result file — much
simpler, and what makes go-s3-server's store reusable as it stands) or split
across CAS digests (Bazel's model — better dedup, needs an indirection the store
does not have), and treat a downloadable key index as an optional optimization
that a wrapper cache probably does not need.

## Appendix: licence

`/home/user/go-s3-server` **has no LICENSE file** (`ls LICENSE*` → nothing).
`/home/user/api-cache/LICENSE:1` is MIT, and CLAUDE.md says the org's other
repos are MIT. Third-party licences in the dependency set: lz4 v4 **BSD-3-Clause**,
klauspost/compress **BSD-3-Clause** (with Apache-2.0 and Go-BSD components for
its vendored s2/snappy parts), testify **MIT**, cobra **Apache-2.0**,
prometheus/client_golang **Apache-2.0**, `wow-look-at-my/go-containers`
**unverified**. Any copy-in of go-s3-server code should get its licence pinned
first.

Sources for §5: [ccache 4.10 manual](https://ccache.dev/manual/4.10.html),
[Bazel remote caching](https://bazel.build/remote/caching),
[bazel-remote](https://github.com/buchgr/bazel-remote).
