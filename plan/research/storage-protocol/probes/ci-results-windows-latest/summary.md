## storage-protocol probes — windows-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343

### machine

```
MINGW64_NT-10.0-26100 runnervmvmocb 3.6.10-710e5275.x86_64 2026-07-28 09:32 UTC x86_64 Msys
model name	: AMD EPYC 7763 64-Core Processor                
4
cpu flags of interest: avx2 sha_ni 
D:             157284348 3261508 154022840   3% /d
go version go1.26.8 windows/amd64
```

### ratio and container-overhead tables

```
go: downloading github.com/klauspost/compress v1.20.0
go: downloading github.com/pierrec/lz4/v4 v4.1.27
file                        raw        lz4    ratio         s2    ratio  s2-better    ratio     zstd-1    ratio     zstd-3    ratio     zstd-9    ratio
testdata/small.o           6973       4458    0.639       4292    0.616       4014    0.576       3149    0.452       3039    0.436       2966    0.425
testdata/mid.o           343092     163641    0.477     164258    0.479     151990    0.443     111262    0.324     108241    0.315      99850    0.291
testdata/big_g1.o       1278766     402652    0.315     400500    0.313     372459    0.291     273642    0.214     263834    0.206     237477    0.186
testdata/big.o          3776318    1488614    0.394    1482036    0.392    1391084    0.368     955945    0.253     923364    0.245     837097    0.222
testdata/mid.d            11738       2061    0.176       2043    0.174       1913    0.163       1399    0.119       1333    0.114       1212    0.103
format                      bytes   overhead      pct
framed (ACE1)              397722        +72   0.018%
tar (ustar)                401408      +3758   0.945%
tar + manifest.json        402432      +4782   1.203%
zip (stored)               398100       +450   0.113%
zip (deflate)              125838    -271812 -68.355%
raw member bytes           397650
    restore_portable_test.go:156: GOOS=windows: rename over an OPEN file FAILS (rename C:\Users\RUNNER~1\AppData\Local\Temp\TestRenameOverOpenFile3120105279\001\entry.part C:\Users\RUNNER~1\AppData\Local\Temp\TestRenameOverOpenFile3120105279\001\entry: Access is denied.). A store must rename the old entry aside and delete it, or retry.
    restore_portable_test.go:184: GOOS=windows: unlinking an OPEN file FAILS (remove C:\Users\RUNNER~1\AppData\Local\Temp\TestUnlinkOpenFile159282216\001\entry: The process cannot access the file because it is being used by another process.). Eviction must skip or retry an entry a reader holds.
    restore_portable_test.go:214: GOOS=windows: a 356-character path works

```

### binpazer round trip

```
go: downloading github.com/klauspost/compress v1.19.1
    binpazer_test.go:318: streamed file: len=125424 hasIndex=false
    binpazer_test.go:320: Find(directory) -> [], err=binpazer: block payload claims 6762810245124 bytes but only 0 remain in the input: binpazer: truncated input
    binpazer_test.go:331: seekable file: len=125424 hasIndex=true Find(directory) -> [125096] err=<nil>
    binpazer_test.go:450: stored       file=398232 raw=397650 overhead=+582 (0.146%)
    binpazer_test.go:450: stored+crc   file=398248 raw=397650 overhead=+598 (0.150%)
    binpazer_test.go:450: zstd         file=125424 raw=397650 overhead=-272226 (-68.459%)
    binpazer_test.go:450: zstd+crc     file=125456 raw=397650 overhead=-272194 (-68.451%)
    binpazer_test.go:450: lz4          file=186816 raw=397650 overhead=-210834 (-53.020%)

```

### benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkEncode/lz4/testdata/small.o` | 123794 | 19648 | 354.90 MB/s 0.6393 ratio 576 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 49536 | 49305 | 141.42 MB/s 0.4516 ratio 8204 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 37116 | 64767 | 107.66 MB/s 0.4358 ratio 8236 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 9554 | 250715 | 27.81 MB/s 0.4254 ratio 13715 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 316324 | 7690 | 906.77 MB/s 0.6155 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 149145 | 16135 | 432.18 MB/s 0.5756 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 5850 | 384658 | 18.13 MB/s 0.4330 ratio 813700 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1639 | 1470741 | 233.28 MB/s 0.4770 ratio 5704 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 1064 | 2236237 | 153.42 MB/s 0.3243 ratio 352846 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 814 | 2912222 | 117.81 MB/s 0.3155 ratio 367624 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 122 | 20017458 | 17.14 MB/s 0.2910 ratio 782640 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 3946 | 575193 | 596.48 MB/s 0.4788 ratio 103 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 2103 | 1127118 | 304.40 MB/s 0.4430 ratio 444 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 193 | 12476481 | 27.50 MB/s 0.3182 ratio 815053 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 600 | 3976334 | 321.59 MB/s 0.3149 ratio 15531 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 417 | 5726020 | 223.33 MB/s 0.2140 ratio 1202099 B/op 10 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 343 | 7110896 | 179.83 MB/s 0.2063 ratio 1194625 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 50 | 40401170 | 31.65 MB/s 0.1857 ratio 2151576 B/op 9 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1261 | 1801245 | 709.93 MB/s 0.3132 ratio 1072 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 652 | 3444538 | 371.24 MB/s 0.2913 ratio 3783 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 72 | 31154492 | 41.05 MB/s 0.2197 ratio 828256 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 176 | 13422592 | 281.34 MB/s 0.3942 ratio 57337 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 100 | 20319621 | 185.85 MB/s 0.2531 ratio 4468061 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 92 | 24092724 | 156.74 MB/s 0.2445 ratio 4542585 B/op 14 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 12 | 170214075 | 22.19 MB/s 0.2217 ratio 8697904 B/op 18 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 421 | 6022971 | 626.99 MB/s 0.3925 ratio 9127 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 204 | 11536841 | 327.33 MB/s 0.3684 ratio 21406 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 21 | 109174900 | 34.59 MB/s 0.2615 ratio 913545 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 190116 | 12550 | 935.29 MB/s 0.1756 ratio 469 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 73795 | 33528 | 350.09 MB/s 0.1136 ratio 12310 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 18044 | 130935 | 89.65 MB/s 0.1033 ratio 15212 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 86896 | 28721 | 408.70 MB/s 0.1192 ratio 12295 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 499689 | 4725 | 2484.12 MB/s 0.1741 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 210519 | 11733 | 1000.44 MB/s 0.1630 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 10174 | 232724 | 50.44 MB/s 0.1009 ratio 813698 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 589560 | 3979 | 1752.32 MB/s 174 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 792243 | 3172 | 2198.61 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 136848 | 16733 | 416.71 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 153800 | 15886 | 438.93 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 159447 | 16024 | 435.17 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 10000 | 214109 | 1602.42 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 8479 | 240267 | 1427.96 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 4934 | 542353 | 632.60 MB/s 108 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4632 | 536585 | 639.40 MB/s 74 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 4402 | 541861 | 633.17 MB/s 78 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 3006 | 776687 | 1646.44 MB/s 1555 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 2916 | 817539 | 1564.16 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1458 | 1503467 | 850.54 MB/s 886 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1712 | 1436966 | 889.91 MB/s 782 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1754 | 1427212 | 895.99 MB/s 737 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 877 | 2513219 | 1502.58 MB/s 9726 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 927 | 2638467 | 1431.25 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 450 | 5320148 | 709.81 MB/s 8407 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 493 | 4962564 | 760.96 MB/s 7873 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 494 | 4585080 | 823.61 MB/s 7647 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 566540 | 4264 | 2753.12 MB/s 167 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 1000000 | 2418 | 4854.15 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 236491 | 10201 | 1150.68 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 231098 | 9845 | 1192.31 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 253951 | 9534 | 1231.22 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 33561176 | 72.78 | 95809.49 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 271678 | 8353 | 41075.81 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 46248 | 52745 | 24244.15 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 15632 | 154052 | 24513.32 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 19678969 | 120.0 | 97831.28 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 2562158 | 1005 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 1000000 | 2019 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 11038232 | 196.4 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 14357458 | 164.5 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 12491197 | 187.9 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 3891 | 576211 | 595.43 MB/s 56 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 3384 | 658967 | 520.65 MB/s 950527 B/op 26 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 2656 | 775060 | 442.67 MB/s 8387593 B/op 6 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 12014 | 200272 | 1713.13 MB/s 858 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 13592 | 171181 | 2322.98 MB/s 1032320 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 10000 | 214204 | 1856.41 MB/s 1034027 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 10000 | 237841 | 1671.91 MB/s 1064461 B/op 68 allocs/op |
| `BenchmarkContainerPack/zipStored` | 10000 | 220949 | 1799.74 MB/s 1042380 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 30919666 | 80.39 | 4946737.93 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 35631 | 68273 | 5824.38 MB/s 401901 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 13862 | 172191 | 2309.35 MB/s 839556 B/op 108 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.899 | 180633328.59 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 28448 | 71629 | 4789.83 MB/s 344250 B/op 2 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 27309 | 98570 | 3480.70 MB/s 346786 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 12247 | 196184 | 1748.83 MB/s 718518 B/op 53 allocs/op |
| `BenchmarkStat` | 97160 | 22157 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 194937 | 11732 | 208 B/op 2 allocs/op |
| `BenchmarkOpenClose` | 102633 | 24482 | 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 67052 | 31719 | 129.13 MB/s 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 58764 | 40802 | 5019.32 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 45897 | 52550 | 9976.89 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 5086 | 539352 | 9720.70 MB/s 360 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 43843 | 53900 | 10259.07 MB/s 376 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 16190 | 147340 | 3752.95 MB/s 1440 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 870801 | 2771 | 1477.98 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18460 | 130101 | 1574.16 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7239 | 332467 | 1576.96 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 723 | 3323093 | 1577.71 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 13864809 | 174.1 | 23520.63 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 267282 | 8753 | 23396.64 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 103408 | 23225 | 22574.14 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 9945 | 239504 | 21890.55 MB/s 0 B/op 0 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 2725 | 844168 | 242.61 MB/s 1344 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 2637 | 903113 | 580.53 MB/s 1344 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 694 | 3136072 | 1671.80 MB/s 1329 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 373 | 6502084 | 31.50 MB/s 1377 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 277 | 9623380 | 54.48 MB/s 1378 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 100 | 29689684 | 176.59 MB/s 1382 B/op 9 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 5089 | 516643 | 396.40 MB/s 592 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 6272 | 537635 | 975.17 MB/s 592 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 6620 | 559881 | 9364.27 MB/s 576 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 30496 | 74224 | 4622.41 MB/s 346595 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 44073 | 53273 | 6440.26 MB/s 344241 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 13656 | 176839 | 2248.66 MB/s 911229 B/op 54 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 14589 | 161626 | 2460.30 MB/s 911221 B/op 58 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 436 | 5658744 | 70.27 MB/s 28286426 B/op 291 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1299 | 1834605 | 216.75 MB/s 1221603 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 12666 | 193766 | 2052.21 MB/s 899780 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 12468 | 194652 | 2042.88 MB/s 899782 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1279 | 1822239 | 218.22 MB/s 11901487 B/op 305 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 6244 | 380855 | 1044.10 MB/s 975112 B/op 148 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 14229 | 169539 | 2023.68 MB/s 779347 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 10000 | 230469 | 1488.67 MB/s 779347 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1389 | 1683759 | 203.77 MB/s 11482753 B/op 137 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 5955 | 365957 | 937.52 MB/s 834132 B/op 85 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 20008 | 123801 | 2771.31 MB/s 411858 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1486 | 1670792 | 205.35 MB/s 11115380 B/op 117 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2347 | 858546 | 399.62 MB/s 8799293 B/op 67 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 9444 | 254520 | 1347.99 MB/s 779443 B/op 77 allocs/op |

