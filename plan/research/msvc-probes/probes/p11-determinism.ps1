# Probe family 11 -- is an MSVC object reproducible?
#
# Nothing in msvc.md states this outright, but the whole plan depends on it: a
# cache that replays a stored .obj is only correct if a re-run would have
# produced the same bytes. The relevant switches are /Brepro (reproducible
# output, no timestamp) and /d1trimfile:<dir> (trim an absolute prefix out of
# the paths the compiler embeds).
#
# msvc.md §14 lists /Brepro nowhere. sccache's flag table carries
# `msvc_flag!("Brepro", PassThrough)` (refs/sccache/src/compiler/msvc.rs:299).

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p11-determinism' -Title 'Probe 11: object reproducibility, /Brepro, /d1trimfile, __DATE__ / __TIME__'

$cl = (Get-Command cl.exe).Source

function Copy-Sources {
    param([string]$Dir)
    Write-Source (Join-Path $Dir 'det.c') @"
#include "det.h"
int det_fn(int x) { return x + DET_K; }
"@
    Write-Source (Join-Path $Dir 'det.h') "#pragma once`n#define DET_K 7`n"
    Write-Source (Join-Path $Dir 'stamp.c') @"
const char *build_date(void) { return __DATE__; }
const char *build_time(void) { return __TIME__; }
const char *build_stamp(void) { return __TIMESTAMP__; }
"@
}

