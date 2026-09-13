#!/bin/sh
# Probe: flag-specific behaviour a wrapper must classify.
cd "$(dirname "$0")/src"
R=$(mktemp -d); trap 'rm -rf $R' EXIT
echo "===== -march=native expansion via -### -E - (ccache's technique) ====="
gcc -### -E - -march=native 2>&1 | grep -o '/cc1 -E.*' | head -c 900; echo
echo "-- clang --"
clang -### -E - -march=native 2>&1 | grep -o '"-cc1".*' | head -c 600; echo
echo
echo "===== diagnostics colour: piped vs. forced ====="
printf 'int main(void){int x; return y;}\n' > $R/bad.c
echo "-- default (stderr is a pipe) --"; gcc -c $R/bad.c -o $R/bad.o 2>&1 | cat -v | head -4
echo "-- -fdiagnostics-color=always --"; gcc -fdiagnostics-color=always -c $R/bad.c -o $R/bad.o 2>&1 | cat -v | head -4
echo
echo "===== -gsplit-dwarf outputs ====="
( cd $R && gcc -g -gsplit-dwarf -c "$OLDPWD/hello.c" -o sd.o && ls -1 )
echo "===== --coverage outputs ====="
( cd $R && rm -f *.gcno && gcc --coverage -c "$OLDPWD/hello.c" -o cov.o && ls -1 *.gcno cov.o )
echo "===== -fsyntax-only: does it write -o? ====="
( cd $R && rm -f syn.o; gcc -fsyntax-only -c "$OLDPWD/hello.c" -o syn.o; echo "exit=$?"; ls syn.o 2>&1 )
echo "===== -o - (stdout) ====="
gcc -c hello.c -o - 2>&1 | head -c 80 | od -c | head -2
echo "===== -E -o - and -S ====="
gcc -S hello.c -o $R/hello.s && head -3 $R/hello.s
echo "===== response file (@file), nested ====="
printf -- '-c\n-O2\n' > $R/r1.rsp
printf -- '@%s\n-o %s\n' "$R/r1.rsp" "$R/rsp.o" > $R/r2.rsp
gcc "@$R/r2.rsp" hello.c && ls -1 $R/rsp.o && echo "nested response file OK"
echo "-- response file quoting rules --"
printf -- "-DSTR=\"a b\"\n-c\n-o %s\n" "$R/q.o" > $R/q.rsp
gcc "@$R/q.rsp" hello.c && echo "quoted rsp OK"
echo "===== PCH (.gch) ====="
( cd $R && cp "$OLDPWD/local.h" . && cp "$OLDPWD/nested.h" . && gcc -x c-header local.h -o local.h.gch && ls -1 local.h.gch && printf '#include "local.h"\nint main(void){return 0;}\n' > u.c && gcc -H -c u.c -o u.o 2>&1 | head -3 )
echo "===== -fpch-preprocess marker in -E output ====="
( cd $R && gcc -E -fpch-preprocess u.c 2>/dev/null | grep -n 'pch_preprocess' | head -3 )
echo "===== stdin source: -x c - ====="
echo 'int main(void){return 0;}' | gcc -x c -c - -o $R/stdin.o && echo "stdin compile OK -> object $(ls -l $R/stdin.o | awk '{print $5}') bytes"
echo "===== -MD with -x c - (stdin) : dep target name ====="
echo 'int main(void){return 0;}' | gcc -x c -c - -MD -MF $R/stdin.d -o $R/stdin.o && cat $R/stdin.d
