// hashbench measures the hashing throughput floor a compiler wrapper works
// inside. The wrapper hashes something on every invocation — the preprocessed
// output, or the source plus every header it pulls in — so the question is
// what that costs per megabyte, and what a whole open-read-hash-close of one
// realistic file costs end to end.
//
// Only hashes available with no network are measured: crypto/sha256 (which
// uses SHA-NI where the CPU has it), crypto/sha512, crypto/md5, the stdlib
// maphash, and a small hand-written xxHash64, whose algorithm is in the public
// domain (the reference implementation is BSD-2-Clause, Yann Collet).
//
// BLAKE3 needs a third-party module; if it resolves it is measured too,
// otherwise its absence is reported rather than guessed at.
package main

import (
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/binary"
	"flag"
	"fmt"
	"hash"
	"hash/crc32"
	"hash/fnv"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// ---------------------------------------------------------------- xxhash64

// A compact xxHash64. The algorithm is Yann Collet's, placed in the public
// domain; the reference C implementation is BSD-2-Clause. This is written out
// here rather than imported so the probe needs no module download.
const (
	p1 = 11400714785074694791
	p2 = 14029467366897019727
	p3 = 1609587929392839161
	p4 = 9650029242287828579
	p5 = 2870177450012600261
)

func rol(x uint64, r uint) uint64 { return x<<r | x>>(64-r) }

func round(acc, in uint64) uint64 { return rol(acc+in*p2, 31) * p1 }

func mergeRound(acc, val uint64) uint64 {
	return (acc^round(0, val))*p1 + p4
}

func xxhash64(b []byte) uint64 {
	n := len(b)
	var h uint64
	if n >= 32 {
		// Written as statements rather than one initializer: p1+p2 and -p1
		// both overflow uint64 as untyped constants, and Go rejects that at
		// compile time even though the wrapped value is what xxHash wants.
		var v1, v2, v3, v4 uint64
		v1 = uint64(p1)
		v1 += uint64(p2)
		v2 = uint64(p2)
		v3 = 0
		v4 -= uint64(p1)
		for len(b) >= 32 {
			v1 = round(v1, binary.LittleEndian.Uint64(b[0:]))
			v2 = round(v2, binary.LittleEndian.Uint64(b[8:]))
			v3 = round(v3, binary.LittleEndian.Uint64(b[16:]))
			v4 = round(v4, binary.LittleEndian.Uint64(b[24:]))
			b = b[32:]
		}
		h = rol(v1, 1) + rol(v2, 7) + rol(v3, 12) + rol(v4, 18)
		h = mergeRound(h, v1)
		h = mergeRound(h, v2)
		h = mergeRound(h, v3)
		h = mergeRound(h, v4)
	} else {
		h = p5
	}
	h += uint64(n)
	for len(b) >= 8 {
		h = rol(h^round(0, binary.LittleEndian.Uint64(b)), 27)*p1 + p4
		b = b[8:]
	}
	if len(b) >= 4 {
		h = rol(h^uint64(binary.LittleEndian.Uint32(b))*p1, 23)*p2 + p3
		b = b[4:]
	}
	for _, c := range b {
		h = rol(h^uint64(c)*p5, 11) * p1
	}
	h ^= h >> 33
	h *= p2
	h ^= h >> 29
	h *= p3
	h ^= h >> 32
	return h
}

// ---------------------------------------------------------------- bench

func mbps(bytes int, d time.Duration) float64 {
	return (float64(bytes) / (1 << 20)) / d.Seconds()
}

func timeN(n int, f func()) time.Duration {
	for i := 0; i < 3; i++ {
		f()
	}
	var ds []time.Duration
	for i := 0; i < n; i++ {
		t0 := time.Now()
		f()
		ds = append(ds, time.Since(t0))
	}
	sort.Slice(ds, func(i, j int) bool { return ds[i] < ds[j] })
	return ds[len(ds)/2] // median, which is robust to a noisy VM
}

// benchBuf and benchN are set in main so the optional blake3 file can reach
// the same buffer and iteration count without re-deriving them.
var (
	benchBuf []byte
	benchN   int
)

func main() {
	sizeKiB := flag.Int("size", 4096, "buffer size in KiB for the throughput table")
	fileKiB := flag.Int("file", 200, "file size in KiB for the end-to-end test")
	n := flag.Int("n", 30, "iterations")
	flag.Parse()

	buf := make([]byte, *sizeKiB*1024)
	for i := range buf {
		buf[i] = byte(i * 7)
	}
	benchBuf, benchN = buf, *n

	fmt.Printf("# hashing throughput\n\n")
	fmt.Printf("- buffer: %d KiB, already in memory\n", *sizeKiB)
	fmt.Printf("- iterations: %d, median reported\n\n", *n)
	fmt.Println("| hash | MB/s | us per 200 KiB | note |")
	fmt.Println("|---|---|---|---|")

	type entry struct {
		name string
		new  func() hash.Hash
		note string
	}
	hashes := []entry{
		{"sha256", sha256.New, "stdlib; uses SHA-NI where the CPU has it"},
		{"sha512", sha512.New, "stdlib; AVX2 path, often faster than sha256 without SHA-NI"},
		{"sha1", sha1.New, "stdlib; broken for security, listed as a speed reference only"},
		{"md5", md5.New, "stdlib; broken for security, listed as a speed reference only"},
		{"crc32 (Castagnoli)", func() hash.Hash { return crc32.New(crc32.MakeTable(crc32.Castagnoli)) }, "SSE4.2 hardware CRC; not collision resistant"},
		{"fnv64a", func() hash.Hash { return fnv.New64a() }, "stdlib; not collision resistant"},
	}
	for _, e := range hashes {
		h := e.new()
		d := timeN(*n, func() {
			h.Reset()
			h.Write(buf)
			_ = h.Sum(nil)
		})
		rate := mbps(len(buf), d)
		fmt.Printf("| %s | %.0f | %.0f | %s |\n", e.name, rate, 200/rate*1000, e.note)
	}
	d := timeN(*n, func() { _ = xxhash64(buf) })
	rate := mbps(len(buf), d)
	fmt.Printf("| xxhash64 (inlined here) | %.0f | %.0f | %s |\n", rate, 200/rate*1000,
		"algorithm public domain, reference impl BSD-2-Clause; not collision resistant")

	blake3Note()

	// ---- end-to-end: open, read, hash, close one file
	dir, err := os.MkdirTemp("", "hashbench")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)
	path := filepath.Join(dir, "unit.i")
	fb := make([]byte, *fileKiB*1024)
	for i := range fb {
		fb[i] = byte(i * 13)
	}
	if err := os.WriteFile(path, fb, 0o644); err != nil {
		panic(err)
	}

	fmt.Printf("\n## end to end: open + read + sha256 + close, one %d KiB file\n\n", *fileKiB)
	fmt.Println("| method | us | note |")
	fmt.Println("|---|---|---|")

	d = timeN(*n, func() {
		f, _ := os.Open(path)
		h := sha256.New()
		_, _ = io.Copy(h, f)
		_ = h.Sum(nil)
		f.Close()
	})
	fmt.Printf("| io.Copy into sha256 | %.0f | 32 KiB default copy buffer, warm page cache |\n",
		float64(d.Microseconds()))

	d = timeN(*n, func() {
		b, _ := os.ReadFile(path)
		s := sha256.Sum256(b)
		_ = s
	})
	fmt.Printf("| os.ReadFile then sha256.Sum256 | %.0f | one allocation of the whole file, warm page cache |\n",
		float64(d.Microseconds()))

	rb := make([]byte, 256*1024)
	d = timeN(*n, func() {
		f, _ := os.Open(path)
		h := sha256.New()
		for {
			k, e := f.Read(rb)
			if k > 0 {
				h.Write(rb[:k])
			}
			if e != nil {
				break
			}
		}
		_ = h.Sum(nil)
		f.Close()
	})
	fmt.Printf("| reused 256 KiB buffer | %.0f | no per-call allocation, warm page cache |\n",
		float64(d.Microseconds()))

	d = timeN(*n, func() {
		f, _ := os.Open(path)
		f.Close()
	})
	fmt.Printf("| open + close only | %.0f | the syscall floor under every row above |\n",
		float64(d.Microseconds()))
	fmt.Println()
}
