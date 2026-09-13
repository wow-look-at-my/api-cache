#!/bin/sh
# Probe 05: rustc compiler identity, --emit outputs, dep-info format and escaping.
# Every step records PASS/FAIL explicitly. No `|| true`.
cd "$(dirname "$0")" || exit 1
. ./probe-lib.sh
cd rustsrc || exit 1
R=$(mktemp -d) || exit 1
trap 'rm -rf "$R"' EXIT
mkdir -p "$R/full"

step "rustc -vV (compiler identity)"        rustc -vV
step "rustc --print=sysroot"                rustc --print=sysroot
step "count sysroot shared libraries (buildcache hashes all of them)" \
	sh -c 'ls "$(rustc --print=sysroot)"/lib/*.so | wc -l'

step "--emit=dep-info : the dep-info file format" \
	env PATH_LIKE_VAR=hello rustc --crate-name demo --crate-type lib \
	    --emit=dep-info --out-dir "$R" lib.rs
step "read it (target line, phony lines, then '# env-dep:' records)" show "$R/demo.d"

step "--emit=link,metadata,dep-info -C extra-filename=-abc123 (out-dir pre-created)" \
	env PATH_LIKE_VAR=hello rustc --crate-name demo --crate-type lib \
	    --emit=link,metadata,dep-info -C extra-filename=-abc123 \
	    --out-dir "$R/full" lib.rs
step "list what rustc actually produced" ls -1 "$R/full"

step "rustc --print file-names (how a wrapper learns the output names)" \
	rustc --crate-name demo --crate-type lib -C extra-filename=-abc123 \
	      --print file-names lib.rs
step "NOTE: --print file-names does NOT list the .rmeta; a wrapper derives it from the .rlib" \
	sh -c 'ls -1 "$1"/full | grep -c rmeta' _ "$R"

step "env-dep record for a SET variable" grep -n 'env-dep' "$R/demo.d"

# An UNSET env! variable: rustc errors (the crate uses env! with a default message),
# but it still writes the dep file, and the env-dep record then has NO '=' -
# which is how 'unset' is distinguished from 'empty'. The compile failure is the
# expected outcome here, so it is an xstep, not a silent skip.
xstep "--emit=dep-info with PATH_LIKE_VAR unset (compile fails; dep file is still written)" nonzero \
	rustc --crate-name demo2 --crate-type lib --emit=dep-info --out-dir "$R" lib.rs
step "expect \$R/demo2.d to exist even though the compile failed" test -f "$R/demo2.d"
step "read it: the env-dep record has NO '=' -> the variable was UNSET" show "$R/demo2.d"

step "-C incremental : what artifact tree does it create? (this is why it is a bypass)" \
	env PATH_LIKE_VAR=x rustc --crate-name demo --crate-type lib --emit=link \
	    -C incremental="$R/inc" --out-dir "$R/i" lib.rs
step "list the incremental directory" ls -1 "$R/inc"
step "list one session directory inside it" sh -c 'ls -1 "$1"/inc/*/ | head -8' _ "$R"

step "dep-info escaping: a path containing a space" sh -c '
	set -e
	mkdir -p "$1/sp ace"
	cp helper.rs inc.txt "$1/sp ace/"
	printf "mod helper;\npub fn f()->i32{helper::g()+include!(\"inc.txt\")}\n" > "$1/sp ace/lib.rs"
' _ "$R"
step "--emit=dep-info over that path" \
	env PATH_LIKE_VAR=x rustc --crate-name sp --crate-type lib --emit=dep-info \
	    --out-dir "$R" "$R/sp ace/lib.rs"
step "read it: rustc escapes a space as '\\ ' and leaves every other char alone" show "$R/sp.d"

probe_summary
