# Probe family 6 -- precompiled headers.
#
# What msvc.md leans on:
#   §6  "/Yc[header] -- create a PCH. Output is the .pch named by /Fp, else
#        derived from the /Yc header name, else the source basename + .pch."
#   §6  "/Yu[header] -- use a PCH. The .pch is an input whose content must be in
#        the key ... mixing objects built against different PCHs produces
#        LNK4206 at link time."
#   §14 "/Yc ... Path resolution order: /Fp -> <h> with .pch -> source basename."
#
# The stale-PCH error text and exit code are what a wrapper must recognise, so
# they are captured verbatim.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p06-pch' -Title 'Probe 6: /Yc, /Yu, /Fp, and the missing / stale .pch'

$cl = (Get-Command cl.exe).Source

function New-PchCase {
    param([string]$Name, [string]$HeaderBody = "#pragma once`nstatic const int pch_v = 1;`n")
    $d = New-Scratch "p06-$Name"
    Write-Source (Join-Path $d 'pch.h') $HeaderBody
    Write-Source (Join-Path $d 'pch.cpp') "#include ""pch.h""`n"
    Write-Source (Join-Path $d 'use.cpp') "#include ""pch.h""`nint use_fn(void) { return pch_v; }`n"
    return $d
}

# --- 1. /Yc with an explicit /Fp.
$d = New-PchCase 'Yc-explicit-Fp'
$null = Invoke-Probe -Id 'Yc-with-Fp' -Exe $cl -CmdArgs @('/nologo', '/c', '/Ycpch.h', '/Fppch.pch', '/Fopch.obj', 'pch.cpp') -WorkDir $d -Comment `
    'Create the PCH with /Fp naming it. Note that /Yc emits BOTH a .pch and a .obj -- two outputs from one compile.'
Add-DirListing $d
$null = Invoke-Probe -Id 'Yu-with-Fp' -Exe $cl -CmdArgs @('/nologo', '/c', '/Yupch.h', '/Fppch.pch', '/Fouse.obj', 'use.cpp') -WorkDir $d -Comment `
    'Use it.'
Add-DirListing $d

# --- 2. /Yc with NO /Fp: what is the derived .pch name?
$d = New-PchCase 'Yc-no-Fp'
$null = Invoke-Probe -Id 'Yc-no-Fp' -Exe $cl -CmdArgs @('/nologo', '/c', '/Ycpch.h', '/Fopch.obj', 'pch.cpp') -WorkDir $d -Comment `
    'No /Fp. msvc.md §6 claims the name comes from the /Yc header name, else the source basename. Which is it?'
Add-DirListing $d

# --- 3. bare /Yc (no header name) -- the "first #include is the barrier" form.
$d = New-PchCase 'Yc-bare'
$null = Invoke-Probe -Id 'Yc-bare' -Exe $cl -CmdArgs @('/nologo', '/c', '/Yc', '/Fopch.obj', 'pch.cpp') -WorkDir $d -Comment `
    'Bare /Yc with no header name.'
Add-DirListing $d

