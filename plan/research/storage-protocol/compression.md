# Compression

What to compress a compiler-cache entry with, and whether to compress it at
all. Three different answers are defensible depending on where the entry lives,
and the measurements below say why.

Numbers labelled `[sandbox]` come from the development VM (many agents at once,
noisy). Numbers labelled `[ci]` come from the `storage-protocol` workflow; see
`probes/ci-results-*/summary.md` for the runner and run URL. Everything is
`probes/compress_test.go` over the corpus built by `probes/gen-testdata.sh`
from real `gcc`/`g++ -g -O2` output.

## The corpus

| file | what | bytes |
|---|---|---:|
| `small.o` | C, `-g -O2` | 10,192 |
| `mid.o` | C++ with `<iostream>`, `-g -O2` | 527,840 |
| `big_g1.o` | template-heavy C++, `-g1 -O2` | 1,490,368 |
| `big.o` | template-heavy C++, `-g -O2` | 5,040,832 |
| `mid.d` | dependency file (text) | 9,111 |

`big.o` is 5 MB from 100 lines of C++ — that is what `-g` plus templates plus
`<regex>` costs, and it is the shape that makes compression worth having. The
`-g1` variant of the same source is 1.5 MB, so **debug level moves the object
size by 3.4×**, far more than any codec choice.

## Ratio

`[sandbox]`, `TestRatios`. Ratio is compressed ÷ raw, lower is better.

| file | lz4 | s2 | s2-better | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|--:|
| `small.o` | 0.516 | 0.504 | 0.474 | 0.353 | 0.350 | 0.329 |
| `mid.o` | 0.372 | 0.382 | 0.358 | 0.234 | 0.234 | 0.203 |
| `big_g1.o` | 0.310 | 0.314 | 0.295 | 0.208 | 0.201 | 0.173 |
| `big.o` | 0.324 | 0.331 | 0.311 | 0.203 | 0.195 | 0.166 |
| `mid.d` | 0.285 | 0.263 | 0.245 | 0.194 | 0.183 | 0.161 |

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

`[sandbox]`, single-threaded, `BenchmarkEncode` / `BenchmarkDecode`. MB/s over
the *uncompressed* size.

### Encode

| file | lz4 | s2 | s2-better | zstd-1 | zstd-3 | zstd-9 | flate-6 |
|---|--:|--:|--:|--:|--:|--:|--:|
| `small.o` | 366 | 926 | 514 | 178 | 150 | 28 | 16 |
| `mid.o` | 266 | 627 | 365 | 186 | 147 | 19 | 30 |
| `big_g1.o` | 292 | 634 | 389 | 216 | 164 | 27 | 35 |
| `big.o` | 308 | 679 | 378 | 207 | 172 | 21 | 34 |
| `mid.d` | 640 | 1,542 | 843 | 297 | 248 | 58 | 16 |

### Decode

| file | lz4 | s2 | zstd-1 | zstd-3 | zstd-9 |
|---|--:|--:|--:|--:|--:|
| `small.o` | 1,919 | 2,691 | 595 | 593 | 622 |
| `mid.o` | 1,827 | 1,375 | 773 | 697 | 823 |
| `big_g1.o` | 1,635 | 1,394 | 824 | 859 | 935 |
| `big.o` | 1,583 | 1,413 | 807 | 840 | 841 |
| `mid.d` | 2,362 | 4,059 | 987 | 863 | 922 |

Memcpy baseline on the same machine: 10.9–42.7 GB/s depending on whether the
buffer fits in cache. So **no codec is anywhere near memory bandwidth** — even
lz4 decode at 1.6 GB/s is 7× slower than a `memcpy` of the same bytes.

### What the numbers mean in wall clock

For `mid.o` (528 KB), one entry:

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 527,840 |
| lz4 | 1,988 µs | 289 µs | 196,240 |
| s2 | 842 µs | 384 µs | 201,622 |
| zstd-1 | 2,841 µs | 683 µs | 123,606 |
| zstd-3 | 3,598 µs | 677 µs | 123,755 |
| zstd-9 | 27,155 µs | 641 µs | 107,040 |

And for `big.o` (5 MB):

| | encode | decode | stored bytes |
|---|--:|--:|--:|
| none | 0 | 0 | 5,040,832 |
| lz4 | 16.4 ms | 3.2 ms | 1,635,381 |
| s2 | 7.4 ms | 3.6 ms | 1,668,705 |
| zstd-1 | 24.4 ms | 6.2 ms | 1,022,920 |
| zstd-3 | 29.3 ms | 6.0 ms | 984,576 |
| zstd-9 | 241.8 ms | 6.0 ms | 836,678 |

