#!/bin/bash
#
# Branching and PR workflow helpers for the Ralph loop.
#

RALPH_BASE_BRANCH="${RALPH_BASE_BRANCH:-main}"
RELEASE_RESULT_STATUS=""
RELEASE_RESULT_PR_NUMBER=""
RELEASE_RESULT_PR_URL=""

detect_base_branch() {
    local project_dir="$1"

    if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$RALPH_BASE_BRANCH"; then
        echo "$RALPH_BASE_BRANCH"
        return 0
    fi

    local remote_head
    remote_head=$(git -C "$project_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n "$remote_head" ]]; then
        basename "$remote_head"
        return 0
    fi

    echo "$RALPH_BASE_BRANCH"
}

sanitize_branch_component() {
    local value="$1"

    value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    value=$(printf '%s' "$value" | sed 's/[^a-z0-9._-]/-/g')
    value=$(printf '%s' "$value" | sed 's/--*/-/g; s/^-//; s/-$//')
    printf '%s' "$value"
}

spec_branch_component_from_path() {
    local spec_path="$1"
    local relative=""
    local parent_name=""
    local file_name=""

    [[ -n "$spec_path" ]] || return 1

    relative="${spec_path#*specs/}"
    if [[ "$relative" = "$spec_path" ]]; then
        relative=$(basename "$spec_path")
    fi

    file_name=$(basename "$relative")
    if [[ "$file_name" = "spec.md" ]]; then
        parent_name=$(basename "$(dirname "$relative")")
        sanitize_branch_component "$parent_name"
        return 0
    fi

    sanitize_branch_component "${file_name%.md}"
}

derive_work_branch_name() {
    local item_id="$1"
    local spec_path="${2:-}"
    local branch_hint="${3:-}"
    local spec_component=""
    local item_component=""

    if [[ -n "$branch_hint" ]]; then
        echo "$branch_hint"
        return 0
    fi

    spec_component=$(spec_branch_component_from_path "$spec_path" 2>/dev/null || true)
    item_component=$(sanitize_branch_component "$item_id")

    if [[ -n "$spec_component" ]]; then
        if [[ -n "$item_component" && "$item_component" != "$spec_component" ]]; then
            echo "ralph/${spec_component}--${item_component}"
        else
            echo "ralph/${spec_component}"
        fi
        return 0
    fi

    if [[ -n "$item_component" ]]; then
        echo "ralph/${item_component}"
        return 0
    fi

    echo ""
}

worktree_is_clean() {
    local project_dir="$1"

    git -C "$project_dir" diff --quiet --no-ext-diff -- 2>/dev/null || return 1
    git -C "$project_dir" diff --cached --quiet --no-ext-diff -- 2>/dev/null || return 1
    return 0
}

ensure_work_item_branch() {
    local project_dir="$1"
    local item_id="$2"
    local branch_hint="${3:-}"

    local base_branch
    local current_branch
    local target_branch

    base_branch=$(detect_base_branch "$project_dir")
    current_branch=$(git -C "$project_dir" branch --show-current 2>/dev/null || echo "$base_branch")
    target_branch=$(derive_work_branch_name "$item_id" "" "$branch_hint")

    if [[ "$current_branch" = "$target_branch" ]]; then
        echo "$target_branch"
        return 0
    fi

    if [[ "$current_branch" != "$base_branch" ]]; then
        echo -e "${RED}Error: refusing to switch branches from '$current_branch' while task '$item_id' expects '$target_branch'.${NC}"
        echo -e "${YELLOW}Return to '$base_branch' or finish the current branch before continuing.${NC}"
        return 1
    fi

    if ! worktree_is_clean "$project_dir"; then
        echo -e "${RED}Error: cannot create or switch task branches with tracked changes on '$base_branch'.${NC}"
        echo -e "${YELLOW}Commit, stash, or clean staged/modified files before starting the next task.${NC}"
        return 1
    fi

    if git -C "$project_dir" show-ref --verify --quiet "refs/heads/$target_branch"; then
        git -C "$project_dir" switch "$target_branch" >/dev/null 2>&1 || {
            echo -e "${RED}Error: failed to switch to existing branch '$target_branch'.${NC}"
            return 1
        }
    else
        git -C "$project_dir" switch -c "$target_branch" "$base_branch" >/dev/null 2>&1 || {
            echo -e "${RED}Error: failed to create branch '$target_branch' from '$base_branch'.${NC}"
            return 1
        }
    fi

    echo "$target_branch"
}

gh_pr_ready() {
    command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

git_remote_branch_exists() {
    local project_dir="$1"
    local branch="$2"

    git -C "$project_dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

build_pull_request_title() {
    local item_id="$1"
    local item_title="$2"

    if [[ -n "$item_title" ]]; then
        echo "[$item_id] $item_title"
    else
        echo "$item_id"
    fi
}

build_pull_request_body() {
    local item_id="$1"
    local item_title="$2"
    local item_spec="$3"
    local item_tasks="$4"

    cat <<EOF
## Ralph Work Item

- id: \`$item_id\`
- title: $item_title
- spec: \`$item_spec\`
- tasks: \`$item_tasks\`

This PR was opened automatically by the Ralph loop after local implementation,
verification, and self-review completed for this task.
EOF
}

ensure_draft_pull_request() {
    local project_dir="$1"
    local branch="$2"
    local pr_title="$3"
    local pr_body="$4"
    local base_branch

    gh_pr_ready || return 2

    base_branch=$(detect_base_branch "$project_dir")

    local existing_json
    existing_json=$(cd "$project_dir" && gh pr view --head "$branch" --json number,url,state,mergedAt 2>/dev/null || true)
    if [[ -z "$existing_json" ]]; then
        (cd "$project_dir" && gh pr create --draft --base "$base_branch" --head "$branch" --title "$pr_title" --body "$pr_body") >/dev/null 2>&1 || return 1
        existing_json=$(cd "$project_dir" && gh pr view --head "$branch" --json number,url,state,mergedAt 2>/dev/null || true)
        [[ -n "$existing_json" ]] || return 1
    fi

    _work_item_python "$existing_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
merged = bool(data.get("mergedAt")) or data.get("state") == "MERGED"
status = "merged" if merged else "open"
number = "" if data.get("number") is None else str(data.get("number"))
url = data.get("url", "")
print(f"{number}\t{url}\t{status}")
PY
}

sync_local_base_branch() {
    local project_dir="$1"
    local base_branch

    base_branch=$(detect_base_branch "$project_dir")

    git -C "$project_dir" switch "$base_branch" >/dev/null 2>&1 || return 1

    if git_remote_branch_exists "$project_dir" "$base_branch"; then
        git -C "$project_dir" pull --ff-only origin "$base_branch" >/dev/null 2>&1 || return 1
    fi

    return 0
}

merge_work_item_release() {
    local project_dir="$1"
    local item_id="$2"
    local branch="$3"
    local pr_number="${4:-}"

    if [[ -n "$pr_number" ]] && gh_pr_ready; then
        if (cd "$project_dir" && gh pr merge "$pr_number" --merge --delete-branch=false) >/dev/null 2>&1; then
            sync_local_base_branch "$project_dir" || return 1
            return 0
        fi
    fi

    return 1
}

reset_release_result() {
    RELEASE_RESULT_STATUS=""
    RELEASE_RESULT_PR_NUMBER=""
    RELEASE_RESULT_PR_URL=""
}

perform_work_item_release() {
    local project_dir="$1"
    local item_id="$2"
    local branch="$3"
    local item_title="${4:-}"
    local item_spec="${5:-}"
    local item_tasks="${6:-}"
    local existing_pr_number="${7:-}"
    local existing_pr_url="${8:-}"

    reset_release_result
    RELEASE_RESULT_PR_NUMBER="$existing_pr_number"
    RELEASE_RESULT_PR_URL="$existing_pr_url"

    if [[ -n "$branch" ]] && declare -F push_branch_if_needed >/dev/null 2>&1; then
        if ! push_branch_if_needed "$branch" "$project_dir"; then
            RELEASE_RESULT_STATUS="awaiting_merge"
            return 1
        fi
    fi

    local pr_title
    local pr_body
    local pr_info=""
    local pr_number=""
    local pr_url=""
    local pr_status=""

    pr_title=$(build_pull_request_title "$item_id" "$item_title")
    pr_body=$(build_pull_request_body "$item_id" "$item_title" "$item_spec" "$item_tasks")

    if pr_info=$(ensure_draft_pull_request "$project_dir" "$branch" "$pr_title" "$pr_body"); then
        IFS=$'\t' read -r pr_number pr_url pr_status <<< "$pr_info"
        RELEASE_RESULT_PR_NUMBER="$pr_number"
        RELEASE_RESULT_PR_URL="$pr_url"

        if [[ "$pr_status" = "merged" ]]; then
            sync_local_base_branch "$project_dir" || {
                RELEASE_RESULT_STATUS="awaiting_merge"
                return 1
            }
            RELEASE_RESULT_STATUS="merged"
            return 0
        fi

        if merge_work_item_release "$project_dir" "$item_id" "$branch" "$pr_number"; then
            RELEASE_RESULT_STATUS="merged"
            return 0
        fi

        RELEASE_RESULT_STATUS="awaiting_merge"
        return 1
    fi

    RELEASE_RESULT_STATUS="awaiting_merge"
    return 1
}

print_awaiting_merge_message() {
    local item_id="$1"
    local branch="$2"
    local pr_number="${3:-}"
    local pr_url="${4:-}"
    local project_dir="${5:-$(pwd)}"
    local action_text="${6:-Merge this PR manually into}"

    echo ""
    echo -e "${YELLOW}⏸ Work item '${item_id}' is ready and awaiting merge.${NC}"
    echo -e "${YELLOW}Branch:${NC} $branch"
    if [[ -n "$pr_number" ]]; then
        echo -e "${YELLOW}PR:${NC}     #$pr_number"
    fi
    if [[ -n "$pr_url" ]]; then
        echo -e "${YELLOW}URL:${NC}    $pr_url"
    fi
    echo -e "${YELLOW}${action_text} $(detect_base_branch "$project_dir"), return to that branch, and rerun the loop.${NC}"
}
