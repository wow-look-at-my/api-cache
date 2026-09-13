# go-s3-server wire protocol

Every endpoint, header, body format and status code of the server at
`/home/user/go-s3-server`, with a verdict per item: **generic** (works for "any
action key -> any blob"), **Go-shaped** (assumes the GOCACHEPROG contract), or
**mixed**.

The protocol is *not* S3 despite the repo name. `CLAUDE.md` calls the remaining
S3 names "a deprecated compatibility shim"; only the `X-Amz-Meta-*` header
prefix, the `s3_` metric prefix, the `user.s3*` xattr prefix, the `bucket` path
segment and the binary name survive.

## 0. Licence and module facts

- **There is no `LICENSE` file in `/home/user/go-s3-server`.** `/home/user/api-cache/LICENSE:1`
  is MIT ("Copyright (c) 2026 wow, look at my code!"), and CLAUDE.md says the
  org's repos are MIT, but go-s3-server itself ships none. A planner that wants
  to vendor or fork it should get one added.
- Server module `github.com/wow-look-at-my/go-s3-server`, go 1.26 (`go.mod:1-3`).
  Deps: lz4 v4, klauspost/compress (zstd), prometheus client, cobra, testify,
  `wow-look-at-my/go-containers`, `golang.org/x/sys`.
- Client module is separate: `github.com/wow-look-at-my/go-s3-server/cacheclient`
  (`cacheclient/go.mod:1`), deps only lz4, klauspost/compress, go-containers,
  testify. Root `go.mod:17` has `replace ... => ./cacheclient`, so protocol and
  server change in one commit.

## 1. Request routing

All routing is one `switch` in `ServeHTTP` (`server.go:291-318`). There is no
mux, no path template. Path shape is `/{bucket}/{key...}`; the bucket is split
off at `server.go:276-284` and must equal `config.bucket` exactly or the request
is `404 unknown_bucket`.

| Method | Path | Route label | Handler | Verdict |
|---|---|---|---|---|
| GET | `/_health`, `/.well-known/docker-updater/health` | (pre-gate) | `server.go:172-181` | generic |
| GET | `/_version` | (pre-gate) | `version.go:206` | generic |
| GET | `/.well-known/docker-updater/pre-update` | (pre-gate) | `server.go:195-203` | generic |
| GET | `/{bucket}/_index` | `Index` | `handleGetIndex` `handlers.go:330` | Go-shaped (see §5) |
| GET or POST | `/{bucket}/_batch/get` | `BatchGet` | `handleBatchGet` `batch.go:177` | mixed |
| PUT | `/{bucket}/_batch/put` | `BatchPut` | `handleBatchPut` `batch.go:388` | generic |
| GET | `/{bucket}/{key}` | `GetObject` | `handleGetObject` `handlers.go:43` | mixed |
| HEAD | `/{bucket}/{key}` | `HeadObject` | `handleHeadObject` `handlers.go:150` | generic |
| PUT | `/{bucket}/{key}` | `PutObject` | `handlePutObject` `handlers.go:164` | mixed |
| DELETE | `/{bucket}/{key}` | `DeleteObject` | `handleDeleteObject` `handlers.go:318` | generic |
| anything else | | | `405 method_not_allowed` `server.go:317` | generic |

The three pre-gate paths answer **before** logging, metrics, auth, the stall
guard and admission control (`server.go:165-203`). Everything else goes through,
in order: stall guard arm (`server.go:210`), admission control (`server.go:246-255`),
auth (`server.go:257-264`), audit context (`server.go:267-273`), bucket check,
switch.

There is exactly one bucket per process. `bucket` is not a namespace mechanism —
it is a fixed string the client must repeat. (Relevant to §"namespacing" in
generalization.md.)

## 2. Auth

HTTP Basic only (`auth.go:118-160`). `disable_auth: true` returns the sentinel
username `<ANON>` (`auth.go:113`). Credentials compared with
`subtle.ConstantTimeCompare` (`auth.go:153`), and an entry with an empty
username **or** password is skipped even if constructed via the Go API
(`auth.go:150-152`) — the regression that empty creds must not bypass auth.
Failure is always `403 access_denied`, never 401, so no `WWW-Authenticate`
challenge is sent. **Generic.** No bearer token support, no per-key ACL, no
read-only credential class.

## 3. Errors

`writeError` (`handlers.go:22-27`):

```
Content-Type: text/plain; charset=utf-8
X-Cache-Error-Code: <code>
<status>

<code>: <message>\n
```

Codes (CLAUDE.md pins the list; grep confirms every call site):
`not_found` (404), `unknown_bucket` (404), `access_denied` (403),
`overloaded` (503), `conflict` (409), `too_large` (413),
`method_not_allowed` (405), `invalid_request` (400), `internal_error` (500).

**Generic.** The code vocabulary carries no Go semantics.

## 4. Single-object endpoints

### PUT /{bucket}/{key}

`handlePutObject` (`handlers.go:164-231`).

Request headers:
- `X-Cache-Meta-<Name>: <value>` — user metadata; the handler lowercases the
  header, strips `x-cache-meta-`, and keeps the remainder as the metadata key
  (`handlers.go:167-172`). **Generic mechanism.**
- `X-Amz-Meta-<Name>` — deprecated; fills only keys native did not set, and
  trips `noteDeprecatedS3Meta` (`handlers.go:176-188`, `deprecation.go:326`).
- `X-Cache-Module`, `X-Cache-Kind`, `X-Cache-Build` — provenance
  (`logagg.go:25-29`). `X-Cache-Kind: look-ahead` marks a speculative request.
  docs/look-ahead.md also names `X-Cache-Toolchain`, `X-Cache-Target`,
  `X-Cache-Client`, but only Module/Kind/Build are read by the server today
  (`provenanceOf`, `logagg.go:295-307`). **Generic in mechanism**, Go-flavoured
  in the value ("module").

The metadata *keys* the server treats specially are Go-shaped:
`outputid` (`selfheal.go:17`), `compression` (`modindex.go` / `storage_unix.go`
protected list), `body-size` (`logagg.go:rawSizeOf`), plus the label fields
`object-type`, `pkg`, `src`, `go-version`, `target`, `module`
(`handlers.go:343-364`, `logagg.go:332-347`). Everything else is opaque.

Body: streamed. `http.MaxBytesReader(w, r.Body, maxObjectBytes)`
(`handlers.go:195`), then `storeOneObject` (`handlers.go:278-310`), which:
1. reads a self-sizing peek capped at `indexPutPeekBytes` = 1 MiB
   (`handlers.go:279`, `modindex.go:47`);
2. **Go-shaped**: refuses the upload if the peek decompresses to `go index v`
   (`looksLikeGoModuleIndex`, `modindex.go:87`) — returns `200` and stores
   nothing, counted as `s3_put_refusals_total{reason="module_index"}`
   (`handlers.go:292`);
3. stitches the peek back with `io.MultiReader` and calls `storage.PutStream`
   (`handlers.go:302-303`).

Statuses: `200` stored, `200` dropped (module index), `409 conflict` on a
write_once conflict (`handlers.go:214-218`), `413 too_large` on MaxBytesError
(`handlers.go:206-208`), `500 internal_error` otherwise.

Note `200` is used for both "stored" and "silently refused". A generalized
protocol would want those distinguished.

### GET /{bucket}/{key}

`handleGetObject` (`handlers.go:43-121`). Order of operations:
1. `storage.Open` → 404 `not_found` on miss, classified by `absentKeyOutcome`
   (`handlers.go:36-41`) into `miss_not_found` or `miss_advertised_unservable`.
2. **Go-shaped**: `evictModuleIndexOnRead` (`modindex.go:268`) — a stored
   `go index v` blob is deleted and reported as 404.
3. **Go-shaped**: `ensureOutputID` (`selfheal.go:56`) — an object with no
   `outputid` metadata is repaired by recomputing `sha256(decompressed body)`;
   an unrepairable one is de-advertised and reported as 404.
4. `emitObjectHeaders` then `io.Copy` from the `*os.File` (keeps sendfile).

Response headers (`handlers.go:126-142`): every metadata key emitted **twice**,
as `X-Cache-Meta-<Name>` and `X-Amz-Meta-<Name>`, with only the first letter
upper-cased; plus `Last-Modified` (HTTP date) and `Content-Length`. No ETag, no
`Content-Type`, no caching headers, no range support.

GET outcomes land in `s3_get_requests_total{outcome}`: `hit`, `miss_not_found`,
`miss_advertised_unservable`, `miss_module_index_evicted`, `miss_peek_error`,
`miss_selfheal_failed` (`metrics.go:261`, `handlers.go:51,74,78,95,103`).

### HEAD

Stat-only; identical header surface, no body, **no guard, no self-heal, no
last-access stamp** (`handlers.go:144-162`). Deliberately non-mutating. Generic
and directly reusable as an existence probe.

### DELETE

Idempotent, `204` even for a missing key (`handlers.go:318-324`). Drops the file
and the index entry. Generic.

## 5. GET /{bucket}/_index — the GBCI v1 blob

`handleGetIndex` (`handlers.go:330-339`) serves `idx.Blob()` through
`http.ServeContent`, so `If-None-Match`/`Range` are handled by the stdlib.

- `Content-Type: application/octet-stream`
- `ETag: "<64 hex>"` — the hex SHA-256 trailer, quoted (`index.go` Blob).

Byte layout, serialized in `Index.Blob` (`index.go:~500-540`):

| Offset | Size | Content |
|---|---|---|
| 0 | 4 | magic `GBCI` (`index.go:33`) |
| 4 | 1 | version = 1 (`index.go:30`) |
| 5 | 1 | hash size = 32 (`index.go:27`) |
| 6 | 2 | LE uint16, always 0 (reserved) |
| 8 | 8 | LE uint64 `generation` — **content-derived**: the first 8 bytes of `sha256(body)` |
| 16 | 8 | LE uint64 `count` = number of hashes |
| 24 | 32×count | the sorted, deduplicated 32-byte action IDs |
| 24+32×count | 32 | `sha256(header ‖ body)` |

Header is `gbciHeaderSize = 24` (`index.go:24`).

Two design points worth carrying forward:
- **ETag purity.** The `generation` field is derived from the body digest, not a
  counter, so an unchanged key set reserializes byte-identically and clients keep
  getting `304` across duplicate PUT traffic and restarts. The comment at
  `index.go` in `Blob()` says the old monotonic counter forced a multi-MB
  re-download on every serialization.
- **Blob interval.** A serialization happens at most once per
  `defaultIndexBlobInterval` = 15s (`index.go:88`), configurable via
  `index_blob_interval` (`config.go:179`). A removal expires it at once by
  zeroing `builtAt` (`index.go` Remove/RemoveKeys).

**Verdict: Go-shaped in its key model, generic in its framing.** The blob carries
raw 32-byte hashes with no key strings, which only works because every indexed
key is exactly `go-buildcache/v1` + 64 lowercase hex (`extractActionHash`,
`index.go:117-131`). A key outside that pattern is stored and served but **never
advertised** (`index.go:167-170`, `compactkey.go:360-365`). For api-cache this
is the single most consequential assumption: a wrapper cache whose keys are not
32-byte hex would get an always-empty index.

## 6. POST (or GET) /{bucket}/_batch/get

Request body JSON (`batch.go:16-24`), read through a 1 MiB LimitReader
(`batch.go:186`):

```json
{"keys": ["..."], "prefetch": true, "prefetch_only": false}
```

- `keys` required, non-empty, ≤ `maxBatchKeys` = 4096 (`batch.go:83`,
  `batch.go:193-200`), else `400 invalid_request`.
- `prefetch` adds temporally-nearby keys.
- `prefetch_only` returns *only* the window and drops the anchors' bodies
  (`batch.go:21-24`, `batch.go:288-292`) — the look-ahead shape.

Response: `200`, `Content-Type: application/x-tar`, an **uncompressed** tar:

```
manifest.json          (FIRST member)
data/<key>             (one per manifest entry, same order)
```

`manifest.json` (`batch.go:27-37`):
```json
{"entries":[{"key":"...","size":123,"metadata":{...},"prefetch":true}]}
```
`prefetch` is `omitempty`, so requested entries carry no flag.

Tar members are written with `Mode: 0644` and an exact declared size; a short
read is `io.ErrUnexpectedEOF` rather than a truncated member (`batch.go:568-585`).
Bodies stream one at a time through a pooled 64 KiB buffer (`batch.go:552-556`).
Phase 1 stats every key (metadata only), phase 2 streams (`batch.go:216-360`) —
so a batch of hundreds of large objects never sits in the heap.

The per-key gates in phase 1 and in `buildPrefetchEntries` are the same two
**Go-shaped** ones as a single GET: `evictModuleIndexOnReadByKey` and
`ensureOutputID` (`batch.go:230-243`, `batch.go:589-604`). A key that fails
either is silently omitted; the client reads a missing `data/<key>` as a miss.

Metrics: `s3_batch_requests_total`, `s3_batch_keys_total{kind=requested|found|prefetched|suppressed|streamed}`
(`batch.go:362-368`).

**Verdict: the envelope is fully generic** (JSON key list → tar of blobs). The
prefetch selection and the two gates are what carry Go semantics.

## 7. PUT /{bucket}/_batch/put

`handleBatchPut` (`batch.go:388-525`). `Content-Type: application/x-tar`.
Request tar mirrors the GET response:

```
manifest.json          FIRST member, {"entries":[{"key":"...","metadata":{k:v}}]}
data/<key>             one per entry, in manifest order
```

Metadata keys are the lowercased meta names **without** the `X-Cache-Meta-`
prefix (`batch.go:40-46`) — so `outputid`, `compression`, `size`.

Bounds:
- whole body: `http.MaxBytesReader` at `maxBatchKeys * max_object_bytes`
  (`batch.go:410-412`) → `413 too_large`.
- entries: ≤ 4096 → `413` (`batch.go:439-442`).
- each member: `io.LimitReader(tr, maxObjectBytes)` (`batch.go:489`).

Whole-request `400 invalid_request` for: unreadable tar, first member not
`manifest.json`, bad manifest JSON, empty manifest, empty key, duplicate
manifest key, a data member with no manifest entry, a duplicate data member, a
manifest entry with no data member (`batch.go:420-513`).

Response `200`, `application/json`:
```json
{"results":[{"key":"...","status":"stored|dropped|conflict|error","message":"..."}]}
```
One result per manifest key, in manifest order (`batch.go:53-66`). A per-member
failure is recorded and does **not** abort the batch (`batch.go:497-508`).

Every member goes through the same `storeOneObject` as a single PUT, so the
module-index refusal, write_once and audit behaviour cannot drift
(`batch.go:491`, `handlers.go:244-247`).

**Verdict: generic**, apart from the module-index refusal inherited from
`storeOneObject`. This is the single most reusable endpoint in the protocol for
a compiler-wrapper cache: one admission slot for N objects.

## 8. Admission control, stall guard, drain

- **Admission control** (`server.go:246-255`): a buffered `sem` of
  `max_concurrent_requests` (default 128, `config.go:194`). A full channel is
  `503 overloaded` with `Retry-After: 2` (`server.go:17`, `server.go:252-253`)
  and `s3_http_rejected_total`. Deliberately never queues.
- **Stall guard** (`stallguard.go:265-287`): the server sets `ReadHeaderTimeout`
  and `IdleTimeout` but **no** `ReadTimeout`/`WriteTimeout`. Instead a
  `time.AfterFunc` watchdog samples `statusRecorder.progress` plus a counting
  request body; 60s (`stallguard.go:236`) of no movement in either direction
  sets both connection deadlines to `now`. A written header counts as progress,
  so a 304 is progress. Rationale at `stallguard.go:219-234`: a total cap
  measures size, not health.
- **Drain**: `BeginShutdown` flips `/_health` to `503` (`server.go:104-106`),
  then `httpSrv.Shutdown(ctx)` with a 280s timeout (CLAUDE.md, `main.go`).
  `/_version` never drains.

All three are **fully generic** and are arguably the highest-value part of the
server to reuse verbatim.

## 9. What the wire assumes about Go — the checklist

| Assumption | Where | Generalizable? |
|---|---|---|
| Key shape `go-buildcache/v1` + 64 lowercase hex | `index.go:20`, `extractActionHash` `index.go:117` | **No, as written.** It is a hard-coded const + a length/hex check. Parameterizing it is a small change (a prefix + hash-size config), but the GBCI blob format hard-codes 32-byte hashes at `index.go:27`. |
| One 32-byte action hash per key, index carries hashes not strings | `index.go`, `compactkey.go:355` | Generalizes only if api-cache keys are also fixed-width binary hashes. A variable-length key needs a different blob format (length-prefixed strings) and loses the memory win `compactkey.go:337-354` exists for. |
| `outputid` metadata == `sha256(decompressed body)` | `selfheal.go:12-17,98-121` | **Go/GOCACHEPROG-specific in name, generic in idea.** "The blob's content address is verifiable from the blob" is exactly what ccache and Bazel CAS assume too. Rename it `content-sha256` and it is generic. The *repair* path is a pure win for any content-addressed store. |
| Action ID vs output ID split (key = action, metadata = output) | GOCACHEPROG model; `selfheal.go`, `cacheclient/integrity.go` | Generic: it is exactly Bazel's Action Cache → CAS indirection collapsed into one object. A compiler wrapper has the same split (hash of compiler+flags+preprocessed source → result blob). |
| Bodies arrive compressed, and the codec is in the body's own first 4 bytes | `codec.go:14-47` | **Fully generic and a good idea.** zstd magic `0xFD2FB528`, lz4 magic `0x184D2204`, anything else reads as uncompressed. The server never compresses (`compression.go`) and never decompresses except to peek. |
| lz4 specifically | `lz4head.go`, `modindex.go` | Legacy. docs/look-ahead.md: "The codec is zstd. It replaced lz4 because this cache's constraint is bandwidth." The lz4 reader stays only for old objects. **Note CLAUDE.md still says lz4 throughout — it is behind `codec.go`.** |
| Module-index guard (`go index v` magic, evict on read, refuse on PUT) | `modindex.go:17,87,146,268,316` | **Purely Go.** It exists because a mis-keyed Go module index breaks `cmd/go` at package load. For api-cache it is dead weight — *and a hazard*: it decompresses and prefix-matches every indexed body, so a non-Go blob whose decompressed bytes happen to start `go index v` would be refused. Scoping saves it: both read variants are gated on `extractActionHash` succeeding (`modindex.go:268,316`), so a differently-shaped key is never inspected. |
| Metadata keys `pkg`, `go-version`, `object-type`, `module`, `target`, `body-size` | `handlers.go:343-364`, `logagg.go:332-359` | Cosmetic: only the log label and the per-project byte rate use them. Easy to re-map. |
| Prefetch = "keys written within ±30s" | `batch.go:87-92` | Generic heuristic (see index-and-prefetch.md), not Go-specific at all. |
| Provenance headers name a Go *module* | `logagg.go:26-29` | Rename only. |
| One fixed bucket per process | `server.go:280` | Not a namespace. See generalization.md. |

## 10. Things the protocol does NOT have

Worth listing because a compiler-wrapper cache may need them:

- **No range requests on an object.** `http.ServeContent` is used only for
  `/_index`; GET writes `Content-Length` and copies (`handlers.go:106-120`).
- **No multi-output entries.** One key → one opaque blob. A compile produces
  `.o` + `.d` + stderr; that must be packed by the client (see storage.md).
- **No compression negotiation.** No `Accept-Encoding`/`Content-Encoding`. The
  body is whatever frame the client wrote.
- **No key listing** except the GBCI blob, which is hash-only and Go-key-only.
- **No TTL / expiry per object.** Eviction is server-side LRU only.
- **No bearer / token auth**, no 401 challenge.
- **No CAS-style "does this digest exist" batch probe** other than `/_index`
  (all keys) or `/_batch/get` (which returns bodies).
- **No conditional PUT** other than `write_once`, which is server config, not a
  request header.
