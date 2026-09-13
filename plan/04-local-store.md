# 04 — The local store

The on-disk cache: layout, the entry container, atomicity, integrity, restore, compression, eviction, stats. Every number here is from `plan/research/storage-protocol/`, measured on GitHub runners across ext4, NTFS and APFS.

## Layout

```
<dir>/
  api-cache.lock            exclusive flock at startup-sweep time only
  version                   the format fingerprint (derived, see below)
  stats/                    one counters file per shard prefix, see "Stats"
  log/                      per-build aggregated logs, see 08-cli-and-ops.md
  tmp/                      scratch, swept of .tmp-* at startup under the lock
  r/aa/bb/<rest of hex>     result entries, keyed by result key
  m/aa/bb/<rest of hex>     manifests, keyed by direct key
```

- **Fixed two-level sharding, one stat per miss.** ccache's dynamic 2-to-4 depth costs three stats on a miss, which is 4 µs on Linux and 35 µs on Windows (`local-layout.md`, "what a lookup costs"). Two hex characters per level is the convergent default of every tool surveyed.
- **Two key spaces, two prefixes.** Results and manifests are separate trees so eviction and stats can treat them differently, and so a key never needs a type byte read from the file to know what it is.
- **Nothing in xattrs, nothing in sidecars.** Metadata lives inside the entry. On NTFS every extra file costs a 22 µs stat; on any platform a sidecar can be orphaned. go-s3-server's xattr design is the wrong fit for a multi-output entry and shares a 4 KiB EA block on ext4.
- **The format fingerprint** is a hash of the entry format version, the manifest format version, the hash algorithm and the shard scheme, written to `version`. A mismatch at startup purges the tree, api-mirror's derived-fingerprint rule rather than a hand-bumped constant.

## The entry container: binpazer

One result is one file, a binpazer container (`refs/bin-file-fmt`, MIT). The mapping:

| Block | type | Content |
|---|---|---|
| Block Type Table | 65534 | interns the user types |
| `Directory` | 1 | JSON: format version, rule name and version, the invocation summary for `explain`, the exit code, `[{role, name, offset, size, codec, crc}]` |
| `Output` × N | 2 | one output's bytes: primary, dep, each derived sibling |
| `Stream` × 2 | 3 | stdout, stderr, verbatim (coloured) |
| `Raw` × N | 4 | a marker for an output stored as a sibling file, see "Restore" |
| Block Index + footer | 65533 | `footer → index → directory → seek` |

Why binpazer over a fixed-width table (`container-format.md`, "criteria table"): per-block compression with a codec registry so stderr stays stored while DWARF gets zstd; per-block CRC-32C over the stored bytes, checkable before any decoder runs; a spec with forward-compatibility rules; C and C++ readers in-tree, which matters if a native client is ever built. Its cost is measured: 187 µs versus 60 µs for a single-member read on the ubuntu runner, 71 µs versus 47 µs on the M1, against a 501 to 1,266 µs restore that follows. The read path is under 15% of the hit. Two implementation rules come from the same measurements:

- **Size every read.** `io.ReadAll` costs 77% more than a sized read; the directory carries every size.
- **Pool the codecs, use one-shot decode.** A fresh `lz4.NewReader` per member allocates 8.4 MB (identical on all three runners); a pooled `zstd.DecodeAll` allocates 60 bytes. The engine registers its own pooled codecs with binpazer's `RegisterCodec`.
- **Write through a seekable writer.** A streamed binpazer write leaves `file_length` at the sentinel and the reader never finds the index (reproduced on all three platforms). Entries are always written to a temp file and renamed, which is seekable, so this is free locally. For the remote, the entry is serialised to the scratch file first and then sent.

The manifest is a second, smaller binpazer container with `Paths`, `FileInfos` and `Candidates` blocks, CRC'd, uncompressed.

Roles in the directory are a small closed enum, not free strings, so a restored path can never be `../../etc/passwd` from a hostile entry: the engine maps role to the destination the current invocation named, and the entry only says which role a block is.

## Atomicity and durability

- **Write:** assemble in `tmp/` (same filesystem), CRC every block, rename into place. On NTFS rename over an open file fails (measured), so the store renames the old entry aside to a `.old-*` name and unlinks it after; a failure to unlink is a retry, never an error.
- **No fsync.** It costs +7% on ext4, +356% on APFS and +966% on NTFS at 512 KiB (`local-layout.md`). A torn entry after a power cut is a miss, because the read path verifies CRC-32C over the stored bytes before decoding. The checksum is not optional.
- **Restore:** each output is written to a temp file in the destination's directory and renamed, with the caller's umask and the stored executable bit. A reader of a half-restored entry sees the old file or the new one.
- **Startup sweep** of `tmp/.tmp-*` under the exclusive lock, lifted from go-s3-server's `NewStorage`.
- **NFS:** unlink tolerates `ESTALE`, the walk ignores `.nfs*` names.

## Integrity

CRC-32C per block over the stored bytes (binpazer `has_crc`), checked on every read. 23 µs per 512 KiB on x86, 67 µs on the M1. Never SHA-256 for integrity: 62x the cost on a machine without `sha_ni` for nothing, since integrity is not authenticity. An entry that fails its CRC is treated as a miss, deleted, counted (`corrupt_entry`), and logged once per build.

## Restore

The restore is where a hit spends its time (48x the read on ext4), so it is negotiated per platform and per filesystem at store-open time and cached in the store's runtime state:

