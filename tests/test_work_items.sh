#!/bin/bash
#
# Tests for scripts/lib/work_items.sh and scripts/lib/release_workflow.sh
# Covers: select_next_work_item, mark_* transitions, dependency ordering,
#         reconcile_merged_pull_requests (offline stub), build_pull_request_*.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

source "$SCRIPT_DIR/../scripts/lib/work_items.sh"
source "$SCRIPT_DIR/../scripts/lib/release_workflow.sh"

# Helper: write a minimal work-items.json
write_work_items() {
    local path="$1"
    cat > "$path" <<'JSON'
{
  "items": [
    {
      "id": "task-1",
      "title": "First task",
      "spec": "specs/task-1/spec.md",
      "tasks": "",
      "priority": 1,
      "status": "pending",
      "dependencies": []
    },
    {
      "id": "task-2",
      "title": "Second task",
      "spec": "specs/task-2/spec.md",
      "tasks": "",
      "priority": 2,
      "status": "pending",
      "dependencies": ["task-1"]
    },
    {
      "id": "task-3",
      "title": "Done task",
      "spec": "specs/task-3/spec.md",
      "tasks": "",
      "priority": 0,
      "status": "done",
      "dependencies": []
    }
  ]
}
JSON
}

# ── has_work_items_file / work_items_file_path ────────────────────────────────

suite "has_work_items_file"

TMPDIR_WI=$(make_tmpdir)

has_work_items_file "$TMPDIR_WI"
assert_false "no file → returns false" "$?"

write_work_items "$TMPDIR_WI/work-items.json"
has_work_items_file "$TMPDIR_WI"
assert_true  "file present → returns true" "$?"

# ── select_next_work_item ─────────────────────────────────────────────────────

suite "select_next_work_item"

PROJ="$TMPDIR_WI"

# task-1 is pending, no deps → should be selected (priority 1 < 2)
select_next_work_item "$PROJ"
assert_equals "selects first eligible item"  "task-1" "$ACTIVE_WORK_ITEM_ID"
assert_equals "title populated"              "First task" "$ACTIVE_WORK_ITEM_TITLE"

# task-3 is done → should not be selected
assert_not_equals "done item not selected"   "task-3" "$ACTIVE_WORK_ITEM_ID"

# task-2 depends on task-1 (still pending) → blocked
cp "$PROJ/work-items.json" "$PROJ/work-items.json.bak"
# Remove task-1 from the selectable pool by marking it done
python3 - "$PROJ/work-items.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for item in d["items"]:
    if item["id"] == "task-1": item["status"] = "done"
with open(sys.argv[1], "w") as f: json.dump(d, f, indent=2)
PY

select_next_work_item "$PROJ"
assert_equals "task-2 selectable once task-1 is done" "task-2" "$ACTIVE_WORK_ITEM_ID"

mv "$PROJ/work-items.json.bak" "$PROJ/work-items.json"

# ── select_next_work_item: all done ──────────────────────────────────────────

suite "select_next_work_item: all done returns false"

TMPDIR_WI2=$(make_tmpdir)
cat > "$TMPDIR_WI2/work-items.json" <<'JSON'
{"items":[{"id":"t1","status":"done","dependencies":[],"priority":1}]}
JSON
select_next_work_item "$TMPDIR_WI2"
assert_false "no eligible items → returns false" "$?"

# ── mark_work_item_in_progress ────────────────────────────────────────────────

suite "mark_work_item_in_progress"

write_work_items "$TMPDIR_WI/work-items.json"
mark_work_item_in_progress "$TMPDIR_WI" "task-1" "ralph/task-1"

set_active_work_item_by_id "$TMPDIR_WI" "task-1"
assert_equals "status set to in_progress"   "in_progress"  "$ACTIVE_WORK_ITEM_STATUS"
assert_equals "branch stored"               "ralph/task-1" "$ACTIVE_WORK_ITEM_BRANCH"

# ── mark_work_item_awaiting_merge ────────────────────────────────────────────

suite "mark_work_item_awaiting_merge"

write_work_items "$TMPDIR_WI/work-items.json"
mark_work_item_awaiting_merge "$TMPDIR_WI" "task-1" "ralph/task-1" "https://github.com/x/x/pull/42" "42"

set_active_work_item_by_id "$TMPDIR_WI" "task-1"
assert_equals "status awaiting_merge"    "awaiting_merge"               "$ACTIVE_WORK_ITEM_STATUS"
assert_equals "PR URL stored"           "https://github.com/x/x/pull/42" "$ACTIVE_WORK_ITEM_PR_URL"
assert_equals "PR number stored"        "42"                             "$ACTIVE_WORK_ITEM_PR_NUMBER"

# ── mark_work_item_done ───────────────────────────────────────────────────────

suite "mark_work_item_done"

write_work_items "$TMPDIR_WI/work-items.json"
mark_work_item_done "$TMPDIR_WI" "task-1"

