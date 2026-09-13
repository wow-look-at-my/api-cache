// xmlbench measures what a declarative-XML config costs a process that must
// load it on every single exec.
//
// The stages are separated deliberately, because each one is a different
// mitigation target:
//
//	read      the file into memory
//	parse     encoding/xml tokenizing into api-dsl's order-preserving DOM
//	compile   every placeholder element into Go template SOURCE
//	tparse    text/template.Parse of that source, with the func map attached
//	exec      executing the parsed templates against a small data context
//
// It then measures three "cooked" alternatives that skip earlier stages:
//
//	gob       encoding/gob of a mirror of the DOM
//	flat      a hand-rolled string-table + node-array binary format
//	cooked    the compiled TEMPLATE SOURCES alone, in the flat format
//
// Every figure is a per-operation median over many iterations, reported in
// microseconds, so it can be compared against the ~1 ms process-exec floor
// measured separately.
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/gob"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/template"
	"time"

	apidsl "github.com/wow-look-at-my/api-dsl"
)

// ---------------------------------------------------------------- timing

type stat struct {
	label string
	us    []float64
	note  string
}

func (s *stat) add(d time.Duration) { s.us = append(s.us, float64(d.Nanoseconds())/1000.0) }

func (s *stat) row() string {
	sort.Float64s(s.us)
	var sum float64
	for _, v := range s.us {
		sum += v
	}
	n := len(s.us)
	return fmt.Sprintf("| %s | %.1f | %.1f | %.1f | %.1f | %s |",
		s.label, s.us[0], s.us[n/2], s.us[int(float64(n)*0.90)], sum/float64(n), s.note)
}

// bench runs f n times, timing each call.
func bench(label string, n int, note string, f func()) *stat {
	s := &stat{label: label, note: note}
	for i := 0; i < 5; i++ { // warm up: first-call allocation is not the steady state
		f()
	}
	for i := 0; i < n; i++ {
		t0 := time.Now()
		f()
		s.add(time.Since(t0))
	}
	return s
}

// ---------------------------------------------------------------- compile walk

// compileAll walks the whole DOM and compiles the content of every element
// that holds a placeholder, exactly as a consumer's loader does. It returns
// the compiled template sources so a later stage can parse them.
func compileAll(n *apidsl.Node, out *[]string) {
	src, err := apidsl.CompileContent(n)
	if err == nil && strings.Contains(src, "{{") {
		*out = append(*out, src)
	}
	for _, c := range n.Children() {
		compileAll(c, out)
	}
}

// ---------------------------------------------------------------- flat format

// The flat format is the cheapest decode a cooked form can plausibly have:
// one length-prefixed string blob, then a node array of fixed-width records
// that index into it. Decoding is a single pass with no per-node allocation
// beyond the two slices, and every string is a sub-slice of the mmap-able
// blob rather than a copy.
//
//	u32 stringCount, then for each: u32 offset, u32 length   (into blob)
//	u32 blobLen, blob bytes
//	u32 nodeCount, then for each: u32 nameIdx, u32 attrCount, u32 contentCount
//	    attrs:    u32 nameIdx, u32 valIdx
//	    content:  u32 kind(0=text,1=elem), u32 idx (textIdx or nodeIdx)

type flatDoc struct {
	blob    []byte
	strOff  []uint32
	strLen  []uint32
	nodes   []flatNode
	strings []string // resolved lazily; measured both ways
}

type flatNode struct {
	name    uint32
	attrs   []uint32 // pairs
	content []uint32 // pairs
}

type flatBuilder struct {
	buf     bytes.Buffer
	strIdx  map[string]uint32
	strList []string
	nodes   []flatNode
}

func (b *flatBuilder) str(s string) uint32 {
	if i, ok := b.strIdx[s]; ok {
		return i
	}
	i := uint32(len(b.strList))
	b.strList = append(b.strList, s)
	b.strIdx[s] = i
	return i
}

func (b *flatBuilder) node(m *mirrorNode) uint32 {
	idx := uint32(len(b.nodes))
	b.nodes = append(b.nodes, flatNode{})
	n := flatNode{name: b.str(m.Name)}
	for _, a := range m.Attrs {
		n.attrs = append(n.attrs, b.str(a.Name), b.str(a.Value))
	}
	for _, it := range m.Content {
		if it.Elem == nil {
			n.content = append(n.content, 0, b.str(it.Text))
		} else {
			child := b.node(it.Elem)
			n.content = append(n.content, 1, child)
		}
	}
	b.nodes[idx] = n
	return idx
}

