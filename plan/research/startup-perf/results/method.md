# How every number here was produced

## Where the numbers come from

**Every reported figure comes from a GitHub Actions hosted runner.** The
workflow is `.github/workflows/startup-perf.yml`, one job per measurement
family, and each job uploads its markdown and JSON as an artifact. Each results
file names the runner label, the commit and the run URL it came from.

Nothing reported here was timed on a development machine. The sandbox this
research was written in runs several agents at once, and a millisecond
measurement taken beside someone else's compile job is noise with a decimal
point on it. The sandbox was used to write the probes and to prove each one
starts and exits zero (`results/smoke.log`), and for nothing else. Files named
`raw-*.txt` are the development record and are marked superseded at the top.

## The two kinds of measurement, and why they are not the same tool

**Whole-process timings use [hyperfine](https://github.com/sharkdp/hyperfine)
1.19.0** (MIT OR Apache-2.0), with:

    hyperfine --shell=none --warmup 20 --runs 300

`--shell=none` matters: without it hyperfine spawns a shell per run and the
shell's own startup lands in every row, which for a measurement whose whole
subject is process startup would swamp the thing being measured. `--warmup 20`
gets the page cache and the branch predictors warm first. Each job exports both
`--export-markdown` (the committed table) and `--export-json` (every individual
run time, so a reader can re-derive a percentile hyperfine does not print).

hyperfine reports **mean ± σ, min and max**. It prints no median and no p90, so
the tables carry what it prints. The JSON beside each table holds the raw times.

**In-process timings are measured by the probe itself.** The stages inside a
config load, and the throughput of a hash, are tens to hundreds of microseconds.
Timing those from outside would measure only their sum against a millisecond of
process startup and would tell you nothing about which stage to attack. Those
probes time each stage directly and report a median over many iterations. The
process floor those microseconds sit on top of comes from the hyperfine jobs, so
the two can be added.

## What is comparable with what

- **Rows within one table are comparable.** Same runner, same run, interleaved.
- **Rows across jobs are not.** Every job gets its own runner: different
  hardware, different neighbours, different noise.
- **Rows across platforms are especially not.** A macOS ARM64 runner and an
  Ubuntu x64 runner are different computers. What travels across platforms is
  the RATIO within each platform, not the absolute milliseconds.

## Caveats that change how a number should be read

- **A hosted runner is a shared virtual machine.** Absolute figures are higher
  and noisier than the same code on a developer's idle laptop. The ratios are
  the durable part.
- **`--warmup 20` means every file is in the page cache.** No number here is a
  cold-start number. A first-ever exec of a 24 MB binary on a cold cache is a
  different and worse measurement that nothing here covers.
- **SHA-NI changes the sha256 row by roughly an order of magnitude.** The
  hashing job records the CPU's flags for that reason, and runs on both x64 and
  ARM64 because the answer differs.
- **These probes are hello-world sized.** They measure the floor a real wrapper
  starts from, not a real wrapper. The `config-load` family is the closest thing
  here to real work.

## Nothing fails quietly

Every CI script checks its prerequisites and aborts with the real error rather
than dropping a row. A build failure, a missing compiler, a hyperfine that is
not on PATH, or a hyperfine that produced no table each fail the job red. There
is no `continue-on-error`, no `|| true` on a measurement, and no branch that
writes a partial table as if it were complete. A green job with a short table
is worse than a red one, because the short table gets copied into a results
file and read as though it were the whole answer.

A handful of `|| true` and `2>/dev/null` remain in the CI scripts. Every one is
on a DESCRIPTIVE HEADER FIELD or a cleanup trap, never on a measurement: the
CPU model string (ARM64 `/proc/cpuinfo` has no `model name` line at all), the
core count (`nproc` on Linux versus `sysctl` on macOS), killing the test daemon
on exit, and one `grep -c` whose zero-match case IS the failure being checked
and must reach the comparison as a number rather than abort before it. A
missing CPU model reports what the kernel does give and the benchmark proceeds;
a missing benchmark fails the job.

The single documented exception is macOS's static rows, and it is a platform
fact rather than a failure: Apple does not support statically linking libSystem,
and clang on macOS links libc++ dynamically. Those targets are not attempted
there, they are named as unsupported, and the report says so in place of the
numbers.
