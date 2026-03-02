#!/bin/bash
#
# Tests for scripts/lib/prompt_builder.sh
# Covers: parse_plan_mode_arguments, reset_plan_mode_state, validate_plan_mode_arguments.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

# prompt_builder.sh sources verification_profiles.sh and speckit_runner.sh if present.
# Those are expected to exist at the sibling path.
source "$SCRIPT_DIR/../scripts/lib/prompt_builder.sh"

# ── reset_plan_mode_state ─────────────────────────────────────────────────────

suite "reset_plan_mode_state"

PLAN_PRD_FILE="something"
PLAN_BRIEF="a brief"
PLAN_ITERATION_OVERRIDE="5"

reset_plan_mode_state

assert_equals "PRD file cleared"            ""     "$PLAN_PRD_FILE"
assert_equals "notes file cleared"          ""     "$PLAN_NOTES_FILE"
assert_equals "brief cleared"               ""     "$PLAN_BRIEF"
assert_equals "iteration override cleared"  ""     "$PLAN_ITERATION_OVERRIDE"
assert_equals "args consumed reset"         "0"    "$PLAN_ARGS_CONSUMED"
assert_equals "input kind reset to repo"    "repo" "$PLAN_INPUT_KIND"

# ── parse_plan_mode_arguments: --prd ─────────────────────────────────────────

suite "parse_plan_mode_arguments: --prd"

reset_plan_mode_state
TMPDIR_PB=$(make_tmpdir)
echo "# PRD content" > "$TMPDIR_PB/prd.md"

parse_plan_mode_arguments --prd "$TMPDIR_PB/prd.md"
assert_equals "--prd sets PLAN_PRD_FILE"      "$TMPDIR_PB/prd.md" "$PLAN_PRD_FILE"
assert_equals "--prd consumes 2 args"         "2"                  "$PLAN_ARGS_CONSUMED"

# ── parse_plan_mode_arguments: --notes ───────────────────────────────────────

suite "parse_plan_mode_arguments: --notes"

reset_plan_mode_state
echo "# Notes content" > "$TMPDIR_PB/notes.md"

parse_plan_mode_arguments --notes "$TMPDIR_PB/notes.md"
assert_equals "--notes sets PLAN_NOTES_FILE"  "$TMPDIR_PB/notes.md" "$PLAN_NOTES_FILE"
assert_equals "--notes consumes 2 args"       "2"                    "$PLAN_ARGS_CONSUMED"

# ── parse_plan_mode_arguments: --brief ───────────────────────────────────────

suite "parse_plan_mode_arguments: --brief"

reset_plan_mode_state
parse_plan_mode_arguments --brief "Build an Expo app for field sales"
assert_equals "--brief sets PLAN_BRIEF"       "Build an Expo app for field sales" "$PLAN_BRIEF"
assert_equals "--brief consumes 2 args"       "2"                                  "$PLAN_ARGS_CONSUMED"

# ── parse_plan_mode_arguments: missing value ─────────────────────────────────

suite "parse_plan_mode_arguments: missing values return error"

reset_plan_mode_state
parse_plan_mode_arguments --prd 2>/dev/null
assert_false "--prd without value returns non-zero" "$?"

reset_plan_mode_state
parse_plan_mode_arguments --notes 2>/dev/null
assert_false "--notes without value returns non-zero" "$?"

reset_plan_mode_state
parse_plan_mode_arguments --brief 2>/dev/null
assert_false "--brief without value returns non-zero" "$?"

# ── validate_plan_mode_arguments ─────────────────────────────────────────────

suite "validate_plan_mode_arguments"

TMPDIR_VP=$(make_tmpdir)
# Initialise a bare git repo so the directory is a valid project
git -C "$TMPDIR_VP" init -q
git -C "$TMPDIR_VP" commit --allow-empty -q -m "init"

# No input: defaults to "repo" — should succeed
reset_plan_mode_state
validate_plan_mode_arguments "$TMPDIR_VP" >/dev/null 2>&1
assert_true "no input flag passes validation (repo mode)" "$?"

# --prd pointing at a real file
reset_plan_mode_state
echo "# PRD" > "$TMPDIR_VP/prd.md"
parse_plan_mode_arguments --prd "$TMPDIR_VP/prd.md"
validate_plan_mode_arguments "$TMPDIR_VP" >/dev/null 2>&1
assert_true "--prd with valid file passes validation" "$?"

# --prd pointing at a missing file
reset_plan_mode_state
parse_plan_mode_arguments --prd "/nonexistent/prd.md" 2>/dev/null
validate_plan_mode_arguments "$TMPDIR_VP" >/dev/null 2>&1
assert_false "--prd with missing file fails validation" "$?"

# ── build_runtime_prompt: testing policy context ─────────────────────────────

suite "build_runtime_prompt: appends testing policy"

TMPDIR_BP=$(make_tmpdir)
mkdir -p "$TMPDIR_BP/templates" "$TMPDIR_BP/logs" "$TMPDIR_BP/.specify/memory"
cat > "$TMPDIR_BP/templates/PROMPT_build.md" <<'EOF'
# Test Build Prompt
EOF
cat > "$TMPDIR_BP/.specify/memory/constitution.md" <<'EOF'
# Example Constitution

## Testing Policy

### Unit Tests
- `pnpm test`

### End-to-End Tests
- `maestro test .maestro/smoke.yaml`

## Something Else

ignored
EOF

PREFLIGHT_PROJECT_PROFILE="unknown"
prompt_file=$(build_runtime_prompt "build" "$TMPDIR_BP" "$TMPDIR_BP/logs")
prompt_content=$(cat "$prompt_file")

assert_contains "testing policy heading appended" "## Testing Policy" "$prompt_content"
assert_contains "unit test command included" '`pnpm test`' "$prompt_content"
assert_contains "e2e command included" '`maestro test .maestro/smoke.yaml`' "$prompt_content"

print_test_summary
