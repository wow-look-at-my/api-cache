#!/bin/sh
# Probe 04: flag-specific behaviour a wrapper must classify.
# Every step records PASS/FAIL explicitly. A step whose NON-ZERO exit IS the
# finding uses xstep with a stated expectation. No `|| true`.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
cd src || exit 1
R=$(mktemp -d) || exit 1
trap 'rm -rf "$R"' EXIT

step "gcc: -march=native expansion via '-### -E -' (ccache's technique)" \
	sh -c 'gcc -### -E - -march=native 2>&1 | grep -o "/cc1 -E.*" | cut -c1-700'
step "clang: the same, via the \"-cc1\" line" \
	sh -c 'clang -### -E - -march=native 2>&1 | grep -o "\"-cc1\".*" | cut -c1-500'

step "prepare a source with an error, for the diagnostics probes" \
	sh -c 'printf "int main(void){int x; return y;}\n" > "$1/bad.c"' _ "$R"
xstep "diagnostics with stderr a PIPE: plain text, no escapes" nonzero \
	sh -c 'gcc -c "$1/bad.c" -o "$1/bad.o" > "$1/o.txt" 2>&1; rc=$?; cat -v "$1/o.txt" | head -3; exit $rc' _ "$R"
xstep "diagnostics with -fdiagnostics-color=always: ANSI escapes present" nonzero \
	sh -c 'gcc -fdiagnostics-color=always -c "$1/bad.c" -o "$1/bad.o" > "$1/o.txt" 2>&1; rc=$?; cat -v "$1/o.txt" | head -3; exit $rc' _ "$R"
say "NOTE: the wrapper always captures through a pipe, so the compiler never colours"
say "      on its own. ccache forces colour ON for the child and strips on replay."

step "-gsplit-dwarf produces a .dwo sibling" \
	sh -c 'cd "$1" && gcc -g -gsplit-dwarf -c "$2/hello.c" -o sd.o && ls -1 sd.o sd.dwo' _ "$R" "$PWD"
step "--coverage produces a .gcno sibling" \
	sh -c 'cd "$1" && gcc --coverage -c "$2/hello.c" -o cov.o && ls -1 cov.o cov.gcno' _ "$R" "$PWD"
step "-fsyntax-only exits 0 and writes NOTHING, even with -c -o" \
	sh -c 'cd "$1" && rm -f syn.o && gcc -fsyntax-only -c "$2/hello.c" -o syn.o && test ! -f syn.o' _ "$R" "$PWD"

xstep "gcc -c -o - : FAILS outright on this platform (the assembler cannot write to stdout)" nonzero \
	sh -c 'gcc -c hello.c -o - > "$1/o.txt" 2>&1; rc=$?; head -2 "$1/o.txt"; exit $rc' _ "$R"
step "-S writes assembly and is a normal, cacheable compile" \
	sh -c 'gcc -S hello.c -o "$1/hello.s" && head -2 "$1/hello.s"' _ "$R"

step "response file: NESTED @file is expanded by gcc" sh -c '
	set -e
	printf -- "-c\n-O2\n" > "$1/r1.rsp"
	printf "@%s\n-o %s\n" "$1/r1.rsp" "$1/rsp.o" > "$1/r2.rsp"
	gcc "@$1/r2.rsp" hello.c
	test -f "$1/rsp.o"
' _ "$R"
step "response file: shell-like quoting inside" sh -c '
	set -e
	printf -- "-DSTR=\"a b\"\n-c\n-o %s\n" "$1/q.o" > "$1/q.rsp"
	gcc "@$1/q.rsp" hello.c
	test -f "$1/q.o"
' _ "$R"

step "PCH: build a .gch and confirm gcc uses it (-H shows '! local.h.gch')" sh -c '
	set -e
	cp local.h nested.h "$1/"
	printf "#include \"local.h\"\nint main(void){return 0;}\n" > "$1/u.c"
	cd "$1"
	gcc -x c-header local.h -o local.h.gch 2>/dev/null
	gcc -H -c u.c -o u.o 2>&1 | head -2
' _ "$R"

step "stdin source: gcc -x c -c - works, but has no source identity to key on" \
	sh -c 'echo "int main(void){return 0;}" | gcc -x c -c - -o "$1/stdin.o" && test -s "$1/stdin.o"' _ "$R"
step "stdin source + -MD: the dep file does NOT name the source" \
	sh -c 'echo "int main(void){return 0;}" | gcc -x c -c - -MD -MF "$1/stdin.d" -o "$1/stdin.o" && cat "$1/stdin.d"' _ "$R"

probe_summary
