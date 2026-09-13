// Probe: container formats for a multi-output cache entry.
//
// One compile result is several files: the object, the dependency file, the
// captured stderr, and sometimes coverage notes or a split-DWARF object. The
// question is what one file on disk (and one body on the wire) should look
// like. Measured here: pack cost, unpack-everything cost, the cost of reading
// ONE member out of the middle, and the framing overhead in bytes.
package probes

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"testing"
)

type member struct {
	Name string
	Data []byte
}

func entrySet(tb testing.TB) []member {
	tb.Helper()
	obj := load(tb, "testdata/mid.o")
	dep := load(tb, "testdata/mid.d")
	// Realistic stderr: a couple of warnings.
	stderr := bytes.Repeat([]byte("mid.cc:41:9: warning: unused variable 'x' [-Wunused-variable]\n"), 30)
	// Coverage notes are a fraction of the object's size.
	gcno := obj[:40<<10]
	return []member{
		{"object", obj},
		{"dependency", dep},
		{"stderr", stderr},
		{"coverage", gcno},
	}
}

// --- custom framed container ---------------------------------------------
//
// Layout (little-endian, every offset absolute from byte 0):
//
//	magic    4    "ACE1"
//	version  1
//	flags    1    bit0 = payloads compressed
//	n        2    member count
//	table    n * (type u8, pad u8, len u32, off u64)
//	payloads concatenated, in table order
//	trailer  8    xxhash/crc of everything above
//
// The table is fixed-width, so member i is found with one multiply and no
// scan. Reading only the object is one pread of the table plus one pread of
// that member's range.

const aceHeaderLen = 8
const aceEntryLen = 14

func acePack(ms []member) []byte {
	var buf bytes.Buffer
	buf.WriteString("ACE1")
	buf.WriteByte(1)
	buf.WriteByte(0)
	var n [2]byte
	binary.LittleEndian.PutUint16(n[:], uint16(len(ms)))
	buf.Write(n[:])
	off := uint64(aceHeaderLen + aceEntryLen*len(ms))
	tbl := make([]byte, 0, aceEntryLen*len(ms))
	for i, m := range ms {
		var e [aceEntryLen]byte
		e[0] = byte(i) // file type id
		binary.LittleEndian.PutUint32(e[2:6], uint32(len(m.Data)))
		binary.LittleEndian.PutUint64(e[6:14], off)
		off += uint64(len(m.Data))
		tbl = append(tbl, e[:]...)
	}
	buf.Write(tbl)
	for _, m := range ms {
		buf.Write(m.Data)
	}
	var trailer [8]byte
	buf.Write(trailer[:])
	return buf.Bytes()
}

func aceUnpackAll(b []byte) [][]byte {
	n := int(binary.LittleEndian.Uint16(b[6:8]))
	out := make([][]byte, n)
	for i := 0; i < n; i++ {
		e := b[aceHeaderLen+aceEntryLen*i:]
		l := binary.LittleEndian.Uint32(e[2:6])
		o := binary.LittleEndian.Uint64(e[6:14])
		out[i] = b[o : o+uint64(l)]
	}
	return out
}

func aceReadOne(b []byte, idx int) []byte {
	e := b[aceHeaderLen+aceEntryLen*idx:]
	l := binary.LittleEndian.Uint32(e[2:6])
	o := binary.LittleEndian.Uint64(e[6:14])
	return b[o : o+uint64(l)]
}

// aceReadOneFromFile is the honest version: it never maps the whole entry.
// Two preads, one for the table and one for the member.
func aceReadOneFromFile(f *os.File, idx int) ([]byte, error) {
	hdr := make([]byte, aceHeaderLen+aceEntryLen*8)
	if _, err := f.ReadAt(hdr, 0); err != nil && err != io.EOF {
		return nil, err
	}
	e := hdr[aceHeaderLen+aceEntryLen*idx:]
	l := binary.LittleEndian.Uint32(e[2:6])
	o := binary.LittleEndian.Uint64(e[6:14])
	out := make([]byte, l)
	if _, err := f.ReadAt(out, int64(o)); err != nil {
		return nil, err
	}
	return out, nil
}

// --- tar ------------------------------------------------------------------

func tarPack(ms []member) []byte {
	var buf bytes.Buffer
	w := tar.NewWriter(&buf)
	for _, m := range ms {
		w.WriteHeader(&tar.Header{Name: m.Name, Size: int64(len(m.Data)), Mode: 0o644, Format: tar.FormatUSTAR})
		w.Write(m.Data)
	}
	w.Close()
	return buf.Bytes()
}

func tarUnpackAll(b []byte) [][]byte {
	r := tar.NewReader(bytes.NewReader(b))
	var out [][]byte
	for {
		h, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			panic(err)
		}
		d := make([]byte, h.Size)
		io.ReadFull(r, d)
		out = append(out, d)
	}
	return out
}

// tarReadOne must walk the members in order: there is no index.
func tarReadOne(b []byte, name string) []byte {
	r := tar.NewReader(bytes.NewReader(b))
	for {
		h, err := r.Next()
		if err != nil {
			return nil
		}
		if h.Name == name {
			d := make([]byte, h.Size)
			io.ReadFull(r, d)
			return d
		}
	}
}

// --- tar + sidecar manifest (the go-s3-server /_batch/get shape) ----------

