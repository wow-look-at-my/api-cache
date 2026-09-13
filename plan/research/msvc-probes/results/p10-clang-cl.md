# Probe 10: clang-cl -- /showIncludes, /Fo, /Zi, /sourceDependencies, colour

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p10-clang-cl/` in this artifact.

clang-cl resolved to `C:\Program Files\LLVM\bin\clang-cl.exe`

### clang-cl-version

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe --version`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 112 bytes  |  stderr: 0 bytes

stdout:
```
clang version 20.1.8
Target: x86_64-pc-windows-msvc
Thread model: posix
InstalledDir: C:\Program Files\LLVM\bin
```

stderr:
```
(empty)
```

### clang-cl-no-args

Bare clang-cl. buildcache's get_program_id reads stderr and THROWS if it is empty -- does clang-cl put anything there?

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe `
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 33 bytes

stdout:
```
(empty)
```

stderr:
```
clang-cl: error: no input files
```

stdout of --version, verbatim (112 bytes):
```
00000000  63 6c 61 6e 67 20 76 65 72 73 69 6f 6e 20 32 30  |clang version 20|
00000010  2e 31 2e 38 0a 54 61 72 67 65 74 3a 20 78 38 36  |.1.8.Target: x86|
00000020  5f 36 34 2d 70 63 2d 77 69 6e 64 6f 77 73 2d 6d  |_64-pc-windows-m|
00000030  73 76 63 0a 54 68 72 65 61 64 20 6d 6f 64 65 6c  |svc.Thread model|
00000040  3a 20 70 6f 73 69 78 0a 49 6e 73 74 61 6c 6c 65  |: posix.Installe|
00000050  64 44 69 72 3a 20 43 3a 5c 50 72 6f 67 72 61 6d  |dDir: C:\Program|
00000060  20 46 69 6c 65 73 5c 4c 4c 56 4d 5c 62 69 6e 0a  | Files\LLVM\bin.|
```

stderr of --version, verbatim: (empty)

### clang-cl-compile-plain

A plain compile with no /nologo. Does clang-cl print a banner or the source filename at all?

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /c /Foa.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

stdout bytes, verbatim: (empty)

stderr bytes, verbatim: (empty)

### clang-cl-compile-nologo

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Foa2.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### clang-cl-showincludes

The same include chain family 2 ran through cl.exe.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /c /I inc /showIncludes /Fosi.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 1059 bytes  |  stderr: 0 bytes

stdout:
```
Note: including file: .\inc/lvl1.h
Note: including file:  .\inc\lvl2.h
Note: including file: C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt\stdio.h
Note: including file:  C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt\corecrt.h
Note: including file:   C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vcruntime.h
Note: including file:    C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\sal.h
Note: including file:     C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\concurrencysal.h
Note: including file:    C:\Program Files\LLVM\lib\clang\20\include\vadefs.h
Note: including file:     C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vadefs.h
Note: including file:  C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt\corecrt_wstdio.h
Note: including file:   C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt\corecrt_stdio_config.h
```

stderr:
```
(empty)
```

notes on stdout: **True**  |  on stderr: **False**

Every include-note line, spaces rendered as `.`:
```
Note:.including.file:..\inc/lvl1.h
Note:.including.file:...\inc\lvl2.h
Note:.including.file:.C:\Program.Files.(x86)\Windows.Kits\10\include\10.0.26100.0\ucrt\stdio.h
Note:.including.file:..C:\Program.Files.(x86)\Windows.Kits\10\include\10.0.26100.0\ucrt\corecrt.h
Note:.including.file:...C:\Program.Files\Microsoft.Visual.Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vcruntime.h
Note:.including.file:....C:\Program.Files\Microsoft.Visual.Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\sal.h
Note:.including.file:.....C:\Program.Files\Microsoft.Visual.Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\concurrencysal.h
Note:.including.file:....C:\Program.Files\LLVM\lib\clang\20\include\vadefs.h
Note:.including.file:.....C:\Program.Files\Microsoft.Visual.Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vadefs.h
Note:.including.file:..C:\Program.Files.(x86)\Windows.Kits\10\include\10.0.26100.0\ucrt\corecrt_wstdio.h
Note:.including.file:...C:\Program.Files.(x86)\Windows.Kits\10\include\10.0.26100.0\ucrt\corecrt_stdio_config.h
```

### clang-cl-showincludes-user

/showIncludes:user -- msvc.md §12 says clang-cl supports it and that it lists project headers only.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /c /I inc /showIncludes:user /Fosiu.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 71 bytes  |  stderr: 0 bytes

stdout:
```
Note: including file: .\inc/lvl1.h
Note: including file:  .\inc\lvl2.h
```

stderr:
```
(empty)
```

### clang-cl-detect-invocation

sccache's detect_showincludes_prefix shape for a clang driver (refs/sccache/src/compiler/msvc.rs:197-206).

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe --driver-mode=cl -nologo -showIncludes -c -Fonul -I. -E test.c`
cwd: `C:\p\p10-detect`

