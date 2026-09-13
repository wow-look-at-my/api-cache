# Probe 1: cl.exe identity, banner, stream and exit code

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p01-identity/` in this artifact.

cl.exe resolved to `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe`

### bare-cl

Bare `cl.exe`, no arguments. buildcache's get_program_id runs exactly this and reads std_err.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe `
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 61 bytes  |  stderr: 131 bytes

stdout:
```
usage: cl [ option... ] filename... [ /link linkoption... ]
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.
```

stderr bytes, verbatim (131 bytes):
```
00000000  4d 69 63 72 6f 73 6f 66 74 20 28 52 29 20 43 2f  |Microsoft (R) C/|
00000010  43 2b 2b 20 4f 70 74 69 6d 69 7a 69 6e 67 20 43  |C++ Optimizing C|
00000020  6f 6d 70 69 6c 65 72 20 56 65 72 73 69 6f 6e 20  |ompiler Version |
00000030  31 39 2e 35 31 2e 33 36 32 35 36 20 66 6f 72 20  |19.51.36256 for |
00000040  78 36 34 0d 0a 43 6f 70 79 72 69 67 68 74 20 28  |x64..Copyright (|
00000050  43 29 20 4d 69 63 72 6f 73 6f 66 74 20 43 6f 72  |C) Microsoft Cor|
00000060  70 6f 72 61 74 69 6f 6e 2e 20 20 41 6c 6c 20 72  |poration.  All r|
00000070  69 67 68 74 73 20 72 65 73 65 72 76 65 64 2e 0d  |ights reserved..|
00000080  0a 0d 0a                                         |...|
```

stdout bytes, verbatim (61 bytes):
```
00000000  75 73 61 67 65 3a 20 63 6c 20 5b 20 6f 70 74 69  |usage: cl [ opti|
00000010  6f 6e 2e 2e 2e 20 5d 20 66 69 6c 65 6e 61 6d 65  |on... ] filename|
00000020  2e 2e 2e 20 5b 20 2f 6c 69 6e 6b 20 6c 69 6e 6b  |... [ /link link|
00000030  6f 70 74 69 6f 6e 2e 2e 2e 20 5d 0d 0a           |option... ]..|
```

### bare-cl-nologo

Does /nologo suppress the banner on the no-input error path?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo`
cwd: `C:\p\p01`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 57 bytes

stdout:
```
(empty)
```

stderr:
```
cl : Command line error D8003 : missing source filename
```

### cl-Bv

/Bv prints the version of every compiler component. A candidate tool-identity source.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /Bv`
cwd: `C:\p\p01`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 1296 bytes

stdout:
```
(empty)
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.

Compiler Passes:
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1.dll:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1xx.dll:      Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c2.dll:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1xx.dll:      Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\link.exe:      Version 14.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\mspdb140.dll:  Version 14.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\1033\clui.dll: Version 19.51.36256.0

cl : Command line error D8003 : missing source filename
```

stdout bytes, verbatim: (empty)

