# Probe family 10 -- clang-cl.
#
# What msvc.md leans on (§12, §14):
#   "clang-cl has no /sourceDependencies (use -showIncludes and synthesise
#    the .d)."
#   "it supports /showIncludes:user."
#   "/Zi /ZI -> bypass:unsupported_compiler_option" is stated for the MSVC family
#    as a whole, while ccache gates its /Z check on
#    is_compiler_group_msvc() && !is_compiler_group_clang().
#
# clang-cl's /Zi is the interesting one: clang has no separate-PDB compile mode,
# so if clang-cl treats /Zi as /Z7 the blanket bypass costs hits for nothing.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p10-clang-cl' -Title 'Probe 10: clang-cl -- /showIncludes, /Fo, /Zi, /sourceDependencies, colour'

$cc = Get-Command clang-cl.exe -ErrorAction SilentlyContinue
if (-not $cc) {
    Add-Note '**clang-cl.exe was NOT on PATH.** This family could not run.'
    Add-Note ''
    $probe = Join-Path $script:ResultsRoot 'MISSING-PREREQUISITES.txt'
    Add-Content -Path $probe -Value 'clang-cl.exe not found on PATH' -Encoding utf8
    throw 'clang-cl.exe is not on PATH on this runner'
}
$clangcl = $cc.Source
Add-Note "clang-cl resolved to ``$clangcl``"
Add-Note ''

$d = New-Scratch 'p10'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'inc') | Out-Null
Write-Source (Join-Path $d 'inc\lvl2.h') "#pragma once`nstatic const int lvl2 = 2;`n"
Write-Source (Join-Path $d 'inc\lvl1.h') "#pragma once`n#include ""lvl2.h""`nstatic const int lvl1 = 1;`n"
Write-Source (Join-Path $d 'a.c') @"
#include "inc/lvl1.h"
#include <stdio.h>
int a_fn(void) { return lvl1 + lvl2; }
"@
Write-Source (Join-Path $d 'err.c') "int err_fn(void) { return nosuchsymbol; }`n"

# --- version and identity.
$v = Invoke-Probe -Id 'clang-cl-version' -Exe $clangcl -CmdArgs @('--version') -WorkDir $d
$null = Invoke-Probe -Id 'clang-cl-no-args' -Exe $clangcl -WorkDir $d -Comment `
    'Bare clang-cl. buildcache''s get_program_id reads stderr and THROWS if it is empty -- does clang-cl put anything there?'
Add-HexDump -Bytes $v.OutBytes -Caption 'stdout of --version, verbatim' -Max 512
Add-HexDump -Bytes $v.ErrBytes -Caption 'stderr of --version, verbatim' -Max 256

# --- does clang-cl echo the source name on stdout the way cl does?
$c = Invoke-Probe -Id 'clang-cl-compile-plain' -Exe $clangcl -CmdArgs @('/c', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    'A plain compile with no /nologo. Does clang-cl print a banner or the source filename at all?'
Add-HexDump -Bytes $c.OutBytes -Caption 'stdout bytes, verbatim'
Add-HexDump -Bytes $c.ErrBytes -Caption 'stderr bytes, verbatim'
$null = Invoke-Probe -Id 'clang-cl-compile-nologo' -Exe $clangcl -CmdArgs @('/nologo', '/c', '/Foa2.obj', 'a.c') -WorkDir $d

# --- /showIncludes: prefix, depth, stream.
$si = Invoke-Probe -Id 'clang-cl-showincludes' -Exe $clangcl -CmdArgs @('/c', '/I', 'inc', '/showIncludes', '/Fosi.obj', 'a.c') -WorkDir $d -Comment `
    'The same include chain family 2 ran through cl.exe.'
Add-Note ("notes on stdout: **{0}**  |  on stderr: **{1}**" -f ($si.Stdout -match 'including file'), ($si.Stderr -match 'including file'))
Add-Note ''
$vis = @()
foreach ($line in (($si.Stdout + "`n" + $si.Stderr) -split "`r?`n")) {
    if ($line -match 'including file') { $vis += ($line -replace ' ', '.') }
}
Add-Note 'Every include-note line, spaces rendered as `.`:'
Add-Note '```'
Add-Note $vis
Add-Note '```'
Add-Note ''

$null = Invoke-Probe -Id 'clang-cl-showincludes-user' -Exe $clangcl -CmdArgs @('/c', '/I', 'inc', '/showIncludes:user', '/Fosiu.obj', 'a.c') -WorkDir $d -Comment `
    '/showIncludes:user -- msvc.md §12 says clang-cl supports it and that it lists project headers only.'

# --- sccache's detection invocation against clang-cl, with and without the
#     --driver-mode=cl prefix it adds for clang.
$dd = New-Scratch 'p10-detect'
Write-Source (Join-Path $dd 'test.c') "#include ""test.h""`n"
Write-Source (Join-Path $dd 'test.h') "/* empty */`n"
$null = Invoke-Probe -Id 'clang-cl-detect-invocation' -Exe $clangcl `
    -CmdArgs @('--driver-mode=cl', '-nologo', '-showIncludes', '-c', '-Fonul', '-I.', '-E', 'test.c') -WorkDir $dd -Comment `
    'sccache''s detect_showincludes_prefix shape for a clang driver (refs/sccache/src/compiler/msvc.rs:197-206).'
$null = Invoke-Probe -Id 'clang-cl-detect-no-drivermode' -Exe $clangcl `
    -CmdArgs @('-nologo', '-showIncludes', '-c', '-Fonul', '-I.', '-E', 'test.c') -WorkDir $dd

# --- /sourceDependencies: msvc.md §12 says clang-cl does not have it.
$null = Invoke-Probe -Id 'clang-cl-sourcedependencies' -Exe $clangcl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/sourceDependencies', 'deps.json', '/Fosd.obj', 'a.c') -WorkDir $d -Comment `
    'Is the flag accepted, ignored with a warning, or an error? And is deps.json written?'