exit code: **0**  |  stdout: 163 bytes  |  stderr: 126 bytes

stdout:
```
# 1 "test.c"
# 1 "<built-in>" 1
# 1 "<built-in>" 3
# 394 "<built-in>" 3
# 1 "<command line>" 1
# 1 "<built-in>" 2
# 1 "test.c" 2
# 1 ".\\test.h" 1
# 2 "test.c" 2
```

stderr:
```
clang-cl: warning: argument unused during compilation: '-c' [-Wunused-command-line-argument]
Note: including file: .\test.h
```

### clang-cl-detect-no-drivermode

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe -nologo -showIncludes -c -Fonul -I. -E test.c`
cwd: `C:\p\p10-detect`

exit code: **0**  |  stdout: 163 bytes  |  stderr: 126 bytes

stdout:
```
# 1 "test.c"
# 1 "<built-in>" 1
# 1 "<built-in>" 3
# 394 "<built-in>" 3
# 1 "<command line>" 1
# 1 "<built-in>" 2
# 1 "test.c" 2
# 1 ".\\test.h" 1
# 2 "test.c" 2
```

stderr:
```
clang-cl: warning: argument unused during compilation: '-c' [-Wunused-command-line-argument]
Note: including file: .\test.h
```

### clang-cl-sourcedependencies

Is the flag accepted, ignored with a warning, or an error? And is deps.json written?

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /I inc /sourceDependencies deps.json /Fosd.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 121 bytes

stdout:
```
(empty)
```

stderr:
```
clang-cl: warning: argument unused during compilation: '/sourceDependencies deps.json' [-Wunused-command-line-argument]
```

deps.json written: **False**

### clang-cl-MD-MF

-MD/-MF forwarded through /clang:. If this works, a wrapper need not synthesise the .d by hand for clang-cl.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /I inc /clang:-MD /clang:-MF /clang:a.d /Fomd.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

a.d, verbatim:
```make
md.obj: a.c inc\lvl1.h inc\lvl2.h \
  C:\Program\ Files\ (x86)\Windows\ Kits\10\include\10.0.26100.0\ucrt\stdio.h \
  C:\Program\ Files\ (x86)\Windows\ Kits\10\include\10.0.26100.0\ucrt\corecrt.h \
  C:\Program\ Files\Microsoft\ Visual\ Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vcruntime.h \
  C:\Program\ Files\Microsoft\ Visual\ Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\sal.h \
  C:\Program\ Files\Microsoft\ Visual\ Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\concurrencysal.h \
  C:\Program\ Files\LLVM\lib\clang\20\include\vadefs.h \
  C:\Program\ Files\Microsoft\ Visual\ Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include\vadefs.h \
  C:\Program\ Files\ (x86)\Windows\ Kits\10\include\10.0.26100.0\ucrt\corecrt_wstdio.h \
  C:\Program\ Files\ (x86)\Windows\ Kits\10\include\10.0.26100.0\ucrt\corecrt_stdio_config.h