stderr bytes, verbatim (1296 bytes):
```
00000000  4d 69 63 72 6f 73 6f 66 74 20 28 52 29 20 43 2f  |Microsoft (R) C/|
00000010  43 2b 2b 20 4f 70 74 69 6d 69 7a 69 6e 67 20 43  |C++ Optimizing C|
00000020  6f 6d 70 69 6c 65 72 20 56 65 72 73 69 6f 6e 20  |ompiler Version |
00000030  31 39 2e 35 31 2e 33 36 32 35 36 20 66 6f 72 20  |19.51.36256 for |
00000040  78 36 34 0d 0a 43 6f 70 79 72 69 67 68 74 20 28  |x64..Copyright (|
00000050  43 29 20 4d 69 63 72 6f 73 6f 66 74 20 43 6f 72  |C) Microsoft Cor|
00000060  70 6f 72 61 74 69 6f 6e 2e 20 20 41 6c 6c 20 72  |poration.  All r|
00000070  69 67 68 74 73 20 72 65 73 65 72 76 65 64 2e 0d  |ights reserved..|
00000080  0a 0d 0a 43 6f 6d 70 69 6c 65 72 20 50 61 73 73  |...Compiler Pass|
00000090  65 73 3a 0d 0a 20 43 3a 5c 50 72 6f 67 72 61 6d  |es:.. C:\Program|
000000a0  20 46 69 6c 65 73 5c 4d 69 63 72 6f 73 6f 66 74  | Files\Microsoft|
000000b0  20 56 69 73 75 61 6c 20 53 74 75 64 69 6f 5c 31  | Visual Studio\1|
000000c0  38 5c 45 6e 74 65 72 70 72 69 73 65 5c 56 43 5c  |8\Enterprise\VC\|
000000d0  54 6f 6f 6c 73 5c 4d 53 56 43 5c 31 34 2e 35 31  |Tools\MSVC\14.51|
000000e0  2e 33 36 32 33 31 5c 62 69 6e 5c 48 6f 73 74 58  |.36231\bin\HostX|
000000f0  36 34 5c 78 36 34 5c 63 6c 2e 65 78 65 3a 20 20  |64\x64\cl.exe:  |
00000100  20 20 20 20 20 20 56 65 72 73 69 6f 6e 20 31 39  |      Version 19|
00000110  2e 35 31 2e 33 36 32 35 36 2e 30 0d 0a 20 43 3a  |.51.36256.0.. C:|
00000120  5c 50 72 6f 67 72 61 6d 20 46 69 6c 65 73 5c 4d  |\Program Files\M|
00000130  69 63 72 6f 73 6f 66 74 20 56 69 73 75 61 6c 20  |icrosoft Visual |
00000140  53 74 75 64 69 6f 5c 31 38 5c 45 6e 74 65 72 70  |Studio\18\Enterp|
00000150  72 69 73 65 5c 56 43 5c 54 6f 6f 6c 73 5c 4d 53  |rise\VC\Tools\MS|
00000160  56 43 5c 31 34 2e 35 31 2e 33 36 32 33 31 5c 62  |VC\14.51.36231\b|
00000170  69 6e 5c 48 6f 73 74 58 36 34 5c 78 36 34 5c 63  |in\HostX64\x64\c|
00000180  31 2e 64 6c 6c 3a 20 20 20 20 20 20 20 20 56 65  |1.dll:        Ve|
00000190  72 73 69 6f 6e 20 31 39 2e 35 31 2e 33 36 32 35  |rsion 19.51.3625|
000001a0  36 2e 30 0d 0a 20 43 3a 5c 50 72 6f 67 72 61 6d  |6.0.. C:\Program|
000001b0  20 46 69 6c 65 73 5c 4d 69 63 72 6f 73 6f 66 74  | Files\Microsoft|
000001c0  20 56 69 73 75 61 6c 20 53 74 75 64 69 6f 5c 31  | Visual Studio\1|
000001d0  38 5c 45 6e 74 65 72 70 72 69 73 65 5c 56 43 5c  |8\Enterprise\VC\|
000001e0  54 6f 6f 6c 73 5c 4d 53 56 43 5c 31 34 2e 35 31  |Tools\MSVC\14.51|
000001f0  2e 33 36 32 33 31 5c 62 69 6e 5c 48 6f 73 74 58  |.36231\bin\HostX|
00000200  36 34 5c 78 36 34 5c 63 31 78 78 2e 64 6c 6c 3a  |64\x64\c1xx.dll:|
00000210  20 20 20 20 20 20 56 65 72 73 69 6f 6e 20 31 39  |      Version 19|
00000220  2e 35 31 2e 33 36 32 35 36 2e 30 0d 0a 20 43 3a  |.51.36256.0.. C:|
00000230  5c 50 72 6f 67 72 61 6d 20 46 69 6c 65 73 5c 4d  |\Program Files\M|
00000240  69 63 72 6f 73 6f 66 74 20 56 69 73 75 61 6c 20  |icrosoft Visual |
00000250  53 74 75 64 69 6f 5c 31 38 5c 45 6e 74 65 72 70  |Studio\18\Enterp|
00000260  72 69 73 65 5c 56 43 5c 54 6f 6f 6c 73 5c 4d 53  |rise\VC\Tools\MS|
00000270  56 43 5c 31 34 2e 35 31 2e 33 36 32 33 31 5c 62  |VC\14.51.36231\b|
00000280  69 6e 5c 48 6f 73 74 58 36 34 5c 78 36 34 5c 63  |in\HostX64\x64\c|
00000290  32 2e 64 6c 6c 3a 20 20 20 20 20 20 20 20 56 65  |2.dll:        Ve|
000002a0  72 73 69 6f 6e 20 31 39 2e 35 31 2e 33 36 32 35  |rsion 19.51.3625|
000002b0  36 2e 30 0d 0a 20 43 3a 5c 50 72 6f 67 72 61 6d  |6.0.. C:\Program|
000002c0  20 46 69 6c 65 73 5c 4d 69 63 72 6f 73 6f 66 74  | Files\Microsoft|
000002d0  20 56 69 73 75 61 6c 20 53 74 75 64 69 6f 5c 31  | Visual Studio\1|
000002e0  38 5c 45 6e 74 65 72 70 72 69 73 65 5c 56 43 5c  |8\Enterprise\VC\|
000002f0  54 6f 6f 6c 73 5c 4d 53 56 43 5c 31 34 2e 35 31  |Tools\MSVC\14.51|
00000300  2e 33 36 32 33 31 5c 62 69 6e 5c 48 6f 73 74 58  |.36231\bin\HostX|
00000310  36 34 5c 78 36 34 5c 63 31 78 78 2e 64 6c 6c 3a  |64\x64\c1xx.dll:|
00000320  20 20 20 20 20 20 56 65 72 73 69 6f 6e 20 31 39  |      Version 19|
00000330  2e 35 31 2e 33 36 32 35 36 2e 30 0d 0a 20 43 3a  |.51.36256.0.. C:|
00000340  5c 50 72 6f 67 72 61 6d 20 46 69 6c 65 73 5c 4d  |\Program Files\M|
00000350  69 63 72 6f 73 6f 66 74 20 56 69 73 75 61 6c 20  |icrosoft Visual |
00000360  53 74 75 64 69 6f 5c 31 38 5c 45 6e 74 65 72 70  |Studio\18\Enterp|
00000370  72 69 73 65 5c 56 43 5c 54 6f 6f 6c 73 5c 4d 53  |rise\VC\Tools\MS|
00000380  56 43 5c 31 34 2e 35 31 2e 33 36 32 33 31 5c 62  |VC\14.51.36231\b|
00000390  69 6e 5c 48 6f 73 74 58 36 34 5c 78 36 34 5c 6c  |in\HostX64\x64\l|
000003a0  69 6e 6b 2e 65 78 65 3a 20 20 20 20 20 20 56 65  |ink.exe:      Ve|
000003b0  72 73 69 6f 6e 20 31 34 2e 35 31 2e 33 36 32 35  |rsion 14.51.3625|
000003c0  36 2e 30 0d 0a 20 43 3a 5c 50 72 6f 67 72 61 6d  |6.0.. C:\Program|
000003d0  20 46 69 6c 65 73 5c 4d 69 63 72 6f 73 6f 66 74  | Files\Microsoft|
000003e0  20 56 69 73 75 61 6c 20 53 74 75 64 69 6f 5c 31  | Visual Studio\1|
000003f0  38 5c 45 6e 74 65 72 70 72 69 73 65 5c 56 43 5c  |8\Enterprise\VC\|
... (1296 bytes total)
```

