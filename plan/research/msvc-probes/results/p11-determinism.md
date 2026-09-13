# Probe 11: object reproducibility, /Brepro, /d1trimfile, __DATE__ / __TIME__

Runner: `win25-vs2026 / 20260907.229.1` on `Windows`.
Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34731245969

Raw captures (stdout / stderr / exit code, one file each) are under `p11-determinism/` in this artifact.

### same-dir-Z7-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Forun1.obj det.c`
cwd: `C:\p\p11-Z7`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### same-dir-Z7-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Forun2.obj det.c`
cwd: `C:\p\p11-Z7`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### two runs, same directory, flags: /Z7 (none = no debug flag)

```
run 1 : 3BD814F62B7A5B9B7301D23EB4600E1A5A18FDB0722A22CB0F578464FDCE0696  (2021 bytes)  run1.obj
run 2 : AB6B5C594379E944405364B08161356952F6B2F5DA90D045D7CDEE401055B9AA  (2021 bytes)  run2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 01 00 a6 6a f7 06 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 03 00 a6 6a f7 06 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 10 of 2021
```

files on disk after the run (C:\p\p11-Z7):
```
        57  det.c
        29  det.h
      2021  run1.obj
      2021  run2.obj
       157  stamp.c
```

### same-dir-Zi-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Forun1.obj det.c`
cwd: `C:\p\p11-Zi`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### same-dir-Zi-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Zi /Forun2.obj det.c`
cwd: `C:\p\p11-Zi`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### two runs, same directory, flags: /Zi (none = no debug flag)

```
run 1 : D94D2F932EA9E3ECBEC582F4EDCB10DBAB027B4072D5B8A286FBB1426E8F1016  (1049 bytes)  run1.obj
run 2 : 3CA55863EFD1D350F3A6A3C9238586CBDDAED4769A0527CD6D2BD42A75A6197B  (1049 bytes)  run2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 03 00 a6 6a 2b 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 05 00 a6 6a 2b 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 19 of 1049
```

files on disk after the run (C:\p\p11-Zi):
```
        57  det.c
        29  det.h
      1049  run1.obj
      1049  run2.obj
       157  stamp.c
     69632  vc140.pdb
```

### same-dir-none-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Forun1.obj det.c`
cwd: `C:\p\p11-none`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### same-dir-none-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Forun2.obj det.c`
cwd: `C:\p\p11-none`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### two runs, same directory, flags:  (none = no debug flag)

```
run 1 : 1CEE3E36D1B07AFC017432C9B661621F62B9C803B6BDF3F4964214319858582B  (577 bytes)  run1.obj
run 2 : 3DF99F636CB10D76396401D3442A042249A2A7536CC77840554DCF70E603F8C5  (577 bytes)  run2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 04 00 05 00 a6 6a 77 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 04 00 07 00 a6 6a 77 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 10 of 577
```

files on disk after the run (C:\p\p11-none):
```
        57  det.c
        29  det.h
       577  run1.obj
       577  run2.obj
       157  stamp.c
```

### same-dir-Brepro-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Brepro /Forun1.obj det.c`
cwd: `C:\p\p11-Brepro`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### same-dir-Brepro-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Brepro /Forun2.obj det.c`
cwd: `C:\p\p11-Brepro`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### two runs, same directory, flags: /Brepro (none = no debug flag)

```
run 1 : 160CBE56C54656537435D0B60A323E4F3AA5A8847FD73111F1A4356718E6F5E3  (581 bytes)  run1.obj
run 2 : 496D259BB5EA215ABBC754F6821046633EC0B6D26418657BB61B16E308DFBE7C  (581 bytes)  run2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 04 00 c6 f9 ac eb 7b 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 04 00 46 46 df d7 7b 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 13 of 581
```

files on disk after the run (C:\p\p11-Brepro):
```
        57  det.c
        29  det.h
       581  run1.obj
       581  run2.obj
       157  stamp.c
```

### same-dir-Z7-Brepro-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Brepro /Forun1.obj det.c`
cwd: `C:\p\p11-Z7-Brepro`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### same-dir-Z7-Brepro-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Brepro /Forun2.obj det.c`
cwd: `C:\p\p11-Z7-Brepro`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### two runs, same directory, flags: /Z7 /Brepro (none = no debug flag)

