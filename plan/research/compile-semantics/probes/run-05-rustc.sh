#!/bin/sh
cd "$(dirname "$0")/rustsrc"
R=$(mktemp -d); trap 'rm -rf $R' EXIT
echo "===== rustc -vV (compiler identity) ====="; rustc -vV
echo "===== rustc --print=sysroot ====="; rustc --print=sysroot
echo "===== --emit=dep-info output format ====="
PATH_LIKE_VAR=hello rustc --crate-name demo --crate-type lib --emit=dep-info --out-dir $R lib.rs && cat $R/demo.d
echo "===== --emit=link,metadata,dep-info with -C extra-filename ====="
PATH_LIKE_VAR=hello rustc --crate-name demo --crate-type lib --emit=link,metadata,dep-info -C extra-filename=-abc123 --out-dir $R/full lib.rs 2>&1; ls -1 $R/full
echo "===== rustc --print file-names (how buildcache learns output names) ====="
rustc --crate-name demo --crate-type lib -C extra-filename=-abc123 --print file-names lib.rs
echo "===== dep-info when an env! is used: env-dep lines ====="
grep -n 'env-dep' $R/demo.d || echo "(no env-dep lines)"
echo "===== unset env var case ====="
rustc --crate-name demo2 --crate-type lib --emit=dep-info --out-dir $R lib.rs 2>&1 | head -3; cat $R/demo2.d 2>/dev/null
echo "===== -C incremental artifacts ====="
PATH_LIKE_VAR=x rustc --crate-name demo --crate-type lib --emit=link -C incremental=$R/inc --out-dir $R/i lib.rs && ls -1 $R/inc | head -5
echo "===== dep-info escaping of a space in a path ====="
mkdir -p "$R/sp ace" && cp helper.rs inc.txt "$R/sp ace/" && printf 'mod helper;\npub fn f()->i32{helper::g()+include!("inc.txt")}\n' > "$R/sp ace/lib.rs"
PATH_LIKE_VAR=x rustc --crate-name sp --crate-type lib --emit=dep-info --out-dir $R "$R/sp ace/lib.rs" && cat $R/sp.d
