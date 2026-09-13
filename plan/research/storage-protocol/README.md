# Worker: storage-protocol

Local storage design and remote protocol design for api-cache. Evidence and
options; no decisions.

## Files

| file | what it covers |
|---|---|
| `local-layout.md` | ccache, sccache, Bazel/bazel-remote and go-s3-server on-disk layouts; the container-vs-CAS decision; measured lookup, restore and hashing costs; Windows, NFS and atomicity |
| `container-format.md` | tar, ccache's result format, a hand-rolled framed format, zip and **binpazer** as the multi-output entry container; measured framing overhead, pack/unpack, single-member extraction, and binpazer's streaming-writer gap |
| `compression.md` | zstd vs lz4 vs s2 vs none on real `-g -O2` objects; ratios, encode/decode throughput, the hot-local vs remote split, and the codec-instance trap |
| `remote-protocols.md` | go-s3-server native, bazel-remote HTTP, REAPI v2, ccache HTTP/Redis/storage-helper, sccache object stores, Gradle, Turborepo, Nx, GHA v2; whether one server can speak several; what AC/CAS buys and costs |
| `consistency-and-safety.md` | read-after-write, concurrent writers, corruption and self-heal, poisoning and trust, eviction, known-key-index staleness |
| `probes/` | every measurement, its source, and its results. `run.sh` regenerates. `gen-testdata.sh` builds the corpus from real compiler output |
| `STATUS.md` | what the interrupted first session finished, what was left, and how the gap was closed |
| `PREDECESSOR-TRAIL.md` | the first session's own notes and its ordered tool-call log, recovered from its transcript |

## Where the numbers come from

`[ci]` numbers come from `.github/workflows/storage-protocol.yml` and are the
ones to quote. Raw artifacts are committed under `probes/ci-results-<runner>/`,
each with a `PROVENANCE.txt` naming the run URL, the commit and the machine.
**All three runners' quoted figures are from one run**,
<https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343>, because
a cross-platform comparison has to come from a single run.

| label | machine |
|---|---|
| `[ci] ubuntu` | ubuntu-latest, AMD EPYC 7763, 4 vCPU, **`sha_ni`** + avx2, ext4, gcc/g++, Go 1.26.8 |
| `[ci] windows` | windows-latest, same EPYC silicon, NTFS on `D:`, MinGW g++, Go 1.26.8 |
| `[ci] macos` | macos-latest, **Apple M1 (Virtual), arm64**, 3 vCPU, **APFS**, Apple clang, Go 1.26.8 |
| `[sandbox]` | development VM, Intel Xeon @2.8 GHz, **no `sha_ni`**, ext4 — noisy, many agents at once, kept only for contrast |

A second, identical run is committed at
`probes/ci-results-repeat-34729790831/` for two reasons: it carries the first
**correct** `clonefile(2)` probe, and it measures how far a CI figure moves
between runs (±2% on ubuntu, ±15–35% on the two shared-tenancy runners). Treat
every number here as good to a ratio, not to three significant figures.

To start a run: write a UTC timestamp into `TRIGGER` and push.

The probes never skip. A missing corpus file is a fatal error, a codec that
cannot be built is a failure, and an unsupported filesystem capability is
reported as a stated verdict (`TestReflinkSupport`, `TestClonefileSupport`)
rather than a silent skip.

## Summary

1. **A miss is a stat; a hit is a write.** `[ci]` a stat miss is 1.3 µs on
   Linux, 1.7 µs on macOS and **11.7 µs on Windows**; restoring a 512 KiB
   object costs **1,266 µs** on Linux. The write dominates a hit by ~48×, so
   lookup-side micro-design matters far less than the restore path does.
2. **Windows is a different cost regime on identical silicon, and macOS is
   not.** `os.Stat` is 22.2 µs on NTFS against Linux's 1.9 µs — but macOS's is
   1.9 µs too. Expensive metadata is an NTFS property, not a not-Linux
   property. macOS pays instead on the bare **open** (9.1 µs against 5.4 µs),
   which is the cost a multi-blob layout multiplies.
