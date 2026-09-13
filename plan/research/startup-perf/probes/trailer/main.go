// trailer measures the "cooked binary" idea: append the compiled config to the
// end of the executable and have the program read it back out of itself on
// every exec.
//
// Two questions are separate and both matter:
//
//  1. Does a BIGGER file cost more to exec? It should not: execve maps the
//     ELF's own segments, and bytes past the last segment are never paged in.
//     The measurement runs the same program with a 0, 1 MiB and 10 MiB
//     trailer appended.
//  2. What does READING the trailer cost? os.Executable() plus one ReadAt of
//     the last N bytes. That is the per-exec price of the cooked form.
//
// Mode is chosen by argv[1]: "quiet" exits immediately (for the exec-cost
// measurement), "read" reads its own trailer and reports what it found.
package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"time"
)

// magic marks the trailer footer, which is the LAST 16 bytes of the file:
//
//	magic[8] | payloadLen uint64
//
// A footer at a fixed offset from the end means one Seek and one Read, with
// no scan, so the cost does not grow with the binary.
const magic = "APCACHE1"

func main() {
	if len(os.Args) > 1 && os.Args[1] == "quiet" {
		return
	}
	n := 1
	if len(os.Args) > 2 {
		fmt.Sscanf(os.Args[2], "%d", &n)
	}

	var totalExe, totalRead time.Duration
	var payload []byte
	for i := 0; i < n; i++ {
		t0 := time.Now()
		exe, err := os.Executable()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		t1 := time.Now()
		payload, err = readTrailer(exe)
		t2 := time.Now()
		if err != nil {
			fmt.Fprintln(os.Stderr, "no trailer:", err)
			os.Exit(1)
		}
		totalExe += t1.Sub(t0)
		totalRead += t2.Sub(t1)
	}
	fmt.Printf("os.Executable: %.1f us/op   readTrailer: %.1f us/op   payload: %d bytes\n",
		float64(totalExe.Nanoseconds())/float64(n)/1000,
		float64(totalRead.Nanoseconds())/float64(n)/1000,
		len(payload))
}

func readTrailer(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	foot := make([]byte, 16)
	if _, err := f.ReadAt(foot, st.Size()-16); err != nil {
		return nil, err
	}
	if string(foot[:8]) != magic {
		return nil, fmt.Errorf("bad magic %q", foot[:8])
	}
	pl := binary.LittleEndian.Uint64(foot[8:])
	if int64(pl) > st.Size() {
		return nil, fmt.Errorf("trailer length %d exceeds file", pl)
	}
	buf := make([]byte, pl)
	if _, err := f.ReadAt(buf, st.Size()-16-int64(pl)); err != nil {
		return nil, err
	}
	return buf, nil
}
