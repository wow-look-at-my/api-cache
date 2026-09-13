# hashing throughput: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- go: go version go1.24.13 linux/amd64
- cpu: AMD EPYC 7763 64-Core Processor
- sha extensions: present (sha_ni)

# hashing throughput

- buffer: 4096 KiB, already in memory
- iterations: 60, median reported

| hash | MB/s | us per 200 KiB | note |
|---|---|---|---|
| sha256 | 1513 | 132 | stdlib; uses SHA-NI where the CPU has it |
| sha512 | 648 | 309 | stdlib; AVX2 path, often faster than sha256 without SHA-NI |
| sha1 | 1049 | 191 | stdlib; broken for security, listed as a speed reference only |
| md5 | 677 | 295 | stdlib; broken for security, listed as a speed reference only |
| crc32 (Castagnoli) | 20989 | 10 | SSE4.2 hardware CRC; not collision resistant |
| fnv64a | 764 | 262 | stdlib; not collision resistant |
| xxhash64 (inlined here) | 6483 | 31 | algorithm public domain, reference impl BSD-2-Clause; not collision resistant |
| blake3 (lukechampine.com/blake3, MIT) | 4653 | 43 | pure Go, AVX-512 path; cryptographic |

## end to end: open + read + sha256 + close, one 200 KiB file

| method | us | note |
|---|---|---|
| io.Copy into sha256 | 152 | 32 KiB default copy buffer, warm page cache |
| os.ReadFile then sha256.Sum256 | 151 | one allocation of the whole file, warm page cache |
| reused 256 KiB buffer | 142 | no per-call allocation, warm page cache |
| open + close only | 5 | the syscall floor under every row above |

