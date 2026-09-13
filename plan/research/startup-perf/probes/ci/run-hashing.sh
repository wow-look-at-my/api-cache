#!/usr/bin/env bash
# Measurement family 5: the hashing throughput floor.
#
# A compiler wrapper hashes something on every invocation, so its cache key
# costs whatever the hash costs per megabyte. This is in-process throughput,
# not a process measurement, so the probe times it itself.
#
# Whether the CPU carries SHA-NI decides the sha256 row by an order of
# magnitude, so the job records the CPU's flags beside the numbers.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/.." && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
N="${BENCH_N:-60}"

{
	echo "# hashing throughput: $(uname -s) $(uname -m)"
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`  (GitHub Actions hosted runner)"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- go: $(go version)"
	if [ -r /proc/cpuinfo ]; then
		echo "- cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
		echo "- sha extensions: $(grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -c '^sha_ni$' | sed 's/^0$/absent (sha_ni not in flags)/;s/^1$/present (sha_ni)/')"
	else
		echo "- cpu: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
		echo "- sha extensions: ARM64 runners carry the ARMv8 crypto extensions, which Go's sha256 uses"
	fi
	echo
} > "$OUT/hashing.md"

( cd "$P/hashing" && CGO_ENABLED=0 go build -tags blake3 -o "$OUT/hashbench" . )
"$OUT/hashbench" -n "$N" >> "$OUT/hashing.md"
cat "$OUT/hashing.md"
