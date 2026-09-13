# Local storage layout

How the four comparable systems lay a compiler-cache entry on disk, what each
choice costs, and what the measurements say about the two decisions that
actually matter: **one file per result or one file per output**, and **how the
outputs get back into the build tree**.

> **Where the numbers come from.** `[ci]` numbers are from a GitHub Actions
> runner via `.github/workflows/storage-protocol.yml` and are the ones to
> quote. `[sandbox]` numbers are from the development VM, which runs many
> agents at once; they are noisy and are kept only where CI has not replaced
> them yet.
>
> **`[ci] ubuntu-latest`** — AMD EPYC 7763 64-Core, 4 vCPU, **`sha_ni` and
> `avx2` present**, ext4 on Azure premium storage, Go 1.26.8, `-benchtime 2s`.
> Run: <https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981>.
> Raw files in `probes/ci-results-ubuntu-latest/`.
>
> **`[ci] windows-latest`** — same AMD EPYC 7763 hardware, NTFS on `D:`,
> MinGW g++, Go 1.26.8 windows/amd64, same run.
> Raw files in `probes/ci-results-windows-latest/`.
>
> **`[sandbox]`** — Intel Xeon @2.80GHz, 4 vCPU, **no `sha_ni`** (avx2,
> avx512f, bmi2), ext4 on a local virtio disk, Go 1.26.0, Firecracker VM.
> Raw files in `probes/results/`.
>
> The machines differ in exactly the ways that make the comparison useful: the
> CI Linux box has the SHA-256 instruction and slow storage, the sandbox has
> fast storage and no SHA-256 instruction, and the Windows box is the same
> silicon as the CI Linux box with a filesystem an order of magnitude slower
> per syscall.

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

`probes/readcost_test.go`, hot page cache, ext4.

| operation | `[ci]` ubuntu | `[ci]` **windows** | `[ci]` macos | `[sandbox]` |
|---|--:|--:|--:|--:|
| `syscall.Stat` (hit) | 1,734 | n/a | n/a | 678 |
| `syscall.Stat` (miss, ENOENT) | 1,178 | n/a | n/a | 511 |
| `os.Stat` (hit) | 1,896 | **22,157** | 1,917 | 877 |
| `os.Stat` (miss) | 1,333 | **11,732** | 1,685 | 713 |
| open + close, 4 KiB file | 5,434 | **24,482** | 9,121 | 2,731 |
| open + read-all, 4 KiB | 6,515 | **31,719** | 9,127 | 3,261 |
| open + read-all, 200 KiB | 14,068 | 40,802 | 15,580 | 7,991 |
| open + read-all, 512 KiB | 26,274 | 52,550 | 25,079 | 20,030 |
| open + read-all, 5 MiB | 181,487 | 539,352 | 374,867 | 378,299 |

All in ns/op. Four quite different machines, and the spread is the point.
The macOS runner is an Apple M1 on APFS, so it is a different ISA and a
different filesystem as well as a different OS.

**Windows is an order of magnitude slower per file operation.** Same CPU as the
Linux runner: `os.Stat` is **22.2 µs against 1.9 µs**, and opening and closing
a file is 24.5 µs against 5.4 µs. Reading a 4 KiB file runs at 129 MB/s. NTFS
plus Defender plus the Win32 path layer is a different cost regime, and any
design validated only on Linux will be wrong about Windows by 10×.

**macOS is on Linux's side of that line, not Windows'.** `os.Stat` is 1.9 µs,
statistically the same as ext4, and a 512 KiB read is 25.1 µs against ext4's
26.3 µs. Only the bare open is dearer (9.1 µs against 5.4 µs). So the
expensive-metadata problem is an NTFS problem, not a "not-Linux" problem, and
a design tuned for two of the three platforms should be tuned for Windows.

At 4,000 compiles, **one stat per lookup is 7.6 ms on Linux, 6.7 ms on macOS
and 89 ms on Windows**. ccache's 2-to-4-level probe (three stats on a miss) is
23 ms, 20 ms and 267 ms respectively. On Windows a fixed shard depth stops being a tidiness
preference and becomes a measurable win.

