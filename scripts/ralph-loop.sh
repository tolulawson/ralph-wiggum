#!/bin/bash
#
# Unified Ralph Loop entrypoint.
#
# Usage:
#   ./scripts/ralph-loop.sh [--runtime claude|codex|gemini|copilot] [--model MODEL] [MAX_ITERATIONS]
#   ./scripts/ralph-loop.sh [--runtime ...] [--model MODEL] plan [PLAN OPTIONS]
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
CONSTITUTION="$PROJECT_DIR/.specify/memory/constitution.md"

# Configuration
MAX_ITERATIONS=0
MODE="build"
RUNTIME="${RALPH_RUNTIME:-claude}"
MODEL_OVERRIDE=""
TAIL_LINES=5
TAIL_RENDERED_LINES=0
ROLLING_OUTPUT_LINES=5
ROLLING_OUTPUT_INTERVAL=10
ROLLING_RENDERED_LINES=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$LOG_DIR"
source "$SCRIPT_DIR/lib/prompt_builder.sh"
source "$SCRIPT_DIR/lib/runtime_helpers.sh"
source "$SCRIPT_DIR/lib/work_items.sh"
source "$SCRIPT_DIR/lib/release_workflow.sh"
source "$SCRIPT_DIR/lib/provider_adapters.sh"
source "$SCRIPT_DIR/lib/preflight.sh"
source "$SCRIPT_DIR/lib/verification_profiles.sh"
source "$SCRIPT_DIR/lib/circuit_breaker.sh"
source "$SCRIPT_DIR/lib/nr_of_tries.sh"
source "$SCRIPT_DIR/lib/speckit_runner.sh"
source "$SCRIPT_DIR/lib/observability.sh"
CB_STATE_FILE="$PROJECT_DIR/.circuit_breaker_state"
reset_plan_mode_state

# Session-level observability tracking
SESSION_START_TIME=0
DONE_COUNT=0
NO_SIGNAL_COUNT=0
FAILED_COUNT=0

YOLO_ENABLED=true
if [[ -f "$CONSTITUTION" ]]; then
    if grep -q "YOLO Mode.*DISABLED" "$CONSTITUTION" 2>/dev/null; then
        YOLO_ENABLED=false
    fi
fi

show_help() {
    cat <<EOF
Ralph Loop

Usage:
  ./scripts/ralph-loop.sh [--runtime RUNTIME] [--model MODEL]              # Build mode, unlimited
  ./scripts/ralph-loop.sh [--runtime RUNTIME] [--model MODEL] 20           # Build mode, max 20 iterations
  ./scripts/ralph-loop.sh [--runtime RUNTIME] [--model MODEL] plan         # Planning mode
  ./scripts/ralph-loop.sh [--runtime RUNTIME] plan --prd docs/PRD.md
  ./scripts/ralph-loop.sh [--runtime RUNTIME] plan --notes docs/ideas.md
  ./scripts/ralph-loop.sh [--runtime RUNTIME] plan --brief "Build an Expo app for field sales"

Runtimes:
  claude   Claude Code (default)
  codex    OpenAI Codex CLI
  gemini   Google Gemini CLI
  copilot  GitHub Copilot CLI

Options:
  --runtime RUNTIME   Select the AI runtime (default: claude)
  --model MODEL       Override the runtime model when the selected runtime supports it
  --reset-circuit     Reset the circuit breaker to CLOSED state and exit
  -h, --help          Show this help

Notes:
  - The unified loop shares one control flow across all runtimes.
  - --model is applied for runtimes with explicit model flags in this wrapper.
  - Plan mode accepts exactly one input source: --prd, --notes, or --brief.
EOF
}


RAW_ARGS=("$@")
SANITIZED_ARGS=()
ARG_INDEX=0

