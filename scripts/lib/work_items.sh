#!/bin/bash
#
# work-items.json helpers for task selection and release-state transitions.
#

ACTIVE_WORK_ITEM_ID=""
ACTIVE_WORK_ITEM_TITLE=""
ACTIVE_WORK_ITEM_SPEC=""
ACTIVE_WORK_ITEM_TASKS=""
ACTIVE_WORK_ITEM_PRIORITY=""
ACTIVE_WORK_ITEM_STATUS=""
ACTIVE_WORK_ITEM_BRANCH=""
ACTIVE_WORK_ITEM_REVIEW_STATUS=""
ACTIVE_WORK_ITEM_PR_NUMBER=""
ACTIVE_WORK_ITEM_PR_URL=""
ACTIVE_WORK_ITEM_MERGE_STATUS=""
ACTIVE_WORK_ITEM_TESTING_DETAILS=""

reset_active_work_item() {
    ACTIVE_WORK_ITEM_ID=""
    ACTIVE_WORK_ITEM_TITLE=""
    ACTIVE_WORK_ITEM_SPEC=""
    ACTIVE_WORK_ITEM_TASKS=""
    ACTIVE_WORK_ITEM_PRIORITY=""
    ACTIVE_WORK_ITEM_STATUS=""
    ACTIVE_WORK_ITEM_BRANCH=""
    ACTIVE_WORK_ITEM_REVIEW_STATUS=""
    ACTIVE_WORK_ITEM_PR_NUMBER=""
    ACTIVE_WORK_ITEM_PR_URL=""
    ACTIVE_WORK_ITEM_MERGE_STATUS=""
    ACTIVE_WORK_ITEM_TESTING_DETAILS=""
}

work_items_file_path() {
    local project_dir="$1"
    echo "$project_dir/work-items.json"
}

has_work_items_file() {
    local project_dir="$1"
    [[ -f "$(work_items_file_path "$project_dir")" ]]
}

_work_item_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${RED}Error: python3 is required to manage work-items.json state.${NC}" >&2
        return 1
    fi
    python3 - "$@"
}

set_active_work_item_by_id() {
    local project_dir="$1"
    local item_id="$2"
    local work_items_file
    local result

    reset_active_work_item
    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1

    result=$(
        _work_item_python "$work_items_file" "$item_id" <<'PY'
import json
import sys

path, item_id = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

sep = "\x1f"

def testing_summary(item):
    testing = item.get("testing")
    if not isinstance(testing, dict):
        return ""
    parts = []
    for key in ("unit", "integration", "e2e", "device", "manual"):
        values = testing.get(key) or []
        if values:
            parts.append(f"{key}: {'; '.join(str(v) for v in values)}")
    notes = testing.get("notes", "")
    if notes:
        parts.append(f"notes: {notes}")
    return " | ".join(parts)

for item in data.get("items", []):
    if item.get("id") != item_id:
        continue
    fields = [
        item.get("id", ""),
        item.get("title", ""),
        item.get("spec", ""),
        item.get("tasks", ""),
        str(item.get("priority", "")),
        item.get("status", ""),
        item.get("branch", ""),
        item.get("review_status", ""),
        "" if item.get("pr_number") is None else str(item.get("pr_number")),
        item.get("pr_url", ""),
        item.get("merge_status", ""),
        testing_summary(item),
    ]
    print(sep.join(fields))
    break
PY
    ) || return 1

    [[ -n "$result" ]] || return 1

    IFS=$'\x1f' read -r ACTIVE_WORK_ITEM_ID ACTIVE_WORK_ITEM_TITLE ACTIVE_WORK_ITEM_SPEC ACTIVE_WORK_ITEM_TASKS \
        ACTIVE_WORK_ITEM_PRIORITY ACTIVE_WORK_ITEM_STATUS ACTIVE_WORK_ITEM_BRANCH ACTIVE_WORK_ITEM_REVIEW_STATUS \
        ACTIVE_WORK_ITEM_PR_NUMBER ACTIVE_WORK_ITEM_PR_URL ACTIVE_WORK_ITEM_MERGE_STATUS ACTIVE_WORK_ITEM_TESTING_DETAILS <<< "$result"

    return 0
}

