# Probe 4: /Fo spellings, sibling outputs, /MP

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p04-output-naming/` in this artifact.

### default-no-Fo

No /Fo at all. msvc.md §13 says the object is foo.obj in the cwd.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c foo.c`
cwd: `C:\p\p04-default`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-default):
```
        28  bar.c
        28  baz.c
        28  foo.c
       575  foo.obj
```

### default-source-in-subdir

The source is in src\. Does deep.obj land in the cwd or in src\?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c src\deep.c`
cwd: `C:\p\p04-default-subdir`

exit code: **0**  |  stdout: 8 bytes  |  stderr: 0 bytes

stdout:
```
deep.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-default-subdir):
```
        28  bar.c
        28  baz.c
       583  deep.obj
        28  foo.c
        29  src\deep.c
```

### Fo-concat-name

/Fo<name>: glued

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foname.obj foo.c`
cwd: `C:\p\p04-Fo-concat-name`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-concat-name):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  name.obj
```

### Fo-colon-name

/Fo:<name>: the optional colon msvc.md calls `concat-colon`

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fo:name.obj foo.c`
cwd: `C:\p\p04-Fo-colon-name`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-colon-name):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  name.obj
```

### Fo-dash-concat

-Fo<name>: the dash leader

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c -Foname.obj foo.c`
cwd: `C:\p\p04-Fo-dash-concat`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-dash-concat):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  name.obj
```

### Fo-separated

/Fo <name>: SEPARATED. msvc.md does NOT list /Fo as separable, so this should misparse. What does cl do with it?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fo name.obj foo.c`
cwd: `C:\p\p04-Fo-separated`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 66 bytes

stdout:
```
foo.c
```

stderr:
```
cl : Command line warning D9027 : source file 'name.obj' ignored
```

files on disk after the run (C:\p\p04-Fo-separated):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  foo.obj
```

### Fo-dir-trailing

/Fo<dir>\ with the directory ALREADY EXISTING

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foout\ foo.c`
cwd: `C:\p\p04-Fo-dir-trailing`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-dir-trailing):
```
        28  bar.c
        28  baz.c
        28  foo.c
       587  out\foo.obj
```

### Fo-dir-trailing-missing

/Fo<dir>\ where the directory does NOT exist. Does cl create it or fail?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fomissing\ foo.c`
cwd: `C:\p\p04-Fo-dir-trailing-missing`

exit code: **1**  |  stdout: 183 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
C:\p\p04-Fo-dir-trailing-missing\foo.c : fatal error C1083: Cannot open compiler generated file: 'C:\p\p04-Fo-dir-trailing-missing\missing\foo.obj': No such file or directory
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-dir-trailing-missing):
```
        28  bar.c
        28  baz.c
        28  foo.c
```

### Fo-dir-no-slash

/Fo<dir> with NO trailing slash, directory existing. msvc.md says an existing directory also derives the name.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foout foo.c`
cwd: `C:\p\p04-Fo-dir-no-slash`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-dir-no-slash):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  out.obj
```

### Fo-colon-dir

/Fo:<dir>\ -- the worked example in msvc.md §13

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fo:out\ foo.c`
cwd: `C:\p\p04-Fo-colon-dir`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-colon-dir):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  out\foo.obj
```

### Fo-no-extension

/Fo<name> with no extension and no such directory. Does cl append .obj?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foname foo.c`
cwd: `C:\p\p04-Fo-no-extension`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-no-extension):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  name.obj
```

### Fo-other-extension

/Fo<name>.o -- a non-.obj extension

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foname.o foo.c`
cwd: `C:\p\p04-Fo-other-extension`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fo-other-extension):
```
        28  bar.c
        28  baz.c
        28  foo.c
       583  name.o
```

### Fo-twice

Two /Fo flags. Which wins, and is there a warning?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fofirst.obj /Fosecond.obj foo.c`
cwd: `C:\p\p04-Fo-twice`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 82 bytes

stdout:
```
foo.c
```

stderr:
```
cl : Command line warning D9025 : overriding '/Fofirst.obj' with '/Fosecond.obj'
```

files on disk after the run (C:\p\p04-Fo-twice):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  second.obj
```

### Fa-listing

/Fa: an assembly listing

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fafoo.asm foo.c`
cwd: `C:\p\p04-Fa-listing`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fa-listing):
```
        28  bar.c
        28  baz.c
       310  foo.asm
        28  foo.c
       575  foo.obj
```

### FA-listing-flag

/FAsc: source+machine-code listing, name derived

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /FAsc foo.c`
cwd: `C:\p\p04-FA-listing-flag`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-FA-listing-flag):
```
        28  bar.c
        28  baz.c
        28  foo.c
       384  foo.cod
       583  foo.obj
