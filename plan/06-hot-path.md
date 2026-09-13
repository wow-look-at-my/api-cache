# 06 — The hot path

The per-invocation budget, the language decision, and the measured basis for both. Every number is from GitHub Actions runners via hyperfine or the probes' own timers (`plan/research/startup-perf/`, `plan/research/storage-protocol/`), and each has a run URL in the research file that reports it.

## The floors

| Platform | Cheapest possible exec | Go hello | Go relative |
|---|---|---|---|
| Linux x64 | 451 µs (static C) | 1,041 µs | 2.31x |
| Linux ARM64 | (C static) | | 2.6x |
| macOS ARM64 | ~2.2 ms (dynamic; static linking is not available on macOS) | | ~1.2x |
| Windows x64 | ~5.2 ms (`CreateProcess`) | | 1.39x |

The 590 µs Go tax on Linux has a specific shape: 206 syscalls before `main` against a static C hello's 17, of which 114 are `rt_sigaction` and 4 are `clone`. No amount of careful Go removes it; it is the runtime being present. On the other two platforms the process model dominates and the language matters far less.

## What dominated, and what fixes it

Loading a 30 KB api-dsl config naively costs ~2,269 µs, more than twice the Go process it runs in: ~900 µs of XML parse and compile, ~800 µs of `text/template.Parse`, and almost all of the latter is `Funcs()` copying sprig's 214-entry map into every template. The fixes are cheap and not architectural:

| Step | Cost | After |
|---|---|---|
| naive load | 2,269 µs | |
| cooked form: pre-compiled template sources, no XML at run time | decode 1.7 µs | template parse remains |
| one shared root template, the func map copied once | 76 templates: 3,417 µs → 276 µs | 12x |
| cooked + shared root | 279 µs | 8x |
| literal strings never enter the renderer | 0 for most fields | |
| prepared-template cache by source | 70 µs → 3 µs per render | 23x |
| pure, smaller func map | 5x on its own | composes |

After those, a plain Go wrapper costs roughly 1,337 µs per exec on Linux against ~3,300 µs before. Every comparison against C or a daemon made on the pre-fix number was a straw man.

## The budget

Per invocation, Linux x64, warm page cache, targets the plan holds itself to:

| Stage | Budget | Basis |
|---|---|---|
| process start | 1,041 µs | Go floor, not recoverable |
| read cooked config | 20 µs | binpazer trailer read measured at 17 µs |
| resolve tool, expand, classify | 30 µs | string work over ~60 args |
| tool identity | 5 µs memoised | `path:size:mtime` memo; a `--version` run only on memo miss |
| direct-mode manifest validation | 40 µs + 1 stat per include | stat 1.3 µs on ext4; content hash only on stat mismatch |
| direct hit: source hash | 130 µs per 200 KiB | BLAKE3, hardware-independent |
| entry open, index, directory | 190 µs | binpazer measured; 15% of the restore |
| restore 512 KiB | 1,266 µs ext4 copy, 167 µs APFS clone | the dominant term on a hit |
| CRC-32C 512 KiB | 23 µs x86, 67 µs arm64 | |
| replay streams, exit | 20 µs | |
| **direct hit total, ext4** | **~2.8 ms** | vs ccache's hit on the same machine: to be measured in phase 1's benchmark |
| preprocessor-mode hit | + the preprocessor run | dominated by the compiler, not by us |

The success criterion in `00-goals.md` is measured against ccache on the same runner with the same file, by the benchmark workflow in `10-testing-and-ci.md`. If api-cache's direct hit is slower than ccache's by more than the Go floor difference (~590 µs), something above is over budget and the phase does not close.

## The language decision

**Go for the engine, the wrapper, the server and the cook. No second language in the first release.** The numbers say the config load was the problem, not the language, and the cheap fixes remove it. Rewriting in C, Rust or Zig attacks the smaller term, costs a rewrite of everything api-dsl gives for free, and on the two platforms with taller floors buys ~1.2x to 1.4x.

**The daemon option is closed for the first release.** A Go client plus Go daemon is 1,290 µs, within noise of the cooked Go binary. A static C client is 608 µs, a genuine ~730 µs per exec on Linux, about 7 s on a 10,000-file build, for a second language, a two-implementation protocol, a lifecycle, version skew, and a wedge mode. `12-decisions.md` decision 5 records the conditions under which it reopens: a Linux-heavy deployment whose measured hit path is dominated by the Go floor after everything else is at budget.

**What Go must not do on the hot path:**

- Import net/http, encoding/xml, or any package whose `init` is heavy. Measured: net/http + encoding/xml + text/template cost 2.2 ms on Windows and 2.7 ms on macOS per exec (0.22 ms on Linux). The cook owns XML and template parsing; the wrapper owns neither. text/template's `Execute` is needed for the few templates a rule renders at run time; its parser is not, if the cooked form can carry parse trees (measured as workable via gob and `AddParseTree`, but 14x the bytes for a 6 µs saving; decision 7 weighs a serialised parse tree against re-parsing under the shared root, which is 3 µs per template with the cache).
- Start goroutines it does not need. The runtime's own four `clone`s are unavoidable; the wrapper adds none on a hit.
- Allocate per-block codec instances (8.4 MB each for lz4). Codecs are pooled or one-shot.
- Use `io.ReadAll` on an entry. Every read is sized from the directory.
- Hash with SHA-256 anywhere but the GOCACHEPROG output id.

**Static versus dynamic linking** is a measured 30 to 40% in C on Linux and 13% on Windows, and the Go wrapper is static by default with `CGO_ENABLED=0`. `clonefile` on macOS needs `golang.org/x/sys/unix`, not cgo.

## Per-platform notes

- **Windows.** `os.Stat` is 22 µs and an open 24 µs on NTFS: the store's one-stat miss, one-open hit, and metadata-inside-the-container rules exist for this platform. The 5.2 ms process floor means a 10,000-file build pays ~52 s of process creation before any wrapper runs; nothing in the wrapper can change that, and the plan says so in the docs rather than promising Linux numbers.
- **macOS.** Cannot statically link. Open is 9.1 µs against Linux's 5.4 µs, so the multi-blob layout is 2x worse there; the container wins. `clonefile` makes the restore 167 µs and constant in size, and forces the entry uncompressed.
- **Machines without `sha_ni`.** Irrelevant once the key hash is BLAKE3; the only SHA-256 left is the Go output id.

## Instrumentation

Every stage above emits its elapsed time into the per-invocation log line and the stats histogram. `api-cache stats --timing` prints the per-stage p50 and p90 for the current cache dir, so an operator can see which stage is over budget on their machine without a profiler. The benchmark workflow asserts the budget on every CI run of the hot-path package.
