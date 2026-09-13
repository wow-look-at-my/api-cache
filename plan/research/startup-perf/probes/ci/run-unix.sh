#!/usr/bin/env bash
# Measurement family 1: the process startup floor, on a unix runner.
#
# Everything is timed by hyperfine with --shell=none, so no shell is spawned
# between the timer and the target and the number is execve plus the program.
# Builds that fail are reported and their target is dropped from the run rather
# than aborting the job, because one missing static libstdc++ must not hide the
# other twelve numbers.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
RUNS="${BENCH_RUNS:-300}"
WARMUP="${BENCH_WARMUP:-20}"
UNAME="$(uname -s)"
CC="${CC:-cc}"; CXX="${CXX:-c++}"

{
	echo "# startup floor: $(uname -s) $(uname -m)"
	echo
	echo "- runner label: \`${RUNNER_LABEL:-unknown}\`  (GitHub Actions hosted runner)"
	echo "- run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
	echo "- cpu cores: $( (nproc 2>/dev/null) || sysctl -n hw.ncpu )"
	echo "- cc: $($CC --version 2>&1 | head -1)"
	echo "- c++: $($CXX --version 2>&1 | head -1)"
	echo "- go: $(go version 2>&1)"
	echo "- rustc: $(rustc --version 2>&1 || echo 'not installed')"
	echo "- hyperfine: $(hyperfine --version 2>&1)"
	echo "- method: \`hyperfine --shell=none --warmup $WARMUP --runs $RUNS\`"
	echo
} > "$OUT/meta.md"

# ---- builds
$CC  -O2 -o "$OUT/c-dyn"   "$D/src/hello.c"   2>"$OUT/build-c-dyn.log"
$CXX -O2 -o "$OUT/cpp-dyn" "$D/src/hello.cpp" 2>"$OUT/build-cpp-dyn.log"
if [ "$UNAME" != "Darwin" ]; then
	# macOS does not support statically linking libSystem: Apple ships no
	# crt1.o for it and the ABI is the dylib. The row is reported as n/a
	# rather than faked with something that is not a static link.
	$CC  -O2 -static -o "$OUT/c-static"   "$D/src/hello.c"   2>"$OUT/build-c-static.log"
	$CXX -O2 -static -o "$OUT/cpp-static" "$D/src/hello.cpp" 2>"$OUT/build-cpp-static.log"
	$CXX -O2 -static-libstdc++ -static-libgcc -o "$OUT/cpp-staticcxx" "$D/src/hello.cpp" 2>"$OUT/build-cpp-staticcxx.log"
fi
( cd "$D/src/gohello"   && CGO_ENABLED=0 go build -o "$OUT/go-hello-nocgo" . ) 2>"$OUT/build-go-nocgo.log"
( cd "$D/src/gohello"   && CGO_ENABLED=1 go build -o "$OUT/go-hello-cgo"   . ) 2>"$OUT/build-go-cgo.log"
( cd "$D/src/gohello"   && CGO_ENABLED=0 go build -ldflags="-s -w" -o "$OUT/go-hello-sw" . ) 2>"$OUT/build-go-sw.log"
( cd "$D/src/goimports" && CGO_ENABLED=0 go build -o "$OUT/go-imports" . ) 2>"$OUT/build-go-imports.log"
rustc -O -o "$OUT/rust-hello" "$D/src/hello.rs" 2>"$OUT/build-rust.log"

# args builds one -n/command pair per target that actually exists.
args=()
add() { # add <label> <path>
	if [ -x "$2" ]; then args+=( -n "$1" "$2" ); else echo "MISSING: $1 ($2)" >> "$OUT/missing.txt"; fi
}
add "C hello, dynamic"                     "$OUT/c-dyn"
add "C hello, static"                      "$OUT/c-static"
add "C++ iostream, dynamic"                "$OUT/cpp-dyn"
add "C++ iostream, static"                 "$OUT/cpp-static"
add "C++ iostream, -static-libstdc++"      "$OUT/cpp-staticcxx"
add "Go hello, CGO_ENABLED=0"              "$OUT/go-hello-nocgo"
add "Go hello, CGO_ENABLED=1"              "$OUT/go-hello-cgo"
add "Go hello, -ldflags=-s -w"             "$OUT/go-hello-sw"
add "Go + net/http + encoding/xml + text/template" "$OUT/go-imports"
add "Rust hello"                           "$OUT/rust-hello"

hyperfine --shell=none --warmup "$WARMUP" --runs "$RUNS" \
	--export-markdown "$OUT/startup.md" \
	--export-json     "$OUT/startup.json" \
	"${args[@]}" > "$OUT/startup.console.txt" 2>&1
rc=$?

# Binary sizes belong with the timings: a 24 MB binary and a 16 KB one are not
# the same proposition even when they start in the same time.
{
	echo
	echo "## binary sizes"
	echo
	echo "| binary | bytes |"
	echo "|---|---|"
	for f in c-dyn c-static cpp-dyn cpp-static cpp-staticcxx go-hello-nocgo go-hello-cgo go-hello-sw go-imports rust-hello; do
		[ -f "$OUT/$f" ] && echo "| $f | $(wc -c < "$OUT/$f" | tr -d ' ') |"
	done
	if [ "$UNAME" = "Darwin" ]; then
		echo
		echo "> macOS carries no static rows. Apple does not support statically"
		echo "> linking libSystem, and clang on macOS links libc++ dynamically,"
		echo "> so there is no honest static counterpart to measure."
	fi
	if [ -f "$OUT/missing.txt" ]; then
		echo
		echo "## targets that failed to build"
		echo
		echo '```'
		cat "$OUT/missing.txt"
		echo '```'
	fi
} > "$OUT/extra.md"

cat "$OUT/meta.md" "$OUT/startup.md" "$OUT/extra.md" > "$OUT/report.md"
cat "$OUT/report.md"
exit $rc
