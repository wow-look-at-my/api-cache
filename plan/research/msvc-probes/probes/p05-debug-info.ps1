# Probe family 5 -- debug information and the PDB.
#
# What msvc.md leans on:
#   §3  "/Z7 debug info inside the .obj -- cacheable. /Zi debug info in a
#        separate shared .pdb -- bypass. /ZI /Zi plus edit-and-continue."
#   §3  "a .pdb is shared across every .obj in the project and is written by
#        several compiler processes serially (that is what /FS exists for)."
#   §3  "sccache appends .pdb if the /Fd value has no extension."
#   §14 "/Fd<p> ... the PDB. Passed through, never hashed."
#
# This is the single biggest MSVC-specific hazard in the plan, so it gets the
# most careful listing: every compile runs in its own clean directory and the
# directory is listed before and after.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p05-debug-info' -Title 'Probe 5: /Z7 vs /Zi vs /ZI, the shared PDB, /Fd naming'

$cl = (Get-Command cl.exe).Source

function New-DebugCase {
    param([string]$Name)
    $d = New-Scratch "p05-$Name"
    Write-Source (Join-Path $d 'a.c') "int a_fn(int x) { return x + 1; }`n"
    Write-Source (Join-Path $d 'b.c') "int b_fn(int x) { return x + 2; }`n"
    return $d
}

# --- /Z7: is the object really self-contained?
$d = New-DebugCase 'Z7'
$null = Invoke-Probe -Id 'Z7-single' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    '/Z7 on one source. msvc.md §3: cacheable, the object is self-contained. Is there ANY sibling file?'
Add-DirListing $d

$null = Invoke-Probe -Id 'Z7-second-source' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Fob.obj', 'b.c') -WorkDir $d -Comment `
    'A second /Z7 compile into the same directory. Still no shared file?'
Add-DirListing $d

# --- /Zi: the shared PDB. What is it called, and does a second compile mutate it?
$d = New-DebugCase 'Zi'
$null = Invoke-Probe -Id 'Zi-first' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    '/Zi with no /Fd. What is the default PDB name? (msvc.md §13 assumes vc143.pdb.)'
Add-DirListing $d -Caption 'after the FIRST /Zi compile'

$pdbs = Get-ChildItem -Path $d -Filter '*.pdb' -File
$pdbName = if ($pdbs) { $pdbs[0].Name } else { $null }
$hash1 = if ($pdbs) { (Get-FileHash $pdbs[0].FullName -Algorithm SHA256).Hash } else { $null }
$size1 = if ($pdbs) { $pdbs[0].Length } else { 0 }
$objA1 = (Get-FileHash (Join-Path $d 'a.obj') -Algorithm SHA256).Hash

$null = Invoke-Probe -Id 'Zi-second' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Fob.obj', 'b.c') -WorkDir $d -Comment `
    'A SECOND /Zi compile in the same directory, into the same default PDB. This is the accumulator msvc.md §3 describes.'
Add-DirListing $d -Caption 'after the SECOND /Zi compile'

$hash2 = if ($pdbName) { (Get-FileHash (Join-Path $d $pdbName) -Algorithm SHA256).Hash } else { $null }
$size2 = if ($pdbName) { (Get-Item (Join-Path $d $pdbName)).Length } else { 0 }
Add-Note '## Is the PDB an accumulator?'
Add-Note ''
Add-Note '```'
Add-Note ("default PDB name        : {0}" -f $pdbName)
Add-Note ("size after compile 1    : {0}" -f $size1)
Add-Note ("sha256 after compile 1  : {0}" -f $hash1)
Add-Note ("size after compile 2    : {0}" -f $size2)
Add-Note ("sha256 after compile 2  : {0}" -f $hash2)
Add-Note ("PDB changed by the second, unrelated compile: {0}" -f ($hash1 -ne $hash2))
Add-Note '```'
Add-Note ''

# --- order dependence: build the same two objects in the other order in a fresh
#     directory and compare the resulting PDB byte for byte.
$d2 = New-DebugCase 'Zi-reordered'
$null = Invoke-Probe -Id 'Zi-reordered-b-first' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Fob.obj', 'b.c') -WorkDir $d2
$null = Invoke-Probe -Id 'Zi-reordered-a-second' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Foa.obj', 'a.c') -WorkDir $d2
Add-DirListing $d2 -Caption 'after both compiles, b.c first'
if ($pdbName -and (Test-Path (Join-Path $d2 $pdbName))) {
    $hashR = (Get-FileHash (Join-Path $d2 $pdbName) -Algorithm SHA256).Hash
    $objA2 = (Get-FileHash (Join-Path $d2 'a.obj') -Algorithm SHA256).Hash
    Add-Note '```'
    Add-Note ("PDB sha256, a.c then b.c : {0}" -f $hash2)
    Add-Note ("PDB sha256, b.c then a.c : {0}" -f $hashR)
    Add-Note ("PDB is order-dependent   : {0}" -f ($hash2 -ne $hashR))
    Add-Note ("a.obj sha256, compiled 1st: {0}" -f $objA1)
    Add-Note ("a.obj sha256, compiled 2nd: {0}" -f $objA2)
    Add-Note ("the OBJECT is order-dependent under /Zi: {0}" -f ($objA1 -ne $objA2))
    Add-Note '```'
    Add-Note ''
}

