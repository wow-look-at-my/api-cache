#!/bin/sh
# Regenerates results/. RESULTS_DIR overrides the output directory, which CI
# uses to keep one directory per runner.
set -eu
cd "$(dirname "$0")"
OUT=${RESULTS_DIR:-results}
GO=${GO:-go}
BENCHTIME=${BENCHTIME:-500ms}
[ -f testdata/mid.o ] || ./gen-testdata.sh
mkdir -p "$OUT"
# Machine description. Every branch writes something; nothing is swallowed, so
# a runner whose CPU cannot be identified says so in the results instead of
# leaving a blank line that reads like an answer.
{
	uname -a
	if [ -r /proc/cpuinfo ]; then
		grep -m1 '^model name' /proc/cpuinfo
		nproc
		echo "cpu flags of interest: $(grep -o -E 'sha_ni|avx2|avx512f' /proc/cpuinfo | sort -u | tr '\n' ' ')"
	elif command -v sysctl >/dev/null 2>&1; then
		sysctl -n machdep.cpu.brand_string
		sysctl -n hw.ncpu
		echo "cpu flags of interest: NOT PROBED (no /proc/cpuinfo)"
	else
		echo "CPU: UNKNOWN on this platform"
	fi
	df . | tail -1
	$GO version
} > "$OUT/machine.txt" 2>&1
$GO test -run 'TestRatios|TestContainerOverhead' -v . > "$OUT/tables.txt" 2>&1
$GO test -run '^$' -bench . -benchtime "$BENCHTIME" -count 1 . > "$OUT/bench.txt" 2>&1
# The binpazer probe is mandatory; a missing directory is a failure.
[ -d binpazer ] || { echo "binpazer probe directory missing" >&2; exit 1; }
(cd binpazer && $GO test -run 'TestBinpazer' -v . > "../$OUT/binpazer-tables.txt" 2>&1)
(cd binpazer && $GO test -run '^$' -bench . -benchtime "$BENCHTIME" -count 1 . > "../$OUT/binpazer-bench.txt" 2>&1)
tail -3 "$OUT/bench.txt"
