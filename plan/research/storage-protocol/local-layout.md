# Local storage layout

How the four comparable systems lay a compiler-cache entry on disk, what each
choice costs, and what the measurements say about the two decisions that
actually matter: **one file per result or one file per output**, and **how the
outputs get back into the build tree**.

> Numbers in this file are labelled with where they came from. Anything marked
> `[sandbox]` is from the development VM, which runs many agents at once; it is
> noisy and indicative only. Anything marked `[ci]` is from a GitHub Actions
> runner via `.github/workflows/storage-protocol.yml`, with the run URL in
> `probes/ci-results-*/summary.md`.

## What a compiler-cache entry actually is

One compile produces more than an object file. ccache enumerates the full set
in `FileType` (`src/ccache/core/result.hpp`, GPL-3.0 — described, not copied):

| id | output | typical size |
|---:|---|---|
| 0 | object (`-o`) | 10 KiB – 5 MiB |
| 1 | dependency file (`-MF`) | 3 – 12 KiB of text |
| 2 | stderr | 0 – a few KiB |
| 3 | coverage notes, unmangled (`.gcno`) | tens of KiB |
| 4 | stack usage (`.su`) | small |
| 5 | diagnostics | small |
| 6 | split DWARF object (`.dwo`) | often larger than the `.o` |
| 7 | coverage notes, mangled | tens of KiB |
| 8 | stdout | usually empty |
| 9 | assembler listing | — |
| 10 | MSVC precompiled header | large |
| 11 | callgraph info (`.ci`) | small |
| 12 | IPA clones dump | small |
| 13 | MSVC source dependencies | small |
| 14 | SARIF diagnostics | small |

The comment on that enum is the interesting part: the ids "are written into the
cache result file" and "must never be changed or removed unless the result file
version is incremented". A numeric role id in the on-disk entry is a permanent
compatibility commitment; a string role name is not, but costs bytes and a
comparison. ccache chose the id.

Corpus used for every measurement below, built by `probes/gen-testdata.sh` from
real `gcc`/`g++ -g -O2` output (not synthetic buffers):

| file | what | bytes |
|---|---|---:|
| `small.o` | C, `-g -O2` | 10,192 |
| `mid.o` | C++ with `<iostream>`, `-g -O2` | 527,840 |
| `big_g1.o` | template-heavy C++, `-g1 -O2` | 1,490,368 |
| `big.o` | template-heavy C++, `-g -O2` | 5,040,832 |
| `mid.d` | dependency file | 9,111 |

## ccache (GPL-3.0 — behaviour described from the source, no code reused)

Source: <https://github.com/ccache/ccache>, `src/ccache/storage/local/localstorage.cpp`.

**Key.** A 20-byte BLAKE3 digest (`using Digest = std::array<uint8_t, 20>` in
`src/ccache/hash.hpp`), rendered as 40 hex characters.

**Path.** `get_path_in_cache(level, name)` spends one hex character per
directory level and puts the remainder in the filename:

```
<cache_dir>/<h0>/<h1>/<h2…39>              level 2
<cache_dir>/<h0>/<h1>/<h2>/<h3…39>         level 3
<cache_dir>/<h0>/<h1>/<h2>/<h3>/<h4…39>    level 4
```

`k_min_cache_levels = 2`, `k_max_cache_levels = 4`. The depth is **dynamic**:
`look_up_cache_file` tries every level from 2 to 4 and takes the first that
exists, and `move_to_wanted_cache_level` renames an entry deeper as the cache
grows (`k_max_cache_files_per_directory = 2000`). The cost is stated in a
comment right next to the constants: a **miss costs
`k_max_cache_levels - k_min_cache_levels + 1` = 3 stat calls**, not one.

There is no `.R`/`.M` filename suffix in current ccache. The entry *type*
(0 = result, 1 = manifest) is a byte in the cache-entry header, so a result and
a manifest are told apart by reading the file, not by its name. Two different
keys (the manifest key and the result key) give two different paths.

**Entry file.** Every entry — result or manifest — is one file with this shape
(`src/ccache/core/cacheentry.cpp`):

