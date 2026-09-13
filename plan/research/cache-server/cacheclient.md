# `cacheclient` — the client module

`github.com/wow-look-at-my/go-s3-server/cacheclient` (`cacheclient/go.mod:1`) is
a **separate Go module inside the server repo**, with a `replace` in the root
`go.mod:17` so protocol and server change in one commit. It is the piece an
api-cache client could import most directly, so this file is about what its
public surface actually is and how much of it is Go-shaped.

## 0. Dependencies and licence

`cacheclient/go.mod:5-19`:

| Dep | Purpose | Licence |
|---|---|---|
| `github.com/klauspost/compress` v1.20.0 | zstd encoder/decoder | BSD-3-Clause (plus Apache-2.0 and Go BSD for vendored s2/snappy parts) |
| `github.com/pierrec/lz4/v4` v4.1.27 | reading legacy lz4 bodies | BSD-3-Clause |
| `github.com/wow-look-at-my/go-containers` | `set.Set[T]` | org-internal; presumed MIT, **unverified** |
| `github.com/stretchr/testify` | tests only | MIT |

The module deliberately excludes cobra and prometheus: CLAUDE.md says "The
server's cobra and prometheus tree stays out, because a consumer vendors this
module into a tree that will not take them."

**There is no LICENSE file in `/home/user/go-s3-server`** (checked: `ls LICENSE*`
returns nothing). api-cache's own `LICENSE:1` is MIT. A planner intending to
import or fork `cacheclient` should get a licence added upstream first.

**No tracing.** CLAUDE.md: "Nobody can reimplement OpenTelemetry by hand here."
Diagnostics go only through the `Logger` seam (below).

## 1. The `Logger` seam

`cacheclient/logging.go:131-154`. Three methods (`Infof`/`Warnf`/`Debugf`), a
package-level `logging` var, `SetLogger(nil)` restores silence, default is
`discardLogger`. Reason given at `logging.go:128-130`: "A caller whose stdout is
a protocol channel must not have stderr written for it."

**Fully generic and directly reusable.** A compiler wrapper has exactly the same
constraint (a `-fdiagnostics` stream must not be polluted).

Errors already reported carry `ErrLogged` (`web.go:19`) so a caller does not
double-log.

There is also a **coalescing HTTP error logger** (`httperrlog.go`) that groups
identical `(op, status, body)` failures and flushes a summary on an interval —
a build hitting a down cache prints one line, not ten thousand. Generic.

## 2. Configuration

`WebConfig` (`web.go:24-42`):

```
Bucket, Endpoint, Prefix, AccessKey, SecretKey,
Version, Module, Target,        // provenance, stored as object metadata
IndexDir, IndexMaxAge
```

`Bucket == ""` means "no remote": `NewWebBackend` returns `(nil, nil)`
(`web.go:202-204`). A build without the shared cache is slower and still
correct — that policy is baked into the constructor.

`ConfigFromEnv` (`config.go:40-98`) reads **one base64-encoded JSON blob** from
`GO_BUILDCACHE_CONFIG` (`config.go:11`), accepting standard or URL-safe base64,
padded or not (`config.go:46-49`). Fields: `endpoint`, `bucket`, `username`,
`password`, plus deprecated `key_id`/`access_key`/`region`. Default bucket
`gobuildcache` (`config.go:31`).

**Generic mechanism**, but note: api-cache's declarative-XML house style would
want this configured through the XML spec, not an env var. The env var exists
because the client runs inside `cmd/go`, which has no config file of its own.

Tunables are all env ints via `envInt` (`web_resilience.go:103`):
`GO_TOOLCHAIN_CACHE_MAX_RETRIES`, `GO_TOOLCHAIN_CACHE_EMPTY_BATCH_BACKOFF`,
`GO_TOOLCHAIN_CACHE_PREP`, `GO_TOOLCHAIN_CACHE_LOOKAHEAD`,
`GO_TOOLCHAIN_CACHE_LOOKAHEAD_BYTES`, `GO_TOOLCHAIN_CACHE_ZSTD_LEVEL`,
`GO_TOOLCHAIN_CACHE_PUT_WINDOW_MS`.

## 3. Public API surface

