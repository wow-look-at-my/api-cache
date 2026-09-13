#!/usr/bin/env bash
# Measurement family 6: WHY the startup floors differ.
#
# This one counts syscalls rather than microseconds, with strace -c -f. A count
# is not a timing, so it does not belong to hyperfine and it is not sensitive to
# a noisy neighbour: the same program makes the same syscalls every time. It is
# here because the startup-floor table says Go costs about 2.3x a static C
# binary and does not say what Go is doing with the difference.
#
# -f follows the threads the Go runtime clones, which is most of the answer.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/.." && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL: $1 is not on PATH" >&2; exit 1; }; }
need strace
need go
need cc

{
	echo "# startup syscall counts: $(uname -s) $(uname -m)"
	echo
	echo "> Measured on a GitHub Actions hosted runner. Not a development machine."
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`"
	echo "- commit: \`${GITHUB_SHA:-?}\`"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- go: $(go version)"
	echo "- strace: $(strace -V 2>&1 | head -1)"
	echo "- method: \`strace -c -f <prog>\`, which follows cloned threads"
	echo
} > "$OUT/syscalls.md"

cc -O2 -static -o "$OUT/c-static" "$D/src/hello.c"
cc -O2         -o "$OUT/c-dyn"    "$D/src/hello.c"
( cd "$D/src/gohello"   && CGO_ENABLED=0 go build -o "$OUT/go-hello"   . )
( cd "$D/src/goimports" && CGO_ENABLED=0 go build -o "$OUT/go-imports" . )

# total <binary> prints the total syscall count from strace's summary line.
total() {
	strace -c -f "$1" 2>"$OUT/$(basename "$1").strace" >/dev/null
	# The summary's last line is "100.00 ... <total> ... total". Take the
	# calls column, which is the 4th field.
	awk '/ total$/ { print $4 }' "$OUT/$(basename "$1").strace" | tail -1
}
count_of() { # count_of <straceFile> <syscall>
	awk -v s="$2" '$NF == s { print $4 }' "$1" | tail -1
}

{
	echo "| binary | total syscalls | clone | rt_sigaction | mmap | openat |"
	echo "|---|---|---|---|---|---|"
	for b in c-static c-dyn go-hello go-imports; do
		t="$(total "$OUT/$b")"
		f="$OUT/$b.strace"
		printf '| %s | %s | %s | %s | %s | %s |\n' \
			"$b" "${t:-?}" \
			"$(count_of "$f" clone)"        \
			"$(count_of "$f" rt_sigaction)" \
			"$(count_of "$f" mmap)"         \
			"$(count_of "$f" openat)"
	done
	echo
	echo "An empty cell means the program makes that syscall zero times."
	echo
	echo "## full strace summaries"
	echo
	for b in c-static c-dyn go-hello go-imports; do
		echo "### $b"
		echo
		echo '```'
		cat "$OUT/$b.strace"
		echo '```'
		echo
	done
} >> "$OUT/syscalls.md"

# A count that came back empty means the parse broke, not that the program is
# free. Fail rather than publish a table of question marks.
grep -q '| c-static | [0-9]' "$OUT/syscalls.md" || {
	echo "FATAL: could not parse a syscall total out of strace's summary" >&2
	exit 1
}
cat "$OUT/syscalls.md"
