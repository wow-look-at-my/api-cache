// crypto/sha256 alone: what a hashing wrapper minimally needs.
package main

import (
	"crypto/sha256"
	"os"
)

var sink = sha256.New()

func main() { os.Stdout.WriteString("hello\n") }
