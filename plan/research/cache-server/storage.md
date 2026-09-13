# Storage layer

`storage.go` (699 lines), `storage_unix.go`, `storage_windows.go`,
`cacheversion.go`, `metacache.go`, `cleanmemo.go`, `compactkey.go`,
`atime.go`, `eviction.go`, `lrucache.go`. Depth docs: `docs/eviction.md`,
`docs/hot-path-cpu.md`, `docs/memory-limits.md`.

This is a **local blob store with metadata**, used server-side. A wrapper cache
needs one of these on both ends (the local tier the wrapper hits first, and the
remote tier's disk).

## 1. Key → path

`isKeySafe` (`storage.go:162-174`) accepts only `[a-zA-Z0-9/_-]`. **Dots are
excluded on purpose**, which kills `..` traversal.

`keyToPath` (`storage.go:185-192`):
- safe key → `shardPath`: `go-buildcache/v1aabbccdd…` →
  `{dataDir}/go-buildcache/v1/aa/bbccdd…`. The split is on the *basename*:
  `name[:2]/name[2:4]/name[4:]` for names > 4 chars, one level for > 2, flat
  otherwise (`storage.go:194-208`).
- unsafe key → `{dataDir}/__hashed__/{h[:2]}/{h[2:4]}/{h[4:]}` where
  `h = hex(sha256(key))`, and the **original key is stored in an xattr**
  (`setOriginalKey`) so `pathToKey` can reverse it (`storage.go:210-253`).

**Fully generic and directly reusable.** Two-level sharding on a hex digest is
exactly what ccache does (`CCACHE_DIR/<1 hex>/<1 hex>/...`) and what Bazel's
disk cache does. The `__hashed__` escape hatch means *any* key string works,
including one with spaces or slashes — worth noting, because a compiler-wrapper
key namespace (`cxx/v1/<hash>`, `manifest/v1/<hash>`) fits the safe path
directly.

Reserved names skipped by every walk (`isReservedFile`, `storage.go:616-625`):
`.lock`, `.cache_version`, `.last_sweep`, anything with the `.tmp-` prefix, and
Windows sidecars.

## 2. Metadata: xattrs, two namespaces

Unix (`storage_unix.go`):
- User metadata → `user.s3.<key>` (`metaAttrPrefix`, `storage_unix.go:123`).
- Audit → `user.s3audit.<field>` (`auditAttrPrefix`).

**The namespace collision is load-bearing**: `"user.s3audit."` *begins with*
`"user.s3."`, so `isUserMetaAttr` (`storage_unix.go:125-127`) must exclude it
explicitly. Without that exclusion, audit fields read back as metadata named
`audit.uploader` and were emitted to every client as `X-Cache-Meta-Audit.*` —
"the uploader's identity and IP handed to anyone who could fetch the object"
(`storage_unix.go:115-122`). **A generalized design should just use two
non-prefixing namespaces.**

Audit fields (from CLAUDE.md and `handlers.go:373-384`): `uploader`,
`uploaded_at`, `client_ip`, `user_agent`, `content_length` (filled by
`PutStream` from the bytes actually streamed, `storage.go:344-346`).

### Protected vs optional metadata — a real constraint

`metadataProtectedKeys = set.Of("outputid", "compression")` (`storage_unix.go:32`).
Those are written **first**, and any error on them fails the PUT. Everything
else degrades: an `E2BIG`/`ENOSPC`/`EDQUOT` drops that key, counts
`s3_metadata_xattrs_dropped_total`, and logs (`storage_unix.go:62-78`).

The reason (`storage_unix.go:36-43`): **on ext4 without `ea_inode`, all of a
file's xattrs share one ~4 KiB EA block.** The client's `src` list was
uncapped, so a many-file package overflowed it, and the old behaviour (any
xattr error → 500) made "exactly the biggest packages permanently uncacheable."

**This is the single most important storage constraint for api-cache.** A
compiler-wrapper entry has *more* metadata to carry than a Go object: the
command line, the `.d` dependency list, the compiler version, the working
directory, the stderr. A `.d` file alone routinely names hundreds of headers.
**Putting that in xattrs will not fit.** The options are (a) keep only a few
fixed small fields in xattrs and put the rest *inside the blob* (ccache's
approach — see §7), or (b) sidecar files.

`getMetadata` reads via `listXattrs` + `getXattrBuf` into a **stack buffer**,
falling back to the size probe only on `ERANGE`, halving syscalls per read
(CLAUDE.md; `storage_unix.go:129+`).

Windows (`storage_windows.go`) keeps metadata in JSON sidecars with a full
lifecycle: `finalizeSidecars` renames them with the body (`:25`),
`removeSidecars` on delete (`:46`), `isSidecarName` keeps `Walk` from reading a
sidecar as an object (`:55`), `setMetadata` reads-merges-writes so it never
destroys another key (`:79`). `.originalkey` is its own file (`:120`).
Compile-checked, untested on Windows.

## 3. PutStream — the write path

`storage.go:265-378`:

1. `os.MkdirAll(dir)`, `os.CreateTemp(dir, ".tmp-*")` — temp in the **same
   directory** so the rename is same-filesystem.
2. `io.Copy(tmp, r)` — fixed 32 KiB buffer, **never buffers the whole body**.
   "resident memory per upload is flat regardless of object size."
3. **fsync only at or above `fsyncThresholdBytes` = 8 MiB** (`storage.go:62`,
   `:300-306`). Rationale (`:295-299`): a full fsync-per-PUT would throttle CI
   bursts, and "the client hash-verifies every download, so a rare torn small
   object costs one refused fetch, not correctness."
4. `write_once` applied **after** the body is on disk so the comparison streams
   two files rather than buffering either (`:312-334`).
5. `setMetadata(tmpPath, meta)` — onto the temp file, before the rename.
6. `setAudit` — **best-effort**, logged on failure, never fails the PUT.
7. `setOriginalKey` for a hashed key.
8. `os.Rename(tmpPath, path)` — atomic publish.
9. `finalizeSidecars` (Windows) — **failing here fails the PUT**.
10. `forgetClean(key)`, `forgetMeta(key)`, `Index.Put(key, n)`.

**Generic and a good template.** The ordering — metadata onto the temp inode
before the rename — is the right shape for any content-addressed store.

`write_once` config (`config.go:60-63`, defaults `action=allow`,
`notification=never`): `deny` + `always` → `ErrWriteOnceDuplicate`;
`deny` + `content_differs` → stream-compare via `filesEqual` (64 KiB chunks,
`storage.go:384-417`), equal is a silent success, different is
`ErrWriteOnceConflict` → 409.

## 4. Read paths

Four openers, deliberately distinct (`storage.go:478-583`):

| | metadata? | `get` metric? | last-access stamp? |
|---|---|---|---|
| `Stat(key)` | yes | no | no |
| `Open(key)` | yes | yes | yes |
| `OpenBody(key)` | **no** | yes | yes |
| `openRaw(key)` | no | **no** | **no** |

`openRaw` exists so an internal peek (module-index guard, self-heal hashing)
"neither double-counts the `get` storage op nor stamps last-access onto
candidates that are never served" (`storage.go:570-576`). **This distinction
generalizes directly** — any cache with speculative reads needs it, or its LRU
lies.

## 5. compactKey

`compactkey.go:355-379`. A key held as the inline 32-byte action hash, with a
`raw string` fallback for a non-conforming key. Comparable, so it doubles as a
map key. The stated cost it avoids: 80 bytes of string carrying 32 bytes of
entropy, per indexed object, per last-access record, per eviction candidate —
"at a million objects the string form costs hundreds of megabytes and gives the
GC a million more objects to chase."

**Reusable *if* api-cache keys are fixed-width digests.** With variable-length
keys the type degenerates to `raw` and buys nothing.

## 6. The two memo caches + LRU

Both are built on `lruCache` (`lrucache.go`): **byte-bounded, sharded**, with
`SetBudget` changing the bound at runtime. Each shard holds an equal slice of
the budget, so an insert evicts only within its shard and the hot path stays
lock-local. An entry larger than a whole shard's budget is **still held** —
"a cache that refuses to hold anything is a permanent miss."

**metadata cache** (`metacache.go`): key → `{modNano, size, []kvPair}`.
**Self-validating**: a hit is served only when a fresh stat matches the recorded
mtime and size (`metacache.go:76-78`). An overwrite makes a new inode, so stale
metadata cannot be served. The one mutation that does not move mtime — the
self-heal's `fsetxattr` — drops the entry explicitly via `forgetMeta`. Measured
cost avoided: ~42 µs per key of listxattr + per-attribute getxattr.

**known-clean memo** (`cleanmemo.go`): a *set* of action hashes whose body
already passed the module-index probe. Membership **is** the verdict, so an
entry is a constant 96 bytes. Forgotten on overwrite PUT, DELETE and eviction.
Explicitly "a probe-skip optimization, not the safety boundary".

Both are registered with the memory controller (`server.go:88-96`) and are the
first things given up under pressure.

**Generic pattern, Go-specific content.** For api-cache the clean memo has no
analogue (there is no poison to guard against), but the *shape* — memoize an
expensive per-key verdict, invalidate at every write point, bound it in bytes —
transfers if a wrapper cache ever needs a per-blob verdict.

## 7. Last-access tracking

`accessShards` (`eviction.go:24-100`): 256 shards keyed by `compactKey`,
allocated **only** when `EnableAccessTracking` is called, which `main.go` does
**only when the data_dir does not record file access times** (CLAUDE.md,
`atime.go`). `recordAccess` is a no-op while nil, so the read hot path pays
nothing on a normal mount.

`atimeIsRecorded` (`atime.go:36`) **probes the real data_dir at startup**: write
a throwaway file, backdate it by `atimeProbeAge` = 48h, read it, see whether
atime moved. That detects `noatime`, overlayfs, bind mounts and NFS rather than
inferring from mount options.

`lastUsedUnix(obj, memAccess)` (`atime.go:74-85`) = `max(mtime, atime, in-memory
record)`. A missing signal can only make an entry look **older**, never younger.

**mtime is never rewritten on read**, because the prefetch grouping keys on it
(`config.go:115-118`). That separation is a deliberate design decision worth
copying: write-time and use-time are different questions.

## 8. Eviction

`eviction.go`, `docs/eviction.md`. An **LRU bounded by `max_bytes`**; `max_age`
is an off-by-default second cutoff.

`Evict(maxAge, maxBytes, now)` (`eviction.go:168`) is **two walks, never a
list**:

- **Walk 1** `scanForEviction` (`:211`): total bytes plus a histogram of bytes by
  last-use in 10-minute buckets (`evictionBucketSeconds = 600`, `:136`). The
  histogram is bounded by the *spread* of last-use times, not by object count.
- Derive ONE cutoff: `max(ageCutoff, sizeCutoff)`. `sizeCutoff` (`:236`) walks
  buckets oldest-first accumulating until the running total covers
  `total - max_bytes`.
- **Walk 2** `sweepBelow` (`:278`): deletes below the cutoff in batches of
  `evictionBatchSize = 65536` (`:265`). **Each batch is de-advertised from
  `/_index` via `Index.RemoveKeys` BEFORE its files are unlinked.** It re-reads
  last-use, so anything read between the walks is spared.
- `evictOne(key, expectMtime)` (`:339`) **re-stats before deleting**, closing
  the overwrite TOCTOU, and drops the access record, the clean memo, the
  metadata entry and the Windows sidecars.

Peak sweep memory is a batch plus the histogram, not the cache.

Schedule (`docs/eviction.md`, `eviction.go:391-438`): `.last_sweep` marker in the
data_dir. No marker or a sweep at least an interval old → sweep now after a
**jittered 1–5 minute delay** that spreads restarting replicas; a more recent
sweep → wait out the remainder. Both halves matter: "A schedule that restarted
on every boot meant a deployment that rolls more often than the interval — which
is the production model — never swept at all."

`s3_cache_bytes` refreshes every 15 min on its own cadence (`:459`).

**Fully generic and, with the atime probe, notably better than what ccache
does** (ccache's `max_size` sweep is per-subdirectory and uses atime with no
probe). Directly reusable.

## 9. Cache version purge

`cacheversion.go`. `currentCacheVersion = 4` (`storage.go:47`), stamped in
`.cache_version`. A missing marker reads as version 1. A mismatch removes
**every entry** in `data_dir` before serving. Runs once, before serving, under
the data_dir's exclusive flock. `sweepTempFiles` (`:88`) clears `.tmp-*`
orphans at the same point — invisible to `Walk` and to eviction, so they leak
disk forever otherwise; safe because the flock guarantees no in-flight writer.

Version history is instructive: v3 purged possible module-index poison, v4
purged entries the retired executable-cache path stored as **directories**.

**Generic and worth copying.** A wrapper cache's result format will change; a
one-line constant bump that forces a rebuild is far cheaper than a migration.

## 10. What is missing for a compiler-wrapper cache

### Multi-output entries — the big gap

`Storage` is strictly **one key → one opaque body + a flat string map**. A
compile produces:
- the object file (`.o`),
- the dependency list (`.d` / `-MD` output),
- stderr (warnings — which **must** be replayed on a cache hit, or `-Werror`
  and warning-driven workflows break),
- the exit status,
- optionally `.gcno`, `.dwo`, `.su`, `-fprofile` outputs, `.gch`.

ccache solves this with a **result file**: one blob with an internal framed
format holding N embedded entries, each tagged by its output role. sccache does
the same with a serialized `CacheWrite`. Bazel instead uses a CAS: the Action
Result is a small proto naming several CAS digests.

Neither shape exists here. **Two ways to bridge:**

1. **Pack client-side.** api-cache's client packs `.o`+`.d`+stderr+status into
   one framed blob and PUTs that under one key. The server needs **zero**
   changes: it already stores an opaque body with a content address. The blob is
   self-describing, and the `outputid`/`content-sha256` metadata still verifies
   it end to end. This is the ccache model and it fits go-s3-server exactly as
   it stands.
2. **Multiple keys per entry.** `<hash>/obj`, `<hash>/dep`, `<hash>/err`. The
   store handles this fine (slashes are safe key characters), but each output
   costs a round trip, each is separately evictable — so an entry can lose one
   member and become silently incomplete — and `/_index` would advertise them
   as unrelated keys. **Do not do this** without an atomic grouping primitive,
   which the store does not have.

### Direct mode needs a *manifest* object

ccache's direct mode stores, per (preprocessor-input hash), a **manifest**: a
list of (included-header path, header hash) → result key. It is read-modify-write
(each new include set appends an entry), mutable, and grows.

Nothing here supports read-modify-write. `PutStream` is whole-object replace,
and `write_once: deny` actively fights it. A manifest would need either:
- append-only whole-object rewrite (read, merge, PUT — racy across machines,
  last writer wins, which for a manifest means losing entries), or
- a new server-side merge endpoint, or
- keeping manifests **local only** and treating the remote as result-store-only.

The third is what sccache does (no direct mode at all) and is much the simplest.
**Worth flagging to the planner as a real fork in the road.**

### Other gaps

- **No grouping / transaction.** No way to say "these N objects land together
  or not at all."
- **No per-object TTL or pinning.** A toolchain blob you never want evicted has
  no way to say so.
- **No compression by the store.** `compression.go`: "this server compresses
  nothing." Bodies arrive already compressed; the store is byte-for-byte. It
  even warns once at startup when `data_dir` sits on a ZFS dataset with
  `compression` set, because that is a second, wasted compression pass
  (`logCompressionAdvisory`, detection via a cheap `statfs` ZFS-magic check in
  `dirIsZFS`, then `zfs list`/`zfs get` probes; silent on every uncertainty).
- **No content-addressed dedup between keys.** Two action keys whose outputs are
  byte-identical (very common for C++ — the same header compiled under two
  targets) are stored twice. Bazel's CAS/AC split exists precisely for this.
  Adding it here would mean an indirection layer the protocol does not have.
- **No key namespacing.** One bucket string, checked for equality
  (`server.go:280`).