| field | type | notes |
|---|---|---|
| `magic` | u16 | |
| `entry_format_version` | u8 | currently 1 |
| `entry_type` | u8 | 0 = result, 1 = manifest |
| `compression_type` | u8 | |
| `compression_level` | u8 | zstd level, 0 = writer default |
| `self_contained` | u8 | false when raw files sit beside it |
| `creation_time` | u64 | |
| `ccache_version` | string | u8 length prefix |
| `namespace_` | string | u8 length prefix |
| `entry_size` | u64 | header + payload + epilogue |
| payload | bytes | compressed or not |
| checksum | 16 bytes | **XXH3-128 over header and payload**, stored uncompressed |

Two observations worth carrying forward. First, the checksum covers the header
*and* the payload and is written outside the compression, so integrity is
checkable without decompressing. Second, the header carries the writer's
version and a namespace string, which is how `ccache --evict-namespace` and
version-scoped invalidation work without a separate index.

**Result payload** (`src/ccache/core/result.cpp`, big-endian integers):

```
<payload>             ::= <format_ver:u8> <n_files:u8> <file_entry>*
<embedded_file_entry> ::= 0x00 <file_type:u8> <file_size:u64> <file_data>
<raw_file_entry>      ::= 0x01 <file_type:u8> <file_size:u64>
```

There is no offset table. Entries are read in order and each one's length is
known before its bytes, so a reader streams through; there is no seek to the
object without walking whatever precedes it. With `n_files` capped at a `u8`
and the object written first in practice, the walk is short.

The `raw_file_entry` variant is the important one. When `file_clone` or
`hard_link` is enabled, a large output is **not** embedded: it lives beside the
entry as `<entry_path>_<NN>` (`get_raw_file_path`, two hex digits of the file
number) and the entry records only its type and size. That is ccache admitting
that a container is the wrong shape when the restore wants to be a link or a
reflink — you cannot hard-link *out of the middle of a file*. Hence the manual's
"files stored in this way cannot be compressed" and "compression is disabled if
`file_clone` or `hard_link` is enabled".

**Manifest payload** (`src/ccache/core/manifest.cpp`) — the direct-mode second
level, the thing that turns "source + flags" into "which result key":

```
<payload>       ::= <format_ver:u8> <paths> <includes> <results>
<path_entry>    ::= <path_len:u16> <path>
<include_entry> ::= <path_index:u32> <digest> <fsize:u64> <mtime:i64> <ctime:i64>
<result>        ::= <n_indexes:u32> <include_index:u32>* <result_key>
```

Paths are interned once and referenced by index, because the same headers
recur across every result in the manifest. `k_max_manifest_entries = 100`
bounds the results per manifest and `k_max_manifest_file_info_entries = 10000`
bounds the include set; past those the manifest is discarded and rebuilt, which
is how an unbounded manifest is avoided without an eviction policy of its own.
mtime and ctime are stored in nanoseconds with `0 = not recorded`, which is the
"include file is too new to trust" guard.

