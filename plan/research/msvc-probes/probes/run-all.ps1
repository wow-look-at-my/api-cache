# Driver for the msvc-probes families.
#
# Every family runs. A family that throws is recorded and the DRIVER FAILS at
# the end with a non-zero exit code, so a missing prerequisite turns the job red
# instead of quietly producing a short report. Nothing here suppresses a failure;
# the only reason the driver does not stop at the first one is that a single
# missing tool should not hide the nine families that would have run.

$ErrorActionPreference = 'Stop'

$results = if ($env:PROBE_RESULTS) { $env:PROBE_RESULTS } else { Join-Path $PSScriptRoot 'ci-results' }
New-Item -ItemType Directory -Force -Path $results | Out-Null
$env:PROBE_RESULTS = $results
if (-not $env:PROBE_SCRATCH) { $env:PROBE_SCRATCH = 'C:\p' }
New-Item -ItemType Directory -Force -Path $env:PROBE_SCRATCH | Out-Null

# --- hard prerequisite. Without cl.exe nothing in this worker means anything.
$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $cl) {
    throw 'cl.exe is not on PATH. The MSVC developer environment step did not run or did not export its environment.'
}

# --- the environment every result file is read against.
$envLines = @(
    '# Runner environment',
    '',
    '```',
    "ImageOS           = $($env:ImageOS)",
    "ImageVersion      = $($env:ImageVersion)",
    "RUNNER_OS         = $($env:RUNNER_OS)",
    "RUNNER_ARCH       = $($env:RUNNER_ARCH)",
    "OS caption        = $((Get-CimInstance Win32_OperatingSystem).Caption)",
    "OS version        = $((Get-CimInstance Win32_OperatingSystem).Version)",
    "PowerShell        = $($PSVersionTable.PSVersion)",
    "cl.exe            = $($cl.Source)",
    "VCToolsVersion    = $($env:VCToolsVersion)",
    "VCToolsInstallDir = $($env:VCToolsInstallDir)",
    "VSCMD_VER         = $($env:VSCMD_VER)",
    "VSCMD_ARG_TGT_ARCH= $($env:VSCMD_ARG_TGT_ARCH)",
    "WindowsSDKVersion = $($env:WindowsSDKVersion)",
    "UCRTVersion       = $($env:UCRTVersion)",
    "VSLANG            = $($env:VSLANG)",
    "CurrentCulture    = $([System.Globalization.CultureInfo]::CurrentCulture.Name)",
    "ANSICodePage      = $([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)",
    "OEMCodePage       = $([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)",
    "console output CP = $([Console]::OutputEncoding.CodePage)",
    "run URL           = $($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)",
    '```',
    ''
)
$clangcl = Get-Command clang-cl.exe -ErrorAction SilentlyContinue
$envLines += @('```', "clang-cl.exe      = $(if ($clangcl) { $clangcl.Source } else { '(NOT FOUND)' })", '```', '')
Set-Content -Path (Join-Path $results 'environment.md') -Value $envLines -Encoding utf8
$envLines | Write-Host

$families = @(
    'p01-identity.ps1',
    'p02-showincludes.ps1',
    'p03-localization.ps1',
    'p04-output-naming.ps1',
    'p05-debug-info.ps1',
    'p06-pch.ps1',
    'p07-response-files.ps1',
    'p08-environment.ps1',
    'p09-diagnostics.ps1',
    'p10-clang-cl.ps1',
    'p11-determinism.ps1'
)

$failures = @()
foreach ($f in $families) {
    $path = Join-Path $PSScriptRoot $f
    Write-Host ''
    Write-Host "================ FAMILY START $f ================"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Belt and braces against the run-3 contamination: no family may start
    # under a VS_UNICODE_OUTPUT left behind by the previous one.
    if (Test-Path -LiteralPath 'Env:\VS_UNICODE_OUTPUT') { Remove-Item -LiteralPath 'Env:\VS_UNICODE_OUTPUT' -Force }
    try {
        & $path
        Write-Host "================ FAMILY END $f ok ($([int]$sw.Elapsed.TotalSeconds)s) ================"
    } catch {
        Write-Host "================ FAMILY END $f FAILED ($([int]$sw.Elapsed.TotalSeconds)s) ================"
        $msg = "$f FAILED: $($_.Exception.Message)"
        Write-Host $msg
        Write-Host ($_.ScriptStackTrace)
        $failures += $msg
        Add-Content -Path (Join-Path $results 'FAILURES.txt') -Value @($msg, $_.ScriptStackTrace, '') -Encoding utf8
    }
}

Write-Host ''
Write-Host '================ summary ================'
Get-ChildItem -Path $results -File | Sort-Object Name | ForEach-Object { Write-Host ("{0,10}  {1}" -f $_.Length, $_.Name) }

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($m in $failures) { Write-Host "FAILED: $m" }
    throw "$($failures.Count) probe family/families failed. See FAILURES.txt in the artifact."
}
Write-Host 'all families completed'
