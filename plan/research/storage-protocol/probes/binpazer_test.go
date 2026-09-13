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
package probes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"testing"

	bp "github.com/wow-look-at-my/bin-file-fmt/go"
)

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

// bpPack writes one result. flags decides CRC and compression per block.
func bpPack(ms []member, codec uint16, crc bool) ([]byte, error) {
	var buf bytes.Buffer
	w, err := bp.NewWriterVersion(&buf, guidWriter, "api-cache", typeDefs, bp.VersionMinorCompression)
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
	return buf.Bytes(), nil
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

	// From a real file on disk rather than a []byte, so the syscalls are real.
	blob, _ := bpPack(rev, bp.CodecStored, false)
	p := b.TempDir() + "/entry.bp"
	os.WriteFile(p, blob, 0o644)
	f, _ := os.Open(p)
	defer f.Close()
	st, _ := f.Stat()
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