Add-Note ("deps.json written: **{0}**" -f (Test-Path (Join-Path $d 'deps.json')))
Add-Note ''

# --- the gcc-style dep flags clang-cl does have.
$null = Invoke-Probe -Id 'clang-cl-MD-MF' -Exe $clangcl `
    -CmdArgs @('/nologo', '/c', '/I', 'inc', '/clang:-MD', '/clang:-MF', '/clang:a.d', '/Fomd.obj', 'a.c') -WorkDir $d -Comment `
    '-MD/-MF forwarded through /clang:. If this works, a wrapper need not synthesise the .d by hand for clang-cl.'
if (Test-Path (Join-Path $d 'a.d')) {
    Add-Note 'a.d, verbatim:'
    Add-Note '```make'
    Add-Note (Get-Content -Raw (Join-Path $d 'a.d')).TrimEnd()
    Add-Note '```'
    Add-Note ''
}

# --- /Fo spellings under clang-cl.
foreach ($case in @(
    @{ id = 'clang-cl-Fo-concat';   args = @('/nologo', '/c', '/Foname.obj', 'a.c');  note = '/Fo<name>' },
    @{ id = 'clang-cl-Fo-colon';    args = @('/nologo', '/c', '/Fo:colon.obj', 'a.c'); note = '/Fo:<name> -- does clang-cl accept the colon form?' },
    @{ id = 'clang-cl-Fo-dir';      args = @('/nologo', '/c', '/Foout\', 'a.c');      note = '/Fo<dir>\ with the directory existing' },
    @{ id = 'clang-cl-Fo-dir-missing'; args = @('/nologo', '/c', '/Fomissing\', 'a.c'); note = '/Fo<dir>\ with the directory absent' },
    @{ id = 'clang-cl-Fo-separated'; args = @('/nologo', '/c', '/Fo', 'sep.obj', 'a.c'); note = '/Fo <name> separated' }
)) {
    $cd = New-Scratch "p10-$($case.id)"
    New-Item -ItemType Directory -Force -Path (Join-Path $cd 'out') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $cd 'inc') | Out-Null
    Copy-Item (Join-Path $d 'inc\*') (Join-Path $cd 'inc')
    Copy-Item (Join-Path $d 'a.c') (Join-Path $cd 'a.c')
    $null = Invoke-Probe -Id $case.id -Exe $clangcl -CmdArgs $case.args -WorkDir $cd -Comment $case.note
    Add-DirListing $cd
}

# --- /Z7 vs /Zi vs /ZI under clang-cl: is a separate PDB even produced?
foreach ($z in @('Z7', 'Zi', 'ZI')) {
    $zd = New-Scratch "p10-clang-cl-$z"
    Copy-Item (Join-Path $d 'a.c') (Join-Path $zd 'a.c')
    New-Item -ItemType Directory -Force -Path (Join-Path $zd 'inc') | Out-Null
    Copy-Item (Join-Path $d 'inc\*') (Join-Path $zd 'inc')
    $null = Invoke-Probe -Id "clang-cl-$z" -Exe $clangcl -CmdArgs @('/nologo', '/c', "/$z", '/Foa.obj', 'a.c') -WorkDir $zd -Comment `
        "clang-cl /$z. If no .pdb appears, a blanket /Zi bypass costs clang-cl users every hit for nothing."
    Add-DirListing $zd
}

# --- colour under clang-cl, into a file and through a pipe.
foreach ($case in @(
    @{ id = 'clang-cl-colour-default';   args = @('/nologo', '/c', '/Foe.obj', 'err.c') },
    @{ id = 'clang-cl-fcolor';           args = @('/nologo', '/c', '-fcolor-diagnostics', '/Foe2.obj', 'err.c') },
    @{ id = 'clang-cl-fcolor-ansi';      args = @('/nologo', '/c', '-fcolor-diagnostics', '-fansi-escape-codes', '/Foe3.obj', 'err.c') },
    @{ id = 'clang-cl-fdiagnostics-color'; args = @('/nologo', '/c', '-fdiagnostics-color=always', '/Foe4.obj', 'err.c') },
    @{ id = 'clang-cl-fno-color';        args = @('/nologo', '/c', '-fno-color-diagnostics', '/Foe5.obj', 'err.c') }
)) {
    $r = Invoke-Probe -Id $case.id -Exe $clangcl -CmdArgs $case.args -WorkDir $d
    Add-Note ("ESC (0x1b) present -- stdout: **{0}**, stderr: **{1}**" -f (Test-HasEscape $r.OutBytes), (Test-HasEscape $r.ErrBytes))
    Add-Note ''
    if (Test-HasEscape $r.ErrBytes) { Add-HexDump -Bytes $r.ErrBytes -Caption 'stderr bytes with the escapes' -Max 400 }
}

# --- the diagnostic format itself: clang's, or MSVC's?
$null = Invoke-Probe -Id 'clang-cl-error-format' -Exe $clangcl -CmdArgs @('/nologo', '/c', '/Foef.obj', 'err.c') -WorkDir $d -Comment `
    'Is the message `file(line,col): error: ...` (MSVC-shaped) or `file:line:col: error: ...` (clang-shaped)?'

# --- /Brepro, which clang-cl also takes.
$null = Invoke-Probe -Id 'clang-cl-Brepro' -Exe $clangcl -CmdArgs @('/nologo', '/c', '/Brepro', '/Fobr.obj', 'a.c') -WorkDir $d

Add-DirListing $d
