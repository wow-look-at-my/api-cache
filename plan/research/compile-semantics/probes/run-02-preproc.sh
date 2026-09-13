#!/bin/sh
# Probe: preprocessor output shape, line markers, -P, -fpreprocessed, __DATE__ family.
cd "$(dirname "$0")/src"
echo "===== gcc -E hello.c (head 25) ====="; gcc -E hello.c | head -25
echo "===== gcc -E -P hello.c (head 15) ====="; gcc -E -P hello.c | head -15
echo "===== clang -E hello.c (head 25) ====="; clang -E hello.c | head -25
echo "===== gcc -E -P timey.c (tail) ====="; gcc -E -P timey.c | tail -3
echo "===== gcc -E hello.c | md5 twice (stability) ====="
gcc -E hello.c | md5sum; gcc -E hello.c | md5sum
echo "===== gcc -E from a different cwd, relative include (path leakage) ====="
( cd .. && gcc -E -Isrc src/hello.c | grep -n '"' | head -8 )
echo "===== gcc -E with absolute source ====="
gcc -E "$PWD/hello.c" | grep -n '"' | head -8
echo "===== gcc -E -fdirectives-only ====="; gcc -E -fdirectives-only hello.c | head -12
