#!/usr/bin/env bash
# Measurement family 2: what a declarative XML config costs per exec.
#
# This one is NOT a hyperfine job. The stages inside a config load (tokenize,
# compile placeholders, parse templates, execute, decode a cooked form) are
# tens to hundreds of microseconds each and happen inside one process, so
# timing them from outside would measure only their sum against a millisecond
# of process startup. The probe times each stage in process and reports a
# median over many iterations. The number that IS measured from outside, the
# exec floor those microseconds sit on top of, comes from the startup job.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/.." && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
N="${BENCH_N:-400}"

{
	echo "# config load cost: $(uname -s) $(uname -m)"
	echo
	echo "> Measured on a GitHub Actions hosted runner. Not a development machine."
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`"
	echo "- commit: \`${GITHUB_SHA:-?}\`"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- cpu cores: $( (nproc 2>/dev/null) || sysctl -n hw.ncpu )"
	echo "- go: $(go version)"
	echo "- method: in-process, median of $N iterations per stage"
	echo
} > "$OUT/config-load.md"

( cd "$P/xml-parse" && go build -o "$OUT/xmlbench" . )
"$OUT/xmlbench" -n "$N" -f "$P/fixtures/github.xml" >> "$OUT/config-load.md"
cat "$OUT/config-load.md"
