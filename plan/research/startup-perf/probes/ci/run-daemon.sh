#!/usr/bin/env bash
# Measurement family 4: the daemon option.
#
# The architecture in question is sccache's: a long-lived server holds the
# cache state, and each compiler invocation execs a thin client that asks it a
# question over a unix socket. Two costs decide whether that is worth it.
#
#   (a) The WHOLE-PROCESS cost of the client: exec it, connect, round trip,
#       exit. hyperfine measures that, against the same binaries doing nothing,
#       so the round trip is the difference between the two rows.
#   (b) The in-process round trip alone, cold-connect and reused-connection,
#       which is the floor any protocol on top of this pays.
#
# The C client bounds the "thin native client, Go daemon" split: both clients
# make the same syscalls, so the gap between them is the Go runtime's startup.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/.." && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
RUNS="${BENCH_RUNS:-300}"
WARMUP="${BENCH_WARMUP:-20}"
N="${BENCH_N:-2000}"
SOCK="${TMPDIR:-/tmp}/apcache-bench.sock"

{
	echo "# daemon round trip: $(uname -s) $(uname -m)"
	echo
	echo "> Measured on a GitHub Actions hosted runner. Not a development machine."
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`  (GitHub Actions hosted runner)"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- go: $(go version)"
	echo "- hyperfine: $(hyperfine --version)"
	echo "- commit: \`${GITHUB_SHA:-?}\`"
	echo "- protocol: 4-byte length prefix, 512-byte request, 65-byte reply. No framing library."
	echo
} > "$OUT/daemon.md"

( cd "$P/ipc/server"   && CGO_ENABLED=0 go build -o "$OUT/ipc-server"   . )
( cd "$P/ipc/goclient" && CGO_ENABLED=0 go build -o "$OUT/ipc-goclient" . )
( cd "$P/go-hello"     && CGO_ENABLED=0 go build -o "$OUT/go-hello"     . )
"${CC:-cc}" -O2 -o "$OUT/ipc-cclient" "$P/ipc/cclient.c"
"${CC:-cc}" -O2 -o "$OUT/c-hello"     "$D/src/hello.c"
# A static C client is the smallest the shim gets. This job runs on Linux
# only, where a static link works, so a failure here is a real regression and
# aborts the script rather than dropping a row.
"${CC:-cc}" -O2 -static -o "$OUT/ipc-cclient-static" "$P/ipc/cclient.c"

rm -f "$SOCK"
"$OUT/ipc-server" "$SOCK" &
SRV=$!
trap 'kill $SRV 2>/dev/null || true; rm -f "$SOCK"' EXIT
for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
[ -S "$SOCK" ] || { echo "server never bound $SOCK" >&2; exit 1; }

{
	echo "## (a) whole process: exec the client, connect, round trip, exit"
	echo
	echo "hyperfine, \`--shell=none --warmup $WARMUP --runs $RUNS\`. The two"
	echo "\"no daemon contact\" rows are the same languages doing nothing, so the"
	echo "round trip is the difference."
	echo
} >> "$OUT/daemon.md"

for b in ipc-cclient ipc-cclient-static ipc-goclient c-hello go-hello; do
	[ -x "$OUT/$b" ] || { echo "FATAL: $b was not built" >&2; exit 1; }
done
args=(
	-n "C client, dynamic"        "$OUT/ipc-cclient 1 $SOCK"
	-n "C client, static"         "$OUT/ipc-cclient-static 1 $SOCK"
	-n "Go client"                "$OUT/ipc-goclient 1 $SOCK"
	-n "C hello, no daemon contact"  "$OUT/c-hello"
	-n "Go hello, no daemon contact" "$OUT/go-hello"
)

hyperfine --shell=none --warmup "$WARMUP" --runs "$RUNS" \
	--export-markdown "$OUT/daemon-exec.md" \
	--export-json     "$OUT/daemon-exec.json" \
	"${args[@]}" 2>&1 | tee "$OUT/daemon-exec.console.txt"
[ -s "$OUT/daemon-exec.md" ] || { echo "FATAL: hyperfine wrote no markdown table" >&2; exit 1; }
cat "$OUT/daemon-exec.md" >> "$OUT/daemon.md"

{
	echo
	echo "## (b) the round trip alone, in process, mean of $N"
	echo
	echo '```'
} >> "$OUT/daemon.md"
"$OUT/ipc-goclient" "$N" "$SOCK" >> "$OUT/daemon.md"
"$OUT/ipc-cclient"  "$N" "$SOCK" >> "$OUT/daemon.md"
echo '```' >> "$OUT/daemon.md"

cat "$OUT/daemon.md"