while [ $ARG_INDEX -lt ${#RAW_ARGS[@]} ]; do
    ARG_VALUE="${RAW_ARGS[$ARG_INDEX]}"
    case "$ARG_VALUE" in
        --runtime)
            if [ $((ARG_INDEX + 1)) -ge ${#RAW_ARGS[@]} ]; then
                echo -e "${RED}Error: --runtime requires a value${NC}"
                show_help
                exit 1
            fi
            RUNTIME="${RAW_ARGS[$((ARG_INDEX + 1))]}"
            ARG_INDEX=$((ARG_INDEX + 2))
            ;;
        --model)
            if [ $((ARG_INDEX + 1)) -ge ${#RAW_ARGS[@]} ]; then
                echo -e "${RED}Error: --model requires a value${NC}"
                show_help
                exit 1
            fi
            MODEL_OVERRIDE="${RAW_ARGS[$((ARG_INDEX + 1))]}"
            ARG_INDEX=$((ARG_INDEX + 2))
            ;;
        *)
            SANITIZED_ARGS+=("$ARG_VALUE")
            ARG_INDEX=$((ARG_INDEX + 1))
            ;;
    esac
done

set -- "${SANITIZED_ARGS[@]}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        plan)
            MODE="plan"
            parse_plan_mode_arguments "${@:2}" || exit 1
            if [[ -n "$PLAN_ITERATION_OVERRIDE" ]]; then
                MAX_ITERATIONS="$PLAN_ITERATION_OVERRIDE"
            else
                MAX_ITERATIONS=1
            fi
            shift $((1 + PLAN_ARGS_CONSUMED))
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        [0-9]*)
            MODE="build"
            MAX_ITERATIONS="$1"
            shift
            ;;
        --reset-circuit)
            reset_circuit_breaker "Manual reset via --reset-circuit flag"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"
init_circuit_breaker

if [[ "$MODE" = "plan" ]]; then
    validate_plan_mode_arguments "$PROJECT_DIR" || exit 1
fi

configure_runtime "$RUNTIME" "$MODEL_OVERRIDE" || exit 1

SESSION_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SESSION_LOG="$LOG_DIR/${RUNTIME_SESSION_PREFIX}_${MODE}_session_${SESSION_TIMESTAMP}.log"
SUMMARY_LOG="$LOG_DIR/${RUNTIME_SESSION_PREFIX}_${MODE}_summary_${SESSION_TIMESTAMP}.log"
SESSION_START_TIME=$(date +%s)
exec > >(tee -a "$SESSION_LOG") 2>&1

validate_runtime_requirements || exit 1

echo -e "${BLUE}Preflight:${NC}"
run_preflight "$PROJECT_DIR" "$CONSTITUTION" "$MODE" || exit 1
echo ""

# Phase 8: Discover and directly invoke SpecKit bash helpers when available.
# This must run after preflight (project dir is validated) and before prompt
# building so that discover_speckit_scripts() populates SPECKIT_SCRIPTS_DIR
# which prompt_builder uses when constructing the plan-mode prompt.
discover_speckit_scripts "$PROJECT_DIR"
if [[ "$MODE" = "plan" && "$SPECKIT_RUNNER_STATUS" = "direct" ]]; then
    echo -e "${BLUE}SpecKit scripts:${NC} found at $SPECKIT_SCRIPTS_DIR"
    if has_speckit_script "check-prereqs.sh"; then
        echo -e "  Running check-prereqs.sh directly..."
        run_speckit_prereqs || true
    fi
    if has_speckit_script "update-context.sh"; then
        echo -e "  Running update-context.sh directly..."
        run_speckit_context_update || true
    fi
    echo ""
elif [[ "$MODE" = "plan" ]]; then
    echo -e "${BLUE}SpecKit scripts:${NC} not found — using prompt-driven emulation"
    echo ""
fi

PROMPT_FILE=$(build_runtime_prompt "$MODE" "$PROJECT_DIR" "$LOG_DIR")
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: failed to build runtime prompt${NC}"
    exit 1
fi
BASE_PROMPT_FILE="$PROMPT_FILE"

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

HAS_WORK_ITEMS=false
HAS_PLAN=false
HAS_SPECS=false
HAS_AGENTS=false
SPEC_COUNT=0
[ -f "work-items.json" ] && HAS_WORK_ITEMS=true
[ -f "IMPLEMENTATION_PLAN.md" ] && HAS_PLAN=true
[ -f "AGENTS.md" ] && HAS_AGENTS=true
if [ -d "specs" ]; then
    SPEC_COUNT=$(find specs -name "*.md" -type f 2>/dev/null | wc -l)
    [ "$SPEC_COUNT" -gt 0 ] && HAS_SPECS=true
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}         RALPH LOOP (${RUNTIME_LABEL}) STARTING              ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Runtime:${NC}  $RUNTIME"
echo -e "${BLUE}Mode:${NC}     $MODE"
if [[ -n "$RUNTIME_MODEL" ]]; then
    echo -e "${BLUE}Model:${NC}    $RUNTIME_MODEL"
