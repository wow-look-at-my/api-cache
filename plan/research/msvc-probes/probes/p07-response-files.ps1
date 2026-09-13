# Probe family 7 -- response files, and the CL / _CL_ environment variables.
#
# What msvc.md leans on:
#   §11 "They may be UTF-16 with a BOM."
#   §11 "They are not recursive ... It is not possible to specify the @ option
#        from within a response file."
#   §11 "Relative response-file paths are legal ... they resolve against the cwd."
#   §8  "CL, _CL_ -- arguments prepended / appended to every cl.exe command line
#        ... argv alone no longer describes the compile."
#   §14 "@<file> -- expand ONE level (BOM-aware), then re-dispatch."
#
# Every case compiles a probe source that reports, through #pragma message, which
# macros reached the compiler. The stdout of that compile IS the measurement.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p07-response-files' -Title 'Probe 7: @response files, quoting, nesting, UTF-16; CL and _CL_'

$cl = (Get-Command cl.exe).Source

$probeSrc = @"
#define STR2(x) #x
#define STR(x) STR2(x)
#ifdef FOO
#pragma message("SEEN FOO=" STR(FOO))
#else
#pragma message("NO FOO")
#endif
#ifdef BAR
#pragma message("SEEN BAR=" STR(BAR))
#endif
#ifdef MSG
#pragma message("SEEN MSG=" STR(MSG))
#endif
#ifdef PATHDEF
#pragma message("SEEN PATHDEF=" STR(PATHDEF))
#endif
#ifdef VAL
#pragma message("SEEN VAL=" STR(VAL))
#endif
#ifdef FROMINNER
#pragma message("SEEN FROMINNER=" STR(FROMINNER))
#endif
#ifdef WANT_SPACED_HEADER
#include "spaced.h"
#pragma message("SEEN spaced.h")
#endif
int probe_fn(void) { return 0; }
"@

function New-RspCase {
    param([string]$Name)
    $d = New-Scratch "p07-$Name"
    Write-Source (Join-Path $d 'probe.c') $probeSrc
    New-Item -ItemType Directory -Force -Path (Join-Path $d 'inc dir') | Out-Null
    Write-Source (Join-Path $d 'inc dir\spaced.h') "#pragma once`nstatic const int spaced = 1;`n"
    return $d
}

function Write-RspAscii {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.ASCIIEncoding))
}

# --- 1. a plain ASCII response file, one line.
$d = New-RspCase 'plain'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c /DFOO=1 /Foplain.obj probe.c')
Add-Note 'args.rsp:'
Add-Note '```'
Add-Note (Get-Content -Raw (Join-Path $d 'args.rsp')).TrimEnd()
Add-Note '```'
Add-Note ''
$null = Invoke-Probe -Id 'rsp-plain' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d
Add-DirListing $d

# --- 2. arguments split over several lines.
$d = New-RspCase 'multiline'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo', '/c', '/DFOO=2', '/Fomulti.obj', 'probe.c')
$null = Invoke-Probe -Id 'rsp-multiline' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'One argument per line. A line break is a separator.'
Add-DirListing $d

# --- 3. a quoted path containing a space.
$d = New-RspCase 'quoted-space'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c /DWANT_SPACED_HEADER /I"inc dir" /Foq.obj probe.c')
$null = Invoke-Probe -Id 'rsp-quoted-space' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'A double-quoted include directory with a space in it.'

# --- 4. the same path UNquoted: proof the quotes are load-bearing.
$d = New-RspCase 'unquoted-space'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c /DWANT_SPACED_HEADER /Iinc dir /Fou.obj probe.c')
$null = Invoke-Probe -Id 'rsp-unquoted-space' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'The same directory unquoted. `dir` should become a second input file.'

# --- 5. a define whose value contains a space.
$d = New-RspCase 'define-with-space'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c "/DMSG=hello world" /Fod.obj probe.c')
$null = Invoke-Probe -Id 'rsp-define-with-space' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'The whole argument is quoted, value included: "/DMSG=hello world".'

$d = New-RspCase 'define-with-space-inner'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c /D"MSG=hello world" /Fod2.obj probe.c')
$null = Invoke-Probe -Id 'rsp-define-with-space-inner' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'The quote opens AFTER /D: /D"MSG=hello world". Does the leader stay outside the quoted run?'

