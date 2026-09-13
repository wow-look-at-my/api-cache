# Entry container formats

A compile result is several files. This evaluates the ways to put them in one
byte stream — one that has to work as a file on local disk *and* as an HTTP
body to a remote — against six criteria:

1. **Zero-copy restore.** Can the object's bytes be handed to `write` (or
   `copy_file_range`) without an intermediate copy or a decode of anything
   else?
2. **Seek to one member.** Can the `.o` be read without reading the `.d` and
   the stderr that may precede it?
3. **Per-member vs whole-entry compression.** Text (`.d`, stderr) and DWARF
   compress differently, and a member sometimes should not be compressed at all.
4. **Integrity.** Is there a checksum, does it cover the stored bytes or the
   decoded bytes, and can it be checked without decompressing?
5. **Forward compatibility.** Can a reader that does not know a member kind
   still read the ones it does?
6. **Streaming over HTTP.** Can a writer produce it without knowing the total
   length, and can a reader consume it without seeking?

Measured numbers are labelled by where they come from. **`[ci] ubuntu`** and
**`[ci] windows`** are from a GitHub Actions run on AMD EPYC 7763 (4 vCPU,
`sha_ni`, `avx2`), ext4 and NTFS respectively, Go 1.26.8, `-benchtime 2s`;
raw files in `probes/ci-results-ubuntu-latest/` and
`probes/ci-results-windows-latest/`, run
<https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981>.
**`[sandbox]`** is the development VM (Intel Xeon @2.8 GHz, no `sha_ni`), which
runs many agents at once and is noisy; it is kept only where it adds contrast.

The three environments use *slightly different corpora*, because each runner's
compiler emits different DWARF: `mid.o` is 527,880 B from GCC on the Linux
runner and 343,092 B from MinGW g++ on Windows. Absolute byte counts therefore
differ between the tables below; the ratios and the relative timings are what
transfer.

## The candidates

### tar (stdlib `archive/tar`)

512-byte header per member, padded to a 512-byte boundary, two zero blocks at
the end. Names are strings. No index: finding a member means walking headers.

This is what go-s3-server's `/_batch/get` and `/_batch/put` already use, with a
`manifest.json` as the first member carrying each entry's key and metadata
(`batch.go`, `batchGetManifest` / `batchPutManifest`). That precedent matters:
the batch protocol has already decided that a tar plus a leading JSON manifest
is a workable multi-object body over HTTP, and the code to write and read it
exists.

### ccache's result format (GPL-3.0 — described, not copied)

`<format_ver:u8> <n_files:u8>` then, per member,
`<marker:u8> <file_type:u8> <file_size:u64>` and (for an embedded member) the
bytes. `marker = 1` means the member is **not** here: it lives beside the entry
file as `<entry>_<NN>`. The whole payload sits inside a cache-entry envelope
that carries the compression type and level and an **XXH3-128 checksum over the
header and payload**, written uncompressed.

No offset table. Role is a `u8` id, not a name. `n_files` is a `u8`, so an
entry holds at most 255 members.

### A hand-rolled framed format ("ACE1", `probes/container_test.go`)

Written purely as a lower bound to measure the others against:

```
magic    4    "ACE1"
version  1
flags    1
n        2
table    n × (type u8, pad u8, len u32, off u64)   ← fixed width, 14 bytes
payloads concatenated, in table order
trailer  8
```

Fixed-width table, so member *i* is one multiply and no scan. Reading only the
object from a file is two `pread`s: the header+table, then that member's range.

### zip (stdlib `archive/zip`)

Central directory at the end maps names to offsets. ~30-byte local header plus
~46-byte central entry plus the name, twice. Per-member compression method is
part of the format.

This is what **sccache** uses — with a twist worth noting: members are declared
`CompressionMethod::Stored` and the bytes written into them are **zstd
streams** (`src/cache/cache_io.rs`). zip is used as a named-member directory
and its own compression is bypassed, because zip's only well-supported method
is deflate.

### binpazer (`github.com/wow-look-at-my/bin-file-fmt`, MIT)

