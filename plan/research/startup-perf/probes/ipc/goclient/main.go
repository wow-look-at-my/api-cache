// The Go client side of the daemon round trip. It runs as a fresh process,
// exactly as a wrapper would, so what it measures is connect + write + read +
// close on a cold connection. That is the whole per-exec cost the daemon
// architecture adds on TOP of the process startup floor.
//
// With an argument it reports the in-process per-op time over a reused
// connection as well, which separates connection setup from the round trip.
package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

func main() {
	sock := "/tmp/apcache-bench.sock"
	n := 1
	if len(os.Args) > 1 {
		fmt.Sscanf(os.Args[1], "%d", &n)
	}
	if len(os.Args) > 2 {
		sock = os.Args[2]
	}
	// A realistic request: the wrapper's argv, cwd and the hash of its inputs.
	req := make([]byte, 512)
	for i := range req {
		req[i] = byte('a' + i%26)
	}

	if n == 1 {
		// One cold connection, which is the per-exec shape.
		c, err := net.Dial("unix", sock)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		roundTrip(c, req)
		c.Close()
		return
	}

	// Cold-connect cost: a fresh Dial and one round trip, n times.
	var cold time.Duration
	for i := 0; i < n; i++ {
		t0 := time.Now()
		c, err := net.Dial("unix", sock)
		if err != nil {
			panic(err)
		}
		roundTrip(c, req)
		c.Close()
		cold += time.Since(t0)
	}

	// Warm round trip: one connection, n round trips.
	c, err := net.Dial("unix", sock)
	if err != nil {
		panic(err)
	}
	roundTrip(c, req) // warm up
	t0 := time.Now()
	for i := 0; i < n; i++ {
		roundTrip(c, req)
	}
	warm := time.Since(t0)
	c.Close()

	fmt.Printf("go client: dial+roundtrip+close %.1f us/op   roundtrip only (reused conn) %.1f us/op\n",
		float64(cold.Nanoseconds())/float64(n)/1000,
		float64(warm.Nanoseconds())/float64(n)/1000)
}

func roundTrip(c net.Conn, req []byte) {
	hdr := make([]byte, 4)
	binary.LittleEndian.PutUint32(hdr, uint32(len(req)))
	if _, err := c.Write(hdr); err != nil {
		panic(err)
	}
	if _, err := c.Write(req); err != nil {
		panic(err)
	}
	if _, err := io.ReadFull(c, hdr); err != nil {
		panic(err)
	}
	rn := binary.LittleEndian.Uint32(hdr)
	buf := make([]byte, rn)
	if _, err := io.ReadFull(c, buf); err != nil {
		panic(err)
	}
}