Three things fall out.

**1. A miss is a stat, and a stat is cheap everywhere but Windows.**
1.3 µs on Linux, 1.7 µs on macOS, 0.5 µs on the sandbox, **11.7 µs on
Windows**. ccache's
dynamic depth turns one miss into three stats. A fixed two-level shard costs
one stat and needs no promotion logic, no `move_to_wanted_cache_level`, and no
rename racing another process.

**2. Open costs ~3–5× a stat everywhere.** 5.4 µs Linux / 24.5 µs Windows /
9.1 µs macOS / 2.7 µs sandbox to open and close a file you then read nothing
from. That is the tax a multi-blob layout pays per extra member, and it is the
same multiple on every platform — macOS is the worst ratio at 4.8×, which is
why its four-blob penalty below is proportionally closer to Windows' than its
stat cost is.

**3. One container beats N blobs, and the gap is exactly the opens.** Same
540 KiB of payload, as one file or as four (512 + 8 + 4 + 16 KiB):

| layout | `[ci]` ubuntu | `[ci]` **windows** | `[ci]` macos | `[sandbox]` |
|---|--:|--:|--:|--:|
| 1 open, read 540 KiB | 27,746 | 53,900 | 26,814 | 20,749 |
| 4 opens, read 540 KiB total | 46,664 | **147,340** | 53,893 | 30,509 |
| difference | +18.9 µs (1.68×) | **+93.4 µs (2.73×)** | +27.1 µs (2.01×) | +9.8 µs (1.5×) |

Extrapolated to 4,000 compiles, the cost of splitting one result into four
files instead of one:

| | extra wall clock per build |
|---|--:|
| ubuntu-latest | 76 ms |
| **windows-latest** | **374 ms** |
| macos-latest | 108 ms |
| sandbox | 39 ms |

On Linux the container's win is real but modest — 76 ms across a build that
takes minutes. **On Windows it is 2.7× and 374 ms**, and on macOS 2.0× and
108 ms, and that is with only four members; a CAS layout that also fetches a
shared `.d` blob adds more. Note that macOS doubles its cost while having
Linux's stat price: this penalty is paid in *opens*, and macOS opens are dear. The
container wins on *bytes-per-syscall*, and Windows is where syscalls are
expensive enough for it to matter. A CAS layout that de-duplicates a `.d` file
across twenty configurations still saves disk, but it should expect to pay for
it in Windows latency.

## Measured: what a restore costs

`probes/restore_portable_test.go` on every platform, plus
`probes/restore_test.go` for the Linux-only syscalls and
`probes/restore_darwin_test.go` for `clonefile(2)`. This is the other half of a
hit — the outputs have to end up where the compiler would have written them.

**Every platform, the portable methods** (`[ci]`, µs):

| restore method | | 200 KiB | 512 KiB | 5 MiB |
|---|---|--:|--:|--:|
| read + write + rename | ubuntu | 479 | 1,266 | 12,641 |
| | windows | 844 | 903 | 3,136 |
| | macos | 322 | 501 | 2,549 |
| read + write + **fsync** + rename | ubuntu | 590 | 1,359 | 12,692 |
| | **windows** | **6,502** | **9,623** | **29,690** |
| | **macos** | **2,253** | **2,283** | 4,676 |
| `link()` (hard link) | ubuntu | 12.2 | 12.3 | 12.2 |
| | windows | 517 | 538 | 560 |
| | macos | 272 | 277 | 265 |

**Linux-only syscalls**, `[ci]` ubuntu:

| restore method | 200 KiB | 512 KiB | 5 MiB |
|---|--:|--:|--:|
| `copy_file_range` + rename | 507 µs | 1,279 µs | 12,734 µs |
| `FICLONE` (reflink) | unsupported | unsupported | unsupported |

`[sandbox]`, for contrast:

| restore method | 200 KiB | 512 KiB | 5 MiB |
|---|--:|--:|--:|
| read + write + rename | 246.7 µs | 241.3 µs | 1,871 µs |
| `copy_file_range` + rename | 147.3 µs | 240.6 µs | 1,671 µs |
| `link()` (hard link) | 4.0 µs | 4.0 µs | 4.0 µs |
| `FICLONE` (reflink) | unsupported | unsupported | unsupported |

