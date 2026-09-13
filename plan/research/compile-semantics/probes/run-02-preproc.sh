#!/bin/sh
# Probe 02: preprocessor output shape, line markers, -P, path leakage, __DATE__ family.
# Every step records PASS/FAIL explicitly. No `|| true`.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
cd src || exit 1

step "gcc -E : the linemarker preamble (source path is embedded AS WRITTEN)" \
	sh -c 'gcc -E hello.c | head -12'
step "gcc -E -P : no linemarkers at all" \
	sh -c 'gcc -E -P hello.c | head -6'
step "clang -E : a DIFFERENT preamble shape from gcc's" \
	sh -c 'clang -E hello.c | head -12'
step "__DATE__ / __TIME__ / __FILE__ / __TIMESTAMP__ expansion" \
	sh -c 'gcc -E -P timey.c | tail -2'
step "stability: the same -E run twice must hash identically" \
	sh -c 'a=$(gcc -E hello.c | md5sum); b=$(gcc -E hello.c | md5sum);
	       printf "%s\n%s\n" "$a" "$b"; [ "$a" = "$b" ]'
step "path leakage: invoked from the PARENT dir as src/hello.c" \
	sh -c 'cd .. && gcc -E -Isrc src/hello.c | head -6'
step "path leakage: invoked with an ABSOLUTE source path" \
	sh -c 'gcc -E "$PWD/hello.c" | head -6'
step "-P still keeps the PCH marker (it is content, not a linemarker)" sh -c '
	set -e
	T=$(mktemp -d); trap "rm -rf $T" EXIT
	cp local.h nested.h "$T/"
	printf "#include \"local.h\"\nint main(void){return 0;}\n" > "$T/u.c"
	( cd "$T" && gcc -x c-header local.h -o local.h.gch 2>/dev/null
	  printf "with -E:   "; gcc -E -fpch-preprocess u.c | grep pch_preprocess
	  printf "with -E -P: "; gcc -E -P -fpch-preprocess u.c | grep pch_preprocess )'
step "gcc -E -fdirectives-only : macros kept as #define" \
	sh -c 'gcc -E -fdirectives-only hello.c | head -6'

probe_summary
