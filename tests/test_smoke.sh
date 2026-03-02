#!/bin/bash
#
# Smoke tests for the Ralph loop.
# Covers: bash -n syntax checks for all scripts, --help output, provider
#         adapter function presence, and plan/build work-source precedence.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
source "$SCRIPT_DIR/lib/test_helpers.sh"

# ── Syntax checks ─────────────────────────────────────────────────────────────

suite "bash -n syntax checks: scripts/lib/*.sh"

for lib in \
    prompt_builder.sh \
    runtime_helpers.sh \
    work_items.sh \
    release_workflow.sh \
    provider_adapters.sh \
    preflight.sh \
    verification_profiles.sh \
    circuit_breaker.sh \
    nr_of_tries.sh \
    speckit_runner.sh \
    observability.sh \
    date_utils.sh \
    notifications.sh \
; do
    path="$ROOT_DIR/scripts/lib/$lib"
    if [[ -f "$path" ]]; then
        bash -n "$path" 2>/dev/null
        assert_true "syntax OK: scripts/lib/$lib" "$?"
    else
        skip "scripts/lib/$lib (not found)"
    fi
done

suite "bash -n syntax checks: scripts/ralph-loop.sh"

bash -n "$ROOT_DIR/scripts/ralph-loop.sh" 2>/dev/null
assert_true "syntax OK: scripts/ralph-loop.sh" "$?"

# ── ralph-loop.sh --help ──────────────────────────────────────────────────────

suite "ralph-loop.sh --help"

help_output=$("$ROOT_DIR/scripts/ralph-loop.sh" --help 2>&1)
help_exit=$?
assert_true  "--help exits 0"                               "$help_exit"
assert_contains "--help shows 'Usage'"                      "Usage"    "$help_output"
assert_contains "--help shows 'plan' mode"                  "plan"     "$help_output"
assert_contains "--help shows '--runtime' flag"             "--runtime" "$help_output"
assert_contains "--help shows '--model' flag"               "--model"   "$help_output"
assert_contains "--help lists 'claude' runtime"             "claude"    "$help_output"
assert_contains "--help lists 'codex' runtime"              "codex"     "$help_output"
assert_contains "--help lists 'gemini' runtime"             "gemini"    "$help_output"
assert_contains "--help lists 'copilot' runtime"            "copilot"   "$help_output"

# ── provider_adapters: configure_runtime ─────────────────────────────────────

suite "provider_adapters: configure_runtime sets required vars"

RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
source "$ROOT_DIR/scripts/lib/provider_adapters.sh"

for runtime in claude codex gemini copilot; do
    configure_runtime "$runtime" "" >/dev/null 2>&1
    assert_not_equals "RUNTIME_ID set for $runtime"         ""  "$RUNTIME_ID"
    assert_not_equals "RUNTIME_SHORT_NAME set for $runtime" ""  "$RUNTIME_SHORT_NAME"
    assert_not_equals "RUNTIME_LABEL set for $runtime"      ""  "$RUNTIME_LABEL"
done

# Unknown runtime should return non-zero
configure_runtime "unknown-runtime" "" >/dev/null 2>&1
assert_false "unknown runtime returns error" "$?"

# ── provider_adapters: validate_runtime_requirements ─────────────────────────

suite "provider_adapters: validate_runtime_requirements callable"

# Just verify the function exists and returns without crashing the shell
configure_runtime "claude" "" >/dev/null 2>&1
type validate_runtime_requirements >/dev/null 2>&1
assert_true "validate_runtime_requirements function exists" "$?"

# ── work-source precedence ────────────────────────────────────────────────────

suite "work-source precedence visible in startup banner"

TMPDIR_PREC=$(make_tmpdir)
git -C "$TMPDIR_PREC" init -q
git -C "$TMPDIR_PREC" commit --allow-empty -q -m "init"

# work-items.json present
echo '{"items":[]}' > "$TMPDIR_PREC/work-items.json"
# IMPLEMENTATION_PLAN.md present (fallback)
echo "# Plan" > "$TMPDIR_PREC/IMPLEMENTATION_PLAN.md"
# specs/ present (final fallback)
mkdir -p "$TMPDIR_PREC/specs"
echo "# spec" > "$TMPDIR_PREC/specs/a.md"

# Source the preflight and check that work sources resolve correctly
source "$ROOT_DIR/scripts/lib/preflight.sh" 2>/dev/null || true

PREFLIGHT_ERRORS=()
check_work_source "$TMPDIR_PREC"
assert_true "preflight passes when all three work sources present" "$?"

# Remove work-items.json; IMPLEMENTATION_PLAN.md should still pass
rm "$TMPDIR_PREC/work-items.json"
PREFLIGHT_ERRORS=()
check_work_source "$TMPDIR_PREC"
assert_true "preflight passes with only IMPLEMENTATION_PLAN.md" "$?"

# Remove IMPLEMENTATION_PLAN.md; specs/ should still pass
rm "$TMPDIR_PREC/IMPLEMENTATION_PLAN.md"
PREFLIGHT_ERRORS=()
check_work_source "$TMPDIR_PREC"
assert_true "preflight passes with only specs/" "$?"

# Remove specs/; should fail
rm -rf "$TMPDIR_PREC/specs"
PREFLIGHT_ERRORS=()
check_work_source "$TMPDIR_PREC"
assert_false "preflight fails with no work source" "$?"

print_test_summary