3. **One container beats N blobs on every platform.** Same 540 KiB, 1 open vs
   4: **+18.9 µs (1.68×)** on Linux, **+93.4 µs (2.73×)** on Windows,
   **+27.1 µs (2.01×)** on macOS — 76 ms, 374 ms and 108 ms across 4,000
   compiles.
4. **`clonefile(2)` works on APFS, and it is the best restore measured
   anywhere.** 167 µs for 512 KiB, **constant in file size**, 34× faster than
   copying a 5 MiB object — and unlike a hard link the result is safe to write
   to. Meanwhile `FICLONE` is `EOPNOTSUPP` on ext4 on both Linux machines and
   `copy_file_range` buys nothing there (507 vs 479 µs). **The restore method
   has to be per-platform**, and on the one platform where the cheap restore
   works, it forbids compressing the entry.
5. **`fsync` before rename costs +7% on ext4, +356% on APFS and +966% on
   NTFS.** Go issues `F_FULLFSYNC` on darwin. "Just fsync, it is cheap" is an
   ext4 belief; everywhere else it is the most expensive thing on the store
   path, and a 23–67 µs checksum on read makes it unnecessary.
6. **Hashing is where the ISA shows.** SHA-256 swings 4.3× on x86 with
   `sha_ni` (1,588 vs 365 MB/s) — but the **Apple M1 is the fastest of all at
   2,177 MB/s**, because ARMv8 crypto is mandatory. Conversely **CRC-32C is
   23 GB/s on x86 and only 7.2 GB/s on the M1**. So the "integrity is 14×
   cheaper than authenticity" margin is an x86 margin; on arm64 it is 3.3×.
   Use a cryptographic hash (BLAKE3, as ccache does) for the *key* because it
   is *uniformly* fast, and CRC-32C or XXH3 for *integrity*.
7. **zstd beats lz4/s2 by ~1.3–1.6× on ratio and loses on decode by 2.2× on
   x86 and 3.9× on arm64.** zstd-1 lands at 0.203–0.352 on GCC objects, lz4 at
   0.310–0.517. zstd decode is level-independent (~950 MB/s x86, ~730 MB/s
   arm64), so a slow encode is only a store-side cost.
8. **zstd-9 is disqualified: 151 ms to store one 5 MB object**, for 15% fewer
   bytes than zstd-3. And in klauspost's Go zstd, **level 1 and level 3 give
   the same ratio** on this corpus while level 1 is 20% faster.
9. **Compressing the local cache costs +48% of the hit path on ext4, +87% on
   NTFS and +143% on APFS.** The decode sits next to the restore, and on Apple
   silicon the decode is *larger* than the restore. The local codec is a
   per-platform question; the bigger lever is restoring by clone, which removes
   the decode entirely.
10. **On a 1 Gbit LAN, compression is a wash on store and a win on fetch.**
    Below ~100 Mbit it wins both ways. So the codec belongs in the entry
    header, not in a constant.
11. **The codec-instance trap is worth more than the codec choice.** A fresh
    `lz4.Reader` per member costs **8.4 MB** of allocation — *identical to four
    significant figures on all three runners*, which proves it is the library's
    shape and not any machine. A pooled `zstd.DecodeAll` costs **60 B** for the
    same output, and is faster than the streaming path.
12. **tar's framing is the only one that moves with the corpus** (+3,758 to
    +4,084 B on four members, against a flat +72 for a fixed table, +450 for
    zip and ~+580 for binpazer), because its cost is 512-byte rounding per
    member. It also has no index, so "read only the object" is a walk.
13. **binpazer fits the shape** — per-block compression with a codec registry,
    per-block CRC-32C over the *stored* bytes, a Block Index plus footer, MIT,
    with C and C++ readers in-tree. Its read costs **3.1× a fixed-width table's
    on the ubuntu runner but only 1.5× on the M1**: the overhead is CPU work
    plus small reads, so 3× is the worst measurement, not the typical one.