From `WebBackend` (`web.go:57-176`) and friends:

| Symbol | File:line | Verdict |
|---|---|---|
| `NewWebBackend(WebConfig) (*WebBackend, error)` | `web.go:202` | generic |
| `Get(actionID) (outputID, data, t, miss)` | `web.go:361` | **actionID must be ≤64-char even-length hex** |
| `Put(actionID, outputID string, data []byte) error` | `webput.go:38` | same |
| `PutFile(actionID, outputID, path string) error` | `webput.go:50` | same |
| `Close() error` | `web.go:469` | generic; drains prep → PUT coalescer → GET coalescer → look-ahead, **in that order** |
| `Verify(BatchEntry, actionID) ([]byte, bool)` | `web.go:404` | Go-shaped (build-id + module-index gates) |
| `ActionIDFromKey(key) (string, bool)` | `web.go:410` | Go key grammar |
| `KeyPrefix() string` | `web.go:338` | returns `prefix + "v1"` |
| `OnBatchEntries func([]BatchEntry)` field | `web.go:107-118` | generic hook; **nil turns look-ahead off entirely** |
| `SetLogger(Logger)` | `logging.go:142` | generic |
| `SetModule(string)` | `web.go:520` | rename-only |
| `MarkPresent/Present/NewBareBackend` | `support.go:165-193` | test seams for consumers |
| `SummarySnapshot() WebSummary` | `websummary.go:67` | generic |
| `GetStats() *CacheStats` | `web.go:493` | generic |
| ~30 exported `AtomicCounter` miss-reason fields | `web.go:120-148` | mostly generic |
| `OutputIDMatches(outputID, body)` | `integrity.go:109` | generic sha256 check |
| `IsGoModuleIndex(body)` | `modindex.go:123` | pure Go |
| `BuildIDMatchesAction`, `ArchiveExportInfo`, `ExpectedBuildIDAction` | `buildid.go:143-211` | pure Go |
| `Compress`/`Decompress`/`DecompressSized` | `compress.go:255-260` | generic |
| `ShortID(id)` | `httperrlog.go:263` | generic |

`Get` returns `(outputID, data, t, miss)` — the GOCACHEPROG shape. `data` is the
**decompressed, fully verified** body, as `[]byte` not a reader, because
"the client has the whole object in memory by the time it can answer at all"
(`web.go:181-186`).

## 4. How Get works — the index-driven routing policy

`Get` (`web.go:361-397`), documented at `web.go:345-360`:

1. `parseActionHash(actionID)` → 32-byte array, or immediate miss
   (`web_index.go:59-69`). A **shorter** hex id is left-aligned and
   zero-extended rather than refused, explicitly so a consumer's synthetic ids
   work (`web_index.go:47-58`). That is the one crack in the 32-byte assumption.
2. `ensureIndex()` — the index loads lazily on the **first Get or Put**, under a
   `sync.Once` (`web.go:326-336`). "A go command that never asks for a key never
   downloads it."
3. If the hash is in `keys` → `getBatch` (the coalescer).
4. Else if already in `knownMiss` → miss, no network.
5. Else if the index is **authoritative** → miss, no network, counted as
   `SkippedEmptyIndex` or `SkippedNotInIndex`.
6. Else if the empty-batch backoff has tripped → miss, counted
   `SkippedBatchBackoff`.
7. Else → batch-probe anyway (the recovery path when the index fetch failed).

"Authoritative" (`web_index.go:112-165`) means server-confirmed this run: a
freshly parsed blob, a 304 validating the disk copy, **or** a disk copy younger
than `IndexMaxAge`. A non-authoritative set proves nothing about absence, so
absences are probed.

### The known-key / skip-re-upload logic

`enqueuePut` (`webput.go:60-83`) does an **atomic check-and-claim** under
`keysMu`: if `keys.Contains(h)` it returns immediately and counts
`PutSkippedKnown`; otherwise it adds the hash *optimistically* and submits the
job. Every failure path afterwards calls `removeClaimed` to roll the claim back
(`webput.go:79-81,99,112,120,131,185`; `webget.go:124-128`).

`reclaimAbsent` (`web.go:441-458`) is the inverse: a 404, or a key the batch
response never named, drops the index claim *and* records `knownMiss`. Counted
as `Reclaimed404`.

