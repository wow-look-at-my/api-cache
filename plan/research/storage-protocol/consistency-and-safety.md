# Consistency and safety

The failure modes that matter for a cache whose output is fed straight into a
link step: read-after-write, concurrent writers of one key, corruption,
poisoning, eviction, and the staleness of the known-key index. Each section
says what the surveyed systems do and what it costs.

The premise throughout: **a compiler cache is allowed to miss, and is never
allowed to return the wrong bytes.** Every trade below resolves in that
direction.

## Read-after-write

**Local.** Temp file in the same directory, then `rename(2)`. POSIX rename is
atomic within a filesystem, so a reader either sees the old entry or the new
one, never a partial one. Two constraints: the temp file must be a sibling (a
cross-device rename is `EXDEV` and degrades to copy+unlink, which is not
atomic), and the directory entry's durability is separate from the file's.
go-s3-server's `PutStream` does exactly this and fsyncs only at or above
`fsyncThresholdBytes` (8 MiB), on the argument that the client hash-verifies
every download.

For a compiler cache the argument is stronger still: an entry that survives the
rename but not the crash is a **miss**, not a wrong answer, provided the read
path verifies a checksum. So the right rule is "cheap write, verified read",
and the checksum has to be non-optional for that to hold.

**Measured, that rule is worth far more off Linux than on it.** Adding an
`fsync` before the rename of a 512 KiB entry costs **+7% on ext4, +356% on APFS
and +966% on NTFS** (`local-layout.md`). Go's `File.Sync` issues `F_FULLFSYNC`
on darwin, a real barrier to the device rather than a flush of the OS cache,
which is the whole APFS gap. So "just fsync, it is cheap" is an ext4 belief. On
two of three platforms the fsync is the single most expensive operation on the
store path — more than the compression, the hashing and the lookup together —
and the checksum that makes it unnecessary costs 23–67 µs.

**POSIX rename semantics are also not universal.** `TestRenameOverOpenFile`
and `TestUnlinkOpenFile` measure it rather than assume it:

| | rename over an open file | unlink an open file |
|---|---|---|
| ext4 | succeeds; the handle reads the old bytes | succeeds; the handle keeps reading |
| APFS | succeeds; the handle reads the old bytes | succeeds; the handle keeps reading |
| **NTFS** | **fails**, "Access is denied" | **fails**, "used by another process" |

On Windows a concurrent *reader* of the old entry blocks the store, because
Go's `os.Open` does not request `FILE_SHARE_DELETE`. A store there must rename
the old entry aside and delete it later, or retry; and **eviction has the same
problem**, so an evictor must skip or retry an entry a reader holds and must
not read that failure as corruption. This is the one place where the POSIX
mental model produces a Windows bug rather than a Windows slowdown.

