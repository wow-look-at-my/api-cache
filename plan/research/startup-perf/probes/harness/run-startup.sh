#!/usr/bin/env bash
# Run the startup floor benchmark three times over every target, interleaved,
# so a slow patch of the VM hits every target rather than whichever one
# happened to be running. The fork baseline is measured between every pass.
set -u
B="$(cd "$(dirname "$0")/../../bin" && pwd)"
N="${N:-400}"
TARGETS="c-null-static c-null-dyn c-hello-static c-hello-dyn c-hello-printf-static c-hello-printf-dyn rust-hello go-hello go-hello-sw go-hello-cgo go-crypto-sha go-stdlib-xml go-stdlib-tmpl go-stdlib-http go-stdlib-all go-sprig go-cobra"
# warm the page cache: a cold binary measures disk, not startup
for t in $TARGETS; do cat "$B/$t" > /dev/null; done
for pass in 1 2 3; do
	echo "=== pass $pass"
	"$B/forkbase" "$N"
	for t in $TARGETS; do "$B/execbench" "$N" "$B/$t"; done
done
