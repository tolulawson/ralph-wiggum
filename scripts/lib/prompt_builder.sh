#!/bin/bash
#
# Prompt builder and plan-mode argument parsing helpers.
#
# This keeps prompt templates in templates/ and adds a richer plan-mode
# orchestration layer that can ingest a PRD, notes file, or inline brief.
#

# Optionally load verification profile helpers if the file lives alongside this one.
_PROMPT_BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$_PROMPT_BUILDER_DIR/verification_profiles.sh" ]]; then
    # shellcheck source=./verification_profiles.sh
    source "$_PROMPT_BUILDER_DIR/verification_profiles.sh"
fi
if [[ -f "$_PROMPT_BUILDER_DIR/speckit_runner.sh" ]]; then
    # shellcheck source=./speckit_runner.sh
    source "$_PROMPT_BUILDER_DIR/speckit_runner.sh"
fi

PLAN_PRD_FILE=""
PLAN_NOTES_FILE=""
PLAN_BRIEF=""
PLAN_ITERATION_OVERRIDE=""
PLAN_ARGS_CONSUMED=0
PLAN_INPUT_KIND="repo"
PLAN_INPUT_SUMMARY="Inspect existing repo context and derive planning inputs from current docs/specs."
SPECKIT_STATUS="not-detected"
SPECKIT_PRIMARY_SOURCE="manual-fallback"
SPECKIT_PRIMARY_PATH=""
VENDORED_SPECKIT_DIR=""

reset_plan_mode_state() {
    PLAN_PRD_FILE=""
    PLAN_NOTES_FILE=""
    PLAN_BRIEF=""
    PLAN_ITERATION_OVERRIDE=""
    PLAN_ARGS_CONSUMED=0
    PLAN_INPUT_KIND="repo"
    PLAN_INPUT_SUMMARY="Inspect existing repo context and derive planning inputs from current docs/specs."
    SPECKIT_STATUS="not-detected"
    SPECKIT_PRIMARY_SOURCE="manual-fallback"
    SPECKIT_PRIMARY_PATH=""
    VENDORED_SPECKIT_DIR=""
}