Three results here were not visible before the other two platforms ran.

**`fsync` before the rename is nearly free on ext4 and ruinous elsewhere.**
On the Linux runner it costs 7–23% (1,266 → 1,359 µs at 512 KiB). On **NTFS it
costs 10.7×** (903 → 9,623 µs) and on **APFS 4.6×** (501 → 2,283 µs). Go's
`File.Sync` issues `F_FULLFSYNC` on darwin, which is a real barrier down to the
platter rather than a flush of the OS cache, and that is the whole gap on
macOS. The design consequence is that "fsync before rename" cannot be a
constant: on two of three platforms it is the single most expensive thing on
the hit path, more expensive than the compression, the hashing and the lookup
put together. It only buys anything if the read path does **not** verify a
checksum, and the read path should verify a checksum, which costs 23 µs.

**Hard linking is constant in the file size on every platform, but the constant
is not.** 12 µs on ext4, 272 µs on APFS, 538 µs on NTFS — so the celebrated
"39–104× faster than copying" is a Linux number. On macOS the win at 200 KiB is
1.2× and at 5 MiB 9.6×; on Windows 1.6× and 5.6×. Linking is still the right
restore for a large object everywhere, and it is still never the right restore
for a *compressed* cache, but on Windows it buys far less than the Linux
measurement suggests.

**`copy_file_range` still buys nothing on ext4**, confirming the earlier run:
507 µs against 479 µs at 200 KiB.

`TestReflinkSupport` reports `EOPNOTSUPP` on **both** Linux machines: **ext4 has
no reflink support**, and that answer is recorded in the results rather than
skipped over — reflink
restore is a btrfs/XFS-with-reflink/APFS feature, not something to design the
hot path around. On the filesystems that do support it, a clone is a metadata
operation like a hard link but stays copy-on-write, which is why ccache
documents `file_clone` as "completely safe to use" while warning that
`hard_link` corrupts the cache if anything writes to the restored file (and
mitigates it by making cached files read-only).

The numbers say the restore, not the lookup, is where a hit spends its time, on
every platform. Putting back a 512 KiB object against reading it:

| | restore | read | ratio |
|---|--:|--:|--:|
| ubuntu | 1,266 µs | 26.3 µs | **48×** |
| windows | 903 µs | 52.6 µs | 17× |
| macos | 501 µs | 25.1 µs | 20× |
| sandbox | 241 µs | 20.0 µs | 12× |

Either way the write dominates. Note that Windows, the platform with the most
expensive *lookup*, has the second cheapest *restore* — its per-syscall tax is
large and its per-byte throughput is fine, which is the same story the container
argument tells.

`copy_file_range` is worth having in principle — one syscall, no bytes through
userspace, and on a reflink filesystem the kernel may turn it into a share —
but measured it buys **nothing on the CI runner** and 10–20% on the sandbox. It
is not the optimisation it looks like on ext4.

Hard-linking is **39–104× faster on Linux** (1.2–9.6× on macOS, 1.6–5.6× on
Windows) and constant in the file size on all three, and it comes
with a correctness cliff: the cache entry and the build tree share an inode, so
anything that writes to the restored object corrupts the cache. ccache mitigates
by making cached files read-only and documents the risk; it also **disables
compression** whenever `hard_link` or `file_clone` is on, because you cannot
link into a compressed blob.

Platform equivalents: `copy_file_range(2)` on Linux, `clonefile(2)` on macOS
(APFS, always CoW), `FSCTL_DUPLICATE_EXTENTS_TO_FILE` on Windows (ReFS only).
`CopyFileEx` with `COPY_FILE_NO_BUFFERING` is the Windows fallback.
`clonefile(2)` is probed directly by `probes/restore_darwin_test.go`; its
verdict is in "The `clonefile` verdict" below.

## Measured: hashing is the expensive part

