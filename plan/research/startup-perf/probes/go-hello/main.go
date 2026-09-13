// Minimal Go process: runtime bring-up (scheduler, mheap, GC, signal handlers)
// plus one write. Nothing else is linked in.
package main

import "os"

func main() { os.Stdout.WriteString("hello\n") }