function Compare-Objects {
    param([string]$A, [string]$B, [string]$Caption)
    $ha = (Get-FileHash $A -Algorithm SHA256).Hash
    $hb = (Get-FileHash $B -Algorithm SHA256).Hash
    $sa = (Get-Item $A).Length
    $sb = (Get-Item $B).Length
    $same = ($ha -eq $hb)
    $firstDiff = -1
    if (-not $same) {
        $ba = [System.IO.File]::ReadAllBytes($A)
        $bb = [System.IO.File]::ReadAllBytes($B)
        $n = [Math]::Min($ba.Length, $bb.Length)
        for ($i = 0; $i -lt $n; $i++) { if ($ba[$i] -ne $bb[$i]) { $firstDiff = $i; break } }
        if ($firstDiff -lt 0) { $firstDiff = $n }
    }
    Add-Note "#### $Caption"
    Add-Note ''
    Add-Note '```'
    Add-Note ("run 1 : {0}  ({1} bytes)  {2}" -f $ha, $sa, (Split-Path -Leaf $A))
    Add-Note ("run 2 : {0}  ({1} bytes)  {2}" -f $hb, $sb, (Split-Path -Leaf $B))
    Add-Note ("byte-identical : {0}" -f $same)
    if (-not $same) {
        Add-Note ("first differing byte offset : {0} (0x{0:x})" -f $firstDiff)
        $ba = [System.IO.File]::ReadAllBytes($A)
        $bb = [System.IO.File]::ReadAllBytes($B)
        $lo = [Math]::Max(0, $firstDiff - 16)
        $hi = [Math]::Min([Math]::Min($ba.Length, $bb.Length) - 1, $firstDiff + 31)
        $ra = ($ba[$lo..$hi] | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
        $rb = ($bb[$lo..$hi] | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
        Add-Note ("window at 0x{0:x}, run 1 : {1}" -f $lo, $ra)
        Add-Note ("window at 0x{0:x}, run 2 : {1}" -f $lo, $rb)
        # How many bytes differ in total?
        $n = [Math]::Min($ba.Length, $bb.Length)
        $diff = 0
        for ($i = 0; $i -lt $n; $i++) { if ($ba[$i] -ne $bb[$i]) { $diff++ } }
        Add-Note ("differing bytes in the common prefix : {0} of {1}" -f $diff, $n)
    }
    Add-Note '```'
    Add-Note ''
    return $same
}

# --- the same compile twice, in the SAME directory, seconds apart.
# Hashtables, not nested arrays. PowerShell UNROLLS a nested array inside @(),
# so @('Z7-Brepro', @('/Z7','/Brepro')) becomes the flat three-element
# @('Z7-Brepro','/Z7','/Brepro') and the run silently loses /Brepro, while
# @('none', @()) collapses to one element and leaves $extra null. A hashtable
# is not an array, so nothing unrolls and every case runs the flags it names.
foreach ($case in @(
    @{ name = 'Z7';        extra = @('/Z7') },
    @{ name = 'Zi';        extra = @('/Zi') },
    @{ name = 'none';      extra = @() },
    @{ name = 'Brepro';    extra = @('/Brepro') },
    @{ name = 'Z7-Brepro'; extra = @('/Z7', '/Brepro') }
)) {
    $name = $case.name; $extra = @($case.extra)
    $d = New-Scratch "p11-$name"
    Copy-Sources $d
    $a = @('/nologo', '/c') + $extra + @('/Forun1.obj', 'det.c')
    $b = @('/nologo', '/c') + $extra + @('/Forun2.obj', 'det.c')
    $null = Invoke-Probe -Id "same-dir-$name-run1" -Exe $cl -CmdArgs $a -WorkDir $d
    Start-Sleep -Seconds 2
    $null = Invoke-Probe -Id "same-dir-$name-run2" -Exe $cl -CmdArgs $b -WorkDir $d
    if ((Test-Path (Join-Path $d 'run1.obj')) -and (Test-Path (Join-Path $d 'run2.obj'))) {
        $null = Compare-Objects (Join-Path $d 'run1.obj') (Join-Path $d 'run2.obj') "two runs, same directory, flags: $($extra -join ' ') (none = no debug flag)"
    }
    Add-DirListing $d
}

# --- the same compile in TWO DIFFERENT directories: does the absolute path get
#     baked into the object? This is what decides whether a shared cache can
#     hand one workstation's object to another.
$d1 = New-Scratch 'p11-pathA'
$d2 = New-Scratch 'p11-path-a-much-longer-directory-name-B'
Copy-Sources $d1
Copy-Sources $d2
foreach ($z in @('Z7', 'none')) {
    $extra = @(if ($z -eq 'Z7') { '/Z7' })
    $null = Invoke-Probe -Id "pathA-$z" -Exe $cl -CmdArgs (@('/nologo', '/c') + $extra + @("/Fo$z.obj", 'det.c')) -WorkDir $d1
    $null = Invoke-Probe -Id "pathB-$z" -Exe $cl -CmdArgs (@('/nologo', '/c') + $extra + @("/Fo$z.obj", 'det.c')) -WorkDir $d2
    $null = Compare-Objects (Join-Path $d1 "$z.obj") (Join-Path $d2 "$z.obj") "same source, two different absolute directories, flags: $($extra -join ' ')"
    # Does either object carry its own directory as a literal string?
    # Again a hashtable per case: @(@($d1,$n), @($d2,$n)) would unroll to four
    # bare strings, and $pair[0] would index a CHARACTER out of one of them.
    foreach ($pair in @(@{ dir = $d1; file = "$z.obj" }, @{ dir = $d2; file = "$z.obj" })) {
        $obj = Join-Path $pair.dir $pair.file
        $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($obj))
        Add-Note ('`' + $obj + '` contains its own directory path as a literal string: **' + $txt.Contains($pair.dir) + '**')
    }
    Add-Note ''
}

# --- /d1trimfile: does it remove the embedded prefix?
$dt = New-Scratch 'p11-trimfile'
Copy-Sources $dt
$null = Invoke-Probe -Id 'Z7-no-trim' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Fonotrim.obj', (Join-Path $dt 'det.c')) -WorkDir $dt -Comment `
    'An ABSOLUTE source path under /Z7, with no trimming.'
$null = Invoke-Probe -Id 'Z7-d1trimfile' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', "/d1trimfile:$dt\", '/Fotrim.obj', (Join-Path $dt 'det.c')) -WorkDir $dt -Comment `
    '/d1trimfile:<dir>\ -- the undocumented switch that strips a prefix from the paths the compiler embeds.'
foreach ($n in @('notrim', 'trim')) {
    $p = Join-Path $dt "$n.obj"
    if (Test-Path $p) {
        $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($p))
        Add-Note ('`' + $n + '.obj` contains the literal directory `' + $dt + '`: **' + $txt.Contains($dt) + '**  |  size ' + (Get-Item $p).Length)
    }
}
Add-Note ''
if ((Test-Path (Join-Path $dt 'notrim.obj')) -and (Test-Path (Join-Path $dt 'trim.obj'))) {
    $null = Compare-Objects (Join-Path $dt 'notrim.obj') (Join-Path $dt 'trim.obj') '/Z7 with and without /d1trimfile'
}
Add-DirListing $dt

