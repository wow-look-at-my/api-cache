#!/usr/bin/env bash
# Install hyperfine (github.com/sharkdp/hyperfine, MIT OR Apache-2.0) into
# $HOME, not into the repo tree. hyperfine is the reported measurement method
# for every exec timing here; the C harness beside it stays only as a probe.
set -euo pipefail
VER="${HYPERFINE_VERSION:-1.19.0}"
DEST="${HYPERFINE_DEST:-$HOME/.local/bin}"
case "$(uname -m)" in
	x86_64|amd64) ARCH=x86_64 ;;
	aarch64|arm64) ARCH=aarch64 ;;
	*) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
TARBALL="hyperfine-v${VER}-${ARCH}-unknown-linux-musl"
URL="https://github.com/sharkdp/hyperfine/releases/download/v${VER}/${TARBALL}.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "fetching $URL"
curl -fSL "$URL" -o "$TMP/hf.tar.gz"
tar -xzf "$TMP/hf.tar.gz" -C "$TMP"
mkdir -p "$DEST"
install -m 0755 "$TMP/$TARBALL/hyperfine" "$DEST/hyperfine"
"$DEST/hyperfine" --version
