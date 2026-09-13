# Build and time every startup probe on a Windows runner.
# MSVC /MT is the static CRT and /MD is the shared CRT DLL, which is the
# Windows spelling of the static-versus-dynamic question. Every build failure
# becomes a table row rather than aborting the job.
$ErrorActionPreference = "Continue"
# Put MSVC on PATH without a third-party action. vswhere ships in the Visual
# Studio installer directory on every GitHub windows runner image, and
# VsDevCmd.bat is the supported way to import the toolchain environment.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
	$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
	if ($vsPath) {
		$devCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
		# Run VsDevCmd in a cmd shell, dump the resulting environment, and
		# import it into this PowerShell session.
		cmd /c "`"$devCmd`" -arch=$(if ($env:RUNNER_ARCH -eq 'ARM64') {'arm64'} else {'amd64'}) -no_logo && set" | ForEach-Object {
			if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue }
		}
	}
}

$D   = $PSScriptRoot
$OUT = Join-Path $D "out"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null
$N = if ($env:BENCH_N) { $env:BENCH_N } else { "300" }

Write-Output "## Windows $env:RUNNER_ARCH"
Write-Output ""
Write-Output "- runner: ``$env:RUNNER_OS $env:RUNNER_ARCH``"
Write-Output "- cpu cores: $env:NUMBER_OF_PROCESSORS"
Write-Output "- cl: $((cl.exe 2>&1 | Select-Object -First 1))"
Write-Output "- go: $(go version)"
Write-Output "- rustc: $(rustc --version)"
Write-Output ""

Push-Location $D
go build -o "$OUT\bench.exe" .\bench.go
Pop-Location
$BENCH = "$OUT\bench.exe"

# --- MSVC: /MT static CRT, /MD shared CRT
Push-Location $OUT
cl.exe /nologo /O2 /MT  /Fe:c-static.exe   "$D\src\hello.c"   2>&1 | Out-Null
cl.exe /nologo /O2 /MD  /Fe:c-dyn.exe      "$D\src\hello.c"   2>&1 | Out-Null
cl.exe /nologo /O2 /EHsc /MT /Fe:cpp-static.exe "$D\src\hello.cpp" 2>&1 | Out-Null
cl.exe /nologo /O2 /EHsc /MD /Fe:cpp-dyn.exe    "$D\src\hello.cpp" 2>&1 | Out-Null
Pop-Location

Push-Location "$D\src\gohello"
$env:CGO_ENABLED="0"; go build -o "$OUT\go-hello-nocgo.exe" .
$env:CGO_ENABLED="1"; go build -o "$OUT\go-hello-cgo.exe"   .
Pop-Location
Push-Location "$D\src\goimports"
$env:CGO_ENABLED="0"; go build -o "$OUT\go-imports.exe" .
Pop-Location

rustc -O -o "$OUT\rust-hello.exe" "$D\src\hello.rs" 2>&1 | Out-Null

function Row($label, $bin) {
	if (Test-Path $bin) { & $BENCH -n $N -label $label -- $bin }
	else { Write-Output "| $label | build failed | | | | |" }
}

Write-Output "| binary | min us | p50 us | p90 us | mean us | size bytes |"
Write-Output "|---|---|---|---|---|---|"
Row "C hello, MSVC /MD (shared CRT)"   "$OUT\c-dyn.exe"
Row "C hello, MSVC /MT (static CRT)"   "$OUT\c-static.exe"
Row "C++ iostream, MSVC /MD (shared CRT)" "$OUT\cpp-dyn.exe"
Row "C++ iostream, MSVC /MT (static CRT)" "$OUT\cpp-static.exe"
Row "Go hello, CGO_ENABLED=0"          "$OUT\go-hello-nocgo.exe"
Row "Go hello, CGO_ENABLED=1"          "$OUT\go-hello-cgo.exe"
Row "Go +net/http+encoding/xml+text/template" "$OUT\go-imports.exe"
Row "Rust hello"                       "$OUT\rust-hello.exe"
Write-Output ""
