#!/bin/sh
# Builds the probe corpus: real compiler output, not synthetic buffers.
# Run from this directory. CC/CXX override the compilers (macOS: clang via the
# gcc/g++ shims).
set -eu
cd "$(dirname "$0")"
CC=${CC:-gcc}
CXX=${CXX:-g++}
mkdir -p testdata
"$CXX" -std=c++17 -g  -O2 -c src/mid.cc   -o testdata/mid.o    -MD -MF testdata/mid.d
"$CC"             -g  -O2 -c src/small.c  -o testdata/small.o  -MD -MF testdata/small.d
"$CXX" -std=c++17 -g  -O2 -c src/big.cc   -o testdata/big.o    -MD -MF testdata/big.d
"$CXX" -std=c++17 -g1 -O2 -c src/big.cc   -o testdata/big_g1.o
ls -l testdata