set_active_work_item_by_id "$TMPDIR_WI" "task-1"
assert_equals "status done"          "done"   "$ACTIVE_WORK_ITEM_STATUS"
assert_equals "merge_status merged"  "merged" "$ACTIVE_WORK_ITEM_MERGE_STATUS"

# ── increment_work_item_retry_count ──────────────────────────────────────────

suite "increment_work_item_retry_count"

write_work_items "$TMPDIR_WI/work-items.json"
increment_work_item_retry_count "$TMPDIR_WI" "task-1"
increment_work_item_retry_count "$TMPDIR_WI" "task-1"

retry=$(python3 - "$TMPDIR_WI/work-items.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for item in d["items"]:
    if item["id"] == "task-1":
        print(item.get("retry_count", 0))
PY
)
assert_equals "retry_count incremented to 2" "2" "$retry"

# ── build_pull_request_title / body ──────────────────────────────────────────

suite "build_pull_request_title and body"

title=$(build_pull_request_title "task-1" "First task")
assert_contains "title includes item ID"    "task-1"     "$title"
assert_contains "title includes item title" "First task" "$title"

body=$(build_pull_request_body "task-1" "First task" "specs/task-1/spec.md" "")
assert_contains "body includes item ID"   "task-1"               "$body"
assert_contains "body mentions Ralph loop" "Ralph loop"          "$body"

# ── testing details in active work item context ──────────────────────────────

suite "active work item testing details"

TMPDIR_WI3=$(make_tmpdir)
cat > "$TMPDIR_WI3/work-items.json" <<'JSON'
{
  "items": [
    {
      "id": "mobile-1",
      "title": "Mobile flow",
      "spec": "specs/mobile-1/spec.md",
      "tasks": "specs/mobile-1/tasks.md",
      "priority": 1,
      "status": "pending",
      "dependencies": [],
      "testing": {
        "unit": ["pnpm test"],
        "e2e": ["maestro test .maestro/smoke.yaml"],
        "device": ["mcp device smoke-test ios"],
        "notes": "Run device checks separately"
      }
    }
  ]
}
JSON

set_active_work_item_by_id "$TMPDIR_WI3" "mobile-1"
assert_contains "testing summary includes e2e" "e2e: maestro test .maestro/smoke.yaml" "$ACTIVE_WORK_ITEM_TESTING_DETAILS"
rendered_context=$(render_active_work_item_context)
assert_contains "rendered context includes testing line" "- testing:" "$rendered_context"

# ── merge_work_item_release ──────────────────────────────────────────────────

suite "merge_work_item_release"

TMPDIR_REPO=$(make_tmpdir)
git -C "$TMPDIR_REPO" init -b main >/dev/null 2>&1
git -C "$TMPDIR_REPO" config user.name "Test User"
git -C "$TMPDIR_REPO" config user.email "test@example.com"
printf 'base\n' > "$TMPDIR_REPO/note.txt"
git -C "$TMPDIR_REPO" add note.txt
git -C "$TMPDIR_REPO" commit -m "base" >/dev/null 2>&1
git -C "$TMPDIR_REPO" switch -c "ralph/task-1" >/dev/null 2>&1
printf 'task\n' >> "$TMPDIR_REPO/note.txt"
git -C "$TMPDIR_REPO" commit -am "task work" >/dev/null 2>&1

merge_work_item_release "$TMPDIR_REPO" "task-1" "ralph/task-1"
assert_true "local merge fallback succeeds" "$?"

current_branch=$(git -C "$TMPDIR_REPO" branch --show-current)
assert_equals "returns to base branch" "main" "$current_branch"

git -C "$TMPDIR_REPO" merge-base --is-ancestor "ralph/task-1" "main"
assert_true "task branch is merged into main" "$?"

# ── worktree_is_clean / branch switching hygiene ──────────────────────────────

suite "worktree_is_clean ignores untracked files"

TMPDIR_REPO2=$(make_tmpdir)
git -C "$TMPDIR_REPO2" init -b main >/dev/null 2>&1
git -C "$TMPDIR_REPO2" config user.name "Test User"
git -C "$TMPDIR_REPO2" config user.email "test@example.com"
printf 'base\n' > "$TMPDIR_REPO2/note.txt"
git -C "$TMPDIR_REPO2" add note.txt
git -C "$TMPDIR_REPO2" commit -m "base" >/dev/null 2>&1

mkdir -p "$TMPDIR_REPO2/logs"
printf 'runtime log\n' > "$TMPDIR_REPO2/logs/run.log"

worktree_is_clean "$TMPDIR_REPO2"
assert_true "untracked runtime files do not make worktree dirty" "$?"

branch_name=$(ensure_work_item_branch "$TMPDIR_REPO2" "task-2")
assert_equals "branch can be created with only untracked files present" "ralph/task-2" "$branch_name"

suite "worktree_is_clean blocks tracked modifications"

git -C "$TMPDIR_REPO2" switch main >/dev/null 2>&1
printf 'changed\n' >> "$TMPDIR_REPO2/note.txt"

worktree_is_clean "$TMPDIR_REPO2"
assert_false "tracked modifications make worktree dirty" "$?"

print_test_summary
