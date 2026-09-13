# Vendored: binpazer C implementation

`binpazer.c` and `binpazer.h` are copied verbatim from
`github.com/wow-look-at-my/bin-file-fmt`, directory `c/`, MIT licensed
(`LICENSE` beside them).

They are vendored rather than fetched because the Go module proxy serves only
the `go/` subdirectory of that repository, and the repository itself is not
anonymously clonable from a GitHub Actions runner. The Go half of the same
format IS fetched normally, as `github.com/wow-look-at-my/bin-file-fmt/go`.

Nothing here is modified. Refresh by re-copying both files and the LICENSE.