**Remote.** Object stores differ. S3 has been strongly read-after-write
consistent for new objects and overwrites since December 2020
(<https://aws.amazon.com/s3/consistency/>); GCS has always been strongly
consistent for object reads. A plain HTTP cache server backed by a local
filesystem is trivially consistent. The case that still bites is a **CDN or
caching proxy in front of the cache**: a 404 for a key that was just written
can be cached and served for the proxy's TTL. bazel-remote and go-s3-server
both expect to sit behind a trusted reverse proxy, and neither says anything
about negative caching, which is a gap worth naming.

**A local cache with a remote tier has a third case**: the local store writes,
the remote PUT is still in flight, and a second process on the same machine
reads. Both ccache and sccache resolve this by writing local-first and treating
the remote as best-effort — the remote PUT failing is not a build failure. That
is the only sane ordering, and it means the remote can be eventually consistent
without anyone noticing.

## Concurrent writers of the same key

Two processes compile the same translation unit and both try to store. Three
policies exist:

**Last writer wins.** What `rename(2)` does for free. Cheap, and correct when
the key is a sound hash of every input, because both writers are storing the
same logical result. The risk is not the race, it is the premise: if the key is
*under-specified*, last-writer-wins silently picks one of two different
answers. ccache's whole `sloppiness` config is a list of ways a user can make
that premise false on purpose.

**First writer wins.** A `link(2)`-based or `O_EXCL` create that fails if the
key exists. Cheaper on I/O (the loser does not write the bytes) and removes a
class of surprise: an entry, once stored, never changes.

**Content-equal check (go-s3-server's `write_once`).** On a PUT to an existing
key, stream-compare the new bytes against the stored ones (`filesEqual`,
64 KiB chunks). Equal bytes are an idempotent success. Different bytes are a
`409 conflict`. Configured as an object,
`{"action": "allow"|"deny", "notification": "never"|"always"|"content_differs"}`,
defaulting to `action=allow`, `notification=never`.

That third one is the valuable one and it is worth being clear about **why**:
a differing PUT to an identical key means the key is not capturing something
that matters — a compiler version, an environment variable, a `__DATE__`. As a
production policy it costs a full re-read of the stored object on every
duplicate PUT (measured: reading 512 KB from the page cache is 26 µs on ext4,
25 µs on APFS and **53 µs on NTFS**, so it is affordable everywhere). As a **diagnostic**, run with `notification=content_differs` and
`action=allow`: nothing breaks, and every log line is a real bug in the key
derivation. That is the single highest-value safety feature in this survey and
it costs almost nothing.

**Deduplicating the compile itself.** ccache and sccache do not; both let the
duplicate compile run. sccache's server does coalesce *identical in-flight
requests* within one process. A cross-process singleflight (a lock file per
key, losers wait) trades a compile for a lock, and is only a win when the
compile is long and the contention is real — the classic case being a
distributed build where twenty machines start the same file at once.

## Corruption detection

**The checksum has to exist, and it has to be checked on read.** Without that,
a torn write, a bad disk, or a truncated download becomes a corrupt `.o` handed
to the linker, and the symptom appears somewhere else entirely.

| system | checksum | covers | checked when |
|---|---|---|---|
| ccache | XXH3-128, 16 bytes | the entry header **and** the payload, stored uncompressed | on read, before decompression |
| binpazer | CRC-32C per block, optional (`has_crc`) | the **stored** bytes of that block, header included | on read, before the codec |
| bazel-remote / REAPI CAS | the key itself is SHA-256 of the content | the content | whenever anyone cares to |
| zip (sccache) | CRC-32 per member | the **uncompressed** member | by the zip reader |
| tar | none | — | — |
| go-s3-server | `outputid` xattr = SHA-256 of the decompressed body | the body | by the **client**, after download |

Two design points fall out of that table.

**Checksum the stored bytes, not the decoded bytes.** ccache and binpazer both
do; zip does not. Checking before decompression means a corrupt entry is
rejected without running a decoder over hostile bytes, and it is also the only
order that lets a proxy verify an entry it cannot decode.

**Cost.** CRC-32C runs at 23 GB/s on x86 and **7.2 GB/s on an Apple M1**
(`probes/readcost_test.go`), so a checksum over a 528 KB entry is 23 µs or
67 µs depending on the machine; the measured end-to-end cost of turning
per-block CRC on in binpazer was ~11% of pack time and free on read
(`container-format.md`). SHA-256 over the same bytes is 1,421 µs on a CPU
without SHA-NI — 62× more. There is no reason to use a cryptographic hash for
integrity. Two qualifications the three-platform run added: the margin is 14×
on x86 but only 3.3× on arm64, where SHA-256 has a mandatory hardware
instruction and CRC-32C's is narrower; and if the checksum ever shows up in an
arm64 profile the answer is XXH3, a software construction with a NEON path,
rather than a wider CRC instruction that does not exist.

**The go-s3-server self-heal precedent** (`selfheal.go`) is worth studying
because it is a real answer to a real production wedge rather than a
hypothetical. The situation: an object stored without its `outputid` xattr
cannot be verified by the client, so the client discards the download and
rebuilds — but the key stays advertised in `/_index`, so the client also skips
re-uploading it. The result is a **permanent forced miss** that never
self-corrects. The fix has three parts, and all three generalise:

1. **Repair, do not evict.** `outputID` is by definition
   `sha256(decompressed body)`, so it can be recomputed from the body and
   stamped back. The body, the audit xattrs and the index entry are untouched.
2. **Stamp through the same file descriptor you hashed** (`setMetadataFd` /
   `unix.Fsetxattr`). The earlier path-based version landed the *old* inode's
   hash on a body a concurrent overwrite PUT had just renamed into place,
   leaving `outputid != sha256(body)` permanently, which made every client
   discard and never re-upload. The metric `s3_outputid_mismatch_total` exists
   to count that.
3. **When repair is impossible, de-advertise rather than delete.** A body that
   cannot be decompressed is dropped from `/_index` (`Index.Remove`) and left
   on disk for forensics and for eviction. The next consumer re-uploads a good
   body. Deleting it would create an evict-and-re-upload churn loop that cannot
   be audited.

The general lesson: **an entry the client will always reject, but which the
server still advertises, is worse than a missing entry.** Any design with a
known-key index has to be able to withdraw a key from it, and has to have a
metric for how often that happens.

## Poisoning

Three distinct threats, with three different answers.

**A misbehaving compiler.** A miscompile, a flaky code generator, a compiler
reading something the key does not cover. The cache faithfully stores and
replays a wrong `.o`, and — worse than a one-off — replays it forever. Nothing
detects this: the bytes are self-consistent and the checksum passes. The only
mitigations are operational: a version/namespace component in the key so the
whole generation can be evicted at once (ccache's `namespace_` field in the
cache-entry header plus `--evict-namespace`), and a documented way to nuke.
A cache-version marker like go-s3-server's `.cache_version` file
(`currentCacheVersion`, purge-on-mismatch) is the same idea for the format.

**An under-specified key.** Strictly a bug in the key derivation, not an
attack, but it produces the same symptom and it is far more common. The
detector is the content-equal check above. The compile-semantics worker owns
what belongs in the key; the storage layer's contribution is the ability to
*notice*.

**A hostile writer on a shared remote.** Here the surveyed tools are unanimous
and blunt, and it is worth quoting the posture rather than paraphrasing it:
ccache's and sccache's model is that **a remote cache is trusted**. Anyone who
can write to it can execute code on every machine that reads from it, because a
cached `.o` gets linked and run. There is no signing, no provenance, no
sandbox.

The practices that follow, in increasing order of strength:

- **Split read and write credentials.** Every protocol in the survey supports
  it: ccache `read-only=true`, sccache `check() → CacheMode::ReadOnly`, Gradle
  `isPush=false` (and note that push-off is the *default* for Gradle's remote
  cache), bazel-remote's "unauthenticated read with authenticated write",
  Bazel's `--remote_upload_local_results=false`. go-s3-server has no read-only
  mode of its own — a credential either can PUT or cannot authenticate at all —
  which is a gap for this use case.
- **CI-only writes.** Only trusted builders populate the shared cache;
  developers read. This is the deployment pattern behind all of the above and
  it is the single most effective control, because it turns "anyone who can
  write" into "anyone who can merge".
- **Per-writer namespaces.** Untrusted writers get a prefix only they can read
  back. Removes sharing, which was the point.
- **Provenance metadata.** go-s3-server records `user.s3audit.uploader`,
  `uploaded_at`, `client_ip`, `user_agent` and `content_length` as xattrs in a
  namespace separate from client metadata, and `isUserMetaAttr` excludes the
  audit namespace from metadata reads so an uploader's identity and IP are
  never emitted back as `X-Cache-Meta-Audit.*` headers to a downloader. That is
  a nice detail: audit data that is *written* server-side and *not readable*
  client-side. It does not prevent poisoning; it makes the post-mortem
  possible, and that is worth the xattrs.
- **Signing.** Turborepo's `x-artifact-tag` HMAC is the only signing in the
  survey. It authenticates that an artifact came from someone holding the
  shared secret — which, when everyone holds it, authenticates very little.
  Real provenance would need per-writer keys and a verifying reader, and
  nothing here does that.

**Sandboxing the wrapper itself** is a separate concern. A compiler wrapper
runs on every compile, reads a config, and executes a program. Everything it
reads from the cache — paths inside an entry, a `.d` file it writes out — is
attacker-controlled if the remote is. Path traversal in a restored output path
is the obvious one: go-s3-server's `isKeySafe` rejects `.` outright to prevent
`..` traversal and hashes unsafe keys into a separate tree. Restored **output
paths** need the same treatment, and a role id (ccache's `FileType` `u8`) is
safer here than a stored path string precisely because it cannot express
`../../etc`.

## Eviction

**Local: LRU bounded by size.** The two implementations differ instructively.

*ccache.* Per level-2 directory, independently: `clean_dir()` lists that
directory, sorts by **mtime**, and deletes oldest-first until it is under
`max_size/256` and `max_files/256`. 256 independent LRUs, which is why the
manual admits "the oldest entries aren't always removed first". mtime, not
atime, so a *read* does not refresh an entry — ccache compensates by touching
entries on a hit. Cheap, approximate, no global lock, bounded work.

*go-s3-server.* Global, in two walks. The first measures total bytes and builds
a bounded last-use histogram; from that it derives **one** cutoff,
`max(ageCutoff, sizeCutoff)`. The second walk deletes everything below it, in
batches, **de-advertising each batch from the index before unlinking any file**
so a key is never advertised-but-deleted. `evictOne(key, expectMtime)` re-stats
before deleting, closing the overwrite TOCTOU. Last use is
`max(mtime, atime, in-memory record)`, and the in-memory access map exists only
when the data_dir does not record atime — `atimeIsRecorded` probes the real
directory at startup by writing a file, backdating it, reading it back and
seeing whether atime moved, which detects a `noatime` mount instead of silently
degrading to write-time-only eviction.

The ordering rule is the transferable one: **withdraw from the index, then
unlink.** The reverse order produces exactly the advertised-but-unservable
state that `s3_get_requests_total{outcome="miss_advertised_unservable"}` exists
to catch.

**Two-level entries make eviction harder.** A manifest (direct mode) points at
result keys; a CAS layout has an action-cache entry pointing at blobs. Evicting
the pointee and not the pointer leaves a dangling reference that reads as a hit
and fails on the fetch. Options, none free:

- Refcount. Correct, and now the cache has a mutable secondary index.
- Evict pointers before pointees, with a grace window. Approximate.
- Tolerate and repair: a dangling reference is treated as a miss and the
  pointer is dropped. Simplest, and it needs a metric so the rate is visible.

ccache sidesteps this by letting a manifest go stale: its result keys are
looked up normally, and a missing one is simply a miss
(`k_max_manifest_entries = 100` bounds the damage). That is option three, and
it works because a manifest is cheap to rebuild.

**Remote eviction** is the same LRU problem plus the observation that the
remote's hit rate is what justifies its existence: evicting an entry that ten
developers would have hit is ten rebuilds. go-s3-server refreshes
`s3_cache_bytes` every 15 minutes rather than only at sweep end, and warns
loudly at startup when neither `max_bytes` nor `max_age` is set, so unbounded
growth is at least noticed. GitHub Actions' 10 GB per-repository quota with LRU
eviction is the constraint most CI users will actually hit first.

## The known-key index and its staleness

A cached membership answer is an optimisation whose failure modes are
asymmetric, and getting the asymmetry right is the whole design.

| the index says | truth | consequence |
|---|---|---|
| present | present | correct |
| **absent** | present | a redundant upload. Wasted bandwidth, no wrong answer |
| **present** | absent | a fetch that 404s. Must degrade to a miss, never to an error |
| present | present but corrupt | the failure `selfheal.go` exists for |

So the rule is: **a stale index must only ever cost work, never correctness.**
Concretely, the client must treat a 404 on an advertised key as an ordinary
miss, and a PUT of something already present must be idempotent rather than a
conflict.

go-s3-server's freshness machinery is worth listing because each piece answers
a specific failure:

- **The ETag is content-derived.** The serialised `generation` field is the
  first 8 bytes of the hash body's digest, not a counter, so the blob — and
  therefore the ETag — is a pure function of the advertised key set. A restart,
  or a period of duplicate-only PUTs, reserialises byte-identically and the
  client keeps getting a 304. A counter would have invalidated a 40 MB
  download every time.
- **The blob is rebuilt at most once per interval** (`index_blob_interval`,
  15 s). Inside the interval a GET serves the previous blob. Under CI load the
  earlier behaviour rebuilt the blob on every GET and every client re-downloaded
  it.
- **A removal expires the blob at once**, because the false-positive direction
  (advertised but gone) is the one that costs a wasted fetch.
- **A PUT is an O(1) append** to an unsorted pending buffer under a
  microsecond-scale mutex; the sort, dedupe and serialise wait for the next
  `Blob()`. A writer never convoys on a global sort.
- **Rebuild merges, never clobbers.** `applyRebuild` installs a freshly walked
  index while *preserving* the pending buffers. The earlier version nil'd both
  and silently dropped every PUT that completed during the multi-second walk.
- **Client-side staleness** is bounded by `IndexMaxAge` (default 1 minute): a
  disk copy younger than that is used with no request at all. The cost is up to
  a minute of redundant uploads after someone else populates a key. The benefit
  is that a test suite starting thousands of `go` commands a minute does not
  download a tens-of-megabytes blob thousands of times.

**The size question this raises for a compiler cache.** go-s3-server's index is
32 bytes per key. At 100,000 entries that is 3.2 MB; at 1,000,000 it is 32 MB —
and the CLAUDE.md notes a 40 MB blob in production. A compiler cache with
direct mode has **two** key spaces (manifests and results), so the index is
larger for the same number of compiles. Options if that gets uncomfortable:
a Bloom or cuckoo filter (a 1% false-positive rate at ~10 bits per key is
1.25 MB per million, and false positives are the *cheap* direction — a fetch
that misses), or a prefix-sharded index where a client downloads only the
shards its keys fall in.

## Sources

- ccache manual and source — <https://ccache.dev/manual/latest.html>,
  <https://github.com/ccache/ccache>, `src/ccache/storage/local/localstorage.cpp`
  (`clean_dir`, `get_stats_file`, lock files, `remove_nfs_safe`) and
  `src/ccache/core/cacheentry.cpp` (checksum, namespace). GPL-3.0: behaviour
  described, no code reused.
- sccache — <https://github.com/mozilla/sccache>, `src/cache/cache.rs`
  (`Storage::check`, `CacheMode`) (Apache-2.0)
- bazel-remote — <https://github.com/buchgr/bazel-remote> (Apache-2.0)
- Bazel `--remote_upload_local_results` — <https://bazel.build/remote/caching>
- Gradle `isPush` default — <https://docs.gradle.org/current/userguide/build_cache.html>
- go-s3-server — `selfheal.go`, `index.go`, `eviction.go`, `storage.go`,
  `storage_unix.go`, `cacheversion.go`, `docs/eviction.md`,
  `docs/module-index-guard.md` in this org
- S3 strong consistency — <https://aws.amazon.com/s3/consistency/>
- Turborepo artifact signing —
  <https://turborepo.com/docs/core-concepts/remote-caching>