**This is the single most valuable pattern for api-cache and it is fully
generic**: the client keeps a local belief about what the remote holds, never
re-uploads what the remote claims, and self-corrects when the remote disagrees.
It is also the pattern that makes the server's `miss_advertised_unservable`
metric load-bearing.

## 5. The GET coalescer

`batchCoalescer` (`batch.go:159+`). Its window is **Nagle's rule, not a fixed
wait** (`batch.go:150-158`): the first batch leaves at once, and only what
arrives while a request is in flight rides the next one. Rationale: a four-way
build never offers more than four keys, so a fixed window bought nothing but
latency. `batchMaxKeys = 128`, `batchCoalesceWait = 10ms`,
`batchReqChBuf = 1024` (`web.go:196-200`).

`sendBatch` (`batch.go:242-360`):
- POSTs `{"keys":[...]}` to `/{bucket}/_batch/get`, `Content-Type: application/json`,
  `X-Cache-Kind: critical` (`batch.go:262-272`).
- `404` or `405` → **falls back to individual GETs for every caller in the
  batch** (`batch.go:285-290`). This is how the client tolerates an old server.
- Streams the tar with `streamBatchResponse` and answers each caller **as its
  own body lands**, not after the last (`batch.go:308-325`).
- Every key the stream never named is authoritatively absent →
  `reclaimAbsent` (`batch.go:342-348`).
- Seeds the look-ahead with **only the keys that hit** (`batch.go:359`).

`streamBatchResponse` (`batch.go:66-137`) is the tar reader. It relies on
`manifest.json` being the **first** member so metadata is known before each
body arrives, and it pre-allocates each member exactly from `hdr.Size`. The
doc comment names the failure it fixed: nothing bounded the *bytes*, only the
entry count, and a Windows runner hit `ERROR_COMMITMENT_LIMIT`.

**Fully generic.** A compiler wrapper coalescing lookups would want exactly this.

## 6. The PUT coalescer and prep pool

Two stages:

**prepPool** (`prep.go:247-330`): `runtime.NumCPU()` workers clamped to [2,32],
queue depth `workers*4`. It does the CPU work off the build's goroutine:
read the file if `PutFile`, run the guards, compress, build the metadata map.
`submit` **blocks** when full, deliberately — "the alternative is dropping an
object the build just paid to produce" (`prep.go:288-292`).

`prepare` (`webput.go:90-187`) is the Go-shaped part:
- `BuildIDMatchesAction` refuses a body whose embedded Go build id names a
  different action (`webput.go:108-114`). **Go-only** — it parses an `ar`
  archive's `__.PKGDEF` member (`buildid.go:156-180`).
- `IsGoModuleIndex` refuses an index (`webput.go:118-122`). **Go-only.**
- `Compress` = zstd (`compress.go:255`).
- Metadata map, keys: `outputid`, `object-type`, `body-size`,
  `compression: "zstd"`, `created`, and optionally `toolchain-version`,
  `module`, `go-version`, `target`, `pkg`, `src` (`webput.go:139-161`).
  Note `compression` is hardcoded `"zstd"` here while the **server reads the
  frame magic instead** (`codec.go:14-17`) precisely because metadata can lie.
- `capSrcList` (`webput.go:209-228`) caps the `src` value at 8 names / 256 bytes
  "so it always fits the cache server's shared ext4 xattr block". **A real
  constraint any generalized client inherits** — see storage.md.

**batchPutCoalescer** (`batchput.go:53-115`): a **fixed 50 ms window**
(`batchput.go:37`), unlike the GET side. Flushes on count (128), on the window,
or on drain. `buildPutTar` (`batchput.go:123-166`) writes manifest-first, then
`data/<key>` members, all in memory (`bytes.Buffer`).

`sendBatchPut` (`batchput.go:168+`) outcome handling, from its doc comment:
- per-object `stored`/`conflict` → keep the claim;
- `dropped` → keep the claim, no retry;
- `error` → roll back **only that object's** claim;
- `404`/`405` → set the sticky `batchPutUnsupported` flag and re-issue every
  object through `putSingle`;