```
run 1 : BB9C501B870CCF591A71D010DC0F87C572A8429CEBC6E374E844DC0DC4139B90  (1185 bytes)  run1.obj
run 2 : D7D94C50A0F502716BAFC3DADC6C142389530B129E07AF50139EFBF5CC7217D6  (1185 bytes)  run2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 aa 40 ff d3 b3 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 9c 20 5d da b3 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 13 of 1185
```

files on disk after the run (C:\p\p11-Z7-Brepro):
```
        57  det.c
        29  det.h
      1185  run1.obj
      1185  run2.obj
       157  stamp.c
```

### pathA-Z7

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /FoZ7.obj det.c`
cwd: `C:\p\p11-pathA`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### pathB-Z7

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /FoZ7.obj det.c`
cwd: `C:\p\p11-path-a-much-longer-directory-name-B`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### same source, two different absolute directories, flags: /Z7

```
run 1 : 62EEE20B6F1766FDBF2DBBA0187AC38266426A1D06A589243BCEFAC853E0083B  (2033 bytes)  Z7.obj
run 2 : 08F3E716E73A7266F0235C93A722CBB08E07B2F786665CA084572A07508DC2E3  (2181 bytes)  Z7.obj
byte-identical : False
first differing byte offset : 8 (0x8)
window at 0x0, run 1 : 64 86 05 00 0c 00 a6 6a 03 07 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
window at 0x0, run 2 : 64 86 05 00 0c 00 a6 6a 97 07 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
differing bytes in the common prefix : 1592 of 2033
```

`C:\p\p11-pathA\Z7.obj` contains its own directory path as a literal string: **True**
`C:\p\p11-path-a-much-longer-directory-name-B\Z7.obj` contains its own directory path as a literal string: **True**

### pathA-none

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fonone.obj det.c`
cwd: `C:\p\p11-pathA`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### pathB-none

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fonone.obj det.c`
cwd: `C:\p\p11-path-a-much-longer-directory-name-B`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### same source, two different absolute directories, flags: 

```
run 1 : 96E932072723F27FD7669B48EE4A4F3F3225C97A2F45B7E34E8018F1F06B1868  (577 bytes)  none.obj
run 2 : FA3FFDC888CEBA0E3F7F532B40032942C1C44DC5FEECD3AE48F85879A762C758  (609 bytes)  none.obj
byte-identical : False
first differing byte offset : 8 (0x8)
window at 0x0, run 1 : 64 86 04 00 0c 00 a6 6a 77 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
window at 0x0, run 2 : 64 86 04 00 0c 00 a6 6a 97 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
differing bytes in the common prefix : 261 of 577
```

`C:\p\p11-pathA\none.obj` contains its own directory path as a literal string: **True**
`C:\p\p11-path-a-much-longer-directory-name-B\none.obj` contains its own directory path as a literal string: **True**

### Z7-no-trim

An ABSOLUTE source path under /Z7, with no trimming.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Fonotrim.obj C:\p\p11-trimfile\det.c`
cwd: `C:\p\p11-trimfile`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### Z7-d1trimfile

/d1trimfile:<dir>\ -- the undocumented switch that strips a prefix from the paths the compiler embeds.

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /d1trimfile:C:\p\p11-trimfile\ /Fotrim.obj C:\p\p11-trimfile\det.c`
cwd: `C:\p\p11-trimfile`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

`notrim.obj` contains the literal directory `C:\p\p11-trimfile`: **True**  |  size 2069
`trim.obj` contains the literal directory `C:\p\p11-trimfile`: **True**  |  size 2073

#### /Z7 with and without /d1trimfile

```
run 1 : 6872CB7B21049CB5D833561D241E516CA05C088003129A33CE2E8259091D6A6C  (2069 bytes)  notrim.obj
run 2 : E4DAAE5F1163263128661FF9955B6A2302085EE436440129F7B3A740FF582A1B  (2073 bytes)  trim.obj
byte-identical : False
first differing byte offset : 8 (0x8)
window at 0x0, run 1 : 64 86 05 00 0c 00 a6 6a 27 07 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
window at 0x0, run 2 : 64 86 05 00 0c 00 a6 6a 2b 07 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00 2f 00 00 00
differing bytes in the common prefix : 1508 of 2069
```

files on disk after the run (C:\p\p11-trimfile):
```
        57  det.c
        29  det.h
      2069  notrim.obj
       157  stamp.c
      2073  trim.obj
```

