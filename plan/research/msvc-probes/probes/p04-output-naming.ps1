# Probe family 4 -- where the object actually lands.
#
# What msvc.md leans on:
#   §2  "Output: /Fo<path>. If /Fo names a directory (trailing \ or an existing
#        directory), the object name is derived from the source basename."
#   §14 "/Fo<p> | concat-colon | primary-output"
#   §14 "/Fe<p> /Fa<p> /Fi<p> /Fr<p> /FR<p> /Ft<p> /Fx /FA<x> -> bypass"
#   §3  "/MP ... with several sources it implies the multiple-source bypass"
#
# A cache that writes the object to the wrong place is worse than no cache, so
# every /Fo spelling gets its own clean directory and a full listing afterwards.

. "$PSScriptRoot\common.ps1"
Start-Family -Name 'p04-output-naming' -Title 'Probe 4: /Fo spellings, sibling outputs, /MP'

$cl = (Get-Command cl.exe).Source

function New-Case {
    param([string]$Name)
    $d = New-Scratch "p04-$Name"
    Write-Source (Join-Path $d 'foo.c') "int foo(void) { return 1; }`n"
    Write-Source (Join-Path $d 'bar.c') "int bar(void) { return 2; }`n"
    Write-Source (Join-Path $d 'baz.c') "int baz(void) { return 3; }`n"
    return $d
}

# --- 1. the default: /c foo.c with no /Fo.
$d = New-Case 'default'
$null = Invoke-Probe -Id 'default-no-Fo' -Exe $cl -CmdArgs @('/nologo', '/c', 'foo.c') -WorkDir $d -Comment `
    'No /Fo at all. msvc.md §13 says the object is foo.obj in the cwd.'
Add-DirListing $d

# --- 2. the default when the source is in a subdirectory: cwd or beside the source?
$d = New-Case 'default-subdir'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
Write-Source (Join-Path $d 'src\deep.c') "int deep(void) { return 4; }`n"
$null = Invoke-Probe -Id 'default-source-in-subdir' -Exe $cl -CmdArgs @('/nologo', '/c', 'src\deep.c') -WorkDir $d -Comment `
    'The source is in src\. Does deep.obj land in the cwd or in src\?'
Add-DirListing $d

# --- 3. every /Fo spelling.
$spellings = @(
    @{ id = 'Fo-concat-name';     args = @('/nologo', '/c', '/Foname.obj', 'foo.c');   note = '/Fo<name>: glued' },
    @{ id = 'Fo-colon-name';      args = @('/nologo', '/c', '/Fo:name.obj', 'foo.c');  note = '/Fo:<name>: the optional colon msvc.md calls `concat-colon`' },
    @{ id = 'Fo-dash-concat';     args = @('/nologo', '/c', '-Foname.obj', 'foo.c');   note = '-Fo<name>: the dash leader' },
    @{ id = 'Fo-separated';       args = @('/nologo', '/c', '/Fo', 'name.obj', 'foo.c'); note = '/Fo <name>: SEPARATED. msvc.md does NOT list /Fo as separable, so this should misparse. What does cl do with it?' },
    @{ id = 'Fo-dir-trailing';    args = @('/nologo', '/c', '/Foout\', 'foo.c');       note = '/Fo<dir>\ with the directory ALREADY EXISTING' },
    @{ id = 'Fo-dir-trailing-missing'; args = @('/nologo', '/c', '/Fomissing\', 'foo.c'); note = '/Fo<dir>\ where the directory does NOT exist. Does cl create it or fail?' },
    @{ id = 'Fo-dir-no-slash';    args = @('/nologo', '/c', '/Foout', 'foo.c');        note = '/Fo<dir> with NO trailing slash, directory existing. msvc.md says an existing directory also derives the name.' },
    @{ id = 'Fo-colon-dir';       args = @('/nologo', '/c', '/Fo:out\', 'foo.c');      note = '/Fo:<dir>\ -- the worked example in msvc.md §13' },
    @{ id = 'Fo-no-extension';    args = @('/nologo', '/c', '/Foname', 'foo.c');       note = '/Fo<name> with no extension and no such directory. Does cl append .obj?' },
    @{ id = 'Fo-other-extension'; args = @('/nologo', '/c', '/Foname.o', 'foo.c');     note = '/Fo<name>.o -- a non-.obj extension' },
    @{ id = 'Fo-twice';           args = @('/nologo', '/c', '/Fofirst.obj', '/Fosecond.obj', 'foo.c'); note = 'Two /Fo flags. Which wins, and is there a warning?' }
)
foreach ($s in $spellings) {
    $d = New-Case $s.id
    New-Item -ItemType Directory -Force -Path (Join-Path $d 'out') | Out-Null
    $null = Invoke-Probe -Id $s.id -Exe $cl -CmdArgs $s.args -WorkDir $d -Comment $s.note
    Add-DirListing $d
}

# --- 4. the sibling-output flags msvc.md §14 sends straight to bypass.
$siblings = @(
    @{ id = 'Fa-listing';      args = @('/nologo', '/c', '/Fafoo.asm', 'foo.c');  note = '/Fa: an assembly listing' },
    @{ id = 'FA-listing-flag'; args = @('/nologo', '/c', '/FAsc', 'foo.c');       note = '/FAsc: source+machine-code listing, name derived' },
    @{ id = 'Fm-map';          args = @('/nologo', '/c', '/Fmfoo.map', 'foo.c');  note = '/Fm under /c: the map file is a LINKER output. Does cl warn that the option is unused?' },
    @{ id = 'Fe-exe-with-c';   args = @('/nologo', '/c', '/Fefoo.exe', 'foo.c');  note = '/Fe under /c: an executable name with no link step' },
    @{ id = 'Fe-exe-no-c';     args = @('/nologo', '/Fefoo.exe', 'foo.c');        note = '/Fe with NO /c: a real link. This is the called_for_link shape.' },
    @{ id = 'Fi-preproc';      args = @('/nologo', '/P', '/Fifoo.i', 'foo.c');    note = '/Fi names the /P preprocessed output' },
    @{ id = 'FR-browse';       args = @('/nologo', '/c', '/FRfoo.sbr', 'foo.c');  note = '/FR: browse info' }
)
foreach ($s in $siblings) {
    $d = New-Case $s.id
    $null = Invoke-Probe -Id $s.id -Exe $cl -CmdArgs $s.args -WorkDir $d -Comment $s.note
    Add-DirListing $d
}

# --- 5. /MP with several sources, and /MP with one.
$d = New-Case 'MP-three'
$null = Invoke-Probe -Id 'MP-three-sources' -Exe $cl -CmdArgs @('/nologo', '/c', '/MP', 'foo.c', 'bar.c', 'baz.c') -WorkDir $d -Comment `
    '/MP with three sources. Note the stdout line ORDER -- with parallel compiles it need not match argv order, which matters for a wrapper that replays stdout.'
