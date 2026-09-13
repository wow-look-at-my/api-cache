# Compression

What to compress a compiler-cache entry with, and whether to compress it at
all. Three different answers are defensible depending on where the entry lives,
and the measurements below say why.

Unqualified **`[ci]`** numbers are from the GitHub Actions `ubuntu-latest`
runner — AMD EPYC 7763, 4 vCPU, `sha_ni` and `avx2`, Go 1.26.8 — with
`[ci] windows` (same silicon, MinGW) and `[ci] macos` (**Apple M1, arm64,
Apple clang**) beside them. All three are one run,
<https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343>
(commit `241bdc50`, `-benchtime 2s`); raw files in
`probes/ci-results-<runner>/`. **`[sandbox]`** is the development VM (Intel
Xeon @2.8 GHz, no `sha_ni`), which runs many agents at once; kept only for
contrast. Everything is `probes/compress_test.go` over the corpus built by
`probes/gen-testdata.sh` from real `-g -O2` compiler output.

## The corpus

| file | what | bytes (`[ci]` ubuntu) |
|---|---|---:|
| `small.o` | C, `-g -O2` | 10,232 |
| `mid.o` | C++ with `<iostream>`, `-g -O2` | 527,880 |
| `big_g1.o` | template-heavy C++, `-g1 -O2` | 1,490,416 |
| `big.o` | template-heavy C++, `-g -O2` | 5,040,872 |
| `mid.d` | dependency file (text) | 9,124 |

Each runner's own compiler builds the corpus, so the byte counts differ between
environments — and on macOS they differ a great deal:

| file | `[ci]` ubuntu (GCC) | `[ci]` windows (MinGW) | `[ci]` macos (clang) |
|---|--:|--:|--:|
| `small.o` | 10,232 | 6,973 | 6,296 |
| `mid.o` | 527,880 | 343,092 | 243,888 |
| `big_g1.o` | 1,490,416 | 1,278,766 | 423,952 |
| `big.o` | 5,040,872 | 3,776,318 | 1,379,328 |
| `mid.d` | 9,124 | 11,738 | **116,760** |

Two things fall out that no single-platform run would have shown.

**The same source is a 5.0 MB object under GCC and a 1.4 MB object under Apple
clang** — 3.7×, from DWARF encoding alone. Entry-size budgeting is therefore a
per-toolchain question, and "the average entry is N KB" is not a portable
constant.

**The `.d` file is 12.8× larger on macOS** (117 KB against 9 KB), because
clang's `-MD` lists every header reached through the SDK's framework umbrella
headers. On Linux the dependency file is a rounding error next to the object;
on macOS it is 8% of the entry before compression. It also compresses to 0.058,
better than anything else in the corpus, so the cost after compression is
6.8 KB — but a design that assumes the `.d` is negligible is assuming Linux.

`big.o` is 5 MB from 100 lines of C++ — that is what `-g` plus templates plus
`<regex>` costs, and it is the shape that makes compression worth having. The
`-g1` variant of the same source is 1.5 MB, so **debug level moves the object
size by 3.4×**, far more than any codec choice.

## Ratio

`[ci]`, `TestRatios`. Ratio is compressed ÷ raw, lower is better.

| file | lz4 | s2 | s2-better | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|--:|
| `small.o` | 0.517 | 0.502 | 0.473 | 0.352 | 0.344 | 0.327 |
| `mid.o` | 0.372 | 0.382 | 0.358 | 0.234 | 0.234 | 0.203 |
| `big_g1.o` | 0.310 | 0.314 | 0.295 | 0.208 | 0.202 | 0.173 |
| `big.o` | 0.324 | 0.331 | 0.311 | 0.203 | 0.195 | 0.166 |
| `mid.d` | 0.287 | 0.262 | 0.246 | 0.194 | 0.183 | 0.161 |

`[ci] windows`, MinGW objects — the *absolute* ratios move because the DWARF is
different, the *ordering* does not:

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 0.639 | 0.616 | 0.452 | 0.436 | 0.425 |
| `mid.o` | 0.477 | 0.479 | 0.324 | 0.315 | 0.291 |
| `big.o` | 0.394 | 0.392 | 0.253 | 0.245 | 0.222 |
| `mid.d` | 0.176 | 0.174 | 0.119 | 0.114 | 0.103 |