### Brepro-pathA

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Brepro /Fobr.obj det.c`
cwd: `C:\p\p11-breproA`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### Brepro-pathB

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Z7 /Brepro /Fobr.obj det.c`
cwd: `C:\p\p11-brepro-longer-dir-B`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### /Z7 /Brepro from two different directories

```
run 1 : D5C923C937D30F99EAF7553A42E3049CFFECA5128BD6A536D4D37C0C4BD80523  (1177 bytes)  br.obj
run 2 : 283A4D3D2873DF93940DA4AB9C763A1C5B331CC862A9652242BDA95DD50BB3AB  (1213 bytes)  br.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 e4 0f 3f ec ab 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 18 8e d1 d2 cf 03 00 00 0d 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 635 of 1177
```

### stamp-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fostamp1.obj stamp.c`
cwd: `C:\p\p11-stamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

Sleeping 3 seconds. `__TIME__` expands to HH:MM:SS, so seconds are enough to move it.

### stamp-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fostamp2.obj stamp.c`
cwd: `C:\p\p11-stamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### __DATE__/__TIME__/__TIMESTAMP__ source, two runs a few seconds apart

```
run 1 : C1551AFFBF963EEFD807BFA2C843993CD23FDEB38A760D00FF3BBCA4CE701E19  (904 bytes)  stamp1.obj
run 2 : C98F368445EDB3B85C513B2A0E1F550BB39B011E11035D25D2E553B1FAFCEAC0  (904 bytes)  stamp2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 0d 00 a6 6a 1e 02 00 00 12 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 10 00 a6 6a 1e 02 00 00 12 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 23 of 904
```

### stamp-brepro-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Brepro /Fobs1.obj stamp.c`
cwd: `C:\p\p11-stamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### stamp-brepro-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Brepro /Fobs2.obj stamp.c`
cwd: `C:\p\p11-stamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### the same source with /Brepro, two runs a few seconds apart -- /Brepro must NOT fix this

```
run 1 : D00EC4EE59DECBAFFC1FA70B3CB73078BEE54EA26CC54A37A2663B73FD41515C  (853 bytes)  bs1.obj
run 2 : 86658A0E468A29E8638CFE183D1490255AE9376F04A5290E37DA9AC310C39903  (853 bytes)  bs2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 05 00 8a 6b 10 e7 eb 01 00 00 12 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 05 00 7a 6c a6 f0 eb 01 00 00 12 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 13 of 853
```

`stamp1.obj` embedded HH:MM:SS strings: `01:44:45`
`stamp2.obj` embedded HH:MM:SS strings: `01:44:48, 01:44:45`
`bs1.obj` embedded HH:MM:SS strings: ``
`bs2.obj` embedded HH:MM:SS strings: ``

The `__TIMESTAMP__` expansion is the source file's own mtime, not the compile time, so it moves only when the file is touched. The `__TIME__` strings above are the ones that move per run.

### nostamp-run1

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fon1.obj det.c`
cwd: `C:\p\p11-nostamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

### nostamp-run2

cmd: `C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\14.51.36231\bin\HostX64\x64\cl.exe /nologo /c /Fon2.obj det.c`
cwd: `C:\p\p11-nostamp`

exit code: **0**  |  stdout: 0 bytes  |  stderr: 0 bytes

stdout:
```
(empty)
```

stderr:
```
(empty)
```

#### a source with no temporal macro, two runs a few seconds apart

```
run 1 : B05C3E3B695752CB9101750C731D3414BB4B65CD042D1D20043555454236D5B2  (577 bytes)  n1.obj
run 2 : 19553DC0875B2E1FA19913A8A266D25FBCC727727F87A4AC6D1BB6A0BEEDF606  (577 bytes)  n2.obj
byte-identical : False
first differing byte offset : 4 (0x4)
window at 0x0, run 1 : 64 86 04 00 13 00 a6 6a 77 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
window at 0x0, run 2 : 64 86 04 00 16 00 a6 6a 77 01 00 00 0b 00 00 00 00 00 00 00 2e 64 72 65 63 74 76 65 00 00 00 00 00 00 00 00
differing bytes in the common prefix : 10 of 577
```

files on disk after the run (C:\p\p11-stamp):
```
       853  bs1.obj
       853  bs2.obj
        57  det.c
        29  det.h
       157  stamp.c
       904  stamp1.obj
       904  stamp2.obj
```

