#!/bin/bash
#
# Shared preflight module for the Ralph Loop.
#
# Runs essential checks before any build iteration.
# Fails fast with clear messages if required prerequisites are missing.
# Emits warnings for optional tooling that is missing but non-fatal.
#

# Profile constants
PROFILE_WEB="web"
PROFILE_EXPO="expo"
PROFILE_BACKEND="backend"
PROFILE_LIBRARY="library"
PROFILE_UNKNOWN="unknown"

PREFLIGHT_PROJECT_PROFILE="$PROFILE_UNKNOWN"
PREFLIGHT_WARNINGS=()
PREFLIGHT_ERRORS=()

# Detect the project profile from constitution or project structure.
# Writes to PREFLIGHT_PROJECT_PROFILE.
detect_project_profile() {
    local project_dir="$1"
    local constitution="$2"

    # Check constitution for an explicit profile declaration: "profile: expo"
    if [[ -f "$constitution" ]]; then
        local profile_line
        profile_line=$(grep -iE '^\s*profile\s*:\s*\S+' "$constitution" 2>/dev/null | head -1 \
                       | tr '[:upper:]' '[:lower:]' \
                       | sed 's/.*profile[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
        case "$profile_line" in
            web|expo|backend|library)
                PREFLIGHT_PROJECT_PROFILE="$profile_line"
                return 0
                ;;
        esac
    fi

    # Auto-detect from project structure: Expo
    if [[ -f "$project_dir/app.json" || -f "$project_dir/app.config.js" || -f "$project_dir/app.config.ts" ]]; then
        if grep -q '"expo"' "$project_dir/app.json" 2>/dev/null ||
           [[ -f "$project_dir/app.config.js" ]] || [[ -f "$project_dir/app.config.ts" ]]; then
            PREFLIGHT_PROJECT_PROFILE="$PROFILE_EXPO"
            return 0
        fi
    fi

    if [[ -f "$project_dir/package.json" ]]; then
        # Expo via package.json dependency
        if grep -qE '"expo"\s*:' "$project_dir/package.json" 2>/dev/null; then
            PREFLIGHT_PROJECT_PROFILE="$PROFILE_EXPO"
            return 0
        fi
        # Web frameworks
        if grep -qE '"(react|react-dom|next|vite|angular|svelte|vue)"' "$project_dir/package.json" 2>/dev/null; then
            PREFLIGHT_PROJECT_PROFILE="$PROFILE_WEB"
            return 0
        fi
    fi

    # Backend by convention
    if [[ -d "$project_dir/src/server" || -d "$project_dir/src/api" \
       || -f "$project_dir/server.js"  || -f "$project_dir/server.ts" \
       || -f "$project_dir/main.py"    || -f "$project_dir/app.py" ]]; then
        PREFLIGHT_PROJECT_PROFILE="$PROFILE_BACKEND"
        return 0
    fi

    # Library: has package.json but no obvious app entry points
    if [[ -f "$project_dir/package.json" ]]; then
        if grep -q '"main"' "$project_dir/package.json" 2>/dev/null &&
           ! grep -qE '"(start|serve)"' "$project_dir/package.json" 2>/dev/null; then
            PREFLIGHT_PROJECT_PROFILE="$PROFILE_LIBRARY"
            return 0
        fi
    fi

    PREFLIGHT_PROJECT_PROFILE="$PROFILE_UNKNOWN"
}

# Check that the working directory is inside a git repository.
check_git_repo() {
    local project_dir="$1"
    if ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
        PREFLIGHT_ERRORS+=("Not a git repository: $project_dir — initialise with 'git init' and commit at least once")
        return 1
    fi
    return 0
}

# Validate the constitution presence.
# In build mode it is required because it is the policy source of truth.
# In plan mode we warn but allow the loop to continue.
check_constitution() {
    local constitution="$1"
    local mode="${2:-build}"

    if [[ -f "$constitution" ]]; then
        return 0
    fi

    if [[ "$mode" = "build" ]]; then
        PREFLIGHT_ERRORS+=("Constitution not found at $constitution — create it before running build mode")
        return 1
    fi

    if [[ "$mode" = "plan" ]]; then
        PREFLIGHT_WARNINGS+=("Constitution not found at $constitution — run the guided setup or see CLAUDE.md")
    fi
}

