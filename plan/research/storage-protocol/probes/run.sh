#!/bin/sh
# Regenerates everything in results/. Needs gcc, g++ and a Go toolchain with
# the module cache warm (GOPROXY=off is deliberate: no network at probe time).
set -eu
cd "$(dirname "$0")"
[ -f testdata/mid.o ] || ./gen-testdata.sh
mkdir -p results
export GOPROXY=off GOFLAGS=-mod=mod
GO=${GO:-/usr/local/go/bin/go}
{ uname -a; lscpu | grep -E 'Model name|^CPU\(s\)'; grep -o -E 'sha_ni|avx2|avx512f' /proc/cpuinfo | sort -u | tr '\n' ' '; echo; df -T . | tail -1; $GO version; } > results/machine.txt 2>&1
$GO test -run 'TestRatios|TestContainerOverhead|TestBinpazer' -v . > results/tables.txt 2>&1
$GO test -run '^$' -bench . -benchtime 500ms -count 1 . > results/bench.txt 2>&1
tail -3 results/bench.txt
