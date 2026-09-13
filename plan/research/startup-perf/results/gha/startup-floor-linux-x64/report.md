# startup floor: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- cpu cores: 4
- cc: cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
- c++: c++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
- go: go version go1.24.13 linux/amd64
- rustc: rustc 1.98.1 (48a229cea 2026-09-01)
- hyperfine: hyperfine 1.19.0
- method: `hyperfine --shell=none --warmup 20 --runs 300`

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, dynamic` | 652.5 ± 41.9 | 585.3 | 884.0 | 1.45 ± 0.14 |
| `C++ iostream, dynamic` | 1154.3 ± 51.9 | 1076.0 | 1379.4 | 2.56 ± 0.22 |
| `C hello, static` | 450.8 ± 32.7 | 405.4 | 617.4 | 1.00 |
| `C++ iostream, static` | 567.7 ± 35.3 | 518.7 | 829.8 | 1.26 ± 0.12 |
| `C++ iostream, -static-libstdc++` | 741.7 ± 41.0 | 676.8 | 977.0 | 1.65 ± 0.15 |
| `Go hello, CGO_ENABLED=0` | 1041.2 ± 73.0 | 906.8 | 1330.9 | 2.31 ± 0.23 |
| `Go hello, CGO_ENABLED=1` | 1059.2 ± 58.2 | 935.0 | 1272.8 | 2.35 ± 0.21 |
| `Go hello, -ldflags=-s -w` | 1028.4 ± 70.8 | 908.8 | 1498.5 | 2.28 ± 0.23 |
| `Go + net/http + encoding/xml + text/template` | 1259.8 ± 82.2 | 1132.2 | 1526.4 | 2.79 ± 0.27 |
| `Rust hello` | 814.6 ± 41.2 | 740.5 | 1024.6 | 1.81 ± 0.16 |

## binary sizes

| binary | bytes |
|---|---|
| c-dyn | 16008 |
| c-static | 785232 |
| cpp-dyn | 16152 |
| cpp-static | 2330544 |
| cpp-staticcxx | 1433224 |
| go-hello-nocgo | 1889616 |
| go-hello-cgo | 1889608 |
| go-hello-sw | 1216696 |
| go-imports | 5126640 |
| rust-hello | 4505288 |
