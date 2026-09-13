#!/bin/sh
# Probe 01: gcc/clang dependency-file generation — placement, target, escaping.
# Every step records PASS/FAIL explicitly (see probe-lib.sh). No silent skips.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
cd src || exit 1
R=$(mktemp -d) || exit 1
trap 'rm -rf "$R"' EXIT
mkdir -p "$R/objs"


step "gcc --version"            gcc --version
step "clang --version"          clang --version

step "gcc -c -MD -MF objs/custom.d, -o objs/hello.o" \
	gcc -c -MD -MF "$R/objs/custom.d" hello.c -o "$R/objs/hello.o"
step "read the generated dep file" show "$R/objs/custom.d"

step "gcc -c -MD with -o /tmp/h1.o : where does the .d land?" \
	gcc -c -MD hello.c -o "$R/h1.o"
step "expect \$R/h1.d to exist (derived from -o, NOT from the source name)" \
	test -f "$R/h1.d"
step "confirm no hello.d was written in the cwd" \
	test ! -f hello.d

step "gcc -c -MD with NO -o : .d takes the source basename in the cwd" \
	sh -c 'cd "$1" && cp "$2/hello.c" "$2/local.h" "$2/nested.h" . && gcc -c -MD hello.c' _ "$R" "$PWD"
step "expect \$R/hello.d to exist" test -f "$R/hello.d"

step "gcc -c -MD -MP" gcc -c -MD -MP -MF "$R/objs/mp.d" hello.c -o "$R/objs/hello.o"
step "read it (note the phony target per prerequisite)" show "$R/objs/mp.d"

step "gcc -MD -MT 'a b.o' (target verbatim, ambiguous to make)" \
	gcc -c -MD -MT 'a b.o' -MF "$R/objs/mt.d" hello.c -o "$R/objs/hello.o"
step "read it" sh -c 'head -1 "$1"' _ "$R/objs/mt.d"

step "gcc -MD -MQ 'a b.o' (target quoted for make)" \
	gcc -c -MD -MQ 'a b.o' -MF "$R/objs/mq.d" hello.c -o "$R/objs/hello.o"
step "read it" sh -c 'head -1 "$1"' _ "$R/objs/mq.d"

step "gcc -M (stdout; implies -E, produces no object)" sh -c 'gcc -M hello.c | head -3'
step "gcc -MM (project headers only)" gcc -MM hello.c

step "gcc -Wp,-MD,<file> -c" gcc "-Wp,-MD,$R/objs/wp.d" -c hello.c -o "$R/objs/hello.o"
step "read it" sh -c 'head -1 "$1"' _ "$R/objs/wp.d"
step "gcc -Wp,-MMD,<file> -c" gcc "-Wp,-MMD,$R/objs/wpmm.d" -c hello.c -o "$R/objs/hello.o"
step "read it" show "$R/objs/wpmm.d"

step "gcc -E -MD -o /dev/null : does a .d appear?" \
	sh -c 'cd "$1" && rm -f hello.d && gcc -E -MD hello.c -o /dev/null; exit 0' _ "$R"
step "expect NO \$R/hello.d (finding: -E writes no dep file)" test ! -f "$R/hello.d"

# ---- escaping, with files literally named with special characters ----
W="$R/weird dir"
step "create the weird-name header set" sh -c '
	set -e
	mkdir -p "$1"
	n=0
	for f in "sp ace.h" "dol\$lar.h" "hash#mark.h" "back\\slash.h" "colon:c.h"; do
		n=$((n + 1))
		# Contents MUST be unique per file: gcc implements #pragma once by
		# comparing file CONTENT, so byte-identical headers are deduped and
		# vanish from the dep list (that hazard is probed separately below).
		printf "#pragma once\nint fn_%d(void);\n" "$n" > "$1/$f"
	done
	{
		echo "#include \"sp ace.h\""
		echo "#include \"dol\$lar.h\""
		echo "#include \"hash#mark.h\""
		echo "#include \"back\\slash.h\""
		echo "#include \"colon:c.h\""
		echo "int main(void){return 0;}"
	} > "$1/w.c"
' _ "$W"
step "gcc -MM over the weird names" sh -c 'cd "$1" && gcc -MM w.c' _ "$W"
step "clang -MM over the weird names (note \\ -> / and the \\# escape)" \
	sh -c 'cd "$1" && clang -MM w.c' _ "$W"
step "gcc -MM with a directory name containing a space" \
	sh -c 'cd "$1" && gcc -MM -I "weird dir" "weird dir/w.c"' _ "$R"

# ---- gcc's #pragma once CONTENT dedup: a real manifest-completeness hazard ----
step "two DISTINCT headers with byte-identical content, both #pragma once" sh -c '
	set -e
	mkdir -p "$1/once"
	printf "#pragma once\nint q(void);\n" > "$1/once/a.h"
	printf "#pragma once\nint q(void);\n" > "$1/once/b.h"
	printf "#include \"a.h\"\n#include \"b.h\"\nint main(void){return 0;}\n" > "$1/once/m.c"
' _ "$R"
step "gcc -MM : HAZARD — b.h is absent from the dep list" sh -c 'cd "$1/once" && gcc -MM m.c' _ "$R"
step "clang -MM : both are listed" sh -c 'cd "$1/once" && clang -MM m.c' _ "$R"
step "make b.h differ, then gcc -MM lists both" sh -c '
	set -e
	cd "$1/once"
	printf "#pragma once\nint q2(void);\n" > b.h
	gcc -MM m.c
' _ "$R"
step "include GUARDS with identical content are NOT deduped" sh -c '
	set -e
	cd "$1/once"
	printf "#ifndef G\n#define G\nint q(void);\n#endif\n" > c.h
	cp c.h d.h
	printf "#include \"c.h\"\n#include \"d.h\"\nint main(void){return 0;}\n" > n.c
	gcc -MM n.c
' _ "$R"

probe_summary
