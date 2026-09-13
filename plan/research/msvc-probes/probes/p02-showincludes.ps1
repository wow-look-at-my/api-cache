# Probe family 2 -- /showIncludes and /sourceDependencies.
#
# What msvc.md leans on:
#   §4  "cl.exe /showIncludes writes one line per included file to stdout (not
#        stderr -- this differs from gcc's -H)".
#   §4  "The indentation after the prefix encodes nesting depth."
#   §4  "The lines are interleaved with real diagnostics on stdout."
#   §5  the /sourceDependencies JSON shape: Version, Data.Source,
#        Data.ProvidedModule, Data.Includes, Data.ImportedModules,
#        Data.ImportedHeaderUnits.
#   §14 "/showIncludes:user" listed as a clang-cl-only spelling.
#
# The stream question is load-bearing twice over: a wrapper that strips the
# lines from the wrong stream either caches another workspace's paths or throws
# away the compiler's real diagnostics.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p02-showincludes' -Title 'Probe 2: /showIncludes format, stream, depth; /sourceDependencies JSON'

$cl = (Get-Command cl.exe).Source
$w = New-Scratch 'p02'

# A three-level include chain, plus a system header, plus a duplicate include
# (does cl report a header twice, or only the first time?).
New-Item -ItemType Directory -Force -Path (Join-Path $w 'inc') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $w 'ext') | Out-Null
Write-Source (Join-Path $w 'inc\lvl3.h') "#pragma once`nstatic const int lvl3 = 3;`n"
Write-Source (Join-Path $w 'inc\lvl2.h') "#pragma once`n#include ""lvl3.h""`nstatic const int lvl2 = 2;`n"
Write-Source (Join-Path $w 'inc\lvl1.h') "#pragma once`n#include ""lvl2.h""`nstatic const int lvl1 = 1;`n"
Write-Source (Join-Path $w 'ext\extern.h') "#pragma once`nstatic const int ext_v = 9;`n"
Write-Source (Join-Path $w 'dup.h') "static const int dup_v = 5;`n"
Write-Source (Join-Path $w 'a.c') @"
#include "inc/lvl1.h"
#include <stdio.h>
#include "dup.h"
#include "dup.h"
int a(void) { return lvl1 + lvl2 + lvl3 + dup_v; }
"@

# --- the baseline: which stream, what prefix, what indentation.
$si = Invoke-Probe -Id 'showincludes-plain' -Exe $cl -CmdArgs @('/c', '/I', 'inc', '/showIncludes', 'a.c') -WorkDir $w -Comment `
    'Baseline. Banner NOT suppressed, so the interleaving with the banner and the source-name line is visible.'
Add-HexDump -Bytes $si.OutBytes -Caption 'stdout bytes (first 512)' -Max 512
Add-HexDump -Bytes $si.ErrBytes -Caption 'stderr bytes (first 512)' -Max 512

$hasNote = $si.Stdout -match 'including file'
$errNote = $si.Stderr -match 'including file'
Add-Note "stdout carries the include notes: **$hasNote**  |  stderr carries them: **$errNote**"
Add-Note ''

# The indentation question, isolated: show every note line with its leading
# whitespace made visible.
$vis = @()
foreach ($line in ($si.Stdout -split "`r?`n")) {
    if ($line -match 'including file') {
        $vis += ($line -replace ' ', '.')
    }
}
Add-Note 'Every include-note line from the stdout capture, with each space rendered as `.` so the depth indentation is countable:'
Add-Note '```'
Add-Note $vis
Add-Note '```'
Add-Note ''

# --- with /nologo: does the note format change at all?
$null = Invoke-Probe -Id 'showincludes-nologo' -Exe $cl -CmdArgs @('/nologo', '/c', '/I', 'inc', '/showIncludes', 'a.c') -WorkDir $w -Comment `
    'Does /nologo change anything about the notes themselves?'

# --- interleaving with a real diagnostic: a warning in the middle of the file.
Write-Source (Join-Path $w 'warn.c') @"
#include "inc/lvl1.h"
int warn(void) { int unused_local; return lvl1; }
"@
$null = Invoke-Probe -Id 'showincludes-with-warning' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/I', 'inc', '/showIncludes', 'warn.c') -WorkDir $w -Comment `
    'A C4101 warning plus the include notes: are they on the same stream, and in what order?'

# --- /external:I and /external:W0: are external headers still reported?
Write-Source (Join-Path $w 'e.c') @"
#include <extern.h>
#include "inc/lvl1.h"
int e(void) { return ext_v + lvl1; }
"@
$null = Invoke-Probe -Id 'showincludes-external-I' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/external:I', 'ext', '/external:W0', '/showIncludes', 'e.c') -WorkDir $w -Comment `
    '/external:I ext /external:W0 with /showIncludes. Is the external header still listed? Does it carry a different marker?'

$null = Invoke-Probe -Id 'showincludes-external-anglebrackets' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/external:I', 'ext', '/external:W0', '/external:anglebrackets', '/showIncludes', 'e.c') -WorkDir $w

