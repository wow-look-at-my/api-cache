# Process startup floor

**Source: GitHub Actions hosted runners, run
[34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912),
commit `9f95956`.** Method: `hyperfine --shell=none --warmup 20 --runs 300`.
See [method.md](method.md). Raw tables and per-run JSON are under
[`gha/`](gha/).

## The question

A compiler wrapper is exec'd once per translation unit. What does one exec of
a do-nothing program cost in each candidate language, and what does the link
mode cost on top of that?

## Linux x64 (`ubuntu-latest`, AMD EPYC 7763, 4 cores, gcc 13.3, go 1.24.13, rustc 1.98.1)

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, static` | 450.8 ± 32.7 | 405.4 | 617.4 | 1.00 |
| `C++ iostream, static` | 567.7 ± 35.3 | 518.7 | 829.8 | 1.26 ± 0.12 |
| `C hello, dynamic` | 652.5 ± 41.9 | 585.3 | 884.0 | 1.45 ± 0.14 |
| `C++ iostream, -static-libstdc++` | 741.7 ± 41.0 | 676.8 | 977.0 | 1.65 ± 0.15 |
| `Rust hello` | 814.6 ± 41.2 | 740.5 | 1024.6 | 1.81 ± 0.16 |
| `Go hello, -ldflags=-s -w` | 1028.4 ± 70.8 | 908.8 | 1498.5 | 2.28 ± 0.23 |
| `Go hello, CGO_ENABLED=0` | 1041.2 ± 73.0 | 906.8 | 1330.9 | 2.31 ± 0.23 |
| `Go hello, CGO_ENABLED=1` | 1059.2 ± 58.2 | 935.0 | 1272.8 | 2.35 ± 0.21 |
| `C++ iostream, dynamic` | 1154.3 ± 51.9 | 1076.0 | 1379.4 | 2.56 ± 0.22 |
| `Go + net/http + encoding/xml + text/template` | 1259.8 ± 82.2 | 1132.2 | 1526.4 | 2.79 ± 0.27 |

Binary sizes: c-dyn 16 KB, c-static 785 KB, cpp-dyn 16 KB, cpp-static 2.33 MB,
cpp-staticcxx 1.43 MB, go-hello 1.89 MB, go-hello-sw 1.22 MB, go-imports
5.13 MB, rust-hello 4.51 MB.

## Linux ARM64 (`ubuntu-24.04-arm`, 4 cores, gcc 13.3, go 1.24.13, rustc 1.98.1)

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, static` | 349.0 ± 20.0 | 310.3 | 446.0 | 1.00 |
| `C++ iostream, static` | 443.0 ± 27.1 | 383.0 | 539.3 | 1.27 ± 0.11 |
| `C hello, dynamic` | 474.0 ± 31.0 | 402.1 | 567.7 | 1.36 ± 0.12 |
| `C++ iostream, -static-libstdc++` | 582.6 ± 31.5 | 520.2 | 699.7 | 1.67 ± 0.13 |
| `Rust hello` | 634.9 ± 33.1 | 562.1 | 805.2 | 1.82 ± 0.14 |
| `C++ iostream, dynamic` | 915.8 ± 34.2 | 826.3 | 1029.7 | 2.62 ± 0.18 |
| `Go hello, CGO_ENABLED=1` | 913.7 ± 52.3 | 810.9 | 1389.9 | 2.62 ± 0.21 |
| `Go hello, CGO_ENABLED=0` | 915.8 ± 46.8 | 807.4 | 1199.2 | 2.62 ± 0.20 |
| `Go hello, -ldflags=-s -w` | 919.4 ± 43.2 | 831.6 | 1366.6 | 2.63 ± 0.20 |
| `Go + net/http + encoding/xml + text/template` | 1135.5 ± 67.8 | 1002.6 | 1753.8 | 3.25 ± 0.27 |

## What the two platforms agree on

The absolute microseconds differ, and they should: two different machines. The
RATIOS are almost identical across them, which is what makes them worth
reading.

**1. Go costs about 2.3x to 2.6x the C static floor, and the gap is
~470 to ~570 µs per exec.** That is the whole Go tax for this role, and it is
the same tax on both architectures.

**2. Static linking is worth 30% to 40% in C.** Dynamic costs 1.45x static on
x64 and 1.36x on ARM64. The dynamic loader has to open, map and relocate libc
on every single exec, and at this scale that is not a rounding error.

**3. `<iostream>` is the expensive part of C++, and only when dynamic.**
Statically linked, C++ with iostream costs 1.26x the C floor on both platforms,
which is the `std::ios_base::Init` static initializer and little else.
Dynamically linked it costs 2.56x on x64 and 2.62x on ARM64 — as slow as Go —
because libstdc++ is a large shared object that the loader must process every
time. `-static-libstdc++` sits between them at 1.65x. **A C++ implementation
that links libstdc++ dynamically throws away the entire reason to choose C++
here.**

**4. Stripping a Go binary buys nothing.** `-ldflags=-s -w` takes 1.89 MB down
to 1.22 MB and moves the time by less than the noise. Binary size and startup
time are not the same axis: the kernel maps what the program touches, and the
symbol table is not touched.

**5. `CGO_ENABLED` does not matter for a program that uses no cgo.** The two
rows are within noise of each other on both platforms, and the binaries are
within 32 bytes of the same size.

**6. Importing net/http, encoding/xml and text/template costs ~220 µs per exec
over the Go floor** on both platforms (1041 → 1260 on x64, 916 → 1136 on
ARM64). That is package-level `init` work happening before `main` on every
invocation, and it is paid whether or not the program does any HTTP.

## macOS and Windows

Those legs of the matrix are in [ci-platforms.md](ci-platforms.md) with their
own tables and their own caveats. macOS carries no static rows at all: Apple
does not support statically linking libSystem, and clang there links libc++
dynamically, so the static-versus-dynamic comparison has no honest counterpart
on that platform.