`[ci] macos`, Apple clang and Mach-O — **the least compressible of the three**:

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 0.689 | 0.682 | 0.549 | 0.516 | 0.504 |
| `mid.o` | 0.503 | 0.500 | 0.389 | 0.372 | 0.343 |
| `big_g1.o` | 0.557 | 0.565 | 0.401 | 0.383 | 0.364 |
| `big.o` | 0.433 | 0.455 | 0.351 | 0.308 | 0.283 |
| `mid.d` | 0.081 | 0.093 | **0.058** | 0.056 | 0.049 |

Clang's objects are already denser — Apple clang emits fewer and smaller DWARF
sections than GCC for this source — so there is less redundancy left for the
codec to find. zstd-1 gets 0.234 on the GCC object and only 0.389 on the clang
one. **Cache-capacity planning done on one toolchain will be ~1.7× optimistic
on another**, and that is a bigger error than any codec choice in this
document.

The shape is nonetheless consistent across every input and every platform:
**zstd beats lz4/s2 by roughly 1.3–1.6×** on objects with DWARF, and zstd-9
beats zstd-1 by another 1.1–1.25×.
The `.d` file — plain text, mostly repeated path prefixes — compresses better
than any object under every codec, which is the same observation that makes
CAS-style de-duplication of the `.d` attractive (see `local-layout.md`).

Also worth noting: `zstd-1` and `zstd-3` are within 0.5% of each other on three
of the five inputs. In klauspost's Go implementation `SpeedFastest` and
`SpeedDefault` share most of their match-finding, so the level dial between
them is nearly free of ratio consequences and the speed difference is what
decides.

## Throughput

`[ci]`, single-threaded, `BenchmarkEncode` / `BenchmarkDecode`. MB/s over the
*uncompressed* size.

### Encode

| file | lz4 | s2 | s2-better | zstd-1 | zstd-3 | zstd-9 | flate-6 |
|---|--:|--:|--:|--:|--:|--:|--:|
| `small.o` | 367 | 1,002 | 514 | 180 | 145 | 38 | 21 |
| `mid.o` | 297 | 677 | 358 | 191 | 158 | 33 | 33 |
| `big_g1.o` | 330 | 704 | 384 | 226 | 188 | 43 | 37 |
| `big.o` | 346 | 725 | 385 | 221 | 195 | 33 | 36 |
| `mid.d` | 690 | 1,578 | 818 | 310 | 265 | 72 | 52 |

### Decode

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 1,791 | 2,693 | 583 | 592 | 606 |
| `mid.o` | 1,888 | 1,583 | 858 | 872 | 925 |
| `big_g1.o` | 1,804 | 1,611 | 940 | 982 | 1,087 |
| `big.o` | 1,916 | 1,672 | 958 | 986 | 1,068 |
| `mid.d` | 2,397 | 4,133 | 1,017 | 918 | 990 |

`[ci] macos` decode, the same code on arm64 — **everything is faster, but zstd
much less so**:

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 2,614 | 3,980 | 655 | 559 | 512 |
| `mid.o` | 2,731 | 2,301 | 704 | 843 | 849 |
| `big_g1.o` | 1,757 | 1,923 | 686 | 724 | 739 |
| `big.o` | 2,079 | 2,111 | 733 | 814 | 713 |
| `mid.d` | 3,694 | 7,363 | 2,771 | 3,252 | 3,332 |

Memcpy baseline: 22.2–100 GB/s on the EPYC, 50–62 GB/s on the M1, depending on
whether the buffer fits in cache. So **no codec is anywhere near memory
bandwidth** — even lz4 decode at 1.9 GB/s is 12× slower than a `memcpy` of the
same bytes.

Three stable facts across all four machines and all four object files:

- **lz4 and s2 decode at 1.5–2.7 GB/s; zstd at 0.6–1.0 GB/s.**
- **The zstd-versus-lz4 decode gap is 2.2× on x86 and 3.9× on arm64.** On the
  ubuntu runner it is 1,888 against 858 MB/s on `mid.o`; on Windows 1,602
  against 633; on the M1 2,731 against 704. klauspost's lz4-class decoders get
  more out of the M1 than its zstd decoder does, so **the "zstd costs 1.6× the
  decode" rule of thumb understates the cost on Apple silicon by more than 2×.**
  That is the one place in this document where the codec choice is meaningfully
  platform-dependent.
- **zstd decode speed is level-independent** — `zstd-9` decodes as fast as
  `zstd-1` or slightly faster, because a better-compressed stream has fewer
  bytes to read. Holds on all three runners. That asymmetry is what makes a
  slow encode affordable for anything read more than a few times.

### What the numbers mean in wall clock

