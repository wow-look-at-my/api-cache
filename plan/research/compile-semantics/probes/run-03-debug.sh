#!/bin/sh
# Probe 03: what a compile embeds in the object, prefix maps, determinism.
# Every step records PASS/FAIL explicitly. No `|| true`.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
cd src || exit 1
R=$(mktemp -d) || exit 1
trap 'rm -rf "$R"' EXIT

step "readelf is present (the probe needs it; a missing tool is a FAIL, not a skip)" \
	sh -c 'command -v readelf'

dump() {
	say "--- DW_AT_name / DW_AT_comp_dir / DW_AT_producer of $1 ---"
	readelf --debug-dump=info "$1" | grep -E 'DW_AT_(name|comp_dir|producer)' | head -3
	say "--- end ---"
}

step "1. -g, cwd=src, relative source"        gcc -g -c hello.c -o "$R/a.o"
step "   inspect"                              dump "$R/a.o"
step "2. -g, cwd=parent, source 'src/hello.c'" sh -c 'cd .. && gcc -g -c src/hello.c -o "$1/b.o"' _ "$R"
step "   inspect"                              dump "$R/b.o"
xstep "   (1) and (2) must DIFFER: comp_dir and DW_AT_name both moved" nonzero \
	cmp -s "$R/a.o" "$R/b.o"
step "3. -g with an ABSOLUTE source path"      gcc -g -c "$PWD/hello.c" -o "$R/c.o"
step "   inspect"                              dump "$R/c.o"
step "4. -g -fdebug-prefix-map=\$PWD=/proj"    gcc -g -fdebug-prefix-map="$PWD=/proj" -c "$PWD/hello.c" -o "$R/d.o"
step "   inspect"                              dump "$R/d.o"
step "5. -g -ffile-prefix-map=\$PWD=/proj"     gcc -g -ffile-prefix-map="$PWD=/proj" -c "$PWD/hello.c" -o "$R/e.o"
step "   inspect"                              dump "$R/e.o"
step "6. clang -g -fdebug-compilation-dir=/proj" clang -g -fdebug-compilation-dir=/proj -c hello.c -o "$R/f.o"
step "   inspect"                              dump "$R/f.o"

step "7. determinism, -O2 (no -g): compile twice" \
	sh -c 'gcc -O2 -c hello.c -o "$1/g1.o" && gcc -O2 -c hello.c -o "$1/g2.o"' _ "$R"
step "   the two objects must be IDENTICAL"    cmp -s "$R/g1.o" "$R/g2.o"
step "8. determinism, -O2 -g: compile twice" \
	sh -c 'gcc -O2 -g -c hello.c -o "$1/h1.o" && gcc -O2 -g -c hello.c -o "$1/h2.o"' _ "$R"
step "   the two objects must be IDENTICAL"    cmp -s "$R/h1.o" "$R/h2.o"
step "9. the -o NAME must NOT leak into the object" \
	sh -c 'gcc -g -O2 -c hello.c -o "$1/name1.o" && gcc -g -O2 -c hello.c -o "$1/name2.o" && cmp -s "$1/name1.o" "$1/name2.o"' _ "$R"

step "10. LTO bitcode reproducibility: compile the same TU twice with -flto" sh -c '
	set -e
	printf "static int f(void){return 1;}\nint g(void){return f();}\n" > "$1/r.c"
	gcc -c -flto "$1/r.c" -o "$1/r1.o"
	gcc -c -flto "$1/r.c" -o "$1/r2.o"
	gcc -c -flto -frandom-seed=0 "$1/r.c" -o "$1/r3.o"
	gcc -c -flto -frandom-seed=0 "$1/r.c" -o "$1/r4.o"
' _ "$R"
xstep "    FINDING: -flto objects DIFFER run-to-run" nonzero cmp -s "$R/r1.o" "$R/r2.o"
xstep "    FINDING: -frandom-seed=0 does NOT make them identical on this gcc" nonzero cmp -s "$R/r3.o" "$R/r4.o"
step "    control: the SAME TU without -flto is reproducible" sh -c '
	set -e
	gcc -c "$1/r.c" -o "$1/r5.o"
	gcc -c "$1/r.c" -o "$1/r6.o"
	cmp -s "$1/r5.o" "$1/r6.o"
' _ "$R"

step "11. __FILE__ takes the path AS WRITTEN" sh -c '
	set -e
	printf "const char *p=__FILE__;\n" > "$1/fi.c"
	printf "absolute invocation: "; gcc -E "$1/fi.c" | tail -1
	cd "$1"
	printf "relative invocation: "; gcc -E fi.c | tail -1
	printf "relative + -ffile-prefix-map (no effect, path is already relative): "
	gcc -E -ffile-prefix-map="$1=/X" fi.c | tail -1
' _ "$R"

probe_summary
