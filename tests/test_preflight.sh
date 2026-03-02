#!/bin/bash
#
# Tests for scripts/lib/preflight.sh
# Covers: git-repo detection, constitution check, work-source check,
#         project profile detection, profile tooling dispatch.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

# Stub colour variables expected by preflight.sh
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

source "$SCRIPT_DIR/../scripts/lib/preflight.sh"

# ── check_git_repo ────────────────────────────────────────────────────────────

suite "check_git_repo"

TMPDIR_GIT=$(make_tmpdir)
PREFLIGHT_ERRORS=()

check_git_repo "$TMPDIR_GIT"
assert_false "non-git dir triggers error"  "$?"
assert_equals "error message added"        "1" "${#PREFLIGHT_ERRORS[@]}"

# The ralph-wiggum repo itself is a git repo
PREFLIGHT_ERRORS=()
check_git_repo "$SCRIPT_DIR/.."
assert_true  "valid git repo passes"       "$?"
assert_equals "no errors added"            "0" "${#PREFLIGHT_ERRORS[@]}"

# ── check_constitution ────────────────────────────────────────────────────────

suite "check_constitution"

PREFLIGHT_WARNINGS=()

check_constitution "/nonexistent/constitution.md"
assert_equals "missing constitution adds 1 warning" "1" "${#PREFLIGHT_WARNINGS[@]}"

PREFLIGHT_WARNINGS=()
TMP_CONST=$(mktemp)
check_constitution "$TMP_CONST"
assert_equals "existing constitution: no warning" "0" "${#PREFLIGHT_WARNINGS[@]}"
rm -f "$TMP_CONST"

# ── check_work_source ─────────────────────────────────────────────────────────

suite "check_work_source"

TMPDIR_WS=$(make_tmpdir)
PREFLIGHT_ERRORS=()

check_work_source "$TMPDIR_WS"
assert_false "empty dir: no work source" "$?"
assert_equals "error added for missing work source" "1" "${#PREFLIGHT_ERRORS[@]}"

# work-items.json present
PREFLIGHT_ERRORS=()
echo '{"items":[]}' > "$TMPDIR_WS/work-items.json"
check_work_source "$TMPDIR_WS"
assert_true  "work-items.json counts as work source" "$?"
assert_equals "no error when work-items.json present" "0" "${#PREFLIGHT_ERRORS[@]}"
rm "$TMPDIR_WS/work-items.json"

# IMPLEMENTATION_PLAN.md present
PREFLIGHT_ERRORS=()
echo "# Plan" > "$TMPDIR_WS/IMPLEMENTATION_PLAN.md"
check_work_source "$TMPDIR_WS"
assert_true  "IMPLEMENTATION_PLAN.md counts as work source" "$?"
assert_equals "no error when IMPLEMENTATION_PLAN.md present" "0" "${#PREFLIGHT_ERRORS[@]}"
rm "$TMPDIR_WS/IMPLEMENTATION_PLAN.md"

# specs/ dir with a markdown file
PREFLIGHT_ERRORS=()
mkdir -p "$TMPDIR_WS/specs"
echo "# spec" > "$TMPDIR_WS/specs/my-spec.md"
check_work_source "$TMPDIR_WS"
assert_true  "specs/*.md counts as work source" "$?"
assert_equals "no error when specs present" "0" "${#PREFLIGHT_ERRORS[@]}"

# ── detect_project_profile: explicit constitution ─────────────────────────────

suite "detect_project_profile: explicit profile in constitution"

TMPDIR_PROF=$(make_tmpdir)

for profile in web expo backend library; do
    echo "profile: $profile" > "$TMPDIR_PROF/constitution.md"
    PREFLIGHT_PROJECT_PROFILE="unknown"
    detect_project_profile "$TMPDIR_PROF" "$TMPDIR_PROF/constitution.md"
    assert_equals "explicit '$profile' read from constitution" "$profile" "$PREFLIGHT_PROJECT_PROFILE"
done

# Mixed case
echo "Profile: EXPO" > "$TMPDIR_PROF/constitution.md"
detect_project_profile "$TMPDIR_PROF" "$TMPDIR_PROF/constitution.md"
assert_equals "case-insensitive profile read" "expo" "$PREFLIGHT_PROJECT_PROFILE"

