# Probe family 1 -- cl.exe identity.
#
# What msvc.md leans on:
#   §9  "The version banner appears on stderr: buildcache's get_program_id runs
#        bare cl.exe and reads result.std_err, throwing if it is empty."
#   §9  "cl.exe writes the source filename to stdout on every compile."
#   §14 "/nologo -> hash-verbatim. Changes stdout, which is cached."
# A cache derives the tool identity from this, so the exact stream, the exact
# bytes and the exit code all matter.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p01-identity' -Title 'Probe 1: cl.exe identity, banner, stream and exit code'

$cl = (Get-Command cl.exe).Source
Add-Note "cl.exe resolved to ``$cl``"
Add-Note ""

$w = New-Scratch 'p01'
Write-Source (Join-Path $w 'foo.c') @"
int foo(void) { return 42; }
"@

# --- bare cl, no arguments: the buildcache get_program_id call shape.
$bare = Invoke-Probe -Id 'bare-cl' -Exe $cl -WorkDir $w -Comment `
    'Bare `cl.exe`, no arguments. buildcache''s get_program_id runs exactly this and reads std_err.'
Add-HexDump -Bytes $bare.ErrBytes -Caption 'stderr bytes, verbatim'
Add-HexDump -Bytes $bare.OutBytes -Caption 'stdout bytes, verbatim'

# --- bare cl with /nologo: does the banner go away, and what is left?
$null = Invoke-Probe -Id 'bare-cl-nologo' -Exe $cl -CmdArgs @('/nologo') -WorkDir $w -Comment `
    'Does /nologo suppress the banner on the no-input error path?'

# --- /Bv: the full tool-chain component version list.
$bv = Invoke-Probe -Id 'cl-Bv' -Exe $cl -CmdArgs @('/Bv') -WorkDir $w -Comment `
    '/Bv prints the version of every compiler component. A candidate tool-identity source.'
Add-HexDump -Bytes $bv.OutBytes -Caption 'stdout bytes, verbatim' -Max 1024
Add-HexDump -Bytes $bv.ErrBytes -Caption 'stderr bytes, verbatim' -Max 1024

$null = Invoke-Probe -Id 'cl-Bv-nologo' -Exe $cl -CmdArgs @('/nologo', '/Bv') -WorkDir $w

# --- a normal /c compile: the source-filename line on stdout.
$c1 = Invoke-Probe -Id 'compile-plain' -Exe $cl -CmdArgs @('/c', 'foo.c') -WorkDir $w -Comment `
    'A normal compile with no /nologo: banner plus the source filename line.'
Add-HexDump -Bytes $c1.OutBytes -Caption 'stdout bytes, verbatim'
Add-HexDump -Bytes $c1.ErrBytes -Caption 'stderr bytes, verbatim'

$c2 = Invoke-Probe -Id 'compile-nologo' -Exe $cl -CmdArgs @('/nologo', '/c', 'foo.c') -WorkDir $w -Comment `
    'The same compile with /nologo. Is the `foo.c` line still there?'
Add-HexDump -Bytes $c2.OutBytes -Caption 'stdout bytes, verbatim'
Add-HexDump -Bytes $c2.ErrBytes -Caption 'stderr bytes, verbatim'

# --- the same source under a different name and a directory prefix: is the
#     stdout line the argv spelling or the basename? A cache replays this line,
#     so which one it is decides whether the line is a function of argv.
New-Item -ItemType Directory -Force -Path (Join-Path $w 'sub') | Out-Null
Write-Source (Join-Path $w 'sub\bar.c') "int bar(void) { return 7; }`n"
$null = Invoke-Probe -Id 'compile-subdir-relpath' -Exe $cl -CmdArgs @('/nologo', '/c', 'sub\bar.c') -WorkDir $w -Comment `
    'Relative path with a directory component: does stdout echo `sub\bar.c` or `bar.c`?'
$null = Invoke-Probe -Id 'compile-abspath' -Exe $cl -CmdArgs @('/nologo', '/c', (Join-Path $w 'sub\bar.c')) -WorkDir $w -Comment `
    'Absolute path: does stdout echo the whole absolute path? (It decides whether the replayed stdout leaks another workspace''s paths.)'

# --- two sources without /c: does each get its own stdout line?
Write-Source (Join-Path $w 'baz.c') "int baz(void) { return 1; }`n"
$null = Invoke-Probe -Id 'compile-two-sources' -Exe $cl -CmdArgs @('/nologo', '/c', 'foo.c', 'baz.c') -WorkDir $w -Comment `
    'Two sources under /c: one stdout line each, in argv order?'

# --- /? and version-only spellings a wrapper might use for identity.
$null = Invoke-Probe -Id 'cl-help' -Exe $cl -CmdArgs @('/help') -WorkDir $w -Comment `
    '/help, truncated in the capture only by cl itself.'

Add-DirListing $w

Add-Note '## Environment recorded for this family'
Add-Note ''
Add-Note '```'
foreach ($n in @('VCToolsVersion', 'VCToolsInstallDir', 'VCINSTALLDIR', 'VisualStudioVersion', 'VSCMD_VER', 'Platform', 'VSLANG')) {
    $v = [System.Environment]::GetEnvironmentVariable($n)
    Add-Note ("{0}={1}" -f $n, $v)
}
Add-Note ("ANSICodePage={0}" -f [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
Add-Note ("OEMCodePage={0}" -f [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
Add-Note ("CurrentCulture={0}" -f [System.Globalization.CultureInfo]::CurrentCulture.Name)
Add-Note '```'
