#!/usr/bin/env bash
# Re-measure every local startup target through hyperfine.
#
# Flags and why:
#   -N / --shell=none   no shell is spawned between hyperfine and the target,
#                       so the number is execve + the program, not bash.
#   --warmup 20         the page cache and the branch predictors are warm
#                       before anything is recorded.
#   --runs 300          enough samples for a stable median on a noisy VM.
#   --export-markdown   the committed table; --export-json keeps the raw
#                       per-run times so a later reader can re-derive anything.
#
# hyperfine reports mean +/- sigma, min and max. It does not report a median or
# a p90, so the committed tables carry mean and min, and the JSON beside them
# holds every individual run time for anyone who wants a percentile.
set -euo pipefail
HF="${HYPERFINE:-$HOME/.local/bin/hyperfine}"
B="$(cd "$(dirname "$0")/../../bin" && pwd)"
R="$(cd "$(dirname "$0")/../../results" && pwd)"
RUNS="${RUNS:-300}"
mkdir -p "$R/hyperfine"

# ---- 1. the startup floor across languages and link modes
"$HF" -N --warmup 20 --runs "$RUNS" \
	--export-markdown "$R/hyperfine/startup-floor.md" \
	--export-json     "$R/hyperfine/startup-floor.json" \
	-n "C null, static"            "$B/c-null-static" \
	-n "C null, dynamic"           "$B/c-null-dyn" \
	-n "C hello write(2), static"  "$B/c-hello-static" \
	-n "C hello write(2), dynamic" "$B/c-hello-dyn" \
	-n "C hello printf, static"    "$B/c-hello-printf-static" \
	-n "C hello printf, dynamic"   "$B/c-hello-printf-dyn" \
	-n "Rust hello"                "$B/rust-hello" \
	-n "Go hello"                  "$B/go-hello" \
	-n "Go hello, -ldflags=-s -w"  "$B/go-hello-sw" \
	-n "Go hello, CGO_ENABLED=1"   "$B/go-hello-cgo"

# ---- 2. what each import costs a Go binary at startup
"$HF" -N --warmup 20 --runs "$RUNS" \
	--export-markdown "$R/hyperfine/go-imports.md" \
	--export-json     "$R/hyperfine/go-imports.json" \
	-n "Go hello (baseline)"                 "$B/go-hello" \
	-n "Go + crypto/sha256"                  "$B/go-crypto-sha" \
	-n "Go + encoding/xml"                   "$B/go-stdlib-xml" \
	-n "Go + text/template"                  "$B/go-stdlib-tmpl" \
	-n "Go + net/http"                       "$B/go-stdlib-http" \
	-n "Go + xml + template + net/http"      "$B/go-stdlib-all" \
	-n "Go + cobra (root cmd built and run)" "$B/go-cobra" \
	-n "Go + sprig linked, map not built"    "$B/go-sprig-initonly" \
	-n "Go + sprig TxtFuncMap() built"       "$B/go-sprig"

# ---- 3. does a trailer on the binary slow exec?
# The targets run in "quiet" mode: they exit without reading the trailer, so
# what is measured is purely whether a bigger FILE costs more to execve.
"$HF" -N --warmup 20 --runs "$RUNS" \
	--export-markdown "$R/hyperfine/trailer-exec.md" \
	--export-json     "$R/hyperfine/trailer-exec.json" \
	-n "Go + 3 KiB trailer (not read)"   "$B/trailer-0 quiet" \
	-n "Go + 1 MiB trailer (not read)"   "$B/trailer-1m quiet" \
	-n "Go + 10 MiB trailer (not read)"  "$B/trailer-10m quiet" \
	-n "Go hello (no trailer at all)"    "$B/go-hello"

# ---- 4. the daemon round trip, as a whole process
if [ -S /tmp/apcache-bench.sock ]; then
	"$HF" -N --warmup 20 --runs "$RUNS" \
		--export-markdown "$R/hyperfine/daemon-client.md" \
		--export-json     "$R/hyperfine/daemon-client.json" \
		-n "C client, dynamic: connect+roundtrip+exit" "$B/ipc-cclient" \
		-n "C client, static: connect+roundtrip+exit"  "$B/ipc-cclient-static" \
		-n "Go client: connect+roundtrip+exit"         "$B/ipc-goclient" \
		-n "C hello (no daemon contact)"               "$B/c-hello-dyn" \
		-n "Go hello (no daemon contact)"              "$B/go-hello"
else
	echo "daemon socket absent; skipping the client comparison" >&2
fi

# ---- 5. a real config-driven Go CLI
if [ -x "$B/api-cli" ]; then
	"$HF" -N --warmup 20 --runs "$RUNS" \
		--export-markdown "$R/hyperfine/api-cli.md" \
		--export-json     "$R/hyperfine/api-cli.json" \
		-n "api-cli --help (no config found)"           "$B/api-cli --help" \
		-n "api-cli docs schema"                        "$B/api-cli docs schema" \
		-n "api-cli --config github.xml --help"         "$B/api-cli --config /home/user/api-cli/samples/github/github.xml --help" \
		-n "api-cli --config api.example.xml --help"    "$B/api-cli --config /home/user/api-cli/api.example.xml --help" \
		-n "Go hello (the floor under all of these)"    "$B/go-hello"
fi