```

### Fm-map

/Fm under /c: the map file is a LINKER output. Does cl warn that the option is unused?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fmfoo.map foo.c`
cwd: `C:\p\p04-Fm-map`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fm-map):
```
        28  bar.c
        28  baz.c
        28  foo.c
       571  foo.obj
```

### Fe-exe-with-c

/Fe under /c: an executable name with no link step

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fefoo.exe foo.c`
cwd: `C:\p\p04-Fe-exe-with-c`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fe-exe-with-c):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  foo.obj
```

### Fe-exe-no-c

/Fe with NO /c: a real link. This is the called_for_link shape.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /Fefoo.exe foo.c`
cwd: `C:\p\p04-Fe-exe-no-c`

exit code: **2**  |  stdout: 64 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
LINK : fatal error LNK1561: entry point must be defined
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Fe-exe-no-c):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  foo.obj
```

### Fi-preproc

/Fi names the /P preprocessed output

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /P /Fifoo.i foo.c`
cwd: `C:\p\p04-Fi-preproc`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 7 bytes

stdout:
```
(empty)
```

stderr:
```
foo.c
```

files on disk after the run (C:\p\p04-Fi-preproc):
```
        28  bar.c
        28  baz.c
        28  foo.c
        46  foo.i
```

### FR-browse

/FR: browse info

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /FRfoo.sbr foo.c`
cwd: `C:\p\p04-FR-browse`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-FR-browse):
```
        28  bar.c
        28  baz.c
        28  foo.c
       575  foo.obj
        81  foo.sbr
```

### MP-three-sources

/MP with three sources. Note the stdout line ORDER -- with parallel compiles it need not match argv order, which matters for a wrapper that replays stdout.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /MP foo.c bar.c baz.c`
cwd: `C:\p\p04-MP-three`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
bar.c
baz.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-MP-three):
```
        28  bar.c
       575  bar.obj
        28  baz.c
       575  baz.obj
        28  foo.c
       575  foo.obj
```

### MP-one-source

/MP with a single source: msvc.md §3 calls this a no-op for the key.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /MP foo.c`
cwd: `C:\p\p04-MP-one`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-MP-one):
```
        28  bar.c
        28  baz.c
        28  foo.c
       571  foo.obj
```

### MP-Fo-dir

Three sources into one /Fo directory.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /MP /Foobj\ foo.c bar.c baz.c`
cwd: `C:\p\p04-MP-Fo-dir`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
bar.c
baz.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-MP-Fo-dir):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  obj\bar.obj
       579  obj\baz.obj
       579  obj\foo.obj
```

### two-sources-one-Fo-file

Two sources and a single /Fo FILE. Error D8036, or does the second object overwrite the first?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foboth.obj foo.c bar.c`
cwd: `C:\p\p04-multi-one-Fo`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 86 bytes

stdout:
```
(empty)
```

stderr:
```
cl : Command line error D8036 : '/Foboth.obj' not allowed with multiple source files
```

files on disk after the run (C:\p\p04-multi-one-Fo):
```
        28  bar.c
        28  baz.c
        28  foo.c
```

### Tc-forces-c

/Tc<file>: compile an arbitrary extension as C.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Tcplain.txt /Fotxt.obj`
cwd: `C:\p\p04-Tc-Tp`

exit code: **0**  |  stdout: 11 bytes  |  stderr: 0 bytes

stdout:
```
plain.txt
```

stderr:
```
(empty)
```

### Tp-forces-cpp

/Tp<file>: the same file as C++.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Tpplain.txt /Fotxtpp.obj`
cwd: `C:\p\p04-Tc-Tp`

exit code: **0**  |  stdout: 11 bytes  |  stderr: 0 bytes

stdout:
```
plain.txt
```

stderr:
```
(empty)
```

### Tc-separated

/Tc <file> separated: accepted?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Tc plain.txt /Fotxt2.obj`
cwd: `C:\p\p04-Tc-Tp`

exit code: **0**  |  stdout: 11 bytes  |  stderr: 0 bytes

stdout:
```
plain.txt
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Tc-Tp):
```
        28  bar.c
        28  baz.c
        28  foo.c
        33  plain.txt
       571  txt.obj
       571  txt2.obj
       592  txtpp.obj
```

### double-dash-before-source

msvc.md §1: "`--` before the source file is accepted". Is it?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c -- foo.c`
cwd: `C:\p\p04-double-dash`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 64 bytes

stdout:
```
foo.c
```

stderr:
```
cl : Command line warning D9002 : ignoring unknown option '--'
```

files on disk after the run (C:\p\p04-double-dash):
```
        28  bar.c
        28  baz.c
        28  foo.c
       579  foo.obj
```

### Zs-syntax-only

/Zs: syntax check only. Does it write any file?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /Zs foo.c`
cwd: `C:\p\p04-Zs`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p04-Zs):
```
        28  bar.c
        28  baz.c
        28  foo.c
```

