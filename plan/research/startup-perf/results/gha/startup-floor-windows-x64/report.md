# startup floor: Windows X64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `windows-latest`
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- cpu cores: 4
- cl: usage: cl [ option... ] filename... [ /link linkoption... ]
- go: go version go1.24.13 windows/amd64
- rustc: rustc 1.98.1 (48a229cea 2026-09-01)
- hyperfine: hyperfine 1.19.0
- method: `hyperfine --shell=none --warmup 20 --runs 300`


## binary sizes

| binary | bytes |
|---|---|
| c-dyn.exe | 9728 |
| c-static.exe | 110592 |
| cpp-dyn.exe | 11776 |
| cpp-static.exe | 215040 |
| go-hello-nocgo.exe | 1985536 |
| go-hello-cgo.exe | 1986048 |
| go-hello-sw.exe | 1314816 |
| go-imports.exe | 5303296 |
| rust-hello.exe | 131072 |