select_next_work_item() {
    local project_dir="$1"
    local work_items_file
    local result

    reset_active_work_item
    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1

    result=$(
        _work_item_python "$work_items_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

sep = "\x1f"

def testing_summary(item):
    testing = item.get("testing")
    if not isinstance(testing, dict):
        return ""
    parts = []
    for key in ("unit", "integration", "e2e", "device", "manual"):
        values = testing.get(key) or []
        if values:
            parts.append(f"{key}: {'; '.join(str(v) for v in values)}")
    notes = testing.get("notes", "")
    if notes:
        parts.append(f"notes: {notes}")
    return " | ".join(parts)

items = data.get("items", [])
by_id = {item.get("id"): item for item in items}

def deps_done(item):
    for dep in item.get("dependencies", []) or []:
        dep_item = by_id.get(dep)
        if dep_item is None:
            return False
        if dep_item.get("status") != "done":
            return False
    return True

eligible = []
for item in items:
    status = item.get("status", "pending")
    if status not in {"pending", "in_progress"}:
        continue
    if not deps_done(item):
        continue
    status_rank = 0 if status == "in_progress" else 1
    priority = item.get("priority", 999999)
    eligible.append((status_rank, priority, item.get("id", ""), item))

if not eligible:
    sys.exit(0)

eligible.sort(key=lambda row: (row[0], row[1], row[2]))
item = eligible[0][3]

fields = [
    item.get("id", ""),
    item.get("title", ""),
    item.get("spec", ""),
    item.get("tasks", ""),
    str(item.get("priority", "")),
    item.get("status", ""),
    item.get("branch", ""),
    item.get("review_status", ""),
    "" if item.get("pr_number") is None else str(item.get("pr_number")),
    item.get("pr_url", ""),
    item.get("merge_status", ""),
    testing_summary(item),
]
print(sep.join(fields))
PY
    )

    [[ -n "$result" ]] || return 1

    IFS=$'\x1f' read -r ACTIVE_WORK_ITEM_ID ACTIVE_WORK_ITEM_TITLE ACTIVE_WORK_ITEM_SPEC ACTIVE_WORK_ITEM_TASKS \
        ACTIVE_WORK_ITEM_PRIORITY ACTIVE_WORK_ITEM_STATUS ACTIVE_WORK_ITEM_BRANCH ACTIVE_WORK_ITEM_REVIEW_STATUS \
        ACTIVE_WORK_ITEM_PR_NUMBER ACTIVE_WORK_ITEM_PR_URL ACTIVE_WORK_ITEM_MERGE_STATUS ACTIVE_WORK_ITEM_TESTING_DETAILS <<< "$result"

    return 0
}

find_awaiting_merge_item() {
    local project_dir="$1"
    local work_items_file

    reset_active_work_item
    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1

    local result
    result=$(
        _work_item_python "$work_items_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

sep = "\x1f"

def testing_summary(item):
    testing = item.get("testing")
    if not isinstance(testing, dict):
        return ""
    parts = []
    for key in ("unit", "integration", "e2e", "device", "manual"):
        values = testing.get(key) or []
        if values:
            parts.append(f"{key}: {'; '.join(str(v) for v in values)}")
    notes = testing.get("notes", "")
    if notes:
        parts.append(f"notes: {notes}")
    return " | ".join(parts)

items = data.get("items", [])
eligible = []
for item in items:
    status = item.get("status", "")
    if status not in {"awaiting_merge", "pr_open"}:
        continue
    priority = item.get("priority", 999999)
    eligible.append((priority, item.get("id", ""), item))

if not eligible:
    sys.exit(0)

eligible.sort(key=lambda row: (row[0], row[1]))
item = eligible[0][2]

fields = [
    item.get("id", ""),
    item.get("title", ""),
    item.get("spec", ""),
    item.get("tasks", ""),
    str(item.get("priority", "")),
    item.get("status", ""),
    item.get("branch", ""),
    item.get("review_status", ""),
    "" if item.get("pr_number") is None else str(item.get("pr_number")),
    item.get("pr_url", ""),
    item.get("merge_status", ""),
    testing_summary(item),
]
print(sep.join(fields))
PY
    )

    [[ -n "$result" ]] || return 1

    IFS=$'\x1f' read -r ACTIVE_WORK_ITEM_ID ACTIVE_WORK_ITEM_TITLE ACTIVE_WORK_ITEM_SPEC ACTIVE_WORK_ITEM_TASKS \
        ACTIVE_WORK_ITEM_PRIORITY ACTIVE_WORK_ITEM_STATUS ACTIVE_WORK_ITEM_BRANCH ACTIVE_WORK_ITEM_REVIEW_STATUS \
        ACTIVE_WORK_ITEM_PR_NUMBER ACTIVE_WORK_ITEM_PR_URL ACTIVE_WORK_ITEM_MERGE_STATUS ACTIVE_WORK_ITEM_TESTING_DETAILS <<< "$result"

    return 0
}

