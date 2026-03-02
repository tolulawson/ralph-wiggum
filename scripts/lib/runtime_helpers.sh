#!/bin/bash
#
# Shared runtime helpers for provider loop scripts.
#

PROMISE_DONE_PATTERN='<promise>(ALL_)?DONE</promise>'
PROMISE_BLOCKED_PATTERN='<promise>BLOCKED:[^<]*</promise>'
PROMISE_DECIDE_PATTERN='<promise>DECIDE:[^<]*</promise>'

LAST_PROMISE_SIGNAL="NONE"
LAST_PROMISE_PAYLOAD=""
LAST_PROMISE_SOURCE=""

EXIT_MAX_ITERATIONS=1
EXIT_BLOCKED=2
EXIT_DECIDE=3
EXIT_PROVIDER_ERROR=4

reset_promise_context() {
    LAST_PROMISE_SIGNAL="NONE"
    LAST_PROMISE_PAYLOAD=""
    LAST_PROMISE_SOURCE=""
}

parse_promise_signal_from_text() {
    local content="$1"
    reset_promise_context

    if [[ -z "$content" ]]; then
        return 0
    fi

    if echo "$content" | grep -qE "$PROMISE_DONE_PATTERN"; then
        local match
        match=$(echo "$content" | grep -oE "$PROMISE_DONE_PATTERN" | tail -1)
        if [[ "$match" = "<promise>ALL_DONE</promise>" ]]; then
            LAST_PROMISE_SIGNAL="ALL_DONE"
        else
            LAST_PROMISE_SIGNAL="DONE"
        fi
        return 0
    fi

    if echo "$content" | grep -qE "$PROMISE_BLOCKED_PATTERN"; then
        local blocked_match
        blocked_match=$(echo "$content" | grep -oE "$PROMISE_BLOCKED_PATTERN" | head -1)
        LAST_PROMISE_SIGNAL="BLOCKED"
        LAST_PROMISE_PAYLOAD=$(echo "$blocked_match" | sed 's/<promise>BLOCKED://;s/<\/promise>//')
        return 0
    fi

    if echo "$content" | grep -qE "$PROMISE_DECIDE_PATTERN"; then
        local decide_match
        decide_match=$(echo "$content" | grep -oE "$PROMISE_DECIDE_PATTERN" | head -1)
        LAST_PROMISE_SIGNAL="DECIDE"
        LAST_PROMISE_PAYLOAD=$(echo "$decide_match" | sed 's/<promise>DECIDE://;s/<\/promise>//')
        return 0
    fi
}

detect_promise_signal_from_files() {
    local file
    reset_promise_context

    for file in "$@"; do
        if [[ -n "$file" && -f "$file" ]]; then
            parse_promise_signal_from_text "$(cat "$file" 2>/dev/null)"
            if [[ "$LAST_PROMISE_SIGNAL" != "NONE" ]]; then
                LAST_PROMISE_SOURCE="$file"
                return 0
            fi
        fi
    done

    return 0
}

has_completion_promise() {
    [[ "$LAST_PROMISE_SIGNAL" = "DONE" || "$LAST_PROMISE_SIGNAL" = "ALL_DONE" ]]
}

has_help_promise() {
    [[ "$LAST_PROMISE_SIGNAL" = "BLOCKED" || "$LAST_PROMISE_SIGNAL" = "DECIDE" ]]
}

print_blocked_signal() {
    local provider="$1"
    local message="$2"

    echo ""
    echo -e "${RED}⚠ ${provider} reported BLOCKED${NC}"
    echo -e "${YELLOW}Reason:${NC} ${message}"
    echo -e "${YELLOW}Resolve the blocker, then rerun the loop to continue.${NC}"
}

print_decide_signal() {
    local provider="$1"
    local message="$2"

    echo ""
    echo -e "${PURPLE}⚠ ${provider} needs a decision${NC}"
    echo -e "${YELLOW}Question:${NC} ${message}"
    echo -e "${YELLOW}Make the decision, update the relevant files if needed, then rerun the loop.${NC}"
}

push_branch_if_needed() {
    local branch="$1"

    git push origin "$branch" 2>/dev/null || {
        if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
            echo -e "${YELLOW}Push failed, creating remote branch...${NC}"
            git push -u origin "$branch" 2>/dev/null || true
        elif git log "origin/$branch"..HEAD --oneline 2>/dev/null | grep -q .; then
            echo -e "${YELLOW}Push failed, creating remote branch...${NC}"
            git push -u origin "$branch" 2>/dev/null || true
        fi
    }
}
