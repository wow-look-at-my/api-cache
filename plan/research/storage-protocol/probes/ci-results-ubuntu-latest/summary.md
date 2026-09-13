## storage-protocol probes — ubuntu-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981

### machine

```
Linux runnervmlun5p 6.17.0-1022-azure #22-Ubuntu SMP Mon Jul 27 17:24:03 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
model name	: AMD EPYC 7763 64-Core Processor
4
cpu flags of interest: avx2 sha_ni 
/dev/root      151263856 61139568  90107904  41% /
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
| `BenchmarkEncode/lz4/testdata/small.o` | 91802 | 25743 | 397.47 MB/s 0.5174 ratio 494 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 34412 | 70200 | 145.75 MB/s 0.3437 ratio 10288 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 7519 | 269598 | 37.95 MB/s 0.3270 ratio 17258 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 42042 | 57500 | 177.95 MB/s 0.3515 ratio 10254 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 233767 | 10251 | 998.19 MB/s 0.5017 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 122014 | 19683 | 519.83 MB/s 0.4733 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 4435 | 510247 | 20.05 MB/s 0.3405 ratio 813700 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1302 | 1842405 | 286.52 MB/s 0.3718 ratio 7103 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 862 | 2755086 | 191.60 MB/s 0.2342 ratio 543323 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 710 | 3338592 | 158.11 MB/s 0.2343 ratio 559479 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 135 | 17811765 | 29.64 MB/s 0.2028 ratio 927234 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 3050 | 783669 | 673.60 MB/s 0.3819 ratio 196 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 1582 | 1492947 | 353.58 MB/s 0.3578 ratio 709 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 146 | 16384049 | 32.22 MB/s 0.2302 ratio 815489 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 512 | 4667144 | 319.34 MB/s 0.3104 ratio 17971 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 361 | 6622800 | 225.04 MB/s 0.2081 ratio 1598805 B/op 11 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 297 | 7996786 | 186.38 MB/s 0.2016 ratio 1408084 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 50 | 44094757 | 33.80 MB/s 0.1734 ratio 1999778 B/op 8 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1126 | 2132856 | 698.79 MB/s 0.3144 ratio 1382 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 580 | 3929573 | 379.28 MB/s 0.2954 ratio 3589 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 55 | 41323707 | 36.07 MB/s 0.2014 ratio 832759 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 158 | 15082953 | 334.21 MB/s 0.3244 ratio 80672 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 97 | 22438837 | 224.65 MB/s 0.2029 ratio 5503196 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 84 | 25615471 | 196.79 MB/s 0.1953 ratio 5454827 B/op 13 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 13 | 171156118 | 29.45 MB/s 0.1660 ratio 8359667 B/op 16 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 349 | 6851187 | 735.77 MB/s 0.3310 ratio 14648 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 176 | 13520507 | 372.83 MB/s 0.3113 ratio 32026 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 15 | 141987359 | 35.50 MB/s 0.1987 ratio 953485 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 169231 | 14056 | 649.11 MB/s 0.2869 ratio 476 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 81469 | 29348 | 310.89 MB/s 0.1943 ratio 9479 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 67825 | 35269 | 258.70 MB/s 0.1829 ratio 9496 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 18901 | 126368 | 72.20 MB/s 0.1612 ratio 12263 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 416210 | 5735 | 1591.05 MB/s 0.2625 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 212467 | 11210 | 813.95 MB/s 0.2459 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 10000 | 201345 | 45.32 MB/s 0.1588 ratio 813698 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 362202 | 6604 | 1549.48 MB/s 183 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 564294 | 4240 | 2413.44 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 144477 | 16625 | 615.45 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 138910 | 17239 | 593.54 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 132918 | 16964 | 603.17 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 7159 | 331579 | 1592.02 MB/s 745 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 7036 | 340832 | 1548.80 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 3938 | 606678 | 870.12 MB/s 177 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 4015 | 596602 | 884.81 MB/s 141 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4242 | 563101 | 937.45 MB/s 125 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 2490 | 956172 | 1558.73 MB/s 1844 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 2564 | 934426 | 1595.01 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1533 | 1557446 | 956.96 MB/s 998 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1608 | 1489252 | 1000.78 MB/s 953 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1770 | 1351063 | 1103.14 MB/s 843 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 788 | 3036076 | 1660.32 MB/s 5483 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 780 | 3082142 | 1635.51 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 463 | 5176879 | 973.73 MB/s 10901 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 476 | 5029179 | 1002.33 MB/s 10690 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 513 | 4655460 | 1082.79 MB/s 9839 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 506607 | 4603 | 1982.37 MB/s 168 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 1000000 | 2198 | 4151.28 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 280857 | 8482 | 1075.63 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 243865 | 9800 | 931.03 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 261742 | 9137 | 998.58 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 23420923 | 101.8 | 100536.24 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 163974 | 14341 | 36810.37 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 36148 | 67073 | 22220.66 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 10000 | 224592 | 22444.57 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 26048524 | 91.75 | 99446.38 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 4984446 | 478.0 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 2043630 | 1169 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 14910576 | 155.9 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 20770929 | 116.5 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 17813053 | 135.1 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 3405 | 704893 | 748.88 MB/s 59 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 2932 | 823010 | 641.40 MB/s 1311210 B/op 27 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 3147 | 994114 | 531.01 MB/s 8386923 B/op 7 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 7047 | 328417 | 1607.35 MB/s 1350 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 10628 | 210353 | 2756.43 MB/s 1597569 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 5988 | 423696 | 1368.49 MB/s 1599276 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 4874 | 423974 | 1367.59 MB/s 1605534 B/op 71 allocs/op |
| `BenchmarkContainerPack/zipStored` | 4198 | 574773 | 1008.79 MB/s 1607630 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 41725576 | 53.96 | 10746408.40 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 19638 | 124201 | 4668.44 MB/s 588023 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 9639 | 305091 | 1900.49 MB/s 1198089 B/op 110 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.872 | 281996833.51 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 22521 | 97784 | 5398.45 MB/s 532481 B/op 1 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 13026 | 186821 | 2825.60 MB/s 535729 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 5358 | 410268 | 1286.67 MB/s 1079869 B/op 55 allocs/op |
| `BenchmarkStat` | 1265865 | 1896 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 1813165 | 1331 | 304 B/op 3 allocs/op |
| `BenchmarkOpenClose` | 444057 | 5389 | 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 355687 | 6529 | 627.35 MB/s 152 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 173029 | 14363 | 14259.24 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 91831 | 26401 | 19858.41 MB/s 168 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 13316 | 180410 | 29060.99 MB/s 152 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 86280 | 27548 | 20072.36 MB/s 168 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 51115 | 47181 | 11719.99 MB/s 608 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 849756 | 2733 | 1498.84 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18584 | 129163 | 1585.60 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7254 | 330371 | 1586.97 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 724 | 3300682 | 1588.42 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 14002564 | 171.3 | 23912.04 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 270472 | 8870 | 23089.39 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 102998 | 23169 | 22628.52 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 8990 | 226766 | 23120.26 MB/s 0 B/op 0 allocs/op |
| `BenchmarkRawStat` | 1401962 | 1711 | 48 B/op 1 allocs/op |
| `BenchmarkRawStatMiss` | 2040666 | 1174 | 48 B/op 1 allocs/op |
| `BenchmarkRestoreCopyRename/200KiB` | 9645 | 474136 | 431.94 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/512KiB` | 1608 | 1277049 | 410.55 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyRename/5MiB` | 193 | 12624646 | 415.29 MB/s 800 B/op 11 allocs/op |
| `BenchmarkRestoreCopyFileRange/200KiB` | 4624 | 501469 | 408.40 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/512KiB` | 1933 | 1283121 | 408.60 MB/s 928 B/op 12 allocs/op |
| `BenchmarkRestoreCopyFileRange/5MiB` | 193 | 12620609 | 415.42 MB/s 864 B/op 12 allocs/op |
| `BenchmarkRestoreHardLink/200KiB` | 193112 | 12282 | 16674.35 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/512KiB` | 196674 | 12278 | 42701.45 MB/s 192 B/op 3 allocs/op |
| `BenchmarkRestoreHardLink/5MiB` | 196100 | 12300 | 426243.43 MB/s 192 B/op 3 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 17648 | 140539 | 3756.11 MB/s 535755 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 31095 | 64321 | 8206.91 MB/s 532609 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 9460 | 292853 | 1979.92 MB/s 1337439 B/op 55 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 7780 | 341462 | 1698.06 MB/s 1337507 B/op 60 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 387 | 6329890 | 91.60 MB/s 28790686 B/op 296 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1071 | 2196127 | 264.02 MB/s 1413956 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 5210 | 444255 | 1305.16 MB/s 1258313 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 6156 | 428105 | 1354.40 MB/s 1258314 B/op 122 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1252 | 2002478 | 289.55 MB/s 12693329 B/op 303 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 4369 | 528358 | 1097.41 MB/s 1469769 B/op 150 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 5678 | 464247 | 1137.07 MB/s 1140691 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 5718 | 459345 | 1149.20 MB/s 1140695 B/op 80 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1563 | 1817533 | 290.44 MB/s 12259827 B/op 140 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 4292 | 481483 | 1096.36 MB/s 1376812 B/op 87 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 12067 | 203022 | 2600.11 MB/s 600272 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1304 | 1793050 | 294.40 MB/s 11722224 B/op 119 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2784 | 870666 | 606.29 MB/s 8988402 B/op 68 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 9770 | 240420 | 2195.66 MB/s 1140640 B/op 79 allocs/op |

