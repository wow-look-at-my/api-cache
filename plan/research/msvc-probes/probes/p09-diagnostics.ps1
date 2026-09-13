# Probe family 9 -- diagnostics: format, stream, colour.
#
# What msvc.md leans on:
#   §9  "Diagnostics go to stdout too for cl.exe (warnings/errors are on stdout,
#        unlike gcc's stderr)."
#   §9  "stdout is not empty on success, so a cache that treats 'compiler
#        produced stdout' as a bypass will never cache MSVC at all."
#   §14 "/FC -- full paths in diagnostic messages. Implied by /ZI."
#
# A cache replays these bytes, so the stream, the path spelling inside the
# message and any escape sequence all have to be measured, not assumed.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p09-diagnostics' -Title 'Probe 9: warning/error format, which stream, /FC, /WX, colour'

$cl = (Get-Command cl.exe).Source
$d = New-Scratch 'p09'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'sub') | Out-Null

Write-Source (Join-Path $d 'warn.c') @"
int warn_fn(void)
{
	int unused_local;
	return 0;
}
"@
Write-Source (Join-Path $d 'err.c') @"
int err_fn(void)
{
	return nosuchsymbol + 1;
}
"@
Write-Source (Join-Path $d 'sub\deep.c') @"
int deep_fn(void)
{
	return nosuchsymbol;
}
"@
Write-Source (Join-Path $d 'hdr.h') "#pragma once`nstatic int hdr_unused(void) { int z; return 0; }`n"
Write-Source (Join-Path $d 'viahdr.c') "#include ""hdr.h""`nint viahdr_fn(void) { return hdr_unused(); }`n"

# --- a warning: which stream, what format?
$w = Invoke-Probe -Id 'warning-W4' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/Fowarn.obj', 'warn.c') -WorkDir $d -Comment `
    'C4101 (unreferenced local). msvc.md §9 says diagnostics are on STDOUT.'
Add-Note ("warning text on stdout: **{0}**  |  on stderr: **{1}**" -f ($w.Stdout -match 'warning C'), ($w.Stderr -match 'warning C'))
Add-Note ''
Add-HexDump -Bytes $w.OutBytes -Caption 'stdout bytes, verbatim' -Max 512
Add-HexDump -Bytes $w.ErrBytes -Caption 'stderr bytes, verbatim' -Max 512

# --- an error: same questions, plus the exit code.
$e = Invoke-Probe -Id 'error-C2065' -Exe $cl -CmdArgs @('/nologo', '/c', '/Foerr.obj', 'err.c') -WorkDir $d -Comment `
    'C2065 (undeclared identifier).'
Add-Note ("error text on stdout: **{0}**  |  on stderr: **{1}**" -f ($e.Stdout -match 'error C'), ($e.Stderr -match 'error C'))
Add-Note ''
Add-HexDump -Bytes $e.OutBytes -Caption 'stdout bytes, verbatim' -Max 512
Add-HexDump -Bytes $e.ErrBytes -Caption 'stderr bytes, verbatim' -Max 512

# --- the path spelling in a message: relative argv, relative subdir, absolute.
$null = Invoke-Probe -Id 'error-path-relative-subdir' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fodeep.obj', 'sub\deep.c') -WorkDir $d -Comment `
    'The source is named relatively. Is the path in the message the argv spelling?'
$null = Invoke-Probe -Id 'error-path-absolute-argv' -Exe $cl -CmdArgs @('/nologo', '/c', '/Fodeep2.obj', (Join-Path $d 'sub\deep.c')) -WorkDir $d -Comment `
    'The source is named absolutely. A cache replaying this stdout would replay another workspace''s absolute path.'
$null = Invoke-Probe -Id 'error-path-FC' -Exe $cl -CmdArgs @('/nologo', '/c', '/FC', '/Fodeep3.obj', 'sub\deep.c') -WorkDir $d -Comment `
    '/FC with a RELATIVE argv spelling: msvc.md §14 says /FC forces full paths, which makes the diagnostic a function of the cwd.'

# --- a diagnostic that originates in a header.
$null = Invoke-Probe -Id 'warning-from-header' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/Fovh.obj', 'viahdr.c') -WorkDir $d -Comment `
    'The warning is reported against hdr.h, not against the .c. Note whether cl prints an additional "see reference" line.'

# --- /WX.
$null = Invoke-Probe -Id 'WX-turns-warning-into-error' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/WX', '/Fowx.obj', 'warn.c') -WorkDir $d
$null = Invoke-Probe -Id 'WX-minus' -Exe $cl -CmdArgs @('/nologo', '/c', '/W4', '/WX-', '/Fowxm.obj', 'warn.c') -WorkDir $d -Comment `
    '/WX- is what sccache adds to its own preprocessing run (msvc.md §5, sccache #1725/#2250).'

# --- C4668 during preprocessing: the reason sccache adds /WX-.
Write-Source (Join-Path $d 'c4668.c') @"
#if SOME_UNDEFINED_MACRO
#endif
int c4668_fn(void) { return 0; }
"@
$null = Invoke-Probe -Id 'C4668-compile' -Exe $cl -CmdArgs @('/nologo', '/c', '/Wall', '/Fo4668.obj', 'c4668.c') -WorkDir $d -Comment `
    'C4668 (undefined macro replaced with 0 in #if) during a normal compile under /Wall.'
