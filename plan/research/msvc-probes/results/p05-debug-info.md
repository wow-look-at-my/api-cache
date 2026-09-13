# Probe 5: /Z7 vs /Zi vs /ZI, the shared PDB, /Fd naming

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p05-debug-info/` in this artifact.

### Z7-single

/Z7 on one source. msvc.md §3: cacheable, the object is self-contained. Is there ANY sibling file?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Foa.obj a.c`
cwd: `C:\p\p05-Z7`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Z7):
```
        34  a.c
      1952  a.obj
        34  b.c
```

### Z7-second-source

A second /Z7 compile into the same directory. Still no shared file?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Fob.obj b.c`
cwd: `C:\p\p05-Z7`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
b.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Z7):
```
        34  a.c
      1952  a.obj
        34  b.c
      1953  b.obj
```

### Zi-first

/Zi with no /Fd. What is the default PDB name? (msvc.md §13 assumes vc143.pdb.)

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Foa.obj a.c`
cwd: `C:\p\p05-Zi`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

after the FIRST /Zi compile (C:\p\p05-Zi):
```
        34  a.c
       984  a.obj
        34  b.c
     69632  vc140.pdb
```

### Zi-second

A SECOND /Zi compile in the same directory, into the same default PDB. This is the accumulator msvc.md §3 describes.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fob.obj b.c`
cwd: `C:\p\p05-Zi`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
b.c
```

stderr:
```
(empty)
```

after the SECOND /Zi compile (C:\p\p05-Zi):
```
        34  a.c
       984  a.obj
        34  b.c
       985  b.obj
     69632  vc140.pdb
```

## Is the PDB an accumulator?

```
default PDB name        : vc140.pdb
size after compile 1    : 69632
sha256 after compile 1  : 9B5FD5E5F4FA729A9E222ECEB1C134193872084A3EC795D25E061E44F4C443C5
size after compile 2    : 69632
sha256 after compile 2  : AFC6CC5C7853844EC5D15C456AA477BE92395F6159EB50A81F8307575F4C5B4E
PDB changed by the second, unrelated compile: True
```

### Zi-reordered-b-first

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fob.obj b.c`
cwd: `C:\p\p05-Zi-reordered`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
b.c
```

stderr:
```
(empty)
```

### Zi-reordered-a-second

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Foa.obj a.c`
cwd: `C:\p\p05-Zi-reordered`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

after both compiles, b.c first (C:\p\p05-Zi-reordered):
```
        34  a.c
      1008  a.obj
        34  b.c
      1009  b.obj
     69632  vc140.pdb
```

```
PDB sha256, a.c then b.c : AFC6CC5C7853844EC5D15C456AA477BE92395F6159EB50A81F8307575F4C5B4E
PDB sha256, b.c then a.c : 368AEDCC6ECB8B4B7119771B3B0B0F9B7E818F58E9EB08535C2E4325C149FB52
PDB is order-dependent   : True
a.obj sha256, compiled 1st: 6D9350F5A22D06F72180FDADD2A4C9081A85561DC1CCBF3901FBE4991A760E49
a.obj sha256, compiled 2nd: 0DF31271A7A34EF62949CE85BCCE81BFC28A973609C6ECD05560F7C6B5585756
the OBJECT is order-dependent under /Zi: True
```

### Fd-with-extension

/Fd<name>.pdb

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fdcustom.pdb /Foa.obj a.c`
cwd: `C:\p\p05-Fd-with-extension`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Fd-with-extension):
```
        34  a.c
      1028  a.obj
        34  b.c
     69632  custom.pdb
```

### Fd-no-extension

/Fd<name> with NO extension. msvc.md §3: "sccache appends .pdb if the /Fd value has no extension". Does cl?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fdcustom /Foa.obj a.c`
cwd: `C:\p\p05-Fd-no-extension`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Fd-no-extension):
```
        34  a.c
      1020  a.obj
        34  b.c
     69632  custom.pdb
```

### Fd-colon

/Fd:<name> -- the colon form msvc.md §14 claims for /Fd

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fd:custom.pdb /Foa.obj a.c`
cwd: `C:\p\p05-Fd-colon`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Fd-colon):
```
        34  a.c
      1000  a.obj
        34  b.c
     69632  custom.pdb
```

### Fd-directory

/Fd<dir>\ with the directory existing

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fdpdbs\ /Foa.obj a.c`
cwd: `C:\p\p05-Fd-directory`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Fd-directory):
```
        34  a.c
      1016  a.obj
        34  b.c
     69632  pdbs\vc140.pdb
