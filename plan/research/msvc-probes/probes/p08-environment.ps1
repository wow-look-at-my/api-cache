# Probe family 8 -- the environment a compile reads.
#
# What msvc.md leans on (§8, §14.3):
#   INCLUDE "the system include search path. Must be in the key."
#   EXTERNAL_INCLUDE "/external:I equivalent. Same."
#   LIB "link-time only. Irrelevant to a -c compile."
#   CL, _CL_ -- covered in family 7.
#   VS_UNICODE_OUTPUT "when set, cl sends its output TO THE IDE PROCESS rather
#     than to stdout/stderr. Must be unset around every child run, or the
#     wrapper captures nothing."
#   VCToolsVersion, VCToolsInstallDir "ccache hashes both on Windows."
#
# VS_UNICODE_OUTPUT is the one with a testable, dramatic claim, so it is
# measured directly rather than cited.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p08-environment' -Title 'Probe 8: INCLUDE, EXTERNAL_INCLUDE, LIB, TMP, VS_UNICODE_OUTPUT'

$cl = (Get-Command cl.exe).Source

$d = New-Scratch 'p08'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'incA') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $d 'incB') | Out-Null
Write-Source (Join-Path $d 'incA\pick.h') "#pragma once`n#define PICKED ""incA""`n"
Write-Source (Join-Path $d 'incB\pick.h') "#pragma once`n#define PICKED ""incB""`n"
Write-Source (Join-Path $d 'e.c') @"
#include <pick.h>
#pragma message("PICKED=" PICKED)
int e_fn(void) { return 0; }
"@
Write-Source (Join-Path $d 'sys.c') @"
#include <stdio.h>
int sys_fn(void) { return 0; }
"@

$origInclude = [System.Environment]::GetEnvironmentVariable('INCLUDE')
Add-Note 'The INCLUDE the toolchain step set, one entry per line:'
Add-Note '```'
Add-Note ($origInclude -split ';' | Where-Object { $_ })
Add-Note '```'
Add-Note ''
foreach ($n in @('EXTERNAL_INCLUDE', 'LIB', 'LIBPATH', 'CL', '_CL_', 'TMP', 'TEMP', 'VSLANG', 'VS_UNICODE_OUTPUT', 'VCToolsVersion', 'VCToolsInstallDir', 'UCRTVersion', 'WindowsSdkVerBinPath')) {
    $v = [System.Environment]::GetEnvironmentVariable($n)
    if ($null -eq $v) { $v = '(unset)' }
    Add-Note ('`' + $n + '` = `' + $v + '`')
}
Add-Note ''

