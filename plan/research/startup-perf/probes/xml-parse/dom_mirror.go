package main

// apidsl.Node keeps its fields unexported, so neither gob nor a hand-rolled
// encoder can reach them from outside the package. mirrorNode is the same
// shape with exported fields, built by walking the parsed DOM once. Every
// serialization number below is therefore measured against the mirror, not
// against apidsl.Node directly, and the walk that builds it is reported
// separately so nothing is hidden inside a decode figure.
//
// A production "cooked form" would not serialize the DOM at all: it would
// serialize the COMPILED templates, which is what cookedDoc below measures.

import apidsl "github.com/wow-look-at-my/api-dsl"

type mirrorAttr struct {
	Name  string
	Value string
}

type mirrorItem struct {
	Text string
	Elem *mirrorNode
}

type mirrorNode struct {
	Name    string
	Attrs   []mirrorAttr
	Content []mirrorItem
}

func mirror(n *apidsl.Node) *mirrorNode {
	if n == nil {
		return nil
	}
	m := &mirrorNode{Name: n.Name()}
	for _, a := range n.Attrs() {
		m.Attrs = append(m.Attrs, mirrorAttr{a.Name, a.Value})
	}
	for _, it := range n.Content() {
		if it.Elem == nil {
			m.Content = append(m.Content, mirrorItem{Text: it.Text})
		} else {
			m.Content = append(m.Content, mirrorItem{Elem: mirror(it.Elem)})
		}
	}
	return m
}

func countNodes(m *mirrorNode) int {
	if m == nil {
		return 0
	}
	n := 1
	for _, it := range m.Content {
		n += countNodes(it.Elem)
	}
	return n
}
