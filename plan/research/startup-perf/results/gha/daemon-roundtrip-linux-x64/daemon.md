# daemon round trip: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`  (GitHub Actions hosted runner)
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- go: go version go1.24.13 linux/amd64
- hyperfine: hyperfine 1.19.0
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- protocol: 4-byte length prefix, 512-byte request, 65-byte reply. No framing library.

## (a) whole process: exec the client, connect, round trip, exit

hyperfine, `--shell=none --warmup 20 --runs 300`. The two
"no daemon contact" rows are the same languages doing nothing, so the
round trip is the difference.

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C client, dynamic` | 798.5 ± 34.3 | 722.9 | 943.8 | 1.31 ± 0.10 |
| `C client, static` | 608.0 ± 35.5 | 544.5 | 737.4 | 1.00 |
| `Go client` | 1290.2 ± 70.3 | 1165.7 | 1733.4 | 2.12 ± 0.17 |
| `C hello, no daemon contact` | 635.4 ± 33.9 | 582.6 | 829.8 | 1.05 ± 0.08 |
| `Go hello, no daemon contact` | 1059.6 ± 57.1 | 947.0 | 1381.5 | 1.74 ± 0.14 |

## (b) the round trip alone, in process, mean of 2000

```
go client: dial+roundtrip+close 81.4 us/op   roundtrip only (reused conn) 27.6 us/op
c client:  dial+roundtrip+close 66.0 us/op   roundtrip only (reused conn) 22.2 us/op
```