A block-based container: a 56-byte fixed header plus a length-prefixed
`writer_name`, then a required Block Type Table, then blocks. Every block has
an 8-byte header — `u16 type_id`, `u16 flags`, `u32 length` — directly castable
as a C struct. Everything is little-endian and 8-byte aligned, explicitly so a
C reader can `mmap` and point a `struct *` at it.

The pieces that matter here:

- **`type_id` is interned, not a name.** The Block Type Table maps each
  `type_id` to a 16-byte GUID and an optional name, once per file, so repeating
  a type costs 2 bytes per block. **A block header carries no per-block name.**
  For a compile result with two coverage files, or with an `-o` path that must
  be restored verbatim, the names have to live somewhere else: either a
  distinct `type_id` per role, or a directory block.
- **`large_mode` (flag bit 4)** reinterprets `length` as a count of 4096-byte
  units, raising the ceiling from 4 GiB to ~16 TiB at page granularity. A
  compile output never needs it; below 4 GiB `length` is exact bytes.
- **`has_crc` (bit 3)** appends a 4-byte CRC-32C over `[block_start .. end of
  payload]`, i.e. over the **stored** bytes, before any codec runs. That is the
  right place for it: integrity is checkable without decompressing.
- **`compressed` (bit 2)** replaces the payload with a Compression Envelope —
  `u16 codec_id`, `u16 codec_flags`, `u32 reserved`, `u64 uncompressed_length`,
  then the codec's bytes. Registry: `1 stored`, `2 deflate`, `3 zstd`,
  `4 lz4`, `65535` = a GUID escape for anything else. The block's `length`
  always describes the stored envelope, so walking, skipping, the index and the
  next-block formula are unaffected by compression — a reader with no codec
  support still traverses the file correctly.
  `uncompressed_length` is authoritative and the spec requires it to bound the
  allocation *before* decoding, which is the right answer to
  "a decoder is an unbounded allocator driven by untrusted bytes".
- **Block Index (`type_id` 65533) plus a 16-byte footer.** The footer is
  `u64 index_block_offset` then the magic `rezapnib`. The index maps `type_id`
  to absolute offsets, 16 bytes per entry. It is a hint: a block missing from
  it is still found by walking, and the index is explicitly not `safe_to_copy`.
- **`file_length` sentinel.** `0xFFFFFFFFFFFFFFFF` means unknown/streaming.

Go API: `NewWriterVersion`, `Put` / `PutCompressed` / `PutJSON` (each returns
the offset the block landed at), `WriteIndex`, `End`, and the convenience
`Finish`. On the read side `NewReaderAt`, `Find` / `FindFirst` / `FindLast`,
`At`, `BlockAt`, `OpenAt(offset, wantTypeID)` (streams the payload,
decompressing), `DecodeJSON` / `DecodeJSONLast`. `DefaultMaxAlloc` is 1 GiB.
There are complete C (`c/binpazer.c`) and C++ (`cpp/binpazer.hpp`)
implementations in the same repository, plus a `binpazer` CLI that dumps and
extracts blocks.

### How a compile result maps onto binpazer blocks

The shape the library is built for is "content blocks + a directory + an
index", which is exactly this problem. `probes/binpazer/binpazer_test.go`
implements it:

| block | `type_id` | contents |
|---|---|---|
| Block Type Table | 65534 | required first block; interns the two user types |
| `CompilerOutput` × N | 1 | one output's bytes, optionally compressed, optionally CRC'd |
| `ResultDirectory` | 2 | JSON: `[{role, off, size}]` — role name, block offset, decoded size |
| Block Index | 65533 | `type_id` → offsets |
| footer | — | 16 bytes pointing at the index |

The directory block is load-bearing and is **not** optional, for two reasons.
First, the block header has no name, so nothing else records that block 1 is
the object and block 3 is the stderr. (The alternative — a distinct `type_id`
per role — works for a fixed role set and collapses as soon as two blocks share
a role, e.g. two coverage files.) Second, the Block Index keys on `type_id`, so
with every output sharing `type_id = 1` the index alone cannot say *which* of
the four offsets is the object. The directory turns `role → offset` into a
seek; the index is then only used to find the directory.