| hash | 4 KiB | 200 KiB | 512 KiB | 5 MiB | throughput |
|---|--:|--:|--:|--:|--:|
| SHA-256 `[ci]` ubuntu, **with `sha_ni`** | 2.7 µs | 129 µs | 331 µs | 3,302 µs | **1,588 MB/s** |
| SHA-256 `[ci]` windows, same silicon | 2.8 µs | 130 µs | 332 µs | 3,323 µs | 1,578 MB/s |
| SHA-256 `[ci]` **macos, Apple M1** | 2.1 µs | 92.6 µs | 247 µs | 2,409 µs | **2,177 MB/s** |
| SHA-256 `[sandbox]`, **no `sha_ni`** | 11.5 µs | 560 µs | 1,421 µs | 14,380 µs | **365 MB/s** |
| CRC-32C `[ci]` ubuntu | 0.17 µs | 8.7 µs | 23.2 µs | 236 µs | **23 GB/s** |
| CRC-32C `[ci]` windows | 0.17 µs | 8.8 µs | 23.2 µs | 240 µs | **23 GB/s** |
| CRC-32C `[ci]` **macos, Apple M1** | 0.51 µs | 26.5 µs | 67.3 µs | 753 µs | **7.2 GB/s** |
| CRC-32C `[sandbox]` | 0.16 µs | 8.4 µs | 21.2 µs | 247 µs | **24 GB/s** |

This is the single most important measurement in this document, because the
runners bracket the design question rather than answering it. Adding an Apple
M1 to the set changed the conclusion, which is the argument for having measured
three platforms rather than one:

- **The SHA-NI instruction is worth 4.3×** — 1,588 MB/s against 365 MB/s, same
  Go code, same `crypto/sha256`. Hashing a 5 MiB object costs 3.3 ms on the
  EPYC and **14.4 ms** on the Xeon, and 14 ms is comparable to the compile you
  are trying to avoid.
- **A build cache cannot assume the instruction is there.** SHA-NI shipped on
  AMD from Zen (2017) and on Intel mainstream desktop/server only from Ice Lake
  (2019) / Alder Lake; plenty of build machines and most CI VMs before that
  generation lack it, and the sandbox here is a live example.
- **SHA-256 is not slow on Apple silicon — it is the fastest of the four.**
  2,177 MB/s on the M1 against 1,588 MB/s on the EPYC with SHA-NI, from the
  same `crypto/sha256`. ARMv8's crypto extensions are mandatory on every Apple
  core, so on that platform there is no feature to be missing. The 4.3× spread
  is therefore **an x86 spread**, between machines that have SHA-NI and machines
  that do not, and not a spread between architectures.
- **CRC-32C is *not* machine-independent, and this is the finding that changed
  with the third runner.** 21–24 GB/s on all three x86 machines, because it is
  the `crc32q` instruction present on every x86-64 since SSE4.2 (2008) — but
  **7.2 GB/s on the M1**, 3.2× slower. Go's `hash/crc32` has an ARM64 assembly
  path using `CRC32CX`, so this is the hardware instruction on both; it is
  simply not as wide on this core. The practical effect is that the *margin*
  between an integrity checksum and a cryptographic hash collapses from 14× on
  x86 to **3.3× on arm64** (7.2 GB/s against 2.2 GB/s).
- ccache does not use SHA-256. It uses **BLAKE3** (`src/ccache/hash.hpp`
  includes `blake3.h`), truncated to 20 bytes. BLAKE3's published single-thread
  throughput is around 1–3 GB/s on x86-64 with AVX2 and it does not depend on a
  crypto extension. The Go ecosystem's BLAKE3 (`zeebo/blake3`, CC0/BSD-2) is
  the obvious candidate; Go's stdlib has none.
- ccache uses **XXH3-128** for the entry checksum, not a cryptographic hash,
  because integrity is not authenticity. CRC-32C is effectively free on x86 and
  still cheap on arm64, and is what `binpazer` and go-s3-server both already
  use. XXH3 is the better arm64 answer than CRC-32C if the checksum ever shows
  up in a profile, because it is a software construction with a NEON path rather
  than a fixed-width instruction.

