# Why the startup floors differ: syscall counts

**Source: GitHub Actions hosted runner `ubuntu-latest`, run
[34728781892](https://github.com/wow-look-at-my/api-cache/actions/runs/34728781892),
commit `9b08f71`.** Method: `strace -c -f <prog>`, which follows the threads a
runtime clones. Raw summaries:
[`gha/syscall-counts-linux-x64/`](gha/syscall-counts-linux-x64/).

A count is not a timing. The same program makes the same syscalls every run, so
this table is not sensitive to a noisy neighbour the way the millisecond tables
are. It is here because [startup-floor.md](startup-floor.md) says Go costs about
2.3x a static C binary and does not say what Go is spending it on.

| binary | total syscalls | clone | rt_sigaction | mmap | openat |
|---|---|---|---|---|---|
| c-static | **17** | | | | |
| c-dyn | **35** | | | 8 | 2 |
| go-hello | **206** | 4 | 114 | 22 | 1 |
| go-imports (net/http + encoding/xml + text/template) | **203** | 4 | 114 | 22 | 1 |

An empty cell means the program makes that syscall zero times.

## Findings

### 1. Go makes 12x the syscalls of a static C binary before it prints anything

17 against 206. That is the 2.3x wall-clock gap, in the units the kernel
charges for.

### 2. Over half of Go's syscalls are installing signal handlers

**114 of 206 are `rt_sigaction`.** The Go runtime installs a handler for every
signal it wants to manage before `main` runs, because the scheduler needs
`SIGURG` for preemption, and the runtime wants to turn faults into panics.
A static C hello installs none.

This is not a cost the program chose and it is not one an author can opt out
of. It is the price of the runtime being there, paid on every exec whether the
program runs for a microsecond or a day — which is exactly the wrong shape for
a process that is exec'd ten thousand times and lives for a millisecond.

### 3. Four clones: the scheduler builds a thread pool for a program with one goroutine

`go-hello` writes six bytes and exits, and it still starts four additional OS
threads. `sysmon`, and the Ms the scheduler spins up for `GOMAXPROCS`, do not
know the program is about to be done.

### 4. Dynamic linking exactly doubles C's syscall count

17 to 35, and the added calls are `openat` and `mmap`: `ld.so` finding libc,
mapping it, and relocating. That is the mechanism behind the 31% wall-clock
penalty for dynamic linking in the startup-floor table.

### 5. Importing net/http, encoding/xml and text/template adds NO syscalls

206 against 203 — the import-heavy binary makes slightly fewer, which is noise
in whichever thread happened to be scheduled. Yet the same binary costs
**220 µs more** per exec in the timing table.

That is worth stating plainly, because it locates the cost. **Package `init`
work is CPU, not syscalls.** Building maps, compiling regexps, constructing the
TLS ciphersuite list and the mime type tables all happen in user space. So the
import cost cannot be found by counting syscalls, it does not show up in
`strace`, and the only way to see it is to time the two binaries side by side,
which is what [startup-floor.md](startup-floor.md) does.

## What this does and does not tell you

It explains the Go tax and it prices dynamic linking. It says nothing about the
config load, which is pure user-space CPU and is measured in
[config-load.md](config-load.md) instead. It is Linux-only: Windows has no
strace and its cost lives inside `CreateProcess`, which is why its floor is
5.2 ms rather than 451 µs ([ci-platforms.md](ci-platforms.md)).
