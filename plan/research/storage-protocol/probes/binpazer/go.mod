module apicache/probes/binpazer

go 1.24

require github.com/wow-look-at-my/bin-file-fmt/go v0.0.0

// Local development points at the read-only reference clone. CI rewrites this
// with `go mod edit -replace` after checking the repository out; see
// .github/workflows/storage-bench.yml.
replace github.com/wow-look-at-my/bin-file-fmt/go => /home/user/refs/bin-file-fmt/go