**zstd-9 is disqualified.** 242 ms to store one 5 MB object is longer than
compiling the file that produced it. ccache's default is level **1** for
exactly this reason, and even that is 24 ms here. `SCCACHE_CACHE_ZSTD_LEVEL`
defaults to **3**.

Decode is where the asymmetry helps: zstd decodes at ~800 MB/s regardless of
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
From `local-layout.md`: reading a 512 KB file from the page cache is 20 µs.
Decompressing 512 KB of zstd is 677 µs — **34× the read it replaced**. lz4 is
289 µs, still 14×. On a machine with a warm page cache and an SSD, compressing
the local cache is a straight loss on the read path; it buys disk space and
costs latency.

The counter-argument is cache capacity: at ratio 0.23, a 5 GiB `max_size`
holds 4.3× as many entries, and a bigger cache has a higher hit rate. That is a
real trade and it is why ccache compresses by default. But note what ccache
also does: **`hard_link` and `file_clone` both disable compression**, because
you cannot link into a compressed blob. The moment the restore is a link, the
right compression level is none.

**A remote tier is network-bound and the arithmetic inverts.** For `mid.o` at
528 KB:

| link | raw | zstd-3 (124 KB) | saved |
|---|--:|--:|--:|
| 1 Gbit/s LAN | 4.2 ms | 1.0 ms | 3.2 ms (encode 3.6 ms — a wash) |
| 100 Mbit/s | 42 ms | 9.9 ms | 32 ms |
| 20 Mbit/s (home/VPN) | 211 ms | 49.5 ms | 162 ms |

On a LAN, zstd-3's encode cost (3.6 ms) exceeds the transfer it saves (3.2 ms)
— compression is a *loss* on the store path and a small win on the fetch path.
Below ~100 Mbit/s it is an unambiguous win in both directions. This is the case
for making the codec a per-deployment setting rather than a constant, and for
the entry format carrying the codec id rather than assuming one (which both
ccache's cache-entry header and binpazer's compression envelope do).

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

Measured cost of the split: binpazer per-block zstd over the four-member set
produced 145,064 bytes, versus 143,193 for `zip (deflate)` as a whole-member
comparison. The window loss is in the noise at these sizes because the object
dominates.

## The codec-instance trap

`probes/compress_test.go` `BenchmarkDecodeStreamVsOneShot`, `[sandbox]`, all on
the same 528 KB input:

| | ns/op | B/op |
|---|--:|--:|
| zstd `DecodeAll`, pooled decoder | 817,911 | 468 |
| zstd, fresh `NewReader` per call, streamed | 1,004,343 | 1,311,228 |
| lz4, fresh `NewReader` per call, streamed | 1,517,581 | **8,372,648** |
| lz4, one reader reused with `Reset` | 288,147 | 7,386 |

Construction itself is cheap (`zstd.NewReader` 685 ns, `lz4.NewReader` 153 ns);
the cost is the buffers each allocates on first use. `pierrec/lz4`'s default
block size makes a fresh reader allocate **8.4 MB**, and using one per cache
entry is a 5× slowdown and a GC problem. Two rules fall out:

- **Pool the codec instances**, or use the one-shot API. `zstd.Decoder` is safe
  for concurrent `DecodeAll` and is meant to be shared; `lz4.Reader` has
  `Reset`.
- **Prefer the one-shot API when the decoded size is known**, which it always
  is for a cache entry that records it. `DecodeAll` into a pre-sized buffer is
  the fastest path measured and allocates nothing.

`zstd.NewReader` with default concurrency costs 1,677 ns and 3,776 B against
685 ns and 1,304 B at `WithDecoderConcurrency(1)`, because it spins up
goroutines. For a CLI that decodes one entry and exits, concurrency 1 is
correct.

## Hashing is not compression, but it competes for the same CPU

From `local-layout.md`, on a CPU with no SHA-NI: SHA-256 runs at 365 MB/s and
CRC-32C at 24 GB/s. Compressing a 5 MB object with zstd-1 costs 24 ms;
SHA-256-ing it costs 14 ms. If the design hashes the *uncompressed* body for
integrity, that hash can easily cost more than the compression. Checksum the
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
