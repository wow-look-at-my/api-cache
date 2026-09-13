// encoding/xml only. Package init for the xml decoder plus reflect.
package main

import (
	"encoding/xml"
	"os"
)

var sink any = xml.Name{}

func main() { os.Stdout.WriteString("hello\n") }
