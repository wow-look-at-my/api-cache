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

## Windows x64 (`windows-latest`)

Windows spells the question `/MT` (static CRT, linked into the exe) versus
`/MD` (the CRT as a DLL). Both are built with MSVC, located through `vswhere`
and `VsDevCmd.bat` rather than a third-party action.

**The Windows leg has not yet produced a table.** The first attempt failed at
checkout (a sibling worker's file name held a backslash, which Windows git
refuses for the whole index). The second got past checkout and built every
target — the binary sizes came back — but every hyperfine benchmark died with
`program not found`:

    Benchmark 1: C hello, MSVC /MD (shared CRT)
    Error: Failed to run command 'D:\a\api-cache\api-cache\out\c-dyn.exe': program not found

The cause is that under `--shell=none` hyperfine splits each command with
shell-words rules, in which a backslash is an escape character, so the Windows
path arrives with its separators eaten. The fix (forward slashes, which Windows
accepts) is in `probes/ci/run-windows.ps1`.

That attempt is also the reason this research now asserts a non-empty table
with the expected row count rather than merely a file that exists: **hyperfine
creates its export file before it runs, so the job went green with an empty
table and a complete-looking binary-size section.** That is exactly the kind of
partial result that gets copied into a document and read as an answer.

Binary sizes from that run, which did build correctly:

| binary | bytes |
|---|---|
| c-dyn.exe (`/MD`) | 9,728 |
| c-static.exe (`/MT`) | 110,592 |
| cpp-dyn.exe (`/MD`) | 11,776 |
| cpp-static.exe (`/MT`) | 215,040 |
| go-hello-nocgo.exe | 1,985,536 |
| go-hello-cgo.exe | 1,986,048 |
| go-hello-sw.exe | 1,314,816 |
| go-imports.exe | 5,303,296 |
| rust-hello.exe | 131,072 |

Sizes are not timings and nothing should be inferred from them about startup —
the Linux tables show a 1.22 MB and a 1.89 MB Go binary starting in the same
time. They are recorded because the build half of the Windows job is known
good, which narrows what remains to be fixed.
