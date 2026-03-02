#!/bin/bash
#
# Tests for scripts/lib/nr_of_tries.sh
# Covers: get/increment/reset nr_of_tries, is_spec_stuck, get_stuck_specs.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/lib/nr_of_tries.sh"

# ── get_nr_of_tries ───────────────────────────────────────────────────────────

suite "get_nr_of_tries"

TMPDIR_NR=$(make_tmpdir)

# Fresh spec has no counter
echo "# My Spec" > "$TMPDIR_NR/fresh.md"
result=$(get_nr_of_tries "$TMPDIR_NR/fresh.md")
assert_equals "fresh spec returns 0" "0" "$result"

# Spec with existing counter
echo -e "# Spec\n<!-- NR_OF_TRIES: 5 -->" > "$TMPDIR_NR/existing.md"
result=$(get_nr_of_tries "$TMPDIR_NR/existing.md")
assert_equals "existing counter read correctly" "5" "$result"

# Non-existent file
result=$(get_nr_of_tries "$TMPDIR_NR/nonexistent.md")
assert_equals "missing file returns 0" "0" "$result"

# ── increment_nr_of_tries ─────────────────────────────────────────────────────

suite "increment_nr_of_tries"

echo "# Spec A" > "$TMPDIR_NR/spec_a.md"
new_val=$(increment_nr_of_tries "$TMPDIR_NR/spec_a.md")
assert_equals "first increment returns 1"      "1" "$new_val"
stored=$(get_nr_of_tries "$TMPDIR_NR/spec_a.md")
assert_equals "counter stored in file is 1"    "1" "$stored"

new_val=$(increment_nr_of_tries "$TMPDIR_NR/spec_a.md")
assert_equals "second increment returns 2"     "2" "$new_val"
stored=$(get_nr_of_tries "$TMPDIR_NR/spec_a.md")
assert_equals "counter stored in file is 2"    "2" "$stored"

# Start from a high value
echo -e "# Spec B\n<!-- NR_OF_TRIES: 9 -->" > "$TMPDIR_NR/spec_b.md"
new_val=$(increment_nr_of_tries "$TMPDIR_NR/spec_b.md")
assert_equals "increment from 9 gives 10"      "10" "$new_val"

# ── reset_nr_of_tries ─────────────────────────────────────────────────────────

suite "reset_nr_of_tries"

echo -e "# Spec C\n<!-- NR_OF_TRIES: 7 -->" > "$TMPDIR_NR/spec_c.md"
reset_nr_of_tries "$TMPDIR_NR/spec_c.md"
stored=$(get_nr_of_tries "$TMPDIR_NR/spec_c.md")
assert_equals "reset sets counter to 0" "0" "$stored"

# reset on spec with no counter is a no-op
echo "# Spec D" > "$TMPDIR_NR/spec_d.md"
reset_nr_of_tries "$TMPDIR_NR/spec_d.md"
stored=$(get_nr_of_tries "$TMPDIR_NR/spec_d.md")
assert_equals "reset on no-counter spec stays 0" "0" "$stored"

# ── is_spec_stuck ─────────────────────────────────────────────────────────────

suite "is_spec_stuck"

echo "# Spec" > "$TMPDIR_NR/below.md"
echo "<!-- NR_OF_TRIES: 3 -->" >> "$TMPDIR_NR/below.md"
is_spec_stuck "$TMPDIR_NR/below.md"
assert_false "3 tries is not stuck (threshold is $MAX_NR_OF_TRIES)" "$?"

echo "# Spec" > "$TMPDIR_NR/at_limit.md"
echo "<!-- NR_OF_TRIES: $MAX_NR_OF_TRIES -->" >> "$TMPDIR_NR/at_limit.md"
is_spec_stuck "$TMPDIR_NR/at_limit.md"
assert_true "at threshold ($MAX_NR_OF_TRIES) is stuck" "$?"

echo "# Spec" > "$TMPDIR_NR/over_limit.md"
echo "<!-- NR_OF_TRIES: $((MAX_NR_OF_TRIES + 5)) -->" >> "$TMPDIR_NR/over_limit.md"
is_spec_stuck "$TMPDIR_NR/over_limit.md"
assert_true "above threshold is stuck" "$?"

# ── get_stuck_specs ───────────────────────────────────────────────────────────

suite "get_stuck_specs"

SPECS_DIR="$TMPDIR_NR/specs"
mkdir -p "$SPECS_DIR"

echo "# OK Spec"       > "$SPECS_DIR/ok.md"
echo "<!-- NR_OF_TRIES: 2 -->" >> "$SPECS_DIR/ok.md"

echo "# Stuck Spec"    > "$SPECS_DIR/stuck.md"
echo "<!-- NR_OF_TRIES: $MAX_NR_OF_TRIES -->" >> "$SPECS_DIR/stuck.md"

stuck_output=$(get_stuck_specs "$SPECS_DIR")
assert_contains "stuck spec appears in output"   "stuck.md"   "$stuck_output"

# ok.md should NOT appear in the stuck list
if echo "$stuck_output" | grep -qF "ok.md"; then
    fail "non-stuck spec should not appear in stuck list"
else
    pass "non-stuck spec does not appear in stuck list"
fi

print_test_summary
