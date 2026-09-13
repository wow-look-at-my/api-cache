# startup floor: Linux aarch64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-24.04-arm`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- cpu cores: 4
- cc: cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
- c++: c++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
- go: go version go1.24.13 linux/arm64
- rustc: rustc 1.98.1 (48a229cea 2026-09-01)
- hyperfine: hyperfine 1.19.0
- method: `hyperfine --shell=none --warmup 20 --runs 300`

| Command | Mean [µs] | Min [µs] | Max [µs] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, dynamic` | 474.0 ± 31.0 | 402.1 | 567.7 | 1.36 ± 0.12 |
| `C++ iostream, dynamic` | 915.8 ± 34.2 | 826.3 | 1029.7 | 2.62 ± 0.18 |
| `C hello, static` | 349.0 ± 20.0 | 310.3 | 446.0 | 1.00 |
| `C++ iostream, static` | 443.0 ± 27.1 | 383.0 | 539.3 | 1.27 ± 0.11 |
| `C++ iostream, -static-libstdc++` | 582.6 ± 31.5 | 520.2 | 699.7 | 1.67 ± 0.13 |
| `Go hello, CGO_ENABLED=0` | 915.8 ± 46.8 | 807.4 | 1199.2 | 2.62 ± 0.20 |
| `Go hello, CGO_ENABLED=1` | 913.7 ± 52.3 | 810.9 | 1389.9 | 2.62 ± 0.21 |
| `Go hello, -ldflags=-s -w` | 919.4 ± 43.2 | 831.6 | 1366.6 | 2.63 ± 0.20 |
| `Go + net/http + encoding/xml + text/template` | 1135.5 ± 67.8 | 1002.6 | 1753.8 | 3.25 ± 0.27 |
| `Rust hello` | 634.9 ± 33.1 | 562.1 | 805.2 | 1.82 ± 0.14 |

## binary sizes

| binary | bytes |
|---|---|
| c-dyn | 70360 |
| c-static | 639600 |
| cpp-dyn | 70504 |
| cpp-static | 2249424 |
| cpp-staticcxx | 1603296 |
| go-hello-nocgo | 1958888 |
| go-hello-cgo | 1958856 |
| go-hello-sw | 1310904 |
| go-imports | 4978051 |
| rust-hello | 4573904 |
