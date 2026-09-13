# Worker: storage-protocol

Local storage design and remote protocol design for api-cache. Evidence and
options; no decisions.

## Files

| file | what it covers |
|---|---|
| `local-layout.md` | ccache, sccache, Bazel/bazel-remote and go-s3-server on-disk layouts; the container-vs-CAS decision; measured lookup, restore and hashing costs; Windows, NFS and atomicity |
| `container-format.md` | tar, ccache's result format, a hand-rolled framed format, zip and **binpazer** as the multi-output entry container; measured framing overhead, pack/unpack, single-member extraction, and binpazer's streaming-writer gap |
| `compression.md` | zstd vs lz4 vs s2 vs none on real `-g -O2` objects; ratios, encode/decode throughput, the hot-local vs remote split, and the codec-instance trap |
| `remote-protocols.md` | go-s3-server native, bazel-remote HTTP, REAPI v2, ccache HTTP/Redis/storage-helper, sccache object stores, Gradle, GHA v2; whether one server can speak several; what AC/CAS buys and costs |
| `consistency-and-safety.md` | read-after-write, concurrent writers, corruption and self-heal, poisoning and trust, eviction, known-key-index staleness |
| `probes/` | every measurement, its source, and its results. `run.sh` regenerates. `gen-testdata.sh` builds the corpus from real compiler output |

## Where the numbers come from

`[ci]` numbers come from `.github/workflows/storage-protocol.yml` and are the
ones to quote. Raw artifacts are committed under
`probes/ci-results-<runner>/`, each with a `PROVENANCE.txt` naming the run URL,
the commit and the machine.

| label | machine |
|---|---|
| `[ci] ubuntu` | ubuntu-latest, AMD EPYC 7763, 4 vCPU, **`sha_ni`** + avx2, ext4, Go 1.26.8 |
| `[ci] windows` | windows-latest, same EPYC silicon, NTFS, MinGW g++, Go 1.26.8 |
| `[ci] macos` | macos-latest (see `probes/ci-results-macos-latest/`) |
| `[sandbox]` | development VM, Intel Xeon @2.8 GHz, **no `sha_ni`**, ext4 — noisy, many agents at once, kept only for contrast |

To start a run: write a UTC timestamp into `TRIGGER` and push.

The probes never skip. A missing corpus file is a fatal error, a codec that
cannot be built is a failure, and an unsupported filesystem capability is
reported as a stated verdict (`TestReflinkSupport`) rather than a silent skip.

## Summary

1. **A miss is a stat; a hit is a write.** `[ci]` a stat miss is 1.2 µs on
   Linux and **11.3 µs on Windows**; restoring a 512 KiB object costs
   **1,277 µs**. The write dominates a hit by ~50×, so lookup-side micro-design
   matters far less than the restore path does.
2. **Windows is a different cost regime on identical silicon.** `os.Stat` is
   19.2 µs against Linux's 1.9 µs; open+close 21.9 µs against 5.4 µs. Any
   layout validated only on Linux is wrong about Windows by ~10×.
3. **One container beats N blobs, and Windows is where it shows.** Same 540 KiB:
   1 open vs 4 opens is +19.6 µs (1.7×) on Linux and **+91.6 µs (2.6×)** on
   Windows — 78 ms vs **366 ms** across 4,000 compiles.
4. **`copy_file_range` buys nothing on ext4** (501 vs 474 µs at 200 KiB).
   **`FICLONE` is unsupported on ext4** on both Linux machines tested. Hard
   linking is 39–104× faster than copying and constant in size — and ccache
   disables compression whenever it is on, because you cannot link into a
   compressed blob.
5. **SHA-NI is worth 4.3×**: SHA-256 runs at 1,588 MB/s with it and 365 MB/s
   without, same Go code. CRC-32C is 21–24 GB/s everywhere. Use a
   cryptographic hash (BLAKE3, as ccache does) for the *key* and CRC-32C or
   XXH3 for *integrity*; never SHA-256 for integrity.
