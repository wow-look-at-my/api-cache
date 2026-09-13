# The key index and prefetch

The two mechanisms that make go-s3-server faster than a plain blob store, and
whether either transfers to a compiler-wrapper cache. Server side: `index.go`,
`batch.go`. Client side: `cacheclient/web_index.go`, `cacheclient/lookahead.go`.
Depth: `docs/look-ahead.md`.

## 1. What the index is

An in-memory structure with two independent halves (`index.go:43-84`):

- **`entries []indexEntry`** — `{compactKey, mtimeUnix}`, sorted by mtime.
  Serves `NearbyKeys` (prefetch selection) only. **Every** stored key is here.
- **`hashes [][32]byte`** — sorted, deduplicated action IDs. Serves the GBCI
  blob and `Contains`. Only keys matching `go-buildcache/v1<64 hex>` are here
  (`index.go:167-170`).

Plus two unsorted append-only buffers, `pending` (hashes) and `pendingEntries`
(mtimes), so `Put` is **O(1) under a microsecond-scale mutex**
(`index.go:150-171`). The O(n log n) work is deferred to the next reader:
`drainEntriesLocked` for the mtime list, `Blob()` for the hash list.

The comment names the bug this fixed (`index.go:47-55`): `Put` used to re-sort
the whole mtime list on every call under the same lock, "which serialized
writers into a lock convoy under the concurrent CI matrix load — the upstream
stall a fronting proxy reported as a 502."

### Rebuild merges, never clobbers

`rebuild` (`index.go:~560`) streams `Storage.Walk` into an `indexBuild`, sorts
and dedupes **off-lock** (`finish()`), then `applyRebuild` installs the master
lists while **preserving the pending buffers** (`index.go:~600-640`). The old
code nil'd both, silently dropping every PUT that completed during the
multi-second walk. Those keys then vanished from `/_index` until the next
rebuild — i.e. the next eviction sweep — "forcing misses and duplicate
re-uploads right after every sweep."

`RemoveKeys` (`index.go:232-275`) batch-drops a victim set in one O(n+v) filter
pass, and the eviction sweeper calls it **before** unlinking any file.

## 2. The GBCI blob and ETag purity

Layout is in wire-protocol.md §5. The two properties worth restating:

**Content-derived generation.** The `generation` field at offset 8 holds the
first 8 bytes of `sha256(hash body)`, not a counter. The comment
(`index.go`, in `Blob()`) records exactly why: a monotonic counter sat inside
the hashed region, so duplicate-only PUT traffic produced a new ETag on every
reserialization and "forced every client into a pointless multi-MB `/_index`
re-download with zero informational gain." Now identical key sets serialize
byte-identically, so `If-None-Match` answers 304 across duplicate PUTs **and
across server restarts**.

The client never reads the field (`cacheclient/web_index.go:279-313` validates
magic, version, hash size, length equation and trailer only), which is what let
the server change the field's meaning with no client change. **A good lesson:
put change-detection in the content, and validate only what you need.**

**Serialization interval.** `defaultIndexBlobInterval = 15s` (`index.go:88`),
overridable by `index_blob_interval` (`config.go:176-179`, `"0s"` is what the
dats suite uses). Inside the interval a GET serves the previous blob and its
ETag. A removal expires it at once by zeroing `builtAt`
(`index.go:218`, `:271`). Cost of a key stored inside the interval: it is
treated as a miss and stored again, which the store answers as a duplicate.

## 3. The client side of the index

`cacheclient/web_index.go`:
- Disk copy keyed by `sha256(endpoint + "/" + bucket + "/" + prefix)[:8]`.
- **`IndexMaxAge` default 1 minute** (`web.go:45`). A copy younger than that is
  served with **no request at all** and counted authoritative. Justification
  (`web_index.go:102-111`): "A test suite starts thousands of go commands a
  minute, and the blob is tens of megabytes."
