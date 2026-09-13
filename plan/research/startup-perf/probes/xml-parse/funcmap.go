package main

// "template.Parse x20 WITH func map" costs ~780 us and "x20 with NO func map"
// costs ~56 us. The whole difference is Funcs() copying sprig's ~190-entry map
// into every template. These stages confirm that and measure the two ways out:
//
//   shared root:  one template carries the func map, and each config template
//                 is ASSOCIATED with it via root.New(name).Parse(). Associated
//                 templates share the parent's func map, so the copy is paid
//                 once per process instead of once per template.
//   small map:    the func map trimmed to just the handful of helpers the
//                 language itself defines, with sprig dropped.

import (
	"fmt"
	"text/template"

	apidsl "github.com/wow-look-at-my/api-dsl"
)

func funcMapStages(n int, src []string, data any) []*stat {
	var rows []*stat

	lim := src
	if len(lim) > 20 {
		lim = lim[:20]
	}

	full := apidsl.FuncMap()
	rows = append(rows, bench("shared-root Parse x20 (full func map)", n,
		fmt.Sprintf("one root carries the %d-entry map, 20 associated templates", len(full)),
		func() {
			root := template.New("root").Funcs(full).Option("missingkey=zero")
			for i, s := range lim {
				if _, e := root.New(fmt.Sprintf("t%d", i)).Parse(s); e != nil {
					panic(e)
				}
			}
		}))

	rows = append(rows, bench("shared-root Parse xALL (full func map)", n,
		fmt.Sprintf("one root, %d associated templates", len(src)), func() {
			root := template.New("root").Funcs(full).Option("missingkey=zero")
			for i, s := range src {
				_, _ = root.New(fmt.Sprintf("t%d", i)).Parse(s)
			}
		}))

	// The language's own helpers, without sprig. api-dsl's FuncMap is sprig
	// plus four names; this is those four alone, to price sprig's presence.
	small := template.FuncMap{
		"truthy":      apidsl.Truthy,
		"querystring": full["querystring"],
		"urlpath":     full["urlpath"],
		"repeatkey":   full["repeatkey"],
		"default":     full["default"],
	}
	rows = append(rows, bench("Parse x20, 5-entry func map", n,
		"per-template Funcs() but with sprig dropped", func() {
			for _, s := range lim {
				t := template.New("t").Funcs(small).Option("missingkey=zero")
				_, _ = t.Parse(s)
			}
		}))

	// The end-to-end number a wrapper would actually pay with both fixes:
	// cooked bytes in, one shared root, every template parsed, one executed.
	cooked := cookedEncode(src)
	rows = append(rows, bench("BEST: cooked decode + shared-root Parse xALL", n,
		"cooked form plus a single func-map copy: the whole per-exec config cost",
		func() {
			s := cookedDecode(cooked)
			root := template.New("root").Funcs(full).Option("missingkey=zero")
			for i, x := range s {
				_, _ = root.New(fmt.Sprintf("t%d", i)).Parse(x)
			}
		}))

	return rows
}
