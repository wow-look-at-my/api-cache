// Probe: what a local cache lookup costs on a hot page cache.
//
// A compiler-cache lookup does, per compile: one or two stats (does the key
// exist), then one or more opens and reads (pull the result back out). This
// measures each piece separately so the layout choice (one container file vs
// N blobs) can be costed in ns, not in adjectives.
package probes

import (
	"crypto/sha256"
	"hash/crc32"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func writeN(tb testing.TB, dir string, n int, size int) []string {
	tb.Helper()
	buf := make([]byte, size)
	for i := range buf {
		buf[i] = byte(i * 31)
	}
	paths := make([]string, n)
	for i := 0; i < n; i++ {
		p := filepath.Join(dir, "f"+string(rune('a'+i%26))+string(rune('0'+i/26)))
		if err := os.WriteFile(p, buf, 0o644); err != nil {
			tb.Fatal(err)
		}
		paths[i] = p
	}
	return paths
}

var sizes = []struct {
	name string
	n    int
}{
	{"4KiB", 4 << 10},
	{"200KiB", 200 << 10},
	{"512KiB", 512 << 10},
	{"5MiB", 5 << 20},
}

func BenchmarkStat(b *testing.B) {
	dir := b.TempDir()
	p := writeN(b, dir, 1, 4<<10)[0]
	b.ReportAllocs()
	for b.Loop() {
		if _, err := os.Stat(p); err != nil {
			b.Fatal(err)
		}
	}
}

// Stat of a path that does not exist: the miss half of every lookup.
func BenchmarkStatMiss(b *testing.B) {
	p := filepath.Join(b.TempDir(), "nope")
	b.ReportAllocs()
	for b.Loop() {
		if _, err := os.Stat(p); err == nil {
			b.Fatal("expected miss")
		}
	}
}

func BenchmarkOpenClose(b *testing.B) {
	dir := b.TempDir()
	p := writeN(b, dir, 1, 4<<10)[0]
	b.ReportAllocs()
	for b.Loop() {
		f, err := os.Open(p)
		if err != nil {
			b.Fatal(err)
		}
		f.Close()
	}
}

func BenchmarkOpenReadAll(b *testing.B) {
	for _, s := range sizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			p := writeN(b, dir, 1, s.n)[0]
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				f, err := os.Open(p)
				if err != nil {
					b.Fatal(err)
				}
				if _, err := io.ReadFull(f, buf); err != nil {
					b.Fatal(err)
				}
				f.Close()
			}
		})
	}
}

// One open of a 540 KiB container vs four opens of the pieces that make it up
// (.o 512 KiB, .d 8 KiB, stderr 4 KiB, .gcno 16 KiB). Same bytes either way.
func BenchmarkReadOneContainer(b *testing.B) {
	dir := b.TempDir()
	total := (512 + 8 + 4 + 16) << 10
	p := writeN(b, dir, 1, total)[0]
	buf := make([]byte, total)
	b.SetBytes(int64(total))
	b.ReportAllocs()
	for b.Loop() {
		f, err := os.Open(p)
		if err != nil {
			b.Fatal(err)
		}
		if _, err := io.ReadFull(f, buf); err != nil {
			b.Fatal(err)
		}
		f.Close()
	}
}

func BenchmarkReadFourBlobs(b *testing.B) {
	dir := b.TempDir()
	parts := []int{512 << 10, 8 << 10, 4 << 10, 16 << 10}
	var paths []string
	for i, n := range parts {
		p := filepath.Join(dir, "p"+string(rune('0'+i)))
		bufw := make([]byte, n)
		if err := os.WriteFile(p, bufw, 0o644); err != nil {
			b.Fatal(err)
		}
		paths = append(paths, p)
	}
	total := 0
	for _, n := range parts {
		total += n
	}
	buf := make([]byte, 512<<10)
	b.SetBytes(int64(total))
	b.ReportAllocs()
	for b.Loop() {
		for i, p := range paths {
			f, err := os.Open(p)
			if err != nil {
				b.Fatal(err)
			}
			if _, err := io.ReadFull(f, buf[:parts[i]]); err != nil {
				b.Fatal(err)
			}
			f.Close()
		}
	}
}

// Hashing cost: the key derivation hashes the preprocessed source, and an
// integrity check hashes the stored body. Both are per-lookup costs.
func BenchmarkHashSHA256(b *testing.B) {
	for _, s := range sizes {
		b.Run(s.name, func(b *testing.B) {
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				h := sha256.New()
				h.Write(buf)
				h.Sum(nil)
			}
		})
	}
}

func BenchmarkHashCRC32C(b *testing.B) {
	tab := crc32.MakeTable(crc32.Castagnoli)
	for _, s := range sizes {
		b.Run(s.name, func(b *testing.B) {
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				crc32.Checksum(buf, tab)
			}
		})
	}
}
