## storage-protocol probes — windows-latest

Run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728376981

### machine

```
MINGW64_NT-10.0-26100 runnervmvmocb 3.6.10-710e5275.x86_64 2026-07-28 09:32 UTC x86_64 Msys
model name	: AMD EPYC 7763 64-Core Processor                
4
cpu flags of interest: avx2 sha_ni 
D:             157284348 3260152 154024196   3% /d
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
| `BenchmarkEncode/lz4/testdata/small.o` | 116174 | 19341 | 360.54 MB/s 0.6393 ratio 516 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/small.o` | 49785 | 49225 | 141.66 MB/s 0.4516 ratio 8204 B/op 1 allocs/op |
| `BenchmarkEncode/zstd3/testdata/small.o` | 37742 | 63891 | 109.14 MB/s 0.4358 ratio 8235 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/small.o` | 9666 | 247754 | 28.14 MB/s 0.4254 ratio 13651 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/small.o` | 314948 | 7661 | 910.22 MB/s 0.6155 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/small.o` | 152622 | 15810 | 441.05 MB/s 0.5756 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/small.o` | 5845 | 380716 | 18.32 MB/s 0.4330 ratio 813700 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.o` | 1525 | 1504557 | 228.04 MB/s 0.4770 ratio 6101 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.o` | 810 | 2907347 | 118.01 MB/s 0.3155 ratio 367740 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.o` | 147 | 14431722 | 23.77 MB/s 0.2910 ratio 708052 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.o` | 1084 | 2216525 | 154.79 MB/s 0.3243 ratio 352684 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.o` | 4221 | 667292 | 514.16 MB/s 0.4788 ratio 97 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.o` | 2054 | 1251081 | 274.24 MB/s 0.4430 ratio 454 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.o` | 193 | 12326795 | 27.83 MB/s 0.3182 ratio 815054 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big_g1.o` | 574 | 4109083 | 311.20 MB/s 0.3149 ratio 15973 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big_g1.o` | 424 | 5690628 | 224.71 MB/s 0.2140 ratio 1201728 B/op 10 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big_g1.o` | 339 | 7162429 | 178.54 MB/s 0.2063 ratio 1195285 B/op 9 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big_g1.o` | 49 | 41223490 | 31.02 MB/s 0.1857 ratio 2173417 B/op 10 allocs/op |
| `BenchmarkEncode/s2/testdata/big_g1.o` | 1203 | 2130348 | 600.26 MB/s 0.3132 ratio 1124 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big_g1.o` | 691 | 3467627 | 368.77 MB/s 0.2913 ratio 2716 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big_g1.o` | 78 | 29845454 | 42.85 MB/s 0.2197 ratio 827136 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/big.o` | 176 | 13495419 | 279.82 MB/s 0.3942 ratio 57337 B/op 3 allocs/op |
| `BenchmarkEncode/zstd1/testdata/big.o` | 122 | 19363525 | 195.02 MB/s 0.2531 ratio 4451198 B/op 15 allocs/op |
| `BenchmarkEncode/zstd3/testdata/big.o` | 96 | 22699789 | 166.36 MB/s 0.2445 ratio 4533876 B/op 14 allocs/op |
| `BenchmarkEncode/zstd9/testdata/big.o` | 12 | 181997742 | 20.75 MB/s 0.2217 ratio 8697904 B/op 18 allocs/op |
| `BenchmarkEncode/s2/testdata/big.o` | 426 | 5574673 | 677.41 MB/s 0.3925 ratio 9020 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/big.o` | 206 | 11574671 | 326.26 MB/s 0.3684 ratio 21198 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/big.o` | 21 | 108731424 | 34.73 MB/s 0.2615 ratio 913545 B/op 16 allocs/op |
| `BenchmarkEncode/lz4/testdata/mid.d` | 173424 | 13461 | 872.00 MB/s 0.1756 ratio 525 B/op 3 allocs/op |
| `BenchmarkEncode/zstd3/testdata/mid.d` | 73718 | 32936 | 356.39 MB/s 0.1136 ratio 12310 B/op 1 allocs/op |
| `BenchmarkEncode/zstd9/testdata/mid.d` | 17984 | 132619 | 88.51 MB/s 0.1033 ratio 15222 B/op 1 allocs/op |
| `BenchmarkEncode/zstd1/testdata/mid.d` | 87090 | 27929 | 420.28 MB/s 0.1192 ratio 12295 B/op 1 allocs/op |
| `BenchmarkEncode/s2/testdata/mid.d` | 497401 | 4852 | 2419.41 MB/s 0.1741 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/s2better/testdata/mid.d` | 217046 | 11033 | 1063.89 MB/s 0.1630 ratio 0 B/op 0 allocs/op |
| `BenchmarkEncode/flate6/testdata/mid.d` | 11781 | 199502 | 58.84 MB/s 0.1009 ratio 813698 B/op 16 allocs/op |
| `BenchmarkDecode/lz4/testdata/small.o` | 510266 | 4534 | 1537.96 MB/s 176 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/small.o` | 773382 | 3132 | 2226.65 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/small.o` | 174120 | 13857 | 503.20 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/small.o` | 174368 | 13843 | 503.73 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/small.o` | 163984 | 14749 | 472.77 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.o` | 10000 | 228341 | 1502.55 MB/s 579 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.o` | 10000 | 227337 | 1509.18 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.o` | 4538 | 495574 | 692.31 MB/s 117 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.o` | 4628 | 478402 | 717.16 MB/s 87 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.o` | 4995 | 480709 | 713.72 MB/s 69 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big_g1.o` | 2925 | 821766 | 1556.12 MB/s 1594 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big_g1.o` | 3130 | 764014 | 1673.75 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big_g1.o` | 1680 | 1378121 | 927.91 MB/s 769 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big_g1.o` | 1854 | 1296596 | 986.25 MB/s 719 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big_g1.o` | 1887 | 1270777 | 1006.29 MB/s 682 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/big.o` | 907 | 2644281 | 1428.11 MB/s 4785 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/big.o` | 979 | 2415931 | 1563.09 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/big.o` | 522 | 4621975 | 817.04 MB/s 7248 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/big.o` | 536 | 4491160 | 840.83 MB/s 7241 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/big.o` | 535 | 4471246 | 844.58 MB/s 7061 B/op 0 allocs/op |
| `BenchmarkDecode/lz4/testdata/mid.d` | 449476 | 5347 | 2195.23 MB/s 169 B/op 2 allocs/op |
| `BenchmarkDecode/s2/testdata/mid.d` | 1000000 | 2300 | 5102.85 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd9/testdata/mid.d` | 251240 | 9365 | 1253.35 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd1/testdata/mid.d` | 237003 | 10024 | 1170.98 MB/s 0 B/op 0 allocs/op |
| `BenchmarkDecode/zstd3/testdata/mid.d` | 250302 | 9651 | 1216.28 MB/s 0 B/op 0 allocs/op |
| `BenchmarkMemcpyBaseline/testdata/small.o` | 33468508 | 71.89 | 96993.56 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.o` | 239372 | 10043 | 34162.42 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big_g1.o` | 46366 | 51825 | 24674.90 MB/s |
| `BenchmarkMemcpyBaseline/testdata/big.o` | 15765 | 152206 | 24810.65 MB/s |
| `BenchmarkMemcpyBaseline/testdata/mid.d` | 20137657 | 118.8 | 98825.61 MB/s |
| `BenchmarkCodecConstruct/zstd.NewReader` | 3134652 | 741.7 | 1304 B/op 7 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewReader/default-concurrency` | 1321737 | 1822 | 3776 B/op 13 allocs/op |
| `BenchmarkCodecConstruct/zstd.NewWriter` | 11397736 | 176.3 | 640 B/op 1 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewReader` | 16673694 | 159.7 | 304 B/op 2 allocs/op |
| `BenchmarkCodecConstruct/lz4.NewWriter` | 14732674 | 188.3 | 288 B/op 2 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/DecodeAll/pooled` | 4120 | 572804 | 598.97 MB/s 51 B/op 0 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/zstd/NewReader-per-call/stream` | 3339 | 656739 | 522.42 MB/s 950514 B/op 26 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/NewReader-per-call/stream` | 2512 | 851266 | 403.04 MB/s 8387520 B/op 6 allocs/op |
| `BenchmarkDecodeStreamVsOneShot/lz4/Reset/stream` | 9813 | 228390 | 1502.22 MB/s 1015 B/op 2 allocs/op |
| `BenchmarkContainerPack/framed` | 14179 | 163668 | 2429.61 MB/s 1032320 B/op 4 allocs/op |
| `BenchmarkContainerPack/tar` | 10000 | 217920 | 1824.75 MB/s 1034027 B/op 26 allocs/op |
| `BenchmarkContainerPack/tar+manifest` | 9793 | 242046 | 1642.87 MB/s 1064500 B/op 69 allocs/op |
| `BenchmarkContainerPack/zipStored` | 10000 | 218973 | 1815.98 MB/s 1042381 B/op 59 allocs/op |
| `BenchmarkContainerUnpackAll/framed` | 28850592 | 82.65 | 4811355.03 MB/s 96 B/op 1 allocs/op |
| `BenchmarkContainerUnpackAll/tar` | 30558 | 72519 | 5483.36 MB/s 401921 B/op 62 allocs/op |
| `BenchmarkContainerUnpackAll/zipStored` | 13888 | 171485 | 2318.87 MB/s 839555 B/op 108 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/inmem` | 1000000000 | 1.905 | 180146925.82 MB/s 0 B/op 0 allocs/op |
| `BenchmarkContainerReadObjectOnly/framed/pread` | 28604 | 84786 | 4046.57 MB/s 344250 B/op 2 allocs/op |
| `BenchmarkContainerReadObjectOnly/tar/scan` | 28640 | 94763 | 3620.52 MB/s 346623 B/op 56 allocs/op |
| `BenchmarkContainerReadObjectOnly/zipStored/central-dir` | 10000 | 219417 | 1563.65 MB/s 718519 B/op 53 allocs/op |
| `BenchmarkStat` | 125377 | 19169 | 256 B/op 2 allocs/op |
| `BenchmarkStatMiss` | 210562 | 11257 | 208 B/op 2 allocs/op |
| `BenchmarkOpenClose` | 108578 | 21877 | 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/4KiB` | 78399 | 30210 | 135.58 MB/s 360 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/200KiB` | 57855 | 40696 | 5032.44 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/512KiB` | 42957 | 55206 | 9496.86 MB/s 376 B/op 3 allocs/op |
| `BenchmarkOpenReadAll/5MiB` | 4815 | 528243 | 9925.13 MB/s 360 B/op 3 allocs/op |
| `BenchmarkReadOneContainer` | 42284 | 56325 | 9817.39 MB/s 376 B/op 3 allocs/op |
| `BenchmarkReadFourBlobs` | 16132 | 147885 | 3739.12 MB/s 1440 B/op 12 allocs/op |
| `BenchmarkHashSHA256/4KiB` | 822889 | 2753 | 1487.59 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/200KiB` | 18529 | 129626 | 1579.93 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/512KiB` | 7207 | 332210 | 1578.18 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashSHA256/5MiB` | 721 | 3324169 | 1577.20 MB/s 160 B/op 2 allocs/op |
| `BenchmarkHashCRC32C/4KiB` | 13318586 | 176.2 | 23248.71 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/200KiB` | 276406 | 8742 | 23427.77 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/512KiB` | 100518 | 23481 | 22327.79 MB/s 0 B/op 0 allocs/op |
| `BenchmarkHashCRC32C/5MiB` | 9757 | 246301 | 21286.51 MB/s 0 B/op 0 allocs/op |

