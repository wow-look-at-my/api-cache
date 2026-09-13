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
	echo "> Measured on a GitHub Actions hosted runner. Not a development machine."
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`"
	echo "- commit: \`${GITHUB_SHA:-?}\`"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- go: $(go version)"
	# The CPU feature name differs by architecture, and getting it wrong makes
	# the sha256 row unreadable: x86 reports `sha_ni` in `flags`, while ARM64
	# reports `sha2` in `Features`. An arm64 run once printed "sha_ni absent"
	# beside 2 GB/s of sha256, which is the crypto extensions plainly in use.
	if [ -r /proc/cpuinfo ]; then
		# `grep` exits 1 when it matches nothing, which under `set -e` killed the
		# whole arm64 job: ARM64 /proc/cpuinfo carries no "model name" line. This
		# is a descriptive header field, not a measurement, so a miss reports what
		# the kernel does give instead of aborting.
		model="$( (grep -m1 -E '^(model name|Model|CPU part)' /proc/cpuinfo || true) | cut -d: -f2- | sed 's/^ //')"
		[ -n "$model" ] || model="$(uname -m); the kernel exposes no model string on this platform"
		echo "- cpu: $model"
		case "$(uname -m)" in
			x86_64|amd64)
				if (grep -m1 '^flags' /proc/cpuinfo || true) | tr ' ' '\n' | grep -qx 'sha_ni'; then
					echo "- sha acceleration: **present** (x86 \`sha_ni\`); Go's sha256 uses it"
				else
					echo "- sha acceleration: **absent** (no x86 \`sha_ni\`); Go's sha256 runs the generic path"
				fi ;;
			aarch64|arm64)
				if (grep -m1 '^Features' /proc/cpuinfo || true) | tr ' ' '\n' | grep -qx 'sha2'; then
					echo "- sha acceleration: **present** (ARMv8 \`sha2\` crypto extensions); Go's sha256 uses it"
				else
					echo "- sha acceleration: **absent** (no ARMv8 \`sha2\`); Go's sha256 runs the generic path"
				fi ;;
			*) echo "- sha acceleration: unknown for $(uname -m)" ;;
		esac
	else
		echo "- cpu: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
		echo "- sha acceleration: Apple silicon carries the ARMv8 crypto extensions; Go's sha256 uses them"
	fi
	echo
} > "$OUT/hashing.md"

( cd "$P/hashing" && CGO_ENABLED=0 go build -o "$OUT/hashbench" . )
"$OUT/hashbench" -n "$N" >> "$OUT/hashing.md"
cat "$OUT/hashing.md"