func tarManifestPack(ms []member) []byte {
	type ent struct {
		Key  string            `json:"key"`
		Meta map[string]string `json:"metadata"`
	}
	var mf struct {
		Entries []ent `json:"entries"`
	}
	for _, m := range ms {
		mf.Entries = append(mf.Entries, ent{Key: m.Name, Meta: map[string]string{"size": fmt.Sprint(len(m.Data))}})
	}
	j, _ := json.Marshal(mf)
	all := append([]member{{"manifest.json", j}}, ms...)
	return tarPack(all)
}

// --- zip ------------------------------------------------------------------

func zipPack(ms []member, method uint16) []byte {
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)
	for _, m := range ms {
		fw, _ := w.CreateHeader(&zip.FileHeader{Name: m.Name, Method: method})
		fw.Write(m.Data)
	}
	w.Close()
	return buf.Bytes()
}

func zipUnpackAll(b []byte) [][]byte {
	r, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		panic(err)
	}
	var out [][]byte
	for _, f := range r.File {
		rc, _ := f.Open()
		d, _ := io.ReadAll(rc)
		rc.Close()
		out = append(out, d)
	}
	return out
}

func zipReadOne(b []byte, name string) []byte {
	r, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		panic(err)
	}
	for _, f := range r.File {
		if f.Name == name {
			rc, _ := f.Open()
			d, _ := io.ReadAll(rc)
			rc.Close()
			return d
		}
	}
	return nil
}

// TestContainerOverhead reports the framing cost in bytes.
func TestContainerOverhead(t *testing.T) {
	ms := entrySet(t)
	raw := 0
	for _, m := range ms {
		raw += len(m.Data)
	}
	rows := []struct {
		name string
		b    []byte
	}{
		{"framed (ACE1)", acePack(ms)},
		{"tar (ustar)", tarPack(ms)},
		{"tar + manifest.json", tarManifestPack(ms)},
		{"zip (stored)", zipPack(ms, zip.Store)},
		{"zip (deflate)", zipPack(ms, zip.Deflate)},
	}
	fmt.Printf("%-22s %10s %10s %8s\n", "format", "bytes", "overhead", "pct")
	for _, r := range rows {
		fmt.Printf("%-22s %10d %+10d %7.3f%%\n", r.name, len(r.b), len(r.b)-raw,
			100*float64(len(r.b)-raw)/float64(raw))
	}
	fmt.Printf("%-22s %10d\n", "raw member bytes", raw)
}

func BenchmarkContainerPack(b *testing.B) {
	ms := entrySet(b)
	total := 0
	for _, m := range ms {
		total += len(m.Data)
	}
	run := func(name string, f func([]member) []byte) {
		b.Run(name, func(b *testing.B) {
			b.SetBytes(int64(total))
			b.ReportAllocs()
			for b.Loop() {
				f(ms)
			}
		})
	}
	run("framed", acePack)
	run("tar", tarPack)
	run("tar+manifest", tarManifestPack)
	run("zipStored", func(m []member) []byte { return zipPack(m, zip.Store) })
}

func BenchmarkContainerUnpackAll(b *testing.B) {
	ms := entrySet(b)
	total := 0
	for _, m := range ms {
		total += len(m.Data)
	}
	cases := []struct {
		name string
		blob []byte
		f    func([]byte) [][]byte
	}{
		{"framed", acePack(ms), aceUnpackAll},
		{"tar", tarPack(ms), tarUnpackAll},
		{"zipStored", zipPack(ms, zip.Store), zipUnpackAll},
	}
	for _, c := range cases {
		b.Run(c.name, func(b *testing.B) {
			b.SetBytes(int64(total))
			b.ReportAllocs()
			for b.Loop() {
				c.f(c.blob)
			}
		})
	}
}

// The common case on a hit with no warnings and no -MD: only the object is
// wanted. This is where an index earns its keep.
func BenchmarkContainerReadObjectOnly(b *testing.B) {
	ms := entrySet(b)
	// Put the object LAST, the worst case for a format with no index.
	rev := []member{ms[1], ms[2], ms[3], ms[0]}
	n := int64(len(ms[0].Data))

	aceBlob := acePack(rev)
	b.Run("framed/inmem", func(b *testing.B) {
		b.SetBytes(n)
		b.ReportAllocs()
		for b.Loop() {
			aceReadOne(aceBlob, 3)
		}
	})

	p := b.TempDir() + "/entry.ace"
	os.WriteFile(p, aceBlob, 0o644)
	f, _ := os.Open(p)
	defer f.Close()
	b.Run("framed/pread", func(b *testing.B) {
		b.SetBytes(n)
		b.ReportAllocs()
		for b.Loop() {
			if _, err := aceReadOneFromFile(f, 3); err != nil {
				b.Fatal(err)
			}
		}
	})

	tarBlob := tarPack(rev)
	b.Run("tar/scan", func(b *testing.B) {
		b.SetBytes(n)
		b.ReportAllocs()
		for b.Loop() {
			if tarReadOne(tarBlob, "object") == nil {
				b.Fatal("not found")
			}
		}
	})

	zipBlob := zipPack(rev, zip.Store)
	b.Run("zipStored/central-dir", func(b *testing.B) {
		b.SetBytes(n)
		b.ReportAllocs()
		for b.Loop() {
			if zipReadOne(zipBlob, "object") == nil {
				b.Fatal("not found")
			}
		}
	})
}
