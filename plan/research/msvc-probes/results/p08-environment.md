# Probe 8: INCLUDE, EXTERNAL_INCLUDE, LIB, TMP, VS_UNICODE_OUTPUT

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731635556

Raw captures (stdout / stderr / exit code, one file each) are under `p08-environment/` in this artifact.

The INCLUDE the toolchain step set, one entry per line:
```
C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include
C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include
C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include
C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt
C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um
C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared
C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt
C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt
C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um
```

`EXTERNAL_INCLUDE` = `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`
`LIB` = `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\lib\x64;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\lib\x64;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\lib\um\x64;C:\Program Files (x86)\Windows Kits\10\lib\10.0.26100.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\\lib\10.0.26100.0\\um\x64`
`LIBPATH` = `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\lib\x64;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\lib\x64;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\lib\x86\store\references;C:\Program Files (x86)\Windows Kits\10\UnionMetadata\10.0.26100.0;C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0;C:\Windows\Microsoft.NET\Framework64\v4.0.30319`
`CL` = `(unset)`
`_CL_` = `(unset)`
`TMP` = `C:\Users\RUNNER~1\AppData\Local\Temp`
`TEMP` = `C:\Users\RUNNER~1\AppData\Local\Temp`
`VSLANG` = ``
`VS_UNICODE_OUTPUT` = `(unset)`
`VCToolsVersion` = `14.51.36231`
`VCToolsInstallDir` = `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\`
`UCRTVersion` = `10.0.26100.0`
`WindowsSdkVerBinPath` = `C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\`

### INCLUDE-incA

INCLUDE leads with incA. `#include <pick.h>` must resolve there.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /FoA.obj e.c`
cwd: `C:\p\p08`
env: `INCLUDE=C:\p\p08\incA;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 18 bytes  |  stderr: 0 bytes

stdout:
```
e.c
PICKED=incA
```

stderr:
```
(empty)
```

### INCLUDE-incB

The identical argv with INCLUDE leading with incB. A different header, a different object, the SAME command line -- which is exactly why INCLUDE must be in the key.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /FoB.obj e.c`
cwd: `C:\p\p08`
env: `INCLUDE=C:\p\p08\incB;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 18 bytes  |  stderr: 0 bytes

stdout:
```
e.c
PICKED=incB
```

stderr:
```
(empty)
```

```
A.obj (INCLUDE=incA;...) : 3D99B10455B09DA8231C77EF30E0415192975613A40BE4B58A894A038B80143A
B.obj (INCLUDE=incB;...) : F7F33ACB057BC9D6E2DAC8FA0E81CA843240FE69B613E85A4D699FF6DE8E0582
identical                : False
```

### INCLUDE-vs-I-flag

/I names incA while INCLUDE leads with incB. Which wins?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /IincA /FoI.obj e.c`
cwd: `C:\p\p08`
env: `INCLUDE=C:\p\p08\incB;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 18 bytes  |  stderr: 0 bytes

stdout:
```
e.c
PICKED=incA
```

stderr:
```
(empty)
```

### INCLUDE-empty

INCLUDE points nowhere. `#include <stdio.h>` should fail with C1083 -- proof that cl has no built-in system path.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fosys.obj sys.c`
cwd: `C:\p\p08`
env: `INCLUDE=C:\nonexistent-include-path`

exit code: **2**  |  stdout: 100 bytes  |  stderr: 0 bytes

stdout:
```
sys.c
sys.c(1): fatal error C1083: Cannot open include file: 'stdio.h': No such file or directory
```

stderr:
```
(empty)
```

### EXTERNAL_INCLUDE-resolves

EXTERNAL_INCLUDE names incB and INCLUDE does not. Does the header resolve through EXTERNAL_INCLUDE alone?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /external:W0 /Foext.obj ext.c`
cwd: `C:\p\p08`
env: `EXTERNAL_INCLUDE=C:\p\p08\incB; INCLUDE=C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 20 bytes  |  stderr: 0 bytes

stdout:
```
ext.c
PICKED=incB
```

stderr:
```
(empty)
```

### external-env-flag

/external:env:<var> -- a THIRD env-var name that reaches the include search, and one chosen by argv. A wrapper cannot use a fixed allowlist for it.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /external:env:MYEXT /external:W0 /Foextenv.obj ext.c`
cwd: `C:\p\p08`
env: `MYEXT=C:\p\p08\incB; INCLUDE=C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 20 bytes  |  stderr: 0 bytes

stdout:
```
ext.c
PICKED=incB
```

stderr:
```
(empty)
```

### LIB-irrelevant-under-c

LIB points nowhere and the compile is /c. msvc.md §8 says LIB is link-time only.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Folib.obj sys.c`
cwd: `C:\p\p08`
env: `LIB=C:\nonexistent-lib-path`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
sys.c
```

stderr:
```
(empty)
```

### TMP-redirected

TMP and TEMP redirected to an empty directory.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fotmp.obj sys.c`
cwd: `C:\p\p08`
env: `TEMP=C:\p\p08\mytmp; TMP=C:\p\p08\mytmp`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
sys.c
```

stderr:
```
(empty)
```

contents of the redirected TMP after the compile (C:\p\p08\mytmp):
```
(no files)
```

### TMP-nonexistent

TMP points at a directory that does not exist.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fotmp2.obj sys.c`
cwd: `C:\p\p08`
env: `TEMP=C:\no-such-tmp-dir; TMP=C:\no-such-tmp-dir`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
sys.c
```

stderr:
```
(empty)
```

### VS_UNICODE_OUTPUT-set-1

VS_UNICODE_OUTPUT=1. msvc.md §8: cl then sends its output to the IDE process rather than to stdout/stderr, so the capture should be EMPTY. The value is normally a pipe handle number, so 1 is a plausible-but-wrong handle; the capture records what cl does with it.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /Fovsu.obj e.c`
cwd: `C:\p\p08`
env: `VS_UNICODE_OUTPUT=1; INCLUDE=C:\p\p08\incA;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### VS_UNICODE_OUTPUT-set-0

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /Fovsu0.obj e.c`
cwd: `C:\p\p08`
env: `VS_UNICODE_OUTPUT=0; INCLUDE=C:\p\p08\incA;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### VS_UNICODE_OUTPUT-set-garbage

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /W4 /Fovsug.obj e.c`
cwd: `C:\p\p08`
env: `VS_UNICODE_OUTPUT=notanumber; INCLUDE=C:\p\p08\incA;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\ATLMFC\include;C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt;C:\Program Files (x86)\Windows Kits\NETFXSDK\4.8.1\include\um`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### VS_UNICODE_OUTPUT-error-path

A compile that must emit C2065. If the capture is empty but the exit code is non-zero, a wrapper caching this run would store an error with no message.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fobad.obj bad.c`
cwd: `C:\p\p08`
env: `VS_UNICODE_OUTPUT=1`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### error-path-baseline

The same compile with VS_UNICODE_OUTPUT unset, for the comparison.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fobad2.obj bad.c`
cwd: `C:\p\p08`

exit code: **2**  |  stdout: 69 bytes  |  stderr: 0 bytes

stdout:
```
bad.c
bad.c(1): error C2065: 'nosuchsymbol': undeclared identifier
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p08):
```
       560  A.obj
       560  B.obj
        42  bad.c
        82  e.c
        84  ext.c
       564  ext.obj
       564  extenv.obj
       560  I.obj
        35  incA\pick.h
        35  incB\pick.h
       564  lib.obj
        50  sys.c
       564  tmp.obj
       564  tmp2.obj
       564  vsu.obj
       564  vsu0.obj
       564  vsug.obj
```

