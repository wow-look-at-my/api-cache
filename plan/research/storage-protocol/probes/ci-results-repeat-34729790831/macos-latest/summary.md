## storage-protocol probes — macos-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729790831

### machine

```
Darwin sjc22-be109-d0874473-8e1d-4db0-9361-000c7fe03a22-06D1B0AB9E14.local 25.6.0 Darwin Kernel Version 25.6.0: Fri Jul 31 19:16:43 PDT 2026; root:xnu-12377.161.14~5/RELEASE_ARM64_VMAPPLE arm64
Apple M1 (Virtual)
3
cpu flags of interest: NOT PROBED (no /proc/cpuinfo)
/dev/disk2s5  670064640 428564112 199941112    69% 1876461 999705560    0%   /System/Volumes/Data
go version go1.26.8 darwin/arm64
```

### ratio and container-overhead tables

```
go: downloading github.com/klauspost/compress v1.20.0
go: downloading github.com/pierrec/lz4/v4 v4.1.27
go: downloading golang.org/x/sys v0.47.0
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
    restore_darwin_test.go:62: clonefile via syscall(2) number 462: FAILED (invalid argument). Expected: the generic syscall shim is deprecated on macOS. This is not a filesystem verdict.
    restore_darwin_test.go:80: clonefile(2) via libSystem: SUPPORTED; cloned 524288 bytes as a copy-on-write share, in /var/folders/36/tjdph2t965j8snz9_vkdnw0r0000gn/T/TestClonefileSupport3130756364/001
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
| `BenchmarkEncode/lz4/testdata/small.o` | 162218 | 15666 | 401.88 MB/s 0.6895 ratio 507 B/op 3 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 11511 | 212358 | 29.65 MB/s 0.5037 ratio 11112 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 70117 | 35818 | 175.78 MB/s 0.5488 ratio 6536 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 49489 | 51781 | 121.59 MB/s 0.5160 ratio 6561 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 380883 | 7293 | 863.24 MB/s 0.6819 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 112245 | 20731 | 303.70 MB/s 0.6382 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 7068 | 310064 | 20.31 MB/s 0.5079 ratio 813702 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 2347 | 896755 | 271.97 MB/s 0.5027 ratio 4086 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 1566 | 1463668 | 166.63 MB/s 0.3894 ratio 251595 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 1284 | 1992610 | 122.40 MB/s 0.3716 ratio 260536 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 177 | 13559540 | 17.99 MB/s 0.3431 ratio 546921 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 7014 | 405194 | 601.90 MB/s 0.4998 ratio 44 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 2854 | 1006299 | 242.36 MB/s 0.4570 ratio 292 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 400 | 6432521 | 37.91 MB/s 0.3548 ratio 814356 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 1448 | 1804407 | 234.95 MB/s 0.5568 ratio 6455 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 1056 | 2366099 | 179.18 MB/s 0.4009 ratio 434882 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 705 | 3800811 | 111.54 MB/s 0.3833 ratio 452895 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 82 | 27611618 | 15.35 MB/s 0.3641 ratio 1078649 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 3550 | 710257 | 596.90 MB/s 0.5652 ratio 138 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 1332 | 1866171 | 227.18 MB/s 0.5122 ratio 762 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 180 | 13643337 | 31.07 MB/s 0.3805 ratio 816608 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 504 | 5051136 | 273.07 MB/s 0.4325 ratio 18509 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 406 | 6674658 | 206.65 MB/s 0.3510 ratio 2087251 B/op 11 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 260 | 9904283 | 139.27 MB/s 0.3084 ratio 1532055 B/op 8 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 37 | 65776216 | 20.97 MB/s 0.2834 ratio 3175206 B/op 10 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 1209 | 2039044 | 676.46 MB/s 0.4553 ratio 1199 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 448 | 5303463 | 260.08 MB/s 0.3930 ratio 4408 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 80 | 39389916 | 35.02 MB/s 0.3064 ratio 826802 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 24168 | 98856 | 1181.11 MB/s 0.08094 ratio 753 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 15802 | 147481 | 791.70 MB/s 0.05809 ratio 123449 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 12253 | 198744 | 587.49 MB/s 0.05581 ratio 123015 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 2785 | 781926 | 149.32 MB/s 0.04943 ratio 141830 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 85840 | 35434 | 3295.17 MB/s 0.09286 ratio 2 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 24872 | 99263 | 1176.27 MB/s 0.08636 ratio 28 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 2893 | 724250 | 161.22 MB/s 0.05095 ratio 813707 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 856012 | 2743 | 2295.47 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 1460076 | 1683 | 3741.25 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 246692 | 10716 | 587.53 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 204873 | 11886 | 529.69 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 183427 | 13591 | 463.26 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 23101 | 102781 | 2372.89 MB/s 341 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 20382 | 122375 | 1992.95 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 6481 | 350402 | 696.02 MB/s 69 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 6589 | 334600 | 728.89 MB/s 44 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 5962 | 410778 | 593.72 MB/s 41 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 8347 | 268816 | 1577.11 MB/s 662 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 8053 | 264174 | 1604.82 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 3232 | 702544 | 603.45 MB/s 132 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 3105 | 704249 | 601.99 MB/s 137 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 4292 | 735914 | 576.09 MB/s 100 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 2976 | 796828 | 1731.02 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 3192 | 768717 | 1794.32 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 1184 | 1899512 | 726.15 MB/s 1223 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 1155 | 1976103 | 698.00 MB/s 1317 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 1326 | 2180564 | 632.56 MB/s 1044 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 58022 | 35980 | 3245.17 MB/s 232 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 136281 | 21718 | 5376.15 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 47767 | 53684 | 2174.94 MB/s 2 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 50864 | 48493 | 2407.76 MB/s 2 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 59395 | 49884 | 2340.61 MB/s 2 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 18394408 | 130.5 | 48227.85 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 487942 | 6367 | 38305.13 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 249110 | 10834 | 39132.12 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 81031 | 37815 | 36475.74 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 864340 | 2531 | 46135.85 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 3410643 | 707.0 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 1644022 | 1377 | 2952 B/op 11 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 7692230 | 312.5 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 17130559 | 163.0 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 13820005 | 198.6 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 5352 | 470486 | 518.38 MB/s 41 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 5130 | 592201 | 411.83 MB/s 770449 B/op 27 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 2916 | 689055 | 353.95 MB/s 8387907 B/op 7 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 24001 | 94369 | 2584.40 MB/s 509 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 24070 | 111109 | 3631.30 MB/s 737414 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 20932 | 113348 | 3559.55 MB/s 739116 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 14431 | 160628 | 2511.81 MB/s 744890 B/op 68 allocs/op |
| `BenchmarkContainerPack/zipStored` | 12268 | 193428 | 2085.88 MB/s 747468 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 38735421 | 73.60 | 5482218.95 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 27901 | 88616 | 4552.99 MB/s 414499 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 10000 | 296669 | 1359.99 MB/s 893833 B/op 114 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 879360982 | 2.605 | 93640594.13 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 48348 | 43979 | 5545.62 MB/s 245762 B/op 1 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 52519 | 47484 | 5136.26 MB/s 248277 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 20019 | 121416 | 2008.71 MB/s 505524 B/op 52 allocs/op |
| `BenchmarkStat` | 1231682 | 1942 | 304 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 1566962 | 1529 | 352 B/op 3 allocs/op |
| `BenchmarkOpenClose` | 305131 | 8951 | 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 218810 | 10527 | 389.10 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 141084 | 15915 | 12868.10 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 95318 | 26202 | 20009.70 MB/s 200 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 5604 | 479189 | 10941.16 MB/s 200 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 60777 | 36486 | 15155.35 MB/s 200 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 34297 | 58544 | 9445.23 MB/s 800 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 1200519 | 2030 | 2017.95 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 24260 | 95215 | 2150.91 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 10000 | 237084 | 2211.40 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 990 | 2550167 | 2055.90 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 4381281 | 586.8 | 6980.53 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 72332 | 35268 | 5806.94 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 28104 | 81922 | 6399.84 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 3392 | 732036 | 7162.06 MB/s 0 B/op 0 allocs/op |
| `BenchmarkRestoreClonefile/200KiB` | 21832 | 114148 | 1794.16 MB/s 336 B/op 3 allocs/op |
| `BenchmarkRestoreClonefile/512KiB` | 20758 | 167171 | 3136.24 MB/s 336 B/op 3 allocs/op |
| `BenchmarkRestoreClonefile/5MiB` | 16735 | 140447 | 37329.98 MB/s 336 B/op 3 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 7636 | 335960 | 609.60 MB/s 1136 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 6866 | 407786 | 1285.70 MB/s 1136 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 417 | 4831365 | 1085.18 MB/s 1088 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 1188 | 2016666 | 101.55 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 1107 | 2128309 | 246.34 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 522 | 4551842 | 1151.81 MB/s 1184 B/op 11 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 10000 | 266227 | 769.27 MB/s 336 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 10000 | 251334 | 2086.02 MB/s 336 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 10537 | 226853 | 23111.31 MB/s 336 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 44462 | 49920 | 4885.57 MB/s 248251 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 65352 | 33859 | 7203.04 MB/s 245888 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 13183 | 196872 | 2049.39 MB/s 1247213 B/op 55 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 10000 | 283418 | 1423.58 MB/s 1247300 B/op 61 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 774 | 3114624 | 129.54 MB/s 27933724 B/op 283 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 2238 | 1074200 | 375.60 MB/s 905943 B/op 81 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 10000 | 206096 | 1957.67 MB/s 954087 B/op 126 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 10000 | 236315 | 1707.33 MB/s 954087 B/op 126 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1678 | 1502200 | 268.58 MB/s 11879058 B/op 298 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 8958 | 259553 | 1554.47 MB/s 1041433 B/op 154 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 21038 | 116620 | 2091.31 MB/s 566386 B/op 77 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 19820 | 131439 | 1855.52 MB/s 566387 B/op 77 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1728 | 1205285 | 202.35 MB/s 10818404 B/op 133 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 10000 | 217226 | 1122.74 MB/s 615554 B/op 84 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 32187 | 73598 | 3313.79 MB/s 313585 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 2002 | 1240526 | 196.60 MB/s 10565126 B/op 113 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 3354 | 706974 | 344.97 MB/s 8700425 B/op 68 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 19662 | 131459 | 1855.24 MB/s 566337 B/op 76 allocs/op |