parse_plan_mode_arguments() {
    PLAN_ARGS_CONSUMED=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prd)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --prd requires a file path" >&2
                    return 1
                fi
                PLAN_PRD_FILE="$2"
                PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 2))
                shift 2
                ;;
            --notes)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --notes requires a file path" >&2
                    return 1
                fi
                PLAN_NOTES_FILE="$2"
                PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 2))
                shift 2
                ;;
            --brief)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --brief requires quoted text" >&2
                    return 1
                fi
                if [[ -n "$PLAN_BRIEF" ]]; then
                    PLAN_BRIEF="$PLAN_BRIEF $2"
                else
                    PLAN_BRIEF="$2"
                fi
                PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 2))
                shift 2
                ;;
            --)
                shift
                PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 1))
                if [[ $# -gt 0 ]]; then
                    if [[ -n "$PLAN_BRIEF" ]]; then
                        PLAN_BRIEF="$PLAN_BRIEF $*"
                    else
                        PLAN_BRIEF="$*"
                    fi
                    PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + $#))
                fi
                return 0
                ;;
            -h|--help)
                return 0
                ;;
            -*)
                echo "Error: Unknown plan option: $1" >&2
                return 1
                ;;
            [0-9]*)
                if [[ -z "$PLAN_ITERATION_OVERRIDE" && -z "$PLAN_PRD_FILE" && -z "$PLAN_NOTES_FILE" && -z "$PLAN_BRIEF" ]]; then
                    PLAN_ITERATION_OVERRIDE="$1"
                    PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 1))
                    shift
                else
                    if [[ -n "$PLAN_BRIEF" ]]; then
                        PLAN_BRIEF="$PLAN_BRIEF $1"
                    else
                        PLAN_BRIEF="$1"
                    fi
                    PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + 1))
                    shift
                fi
                ;;
            *)
                if [[ -n "$PLAN_BRIEF" ]]; then
                    PLAN_BRIEF="$PLAN_BRIEF $*"
                else
                    PLAN_BRIEF="$*"
                fi
                PLAN_ARGS_CONSUMED=$((PLAN_ARGS_CONSUMED + $#))
                return 0
                ;;
        esac
    done

    return 0
}

abspath_safe() {
    local input="$1"
    if [[ -z "$input" ]]; then
        return 1
    fi

    if [[ "$input" = /* ]]; then
        echo "$input"
        return 0
    fi

    local dir
    local base
    dir=$(dirname "$input")
    base=$(basename "$input")

    if [[ -d "$dir" ]]; then
        (
            cd "$dir" 2>/dev/null && printf "%s/%s\n" "$(pwd)" "$base"
        )
    else
        return 1
    fi
}

detect_speckit_status() {
    local project_dir="$1"
    local found=()
    local runtime_found=()
    local global_found=()
    local required_skills=(
        "speckit-constitution"
        "speckit-specify"
        "speckit-clarify"
        "speckit-plan"
        "speckit-tasks"
    )
    local has_vendored=true

    VENDORED_SPECKIT_DIR="$project_dir/vendor/speckit-agent-skills/skills"
    for skill in "${required_skills[@]}"; do
        if [[ ! -f "$VENDORED_SPECKIT_DIR/$skill/SKILL.md" ]]; then
            has_vendored=false
            break
        fi
    done

    if [[ "$has_vendored" = true ]]; then
        SPECKIT_STATUS="vendored ($VENDORED_SPECKIT_DIR)"
        SPECKIT_PRIMARY_SOURCE="vendored"
        SPECKIT_PRIMARY_PATH="$VENDORED_SPECKIT_DIR"
        return 0
    fi

    if [[ -d "$project_dir/.specify" ]]; then
        runtime_found+=(".specify")
    fi
    if [[ -f "$project_dir/.claude/commands/speckit.plan.md" ]]; then
        runtime_found+=(".claude")
    fi
    if [[ -f "$project_dir/.codex/prompts/speckit.plan.md" ]]; then
        runtime_found+=(".codex")
    fi
    if [[ -f "$project_dir/.github/prompts/speckit.plan.prompt.md" ]]; then
        runtime_found+=(".github")
    fi
    if [[ -f "$project_dir/.gemini/commands/speckit.plan.toml" ]]; then
        runtime_found+=(".gemini")
    fi
    if [[ -d "$HOME/.claude/skills/speckit-plan" ]]; then
        global_found+=("\$HOME/.claude/skills")
    fi
    if [[ -d "$HOME/.codex/skills/speckit-plan" ]]; then
        global_found+=("\$HOME/.codex/skills")
    fi
    if [[ -d "$HOME/.agents/skills/speckit-plan" ]]; then
        global_found+=("\$HOME/.agents/skills")
    fi

    if [[ ${#runtime_found[@]} -gt 0 ]]; then
        found+=("${runtime_found[@]}")
        SPECKIT_STATUS="detected (${found[*]})"
        SPECKIT_PRIMARY_SOURCE="project-local"
        SPECKIT_PRIMARY_PATH="$project_dir"
    elif [[ ${#global_found[@]} -gt 0 ]]; then
        found+=("${global_found[@]}")
        SPECKIT_STATUS="detected (${found[*]})"
        SPECKIT_PRIMARY_SOURCE="user-global"
        SPECKIT_PRIMARY_PATH="${global_found[0]}"
    else
        SPECKIT_STATUS="not-detected"
        SPECKIT_PRIMARY_SOURCE="manual-fallback"
        SPECKIT_PRIMARY_PATH=""
    fi
}

validate_plan_mode_arguments() {
    local project_dir="$1"
    local input_count=0

    if [[ -n "$PLAN_PRD_FILE" ]]; then
        if [[ ! -f "$PLAN_PRD_FILE" ]]; then
            echo "Error: PRD file not found: $PLAN_PRD_FILE" >&2
            return 1
        fi
        PLAN_PRD_FILE=$(abspath_safe "$PLAN_PRD_FILE")
        input_count=$((input_count + 1))
        PLAN_INPUT_KIND="prd"
        PLAN_INPUT_SUMMARY="Use the provided PRD as the canonical planning source: $PLAN_PRD_FILE"
    fi

    if [[ -n "$PLAN_NOTES_FILE" ]]; then
        if [[ ! -f "$PLAN_NOTES_FILE" ]]; then
            echo "Error: Notes file not found: $PLAN_NOTES_FILE" >&2
            return 1
        fi
        PLAN_NOTES_FILE=$(abspath_safe "$PLAN_NOTES_FILE")
        input_count=$((input_count + 1))
        PLAN_INPUT_KIND="notes"
        PLAN_INPUT_SUMMARY="Use the provided notes as ideation input, normalize them into a structured PRD before decomposition: $PLAN_NOTES_FILE"
    fi

    if [[ -n "$PLAN_BRIEF" ]]; then
        input_count=$((input_count + 1))
        PLAN_INPUT_KIND="brief"
        PLAN_INPUT_SUMMARY="Use the provided inline brief as planning input, normalize it into a structured PRD before decomposition."
    fi

    if [[ $input_count -gt 1 ]]; then
        echo "Error: plan mode accepts only one input source at a time (--prd, --notes, or --brief/bare text)" >&2
        return 1
    fi

    detect_speckit_status "$project_dir"
    return 0
}

prompt_template_path() {
    local mode="$1"
    local project_dir="$2"
    echo "$project_dir/templates/PROMPT_${mode}.md"
}

extract_markdown_section() {
    local file_path="$1"
    local section_name="$2"

    [[ -f "$file_path" ]] || return 1

    awk -v heading="## ${section_name}" '
        $0 == heading { capture = 1; next }
        capture && /^## / { exit }
        capture { print }
    ' "$file_path"
}

append_plan_prompt_context() {
    local prompt_file="$1"
    local project_dir="$2"
    local constitution_path="$project_dir/.specify/memory/constitution.md"
    local canonical_summary

    cat >> "$prompt_file" <<EOF

## Planning Intake

- Input mode: $PLAN_INPUT_KIND
- Intake summary: $PLAN_INPUT_SUMMARY
- Spec Kit assets: $SPECKIT_STATUS
- Spec Kit source preference: $SPECKIT_PRIMARY_SOURCE
- Spec Kit script runner: $(speckit_runner_status_line 2>/dev/null || echo "unavailable")

EOF

    if [[ -n "$PLAN_BRIEF" ]]; then
        cat >> "$prompt_file" <<EOF
### Inline Brief

$PLAN_BRIEF

EOF
    fi

    if [[ "$SPECKIT_PRIMARY_SOURCE" = "vendored" ]]; then
        cat >> "$prompt_file" <<EOF
## Vendored SpecKit Files

Use these in-repo skill files as the canonical planning source of truth:

- \`$VENDORED_SPECKIT_DIR/speckit-constitution/SKILL.md\`
- \`$VENDORED_SPECKIT_DIR/speckit-specify/SKILL.md\`
- \`$VENDORED_SPECKIT_DIR/speckit-clarify/SKILL.md\`
- \`$VENDORED_SPECKIT_DIR/speckit-plan/SKILL.md\`
- \`$VENDORED_SPECKIT_DIR/speckit-tasks/SKILL.md\`

EOF
    fi

    # Append SpecKit direct-script guidance (Phase 8).
    if declare -f speckit_runner_prompt_block >/dev/null 2>&1; then
        speckit_runner_prompt_block >> "$prompt_file"
        echo "" >> "$prompt_file"
    fi

    if [[ "$SPECKIT_PRIMARY_SOURCE" = "vendored" ]]; then
        canonical_summary="Use the vendored in-repo SpecKit files first."
    elif [[ "$SPECKIT_PRIMARY_SOURCE" = "project-local" ]]; then
        canonical_summary="Use project-local SpecKit runtime assets first."
    elif [[ "$SPECKIT_PRIMARY_SOURCE" = "user-global" ]]; then
        canonical_summary="Use user-global installed SpecKit assets first."
    else
        canonical_summary="No executable SpecKit assets detected; emulate the same workflow manually."
    fi

    cat >> "$prompt_file" <<EOF
## Canonical SpecKit Orchestration

Treat this plan run as a Spec-Driven Development orchestration pass.

$canonical_summary

1. If \`$constitution_path\` does not exist, bootstrap or update it first using the
   canonical \`speckit-constitution\` workflow.
2. If the intake is raw notes or an inline brief, first normalize it into a detailed
   PRD at \`planning/PRD.md\` before any feature decomposition.
3. Decompose the PRD into feature-sized, numbered specs under \`specs/\` using
   the canonical SpecKit flow.
4. For each feature, follow this exact order:
   - \`speckit-specify\`
   - \`speckit-clarify\` (only when ambiguities remain)
   - \`speckit-plan\`
   - \`speckit-tasks\`
5. Prefer this asset resolution order:
   - vendored in-repo SpecKit files
   - project-local SpecKit runtime assets
   - user-global installed SpecKit assets
   - manual emulation of the same workflow only as a last resort
6. Ensure each feature ends with clear, bite-sized work items in
   \`specs/<feature>/tasks.md\`.
7. Create or update \`IMPLEMENTATION_PLAN.md\` as a master execution index that:
   - links each generated feature directory
   - summarizes readiness and dependencies
   - identifies the recommended execution order
   - highlights any clarifications or blockers
8. After creating \`IMPLEMENTATION_PLAN.md\`, write \`work-items.json\` at the project
   root using the schema defined in the planning prompt. Set every item's \`status\`
   to \`"pending"\` and \`retry_count\` to \`0\`. Derive \`priority\` from spec ordering
   (001 = priority 1, 002 = priority 2, etc.). Infer \`profile\` from the spec content
   or constitution; default to \`"unknown"\`. List \`verification\` steps appropriate
   for the detected profile. When the spec or constitution provides explicit testing
   requirements, also include a structured \`testing\` object that keeps unit,
   integration, E2E, and device workflows separate. Initialize release fields for
   every item:
   \`branch = ""\`, \`review_status = "pending"\`, \`pr_number = null\`,
   \`pr_url = ""\`, and \`merge_status = "not_requested"\`.
9. Do not implement product code in this mode. Planning artifacts only.

## Output Rules

- Output \`<promise>DONE</promise>\` only after the planning pipeline is complete.
- If planning is blocked on a real external dependency, use
  \`<promise>BLOCKED:reason</promise>\`.
- If planning needs a human choice, use
  \`<promise>DECIDE:question</promise>\`.

EOF
}

append_verification_context_to_build_prompt() {
    local prompt_file="$1"
    local profile="${PREFLIGHT_PROJECT_PROFILE:-unknown}"

    # Only append when we have a known profile to add useful guidance.
    if [[ "$profile" = "unknown" ]]; then
        return 0
    fi

    local stack
    stack=$(verification_stack_summary "$profile")

    local steps
    steps=$(describe_verification_steps "$profile")

    cat >> "$prompt_file" <<EOF

## Verification Profile: ${profile}

The detected project profile is **${profile}**.

Before outputting \`<promise>DONE</promise>\`, run the verification stack for this
profile and confirm each step passes:

${steps}
Abbreviated stack: \`${stack}\`

If a step is not configured or not applicable to the specific change being made,
you may skip it — but note which steps were skipped and why.

EOF
}

append_testing_policy_context_to_build_prompt() {
    local prompt_file="$1"
    local project_dir="$2"
    local constitution_path="$project_dir/.specify/memory/constitution.md"
    local testing_policy

    testing_policy=$(extract_markdown_section "$constitution_path" "Testing Policy" 2>/dev/null || true)
    [[ -n "$testing_policy" ]] || return 0

    cat >> "$prompt_file" <<EOF

## Testing Policy

The constitution defines explicit testing requirements for this project. Use them as
the highest-priority testing instructions after any work-item-specific \`testing\`
details.

Testing precedence:
1. Active work item's \`testing\` object (if present)
2. Constitution \`## Testing Policy\`
3. Active work item's \`verification\` list
4. Generic project profile defaults

$testing_policy

If the constitution lists exact commands for E2E, device, or manual verification,
run them separately from unit or integration tests and report each category clearly.

EOF
}

append_plan_profile_context() {
    local prompt_file="$1"
    local profile="${PREFLIGHT_PROJECT_PROFILE:-unknown}"

    local stack
    stack=$(verification_stack_summary "$profile")

    cat >> "$prompt_file" <<EOF

## Detected Project Profile: ${profile}

The auto-detected project profile is **${profile}** (from project structure analysis).
Use this as the default profile when populating the \`profile\` field of work items
unless a spec or the constitution specifies a different profile explicitly.

Verification stack for **${profile}**: \`${stack}\`

When writing work-items.json, assign appropriate \`verification\` arrays to each item
based on this profile. Reference verification_profiles.sh for the canonical lists:
- web:     ["lint", "typecheck", "unit-tests", "build", "e2e"]
- expo:    ["expo-doctor", "metro-export", "typecheck", "unit-tests", "simulator-smoke-test", "maestro-flows", "device-mcp", "agent-device-skills"]
- backend: ["lint", "typecheck", "unit-tests", "integration-tests", "build"]
- library: ["lint", "typecheck", "unit-tests", "build", "package-exports"]

If the constitution defines a \`## Testing Policy\`, reflect it in a structured
\`testing\` object on each relevant work item so exact E2E and device checks remain
separate from the generic \`verification\` categories.

EOF
}

append_testing_policy_context_to_plan_prompt() {
    local prompt_file="$1"
    local project_dir="$2"
    local constitution_path="$project_dir/.specify/memory/constitution.md"
    local testing_policy

    testing_policy=$(extract_markdown_section "$constitution_path" "Testing Policy" 2>/dev/null || true)
    [[ -n "$testing_policy" ]] || return 0

    cat >> "$prompt_file" <<EOF

## Testing Policy Overrides

The constitution includes explicit testing guidance. Use it when generating both the
\`verification\` array and any structured \`testing\` details for work items.

When the policy distinguishes unit, integration, E2E, device, or manual testing,
preserve that separation in \`work-items.json\` rather than collapsing everything
into a single generic test step.

$testing_policy

EOF
}

build_runtime_prompt() {
    local mode="$1"
    local project_dir="$2"
    local log_dir="$3"
    local template_path
    local prompt_file

    template_path=$(prompt_template_path "$mode" "$project_dir")
    prompt_file="$log_dir/ralph_${mode}_prompt_$(date '+%Y%m%d_%H%M%S').md"

    if [[ -f "$template_path" ]]; then
        cat "$template_path" > "$prompt_file"
    else
        if [[ "$mode" = "plan" ]]; then
            cat > "$prompt_file" <<'EOF'
# Ralph Loop — Planning Mode

Read the project constitution if it exists. If it does not exist, create it first.
Create planning artifacts only. Do not implement product code.
When planning is complete, output `<promise>DONE</promise>`.
EOF
        else
            cat > "$prompt_file" <<'EOF'
# Ralph Loop — Build Mode

Read the project constitution and implement the highest-priority incomplete work item.
Verify acceptance criteria before outputting `<promise>DONE</promise>`.
EOF
        fi
    fi

    if [[ "$mode" = "plan" ]]; then
        append_plan_prompt_context "$prompt_file" "$project_dir"
        append_plan_profile_context "$prompt_file"
        append_testing_policy_context_to_plan_prompt "$prompt_file" "$project_dir"
    else
        append_verification_context_to_build_prompt "$prompt_file"
        append_testing_policy_context_to_build_prompt "$prompt_file" "$project_dir"
    fi

    echo "$prompt_file"
}