```

### Fd-with-Z7

/Fd together with /Z7. msvc.md §3: "the PDB path does not change the object under /Z7". Is a PDB even written?

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Fdignored.pdb /Foa.obj a.c`
cwd: `C:\p\p05-Fd-with-Z7`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Fd-with-Z7):
```
        34  a.c
      1984  a.obj
        34  b.c
```

### Z7-Fd-one

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Fdone.pdb /Foone.obj a.c`
cwd: `C:\p\p05-Z7-Fd-object-identity`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

### Z7-Fd-two

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Fdtwo.pdb /Fotwo.obj a.c`
cwd: `C:\p\p05-Z7-Fd-object-identity`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

## Does /Fd change the object under /Z7? (ccache's add_compiler_only_arg_no_hash rests on "no".)

```
object with /Fdone.pdb : 0ADC6EF9C4C2DEA8C5DE8488C07480701F90089872DCC90B8FE13F41AFB17ADA
object with /Fdtwo.pdb : CABD2542CA6C213320A092304E401788CD2F754E33C03B0E8520E9076EE69923
identical              : False
```

files on disk after the run (C:\p\p05-Z7-Fd-object-identity):
```
        34  a.c
        34  b.c
      2024  one.obj
      2024  two.obj
```

### Zi-Fd-one

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fdone.pdb /Foone.obj a.c`
cwd: `C:\p\p05-Zi-Fd-object-identity`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

### Zi-Fd-two

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Fdtwo.pdb /Fotwo.obj a.c`
cwd: `C:\p\p05-Zi-Fd-object-identity`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

```
under /Zi, object with /Fdone.pdb : 33621A6E9D95FADA70DC03CDF85EAFEEAE8AD6088F6385A638211405021470A8
under /Zi, object with /Fdtwo.pdb : 252B24A785A04B257A3E2F0B5CABE52DD0477FB06780FFAFD3CCD171A839DFDA
identical                         : False
```

`one.obj` contains the literal string `one.pdb`: **True**
`two.obj` contains the literal string `two.pdb`: **True**

files on disk after the run (C:\p\p05-Zi-Fd-object-identity):
```
        34  a.c
        34  b.c
      1036  one.obj
     69632  one.pdb
      1036  two.obj
     69632  two.pdb
```

### ZI-edit-continue

/ZI. msvc.md §3: "/Zi plus edit-and-continue; implies /FC". Which files appear? (.idb is the edit-and-continue state.)

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /ZI /Foa.obj a.c`
cwd: `C:\p\p05-ZI`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-ZI):
```
        34  a.c
      1546  a.obj
        34  b.c
     19456  vc140.idb
     69632  vc140.pdb
```

### Zi-FS

/FS: force synchronous PDB writes. msvc.md §3 calls it added-but-not-hashed.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /FS /Foa.obj a.c`
cwd: `C:\p\p05-FS`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 0 bytes

stdout:
```
a.c
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-FS):
```
        34  a.c
       984  a.obj
        34  b.c
     53248  vc140.pdb
```

### Zi-then-Z7

/Zi /Z7 in that order. ccache records the LAST-seen /Z option. Is a PDB written? (If not, last-wins is confirmed.)

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Z7 /Foa.obj a.c`
cwd: `C:\p\p05-Z-last-wins`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 63 bytes

stdout:
```
a.c
```

stderr:
```
cl : Command line warning D9025 : overriding '/Zi' with '/Z7'
```

files on disk after the run (C:\p\p05-Z-last-wins):
```
        34  a.c
      1988  a.obj
        34  b.c
```

### Z7-then-Zi

The reverse order.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Zi /Fob.obj b.c`
cwd: `C:\p\p05-Z-last-wins`

exit code: **0**  |  stdout: 5 bytes  |  stderr: 63 bytes

stdout:
```
b.c
```

stderr:
```
cl : Command line warning D9025 : overriding '/Z7' with '/Zi'
```

files on disk after the run (C:\p\p05-Z-last-wins):
```
        34  a.c
      1988  a.obj
        34  b.c
      1009  b.obj
     69632  vc140.pdb
```

### Zi-compile-and-link

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /Zi a.c b.c /Feab.exe`
cwd: `C:\p\p05-Zi-link`

exit code: **2**  |  stdout: 87 bytes  |  stderr: 0 bytes

stdout:
```
a.c
b.c
Generating Code...
LINK : fatal error LNK1561: entry point must be defined
```

stderr:
```
(empty)
```

files on disk after the run (C:\p\p05-Zi-link):
```
        34  a.c
       996  a.obj
    101376  ab.pdb
        34  b.c
       997  b.obj
     69632  vc140.pdb
```

