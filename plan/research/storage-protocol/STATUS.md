# storage-protocol — status

Written on resumption, after reading every file in this directory and
`.github/workflows/storage-protocol.yml`. It records what the previous session
finished before it was killed, and what this session had left to do. It is kept
after completion so the gap and its fix stay visible.

## Finished before the interruption

**All six prose deliverables are written and self-consistent.**

| file | lines | state |
|---|---|---|
| `README.md` | 151 | index, 25-point summary, trade-off table, open questions |
| `local-layout.md` | 498 | ccache, sccache, Bazel/bazel-remote, go-s3-server; container-vs-CAS; lookup/restore/hash measurements; atomicity and platform notes |
| `container-format.md` | 455 | tar, ccache `.R`, hand-rolled ACE1 framing, zip, binpazer; framing overhead, single-member read, pack/unpack, the streaming gap |
| `compression.md` | 339 | zstd/lz4/s2/none on real `-g -O2` objects; ratio, encode, decode, wall clock, the codec-instance trap |
| `remote-protocols.md` | 429 | go-s3-server native, bazel-remote HTTP, REAPI v2, ccache HTTP/Redis/helper, sccache, Gradle, Nx/Turborepo/GHA; one-mux question; AC/CAS |
| `consistency-and-safety.md` | 330 | read-after-write, concurrent writers, corruption, poisoning, eviction, index staleness |

**The probe suite is complete and runs clean.** `probes/` holds
`readcost_test.go`, `compress_test.go`, `container_test.go`,
`restore_test.go` (Linux-only syscalls), `restore_portable_test.go` (every
platform), `restore_darwin_test.go` (APFS `clonefile(2)`),
`binpazer/binpazer_test.go` (separate module, `replace` onto the
`refs/bin-file-fmt` submodule), `cmd/benchreport`, `run.sh`, `gen-testdata.sh`
and the C/C++ corpus sources. No probe skips silently: a missing corpus file is
fatal and an unsupported filesystem capability is a stated verdict
(`TestReflinkSupport`, `TestClonefileSupport`).

**The workflow is complete.** Three-OS matrix, `submodules: true`, public
actions only, no `continue-on-error`, no `|| true`, `if-no-files-found: error`,
the required `concurrency` group, and a push trigger scoped to
`storage-protocol*.yml` plus this directory's `TRIGGER`.

**Two CI artifact sets are committed**, both from run
[34728376981](https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981)
(commit `2b3e8057`, 2026-09-13T00:35Z):
`probes/ci-results-ubuntu-latest/` and `probes/ci-results-windows-latest/`.

**Sandbox numbers are quarantined.** `probes/results/README.txt` labels them
noisy and superseded, exactly as the rules require.

## Not finished — the gap this session closed

1. **No macOS results exist anywhere.** `README.md` cites
   `probes/ci-results-macos-latest/` in its machine table and in its open
   questions. That directory was never created: a dangling reference.
2. **The committed artifacts predate the portable restore probe.**
   `restore_portable_test.go` was written at 00:44:59Z; run 34728376981 started
   at 00:35:58Z. `ci-results-windows-latest/PROVENANCE.txt` says so in as many
   words. There are therefore **no Windows and no macOS restore numbers** in the
   committed evidence — only Linux ones, from `restore_test.go`.
3. **The `clonefile(2)` probe has never executed.** `restore_darwin_test.go`
   was written at 00:50:52Z. The last run this worker started came from the
   `TRIGGER` timestamp 00:45:10Z. The single open question the README calls out
   by name is unmeasured.
