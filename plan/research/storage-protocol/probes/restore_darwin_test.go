//go:build darwin

// Probe: APFS copy-on-write clone as a restore path.
//
// Linux's reflink is FICLONE (restore_test.go) and is unsupported on ext4.
// macOS's equivalent is clonefile(2), and APFS is copy-on-write throughout, so
// this is the one platform where a clone restore should actually be available.
// The verdict is reported either way — an unexpected errno is printed, never
// swallowed.
package probes

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"unsafe"
)

// SYS_CLONEFILE from Darwin's <sys/syscall.h>.
// int clonefile(const char *src, const char *dst, int flags);
const sysClonefile = 462

func clonefile(src, dst string) error {
	s, err := syscall.BytePtrFromString(src)
	if err != nil {
		return err
	}
	d, err := syscall.BytePtrFromString(dst)
	if err != nil {
		return err
	}
	_, _, e := syscall.Syscall(sysClonefile,
		uintptr(unsafe.Pointer(s)), uintptr(unsafe.Pointer(d)), 0)
	if e != 0 {
		return e
	}
	return nil
}

// TestClonefileSupport states whether this filesystem supports clonefile(2).
// It records the answer rather than skipping, so "not measured" and
// "unsupported" are never confused in the results.
func TestClonefileSupport(t *testing.T) {
	dir := t.TempDir()
	src := portableSrc(t, dir, 512<<10)
	dst := filepath.Join(dir, "clone.o")
	if err := clonefile(src, dst); err != nil {
		t.Logf("clonefile(2): NOT AVAILABLE here (%v). Clone restore is "+
			"unavailable; an ENOSYS would mean the syscall number is wrong "+
			"rather than the filesystem refusing.", err)
		return
	}
	st, err := os.Stat(dst)
	if err != nil {
		t.Fatalf("clonefile reported success but the destination is unusable: %v", err)
	}
	t.Logf("clonefile(2): SUPPORTED; cloned %d bytes as a copy-on-write share", st.Size())
}

// BenchmarkRestoreClonefile measures the clone restore where it works.
// TestClonefileSupport records the verdict when it does not.
func BenchmarkRestoreClonefile(b *testing.B) {
	for _, s := range portableSizes {
		b.Run(s.name, func(b *testing.B) {
			dir := b.TempDir()
			src := portableSrc(b, dir, s.n)
			dst := filepath.Join(dir, "out.o")
			if err := clonefile(src, dst); err != nil {
				b.Skipf("clonefile unavailable; see TestClonefileSupport in the tables: %v", err)
			}
			if err := os.Remove(dst); err != nil {
				b.Fatal(err)
			}
			b.SetBytes(int64(s.n))
			b.ReportAllocs()
			for b.Loop() {
				if err := os.Remove(dst); err != nil && !os.IsNotExist(err) {
					b.Fatal(err)
				}
				if err := clonefile(src, dst); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
