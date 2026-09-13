# hashing throughput: Linux aarch64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-24.04-arm`
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- go: go version go1.24.13 linux/arm64
- cpu: 
- sha extensions: absent (sha_ni not in flags)

# hashing throughput

- buffer: 4096 KiB, already in memory
- iterations: 60, median reported

| hash | MB/s | us per 200 KiB | note |
|---|---|---|---|
| sha256 | 2025 | 99 | stdlib; uses SHA-NI where the CPU has it |
| sha512 | 1267 | 158 | stdlib; AVX2 path, often faster than sha256 without SHA-NI |
| sha1 | 1952 | 102 | stdlib; broken for security, listed as a speed reference only |
| md5 | 677 | 295 | stdlib; broken for security, listed as a speed reference only |
| crc32 (Castagnoli) | 25787 | 8 | SSE4.2 hardware CRC; not collision resistant |
| fnv64a | 1041 | 192 | stdlib; not collision resistant |
| xxhash64 (inlined here) | 14216 | 14 | algorithm public domain, reference impl BSD-2-Clause; not collision resistant |
| blake3 (lukechampine.com/blake3, MIT) | 1405 | 142 | pure Go, AVX-512 path; cryptographic |

## end to end: open + read + sha256 + close, one 200 KiB file

| method | us | note |
|---|---|---|
| io.Copy into sha256 | 112 | 32 KiB default copy buffer, warm page cache |
| os.ReadFile then sha256.Sum256 | 118 | one allocation of the whole file, warm page cache |
| reused 256 KiB buffer | 107 | no per-call allocation, warm page cache |
| open + close only | 2 | the syscall floor under every row above |

