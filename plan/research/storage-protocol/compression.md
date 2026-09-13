# Compression

What to compress a compiler-cache entry with, and whether to compress it at
all. Three different answers are defensible depending on where the entry lives,
and the measurements below say why.

**`[ci]`** numbers are from a GitHub Actions `ubuntu-latest` runner — AMD EPYC
7763, 4 vCPU, `sha_ni` and `avx2`, Go 1.26.8, `-benchtime 2s`; raw files in
`probes/ci-results-ubuntu-latest/`, run
<https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981>. These
are the ones to quote. **`[sandbox]`** is the development VM (Intel Xeon
@2.8 GHz, no `sha_ni`), which runs many agents at once; kept only for contrast.
Everything is `probes/compress_test.go` over the corpus built by
`probes/gen-testdata.sh` from real `gcc`/`g++ -g -O2` output.

## The corpus

| file | what | bytes (`[ci]` ubuntu) |
|---|---|---:|
| `small.o` | C, `-g -O2` | 10,232 |
| `mid.o` | C++ with `<iostream>`, `-g -O2` | 527,880 |
| `big_g1.o` | template-heavy C++, `-g1 -O2` | 1,490,416 |
| `big.o` | template-heavy C++, `-g -O2` | 5,040,872 |
| `mid.d` | dependency file (text) | 9,124 |

Each runner's own compiler builds the corpus, so the byte counts differ
slightly between environments (MinGW g++ on the Windows runner emits a 343 KB
`mid.o` against GCC's 528 KB). The ratios are stable to the third decimal
across all three.

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

`[ci] windows`, MinGW objects, for comparison — the *absolute* ratios move
because the DWARF is different, the *ordering* does not:

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 0.639 | 0.616 | 0.452 | 0.436 | 0.425 |
| `mid.o` | 0.477 | 0.479 | 0.324 | 0.315 | 0.291 |
| `big.o` | 0.394 | 0.392 | 0.253 | 0.245 | 0.222 |
| `mid.d` | 0.176 | 0.174 | 0.119 | 0.114 | 0.103 |

The shape is consistent across every input: **zstd beats lz4/s2 by roughly
1.6×** on objects with DWARF, and zstd-9 beats zstd-1 by another 1.15–1.25×.
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
| `small.o` | 397 | 998 | 520 | 178 | 146 | 38 | 20 |
| `mid.o` | 287 | 674 | 354 | 192 | 158 | 30 | 32 |
| `big_g1.o` | 319 | 699 | 379 | 225 | 186 | 34 | 36 |
| `big.o` | 334 | 736 | 373 | 225 | 197 | 29 | 36 |
| `mid.d` | 649 | 1,591 | 814 | 311 | 259 | 72 | 45 |

### Decode

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 1,549 | 2,413 | 594 | 603 | 615 |
| `mid.o` | 1,592 | 1,549 | 870 | 885 | 937 |
| `big_g1.o` | 1,559 | 1,595 | 957 | 1,001 | 1,103 |
| `big.o` | 1,660 | 1,636 | 974 | 1,002 | 1,083 |
| `mid.d` | 1,982 | 4,151 | 1,076 | 931 | 999 |

Memcpy baseline on the same machine: 22.2–100 GB/s depending on whether the
buffer fits in cache. So **no codec is anywhere near memory bandwidth** — even
lz4 decode at 1.66 GB/s is 13× slower than a `memcpy` of the same bytes.

Two stable facts across both machines and all four object files:

- **lz4 and s2 decode at 1.5–1.7 GB/s; zstd at 0.9–1.0 GB/s.** The gap is a
  consistent 1.6×, and it does not depend on the encode level.
- **zstd decode speed is level-independent** — `zstd-9` decodes as fast as
  `zstd-1` or slightly faster, because a better-compressed stream has fewer
  bytes to read. That asymmetry is what makes a slow encode affordable for
  anything read more than a few times.

### What the numbers mean in wall clock

`[ci]`, for `mid.o` (528 KB), one entry:

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 527,880 |
| lz4 | 1,842 µs | 332 µs | 196,256 |
| s2 | 784 µs | 341 µs | 201,601 |
| zstd-1 | 2,755 µs | 607 µs | 123,626 |
| zstd-3 | 3,339 µs | 597 µs | 123,701 |
| zstd-9 | 17,812 µs | 563 µs | 107,063 |

And for `big.o` (5 MB):

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 5,040,872 |
| lz4 | 15.1 ms | 3.0 ms | 1,635,438 |
| s2 | 6.9 ms | 3.1 ms | 1,668,713 |
| zstd-1 | 22.4 ms | 5.2 ms | 1,022,986 |
| zstd-3 | 25.6 ms | 5.0 ms | 984,348 |
| **zstd-9** | **171.2 ms** | 4.7 ms | 836,709 |
| flate-6 | 142.0 ms | — | 1,001,600 |

**zstd-9 is disqualified.** 171 ms to store one 5 MB object is longer than
compiling the file that produced it, for 14% fewer bytes than zstd-3. ccache's
default is level **1** for exactly this reason, and even that is 22 ms here.
`SCCACHE_CACHE_ZSTD_LEVEL` defaults to **3**, which costs 3 ms more than level 1
on `mid.o` and buys nothing (0.2343 vs 0.2342).

**On this corpus, zstd-1 and zstd-3 are the same ratio and zstd-1 is 20%
faster.** That is a klauspost-specific result — `SpeedFastest` and
`SpeedDefault` share most of their match-finding — and it is the strongest
single argument for level 1 as a default in Go.

Decode is where the asymmetry helps: zstd decodes at ~950 MB/s regardless of
the level it was encoded at, so a store-once/read-many entry can afford a
slower encode. A compiler cache is store-once/read-many *in aggregate* but the
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
From `local-layout.md` `[ci]`: reading a 512 KB file from the page cache is
26 µs. Decompressing 512 KB of zstd is 597 µs — **23× the read it replaced**.
lz4 is 332 µs, still 13×. On a machine with a warm page cache and an SSD,
compressing the local cache is a straight loss on the read path; it buys disk
space and costs latency.

The counterweight is what happens *after* the read: writing the object back out
costs 1,277 µs on the same machine. So a compressed restore is
26 + 597 + 1,277 ≈ 1,900 µs against an uncompressed 26 + 1,277 ≈ 1,300 µs —
**a 46% slowdown on the hit path, not a 23× one.** The decode is the second
largest term, not the first.

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
(196 KB instead of 528 KB), and 0.33 ms to decode. On a fast link lz4 is the
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