### binpazer benchmarks

| benchmark | iters | ns/op | rest |
|---|--:|--:|---|
| `BenchmarkBaselineReadOne/tar/scan` | 35640 | 76552 | 4481.81 MB/s 346632 B/op 56 allocs/op |
| `BenchmarkBaselineReadOne/framed/pread` | 45418 | 53662 | 6393.62 MB/s 344243 B/op 2 allocs/op |
| `BenchmarkBinpazerPack/stored` | 13645 | 174617 | 2277.27 MB/s 911246 B/op 54 allocs/op |
| `BenchmarkBinpazerPack/stored+crc` | 14758 | 164750 | 2413.66 MB/s 911235 B/op 58 allocs/op |
| `BenchmarkBinpazerPack/zstd` | 487 | 5213351 | 76.28 MB/s 28286374 B/op 290 allocs/op |
| `BenchmarkBinpazerPack/lz4` | 1316 | 1802113 | 220.66 MB/s 1236587 B/op 82 allocs/op |
| `BenchmarkBinpazerReadAll/stored` | 12069 | 195494 | 2034.08 MB/s 899780 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/stored+crc` | 12984 | 185202 | 2147.11 MB/s 899782 B/op 120 allocs/op |
| `BenchmarkBinpazerReadAll/zstd` | 1352 | 1782145 | 223.13 MB/s 11901135 B/op 305 allocs/op |
| `BenchmarkBinpazerReadAll/lz4` | 6466 | 370673 | 1072.78 MB/s 961571 B/op 148 allocs/op |
| `BenchmarkBinpazerReadOne/stored` | 14370 | 171493 | 2000.61 MB/s 779347 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/stored+crc` | 13537 | 177262 | 1935.51 MB/s 779347 B/op 78 allocs/op |
| `BenchmarkBinpazerReadOne/zstd` | 1527 | 1516553 | 226.23 MB/s 11483429 B/op 138 allocs/op |
| `BenchmarkBinpazerReadOne/lz4` | 7305 | 327983 | 1046.07 MB/s 846492 B/op 85 allocs/op |
| `BenchmarkBinpazerReadOne/sized/stored` | 21424 | 115522 | 2969.92 MB/s 411858 B/op 59 allocs/op |
| `BenchmarkBinpazerReadOne/sized/zstd` | 1617 | 1659317 | 206.77 MB/s 11115537 B/op 117 allocs/op |
| `BenchmarkBinpazerReadOne/sized/lz4` | 2541 | 949994 | 361.15 MB/s 8799468 B/op 67 allocs/op |
| `BenchmarkBinpazerReadOne/stored/file` | 9732 | 255337 | 1343.68 MB/s 779448 B/op 77 allocs/op |

