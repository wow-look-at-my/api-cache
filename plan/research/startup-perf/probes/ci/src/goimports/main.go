// The import set a config-driven Go wrapper built the obvious way carries:
// encoding/xml to read the config, text/template to render it, net/http
// because the language's consumers speak HTTP. Package init for all three
// runs before main on every single exec.
package main

import (
	"encoding/xml"
	"net/http"
	"os"
	"text/template"
)

var sink = []any{http.DefaultClient, xml.Name{}, template.New("x")}

func main() {
	_ = sink
	os.Stdout.WriteString("hello\n")
}
