#!/bin/bash
#
# Branching and PR workflow helpers for the Ralph loop.
#

RALPH_BASE_BRANCH="${RALPH_BASE_BRANCH:-main}"

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
    target_branch="${branch_hint:-ralph/${item_id}}"

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

    local base_branch
    base_branch=$(detect_base_branch "$project_dir")

    if [[ -n "$pr_number" ]] && gh_pr_ready; then
        if (cd "$project_dir" && gh pr merge "$pr_number" --merge --delete-branch=false) >/dev/null 2>&1; then
            sync_local_base_branch "$project_dir" || return 1
            if [[ -n "$branch" ]] && git -C "$project_dir" merge-base --is-ancestor "$branch" "$base_branch" 2>/dev/null; then
                return 0
            fi
            return 1
        fi
    fi

    if [[ -z "$branch" ]]; then
        return 1
    fi

    if ! git -C "$project_dir" show-ref --verify --quiet "refs/heads/$branch"; then
        return 1
    fi

    if ! sync_local_base_branch "$project_dir"; then
        return 1
    fi

    if git -C "$project_dir" merge-base --is-ancestor "$branch" "$base_branch" 2>/dev/null; then
        return 0
    fi

    git -C "$project_dir" merge --no-ff --no-edit "$branch" >/dev/null 2>&1 || return 1

    if git_remote_branch_exists "$project_dir" "$base_branch"; then
        git -C "$project_dir" push origin "$base_branch" >/dev/null 2>&1 || return 1
    fi

    return 0
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
