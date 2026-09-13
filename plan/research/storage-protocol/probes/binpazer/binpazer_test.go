// Probe: binpazer (github.com/wow-look-at-my/bin-file-fmt, MIT) as the entry
// container for a multi-output compile result.
//
// The shape under test is the one a compiler cache needs: several content
// blocks (.o, .d, stderr), a small JSON directory block naming them and giving
// each one's offset, a Block Index, and the 16-byte footer that points at the
// index. The reads measured are the two that matter on a hit:
//
//	full   — pull every member back out (the restore path)
//	one    — footer -> index -> seek -> read only the object
//
// The comparison is against the same members in a tar and in the hand-rolled
// ACE1 framing from container_test.go.
package binpazerprobe

import (
	"archive/tar"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"testing"

	bp "github.com/wow-look-at-my/bin-file-fmt/go"
)

// --- corpus (shared shape with the parent probes module) ------------------

type member struct {
	Name string
	Data []byte
}

func load(tb testing.TB, p string) []byte {
	tb.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		tb.Fatalf("corpus file %s is missing: run ../gen-testdata.sh. A probe never "+
			"skips: an absent input is a broken run, not a smaller one. (%v)", p, err)
	}
	return b
}

func entrySet(tb testing.TB) []member {
	tb.Helper()
	obj := load(tb, "../testdata/mid.o")
	dep := load(tb, "../testdata/mid.d")
	stderr := bytes.Repeat([]byte("mid.cc:41:9: warning: unused variable 'x' [-Wunused-variable]\n"), 30)
	gcno := obj[:40<<10]
	return []member{
		{"object", obj},
		{"dependency", dep},
		{"stderr", stderr},
		{"coverage", gcno},
	}
}

// --- the two baselines, duplicated here so one CI run compares all three ---

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
		e[0] = byte(i)
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