fi
echo -e "${BLUE}Prompt:${NC}   $PROMPT_FILE"
echo -e "${BLUE}Branch:${NC}   $CURRENT_BRANCH"
echo -e "${YELLOW}YOLO:${NC}     $([ "$YOLO_ENABLED" = true ] && echo "ENABLED" || echo "DISABLED")"
echo -e "${BLUE}Log:${NC}      $SESSION_LOG"
echo -e "${BLUE}Summary:${NC}  $SUMMARY_LOG"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${BLUE}Max:${NC}      $MAX_ITERATIONS iterations"
if [ "$MODE" = "plan" ]; then
    echo -e "${BLUE}Plan input:${NC} $PLAN_INPUT_KIND"
    echo -e "${BLUE}SpecKit:${NC}   $SPECKIT_STATUS"
    echo -e "${BLUE}SpecKit scripts:${NC} $(speckit_runner_status_line)"
fi
echo ""
echo -e "${BLUE}Custom Instructions:${NC}"
if [ "$HAS_AGENTS" = true ]; then
    echo -e "  ${GREEN}✓${NC} AGENTS.md found"
else
    echo -e "  ${YELLOW}○${NC} AGENTS.md not found (optional)"
fi
echo ""
echo -e "${BLUE}Work source:${NC} (checked in priority order)"
if [ "$HAS_WORK_ITEMS" = true ]; then
    echo -e "  ${GREEN}✓${NC} work-items.json (primary)"
else
    echo -e "  ${YELLOW}○${NC} work-items.json (not found; run plan mode to generate)"
fi
if [ "$HAS_PLAN" = true ]; then
    echo -e "  ${GREEN}✓${NC} IMPLEMENTATION_PLAN.md (fallback)"
else
    echo -e "  ${YELLOW}○${NC} IMPLEMENTATION_PLAN.md (not found)"
fi
if [ "$HAS_SPECS" = true ]; then
    echo -e "  ${GREEN}✓${NC} specs/ folder ($SPEC_COUNT specs) (final fallback)"
else
    echo -e "  ${RED}✗${NC} specs/ folder (no .md files found)"
fi
if [[ "$MODE" = "build" && "${PREFLIGHT_PROJECT_PROFILE:-unknown}" != "unknown" ]]; then
    echo ""
    BANNER_VSTACK=$(verification_stack_summary "$PREFLIGHT_PROJECT_PROFILE")
    echo -e "${BLUE}Verification profile:${NC} $PREFLIGHT_PROJECT_PROFILE"
    echo -e "${BLUE}Verification stack:${NC}   $BANNER_VSTACK"
fi
echo ""
echo -e "${CYAN}The loop checks for terminal promise tags in each iteration.${NC}"
echo -e "${CYAN}Agent must verify acceptance criteria before outputting them.${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the loop${NC}"
echo ""

