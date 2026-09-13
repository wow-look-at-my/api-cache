// binpazerbench measures binpazer (github.com/wow-look-at-my/bin-file-fmt, MIT)
// as the container for a cooked config appended to an executable.
//
// The shape fits the problem exactly. A 16-byte footer sits at the very END of
// the file, carrying the magic `rezapnib` and the absolute offset of the Block
// Index. So a wrapper reads its own last 16 bytes, jumps to the index, and
// seeks to the one or two blocks it needs, without parsing a byte of anything
// else. That is the same access pattern the hand-rolled flat format uses, with
// a real spec, a C implementation and a versioning story behind it.
//
// Appending a container to an executable needs one detail handled: every offset
// in the footer and index is relative to the CONTAINER start, not the file
// start. io.NewSectionReader over the trailer region rebases them, and the
// footer itself is found from the file's own end. Both are measured.
//
// Two payload blocks stand in for a real cooked config:
//
//	type 1  string table   every distinct name, attribute and literal
//	type 2  rules block    the compiled templates, which is what gets executed
//
// The point of separating them is that a wrapper on a cache hit needs only the
// rules block, and never pays for the string table at all.
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"time"

	binpazer "github.com/wow-look-at-my/bin-file-fmt/go"
)

const (
	typeStrings uint16 = 0x4000
	typeRules   uint16 = 0x4001
)

var (
	guidStrings = binpazer.GUID{0xa9, 0x1c, 0x00, 0x01, 0x11, 0x22, 0x43, 0x33, 0x84, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa}
	guidRules   = binpazer.GUID{0xa9, 0x1c, 0x00, 0x02, 0x11, 0x22, 0x43, 0x33, 0x84, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xbb}
	writerGUID  = binpazer.GUID{0xa9, 0x1c, 0xff, 0xff, 0x11, 0x22, 0x43, 0x33, 0x84, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xcc}
)

func med(ds []time.Duration) float64 {
	sort.Slice(ds, func(i, j int) bool { return ds[i] < ds[j] })
	return float64(ds[len(ds)/2].Nanoseconds()) / 1000.0
}

func timeN(n int, f func()) float64 {
	for i := 0; i < 3; i++ {
		f()
	}
	ds := make([]time.Duration, 0, n)
	for i := 0; i < n; i++ {
		t0 := time.Now()
		f()
		ds = append(ds, time.Since(t0))
	}
	return med(ds)
}