- whole-request failure after retries → roll back **all** claims.

**Generic apart from the two guards.** The sticky-downgrade-on-405 pattern is
what lets one client speak to servers of two vintages.

## 7. Look-ahead / prefetch

`lookahead.go`. The reasoning is in the file header (`lookahead.go:14-39`) and
in `docs/look-ahead.md`, and it is **not Go-specific at all**:

> A build asks for one key at a time, in dependency order. ... the number of
> keys a build has outstanding is its own `-p`. No amount of batching on the
> client changes that.

Design:
- A pool of `4*NumCPU` workers clamped to [8,64], queue depth `workers*8`
  (`lookahead.go:128-137`).
- Seeded **only by keys that hit** (`batch.go:359`), deduplicated by a
  `set.Set[string]` so a key is never seeded twice (`lookahead.go:52-54`).
- `expand` (`lookahead.go:229-321`) POSTs
  `{"keys":seed,"prefetch":true,"prefetch_only":true}` with
  `X-Cache-Kind: look-ahead`. `prefetch_only` keeps the seed's own bodies off
  the wire.
- **A byte budget, not an entry count.** `lookAheadBudget()` = 32 MiB default
  (`lookahead.go:74-76`); `chunkBudget` divides it across workers with a
  256 KiB floor (`lookahead.go:114-126`). The comment at `lookahead.go:55-66`
  names the bug: "The server caps a window at maxPrefetchEntries, which counts
  ENTRIES. A count is not a size. ... That is how a windows runner reached 'Out
  of memory' with an empty log."
- Over budget → the seed goes **on the floor**, never waits
  (`lookahead.go:236-240`). "A build goroutine must never wait on it."
- `OnBatchEntries == nil` short-circuits `expand` at its first line
  (`lookahead.go:232`). docs/look-ahead.md records that the old shape rode the
  critical-path request and was *slower than no prefetch at all* on loopback.

Benchmark from `docs/look-ahead.md` (BenchmarkBuildShape, 12-level graph, 4 wide):

| | wall | bytes | allocs |
|---|---|---|---|
| loopback, none | 23.96 ms | 4.2 MB | 6,592 |
| loopback, blocking | 26.51 ms | 5.0 MB | 17,023 |
| loopback, lookahead | 5.01 ms | 1.2 MB | 5,410 |
| 5 ms RTT, none | 152.88 ms | 4.1 MB | 6,580 |
| 5 ms RTT, blocking | 147.04 ms | 5.0 MB | 17,406 |
| 5 ms RTT, lookahead | 36.13 ms | 1.2 MB | 5,379 |

4.2–4.8x against fetching nothing ahead; 4.1–5.3x against the old blocking shape.

**Whether this transfers to a compiler wrapper is the open question** — see
index-and-prefetch.md §"Does a C++ build have a critical path?".

## 8. Resilience

`web_resilience.go`:
- `defaultMaxRetries = 2` (`:22`), `retryBaseDelay = 100ms`,
  `retryMaxDelay = 2s` (`:28-29`).
- `transientStatus` = `>= 500 || 429` (`:119-121`). A 4xx is definitive.
- `parseRetryAfter` handles both delta-seconds and HTTP-date, capped at
  `retryMaxDelay` so "a server cannot pin a retry far into the future"
  (`:128-155`).
- `sleepBackoff` uses **full jitter** (`rand.Int64N(d+1)`) "so parallel builds
  don't sync into a thundering herd" (`:233-252`).
- **No `http.Client.Timeout`** (`web.go:262-273`): a whole-request deadline kills
  a healthy large transfer. Liveness comes from `ResponseHeaderTimeout` (30s)
  plus a per-read stall watchdog (`guardedBody`, `:42-60`, `stallTimeout` 30s).
  This mirrors the server's `stallguard.go` exactly.
- **HTTP/1.1 forced off HTTP/2** (`web.go:246-256`): "H2 multiplexes every
  request onto ONE TCP connection, so MaxConnsPerHost stops meaning anything."
  `MaxConnsPerHost = 64` (`web.go:21`).
- `CheckRedirect` preserves method and re-supplies the body via `GetBody`
  (`web.go:274-296`).