ITERATION=0
CONSECUTIVE_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo -e "${GREEN}Reached max iterations: $MAX_ITERATIONS${NC}"
        break
    fi

    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    ITER_START_TIME=$(date +%s)
    TAIL_RENDERED_LINES=0

    echo ""
    echo -e "${PURPLE}════════════════════ LOOP $ITERATION ════════════════════${NC}"
    echo -e "${BLUE}[$TIMESTAMP]${NC} Starting iteration $ITERATION"
    echo ""

    LOG_FILE="$LOG_DIR/${RUNTIME_ITER_PREFIX}_${MODE}_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').log"
    : > "$LOG_FILE"
    WATCH_PID=""
    ITERATION_PROMPT_FILE="$BASE_PROMPT_FILE"
    reset_active_work_item

    # Stuck-loop protection: halt if circuit breaker is open
    if ! can_execute; then
        should_halt_execution
        print_stuck_specs_summary "$PROJECT_DIR/specs"
        exit $EXIT_PROVIDER_ERROR
    fi

    if [[ "$MODE" = "build" && "$HAS_WORK_ITEMS" = true ]]; then
        reconcile_merged_pull_requests "$PROJECT_DIR"

        if find_awaiting_merge_item "$PROJECT_DIR"; then
            print_awaiting_merge_message "$ACTIVE_WORK_ITEM_ID" "$ACTIVE_WORK_ITEM_BRANCH" "$ACTIVE_WORK_ITEM_PR_NUMBER" "$ACTIVE_WORK_ITEM_PR_URL" "$PROJECT_DIR"
            exit $EXIT_AWAITING_MERGE
        fi

        if select_next_work_item "$PROJECT_DIR"; then
            ACTIVE_WORK_ITEM_BRANCH=$(ensure_work_item_branch "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" "$ACTIVE_WORK_ITEM_BRANCH") || exit 1
            mark_work_item_in_progress "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" "$ACTIVE_WORK_ITEM_BRANCH"
            set_active_work_item_by_id "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" || true

            ITERATION_PROMPT_FILE="$LOG_DIR/${RUNTIME_ITER_PREFIX}_${MODE}_prompt_${ITERATION}_$(date '+%Y%m%d_%H%M%S').md"
            cp "$BASE_PROMPT_FILE" "$ITERATION_PROMPT_FILE"
            render_active_work_item_context >> "$ITERATION_PROMPT_FILE"

            CURRENT_BRANCH="$ACTIVE_WORK_ITEM_BRANCH"
            echo -e "${BLUE}Work item:${NC} $ACTIVE_WORK_ITEM_ID — $ACTIVE_WORK_ITEM_TITLE"
            echo -e "${BLUE}Task branch:${NC} $ACTIVE_WORK_ITEM_BRANCH"
            echo ""
        else
            echo -e "${GREEN}All work-items are complete.${NC}"
            break
        fi
    fi

    GIT_HASH_BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "none")

    if [ "$ROLLING_OUTPUT_INTERVAL" -gt 0 ] && [ "$ROLLING_OUTPUT_LINES" -gt 0 ] && [ -t 1 ] && [ -w /dev/tty ]; then
        watch_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME" "$ITERATION" "$MAX_ITERATIONS" "$ITER_START_TIME" &
        WATCH_PID=$!
    fi

    ITER_STATUS="FAILED"
    ITER_SIGNAL_DETAIL=""

    if run_runtime_command "$ITERATION_PROMPT_FILE" "$LOG_FILE" "$LOG_DIR" "$MODE" "$ITERATION" "$YOLO_ENABLED"; then
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo ""
        echo -e "${GREEN}✓ ${RUNTIME_SHORT_NAME} execution completed${NC}"

        GIT_HASH_AFTER=$(git rev-parse HEAD 2>/dev/null || echo "none")
        ITER_FILES_CHANGED=0
        if [[ "$GIT_HASH_BEFORE" != "$GIT_HASH_AFTER" ]]; then
            ITER_FILES_CHANGED=$(git diff --name-only "$GIT_HASH_BEFORE" "$GIT_HASH_AFTER" 2>/dev/null | wc -l | tr -d ' ')
        fi

        detect_runtime_promise_signal "$LOG_FILE"

        if has_completion_promise; then
            DETECTED_SIGNAL="<promise>${LAST_PROMISE_SIGNAL}</promise>"
            echo -e "${GREEN}✓ Completion signal detected: ${DETECTED_SIGNAL}${NC}"
            if [[ "$MODE" = "build" && -n "$ACTIVE_WORK_ITEM_ID" ]]; then
                echo -e "${GREEN}✓ Implementation for work item '$ACTIVE_WORK_ITEM_ID' is ready for release workflow.${NC}"
            else
                echo -e "${GREEN}✓ Task completed successfully!${NC}"
            fi
            CONSECUTIVE_FAILURES=0
            ITER_STATUS="$LAST_PROMISE_SIGNAL"
            DONE_COUNT=$((DONE_COUNT + 1))
            record_loop_result "$ITERATION" "$ITER_FILES_CHANGED" "false"

            ITER_DURATION=$(($(date +%s) - ITER_START_TIME))
            print_iter_summary "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"
            append_iter_to_summary_log "$SUMMARY_LOG" "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"

            if [ "$MODE" = "plan" ]; then
                echo ""
                echo -e "${GREEN}Planning complete!${NC}"
                echo -e "${CYAN}Run './scripts/ralph-loop.sh --runtime $RUNTIME' to start building.${NC}"
                echo -e "${CYAN}Or delete IMPLEMENTATION_PLAN.md to work directly from specs.${NC}"
                break
            fi

            if [[ "$MODE" = "build" ]]; then
                RELEASE_BRANCH=$(git branch --show-current 2>/dev/null || echo "$CURRENT_BRANCH")
                push_branch_if_needed "$RELEASE_BRANCH"

                if [[ -n "$ACTIVE_WORK_ITEM_ID" ]]; then
                    PR_TITLE=$(build_pull_request_title "$ACTIVE_WORK_ITEM_ID" "$ACTIVE_WORK_ITEM_TITLE")
                    PR_BODY=$(build_pull_request_body "$ACTIVE_WORK_ITEM_ID" "$ACTIVE_WORK_ITEM_TITLE" "$ACTIVE_WORK_ITEM_SPEC" "$ACTIVE_WORK_ITEM_TASKS")

                    PR_INFO=""
                    if PR_INFO=$(ensure_draft_pull_request "$PROJECT_DIR" "$RELEASE_BRANCH" "$PR_TITLE" "$PR_BODY"); then
                        IFS=$'\t' read -r PR_NUMBER PR_URL PR_STATUS <<< "$PR_INFO"
                        if [[ "$PR_STATUS" = "merged" ]]; then
                            mark_work_item_done "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID"
                            echo -e "${GREEN}✓ Pull request for $ACTIVE_WORK_ITEM_ID is already merged.${NC}"
                        else
                            mark_work_item_awaiting_merge "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" "$RELEASE_BRANCH" "$PR_URL" "$PR_NUMBER"
                            print_awaiting_merge_message "$ACTIVE_WORK_ITEM_ID" "$RELEASE_BRANCH" "$PR_NUMBER" "$PR_URL" "$PROJECT_DIR"
                            exit $EXIT_AWAITING_MERGE
                        fi
                    else
                        echo -e "${YELLOW}Warning: could not create or inspect a draft pull request automatically.${NC}"
                        echo -e "${YELLOW}The branch has been pushed. Open and merge a PR manually, then rerun the loop from the base branch.${NC}"
                        mark_work_item_awaiting_merge "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" "$RELEASE_BRANCH"
                        print_awaiting_merge_message "$ACTIVE_WORK_ITEM_ID" "$RELEASE_BRANCH" "" "" "$PROJECT_DIR"
                        exit $EXIT_AWAITING_MERGE
                    fi
                fi
            fi
        elif [[ "$LAST_PROMISE_SIGNAL" = "BLOCKED" ]]; then
            ITER_STATUS="BLOCKED"
            ITER_SIGNAL_DETAIL="$LAST_PROMISE_PAYLOAD"
            ITER_DURATION=$(($(date +%s) - ITER_START_TIME))
            print_iter_summary "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED" "$ITER_SIGNAL_DETAIL"
            append_iter_to_summary_log "$SUMMARY_LOG" "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"
            print_blocked_signal "$RUNTIME_SHORT_NAME" "$LAST_PROMISE_PAYLOAD"
            exit $EXIT_BLOCKED
        elif [[ "$LAST_PROMISE_SIGNAL" = "DECIDE" ]]; then
            ITER_STATUS="DECIDE"
            ITER_SIGNAL_DETAIL="$LAST_PROMISE_PAYLOAD"
            ITER_DURATION=$(($(date +%s) - ITER_START_TIME))
            print_iter_summary "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED" "$ITER_SIGNAL_DETAIL"
            append_iter_to_summary_log "$SUMMARY_LOG" "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"
            print_decide_signal "$RUNTIME_SHORT_NAME" "$LAST_PROMISE_PAYLOAD"
            exit $EXIT_DECIDE
        else
            echo -e "${YELLOW}⚠ No completion signal found${NC}"
            echo -e "${YELLOW}  Agent did not output a terminal promise tag.${NC}"
            echo -e "${YELLOW}  This means acceptance criteria were not met.${NC}"
            echo -e "${YELLOW}  Retrying in next iteration...${NC}"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            ITER_STATUS="NO_SIGNAL"
            NO_SIGNAL_COUNT=$((NO_SIGNAL_COUNT + 1))
            print_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME"

            # Update per-spec attempt tracking for any spec files touched this iteration
            if [[ -d "specs" && "$GIT_HASH_BEFORE" != "$GIT_HASH_AFTER" ]]; then
                TOUCHED_SPECS=$(git diff --name-only "$GIT_HASH_BEFORE" "$GIT_HASH_AFTER" 2>/dev/null | grep -E 'specs/.*\.md' || true)
                if [[ -n "$TOUCHED_SPECS" ]]; then
                    while IFS= read -r spec_file; do
                        [[ -f "$spec_file" ]] || continue
                        new_tries=$(increment_nr_of_tries "$spec_file")
                        if is_spec_stuck "$spec_file"; then
                            echo -e "${YELLOW}⚠ Spec '$spec_file' is stuck ($new_tries/$MAX_NR_OF_TRIES attempts)${NC}"
                            echo -e "${YELLOW}  Consider splitting this spec into smaller tasks.${NC}"
                        fi
                    done <<< "$TOUCHED_SPECS"
                fi
            fi
            if [[ -n "$ACTIVE_WORK_ITEM_ID" ]]; then
                increment_work_item_retry_count "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" || true
            fi
            record_loop_result "$ITERATION" "$ITER_FILES_CHANGED" "false"

            ITER_DURATION=$(($(date +%s) - ITER_START_TIME))
            print_iter_summary "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"
            append_iter_to_summary_log "$SUMMARY_LOG" "$ITERATION" "$ITER_STATUS" "$ITER_DURATION" "$ITER_FILES_CHANGED"

            if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
                echo ""
                echo -e "${RED}⚠ $MAX_CONSECUTIVE_FAILURES consecutive iterations without completion.${NC}"
                echo -e "${RED}  The agent may be stuck. Consider:${NC}"
                echo -e "${RED}  - Checking the logs in $LOG_DIR${NC}"
                if [ -n "$RUNTIME_OUTPUT_FILE" ]; then
                    echo -e "${RED}  - Reviewing $RUNTIME_OUTPUT_FILE${NC}"
                fi
                echo -e "${RED}  - Simplifying the current spec${NC}"
                echo -e "${RED}  - Manually fixing blocking issues${NC}"
                print_stuck_specs_summary "$PROJECT_DIR/specs"
                echo ""
                CONSECUTIVE_FAILURES=0
            fi
        fi
    else
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo -e "${RED}✗ ${RUNTIME_SHORT_NAME} execution failed${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        if [ -n "$RUNTIME_OUTPUT_FILE" ]; then
            echo -e "${YELLOW}Check output: $RUNTIME_OUTPUT_FILE${NC}"
        fi
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        FAILED_COUNT=$((FAILED_COUNT + 1))
        print_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME"

        GIT_HASH_AFTER=$(git rev-parse HEAD 2>/dev/null || echo "none")
        ITER_FILES_CHANGED=0
        if [[ "$GIT_HASH_BEFORE" != "$GIT_HASH_AFTER" ]]; then
            ITER_FILES_CHANGED=$(git diff --name-only "$GIT_HASH_BEFORE" "$GIT_HASH_AFTER" 2>/dev/null | wc -l | tr -d ' ')
        fi
        if [[ -n "$ACTIVE_WORK_ITEM_ID" ]]; then
            increment_work_item_retry_count "$PROJECT_DIR" "$ACTIVE_WORK_ITEM_ID" || true
        fi
        record_loop_result "$ITERATION" "$ITER_FILES_CHANGED" "true"

        ITER_DURATION=$(($(date +%s) - ITER_START_TIME))
        print_iter_summary "$ITERATION" "FAILED" "$ITER_DURATION" "$ITER_FILES_CHANGED"
        append_iter_to_summary_log "$SUMMARY_LOG" "$ITERATION" "FAILED" "$ITER_DURATION" "$ITER_FILES_CHANGED"
    fi

    echo ""
    echo -e "${BLUE}Waiting 2s before next iteration...${NC}"
    sleep 2
done

SESSION_DURATION=$(($(date +%s) - SESSION_START_TIME))
print_session_summary "$ITERATION" "$SESSION_DURATION" "$DONE_COUNT" "$NO_SIGNAL_COUNT" "$FAILED_COUNT" "$RUNTIME_LABEL"
echo -e "${BLUE}Summary log:${NC} $SUMMARY_LOG"
