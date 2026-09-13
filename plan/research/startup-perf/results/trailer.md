# The cooked trailer: appending a compiled config to the binary

**Source: GitHub Actions hosted runner `ubuntu-latest`, run
[34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912),
commit `9f95956`.** The exec table is hyperfine
(`--shell=none --warmup 20 --runs 300`); the read tables are in-process medians
of 400. See [method.md](method.md). Raw output:
[`gha/cooked-trailer-linux-x64/`](gha/cooked-trailer-linux-x64/).

## The idea

Compile the XML once at install time, append the result to the executable, and
have the binary read its own tail on startup. Two separate questions.

## (a) Does a trailer slow `execve`? No.

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `Go, 3 KiB trailer` | 1.1 ± 0.1 | 1.0 | 1.5 | 1.03 ± 0.10 |
| `Go, 1 MiB trailer` | 1.1 ± 0.1 | 1.0 | 1.3 | 1.03 ± 0.09 |
| `Go, 10 MiB trailer` | 1.1 ± 0.1 | 0.9 | 1.4 | 1.00 |

The targets exit without reading the trailer, so this is purely file size. A
10 MiB trailer starts no slower than a 3 KiB one, and the 10 MiB row is
nominally the fastest, which is how you know the difference is noise.

This is the expected result and it is worth stating why: `execve` maps the
ELF's own program headers. Bytes past the last segment are not part of any
mapping and are never paged in. **Binary size and startup time are different
axes.** The same reasoning explains why stripping a Go binary buys nothing
(see [startup-floor.md](startup-floor.md)).

## (b) Reading the trailer: cheap, but only if it is small

| binary | `os.Executable` µs/op | read trailer µs/op | payload |
|---|---|---|---|
| 3 KiB trailer | 4.1 | 10.6 | 3,072 bytes |
| 1 MiB trailer | 9.0 | 126.0 | 1,048,576 bytes |
| 10 MiB trailer | 10.1 | 1,231.8 | 10,485,760 bytes |

`os.Executable` is a `readlink` of `/proc/self/exe` and is effectively
constant. The read scales with the payload at roughly 8 GB/s, which is memory
bandwidth, not cleverness.

**So the trailer must stay small.** 3 KiB costs ~15 µs all in, which against a
~1,041 µs Go startup floor is 1.4%. 10 MiB costs 1.2 ms, which doubles the
process cost. The compiled-template form of the 30 KB sample config is **2,862
bytes** ([config-load.md](config-load.md)), which lands exactly in the cheap
column. A cooked form that embedded the whole DOM instead would not.

## (c) The same thing through binpazer, a real container format

[binpazer](https://github.com/wow-look-at-my/bin-file-fmt) (MIT, vendored in
this repository as the submodule `refs/bin-file-fmt`) is block-based with a
16-byte footer at the very END of the file: the magic `rezapnib` plus the
absolute offset of a Block Index. A reader takes the last 16 bytes, jumps to the
index, and seeks straight to the block it wants.

Two blocks stand in for a cooked config: a 24 KiB string table and the 2,862-byte
rules block. Container: 27,728 bytes, **1.1% overhead** over the two payloads.

Container alone, in memory:

| operation | µs |
|---|---|
| open reader (header + type table + footer) | 4.3 |
| open + `FindFirst(rules)` + `ReadPayload` | 4.8 |
| open + both blocks | 6.8 |

Appended to a real 2.5 MB executable, read from disk:

| operation | µs | note |
|---|---|---|
| **Go: open + last 8 B + section reader + rules block** | **17.0** | the whole per-exec cost |
| Go: open + close only | 5.6 | the syscall floor under it |
| **C: open + footer + index + rules block** | **19.6** (min 19.5, mean 20.2) | allocation-free reader |
| C: open + close only | 3.0 | the syscall floor under it |

### What this says

**The container costs essentially nothing over a hand-rolled footer.** 17 µs
against the raw offset read's ~15 µs, for a spec, a versioning story, a C
implementation and skippable unknown blocks.

**Block-level laziness is real.** Reading only the rules block costs 4.8 µs
against 6.8 µs for both. A wrapper on a cache hit never touches the string
table. That is the property a flat blob does not have.

**The C reader is not faster than the Go one here, and that is the point.**
19.6 µs versus 17.0 µs — the C side is nominally slower, within noise. Both are
doing the same four syscalls, and at this size the work is syscalls rather than
parsing. **Reading a cooked trailer is not a reason to write the client in C.**
Whatever case exists for a C client (see [daemon.md](daemon.md)) has to be made
on process startup, not on this.

### Two traps worth recording

**The container must be written through a seekable writer.** `Writer.End`
back-patches `file_length` in the header, and skips that when it cannot seek.
The reader's footer probe is gated on `file_length`, so a container generated
through a pipe comes back with `HasIndex() == false` and every lookup silently
degrades to a full forward walk — same answers, none of the speed. The probe
asserts `HasIndex()` before timing anything, and the build writes through a
temp file rather than a `bytes.Buffer` for this reason.

**Offsets inside the container are relative to the container, not the file.**
Appending it to an executable means the footer and index offsets need rebasing.
`io.NewSectionReader` does it in Go and a base offset in the read callback does
it in C. The file's own last 8 bytes carry the container length so the base can
be computed; binpazer's footer gives the index offset, which is not the same
thing.