func flatEncode(m *mirrorNode) []byte {
	b := &flatBuilder{strIdx: map[string]uint32{}}
	b.node(m)

	var blob bytes.Buffer
	offs := make([]uint32, len(b.strList))
	lens := make([]uint32, len(b.strList))
	for i, s := range b.strList {
		offs[i] = uint32(blob.Len())
		lens[i] = uint32(len(s))
		blob.WriteString(s)
	}

	var out bytes.Buffer
	w32 := func(v uint32) { var t [4]byte; binary.LittleEndian.PutUint32(t[:], v); out.Write(t[:]) }
	w32(uint32(len(b.strList)))
	for i := range b.strList {
		w32(offs[i])
		w32(lens[i])
	}
	w32(uint32(blob.Len()))
	out.Write(blob.Bytes())
	w32(uint32(len(b.nodes)))
	for _, n := range b.nodes {
		w32(n.name)
		w32(uint32(len(n.attrs)))
		w32(uint32(len(n.content)))
		for _, v := range n.attrs {
			w32(v)
		}
		for _, v := range n.content {
			w32(v)
		}
	}
	return out.Bytes()
}

// flatDecode is the decode a cooked binary pays at startup: two slice header
// reads and one pass over the node array. No string is copied; the blob stays
// as one allocation and every name is a sub-slice of it.
func flatDecode(p []byte) *flatDoc {
	pos := 0
	r32 := func() uint32 { v := binary.LittleEndian.Uint32(p[pos:]); pos += 4; return v }
	sc := r32()
	d := &flatDoc{strOff: make([]uint32, sc), strLen: make([]uint32, sc)}
	for i := uint32(0); i < sc; i++ {
		d.strOff[i] = r32()
		d.strLen[i] = r32()
	}
	bl := r32()
	d.blob = p[pos : pos+int(bl)]
	pos += int(bl)
	nc := r32()
	d.nodes = make([]flatNode, nc)
	for i := uint32(0); i < nc; i++ {
		name := r32()
		na := r32()
		ncnt := r32()
		n := flatNode{name: name}
		if na > 0 {
			n.attrs = make([]uint32, na)
			for j := uint32(0); j < na; j++ {
				n.attrs[j] = r32()
			}
		}
		if ncnt > 0 {
			n.content = make([]uint32, ncnt)
			for j := uint32(0); j < ncnt; j++ {
				n.content[j] = r32()
			}
		}
		d.nodes[i] = n
	}
	return d
}

// ---------------------------------------------------------------- cooked templates

// cookedEncode stores only the compiled template SOURCES, length-prefixed.
// This is what a cooked binary would actually carry: the XML is gone, and so
// is the DOM. What remains is still Go template source, which text/template
// must still Parse, and that parse is the number the cooked form does NOT
// remove.
func cookedEncode(src []string) []byte {
	var out bytes.Buffer
	var t [4]byte
	binary.LittleEndian.PutUint32(t[:], uint32(len(src)))
	out.Write(t[:])
	for _, s := range src {
		binary.LittleEndian.PutUint32(t[:], uint32(len(s)))
		out.Write(t[:])
		out.WriteString(s)
	}
	return out.Bytes()
}

func cookedDecode(p []byte) []string {
	pos := 0
	r32 := func() uint32 { v := binary.LittleEndian.Uint32(p[pos:]); pos += 4; return v }
	n := r32()
	out := make([]string, n)
	for i := uint32(0); i < n; i++ {
		l := int(r32())
		out[i] = string(p[pos : pos+l]) // a copy, so the caller may drop the buffer
		pos += l
	}
	return out
}

// ---------------------------------------------------------------- main