`[ci]`, for `mid.o` (528 KB), one entry:

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 527,880 |
| lz4 | 1,775 µs | 280 µs | 196,256 |
| s2 | 779 µs | 334 µs | 201,601 |
| zstd-1 | 2,768 µs | 615 µs | 123,626 |
| zstd-3 | 3,336 µs | 606 µs | 123,701 |
| zstd-9 | 15,764 µs | 571 µs | 107,063 |

And for `big.o` (5 MB):

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 5,040,872 |
| lz4 | 14.6 ms | 2.6 ms | 1,635,438 |
| s2 | 7.0 ms | 3.0 ms | 1,668,713 |
| zstd-1 | 22.8 ms | 5.3 ms | 1,022,986 |
| zstd-3 | 25.8 ms | 5.1 ms | 984,348 |
| **zstd-9** | **150.9 ms** | 4.7 ms | 836,709 |
| flate-6 | 140.8 ms | — | 1,001,600 |

**zstd-9 is disqualified.** 151 ms to store one 5 MB object is longer than
compiling the file that produced it, for 15% fewer bytes than zstd-3. ccache's
default is level **1** for exactly this reason, and even that is 23 ms here.
`SCCACHE_CACHE_ZSTD_LEVEL` defaults to **3**, which costs 3 ms more than level 1
on `mid.o` and buys nothing (0.2343 vs 0.2342).

**On this corpus, zstd-1 and zstd-3 are the same ratio and zstd-1 is 20%
faster.** That is a klauspost-specific result — `SpeedFastest` and
`SpeedDefault` share most of their match-finding — and it is the strongest
single argument for level 1 as a default in Go.

Decode is where the asymmetry helps: zstd decodes at ~950 MB/s on x86 and
~730 MB/s on the M1 regardless of the level it was encoded at, so a
store-once/read-many entry can afford a slower encode. A compiler cache is store-once/read-many *in aggregate* but the
hit rate on a fresh entry is zero — the first build pays the encode and gets
nothing back.

## Published reference numbers (C implementations)

The Go implementations above are 2–4× slower than the reference C libraries,
which matters if a native client is ever on the table. Published figures, from
the projects' own README benchmarks (Silesia corpus, single core, ~3 GHz):

| codec | ratio | encode MB/s | decode MB/s |
|---|--:|--:|--:|
| zstd -1 (C) | ~2.9× | ~500 | ~1,600 |
| zstd -3 (C, default) | ~3.2× | ~250 | ~1,500 |
| zstd -9 (C) | ~3.6× | ~50 | ~1,600 |
| lz4 (C, default) | ~2.1× | ~750 | ~4,500 |
| lz4 -9 / HC (C) | ~2.7× | ~40 | ~4,500 |
| zlib -6 (C) | ~3.1× | ~90 | ~400 |

Sources: <https://github.com/facebook/zstd> and
<https://github.com/lz4/lz4>. Those are on text-heavy Silesia, not object
files, so the *ratios* do not transfer — the ratios measured above do. The
*relative* speeds do transfer: C lz4 decodes ~3× faster than C zstd, and the Go
gap is smaller (1.9×) because klauspost's zstd is unusually good and
`pierrec/lz4` is unusually ordinary.

## What each system does

| system | codec | level | scope |
|---|---|---|---|
| ccache | zstd | `compression_level = 0` → writer picks, currently **1** | whole entry payload, inside the cache-entry envelope |
| sccache | zstd | `SCCACHE_CACHE_ZSTD_LEVEL`, default **3** | per zip member; the zip method is `Stored` and the member bytes are a zstd stream |
| bazel-remote | zstd | not configurable per entry | whole blob; `Accept-Encoding: zstd` on the wire, and it stores compressed by default |
| go-s3-server | lz4 | client's choice | **none of its own** — bodies arrive already lz4-framed from the go-toolchain client and are stored byte-for-byte |
| binpazer | any of `stored`/`deflate`/`zstd`/`lz4` | writer's choice | **per block** |

go-s3-server's position is worth stating explicitly because it is a real design
stance, not an omission: the server compresses nothing, decompresses nothing
except one lz4 block for its read guards, and `logCompressionAdvisory` warns at
startup if `data_dir` sits on a ZFS dataset with compression enabled, because
that would compress every already-compressed body a second time. Its
`compression.go` comment — "this server compresses nothing" — is the cheapest
possible server, and it pushes the CPU cost onto the client that has it.

## The hot-local vs remote split

These are different problems and they deserve different answers.

