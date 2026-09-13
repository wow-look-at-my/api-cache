| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `Go hello (baseline)` | 1.5 ± 0.3 | 1.2 | 3.9 | 1.00 |
| `Go + crypto/sha256` | 1.5 ± 0.2 | 1.3 | 4.8 | 1.02 ± 0.24 |
| `Go + encoding/xml` | 1.5 ± 0.2 | 1.2 | 2.1 | 1.03 ± 0.21 |
| `Go + text/template` | 1.7 ± 0.2 | 1.3 | 3.8 | 1.11 ± 0.25 |
| `Go + net/http` | 2.1 ± 0.1 | 1.7 | 2.6 | 1.39 ± 0.26 |
| `Go + xml + template + net/http` | 2.1 ± 0.2 | 1.7 | 3.2 | 1.40 ± 0.28 |
| `Go + cobra (root cmd built and run)` | 1.9 ± 0.5 | 1.5 | 7.6 | 1.29 ± 0.39 |
| `Go + sprig linked, map not built` | 2.5 ± 0.2 | 2.1 | 3.4 | 1.68 ± 0.33 |
| `Go + sprig TxtFuncMap() built` | 2.3 ± 0.2 | 2.0 | 4.2 | 1.56 ± 0.32 |