- Loaded lazily under `sync.Once` on the **first Get or Put** (`web.go:326-336`).
- A parse failure or fetch failure yields a **non-authoritative** set: Get/Put
  still work, but absences prove nothing so cold keys are batch-probed.

The blob at production scale is stated in `docs/look-ahead.md` as **over 750,000
keys** and in `cacheclient/hashset.go:17-20` as "about 1,008,000 keys" ≈ **32 MiB
of key material**. That is the cost every process pays before it can tell a hit
from a miss, and it is why `IndexMaxAge` and ETag purity exist at all.

## 4. Prefetch: `NearbyKeys` by mtime

`Index.NearbyKeys(startUnix, endUnix, limit, exclude, skip)` (`index.go:365-405`):

1. Binary-search `entries` for the window start.
2. Collect every entry in `[start, end]` not in `exclude`, with its distance
   from the window midpoint.
3. Sort by distance.
4. Take the nearest `limit` the caller still wants.

Window is `[min(requested mtimes) - 30s, max + 30s]`
(`prefetchWindow = 30s`, `batch.go:87`), capped at
`maxPrefetchEntries = 200` (`batch.go:91`).

**The premise** (`docs/look-ahead.md`): "The objects one build writes land next
to each other in that order. So the window around a key this build just wanted
is mostly keys this build wants next."

### The skip-during-selection fix

`skip` is applied **during** selection, not after (`index.go:355-364`):

> A caller that filters the result instead gets the same keys proposed on every
> request: once the nearest limit candidates have all been rejected, the window
> never advances and the caller receives an empty set forever. That is exactly
> what happened to prefetch, where a client got one pool of entries and then
> nothing at all for the rest of its build.

The scan is budgeted at `nearbyScanFactor = 8` × limit examined candidates
(`index.go:407-412`), and hitting the cap increments
`s3_prefetch_scan_exhausted_total` — "never silent."

### The prefetch tracker

`prefetchTracker` (`batch.go:120-160`) remembers `"scope\x00key" → sent_at` in a
byte-bounded LRU, TTL 5 minutes (`batch.go:95`).

**The scope is the BUILD, not the user** (`batch.go:104-113`). It used to be the
user for five minutes, and "a user runs several builds in five minutes: the
first build received the window and every build after it received an empty one,
so a second build in a row fetched every object on its critical path and
finished slower than a build with no cache at all." The client supplies
`X-Cache-Build`, a random 16-byte hex per process (`cacheclient/web.go:555-568`).
A client that sends no build header falls back to the username.

Ordering in `handleBatchGet` (`batch.go:246-294`) is deliberate and cheap-first:
tracker suppression (one map lookup) → stat → module-index guard → self-heal.
Only keys **actually included** are recorded as sent, so a candidate the guard
dropped stays eligible.

## 5. Does any of this transfer to a C/C++ build?

### The key index: **probably not worth it, and here is why**

The index exists to answer one question with no round trip: *does the remote
hold this key?* For `cmd/go` that is worth 32 MiB of download because:

1. A Go build's action IDs are **computed from dependency output IDs**, so the
   key set a build asks for is deeply serialized and each miss costs a round
   trip on the critical path.
2. A `dist test` run starts **thousands of `go` processes a minute**, each of
   which would otherwise probe the remote for every cold key.
3. The client *also* uses it to **skip re-uploading** — arguably the bigger win,
   because a CI build offers thousands of objects and most are already there.

A ccache-style build is different in every one of those:

1. **A compile's cache key does not depend on another compile's output.** The
   key is `hash(compiler, flags, preprocessed source)` (or, in direct mode,
   `hash(source) + hash(each include)`). Every translation unit's key is
   computable **immediately and independently**. There is no dependency-ordered
   critical path through the cache at all. `make -j32` offers 32 keys at once
   and can offer the next 32 the instant a slot frees. **The entire reason the
   look-ahead pool exists does not apply.**
2. A build is typically **one long-lived wrapper invocation per TU**, or a
   daemon (sccache). Either way there is one process (or a handful) per build,
   not thousands.
