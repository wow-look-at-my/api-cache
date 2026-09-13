// Probe: compression of real compiler outputs.
//
// Inputs are built by gen-testdata.sh from real gcc/g++ -g -O2 output, so the
// DWARF is real DWARF and the ratios are not the ratios of a synthetic buffer.
package probes

import (
	"bytes"
	"compress/flate"
	"fmt"
	"io"
	"os"
	"testing"

	"github.com/klauspost/compress/s2"
	"github.com/klauspost/compress/zstd"
	"github.com/pierrec/lz4/v4"
)

var corpus = []string{
	"testdata/small.o",  // C, -g -O2, ~10 KiB
	"testdata/mid.o",    // C++ with <iostream>, -g -O2, ~515 KiB
	"testdata/big_g1.o", // C++ template-heavy, -g1 -O2, ~1.4 MiB
	"testdata/big.o",    // C++ template-heavy, -g -O2, ~4.8 MiB
	"testdata/mid.d",    // dependency file, ~9 KiB of text
}

func load(tb testing.TB, p string) []byte {
	tb.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		tb.Skipf("missing %s: run gen-testdata.sh", p)
	}
	return b
}

func zstdEnc(level zstd.EncoderLevel) *zstd.Encoder {
	e, _ := zstd.NewWriter(nil, zstd.WithEncoderLevel(level), zstd.WithEncoderConcurrency(1))
	return e
}

// TestRatios prints a ratio table for every codec over every corpus file.
// It is a report, not an assertion.
func TestRatios(t *testing.T) {
	dec, _ := zstd.NewReader(nil, zstd.WithDecoderConcurrency(1))
	defer dec.Close()
	fmt.Printf("%-20s %10s %10s %8s %10s %8s %10s %8s %10s %8s %10s %8s %10s %8s\n",
		"file", "raw", "lz4", "ratio", "s2", "ratio", "s2-better", "ratio", "zstd-1", "ratio", "zstd-3", "ratio", "zstd-9", "ratio")
	for _, p := range corpus {
		src := load(t, p)
		var row []any
		row = append(row, p, len(src))

		var lz4buf bytes.Buffer
		w := lz4.NewWriter(&lz4buf)
		w.Write(src)
		w.Close()
		row = append(row, lz4buf.Len(), fmt.Sprintf("%.3f", float64(lz4buf.Len())/float64(len(src))))

		s2b := s2.Encode(nil, src)
		row = append(row, len(s2b), fmt.Sprintf("%.3f", float64(len(s2b))/float64(len(src))))
		s2bb := s2.EncodeBetter(nil, src)
		row = append(row, len(s2bb), fmt.Sprintf("%.3f", float64(len(s2bb))/float64(len(src))))

		for _, lv := range []zstd.EncoderLevel{zstd.SpeedFastest, zstd.SpeedDefault, zstd.SpeedBestCompression} {
			e := zstdEnc(lv)
			out := e.EncodeAll(src, nil)
			e.Close()
			row = append(row, len(out), fmt.Sprintf("%.3f", float64(len(out))/float64(len(src))))
		}
		fmt.Printf("%-20s %10d %10d %8s %10d %8s %10d %8s %10d %8s %10d %8s %10d %8s\n", row...)
	}
}

func benchEncode(b *testing.B, path string, enc func([]byte) int) {
	src := load(b, path)
	b.SetBytes(int64(len(src)))
	b.ReportAllocs()
	var out int
	for b.Loop() {
		out = enc(src)
	}
	b.ReportMetric(float64(out)/float64(len(src)), "ratio")
}

func BenchmarkEncode(b *testing.B) {
	for _, p := range corpus {
		b.Run("lz4/"+p, func(b *testing.B) {
			var buf bytes.Buffer
			benchEncode(b, p, func(src []byte) int {
				buf.Reset()
				w := lz4.NewWriter(&buf)
				w.Write(src)
				w.Close()
				return buf.Len()
			})
		})
		for name, lv := range map[string]zstd.EncoderLevel{
			"zstd1": zstd.SpeedFastest, "zstd3": zstd.SpeedDefault, "zstd9": zstd.SpeedBestCompression,
		} {
			e := zstdEnc(lv)
			b.Run(name+"/"+p, func(b *testing.B) {
				benchEncode(b, p, func(src []byte) int { return len(e.EncodeAll(src, nil)) })
			})
			e.Close()
		}
		b.Run("s2/"+p, func(b *testing.B) {
			var dst []byte
			benchEncode(b, p, func(src []byte) int {
				dst = s2.Encode(dst[:0], src)
				return len(dst)
			})
		})
		b.Run("s2better/"+p, func(b *testing.B) {
			var dst []byte
			benchEncode(b, p, func(src []byte) int {
				dst = s2.EncodeBetter(dst[:0], src)
				return len(dst)
			})
		})
		b.Run("flate6/"+p, func(b *testing.B) {
			var buf bytes.Buffer
			benchEncode(b, p, func(src []byte) int {
				buf.Reset()
				w, _ := flate.NewWriter(&buf, 6)
				w.Write(src)
				w.Close()
				return buf.Len()
			})
		})
	}
}

