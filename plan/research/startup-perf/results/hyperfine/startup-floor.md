| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C null, static` | 1.3 ± 0.1 | 1.2 | 2.2 | 1.00 |
| `C null, dynamic` | 1.5 ± 0.2 | 1.3 | 3.6 | 1.11 ± 0.16 |
| `C hello write(2), static` | 1.4 ± 0.1 | 1.2 | 1.9 | 1.03 ± 0.11 |
| `C hello write(2), dynamic` | 1.4 ± 0.1 | 1.3 | 2.7 | 1.09 ± 0.12 |
| `C hello printf, static` | 1.3 ± 0.1 | 1.2 | 1.9 | 1.00 ± 0.10 |
| `C hello printf, dynamic` | 1.5 ± 0.1 | 1.3 | 2.2 | 1.12 ± 0.12 |
| `Rust hello` | 1.7 ± 0.1 | 1.5 | 2.4 | 1.29 ± 0.13 |
| `Go hello` | 1.4 ± 0.1 | 1.1 | 1.9 | 1.09 ± 0.14 |
| `Go hello, -ldflags=-s -w` | 1.6 ± 0.2 | 1.2 | 2.5 | 1.23 ± 0.20 |
| `Go hello, CGO_ENABLED=1` | 1.4 ± 0.1 | 1.2 | 2.1 | 1.08 ± 0.13 |
