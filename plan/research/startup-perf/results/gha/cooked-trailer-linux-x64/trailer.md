# cooked trailer: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- go: go version go1.24.13 linux/amd64
- cc: cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
- hyperfine: hyperfine 1.19.0

## (a) does a trailer slow execve? (hyperfine, --shell=none, warmup 20, runs 300)

The target exits without reading its trailer, so this row is purely
whether a bigger FILE costs more to start.

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `Go, 3 KiB trailer` | 1.1 ± 0.1 | 1.0 | 1.5 | 1.03 ± 0.10 |
| `Go, 1 MiB trailer` | 1.1 ± 0.1 | 1.0 | 1.3 | 1.03 ± 0.09 |
| `Go, 10 MiB trailer` | 1.1 ± 0.1 | 0.9 | 1.4 | 1.00 |

## (b) reading the trailer, in process, median of 400

| binary | os.Executable us/op | readTrailer us/op | payload |
|---|---|---|---|
| trailer-0 | 4.1 | 10.6 | 3072 bytes |
| trailer-1m | 9.0 | 126.0 | 1048576 bytes |
| trailer-10m | 10.1 | 1231.8 | 10485760 bytes |

# binpazer as a cooked-config trailer

- library: `github.com/wow-look-at-my/bin-file-fmt/go` (MIT)
- blocks: string table 24576 B, rules 2862 B
- container: 27728 B (1.1% overhead over the two payloads)
- iterations: 400, median reported

| operation | us | note |
|---|---|---|
| open reader (header + type table + footer) | 4.3 | NewReaderAt: what every read below starts with |
| open + FindFirst(rules) + ReadPayload | 4.8 | the hot path: only the block the invocation needs |
| open + both blocks | 6.8 | string table plus rules, for the cold path that needs both |

## appended to `/home/runner/work/api-cache/api-cache/out/trailer-0` (2548528 B host + 27728 B container)

| operation | us | note |
|---|---|---|
| os.Executable-style open + last 8 B + section reader + rules block | 17.0 | the whole per-exec cost of a binpazer-cooked binary |
| open + close only | 5.6 | the syscall floor under the row above |


## the same binpazer read from C (allocation-free reader, injected read/seek)

| operation | min us | p50 us | mean us | note |
|---|---|---|---|---|
| C: open + footer + index + rules block | 19.5 | 19.6 | 20.2 | payload 2862 B, allocation-free reader |
| C: open + close only | 3.0 | 3.0 | 3.1 | the syscall floor under the row above |
