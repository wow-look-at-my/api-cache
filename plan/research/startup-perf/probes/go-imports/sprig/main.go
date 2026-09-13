// sprig's TxtFuncMap built once. api-dsl's FuncMap() calls this on every
// renderer construction, so its cost is on the wrapper's startup path.
package main

import (
	"os"

	"github.com/Masterminds/sprig/v3"
)

var sink = sprig.TxtFuncMap()

func main() {
	if len(sink) == 0 {
		os.Exit(1)
	}
	os.Stdout.WriteString("hello\n")
}
