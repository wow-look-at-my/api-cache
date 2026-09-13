# The daemon option

**Source: GitHub Actions hosted runner `ubuntu-latest`, run
[34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912),
commit `9f95956`.** Whole-process rows are hyperfine
(`--shell=none --warmup 20 --runs 300`); the round-trip rows are in-process
means of 2,000. See [method.md](method.md). Raw output:
[`gha/daemon-roundtrip-linux-x64/`](gha/daemon-roundtrip-linux-x64/).

## The architecture

sccache's: a long-lived server holds the cache state, and each compiler
invocation execs a thin client that asks it over a unix socket. The protocol
measured here is the cheapest thing that could work — a 4-byte little-endian
length, a 512-byte request, a 65-byte reply, no framing library and no
serialization format — so what is measured is the **syscall and scheduler
floor** of the architecture, not the cost of a protocol nobody has chosen yet.

## (a) Whole process: exec the client, connect, round trip, exit

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C client, static` | 608.0 ± 35.5 | 544.5 | 737.4 | 1.00 |
| `C hello, no daemon contact` | 635.4 ± 33.9 | 582.6 | 829.8 | 1.05 ± 0.08 |
| `C client, dynamic` | 798.5 ± 34.3 | 722.9 | 943.8 | 1.31 ± 0.10 |
| `Go hello, no daemon contact` | 1059.6 ± 57.1 | 947.0 | 1381.5 | 1.74 ± 0.14 |
| `Go client` | 1290.2 ± 70.3 | 1165.7 | 1733.4 | 2.12 ± 0.17 |

## (b) The round trip alone, in process

    go client: dial+roundtrip+close 81.4 µs/op   roundtrip only (reused conn) 27.6 µs/op
    c client:  dial+roundtrip+close 66.0 µs/op   roundtrip only (reused conn) 22.2 µs/op

## Findings

### 1. The round trip is small: 66 to 81 µs including the connect

Against a process startup floor of 450 µs (C static) to 1,041 µs (Go), a unix
socket round trip is **noise**. Reusing the connection halves it again, to
22-28 µs, though a wrapper that execs once per file has no connection to reuse.

### 2. A thin C client plus a Go daemon is genuinely the cheapest option here

`C client, static` at 608 µs is the fastest row in the table, and it is
**within noise of a C hello that talks to nothing** (635 µs). The daemon
contact is free relative to the process it happens in.

Against the Go client's 1,290 µs, the C shim saves about **680 µs per exec**.
On a 10,000-file build that is roughly **7 seconds of wall time**, every build.

### 3. Link the C client statically or give the saving straight back

`C client, dynamic` is 798 µs against `C client, static` at 608 µs. **The
dynamic loader costs 190 µs per exec — more than twice the entire round trip
it is there to perform.** A thin client that is dynamically linked has spent
its own advantage on `ld.so` before it opens the socket.

### 4. Against the cooked-binary option, the daemon's win is smaller than it looks

The daemon's real argument is that the config load moves off the per-exec path
entirely, because the daemon holds the parsed form. But a cooked Go binary with
a shared template root already gets that cost down to ~279 µs
([config-load.md](config-load.md)):

| approach | startup | config | round trip | total |
|---|---|---|---|---|
| Go, cooked trailer, shared root | ~1,041 | ~279 + ~17 | — | **~1,337 µs** |
| Go client + Go daemon | ~1,041 | 0 | ~250 (measured delta) | **~1,290 µs** |
| C static client + Go daemon | ~451 | 0 | ~157 (measured delta) | **~608 µs** |

A Go daemon with a Go client buys almost nothing over a cooked Go binary: both
land near 1.3 ms, because the Go runtime startup that neither removes is the
dominant term. **The daemon is only worth its complexity with a native client
in front of it**, and at that point the daemon is doing the work the client
cannot: holding state.

### 5. What a microbenchmark cannot tell you

The numbers above are the cost when everything works. A daemon also brings
lifecycle (who starts it, when does it exit), version skew between client and
daemon, per-user versus per-project instances, a stale daemon serving a config
that has since changed on disk, and a failure mode where a wedged daemon hangs
every compile instead of falling back to a miss. A 157 µs saving does not price
any of that, and the decision should not be made on the 157 µs alone.

Also: this measures a daemon that answers instantly. A real one does a cache
lookup, which is disk or network, and that work is not in any row here.

## What is not covered

Linux x64 only, and a unix socket specifically. Windows has no unix-socket
equivalent in the same form (named pipes are the usual answer) and its process
floor is ten times taller, which changes the arithmetic in finding 4 completely:
against a 5.2 ms `CreateProcess`, a 66 µs round trip and a 2.1 ms Go runtime
are both small, so the case for a native client is much weaker there. That is
the single biggest gap in this file and it should be measured before the daemon
question is settled.
