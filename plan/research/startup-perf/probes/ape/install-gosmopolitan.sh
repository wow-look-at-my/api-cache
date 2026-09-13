#!/usr/bin/env bash
# Install the org's gosmopolitan Go fork (GOOS=cosmo, fat Actually Portable
# Executable output) into $HOME, NOT into the repo tree.
#
# Resolution follows go-toolchain's own src/cmd/cosmobootstrap.go: buildhost
# serves the tarball at dl.pazer.build/gosmopolitan and decides what exists for
# the asking host. There is no version list to keep in step here.
set -euo pipefail
BRANCH="${GO_TOOLCHAIN_COSMO_BRANCH:-master}"
DEST="${COSMO_DEST:-$HOME/gosmopolitan}"
OS="${OS_OVERRIDE:-linux}"
ARCH="${ARCH_OVERRIDE:-amd64}"
URL="https://dl.pazer.build/gosmopolitan?branch=${BRANCH}&os=${OS}&arch=${ARCH}"

mkdir -p "$DEST"
echo "fetching $URL"
curl -fSL --compressed "$URL" -o "$DEST/gosmopolitan.tar.gz"
ls -la "$DEST/gosmopolitan.tar.gz"
# The tarball carries a top-level go/ directory, per cosmobootstrap.go.
tar -xzf "$DEST/gosmopolitan.tar.gz" -C "$DEST"
echo "GOROOT=$DEST/go"
"$DEST/go/bin/go" version
