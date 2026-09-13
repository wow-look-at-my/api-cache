#!/bin/sh
# Run every probe, and FAIL LOUDLY if any of them failed.
# Hard rule: no probe failure is ever silent, and no result is written as if
# complete when a step did not run.
cd "$(dirname "$0")" || exit 1
mkdir -p out
rc_total=0
for s in run-01-depfiles.sh run-02-preproc.sh run-03-debug.sh \
         run-04-flags.sh run-05-rustc.sh run-06-rustc-wrapper.sh; do
	out="out/$(echo "$s" | sed -e 's/^run-//' -e 's/\.sh$/.txt/')"
	case "$s" in
		run-03-debug.sh) out="out/03-debug-and-paths.txt" ;;
	esac
	printf '%s\n' "=== $s -> $out"
	./"$s" > "$out" 2>&1
	rc=$?
	tail -2 "$out" | head -1
	if [ "$rc" -ne 0 ]; then
		printf '%s\n' "!!! $s FAILED (exit $rc) - see $out"
		rc_total=1
	fi
done
if [ "$rc_total" -eq 0 ]; then
	printf '%s\n' "ALL PROBES PASSED"
else
	printf '%s\n' "ONE OR MORE PROBES FAILED - findings must not be treated as complete"
fi
exit "$rc_total"