14. **binpazer's index needs a seekable writer.** A streamed write leaves
    `file_length` at the sentinel, the reader never finds the footer, and the
    linear-walk fallback reads the footer as a block header and reports
    corruption. Reproduced byte-identically on all three platforms.
15. **Per-block CRC is free.** ~11% on pack on ubuntu, inside the run-to-run
    spread on the other two, and free on unpack everywhere. Default it on.
16. **The known-key index is the most valuable idea in the remote survey.**
    go-s3-server's `/_index` turns "does the server have this?" into a local
    binary search, with a content-derived ETag so a restart still 304s. No
    other protocol here has it; REAPI's `FindMissingBlobs` costs a round trip
    and Turborepo's `HEAD` costs one **per key**.
17. **Five of the eight remote protocols are the same protocol.** ccache HTTP,
    Gradle, sccache/WebDAV, Turborepo and bazel-remote's `/cas/` are all
    "GET/PUT an opaque body at a path" and can share one mux over one blob
    store. REAPI gRPC is a second front end. GHA v2 cannot be served at all.
18. **Turborepo is the only protocol here with an end-to-end artifact
    signature** (`x-artifact-tag`) and the only one with a published
    machine-readable self-hosting spec. Everything else trusts the transport.
19. **Shipping a `ccache-storage-<scheme>` helper** reaches stock ccache with
    ~200 lines over a Unix socket, with connection reuse already amortised.
20. **AC/CAS buys dedupe, integrity and partial fetch; it costs two round trips
    and a dangling-reference eviction problem.** For a compiler cache the
    object rarely repeats — the `.d` and stderr do, and on macOS the `.d` is
    117 KB rather than 9 KB, which makes that dedupe worth more there.
21. **go-s3-server's `write_once` content-equal check is the cheapest key-bug
    detector available**: run it as `notification=content_differs,
    action=allow` and every log line is a real hole in the key derivation. It
    costs one re-read: 26 µs ext4, 25 µs APFS, 53 µs NTFS.
22. **Withdraw from the index, then unlink.** The reverse order produces
    advertised-but-unservable keys, which is the failure `selfheal.go` exists
    for; that whole mechanism is a consequence of keys that are not content
    addresses. And **a stale index must only ever cost work, never
    correctness**: a 404 on an advertised key is an ordinary miss, a duplicate
    PUT is idempotent.
23. **Windows breaks two POSIX assumptions, and this is now measured rather
    than assumed.** Rename over an open file and unlink of an open file both
    **fail** on NTFS and both **succeed** on ext4 and APFS. So a store must
    rename the old entry aside, and an evictor must skip or retry an entry a
    reader holds rather than read the failure as corruption. This is the one
    place the POSIX model produces a Windows *bug* rather than a slowdown.
24. **The corpus is the finding too.** The same 100 lines of template-heavy
    C++ with `-g` is a **5.0 MB object under GCC and 1.4 MB under Apple
    clang** — 3.7×, larger than any codec effect here — and `-g1` under GCC is
    1.5 MB. Clang's objects also compress *worse* (zstd-1 0.389 against GCC's
    0.234). Capacity planning is a per-toolchain question.
25. **Every shared cache in this survey says "trust the remote".** The real
    control is split read/write credentials plus CI-only writes; every protocol
    here supports it and go-s3-server is the one that does not. The three cheap
    safety features, in order: a checksum over the stored bytes checked before
    decoding; a namespace/version component in the key so a bad generation can
    be evicted wholesale; provenance metadata written server-side and not
    readable client-side.
26. **Nothing measured here is the bottleneck.** Every format, codec and
    protocol decision is worth tens to hundreds of microseconds per compile
    against a compile that takes tens to hundreds of milliseconds. The
    decisions that matter are the ones that change *round trips*,
    *correctness*, and *which platform you are on* — not the ones that change
    microseconds.

## Trade-off table

