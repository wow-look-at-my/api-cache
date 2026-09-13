# startup floor: Darwin arm64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `macos-latest`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728781892
- commit: `9b08f713116e98c791d5c07099188657b1704fbd`
- cpu cores: 3
- cc: Apple clang version 21.0.0 (clang-2100.1.1.101)
- c++: Apple clang version 21.0.0 (clang-2100.1.1.101)
- go: go version go1.24.13 darwin/arm64
- rustc: rustc 1.98.1 (48a229cea 2026-09-01)
- hyperfine: hyperfine 1.19.0
- method: `hyperfine --shell=none --warmup 20 --runs 300`

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, dynamic` | 2.2 ± 0.7 | 1.1 | 3.5 | 1.09 ± 0.46 |
| `C++ iostream, dynamic` | 2.0 ± 0.6 | 1.4 | 3.9 | 1.00 |
| `Go hello, CGO_ENABLED=0` | 2.5 ± 0.2 | 2.1 | 3.7 | 1.22 ± 0.35 |
| `Go hello, CGO_ENABLED=1` | 2.8 ± 0.6 | 2.0 | 5.9 | 1.36 ± 0.47 |
| `Go hello, -ldflags=-s -w` | 2.9 ± 0.7 | 1.8 | 5.7 | 1.44 ± 0.52 |
| `Go + net/http + encoding/xml + text/template` | 5.2 ± 0.7 | 3.7 | 8.3 | 2.55 ± 0.79 |
| `Rust hello` | 2.3 ± 0.6 | 1.6 | 3.8 | 1.14 ± 0.45 |

## binary sizes

| binary | bytes |
|---|---|
| c-dyn | 33480 |
| cpp-dyn | 35912 |
| go-hello-nocgo | 2005170 |
| go-hello-cgo | 2005170 |
| go-hello-sw | 1335634 |
| go-imports | 5017618 |
| rust-hello | 469160 |

> **No static rows on macOS, by platform rule rather than by failure.**
> Apple does not support statically linking libSystem (no crt1.o is
> shipped for it and the ABI is the dylib), and clang on macOS links
> libc++ dynamically. The static targets are therefore not attempted
> here. Every target this platform DOES support was built and timed;
> a failure in any of them fails the job.