The split is: a **cryptographic** hash (BLAKE3) for the *key*, because the key
is a collision-security boundary; a **fast** checksum (CRC-32C or XXH3) for
*integrity*, because that is only catching a bad disk. The measured argument for
BLAKE3 over SHA-256 is not that it is faster on the best machine — it is that
it is **uniformly** fast: SHA-256 varies 6× across the four machines here
(365 MB/s to 2,177 MB/s), and a cache whose per-compile cost swings by 11 ms
depending on the host is hard to reason about.

Two caveats the third runner added, and neither is fatal to the split:

1. The integrity checksum is cheap because of an instruction, and which
   instruction is fast depends on the ISA. Budget the checksum at **arm64's**
   7.2 GB/s, not x86's 23 GB/s: 67 µs on a 512 KiB entry rather than 23 µs,
   against a 501 µs restore on the same machine. Still 13% of the restore, still
   worth paying.
2. "Never use SHA-256 for integrity" holds, but the margin that makes it
   obvious is an x86 margin. On Apple silicon SHA-256 costs 3.3× a CRC and buys
   authenticity; the reason not to do it is that it is 3.3× for nothing, not
   that it is unaffordable.

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
*provided* the entry carries a checksum that the read path verifies. Measured,
skipping it is worth **+7% on ext4, +356% on APFS and +966% on NTFS** at
512 KiB — see the restore table. The ext4 figure is the one that makes fsync
look like a rounding error, and it is the only platform where that is true.

**Windows.** Measured above: every file operation costs ~10× its Linux
equivalent on the same silicon, which is the dominant Windows fact and the
reason the container-vs-blobs gap widens to 2.7× there. Beyond the timings:

- No xattrs. Metadata goes in a sidecar (go-s3-server's `.audit` JSON) or
  inside the container. Inside the container is strictly better here: one file,
  no orphan sidecars, no `isSidecarName` filter in the directory walk, and — at
  22 µs per stat — one fewer file to touch.
- `MoveFileEx(MOVEFILE_REPLACE_EXISTING)` fails if the destination is open
  without `FILE_SHARE_DELETE`, which Go's `os.Open` does not request.
  **Measured, not assumed** (`TestRenameOverOpenFile`): on NTFS the rename
  returns *Access is denied*, while on ext4 and APFS it succeeds and the open
  handle keeps reading the old bytes. A concurrent reader of the old entry can
  therefore block a store on Windows only. A store must rename the old entry
  aside and delete it, or retry.
- Unlinking an open file has the same split, which makes *eviction* racy too.
  `TestUnlinkOpenFile`: NTFS answers *the process cannot access the file because
  it is being used by another process*; ext4 and APFS both succeed and the
  handle keeps reading. Eviction on Windows must skip or retry an entry a reader
  holds, and must not treat the failure as corruption.
- `MAX_PATH` is 260 unless long paths are enabled *and* the path is prefixed
  `\\?\`. Measured (`TestLongPath`): a 356-character path works on the runner,
  as does 324 on Linux and 368 on macOS — so long paths are enabled there.
  That is a property of the *machine*, not of the OS, so a cache that shards
  deeply still has to handle the failure.
- Hard links exist (`CreateHardLinkW`, NTFS) but cost 538 µs against ext4's
  12 µs, and the read-only-file protection ccache relies on behaves differently.

**macOS and the `clonefile` verdict.** APFS is copy-on-write throughout, so
this is the one platform where a *clone* restore — a metadata-only copy that
stays safe to write to, unlike a hard link — should genuinely be available.
`probes/restore_darwin_test.go` calls it and reports the verdict either way
rather than skipping. The result is in "The `clonefile` verdict" section of
`README.md`'s open questions and in
`probes/ci-results-macos-latest/tables.txt`. One methodological note worth
keeping: the first version of that probe issued `syscall.Syscall(462, ...)`,
the BSD table number, and got `EINVAL`. That was macOS's deprecated generic
`syscall(2)` shim refusing the number, **not** APFS refusing the clone. The
probe now calls the real libSystem symbol through
`golang.org/x/sys/unix.Clonefile` and reports both results, because a wrong
answer to a capability question is worse than no answer.

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
