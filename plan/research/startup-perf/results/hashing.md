# Hashing throughput

**Source: GitHub Actions hosted runners, run
[34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912),
commit `9f95956`.** In-process, median of 60 iterations over a 4 MiB buffer
already in memory. See [method.md](method.md). Raw output:
[`gha/hashing-linux-x64/`](gha/hashing-linux-x64/) and
[`gha/hashing-linux-arm64/`](gha/hashing-linux-arm64/).

## Why this matters here

A compiler wrapper hashes something on every invocation to build its cache key
— the preprocessed output, or the source plus every header it pulls in. A 200
KiB translation unit is a modest one. Whether that hash costs 100 µs or 600 µs
decides whether hashing is a rounding error against process startup or a peer
of it.

## Linux x64 (`ubuntu-latest`, AMD EPYC 7763, **sha_ni present**)

| hash | MB/s | µs per 200 KiB | note |
|---|---|---|---|
| crc32 (Castagnoli) | 20,989 | 10 | hardware CRC instruction; **not** collision resistant |
| xxhash64 | 6,483 | 31 | public-domain algorithm; **not** collision resistant |
| blake3 | 4,653 | 43 | pure Go, AVX-512 path; cryptographic |
| **sha256** | **1,513** | **132** | stdlib; SHA-NI in use on this CPU |
| sha1 | 1,049 | 191 | broken for security; speed reference only |
| md5 | 677 | 295 | broken for security; speed reference only |
| sha512 | 648 | 309 | no dedicated instruction; raw ALU throughput |
| fnv64a | 764 | 262 | **not** collision resistant |

## Linux ARM64 (`ubuntu-24.04-arm`, ARMv8 `sha2` crypto extensions present)

| hash | MB/s | µs per 200 KiB | note |
|---|---|---|---|
| crc32 (Castagnoli) | 25,787 | 8 | hardware CRC instruction; **not** collision resistant |
| xxhash64 | 14,216 | 14 | public-domain algorithm; **not** collision resistant |
| **sha256** | **2,025** | **99** | stdlib; ARMv8 crypto extensions in use |
| sha1 | 1,952 | 102 | broken for security; speed reference only |
| blake3 | 1,405 | 142 | pure Go, **generic path on ARM64** |
| sha512 | 1,267 | 158 | no dedicated instruction |
| fnv64a | 1,041 | 192 | **not** collision resistant |
| md5 | 677 | 295 | broken for security; speed reference only |

## End to end: open + read + sha256 + close, one 200 KiB file

| method | x64 µs | ARM64 µs |
|---|---|---|
| `io.Copy` into sha256 (32 KiB default buffer) | 152 | 112 |
| `os.ReadFile` then `sha256.Sum256` | 151 | 118 |
| reused 256 KiB buffer | 142 | 107 |
| open + close only | 5 | 2 |

## Findings

### 1. With hardware sha acceleration, sha256 is cheap enough to stop arguing about

**132 µs per 200 KiB on x64, 99 µs on ARM64.** Against a Go process startup
floor of ~1,041 µs and ~916 µs, hashing a typical translation unit is
**10% of the exec cost**. Both runner classes here carry the acceleration
(x86 `sha_ni`, ARMv8 `sha2`), and so does essentially every CPU shipped in the
last decade.

The end-to-end figure is the honest one: the whole open-read-hash-close of a
200 KiB file is **142-152 µs on x64 and 107-118 µs on ARM64**, and the syscalls
are 2-5 µs of that. It is all hash.

### 2. That answer is hardware-dependent, and the dependence is large

On a machine WITHOUT sha acceleration, Go's sha256 falls to the generic path.
The development sandbox this research was written on is such a machine (an Intel
Xeon with AVX-512 but no `sha_ni`), and there sha256 measured **348 MB/s** —
**4.3x slower** than the accelerated x64 runner, putting a 200 KiB hash at
~575 µs, which is over half a process startup. That figure is from the
superseded local record (`raw-hashing.txt`) and is cited only to size the
cliff, not as a reported number.

**A wrapper should not assume sha256 is cheap. It should measure the host it is
installed on, or pick a hash that does not depend on an instruction.**

### 3. BLAKE3 is the hedge, and its advantage is architecture-specific

On x64, BLAKE3 at 4,653 MB/s is **3x faster than an accelerated sha256** and
about 13x faster than an unaccelerated one, while still being cryptographic.
On ARM64 the pure-Go implementation has no vector path and runs at 1,405 MB/s,
**slower than the accelerated sha256's 2,025 MB/s**.

So BLAKE3 is not a free win. It is a large win where sha acceleration is absent
and x86 vectors are present, and a loss where sha acceleration is present and
BLAKE3's vector path is not. The two are almost mirror images across these two
runners, which is exactly why both were measured.

### 4. The non-cryptographic hashes are 5-20x faster, and they are a different decision

crc32 at 8-10 µs and xxhash64 at 14-31 µs per 200 KiB are effectively free. But
a build cache key that collides serves the wrong object, and a wrong object is a
miscompile that looks like a working build. Whether a non-cryptographic hash is
acceptable depends on the threat model — accidental collision only, or an
attacker who can choose inputs — and that is not a performance question. The
rows are here so the cost of the cryptographic choice is visible, not to
recommend the cheap one.

### 5. sha512 is not the usual escape hatch here

The common advice that sha512 beats sha256 in Go holds only where sha256 has no
hardware path. On both of these runners sha256 is accelerated and sha512 is not,
so sha512 is **2.3x slower on x64 and 1.6x slower on ARM64**. On the
unaccelerated sandbox the order reverses. It tracks the hardware, not the
algorithm.

### 6. Buffer strategy barely matters

`io.Copy` with its 32 KiB default, `os.ReadFile` with one big allocation, and a
reused 256 KiB buffer are within 7% of each other. The hash dominates.
Optimizing the read path of a wrapper's hasher is not where the time is.

## Licenses

BLAKE3 is measured through `lukechampine.com/blake3` (MIT). xxHash64 is written
out inline in the probe rather than imported: the algorithm is Yann Collet's,
placed in the public domain, and the reference C implementation is BSD-2-Clause.
Everything else is the Go standard library.
