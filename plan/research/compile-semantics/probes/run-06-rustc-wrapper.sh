#!/bin/sh
# Probe 06: the cargo RUSTC_WRAPPER / RUSTC_WORKSPACE_WRAPPER protocol.
# Question answered: when BOTH are set, how does cargo compose them?
# Every step records PASS/FAIL explicitly. No `|| true`.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
R=$(mktemp -d) || exit 1
trap 'rm -rf "$R"' EXIT

step "cargo is present (a missing tool is a FAIL, not a skip)" sh -c 'command -v cargo'
step "cargo --version" cargo --version

step "build a throwaway crate and two logging wrappers" sh -c '
	set -e
	mkdir -p "$1/proj/src"
	cat > "$1/proj/Cargo.toml" <<EOF
[package]
name = "wraptest"
version = "0.1.0"
edition = "2021"
EOF
	echo "fn main(){}" > "$1/proj/src/main.rs"
	for w in w1 w2; do
		printf "#!/bin/sh\necho \"%s argv: \$*\" >> \"%s/wraplog.txt\"\nexec \"\$@\"\n" "$w" "$1" > "$1/$w.sh"
		chmod +x "$1/$w.sh"
	done
' _ "$R"

step "cargo build with BOTH wrappers set" sh -c '
	cd "$1/proj"
	RUSTC_WRAPPER="$1/w1.sh" RUSTC_WORKSPACE_WRAPPER="$1/w2.sh" cargo build --offline 2>&1 | tail -2
' _ "$R"

step "expect a wrapper log to exist" test -s "$R/wraplog.txt"
step "FINDING: the composition is  \$RUSTC_WRAPPER \$RUSTC_WORKSPACE_WRAPPER \$rustc <args>" \
	sh -c 'cut -c1-150 "$1/wraplog.txt"' _ "$R"
step "FINDING: cargo also routes its own PROBES through the wrapper (-vV, --print=file-names)" \
	sh -c 'grep -c -e "-vV" -e "--print=file-names" "$1/wraplog.txt"' _ "$R"
step "the real compile argv, in full (note -C incremental: NOT cacheable by default)" \
	sh -c 'grep -- "--crate-name wraptest" "$1/wraplog.txt" | head -1 | fold -w 150' _ "$R"

probe_summary
