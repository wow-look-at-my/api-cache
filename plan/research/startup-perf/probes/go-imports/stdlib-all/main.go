// net/http + encoding/xml + text/template together: the import set a Go
// config-driven wrapper built the obvious way would carry.
package main

import (
	"encoding/xml"
	"net/http"
	"os"
	"text/template"
)

var sink = []any{http.DefaultClient, xml.Name{}, template.New("x")}

func main() { os.Stdout.WriteString("hello\n") }
