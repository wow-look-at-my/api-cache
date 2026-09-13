# Shared probe harness.
#
# Hard rule: NEVER allow a silent failure. Every step records an explicit
# PASS/FAIL with its exit code, and the run ends with a count. There is no
# `|| true` anywhere in these probes: a step that fails is reported as FAIL,
# the harness exits non-zero, and the finding files say so.
#
# POSIX sh, dash-safe: every literal that could begin with '-' goes through
# `printf '%s\n'`, never through printf's format argument.

PROBE_FAILURES=0
PROBE_STEPS=0

say() { printf '%s\n' "$*"; }

# step "<description>" <command...>
#   Runs the command, shows its output, records PASS (exit 0) or FAIL.
step() {
	_desc=$1
	shift
	PROBE_STEPS=$((PROBE_STEPS + 1))
	say ""
	say "===== STEP: $_desc"
	say "----- \$ $*"
	"$@"
	_rc=$?
	if [ "$_rc" -eq 0 ]; then
		say "----- RESULT: PASS (exit 0)"
	else
		PROBE_FAILURES=$((PROBE_FAILURES + 1))
		say "----- RESULT: **FAIL** (exit $_rc)  <-- RECORDED, NOT IGNORED"
	fi
	return 0
}

# xstep "<description>" <expected-exit|nonzero> <command...>
#   For a step whose non-zero exit IS the finding (e.g. `gcc -c foo.c -o -`).
#   Stating the expectation keeps a behaviour change visible as a FAIL.
xstep() {
	_desc=$1
	_want=$2
	shift 2
	PROBE_STEPS=$((PROBE_STEPS + 1))
	say ""
	say "===== STEP (expects exit $_want): $_desc"
	say "----- \$ $*"
	"$@"
	_rc=$?
	if [ "$_want" = "nonzero" ] && [ "$_rc" -ne 0 ]; then
		say "----- RESULT: PASS (exit $_rc, non-zero as expected)"
	elif [ "$_rc" = "$_want" ]; then
		say "----- RESULT: PASS (exit $_rc, as expected)"
	else
		PROBE_FAILURES=$((PROBE_FAILURES + 1))
		say "----- RESULT: **FAIL** (exit $_rc, expected $_want)  <-- RECORDED"
	fi
	return 0
}

show() {
	say "--- contents of $1 ---"
	cat "$1"
	say "--- end ---"
}

probe_summary() {
	say ""
	say "========================================================="
	say "PROBE SUMMARY: $PROBE_STEPS steps, $PROBE_FAILURES FAILURES"
	say "========================================================="
	[ "$PROBE_FAILURES" -eq 0 ]
}
