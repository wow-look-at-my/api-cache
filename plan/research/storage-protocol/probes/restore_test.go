//go:build linux

// Probe: what it costs to put the outputs back where the compiler would have
// written them. A hit is only fast if the restore is fast.
package probes

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
)

// Raw stat without Go's os.FileInfo allocation, to separate syscall cost from
// runtime cost.
func BenchmarkRawStat(b *testing.B) {
	dir := b.TempDir()
	p := writeN(b, dir, 1, 4<<10)[0]
	var st syscall.Stat_t
	b.ReportAllocs()
	for b.Loop() {
		if err := syscall.Stat(p, &st); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkRawStatMiss(b *testing.B) {
	p := filepath.Join(b.TempDir(), "nope")
	var st syscall.Stat_t
	b.ReportAllocs()
	for b.Loop() {
		if err := syscall.Stat(p, &st); err == nil {
			b.Fatal("expected miss")
		}
	}
}

func srcFile(tb testing.TB, dir string, size int) string {
	tb.Helper()
	p := filepath.Join(dir, "src.bin")
	buf := make([]byte, size)
	for i := range buf {
		buf[i] = byte(i)
	}
	if err := os.WriteFile(p, buf, 0o644); err != nil {
		tb.Fatal(err)
	}
	return p
}

var restoreSizes = []struct {
	name string
	n    int
}{
	{"200KiB", 200 << 10},
	{"512KiB", 512 << 10},
	{"5MiB", 5 << 20},
}

// Restore by writing the bytes out: read the cached body, write the output.
// Includes the temp+rename that makes the restore atomic.
func BenchmarkRestoreCopyRename(b *testing.B) {
	for _, s := range restoreSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := srcFile(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				in, err := os.Open(src)
				if err != nil {
					b.Fatal(err)
				}
				if _, err := in.Read(buf); err != nil {
					b.Fatal(err)
				}
				in.Close()
				tmp := dst + ".part"
				if err := os.WriteFile(tmp, buf, 0o644); err != nil {
					b.Fatal(err)
				}
				if err := os.Rename(tmp, dst); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Restore with copy_file_range: the kernel moves the bytes, and on a
// reflink-capable filesystem it may share extents instead of copying.
func BenchmarkRestoreCopyFileRange(b *testing.B) {
	for _, s := range restoreSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := srcFile(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				in, err := os.Open(src)
				if err != nil {
					b.Fatal(err)
				}
				out, err := os.Create(dst + ".part")
				if err != nil {
					b.Fatal(err)
				}
				remaining := int64(s.n)
				for remaining > 0 {
					n, err := copyFileRange(int(in.Fd()), int(out.Fd()), int(remaining))
					if err != nil || n == 0 {
						b.Fatalf("copy_file_range: n=%d err=%v", n, err)
					}
					remaining -= int64(n)
				}
				out.Close()
				in.Close()
				if err := os.Rename(dst+".part", dst); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

func copyFileRange(in, out, n int) (int, error) {
	r, _, e := syscall.Syscall6(sysCopyFileRange,
		uintptr(in), 0, uintptr(out), 0, uintptr(n), 0)
	if e != 0 {
		return 0, e
	}
	return int(r), nil
}

// Restore by hard link: no bytes move at all. ccache's hard_link option.
// The cache entry and the build tree then share one inode, so a build step
// that writes to the output corrupts the cache.
func BenchmarkRestoreHardLink(b *testing.B) {
	for _, s := range restoreSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := srcFile(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				os.Remove(dst)
				if err := os.Link(src, dst); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

const sysCopyFileRange = 326 // x86-64 copy_file_range

const ficlone = 0x40049409 // FICLONE: _IOW(0x94, 9, int)

// Restore by reflink: a copy-on-write clone. Safe like a copy, cheap like a
// link — where the filesystem supports it. Reports EOPNOTSUPP otherwise, and
// that answer is itself the finding.
func BenchmarkRestoreReflink(b *testing.B) {
	dir := b.TempDir()
	src := srcFile(b, dir, 512<<10)
	dst := filepath.Join(dir, "out.o")
	in, err := os.Open(src)
	if err != nil {
		b.Fatal(err)
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		b.Fatal(err)
	}
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, out.Fd(), uintptr(ficlone), uintptr(in.Fd()))
	out.Close()
	if e != 0 {
		b.Skipf("FICLONE unsupported on this filesystem: %v", syscall.Errno(e))
	}
	b.SetBytes(512 << 10)
	for b.Loop() {
		out, err := os.Create(dst + ".part")
		if err != nil {
			b.Fatal(err)
		}
		_, _, e := syscall.Syscall(syscall.SYS_IOCTL, out.Fd(), uintptr(ficlone), uintptr(in.Fd()))
		out.Close()
		if e != 0 {
			b.Fatal(syscall.Errno(e))
		}
		os.Rename(dst+".part", dst)
	}
}

