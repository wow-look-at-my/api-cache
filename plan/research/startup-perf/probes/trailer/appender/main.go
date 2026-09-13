// appender copies a binary and appends a trailer of the requested size, in the
// footer format trailer/main.go reads back.
package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: appender <in> <out> <payloadBytes>")
		os.Exit(2)
	}
	size, err := strconv.Atoi(os.Args[3])
	if err != nil {
		panic(err)
	}
	in, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer in.Close()
	out, err := os.OpenFile(os.Args[2], os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		panic(err)
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		panic(err)
	}
	// A compressible payload would understate the page-in cost, so the bytes
	// are a cheap non-constant pattern rather than zeroes.
	buf := make([]byte, size)
	for i := range buf {
		buf[i] = byte(i * 31)
	}
	if _, err := out.Write(buf); err != nil {
		panic(err)
	}
	foot := make([]byte, 16)
	copy(foot, "APCACHE1")
	binary.LittleEndian.PutUint64(foot[8:], uint64(size))
	if _, err := out.Write(foot); err != nil {
		panic(err)
	}
	fmt.Printf("wrote %s with a %d-byte trailer\n", os.Args[2], size)
}
