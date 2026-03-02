#!/bin/bash
#
# Tests for scripts/lib/circuit_breaker.sh
# Covers: init, can_execute, record_loop_result state transitions, reset.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

# date_utils.sh is sourced by circuit_breaker.sh
source "$SCRIPT_DIR/../scripts/lib/date_utils.sh"

# Override CB_STATE_FILE to use a temp file for each test run
TMPDIR_CB=$(make_tmpdir)
CB_STATE_FILE="$TMPDIR_CB/.circuit_breaker_state"

source "$SCRIPT_DIR/../scripts/lib/circuit_breaker.sh"

# ── init_circuit_breaker ──────────────────────────────────────────────────────

suite "init_circuit_breaker"

rm -f "$CB_STATE_FILE"
init_circuit_breaker
assert_file_exists "state file created" "$CB_STATE_FILE"
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_equals "initial state is CLOSED" "CLOSED" "$state"

# Re-initialising should not overwrite an existing state file
jq '.state = "HALF_OPEN"' "$CB_STATE_FILE" > "$CB_STATE_FILE.tmp" && mv "$CB_STATE_FILE.tmp" "$CB_STATE_FILE"
init_circuit_breaker
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_equals "init does not overwrite existing state file" "HALF_OPEN" "$state"

# ── can_execute ───────────────────────────────────────────────────────────────

suite "can_execute"

rm -f "$CB_STATE_FILE"
init_circuit_breaker

can_execute
assert_true "can execute when CLOSED" "$?"

jq '.state = "HALF_OPEN"' "$CB_STATE_FILE" > "$CB_STATE_FILE.tmp" && mv "$CB_STATE_FILE.tmp" "$CB_STATE_FILE"
can_execute
assert_true "can execute when HALF_OPEN" "$?"

jq '.state = "OPEN"' "$CB_STATE_FILE" > "$CB_STATE_FILE.tmp" && mv "$CB_STATE_FILE.tmp" "$CB_STATE_FILE"
can_execute
assert_false "cannot execute when OPEN" "$?"

# ── record_loop_result: no-progress transitions ───────────────────────────────

suite "record_loop_result: no-progress opens circuit"

rm -f "$CB_STATE_FILE"
init_circuit_breaker

# Feed iterations with no progress (files_changed=0, no errors)
for i in $(seq 1 $((CB_NO_PROGRESS_THRESHOLD - 1))); do
    record_loop_result "$i" 0 "false" >/dev/null 2>&1
done
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_not_equals "circuit not yet OPEN before threshold" "OPEN" "$state"

record_loop_result "$CB_NO_PROGRESS_THRESHOLD" 0 "false" >/dev/null 2>&1
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_equals "circuit OPEN at no-progress threshold" "OPEN" "$state"

# ── record_loop_result: progress resets counter ───────────────────────────────

suite "record_loop_result: progress resets no-progress counter"

rm -f "$CB_STATE_FILE"
init_circuit_breaker

record_loop_result 1 0 "false" >/dev/null 2>&1
record_loop_result 2 0 "false" >/dev/null 2>&1
no_prog=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
assert_equals "no-progress counter increments" "2" "$no_prog"

# Now record progress (files_changed > 0)
record_loop_result 3 5 "false" >/dev/null 2>&1
no_prog=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
assert_equals "progress resets no-progress counter to 0" "0" "$no_prog"

# ── record_loop_result: same-error opens circuit ─────────────────────────────

suite "record_loop_result: same-error opens circuit"

rm -f "$CB_STATE_FILE"
init_circuit_breaker

# Use files_changed=1 so the no-progress counter stays at 0 while only the
# same-error counter accumulates.  This isolates the same-error trip-wire.
for i in $(seq 1 $((CB_SAME_ERROR_THRESHOLD - 1))); do
    record_loop_result "$i" 1 "true" >/dev/null 2>&1
done
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_not_equals "circuit not yet OPEN before error threshold" "OPEN" "$state"

record_loop_result "$CB_SAME_ERROR_THRESHOLD" 1 "true" >/dev/null 2>&1
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_equals "circuit OPEN at same-error threshold" "OPEN" "$state"

# ── reset_circuit_breaker ─────────────────────────────────────────────────────

suite "reset_circuit_breaker"

rm -f "$CB_STATE_FILE"
init_circuit_breaker
jq '.state = "OPEN"' "$CB_STATE_FILE" > "$CB_STATE_FILE.tmp" && mv "$CB_STATE_FILE.tmp" "$CB_STATE_FILE"

reset_circuit_breaker "test reset" >/dev/null 2>&1
state=$(jq -r '.state' "$CB_STATE_FILE")
assert_equals "reset sets state to CLOSED" "CLOSED" "$state"
no_prog=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
assert_equals "reset clears no-progress counter" "0" "$no_prog"
same_err=$(jq -r '.consecutive_same_error' "$CB_STATE_FILE")
assert_equals "reset clears same-error counter" "0" "$same_err"

can_execute
assert_true "can execute after reset" "$?"

print_test_summary