Add-DirListing $d

$d = New-Case 'MP-one'
$null = Invoke-Probe -Id 'MP-one-source' -Exe $cl -CmdArgs @('/nologo', '/c', '/MP', 'foo.c') -WorkDir $d -Comment `
    '/MP with a single source: msvc.md §3 calls this a no-op for the key.'
Add-DirListing $d

$d = New-Case 'MP-Fo-dir'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'obj') | Out-Null
$null = Invoke-Probe -Id 'MP-Fo-dir' -Exe $cl -CmdArgs @('/nologo', '/c', '/MP', '/Foobj\', 'foo.c', 'bar.c', 'baz.c') -WorkDir $d -Comment `
    'Three sources into one /Fo directory.'
Add-DirListing $d

# --- 6. several sources into ONE /Fo file: an error, or silent clobber?
$d = New-Case 'multi-one-Fo'
$null = Invoke-Probe -Id 'two-sources-one-Fo-file' -Exe $cl -CmdArgs @('/nologo', '/c', '/Foboth.obj', 'foo.c', 'bar.c') -WorkDir $d -Comment `
    'Two sources and a single /Fo FILE. Error D8036, or does the second object overwrite the first?'
Add-DirListing $d

# --- 7. /Tc and /Tp, which ccache marks TOO_HARD.
$d = New-Case 'Tc-Tp'
Write-Source (Join-Path $d 'plain.txt') "int from_txt(void) { return 8; }`n"
$null = Invoke-Probe -Id 'Tc-forces-c' -Exe $cl -CmdArgs @('/nologo', '/c', '/Tcplain.txt', '/Fotxt.obj') -WorkDir $d -Comment `
    '/Tc<file>: compile an arbitrary extension as C.'
$null = Invoke-Probe -Id 'Tp-forces-cpp' -Exe $cl -CmdArgs @('/nologo', '/c', '/Tpplain.txt', '/Fotxtpp.obj') -WorkDir $d -Comment `
    '/Tp<file>: the same file as C++.'
$null = Invoke-Probe -Id 'Tc-separated' -Exe $cl -CmdArgs @('/nologo', '/c', '/Tc', 'plain.txt', '/Fotxt2.obj') -WorkDir $d -Comment `
    '/Tc <file> separated: accepted?'
Add-DirListing $d

# --- 8. `--` before the source, which msvc.md §1 says disambiguates.
$d = New-Case 'double-dash'
$null = Invoke-Probe -Id 'double-dash-before-source' -Exe $cl -CmdArgs @('/nologo', '/c', '--', 'foo.c') -WorkDir $d -Comment `
    'msvc.md §1: "`--` before the source file is accepted". Is it?'
Add-DirListing $d

# --- 9. /Zs, which msvc.md §14 calls MSVC's -fsyntax-only.
$d = New-Case 'Zs'
$null = Invoke-Probe -Id 'Zs-syntax-only' -Exe $cl -CmdArgs @('/nologo', '/Zs', 'foo.c') -WorkDir $d -Comment `
    '/Zs: syntax check only. Does it write any file?'
Add-DirListing $d