### cl-Bv-nologo

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /Bv`
cwd: `C:\p\p01`

exit code: **2**  |  stdout: 0 bytes  |  stderr: 1165 bytes

stdout:
```
(empty)
```

stderr:
```
Compiler Passes:
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1.dll:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1xx.dll:      Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c2.dll:        Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\c1xx.dll:      Version 19.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\link.exe:      Version 14.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\mspdb140.dll:  Version 14.51.36256.0
 C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\1033\clui.dll: Version 19.51.36256.0

cl : Command line error D8003 : missing source filename
```

### compile-plain

A normal compile with no /nologo: banner plus the source filename line.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /c foo.c`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 131 bytes

stdout:
```
foo.c
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.
```

stdout bytes, verbatim (7 bytes):
```
00000000  66 6f 6f 2e 63 0d 0a                             |foo.c..|
```

stderr bytes, verbatim (131 bytes):
```
00000000  4d 69 63 72 6f 73 6f 66 74 20 28 52 29 20 43 2f  |Microsoft (R) C/|
00000010  43 2b 2b 20 4f 70 74 69 6d 69 7a 69 6e 67 20 43  |C++ Optimizing C|
00000020  6f 6d 70 69 6c 65 72 20 56 65 72 73 69 6f 6e 20  |ompiler Version |
00000030  31 39 2e 35 31 2e 33 36 32 35 36 20 66 6f 72 20  |19.51.36256 for |
00000040  78 36 34 0d 0a 43 6f 70 79 72 69 67 68 74 20 28  |x64..Copyright (|
00000050  43 29 20 4d 69 63 72 6f 73 6f 66 74 20 43 6f 72  |C) Microsoft Cor|
00000060  70 6f 72 61 74 69 6f 6e 2e 20 20 41 6c 6c 20 72  |poration.  All r|
00000070  69 67 68 74 73 20 72 65 73 65 72 76 65 64 2e 0d  |ights reserved..|
00000080  0a 0d 0a                                         |...|
```

