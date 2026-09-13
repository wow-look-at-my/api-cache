#!/usr/bin/env bash
# Download one startup-perf artifact zip and unpack its markdown and JSON into
# results/gha/<artifact name>/.
#
# The download URL is a short-lived signed blob link obtained from the GitHub
# API, so it is passed in rather than derived here.
#
# usage: fetch-artifacts.sh <artifact-name> <signed-url>
set -euo pipefail
NAME="$1"
URL="$2"
R="$(cd "$(dirname "$0")/../../results" && pwd)"
DEST="$R/gha/$NAME"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/a.zip"
# Only the reports are kept. The artifact also carries the built probe
# binaries, which are megabytes and belong in nobody's git history.
unzip -o -j "$TMP/a.zip" '*.md' '*.json' '*.txt' -d "$DEST" > "$DEST/.unzip.log" 2>&1 || true
rm -f "$DEST/.unzip.log"
ls -la "$DEST"
