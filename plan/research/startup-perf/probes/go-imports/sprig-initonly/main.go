// sprig imported and linked, but TxtFuncMap() never called. This isolates the
// package's own init from the cost of materializing the ~180-entry map.
package main

import (
	"os"

	"github.com/Masterminds/sprig/v3"
)

var f = sprig.TxtFuncMap

func main() {
	if f == nil {
		os.Exit(1)
	}
	os.Stdout.WriteString("hello\n")
}
