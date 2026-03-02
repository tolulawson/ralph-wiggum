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
source "$SCRIPT_DIR/lib/provider_adapters.sh"
reset_plan_mode_state

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
  -h, --help          Show this help

Notes:
  - The unified loop shares one control flow across all runtimes.
  - --model is applied for runtimes with explicit model flags in this wrapper.
  - Plan mode accepts exactly one input source: --prd, --notes, or --brief.
EOF
}

print_latest_output() {
    local log_file="$1"
    local label="$2"
    local target="/dev/tty"

    [ -f "$log_file" ] || return 0

    if [ ! -w "$target" ]; then
        target="/dev/stdout"
    fi

    if [ "$target" = "/dev/tty" ] && [ "$TAIL_RENDERED_LINES" -gt 0 ]; then
        printf "\033[%dA\033[J" "$TAIL_RENDERED_LINES" > "$target"
    fi

    {
        echo "Latest ${label} output (last ${TAIL_LINES} lines):"
        tail -n "$TAIL_LINES" "$log_file"
    } > "$target"

    if [ "$target" = "/dev/tty" ]; then
        TAIL_RENDERED_LINES=$((TAIL_LINES + 1))
    fi
}

watch_latest_output() {
    local log_file="$1"
    local label="$2"
    local target="/dev/tty"
    local use_tty=false
    local use_tput=false

    [ -f "$log_file" ] || return 0

    if [ ! -w "$target" ]; then
        target="/dev/stdout"
    else
        use_tty=true
        if command -v tput &>/dev/null; then
            use_tput=true
        fi
    fi

    if [ "$use_tty" = true ]; then
        if [ "$use_tput" = true ]; then
            tput cr > "$target"
            tput sc > "$target"
        else
            printf "\r\0337" > "$target"
        fi
    fi

    while true; do
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        if [ "$use_tty" = true ]; then
            if [ "$use_tput" = true ]; then
                tput rc > "$target"
                tput ed > "$target"
                tput cr > "$target"
            else
                printf "\0338\033[J\r" > "$target"
            fi
        fi

        {
            echo -e "${CYAN}[$timestamp] Latest ${label} output (last ${ROLLING_OUTPUT_LINES} lines):${NC}"
            if [ ! -s "$log_file" ]; then
                echo "(no output yet)"
            else
                tail -n "$ROLLING_OUTPUT_LINES" "$log_file" 2>/dev/null || true
            fi
            echo ""
        } > "$target"

        sleep "$ROLLING_OUTPUT_INTERVAL"
    done
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
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

if [[ "$MODE" = "plan" ]]; then
    validate_plan_mode_arguments "$PROJECT_DIR" || exit 1
fi

configure_runtime "$RUNTIME" "$MODEL_OVERRIDE" || exit 1

SESSION_LOG="$LOG_DIR/${RUNTIME_SESSION_PREFIX}_${MODE}_session_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$SESSION_LOG") 2>&1

if [[ ! -f "$CONSTITUTION" ]]; then
    echo -e "${YELLOW}Warning: constitution not found at $CONSTITUTION${NC}"
    echo -e "${YELLOW}The repo instructions reference it as the source of truth.${NC}"
    echo ""
fi

validate_runtime_requirements || exit 1

PROMPT_FILE=$(build_runtime_prompt "$MODE" "$PROJECT_DIR" "$LOG_DIR")
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: failed to build runtime prompt${NC}"
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

HAS_PLAN=false
HAS_SPECS=false
HAS_AGENTS=false
SPEC_COUNT=0
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
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${BLUE}Max:${NC}      $MAX_ITERATIONS iterations"
if [ "$MODE" = "plan" ]; then
    echo -e "${BLUE}Plan input:${NC} $PLAN_INPUT_KIND"
    echo -e "${BLUE}SpecKit:${NC}   $SPECKIT_STATUS"
fi
echo ""
echo -e "${BLUE}Custom Instructions:${NC}"
if [ "$HAS_AGENTS" = true ]; then
    echo -e "  ${GREEN}✓${NC} AGENTS.md found"