# --- 4. /Yu against a MISSING .pch.
$d = New-PchCase 'Yu-missing'
$missing = Invoke-Probe -Id 'Yu-missing-pch' -Exe $cl -CmdArgs @('/nologo', '/c', '/Yupch.h', '/Fpnosuch.pch', '/Fouse.obj', 'use.cpp') -WorkDir $d -Comment `
    'The .pch named by /Fp does not exist. The exact error text and exit code are what a wrapper has to recognise.'
Add-DirListing $d

# --- 5. /Yu against a STALE .pch: build it, then change the header, then reuse.
$d = New-PchCase 'Yu-stale'
$null = Invoke-Probe -Id 'Yu-stale-create' -Exe $cl -CmdArgs @('/nologo', '/c', '/Ycpch.h', '/Fppch.pch', '/Fopch.obj', 'pch.cpp') -WorkDir $d
Write-Source (Join-Path $d 'pch.h') "#pragma once`nstatic const int pch_v = 2;`nstatic const int pch_extra = 3;`n"
$stale = Invoke-Probe -Id 'Yu-stale-use' -Exe $cl -CmdArgs @('/nologo', '/c', '/Yupch.h', '/Fppch.pch', '/Fouse.obj', 'use.cpp') -WorkDir $d -Comment `
    'pch.h was edited AFTER the .pch was built. Does cl detect it (C1859 / C4652), and with what exit code? This is the case that decides whether the .pch content must be in the key.'
Add-DirListing $d

# --- 6. a PCH built with DIFFERENT flags than the user: the LNK4206 setup.
#     Two .pch files from the same header, one /Z7 and one not, then one object
#     against each. The objects' bytes say whether the PCH identity is baked in.
$d = New-PchCase 'pch-identity-in-object'
$null = Invoke-Probe -Id 'pch-A-create' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Ycpch.h', '/FpA.pch', '/FopchA.obj', 'pch.cpp') -WorkDir $d
Copy-Item (Join-Path $d 'pch.h') (Join-Path $d 'pch.h.bak')
Write-Source (Join-Path $d 'pch.h') "#pragma once`nstatic const int pch_v = 1;`nstatic const int other = 99;`n"
$null = Invoke-Probe -Id 'pch-B-create' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Ycpch.h', '/FpB.pch', '/FopchB.obj', 'pch.cpp') -WorkDir $d
Copy-Item (Join-Path $d 'pch.h.bak') (Join-Path $d 'pch.h') -Force
$null = Invoke-Probe -Id 'pch-use-A' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Yupch.h', '/FpA.pch', '/FouseA.obj', 'use.cpp') -WorkDir $d
Write-Source (Join-Path $d 'pch.h') "#pragma once`nstatic const int pch_v = 1;`nstatic const int other = 99;`n"
$null = Invoke-Probe -Id 'pch-use-B' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Yupch.h', '/FpB.pch', '/FouseB.obj', 'use.cpp') -WorkDir $d
Add-DirListing $d
if ((Test-Path (Join-Path $d 'useA.obj')) -and (Test-Path (Join-Path $d 'useB.obj'))) {
    $ha = (Get-FileHash (Join-Path $d 'useA.obj') -Algorithm SHA256).Hash
    $hb = (Get-FileHash (Join-Path $d 'useB.obj') -Algorithm SHA256).Hash
    Add-Note '## Does the object differ when only the .pch behind it differs?'
    Add-Note ''
    Add-Note '```'
    Add-Note ("useA.obj (against A.pch) : {0}" -f $ha)
    Add-Note ("useB.obj (against B.pch) : {0}" -f $hb)
    Add-Note ("identical                : {0}" -f ($ha -eq $hb))
    Add-Note '```'
    Add-Note ''
    Add-Note 'If these differ while `use.cpp`''s own text and argv are identical, the `.pch` content is a genuine hash input and buildcache''s `get_hash_extra_content()` treatment is the correct one.'
    Add-Note ''
}

# --- 7. .pch size, which is the reason buildcache memoises the hash.
$pchFiles = Get-ChildItem -Path $script:ScratchRoot -Recurse -Filter '*.pch' -File -ErrorAction SilentlyContinue
Add-Note 'Every `.pch` written by this family, with its size (msvc.md §6: "a `.pch` is routinely 100-400 MB" -- these are minimal headers, so this is the FLOOR, not a typical project figure):'
Add-Note '```'
$rows = $pchFiles | Sort-Object FullName | ForEach-Object { "{0,12}  {1}" -f $_.Length, $_.FullName }
if (-not $rows) { $rows = @('(none)') }
Add-Note $rows
Add-Note '```'
Add-Note ''

# --- 8. a PCH over a real system header, for a realistic size figure.
$d = New-Scratch 'p06-big-pch'
Write-Source (Join-Path $d 'big.h') "#pragma once`n#include <windows.h>`n#include <vector>`n#include <string>`n#include <map>`n#include <algorithm>`n"
Write-Source (Join-Path $d 'big.cpp') "#include ""big.h""`n"
$null = Invoke-Probe -Id 'big-pch-create' -Exe $cl -CmdArgs @('/nologo', '/c', '/EHsc', '/Ycbig.h', '/Fpbig.pch', '/Fobig.obj', 'big.cpp') -WorkDir $d -Comment `
    'A PCH over windows.h plus five STL headers -- a realistic size for the memoisation argument.'
Add-DirListing $d

# --- 9. /Yu with no /Fp at all.
$d = New-PchCase 'Yu-no-Fp'
$null = Invoke-Probe -Id 'Yu-no-Fp-create' -Exe $cl -CmdArgs @('/nologo', '/c', '/Ycpch.h', '/Fopch.obj', 'pch.cpp') -WorkDir $d
$null = Invoke-Probe -Id 'Yu-no-Fp-use' -Exe $cl -CmdArgs @('/nologo', '/c', '/Yupch.h', '/Fouse.obj', 'use.cpp') -WorkDir $d -Comment `
    'Neither compile names /Fp. The resolution order in msvc.md §6 says the .pch name is derived the same way on both sides.'
Add-DirListing $d
