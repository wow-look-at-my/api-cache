# startup-perf

Can Go keep process startup competitive with C/C++ for a compiler wrapper, and
what does loading a declarative XML config cost per exec?

**Every number here comes from a GitHub Actions hosted runner.** Whole-process
timings are hyperfine 1.19.0 with `--shell=none --warmup 20 --runs 300`;
microsecond-scale in-process stages are timed by the probe itself. See
[results/method.md](results/method.md) for why, and for what is comparable with
what.

## Summary

Go's startup floor is **~1,041 µs** against C's static **~451 µs** on the same
Linux x64 runner: **2.3x, a gap of ~590 µs per exec.** ARM64 agrees at 2.6x.
That gap is real but it is not the biggest number in this research.

**Loading the XML config naively costs ~2,269 µs — more than twice the process
it runs in.** Parsing 30 KB of XML is ~900 µs and parsing the resulting Go
templates is another ~800 µs. Anyone weighing Go against C on startup alone is
arguing about the smaller term.

A cooked form fixes most of it, but **not the way you would expect**. Decoding
pre-compiled templates costs **1.7 µs**, so the XML parse vanishes — yet
`text/template.Parse` remains, and almost all of THAT is `Funcs()` copying
sprig's 214-entry map into every template: 20 templates cost **809 µs** with a
per-template func map and **50 µs** with none. Sharing one root template so the
map is copied once takes all 76 templates from **3,417 µs to 276 µs, 12x**.
Cooked form plus shared root: **2,269 → 279 µs, an 8x win**, and the config
load drops from twice the process cost to a quarter of it.

Appending the cooked form to the binary is free: a 10 MiB trailer execs no
slower than a 3 KiB one, because bytes past the last ELF segment are never
paged in. Reading a 3 KiB trailer costs **~15 µs**, or **17 µs** through
[binpazer](https://github.com/wow-look-at-my/bin-file-fmt) (MIT), which buys a
real format with a block index for 1.1% size overhead. The same read from C is
**19.6 µs** — *slower* — so reading a cooked config is no reason to write a
native client.

A daemon is only worth it with a native client. A unix round trip is **66-81 µs
including connect**, noise beside any startup. A Go client plus Go daemon lands
at **1,290 µs**, barely better than a cooked Go binary's ~1,337 µs, because the
Go runtime neither removes. A **static C client is 608 µs** — within noise of a
C hello that talks to nothing. Link that client dynamically and `ld.so` costs
**190 µs**, more than twice the round trip it exists to perform.

**Windows is a different problem.** A static C hello costs **5.2 ms** there
against 451 µs on Linux: `CreateProcess` is roughly **10x** `fork`+`execve`, so
a 10,000-file build pays ~52 s of process creation before the wrapper does
anything. Because that floor is so tall, Go costs only **1.39x** it instead of
2.31x, and `<iostream>` is free rather than a 2.56x penalty. The one thing that
gets *worse* is imports: net/http + encoding/xml + text/template cost **2.2 ms**
on Windows against 0.22 ms on Linux.

Two more measured facts. Static linking is worth **30-40% in C on Linux** (13%
on Windows, where the CRT DLL is usually already resident), and dynamic
`<iostream>` on Linux costs as much as Go — a C++ wrapper linking libstdc++
dynamically has thrown away its reason to exist. And sha256 is cheap **only with
hardware acceleration**: 132 µs per 200 KiB on a runner with `sha_ni`, but 4.3x
slower on a machine without it.

## Files

| file | what is in it |
|---|---|
| [results/method.md](results/method.md) | how everything was measured, and every caveat |
| [results/startup-floor.md](results/startup-floor.md) | C/C++/Go/Rust, static vs dynamic, Linux x64 and ARM64 |
| [results/ci-platforms.md](results/ci-platforms.md) | the macOS and Windows legs, with their platform limits |
| [results/config-load.md](results/config-load.md) | XML parse, compile, template parse, and every cooked alternative |
| [results/trailer.md](results/trailer.md) | trailer exec cost, trailer read cost, binpazer in Go and C |
| [results/daemon.md](results/daemon.md) | unix-socket round trip, Go client vs C client |
| [results/hashing.md](results/hashing.md) | sha256/blake3/xxhash/crc32 throughput, x64 and ARM64 |
| [options.md](options.md) | the options for closing the gap, each with its measured cost |

`results/gha/` holds the raw artifacts each job uploaded, including hyperfine's
per-run JSON. `results/raw-*.txt` are the development record from the sandbox
and are marked superseded; they are not reported numbers.

`probes/` holds every probe and CI script. The workflow is
[.github/workflows/startup-perf.yml](../../../.github/workflows/startup-perf.yml).