```

### clang-cl-Fo-concat

/Fo<name>

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Foname.obj a.c`
cwd: `C:\p\p10-clang-cl-Fo-concat`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10-clang-cl-Fo-concat):
```
        81  a.c
        58  inc\lvl1.h
        40  inc\lvl2.h
      3403  name.obj
```

### clang-cl-Fo-colon

/Fo:<name> -- does clang-cl accept the colon form?

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Fo:colon.obj a.c`
cwd: `C:\p\p10-clang-cl-Fo-colon`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10-clang-cl-Fo-colon):
```
        81  a.c
      3403  colon.obj
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-Fo-dir

/Fo<dir>\ with the directory existing

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Foout\ a.c`
cwd: `C:\p\p10-clang-cl-Fo-dir`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10-clang-cl-Fo-dir):
```
        81  a.c
        58  inc\lvl1.h
        40  inc\lvl2.h
      3403  out\a.obj
```

### clang-cl-Fo-dir-missing

/Fo<dir>\ with the directory absent

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Fomissing\ a.c`
cwd: `C:\p\p10-clang-cl-Fo-dir-missing`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 100 bytes

stdout:
```
(empty)
```

stderr:
```
error: unable to open output file 'missing\a.obj': 'no such file or directory'
1 error generated.
```

files on disk after the run (C:\p\p10-clang-cl-Fo-dir-missing):
```
        81  a.c
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-Fo-separated

/Fo <name> separated

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Fo sep.obj a.c`
cwd: `C:\p\p10-clang-cl-Fo-separated`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 84 bytes

stdout:
```
(empty)
```

stderr:
```
clang-cl: warning: sep.obj: 'linker' input unused [-Wunused-command-line-argument]
```

files on disk after the run (C:\p\p10-clang-cl-Fo-separated):
```
        81  a.c
      3403  a.obj
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-Z7

clang-cl /Z7. If no .pdb appears, a blanket /Zi bypass costs clang-cl users every hit for nothing.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Z7 /Foa.obj a.c`
cwd: `C:\p\p10-clang-cl-Z7`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10-clang-cl-Z7):
```
        81  a.c
     11707  a.obj
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-Zi

clang-cl /Zi. If no .pdb appears, a blanket /Zi bypass costs clang-cl users every hit for nothing.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Zi /Foa.obj a.c`
cwd: `C:\p\p10-clang-cl-Zi`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10-clang-cl-Zi):
```
        81  a.c
     11707  a.obj
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-ZI

clang-cl /ZI. If no .pdb appears, a blanket /Zi bypass costs clang-cl users every hit for nothing.

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /ZI /Foa.obj a.c`
cwd: `C:\p\p10-clang-cl-ZI`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 95 bytes

stdout:
```
(empty)
```

stderr:
```
clang-cl: warning: argument unused during compilation: '/ZI' [-Wunused-command-line-argument]
```

files on disk after the run (C:\p\p10-clang-cl-ZI):
```
        81  a.c
      3403  a.obj
        58  inc\lvl1.h
        40  inc\lvl2.h
```

### clang-cl-colour-default

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Foe.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 173 bytes

stdout:
```
(empty)
```

stderr:
```
err.c(1,27): error: use of undeclared identifier 'nosuchsymbol'
    1 | int err_fn(void) { return nosuchsymbol; }
      |                           ^
1 error generated.
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### clang-cl-fcolor

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c -fcolor-diagnostics /Foe2.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 173 bytes

stdout:
```
(empty)
```

stderr:
```
err.c(1,27): error: use of undeclared identifier 'nosuchsymbol'
    1 | int err_fn(void) { return nosuchsymbol; }
      |                           ^
1 error generated.
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### clang-cl-fcolor-ansi

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c -fcolor-diagnostics -fansi-escape-codes /Foe3.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 252 bytes

stdout:
```
(empty)
```

stderr:
```
[1merr.c(1,27): [0m[0;1;31merror: [0m[1muse of undeclared identifier 'nosuchsymbol'[0m
    1 | [0;34mint[0m err_fn([0;34mvoid[0m) { [0;34mreturn[0m nosuchsymbol; }[0m
      | [0;1;32m                          ^
[0m1 error generated.
```