That gives the read path its shape: **footer → index → directory block →
one seek → the object's payload**. Three seeks and two small reads before the
payload, versus one `pread` of a fixed-width table in ACE1.

## Measured

The entry under test is `mid.o`, `mid.d`, a 1,860-byte stderr and 40,960 B of
coverage notes — 579,824 bytes of members on the Linux runner.

### Framing overhead, uncompressed

`[ci] ubuntu`, `probes/container_test.go` `TestContainerOverhead` and
`probes/binpazer` `TestBinpazerRoundTrip`:

| format | file bytes | overhead | % |
|---|--:|--:|--:|
| ACE1 framed | 579,896 | +72 | 0.012% |
| binpazer, stored | 580,400 | +576 | 0.099% |
| binpazer, stored + CRC per block | 580,424 | +600 | 0.103% |
| zip (stored members) | 580,274 | +450 | 0.078% |
| tar (ustar) | 583,680 | +3,856 | 0.665% |
| tar + `manifest.json` | 584,704 | +4,880 | 0.842% |

The overhead is a fixed number of bytes per member, so it grows as a *fraction*
when the entry is small. `[ci] windows`, whose MinGW objects are smaller
(397,650 B of members), shows the same absolute overheads at 0.018% / 0.113% /
0.945% / 1.203% — and on a 14 KiB entry with a 10 KiB object, tar's ~3.8 KiB of
framing is about a quarter of the file.

tar's 512-byte header and 512-byte padding per member is 6–54× the others, and
that is the one framing number in the table that is not negligible.

binpazer's 576 bytes is the 56-byte header, the `writer_name`, the Block Type
Table with two GUID entries and their names, the JSON directory, the Block
Index and the footer. Adding a CRC to every block costs 32 bytes for four
blocks (4 bytes each plus alignment). Both are irrelevant at this size and
matter at 10 KiB.

### Compressed entry size

binpazer with per-block compression, same members:

`[ci] ubuntu`:

| codec | file bytes | vs raw |
|---|--:|--:|
| stored | 580,400 | 1.001× |
| lz4 | 225,968 | 0.390× |
| zstd (klauspost default, level 3) | 145,024 | 0.250× |
| zstd + CRC | 145,048 | 0.250× |

The envelope costs 16 bytes per compressed block; the CRC 4. Compare
`zip (deflate)` at 143,192 bytes — deflate at level 6 lands in the same place
as zstd-3 on this corpus but costs 5–10× the CPU (see `compression.md`).

### Read one member, with the object written LAST

The hostile ordering, so a format with no index pays its worst case.

