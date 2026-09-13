#!/bin/sh
# Probe: what a compile embeds in the object file, and how prefix maps change it.
cd "$(dirname "$0")/src"
R=$(mktemp -d); trap 'rm -rf $R' EXIT
dump(){ printf '  DW_AT_name/comp_dir/producer for %s:\n' "$1"; readelf --debug-dump=info "$1" 2>/dev/null | grep -E 'DW_AT_(name|comp_dir|producer)' | head -6; }
echo "===== 1. -g, compiled from cwd=src with relative source ====="
gcc -g -c hello.c -o $R/a.o && dump $R/a.o
echo "===== 2. -g, compiled from parent cwd with relative path src/hello.c ====="
( cd .. && gcc -g -c src/hello.c -o $R/b.o ) && dump $R/b.o
echo "  byte-identical to (1)? "; cmp -s $R/a.o $R/b.o && echo "  YES" || echo "  NO"
echo "===== 3. -g with absolute source path ====="
gcc -g -c "$PWD/hello.c" -o $R/c.o && dump $R/c.o
echo "===== 4. -g -fdebug-prefix-map=\$PWD=/proj ====="
gcc -g -fdebug-prefix-map="$PWD=/proj" -c "$PWD/hello.c" -o $R/d.o && dump $R/d.o
echo "===== 5. -g -ffile-prefix-map=\$PWD=/proj (also rewrites __FILE__) ====="
gcc -g -ffile-prefix-map="$PWD=/proj" -c "$PWD/hello.c" -o $R/e.o && dump $R/e.o
echo "===== 6. clang -g -fdebug-compilation-dir=/proj ====="
clang -g -fdebug-compilation-dir=/proj -c hello.c -o $R/f.o && dump $R/f.o
echo "===== 7. determinism: same argv twice, byte compare (no -g) ====="
gcc -O2 -c hello.c -o $R/g1.o; gcc -O2 -c hello.c -o $R/g2.o
cmp -s $R/g1.o $R/g2.o && echo "  identical" || echo "  DIFFER"
echo "===== 8. determinism with -g ====="
gcc -O2 -g -c hello.c -o $R/h1.o; gcc -O2 -g -c hello.c -o $R/h2.o
cmp -s $R/h1.o $R/h2.o && echo "  identical" || echo "  DIFFER"
echo "===== 9. does the -o NAME leak into the .o? (same input, two -o names) ====="
gcc -g -O2 -c hello.c -o $R/name1.o; gcc -g -O2 -c hello.c -o $R/name2.o
cmp -s $R/name1.o $R/name2.o && echo "  identical -> -o name not embedded" || { echo "  DIFFER -> -o leaks"; cmp -l $R/name1.o $R/name2.o | head -3; }
echo "===== 10. -frandom-seed effect (C++ with anon namespace / static) ====="
printf 'static int f(void){return 1;}\nint g(void){return f();}\n' > $R/r.c
gcc -c -flto $R/r.c -o $R/r1.o; gcc -c -flto $R/r.c -o $R/r2.o; cmp -s $R/r1.o $R/r2.o && echo "  -flto .o identical" || echo "  -flto .o DIFFER (random seed)"
gcc -c -flto -frandom-seed=0 $R/r.c -o $R/r3.o; gcc -c -flto -frandom-seed=0 $R/r.c -o $R/r4.o; cmp -s $R/r3.o $R/r4.o && echo "  -frandom-seed=0 identical" || echo "  -frandom-seed=0 DIFFER"
echo "===== 11. __FILE__ value under relative vs absolute invocation ====="
printf '#include <stdio.h>\nconst char *p=__FILE__;\n' > $R/fi.c
gcc -E $R/fi.c | tail -1
( cd $R && gcc -E fi.c | tail -1 )
( cd $R && gcc -E -ffile-prefix-map=$R=/X fi.c | tail -1 )