$null = Invoke-Probe -Id 'C4668-preprocess-E' -Exe $cl -CmdArgs @('/nologo', '/E', '/Wall', 'c4668.c') -WorkDir $d -Comment `
    'The same under /E. Does the warning appear on the preprocessing run but not the compile? That is the asymmetry sccache works around.'
$null = Invoke-Probe -Id 'C4668-preprocess-E-WXminus' -Exe $cl -CmdArgs @('/nologo', '/E', '/Wall', '/WX-', 'c4668.c') -WorkDir $d

# --- /diagnostics:*
foreach ($mode in @('classic', 'column', 'caret')) {
    $null = Invoke-Probe -Id "diagnostics-$mode" -Exe $cl -CmdArgs @('/nologo', '/c', "/diagnostics:$mode", "/Fod-$mode.obj", 'err.c') -WorkDir $d -Comment `
        "/diagnostics:$mode"
}

# --- colour. cl has no documented colour switch; these record what it does with
#     one, and whether any ESC byte reaches a redirected stream.
$colourProbes = @(
    @{ id = 'diagnostics-color';        args = @('/nologo', '/c', '/diagnostics:color', '/Foc1.obj', 'err.c'); note = '/diagnostics:color -- does cl know it?' },
    @{ id = 'fdiagnostics-color';       args = @('/nologo', '/c', '-fdiagnostics-color', '/Foc2.obj', 'err.c'); note = 'the gcc spelling' },
    @{ id = 'fcolor-diagnostics';       args = @('/nologo', '/c', '-fcolor-diagnostics', '/Foc3.obj', 'err.c'); note = 'the clang spelling' }
)
foreach ($c in $colourProbes) {
    $r = Invoke-Probe -Id $c.id -Exe $cl -CmdArgs $c.args -WorkDir $d -Comment $c.note
    Add-Note ("ESC (0x1b) present -- stdout: **{0}**, stderr: **{1}**" -f (Test-HasEscape $r.OutBytes), (Test-HasEscape $r.ErrBytes))
    Add-Note ''
}

$plain = Invoke-Probe -Id 'colour-baseline-redirected' -Exe $cl -CmdArgs @('/nologo', '/c', '/Focb.obj', 'err.c') -WorkDir $d -Comment `
    'The baseline error with both streams redirected to files (never a console). Any ESC byte here would mean cl colours unconditionally.'
Add-Note ("ESC (0x1b) present -- stdout: **{0}**, stderr: **{1}**" -f (Test-HasEscape $plain.OutBytes), (Test-HasEscape $plain.ErrBytes))
Add-Note ''

# --- and through a PIPE rather than a file, which is what a wrapper actually
#     gives the child. cmd's `| more` keeps a pipe on stdout.
# The pipeline goes in a .cmd file rather than into -ArgumentList. .NET escapes
# an embedded double quote as \" when it builds the child command line, and
# cmd.exe does not understand that escape, so passing
# `/c "<quoted cl path>" ... | findstr` directly mangles the command. A batch
# file has no quoting round trip at all.
$pipeOut = Join-Path $script:Raw 'colour-through-pipe.stdout.txt'
$pipeErr = Join-Path $script:Raw 'colour-through-pipe.stderr.txt'
$pipeBat = Join-Path $d 'pipe.cmd'
# The pipe between cl and findstr is the measurement, so it stays. cmd writes
# the RESULT to files itself and reads stdin from NUL, so PowerShell holds no
# pipe of its own and an orphaned vctip cannot wedge the wait.
Set-Content -Path $pipeBat -Encoding ascii -Value @(
    '@echo off',
    ('"' + $cl + '" /nologo /c /Fopipe.obj err.c | findstr /n . > "' + $pipeOut + '" 2> "' + $pipeErr + '" < NUL')
)
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $pipeBat) -WorkingDirectory $d -NoNewWindow -PassThru
if (-not $p.WaitForExit($script:ProbeTimeoutMs)) { try { $p.Kill($true) } catch { }; throw 'colour-through-pipe probe TIMED OUT' }
Add-Note 'pipe.cmd:'
Add-Note '```'
Add-Note (Get-Content $pipeBat)
Add-Note '```'
Add-Note ''
$pb = Read-Bytes $pipeOut
Add-Note '### colour-through-pipe'
Add-Note ''
Add-Note 'cl''s stdout through a real anonymous pipe (`cl ... | findstr /n .`), which is the shape a wrapper creates:'
Add-Note '```'
Add-Note (Format-Block (ConvertFrom-AnsiBytes $pb))
Add-Note '```'
Add-Note ("exit code: {0}  |  ESC present: **{1}**" -f $p.ExitCode, (Test-HasEscape $pb))
Add-Note ''

# --- an unknown option: the D9002 shape a wrapper will meet constantly.
$null = Invoke-Probe -Id 'unknown-option' -Exe $cl -CmdArgs @('/nologo', '/c', '/ZzNotAnOption', '/Fou.obj', 'warn.c') -WorkDir $d -Comment `
    'An unknown option. Warning D9002, and does the compile still succeed?'

# --- a warning with /nologo absent, to see the full success-path stdout.
$null = Invoke-Probe -Id 'warning-with-banner' -Exe $cl -CmdArgs @('/c', '/W4', '/Fowb.obj', 'warn.c') -WorkDir $d -Comment `
    'Banner + source name + warning, all on one stream, in order. This is the byte sequence a cache has to store and replay.'

Add-DirListing $d
