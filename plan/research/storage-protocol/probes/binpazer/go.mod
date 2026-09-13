module apicache/probes/binpazer

go 1.24

require github.com/wow-look-at-my/bin-file-fmt/go v0.0.0

require (
	github.com/klauspost/compress v1.19.1 // indirect
	github.com/pierrec/lz4/v4 v4.1.27 // indirect
)

// bin-file-fmt is a git submodule at refs/bin-file-fmt (repository root).
// The relative path works both locally and in CI.
replace github.com/wow-look-at-my/bin-file-fmt/go => ../../../../../refs/bin-file-fmt/go