3. The upload-skip win **does** still apply — but a client can get it far more
   cheaply than by downloading the whole key set (see below).

And the cost side is worse. A 32 MiB index is only 32 MiB because every key is
exactly 32 bytes. As soon as api-cache has more than one key namespace
(`cxx/`, `manifest/`, `link/`, per-toolchain), the blob either grows a
length-prefixed string format — several times larger, no longer memcpy-parsable
— or fragments into per-namespace blobs the client fetches several of.

**Recommendation to the planner: treat a downloadable key index as an optional
optimization, not a core protocol feature.** Specifically:

- **The cheap alternative to the index for the skip-re-upload win** is exactly
  what the batch protocol already gives you: a **key-existence probe**. Add
  `HEAD`-equivalent semantics to `/_batch/get` (`prefetch_only` with no bodies
  is nearly this already) or a small `POST /_batch/exists` returning a JSON
  bitmap. A build with 5,000 TUs issues ~40 such requests of 128 keys each,
  costing a few kilobytes, versus 32 MiB. The client then knows exactly what to
  skip uploading, which is the property `/_index` was bought for.
- **If** you keep an index, keep the two properties that make this one work:
  content-derived ETag (so unchanged key sets 304) and a serialization interval
  (so PUT traffic does not force re-downloads).
- A **Bloom filter** is worth considering and is not present here: a 1% FPR
  filter over a million keys is ~1.2 MB versus 32 MB, and a false positive costs
  exactly one wasted batch probe — which is the cost the non-authoritative path
  already pays. This is a real improvement over what go-s3-server does.

### Prefetch by mtime locality: **partly, and it needs a different anchor**

Does mtime locality hold for a C++ CI run? Yes, in the same shallow sense: one
CI job's objects are written within seconds of each other, so the ±30s window
around a key from build N is mostly other keys from build N. If build N+1 is the
same project one commit later, it wants mostly the same keys. So the
*correlation exists*.

But the *value* is much lower:

- The look-ahead pool exists to hide round-trip latency on a **serialized**
  critical path. A `-j32` C++ build has no such path: it can keep 32 requests in
  flight from the first second. The right answer there is **concurrency**, which
  the client already has, not speculation.
- The one place it does help is the **cold-start window**: the first few
  compiles of a build, before parallelism ramps. That is a small win.
- It also helps a **serial** build (`make` with no `-j`, or a link step chain),
  which does exist in the wild.

There is, however, a **better anchor available to a compiler-wrapper cache than
mtime**, and it is worth calling out: the build system knows the full TU list up
front. `compile_commands.json`, a ninja graph, or a make dry-run enumerates every
translation unit before the first compile. A wrapper that can see that list can
compute **every key at once** and issue one bulk existence probe plus a bulk
fetch — perfect prefetch, no heuristic, no server-side mtime index. mtime
locality is the fallback for a client that cannot see its own build graph, which
is exactly `cmd/go`'s position (the cacheclient is called from inside `cmd/go`
one action at a time).

**Recommendation: keep `prefetch` as an optional server capability with the
mtime heuristic as the default implementation, but design the client to prefer a
build-graph-derived key list when one is available.**

### What transfers unconditionally

- **Batch GET and batch PUT.** These are pure wins for any cache with many small
  objects, independent of key shape. One admission slot for N objects is the
  reason the server survives a CI burst at all.
- **The tracker's "scope is the unit of work, not the user" lesson.**
- **Skip-during-selection**, whatever the selection heuristic: filter the
  candidate stream, never the result set, or the window stops advancing.
- **The client's optimistic claim + rollback protocol** (`keys.Add` before the
  upload, `removeClaimed` on every failure path, `reclaimAbsent` on an
  authoritative absence). This works with an index, a Bloom filter, a probe, or
  nothing at all.
- **Byte budgets, not entry counts**, on anything speculative
  (`lookahead.go:55-66`). "A count is not a size" is the single most transferable
  sentence in the repo.
