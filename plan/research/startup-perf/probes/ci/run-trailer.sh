#!/usr/bin/env bash
# Measurement family 3: the cooked-trailer idea.
#
# Two separate questions, measured two different ways.
#
#   (a) Does appending megabytes to an executable slow its exec? That is a
#       whole-process question, so hyperfine answers it, with the target in
#       "quiet" mode so it exits without reading the trailer.
#   (b) What does READING the trailer cost? Microseconds, in process, so the
#       probes time it themselves: a raw offset read, then the same read
#       through binpazer from Go, then through binpazer's C implementation.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/.." && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
RUNS="${BENCH_RUNS:-300}"
WARMUP="${BENCH_WARMUP:-20}"
N="${BENCH_N:-400}"

{
	echo "# cooked trailer: $(uname -s) $(uname -m)"
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`  (GitHub Actions hosted runner)"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- go: $(go version)"
	echo "- cc: $(${CC:-cc} --version 2>&1 | head -1)"
	echo "- hyperfine: $(hyperfine --version)"
	echo
} > "$OUT/trailer.md"

( cd "$P/trailer"          && CGO_ENABLED=0 go build -o "$OUT/trailer" . )
( cd "$P/trailer/appender" && CGO_ENABLED=0 go build -o "$OUT/appender" . )
( cd "$P/trailer/binpazer" && CGO_ENABLED=0 go build -o "$OUT/binpazerbench" . )
"${CC:-cc}" -O2 -I "$D/vendor/binpazer-c" -o "$OUT/binpazer-c" \
	"$P/trailer/binpazer_c.c" "$D/vendor/binpazer-c/binpazer.c"

"$OUT/appender" "$OUT/trailer" "$OUT/trailer-0"   3072     > /dev/null
"$OUT/appender" "$OUT/trailer" "$OUT/trailer-1m"  1048576  > /dev/null
"$OUT/appender" "$OUT/trailer" "$OUT/trailer-10m" 10485760 > /dev/null
chmod +x "$OUT"/trailer-*

{
	echo "## (a) does a trailer slow execve? (hyperfine, --shell=none, warmup $WARMUP, runs $RUNS)"
	echo
	echo "The target exits without reading its trailer, so this row is purely"
	echo "whether a bigger FILE costs more to start."
	echo
} >> "$OUT/trailer.md"
hyperfine --shell=none --warmup "$WARMUP" --runs "$RUNS" \
	--export-markdown "$OUT/trailer-exec.md" \
	--export-json     "$OUT/trailer-exec.json" \
	-n "Go, 3 KiB trailer"   "$OUT/trailer-0 quiet" \
	-n "Go, 1 MiB trailer"   "$OUT/trailer-1m quiet" \
	-n "Go, 10 MiB trailer"  "$OUT/trailer-10m quiet" \
	> "$OUT/trailer-exec.console.txt" 2>&1
cat "$OUT/trailer-exec.md" >> "$OUT/trailer.md"

{
	echo
	echo "## (b) reading the trailer, in process, median of $N"
	echo
	echo "| binary | os.Executable us/op | readTrailer us/op | payload |"
	echo "|---|---|---|---|"
} >> "$OUT/trailer.md"
for t in trailer-0 trailer-1m trailer-10m; do
	echo -n "| $t | " >> "$OUT/trailer.md"
	"$OUT/$t" read "$N" | sed -E 's/os.Executable: ([0-9.]+) us\/op *readTrailer: ([0-9.]+) us\/op *payload: (.*)/\1 | \2 | \3 |/' >> "$OUT/trailer.md"
done

echo >> "$OUT/trailer.md"
"$OUT/binpazerbench" -n "$N" -host "$OUT/trailer-0" -out "$OUT/cooked-host" >> "$OUT/trailer.md"
{
	echo
	echo "## the same binpazer read from C (allocation-free reader, injected read/seek)"
	echo
	echo "| operation | min us | p50 us | mean us | note |"
	echo "|---|---|---|---|---|"
} >> "$OUT/trailer.md"
"$OUT/binpazer-c" "$OUT/cooked-host" "$N" >> "$OUT/trailer.md"

cat "$OUT/trailer.md"
