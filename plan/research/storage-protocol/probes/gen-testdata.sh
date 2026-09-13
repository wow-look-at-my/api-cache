#!/bin/sh
# Builds the probe corpus: real compiler output, not synthetic buffers.
# Run from this directory. Requires gcc and g++.
set -eu
cd "$(dirname "$0")"
mkdir -p testdata
g++ -std=c++17 -g -O2 -c src/mid.cc  -o testdata/mid.o    -MD -MF testdata/mid.d
gcc         -g -O2 -c src/small.c    -o testdata/small.o  -MD -MF testdata/small.d
g++ -std=c++17 -g -O2 -c src/big.cc  -o testdata/big.o    -MD -MF testdata/big.d
g++ -std=c++17 -g1 -O2 -c src/big.cc -o testdata/big_g1.o
ls -l testdata
