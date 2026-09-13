# Probe 6: /Yc, /Yu, /Fp, and the missing / stale .pch

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p06-pch/` in this artifact.

### Yc-with-Fp

Create the PCH with /Fp naming it. Note that /Yc emits BOTH a .pch and a .obj -- two outputs from one compile.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Ycpch.h /Fppch.pch /Fopch.obj pch.cpp`
cwd: `C:\p\p06-Yc-explicit-Fp`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yc-explicit-Fp):
```
        17  pch.cpp
        41  pch.h
       635  pch.obj
   5046272  pch.pch
        52  use.cpp
```

### Yu-with-Fp

Use it.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Yupch.h /Fppch.pch /Fouse.obj use.cpp`
cwd: `C:\p\p06-Yc-explicit-Fp`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yc-explicit-Fp):
```
        17  pch.cpp
        41  pch.h
       635  pch.obj
   5046272  pch.pch
        52  use.cpp
       665  use.obj
```

### Yc-no-Fp

No /Fp. msvc.md §6 claims the name comes from the /Yc header name, else the source basename. Which is it?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Ycpch.h /Fopch.obj pch.cpp`
cwd: `C:\p\p06-Yc-no-Fp`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yc-no-Fp):
```
        17  pch.cpp
        41  pch.h
       625  pch.obj
   5046272  pch.pch
        52  use.cpp
```

### Yc-bare

Bare /Yc with no header name.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Yc /Fopch.obj pch.cpp`
cwd: `C:\p\p06-Yc-bare`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yc-bare):
```
        17  pch.cpp
        41  pch.h
       624  pch.obj
   5046272  pch.pch
        52  use.cpp
```

### Yu-missing-pch

The .pch named by /Fp does not exist. The exact error text and exit code are what a wrapper has to recognise.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Yupch.h /Fpnosuch.pch /Fouse.obj use.cpp`
cwd: `C:\p\p06-Yu-missing`

exit code: **2**  |  stdout: 118 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
use.cpp(1): fatal error C1083: Cannot open precompiled header file: 'nosuch.pch': No such file or directory
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yu-missing):
```
        17  pch.cpp
        41  pch.h
        52  use.cpp
```

### Yu-stale-create

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Ycpch.h /Fppch.pch /Fopch.obj pch.cpp`
cwd: `C:\p\p06-Yu-stale`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

### Yu-stale-use

pch.h was edited AFTER the .pch was built. Does cl detect it (C1859 / C4652), and with what exit code? This is the case that decides whether the .pch content must be in the key.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Yupch.h /Fppch.pch /Fouse.obj use.cpp`
cwd: `C:\p\p06-Yu-stale`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yu-stale):
```
        17  pch.cpp
        73  pch.h
       625  pch.obj
   5046272  pch.pch
        52  use.cpp
       655  use.obj
```

### pch-A-create

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Ycpch.h /FpA.pch /FopchA.obj pch.cpp`
cwd: `C:\p\p06-pch-identity-in-object`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

### pch-B-create

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Ycpch.h /FpB.pch /FopchB.obj pch.cpp`
cwd: `C:\p\p06-pch-identity-in-object`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

### pch-use-A

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Yupch.h /FpA.pch /FouseA.obj use.cpp`
cwd: `C:\p\p06-pch-identity-in-object`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
```

stderr:
```
(empty)
```

### pch-use-B

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Yupch.h /FpB.pch /FouseB.obj use.cpp`
cwd: `C:\p\p06-pch-identity-in-object`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-pch-identity-in-object):
```
   5046272  A.pch
   5046272  B.pch
        17  pch.cpp
        70  pch.h
        41  pch.h.bak
     63300  pchA.obj
     63316  pchB.obj
        52  use.cpp
      2438  useA.obj
      2438  useB.obj
```

## Does the object differ when only the .pch behind it differs?

```
useA.obj (against A.pch) : 2D9AB8091E6128DF3728FAEA3CEC3BD4FC9EC69E84DFFA98BFA7707936E87869
useB.obj (against B.pch) : 878AFF0166C005958BD638575E9B20353ACAC9CECC27F0920B19262608A35460
identical                : False
```

If these differ while `use.cpp`'s own text and argv are identical, the `.pch` content is a genuine hash input and buildcache's `get_hash_extra_content()` treatment is the correct one.

Every `.pch` written by this family, with its size (msvc.md §6: "a `.pch` is routinely 100-400 MB" -- these are minimal headers, so this is the FLOOR, not a typical project figure):
```
     5046272  C:\p\p06-pch-identity-in-object\A.pch
     5046272  C:\p\p06-pch-identity-in-object\B.pch
     5046272  C:\p\p06-Yc-bare\pch.pch
     5046272  C:\p\p06-Yc-explicit-Fp\pch.pch
     5046272  C:\p\p06-Yc-no-Fp\pch.pch
     5046272  C:\p\p06-Yu-stale\pch.pch
```

### big-pch-create

A PCH over windows.h plus five STL headers -- a realistic size for the memoisation argument.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /EHsc /Ycbig.h /Fpbig.pch /Fobig.obj big.cpp`
cwd: `C:\p\p06-big-pch`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
big.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-big-pch):
```
        17  big.cpp
       106  big.h
      2071  big.obj
  50069504  big.pch
```

### Yu-no-Fp-create

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Ycpch.h /Fopch.obj pch.cpp`
cwd: `C:\p\p06-Yu-no-Fp`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
pch.cpp
```

stderr:
```
(empty)
```

### Yu-no-Fp-use

Neither compile names /Fp. The resolution order in msvc.md §6 says the .pch name is derived the same way on both sides.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Yupch.h /Fouse.obj use.cpp`
cwd: `C:\p\p06-Yu-no-Fp`

exit code: **0**  |  stdout: 9 bytes  |  stderr: 0 bytes

stdout:
```
use.cpp
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p06-Yu-no-Fp):
```
        17  pch.cpp
        41  pch.h
       625  pch.obj
   5046272  pch.pch
        52  use.cpp
       655  use.obj
```

