# Remote protocols

Candidate wire protocols for the remote tier, each with its request shapes,
auth story and interop value, plus the two questions the survey exists to
answer: **can one server speak several of them over one blob store**, and
**what does the AC/CAS split actually buy a compiler cache**.

The per-request arithmetic that frames all of it: a build issues one lookup per
compile and thousands of compiles per build. At 4,000 compiles, **every
millisecond of per-lookup latency is 4 seconds of build time** if the lookups
are serialised, and a remote round trip on a LAN is 0.5–2 ms before the server
does anything. That is the number every feature below is really competing on.

## 1. go-s3-server's native protocol (this org)

The cache-server worker covers the internals; this is the comparison view.

**Endpoints.**

| method | path | body | purpose |
|---|---|---|---|
| `GET` / `HEAD` | `/<bucket>/<key>` | — / object | one object |
| `PUT` | `/<bucket>/<key>` | object | store one object |
| `DELETE` | `/<bucket>/<key>` | — | remove one |
| `GET` | `/<bucket>/_index` | GBCI v1 blob | **every key the server holds** |
| `GET` or `POST` | `/<bucket>/_batch/get` | JSON `{keys, prefetch}` | many objects as one tar |
| `PUT` | `/<bucket>/_batch/put` | tar | many objects in one request |
| `GET` | `/_health`, `/_version` | — | unauthenticated probes |

**Metadata** rides as `X-Cache-Meta-<Name>` headers (legacy `X-Amz-Meta-*`
mirrored on responses and still accepted on requests, counted in
`s3_deprecated_requests_total`). **Errors** are plain text — a
`<code>: <message>` body plus an `X-Cache-Error-Code` header with a snake_case
code (`not_found`, `conflict`, `too_large`, `overloaded`, `invalid_request`, …).
**Auth** is HTTP Basic, one username/password per credential entry, with
`disable_auth: true` as the only way to run open.

**The two features nothing else in this survey has.**

*A known-key index.* `GET /_index` returns a binary blob: a 24-byte header
(`GBCI` magic, version, a content-derived generation field, the count), then
the sorted 32-byte action-ID hashes, then a SHA-256 trailer. The ETag is the
hex trailer, and because the generation field is derived from the body's digest
rather than being a counter, **a duplicate-only PUT stream and a server restart
both reserialise byte-identically** and the client keeps getting a 304. The
blob is rebuilt at most once per `index_blob_interval` (15 s default). The
client (`cacheclient/`) loads it lazily on the first Get or Put, serves a disk
copy younger than `IndexMaxAge` (default 1 minute) with no request at all, and
then answers "does the server have this key?" locally.

That turns the most common remote interaction — *checking* whether a key is
there — into an in-process binary search. For a compiler cache this is the
single most valuable idea in the whole survey: a cold build's PUT traffic is
dominated by re-uploading things the server already has, and every other
protocol here either pays a round trip to find out (`HEAD`, `FindMissingBlobs`)
or just re-uploads.

*Batch get with temporal prefetch.* `/_batch/get` takes N keys and answers with
a tar whose first member is `manifest.json` (`{"entries":[{key,size,metadata,
prefetch}]}`) followed by `data/<key>` members. It also *adds* keys the caller
did not ask for: `NearbyKeys` finds entries whose mtime is within a 30-second
window of the requested ones (capped at 200), on the theory that objects
written together are read together. A `prefetchTracker` suppresses keys already
sent to that client within 5 minutes, and — importantly — suppression happens
*before* the stat/guard/heal work, so a candidate the guard dropped stays
eligible later. `/_batch/put` is the mirror: a tar with `manifest.json` first,
one `data/<key>` per entry, answered with per-key `stored|dropped|conflict|
error` JSON, one admission-control slot for the whole batch.

**What a generic-key client would have to deal with.** The guards are scoped,
not universal, and the scoping is the problem:

