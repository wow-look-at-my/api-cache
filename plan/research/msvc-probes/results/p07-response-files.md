# Probe 7: @response files, quoting, nesting, UTF-16; CL and _CL_

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p07-response-files/` in this artifact.

args.rsp:
```
/nologo /c /DFOO=1 /Foplain.obj probe.c
```

### rsp-plain

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-plain`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=1
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p07-plain):
```
        41  args.rsp
        42  inc dir\spaced.h
       572  plain.obj
       584  probe.c
```

### rsp-multiline

One argument per line. A line break is a separator.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-multiline`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=2
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p07-multiline):
```
        45  args.rsp
        42  inc dir\spaced.h
       576  multi.obj
       584  probe.c
```

### rsp-quoted-space

A double-quoted include directory with a space in it.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-quoted-space`

exit code: **0**  |  stdout: 32 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN spaced.h
```

stderr:
```
(empty)
```

### rsp-unquoted-space

The same directory unquoted. `dir` should become a second input file.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-unquoted-space`

exit code: **2**  |  stdout: 114 bytes  |  stderr: 153 bytes

stdout:
```
probe.c
NO FOO
probe.c(24): fatal error C1083: Cannot open include file: 'spaced.h': No such file or directory
```

stderr:
```
cl : Command line warning D9024 : unrecognized source file type 'dir', object file assumed
cl : Command line warning D9027 : source file 'dir' ignored
```

### rsp-define-with-space

The whole argument is quoted, value included: "/DMSG=hello world".

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-define-with-space`

exit code: **0**  |  stdout: 39 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN MSG=hello world
```

stderr:
```
(empty)
```

### rsp-define-with-space-inner

The quote opens AFTER /D: /D"MSG=hello world". Does the leader stay outside the quoted run?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-define-with-space-inner`

exit code: **0**  |  stdout: 39 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN MSG=hello world
```

stderr:
```
(empty)
```

args.rsp (note the trailing `\\` before the closing quote):
```
/nologo /c "/DPATHDEF=c:\dir\\" /Fob.obj probe.c
```

### rsp-backslash-before-quote

Two backslashes before the closing quote: under the MSVCRT rule that is one literal backslash and a real closing quote.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-backslash-quote`

exit code: **2**  |  stdout: 202 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
probe.c(15): warning C4129: 'd': unrecognized character escape sequence
probe.c(15): error C2001: newline in string literal
probe.c(15): warning C4081: expected ')'; found 'newline'
```

stderr:
```
(empty)
```

### rsp-single-backslash-before-quote

ONE backslash before the closing quote: under the MSVCRT rule that escapes the quote, so the quoted run swallows the rest of the line.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-backslash-quote-single`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 57 bytes

stdout:
```
(empty)
```

stderr:
```
cl : Command line error D8003 : missing source filename
```

### rsp-escaped-quote

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-escaped-quote`

exit code: **0**  |  stdout: 36 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN MSG="quoted"
```

stderr:
```
(empty)
```

### rsp-nested-at

A response file containing `@inner.rsp`. If FROMINNER is NOT seen, a wrapper must expand exactly one level. If it IS seen, msvc.md §11 is wrong for this toolset.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-nested`

exit code: **0**  |  stdout: 39 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=9
SEEN FROMINNER=1
```

stderr:
```
(empty)
```

### rsp-relative-path

msvc.md §11: relative response-file paths resolve against the cwd. Does `probe.c` inside it also resolve against the cwd rather than the rsp's directory?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @sub\args.rsp`
cwd: `C:\p\p07-relative-path`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=3
```

stderr:
```
(empty)
```

args.rsp bytes (UTF-16LE with BOM) (80 bytes):
```
00000000  ff fe 2f 00 6e 00 6f 00 6c 00 6f 00 67 00 6f 00  |../.n.o.l.o.g.o.|
00000010  20 00 2f 00 63 00 20 00 2f 00 44 00 46 00 4f 00  | ./.c. ./.D.F.O.|
00000020  4f 00 3d 00 31 00 36 00 20 00 2f 00 46 00 6f 00  |O.=.1.6. ./.F.o.|
00000030  6c 00 65 00 2e 00 6f 00 62 00 6a 00 20 00 70 00  |l.e...o.b.j. .p.|
00000040  72 00 6f 00 62 00 65 00 2e 00 63 00 0d 00 0a 00  |r.o.b.e...c.....|
```

### rsp-utf16le-bom

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-utf16le`