_update_work_item_json() {
    local work_items_file="$1"
    local item_id="$2"
    local update_mode="$3"
    local arg1="${4:-}"
    local arg2="${5:-}"
    local arg3="${6:-}"

    _work_item_python "$work_items_file" "$item_id" "$update_mode" "$arg1" "$arg2" "$arg3" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

path, item_id, mode, arg1, arg2, arg3 = sys.argv[1:7]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
updated = False

for item in data.get("items", []):
    if item.get("id") != item_id:
        continue

    if mode == "in_progress":
        item["status"] = "in_progress"
        item["branch"] = arg1
        item["review_status"] = item.get("review_status") or "pending"
        item["merge_status"] = item.get("merge_status") or "not_requested"
        item["last_started_at"] = now
    elif mode == "retry":
        item["retry_count"] = int(item.get("retry_count", 0)) + 1
        if item.get("status") == "pending":
            item["status"] = "in_progress"
    elif mode == "awaiting_merge_with_pr":
        item["status"] = "awaiting_merge"
        item["branch"] = arg1
        item["review_status"] = "passed"
        item["merge_status"] = "pending"
        item["pr_url"] = arg2
        if arg3:
            try:
                item["pr_number"] = int(arg3)
            except ValueError:
                item["pr_number"] = arg3
        item["ready_for_merge_at"] = now
    elif mode == "awaiting_merge_manual":
        item["status"] = "awaiting_merge"
        item["branch"] = arg1
        item["review_status"] = "passed"
        item["merge_status"] = "pending"
        item["ready_for_merge_at"] = now
    elif mode == "done":
        item["status"] = "done"
        item["review_status"] = item.get("review_status") or "passed"
        item["merge_status"] = "merged"
        item["merged_at"] = now
    else:
        raise SystemExit(f"Unsupported update mode: {mode}")

    updated = True
    break

if not updated:
    raise SystemExit(f"Work item not found: {item_id}")

tmp_path = f"{path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp_path, path)
PY
}

mark_work_item_in_progress() {
    local project_dir="$1"
    local item_id="$2"
    local branch="$3"
    local work_items_file

    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1
    _update_work_item_json "$work_items_file" "$item_id" "in_progress" "$branch"
}

increment_work_item_retry_count() {
    local project_dir="$1"
    local item_id="$2"
    local work_items_file

    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1
    _update_work_item_json "$work_items_file" "$item_id" "retry"
}

mark_work_item_awaiting_merge() {
    local project_dir="$1"
    local item_id="$2"
    local branch="$3"
    local pr_url="${4:-}"
    local pr_number="${5:-}"
    local work_items_file

    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1

    if [[ -n "$pr_url" || -n "$pr_number" ]]; then
        _update_work_item_json "$work_items_file" "$item_id" "awaiting_merge_with_pr" "$branch" "$pr_url" "$pr_number"
    else
        _update_work_item_json "$work_items_file" "$item_id" "awaiting_merge_manual" "$branch"
    fi
}