func main() {
	path := flag.String("f", "/home/user/api-cli/samples/github/github.xml", "XML config to load")
	n := flag.Int("n", 200, "iterations per stage")
	flag.Parse()

	raw, err := os.ReadFile(*path)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// One reference pass, to size everything and to feed the later stages.
	refDOM, err := apidsl.ParseDOM(raw)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ParseDOM:", err)
		os.Exit(1)
	}
	var refSrc []string
	compileAll(refDOM, &refSrc)
	refMirror := mirror(refDOM)

	var gobBuf bytes.Buffer
	if err := gob.NewEncoder(&gobBuf).Encode(refMirror); err != nil {
		fmt.Fprintln(os.Stderr, "gob encode:", err)
		os.Exit(1)
	}
	gobBytes := gobBuf.Bytes()
	flatBytes := flatEncode(refMirror)
	cookedBytes := cookedEncode(refSrc)

	// A small data context, shaped like a leaf's, for the execute stage.
	data := map[string]any{
		"arg":  map[string]any{"owner": "wow-look-at-my", "repo": "api-cache", "n": "20"},
		"flag": map[string]any{"state": "open", "json": "true"},
		"var":  map[string]any{"base": "https://api.github.com"},
		"env":  map[string]any{"GITHUB_TOKEN": "x"},
	}

	// Cap the executed set so one pathological template does not dominate.
	execSrc := refSrc
	if len(execSrc) > 20 {
		execSrc = execSrc[:20]
	}

	fmt.Printf("# xml load cost\n\n")
	fmt.Printf("- file: `%s`\n", *path)
	fmt.Printf("- size: %d bytes, %d lines\n", len(raw), bytes.Count(raw, []byte("\n"))+1)
	fmt.Printf("- DOM nodes: %d\n", countNodes(refMirror))
	fmt.Printf("- compiled templates (elements whose content holds a placeholder): %d\n", len(refSrc))
	fmt.Printf("- iterations per stage: %d\n\n", *n)
	fmt.Printf("- serialized sizes: xml %d B, gob %d B, flat %d B, cooked-templates %d B\n\n",
		len(raw), len(gobBytes), len(flatBytes), len(cookedBytes))

	fmt.Println("| stage | min us | p50 us | p90 us | mean us | note |")
	fmt.Println("|---|---|---|---|---|---|")

	var rows []*stat

	rows = append(rows, bench("read file", *n, "os.ReadFile, warm page cache", func() {
		b, _ := os.ReadFile(*path)
		_ = b
	}))

	rows = append(rows, bench("parse (ParseDOM)", *n, "encoding/xml into the DOM, file already in memory", func() {
		d, e := apidsl.ParseDOM(raw)
		if e != nil {
			panic(e)
		}
		_ = d
	}))

	rows = append(rows, bench("parse + compile", *n, "ParseDOM then CompileContent over every element", func() {
		d, _ := apidsl.ParseDOM(raw)
		var s []string
		compileAll(d, &s)
	}))

	// The func map is what every template must be given before it parses.
	rows = append(rows, bench("apidsl.FuncMap()", *n, "sprig TxtFuncMap plus the language's own helpers", func() {
		fm := apidsl.FuncMap()
		_ = fm
	}))

	fm := apidsl.FuncMap()
	rows = append(rows, bench("template.Parse x20", *n, "text/template.Parse of 20 compiled sources, func map attached", func() {
		for _, s := range execSrc {
			t, e := template.New("t").Funcs(fm).Option("missingkey=zero").Parse(s)
			if e != nil {
				panic(e)
			}
			_ = t
		}
	}))

	parsed := make([]*template.Template, 0, len(execSrc))
	for _, s := range execSrc {
		t, e := template.New("t").Funcs(fm).Option("missingkey=zero").Parse(s)
		if e != nil {
			panic(e)
		}
		parsed = append(parsed, t)
	}
	var sb bytes.Buffer
	rows = append(rows, bench("template.Execute x20", *n, "executing the 20 already-parsed templates", func() {
		for _, t := range parsed {
			sb.Reset()
			_ = t.Execute(&sb, data)
		}
	}))

	rows = append(rows, bench("FULL: read+parse+compile+tparse", *n, "everything a naive per-exec load does, minus Execute", func() {
		b, _ := os.ReadFile(*path)
		d, _ := apidsl.ParseDOM(b)
		var s []string
		compileAll(d, &s)
		f := apidsl.FuncMap()
		lim := s
		if len(lim) > 20 {
			lim = lim[:20]
		}
		for _, x := range lim {
			t, _ := template.New("t").Funcs(f).Option("missingkey=zero").Parse(x)
			_ = t
		}
	}))

	rows = append(rows, bench("gob decode (DOM mirror)", *n, "encoding/gob of the whole DOM", func() {
		var m mirrorNode
		if e := gob.NewDecoder(bytes.NewReader(gobBytes)).Decode(&m); e != nil {
			panic(e)
		}
	}))

	rows = append(rows, bench("flat decode (DOM)", *n, "hand-rolled string table + node array", func() {
		d := flatDecode(flatBytes)
		_ = d
	}))

	rows = append(rows, bench("cooked decode (templates only)", *n, "length-prefixed compiled template sources, no DOM", func() {
		s := cookedDecode(cookedBytes)
		_ = s
	}))

	rows = append(rows, bench("cooked decode + tparse x20", *n, "the cooked form still pays text/template.Parse", func() {
		s := cookedDecode(cookedBytes)
		f := apidsl.FuncMap()
		lim := s
		if len(lim) > 20 {
			lim = lim[:20]
		}
		for _, x := range lim {
			t, _ := template.New("t").Funcs(f).Option("missingkey=zero").Parse(x)
			_ = t
		}
	}))

	rows = append(rows, lazyStages(*n, refSrc, fm, data)...)
	rows = append(rows, funcMapStages(*n, refSrc, data)...)

	for _, r := range rows {
		fmt.Println(r.row())
	}
	fmt.Println()
}
