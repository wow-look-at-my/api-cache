| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, dynamic` | 2.2 ± 0.7 | 1.1 | 3.5 | 1.09 ± 0.46 |
| `C++ iostream, dynamic` | 2.0 ± 0.6 | 1.4 | 3.9 | 1.00 |
| `Go hello, CGO_ENABLED=0` | 2.5 ± 0.2 | 2.1 | 3.7 | 1.22 ± 0.35 |
| `Go hello, CGO_ENABLED=1` | 2.8 ± 0.6 | 2.0 | 5.9 | 1.36 ± 0.47 |
| `Go hello, -ldflags=-s -w` | 2.9 ± 0.7 | 1.8 | 5.7 | 1.44 ± 0.52 |
| `Go + net/http + encoding/xml + text/template` | 5.2 ± 0.7 | 3.7 | 8.3 | 2.55 ± 0.79 |
| `Rust hello` | 2.3 ± 0.6 | 1.6 | 3.8 | 1.14 ± 0.45 |
