# Measurement family 1 on a Windows runner.
#
# MSVC /MT is the static CRT and /MD is the shared CRT DLL, which is the
# Windows spelling of the static-versus-dynamic question. Every build failure
# becomes a note rather than aborting the job.
$ErrorActionPreference = "Continue"
$D   = $PSScriptRoot
$OUT = if ($args.Count -ge 1) { $args[0] } else { Join-Path $D "out" }
New-Item -ItemType Directory -Force -Path $OUT | Out-Null
$RUNS   = if ($env:BENCH_RUNS)   { $env:BENCH_RUNS }   else { "300" }
$WARMUP = if ($env:BENCH_WARMUP) { $env:BENCH_WARMUP } else { "20" }

# Put MSVC on PATH without a third-party action. vswhere ships in the Visual
# Studio installer directory on every GitHub windows runner image, and
# VsDevCmd.bat is the supported way to import the toolchain environment.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
	$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
	if ($vsPath) {
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
$meta += "- runner label: ``$env:RUNNER_LABEL``  (GitHub Actions hosted runner)"
$meta += "- run: $env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
$meta += "- cpu cores: $env:NUMBER_OF_PROCESSORS"
$meta += "- cl: $((cl.exe 2>&1 | Select-Object -First 1))"
$meta += "- go: $(go version)"
$meta += "- rustc: $(rustc --version)"
$meta += "- hyperfine: $(hyperfine --version)"
$meta += "- method: ``hyperfine --shell=none --warmup $WARMUP --runs $RUNS``"
$meta += ""
$meta | Set-Content -Path (Join-Path $OUT "meta.md")

Push-Location $OUT
cl.exe /nologo /O2 /MT   /Fe:c-static.exe   "$D\src\hello.c"   2>&1 | Out-File -Append (Join-Path $OUT "build.log")
cl.exe /nologo /O2 /MD   /Fe:c-dyn.exe      "$D\src\hello.c"   2>&1 | Out-File -Append (Join-Path $OUT "build.log")
cl.exe /nologo /O2 /EHsc /MT /Fe:cpp-static.exe "$D\src\hello.cpp" 2>&1 | Out-File -Append (Join-Path $OUT "build.log")
cl.exe /nologo /O2 /EHsc /MD /Fe:cpp-dyn.exe    "$D\src\hello.cpp" 2>&1 | Out-File -Append (Join-Path $OUT "build.log")
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
$missing = @()
foreach ($t in $targets) {
	$path = Join-Path $OUT $t.bin
	if (Test-Path $path) { $hfArgs += @("-n", $t.label, $path) }
	else { $missing += $t.label }
}
hyperfine @hfArgs *>&1 | Tee-Object -FilePath (Join-Path $OUT "startup.console.txt")

$extra = @("", "## binary sizes", "", "| binary | bytes |", "|---|---|")
foreach ($t in $targets) {
	$path = Join-Path $OUT $t.bin
	if (Test-Path $path) { $extra += "| $($t.bin) | $((Get-Item $path).Length) |" }
}
if ($missing.Count -gt 0) {
	$extra += ""
	$extra += "## targets that failed to build"
	$extra += ""
	foreach ($m in $missing) { $extra += "- $m" }
}
$extra | Set-Content -Path (Join-Path $OUT "extra.md")

Get-Content (Join-Path $OUT "meta.md"), (Join-Path $OUT "startup.md"), (Join-Path $OUT "extra.md") |
	Set-Content -Path (Join-Path $OUT "report.md")
Get-Content (Join-Path $OUT "report.md")
