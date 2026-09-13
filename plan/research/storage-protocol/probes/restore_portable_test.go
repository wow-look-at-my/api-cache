// Probe: the restore half of a hit, on every platform.
//
// restore_test.go covers the Linux-only syscalls (copy_file_range, FICLONE).
// This file covers what every platform can do, so the Windows and macOS
// numbers exist instead of being absent without comment.
package probes

import (
	"io"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func portableSrc(tb testing.TB, dir string, size int) string {
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

var portableSizes = []struct {
	name string
	n    int
}{
	{"200KiB", 200 << 10},
	{"512KiB", 512 << 10},
	{"5MiB", 5 << 20},
}

// The ordinary restore: read the cached body, write the output through a temp
// file, rename it into place.
func BenchmarkPortableRestoreCopyRename(b *testing.B) {
	for _, s := range portableSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := portableSrc(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				in, err := os.Open(src)
				if err != nil {
					b.Fatal(err)
				}
				if _, err := io.ReadFull(in, buf); err != nil {
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

// The same restore with an fsync before the rename, which is what durability
// costs. go-s3-server fsyncs only at or above 8 MiB on the argument that the
// client verifies the body; this measures what that argument is worth.
func BenchmarkPortableRestoreCopyFsyncRename(b *testing.B) {
	for _, s := range portableSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := portableSrc(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			buf := make([]byte, s.n)
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				in, err := os.Open(src)
				if err != nil {
					b.Fatal(err)
				}
				if _, err := io.ReadFull(in, buf); err != nil {
					b.Fatal(err)
				}
				in.Close()
				tmp := dst + ".part"
				out, err := os.Create(tmp)
				if err != nil {
					b.Fatal(err)
				}
				if _, err := out.Write(buf); err != nil {
					b.Fatal(err)
				}
				if err := out.Sync(); err != nil {
					b.Fatal(err)
				}
				out.Close()
				if err := os.Rename(tmp, dst); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Restore by hard link: no bytes move. NTFS supports it, APFS supports it.
// The cache entry and the build tree then share an inode.
func BenchmarkPortableRestoreHardLink(b *testing.B) {
	for _, s := range portableSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := portableSrc(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				if err := os.Remove(dst); err != nil && !os.IsNotExist(err) {
					b.Fatal(err)
				}
				if err := os.Link(src, dst); err != nil {
					b.Fatalf("hard link unsupported here: %v", err)
				}
			}
		})
	}
}

// TestRenameOverOpenFile states whether the platform lets a store replace an
// entry another process is reading. POSIX does; Windows refuses unless the
// reader opened with FILE_SHARE_DELETE, which Go's os.Open does not request.
// The answer decides whether the write path needs a rename-then-delete dance.
func TestRenameOverOpenFile(t *testing.T) {
	dir := t.TempDir()
	victim := filepath.Join(dir, "entry")
	if err := os.WriteFile(victim, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	replacement := filepath.Join(dir, "entry.part")
	if err := os.WriteFile(replacement, []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}

	reader, err := os.Open(victim)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()

	err = os.Rename(replacement, victim)
	if err != nil {
		t.Logf("GOOS=%s: rename over an OPEN file FAILS (%v). A store must "+
			"rename the old entry aside and delete it, or retry.", runtime.GOOS, err)
		return
	}
	// The reader's handle must still see the old bytes.
	got, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("GOOS=%s: rename succeeded but the open handle broke: %v", runtime.GOOS, err)
	}
	t.Logf("GOOS=%s: rename over an OPEN file SUCCEEDS; the open handle still "+
		"reads %q", runtime.GOOS, got)
}

// TestUnlinkOpenFile states whether an entry can be evicted while a reader
// holds it open. POSIX keeps the inode alive; Windows refuses the unlink.
func TestUnlinkOpenFile(t *testing.T) {
	dir := t.TempDir()
	victim := filepath.Join(dir, "entry")
	if err := os.WriteFile(victim, []byte("payload"), 0o644); err != nil {
		t.Fatal(err)
	}
	reader, err := os.Open(victim)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()

	if err := os.Remove(victim); err != nil {
		t.Logf("GOOS=%s: unlinking an OPEN file FAILS (%v). Eviction must skip "+
			"or retry an entry a reader holds.", runtime.GOOS, err)
		return
	}
	got, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("GOOS=%s: unlink succeeded but the open handle broke: %v", runtime.GOOS, err)
	}
	t.Logf("GOOS=%s: unlinking an OPEN file SUCCEEDS; the handle still reads %q",
		runtime.GOOS, got)
}

// TestLongPath states the platform's limit on a deep, long cache path — a
// four-level shard under a long root is exactly the shape that trips MAX_PATH.
func TestLongPath(t *testing.T) {
	dir := t.TempDir()
	deep := dir
	for i := 0; i < 6; i++ {
		deep = filepath.Join(deep, "0123456789012345678901234567890123456789")
	}
	if err := os.MkdirAll(deep, 0o755); err != nil {
		t.Logf("GOOS=%s: MkdirAll at depth %d (%d chars) FAILS: %v",
			runtime.GOOS, 6, len(deep), err)
		return
	}
	f := filepath.Join(deep, "0123456789012345678901234567890123456789.entry")
	if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
		t.Logf("GOOS=%s: WriteFile at %d chars FAILS: %v", runtime.GOOS, len(f), err)
		return
	}
	t.Logf("GOOS=%s: a %d-character path works", runtime.GOOS, len(f))
}
