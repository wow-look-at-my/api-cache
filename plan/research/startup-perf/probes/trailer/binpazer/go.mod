module probe/trailer/binpazer

go 1.24

require github.com/wow-look-at-my/bin-file-fmt/go v0.0.0

require (
	github.com/klauspost/compress v1.19.1 // indirect
	github.com/pierrec/lz4/v4 v4.1.27 // indirect
)

// The format lives in this repository as the submodule at refs/bin-file-fmt,
// so the probe measures the exact revision the repository pins rather than
// whatever the module proxy last published.
replace github.com/wow-look-at-my/bin-file-fmt/go => ../../../../../../refs/bin-file-fmt/go
