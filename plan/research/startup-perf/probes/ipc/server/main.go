// A minimal unix-socket echo server, standing in for a compiler-cache daemon.
// The protocol is deliberately the cheapest thing that could work: a 4-byte
// little-endian length, then that many bytes, and the same shape back. There
// is no framing library and no serialization format, so the number measured is
// the SYSCALL AND SCHEDULER floor of the daemon architecture, not the cost of
// whatever protocol is chosen later.
//
// One goroutine per connection. A real daemon does more per request; this one
// does the least possible, which is the point.
package main

import (
	"encoding/binary"
	"io"
	"net"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	sock := "/tmp/apcache-bench.sock"
	if len(os.Args) > 1 {
		sock = os.Args[1]
	}
	_ = os.Remove(sock)
	ln, err := net.Listen("unix", sock)
	if err != nil {
		panic(err)
	}
	defer os.Remove(sock)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; ln.Close(); os.Remove(sock); os.Exit(0) }()

	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go serve(c)
	}
}

func serve(c net.Conn) {
	defer c.Close()
	hdr := make([]byte, 4)
	buf := make([]byte, 65536)
	for {
		if _, err := io.ReadFull(c, hdr); err != nil {
			return
		}
		n := binary.LittleEndian.Uint32(hdr)
		if int(n) > len(buf) {
			buf = make([]byte, n)
		}
		if _, err := io.ReadFull(c, buf[:n]); err != nil {
			return
		}
		// The reply is a fixed short verdict, the way a cache daemon answers
		// "hit, here is the object id" or "miss, go compile".
		reply := []byte("HIT 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd")
		binary.LittleEndian.PutUint32(hdr, uint32(len(reply)))
		if _, err := c.Write(hdr); err != nil {
			return
		}
		if _, err := c.Write(reply); err != nil {
			return
		}
	}
}