6. **zstd beats lz4/s2 by ~1.6× on ratio and loses by ~1.6× on decode.** On
   `-g -O2` objects: zstd-1 0.203–0.352, lz4 0.310–0.517. zstd decode is
   level-independent (~950 MB/s), so a slow encode is only a store-side cost.
7. **zstd-9 is disqualified: 171 ms to store one 5 MB object.** And in
   klauspost's Go zstd, **level 1 and level 3 give the same ratio** on this
   corpus while level 1 is 20% faster.
8. **Compression is a 46% slowdown on the hit path, not a 23× one** — the
   decode (597 µs) sits next to a 1,277 µs restore, not next to a 26 µs read.
9. **On a 1 Gbit LAN, compression is a wash on store and a win on fetch.**
   Below ~100 Mbit it wins both ways. So the codec belongs in the entry header,
   not in a constant.
10. **The codec-instance trap is worth more than the codec choice.** A fresh
    `lz4.Reader` per member costs **8.4 MB** of allocation; a pooled
    `zstd.DecodeAll` costs **59 B** for the same output, and is faster than the
    streaming path.
11. **tar's framing is 6–54× the alternatives** (+3,856 B on four members) and
    it has no index, so "read only the object" is a walk.
12. **binpazer fits the shape** — per-block compression with a codec registry,
    per-block CRC-32C over the *stored* bytes, a Block Index plus footer, MIT,
    with C and C++ readers in-tree — at ~3× a fixed-width table's
    single-member read (203 µs vs 64 µs) and 59 allocations against 1.
13. **binpazer's index needs a seekable writer.** A streamed write leaves
    `file_length` at the sentinel, the reader never finds the footer, and the
    linear-walk fallback reads the footer as a block header and reports
    corruption. Reproduced on all three platforms.
14. **The known-key index is the most valuable idea in the remote survey.**
    go-s3-server's `/_index` turns "does the server have this?" into a local
    binary search, with a content-derived ETag so a restart still 304s. No
    other protocol here has it; REAPI's `FindMissingBlobs` costs a round trip.
15. **Four of the seven remote protocols are the same protocol.** ccache HTTP,
    Gradle, sccache/WebDAV and bazel-remote's `/cas/` are all "GET/PUT an
    opaque body at a path" and can share one mux over one blob store. REAPI
    gRPC is a second front end. GHA v2 cannot be served at all.
16. **Shipping a `ccache-storage-<scheme>` helper** reaches stock ccache with
    ~200 lines over a Unix socket, with connection reuse already amortised.
17. **AC/CAS buys dedupe, integrity and partial fetch; it costs two round trips
    and a dangling-reference eviction problem.** For a compiler cache the
    object rarely repeats — the `.d` and stderr do.
18. **go-s3-server's `write_once` content-equal check is the cheapest key-bug
    detector available**: run it as `notification=content_differs,
    action=allow` and every log line is a real hole in the key derivation.
19. **Withdraw from the index, then unlink.** The reverse order produces
    advertised-but-unservable keys, which is the failure `selfheal.go` exists
    for; that whole mechanism is a consequence of keys that are not content
    addresses.
20. **A stale index must only ever cost work, never correctness**: a 404 on an
    advertised key is an ordinary miss, and a duplicate PUT is idempotent.
21. **Every shared cache in this survey says "trust the remote".** The real
    control is split read/write credentials plus CI-only writes; every protocol
    here supports it and go-s3-server is the one that does not.
22. **The three cheap safety features**, in order: a checksum over the stored
    bytes checked before decoding; a namespace/version component in the key so
    a bad generation can be evicted wholesale; provenance metadata written
    server-side and not readable client-side.
23. **Windows needs two probes no POSIX design thinks about**: rename over an
    open file and unlink of an open file, both of which POSIX allows and NTFS
    refuses without `FILE_SHARE_DELETE`. `restore_portable_test.go` reports the
    verdict per platform rather than assuming it.
