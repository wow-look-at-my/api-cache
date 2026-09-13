#!/usr/bin/env bash
# Build and time every startup probe on a unix runner (Linux or macOS).
# Emits a markdown table on stdout. Every build failure is reported as a row
# rather than aborting the job, because a missing static libstdc++ on one
# runner must not hide the other twelve numbers.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$D/out}"
mkdir -p "$OUT"
N="${BENCH_N:-300}"
UNAME="$(uname -s)"

echo "## $(uname -s) $(uname -m)"
echo
echo "- runner: \`${RUNNER_OS:-local} ${RUNNER_ARCH:-}\`"
echo "- cpu cores: $( (nproc 2>/dev/null) || sysctl -n hw.ncpu )"
echo "- cc: $(${CC:-cc} --version 2>&1 | head -1)"
echo "- go: $(go version 2>&1)"
echo "- rustc: $(rustc --version 2>&1 || echo 'not installed')"
echo

# The harness itself.
( cd "$D" && go build -o "$OUT/bench" ./bench.go ) || { echo "bench harness build FAILED"; exit 1; }
BENCH="$OUT/bench"

ok() { [ -x "$1" ]; }
row() { # row <label> <binary>
	if ok "$2"; then "$BENCH" -n "$N" -label "$1" -- "$2"
	else echo "| $1 | build failed | | | | |"; fi
}

CC="${CC:-cc}"; CXX="${CXX:-c++}"

# --- C
$CC -O2 -o "$OUT/c-dyn" "$D/src/hello.c" 2>/dev/null
if [ "$UNAME" = "Darwin" ]; then
	# macOS ships no crt1.o for a fully static link and Apple does not support
	# statically linking libSystem. The closest available thing is the default
	# dynamic link, so the static row is reported as unsupported on purpose.
	: > /dev/null
else
	$CC -O2 -static -o "$OUT/c-static" "$D/src/hello.c" 2>/dev/null
fi

# --- C++ with iostream
$CXX -O2 -o "$OUT/cpp-dyn" "$D/src/hello.cpp" 2>/dev/null
if [ "$UNAME" = "Darwin" ]; then
	:
else
	$CXX -O2 -static -o "$OUT/cpp-static" "$D/src/hello.cpp" 2>/dev/null
	$CXX -O2 -static-libstdc++ -static-libgcc -o "$OUT/cpp-staticcxx" "$D/src/hello.cpp" 2>/dev/null
fi

# --- Go
( cd "$D/src/gohello"   && CGO_ENABLED=0 go build -o "$OUT/go-hello-nocgo" . ) 2>/dev/null
( cd "$D/src/gohello"   && CGO_ENABLED=1 go build -o "$OUT/go-hello-cgo"   . ) 2>/dev/null
( cd "$D/src/goimports" && CGO_ENABLED=0 go build -o "$OUT/go-imports"     . ) 2>/dev/null

# --- Rust
rustc -O -o "$OUT/rust-hello" "$D/src/hello.rs" 2>/dev/null

echo "| binary | min us | p50 us | p90 us | mean us | size bytes |"
echo "|---|---|---|---|---|---|"
row "C hello, dynamic"                 "$OUT/c-dyn"
if [ "$UNAME" = "Darwin" ]; then
	echo "| C hello, static | n/a: macOS does not support statically linking libSystem | | | | |"
else
	row "C hello, static"              "$OUT/c-static"
fi
row "C++ iostream, dynamic"            "$OUT/cpp-dyn"
if [ "$UNAME" = "Darwin" ]; then
	echo "| C++ iostream, static | n/a: macOS does not support a fully static link | | | | |"
	echo "| C++ iostream, -static-libstdc++ | n/a: clang on macOS links libc++ dynamically | | | | |"
else
	row "C++ iostream, static"         "$OUT/cpp-static"
	row "C++ iostream, -static-libstdc++" "$OUT/cpp-staticcxx"
fi
row "Go hello, CGO_ENABLED=0"          "$OUT/go-hello-nocgo"
row "Go hello, CGO_ENABLED=1"          "$OUT/go-hello-cgo"
row "Go +net/http+encoding/xml+text/template" "$OUT/go-imports"
row "Rust hello"                       "$OUT/rust-hello"
echo