4. **Two later successful runs were never harvested.** Runs
   [34728776086](https://github.com/wow-look-at-my/api-cache/actions/runs/34728776086)
   and
   [34728859239](https://github.com/wow-look-at-my/api-cache/actions/runs/34728859239)
   both went green on all three runners, but the session died before their
   artifacts were pulled into the tree. Both still predate
   `restore_darwin_test.go`, so harvesting them would leave gap 3 open; a fresh
   run supersedes all three.
5. **Every `[ci]` figure quoted in the prose is a run-34728376981 figure.** Once
   a fresh run lands, the provenance URLs and any figure it moves have to be
   re-checked rather than assumed stable.

## Plan for this session

1. Write this file and commit. *(done first, before any other work.)*
2. Compile-check every probe for all three `GOOS` values locally — build proof
   only, never a quoted number.
3. Stamp `TRIGGER` and push; one run, all three runners, including the darwin
   clonefile probe for the first time.
4. Harvest all three artifacts into `probes/ci-results-<runner>/`, each with a
   `PROVENANCE.txt` naming the run URL, the commit and the machine.
5. Fold the macOS and portable-restore numbers into `local-layout.md`,
   `container-format.md`, `compression.md` and `README.md`; refresh the
   provenance URLs; settle or restate the `clonefile` open question.

## Predecessor trail

`PREDECESSOR-TRAIL.md` was supplied after this file was first written and has
been read. It confirms the reading above rather than changing it: the
predecessor's last recorded intent is *"Run #18 predates my final probes. I'll
wait for it to finish, then trigger one fresh run"*, and its final tool calls
are a poll loop waiting on that run. It was killed inside that wait, before the
fresh run and before any macOS harvest. Its consultation list (ccache
`result.cpp`/`manifest.cpp`/`cacheentry.cpp`/`localstorage.cpp`, sccache
`cache.rs`, bazel-remote, `remote_execution.proto`, the Gradle manual, the GHA
cache v2 Twirp API, go-s3-server's handlers and `cacheclient`) is complete and
is not repeated here. One fetch it never completed is noted below.

## What this session completed

All five gaps above are closed. Two full CI runs were started, both green on
all three runners; neither used `continue-on-error`, a conditional skip or a
fallback.

**Run [34729381343](https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343)**
(commit `241bdc50`) is the quoted set. Its three artifacts are committed at
`probes/ci-results-{ubuntu,windows,macos}-latest/`, each with a fresh
`PROVENANCE.txt`. It is the first run to carry macOS at all and the first to
carry Windows or macOS restore numbers.

**Run [34729790831](https://github.com/wow-look-at-my/api-cache/actions/runs/34729790831)**
(commit `67247320`) is committed at `probes/ci-results-repeat-34729790831/`. It
exists because of a probe bug found while reading run 1's macOS output, and
because a second run of identical code measures how much a CI figure moves.

**The probe bug is worth recording.** `restore_darwin_test.go` called
`syscall.Syscall(462, ...)` — the BSD table number for `clonefile` — and got
`EINVAL` on the runner. Read at face value that says *APFS refuses to clone*,
which would have answered this document's one named open question backwards.
It was macOS's deprecated generic `syscall(2)` shim refusing the number. The
probe now calls the libSystem symbol through `golang.org/x/sys/unix.Clonefile`
and reports **both** results, and the real verdict is **SUPPORTED**:
`clonefile(2)` restores a 512 KiB object in 167 µs, constant in file size,
34× faster than copying at 5 MiB, and — unlike a hard link — safe to write to.

Findings updated with the new data: `local-layout.md` (lookup, restore,
hashing, atomicity, plus two new sections — the `clonefile` verdict and the
run-to-run variance), `container-format.md` (framing, single-member read,
pack/unpack, codec layer, criteria table), `compression.md` (corpus, ratios,
throughput, wall clock, the hot-local split), `consistency-and-safety.md`
(fsync cost, the NTFS rename/unlink verdicts, checksum cost),
`remote-protocols.md` (Turborepo rewritten from its OpenAPI document, which the
predecessor's last fetch had failed on a redirect), and `README.md` (machine
table, a 26-point summary, the trade-off table, the open questions).

## Still open

Named in `README.md` under "Open questions". The one worth flagging to a human:
**no runner here has btrfs, XFS-with-reflink or ReFS**, so the clone restore is
measured as supported on APFS and unsupported on ext4 and unmeasured on the
three filesystems where it might also work. Since the clone turned out to be
the best restore measured and it forces the compression answer with it, that is
the highest-value follow-up, and it needs a machine this worker cannot reach.
