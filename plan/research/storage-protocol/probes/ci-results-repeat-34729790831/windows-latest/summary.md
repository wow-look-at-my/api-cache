## storage-protocol probes — windows-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729790831

### machine

```
MINGW64_NT-10.0-26100 runnervmvmocb 3.6.10-710e5275.x86_64 2026-07-28 09:32 UTC x86_64 Msys
model name	: AMD EPYC 7763 64-Core Processor                
4
cpu flags of interest: avx2 sha_ni 
D:             157284348 3261644 154022704   3% /d
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
    restore_portable_test.go:156: GOOS=windows: rename over an OPEN file FAILS (rename C:\Users\RUNNER~1\AppData\Local\Temp\TestRenameOverOpenFile1471321227\001\entry.part C:\Users\RUNNER~1\AppData\Local\Temp\TestRenameOverOpenFile1471321227\001\entry: Access is denied.). A store must rename the old entry aside and delete it, or retry.
    restore_portable_test.go:184: GOOS=windows: unlinking an OPEN file FAILS (remove C:\Users\RUNNER~1\AppData\Local\Temp\TestUnlinkOpenFile2268248763\001\entry: The process cannot access the file because it is being used by another process.). Eviction must skip or retry an entry a reader holds.
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
| `BenchmarkEncode/lz4/testdata/small.o` | 105850 | 19359 | 360.20 MB/s 0.6393 ratio 484 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 36614 | 65387 | 106.64 MB/s 0.4358 ratio 8237 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 9444 | 252500 | 27.62 MB/s 0.4254 ratio 13780 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 49204 | 49698 | 140.31 MB/s 0.4516 ratio 8204 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 312700 | 7567 | 921.56 MB/s 0.6155 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 148026 | 16134 | 432.20 MB/s 0.5756 ratio 1 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 5220 | 394863 | 17.66 MB/s 0.4330 ratio 813701 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1622 | 1464242 | 234.31 MB/s 0.4770 ratio 5846 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 1075 | 2235543 | 153.47 MB/s 0.3243 ratio 352757 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 823 | 2905442 | 118.09 MB/s 0.3155 ratio 367366 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 154 | 15995992 | 21.45 MB/s 0.2910 ratio 691507 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 4266 | 563726 | 608.62 MB/s 0.4788 ratio 96 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 2071 | 1132900 | 302.84 MB/s 0.4430 ratio 451 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 196 | 12189714 | 28.15 MB/s 0.3182 ratio 815033 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 604 | 3939736 | 324.58 MB/s 0.3149 ratio 15200 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 415 | 5722713 | 223.45 MB/s 0.2140 ratio 1202208 B/op 10 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 338 | 7053009 | 181.31 MB/s 0.2063 ratio 1195453 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 46 | 44635107 | 28.65 MB/s 0.1857 ratio 2244638 B/op 10 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1383 | 1727789 | 740.12 MB/s 0.3132 ratio 977 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 718 | 3327385 | 384.32 MB/s 0.2913 ratio 2614 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 78 | 29237053 | 43.74 MB/s 0.2197 ratio 827136 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 169 | 14136629 | 267.13 MB/s 0.3942 ratio 59693 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 124 | 19154515 | 197.15 MB/s 0.2531 ratio 4449963 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 94 | 22750590 | 165.99 MB/s 0.2445 ratio 4538143 B/op 14 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 12 | 175756000 | 21.49 MB/s 0.2217 ratio 8697904 B/op 18 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 432 | 5557185 | 679.54 MB/s 0.3925 ratio 8894 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 206 | 11540551 | 327.22 MB/s 0.3684 ratio 21200 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 21 | 108683833 | 34.75 MB/s 0.2615 ratio 913545 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 191984 | 12707 | 923.73 MB/s 0.1756 ratio 493 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 84878 | 29001 | 404.74 MB/s 0.1192 ratio 12295 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 70512 | 33768 | 347.61 MB/s 0.1136 ratio 12311 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 17918 | 132758 | 88.42 MB/s 0.1033 ratio 15233 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 507092 | 4728 | 2482.44 MB/s 0.1741 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 210884 | 11351 | 1034.08 MB/s 0.1630 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 11178 | 211129 | 55.60 MB/s 0.1009 ratio 813699 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 611074 | 3893 | 1791.12 MB/s 187 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 791264 | 3059 | 2279.43 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 163077 | 14181 | 491.71 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 168802 | 14182 | 491.68 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 160248 | 15111 | 461.44 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 10000 | 200419 | 1711.87 MB/s 579 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 10000 | 225619 | 1520.67 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 4776 | 501019 | 684.79 MB/s 112 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 4953 | 487006 | 704.49 MB/s 78 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4905 | 489272 | 701.23 MB/s 70 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 3356 | 715823 | 1786.43 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 3013 | 772887 | 1654.53 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1720 | 1397727 | 914.89 MB/s 751 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1818 | 1319811 | 968.90 MB/s 736 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1870 | 1288998 | 992.06 MB/s 699 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 1029 | 2616766 | 1443.12 MB/s 4237 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 985 | 2498622 | 1511.36 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 478 | 4685243 | 806.00 MB/s 8109 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 522 | 4582564 | 824.06 MB/s 7237 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 500 | 4799384 | 786.83 MB/s 7556 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 456506 | 4456 | 2634.29 MB/s 178 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 998186 | 2458 | 4774.81 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 235818 | 10464 | 1121.79 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 243074 | 10111 | 1160.90 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 245655 | 10100 | 1162.23 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 30019399 | 84.96 | 82074.83 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 217066 | 10843 | 31640.61 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 44544 | 53571 | 23870.28 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 15385 | 156296 | 24161.39 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 20291074 | 119.7 | 98076.22 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 3168271 | 762.3 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 1263788 | 1892 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 12382437 | 181.3 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 15669518 | 161.9 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 14281591 | 180.8 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 4137 | 575988 | 595.66 MB/s 51 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 3184 | 647782 | 529.64 MB/s 950514 B/op 26 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 3175 | 784253 | 437.48 MB/s 8387852 B/op 6 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 10000 | 201003 | 1706.90 MB/s 999 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 13230 | 181595 | 2189.76 MB/s 1032321 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 9859 | 216003 | 1840.95 MB/s 1034025 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 9742 | 243566 | 1632.62 MB/s 1064499 B/op 69 allocs/op |
| `BenchmarkContainerPack/zipStored` | 10000 | 214227 | 1856.21 MB/s 1042381 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 30941670 | 83.21 | 4778964.54 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 33892 | 75438 | 5271.21 MB/s 401939 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 13437 | 177627 | 2238.68 MB/s 839556 B/op 108 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.904 | 180229616.10 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 28057 | 87245 | 3932.52 MB/s 344251 B/op 2 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 24160 | 99117 | 3461.49 MB/s 346622 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 10000 | 216050 | 1588.02 MB/s 718519 B/op 53 allocs/op |
| `BenchmarkStat` | 122443 | 19177 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 218796 | 11242 | 208 B/op 2 allocs/op |
| `BenchmarkOpenClose` | 105025 | 22657 | 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 78640 | 30835 | 132.84 MB/s 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 59739 | 40624 | 5041.31 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 41834 | 56399 | 9296.08 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 4922 | 544519 | 9628.45 MB/s 360 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 41847 | 57102 | 9683.68 MB/s 376 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 15958 | 150252 | 3680.21 MB/s 1440 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 879280 | 2782 | 1472.59 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18252 | 130799 | 1565.76 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7168 | 333437 | 1572.37 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 720 | 3325005 | 1576.80 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 13743153 | 176.2 | 23239.94 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 275158 | 8758 | 23384.92 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 101524 | 23384 | 22420.87 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 9740 | 245085 | 21392.06 MB/s 0 B/op 0 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 2826 | 868448 | 235.82 MB/s 1344 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 2538 | 916341 | 572.15 MB/s 1344 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 898 | 2920915 | 1794.94 MB/s 1329 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 277 | 9504722 | 21.55 MB/s 1377 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 204 | 24369532 | 21.51 MB/s 1379 B/op 9 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 100 | 86142545 | 60.86 MB/s 1378 B/op 9 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 6016 | 551059 | 371.65 MB/s 592 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 5846 | 532118 | 985.28 MB/s 592 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 6496 | 631321 | 8304.62 MB/s 576 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 33490 | 70786 | 4846.87 MB/s 346599 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 40954 | 58427 | 5872.12 MB/s 344242 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 14497 | 163540 | 2431.52 MB/s 911219 B/op 53 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 14092 | 171925 | 2312.93 MB/s 911252 B/op 59 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 448 | 5557485 | 71.55 MB/s 28286387 B/op 290 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1309 | 1842568 | 215.81 MB/s 1237668 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 12198 | 196992 | 2018.61 MB/s 899780 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 12414 | 191979 | 2071.32 MB/s 899781 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1233 | 1851559 | 214.77 MB/s 11901324 B/op 305 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 6262 | 383705 | 1036.34 MB/s 970884 B/op 148 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 13862 | 175906 | 1950.43 MB/s 779346 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 14419 | 164136 | 2090.29 MB/s 779347 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1425 | 1534516 | 223.58 MB/s 11483444 B/op 138 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 6055 | 341253 | 1005.39 MB/s 850547 B/op 85 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 17912 | 128306 | 2674.02 MB/s 411857 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1498 | 1675465 | 204.77 MB/s 11115670 B/op 117 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2652 | 905927 | 378.72 MB/s 8799500 B/op 67 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 9825 | 235142 | 1459.09 MB/s 779436 B/op 77 allocs/op |