// build writes a binpazer container holding the two blocks, with a Block Index
// and the footer.
//
// The destination must be SEEKABLE. Writer.End back-patches file_length in the
// header, and skips that when it cannot seek; the reader's footer probe is
// gated on file_length, so a container written to a bytes.Buffer comes back
// with hasIndex=false and every Find degrades to a full forward walk. A temp
// file is used here for that reason, and it is worth stating plainly: a cooked
// form generated through a pipe silently loses the index fast path.
func build(strTable, rules []byte) []byte {
	tmp, err := os.CreateTemp("", "apcache-binpazer-*")
	if err != nil {
		panic(err)
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	w, err := binpazer.NewWriter(tmp, writerGUID, "api-cache cooked config", []binpazer.TypeDef{
		{TypeID: typeStrings, GUID: guidStrings, Name: "strings"},
		{TypeID: typeRules, GUID: guidRules, Name: "rules"},
	})
	if err != nil {
		panic(err)
	}
	if err := w.Block(typeStrings, 0, strTable); err != nil {
		panic(err)
	}
	if err := w.Block(typeRules, 0, rules); err != nil {
		panic(err)
	}
	// WriteIndex then End writes the Block Index and the 16-byte footer, which
	// is the whole point of using this format here.
	if err := w.WriteIndex(); err != nil {
		panic(err)
	}
	if err := w.End(); err != nil {
		panic(err)
	}
	out, err := os.ReadFile(tmp.Name())
	if err != nil {
		panic(err)
	}
	return out
}

func main() {
	strKiB := flag.Int("strings", 24, "size of the string-table block, KiB")
	rulesB := flag.Int("rules", 2862, "size of the rules block, bytes (default: the measured compiled-template size of github.xml)")
	n := flag.Int("n", 300, "iterations")
	exeHost := flag.String("host", "", "a binary to append the container to; empty means measure the container alone")
	keep := flag.String("out", "", "keep the host+container file at this path, for the C probe to read")
	flag.Parse()

	strTable := make([]byte, *strKiB*1024)
	for i := range strTable {
		strTable[i] = byte('a' + i%26)
	}
	rules := make([]byte, *rulesB)
	for i := range rules {
		rules[i] = byte('{' + i%3)
	}
	container := build(strTable, rules)

	fmt.Printf("# binpazer as a cooked-config trailer\n\n")
	fmt.Printf("- library: `github.com/wow-look-at-my/bin-file-fmt/go` (MIT)\n")
	fmt.Printf("- blocks: string table %d B, rules %d B\n", len(strTable), len(rules))
	fmt.Printf("- container: %d B (%.1f%% overhead over the two payloads)\n",
		len(container), 100*float64(len(container)-len(strTable)-len(rules))/float64(len(strTable)+len(rules)))
	fmt.Printf("- iterations: %d, median reported\n\n", *n)

	fmt.Println("| operation | us | note |")
	fmt.Println("|---|---|---|")

	ra := bytes.NewReader(container)
	sz := int64(len(container))
	// Confirm the index fast path is live before timing anything: without it
	// every Find below silently becomes a forward walk and the numbers mean
	// something else entirely.
	probe, err := binpazer.NewReaderAt(ra, sz)
	if err != nil {
		panic(err)
	}
	if !probe.HasIndex() {
		panic("container carries no block index; the numbers below would measure a forward walk")
	}

	fmt.Printf("| open reader (header + type table + footer) | %.1f | %s |\n",
		timeN(*n, func() {
			r, err := binpazer.NewReaderAt(ra, sz)
			if err != nil {
				panic(err)
			}
			_ = r
		}), "NewReaderAt: what every read below starts with")

	fmt.Printf("| open + FindFirst(rules) + ReadPayload | %.1f | %s |\n",
		timeN(*n, func() {
			r, err := binpazer.NewReaderAt(ra, sz)
			if err != nil {
				panic(err)
			}
			b, err := r.FindFirst(typeRules)
			if err != nil {
				panic(err)
			}
			p, err := r.ReadPayload(b)
			if err != nil {
				panic(err)
			}
			if len(p) != len(rules) {
				panic("short rules block")
			}
		}), "the hot path: only the block the invocation needs")

	fmt.Printf("| open + both blocks | %.1f | %s |\n",
		timeN(*n, func() {
			r, _ := binpazer.NewReaderAt(ra, sz)
			b1, err := r.FindFirst(typeStrings)
			if err != nil {
				panic(err)
			}
			if _, err := r.ReadPayload(b1); err != nil {
				panic(err)
			}
			b2, err := r.FindFirst(typeRules)
			if err != nil {
				panic(err)
			}
			if _, err := r.ReadPayload(b2); err != nil {
				panic(err)
			}
		}), "string table plus rules, for the cold path that needs both")

	// ---- appended to a real executable
	if *exeHost != "" {
		host, err := os.ReadFile(*exeHost)
		if err != nil {
			panic(err)
		}
		combined := append(append([]byte{}, host...), container...)
		// The container's own length must be recoverable from the file's end.
		// binpazer's footer gives the INDEX offset, not the container start, so
		// a host-prefixed file needs one extra u64 of its own: the container
		// length, written after the binpazer footer.
		var tail [8]byte
		binary.LittleEndian.PutUint64(tail[:], uint64(len(container)))
		combined = append(combined, tail[:]...)

		path := os.TempDir() + "/apcache-binpazer-host"
		if *keep != "" {
			path = *keep
		}
		if err := os.WriteFile(path, combined, 0o755); err != nil {
			panic(err)
		}
		if *keep == "" {
			defer os.Remove(path)
		}

		fmt.Printf("\n## appended to `%s` (%d B host + %d B container)\n\n",
			*exeHost, len(host), len(container))
		fmt.Println("| operation | us | note |")
		fmt.Println("|---|---|---|")

		fmt.Printf("| os.Executable-style open + last 8 B + section reader + rules block | %.1f | %s |\n",
			timeN(*n, func() {
				f, err := os.Open(path)
				if err != nil {
					panic(err)
				}
				st, _ := f.Stat()
				var t [8]byte
				if _, err := f.ReadAt(t[:], st.Size()-8); err != nil {
					panic(err)
				}
				clen := int64(binary.LittleEndian.Uint64(t[:]))
				base := st.Size() - 8 - clen
				// A section reader rebases every offset in the footer and the
				// index onto the container, so nothing in binpazer needs to
				// know it is riding on an executable.
				sec := io.NewSectionReader(f, base, clen)
				r, err := binpazer.NewReaderAt(sec, clen)
				if err != nil {
					panic(err)
				}
				b, err := r.FindFirst(typeRules)
				if err != nil {
					panic(err)
				}
				if _, err := r.ReadPayload(b); err != nil {
					panic(err)
				}
				f.Close()
			}), "the whole per-exec cost of a binpazer-cooked binary")

		fmt.Printf("| open + close only | %.1f | %s |\n",
			timeN(*n, func() {
				f, _ := os.Open(path)
				f.Close()
			}), "the syscall floor under the row above")
	}
	fmt.Println()
}