**A hot local cache is not disk-bound; it is CPU-bound and syscall-bound.**
From `local-layout.md` `[ci] ubuntu`: reading a 512 KB file from the page cache
is 26 µs. Decompressing 512 KB of zstd is 615 µs — **23× the read it
replaced**. lz4 is 280 µs, still 11×. On a machine with a warm page cache and
an SSD, compressing the local cache is a straight loss on the read path; it
buys disk space and costs latency.

The counterweight is what happens *after* the read: writing the object back out
costs 1,266 µs on the same machine. So a compressed restore is
26 + 615 + 1,266 ≈ 1,907 µs against an uncompressed 26 + 1,266 ≈ 1,292 µs —
**a 48% slowdown on the hit path, not a 23× one.** The decode is the second
largest term, not the first.

**That ratio is far worse on the other two platforms, because their restores
are cheaper and their decodes are not.** Same arithmetic, per runner, for a
512 KB object with zstd:

| | read | decode | restore | compressed total | raw total | penalty |
|---|--:|--:|--:|--:|--:|--:|
| ubuntu | 26 µs | 615 µs | 1,266 µs | 1,907 µs | 1,292 µs | **+48%** |
| windows | 53 µs | 833 µs | 903 µs | 1,789 µs | 956 µs | **+87%** |
| macos | 25 µs | 750 µs | 501 µs | 1,276 µs | 526 µs | **+143%** |