| decision | option A | option B | measured difference | what actually decides it |
|---|---|---|---|---|
| entry layout | one container per result | one blob per output + manifest (CAS) | A is 1.68× faster on ext4, **2.73× on NTFS**, 2.01× on APFS | dedupe and clone-restore want B; round trips and eviction simplicity want A |
| shard depth | fixed 2 levels | dynamic 2–4 (ccache) | dynamic costs 3 stats on a miss: 4 µs Linux, 5 µs macOS, **35 µs Windows** | directory-entry counts at scale vs Windows stat cost |
| container format | binpazer (MIT) | fixed-width framed table | 187 µs vs 60 µs per member on ubuntu, **71 µs vs 47 µs on the M1**; 59 vs 1 allocs | binpazer brings a spec, C/C++ readers, per-block codecs and CRC; framing brings 1.5–3× and nothing else |
| container format | binpazer | tar | binpazer ~+580 B vs tar +3,758–4,084 B framing; 187 µs vs 141 µs read | tar is the interop answer and has no index; binpazer has both |
| checksum | CRC-32C per block | SHA-256 whole entry | 23 GB/s vs 1.6 GB/s **on x86**; 7.2 vs 2.2 GB/s on arm64 | integrity is not authenticity — but the margin is 14× or 3.3× depending on the ISA |
| key hash | BLAKE3 | SHA-256 | SHA-256 spans **6×** across the four machines (365–2,177 MB/s) | uniformity, not peak speed |
| restore | copy + rename | `clonefile` / `link` | APFS clone **167 µs, constant, safe**; ext4 link 12 µs but unsafe; NTFS link 538 µs | what the filesystem supports — and a clone or link forbids compressing the entry |
| durability | fsync before rename | rename + verified checksum on read | **+7% ext4, +356% APFS, +966% NTFS** | a torn entry is a miss **if** the read path verifies; the checksum costs 23–67 µs |
| local compression | zstd-1 | none | **+48% ext4, +87% NTFS, +143% APFS** on the hit path | cache capacity vs hit latency; **none** is forced when restoring by link or clone |
| local compression | zstd-1 | lz4 | zstd 0.234 vs lz4 0.372 ratio; lz4 decodes 2.2× faster on x86, **3.9× on arm64** | disk is cheap, latency is not — and the gap is ISA-dependent |
| remote compression | zstd-1 | none | LAN: a wash. 20 Mbit: 162 ms saved per entry | link speed — so make it configurable |
| codec API | pooled `DecodeAll` | fresh stream per member | **60 B vs 8.4 MB** allocation, identical on three platforms | not close |
| remote protocol | native (index + batch) | bazel-remote HTTP | index removes a round trip per *check*; batch removes N−1 per fetch | interop vs build latency |
| remote protocol | one HTTP mux, many dialects | REAPI gRPC | five dialects are one protocol; REAPI is a second front end | REAPI reaches Bazel/Buck2/Pants and nothing else does |
| write policy | last-writer-wins | content-equal check (`write_once`) | one extra read of the stored object (26–53 µs) | the check is a free key-derivation bug detector |
| Windows store | rename over the old entry | rename aside, then delete | **rename over an open file fails on NTFS and succeeds on ext4 and APFS** | correctness, not speed |

## Open questions this worker did not settle

- **Index size at scale.** go-s3-server's index is 32 B/key; a two-keyspace
  compiler cache (manifests and results) doubles that. A Bloom filter or
  prefix-sharded index is sketched in `consistency-and-safety.md` but not
  measured.
- **Whether `extractActionHash` can be generalised** so go-s3-server's index
  serves a non-Go key shape. That is a cache-server question, flagged here.
- **Whether a clone restore is available on the machines that matter.** APFS
  says yes and ext4 says no; btrfs, XFS-with-reflink and ReFS are untested
  because no runner here has them. Since the clone is the best restore measured
  and it changes the compression answer with it, this is the single highest-value
  follow-up measurement.
- **A repetition count.** Every figure is `-count 1`. The repeat run shows
  ±15–35% on the shared-tenancy runners, so any future decision resting on a
  difference smaller than 1.5× needs `-count 5` or better and a `benchstat`
  comparison, not a second eyeball.
