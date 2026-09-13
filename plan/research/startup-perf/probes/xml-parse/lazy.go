package main

// The full-load table shows text/template.Parse is the stage a cooked form
// does NOT remove: the cooked bytes decode in ~1.5 us, and then 20 templates
// still cost most of a millisecond to parse. These extra stages size that
// cliff: how much of it is per-template, how much is the func map, and what a
// wrapper saves by parsing only the one or two templates an invocation
// actually reaches (lazy parse) instead of the whole config.

import (
	"bytes"
	"fmt"
	"text/template"

	apidsl "github.com/wow-look-at-my/api-dsl"
)

func lazyStages(n int, src []string, fm template.FuncMap, data any) []*stat {
	var rows []*stat

	one := src[0]
	for _, s := range src { // pick a representative one that actually has actions
		if len(s) > len(one) {
			one = s
		}
	}

	rows = append(rows, bench("template.Parse x1 (largest)", n,
		fmt.Sprintf("one template, %d bytes of source", len(one)), func() {
			t, e := template.New("t").Funcs(fm).Option("missingkey=zero").Parse(one)
			if e != nil {
				panic(e)
			}
			_ = t
		}))

	small := src[0]
	for _, s := range src {
		if len(s) < len(small) && len(s) > 0 {
			small = s
		}
	}
	rows = append(rows, bench("template.Parse x1 (smallest)", n,
		fmt.Sprintf("one template, %d bytes of source", len(small)), func() {
			t, _ := template.New("t").Funcs(fm).Option("missingkey=zero").Parse(small)
			_ = t
		}))

	rows = append(rows, bench(fmt.Sprintf("template.Parse xALL (%d)", len(src)), n,
		"every placeholder-bearing element in the config", func() {
			for _, s := range src {
				t, _ := template.New("t").Funcs(fm).Option("missingkey=zero").Parse(s)
				_ = t
			}
		}))

	// Funcs() copies the map into the template. With a ~190-entry sprig map
	// that copy is paid once per template, so it is worth isolating.
	rows = append(rows, bench("template.Parse x20, NO func map", n,
		"same sources, Funcs() never called: isolates the map copy", func() {
			lim := src
			if len(lim) > 20 {
				lim = lim[:20]
			}
			for _, s := range lim {
				// A source that calls a function will not parse without it,
				// so errors are tolerated here; the cost being measured is
				// the lex and parse, not the outcome.
				t := template.New("t").Option("missingkey=zero")
				_, _ = t.Parse(s)
			}
		}))

	// The realistic lazy path: decode the cooked form, build the func map
	// once, parse ONE template, execute it. This is the whole per-exec
	// config cost of a wrapper that knows which template it needs.
	cooked := cookedEncode(src)
	var sb bytes.Buffer
	rows = append(rows, bench("LAZY: cooked decode + 1 parse + 1 exec", n,
		"what a wrapper pays when it parses only the template it reaches", func() {
			s := cookedDecode(cooked)
			f := apidsl.FuncMap()
			t, _ := template.New("t").Funcs(f).Option("missingkey=zero").Parse(s[0])
			sb.Reset()
			if t != nil {
				_ = t.Execute(&sb, data)
			}
		}))

	return rows
}