- `extractActionHash` only recognises `go-buildcache/v1<64 hex>`. Anything else
  is stored and served but **never appears in `/_index`**, so the
  known-key-index advantage vanishes for a differently-shaped key.
- The module-index guard and the outputid self-heal both apply only to that key
  shape. They are Go-specific (`outputid` is the GOCACHEPROG content address;
  the module-index guard exists because a Go module index must never be
  cached). A C/C++ compiler cache needs neither and would want its own
  equivalent.
- `isKeySafe` rejects anything outside `[A-Za-z0-9/_-]`, hashing the rest into
  `__hashed__/` with the original key in an xattr. A key with a `.` in it takes
  that path.

So the honest assessment is that the *architecture* (index, batch, tar+manifest,
plain-text errors, streaming everywhere, no whole-object buffering) transfers
completely, and the *key vocabulary* does not. Reusing the server means either
adopting its key shape or generalising `extractActionHash` into something the
index is parameterised on.

## 2. Bazel remote cache — HTTP and gRPC REAPI v2

**HTTP** (bazel-remote, Apache-2.0,
<https://github.com/buchgr/bazel-remote>). Two namespaces, both keyed by
lowercase hex SHA-256:

```
GET|PUT|HEAD  /cas/<hash>                 arbitrary bytes; hash IS the content
GET|PUT|HEAD  /ac/<hash>                  an ActionResult protobuf
GET|PUT|HEAD  /<instance>/cas/<hash>       instance-scoped
GET           /status                      size, file count, git commit
```

`Accept-Encoding: zstd` on a GET gets a compressed body; a compressed PUT sends
`Content-Encoding: zstd` plus a custom `X-Digest-SizeBytes` header (because the
digest names the *uncompressed* bytes, so the server cannot infer the size from
`Content-Length`). `Accept: application/json` / `Content-Type: application/json`
switches the `ac` payload to JSON. Auth: HTTP Basic against `.htpasswd`, mutual
TLS, or experimental LDAP, with an option for unauthenticated reads alongside
authenticated writes. Storage is disk with LRU eviction and optional S3/GCS/
Azure/gRPC/HTTP proxy backends.

That is about as simple a protocol as exists: four verbs, two prefixes, no
index, no batch, no manifest. **ccache can already talk to it** — the HTTP
backend's `layout=bazel` attribute exists precisely for this.

**gRPC REAPI v2**
(<https://github.com/bazelbuild/remote-apis>, `build/bazel/remote/execution/v2/
remote_execution.proto`, Apache-2.0). The cache-relevant surface:

| service | method | what it does |
|---|---|---|
| `ActionCache` | `GetActionResult` | action digest → `ActionResult`; `inline_stdout`/`inline_stderr`/`inline_output_files` ask the server to embed small outputs in the reply |
| `ActionCache` | `UpdateActionResult` | store one |
| `ContentAddressableStorage` | `FindMissingBlobs` | **"which of these N digests do you not have?"** — the upload-skip primitive |
| `ContentAddressableStorage` | `BatchUpdateBlobs` | upload many small blobs in one RPC |
| `ContentAddressableStorage` | `BatchReadBlobs` | download many small blobs in one RPC |
| `ByteStream` | `Read` / `Write` | one large blob, streamed |
| `Capabilities` | `GetCapabilities` | `CacheCapabilities`: digest functions, supported compressors, `max_batch_total_size_bytes` |

`Digest` is `{hash: string (lowercase hex), size_bytes: int64}` — the size is
part of the identity, which makes a truncated body detectable without hashing
it. `ActionResult` carries `output_files`, `output_directories`,
`output_symlinks`, `exit_code`, `stdout_raw` **or** `stdout_digest`,
`stderr_raw` **or** `stderr_digest`, and `execution_metadata`.

ByteStream resource names are literal strings:

```
{instance}/uploads/{uuid}/blobs/{digest_function/}{hash}/{size}{/metadata}
{instance}/blobs/{digest_function/}{hash}/{size}
```

`max_batch_total_size_bytes` is the one number that decides the protocol's
shape in practice: the conventional limit is ~4 MB (gRPC's default message
cap), so a batch carries small blobs and anything bigger goes through
ByteStream. A 5 MB `-g` object is over that line; a 528 KB one is not.

**What REAPI costs.** A protobuf dependency, a gRPC dependency, and a mental
model built for *remote execution* where cache is a side effect. `ActionResult`
models a directory tree of outputs with symlinks and per-file executable bits —
correct for an arbitrary action, several times more than "an object, a depfile
and some stderr" needs. And the round trips are real: `GetActionResult` then
`BatchReadBlobs` is two sequential RPCs per hit unless `inline_output_files`
covers everything, which for a 528 KB object it will not.

**What REAPI buys.** It is the only protocol here that is a genuine industry
standard with many independent implementations — bazel-remote, BuildBarn,
Buildfarm, NativeLink, BuildBuddy, EngFlow. A cache that speaks it is
immediately usable by Bazel, Buck2 and Pants, and can sit behind any of those
servers. That is a strategic argument, not a performance one.

## 3. ccache's remote storage

Two shapes, and a third arriving.

**HTTP backend** (ccache manual,
<https://ccache.dev/manual/latest.html>; ccache is GPL-3.0 — behaviour
described only):

```
remote_storage = http://host:port/path|attr=value|attr=value
```

`GET`, `PUT` and `DELETE` on `<url>/<key>`. Attributes:

| attribute | meaning |
|---|---|
| `bearer-token` | sent as the HTTP bearer token |
| `layout` | `subdirs` (default, 256 buckets), `flat`, or **`bazel`** |
| `read-only` | read but never write |
| `shards` | the URL contains `*`, replaced by a shard name; rendezvous hashing across shards, with optional weights `name(w)` |
| `connect-timeout` / `operation-timeout` | |

The value at a key is the **entire ccache cache entry** — header, compressed
payload and XXH3-128 checksum. The remote is a dumb blob store; every decision
(what to compress, what the checksum is, what the entry contains) stays in the
client. That is a deliberate and defensible split, and it is why `layout=bazel`
can work at all: ccache does not need the server to understand an
`ActionResult`, only to hold bytes at a key.

**Redis backend.** `redis://[[user:]password@]host[:port][/db]`, same
shards/rendezvous scheme. Values are the same opaque entries.

**Sharding** is the one mechanism ccache has that the HTTP protocol does not:
`shards = a,b(2),c` with an `*` in the URL spreads keys across hosts by
rendezvous hashing with weights, entirely client-side. No coordination, no
server-side ring.

**The storage-helper protocol (new).** `doc/remote_storage_helper_spec.md` in
the ccache tree specifies a long-lived out-of-process helper named
`ccache-storage-<scheme>`, listening on a Unix socket (Windows: a named pipe),
shared by every ccache process with the same settings. Startup parameters
arrive as environment variables (`CRSH_IPC_ENDPOINT`, `CRSH_URL`,
`CRSH_IDLE_TIMEOUT`, and `CRSH_ATTR_KEY_<i>`/`CRSH_ATTR_VALUE_<i>` for the
custom attributes). The wire protocol is tiny and binary, host byte order,
keys capped at 255 bytes and messages at 255 bytes:

```
greeting     ::= 0x01 <cap_len:u8> <cap:u8>*     ; capabilities 0x00 get/put/remove,
                                                 ; 0x01 info, 0x02 exists
get_request  ::= 0x00 <key>                      <key> ::= <u8 len> <bytes>
put_request  ::= 0x01 <key> <flags:u8> <value>   <value> ::= <u64 len> <bytes>
remove_req   ::= 0x02 <key>
stop_request ::= 0x03
response     ::= 0x00 <value?> | 0x01 (noop) | 0x02 <msg>
```

There is deliberately no auth in the protocol: "a client that has access to the
socket/pipe has access to the server". The `put_flags` overwrite bit is
explicitly "only a performance hint".

This matters for interop strategy. **Shipping a `ccache-storage-<scheme>`
helper makes a remote reachable from stock ccache without ccache changing**,
with connection reuse already amortised across every compile in the build. It
is 200 lines of socket code. It is the cheapest possible path to "works with
what people already run".

## 4. sccache — plain object storage

sccache (Apache-2.0, <https://github.com/mozilla/sccache>) has no protocol of
its own. `src/cache/` holds backends for S3 (and R2), GCS, Azure Blob, Redis
(single and cluster), memcached, WebDAV, GitHub Actions, Alibaba OSS and
Tencent COS. All of them implement the same `Storage` trait:

```
get(key) -> Cache::{Hit(CacheRead), Miss}     put(key, CacheWrite)
get_raw(key) -> Bytes                          put_raw(key, Bytes)
check() -> CacheMode::{ReadWrite, ReadOnly}
location()   current_size()   max_size()
```

The key is a hex digest, normalised to `a/b/c/abcdef` for path-shaped backends,
with an optional `key_prefix` prepended. The value is the zip-of-zstd-streams
described in `container-format.md`. `get_raw`/`put_raw` exist so a `chain`
(disk → Redis → S3) can backfill by moving the serialized entry between levels
without decoding it.

`check()` returning `ReadOnly` is a small but useful piece of protocol design:
the backend reports its own writability at startup rather than failing on the
first PUT, which is how "CI writes, developers read" gets configured without a
separate flag.

**Worth being blunt about what this buys.** Plain object storage is one GET per
lookup with no index, no batch and no conditional anything. Against S3 that is
20–80 ms per request; against a LAN MinIO it is 1–3 ms. For 4,000 compiles the
difference between "one GET per lookup" and "one index download then local
membership tests" is the difference between a cache that helps and one that
does not, which is exactly why go-s3-server grew `/_index`.

## 5. Gradle HTTP build cache

<https://docs.gradle.org/current/userguide/build_cache.html>. The simplest
protocol in the survey:

```
GET  <url>/<cache-key>    →  2xx + entry body, or 404
PUT  <url>/<cache-key>    →  any 2xx
```

`413 Payload Too Large` on a PUT is explicitly **not** an error — it means the
entry is over the server's limit and the build carries on. `3xx` is followed
automatically, but only `307`/`308` preserve the method and body on a PUT;
other redirects degrade to a GET. Auth is HTTP Basic with credentials sent
preemptively (`username`, `password`). `isPush` controls whether a build
writes; the default is push-on for the local cache and **push-off for the
remote**, which is the "CI writes, developers read" default baked into the
tool. `isUseExpectContinue` turns on `Expect: 100-continue` so a rejected or
redirected upload does not send the body twice.

The entry format is not part of the protocol — it is an opaque body. That is
the whole design: a Gradle build cache server is a keyed blob store with two
verbs, and there are several trivially small implementations.

## 6. Nx, Turborepo, GitHub Actions cache

**Turborepo remote cache** is the one protocol in this section with a published
OpenAPI 3.0.3 document for *self-hosted* servers, at
<https://turborepo.dev/api/remote-cache-spec> (viewer:
<https://turborepo.dev/docs/openapi>). Its `servers` list names a self-hosted
`{protocol}://{host}` first and Vercel's `api.vercel.com` second as the
"reference implementation", and the docs state that every version of `turbo`
speaks the `v8` endpoints, so a self-hosted base is mounted at `<base>/v8`.
The surface is six operations over one blob:

| operation | path | note |
|---|---|---|
| `HEAD` | `/artifacts/{hash}` | "Check if artifact exists" — one round trip per key |
| `GET` | `/artifacts/{hash}` | `application/octet-stream` body; 400/401/403/404 |
| `PUT` | `/artifacts/{hash}` | `Content-Length` **required**; 200 or 202 |
| `POST` | `/artifacts` | batch "query artifact information" |
| `POST` | `/artifacts/events` | cache usage analytics |
| `GET` | `/artifacts/status` | remote caching enabled/disabled |

Auth is one `bearerToken` HTTP security scheme — `Authorization: Bearer
<token>` — and the spec explicitly leaves the token format to the implementer
("Static tokens ... JWT ... OAuth2"). Tenancy is two optional query parameters,
`?teamId=` or its alternative `?slug=`. The metadata rides as headers on both
the PUT and the 200 GET: `x-artifact-duration`, `x-artifact-tag` (the
end-to-end signing HMAC), `x-artifact-sha` and `x-artifact-dirty-hash`, plus
`x-artifact-client-ci` and `x-artifact-client-interactive` on the request.

Two things are worth carrying forward. First, **`x-artifact-tag` is the only
end-to-end artifact signature in this whole survey** — every other protocol
trusts the transport and the server. Second, the existence check is a `HEAD`
**per key**: it is the same round trip REAPI's `FindMissingBlobs` batches and
go-s3-server's `/_index` removes entirely, which is the comparison in
"The known-key index" below.

**Nx Cloud** is a proprietary service with a self-hostable server; the
file-level protocol is not specified publicly in a way worth building against.

**GitHub Actions cache** is the interesting one because it is free
infrastructure that many builds already sit inside, and because sccache and
several other tools speak it. The v2 service is **Twirp over HTTP** at
`{base_url}/twirp/github.actions.results.api.v1.CacheService/<Method>` with
protobuf (or JSON) bodies:

| method | what it does |
|---|---|
| `CreateCacheEntry` | returns a **pre-signed Azure Blob SAS URL** with write permission |
| `FinalizeCacheEntryUpload` | commits the upload |
| `GetCacheEntryDownloadURL` | returns a read SAS URL, or an empty URL meaning "miss" |

The credentials come from `ACTIONS_RESULTS_URL` and `ACTIONS_RUNTIME_TOKEN` in
the runner environment. The bytes never touch the API: they go to Azure Blob
directly, which is why v2 needs the Azure SDK. The legacy v1 API was sunset on
1 Feb 2025.

Two structural properties matter. First, **restore keys**: a lookup supplies an
exact key plus a list of prefixes, and the service returns the newest entry
whose key starts with one of them. That is a fuzzy-match cache, which is right
for "a `node_modules` tarball close enough to mine" and wrong for a compiler
cache, where an approximate match is a wrong answer. Second, **entries are
immutable and scoped to a branch** with a fallback to the default branch, and
there is a 10 GB per-repository quota with LRU eviction. A compiler cache that
stores one entry per translation unit will blow through both the quota and the
per-entry overhead of a SAS round trip; the pattern that works is storing the
*whole local cache directory* as one entry per job, which is what
`actions/cache` + `ccache` deployments actually do.

## The comparison

| | go-s3-server native | bazel-remote HTTP | REAPI v2 gRPC | ccache HTTP | sccache/S3 | Gradle | GHA v2 |
|---|---|---|---|---|---|---|---|
| transport | HTTP/1.1 | HTTP | gRPC/HTTP2 | HTTP | HTTPS (SigV4 etc) | HTTP | Twirp + Azure Blob |
| verbs | GET/PUT/DELETE/HEAD + 3 custom | GET/PUT/HEAD | 7 RPCs | GET/PUT/DELETE | backend-specific | GET/PUT | 3 RPCs + blob PUT/GET |
| key → value model | opaque key → blob | AC + CAS | AC + CAS | opaque key → blob | opaque key → blob | opaque key → blob | key (+ restore prefixes) → blob |
| known-key index | **yes (`/_index`, cacheable, 304-able)** | no | `FindMissingBlobs` (a round trip) | no | no | no | no |
| batch read | **yes (tar + manifest, with prefetch)** | no | `BatchReadBlobs` (≤ ~4 MB) | no | no | no | no |
| batch write | **yes (tar, one admission slot)** | no | `BatchUpdateBlobs` (≤ ~4 MB) | no | no | no | no |
| compression on the wire | client-side (lz4 bodies) | `Accept-Encoding: zstd` | `compressor` in the request | client-side | client-side | client-side | client-side |
| auth | HTTP Basic | Basic / mTLS / LDAP | TLS + per-call creds | **bearer token** | cloud IAM | HTTP Basic | runtime token + SAS |
| read-only mode | no (auth-level only) | yes (unauth reads) | server policy | **`read-only=true`** | **`check() → ReadOnly`** | **`isPush=false`** | n/a |
| client-side sharding | no | no | no | **yes (rendezvous, weighted)** | no | no | no |
| existing client base | go-toolchain only | Bazel, ccache (`layout=bazel`) | Bazel, Buck2, Pants, + servers | ccache | sccache | Gradle | every GH Actions job |
| licence | this org | Apache-2.0 | Apache-2.0 | GPL-3.0 (client) | Apache-2.0 | Apache-2.0 | proprietary service |

## Can one server speak several of these over one blob store?

Yes for the simple ones, and the reason is that four of the seven are the same
protocol with different spellings.

**ccache HTTP, Gradle, sccache/WebDAV, Turborepo and bazel-remote's `/cas/` are
all "`GET`/`PUT` an opaque body at a path".** They differ in the path prefix,
the auth header, and a handful of status-code conventions:

| | path | auth | notable |
|---|---|---|---|
| ccache `layout=subdirs` | `/<2 hex>/<rest>` | `Authorization: Bearer` | `DELETE` supported |
| ccache `layout=flat` | `/<key>` | bearer | |
| ccache `layout=bazel` | `/ac/<hash>`, `/cas/<hash>` | bearer | same shape as bazel-remote |
| Gradle | `/cache/<key>` | Basic | `413` is a non-error |
| Turborepo | `/v8/artifacts/<hash>` | bearer | `HEAD` exists; `x-artifact-*` metadata headers; `?teamId=`/`?slug=` |
| bazel-remote | `/ac/<hash>`, `/cas/<hash>` | Basic / mTLS | `Accept-Encoding: zstd` |
| go-s3-server | `/<bucket>/<key>` | Basic | `X-Cache-Meta-*`, plain-text errors |

Turborepo is the cheapest dialect to add of the five, because its spec is
published and machine-readable, its metadata is already header-shaped (which is
exactly go-s3-server's `X-Cache-Meta-*` convention with a different prefix), and
its tenancy is two ignorable query parameters. Whether a compiler cache *wants*
`turbo` as a client is a separate question — but the surface costs a prefix.

One HTTP mux with a prefix per dialect, over one key-normalising blob store, is
a few hundred lines. The genuine incompatibilities are narrow and known:

- **Auth header.** Bearer vs Basic. Accept both.
- **Digest verification.** bazel-remote validates that an `/ac/` body parses as
  an `ActionResult` protobuf (disableable) and that a `/cas/` body hashes to
  its key. ccache's bodies are opaque and would fail both. So `/cas/` and the
  ccache prefix cannot share validation rules — they can share the store.
- **`413` semantics.** Gradle treats it as "skip this entry, carry on"; a
  client that treats it as an error will fail the build.
- **Content encoding.** bazel-remote's compressed PUT needs
  `X-Digest-SizeBytes` because the key names the uncompressed bytes.
- **Required `Content-Length`.** Turborepo's spec marks it required on the PUT,
  so a chunked upload is out of spec there while it is fine everywhere else.

**REAPI gRPC is a different matter.** It needs protobuf, gRPC, the `Capabilities`
service, and a real `ActionResult` model. It can sit over the same blob store
(that is exactly what bazel-remote does — one disk cache behind both its HTTP
and gRPC front ends) but it is a second front end, not a path prefix.

**GHA v2 cannot be served at all** without being GitHub: the protocol's whole
shape is "hand the client a SAS URL to Azure Blob". It is a client-side
backend, never a server-side dialect.

## AC/CAS: what the split buys and costs

| | buys | costs |
|---|---|---|
| **dedupe** | identical outputs stored once. For a compiler cache the object rarely repeats, but the `.d` file and the (usually empty) stderr repeat constantly across configurations — and `mid.d` compresses to 1,663 bytes, so the saving is real but small in absolute terms | a second indirection to maintain |
| **integrity** | the key *is* the hash, so a corrupt blob is detectable by anyone with the key and no extra metadata. go-s3-server needs a whole outputid self-heal mechanism (`selfheal.go`) precisely because its keys are *not* content addresses | hashing on write, at 365 MB/s for SHA-256 without SHA-NI — 14 ms for a 5 MB object |
| **partial fetch** | fetch the object and skip the stderr; fetch nothing at all if `FindMissingBlobs` says you already have it. Directly valuable when the same header-only `.d` is shared by 200 translation units | none |
| **round trips** | — | **two per hit** (`GetActionResult`, then read the blobs) unless the server inlines. At 1 ms each and 4,000 compiles that is 8 seconds against 4 |
| **eviction** | — | **the hard one.** An `ActionResult` referencing an evicted blob is a dangling pointer that reads as a hit and fails on the fetch. Every REAPI server has to either refcount, or evict AC entries before their CAS blobs, or tolerate and repair. A single-blob-per-entry cache simply cannot have this bug |

The round-trip cost is answerable — `inline_output_files`, `BatchReadBlobs`, or
a batch endpoint like `/_batch/get`. The eviction cost is structural.

**The synthesis worth flagging for the plan:** a compiler-cache entry is
already *keyed* by a derived hash, and its outputs are already *small in
number*. A middle position exists and nobody in this survey occupies it:
**one container per entry (so a hit is one round trip and eviction is one
decision), plus a known-key index (so the "do you have it?" question costs no
round trip at all), plus batch get/put (so N lookups cost one request).** That
is go-s3-server's architecture with a container as the value instead of a
single blob — and it does not need the AC/CAS split to get the two properties
that matter most here, which are "one round trip per hit" and "no upload of
something you already have".

Against that: no dedupe of a repeated `.d`, and no content-addressed integrity
(so the entry must carry its own checksum — which every format in
`container-format.md` except tar already does).

## Sources

- go-s3-server — `handlers.go`, `batch.go`, `index.go`, `cacheclient/`, and
  `docs/look-ahead.md` in this org
- bazel-remote — <https://github.com/buchgr/bazel-remote> (Apache-2.0)
- Bazel remote caching — <https://bazel.build/remote/caching>
- REAPI v2 — <https://github.com/bazelbuild/remote-apis>,
  `build/bazel/remote/execution/v2/remote_execution.proto` (Apache-2.0)
- ccache manual, `remote_storage` — <https://ccache.dev/manual/latest.html>
  (GPL-3.0 project; behaviour described only)
- ccache storage-helper spec — `doc/remote_storage_helper_spec.md` in
  <https://github.com/ccache/ccache> (GPL-3.0)
- sccache — <https://github.com/mozilla/sccache>, `src/cache/` and
  `docs/Configuration.md` (Apache-2.0)
- Gradle build cache — <https://docs.gradle.org/current/userguide/build_cache.html>
- Turborepo remote caching —
  <https://turborepo.dev/docs/core-concepts/remote-caching>
  (redirected from `turborepo.com`), and the self-hosting OpenAPI 3.0.3
  document itself, read for the endpoint table above:
  <https://turborepo.dev/api/remote-cache-spec>
- GitHub Actions cache — <https://github.com/actions/cache> and
  <https://github.com/actions/toolkit/tree/main/packages/cache> (MIT)