# --- 6. backslashes before a quote -- the MSVCRT quoting rule.
$d = New-RspCase 'backslash-quote'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c "/DPATHDEF=c:\dir\\" /Fob.obj probe.c')
Add-Note 'args.rsp (note the trailing `\\` before the closing quote):'
Add-Note '```'
Add-Note (Get-Content -Raw (Join-Path $d 'args.rsp')).TrimEnd()
Add-Note '```'
Add-Note ''
$null = Invoke-Probe -Id 'rsp-backslash-before-quote' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'Two backslashes before the closing quote: under the MSVCRT rule that is one literal backslash and a real closing quote.'

$d = New-RspCase 'backslash-quote-single'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c "/DPATHDEF=c:\dir\" /Fob2.obj probe.c')
$null = Invoke-Probe -Id 'rsp-single-backslash-before-quote' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'ONE backslash before the closing quote: under the MSVCRT rule that escapes the quote, so the quoted run swallows the rest of the line.'

# --- 7. an embedded escaped quote in a define value.
$d = New-RspCase 'escaped-quote'
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c "/DMSG=\"quoted\"" /Foe.obj probe.c')
$null = Invoke-Probe -Id 'rsp-escaped-quote' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d

# --- 8. NESTED @: msvc.md §11 says Microsoft documents this as impossible.
$d = New-RspCase 'nested'
Write-RspAscii (Join-Path $d 'inner.rsp') @('/DFROMINNER=1')
Write-RspAscii (Join-Path $d 'args.rsp') @('/nologo /c @inner.rsp /DFOO=9 /Fon.obj probe.c')
$null = Invoke-Probe -Id 'rsp-nested-at' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'A response file containing `@inner.rsp`. If FROMINNER is NOT seen, a wrapper must expand exactly one level. If it IS seen, msvc.md §11 is wrong for this toolset.'

# --- 9. a relative path with a directory component.
$d = New-RspCase 'relative-path'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'sub') | Out-Null
Write-RspAscii (Join-Path $d 'sub\args.rsp') @('/nologo /c /DFOO=3 /Forel.obj probe.c')
$null = Invoke-Probe -Id 'rsp-relative-path' -Exe $cl -CmdArgs @('@sub\args.rsp') -WorkDir $d -Comment `
    'msvc.md §11: relative response-file paths resolve against the cwd. Does `probe.c` inside it also resolve against the cwd rather than the rsp''s directory?'

# --- 10. UTF-16LE with a BOM, and UTF-16BE with a BOM.
$d = New-RspCase 'utf16le'
[System.IO.File]::WriteAllText((Join-Path $d 'args.rsp'), "/nologo /c /DFOO=16 /Fole.obj probe.c`r`n", (New-Object System.Text.UnicodeEncoding($false, $true)))
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $d 'args.rsp'))
Add-HexDump -Bytes $bytes -Caption 'args.rsp bytes (UTF-16LE with BOM)' -Max 96
$null = Invoke-Probe -Id 'rsp-utf16le-bom' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d

$d = New-RspCase 'utf16be'
[System.IO.File]::WriteAllText((Join-Path $d 'args.rsp'), "/nologo /c /DFOO=17 /Fobe.obj probe.c`r`n", (New-Object System.Text.UnicodeEncoding($true, $true)))
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $d 'args.rsp'))
Add-HexDump -Bytes $bytes -Caption 'args.rsp bytes (UTF-16BE with BOM)' -Max 96
$null = Invoke-Probe -Id 'rsp-utf16be-bom' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d -Comment `
    'Big-endian. buildcache''s resolve_args accepts both FF FE and FE FF.'

# --- 11. UTF-8 with a BOM, which no cache implementation mentions.
$d = New-RspCase 'utf8bom'
[System.IO.File]::WriteAllText((Join-Path $d 'args.rsp'), "/nologo /c /DFOO=8 /Fou8.obj probe.c`r`n", (New-Object System.Text.UTF8Encoding($true)))
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $d 'args.rsp'))
Add-HexDump -Bytes $bytes -Caption 'args.rsp bytes (UTF-8 with BOM)' -Max 96
$null = Invoke-Probe -Id 'rsp-utf8-bom' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d