| Filesystem | Method | Measured | Constraint |
|---|---|---|---|
| APFS, opt-in | `clonefile(2)` | 167 µs at 512 KiB, constant in size, 34x faster than copy at 5 MiB, safe to write to | the object must be stored uncompressed as its own file; not the default because compression matters more on a Mac |
| btrfs, XFS with reflink | `FICLONE` | not measured (no runner); expected to behave like APFS | same |
| ext4 (and the default everywhere) | read + write + rename | 1,266 µs at 512 KiB; `copy_file_range` buys nothing | none |
| NTFS | `CopyFileEx` | 903 µs at 512 KiB | none; ReFS could clone, unmeasured |
| any, `hard-link="safe"` rule and `restore="link"` setting | `link(2)` | 12 µs ext4, 272 µs APFS, 538 µs NTFS | cache file made read-only; mtime of the visible file is bumped with a `touch` so make and ninja see fresh output; never with compression |

`restore="auto"` probes once per store (a throwaway file, the way go-s3-server probes atime) and records which methods the filesystem supports, but **the default restore is copy on every platform, because copy is the only method compatible with a compressed entry.** Clone and link are opt-in (`restore="clone"`, `restore="link"`), and choosing either forces `compress="never"`. The reason the default is not clone on APFS, despite the 34x: a Mac is the machine where storage is the scarce resource (no expansion, expensive, fast CPUs), so the 1 ms per hit that decompression costs there (~4 s on a 4,000-file build) is worth 4.3x more entries in the same budget. A user who prefers speed over space sets `restore="clone"` and gets the measured 167 µs.

To make clone and link possible at all, the store uses ccache's raw-file escape: when the restore method is clone or link, the primary output is not embedded in the container but stored as a sibling file `<entry>_00`, and the container's `Raw` block records its role and size. The container keeps everything else. `clonefile` clones whole files, so a body inside a container can never be cloned; that is the whole reason for the escape.

**Both, on APFS, is a follow-up to measure:** APFS supports transparent per-file compression (decmpfs, the `com.apple.decmpfs` xattr plus the `UF_COMPRESSED` flag, with lzfse or zlib payloads; what the OS uses for its own files and what `afsctool` writes). A file stored that way reads as its uncompressed bytes to every reader, the kernel decompresses on read, and `clonefile` clones the compressed extents. If a Go writer can produce a valid decmpfs file (the format is documented and has several implementations), a Mac gets compression and clone at once. Listed in `12-decisions.md` decision 15 as the measurement that would change the APFS default.

## Compression

`compress="auto"` resolves per platform from the measurements in `compression.md`:

| Situation | Codec |
|---|---|
| restore by clone or link (opt-in) | none, mandatory |
| restore by copy, local (the default on every platform) | zstd level 1 on outputs larger than 64 KiB; `stored` for small members; the `.d` and stderr are stored when under a few KiB |
| remote store | the remote client's own setting, zstd-1 on a LAN, higher over a WAN; the entry carries the codec id per block so the two tiers can differ |

Local compression costs +48% on the hit path on ext4, +87% on NTFS and +143% on APFS, and buys capacity at ratio 0.23 on gcc DWARF. The default is zstd-1 everywhere: the hit-path cost is about a millisecond, the capacity is 4x, and on the platform where the cost is highest (APFS, fast CPU) storage is also the scarcest. `compress="never"` opts out; `restore="clone"` or `"link"` implies it. zstd-9 is disqualified (151 ms to store a 5 MB object for 15% fewer bytes than zstd-3), and in the Go zstd, level 1 and level 3 give the same ratio on this corpus.

## Eviction

An LRU bounded by `max-size`, with `max-age` as an off-by-default TTL. The mechanism is go-s3-server's two-walk sweep lifted as code (`eviction.go`, `atime.go`), which never lists a directory into memory, derives one cutoff from a bounded last-use histogram, and deletes below it in batches. Adaptations:

- Last use is `max(mtime, atime, in-memory record)`; the atime probe at store-open detects `noatime`. Without atime the store touches an entry on a hit, which ccache also does.
- On NTFS an unlink of an entry a reader holds fails (measured); the evictor skips it and retries on the next sweep, never treating it as corruption.
- Manifests are evicted after results (a dangling manifest candidate is a miss, which is safe); results are never refcounted.
- The sweep runs from the wrapper when the `stats` counters say the size crossed the threshold since the last sweep, under the lock, in the background of a miss, never on a hit path. `api-cache evict` runs it on demand.

## Stats

Counters per outcome and per reason, kept as ccache does: a small binary file per first-level shard, updated with a lock-free append and folded on read, so 32 parallel wrappers do not convoy on one file. `api-cache stats` reads them all. The counter names are the verdict vocabulary plus `hit_direct`, `hit_preprocessed`, `hit_remote`, `miss`, `stored`, `restored_bytes`, `corrupt_entry`, `evicted`, and the timings histogram per stage.

## Settings

```xml
<store dir= max-size= max-age= restore="auto|copy|clone|link" compress="auto|always|never|zstd:N|lz4"
       umask= read-only="false" temp-dir= sloppiness="time_macros,file_stat_matches"/>
```

Every attribute is a template. The environment and command-line spellings are in `08-cli-and-ops.md`.

## What is lifted from go-s3-server

Files, adapted rather than imported (go-s3-server is this org's own code): the `PutStream` shape (temp, threshold-free, rename), the `.tmp-*` startup sweep, `eviction.go`, `atime*.go`, and `lrucache.go` for the in-process memos. Not lifted: xattr metadata, the index, the guards, `compactKey`.
