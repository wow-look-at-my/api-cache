# Put hyperfine (MIT OR Apache-2.0) on PATH for a Windows runner, from the
# release zip rather than choco or cargo, so every platform runs one version.
$ErrorActionPreference = "Stop"
$ver  = if ($env:HYPERFINE_VERSION) { $env:HYPERFINE_VERSION } else { "1.19.0" }
$arch = if ($env:RUNNER_ARCH -eq "ARM64") { "aarch64" } else { "x86_64" }
$name = "hyperfine-v$ver-$arch-pc-windows-msvc"
$dest = Join-Path $env:USERPROFILE ".hyperfine\bin"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$tmp  = Join-Path $env:TEMP "hf.zip"
Invoke-WebRequest -Uri "https://github.com/sharkdp/hyperfine/releases/download/v$ver/$name.zip" -OutFile $tmp
Expand-Archive -Path $tmp -DestinationPath $env:TEMP -Force
Copy-Item (Join-Path $env:TEMP "$name\hyperfine.exe") (Join-Path $dest "hyperfine.exe") -Force
Add-Content -Path $env:GITHUB_PATH -Value $dest
& (Join-Path $dest "hyperfine.exe") --version