# Fail if there is no actionable work source (build mode only).
check_work_source() {
    local project_dir="$1"
    local has_work_items=false
    local has_plan=false
    local has_specs=false

    [[ -f "$project_dir/work-items.json" ]] && has_work_items=true
    [[ -f "$project_dir/IMPLEMENTATION_PLAN.md" ]] && has_plan=true

    if [[ -d "$project_dir/specs" ]]; then
        local count
        count=$(find "$project_dir/specs" -maxdepth 3 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        [[ "$count" -gt 0 ]] && has_specs=true
    fi

    if [[ "$has_work_items" = false && "$has_plan" = false && "$has_specs" = false ]]; then
        PREFLIGHT_ERRORS+=("No work source: create specs/*.md files, an IMPLEMENTATION_PLAN.md, or a work-items.json before running build mode")
        return 1
    fi
    return 0
}

# Expo-specific tool checks.
check_expo_tooling() {
    local project_dir="$1"

    if ! command -v node >/dev/null 2>&1; then
        PREFLIGHT_WARNINGS+=("Expo: 'node' not found — required for Metro bundler (install Node.js)")
    fi

    if ! command -v watchman >/dev/null 2>&1; then
        PREFLIGHT_WARNINGS+=("Expo: 'watchman' not found — Metro bundler may be slow (brew install watchman)")
    fi

    # iOS tooling — macOS only
    if [[ "$(uname)" = "Darwin" ]]; then
        if ! command -v xcodebuild >/dev/null 2>&1; then
            PREFLIGHT_WARNINGS+=("Expo: 'xcodebuild' not found — iOS simulator builds unavailable (install Xcode from App Store)")
        else
            if ! xcrun simctl list >/dev/null 2>&1; then
                PREFLIGHT_WARNINGS+=("Expo: iOS Simulator unavailable — check Xcode installation (xcode-select --install)")
            fi
        fi
    fi

    # Android tooling
    if ! command -v adb >/dev/null 2>&1; then
        PREFLIGHT_WARNINGS+=("Expo: 'adb' not found — Android emulator builds unavailable (install Android SDK / Android Studio)")
    fi

    # expo-doctor (non-blocking, runs in project directory)
    if command -v npx >/dev/null 2>&1; then
        if ! (cd "$project_dir" && npx --yes expo-doctor --non-interactive >/dev/null 2>&1); then
            PREFLIGHT_WARNINGS+=("Expo: expo-doctor reported issues — run 'npx expo-doctor' to review before building")
        fi
    else
        PREFLIGHT_WARNINGS+=("Expo: 'npx' not found — cannot run expo-doctor preflight check")
    fi
}

# Web-profile tool checks.
check_web_tooling() {
    if ! command -v node >/dev/null 2>&1; then
        PREFLIGHT_WARNINGS+=("Web: 'node' not found — required for web project tooling (install Node.js)")
    fi
}

# Backend-profile tool checks.
check_backend_tooling() {
    local has_runtime=false
    command -v node >/dev/null 2>&1    && has_runtime=true
    command -v python3 >/dev/null 2>&1 && has_runtime=true
    command -v go >/dev/null 2>&1      && has_runtime=true
    command -v ruby >/dev/null 2>&1    && has_runtime=true
    command -v java >/dev/null 2>&1    && has_runtime=true

    if [[ "$has_runtime" = false ]]; then
        PREFLIGHT_WARNINGS+=("Backend: no recognised runtime found (node, python3, go, ruby, java) — build validation may fail")
    fi
}

# Dispatch profile-aware tooling checks.
check_profile_tooling() {
    local project_dir="$1"
    local profile="$2"

    case "$profile" in
        "$PROFILE_EXPO")    check_expo_tooling "$project_dir" ;;
        "$PROFILE_WEB")     check_web_tooling ;;
        "$PROFILE_BACKEND") check_backend_tooling ;;
        "$PROFILE_LIBRARY") : ;; # no extra tooling required beyond the provider CLI
    esac
}

# Main preflight entry point.
# Args: project_dir constitution [mode] [fail_on_error]
run_preflight() {
    local project_dir="$1"
    local constitution="$2"
    local mode="${3:-build}"
    local fail_on_error="${4:-true}"

    PREFLIGHT_WARNINGS=()
    PREFLIGHT_ERRORS=()

    check_git_repo "$project_dir"
    check_constitution "$constitution" "$mode"

    if [[ "$mode" = "build" ]]; then
        check_work_source "$project_dir"
    fi

    detect_project_profile "$project_dir" "$constitution"
    check_profile_tooling "$project_dir" "$PREFLIGHT_PROJECT_PROFILE"

    local n_errors=${#PREFLIGHT_ERRORS[@]}
    local n_warnings=${#PREFLIGHT_WARNINGS[@]}

    if [[ $n_warnings -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Preflight warnings:${NC}"
        for w in "${PREFLIGHT_WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC}  $w"
        done
    fi

    if [[ $n_errors -gt 0 ]]; then
        echo ""
        echo -e "${RED}Preflight failed — fix the issues below before running the loop:${NC}"
        for e in "${PREFLIGHT_ERRORS[@]}"; do
            echo -e "  ${RED}✗${NC}  $e"
        done
        if [[ "$fail_on_error" = true ]]; then
            return 1
        fi
    fi

    if [[ $n_errors -eq 0 ]]; then
        if [[ $n_warnings -eq 0 ]]; then
            echo -e "  ${GREEN}✓${NC}  Preflight OK"
        else
            echo -e "  ${GREEN}✓${NC}  Preflight OK (warnings above are non-fatal)"
        fi
    fi

    if [[ "$PREFLIGHT_PROJECT_PROFILE" != "$PROFILE_UNKNOWN" ]]; then
        echo -e "${BLUE}Profile:${NC}  $PREFLIGHT_PROJECT_PROFILE"
    fi

    return 0
}
