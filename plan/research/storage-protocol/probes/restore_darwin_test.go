//go:build darwin

// Probe: APFS copy-on-write clone as a restore path.
//
// Linux's reflink is FICLONE (restore_test.go) and is unsupported on ext4.
// macOS's equivalent is clonefile(2), and APFS is copy-on-write throughout, so
// this is the one platform where a clone restore should actually be available.
//
// The call goes through golang.org/x/sys/unix.Clonefile, which binds the real
// libSystem `clonefile` symbol. An earlier version of this probe issued
// syscall.Syscall(462, ...) instead and got EINVAL on the runner. That was the
// deprecated generic syscall(2) shim refusing the number, not APFS refusing the
// clone, and it would have answered this document's one named open question
// with a measurement of the wrong thing. Both calls are made here, and both
// verdicts are reported, so the distinction stays visible instead of being
// re-derived by the next reader.
package probes

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"unsafe"

	"golang.org/x/sys/unix"
)

// SYS_CLONEFILE from Darwin's <sys/syscall.h>, for the contrast case only.
const sysClonefile = 462

// rawClonefile is the deprecated path: syscall(2) with the BSD table number.
func rawClonefile(src, dst string) error {
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

// clonefile is the real one: the libSystem symbol.
func clonefile(src, dst string) error { return unix.Clonefile(src, dst, 0) }

// TestClonefileSupport states whether this filesystem supports clonefile(2).
// It records the answer rather than skipping, so "not measured" and
// "unsupported" are never confused in the results.
func TestClonefileSupport(t *testing.T) {
	dir := t.TempDir()
	src := portableSrc(t, dir, 512<<10)

	// The contrast case first, so its errno is on the record.
	if err := rawClonefile(src, filepath.Join(dir, "raw.o")); err != nil {
		t.Logf("clonefile via syscall(2) number %d: FAILED (%v). Expected: the "+
			"generic syscall shim is deprecated on macOS. This is not a "+
			"filesystem verdict.", sysClonefile, err)
	} else {
		t.Logf("clonefile via syscall(2) number %d: succeeded.", sysClonefile)
	}

	dst := filepath.Join(dir, "clone.o")
	if err := clonefile(src, dst); err != nil {
		t.Logf("clonefile(2) via libSystem: NOT AVAILABLE here (%v). Clone "+
			"restore is unavailable on this volume; ENOTSUP means the "+
			"filesystem refuses, ENOSYS would mean the symbol is missing.", err)
		return
	}
	st, err := os.Stat(dst)
	if err != nil {
		t.Fatalf("clonefile reported success but the destination is unusable: %v", err)
	}
	t.Logf("clonefile(2) via libSystem: SUPPORTED; cloned %d bytes as a "+
		"copy-on-write share, in %s", st.Size(), dir)
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