# --- /showIncludes:user -- msvc.md §14 calls this a clang-cl spelling. Does
#     real cl accept it?
$null = Invoke-Probe -Id 'showincludes-user' -Exe $cl -CmdArgs @('/nologo', '/c', '/I', 'inc', '/showIncludes:user', 'a.c') -WorkDir $w -Comment `
    'Does real cl.exe accept /showIncludes:user, and if so does it drop the system headers?'

# --- sccache's own detection invocation, verbatim from
#     refs/sccache/src/compiler/msvc.rs:204 -- note it uses -E and reads STDERR.
$d = New-Scratch 'p02-detect'
Write-Source (Join-Path $d 'test.c') "#include ""test.h""`n"
Write-Source (Join-Path $d 'test.h') "/* empty */`n"
$det = Invoke-Probe -Id 'sccache-detect-invocation' -Exe $cl `
    -CmdArgs @('-nologo', '-showIncludes', '-c', '-Fonul', '-I.', '-E', 'test.c') -WorkDir $d -Comment `
    'sccache''s detect_showincludes_prefix invocation, verbatim (refs/sccache/src/compiler/msvc.rs:204). It combines -c with -E and then reads **stderr**. This probe shows which stream the notes actually land on when -E is present.'
Add-Note "notes on stdout: **$($det.Stdout -match 'test\.h')**  |  notes on stderr: **$($det.Stderr -match 'test\.h')**"
Add-Note ''

# --- the same, without -E, for the contrast.
$null = Invoke-Probe -Id 'detect-invocation-no-E' -Exe $cl `
    -CmdArgs @('-nologo', '-showIncludes', '-c', '-Fonul', '-I.', 'test.c') -WorkDir $d -Comment `
    'The same command with -E removed: a normal compile.'

# --- /E alone, and /P: where does the preprocessed text go, and the notes?
$null = Invoke-Probe -Id 'showincludes-E-only' -Exe $cl -CmdArgs @('/nologo', '/E', '/I', 'inc', '/showIncludes', 'a.c') -WorkDir $w
$null = Invoke-Probe -Id 'showincludes-P-only' -Exe $cl -CmdArgs @('/nologo', '/P', '/I', 'inc', '/showIncludes', 'a.c') -WorkDir $w

# ---------------------------------------------------------------- /sourceDependencies
$sd = New-Scratch 'p02-sourcedeps'
Copy-Item -Recurse (Join-Path $w 'inc') (Join-Path $sd 'inc')
Copy-Item (Join-Path $w 'a.c') (Join-Path $sd 'a.c')
Copy-Item (Join-Path $w 'dup.h') (Join-Path $sd 'dup.h')

$null = Invoke-Probe -Id 'sourcedeps-separated' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/sourceDependencies', 'deps.json', 'a.c') -WorkDir $sd -Comment `
    'Separated spelling: /sourceDependencies deps.json'
if (Test-Path (Join-Path $sd 'deps.json')) {
    $json = Get-Content -Raw (Join-Path $sd 'deps.json')
    Add-Note 'deps.json, verbatim:'
    Add-Note '```json'
    Add-Note $json.TrimEnd()
    Add-Note '```'
    Add-Note ''
    Copy-Item (Join-Path $sd 'deps.json') (Join-Path $script:Raw 'sourcedeps-separated.deps.json')
    $obj = $json | ConvertFrom-Json
    Add-Note 'Top-level keys and `Data` keys, as parsed:'
    Add-Note '```'
    Add-Note ("top-level: " + (($obj.PSObject.Properties.Name) -join ', '))
    Add-Note ("Data: " + (($obj.Data.PSObject.Properties.Name) -join ', '))
    Add-Note ("Version value: " + $obj.Version)
    Add-Note '```'
    Add-Note ''
} else {
    Add-Note '**deps.json was not written.**'
    Add-Note ''
}

$null = Invoke-Probe -Id 'sourcedeps-concatenated' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/sourceDependenciesdeps2.json', '/Foa2.obj', 'a.c') -WorkDir $sd -Comment `
    'Concatenated spelling: /sourceDependencies<file>. msvc.md §5 claims both spellings work.'
if (Test-Path (Join-Path $sd 'deps2.json')) {
    Add-Note 'deps2.json was written. Verbatim:'
    Add-Note '```json'
    Add-Note ((Get-Content -Raw (Join-Path $sd 'deps2.json')).TrimEnd())
    Add-Note '```'
    Add-Note ''
} else {
    Add-Note '**deps2.json was NOT written** -- the concatenated spelling did not name an output file.'
    Add-Note ''
}

# --- /sourceDependencies - (to stdout) and /sourceDependencies:directives.
$null = Invoke-Probe -Id 'sourcedeps-to-stdout' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/sourceDependencies', '-', '/Foa3.obj', 'a.c') -WorkDir $sd -Comment `
    '/sourceDependencies - : documented to write the JSON to stdout. If so, the JSON and the source-name line share a stream.'

$null = Invoke-Probe -Id 'sourcedeps-directives' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/sourceDependencies:directives', 'dirs.json', '/Foa4.obj', 'a.c') -WorkDir $sd -Comment `
    '/sourceDependencies:directives -- the module-directive scan.'
if (Test-Path (Join-Path $sd 'dirs.json')) {
    Add-Note 'dirs.json, verbatim:'
    Add-Note '```json'
    Add-Note ((Get-Content -Raw (Join-Path $sd 'dirs.json')).TrimEnd())
    Add-Note '```'
    Add-Note ''
}

# --- both at once: does /sourceDependencies suppress /showIncludes?
$null = Invoke-Probe -Id 'sourcedeps-plus-showincludes' -Exe $cl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/showIncludes', '/sourceDependencies', 'deps3.json', '/Foa5.obj', 'a.c') -WorkDir $sd

Add-DirListing $sd
Add-DirListing $w
