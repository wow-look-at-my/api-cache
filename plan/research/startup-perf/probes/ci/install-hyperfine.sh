#!/usr/bin/env bash
# Put hyperfine (github.com/sharkdp/hyperfine, MIT OR Apache-2.0) on PATH for a
# GitHub Actions runner. hyperfine is the reported measurement method for every
# exec timing in this research directory.
#
# The release binaries are used rather than `cargo install`, which takes minutes
# on a cold runner. macOS gets the same treatment rather than brew, so all three
# platforms run the same version.
set -euo pipefail
VER="${HYPERFINE_VERSION:-1.19.0}"
DEST="${HYPERFINE_DEST:-$HOME/.hyperfine/bin}"
mkdir -p "$DEST"

case "$(uname -s)" in
	Linux)  OS=unknown-linux-musl ;;
	Darwin) OS=apple-darwin ;;
	*) echo "install-hyperfine.sh is for unix runners; Windows uses the PowerShell path" >&2; exit 1 ;;
esac
case "$(uname -m)" in
	x86_64|amd64)  ARCH=x86_64 ;;
	aarch64|arm64) ARCH=aarch64 ;;
	*) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

NAME="hyperfine-v${VER}-${ARCH}-${OS}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fSL "https://github.com/sharkdp/hyperfine/releases/download/v${VER}/${NAME}.tar.gz" -o "$TMP/hf.tar.gz"
tar -xzf "$TMP/hf.tar.gz" -C "$TMP"
install -m 0755 "$TMP/$NAME/hyperfine" "$DEST/hyperfine"
echo "$DEST" >> "${GITHUB_PATH:-/dev/null}"
"$DEST/hyperfine" --version
