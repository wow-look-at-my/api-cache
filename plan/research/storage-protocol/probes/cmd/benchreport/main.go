// benchreport turns a probe results directory into one markdown file, so a CI
// run publishes numbers that can be pasted into the findings unchanged.
//
//	go run ./cmd/benchreport -label ubuntu-latest -run <url> -dir ci-results
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	label := flag.String("label", "", "runner label, e.g. ubuntu-latest")
	runURL := flag.String("run", "", "workflow run URL")
	dir := flag.String("dir", "results", "results directory")
	flag.Parse()

	fmt.Printf("## storage-protocol probes — %s\n\n", *label)
	if *runURL != "" {
		fmt.Printf("Run: %s\n\n", *runURL)
	}

	if s, err := os.ReadFile(filepath.Join(*dir, "machine.txt")); err == nil {
		fmt.Printf("### machine\n\n```\n%s```\n\n", s)
	}
	for _, f := range []struct{ file, title string }{
		{"tables.txt", "ratio and container-overhead tables"},
		{"binpazer-tables.txt", "binpazer round trip"},
	} {
		if s, err := os.ReadFile(filepath.Join(*dir, f.file)); err == nil {
			fmt.Printf("### %s\n\n```\n%s```\n\n", f.title, trimGoTest(string(s)))
		}
	}
	for _, f := range []struct{ file, title string }{
		{"bench.txt", "benchmarks"},
		{"binpazer-bench.txt", "binpazer benchmarks"},
	} {
		if s, err := os.ReadFile(filepath.Join(*dir, f.file)); err == nil {
			fmt.Printf("### %s\n\n%s\n", f.title, benchTable(string(s)))
		}
	}
}

// trimGoTest drops go test's own RUN/PASS scaffolding, keeping the printed
// tables and the t.Logf lines.
func trimGoTest(s string) string {
	var b strings.Builder
	for _, ln := range strings.Split(s, "\n") {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, "=== RUN") || strings.HasPrefix(t, "--- PASS") ||
			t == "PASS" || strings.HasPrefix(t, "ok  ") {
			continue
		}
		b.WriteString(ln)
		b.WriteString("\n")
	}
	return b.String()
}

// benchTable reformats `go test -bench` output as a markdown table. Fields past
// ns/op vary by benchmark, so everything after the iteration count is kept as
// one column rather than guessed at.
func benchTable(s string) string {
	var b strings.Builder
	b.WriteString("| benchmark | iters | ns/op | rest |\n|---|--:|--:|---|\n")
	sc := bufio.NewScanner(strings.NewReader(s))
	rows := 0
	for sc.Scan() {
		ln := sc.Text()
		if !strings.HasPrefix(ln, "Benchmark") {
			continue
		}
		f := strings.Fields(ln)
		if len(f) < 4 {
			continue
		}
		name := strings.TrimSuffix(f[0], "-"+lastDash(f[0]))
		rest := strings.Join(f[3:], " ")
		rest = strings.TrimPrefix(rest, "ns/op")
		b.WriteString(fmt.Sprintf("| `%s` | %s | %s | %s |\n", name, f[1], f[2], strings.TrimSpace(rest)))
		rows++
	}
	if rows == 0 {
		return "_no benchmark lines_\n"
	}
	return b.String()
}

// lastDash returns the text after the final '-' of a benchmark name, which go
// test appends as the GOMAXPROCS suffix.
func lastDash(s string) string {
	i := strings.LastIndex(s, "-")
	if i < 0 {
		return ""
	}
	return s[i+1:]
}
