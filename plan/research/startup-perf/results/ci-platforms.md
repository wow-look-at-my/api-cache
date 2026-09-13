# Static versus dynamic linking, across platforms

**Source: GitHub Actions hosted runners.** Method:
`hyperfine --shell=none --warmup 20 --runs 300`. See [method.md](method.md).

The Linux tables and their analysis are in
[startup-floor.md](startup-floor.md). This file is the cross-platform view of
one question: **what does the link mode cost per exec, on each platform a
developer actually builds on?**

Rows within one platform are comparable. Rows across platforms are not: each is
a different machine.

## The link-mode question, per platform

| platform | what "static" means there | measured |
|---|---|---|
| Linux x64 | `gcc -static`, whole binary | yes |
| Linux ARM64 | `gcc -static`, whole binary | yes |
| macOS ARM64 | **nothing.** Apple does not support statically linking libSystem, and clang there links libc++ dynamically | not measurable |
| Windows x64 | MSVC `/MT` (static CRT) versus `/MD` (CRT DLL) | see below |

## Linux x64 (`ubuntu-latest`), run [34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912)

| Command | Mean [µs] | Min [µs] | Relative |
|:---|---:|---:|---:|
| C hello, **static** | 450.8 ± 32.7 | 405.4 | 1.00 |
| C hello, dynamic | 652.5 ± 41.9 | 585.3 | 1.45 |
| C++ iostream, **static** | 567.7 ± 35.3 | 518.7 | 1.26 |
| C++ iostream, `-static-libstdc++` | 741.7 ± 41.0 | 676.8 | 1.65 |
| C++ iostream, dynamic | 1154.3 ± 51.9 | 1076.0 | 2.56 |

**Static costs 31% less than dynamic in C.** In C++ the spread is far wider:
fully static is 1.26x the C floor, dynamic is 2.56x. The dynamic loader has to
process libstdc++, a large shared object, on every exec.

## Linux ARM64 (`ubuntu-24.04-arm`), same run

| Command | Mean [µs] | Min [µs] | Relative |
|:---|---:|---:|---:|
| C hello, **static** | 349.0 ± 20.0 | 310.3 | 1.00 |
| C hello, dynamic | 474.0 ± 31.0 | 402.1 | 1.36 |
| C++ iostream, **static** | 443.0 ± 27.1 | 383.0 | 1.27 |
| C++ iostream, `-static-libstdc++` | 582.6 ± 31.5 | 520.2 | 1.67 |
| C++ iostream, dynamic | 915.8 ± 34.2 | 826.3 | 2.62 |

The ratios track x64 almost exactly. Static is worth 26% here against 31% on
x64, and every C++ row is within 0.06 of its x64 counterpart. **The link-mode
finding is architecture-independent on Linux.**

## macOS ARM64 (`macos-latest`)

**There is no static row on macOS, and that is a platform fact rather than a
missing measurement.** Apple ships no `crt1.o` for a fully static link, the
libSystem ABI is the dylib, and clang on macOS links libc++ dynamically. The
job does not attempt those targets, it names them as unsupported, and the
report says so in place of numbers.

What that means for the project: **any design whose startup number depends on
static linking does not have that number on macOS.** A C or C++ wrapper that is
fast on Linux because it is statically linked is, on macOS, a dynamically
linked one — and the Linux tables above show dynamic C++ costing as much as Go.