func BenchmarkDecode(b *testing.B) {
	dec, _ := zstd.NewReader(nil, zstd.WithDecoderConcurrency(1))
	defer dec.Close()
	for _, p := range corpus {
		src := load(b, p)

		var l bytes.Buffer
		w := lz4.NewWriter(&l)
		w.Write(src)
		w.Close()
		lz4b := l.Bytes()
		b.Run("lz4/"+p, func(b *testing.B) {
			b.SetBytes(int64(len(src)))
			b.ReportAllocs()
			dst := make([]byte, len(src))
			r := lz4.NewReader(nil)
			for b.Loop() {
				r.Reset(bytes.NewReader(lz4b))
				if _, err := io.ReadFull(r, dst); err != nil {
					b.Fatal(err)
				}
			}
		})

		s2enc := s2.Encode(nil, src)
		b.Run("s2/"+p, func(b *testing.B) {
			b.SetBytes(int64(len(src)))
			b.ReportAllocs()
			dst := make([]byte, len(src))
			for b.Loop() {
				if _, err := s2.Decode(dst, s2enc); err != nil {
					b.Fatal(err)
				}
			}
		})

		for name, lv := range map[string]zstd.EncoderLevel{
			"zstd1": zstd.SpeedFastest, "zstd3": zstd.SpeedDefault, "zstd9": zstd.SpeedBestCompression,
		} {
			e := zstdEnc(lv)
			enc := e.EncodeAll(src, nil)
			e.Close()
			b.Run(name+"/"+p, func(b *testing.B) {
				b.SetBytes(int64(len(src)))
				b.ReportAllocs()
				var dst []byte
				for b.Loop() {
					var err error
					dst, err = dec.DecodeAll(enc, dst[:0])
					if err != nil {
						b.Fatal(err)
					}
				}
			})
		}
	}
}

// Memcpy baseline: the "no compression" restore path is bounded by this.
func BenchmarkMemcpyBaseline(b *testing.B) {
	for _, p := range corpus {
		src := load(b, p)
		dst := make([]byte, len(src))
		b.Run(p, func(b *testing.B) {
			b.SetBytes(int64(len(src)))
			for b.Loop() {
				copy(dst, src)
			}
		})
	}
}

// Codec construction is not free. A container that builds a fresh decoder per
// block (binpazer's Codec interface does: NewReader(r) per payload) pays this
// on every lookup unless the codec is pooled.
func BenchmarkCodecConstruct(b *testing.B) {
	b.Run("zstd.NewReader", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			r, err := zstd.NewReader(nil, zstd.WithDecoderConcurrency(1))
			if err != nil {
				b.Fatal(err)
			}
			r.Close()
		}
	})
	b.Run("zstd.NewReader/default-concurrency", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			r, err := zstd.NewReader(nil)
			if err != nil {
				b.Fatal(err)
			}
			r.Close()
		}
	})
	b.Run("zstd.NewWriter", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			w, err := zstd.NewWriter(nil, zstd.WithEncoderConcurrency(1))
			if err != nil {
				b.Fatal(err)
			}
			w.Close()
		}
	})
	b.Run("lz4.NewReader", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			_ = lz4.NewReader(nil)
		}
	})
	b.Run("lz4.NewWriter", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			_ = lz4.NewWriter(nil)
		}
	})
}

// Streaming decode vs one-shot decode of the same bytes. A container whose
// codec layer is io.Reader-shaped forces the streaming path; a cache entry
// whose decoded size is known can use the one-shot path instead.
func BenchmarkDecodeStreamVsOneShot(b *testing.B) {
	src := load(b, "testdata/mid.o")
	e := zstdEnc(zstd.SpeedDefault)
	enc := e.EncodeAll(src, nil)
	e.Close()

	b.Run("zstd/DecodeAll/pooled", func(b *testing.B) {
		d, _ := zstd.NewReader(nil, zstd.WithDecoderConcurrency(1))
		defer d.Close()
		dst := make([]byte, 0, len(src))
		b.SetBytes(int64(len(src)))
		b.ReportAllocs()
		for b.Loop() {
			if _, err := d.DecodeAll(enc, dst[:0]); err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("zstd/NewReader-per-call/stream", func(b *testing.B) {
		dst := make([]byte, len(src))
		b.SetBytes(int64(len(src)))
		b.ReportAllocs()
		for b.Loop() {
			r, err := zstd.NewReader(bytes.NewReader(enc), zstd.WithDecoderConcurrency(1))
			if err != nil {
				b.Fatal(err)
			}
			if _, err := io.ReadFull(r, dst); err != nil {
				b.Fatal(err)
			}
			r.Close()
		}
	})

	var l bytes.Buffer
	w := lz4.NewWriter(&l)
	w.Write(src)
	w.Close()
	lz4b := l.Bytes()
	b.Run("lz4/NewReader-per-call/stream", func(b *testing.B) {
		dst := make([]byte, len(src))
		b.SetBytes(int64(len(src)))
		b.ReportAllocs()
		for b.Loop() {
			r := lz4.NewReader(bytes.NewReader(lz4b))
			if _, err := io.ReadFull(r, dst); err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("lz4/Reset/stream", func(b *testing.B) {
		dst := make([]byte, len(src))
		r := lz4.NewReader(nil)
		b.SetBytes(int64(len(src)))
		b.ReportAllocs()
		for b.Loop() {
			r.Reset(bytes.NewReader(lz4b))
			if _, err := io.ReadFull(r, dst); err != nil {
				b.Fatal(err)
			}
		}
	})
}
