// net/http: the biggest stdlib init in common use (crypto, TLS ciphersuites,
// the DefaultTransport, mime type tables).
package main

import (
	"net/http"
	"os"
)

var sink any = http.DefaultClient

func main() { os.Stdout.WriteString("hello\n") }
