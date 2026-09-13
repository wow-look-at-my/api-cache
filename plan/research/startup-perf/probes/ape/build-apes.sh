#!/usr/bin/env bash
# Build the startup probes as fat APEs with the gosmopolitan fork, exactly as
# go-toolchain does: GOOS=cosmo, CGO_ENABLED=0, no GOARCH (fat is the default),
# -trimpath and an empty build id.
set -euo pipefail
GOROOT_COSMO="${COSMO_GOROOT:-$HOME/gosmopolitan/go}"
P="$(cd "$(dirname "$0")/.." && pwd)"
B="$(cd "$P/../bin" && pwd)"
export GOROOT="$GOROOT_COSMO"
export PATH="$GOROOT/bin:$PATH"
export GOTOOLCHAIN=local
export GOOS=cosmo
export CGO_ENABLED=0
unset GOARCH || true

build() { # build <srcdir> <outname>
	( cd "$1" && go build -trimpath -ldflags=-buildid= -o "$B/$2" . )
	echo "built $2: $(stat -c%s "$B/$2") bytes"
}
build "$P/go-hello"              ape-hello
build "$P/go-imports/stdlib-all" ape-stdlib-all
build "$P/go-imports/stdlib-xml" ape-stdlib-xml