- **Empty-batch backoff** (`noteBatchEntries`, `:77-101`): after 24 consecutive
  empty batch responses, probing turns off for the run.

**All of this is fully generic and is, alongside the coalescers, the strongest
reuse candidate in the module.**

## 9. The client-side index

`web_index.go`:
- Disk copy at `<IndexDir or os.TempDir>/gocache-web-index-<16hex>.bin`, the hex
  being `sha256(endpoint + "/" + bucket + "/" + prefix)[:8]` (`:80-88`) — so two
  caches on one machine do not collide.
- `IndexMaxAgeDefault = 1 minute` (`web.go:45`). A copy younger than that is
  served **with no request at all** and counted authoritative (`:114-118`). The
  justification (`:102-111`) is that the blob is tens of megabytes and a test
  suite starts thousands of go commands a minute.
- `parseIndexBlob` (`:279-313`) validates magic, version, hash size, the
  length equation `24 + 32*count + 32 == len`, and the SHA-256 trailer. It
  **never reads the `generation` field** — which is exactly what let the server
  change that field's meaning to content-derived without a client change.
- Conditional GET with `If-None-Match`; a 304 refreshes the disk copy's mtime
  via `os.Chtimes` (`:139-146`).
- Its own header budget (10s) and stall timeout (10s), both bounding
  **silence, not duration** (`:20-27`).

`hashSet` (`hashset.go`) is the memory story: a **sorted slice** of 32-byte
arrays plus two small mutation sets compacted at 512 (`hashset.go:26-40`). The
comment quantifies it: a map of a million hashes cost 88 MiB, the slice costs
31 MiB, and one `go install std` went from a 463 MiB peak to 325 MiB.

**Go-shaped in the key type** (`actionHash = [32]byte`), generic in structure.
A variable-length key would need a different container and lose most of the win.

## 10. Reuse verdict for a compiler-wrapper client

### Reusable essentially verbatim (import the module, or lift the file)
- `logging.go` — the Logger seam.
- `web_resilience.go` — retry policy, jittered backoff, Retry-After, stall
  watchdog, transient-status classification, empty-batch backoff.
- `httperrlog.go` — error coalescing.
- `counter.go` — atomic counters, latency histograms, concurrency tracker.
- `batch.go`'s `streamBatchResponse` + the coalescer loop (key type aside).
- `batchput.go`'s tar builder, coalescer, and the sticky-405-downgrade.
- `prep.go` — the off-the-critical-path work pool.
- `lookahead.go` — the byte-budgeted speculative pool (whether you *seed* it the
  same way is a separate question).
- `compress.go` — magic-byte codec dispatch, `DecompressSized`, level env knob.
- `integrity.go` — `sha256(body) == declared` is exactly ccache's and Bazel's
  contract.
- The claim / `removeClaimed` / `reclaimAbsent` protocol.
- The `Bucket == "" → (nil, nil)` "no remote is not an error" policy.

### Go-cache-shaped, would need replacing
- `buildid.go` (all of it) — `ar`/`__.PKGDEF`/`build id "ACTION/CONTENT"`.
  A C/C++ analogue would be checking the `.o`'s embedded debug path or nothing
  at all; there is no generic equivalent.
- `modindex.go` — pure Go poison guard.
- `archive.go` (337 lines) — Go export-data / pkgbits parsing to extract
  `pkg`, `src`, `go-version`, `target` metadata. **Purely cosmetic**: it feeds
  the server's log label. A wrapper cache would parse nothing, or parse the
  compiler command line instead.
- `web_index.go` — the `actionHash = [32]byte` key model and the GBCI blob.
  Reusable only if api-cache keys are also 32-byte digests. (They plausibly are:
  a ccache-style key *is* a hash.)
- `parseActionHash`'s hex-only grammar (`web_index.go:59`).
- `config.go` — the `GO_BUILDCACHE_CONFIG` env contract.
- `Get`'s `(outputID, data, t, miss)` signature — GOCACHEPROG's shape. A wrapper
  entry is **multi-output** (`.o` + `.d` + stderr + exit status), so either the
  wrapper packs them into one blob before `Put` (the ccache "result file"
  approach), or this API needs widening. See storage.md §"multi-output".