# ── detect_project_profile: auto-detect Expo ─────────────────────────────────

suite "detect_project_profile: auto-detect Expo"

TMPDIR_EXPO=$(make_tmpdir)
echo '{"expo":{"name":"MyApp"}}' > "$TMPDIR_EXPO/app.json"
PREFLIGHT_PROJECT_PROFILE="unknown"
detect_project_profile "$TMPDIR_EXPO" "/nonexistent/constitution.md"
assert_equals "app.json → expo profile" "expo" "$PREFLIGHT_PROJECT_PROFILE"
rm "$TMPDIR_EXPO/app.json"

# package.json with expo dependency
PREFLIGHT_PROJECT_PROFILE="unknown"
echo '{"dependencies":{"expo":"~50.0.0"}}' > "$TMPDIR_EXPO/package.json"
detect_project_profile "$TMPDIR_EXPO" "/nonexistent/constitution.md"
assert_equals "package.json expo dep → expo profile" "expo" "$PREFLIGHT_PROJECT_PROFILE"
rm "$TMPDIR_EXPO/package.json"

# ── detect_project_profile: auto-detect Web ──────────────────────────────────

suite "detect_project_profile: auto-detect Web"

TMPDIR_WEB=$(make_tmpdir)
echo '{"dependencies":{"react":"^18.0.0","react-dom":"^18.0.0"}}' > "$TMPDIR_WEB/package.json"
PREFLIGHT_PROJECT_PROFILE="unknown"
detect_project_profile "$TMPDIR_WEB" "/nonexistent/constitution.md"
assert_equals "package.json react dep → web profile" "web" "$PREFLIGHT_PROJECT_PROFILE"

# ── detect_project_profile: auto-detect Backend ──────────────────────────────

suite "detect_project_profile: auto-detect Backend"

TMPDIR_BE=$(make_tmpdir)
touch "$TMPDIR_BE/server.js"
PREFLIGHT_PROJECT_PROFILE="unknown"
detect_project_profile "$TMPDIR_BE" "/nonexistent/constitution.md"
assert_equals "server.js → backend profile" "backend" "$PREFLIGHT_PROJECT_PROFILE"
rm "$TMPDIR_BE/server.js"

touch "$TMPDIR_BE/main.py"
PREFLIGHT_PROJECT_PROFILE="unknown"
detect_project_profile "$TMPDIR_BE" "/nonexistent/constitution.md"
assert_equals "main.py → backend profile" "backend" "$PREFLIGHT_PROJECT_PROFILE"

# ── detect_project_profile: unknown ──────────────────────────────────────────

suite "detect_project_profile: falls back to unknown"

TMPDIR_UNK=$(make_tmpdir)
PREFLIGHT_PROJECT_PROFILE="web"
detect_project_profile "$TMPDIR_UNK" "/nonexistent/constitution.md"
assert_equals "empty dir → unknown profile" "unknown" "$PREFLIGHT_PROJECT_PROFILE"

# ── run_preflight: end-to-end (build mode) ───────────────────────────────────

suite "run_preflight: build mode success"

TMPDIR_PF2=$(make_tmpdir)
git -C "$TMPDIR_PF2" init -q
git -C "$TMPDIR_PF2" commit --allow-empty -q -m "init"
echo "# Plan" > "$TMPDIR_PF2/IMPLEMENTATION_PLAN.md"

run_preflight "$TMPDIR_PF2" "/nonexistent/constitution.md" "build" "false" >/dev/null 2>&1
assert_true "preflight passes with git repo + IMPLEMENTATION_PLAN.md" "$?"

suite "run_preflight: plan mode skips work-source check"

TMPDIR_PF3=$(make_tmpdir)
git -C "$TMPDIR_PF3" init -q
git -C "$TMPDIR_PF3" commit --allow-empty -q -m "init"

# No work source at all — but plan mode should not fail for that
run_preflight "$TMPDIR_PF3" "/nonexistent/constitution.md" "plan" "false" >/dev/null 2>&1
assert_true "plan mode does not fail for missing work source" "$?"

print_test_summary
