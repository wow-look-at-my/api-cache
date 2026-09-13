# Measurement family 1 on a Windows runner.
#
# MSVC /MT is the static CRT and /MD is the shared CRT DLL, which is the
# Windows spelling of the static-versus-dynamic question. Every build failure
# becomes a note rather than aborting the job.
# Stop, not Continue. A build that fails, a missing cl.exe, or a hyperfine that
# is not on PATH must fail this job red. A green job with a short table gets
# copied into a results file and read as if it were complete.
$ErrorActionPreference = "Stop"
$D   = $PSScriptRoot
$OUT = if ($args.Count -ge 1) { $args[0] } else { Join-Path $D "out" }
New-Item -ItemType Directory -Force -Path $OUT | Out-Null
$RUNS   = if ($env:BENCH_RUNS)   { $env:BENCH_RUNS }   else { "300" }
$WARMUP = if ($env:BENCH_WARMUP) { $env:BENCH_WARMUP } else { "20" }

# Put MSVC on PATH without a third-party action. vswhere ships in the Visual
# Studio installer directory on every GitHub windows runner image, and
# VsDevCmd.bat is the supported way to import the toolchain environment.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found at $vswhere; MSVC cannot be located" }
if ($true) {
	$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
	if (-not $vsPath) { throw "vswhere found no Visual Studio install with the C++ toolset" }
	if ($true) {
		$devCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
		$arch = if ($env:RUNNER_ARCH -eq 'ARM64') { 'arm64' } else { 'amd64' }
		cmd /c "`"$devCmd`" -arch=$arch -no_logo && set" | ForEach-Object {
			if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue }
		}
	}
}

$meta = @()
$meta += "# startup floor: Windows $env:RUNNER_ARCH"
$meta += ""
$meta += "> Measured on a GitHub Actions hosted runner. Not a development machine."
$meta += ""
$meta += "- runner label: ``$env:RUNNER_LABEL``"
$meta += "- commit: ``$env:GITHUB_SHA``"
$meta += "- run: $env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
$meta += "- cpu cores: $env:NUMBER_OF_PROCESSORS"
$meta += "- cl: $((cl.exe /help 2>&1 | Select-String -Pattern 'Compiler Version' | Select-Object -First 1))"
$meta += "- go: $(go version)"
$meta += "- rustc: $(rustc --version)"
$meta += "- hyperfine: $(hyperfine --version)"
$meta += "- method: ``hyperfine --shell=none --warmup $WARMUP --runs $RUNS``"
$meta += ""
$meta | Set-Content -Path (Join-Path $OUT "meta.md")

Push-Location $OUT
function Cl([string[]]$clArgs, [string]$what) {
	$log = & cl.exe @clArgs 2>&1
	$log | Out-File -Append (Join-Path $OUT "build.log")
	if ($LASTEXITCODE -ne 0) { $log | Write-Output; throw "cl.exe failed building $what (exit $LASTEXITCODE)" }
}
Cl @("/nologo","/O2","/MT","/Fe:c-static.exe","$D\src\hello.c")            "C static CRT"
Cl @("/nologo","/O2","/MD","/Fe:c-dyn.exe","$D\src\hello.c")               "C shared CRT"
Cl @("/nologo","/O2","/EHsc","/MT","/Fe:cpp-static.exe","$D\src\hello.cpp") "C++ static CRT"
Cl @("/nologo","/O2","/EHsc","/MD","/Fe:cpp-dyn.exe","$D\src\hello.cpp")    "C++ shared CRT"
Pop-Location

Push-Location "$D\src\gohello"
$env:CGO_ENABLED="0"; go build -o "$OUT\go-hello-nocgo.exe" .
$env:CGO_ENABLED="1"; go build -o "$OUT\go-hello-cgo.exe"   .
$env:CGO_ENABLED="0"; go build -ldflags="-s -w" -o "$OUT\go-hello-sw.exe" .
Pop-Location
Push-Location "$D\src\goimports"
$env:CGO_ENABLED="0"; go build -o "$OUT\go-imports.exe" .
Pop-Location

rustc -O -o "$OUT\rust-hello.exe" "$D\src\hello.rs" 2>&1 | Out-File -Append (Join-Path $OUT "build.log")
if ($LASTEXITCODE -ne 0) { throw "rustc failed building hello.rs (exit $LASTEXITCODE)" }

$targets = @(
	@{ label = "C hello, MSVC /MD (shared CRT)";   bin = "c-dyn.exe" },
	@{ label = "C hello, MSVC /MT (static CRT)";   bin = "c-static.exe" },
	@{ label = "C++ iostream, MSVC /MD (shared CRT)"; bin = "cpp-dyn.exe" },
	@{ label = "C++ iostream, MSVC /MT (static CRT)"; bin = "cpp-static.exe" },
	@{ label = "Go hello, CGO_ENABLED=0";          bin = "go-hello-nocgo.exe" },
	@{ label = "Go hello, CGO_ENABLED=1";          bin = "go-hello-cgo.exe" },
	@{ label = "Go hello, -ldflags=-s -w";         bin = "go-hello-sw.exe" },
	@{ label = "Go + net/http + encoding/xml + text/template"; bin = "go-imports.exe" },
	@{ label = "Rust hello";                       bin = "rust-hello.exe" }
)

$hfArgs = @("--shell=none", "--warmup", $WARMUP, "--runs", $RUNS,
            "--export-markdown", (Join-Path $OUT "startup.md"),
            "--export-json",     (Join-Path $OUT "startup.json"))
foreach ($t in $targets) {
	$path = Join-Path $OUT $t.bin
	# Every target must exist. A missing one is a build regression, not a row
	# to quietly drop out of the table.
	if (-not (Test-Path $path)) { throw "target '$($t.label)' was not built: $path is missing" }
	# FORWARD SLASHES, deliberately. With --shell=none hyperfine splits each
	# command with shell-words rules, in which a backslash is an escape
	# character, so `D:\a\repo\out\c-dyn.exe` arrives as
	# `D:arepooutc-dyn.exe` and every benchmark dies with "program not found".
	# Windows accepts forward slashes in a path, so this costs nothing.
	$hfArgs += @("-n", $t.label, ($path -replace '\\', '/'))
}
hyperfine @hfArgs *>&1 | Tee-Object -FilePath (Join-Path $OUT "startup.console.txt")
if ($LASTEXITCODE -ne 0) { throw "hyperfine exited $LASTEXITCODE; see startup.console.txt" }

# A non-empty table, not merely a file. hyperfine creates the export file
# before it runs, so `Test-Path` alone passes even when every benchmark
# failed. That is exactly how this job went green with no numbers in it once.
$tbl = Join-Path $OUT "startup.md"
if (-not (Test-Path $tbl)) { throw "hyperfine wrote no markdown table at $tbl" }
if ((Get-Item $tbl).Length -eq 0) { throw "hyperfine wrote an EMPTY markdown table; see startup.console.txt" }
$rows = @(Get-Content $tbl | Where-Object { $_ -match '^\|' }) .Count
if ($rows -lt ($targets.Count + 2)) {
	throw "hyperfine table has $rows lines for $($targets.Count) targets; a benchmark failed. See startup.console.txt"
}

$extra = @("", "## binary sizes", "", "| binary | bytes |", "|---|---|")
foreach ($t in $targets) {
	$path = Join-Path $OUT $t.bin
	if (Test-Path $path) { $extra += "| $($t.bin) | $((Get-Item $path).Length) |" }
}
$extra | Set-Content -Path (Join-Path $OUT "extra.md")

Get-Content (Join-Path $OUT "meta.md"), (Join-Path $OUT "startup.md"), (Join-Path $OUT "extra.md") |
	Set-Content -Path (Join-Path $OUT "report.md")
Get-Content (Join-Path $OUT "report.md")