# --- /Brepro against a path difference (it is about timestamps, not paths --
#     record that it does not help).
$b1 = New-Scratch 'p11-breproA'
$b2 = New-Scratch 'p11-brepro-longer-dir-B'
Copy-Sources $b1
Copy-Sources $b2
$null = Invoke-Probe -Id 'Brepro-pathA' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Brepro', '/Fobr.obj', 'det.c') -WorkDir $b1
$null = Invoke-Probe -Id 'Brepro-pathB' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Brepro', '/Fobr.obj', 'det.c') -WorkDir $b2
$null = Compare-Objects (Join-Path $b1 'br.obj') (Join-Path $b2 'br.obj') '/Z7 /Brepro from two different directories'

# --- __DATE__ / __TIME__ / __TIMESTAMP__.
$ds = New-Scratch 'p11-stamp'
Copy-Sources $ds
$null = Invoke-Probe -Id 'stamp-run1' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fostamp1.obj', 'stamp.c') -WorkDir $ds
Add-Note 'Sleeping 3 seconds. `__TIME__` expands to HH:MM:SS, so seconds are enough to move it.'
Add-Note ''
Start-Sleep -Seconds 3
$null = Invoke-Probe -Id 'stamp-run2' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fostamp2.obj', 'stamp.c') -WorkDir $ds
$null = Compare-Objects (Join-Path $ds 'stamp1.obj') (Join-Path $ds 'stamp2.obj') '__DATE__/__TIME__/__TIMESTAMP__ source, two runs a few seconds apart'

$null = Invoke-Probe -Id 'stamp-brepro-run1' -Exe $cl -CmdArgs @('/nologo', '/c', '/Brepro', '/Fobs1.obj', 'stamp.c') -WorkDir $ds
Start-Sleep -Seconds 3
$null = Invoke-Probe -Id 'stamp-brepro-run2' -Exe $cl -CmdArgs @('/nologo', '/c', '/Brepro', '/Fobs2.obj', 'stamp.c') -WorkDir $ds
$null = Compare-Objects (Join-Path $ds 'bs1.obj') (Join-Path $ds 'bs2.obj') 'the same source with /Brepro, two runs a few seconds apart -- /Brepro must NOT fix this'

# Show the literal time strings the two objects carry.
foreach ($n in @('stamp1', 'stamp2', 'bs1', 'bs2')) {
    $p = Join-Path $ds "$n.obj"
    if (-not (Test-Path $p)) { continue }
    $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($p))
    $hits = [regex]::Matches($txt, '\d\d:\d\d:\d\d') | ForEach-Object { $_.Value } | Select-Object -Unique
    Add-Note ('`' + $n + '.obj` embedded HH:MM:SS strings: `' + (($hits -join ', ')) + '`')
}
Add-Note ''
Add-Note 'The `__TIMESTAMP__` expansion is the source file''s own mtime, not the compile time, so it moves only when the file is touched. The `__TIME__` strings above are the ones that move per run.'
Add-Note ''

# --- and the same source WITHOUT the macros, to prove the timestamp difference
#     comes from the macros rather than from an object header field.
$dn = New-Scratch 'p11-nostamp'
Copy-Sources $dn
$null = Invoke-Probe -Id 'nostamp-run1' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fon1.obj', 'det.c') -WorkDir $dn
Start-Sleep -Seconds 3
$null = Invoke-Probe -Id 'nostamp-run2' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fon2.obj', 'det.c') -WorkDir $dn
$null = Compare-Objects (Join-Path $dn 'n1.obj') (Join-Path $dn 'n2.obj') 'a source with no temporal macro, two runs a few seconds apart'

Add-DirListing $ds
