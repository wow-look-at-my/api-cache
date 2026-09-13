# Probe 9: warning/error format, which stream, /FC, /WX, colour

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p09-diagnostics/` in this artifact.

### warning-W4

C4101 (unreferenced local). msvc.md §9 says diagnostics are on STDOUT.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /Fowarn.obj warn.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

warning text on stdout: **False**  |  on stderr: **False**

stdout bytes, verbatim: (empty)

stderr bytes, verbatim: (empty)

### error-C2065

C2065 (undeclared identifier).

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foerr.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

error text on stdout: **False**  |  on stderr: **False**

stdout bytes, verbatim: (empty)

stderr bytes, verbatim: (empty)

### error-path-relative-subdir

The source is named relatively. Is the path in the message the argv spelling?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fodeep.obj sub\deep.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### error-path-absolute-argv

The source is named absolutely. A cache replaying this stdout would replay another workspace's absolute path.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fodeep2.obj C:\p\p09\sub\deep.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### error-path-FC

/FC with a RELATIVE argv spelling: msvc.md §14 says /FC forces full paths, which makes the diagnostic a function of the cwd.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /FC /Fodeep3.obj sub\deep.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### warning-from-header

The warning is reported against hdr.h, not against the .c. Note whether cl prints an additional "see reference" line.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /Fovh.obj viahdr.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### WX-turns-warning-into-error

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /WX /Fowx.obj warn.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### WX-minus

/WX- is what sccache adds to its own preprocessing run (msvc.md §5, sccache #1725/#2250).

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /WX- /Fowxm.obj warn.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### C4668-compile

C4668 (undefined macro replaced with 0 in #if) during a normal compile under /Wall.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Wall /Fo4668.obj c4668.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### C4668-preprocess-E

The same under /E. Does the warning appear on the preprocessing run but not the compile? That is the asymmetry sccache works around.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /E /Wall c4668.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 74 bytes  |  stderr: 0 bytes

stdout:
```
#line 1 "c4668.c"

#line 3 "c4668.c"
int c4668_fn(void) { return 0; }
```

stderr:
```
(empty)
```

### C4668-preprocess-E-WXminus

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /E /Wall /WX- c4668.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 74 bytes  |  stderr: 0 bytes

stdout:
```
#line 1 "c4668.c"

#line 3 "c4668.c"
int c4668_fn(void) { return 0; }
```

stderr:
```
(empty)
```

### diagnostics-classic

/diagnostics:classic

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /diagnostics:classic /Fod-classic.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### diagnostics-column

/diagnostics:column

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /diagnostics:column /Fod-column.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### diagnostics-caret

/diagnostics:caret

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /diagnostics:caret /Fod-caret.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### diagnostics-color

/diagnostics:color -- does cl know it?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /diagnostics:color /Foc1.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### fdiagnostics-color

the gcc spelling

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c -fdiagnostics-color /Foc2.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### fcolor-diagnostics

the clang spelling

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c -fcolor-diagnostics /Foc3.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### colour-baseline-redirected

The baseline error with both streams redirected to files (never a console). Any ESC byte here would mean cl colours unconditionally.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Focb.obj err.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

pipe.cmd:
```
@echo off
"C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe" /nologo /c /Fopipe.obj err.c | findstr /n . > "D:\a\api-cache\api-cache\plan\research\msvc-probes\ci-results\p09-diagnostics\colour-through-pipe.stdout.txt" 2> "D:\a\api-cache\api-cache\plan\research\msvc-probes\ci-results\p09-diagnostics\colour-through-pipe.stderr.txt" < NUL
```

### colour-through-pipe

cl's stdout through a real anonymous pipe (`cl ... | findstr /n .`), which is the shape a wrapper creates:
```
(empty)
```
exit code: 1  |  ESC present: **False**

### unknown-option

An unknown option. Warning D9002, and does the compile still succeed?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /ZzNotAnOption /Fou.obj warn.c`
cwd: `C:\p\p09`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### warning-with-banner

Banner + source name + warning, all on one stream, in order. This is the byte sequence a cache has to store and replay.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /c /W4 /Fowb.obj warn.c`
cwd: `C:\p\p09`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p09):
```
       564  4668.obj
        66  c4668.c
        49  err.c
        62  hdr.h
       395  pipe.cmd
        46  sub\deep.c
       943  vh.obj
        62  viahdr.c
        55  warn.c
       564  warn.obj
       560  wb.obj
       564  wxm.obj
```

