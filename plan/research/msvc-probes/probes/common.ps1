# Shared helpers for the msvc-probes scripts.
#
# Every probe captures stdout, stderr and the exit code SEPARATELY and verbatim.
# Start-Process with two distinct redirect files is the only way to do that in
# PowerShell without the host merging the streams or re-encoding them.
#
# A probe's non-zero exit code is DATA, not a failure: several probes exist to
# record exactly what cl.exe prints when it fails. Only a missing prerequisite
# (no cl.exe, no clang-cl) is a failure, and that is raised by the caller.

$ErrorActionPreference = 'Stop'

$script:ResultsRoot = $env:PROBE_RESULTS
if (-not $script:ResultsRoot) { $script:ResultsRoot = Join-Path $PSScriptRoot 'ci-results' }
New-Item -ItemType Directory -Force -Path $script:ResultsRoot | Out-Null

$script:ScratchRoot = $env:PROBE_SCRATCH
if (-not $script:ScratchRoot) { $script:ScratchRoot = 'C:\p' }
New-Item -ItemType Directory -Force -Path $script:ScratchRoot | Out-Null

# The family currently being written. Set by Start-Family.
$script:Family = 'misc'
$script:Log = Join-Path $script:ResultsRoot 'misc.md'
$script:Raw = Join-Path $script:ResultsRoot 'misc'

function Start-Family {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Title)
    $script:Family = $Name
    $script:Log = Join-Path $script:ResultsRoot "$Name.md"
    $script:Raw = Join-Path $script:ResultsRoot $Name
    New-Item -ItemType Directory -Force -Path $script:Raw | Out-Null
    Set-Content -Path $script:Log -Value @(
        "# $Title",
        "",
        "Runner: ``$($env:ImageOS) / $($env:ImageVersion)`` on ``$($env:RUNNER_OS)``.",
        "Run: $($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)",
        "",
        "Raw captures (stdout / stderr / exit code, one file each) are under ``$Name/`` in this artifact.",
        ""
    ) -Encoding utf8
}

function Add-Note {
    param([Parameter(Mandatory)][string]$Text)
    Add-Content -Path $script:Log -Value $Text -Encoding utf8
}

function New-Scratch {
    param([Parameter(Mandatory)][string]$Name)
    $d = Join-Path $script:ScratchRoot $Name
    if (Test-Path $d) { Remove-Item -Recurse -Force $d }
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

# cl.exe writes in the console's code page, not UTF-8. Decode with the active
# ANSI code page so a non-ASCII banner survives the trip into markdown.
function Read-Bytes {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return [byte[]]@() }
    return [System.IO.File]::ReadAllBytes($Path)
}

function ConvertFrom-AnsiBytes {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
    $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
    try { $enc = [System.Text.Encoding]::GetEncoding($cp) } catch { $enc = [System.Text.Encoding]::ASCII }
    return $enc.GetString($Bytes)
}

function Format-Block {
    param([string]$Text)
    if ($null -eq $Text -or $Text.Length -eq 0) { return '(empty)' }
    return $Text.TrimEnd("`r", "`n")
}

