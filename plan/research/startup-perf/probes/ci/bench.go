// bench is the portable exec-timing harness for the CI matrix. It is written
// in Go rather than C because it must run identically on Linux, macOS and
// Windows, where no one C harness compiles with one command line.
//
// It spawns the target N times and reports min / median / p90 wall time in
// microseconds. A spawn includes the runner's own fork-and-wait cost, which is
// a constant per platform, so the DIFFERENCE between rows on one platform is
// the number that means something. Rows are NOT comparable across platforms.
//
// usage: bench -n 300 -label "C static" -- ./prog [args...]
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"time"
)

func main() {
	n := flag.Int("n", 300, "iterations")
	warm := flag.Int("warm", 20, "warmup iterations, not measured")
	label := flag.String("label", "", "row label for the markdown table")
	flag.Parse()
	argv := flag.Args()
	if len(argv) == 0 {
		fmt.Fprintln(os.Stderr, "bench: no target")
		os.Exit(2)
	}

	run := func() error {
		c := exec.Command(argv[0], argv[1:]...)
		c.Stdout = nil // discarded
		c.Stderr = nil
		return c.Run()
	}

	for i := 0; i < *warm; i++ {
		if err := run(); err != nil {
			fmt.Printf("| %s | FAILED: %v | | | |\n", *label, err)
			return
		}
	}

	d := make([]float64, 0, *n)
	for i := 0; i < *n; i++ {
		t0 := time.Now()
		if err := run(); err != nil {
			fmt.Printf("| %s | FAILED: %v | | | |\n", *label, err)
			return
		}
		d = append(d, float64(time.Since(t0).Nanoseconds())/1000.0)
	}
	sort.Float64s(d)
	var sum float64
	for _, v := range d {
		sum += v
	}
	sz := int64(-1)
	if fi, err := os.Stat(argv[0]); err == nil {
		sz = fi.Size()
	}
	fmt.Printf("| %s | %.0f | %.0f | %.0f | %.0f | %d |\n",
		*label, d[0], d[len(d)/2], d[int(float64(len(d))*0.90)], sum/float64(len(d)), sz)
}