ESC (0x1b) present -- stdout: **False**, stderr: **True**

stderr bytes with the escapes (252 bytes):
```
00000000  1b 5b 31 6d 65 72 72 2e 63 28 31 2c 32 37 29 3a  |.[1merr.c(1,27):|
00000010  20 1b 5b 30 6d 1b 5b 30 3b 31 3b 33 31 6d 65 72  | .[0m.[0;1;31mer|
00000020  72 6f 72 3a 20 1b 5b 30 6d 1b 5b 31 6d 75 73 65  |ror: .[0m.[1muse|
00000030  20 6f 66 20 75 6e 64 65 63 6c 61 72 65 64 20 69  | of undeclared i|
00000040  64 65 6e 74 69 66 69 65 72 20 27 6e 6f 73 75 63  |dentifier 'nosuc|
00000050  68 73 79 6d 62 6f 6c 27 1b 5b 30 6d 0d 0a 20 20  |hsymbol'.[0m..  |
00000060  20 20 31 20 7c 20 1b 5b 30 3b 33 34 6d 69 6e 74  |  1 | .[0;34mint|
00000070  1b 5b 30 6d 20 65 72 72 5f 66 6e 28 1b 5b 30 3b  |.[0m err_fn(.[0;|
00000080  33 34 6d 76 6f 69 64 1b 5b 30 6d 29 20 7b 20 1b  |34mvoid.[0m) { .|
00000090  5b 30 3b 33 34 6d 72 65 74 75 72 6e 1b 5b 30 6d  |[0;34mreturn.[0m|
000000a0  20 6e 6f 73 75 63 68 73 79 6d 62 6f 6c 3b 20 7d  | nosuchsymbol; }|
000000b0  1b 5b 30 6d 0d 0a 20 20 20 20 20 20 7c 20 1b 5b  |.[0m..      | .[|
000000c0  30 3b 31 3b 33 32 6d 20 20 20 20 20 20 20 20 20  |0;1;32m         |
000000d0  20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20  |                |
000000e0  20 5e 0d 0a 1b 5b 30 6d 31 20 65 72 72 6f 72 20  | ^...[0m1 error |
000000f0  67 65 6e 65 72 61 74 65 64 2e 0d 0a              |generated...|
```

### clang-cl-fdiagnostics-color

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c -fdiagnostics-color=always /Foe4.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 173 bytes

stdout:
```
(empty)
```

stderr:
```
err.c(1,27): error: use of undeclared identifier 'nosuchsymbol'
    1 | int err_fn(void) { return nosuchsymbol; }
      |                           ^
1 error generated.
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### clang-cl-fno-color

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c -fno-color-diagnostics /Foe5.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 173 bytes

stdout:
```
(empty)
```

stderr:
```
err.c(1,27): error: use of undeclared identifier 'nosuchsymbol'
    1 | int err_fn(void) { return nosuchsymbol; }
      |                           ^
1 error generated.
```

ESC (0x1b) present -- stdout: **False**, stderr: **False**

### clang-cl-error-format

Is the message `file(line,col): error: ...` (MSVC-shaped) or `file:line:col: error: ...` (clang-shaped)?

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Foef.obj err.c`
cwd: `C:\p\p10`

exit code: **1**  |  stdout: 0 bytes  |  stderr: 173 bytes

stdout:
```
(empty)
```

stderr:
```
err.c(1,27): error: use of undeclared identifier 'nosuchsymbol'
    1 | int err_fn(void) { return nosuchsymbol; }
      |                           ^
1 error generated.
```

### clang-cl-Brepro

cmd: `C:\Program Files\LLVM\bin\clang-cl.exe /nologo /c /Brepro /Fobr.obj a.c`
cwd: `C:\p\p10`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p10):
```
        81  a.c
       875  a.d
      3403  a.obj
      3403  a2.obj
      3403  br.obj
        42  err.c
        58  inc\lvl1.h
        40  inc\lvl2.h
      3403  md.obj
      3403  sd.obj
      3403  si.obj
      3403  siu.obj
```

