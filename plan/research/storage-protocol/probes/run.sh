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
{
	uname -a 2>/dev/null || true
	(lscpu 2>/dev/null | grep -E 'Model name|^CPU\(s\)') || sysctl -n machdep.cpu.brand_string 2>/dev/null || true
	(grep -o -E 'sha_ni|avx2|avx512f' /proc/cpuinfo 2>/dev/null | sort -u | tr '\n' ' ') || true
	echo
	df -T . 2>/dev/null | tail -1 || df . | tail -1
	$GO version
} > "$OUT/machine.txt" 2>&1
$GO test -run 'TestRatios|TestContainerOverhead' -v . > "$OUT/tables.txt" 2>&1
$GO test -run '^$' -bench . -benchtime "$BENCHTIME" -count 1 . > "$OUT/bench.txt" 2>&1
if [ -d binpazer ]; then
	(cd binpazer && $GO test -run 'TestBinpazer' -v . > "../$OUT/binpazer-tables.txt" 2>&1 || true)
	(cd binpazer && $GO test -run '^$' -bench . -benchtime "$BENCHTIME" -count 1 . > "../$OUT/binpazer-bench.txt" 2>&1 || true)
fi
tail -3 "$OUT/bench.txt"