### compile-nologo

The same compile with /nologo. Is the `foo.c` line still there?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c foo.c`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
```

stderr:
```
(empty)
```

stdout bytes, verbatim (7 bytes):
```
00000000  66 6f 6f 2e 63 0d 0a                             |foo.c..|
```

stderr bytes, verbatim: (empty)

### compile-subdir-relpath

Relative path with a directory component: does stdout echo `sub\bar.c` or `bar.c`?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c sub\bar.c`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
bar.c
```

stderr:
```
(empty)
```

### compile-abspath

Absolute path: does stdout echo the whole absolute path? (It decides whether the replayed stdout leaks another workspace's paths.)

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c C:\p\p01\sub\bar.c`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 7 bytes  |  stderr: 0 bytes

stdout:
```
bar.c
```

stderr:
```
(empty)
```

### compile-two-sources

Two sources under /c: one stdout line each, in argv order?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c foo.c baz.c`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 34 bytes  |  stderr: 0 bytes

stdout:
```
foo.c
baz.c
Generating Code...
```

stderr:
```
(empty)
```

### cl-help

/help, truncated in the capture only by cl itself.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /help`
cwd: `C:\p\p01`

exit code: **0**  |  stdout: 16350 bytes  |  stderr: 131 bytes

stdout:
```
                         C/C++ COMPILER OPTIONS


                              -OPTIMIZATION-

/O1 maximum optimizations (favor space) /O2 maximum optimizations (favor speed)
/Ob<n> inline expansion (default n=0)   /Od disable optimizations (default)
/Og enable global optimization          /Oi[-] enable intrinsic functions
/Os favor code space                    /Ot favor code speed
/Ox optimizations (favor speed)         
/favor:<blend|AMD64|INTEL64|ATOM> select processor to optimize for, one of:
    blend - a combination of optimizations for several different x64 processors
    AMD64 - 64-bit AMD processors
    INTEL64 - Intel(R)64 architecture processors
    ATOM - Intel(R) Atom(TM) processors

                             -CODE GENERATION-

/Gu[-] ensure distinct functions have distinct addresses
/Gw[-] separate global variables for linker
/GF enable read-only string pooling     /Gy[-] separate functions for linker
/GS[-] enable security checks           /GR[-] enable C++ RTTI
/guard:cf[-] enable CFG (control flow guard)
/guard:ehcont[-] enable EH continuation metadata (CET)
/EHs enable C++ EH (no SEH exceptions)  /EHa enable C++ EH (w/ SEH exceptions)
/EHc extern "C" defaults to nothrow     
/EHr always generate noexcept runtime termination checks
/fp:<contract|except[-]|fast|precise|strict> choose floating-point model:
    contract - consider floating-point contractions when generating code
    except[-] - consider floating-point exceptions when generating code
    fast - "fast" floating-point model; results are less predictable
    precise - "precise" floating-point model; results are predictable
    strict - "strict" floating-point model (implies /fp:except)
/Qfast_transcendentals generate inline FP intrinsics even with /fp:except
/Qspectre[-] enable mitigations for CVE 2017-5753
/Qpar[-] enable parallel code generation
/Qpar-report:1 auto-parallelizer diagnostic; indicate parallelized loops
/Qpar-report:2 auto-parallelizer diagnostic; indicate loops not parallelized
/Qvec-report:1 auto-vectorizer diagnostic; indicate vectorized loops
/Qvec-report:2 auto-vectorizer diagnostic; indicate loops not vectorized
/GL[-] enable link-time code generation 
/volatile:<iso|ms> choose volatile model:
    iso - Acquire/release semantics not guaranteed on volatile accesses
    ms  - Acquire/release semantics guaranteed on volatile accesses
/GA optimize for Windows Application    /Ge force stack checking for all funcs
/Gs[num] control stack checking calls   /Gh enable _penter function call
/GH enable _pexit function call         /GT generate fiber-safe TLS accesses
/RTC1 Enable fast checks (/RTCsu)       /RTCc Convert to smaller type checks
/RTCs Stack Frame runtime checking      /RTCu Uninitialized local usage checks
/clr[:option] compile for common language runtime, where option is:
    pure : produce IL-only output file (no native executable code)
    safe : produce IL-only verifiable output file
    netcore : produce assemblies targeting .NET Core runtime
    noAssembly : do not produce an assembly
    nostdlib : ignore the system .NET framework directory when searching for assemblies
    nostdimport : do not import any required assemblies implicitly
    initialAppDomain : enable initial AppDomain behavior of Visual C++ 2002
    implicitKeepAlive- : turn off implicit emission of System::GC::KeepAlive(this)
    char_t- : turn off metadata support for char8_t, char16_t and char32_t
    ECMAParamArray : use rules specified in ECMA-372/14.6 for overloads with parameter arrays (implied by /clr)
    ECMAParamArray- : use new rules for overloads with parameter arrays (implied by /clr:netcore)
/fsanitize=address Enable address sanitizer codegen
/homeparams Force parameters passed in registers to be written to the stack
/GZ Enable stack checks (/RTCs)         /Gv __vectorcall calling convention
(Preview) /dynamicdeopt Enable dynamic debugging; place deoptimized breakpoints and step in anywhere with on-demand function deoptimization
(Preview) /dynamicdeopt:suffix <suffix> File extension suffix for deoptimized output (default: .alt)
(Preview) /dynamicdeopt:sync Build deoptimized output after optimized output instead of in parallel
/arch:<SSE2|SSE4.2|AVX|AVX2|AVX512|AVX10.x> minimum CPU architecture requirements, one of:
   SSE2 - (default) enable use of instructions available with SSE2-enabled CPUs
   SSE4.2 - enable use of instructions available with SSE 4.2-enabled CPUs
   AVX - enable use of instructions available with AVX-enabled CPUs
   AVX2 - enable use of instructions available with AVX2-enabled CPUs
   AVX512 - enable use of instructions available with AVX-512-enabled CPUs
   AVX10.x - enable use of instructions available with AVX10.x-enabled CPUs. Valid values of x are 1 and 2
/QIntel-jcc-erratum enable mitigations for Intel JCC erratum
/Qspectre-load Enable spectre mitigations for all instructions which load memory
/Qspectre-load-cf Enable spectre mitigations for all control-flow instructions which load memory
/Qspectre-jmp[-] Enable spectre mitigations for unconditional jump instructions
/fpcvt:<IA|BC> FP to unsigned integer conversion compatibility
   IA - results compatible with VCVTTSD2USI instruction
   BC - results compatible with VS2017 and earlier compiler
/jumptablerdata Place jump tables for switch case statements in .rdata section
/vlen=<256|512> Choose vector length of either 256 or 512 for automatic code-generation
/vlen Choose default vector length based on /arch setting
(Preview) /feature:APX - enable use of instructions available with APX-enabled CPUs.

                              -OUTPUT FILES-

/Fa[file] name assembly listing file    /FA[scu] configure assembly listing
/Fd[file] name .PDB file                /Fe<file> name executable file
/Fm[file] name map file                 /Fo<file> name object file
/Fp<file> name precompiled header file  /Fr[file] name source browser file
/FR[file] name extended .SBR file       /Fi[file] name preprocessed file
/Fd: <file> name .PDB file              /Fe: <file> name executable file
/Fm: <file> name map file               /Fo: <file> name object file
/Fp: <file> name .PCH file              /FR: <file> name extended .SBR file
/Fi: <file> name preprocessed file      
/Ft<dir> location of the header files generated for #import
/doc[file] process XML documentation comments and optionally name the .xdc file

                              -PREPROCESSOR-

/AI<dir> add to assembly search path    /FU<file> import .NET assembly/module
/FU:asFriend<file> import .NET assembly/module as friend
/C don't strip comments                 /D<name>{=|#}<text> define macro
/E preprocess to stdout                 /EP preprocess to stdout, no #line
/P preprocess to file                   /Fx merge injected code to file
/FI<file> name forced include file      /U<name> remove predefined macro
/u remove all predefined macros         /I<dir> add to include search path
/X ignore "standard places"             
/PH generate #pragma file_hash when preprocessing
/PD print all macro definitions         

                                -LANGUAGE-

/std:<c++14|c++17|c++20|c++latest> C++ standard version
    c++14 - ISO/IEC 14882:2014 (default)
    c++17 - ISO/IEC 14882:2017
    c++20 - ISO/IEC 14882:2020
    c++latest - latest draft standard (feature set subject to change)
/std:<c11|c17|clatest> C standard version
    c11 - ISO/IEC 9899:2011
    c17 - ISO/IEC 9899:2018
    clatest - latest draft standard (feature set subject to change)
/permissive[-] enable some nonconforming code to compile
               (feature set subject to change) (off by default in C++20 and later)
/Za disable extensions (not recommended for C++)
/ZW enable WinRT language extensions    /Zs syntax check only
/await enable resumable functions extension
/await:strict enable standard C++20 coroutine support with earlier language versions
/constexpr:depth<N>     recursion depth limit for constexpr evaluation (default: 512)
/constexpr:backtrace<N> show N constexpr evaluations in diagnostics (default: 10)
/constexpr:steps<N>     terminate constexpr evaluation after N steps (default: 1048576)
/Zi enable debugging information        /Z7 enable old-style debug info
/Zo[-] generate richer debugging information for optimized code (on by default)
/ZH:[MD5|SHA1|SHA_256] hash algorithm for calculation of file checksum in debug info (default: SHA_256)
/Zp[n] pack structs on n-byte boundary  /Zl omit default library name in .OBJ
/vd{0|1|2} disable/enable vtordisp      /vm<x> type of pointers to members
/Zc:arg1[,arg2] language conformance, where arguments can be:
  forScope[-]           enforce Standard C++ for scoping rules
  wchar_t[-]            wchar_t is the native type, not a typedef
  auto[-]               enforce the new Standard C++ meaning for auto
  trigraphs[-]          enable trigraphs (off by default)
  rvalueCast[-]         enforce Standard C++ explicit type conversion rules
                        (on by default in C++20 or later, implied by /permissive-)
  strictStrings[-]      disable string-literal to [char|wchar_t]*
                        conversion (on by default in C++20 or later, implied by /permissive-)
  implicitNoexcept[-]   enable implicit noexcept on required functions
  threadSafeInit[-]     enable thread-safe local static initialization
  inline[-]             remove unreferenced function or data if it is
                        COMDAT or has internal linkage only (off by default)
  sizedDealloc[-]       enable C++14 global sized deallocation
                        functions (on by default)
  throwingNew[-]        assume operator new throws on failure (off by default)
  referenceBinding[-]   a temporary will not bind to a non-const
                        lvalue reference (on by default in C++20 or later, implied by /permissive-)
  twoPhase-             disable two-phase name lookup
  ternary[-]            enforce C++11 rules for conditional operator
                        (on by default in C++20 or later, implied by /permissive-)
  noexceptTypes[-]      enforce C++17 noexcept rules (on by default in C++17 or later)
  alignedNew[-]         enable C++17 alignment of dynamically allocated objects (on by default)
  hiddenFriend[-]       enforce Standard C++ hidden friend rules
                        (on by default in C++20 or later, implied by /permissive-)
  externC[-]            enforce Standard C++ rules for 'extern "C"' functions
                        (on by default in C++20 or later, implied by /permissive-)
  lambda[-]             better lambda support by using the newer lambda processor
                        (on by default in C++20 or later, implied by /permissive-)
  tlsGuards[-]          generate runtime checks for TLS variable initialization (on by default)
  zeroSizeArrayNew[-]   call member new/delete for 0-size arrays of objects (on by default)
  static_assert[-]      strict handling of 'static_assert' (on by default in C++20 or later,
                        implied by /permissive-)
  gotoScope[-]          cannot jump past the initialization of a variable (implied by /permissive-)
  templateScope[-]      enforce Standard C++ template parameter shadowing rules
  enumTypes[-]          enable Standard C++ underlying enum types (off by default)
  enumEncoding[-]       correctly encode a use of an enumeration as a non-type template
                        argument (off by default)
  checkGwOdr[-]         enforce Standard C++ one definition rule violations
                        when /Gw has been enabled (off by default)
  nrvo[-]               enable optional copy and move elision (on by default in C++20 or later,
                        implied by /permissive- or /O2)
  __STDC__              define __STDC__ to 1 in C
  __cplusplus[-]        __cplusplus macro reports the supported C++ standard (off by default)
  char8_t[-]            enable C++20 native `u8` literal support as `const char8_t`
                        (on by default in C++20 or later)
  externConstexpr[-]    enable external linkage for constexpr variables in C++
                        (on by default in C++20 or later, implied by /permissive-)
  preprocessor[-]       enable standard conforming preprocessor in C/C++
                        (on by default in C11 or later)
/ZI enable Edit and Continue debug info 
/openmp enable OpenMP 2.0 language extensions
/openmp:experimental enable OpenMP 2.0 language extensions plus select OpenMP 3.0+ language extensions
/openmp:llvm OpenMP language extensions using LLVM runtime

                              -MISCELLANEOUS-

@<file> options response file           /?, /help print this help message
/bigobj generate extended object format /c compile only, no link
/FC use full pathnames in diagnostics   /H<num> max external name length
/J default char type is unsigned        
/MP[n] use up to 'n' processes for compilation
/nologo suppress copyright message      /showIncludes show include file names
/Tc<source file> compile file as .c     /Tp<source file> compile file as .cpp
/TC compile all files as .c             /TP compile all files as .cpp
/V<string> set version string           /Yc[file] create .PCH file
/Yd put debug info in every .OBJ        /Yl[sym] inject .PCH ref for debug lib
/Yu[file] use .PCH file                 /Y- disable all PCH options
/Zm<n> max memory alloc (% of default)  /FS force to use MSPDBSRV.EXE
/source-charset:<iana-name>|.nnnn set source character set
/execution-charset:<iana-name>|.nnnn set execution character set
/utf-8 set source and execution character set to UTF-8
/validate-charset[-] validate UTF-8 files for only legal characters
/fastfail[-] enable fast-fail mode      /JMC[-] enable native just my code
/presetPadding[-] zero initialize padding for stack based class types
/volatileMetadata[-] generate metadata on volatile memory accesses
/sourcelink [file] file containing source link information
/templateDepth:N limit the depth of template instantiations (default N=1000)

                                -LINKING-

/LD Create .DLL                         /LDd Create .DLL debug library
/LN Create a .netmodule                 /F<num> set stack size
/link [linker options and libraries]    /MD link with MSVCRT.LIB
/MT link with LIBCMT.LIB                /MDd link with MSVCRTD.LIB debug lib
/MTd link with LIBCMTD.LIB debug lib    

                              -CODE ANALYSIS-

/analyze[-] Enable native analysis      /analyze:quiet[-] No warning to console
/analyze:log<name> Warnings to file     /analyze:autolog Log to *.pftlog
/analyze:autolog:ext<ext> Log to *.<ext>/analyze:autolog- No log file
/analyze:WX- Warnings not fatal         /analyze:stacksize<num> Max stack frame
/analyze:max_paths<num> Max paths       /analyze:only Analyze, no code gen

                              -DIAGNOSTICS-

/diagnostics:<args,...> controls the format of diagnostic messages:
             classic   - retains prior format
             column[-] - prints column information
             caret[-]  - prints column and the indicated line of source
/Wall enable all warnings               /w   disable all warnings
/W<n> set warning level (default n=1)   
/Wv:xx[.yy[.zzzzz]] disable warnings introduced after version xx.yy.zzzzz
/WX treat warnings as errors            /WL enable one line diagnostics
/wd<n> disable warning n                /we<n> treat warning n as an error
/wo<n> issue warning n once             /w<l><n> set warning level 1-4 for n
/external:I <path>      - location of external headers
/external:env:<var>     - environment variable with locations of external headers
/external:anglebrackets - treat all headers included via <> as external
/external:W<n>          - warning level for external headers
/external:templates[-]  - evaluate warning level across template instantiation chain
/sdl enable additional security features and warnings
/options:strict unrecognized compiler options are an error
/limitTemplateNotes:N limit the number of context messages when the compiler
                      detects a runaway template instantiation (default N=25)
```

stderr:
```
Microsoft (R) C/C++ Optimizing Compiler Version 19.51.36256 for x64
Copyright (C) Microsoft Corporation.  All rights reserved.
```

files on disk after the run (C:\p\p01):
```
       567  bar.obj
        28  baz.c
       567  baz.obj
        28  foo.c
       567  foo.obj
        28  sub\bar.c
```

## Environment recorded for this family

```
VCToolsVersion=14.51.36231
VCToolsInstallDir=C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\
VCINSTALLDIR=C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\
VisualStudioVersion=18.0
VSCMD_VER=18.9.2
Platform=x64
VSLANG=
ANSICodePage=1252
OEMCodePage=437
CurrentCulture=en-US
```