func aceReadOneFromFile(f io.ReaderAt, idx int) ([]byte, error) {
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

// BenchmarkBaselineReadOne is tar and ACE1 on the same inputs in the same run,
// so the binpazer numbers below have a same-machine comparison.
func BenchmarkBaselineReadOne(b *testing.B) {
	ms := entrySet(b)
	rev := []member{ms[1], ms[2], ms[3], ms[0]}
	n := int64(len(ms[0].Data))

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

	aceBlob := acePack(rev)
	p := b.TempDir() + "/entry.ace"
	if err := os.WriteFile(p, aceBlob, 0o644); err != nil {
		b.Fatal(err)
	}
	f, err := os.Open(p)
	if err != nil {
		b.Fatal(err)
	}
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
}

// Block type ids. User types ascend from 1.
const (
	tOutput    uint16 = 1 // one compiler output: raw bytes, optionally compressed
	tDirectory uint16 = 2 // JSON: which output is which, and where it sits
)

var (
	guidOutput = bp.GUID{0x61, 0x70, 0x69, 0x63, 0x61, 0x63, 0x68, 0x65,
		0x00, 0x01, 0, 0, 0, 0, 0, 1}
	guidDirectory = bp.GUID{0x61, 0x70, 0x69, 0x63, 0x61, 0x63, 0x68, 0x65,
		0x00, 0x01, 0, 0, 0, 0, 0, 2}
	guidWriter = bp.GUID{0x61, 0x70, 0x69, 0x63, 0x61, 0x63, 0x68, 0x65,
		0x00, 0x00, 0, 0, 0, 0, 0, 0}
)

var typeDefs = []bp.TypeDef{
	{TypeID: tOutput, GUID: guidOutput, Name: "CompilerOutput"},
	{TypeID: tDirectory, GUID: guidDirectory, Name: "ResultDirectory"},
}

// dirEntry is what the directory block records per member. binpazer's block
// header carries no name, so the name lives here, next to the offset the Block
// Index would otherwise only give per TYPE id.
type dirEntry struct {
	Role   string `json:"role"` // object | dependency | stderr | dwo | coverage
	Offset uint64 `json:"off"`  // absolute file offset of the block header
	Size   int64  `json:"size"` // decoded size
}

type resultDir struct {
	Entries []dirEntry `json:"entries"`
}

// seekBuf is an in-memory io.Writer that is also an io.Seeker, which binpazer
// needs: End back-patches file_length (and version_minor) at fixed offsets, and
// a writer with no seeker leaves file_length at the streaming sentinel. A
// reader then cannot locate the footer, so the Block Index is unreachable AND
// the linear-walk fallback runs into the 16-byte footer and reports it as a
// corrupt block. A plain bytes.Buffer is not enough. See container-format.md.
type seekBuf struct {
	b   []byte
	pos int
}

func (s *seekBuf) Write(p []byte) (int, error) {
	if need := s.pos + len(p); need > len(s.b) {
		s.b = append(s.b, make([]byte, need-len(s.b))...)
	}
	copy(s.b[s.pos:], p)
	s.pos += len(p)
	return len(p), nil
}

func (s *seekBuf) Seek(off int64, whence int) (int64, error) {
	switch whence {
	case io.SeekStart:
		s.pos = int(off)
	case io.SeekCurrent:
		s.pos += int(off)
	case io.SeekEnd:
		s.pos = len(s.b) + int(off)
	}
	return int64(s.pos), nil
}

// bpPack writes one result. flags decides CRC and compression per block.
func bpPack(ms []member, codec uint16, crc bool) ([]byte, error) {
	buf := &seekBuf{}
	w, err := bp.NewWriterVersion(buf, guidWriter, "api-cache", typeDefs, bp.VersionMinorCompression)
	if err != nil {
		return nil, err
	}
	flags := uint16(0)
	if crc {
		flags |= bp.FlagHasCRC
	}
	dir := resultDir{}
	for _, m := range ms {
		var off uint64
		if codec == bp.CodecStored {
			off, err = w.Put(tOutput, flags, m.Data)
		} else {
			off, err = w.PutCompressed(tOutput, flags, codec, m.Data)
		}
		if err != nil {
			return nil, err
		}
		dir.Entries = append(dir.Entries, dirEntry{Role: m.Name, Offset: off, Size: int64(len(m.Data))})
	}
	if _, err := w.PutJSON(tDirectory, flags, bp.CodecStored, dir); err != nil {
		return nil, err
	}
	// Finish writes the Block Index, the footer, and back-patches file_length.
	if err := w.Finish(); err != nil {
		return nil, err
	}
	return buf.b, nil
}

// bpPackStreaming is the same file written through a non-seekable writer, the
// shape an HTTP upload takes. Kept so the gap is measured, not asserted.
func bpPackStreaming(ms []member, codec uint16) ([]byte, error) {
	var buf bytes.Buffer
	w, err := bp.NewWriterVersion(&buf, guidWriter, "api-cache", typeDefs, bp.VersionMinorCompression)
	if err != nil {
		return nil, err
	}
	dir := resultDir{}
	for _, m := range ms {
		off, err := w.PutCompressed(tOutput, 0, codec, m.Data)
		if err != nil {
			return nil, err
		}
		dir.Entries = append(dir.Entries, dirEntry{Role: m.Name, Offset: off, Size: int64(len(m.Data))})
	}
	if _, err := w.PutJSON(tDirectory, 0, bp.CodecStored, dir); err != nil {
		return nil, err
	}
	if err := w.Finish(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// TestBinpazerStreamingWriterLosesIndex records what a non-seekable writer
// costs: file_length stays 0xFFFF_FFFF_FFFF_FFFF, so the reader never finds the
// footer, Find falls back to a linear walk, and the walk reads the footer as a
// block header.
func TestBinpazerStreamingWriterLosesIndex(t *testing.T) {
	ms := entrySet(t)
	blob, err := bpPackStreaming(ms, bp.CodecZstd)
	if err != nil {
		t.Fatal(err)
	}
	r, err := bp.NewReaderAt(bytes.NewReader(blob), int64(len(blob)))
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("streamed file: len=%d hasIndex=%v", len(blob), r.HasIndex())
	offs, ferr := r.Find(tDirectory)
	t.Logf("Find(directory) -> %v, err=%v", offs, ferr)

	seek, err := bpPack(ms, bp.CodecZstd, false)
	if err != nil {
		t.Fatal(err)
	}
	r2, err := bp.NewReaderAt(bytes.NewReader(seek), int64(len(seek)))
	if err != nil {
		t.Fatal(err)
	}
	offs2, err := r2.Find(tDirectory)
	t.Logf("seekable file: len=%d hasIndex=%v Find(directory) -> %v err=%v",
		len(seek), r2.HasIndex(), offs2, err)
}

// bpReadAll pulls every output block back out: the restore path.
func bpReadAll(blob []byte) ([][]byte, error) {
	r, err := bp.NewReaderAt(bytes.NewReader(blob), int64(len(blob)))
	if err != nil {
		return nil, err
	}
	var dir resultDir
	if err := r.DecodeJSONLast(tDirectory, &dir); err != nil {
		return nil, err
	}
	out := make([][]byte, 0, len(dir.Entries))
	for _, e := range dir.Entries {
		rd, _, err := r.OpenAt(e.Offset, tOutput)
		if err != nil {
			return nil, err
		}
		b, err := io.ReadAll(rd)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, nil
}

// bpReadOne is the hit path when only the object is wanted: footer -> index ->
// directory -> one seek -> one payload.
func bpReadOne(blob []byte, role string) ([]byte, error) {
	r, err := bp.NewReaderAt(bytes.NewReader(blob), int64(len(blob)))
	if err != nil {
		return nil, err
	}
	var dir resultDir
	if err := r.DecodeJSONLast(tDirectory, &dir); err != nil {
		return nil, err
	}
	for _, e := range dir.Entries {
		if e.Role != role {
			continue
		}
		rd, _, err := r.OpenAt(e.Offset, tOutput)
		if err != nil {
			return nil, err
		}
		return io.ReadAll(rd)
	}
	return nil, fmt.Errorf("role %q not in directory", role)
}

// bpReadOneSized is bpReadOne with the allocation sized from the directory
// instead of grown by io.ReadAll. The directory already carries the decoded
// size, so a real implementation would never pay ReadAll's doubling.
func bpReadOneSized(blob []byte, role string) ([]byte, error) {
	r, err := bp.NewReaderAt(bytes.NewReader(blob), int64(len(blob)))
	if err != nil {
		return nil, err
	}
	var dir resultDir
	if err := r.DecodeJSONLast(tDirectory, &dir); err != nil {
		return nil, err
	}
	for _, e := range dir.Entries {
		if e.Role != role {
			continue
		}
		rd, _, err := r.OpenAt(e.Offset, tOutput)
		if err != nil {
			return nil, err
		}
		out := make([]byte, e.Size)
		if _, err := io.ReadFull(rd, out); err != nil {
			return nil, err
		}
		return out, nil
	}
	return nil, fmt.Errorf("role %q not in directory", role)
}

func TestBinpazerRoundTrip(t *testing.T) {
	ms := entrySet(t)
	for _, c := range []struct {
		name  string
		codec uint16
		crc   bool
	}{
		{"stored", bp.CodecStored, false},
		{"stored+crc", bp.CodecStored, true},
		{"zstd", bp.CodecZstd, false},
		{"zstd+crc", bp.CodecZstd, true},
		{"lz4", bp.CodecLZ4, false},
	} {
		blob, err := bpPack(ms, c.codec, c.crc)
		if err != nil {
			t.Fatalf("%s: pack: %v", c.name, err)
		}
		got, err := bpReadAll(blob)
		if err != nil {
			t.Fatalf("%s: read: %v", c.name, err)
		}
		if len(got) != len(ms) {
			t.Fatalf("%s: got %d members, want %d", c.name, len(got), len(ms))
		}
		for i := range ms {
			if !bytes.Equal(got[i], ms[i].Data) {
				t.Fatalf("%s: member %d differs", c.name, i)
			}
		}
		one, err := bpReadOne(blob, "object")
		if err != nil || !bytes.Equal(one, ms[0].Data) {
			t.Fatalf("%s: read-one: %v", c.name, err)
		}
		raw := 0
		for _, m := range ms {
			raw += len(m.Data)
		}
		t.Logf("%-12s file=%d raw=%d overhead=%+d (%.3f%%)",
			c.name, len(blob), raw, len(blob)-raw, 100*float64(len(blob)-raw)/float64(raw))
	}
}

func BenchmarkBinpazerPack(b *testing.B) {
	ms := entrySet(b)
	total := 0
	for _, m := range ms {
		total += len(m.Data)
	}
	for _, c := range []struct {
		name  string
		codec uint16
		crc   bool
	}{
		{"stored", bp.CodecStored, false},
		{"stored+crc", bp.CodecStored, true},
		{"zstd", bp.CodecZstd, false},
		{"lz4", bp.CodecLZ4, false},
	} {
		b.Run(c.name, func(b *testing.B) {
			b.SetBytes(int64(total))
			b.ReportAllocs()
			for b.Loop() {
				if _, err := bpPack(ms, c.codec, c.crc); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

func BenchmarkBinpazerReadAll(b *testing.B) {
	ms := entrySet(b)
	total := 0
	for _, m := range ms {
		total += len(m.Data)
	}
	for _, c := range []struct {
		name  string
		codec uint16
		crc   bool
	}{
		{"stored", bp.CodecStored, false},
		{"stored+crc", bp.CodecStored, true},
		{"zstd", bp.CodecZstd, false},
		{"lz4", bp.CodecLZ4, false},
	} {
		blob, err := bpPack(ms, c.codec, c.crc)
		if err != nil {
			b.Fatal(err)
		}
		b.Run(c.name, func(b *testing.B) {
			b.SetBytes(int64(total))
			b.ReportAllocs()
			for b.Loop() {
				if _, err := bpReadAll(blob); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Read only the object, with the object written LAST so a format with no index
// pays its worst case. Compare against tar/scan and framed/pread in
// container_test.go.
func BenchmarkBinpazerReadOne(b *testing.B) {
	ms := entrySet(b)
	rev := []member{ms[1], ms[2], ms[3], ms[0]}
	n := int64(len(ms[0].Data))
	for _, c := range []struct {
		name  string
		codec uint16
		crc   bool
	}{
		{"stored", bp.CodecStored, false},
		{"stored+crc", bp.CodecStored, true},
		{"zstd", bp.CodecZstd, false},
		{"lz4", bp.CodecLZ4, false},
	} {
		blob, err := bpPack(rev, c.codec, c.crc)
		if err != nil {
			b.Fatal(err)
		}
		b.Run(c.name, func(b *testing.B) {
			b.SetBytes(n)
			b.ReportAllocs()
			for b.Loop() {
				if _, err := bpReadOne(blob, "object"); err != nil {
					b.Fatal(err)
				}
			}
		})
	}

	for _, c := range []struct {
		name  string
		codec uint16
	}{
		{"stored", bp.CodecStored},
		{"zstd", bp.CodecZstd},
		{"lz4", bp.CodecLZ4},
	} {
		blob, err := bpPack(rev, c.codec, false)
		if err != nil {
			b.Fatal(err)
		}
		b.Run("sized/"+c.name, func(b *testing.B) {
			b.SetBytes(n)
			b.ReportAllocs()
			for b.Loop() {
				if _, err := bpReadOneSized(blob, "object"); err != nil {
					b.Fatal(err)
				}
			}
		})
	}

	// From a real file on disk rather than a []byte, so the syscalls are real.
	blob, err := bpPack(rev, bp.CodecStored, false)
	if err != nil {
		b.Fatal(err)
	}
	p := b.TempDir() + "/entry.bp"
	if err := os.WriteFile(p, blob, 0o644); err != nil {
		b.Fatal(err)
	}
	f, err := os.Open(p)
	if err != nil {
		b.Fatal(err)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		b.Fatal(err)
	}
	b.Run("stored/file", func(b *testing.B) {
		b.SetBytes(n)
		b.ReportAllocs()
		for b.Loop() {
			r, err := bp.NewReaderAt(f, st.Size())
			if err != nil {
				b.Fatal(err)
			}
			var dir resultDir
			if err := r.DecodeJSONLast(tDirectory, &dir); err != nil {
				b.Fatal(err)
			}
			var off uint64
			for _, e := range dir.Entries {
				if e.Role == "object" {
					off = e.Offset
				}
			}
			rd, _, err := r.OpenAt(off, tOutput)
			if err != nil {
				b.Fatal(err)
			}
			if _, err := io.ReadAll(rd); err != nil {
				b.Fatal(err)
			}
		}
	})
}

var _ = json.Marshal