**Stats and cleanup.** `get_stats_file(l1)` is `<cache_dir>/<l1>/stats` and
`get_stats_file(l1,l2)` is `<cache_dir>/<l1>/<l2>/stats`; the level-2 counters
are stored offsetted inside the level-1 file. Cleanup is per level-2 directory:
`clean_dir()` sorts that directory's files by **mtime** (`f1.mtime() <
f2.mtime()`) and deletes oldest-first until the directory is under
`max_size/256` and `max_files/256`. So the "LRU" is 256 independent LRUs, which
is why the manual says "only a subset of the cache is considered, so the oldest
entries aren't always removed first". Temp files older than `1h` are swept in
the same pass. Locks live in `<cache_dir>/lock/`: `auto_cleanup`, and
`subdir_<l1><l2>` per level-2 directory. Deletion goes through
`util::remove_nfs_safe()`, which tolerates `ENOENT` and `ESTALE` — the NFS
silly-rename `.nfsXXXX` problem.

**Defaults worth copying or rejecting** (ccache manual,
<https://ccache.dev/manual/latest.html>): `max_size` 5 GiB; `max_files` 0
(unlimited); `compression` true; `compression_level` 0 meaning "writer picks",
currently **zstd level 1**; `hard_link` false; `file_clone` false;
`inode_cache` true.

## sccache (Apache-2.0)

Source: <https://github.com/mozilla/sccache>, `src/cache/`.

**Path.** `normalize_key` in `src/cache/utils.rs` is three levels of one hex
character each: `abcdef` → `a/b/c/abcdef`. Fixed depth, no promotion.

**Entry file.** `CacheWrite`/`CacheRead` in `src/cache/cache_io.rs` build a
**ZIP** whose members are declared `CompressionMethod::Stored` but whose bytes
are **zstd streams** written by `zstd::stream::copy_encode`. So the zip is used
purely as a named-member directory; zip's own compression is bypassed. Member
names are the output paths for objects (`put_object(&key, …)`) plus the fixed
names `"stdout"` and `"stderr"`. Unix permissions are carried in the zip entry
(`opts.unix_permissions(mode)`) and restored on read. Compression level comes
from `SCCACHE_CACHE_ZSTD_LEVEL`, **default 3**.

This is a genuinely different bet from ccache's: zip's central directory gives
random access by name at the cost of ~110 bytes per member and a seek to the
end of the file. `get_object(name)` is a hash lookup, not a walk.

**Storage trait.** `get(key)`, `put(key, CacheWrite)`, `get_raw(key)`,
`put_raw(key, Bytes)`, `check()`, `location()`, `current_size()`, `max_size()`.
`get_raw`/`put_raw` exist specifically so a multi-level cache can move the
serialized entry between levels without decoding it — worth keeping as a
principle: **the level-to-level transfer moves the container, never the
members.** Local disk is an LRU bounded by `SCCACHE_CACHE_SIZE`, default 10 GB.

## Bazel disk cache and bazel-remote (Apache-2.0)

<https://github.com/buchgr/bazel-remote>. Two namespaces, both keyed by
lowercase hex SHA-256:

- `cas/<hash>` — content-addressed bytes. The name *is* the hash of the content.
- `ac/<hash>` — an `ActionResult` protobuf keyed by the action digest.

Bazel's local `--disk_cache` uses the same two-directory split, sharded two hex
characters deep. bazel-remote stores zstd-compressed by default and can serve
either encoding.

The split is the point: an `ActionResult` names its outputs by digest, so two
actions that produce byte-identical outputs store those bytes once. For a
compiler cache that matters more than it looks: the `.d` file and the stderr
for one translation unit are frequently identical across `-O0`/`-O2`, across
debug and release, and across every configuration that does not change the
include set. The object almost never is.

## go-s3-server (this org, reference material)

`storage.go`. One key, one blob, no container. `keyToPath` shards the
**filename**, not the key path: `go-buildcache/v1aabbcc…` becomes
`go-buildcache/v1/aa/bbcc…` — two levels of two hex characters, fixed. A key
that is not `[A-Za-z0-9/_-]+` is SHA-256'd into a separate `__hashed__/` tree
and the original key is kept in an xattr, so `pathToKey` can reverse it.

Metadata is filesystem xattrs, split into two namespaces: `user.s3.*` for
client metadata and `user.s3audit.*` for server-written audit fields, with
`isUserMetaAttr` excluding the audit namespace from reads so an uploader's IP
cannot leak back to a downloader as a metadata header. On Windows the same
information goes into JSON sidecars, and `finalizeSidecars` renames them with
the body so a sidecar is never orphaned under the temp name.

Writes are temp-file + rename on the same filesystem, with an fsync only at or
above `fsyncThresholdBytes` (8 MiB) — the justification being that the client
hash-verifies every download anyway. `NewStorage` sweeps orphaned `.tmp-*`
files at startup under an exclusive flock.

Three pieces of it are directly reusable for a compiler cache and three are
not. Reusable: the temp+rename+conditional-fsync write path; the `.tmp-*`
startup sweep; the two-walk size-bounded LRU in `eviction.go` (measure, derive
one cutoff, then delete, de-advertising each batch from the index *before*
unlinking). Not reusable as-is: one-key-one-blob has no place to put five
outputs; xattr metadata is a per-key `listxattr` + N × `getxattr` (~42 µs per
key by its own `docs/hot-path-cpu.md`, which is why `metacache.go` exists); and
the whole GBCI index is scoped to the `go-buildcache/v1<64-hex>` key shape.

## Measured: what a lookup costs

`probes/readcost_test.go`, hot page cache, ext4. `[sandbox]` — the CI numbers
supersede these.

| operation | ns/op |
|---|--:|
| `syscall.Stat` (hit) | 678 |
| `syscall.Stat` (miss, ENOENT) | 511 |
| `os.Stat` (hit, with FileInfo alloc) | 877 |
| open + close, 4 KiB file | 2,731 |
| open + read-all, 4 KiB | 3,261 |
| open + read-all, 200 KiB | 7,991 |
| open + read-all, 512 KiB | 20,030 |
| open + read-all, 5 MiB | 378,299 |

Three things fall out.

**1. A miss is a stat, and a stat is cheap.** 0.5 µs. ccache's dynamic depth
turns one miss into three stats — 1.5 µs — which is still nothing next to a
compile, but it is 3× for no benefit if the depth is fixed instead. A fixed
two-level shard costs one stat and needs no promotion logic, no
`move_to_wanted_cache_level`, and no rename racing another process.

**2. Open is 4× stat.** 2.7 µs to open and close a file you then read nothing
from. That is the tax a multi-blob layout pays per extra member.

**3. One container beats N blobs, and the gap is exactly the opens.** Same
540 KiB of payload, as one file or as four (512 + 8 + 4 + 16 KiB):

| layout | ns/op |
|---|--:|
| 1 open, read 540 KiB | 20,749 |
| 4 opens, read 540 KiB total | 30,509 |

+9.8 µs for three extra opens, ~3.3 µs each — consistent with the open+close
number. At 4,000 compiles that is 39 ms of wall clock across a whole build:
real, but far smaller than one compile. The container wins, but it wins on
*bytes-per-syscall*, not by an order of magnitude, and a CAS layout that
de-duplicates a `.d` file across twenty configurations may well pay for the
extra opens in disk space.

## Measured: what a restore costs

`probes/restore_test.go` (Linux only). This is the other half of a hit — the
outputs have to end up where the compiler would have written them.

| restore method | 200 KiB | 512 KiB | 5 MiB |
|---|--:|--:|--:|
| read + write + rename | 246.7 µs | 241.3 µs | 1,871 µs |
| `copy_file_range` + rename | 147.3 µs | 240.6 µs | 1,671 µs |
| `link()` (hard link) | 4.0 µs | 4.0 µs | 4.0 µs |
| `FICLONE` (reflink) | — | — | — |

`[sandbox]`. `FICLONE` returned `EOPNOTSUPP`: **ext4 has no reflink support.**
The probe skips rather than pretending, and that skip is the finding — reflink
restore is a btrfs/XFS-with-reflink/APFS feature, not something to design the
hot path around. On the filesystems that do support it, a clone is a metadata
operation like a hard link but stays copy-on-write, which is why ccache
documents `file_clone` as "completely safe to use" while warning that
`hard_link` corrupts the cache if anything writes to the restored file (and
mitigates it by making cached files read-only).

The numbers say the restore, not the lookup, is where a hit spends its time:
242 µs to put back a 512 KiB object versus 20 µs to read it. `copy_file_range`
is worth having — it is one syscall, it never moves bytes through userspace,
and on a reflink filesystem the kernel may turn it into a share — but on ext4
it buys 10–20%, not an order of magnitude. Hard-linking is 60× faster and
comes with a correctness cliff.

Platform equivalents: `copy_file_range(2)` on Linux, `clonefile(2)` on macOS
(APFS, always CoW), `FSCTL_DUPLICATE_EXTENTS_TO_FILE` on Windows (ReFS only).
`CopyFileEx` with `COPY_FILE_NO_BUFFERING` is the Windows fallback.

## Measured: hashing is the expensive part

| hash | 4 KiB | 200 KiB | 512 KiB | 5 MiB | throughput |
|---|--:|--:|--:|--:|--:|
| SHA-256 (`crypto/sha256`) | 11.5 µs | 560 µs | 1,421 µs | 14,380 µs | **365 MB/s** |
| CRC-32C (`hash/crc32` Castagnoli) | 0.16 µs | 8.4 µs | 21.2 µs | 247 µs | **24 GB/s** |

`[sandbox]`, on a CPU with **no `sha_ni`** (flags: avx2, avx512f, bmi2 — no
sha_ni). This is the single most important number in this document, because it
is the one that changes the design:

- Hashing a 5 MiB object with SHA-256 costs **14 ms** — comparable to the
  compile you are trying to avoid. On a CPU *with* SHA-NI, Go's `crypto/sha256`
  runs roughly 4–5× faster (~1.5–2 GB/s), so this is hardware-dependent in a
  way a build cache cannot assume.
- ccache does not use SHA-256. It uses **BLAKE3** (`src/ccache/hash.hpp`
  includes `blake3.h`), truncated to 20 bytes. BLAKE3's published single-thread
  throughput is around 1–3 GB/s on x86-64 with AVX2 and it does not depend on a
  crypto extension. The Go ecosystem's BLAKE3 (`zeebo/blake3`, CC0/BSD-2) is
  the obvious candidate; Go's stdlib has none.
- ccache uses **XXH3-128** for the entry checksum, not a cryptographic hash,
  because integrity is not authenticity. CRC-32C at 24 GB/s is effectively free
  and is what `binpazer` and go-s3-server both already use.

The split is: a **cryptographic** hash (BLAKE3) for the *key*, because the key
is a collision-security boundary; a **fast** checksum (CRC-32C or XXH3) for
*integrity*, because that is only catching a bad disk.

## The layout decision, as a table

| | one container per result | one blob per output + manifest blob (CAS) |
|---|---|---|
| opens on a hit | 1 | 1 + N (measured: +3.3 µs each) |
| dedupe of identical `.d`/stderr across configs | none | automatic |
| restore by hard link / reflink | impossible for an embedded member; needs ccache's `raw_file_entry` escape | natural — each blob is already a file |
| partial fetch (object only, skip stderr) | needs an offset table | free |
| atomic write | one temp+rename | N renames, or a rename of the manifest last |
| eviction | one file, one decision | manifest and blobs must be evicted together or refcounted |
| corruption blast radius | whole entry | one output |
| remote transfer | one body | N bodies, or one batch call |

The honest summary: the container is simpler and slightly faster on the hot
path; the CAS split is better on space and on partial fetch, and it is the only
one that makes hard-link/reflink restore natural. ccache ships **both** — a
container, with a raw-file escape hatch that turns the big member back into a
sibling file precisely when link-restore is wanted.

## Atomicity and platform notes

**Write.** Temp file in the same directory, fsync (or not — see below), rename.
On POSIX `rename(2)` is atomic within a filesystem; the temp file must
therefore be a *sibling*, not in `/tmp`. go-s3-server's `.tmp-` prefix plus a
startup sweep under an exclusive flock is a complete answer to the crash case.

**fsync.** go-s3-server fsyncs only at or above 8 MiB, on the grounds that the
client verifies the hash. For a *local* compiler cache the same argument is
stronger: a torn entry after a power cut is a cache miss, not a wrong answer,
*provided* the entry carries a checksum that the read path verifies. Skipping
fsync is worth roughly the cost of an fsync (hundreds of µs to milliseconds on
a real disk) per store.

**Windows.**
- No xattrs. Metadata goes in a sidecar (go-s3-server's `.audit` JSON) or
  inside the container. Inside the container is strictly better here: one file,
  no orphan sidecars, no `isSidecarName` filter in the directory walk.
- `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` fails if the destination is open
  without `FILE_SHARE_DELETE`. A concurrent reader of the old entry can
  therefore block the rename, where POSIX would simply let the old inode live
  on. The workaround is rename-to-a-random-name then delete, or retry.
- `MAX_PATH` is 260 unless long paths are enabled *and* the path is prefixed
  `\\?\`. A four-level shard plus a long cache root gets close.
- Hard links exist (`CreateHardLinkW`, NTFS) but the read-only-file protection
  ccache relies on behaves differently.

**NFS.** Deleting an open file leaves a `.nfsXXXX` silly-rename stub; the
directory walk must ignore it and the unlink must tolerate `ESTALE`. ccache's
`remove_nfs_safe` is the minimal handling. A cache on NFS also makes the
flock-based startup sweep unreliable.

## Sources

- ccache manual — <https://ccache.dev/manual/latest.html> (GPL-3.0 project;
  documentation and behaviour described here, no code copied)
- ccache source — <https://github.com/ccache/ccache>, files
  `src/ccache/core/{result,manifest,cacheentry}.cpp`,
  `src/ccache/storage/local/localstorage.cpp`, `src/ccache/hash.hpp` (GPL-3.0)
- sccache — <https://github.com/mozilla/sccache>, `src/cache/cache_io.rs`,
  `src/cache/utils.rs`, `docs/Configuration.md` (Apache-2.0)
- bazel-remote — <https://github.com/buchgr/bazel-remote> (Apache-2.0)
- Bazel remote caching docs — <https://bazel.build/remote/caching>
- go-s3-server — this org's `storage.go`, `eviction.go`, `docs/hot-path-cpu.md`
- BLAKE3 — <https://github.com/BLAKE3-team/BLAKE3> (CC0-1.0 / Apache-2.0 dual)
- xxHash / XXH3 — <https://github.com/Cyan4973/xxHash> (BSD-2-Clause)
