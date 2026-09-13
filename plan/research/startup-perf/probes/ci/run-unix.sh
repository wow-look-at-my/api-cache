#!/usr/bin/env bash
# Measurement family 1: the process startup floor, on a unix runner.
#
# hyperfine with --shell=none, so no shell sits between the timer and the
# target and the number is execve plus the program.
#
# NOTHING here is allowed to fail quietly. Every build must succeed and every
# target must exist before hyperfine runs. A compiler that is missing, a
# static link that the runner cannot do, or a hyperfine that is not on PATH
# fails the job with the real error. A green job with a short table is worse
# than a red one, because the short table gets copied into a results file and
# read as if it were complete.
#
# macOS is the one documented exception, and it is a platform FACT rather than
# a failure: Apple does not support statically linking libSystem, and clang on
# macOS links libc++ dynamically. So the static targets are not attempted
# there, they are declared unsupported by name, and the report says so.
set -euo pipefail

D="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
RUNS="${BENCH_RUNS:-300}"
WARMUP="${BENCH_WARMUP:-20}"
UNAME="$(uname -s)"
CC="${CC:-cc}"; CXX="${CXX:-c++}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL: $1 is not on PATH" >&2; exit 1; }; }
need hyperfine
need go
need rustc
need "$CC"
need "$CXX"

{
	echo "# startup floor: $(uname -s) $(uname -m)"
	echo
	echo "> Measured on a GitHub Actions hosted runner. Not a development machine."
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- commit: \`${GITHUB_SHA:-?}\`"
	echo "- cpu cores: $( (nproc 2>/dev/null) || sysctl -n hw.ncpu )"
	echo "- cc: $($CC --version 2>&1 | head -1)"
	echo "- c++: $($CXX --version 2>&1 | head -1)"
	echo "- go: $(go version)"
	echo "- rustc: $(rustc --version)"
	echo "- hyperfine: $(hyperfine --version)"
	echo "- method: \`hyperfine --shell=none --warmup $WARMUP --runs $RUNS\`"
	echo
} > "$OUT/meta.md"

# targets is the list this platform must produce. Every entry is built, and a
# build failure aborts the script with the compiler's own message.
targets=()
build() { # build <label> <name> <command...>
	local label="$1" name="$2"; shift 2
	if ! "$@"; then
		echo "FATAL: building '$label' failed. Command: $*" >&2
		exit 1
	fi
	[ -x "$OUT/$name" ] || { echo "FATAL: '$label' built but $OUT/$name is missing" >&2; exit 1; }
	targets+=( -n "$label" "$OUT/$name" )
}

build "C hello, dynamic"   c-dyn   $CC  -O2 -o "$OUT/c-dyn"   "$D/src/hello.c"
build "C++ iostream, dynamic" cpp-dyn $CXX -O2 -o "$OUT/cpp-dyn" "$D/src/hello.cpp"

if [ "$UNAME" = "Darwin" ]; then
	STATIC_NOTE=1
else
	STATIC_NOTE=0
	build "C hello, static"   c-static   $CC  -O2 -static -o "$OUT/c-static"   "$D/src/hello.c"
	build "C++ iostream, static" cpp-static $CXX -O2 -static -o "$OUT/cpp-static" "$D/src/hello.cpp"
	build "C++ iostream, -static-libstdc++" cpp-staticcxx \
		$CXX -O2 -static-libstdc++ -static-libgcc -o "$OUT/cpp-staticcxx" "$D/src/hello.cpp"
fi

gobuild() { # gobuild <label> <name> <srcdir> <cgo> [extra ldflags]
	local label="$1" name="$2" dir="$3" cgo="$4"; shift 4
	( cd "$dir" && CGO_ENABLED="$cgo" go build "$@" -o "$OUT/$name" . ) || {
		echo "FATAL: go build for '$label' failed in $dir" >&2; exit 1; }
	[ -x "$OUT/$name" ] || { echo "FATAL: '$label' built but $OUT/$name is missing" >&2; exit 1; }
	targets+=( -n "$label" "$OUT/$name" )
}
gobuild "Go hello, CGO_ENABLED=0"  go-hello-nocgo "$D/src/gohello"   0
gobuild "Go hello, CGO_ENABLED=1"  go-hello-cgo   "$D/src/gohello"   1
gobuild "Go hello, -ldflags=-s -w" go-hello-sw    "$D/src/gohello"   0 -ldflags=-s\ -w
gobuild "Go + net/http + encoding/xml + text/template" go-imports "$D/src/goimports" 0

build "Rust hello" rust-hello rustc -O -o "$OUT/rust-hello" "$D/src/hello.rs"

hyperfine --shell=none --warmup "$WARMUP" --runs "$RUNS" \
	--export-markdown "$OUT/startup.md" \
	--export-json     "$OUT/startup.json" \
	"${targets[@]}" 2>&1 | tee "$OUT/startup.console.txt"

# A non-empty table is not enough: hyperfine can emit a header and no rows
# when every benchmark failed to launch. Count the rows against the targets.
[ -s "$OUT/startup.md" ] || { echo "FATAL: hyperfine wrote an empty markdown table; see startup.console.txt" >&2; exit 1; }
want=$(( ${#targets[@]} / 2 ))
got=$(grep -c '^|' "$OUT/startup.md" || true)
[ "$got" -ge $(( want + 2 )) ] || {
	echo "FATAL: hyperfine table has $got lines for $want targets; a benchmark failed. See startup.console.txt" >&2
	exit 1
}

{
	echo
	echo "## binary sizes"
	echo
	echo "| binary | bytes |"
	echo "|---|---|"
	for f in c-dyn c-static cpp-dyn cpp-static cpp-staticcxx go-hello-nocgo go-hello-cgo go-hello-sw go-imports rust-hello; do
		[ -f "$OUT/$f" ] && echo "| $f | $(wc -c < "$OUT/$f" | tr -d ' ') |"
	done
	if [ "$STATIC_NOTE" = 1 ]; then
		echo
		echo "> **No static rows on macOS, by platform rule rather than by failure.**"
		echo "> Apple does not support statically linking libSystem (no crt1.o is"
		echo "> shipped for it and the ABI is the dylib), and clang on macOS links"
		echo "> libc++ dynamically. The static targets are therefore not attempted"
		echo "> here. Every target this platform DOES support was built and timed;"
		echo "> a failure in any of them fails the job."
	fi
} > "$OUT/extra.md"

cat "$OUT/meta.md" "$OUT/startup.md" "$OUT/extra.md" > "$OUT/report.md"
cat "$OUT/report.md"
