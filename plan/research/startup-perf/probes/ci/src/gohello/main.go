// Go startup floor: runtime bring-up and one write.
package main

import "os"

func main() { os.Stdout.WriteString("hello\n") }