mark_work_item_done() {
    local project_dir="$1"
    local item_id="$2"
    local work_items_file

    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 1
    _update_work_item_json "$work_items_file" "$item_id" "done"
}

render_active_work_item_context() {
    [[ -n "$ACTIVE_WORK_ITEM_ID" ]] || return 1

    cat <<EOF
## Active Work Item

The loop runtime selected this work item for the current iteration. Do not pick a
different task unless you emit \`<promise>DECIDE:...</promise>\` and explain why.

- id: \`$ACTIVE_WORK_ITEM_ID\`
- title: $ACTIVE_WORK_ITEM_TITLE
- status: \`$ACTIVE_WORK_ITEM_STATUS\`
- priority: \`$ACTIVE_WORK_ITEM_PRIORITY\`
- spec: \`$ACTIVE_WORK_ITEM_SPEC\`
- tasks: \`$ACTIVE_WORK_ITEM_TASKS\`
- branch: \`${ACTIVE_WORK_ITEM_BRANCH:-to-be-created}\`
$(if [[ -n "$ACTIVE_WORK_ITEM_TESTING_DETAILS" ]]; then printf '%s\n' "- testing: \`$ACTIVE_WORK_ITEM_TESTING_DETAILS\`"; fi)

Before you output \`<promise>DONE</promise>\`, complete a short self-review pass and
make sure any remaining issues are non-blocking. The loop runtime owns the release
workflow after your implementation succeeds (push, draft PR creation, automatic
merge when possible, manual fallback only if blocked).
EOF
}

reconcile_merged_pull_requests() {
    local project_dir="$1"
    local work_items_file

    work_items_file=$(work_items_file_path "$project_dir")
    [[ -f "$work_items_file" ]] || return 0

    local base_branch="main"
    if declare -F detect_base_branch >/dev/null 2>&1; then
        base_branch=$(detect_base_branch "$project_dir")
    fi

    local candidates
    candidates=$(
        _work_item_python "$work_items_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

for item in data.get("items", []):
    if item.get("status") not in {"awaiting_merge", "pr_open"}:
        continue
    pr_number = item.get("pr_number")
    branch = item.get("branch", "")
    if pr_number in (None, "") and not branch:
        continue
    pr_value = "" if pr_number in (None, "") else str(pr_number)
    print(f"{item.get('id','')}\t{pr_value}\t{item.get('title','')}")
PY
    )

    [[ -n "$candidates" ]] || return 0

    while IFS=$'\t' read -r item_id pr_number item_title; do
        [[ -n "$item_id" ]] || continue

        local item_branch=""
        if set_active_work_item_by_id "$project_dir" "$item_id"; then
            item_branch="$ACTIVE_WORK_ITEM_BRANCH"
        fi

        local merged_state="open"
        if [[ -n "$pr_number" ]] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
            local pr_json
            pr_json=$(cd "$project_dir" && gh pr view "$pr_number" --json number,url,state,mergedAt 2>/dev/null || true)
            if [[ -n "$pr_json" ]]; then
                merged_state=$(
                    _work_item_python <<'PY' "$pr_json"
import json
import sys

data = json.loads(sys.argv[1])
is_merged = bool(data.get("mergedAt")) or data.get("state") == "MERGED"
print("merged" if is_merged else "open")
PY
                )
            fi
        fi

        if [[ "$merged_state" != "merged" && -n "$item_branch" ]]; then
            if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$item_branch"; then
                if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$base_branch" && \
                   git -C "$project_dir" merge-base --is-ancestor "$item_branch" "$base_branch" 2>/dev/null; then
                    merged_state="merged"
                fi
            fi
        fi

        if [[ "$merged_state" = "merged" ]]; then
            mark_work_item_done "$project_dir" "$item_id"
            echo -e "${GREEN}✓ Merge detected for work item ${item_id}${NC}"
            if [[ -n "$item_title" ]]; then
                echo -e "${GREEN}  Merged: $item_title${NC}"
            fi
        fi
    done <<< "$candidates"
}
