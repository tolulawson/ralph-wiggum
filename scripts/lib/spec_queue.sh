#!/bin/bash
#
# Spec selection helpers for build-mode fallback when work-items.json is absent.
#

ACTIVE_SPEC_ID=""
ACTIVE_SPEC_TITLE=""
ACTIVE_SPEC_PATH=""
ACTIVE_SPEC_BRANCH=""
ACTIVE_SPEC_PR_NUMBER=""
ACTIVE_SPEC_PR_URL=""

reset_active_spec() {
    ACTIVE_SPEC_ID=""
    ACTIVE_SPEC_TITLE=""
    ACTIVE_SPEC_PATH=""
    ACTIVE_SPEC_BRANCH=""
    ACTIVE_SPEC_PR_NUMBER=""
    ACTIVE_SPEC_PR_URL=""
}

spec_release_state_file() {
    local project_dir="$1"
    echo "$project_dir/logs/ralph_spec_release_pending.json"
}

spec_is_complete() {
    local spec_file="$1"
    grep -qiE '^[[:space:]]*##[[:space:]]*Status[[:space:]]*:[[:space:]]*COMPLETE[[:space:]]*$' "$spec_file" 2>/dev/null
}

spec_id_from_path() {
    local spec_file="$1"
    local base_name=""
    local parent_name=""

    base_name=$(basename "$spec_file")
    if [[ "$base_name" = "spec.md" ]]; then
        parent_name=$(basename "$(dirname "$spec_file")")
        echo "$parent_name"
        return 0
    fi

    echo "${base_name%.md}"
}

spec_title_from_file() {
    local spec_file="$1"
    local heading=""

    heading=$(grep -m1 -E '^# ' "$spec_file" 2>/dev/null | sed 's/^# //')
    if [[ -n "$heading" ]]; then
        echo "$heading"
        return 0
    fi

    spec_id_from_path "$spec_file"
}

select_next_spec() {
    local project_dir="$1"
    local specs_dir="$project_dir/specs"
    local spec_file=""

    reset_active_spec
    [[ -d "$specs_dir" ]] || return 1

    while IFS= read -r spec_file; do
        [[ -f "$spec_file" ]] || continue
        if spec_is_complete "$spec_file"; then
            continue
        fi

        ACTIVE_SPEC_PATH="$spec_file"
        ACTIVE_SPEC_ID=$(spec_id_from_path "$spec_file")
        ACTIVE_SPEC_TITLE=$(spec_title_from_file "$spec_file")
        return 0
    done < <(find "$specs_dir" -maxdepth 3 -type f -name "*.md" ! -name "tasks.md" | sort)

    return 1
}

render_active_spec_context() {
    [[ -n "$ACTIVE_SPEC_ID" ]] || return 1

    cat <<EOF
## Active Spec

The loop runtime selected this spec for the current iteration. Do not pick a
different spec unless you emit \`<promise>DECIDE:...</promise>\` and explain why.

- id: \`$ACTIVE_SPEC_ID\`
- title: $ACTIVE_SPEC_TITLE
- spec: \`$ACTIVE_SPEC_PATH\`
- branch: \`${ACTIVE_SPEC_BRANCH:-to-be-created}\`

Before you output \`<promise>DONE</promise>\`, make sure the selected spec's
acceptance criteria are fully satisfied and the branch is left review-ready for
the runtime handoff.
EOF
}

load_pending_spec_release() {
    local project_dir="$1"
    local state_file=""
    local result=""

    reset_active_spec
    state_file=$(spec_release_state_file "$project_dir")
    [[ -f "$state_file" ]] || return 1

    result=$(python3 - "$state_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

fields = [
    data.get("id", ""),
    data.get("title", ""),
    data.get("spec", ""),
    data.get("branch", ""),
    "" if data.get("pr_number") in (None, "") else str(data.get("pr_number")),
    data.get("pr_url", ""),
]
print("\x1f".join(fields))
PY
    ) || return 1

    [[ -n "$result" ]] || return 1
    IFS=$'\x1f' read -r ACTIVE_SPEC_ID ACTIVE_SPEC_TITLE ACTIVE_SPEC_PATH ACTIVE_SPEC_BRANCH ACTIVE_SPEC_PR_NUMBER ACTIVE_SPEC_PR_URL <<< "$result"
    [[ -n "$ACTIVE_SPEC_ID" && -n "$ACTIVE_SPEC_BRANCH" ]] || return 1
    return 0
}

write_pending_spec_release() {
    local project_dir="$1"
    local item_id="$2"
    local title="$3"
    local spec_path="$4"
    local branch="$5"
    local pr_number="${6:-}"
    local pr_url="${7:-}"
    local state_file=""

    state_file=$(spec_release_state_file "$project_dir")

    python3 - "$state_file" "$item_id" "$title" "$spec_path" "$branch" "$pr_number" "$pr_url" <<'PY'
import json
import os
import sys

path, item_id, title, spec_path, branch, pr_number, pr_url = sys.argv[1:8]
data = {
    "id": item_id,
    "title": title,
    "spec": spec_path,
    "branch": branch,
    "pr_number": pr_number or None,
    "pr_url": pr_url,
}
tmp_path = f"{path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp_path, path)
PY
}

clear_pending_spec_release() {
    local project_dir="$1"
    local state_file=""

    state_file=$(spec_release_state_file "$project_dir")
    rm -f "$state_file"
}
