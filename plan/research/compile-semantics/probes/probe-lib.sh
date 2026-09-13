# Shared probe harness. Every step records an explicit PASS/FAIL with its exit code.
# No `|| true`. A step that fails is reported, never silently skipped.
PROBE_FAILURES=0
PROBE_STEPS=0
# step "<description>" <command...>   -- runs it, echoes output, records the verdict.
step() {
	desc=$1; shift
	PROBE_STEPS=$((PROBE_STEPS + 1))
	printf '\n===== STEP: %s\n----- $ %s\n' "$desc" "$*"
	"$@"
	rc=$?
	if [ $rc -eq 0 ]; then
		printf '----- RESULT: PASS (exit 0)\n'
	else
		PROBE_FAILURES=$((PROBE_FAILURES + 1))
		printf '----- RESULT: **FAIL** (exit %d)  <-- recorded, not ignored\n' "$rc"
	fi
	return 0
}
# xstep: a step whose NON-ZERO exit is itself the finding (e.g. `gcc -c -o -`).
# It states the expectation, so a change in behaviour is still visible.
xstep() {
	desc=$1; want=$2; shift 2
	PROBE_STEPS=$((PROBE_STEPS + 1))
	printf '\n===== STEP (expects exit %s): %s\n----- $ %s\n' "$want" "$desc" "$*"
	"$@"
	rc=$?
	if [ "$rc" = "$want" ]; then
		printf '----- RESULT: PASS (exit %d, as expected)\n' "$rc"
	elif [ "$want" = "nonzero" ] && [ $rc -ne 0 ]; then
		printf '----- RESULT: PASS (exit %d, non-zero as expected)\n' "$rc"
	else
		PROBE_FAILURES=$((PROBE_FAILURES + 1))
		printf '----- RESULT: **FAIL** (exit %d, expected %s)  <-- recorded\n' "$rc" "$want"
	fi
	return 0
}
probe_summary() {
	printf '\n=========================================================\n'
	printf 'PROBE SUMMARY: %d steps, %d FAILURES\n' "$PROBE_STEPS" "$PROBE_FAILURES"
	printf '=========================================================\n'
	[ "$PROBE_FAILURES" -eq 0 ]
}