The macOS dynamic rows from an earlier run of the same probes
([34728086460](https://github.com/wow-look-at-my/api-cache/actions/runs/34728086460))
are in [`gha/startup-floor-macos-arm64/`](gha/startup-floor-macos-arm64/) where
that artifact was captured; the macOS runner queue did not deliver the leg in
the runs used for the tables above, so no macOS figures are quoted here as
reported numbers.

## Windows x64 (`windows-latest`), run [34728713242](https://github.com/wow-look-at-my/api-cache/actions/runs/34728713242)

MSVC 19.51.36256, located through `vswhere` and `VsDevCmd.bat` rather than a
third-party action. `/MT` links the CRT into the exe; `/MD` uses the CRT DLL.

**Note the unit. This table is in MILLISECONDS; the Linux tables are in
microseconds.**

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C++ iostream, MSVC /MT (static CRT)` | 5.2 ± 0.2 | 5.0 | 6.5 | 1.00 |
| `C hello, MSVC /MT (static CRT)` | 5.2 ± 0.3 | 5.0 | 6.6 | 1.00 ± 0.06 |
| `Rust hello` | 5.7 ± 0.5 | 5.3 | 9.5 | 1.10 ± 0.10 |
| `C hello, MSVC /MD (shared CRT)` | 6.0 ± 0.6 | 5.4 | 8.4 | 1.14 ± 0.11 |
| `C++ iostream, MSVC /MD (shared CRT)` | 6.2 ± 0.3 | 5.8 | 8.6 | 1.18 ± 0.08 |
| `Go hello, CGO_ENABLED=0` | 7.3 ± 0.3 | 6.9 | 8.4 | 1.39 ± 0.07 |
| `Go hello, -ldflags=-s -w` | 7.3 ± 0.3 | 6.9 | 8.6 | 1.39 ± 0.08 |
| `Go hello, CGO_ENABLED=1` | 7.3 ± 0.4 | 7.0 | 9.8 | 1.40 ± 0.09 |
| `Go + net/http + encoding/xml + text/template` | 9.5 ± 0.5 | 9.0 | 12.8 | 1.82 ± 0.12 |

### Windows is a different problem from Linux

**1. Process creation costs about ten times more.** The cheapest thing any
platform here can do is start a static C program: **451 µs on Linux x64,
5,200 µs on Windows.** `CreateProcess` is not `fork` plus `execve`, and on a
build that execs a wrapper 10,000 times that floor alone is **52 seconds on
Windows against 4.5 seconds on Linux**, before the wrapper does anything.

**2. Because of that, the language choice matters much less.** Go is 2.31x the
C static floor on Linux and only **1.39x** on Windows. The Go runtime's
bring-up has not got cheaper; it is being measured against a floor five times
taller, so it is a smaller fraction of it. The absolute Go tax is about 2.1 ms
on Windows against about 0.59 ms on Linux, so it did not shrink either — the
whole picture just moved up.

**3. `/MT` beats `/MD`, by less than static beats dynamic on Linux.** 5.2 ms
against 6.0 ms in C, a 13% saving, where Linux's static-versus-dynamic gap is
31%. The CRT DLL is usually already resident and mapped on Windows, which is
exactly the thing `ld.so` has to redo per exec on Linux.

**4. `<iostream>` is nearly free on Windows.** C++ with iostream costs the same
as C at `/MT` (5.2 ms both) and 0.2 ms more at `/MD`. On Linux the same code
costs 1.26x statically and **2.56x** dynamically. Whatever the C++ standard
library costs to initialize, on Windows it disappears under `CreateProcess`.

**5. The import cost is the one thing that got dramatically worse.** Adding
net/http, encoding/xml and text/template costs **2.2 ms** on Windows against
**0.22 ms** on Linux — ten times as much, and a quarter of the total exec.
That is the largest single lever visible in the Windows column, and it is one a
Go implementation controls directly by not importing what it does not use.

**6. Rust is closer to C here than on Linux.** 1.10x the C floor against 1.81x
on Linux, for the same reason as everything else in this table.

### What was fixed to get this table

The first Windows attempt failed at checkout: a sibling worker's file name held
a backslash, which Windows git refuses for the whole index. The second got past
checkout and built every target, but every benchmark died with
`program not found`, because under `--shell=none` hyperfine splits each command
with shell-words rules, in which a backslash is an escape character, so
`D:\a\repo\out\c-dyn.exe` arrived as `D:arepooutc-dyn.exe`. Forward slashes,
which Windows accepts, fix it.

**That second attempt went green with an empty table**, because hyperfine
creates its export file before it runs, so a `Test-Path` check passed. The job
now asserts a non-empty table with at least one row per target, on both the
Windows and the unix side. A partial result that looks complete is worse than a
failure, because it gets copied into a document and read as an answer.