exit code: **0**  |  stdout: 22 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=16
```

stderr:
```
(empty)
```

args.rsp bytes (UTF-16BE with BOM) (80 bytes):
```
00000000  fe ff 00 2f 00 6e 00 6f 00 6c 00 6f 00 67 00 6f  |.../.n.o.l.o.g.o|
00000010  00 20 00 2f 00 63 00 20 00 2f 00 44 00 46 00 4f  |. ./.c. ./.D.F.O|
00000020  00 4f 00 3d 00 31 00 37 00 20 00 2f 00 46 00 6f  |.O.=.1.7. ./.F.o|
00000030  00 62 00 65 00 2e 00 6f 00 62 00 6a 00 20 00 70  |.b.e...o.b.j. .p|
00000040  00 72 00 6f 00 62 00 65 00 2e 00 63 00 0d 00 0a  |.r.o.b.e...c....|
```

### rsp-utf16be-bom

Big-endian. buildcache's resolve_args accepts both FF FE and FE FF.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-utf16be`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 187 bytes

stdout:
```
(empty)
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.

cl : Command line error D8022 : cannot open 'args.rsp'
```

args.rsp bytes (UTF-8 with BOM) (41 bytes):
```
00000000  ef bb bf 2f 6e 6f 6c 6f 67 6f 20 2f 63 20 2f 44  |.../nologo /c /D|
00000010  46 4f 4f 3d 38 20 2f 46 6f 75 38 2e 6f 62 6a 20  |FOO=8 /Fou8.obj |
00000020  70 72 6f 62 65 2e 63 0d 0a                       |probe.c..|
```

### rsp-utf8-bom

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-utf8bom`

exit code: **0**  |  stdout: 21 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=8
```

stderr:
```
(empty)
```

### rsp-missing

An unopenable response file. gcc leaves such an argument verbatim; what does cl do?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @nosuch.rsp`
cwd: `C:\p\p07-missing-rsp`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 189 bytes

stdout:
```
(empty)
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.

cl : Command line error D8022 : cannot open 'nosuch.rsp'
```

## The `CL` and `_CL_` environment variables

### env-none

Baseline with neither variable set.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fonone.obj probe.c`
cwd: `C:\p\p07-CL-env`

exit code: **0**  |  stdout: 17 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
```

stderr:
```
(empty)
```

### env-CL-define

CL=/DFOO=fromCL with FOO absent from argv. If the message appears, argv alone does not describe the compile.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Focl.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `CL=/DFOO=fromCL`

exit code: **0**  |  stdout: 26 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=fromCL
```

stderr:
```
(empty)
```

### env-_CL_-define

_CL_=/DBAR=fromUnderscoreCL -- the APPENDED variable.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fouscl.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `_CL_=/DBAR=fromUnderscoreCL`

exit code: **0**  |  stdout: 44 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN BAR=fromUnderscoreCL
```

stderr:
```
(empty)
```

### env-CL-precedence

CL and argv both define VAL. CL is documented as PREPENDED, so argv should win the last-wins race.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /DVAL=fromArgv /Foprec.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `CL=/DVAL=fromCL`

exit code: **0**  |  stdout: 36 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN VAL=fromArgv
```

stderr:
```
(empty)
```

### env-_CL_-precedence

_CL_ is APPENDED, so it should win over argv.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /DVAL=fromArgv /Foprec2.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `_CL_=/DVAL=fromUnderscoreCL`

exit code: **0**  |  stdout: 44 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN VAL=fromUnderscoreCL
```

stderr:
```
(empty)
```

### env-CL-both

Both set plus argv: the full ordering in one shot.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /DVAL=fromArgv /Foboth.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `CL=/DVAL=fromCL; _CL_=/DVAL=fromUnderscoreCL`

exit code: **0**  |  stdout: 44 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
SEEN VAL=fromUnderscoreCL
```

stderr:
```
(empty)
```

### env-CL-carries-Zi

CL=/Zi with no debug flag in argv. If a .pdb appears, an env-var STRING hash (buildcache) would key it correctly but would never classify it as a PDB bypass.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fozi.obj probe.c`
cwd: `C:\p\p07-CL-env-Zi`
env: `CL=/Zi`

exit code: **0**  |  stdout: 17 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p07-CL-env-Zi):
```
        42  inc dir\spaced.h
       584  probe.c
     69632  vc140.pdb
       988  zi.obj
```

### env-CL-plus-rsp

CL set and the command line is nothing but @args.rsp.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe @args.rsp`
cwd: `C:\p\p07-CL-with-rsp`
env: `CL=/DFOO=clPlusRsp`

exit code: **0**  |  stdout: 29 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=clPlusRsp
```

stderr:
```
(empty)
```

### env-CL-names-rsp

CL=@extra.rsp. A third expansion site nobody documents.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foclrsp.obj probe.c`
cwd: `C:\p\p07-CL-names-rsp`
env: `CL=@extra.rsp`

exit code: **0**  |  stdout: 29 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
SEEN FOO=fromClRsp
```

stderr:
```
(empty)
```

### env-CL-empty

CL set to the empty string.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Foempty.obj probe.c`
cwd: `C:\p\p07-CL-env`
env: `CL=`

exit code: **0**  |  stdout: 17 bytes  |  stderr: 0 bytes

stdout:
```
probe.c
NO FOO
```

stderr:
```
(empty)
```

