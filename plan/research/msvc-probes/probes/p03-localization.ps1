# Probe family 3 -- the localized /showIncludes prefix.
#
# What msvc.md leans on (§4 hazard 1): "The prefix is localized. On a Japanese
# or German Visual Studio the string is not `Note: including file:`. ccache
# exposes it as a config value (msvc_dep_prefix). sccache detects it at runtime."
#
# A hosted runner carries the English toolset only. This probe therefore does
# two things: it records what VSLANG actually does on a runner with no language
# pack, and it EXECUTES sccache's detection algorithm against the real compiler
# so the algorithm itself is measured rather than merely cited.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p03-localization' -Title 'Probe 3: message language, VSLANG, and sccache''s runtime prefix detection'

$cl = (Get-Command cl.exe).Source
$w = New-Scratch 'p03'
Write-Source (Join-Path $w 'test.c') "#include ""test.h""`n"
Write-Source (Join-Path $w 'test.h') "/* empty */`n"

# What language resources ship beside the compiler? The subdirectory names under
# the compiler's own directory are the installed message DLL locales.
$clDir = Split-Path -Parent $cl
Add-Note "Compiler directory: ``$clDir``"
Add-Note ''
Add-Note 'Locale subdirectories beside cl.exe (each holds the localized message DLLs; only these languages can be selected):'
Add-Note '```'
$subs = Get-ChildItem -Path $clDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name }
if (-not $subs) { $subs = @('(none)') }
Add-Note $subs
Add-Note '```'
Add-Note ''
Add-Note 'Files matching `*ui.dll` / `clui.dll` anywhere under the compiler directory (the message resource):'
Add-Note '```'
$uis = Get-ChildItem -Path $clDir -Recurse -Filter 'clui.dll' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($clDir.Length).TrimStart('\') }
if (-not $uis) { $uis = @('(none)') }
Add-Note $uis
Add-Note '```'
Add-Note ''

# --- VSLANG: the documented way to pick the message language.
$null = Invoke-Probe -Id 'vslang-unset' -Exe $cl -CmdArgs @('/nologo', '/c', '/showIncludes', '/I.', 'test.c') -WorkDir $w -Comment `
    'Baseline, VSLANG untouched.'

# Hashtables, not nested arrays: @(@(1041,'Japanese'), @(1031,'German'))
# UNROLLS into a flat @(1041,'Japanese',1031,'German') and the loop then walks
# LCIDs and language names alternately instead of pairs.
foreach ($pair in @(
    @{ lcid = 1041; name = 'Japanese' },
    @{ lcid = 1031; name = 'German' },
    @{ lcid = 1036; name = 'French' },
    @{ lcid = 2052; name = 'Chinese-Simplified' }
)) {
    $lcid = $pair.lcid; $name = $pair.name
    $null = Invoke-Probe -Id "vslang-$lcid" -Exe $cl -CmdArgs @('/nologo', '/c', '/showIncludes', '/I.', "/Fo$lcid.obj", 'test.c') `
        -WorkDir $w -EnvVars @{ VSLANG = "$lcid" } -Comment `
        "VSLANG=$lcid ($name). With no language pack installed cl falls back to English; the capture records which."
}

# --- sccache's detection algorithm, run for real.
# refs/sccache/src/compiler/msvc.rs:170-253: run `cl -nologo -showIncludes -c
# -Fonul -I. -E test.c` in a temp dir holding test.c (`#include "test.h"`) and
# an empty test.h; take every line ending in `test.h`; walk BACKWARDS from the
# end of the line for a space such that the remainder is an existing path;
# everything up to and including that space is the prefix.
function Get-ShowIncludesPrefix {
    param([string]$Exe, [string]$Dir, [switch]$IsClang)
    $cmdArgs = @()
    if ($IsClang) { $cmdArgs += '--driver-mode=cl' }
    $cmdArgs += @('-nologo', '-showIncludes', '-c', '-Fonul', '-I.', '-E', 'test.c')
    $o = Join-Path $script:Raw 'detect.stdout.txt'
    $e = Join-Path $script:Raw 'detect.stderr.txt'
    $p = Start-Process -FilePath $Exe -ArgumentList $cmdArgs -WorkingDirectory $Dir `
        -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait -PassThru
    $result = [ordered]@{ Exit = $p.ExitCode; Prefix = $null; Stream = $null; Line = $null }
    foreach ($stream in @('stderr', 'stdout')) {
        $text = ConvertFrom-AnsiBytes (Read-Bytes $(if ($stream -eq 'stderr') { $e } else { $o }))
        foreach ($line in ($text -split "`r?`n")) {
            if (-not $line.EndsWith('test.h')) { continue }
            for ($i = $line.Length - 1; $i -ge 0; $i--) {
                if ($line[$i] -ne ' ') { continue }
                # [IO.Path]::Combine plus [IO.File]::Exists, never Join-Path and
                # Test-Path: the candidate substring is arbitrary text off a
                # compiler message and may hold characters a PowerShell path
                # cmdlet throws on, which under $ErrorActionPreference='Stop'
                # would fail the family instead of rejecting the candidate.
                # sccache's own check is exactly "does this path exist".
                $cand = $null
                try { $cand = [System.IO.Path]::Combine($Dir, $line.Substring($i + 1)) } catch { continue }
                if ([System.IO.File]::Exists($cand)) {
                    $result.Prefix = $line.Substring(0, $i + 1)
                    $result.Stream = $stream
                    $result.Line = $line
                    return [pscustomobject]$result
                }
            }
        }
    }
    return [pscustomobject]$result
}

$det = Get-ShowIncludesPrefix -Exe $cl -Dir $w
Add-Note '## sccache''s detect_showincludes_prefix, executed against this cl.exe'
Add-Note ''
Add-Note 'Algorithm transcribed from `refs/sccache/src/compiler/msvc.rs:170-253`. sccache reads **stderr only**; this reimplementation tries stderr first and then stdout, and records which one actually carried the line.'
Add-Note ''
Add-Note '```'
Add-Note ("exit code       : {0}" -f $det.Exit)
Add-Note ("stream with line: {0}" -f $(if ($det.Stream) { $det.Stream } else { '(neither -- detection FAILED)' }))
Add-Note ("matched line    : {0}" -f $det.Line)
Add-Note ("detected prefix : [{0}]" -f $det.Prefix)
Add-Note ("prefix length   : {0}" -f $(if ($det.Prefix) { $det.Prefix.Length } else { 0 }))
Add-Note '```'
Add-Note ''
if ($det.Prefix) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($det.Prefix)
    Add-HexDump -Bytes $bytes -Caption 'the detected prefix, byte for byte'
}
Copy-Item (Join-Path $script:Raw 'detect.stdout.txt') (Join-Path $script:Raw 'sccache-detect.stdout.txt') -Force
Copy-Item (Join-Path $script:Raw 'detect.stderr.txt') (Join-Path $script:Raw 'sccache-detect.stderr.txt') -Force

# --- does the detection still work under a VSLANG that has no language pack?
foreach ($lcid in @(1041, 1031)) {
    $saved = [System.Environment]::GetEnvironmentVariable('VSLANG')
    [System.Environment]::SetEnvironmentVariable('VSLANG', "$lcid")
    $d2 = Get-ShowIncludesPrefix -Exe $cl -Dir $w
    [System.Environment]::SetEnvironmentVariable('VSLANG', $saved)
    Add-Note ('Detection with `VSLANG=' + $lcid + '`: stream=`' + $d2.Stream + '` prefix=`[' + $d2.Prefix + ']`')
}
Add-Note ''
