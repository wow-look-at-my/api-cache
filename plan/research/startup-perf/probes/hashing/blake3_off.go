//go:build !blake3

package main

import "fmt"

// blake3Note reports BLAKE3's absence rather than guessing at a number.
// Build with -tags blake3 once the module resolves to measure it.
func blake3Note() {
	fmt.Println("| blake3 | not measured | | no module vendored; see results for the cited figure |")
}
