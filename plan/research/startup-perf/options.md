# Options for closing the startup gap

Each option below carries its measured cost, or a cited one where it could not be
measured here. Every measured figure comes from a GitHub Actions hosted runner
and names its job; nothing here was timed on the development sandbox.

This file lists options and prices them. It does not choose one. The closing
section says only what the numbers suggest.

## What the numbers have to cover

A compiler wrapper is exec'd once per translation unit. A build of 10,000 files
therefore multiplies every per-exec millisecond into ten seconds of wall time
that no amount of cache hit rate wins back. Three costs stack up per exec:

1. **Process startup** -- `execve` plus whatever the runtime does before `main`.
2. **Config load** -- turning the declarative XML into something executable.
3. **The work** -- hashing the inputs and asking the cache.

An option is only interesting if it moves one of those three, and the sizes are
very different, so an option that moves the smallest one is not worth its
complexity.

## The options

### 1. Plain Go binary, XML parsed on every exec

The obvious implementation. No cooking, no daemon, no cache of the parsed form.

- Cost: the Go startup floor, plus the full parse-compile-template-parse chain.
- See `results/startup-floor.md` and `results/config-load.md`.
- The config load is the dominant term, and it is larger than the whole process
  startup. That is the finding that makes every other option on this list worth
  discussing.

**Verdict:** priced out by the config-load numbers, not by Go.

### 2. Go with a cooked trailer appended to the binary

Compile the XML once, at install time, and append the result to the executable.
The binary reads its own tail on startup.

- A trailer does not slow `execve`: the kernel maps the ELF's own segments and
  never touches bytes past the last one. Measured at 3 KiB, 1 MiB and 10 MiB in
  `results/trailer.md`.
- Reading a small trailer is a `readlink` of `/proc/self/exe`, one `open`, and
  two `ReadAt`s. The cost is in `results/trailer.md`.
- The trailer must stay SMALL. Reading a megabyte costs a megabyte of copying,
  which is real time; the compiled-template form of the 30 KB sample config is
  under 3 KB, which is the right size.

**Caveat that decides the option:** the cooked form removes the XML parse. It
does NOT remove `text/template.Parse`, which is a separate and larger cost, and
it does not remove building the template function map. Both are measured
separately in `results/config-load.md`, along with the two ways around them.

**License:** none. This is a footer format written for the purpose.

### 3. Go with a cooked trailer in binpazer

Same as option 2, but the trailer is a real container format rather than an
ad-hoc footer.