`[ci] ubuntu` — all four formats measured on the same machine in the same run
(binpazer's module carries its own tar and ACE1 baselines for exactly this):

| format | ns/op | B/op | allocs/op |
|---|--:|--:|--:|
| ACE1, from an in-memory blob (subslice) | **1.87** | 0 | 0 |
| ACE1, two `pread`s from a file | 64,321 | 532,609 | 2 |
| ACE1, two `pread`s (parent module, separate temp dir) | 97,784 | 532,481 | 1 |
| tar, header walk | 140,539 | 535,755 | 56 |
| binpazer, stored, sized read | **203,022** | 600,272 | 59 |
| binpazer, stored, from a real file | 240,420 | 1,140,640 | 79 |
| binpazer, stored, `io.ReadAll` | 464,247 | 1,140,691 | 80 |
| binpazer, lz4, sized read | 870,666 | 8,988,402 | 68 |
| binpazer, zstd, sized read | 1,793,050 | 11,722,224 | 119 |
| zip, central directory | 410,268 | 1,079,869 | 55 |

`[ci] windows`, same code, NTFS, smaller corpus (343 KB object):

| format | ns/op | B/op |
|---|--:|--:|
| ACE1, in-memory subslice | 1.91 | 0 |
| ACE1, two `pread`s from a file | 84,786 | 344,250 |
| tar, header walk | 94,763 | 346,623 |
| zip, central directory | 219,417 | 718,519 |

`[sandbox]`, for contrast: ACE1/pread 151,810; tar/scan 330,695;
binpazer sized 283,946; zip 737,160.

Three readings of this table.

**The 2.2 ns row is the real point about a fixed-width table**, not a fair
comparison: it is a subslice of an already-mapped blob. If the entry is
`mmap`'d — which binpazer is explicitly designed for and which ACE1 allows
too — extracting a member is address arithmetic and the only cost left is the
copy into the destination file. That is the ceiling every other row is
measured against.

**binpazer's read path costs about 3× ACE1's and 1.4× tar's** on the CI Linux
runner (203 µs vs 64 µs vs 141 µs), and the gap is structural rather than
implementation slop: footer read, index read, directory block read, JSON
unmarshal of the directory, then the member. ACE1 folds the directory into a
fixed-width table in the header, so the same information is one `pread`.

The right way to read that is against what happens next: writing the object
back out costs **1,277 µs** on the same machine (`local-layout.md`). So every
row above except the compressed ones is under 16% of the restore it precedes,
and the format choice is not the bottleneck. The **allocation counts** are the
number worth watching — 59–119 allocations per lookup against ACE1's 1–2, at
4,000 lookups per build.

**`io.ReadAll` versus a sized read is a 56% difference** (464 µs → 203 µs,
1.14 MB → 600 KB). The directory already carries the decoded size, so a real
implementation sizes the buffer exactly. Worth stating because the obvious
first cut uses `ReadAll`.

**The compressed rows are not measuring the format.** binpazer/zstd at 1,793 µs
and 11.7 MB per lookup, and binpazer/lz4 at 871 µs and 9.0 MB, are dominated by
constructing a fresh streaming codec per block — see "the codec layer is where
the time goes" below. The same 528 KB decodes in 705 µs with 59 B of allocation
through a pooled `zstd.DecodeAll`.

### Pack and unpack everything

`[ci] ubuntu`:

| format | pack ns/op | unpack-all ns/op | unpack B/op |
|---|--:|--:|--:|
| ACE1 | 210,353 | **54** | 96 |
| tar | 423,696 | 124,201 | 588,023 |
| tar + `manifest.json` | 423,974 | — | — |
| zip (stored) | 574,773 | 305,091 | 1,198,089 |
| binpazer, stored | 292,853 | 444,255 | 1,258,313 |
| binpazer, stored + CRC | 341,462 | 428,105 | 1,258,314 |
| binpazer, lz4 | 2,196,127 | 528,358 | 1,469,769 |
| binpazer, zstd | 6,329,890 | 2,002,478 | 12,693,329 |

ACE1's 54 ns unpack is again the zero-copy subslice: it returns views, not
copies. Everything else copies. Its pack is also the fastest of the four
uncompressed formats (210 µs vs tar's 424 µs and zip's 575 µs), because it is
one table write and N `copy`s.

**Per-block CRC costs ~17% on pack** (293 µs → 341 µs `[ci]`; 622 → 834 µs on
the noisier sandbox) and is **free on unpack** (428 µs vs 444 µs — within
noise). CRC-32C over 580 KB is 23 µs at the measured 23 GB/s, so the pack
difference is mostly the extra pass over the buffer rather than the polynomial.
Cheap enough to be default-on.

### The codec layer is where the time goes

binpazer's `Codec` interface is stream-shaped: `NewReader(io.Reader)` and
`NewWriter(io.Writer)` per block. Measured separately (`[ci] ubuntu`):

| | ns/op | B/op |
|---|--:|--:|
| `zstd.NewReader` construction (concurrency 1) | 478 | 1,304 |
| `zstd.NewReader` construction (default concurrency) | 1,169 | 3,776 |
| `lz4.NewReader` construction | 117 | 304 |
| zstd decode 528 KB, `DecodeAll`, pooled decoder | **704,893** | **59** |
| zstd decode 528 KB, fresh reader, streamed | 823,010 | 1,311,210 |
| lz4 decode 528 KB, fresh reader, streamed | 994,114 | **8,386,923** |
| lz4 decode 528 KB, reader reused with `Reset` | **328,417** | 1,350 |

Construction is cheap (117–478 ns); the **first read** is not. `pierrec/lz4`'s
reader allocates its block buffers lazily and a fresh reader per member costs
**8.4 MB of allocation** and 3× the time of a reused one. This is why
`BenchmarkBinpazerReadOne/sized/lz4` shows 9 MB/op: it is not binpazer's
framing, it is one `lz4.NewReader` per block. The pooled one-shot zstd path is
**12,000× cheaper in allocation** than the streaming one (59 B against 1.3 MB)
for the same output.

Any container with a stream-shaped codec layer needs pooled codec instances, or
a one-shot `DecodeAll` path for the common case where the decoded size is
already known. binpazer's `Codec` interface is `NewReader`/`NewWriter`, so
using it well means registering a codec whose reader is pooled — which
`RegisterCodec` allows, and which the default zstd and lz4 codecs do not do.

### The streaming gap

`probes/binpazer` `TestBinpazerStreamingWriterLosesIndex`. Reproduced
identically on `[ci] ubuntu`, `[ci] windows` and `[sandbox]`:

```
streamed file: len=145024 hasIndex=false
Find(directory) -> [], err=binpazer: block payload claims 6762810245124 bytes
                        but only 0 remain in the input: truncated input
seekable file: len=145024 hasIndex=true  Find(directory) -> [144696]
```

Same bytes of content, two writers. binpazer's `End()` back-patches
`file_length` at offset 32 **only when the writer is seekable**. A
non-seekable writer — an HTTP request body, a pipe, a compressing stream —
leaves `file_length` at the streaming sentinel. The reader's footer probe
requires `FileLength <= inputSize`, so it never looks at the footer;
`hasIndex` is false and `Find` falls back to a linear walk. The walk has no
`blocksEnd` to stop at, so it runs off the last block **into the 16-byte
footer** and reads `index_block_offset` as a block header, producing a garbage
length and `ErrTruncated`.

This is a real constraint, not a bug in the probe: **a binpazer entry that
wants its index must be produced by a seekable writer.** For a local cache
that is free — write to a temp file, `Finish`, rename. For a remote PUT it
means the entry is serialized to a buffer or a temp file first and then sent,
which is what the entry-per-key model does anyway. It rules out "compress and
frame straight into the socket". A streaming producer must either omit the
index and footer (then the file walks fine) or back-fill.

The same constraint applies in reverse to the *reader*: `Find`, `At`,
`FindLast` and therefore `DecodeJSONLast` all require a seekable input. A
receiver reading an entry off a socket either buffers it or walks it linearly.

## Criteria table

| | tar | ccache `.R` | ACE1 framed | zip | binpazer |
|---|---|---|---|---|---|
| index / random access | none — walk | none — walk | fixed-width table, O(1) | central directory, by name | Block Index by `type_id` + footer; names need a directory block |
| framing overhead (4 members, 580 KB) | +3,397 B | ~+40 B | +72 B | +450 B | +573 B |
| member naming | string path | `u8` role id | `u8` role id | string path | interned GUID type; **no per-block name** |
| per-member compression | no (whole-stream only) | no — whole payload, one codec + level in the header | possible, not specified | yes, but only deflate/stored in practice | **yes**, per block, `codec_id` registry incl. zstd and lz4, plus a GUID escape |
| integrity | none | XXH3-128 over header+payload, uncompressed | trailer field, unspecified | CRC-32 per member (over uncompressed bytes) | CRC-32C per block over the **stored** bytes, optional per block |
| forward compat | unknown member = a named file you ignore | version byte; role ids frozen | version byte | unknown method = unreadable member | `critical`/`safe_to_copy`/unknown-bit rules are specified; unknown block skippable by length |
| mmap + cast | no | no | yes if aligned | no | **yes — designed for it**, 8-byte aligned, LE, natural field alignment |
| streaming write | yes | yes | yes (offsets known up front only if sizes are) | no (central directory at end) | **only without the index**; `file_length` needs a seekable writer |
| streaming read | yes | yes | yes | no | linear walk yes; index/`Find`/`OpenAt` need a seeker |
| escape for link/reflink restore | no | **yes — `raw_file_entry`** | no | no | no (a block is inside the file) |
| other-language readers | everywhere | ccache only | none | everywhere | **C, C++ and Go in-repo**, MIT |
| license | stdlib | GPL-3.0 (behaviour only) | n/a | stdlib | MIT |

## What each one is good at

**tar** is the interop answer and the wrong local format. Its overhead is 6×
the next worst and it has no index, so "read only the object" is a walk. Its
one real advantage is that `/_batch/get` and `/_batch/put` already speak it, so
a *batch* of entries can be a tar of entries in whatever per-entry format is
chosen — the two decisions are independent.

**ccache's format** is the minimum that works, and its interesting feature is
not the framing but the `raw_file_entry` escape: the entry can say "this member
is a sibling file", which is the only way a container-based cache can also
hard-link or reflink the object into place. Any container design should decide
deliberately whether to have that escape, because retrofitting it means a
format version bump.

**ACE1** (a fixed-width offset table) is the performance ceiling: 0.012%
overhead, O(1) member lookup, two `pread`s to extract one member, and a
zero-copy subslice when mapped. It is also ~200 lines that nobody else can
read, with no C implementation, no spec, and no forward-compatibility story
beyond a version byte.

**zip** buys name-keyed lookup and universal tooling, at 6× ACE1's overhead and
the slowest single-member read measured (737 µs — `archive/zip` re-parses the
central directory per open). sccache's use of it as a stored-member directory
around zstd streams is a reasonable compromise, and the fact that any developer
can `unzip` a cache entry to debug it is worth something.

**binpazer** is the closest fit of the off-the-shelf options, and the reasons
are specific rather than general:

- Per-block compression with a real codec registry, and the block length
  always describing the *stored* bytes, so the structural walk is independent
  of codec support. This is the feature tar and ccache's format both lack and
  the one that lets stderr stay uncompressed while DWARF gets zstd-3.
- Per-block CRC-32C over the stored bytes, checkable before decoding, at a
  measured ~34% pack cost and ~5% read cost.
- A C implementation in the same repository, which matters if a thin native
  client is ever wanted: a compiler wrapper that must start in under a
  millisecond is exactly the place a Go runtime is unwelcome, and a `mmap` +
  pointer-cast reader in C is the cheapest possible restore.
- The forward-compatibility rules are actually written down —
  `critical`/`safe_to_copy`/ignore-unknown-bits — which is more than ACE1 or
  ccache's format offers.

Its costs are equally specific: **no per-block name**, so a directory block is
mandatory and the read path is footer → index → directory → member rather than
one table read; **the index requires a seekable writer**, so streaming straight
onto the wire is out; **~2× ACE1's single-member read** and 60× the
allocations; and **no raw-file escape**, so hard-link/reflink restore of the
object is not expressible.

None of that is disqualifying. Put next to the **1,277 µs** it takes to write
the object back out on the same machine, the difference between a 64 µs and a
203 µs extract is 11% of the restore. The allocation count is the number worth
watching, and it is mostly `io.ReadAll` and per-block codec construction rather
than the format itself.

## Sources

- binpazer — `SPEC.md` and `go/` in `wow-look-at-my/bin-file-fmt` (MIT)
- ccache result and cache-entry formats —
  `src/ccache/core/result.cpp`, `src/ccache/core/cacheentry.cpp`,
  <https://github.com/ccache/ccache> (GPL-3.0; behaviour described, no code
  copied)
- sccache `CacheRead`/`CacheWrite` — `src/cache/cache_io.rs`,
  <https://github.com/mozilla/sccache> (Apache-2.0)
- go-s3-server `/_batch/get` and `/_batch/put` — `batch.go` in this org
- Go `archive/tar`, `archive/zip` — BSD-3-Clause
- `klauspost/compress` — BSD-3-Clause; `pierrec/lz4` — BSD-3-Clause
