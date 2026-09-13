// BLAKE3 is measured unconditionally. It used to sit behind a build tag with a
// fallback that printed "not measured" into the table, which meant a missing
// module produced a complete-looking table with a hole in it. Now a module
// that will not resolve fails the build, which is what should happen.
package main

import (
	"fmt"
	"time"

	"lukechampine.com/blake3"
)

// blake3Note measures BLAKE3 when the module is available.
// lukechampine.com/blake3 is MIT licensed. It is a pure-Go implementation with
// an AVX-512 path, which matters here: this CPU has AVX-512 but NOT SHA-NI, so
// BLAKE3 and sha256 are not competing on equal hardware support.
func blake3Note() {
	buf := benchBuf
	h := blake3.New(32, nil)
	d := timeN(benchN, func() {
		h.Reset()
		h.Write(buf)
		_ = h.Sum(nil)
	})
	rate := (float64(len(buf)) / (1 << 20)) / d.Seconds()
	fmt.Printf("| blake3 (lukechampine.com/blake3, MIT) | %.0f | %.0f | pure Go, AVX-512 path; cryptographic |\n",
		rate, 200/rate*1000)
	_ = time.Now
}