[binpazer](https://github.com/wow-look-at-my/bin-file-fmt) is a block-based
binary container with a 16-byte footer at the very end of the file: the magic
`rezapnib` plus the absolute offset of a Block Index. A reader takes the last 16
bytes, jumps to the index, and seeks straight to the blocks it wants. That is
exactly the access pattern a config trailer needs, and it means a wrapper on a
cache hit can read the rules block without touching the string table at all.

- Go and C read costs are both in `results/trailer.md`. The C implementation
  takes injected read and seek callbacks and allocates nothing, which is what
  makes it usable from a thin client as well.
- Appending a container to an executable needs one detail: every offset inside
  is relative to the container start, not the file start. An `io.SectionReader`
  (Go) or a base offset in the read callback (C) rebases them. The file's own
  last 8 bytes carry the container length so the base can be found.
- **A trap worth writing down:** `Writer.End` back-patches `file_length` in the
  header only when the destination is seekable. Generate the container through a
  pipe and the reader's footer probe finds nothing, `HasIndex()` is false, and
  every lookup silently degrades to a full forward walk. The probe here asserts
  `HasIndex()` before timing anything for that reason.

**License:** MIT.

**What it buys over option 2:** a spec, a C reader, block-level laziness, and
forward compatibility (unknown blocks are skippable) for a few microseconds and
about 1% size overhead on the sample payloads.

### 4. Go with a serialized sidecar cache keyed by the XML's mtime and hash

Compile the XML on first use, write the compiled form next to it, and on every
later exec check the key and load the sidecar.

- Removes the same parse cost as options 2 and 3, and leaves the same
  `text/template.Parse` cost behind.
- Adds a `stat` of the XML plus a validity check per exec, and a
  write-and-rename on the cold path.
- Three encodings are priced in `results/config-load.md`: `encoding/gob` of the
  DOM, a hand-rolled string-table-plus-node-array flat format, and the compiled
  template sources alone. They differ by more than an order of magnitude, so the
  encoding choice matters more than the sidecar-versus-trailer choice.

**Against the trailer:** a sidecar can go stale, can be deleted, can be written
by a different version of the tool, and needs a cache directory and its
invalidation rules. A trailer cannot get out of step with its binary because it
IS its binary.

**For the sidecar:** the config can change without rebuilding the wrapper, which
is the whole point of a declarative config. A trailer forces a re-cook step on
every config edit.

**License:** none for the flat format; `encoding/gob` is stdlib.

### 5. Go daemon plus a Go client

The sccache architecture: a long-lived server holds the cache state, and each
invocation execs a small client that asks it over a unix socket.

- Costs are in `results/daemon.md`: the whole-process client cost, the same
  binaries doing nothing, and the round trip alone both cold and warm.
- The config load moves off the per-exec path entirely, because the daemon holds
  the parsed form. That is the architectural win.
- The per-exec cost becomes the client's startup plus one round trip, and the
  client still pays the Go runtime bring-up.

**The honest caveat:** a daemon also brings daemon problems. Lifecycle
(who starts it, when does it die), version skew between client and daemon,
per-user versus per-project instances, a stale daemon serving a config that has
since changed, and a failure mode where the daemon is wedged and every compile
hangs rather than falling back. None of that is visible in a microbenchmark.

### 6. Go daemon plus a C client

Same architecture, with the client rewritten as a tiny C program: connect,
write, read, exit.

- `results/daemon.md` carries the C client, the static C client and the Go
  client on the same protocol against the same server, so the difference between
  them is the runtime startup and nothing else.
- The protocol becomes a real interface that two languages must agree on, which
  is a maintenance cost the single-language option does not have. binpazer (see
  option 3) is one way to keep that agreement mechanical, since it has both a Go
  and a C implementation of the same spec.

### 7. Pure C or C++, no daemon

- The C startup floor and the C++ startup floor, static and dynamic, are in
  `results/startup-floor.md` for four platforms.
- `<iostream>`'s static initializer is a real and measurable cost, so a C++
  implementation that wants the C floor has to avoid it.
- Static versus dynamic linking is a measured difference on Linux and on
  Windows. macOS carries no static row at all: Apple does not support statically
  linking libSystem, and clang there links libc++ dynamically. An option that
  depends on static linking for its startup number does not have that number on
  macOS.
- Everything in the wrapper then has to be written in C: an XML parser, a
  template evaluator, a hasher, a cache protocol, and a portable file layer.
  That is the cost this option trades startup time for.

**cosmocc / Cosmopolitan (ISC licensed)** builds a single C binary that runs on
Linux, macOS and Windows. It was not measured here. The published mechanism is
worth knowing before anyone prices it: an APE's header is a shell script, so a
bare `execve` of one fails unless the host has a `binfmt_misc` entry registered
(which needs root), and the loader stages a copy of itself before running.
For a binary exec'd thousands of times per build, "a shell interprets the header
on every exec" is exactly the wrong property, and it is the first thing anyone
evaluating cosmocc for this role should measure rather than assume.

### 8. Rust

- The Rust startup floor is in `results/startup-floor.md` on all four platforms.
- Rust gives the C-adjacent startup profile without hand-writing the parser and
  the hasher, since crates.io has both.
- The cost is the same as option 7's: a rewrite, and a second language in the
  project if the rest of the tooling is Go.

### 9. Zig

Not measured. It was not installed on the runners and adding it would have cost
a job slot that a measured option needed.

What is knowable without measuring: Zig produces a native binary with no managed
runtime and no garbage collector, so its startup profile should sit with C's
rather than Go's, and `zig cc` is a drop-in C compiler that cross-compiles,
which would cover the same ground as option 7 with less toolchain pain. Neither
of those is a measurement, and neither should be treated as one. Zig also has no
stable 1.0, which is a real risk for a tool meant to sit in every build.

## Third-party things used in these measurements

| Thing | Used for | License |
|---|---|---|
| [hyperfine](https://github.com/sharkdp/hyperfine) 1.19.0 | every whole-process timing | MIT OR Apache-2.0 |
| [binpazer](https://github.com/wow-look-at-my/bin-file-fmt) | the container-format trailer option, Go and C | MIT |
| [api-dsl](https://github.com/wow-look-at-my/api-dsl) | the XML DOM, placeholder compiler and renderer under test | MIT |
| [sprig](https://github.com/Masterminds/sprig) v3 | api-dsl's template function set, measured as part of it | MIT |
| [lukechampine.com/blake3](https://github.com/lukechampine/blake3) | the BLAKE3 row in the hashing table | MIT |
| xxHash64 | the xxhash row; written out inline, not imported | algorithm public domain; reference impl BSD-2-Clause |

## What the numbers suggest

This is a reading of the measurements, not a decision. Whoever decides has
constraints these probes cannot see.

**The numbers suggest the config load is the problem, not the language.** The
naive XML load is ~2,269 µs and the Go startup floor is ~1,041 µs. Every
option that attacks the language attacks the smaller term. Option 1 is the only
one the measurements rule out outright, and what rules it out is the config
load rather than Go.

**They suggest the cheap fixes come first, because they are nearly free and
they change the shape of the decision.** A cooked form plus a shared template
root is ~279 µs, an 8x reduction, and neither part is architectural: no daemon,
no second language, no new process model. After those two changes a plain Go
binary costs roughly 1,337 µs per exec. Before them it costs roughly 3,300 µs.
Any comparison against C or a daemon made on the pre-fix number is comparing
against a straw man.

**They suggest the trailer and the sidecar are close enough to choose on
correctness rather than speed.** Reading a cooked trailer is ~15-17 µs and a
sidecar read would be the same order. The real difference is that a trailer
cannot get out of step with its binary and a sidecar can, against which a
sidecar lets the config change without re-cooking the wrapper. That is a
correctness and workflow argument, and the timings do not settle it. If a
container format is wanted, binpazer costs ~2 µs and 1.1% over a hand-rolled
footer and brings a block index, a C reader, and skippable unknown blocks.

**They suggest a daemon is worth its complexity only with a native client.** A
Go client plus a Go daemon is ~1,290 µs against a cooked Go binary's ~1,337 µs:
within noise, for a whole new process model, a lifecycle, and a version-skew
problem. A static C client is ~608 µs, which is a genuine ~730 µs per exec
against the cooked Go binary — about 7 seconds on a 10,000-file build. That is
the only daemon configuration the numbers support, and it costs a second
language and a protocol two implementations must agree on.

**They suggest that if the wrapper is written natively, the link mode is not a
detail.** Static linking is worth 30-40% in C, dynamic `<iostream>` costs as
much as Go, and a dynamically linked C daemon client spends 190 µs on `ld.so`
to save a 66 µs round trip. A native implementation that does not control its
link mode is not obviously faster than the Go one it replaced.

**They suggest one thing be measured on the host rather than assumed.**
sha256 is 132 µs per 200 KiB with hardware acceleration and roughly 4.3x slower
without it. That is the difference between hashing being 10% of an exec and
being half of one, and it is a property of the machine the wrapper is installed
on, not of the wrapper.

**What is NOT measured here, and would change the reading if it went badly:**
cold-start costs (every number here is page-cache warm), a config an order of
magnitude larger than the 30 KB sample, real cache lookups inside the daemon,
Windows and macOS for every family rather than only the startup floor, and Zig
at all.
