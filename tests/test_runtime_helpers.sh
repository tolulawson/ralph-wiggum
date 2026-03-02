#!/bin/bash
#
# Tests for scripts/lib/runtime_helpers.sh
# Covers: promise parsing, completion detection, BLOCKED/DECIDE signals.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/lib/runtime_helpers.sh"

# ── parse_promise_signal_from_text ────────────────────────────────────────────

suite "parse_promise_signal_from_text: DONE"

parse_promise_signal_from_text "some output <promise>DONE</promise> more text"
assert_equals "signal is DONE"    "DONE"  "$LAST_PROMISE_SIGNAL"
assert_equals "payload is empty"  ""      "$LAST_PROMISE_PAYLOAD"

suite "parse_promise_signal_from_text: ALL_DONE"

parse_promise_signal_from_text "output <promise>ALL_DONE</promise>"
assert_equals "signal is ALL_DONE"  "ALL_DONE" "$LAST_PROMISE_SIGNAL"

suite "parse_promise_signal_from_text: BLOCKED"

parse_promise_signal_from_text "text <promise>BLOCKED:missing API key</promise>"
assert_equals "signal is BLOCKED"              "BLOCKED"         "$LAST_PROMISE_SIGNAL"
assert_equals "payload contains reason"        "missing API key" "$LAST_PROMISE_PAYLOAD"

suite "parse_promise_signal_from_text: DECIDE"

parse_promise_signal_from_text "text <promise>DECIDE:which database to use?</promise>"
assert_equals "signal is DECIDE"           "DECIDE"                     "$LAST_PROMISE_SIGNAL"
assert_equals "payload contains question"  "which database to use?"     "$LAST_PROMISE_PAYLOAD"

suite "parse_promise_signal_from_text: no signal"

parse_promise_signal_from_text "no promise tags here"
assert_equals "signal is NONE" "NONE" "$LAST_PROMISE_SIGNAL"
assert_equals "payload empty"  ""     "$LAST_PROMISE_PAYLOAD"

suite "parse_promise_signal_from_text: empty input"

parse_promise_signal_from_text ""
assert_equals "signal is NONE on empty input" "NONE" "$LAST_PROMISE_SIGNAL"

suite "parse_promise_signal_from_text: DONE takes precedence over BLOCKED"

parse_promise_signal_from_text "<promise>DONE</promise> and also <promise>BLOCKED:x</promise>"
assert_equals "DONE wins over BLOCKED" "DONE" "$LAST_PROMISE_SIGNAL"

suite "parse_promise_signal_from_text: last DONE wins"

parse_promise_signal_from_text "<promise>DONE</promise> extra <promise>ALL_DONE</promise>"
assert_equals "last tag is ALL_DONE" "ALL_DONE" "$LAST_PROMISE_SIGNAL"

# ── has_completion_promise ────────────────────────────────────────────────────

suite "has_completion_promise"

LAST_PROMISE_SIGNAL="DONE"
has_completion_promise
assert_true  "DONE is a completion promise" "$?"

LAST_PROMISE_SIGNAL="ALL_DONE"
has_completion_promise
assert_true  "ALL_DONE is a completion promise" "$?"

LAST_PROMISE_SIGNAL="BLOCKED"
has_completion_promise
assert_false "BLOCKED is not a completion promise" "$?"

LAST_PROMISE_SIGNAL="NONE"
has_completion_promise
assert_false "NONE is not a completion promise" "$?"

# ── has_help_promise ──────────────────────────────────────────────────────────

suite "has_help_promise"

LAST_PROMISE_SIGNAL="BLOCKED"
has_help_promise
assert_true  "BLOCKED is a help promise" "$?"

LAST_PROMISE_SIGNAL="DECIDE"
has_help_promise
assert_true  "DECIDE is a help promise" "$?"

LAST_PROMISE_SIGNAL="DONE"
has_help_promise
assert_false "DONE is not a help promise" "$?"

LAST_PROMISE_SIGNAL="NONE"
has_help_promise
assert_false "NONE is not a help promise" "$?"

# ── detect_promise_signal_from_files ─────────────────────────────────────────

suite "detect_promise_signal_from_files"

TMPDIR_PF=$(make_tmpdir)

echo "output line 1" > "$TMPDIR_PF/no_signal.log"
echo "good <promise>DONE</promise>" > "$TMPDIR_PF/done.log"
echo "blocked <promise>BLOCKED:db down</promise>" > "$TMPDIR_PF/blocked.log"

detect_promise_signal_from_files "$TMPDIR_PF/no_signal.log"
assert_equals "no signal from log with no tag" "NONE" "$LAST_PROMISE_SIGNAL"

detect_promise_signal_from_files "$TMPDIR_PF/done.log"
assert_equals "DONE detected from file" "DONE" "$LAST_PROMISE_SIGNAL"
assert_equals "source recorded"         "$TMPDIR_PF/done.log" "$LAST_PROMISE_SOURCE"

detect_promise_signal_from_files "$TMPDIR_PF/blocked.log"
assert_equals "BLOCKED detected from file"    "BLOCKED"  "$LAST_PROMISE_SIGNAL"
assert_equals "payload extracted from file"   "db down"  "$LAST_PROMISE_PAYLOAD"

detect_promise_signal_from_files "/nonexistent/path.log"
assert_equals "missing file treated as no signal" "NONE" "$LAST_PROMISE_SIGNAL"

# First-match wins
detect_promise_signal_from_files "$TMPDIR_PF/done.log" "$TMPDIR_PF/blocked.log"
assert_equals "first file wins when multiple provided" "DONE" "$LAST_PROMISE_SIGNAL"

print_test_summary
