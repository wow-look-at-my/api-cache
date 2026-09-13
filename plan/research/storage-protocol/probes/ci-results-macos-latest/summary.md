## storage-protocol probes — macos-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343

### machine

```
Darwin iad20-gt1022-8ffb64d1-112e-4a0f-8f9c-feae05cebade-B66EC2C165F6.local 25.6.0 Darwin Kernel Version 25.6.0: Fri Jul 31 19:16:43 PDT 2026; root:xnu-12377.161.14~5/RELEASE_ARM64_VMAPPLE arm64
Apple M1 (Virtual)
3
cpu flags of interest: NOT PROBED (no /proc/cpuinfo)
/dev/disk2s5  670064640 428486856 200018376    69% 1879240 1000091880    0%   /System/Volumes/Data
go version go1.26.8 darwin/arm64
```

### ratio and container-overhead tables

```
go: downloading github.com/klauspost/compress v1.20.0
go: downloading github.com/pierrec/lz4/v4 v4.1.27
file                        raw        lz4    ratio         s2    ratio  s2-better    ratio     zstd-1    ratio     zstd-3    ratio     zstd-9    ratio
testdata/small.o           6296       4341    0.689       4293    0.682       4018    0.638       3455    0.549       3249    0.516       3171    0.504
testdata/mid.o           243888     122613    0.503     121902    0.500     111454    0.457      94968    0.389      90640    0.372      83684    0.343
testdata/big_g1.o        423952     236059    0.557     239617    0.565     217131    0.512     169958    0.401     162482    0.383     154370    0.364
testdata/big.o          1379328     596621    0.433     627960    0.455     542137    0.393     484140    0.351     425371    0.308     390932    0.283
testdata/mid.d           116760       9451    0.081      10842    0.093      10083    0.086       6783    0.058       6516    0.056       5771    0.049
format                      bytes   overhead      pct
framed (ACE1)              403540        +72   0.018%
tar (ustar)                407552      +4084   1.012%
tar + manifest.json        408576      +5108   1.266%
zip (stored)               403918       +450   0.112%
zip (deflate)              112972    -290496 -72.000%
raw member bytes           403468
    restore_darwin_test.go:49: clonefile(2): NOT AVAILABLE here (invalid argument). Clone restore is unavailable; an ENOSYS would mean the syscall number is wrong rather than the filesystem refusing.
    restore_portable_test.go:165: GOOS=darwin: rename over an OPEN file SUCCEEDS; the open handle still reads "old"
    restore_portable_test.go:192: GOOS=darwin: unlinking an OPEN file SUCCEEDS; the handle still reads "payload"
    restore_portable_test.go:214: GOOS=darwin: a 368-character path works

```

### binpazer round trip

```
go: downloading github.com/klauspost/compress v1.19.1
    binpazer_test.go:318: streamed file: len=118416 hasIndex=false
    binpazer_test.go:320: Find(directory) -> [], err=binpazer: block payload claims 6762810245124 bytes but only 0 remain in the input: binpazer: truncated input
    binpazer_test.go:331: seekable file: len=118416 hasIndex=true Find(directory) -> [118088] err=<nil>
    binpazer_test.go:450: stored       file=404048 raw=403468 overhead=+580 (0.144%)
    binpazer_test.go:450: stored+crc   file=404072 raw=403468 overhead=+604 (0.150%)
    binpazer_test.go:450: zstd         file=118416 raw=403468 overhead=-285052 (-70.650%)
    binpazer_test.go:450: zstd+crc     file=118440 raw=403468 overhead=-285028 (-70.645%)
    binpazer_test.go:450: lz4          file=159640 raw=403468 overhead=-243828 (-60.433%)

```

### benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkEncode/lz4/testdata/small.o` | 181213 | 15941 | 394.96 MB/s 0.6895 ratio 518 B/op 3 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 10000 | 212110 | 29.68 MB/s 0.5037 ratio 11805 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 61153 | 42994 | 146.44 MB/s 0.5488 ratio 6537 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 42615 | 57637 | 109.24 MB/s 0.5160 ratio 6566 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 299361 | 8475 | 742.93 MB/s 0.6819 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 101427 | 25128 | 250.56 MB/s 0.6382 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 8198 | 365782 | 17.21 MB/s 0.5079 ratio 813707 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 2097 | 1025309 | 237.87 MB/s 0.5027 ratio 4526 B/op 3 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 158 | 14892647 | 16.38 MB/s 0.3431 ratio 583137 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 1764 | 1542154 | 158.15 MB/s 0.3894 ratio 250940 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 1212 | 2034704 | 119.86 MB/s 0.3716 ratio 261414 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 7407 | 430494 | 566.53 MB/s 0.4998 ratio 42 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 2582 | 929294 | 262.44 MB/s 0.4570 ratio 323 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 381 | 6985206 | 34.91 MB/s 0.3548 ratio 814392 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 1111 | 2154492 | 196.78 MB/s 0.5568 ratio 8291 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 812 | 2633277 | 161.00 MB/s 0.4009 ratio 437556 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 640 | 3817156 | 111.06 MB/s 0.3833 ratio 455629 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 80 | 29348347 | 14.45 MB/s 0.3641 ratio 1094966 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 2970 | 802116 | 528.54 MB/s 0.5652 ratio 165 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 1296 | 2074558 | 204.36 MB/s 0.5122 ratio 784 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 166 | 13614783 | 31.14 MB/s 0.3805 ratio 816855 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 598 | 4075685 | 338.43 MB/s 0.4325 ratio 15663 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 482 | 5267216 | 261.87 MB/s 0.3510 ratio 2083649 B/op 11 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 303 | 7328872 | 188.20 MB/s 0.3084 ratio 1521575 B/op 8 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 40 | 62772850 | 21.97 MB/s 0.2834 ratio 3066706 B/op 10 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 980 | 2362921 | 583.74 MB/s 0.4553 ratio 1479 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 610 | 3939127 | 350.16 MB/s 0.3930 ratio 3237 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 88 | 28394232 | 48.58 MB/s 0.3064 ratio 825613 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 31870 | 74631 | 1564.49 MB/s 0.08094 ratio 667 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 21624 | 111120 | 1050.76 MB/s 0.05809 ratio 123295 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 16996 | 160634 | 726.87 MB/s 0.05581 ratio 122978 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 1789 | 1344658 | 86.83 MB/s 0.04943 ratio 152380 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 54942 | 37179 | 3140.45 MB/s 0.09286 ratio 3 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 22404 | 113113 | 1032.24 MB/s 0.08636 ratio 31 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 3325 | 635761 | 183.65 MB/s 0.05095 ratio 813703 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 1000000 | 2409 | 2613.56 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 1562796 | 1582 | 3979.54 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 229994 | 9610 | 655.15 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 222194 | 11265 | 558.92 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 197782 | 12290 | 512.28 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 27198 | 89320 | 2730.51 MB/s 314 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 24718 | 106003 | 2300.76 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 7646 | 346505 | 703.85 MB/s 58 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 8214 | 289277 | 843.10 MB/s 36 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 8533 | 287415 | 848.56 MB/s 28 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 10000 | 241332 | 1756.71 MB/s 579 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 10000 | 220442 | 1923.19 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 4089 | 618275 | 685.70 MB/s 104 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 4054 | 585509 | 724.07 MB/s 105 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 4332 | 574025 | 738.56 MB/s 99 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 3600 | 663602 | 2078.55 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 3950 | 653515 | 2110.63 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 1338 | 1881310 | 733.17 MB/s 1082 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 1473 | 1693872 | 814.30 MB/s 1033 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 1191 | 1935476 | 712.66 MB/s 1163 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 65090 | 31610 | 3693.79 MB/s 288 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 154532 | 15857 | 7363.34 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 66508 | 35909 | 3251.59 MB/s 1 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 68662 | 35045 | 3331.71 MB/s 1 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 63660 | 42138 | 2770.87 MB/s 1 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 21794355 | 101.1 | 62259.49 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 545082 | 4478 | 54468.98 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 258757 | 8307 | 51038.16 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 89720 | 27355 | 50422.93 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 1000000 | 2288 | 51026.94 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 3371461 | 688.8 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 1942974 | 1217 | 2952 B/op 11 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 9755376 | 250.7 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 17070945 | 164.1 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 14600794 | 163.9 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 6163 | 364599 | 668.92 MB/s 35 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 5102 | 484143 | 503.75 MB/s 770435 B/op 27 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 4406 | 545677 | 446.95 MB/s 8387356 B/op 6 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 27088 | 97824 | 2493.13 MB/s 469 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 22392 | 104529 | 3859.87 MB/s 737410 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 21745 | 115274 | 3500.08 MB/s 739114 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 17184 | 137431 | 2935.80 MB/s 744873 B/op 68 allocs/op |
| `BenchmarkContainerPack/zipStored` | 13168 | 190228 | 2120.97 MB/s 747468 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 34605128 | 66.58 | 6059728.46 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 31467 | 74695 | 5401.53 MB/s 414452 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 9442 | 254603 | 1584.70 MB/s 893832 B/op 114 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 2.248 | 108470849.36 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 53924 | 49693 | 4907.92 MB/s 245760 B/op 1 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 46695 | 50975 | 4784.45 MB/s 248307 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 16810 | 150182 | 1623.95 MB/s 505524 B/op 52 allocs/op |
| `BenchmarkStat` | 1250614 | 1917 | 304 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 1406677 | 1685 | 352 B/op 3 allocs/op |
| `BenchmarkOpenClose` | 243770 | 9121 | 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 269247 | 9127 | 448.79 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 156183 | 15580 | 13144.83 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 97173 | 25079 | 20905.44 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 6584 | 374867 | 13985.99 MB/s 200 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 83812 | 26814 | 20621.89 MB/s 200 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 44312 | 53893 | 10260.24 MB/s 800 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 1000000 | 2146 | 1908.54 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 25933 | 92602 | 2211.62 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 10000 | 247188 | 2121.01 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 988 | 2408814 | 2176.54 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 4621546 | 509.9 | 8032.25 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 90961 | 26519 | 7722.79 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 35712 | 67324 | 7787.49 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 3145 | 753459 | 6958.42 MB/s 0 B/op 0 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 7238 | 321505 | 637.00 MB/s 1136 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 5712 | 501187 | 1046.09 MB/s 1136 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 1099 | 2548641 | 2057.13 MB/s 1088 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 992 | 2252963 | 90.90 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 1083 | 2283216 | 229.63 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 523 | 4676065 | 1121.22 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 10000 | 271871 | 753.30 MB/s 336 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 10000 | 277403 | 1889.99 MB/s 336 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 9148 | 264660 | 19809.88 MB/s 336 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 37396 | 61732 | 3950.78 MB/s 248254 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 49948 | 46597 | 5234.01 MB/s 245889 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 10987 | 222458 | 1813.68 MB/s 1247255 B/op 56 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 8679 | 281917 | 1431.16 MB/s 1247317 B/op 61 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 646 | 3318213 | 121.59 MB/s 27933832 B/op 285 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 2119 | 1137054 | 354.84 MB/s 907361 B/op 81 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 10131 | 236039 | 1709.33 MB/s 954086 B/op 126 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 9705 | 237432 | 1699.30 MB/s 954087 B/op 126 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1652 | 1462379 | 275.90 MB/s 11879342 B/op 298 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 8712 | 311455 | 1295.43 MB/s 1007246 B/op 154 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 13951 | 161146 | 1513.46 MB/s 566387 B/op 77 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 18022 | 130986 | 1861.94 MB/s 566386 B/op 77 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 2066 | 1150234 | 212.03 MB/s 10817034 B/op 132 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 14646 | 163486 | 1491.80 MB/s 585509 B/op 84 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 38143 | 71433 | 3414.21 MB/s 313585 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1972 | 1215114 | 200.71 MB/s 10564219 B/op 113 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 3751 | 612974 | 397.88 MB/s 8701820 B/op 68 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 16476 | 139186 | 1752.24 MB/s 566337 B/op 76 allocs/op |

