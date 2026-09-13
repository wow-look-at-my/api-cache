| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C hello, MSVC /MD (shared CRT)` | 6.0 ± 0.6 | 5.4 | 8.4 | 1.14 ± 0.11 |
| `C hello, MSVC /MT (static CRT)` | 5.2 ± 0.3 | 5.0 | 6.6 | 1.00 ± 0.06 |
| `C++ iostream, MSVC /MD (shared CRT)` | 6.2 ± 0.3 | 5.8 | 8.6 | 1.18 ± 0.08 |
| `C++ iostream, MSVC /MT (static CRT)` | 5.2 ± 0.2 | 5.0 | 6.5 | 1.00 |
| `Go hello, CGO_ENABLED=0` | 7.3 ± 0.3 | 6.9 | 8.4 | 1.39 ± 0.07 |
| `Go hello, CGO_ENABLED=1` | 7.3 ± 0.4 | 7.0 | 9.8 | 1.40 ± 0.09 |
| `Go hello, -ldflags=-s -w` | 7.3 ± 0.3 | 6.9 | 8.6 | 1.39 ± 0.08 |
| `Go + net/http + encoding/xml + text/template` | 9.5 ± 0.5 | 9.0 | 12.8 | 1.82 ± 0.12 |
| `Rust hello` | 5.7 ± 0.5 | 5.3 | 9.5 | 1.10 ± 0.10 |