(`decode` scaled from each runner's measured `mid.o` zstd-1 throughput.) On
Apple silicon the decode is *larger than the restore*, so compressing the local
cache more than doubles the hit path. **The right local codec is a per-platform
question, and the strongest single lever is not the codec but the restore
method: link instead of copy and the decode cannot be paid at all.**

The counter-argument is cache capacity: at ratio 0.23, a 5 GiB `max_size`
holds 4.3× as many entries, and a bigger cache has a higher hit rate. That is a
real trade and it is why ccache compresses by default. But note what ccache
also does: **`hard_link` and `file_clone` both disable compression**, because
you cannot link into a compressed blob. The moment the restore is a link, the
right compression level is none.

**A remote tier is network-bound and the arithmetic inverts.** For `mid.o` at
528 KB:

| link | raw | zstd-1 (124 KB) | transfer saved | encode cost |
|---|--:|--:|--:|--:|
| 1 Gbit/s LAN | 4.2 ms | 1.0 ms | 3.2 ms | **2.8 ms — a wash** |
| 100 Mbit/s | 42 ms | 9.9 ms | 32 ms | 2.8 ms |
| 20 Mbit/s (home/VPN) | 211 ms | 49.5 ms | 162 ms | 2.8 ms |

On a LAN, zstd-1's encode cost (2.8 ms) is almost exactly the transfer it saves
(3.2 ms) — compression is a wash on the store path and a clear win on the fetch
path (decode 0.6 ms against 3.2 ms of transfer). Below ~100 Mbit/s it is an
unambiguous win in both directions.

lz4 changes the LAN arithmetic: 1.8 ms to encode, saving 2.6 ms of transfer
(196 KB instead of 528 KB), and 0.28 ms to decode. On a fast link lz4 is the
better trade; on a slow one zstd's extra 37% of ratio dominates. This is the
case for making the codec a per-deployment setting rather than a constant, and
for the entry format carrying the codec id rather than assuming one — which
both ccache's cache-entry header and binpazer's compression envelope do, and
tar does not.

## Per-entry vs per-member

Compressing the whole entry as one stream gives a better ratio: the `.d` file
and the stderr share a dictionary window with the object. Compressing per
member allows three things one stream cannot:

1. **Not compressing a member.** stderr is usually empty and always tiny;
   compressing 0–2 KB costs an envelope and a codec instance for nothing.
   binpazer's `stored` codec id exists precisely so a writer can decline per
   block without changing the block's shape.
2. **Fetching one member without decoding the rest.** With one stream, reading
   the object means decompressing everything before it.
3. **Different codecs per member kind.** The `.d` file compresses 1.5× better
   than the object under every codec and is 60× smaller — a slow codec on it is
   free in absolute terms.

Measured cost of the split `[ci]`: binpazer per-block zstd over the four-member
set produced 145,024 bytes, versus 143,192 for `zip (deflate)` as a
whole-member comparison — **1.3% worse**, and that is against a different
codec. The window loss is in the noise at these sizes because the object
dominates the entry.

## The codec-instance trap

`probes/compress_test.go` `BenchmarkDecodeStreamVsOneShot`, `[ci]`, all on the
same 528 KB input:

| | ns/op | B/op |
|---|--:|--:|
| zstd `DecodeAll`, pooled decoder | **704,893** | **59** |
| zstd, fresh `NewReader` per call, streamed | 823,010 | 1,311,210 |
| lz4, fresh `NewReader` per call, streamed | 994,114 | **8,386,923** |
| lz4, one reader reused with `Reset` | **328,417** | 1,350 |

Construction itself is cheap (`zstd.NewReader` 478 ns, `lz4.NewReader` 117 ns);
the cost is the buffers each allocates on first use. `pierrec/lz4`'s default
block size makes a fresh reader allocate **8.4 MB**, and using one per cache
entry is a 5× slowdown and a GC problem. Two rules fall out:

- **Pool the codec instances**, or use the one-shot API. `zstd.Decoder` is safe
  for concurrent `DecodeAll` and is meant to be shared; `lz4.Reader` has
  `Reset`.
- **Prefer the one-shot API when the decoded size is known**, which it always
  is for a cache entry that records it. `DecodeAll` into a pre-sized buffer is
  the fastest path measured and allocates nothing.

`zstd.NewReader` with default concurrency costs 1,169 ns and 3,776 B against
478 ns and 1,304 B at `WithDecoderConcurrency(1)`, because it spins up
goroutines. For a CLI that decodes one entry and exits, concurrency 1 is
correct.

## Hashing is not compression, but it competes for the same CPU

From `local-layout.md`: SHA-256 runs at **1,588 MB/s with the `sha_ni`
instruction and 365 MB/s without it**, while CRC-32C is 21–24 GB/s on every
machine tested. Compressing a 5 MB object with zstd-1 costs 22 ms; SHA-256-ing
it costs 3.3 ms on the EPYC and **14.4 ms** on a CPU without SHA-NI. So on
older hardware the integrity hash can cost most of what the compression costs,
for no compression. Checksum the
**stored** bytes with CRC-32C (binpazer's `has_crc` semantics, go-s3-server's
choice, ccache's XXH3-128) and reserve the cryptographic hash for the key.

## Licences

| library | licence |
|---|---|
| `github.com/klauspost/compress` (zstd, s2, flate) | BSD-3-Clause |
| `github.com/pierrec/lz4/v4` | BSD-3-Clause |
| zstd (reference C, Facebook) | BSD-3-Clause **or** GPL-2.0, dual |
| lz4 (reference C) | BSD-2-Clause (library), GPL-2 (programs) |
| zlib | zlib licence |
| Go stdlib `compress/flate` | BSD-3-Clause |

All permissive. `klauspost/compress` is already a dependency of go-s3-server
(v1.20.0) and of bin-file-fmt (v1.19.1); `pierrec/lz4/v4 v4.1.27` is a
dependency of both as well. Adding neither costs anything new.

## Recommendation shape (not a decision)

| tier | codec | reasoning |
|---|---|---|
| local, restore by copy | zstd level 1, or none | decode is 34× the page-cache read it replaces; the win is capacity, not speed |
| local, restore by hard link or reflink | **none, mandatory** | you cannot link into a compressed blob; ccache disables compression under both options |
| remote store | configurable; zstd-1 on a LAN, zstd-3+ over a WAN | encode cost exceeds transfer saved above ~1 Gbit/s |
| remote fetch | whatever was stored | decode is level-independent at ~800 MB/s |
| small members (stderr, `.d` under a few KB) | `stored` | the envelope and codec instance cost more than the bytes saved |

The format should carry the codec id per entry (or per member), never assume
one. Both ccache's cache-entry header and binpazer's compression envelope do
this; tar does not.

## Sources

- zstd — <https://github.com/facebook/zstd> (BSD-3-Clause / GPL-2.0)
- lz4 — <https://github.com/lz4/lz4> (BSD-2-Clause)
- `klauspost/compress` — <https://github.com/klauspost/compress> (BSD-3-Clause)
- `pierrec/lz4` — <https://github.com/pierrec/lz4> (BSD-3-Clause)
- ccache manual, `compression` / `compression_level` —
  <https://ccache.dev/manual/latest.html> (GPL-3.0 project)
- sccache `SCCACHE_CACHE_ZSTD_LEVEL` and `put_object` —
  <https://github.com/mozilla/sccache> `src/cache/cache_io.rs` (Apache-2.0)
- bazel-remote zstd storage and `Accept-Encoding: zstd` —
  <https://github.com/buchgr/bazel-remote> (Apache-2.0)
- go-s3-server `compression.go`, `docs/look-ahead.md` — this org
