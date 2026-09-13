| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `C client, dynamic: connect+roundtrip+exit` | 1.6 ± 0.1 | 1.5 | 1.9 | 1.17 ± 0.07 |
| `C client, static: connect+roundtrip+exit` | 1.5 ± 0.1 | 1.4 | 1.8 | 1.08 ± 0.06 |
| `Go client: connect+roundtrip+exit` | 1.8 ± 0.2 | 1.6 | 3.0 | 1.29 ± 0.13 |
| `C hello (no daemon contact)` | 1.4 ± 0.1 | 1.3 | 1.7 | 1.00 |
| `Go hello (no daemon contact)` | 1.4 ± 0.2 | 1.2 | 3.9 | 1.01 ± 0.14 |