# --- INCLUDE decides which pick.h wins.
$null = Invoke-Probe -Id 'INCLUDE-incA' -Exe $cl -CmdArgs @('/nologo', '/c', '/FoA.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ INCLUDE = (Join-Path $d 'incA') + ';' + $origInclude } -Comment `
    'INCLUDE leads with incA. `#include <pick.h>` must resolve there.'

$null = Invoke-Probe -Id 'INCLUDE-incB' -Exe $cl -CmdArgs @('/nologo', '/c', '/FoB.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ INCLUDE = (Join-Path $d 'incB') + ';' + $origInclude } -Comment `
    'The identical argv with INCLUDE leading with incB. A different header, a different object, the SAME command line -- which is exactly why INCLUDE must be in the key.'

$objA = Join-Path $d 'A.obj'; $objB = Join-Path $d 'B.obj'
if ((Test-Path $objA) -and (Test-Path $objB)) {
    $ha = (Get-FileHash $objA -Algorithm SHA256).Hash
    $hb = (Get-FileHash $objB -Algorithm SHA256).Hash
    Add-Note '```'
    Add-Note ("A.obj (INCLUDE=incA;...) : {0}" -f $ha)
    Add-Note ("B.obj (INCLUDE=incB;...) : {0}" -f $hb)
    Add-Note ("identical                : {0}" -f ($ha -eq $hb))
    Add-Note '```'
    Add-Note ''
}

# --- /I beats INCLUDE?
$null = Invoke-Probe -Id 'INCLUDE-vs-I-flag' -Exe $cl -CmdArgs @('/nologo', '/c', '/IincA', '/FoI.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ INCLUDE = (Join-Path $d 'incB') + ';' + $origInclude } -Comment `
    '/I names incA while INCLUDE leads with incB. Which wins?'

# --- INCLUDE removed entirely: does a system header still resolve?
$null = Invoke-Probe -Id 'INCLUDE-empty' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fosys.obj', 'sys.c') -WorkDir $d `
    -EnvVars @{ INCLUDE = 'C:\nonexistent-include-path' } -Comment `
    'INCLUDE points nowhere. `#include <stdio.h>` should fail with C1083 -- proof that cl has no built-in system path.'

# --- EXTERNAL_INCLUDE.
Write-Source (Join-Path $d 'ext.c') @"
#include <pick.h>
#pragma message("PICKED=" PICKED)
int ext_fn(void) { return 0; }
"@
$null = Invoke-Probe -Id 'EXTERNAL_INCLUDE-resolves' -Exe $cl -CmdArgs @('/nologo', '/c', '/external:W0', '/Foext.obj', 'ext.c') -WorkDir $d `
    -EnvVars @{ EXTERNAL_INCLUDE = (Join-Path $d 'incB'); INCLUDE = $origInclude } -Comment `
    'EXTERNAL_INCLUDE names incB and INCLUDE does not. Does the header resolve through EXTERNAL_INCLUDE alone?'

$null = Invoke-Probe -Id 'external-env-flag' -Exe $cl -CmdArgs @('/nologo', '/c', '/external:env:MYEXT', '/external:W0', '/Foextenv.obj', 'ext.c') -WorkDir $d `
    -EnvVars @{ MYEXT = (Join-Path $d 'incB'); INCLUDE = $origInclude } -Comment `
    '/external:env:<var> -- a THIRD env-var name that reaches the include search, and one chosen by argv. A wrapper cannot use a fixed allowlist for it.'

# --- LIB under /c.
$null = Invoke-Probe -Id 'LIB-irrelevant-under-c' -Exe $cl -CmdArgs @('/nologo', '/c', '/Folib.obj', 'sys.c') -WorkDir $d `
    -EnvVars @{ LIB = 'C:\nonexistent-lib-path' } -Comment `
    'LIB points nowhere and the compile is /c. msvc.md §8 says LIB is link-time only.'

# --- TMP: does a /c compile write anything into it?
$tmpDir = Join-Path $d 'mytmp'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$null = Invoke-Probe -Id 'TMP-redirected' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fotmp.obj', 'sys.c') -WorkDir $d `
    -EnvVars @{ TMP = $tmpDir; TEMP = $tmpDir } -Comment `
    'TMP and TEMP redirected to an empty directory.'
Add-DirListing $tmpDir -Caption 'contents of the redirected TMP after the compile'

# --- TMP pointing at a nonexistent directory.
$null = Invoke-Probe -Id 'TMP-nonexistent' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fotmp2.obj', 'sys.c') -WorkDir $d `
    -EnvVars @{ TMP = 'C:\no-such-tmp-dir'; TEMP = 'C:\no-such-tmp-dir' } -Comment `
    'TMP points at a directory that does not exist.'

# --- VS_UNICODE_OUTPUT: the claim that the wrapper captures nothing.
$null = Invoke-Probe -Id 'VS_UNICODE_OUTPUT-set-1' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/Fovsu.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ VS_UNICODE_OUTPUT = '1'; INCLUDE = (Join-Path $d 'incA') + ';' + $origInclude } -Comment `
    'VS_UNICODE_OUTPUT=1. msvc.md §8: cl then sends its output to the IDE process rather than to stdout/stderr, so the capture should be EMPTY. The value is normally a pipe handle number, so 1 is a plausible-but-wrong handle; the capture records what cl does with it.'

$null = Invoke-Probe -Id 'VS_UNICODE_OUTPUT-set-0' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/Fovsu0.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ VS_UNICODE_OUTPUT = '0'; INCLUDE = (Join-Path $d 'incA') + ';' + $origInclude }

$null = Invoke-Probe -Id 'VS_UNICODE_OUTPUT-set-garbage' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/Fovsug.obj', 'e.c') -WorkDir $d `
    -EnvVars @{ VS_UNICODE_OUTPUT = 'notanumber'; INCLUDE = (Join-Path $d 'incA') + ';' + $origInclude }

# --- An error case under VS_UNICODE_OUTPUT: is the DIAGNOSTIC lost too?
Write-Source (Join-Path $d 'bad.c') "int bad_fn(void) { return nosuchsymbol; }`n"
$null = Invoke-Probe -Id 'VS_UNICODE_OUTPUT-error-path' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fobad.obj', 'bad.c') -WorkDir $d `
    -EnvVars @{ VS_UNICODE_OUTPUT = '1' } -Comment `
    'A compile that must emit C2065. If the capture is empty but the exit code is non-zero, a wrapper caching this run would store an error with no message.'
$null = Invoke-Probe -Id 'error-path-baseline' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fobad2.obj', 'bad.c') -WorkDir $d -Comment `
    'The same compile with VS_UNICODE_OUTPUT unset, for the comparison.'

Add-DirListing $d
