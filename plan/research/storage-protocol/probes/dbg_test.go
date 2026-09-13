package probes

import (
	"bytes"
	"testing"

	bp "github.com/wow-look-at-my/bin-file-fmt/go"
)

func TestDbg(t *testing.T) {
	ms := entrySet(t)
	var buf bytes.Buffer
	w, err := bp.NewWriterVersion(&buf, guidWriter, "api-cache", typeDefs, bp.VersionMinorCompression)
	if err != nil {
		t.Fatal(err)
	}
	dir := resultDir{}
	for _, m := range ms {
		off, err := w.PutCompressed(tOutput, 0, bp.CodecZstd, m.Data)
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("wrote %s at %d (len %d)", m.Name, off, len(m.Data))
		dir.Entries = append(dir.Entries, dirEntry{Role: m.Name, Offset: off, Size: int64(len(m.Data))})
	}
	doff, err := w.PutJSON(tDirectory, 0, bp.CodecStored, dir)
	t.Logf("dir at %d err=%v", doff, err)
	if err := w.Finish(); err != nil {
		t.Fatal(err)
	}
	blob := buf.Bytes()
	t.Logf("file len %d", len(blob))
	r, err := bp.NewReaderAt(bytes.NewReader(blob), int64(len(blob)))
	if err != nil {
		t.Fatal(err)
	}
	offs, err := r.Find(tDirectory)
	t.Logf("Find(dir)=%v err=%v hasIndex=%v", offs, err, r.HasIndex())
	offs2, err := r.Find(tOutput)
	t.Logf("Find(out)=%v err=%v", offs2, err)
	var got resultDir
	if err := r.DecodeJSONLast(tDirectory, &got); err != nil {
		t.Fatal(err)
	}
	t.Logf("dir read back: %+v", got)
}
