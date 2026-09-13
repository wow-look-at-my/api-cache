# msvc-probes — status

Written after resuming a killed session. It records what the previous instance
finished, what the first CI run did, and what is left.

## Done before the resume

- `README.md` — a stub (one sentence). Still needs the index and the 20-line
  summary the brief asks for.
- `TRIGGER` — holds `2026-09-13T00:43:23Z`.
- `.github/workflows/msvc-probes.yml` — the workflow. Name `msvc-probes`, push
  trigger scoped to `.github/workflows/msvc-probes*.yml` and
  `plan/research/msvc-probes/TRIGGER`, plus `workflow_dispatch`; concurrency
  group `msvc-probes` with `cancel-in-progress`; `submodules: true`; no
  `continue-on-error` anywhere.
- `probes/common.ps1` — shared helpers: `Invoke-Probe` (Start-Process with two
  distinct redirect files, so stdout, stderr and the exit code are captured
  separately and verbatim), `Add-DirListing`, `Add-HexDump`, `Test-HasEscape`,
  `Write-Source`, `ConvertFrom-AnsiBytes`.
- `probes/run-all.ps1` — the driver. Hard-fails when `cl.exe` is absent, writes
  `environment.md`, runs all 11 families, and throws at the end if any family
  threw.
- `probes/p01..p11` — all 11 probe families written (identity, showIncludes,
  localization, output naming, debug info, PCH, response files, environment,
  diagnostics, clang-cl, determinism).
- `results/` — **EMPTY**. No probe output has been copied in yet.
- `corrections.md` — **NOT WRITTEN**.

## Run 1: FAILED

<https://github.com/wow-look-at-my/api-cache/actions/runs/34729088200>
(job 103648447858, `windows-latest`, image `win25-vs2026 / 20260907.229.1`)

Steps 1-4 succeeded. `cl.exe` and `clang-cl.exe` were both found. Step 5 ("run
the probes") failed, and **all 11 families failed with the identical error**:

```
p01-identity.ps1 FAILED: At ...\probes\common.ps1:184 char:49
+         Add-Content -Path $script:Log -Value @("$Caption: (empty)", ' …
+                                                 ~~~~~~~~~
Variable reference is not valid. ':' was not followed by a valid variable name
character. Consider using ${} to delimit the name.
```

One parse error, eleven casualties. PowerShell reads `"$Caption:"` inside a
double-quoted string as a scope- or drive-qualified variable reference
(`$scope:name`), and `(` is not a valid name character. The whole of
`common.ps1` therefore fails to PARSE, so every `. "$PSScriptRoot\common.ps1"`
threw before a single `cl.exe` invocation ran. Zero measurements were produced.

Artifact `msvc-probes-results` carries only `environment.md` (953 B) and
`FAILURES.txt` (7728 B).

## What the failed run did nevertheless establish (from the log)

The runner is usable and no prerequisite is missing:

```
ImageOS           = win25-vs2026
ImageVersion      = 20260907.229.1
OS caption        = Microsoft Windows Server 2025 Datacenter  (10.0.26100)
PowerShell        = 7.6.5
cl.exe            = C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe
VCToolsVersion    = 14.51.36231        (Visual Studio 18.0 Enterprise, VSCMD_VER 18.9.2)
WindowsSDKVersion = 10.0.26100.0\
VSLANG            = (unset)
CurrentCulture    = en-US ; ANSICodePage = 1252 ; OEMCodePage = 437
console output CP = 65001
clang-cl.exe      = C:\Program Files\LLVM\bin\clang-cl.exe
```

So probe 10 (clang-cl) has a compiler to run against, and probe 3's
localization work has an English-only en-US toolset to measure against.

## Fix being applied now

1. `common.ps1:184` — `"$Caption: (empty)"` becomes `"${Caption}: (empty)"`.
2. A sweep of every `.ps1` in `probes/` for the same `$var:` shape and for any
   other construct that only fails at parse time, because a CI round trip costs
   minutes and a second parse error would burn another one.
3. A local `pwsh -NoProfile -Command` parse check of every script before the
   push, if `pwsh` is present in this sandbox; otherwise a mechanical scan.

## Run 2: HUNG, cancelled by the coordinator

<https://github.com/wow-look-at-my/api-cache/actions/runs/34729507919> (job 103649573672)

The parse error was fixed and the probes ran for real. The job then hung in
"run the probes" from 01:02:47 until it was cancelled at ~01:40.

**Where.** The artifact stops inside family p01 at probe `compile-subdir-relpath`
(`cl /nologo /c sub\bar.c`). That probe's `.stdout.txt` holds `bar.c` and its
`.stderr.txt` is empty, but there is **no `.exit.txt`** -- and `.exit.txt` is
written on the line after the wait returns. So cl.exe compiled the file
successfully and the HARNESS never came back.

**Why.** cl.exe spawns `vctip.exe`, the MSVC telemetry uploader. It inherits
cl's stdout and stderr handles and outlives cl. PowerShell's
`Start-Process -Wait -RedirectStandardOutput <file>` waits for the redirection
pipe to reach EOF as well as for the process to exit, so a surviving vctip holds
that pipe open forever and the wait never returns on a compile that already
succeeded. The runner confirms the process at cancellation:

```
2026-09-13T01:40:14.0872352Z Terminate orphan process: pid (4204) (vctip)
```

**Fixes applied for run 3:**

1. `Invoke-Probe` no longer uses `Start-Process -Redirect*` at all. It writes a
   per-probe `.run.cmd` and runs `cmd.exe /c <that file>`, letting **cmd** do
   `> stdout 2> stderr < NUL`. The child then writes to FILE handles rather than
   pipes, so an orphaned vctip cannot hold the parent open, and `< NUL`
   guarantees no invocation can block reading console input.
2. Every probe has a **120 s timeout**: `Start-Process -PassThru` (no `-Wait`),
   then `WaitForExit(120000)`, then `Kill($true)` on the whole process tree.
   The exit status is recorded as `TIMEOUT` and the markdown says so in bold --
   a real finding, never a silent skip.
3. `ConvertTo-CmdArg` refuses (throws on) any argument holding `% ^ & < > |` or
   a quote, so a probe can never silently run a command line different from the
   one it records.
4. The driver prints `=== start <family>/<id>` and `=== end <family>/<id> exit=N`
   for every probe, plus `FAMILY START` / `FAMILY END ... (Ns)` markers, so a
   future hang is attributable straight from the step log.
5. `timeout-minutes: 15` on the job and `12` on the probe step.
6. Telemetry opt-out env (`VSCMD_SKIP_SENDTELEMETRY`, `VCTIP_TELEMETRY_OPTOUT`)
   so vctip preferably never starts.
7. p11's three 65 s sleeps became 3 s. `__TIME__` is `HH:MM:SS`, so seconds are
   enough to move it; the minute-long waits bought nothing.

The same cmd-file treatment was applied to the two probes that call
`Start-Process` directly: p03's sccache-detection re-implementation and p09's
deliberate real-pipe colour test (which keeps its `cl | findstr` pipe, because
that pipe IS the measurement, but no longer hands PowerShell one).

## Left to do

- [ ] re-run (run 3) and confirm all 11 families complete
- [ ] copy the artifact captures into `results/*.md`
- [ ] `README.md`: index + 20-line summary + the contradictions with `msvc.md`
- [ ] `corrections.md`
