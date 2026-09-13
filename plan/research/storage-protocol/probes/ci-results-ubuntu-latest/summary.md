## storage-protocol probes — ubuntu-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34729381343

### machine

```
Linux runnervmlun5p 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
model name	: AMD EPYC 7763 64-Core Processor
4
cpu flags of interest: avx2 sha_ni 
/dev/root      151263856 61140844  90106628  41% /
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
| `BenchmarkEncode/lz4/testdata/small.o` | 86818 | 27883 | 366.96 MB/s 0.5174 ratio 498 B/op 3 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 7996 | 268941 | 38.05 MB/s 0.3270 ratio 16840 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 42337 | 56897 | 179.83 MB/s 0.3515 ratio 10254 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 34092 | 70354 | 145.44 MB/s 0.3437 ratio 10288 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 234643 | 10214 | 1001.73 MB/s 0.5017 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 120481 | 19890 | 514.42 MB/s 0.4733 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 4532 | 498569 | 20.52 MB/s 0.3405 ratio 813698 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1338 | 1775300 | 297.35 MB/s 0.3718 ratio 6922 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 860 | 2767552 | 190.74 MB/s 0.2342 ratio 543349 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 712 | 3336333 | 158.22 MB/s 0.2343 ratio 559403 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 157 | 15764210 | 33.49 MB/s 0.2028 ratio 871918 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 3070 | 779244 | 677.43 MB/s 0.3819 ratio 194 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 1618 | 1473320 | 358.29 MB/s 0.3578 ratio 693 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 147 | 16154091 | 32.68 MB/s 0.2302 ratio 815477 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 529 | 4511086 | 330.39 MB/s 0.3104 ratio 17407 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 360 | 6607195 | 225.57 MB/s 0.2081 ratio 1598876 B/op 11 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 302 | 7906672 | 188.50 MB/s 0.2016 ratio 1407014 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 60 | 34751917 | 42.89 MB/s 0.1734 ratio 1822134 B/op 8 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1123 | 2117904 | 703.72 MB/s 0.3144 ratio 1386 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 614 | 3878148 | 384.31 MB/s 0.2954 ratio 3389 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 57 | 40650567 | 36.66 MB/s 0.2014 ratio 832086 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 164 | 14573761 | 345.89 MB/s 0.3244 ratio 77735 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 98 | 22765909 | 221.42 MB/s 0.2029 ratio 5502213 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 88 | 25815850 | 195.26 MB/s 0.1953 ratio 5444451 B/op 13 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 15 | 150939534 | 33.40 MB/s 0.1660 ratio 7810841 B/op 16 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 340 | 6954068 | 724.88 MB/s 0.3310 ratio 15036 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 182 | 13104126 | 384.68 MB/s 0.3113 ratio 30973 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 16 | 140798085 | 35.80 MB/s 0.1987 ratio 944749 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 180477 | 13225 | 689.89 MB/s 0.2869 ratio 495 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 81206 | 29421 | 310.12 MB/s 0.1943 ratio 9479 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 69588 | 34450 | 264.85 MB/s 0.1829 ratio 9495 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 18829 | 127000 | 71.84 MB/s 0.1612 ratio 12274 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 412258 | 5781 | 1578.39 MB/s 0.2625 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 213447 | 11153 | 818.11 MB/s 0.2459 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 13540 | 176852 | 51.59 MB/s 0.1588 ratio 813697 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 412268 | 5712 | 1791.23 MB/s 180 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 626853 | 3800 | 2692.87 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 138811 | 17282 | 592.07 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 141567 | 16889 | 605.83 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 136110 | 17552 | 582.94 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 8322 | 279589 | 1888.06 MB/s 664 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 7176 | 333564 | 1582.55 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 3876 | 615416 | 857.76 MB/s 179 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 3936 | 605609 | 871.65 MB/s 143 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4165 | 570707 | 924.96 MB/s 128 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 2908 | 826205 | 1803.93 MB/s 160 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 2587 | 925058 | 1611.16 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1508 | 1585551 | 940.00 MB/s 1014 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1580 | 1517287 | 982.29 MB/s 970 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1736 | 1370671 | 1087.36 MB/s 859 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 919 | 2631470 | 1915.61 MB/s 4724 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 794 | 3014093 | 1672.43 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 454 | 5263619 | 957.68 MB/s 11117 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 468 | 5113678 | 985.76 MB/s 10872 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 507 | 4720892 | 1067.78 MB/s 9955 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 613645 | 3807 | 2396.53 MB/s 173 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 1000000 | 2208 | 4132.91 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 268705 | 8975 | 1016.57 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 240358 | 9936 | 918.25 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 259582 | 9212 | 990.39 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 23546038 | 101.8 | 100514.77 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 166148 | 14222 | 37117.62 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 37009 | 64789 | 23004.14 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 10000 | 218531 | 23067.05 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 26180216 | 91.65 | 99556.70 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 4969340 | 481.2 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 2030763 | 1183 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 15288360 | 156.8 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 20359406 | 118.2 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 17691790 | 135.0 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 3358 | 714547 | 738.76 MB/s 60 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 2769 | 828292 | 637.31 MB/s 1311210 B/op 27 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 3513 | 750358 | 703.50 MB/s 8387196 B/op 7 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 8234 | 280528 | 1881.74 MB/s 1179 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 8763 | 236869 | 2447.87 MB/s 1597569 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 5404 | 450690 | 1286.52 MB/s 1599275 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 4964 | 480661 | 1206.30 MB/s 1605548 B/op 71 allocs/op |
| `BenchmarkContainerPack/zipStored` | 4940 | 529665 | 1094.70 MB/s 1607628 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 42681594 | 51.99 | 11151682.52 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 17209 | 133388 | 4346.90 MB/s 588054 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 8490 | 309290 | 1874.70 MB/s 1198089 B/op 110 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.886 | 279900715.52 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 26296 | 83768 | 6301.71 MB/s 532481 B/op 1 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 14398 | 169268 | 3118.61 MB/s 535724 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 5317 | 412634 | 1279.29 MB/s 1079869 B/op 55 allocs/op |
| `BenchmarkStat` | 1264042 | 1896 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 1798956 | 1333 | 304 B/op 3 allocs/op |
| `BenchmarkOpenClose` | 432843 | 5434 | 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 364119 | 6515 | 628.71 MB/s 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 170092 | 14068 | 14557.42 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 91648 | 26274 | 19954.52 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 13250 | 181487 | 28888.49 MB/s 152 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 86377 | 27746 | 19929.65 MB/s 168 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 51457 | 46664 | 11849.83 MB/s 608 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 859417 | 2713 | 1509.57 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18594 | 129057 | 1586.89 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7221 | 330510 | 1586.30 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 724 | 3301847 | 1587.86 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 13993789 | 171.6 | 23870.54 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 274536 | 8745 | 23419.83 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 103647 | 23189 | 22609.53 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 9636 | 236004 | 22215.22 MB/s 0 B/op 0 allocs/op |
| `BenchmarkPortableRestoreCopyRename/200KiB` | 9576 | 478612 | 427.90 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/512KiB` | 2445 | 1266139 | 414.08 MB/s 864 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyRename/5MiB` | 193 | 12641133 | 414.75 MB/s 864 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/200KiB` | 4034 | 590430 | 346.87 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/512KiB` | 1818 | 1359202 | 385.73 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreCopyFsyncRename/5MiB` | 192 | 12692042 | 413.08 MB/s 896 B/op 11 allocs/op |
| `BenchmarkPortableRestoreHardLink/200KiB` | 192289 | 12236 | 16738.02 MB/s 208 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/512KiB` | 194816 | 12299 | 42627.46 MB/s 208 B/op 3 allocs/op |
| `BenchmarkPortableRestoreHardLink/5MiB` | 193047 | 12244 | 428190.50 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRawStat` | 1384159 | 1734 | 48 B/op 1 allocs/op |
| `BenchmarkRawStatMiss` | 2032765 | 1178 | 48 B/op 1 allocs/op |
| `BenchmarkRestoreCopyRename/200KiB` | 10000 | 468808 | 436.85 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/512KiB` | 2449 | 1263426 | 414.97 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/5MiB` | 193 | 12639196 | 414.81 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyFileRange/200KiB` | 4657 | 507129 | 403.84 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/512KiB` | 1671 | 1279199 | 409.86 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/5MiB` | 192 | 12733676 | 411.73 MB/s 864 B/op 12 allocs/op |
| `BenchmarkRestoreHardLink/200KiB` | 191359 | 12331 | 16608.31 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/512KiB` | 195646 | 12253 | 42789.70 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/5MiB` | 196617 | 12270 | 427279.02 MB/s 192 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 20286 | 140597 | 3754.57 MB/s 535628 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 37816 | 59540 | 8865.99 MB/s 532609 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 9248 | 361144 | 1605.52 MB/s 1337426 B/op 55 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 6975 | 402277 | 1441.36 MB/s 1337495 B/op 60 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 420 | 5845554 | 99.19 MB/s 28790618 B/op 295 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1118 | 2110125 | 274.78 MB/s 1439312 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 6570 | 361050 | 1605.94 MB/s 1258315 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 7674 | 363545 | 1594.92 MB/s 1258314 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1447 | 1679559 | 345.22 MB/s 12689950 B/op 302 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 4723 | 502655 | 1153.52 MB/s 1457634 B/op 150 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 8814 | 331797 | 1590.97 MB/s 1140695 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 6792 | 339777 | 1553.61 MB/s 1140696 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1729 | 1382409 | 381.86 MB/s 12254822 B/op 138 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 4774 | 465413 | 1134.22 MB/s 1353911 B/op 87 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 13186 | 187139 | 2820.80 MB/s 600273 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1221 | 2063007 | 255.88 MB/s 11722558 B/op 119 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2655 | 852091 | 619.51 MB/s 8988330 B/op 68 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 6993 | 318236 | 1658.77 MB/s 1140642 B/op 79 allocs/op |

