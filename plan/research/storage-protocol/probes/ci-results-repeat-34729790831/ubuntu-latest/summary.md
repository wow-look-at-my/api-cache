## storage-protocol probes — ubuntu-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729790831

### machine

```
Linux runnervmlun5p 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
model name	: AMD EPYC 7763 64-Core Processor
4
cpu flags of interest: avx2 sha_ni 
/dev/root      151263856 61141040  90106432  41% /
go version go1.26.8 linux/amd64
```

### ratio and container-overhead tables

```
go: downloading github.com/klauspost/compress v1.20.0
go: downloading github.com/pierrec/lz4/v4 v4.1.27
file                        raw        lz4    ratio         s2    ratio  s2-better    ratio     zstd-1    ratio     zstd-3    ratio     zstd-9    ratio
testdata/small.o          10232       5294    0.517       5133    0.502       4843    0.473       3597    0.352       3517    0.344       3346    0.327
testdata/mid.o           527880     196256    0.372     201601    0.382     188876    0.358     123626    0.234     123701    0.234     107063    0.203
testdata/big_g1.o       1490416     462647    0.310     468578    0.314     440277    0.295     310109    0.208     300518    0.202     258379    0.173
testdata/big.o          5040872    1635438    0.324    1668713    0.331    1569350    0.311    1022986    0.203     984348    0.195     836709    0.166
testdata/mid.d             9124       2618    0.287       2395    0.262       2244    0.246       1773    0.194       1669    0.183       1471    0.161
format                      bytes   overhead      pct
framed (ACE1)              579896        +72   0.012%
tar (ustar)                583680      +3856   0.665%
tar + manifest.json        584704      +4880   0.842%
zip (stored)               580274       +450   0.078%
zip (deflate)              143192    -436632 -75.304%
raw member bytes           579824
    restore_portable_test.go:165: GOOS=linux: rename over an OPEN file SUCCEEDS; the open handle still reads "old"
    restore_portable_test.go:192: GOOS=linux: unlinking an OPEN file SUCCEEDS; the handle still reads "payload"
    restore_portable_test.go:214: GOOS=linux: a 324-character path works
    restore_test.go:182: FICLONE: NOT SUPPORTED on this filesystem (operation not supported). Reflink restore is unavailable here; ext4 has no reflink support.

```

### binpazer round trip

```
go: downloading github.com/klauspost/compress v1.19.1
    binpazer_test.go:318: streamed file: len=145024 hasIndex=false
    binpazer_test.go:320: Find(directory) -> [], err=binpazer: block payload claims 6762810245124 bytes but only 0 remain in the input: binpazer: truncated input
    binpazer_test.go:331: seekable file: len=145024 hasIndex=true Find(directory) -> [144696] err=<nil>
    binpazer_test.go:450: stored       file=580400 raw=579824 overhead=+576 (0.099%)
    binpazer_test.go:450: stored+crc   file=580424 raw=579824 overhead=+600 (0.103%)
    binpazer_test.go:450: zstd         file=145024 raw=579824 overhead=-434800 (-74.988%)
    binpazer_test.go:450: zstd+crc     file=145048 raw=579824 overhead=-434776 (-74.984%)
    binpazer_test.go:450: lz4          file=225968 raw=579824 overhead=-353856 (-61.028%)

```

### benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkEncode/lz4/testdata/small.o` | 86352 | 27535 | 371.60 MB/s 0.5174 ratio 500 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 41642 | 58142 | 175.98 MB/s 0.3515 ratio 10254 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 33744 | 70562 | 145.01 MB/s 0.3437 ratio 10289 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 7777 | 270640 | 37.81 MB/s 0.3270 ratio 17025 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 233908 | 10197 | 1003.44 MB/s 0.5017 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 121293 | 19715 | 519.00 MB/s 0.4733 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 4430 | 512585 | 19.96 MB/s 0.3405 ratio 813701 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1339 | 1790294 | 294.86 MB/s 0.3718 ratio 6917 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 850 | 2793647 | 188.96 MB/s 0.2342 ratio 543477 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 702 | 3366466 | 156.81 MB/s 0.2343 ratio 559787 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 134 | 17823183 | 29.62 MB/s 0.2028 ratio 930181 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 3062 | 778115 | 678.41 MB/s 0.3819 ratio 195 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 1621 | 1475617 | 357.74 MB/s 0.3578 ratio 692 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 146 | 16283019 | 32.42 MB/s 0.2302 ratio 815490 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 526 | 4513097 | 330.24 MB/s 0.3104 ratio 17503 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 306 | 7793051 | 191.25 MB/s 0.2016 ratio 1406184 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 51 | 43630735 | 34.16 MB/s 0.1734 ratio 1978879 B/op 8 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 355 | 6782055 | 219.76 MB/s 0.2081 ratio 1599243 B/op 11 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1135 | 2110802 | 706.09 MB/s 0.3144 ratio 1371 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 646 | 3800306 | 392.18 MB/s 0.2954 ratio 3221 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 57 | 40828890 | 36.50 MB/s 0.2014 ratio 832086 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 163 | 14644546 | 344.21 MB/s 0.3244 ratio 79065 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 93 | 23016119 | 219.01 MB/s 0.2029 ratio 5507345 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 87 | 25454870 | 198.03 MB/s 0.1953 ratio 5446957 B/op 13 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 13 | 165282113 | 30.50 MB/s 0.1660 ratio 8359675 B/op 16 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 348 | 6887836 | 731.85 MB/s 0.3310 ratio 14690 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 188 | 12702173 | 396.85 MB/s 0.3113 ratio 29984 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 16 | 141952618 | 35.51 MB/s 0.1987 ratio 944749 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 178437 | 13307 | 685.65 MB/s 0.2869 ratio 450 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 80691 | 29648 | 307.74 MB/s 0.1943 ratio 9479 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 68026 | 35223 | 259.03 MB/s 0.1829 ratio 9496 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 18886 | 126661 | 72.03 MB/s 0.1612 ratio 12266 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 406172 | 5789 | 1576.20 MB/s 0.2625 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 213824 | 11237 | 811.96 MB/s 0.2459 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 12174 | 196795 | 46.36 MB/s 0.1588 ratio 813699 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 408397 | 5729 | 1786.06 MB/s 180 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 625957 | 3817 | 2680.79 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 135902 | 17618 | 580.78 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 137943 | 17398 | 588.11 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 141153 | 16959 | 603.32 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 7884 | 284492 | 1855.52 MB/s 1224 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 7120 | 333602 | 1582.36 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 3876 | 618263 | 853.81 MB/s 180 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 3946 | 606124 | 870.91 MB/s 143 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4176 | 570699 | 924.97 MB/s 127 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 2882 | 828952 | 1797.95 MB/s 1615 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 2576 | 930030 | 1602.55 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1572 | 1520702 | 980.08 MB/s 978 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1730 | 1377436 | 1082.02 MB/s 862 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1419 | 1601229 | 930.79 MB/s 1051 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 918 | 2611836 | 1930.01 MB/s 4729 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 789 | 3023013 | 1667.50 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 452 | 5288497 | 953.18 MB/s 11167 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 465 | 5128795 | 982.86 MB/s 10942 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 505 | 4731023 | 1065.49 MB/s 9995 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 597501 | 3833 | 2380.41 MB/s 174 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 1000000 | 2213 | 4123.65 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 269989 | 8834 | 1032.88 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 238994 | 9994 | 912.95 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 258644 | 9280 | 983.23 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 23378958 | 102.3 | 100016.76 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 164940 | 14285 | 36952.55 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 39285 | 61427 | 24263.27 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 10000 | 206598 | 24399.40 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 26016452 | 91.74 | 99452.56 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 4914255 | 485.8 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 2017746 | 1191 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 15553650 | 161.5 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 20063750 | 118.2 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 17754991 | 134.2 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 3342 | 716829 | 736.41 MB/s 61 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 2766 | 835310 | 631.96 MB/s 1311217 B/op 27 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 2961 | 883339 | 597.60 MB/s 8386757 B/op 8 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 8248 | 283656 | 1860.99 MB/s 1177 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 7074 | 338629 | 1712.27 MB/s 1597570 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 5938 | 426511 | 1359.46 MB/s 1599275 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 5113 | 476084 | 1217.90 MB/s 1605506 B/op 70 allocs/op |
| `BenchmarkContainerPack/zipStored` | 3876 | 623848 | 929.43 MB/s 1607630 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 42427560 | 55.72 | 10406604.15 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 17950 | 133832 | 4332.46 MB/s 588047 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 8468 | 348541 | 1663.57 MB/s 1198089 B/op 110 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.872 | 282004798.46 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 19161 | 122768 | 4299.82 MB/s 532482 B/op 1 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 13060 | 184258 | 2864.90 MB/s 535646 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 5155 | 416801 | 1266.50 MB/s 1079868 B/op 55 allocs/op |
| `BenchmarkStat` | 1243596 | 1928 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 1764282 | 1362 | 304 B/op 3 allocs/op |
| `BenchmarkOpenClose` | 437866 | 5445 | 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 366001 | 6498 | 630.32 MB/s 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 168253 | 13831 | 14807.28 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 89896 | 26446 | 19824.73 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 12916 | 186570 | 28101.34 MB/s 152 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 88004 | 27412 | 20172.18 MB/s 168 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 50842 | 47210 | 11712.89 MB/s 608 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 848275 | 2743 | 1493.08 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18524 | 129651 | 1579.63 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7212 | 332035 | 1579.02 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 723 | 3307399 | 1585.20 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 13949836 | 172.2 | 23790.99 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 279306 | 8597 | 23820.91 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 103273 | 23254 | 22546.49 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 9562 | 236793 | 22141.20 MB/s 0 B/op 0 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 10000 | 479219 | 427.36 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 1887 | 1267398 | 413.67 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 187 | 12759073 | 410.91 MB/s 864 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 3966 | 593895 | 344.84 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 1698 | 1352756 | 387.57 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 184 | 12709854 | 412.51 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 194191 | 12397 | 16520.00 MB/s 208 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 189404 | 12330 | 42520.18 MB/s 208 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 193462 | 12360 | 424170.37 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRawStat` | 1374216 | 1745 | 48 B/op 1 allocs/op |
| `BenchmarkRawStatMiss` | 2039692 | 1175 | 48 B/op 1 allocs/op |
| `BenchmarkRestoreCopyRename/200KiB` | 10000 | 471607 | 434.26 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/512KiB` | 2485 | 1261984 | 415.45 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/5MiB` | 190 | 12582759 | 416.67 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyFileRange/200KiB` | 4743 | 509986 | 401.58 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/512KiB` | 2580 | 1273198 | 411.79 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/5MiB` | 190 | 12572087 | 417.03 MB/s 864 B/op 12 allocs/op |
| `BenchmarkRestoreHardLink/200KiB` | 189643 | 12288 | 16667.03 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/512KiB` | 196566 | 12298 | 42632.93 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/5MiB` | 194646 | 12283 | 426824.30 MB/s 192 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 19514 | 122064 | 4324.63 MB/s 535789 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 34071 | 63671 | 8290.78 MB/s 532608 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 8842 | 389774 | 1487.59 MB/s 1337426 B/op 55 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 7870 | 397604 | 1458.29 MB/s 1337496 B/op 60 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 366 | 6407181 | 90.50 MB/s 28790702 B/op 296 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1092 | 2153233 | 269.28 MB/s 1445625 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 6457 | 401342 | 1444.71 MB/s 1258314 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 5649 | 412405 | 1405.96 MB/s 1258314 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1387 | 1802316 | 321.71 MB/s 12691370 B/op 302 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 4377 | 510050 | 1136.80 MB/s 1455014 B/op 150 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 6008 | 398480 | 1324.73 MB/s 1140692 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 5966 | 412046 | 1281.12 MB/s 1140694 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1566 | 1500807 | 351.73 MB/s 12257323 B/op 139 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 4929 | 464277 | 1136.99 MB/s 1347225 B/op 87 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 10000 | 205304 | 2571.21 MB/s 600272 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1366 | 1748333 | 301.93 MB/s 11721616 B/op 119 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2100 | 973113 | 542.47 MB/s 8985915 B/op 68 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 7143 | 399099 | 1322.68 MB/s 1140641 B/op 79 allocs/op |

