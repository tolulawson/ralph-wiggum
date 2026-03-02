#!/bin/bash
#
# Runtime observability and operator UX helpers.
#
# Provides:
#   - Timing: format_duration, get_elapsed
#   - End-of-iteration summary: print_iter_summary, append_iter_to_summary_log
#   - End-of-session summary: print_session_summary
#   - Rolling live preview: watch_latest_output
#   - Static tail preview: print_latest_output
#
# Keep the UX layer optional and non-blocking:
#   - watch_latest_output only runs when a TTY is attached
#   - All functions degrade gracefully in headless/pipe contexts
#

# Colors (guard against redefinition from parent scripts)
if [[ -z "${_OBSERVABILITY_COLORS_SET:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    _OBSERVABILITY_COLORS_SET=1
fi

# State for in-place terminal rendering (reset at start of each iteration)
TAIL_RENDERED_LINES=0

# ---------------------------------------------------------------------------
# Timing helpers
# ---------------------------------------------------------------------------

# Convert seconds to human-readable duration string.
format_duration() {
    local seconds=$1
    local h=$((seconds / 3600))
    local m=$(( (seconds % 3600) / 60 ))
    local s=$((seconds % 60))
    if [ "$h" -gt 0 ]; then
        printf "%dh %dm %ds" "$h" "$m" "$s"
    elif [ "$m" -gt 0 ]; then
        printf "%dm %ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

# Return elapsed seconds since a given epoch start time.
get_elapsed() {
    local start=$1
    local now
    now=$(date +%s)
    echo $((now - start))
}

# ---------------------------------------------------------------------------
# End-of-iteration summary (persists in terminal scroll buffer)
# ---------------------------------------------------------------------------

# Print a compact persistent summary block after each iteration.
# Args: $1=iteration  $2=iter_status (DONE|ALL_DONE|BLOCKED|DECIDE|NO_SIGNAL|FAILED)
#       $3=duration_seconds  $4=files_changed  $5=signal_detail (optional)
print_iter_summary() {
    local iteration="$1"
    local iter_status="$2"
    local duration_secs="$3"
    local files_changed="$4"
    local signal_detail="${5:-}"

    local duration_str
    duration_str=$(format_duration "$duration_secs")
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local status_color="$BLUE"
    local status_icon="→"
    case "$iter_status" in
        DONE|ALL_DONE) status_color="$GREEN";  status_icon="✓" ;;
        BLOCKED)       status_color="$RED";    status_icon="✗" ;;
        DECIDE)        status_color="$PURPLE"; status_icon="?" ;;
        NO_SIGNAL)     status_color="$YELLOW"; status_icon="↻" ;;
        FAILED)        status_color="$RED";    status_icon="✗" ;;
    esac

    echo ""
    echo -e "${BLUE}┌─ Iteration ${iteration} ─────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  Status:   ${status_color}${status_icon} ${iter_status}${NC}"
    echo -e "${BLUE}│${NC}  Duration: ${duration_str}"
    echo -e "${BLUE}│${NC}  Files:    ${files_changed} changed"
    if [[ -n "$signal_detail" ]]; then
        echo -e "${BLUE}│${NC}  Detail:   ${signal_detail}"
    fi
    echo -e "${BLUE}│${NC}  Time:     ${timestamp}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────────┘${NC}"
}

# Append a single machine-readable line to a summary log file.
# Args: $1=summary_log  $2=iteration  $3=status  $4=duration_secs  $5=files_changed
append_iter_to_summary_log() {
    local summary_log="$1"
    local iteration="$2"
    local status="$3"
    local duration_secs="$4"
    local files_changed="$5"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    printf "[%s] iter=%-3s status=%-10s duration=%ss files=%s\n" \
        "$timestamp" "$iteration" "$status" "$duration_secs" "$files_changed" \
        >> "$summary_log"
}

# ---------------------------------------------------------------------------
# End-of-session summary
# ---------------------------------------------------------------------------

# Print a final session summary after the loop exits.
# Args: $1=total_iterations  $2=total_duration_secs  $3=done_count
#       $4=no_signal_count   $5=failed_count          $6=runtime_label
print_session_summary() {
    local total_iterations="$1"
    local total_duration_secs="$2"
    local done_count="$3"
    local no_signal_count="$4"
    local failed_count="$5"
    local runtime_label="${6:-Unknown}"

    local duration_str
    duration_str=$(format_duration "$total_duration_secs")

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Session Summary — ${runtime_label}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Iterations:  ${total_iterations}"
    echo -e "  Duration:    ${duration_str}"
    echo -e "  Completed:   ${GREEN}${done_count}${NC}"
    echo -e "  No signal:   ${YELLOW}${no_signal_count}${NC}"
    echo -e "  Failed:      ${RED}${failed_count}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---------------------------------------------------------------------------
# Rolling live preview (background watcher)
# ---------------------------------------------------------------------------

# Continuously refresh a live preview of the current iteration log.
# Runs as a background process; killed by the main loop after each iteration.
# Only activates when a writable TTY is present (non-blocking for headless runs).
#
# Args: $1=log_file  $2=label  $3=iteration  $4=max_iterations  $5=iter_start_epoch
watch_latest_output() {
    local log_file="$1"
    local label="${2:-Agent}"
    local iteration="${3:-?}"
    local max_iter="${4:-?}"
    local iter_start="${5:-0}"
    local lines="${ROLLING_OUTPUT_LINES:-5}"
    local interval="${ROLLING_OUTPUT_INTERVAL:-10}"
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

        local elapsed_str=""
        if [[ "$iter_start" -gt 0 ]]; then
            local now
            now=$(date +%s)
            local elapsed=$((now - iter_start))
            elapsed_str=" +$(format_duration "$elapsed")"
        fi

        local status_label="iter ${iteration}"
        if [[ "$max_iter" != "?" && "$max_iter" -gt 0 ]]; then
            status_label="iter ${iteration}/${max_iter}"
        fi

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
            echo -e "${CYAN}[${timestamp}]${elapsed_str} ${label} — ${status_label} — live preview (last ${lines} lines):${NC}"
            if [ ! -s "$log_file" ]; then
                echo "(no output yet)"
            else
                tail -n "$lines" "$log_file" 2>/dev/null || true
            fi
            echo ""
        } > "$target"

        sleep "$interval"
    done
}

# ---------------------------------------------------------------------------
# Static tail preview (shown after a failed iteration)
# ---------------------------------------------------------------------------

# Print the last N lines of a log file, optionally clearing a previous render.
# Uses TAIL_RENDERED_LINES global for in-place TTY refresh; reset between iters.
# Args: $1=log_file  $2=label
print_latest_output() {
    local log_file="$1"
    local label="${2:-Agent}"
    local tail_lines="${TAIL_LINES:-5}"
    local target="/dev/tty"

    [ -f "$log_file" ] || return 0

    if [ ! -w "$target" ]; then
        target="/dev/stdout"
    fi

    if [ "$target" = "/dev/tty" ] && [ "$TAIL_RENDERED_LINES" -gt 0 ]; then
        printf "\033[%dA\033[J" "$TAIL_RENDERED_LINES" > "$target"
    fi

    {
        echo "Latest ${label} output (last ${tail_lines} lines):"
        tail -n "$tail_lines" "$log_file"
    } > "$target"

    if [ "$target" = "/dev/tty" ]; then
        TAIL_RENDERED_LINES=$((tail_lines + 1))
    fi
}

export -f format_duration
export -f get_elapsed
export -f print_iter_summary
export -f append_iter_to_summary_log
export -f print_session_summary
export -f watch_latest_output
export -f print_latest_output
