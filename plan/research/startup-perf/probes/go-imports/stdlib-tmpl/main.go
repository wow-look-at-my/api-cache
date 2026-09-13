// text/template only.
package main

import (
	"os"
	"text/template"
)

var sink any = template.New("x")

func main() { os.Stdout.WriteString("hello\n") }