# --- /Fd spellings.
$fdCases = @(
    @{ id = 'Fd-with-extension'; args = @('/nologo', '/c', '/Zi', '/Fdcustom.pdb', '/Foa.obj', 'a.c'); note = '/Fd<name>.pdb' },
    @{ id = 'Fd-no-extension';   args = @('/nologo', '/c', '/Zi', '/Fdcustom', '/Foa.obj', 'a.c');     note = '/Fd<name> with NO extension. msvc.md §3: "sccache appends .pdb if the /Fd value has no extension". Does cl?' },
    @{ id = 'Fd-colon';          args = @('/nologo', '/c', '/Zi', '/Fd:custom.pdb', '/Foa.obj', 'a.c'); note = '/Fd:<name> -- the colon form msvc.md §14 claims for /Fd' },
    @{ id = 'Fd-directory';      args = @('/nologo', '/c', '/Zi', '/Fdpdbs\', '/Foa.obj', 'a.c');      note = '/Fd<dir>\ with the directory existing' },
    @{ id = 'Fd-with-Z7';        args = @('/nologo', '/c', '/Z7', '/Fdignored.pdb', '/Foa.obj', 'a.c'); note = '/Fd together with /Z7. msvc.md §3: "the PDB path does not change the object under /Z7". Is a PDB even written?' }
)
foreach ($c in $fdCases) {
    $dd = New-DebugCase $c.id
    New-Item -ItemType Directory -Force -Path (Join-Path $dd 'pdbs') | Out-Null
    $null = Invoke-Probe -Id $c.id -Exe $cl -CmdArgs $c.args -WorkDir $dd -Comment $c.note
    Add-DirListing $dd
}

# --- Does /Fd change the OBJECT under /Z7? The no-hash claim rests on this.
$dz = New-DebugCase 'Z7-Fd-object-identity'
$null = Invoke-Probe -Id 'Z7-Fd-one' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Fdone.pdb', '/Foone.obj', 'a.c') -WorkDir $dz
$null = Invoke-Probe -Id 'Z7-Fd-two' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Fdtwo.pdb', '/Fotwo.obj', 'a.c') -WorkDir $dz
$h1 = (Get-FileHash (Join-Path $dz 'one.obj') -Algorithm SHA256).Hash
$h2 = (Get-FileHash (Join-Path $dz 'two.obj') -Algorithm SHA256).Hash
Add-Note '## Does /Fd change the object under /Z7? (ccache''s add_compiler_only_arg_no_hash rests on "no".)'
Add-Note ''
Add-Note '```'
Add-Note ("object with /Fdone.pdb : {0}" -f $h1)
Add-Note ("object with /Fdtwo.pdb : {0}" -f $h2)
Add-Note ("identical              : {0}" -f ($h1 -eq $h2))
Add-Note '```'
Add-Note ''
Add-DirListing $dz

# --- and under /Zi? (Same question, where the answer should differ.)
$dzi = New-DebugCase 'Zi-Fd-object-identity'
$null = Invoke-Probe -Id 'Zi-Fd-one' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Fdone.pdb', '/Foone.obj', 'a.c') -WorkDir $dzi
$null = Invoke-Probe -Id 'Zi-Fd-two' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Fdtwo.pdb', '/Fotwo.obj', 'a.c') -WorkDir $dzi
$i1 = (Get-FileHash (Join-Path $dzi 'one.obj') -Algorithm SHA256).Hash
$i2 = (Get-FileHash (Join-Path $dzi 'two.obj') -Algorithm SHA256).Hash
Add-Note '```'
Add-Note ("under /Zi, object with /Fdone.pdb : {0}" -f $i1)
Add-Note ("under /Zi, object with /Fdtwo.pdb : {0}" -f $i2)
Add-Note ("identical                         : {0}" -f ($i1 -eq $i2))
Add-Note '```'
Add-Note ''
# Does the object embed the PDB path as a string? grep the bytes.
foreach ($n in @('one', 'two')) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $dzi "$n.obj"))
    $txt = [System.Text.Encoding]::ASCII.GetString($bytes)
    $found = $txt.Contains("$n.pdb")
    Add-Note ('`' + $n + '.obj` contains the literal string `' + $n + '.pdb`: **' + $found + '**')
}
Add-Note ''
Add-DirListing $dzi

# --- /ZI: edit and continue.
$d = New-DebugCase 'ZI'
$null = Invoke-Probe -Id 'ZI-edit-continue' -Exe $cl -CmdArgs @('/nologo', '/c', '/ZI', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    '/ZI. msvc.md §3: "/Zi plus edit-and-continue; implies /FC". Which files appear? (.idb is the edit-and-continue state.)'
Add-DirListing $d

# --- /FS, and two concurrent /Zi compiles into one PDB.
$d = New-DebugCase 'FS'
$null = Invoke-Probe -Id 'Zi-FS' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/FS', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    '/FS: force synchronous PDB writes. msvc.md §3 calls it added-but-not-hashed.'
Add-DirListing $d

# --- the last-/Z-wins question ccache implements.
$d = New-DebugCase 'Z-last-wins'
$null = Invoke-Probe -Id 'Zi-then-Z7' -Exe $cl -CmdArgs @('/nologo', '/c', '/Zi', '/Z7', '/Foa.obj', 'a.c') -WorkDir $d -Comment `
    '/Zi /Z7 in that order. ccache records the LAST-seen /Z option. Is a PDB written? (If not, last-wins is confirmed.)'
Add-DirListing $d
$null = Invoke-Probe -Id 'Z7-then-Zi' -Exe $cl -CmdArgs @('/nologo', '/c', '/Z7', '/Zi', '/Fob.obj', 'b.c') -WorkDir $d -Comment `
    'The reverse order.'
Add-DirListing $d

# --- /Zi with NO /c: does the compile-and-link path behave differently? (Recorded
#     for completeness; a cache never sees this shape.)
$d = New-DebugCase 'Zi-link'
$null = Invoke-Probe -Id 'Zi-compile-and-link' -Exe $cl -CmdArgs @('/nologo', '/Zi', 'a.c', 'b.c', '/Feab.exe') -WorkDir $d
Add-DirListing $d
