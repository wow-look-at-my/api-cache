# Probe 3: message language, VSLANG, and sccache's runtime prefix detection

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p03-localization/` in this artifact.

Compiler directory: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64`

Locale subdirectories beside cl.exe (each holds the localized message DLLs; only these languages can be selected):
```
1033
onecore
```

Files matching `*ui.dll` / `clui.dll` anywhere under the compiler directory (the message resource):
```
1033\clui.dll
```

### vslang-unset

Baseline, VSLANG untouched.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /showIncludes /I. test.c`
cwd: `C:\p\p03`

exit code: **0**  |  stdout: 47 bytes  |  stderr: 0 bytes

stdout:
```
test.c
Note: including file: C:\p\p03\test.h
```

stderr:
```
(empty)
```

### vslang-1041

VSLANG=1041 (Japanese). With no language pack installed cl falls back to English; the capture records which.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /showIncludes /I. /Fo1041.obj test.c`
cwd: `C:\p\p03`
env: `VSLANG=1041`

exit code: **0**  |  stdout: 47 bytes  |  stderr: 0 bytes

stdout:
```
test.c
Note: including file: C:\p\p03\test.h
```

stderr:
```
(empty)
```

### vslang-1031

VSLANG=1031 (German). With no language pack installed cl falls back to English; the capture records which.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /showIncludes /I. /Fo1031.obj test.c`
cwd: `C:\p\p03`
env: `VSLANG=1031`

exit code: **0**  |  stdout: 47 bytes  |  stderr: 0 bytes

stdout:
```
test.c
Note: including file: C:\p\p03\test.h
```

stderr:
```
(empty)
```

### vslang-1036

VSLANG=1036 (French). With no language pack installed cl falls back to English; the capture records which.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /showIncludes /I. /Fo1036.obj test.c`
cwd: `C:\p\p03`
env: `VSLANG=1036`

exit code: **0**  |  stdout: 47 bytes  |  stderr: 0 bytes

stdout:
```
test.c
Note: including file: C:\p\p03\test.h
```

stderr:
```
(empty)
```

### vslang-2052

VSLANG=2052 (Chinese-Simplified). With no language pack installed cl falls back to English; the capture records which.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /showIncludes /I. /Fo2052.obj test.c`
cwd: `C:\p\p03`
env: `VSLANG=2052`

exit code: **0**  |  stdout: 47 bytes  |  stderr: 0 bytes

stdout:
```
test.c
Note: including file: C:\p\p03\test.h
```

stderr:
```
(empty)
```

## sccache's detect_showincludes_prefix, executed against this cl.exe

Algorithm transcribed from `refs/sccache/src/compiler/msvc.rs:170-253`. sccache reads **stderr only**; this reimplementation tries stderr first and then stdout, and records which one actually carried the line.

```
exit code       : 0
stream with line: stderr
matched line    : Note: including file: C:\p\p03\test.h
detected prefix : [Note: including file: ]
prefix length   : 22
```

the detected prefix, byte for byte (22 bytes):
```
00000000  4e 6f 74 65 3a 20 69 6e 63 6c 75 64 69 6e 67 20  |Note: including |
00000010  66 69 6c 65 3a 20                                |file: |
```

Detection with `VSLANG=1041`: stream=`stderr` prefix=`[Note: including file: ]`
Detection with `VSLANG=1031`: stream=`stderr` prefix=`[Note: including file: ]`