24. **The corpus is the finding too**: 100 lines of template-heavy C++ with
    `-g` produces a **5 MB** object, and `-g1` produces 1.5 MB. Debug level
    moves entry size by 3.4× — more than any codec choice in this document.
25. **Nothing measured here is the bottleneck.** Every format, codec and
    protocol decision is worth tens to hundreds of microseconds per compile
    against a compile that takes tens to hundreds of milliseconds. The
    decisions that matter are the ones that change *round trips* and
    *correctness*, not the ones that change microseconds.

## Trade-off table

| decision | option A | option B | measured difference | what actually decides it |
|---|---|---|---|---|
| entry layout | one container per result | one blob per output + manifest (CAS) | A is 1.7× faster on Linux, **2.6× on Windows** | dedupe and link-restore want B; round trips and eviction simplicity want A |
| shard depth | fixed 2 levels | dynamic 2–4 (ccache) | dynamic costs 3 stats on a miss: 3.5 µs Linux, **34 µs Windows** | directory-entry counts at scale vs Windows stat cost |
| container format | binpazer (MIT) | fixed-width framed table | 203 µs vs 64 µs per member, 59 vs 1 allocs | binpazer brings a spec, C/C++ readers, per-block codecs and CRC; framing brings 3× and nothing else |
| container format | binpazer | tar | binpazer +576 B vs tar +3,856 B framing; 203 µs vs 141 µs read | tar is the interop answer and has no index; binpazer has both |
| checksum | CRC-32C per block | SHA-256 whole entry | 23 GB/s vs 0.37–1.6 GB/s | integrity is not authenticity |
| key hash | BLAKE3 | SHA-256 | SHA-256 swings **4.3×** on one CPU feature | uniformity, not peak speed |
| local compression | zstd-1 | none | +597 µs decode on a 1,303 µs hit path (+46%) | cache capacity vs hit latency; **none** is forced when restoring by link |
| local compression | zstd-1 | lz4 | zstd 0.234 vs lz4 0.372 ratio; lz4 decodes 1.6× faster | disk is cheap, latency is not |
| remote compression | zstd-1 | none | LAN: a wash. 20 Mbit: 162 ms saved per entry | link speed — so make it configurable |
| codec API | pooled `DecodeAll` | fresh stream per member | **59 B vs 8.4 MB** allocation | not close |
| remote protocol | native (index + batch) | bazel-remote HTTP | index removes a round trip per *check*; batch removes N−1 per fetch | interop vs build latency |
| remote protocol | one HTTP mux, many dialects | REAPI gRPC | four dialects are one protocol; REAPI is a second front end | REAPI reaches Bazel/Buck2/Pants and nothing else does |
| write policy | last-writer-wins | content-equal check (`write_once`) | one extra read of the stored object (26 µs) | the check is a free key-derivation bug detector |
| durability | fsync before rename | rename only | see `BenchmarkPortableRestoreCopyFsyncRename` | a torn entry is a miss, **if** the read path verifies a checksum |

## Open questions this worker did not settle

- **macOS `clonefile`.** Probed by `probes/restore_darwin_test.go`
  (`TestClonefileSupport` and `BenchmarkRestoreClonefile`, via `SYS_CLONEFILE`
  = 462). APFS is copy-on-write throughout, so this is the one platform where a
  clone restore should genuinely be available; the result is in
  `probes/ci-results-macos-latest/`.
- **Index size at scale.** go-s3-server's index is 32 B/key; a two-keyspace
  compiler cache (manifests and results) doubles that. A Bloom filter or
  prefix-sharded index is sketched in `consistency-and-safety.md` but not
  measured.
- **Whether `extractActionHash` can be generalised** so go-s3-server's index
  serves a non-Go key shape. That is a cache-server question, flagged here.
