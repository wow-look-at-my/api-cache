# Why this file is not in the directory above

`binpazer_c.c` lives in its own directory because `go build` refuses a package
directory that holds a `.c` file without cgo:

    C source files not allowed when not using cgo or SWIG: binpazer_c.c

The Go trailer probe is that package, so one stray C file broke its build and,
through it, every downstream step that needed the binary it produces.