else
    echo -e "  ${YELLOW}○${NC} AGENTS.md not found (optional)"
fi
echo ""
echo -e "${BLUE}Work source:${NC}"
if [ "$HAS_PLAN" = true ]; then
    echo -e "  ${GREEN}✓${NC} IMPLEMENTATION_PLAN.md"
else
    echo -e "  ${YELLOW}○${NC} IMPLEMENTATION_PLAN.md (not found, that's OK)"
fi
if [ "$HAS_SPECS" = true ]; then
    echo -e "  ${GREEN}✓${NC} specs/ folder ($SPEC_COUNT specs)"
else
    echo -e "  ${RED}✗${NC} specs/ folder (no .md files found)"
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

    echo ""
    echo -e "${PURPLE}════════════════════ LOOP $ITERATION ════════════════════${NC}"
    echo -e "${BLUE}[$TIMESTAMP]${NC} Starting iteration $ITERATION"
    echo ""

    LOG_FILE="$LOG_DIR/${RUNTIME_ITER_PREFIX}_${MODE}_iter_${ITERATION}_$(date '+%Y%m%d_%H%M%S').log"
    : > "$LOG_FILE"
    WATCH_PID=""

    if [ "$ROLLING_OUTPUT_INTERVAL" -gt 0 ] && [ "$ROLLING_OUTPUT_LINES" -gt 0 ] && [ -t 1 ] && [ -w /dev/tty ]; then
        watch_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME" &
        WATCH_PID=$!
    fi

    if run_runtime_command "$PROMPT_FILE" "$LOG_FILE" "$LOG_DIR" "$MODE" "$ITERATION" "$YOLO_ENABLED"; then
        if [ -n "$WATCH_PID" ]; then
            kill "$WATCH_PID" 2>/dev/null || true
            wait "$WATCH_PID" 2>/dev/null || true
        fi
        echo ""
        echo -e "${GREEN}✓ ${RUNTIME_SHORT_NAME} execution completed${NC}"

        detect_runtime_promise_signal "$LOG_FILE"

        if has_completion_promise; then
            DETECTED_SIGNAL="<promise>${LAST_PROMISE_SIGNAL}</promise>"
            echo -e "${GREEN}✓ Completion signal detected: ${DETECTED_SIGNAL}${NC}"
            echo -e "${GREEN}✓ Task completed successfully!${NC}"
            CONSECUTIVE_FAILURES=0

            if [ "$MODE" = "plan" ]; then
                echo ""
                echo -e "${GREEN}Planning complete!${NC}"
                echo -e "${CYAN}Run './scripts/ralph-loop.sh --runtime $RUNTIME' to start building.${NC}"
                echo -e "${CYAN}Or delete IMPLEMENTATION_PLAN.md to work directly from specs.${NC}"
                break
            fi
        elif [[ "$LAST_PROMISE_SIGNAL" = "BLOCKED" ]]; then
            print_blocked_signal "$RUNTIME_SHORT_NAME" "$LAST_PROMISE_PAYLOAD"
            exit $EXIT_BLOCKED
        elif [[ "$LAST_PROMISE_SIGNAL" = "DECIDE" ]]; then
            print_decide_signal "$RUNTIME_SHORT_NAME" "$LAST_PROMISE_PAYLOAD"
            exit $EXIT_DECIDE
        else
            echo -e "${YELLOW}⚠ No completion signal found${NC}"
            echo -e "${YELLOW}  Agent did not output a terminal promise tag.${NC}"
            echo -e "${YELLOW}  This means acceptance criteria were not met.${NC}"
            echo -e "${YELLOW}  Retrying in next iteration...${NC}"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            print_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME"

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
        print_latest_output "$LOG_FILE" "$RUNTIME_SHORT_NAME"
    fi

    push_branch_if_needed "$CURRENT_BRANCH"

    echo ""
    echo -e "${BLUE}Waiting 2s before next iteration...${NC}"
    sleep 2
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} RALPH LOOP (${RUNTIME_LABEL}) FINISHED ($ITERATION iterations) ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
