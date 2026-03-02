#!/bin/bash
#
# Direct SpecKit script execution helpers.
#
# Discovers and invokes SpecKit bash helpers directly when present in the
# target project.  Falls back to prompt-driven emulation (the existing AI
# prompt approach) when project-local scripts are not available.
#
# Priority order for script resolution:
#   1. Project-local: $PROJECT_DIR/.specify/scripts/bash/
#   2. Prompt-driven emulation (fallback)
#
# Known SpecKit bash helpers (referenced by vendored SKILL.md files):
#   create-new-feature.sh   Creates the feature scaffold directory and spec stub.
#   setup-plan.sh           Sets up the plan directory for a given feature.
#   check-prereqs.sh        Verifies SpecKit prerequisites for the project.
#   update-context.sh       Updates the agent context / memory files.
#

SPECKIT_SCRIPTS_DIR=""           # Absolute path once discovered; empty when unavailable.
SPECKIT_RUNNER_STATUS="unavailable"  # "direct" | "unavailable"

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# Discover SpecKit bash scripts for the given project directory.
# Sets SPECKIT_SCRIPTS_DIR and SPECKIT_RUNNER_STATUS.
discover_speckit_scripts() {
    local project_dir="$1"
    SPECKIT_SCRIPTS_DIR=""
    SPECKIT_RUNNER_STATUS="unavailable"

    local candidate="$project_dir/.specify/scripts/bash"
    if [[ -d "$candidate" ]]; then
        SPECKIT_SCRIPTS_DIR="$candidate"
        SPECKIT_RUNNER_STATUS="direct"
        return 0
    fi

    return 0
}

# Return 0 if a given SpecKit helper script is available.
has_speckit_script() {
    local script_name="$1"
    [[ -n "$SPECKIT_SCRIPTS_DIR" && -f "$SPECKIT_SCRIPTS_DIR/$script_name" ]]
}

# ---------------------------------------------------------------------------
# Internal runner
# ---------------------------------------------------------------------------

# Execute a SpecKit bash helper if present.
# Returns 0 if the script ran (exit code from the script), 1 if not found.
_run_speckit_script() {
    local script_name="$1"
    shift
    local args=("$@")

    if ! has_speckit_script "$script_name"; then
        return 1
    fi

    local script_path="$SPECKIT_SCRIPTS_DIR/$script_name"

    if [[ ! -x "$script_path" ]]; then
        chmod +x "$script_path" 2>/dev/null || true
    fi

    "$script_path" "${args[@]}"
}

# ---------------------------------------------------------------------------
# Wrapper helpers
# ---------------------------------------------------------------------------

# Run SpecKit prerequisite checks.
# Returns 0 if the script ran successfully, 1 if not available or failed.
run_speckit_prereqs() {
    _run_speckit_script "check-prereqs.sh"
}

# Update the agent context / memory files.
# Returns 0 if the script ran, 1 if not available.
run_speckit_context_update() {
    _run_speckit_script "update-context.sh"
}

# Create a new feature scaffold.
# Args: feature-name [extra args forwarded to the script]
# Returns 0 if the script ran, 1 if not available (caller falls back to AI).
run_speckit_feature_create() {
    local feature_name="$1"
    shift
    local extra=("$@")
    _run_speckit_script "create-new-feature.sh" "$feature_name" "${extra[@]}"
}

# Set up a plan directory for the given feature.
# Args: feature-dir
# Returns 0 if the script ran, 1 if not available.
run_speckit_plan_setup() {
    local feature_dir="$1"
    _run_speckit_script "setup-plan.sh" "$feature_dir"
}

# ---------------------------------------------------------------------------
# Prompt context helpers
# ---------------------------------------------------------------------------

# Emit a one-line status string suitable for display in startup banners.
speckit_runner_status_line() {
    if [[ "$SPECKIT_RUNNER_STATUS" = "direct" ]]; then
        echo "direct ($SPECKIT_SCRIPTS_DIR)"
    else
        echo "prompt emulation (no .specify/scripts/bash/ found)"
    fi
}

# Emit a paragraph describing script availability for inclusion in AI prompts.
# When scripts are present, instructs the agent to prefer calling them.
# When absent, instructs the agent to emulate the SpecKit workflow manually.
speckit_runner_prompt_block() {
    if [[ "$SPECKIT_RUNNER_STATUS" = "direct" ]]; then
        cat <<EOF
## Direct SpecKit Script Execution

SpecKit bash helpers are available at: \`$SPECKIT_SCRIPTS_DIR\`

**Prefer calling these scripts directly** (via the Bash tool) instead of
manually creating feature directories or scaffolding files.  The helpers handle
directory layout, template expansion, and numbering automatically.

Available helpers (call with \`bash <path>\` or \`chmod +x\` first):

- \`$SPECKIT_SCRIPTS_DIR/create-new-feature.sh\`  — scaffold a new feature directory
- \`$SPECKIT_SCRIPTS_DIR/setup-plan.sh\`          — set up the plan dir for a feature
- \`$SPECKIT_SCRIPTS_DIR/check-prereqs.sh\`        — verify SpecKit prerequisites
- \`$SPECKIT_SCRIPTS_DIR/update-context.sh\`       — refresh agent context / memory

Only fall back to manual file creation when a helper script does not exist.
EOF
    else
        cat <<EOF
## SpecKit Script Execution

No SpecKit bash helpers found at \`.specify/scripts/bash/\`.
Emulate the canonical SpecKit workflow manually:
- Create feature directories under \`specs/<feature>/\` yourself.
- Use the vendored SKILL.md files as the authoritative workflow guide.
EOF
    fi
}