# --- 12. a nonexistent response file.
$d = New-RspCase 'missing-rsp'
$null = Invoke-Probe -Id 'rsp-missing' -Exe $cl -CmdArgs @('@nosuch.rsp') -WorkDir $d -Comment `
    'An unopenable response file. gcc leaves such an argument verbatim; what does cl do?'

# --------------------------------------------------------------- CL and _CL_
Add-Note '## The `CL` and `_CL_` environment variables'
Add-Note ''

$d = New-RspCase 'CL-env'
$null = Invoke-Probe -Id 'env-none' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fonone.obj', 'probe.c') -WorkDir $d -Comment `
    'Baseline with neither variable set.'

$null = Invoke-Probe -Id 'env-CL-define' -Exe $cl -CmdArgs @('/nologo', '/c', '/Focl.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ CL = '/DFOO=fromCL' } -Comment `
    'CL=/DFOO=fromCL with FOO absent from argv. If the message appears, argv alone does not describe the compile.'

$null = Invoke-Probe -Id 'env-_CL_-define' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fouscl.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ _CL_ = '/DBAR=fromUnderscoreCL' } -Comment `
    '_CL_=/DBAR=fromUnderscoreCL -- the APPENDED variable.'

$null = Invoke-Probe -Id 'env-CL-precedence' -Exe $cl -CmdArgs @('/nologo', '/c', '/DVAL=fromArgv', '/Foprec.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ CL = '/DVAL=fromCL' } -Comment `
    'CL and argv both define VAL. CL is documented as PREPENDED, so argv should win the last-wins race.'

$null = Invoke-Probe -Id 'env-_CL_-precedence' -Exe $cl -CmdArgs @('/nologo', '/c', '/DVAL=fromArgv', '/Foprec2.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ _CL_ = '/DVAL=fromUnderscoreCL' } -Comment `
    '_CL_ is APPENDED, so it should win over argv.'

$null = Invoke-Probe -Id 'env-CL-both' -Exe $cl -CmdArgs @('/nologo', '/c', '/DVAL=fromArgv', '/Foboth.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ CL = '/DVAL=fromCL'; _CL_ = '/DVAL=fromUnderscoreCL' } -Comment `
    'Both set plus argv: the full ordering in one shot.'

# --- CL carrying a flag that changes the OUTPUT SET, not just the key. This is
#     the case msvc.md §8 uses to argue for a bypass rather than a hash.
$d2 = New-RspCase 'CL-env-Zi'
$null = Invoke-Probe -Id 'env-CL-carries-Zi' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fozi.obj', 'probe.c') -WorkDir $d2 `
    -EnvVars @{ CL = '/Zi' } -Comment `
    'CL=/Zi with no debug flag in argv. If a .pdb appears, an env-var STRING hash (buildcache) would key it correctly but would never classify it as a PDB bypass.'
Add-DirListing $d2

# --- does CL apply on top of a response file too?
$d3 = New-RspCase 'CL-with-rsp'
Write-RspAscii (Join-Path $d3 'args.rsp') @('/nologo /c /Forsp.obj probe.c')
$null = Invoke-Probe -Id 'env-CL-plus-rsp' -Exe $cl -CmdArgs @('@args.rsp') -WorkDir $d3 `
    -EnvVars @{ CL = '/DFOO=clPlusRsp' } -Comment `
    'CL set and the command line is nothing but @args.rsp.'

# --- can CL itself name a response file?
$d4 = New-RspCase 'CL-names-rsp'
Write-RspAscii (Join-Path $d4 'extra.rsp') @('/DFOO=fromClRsp')
$null = Invoke-Probe -Id 'env-CL-names-rsp' -Exe $cl -CmdArgs @('/nologo', '/c', '/Foclrsp.obj', 'probe.c') -WorkDir $d4 `
    -EnvVars @{ CL = '@extra.rsp' } -Comment `
    'CL=@extra.rsp. A third expansion site nobody documents.'

# --- an empty CL: is "set but empty" different from unset?
$null = Invoke-Probe -Id 'env-CL-empty' -Exe $cl -CmdArgs @('/nologo', '/c', '/Foempty.obj', 'probe.c') -WorkDir $d `
    -EnvVars @{ CL = '' } -Comment `
    'CL set to the empty string. On Windows an environment variable set to "" is indistinguishable from an unset one -- the harness''s Set-ProbeEnv therefore removes it, which is the only thing "empty" can mean here. The result is the baseline, and that IS the finding.'