# Invoke-Probe: run one command, capture the three things, append a markdown
# section, and hand the captures back to the caller for assertions.
function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Exe,
        [string[]]$CmdArgs = @(),
        [string]$WorkDir,
        [hashtable]$EnvVars = @{},
        [string]$Comment = ''
    )
    if (-not $WorkDir) { $WorkDir = (Get-Location).Path }

    $outFile = Join-Path $script:Raw "$Id.stdout.txt"
    $errFile = Join-Path $script:Raw "$Id.stderr.txt"
    $codeFile = Join-Path $script:Raw "$Id.exit.txt"
    $cmdFile = Join-Path $script:Raw "$Id.cmd.txt"

    $saved = @{}
    foreach ($k in $EnvVars.Keys) {
        $saved[$k] = [System.Environment]::GetEnvironmentVariable($k)
        [System.Environment]::SetEnvironmentVariable($k, $EnvVars[$k])
    }

    $display = "$Exe " + ($CmdArgs -join ' ')
    Set-Content -Path $cmdFile -Value $display -Encoding utf8

    try {
        if ($CmdArgs.Count -gt 0) {
            $p = Start-Process -FilePath $Exe -ArgumentList $CmdArgs -WorkingDirectory $WorkDir `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
                -NoNewWindow -Wait -PassThru
        } else {
            $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
                -NoNewWindow -Wait -PassThru
        }
        $code = $p.ExitCode
    } finally {
        foreach ($k in $saved.Keys) { [System.Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }

    Set-Content -Path $codeFile -Value "$code" -Encoding utf8

    $outBytes = Read-Bytes $outFile
    $errBytes = Read-Bytes $errFile
    $stdout = ConvertFrom-AnsiBytes $outBytes
    $stderr = ConvertFrom-AnsiBytes $errBytes

    $envNote = ''
    if ($EnvVars.Count -gt 0) {
        $pairs = foreach ($k in $EnvVars.Keys) { "$k=$($EnvVars[$k])" }
        $envNote = "`nenv: ``$($pairs -join '; ')``"
    }

    $lines = @(
        "### $Id",
        ""
    )
    if ($Comment) { $lines += @($Comment, "") }
    $lines += @(
        "cmd: ``$display``",
        "cwd: ``$WorkDir``$envNote",
        "",
        "exit code: **$code**  |  stdout: $($outBytes.Length) bytes  |  stderr: $($errBytes.Length) bytes",
        "",
        "stdout:",
        '```',
        (Format-Block $stdout),
        '```',
        "",
        "stderr:",
        '```',
        (Format-Block $stderr),
        '```',
        ""
    )
    Add-Content -Path $script:Log -Value $lines -Encoding utf8

    Write-Host "[$script:Family/$Id] exit=$code out=$($outBytes.Length)B err=$($errBytes.Length)B"

    return [pscustomobject]@{
        Id       = $Id
        Exit     = $code
        Stdout   = $stdout
        Stderr   = $stderr
        OutBytes = $outBytes
        ErrBytes = $errBytes
        WorkDir  = $WorkDir
    }
}

# A recursive listing of what a compile actually left on disk.
function Add-DirListing {
    param([Parameter(Mandatory)][string]$Path, [string]$Caption = 'files on disk after the run')
    $rows = Get-ChildItem -Path $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        "{0,10}  {1}" -f $_.Length, $_.FullName.Substring($Path.Length).TrimStart('\')
    }
    if (-not $rows) { $rows = @('(no files)') }
    Add-Content -Path $script:Log -Value @("$Caption ($Path):", '```', $rows, '```', '') -Encoding utf8
}

# A hex dump, for "the exact bytes of the banner".
function Add-HexDump {
    param([byte[]]$Bytes, [string]$Caption = 'hex dump', [int]$Max = 512)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        Add-Content -Path $script:Log -Value @("$Caption: (empty)", '') -Encoding utf8
        return
    }
    $n = [Math]::Min($Bytes.Length, $Max)
    $rows = @()
    for ($i = 0; $i -lt $n; $i += 16) {
        $chunk = $Bytes[$i..([Math]::Min($i + 15, $n - 1))]
        $hex = ($chunk | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
        $asc = -join ($chunk | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { '.' } })
        $rows += ('{0:x8}  {1,-47}  |{2}|' -f $i, $hex, $asc)
    }
    if ($Bytes.Length -gt $Max) { $rows += "... ($($Bytes.Length) bytes total)" }
    Add-Content -Path $script:Log -Value @("$Caption ($($Bytes.Length) bytes):", '```', $rows, '```', '') -Encoding utf8
}

# Does a capture carry an ANSI escape? The colour question.
function Test-HasEscape {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes) { return $false }
    return ($Bytes -contains 27)
}

function Write-Source {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
    # ASCII, LF->CRLF irrelevant to cl; write without a BOM so /utf-8 questions stay clean.
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}
