#!/bin/bash
#
# Provider-specific runtime helpers for the unified Ralph loop.
#

RUNTIME_ID=""
RUNTIME_SHORT_NAME=""
RUNTIME_LABEL=""
RUNTIME_CMD=""
RUNTIME_MODEL=""
RUNTIME_MODEL_SUPPORTED=false
RUNTIME_MODEL_NOTE=""
RUNTIME_YOLO_FLAG=""
RUNTIME_SESSION_PREFIX=""
RUNTIME_ITER_PREFIX=""
RUNTIME_OUTPUT_FILE=""

configure_runtime() {
    local runtime="$1"
    local model_override="$2"

    RUNTIME_ID=""
    RUNTIME_SHORT_NAME=""
    RUNTIME_LABEL=""
    RUNTIME_CMD=""
    RUNTIME_MODEL=""
    RUNTIME_MODEL_SUPPORTED=false
    RUNTIME_MODEL_NOTE=""
    RUNTIME_YOLO_FLAG=""
    RUNTIME_SESSION_PREFIX=""
    RUNTIME_ITER_PREFIX=""
    RUNTIME_OUTPUT_FILE=""

    case "$runtime" in
        claude)
            RUNTIME_ID="claude"
            RUNTIME_SHORT_NAME="Claude"
            RUNTIME_LABEL="Claude Code"
            RUNTIME_CMD="${CLAUDE_CMD:-claude}"
            RUNTIME_YOLO_FLAG="--dangerously-skip-permissions"
            ;;
        codex)
            RUNTIME_ID="codex"
            RUNTIME_SHORT_NAME="Codex"
            RUNTIME_LABEL="OpenAI Codex"
            RUNTIME_CMD="${CODEX_CMD:-codex}"
            RUNTIME_YOLO_FLAG="--dangerously-bypass-approvals-and-sandbox"
            ;;
        gemini)
            RUNTIME_ID="gemini"
            RUNTIME_SHORT_NAME="Gemini"
            RUNTIME_LABEL="Google Gemini"
            RUNTIME_CMD="${GEMINI_CMD:-gemini}"
            RUNTIME_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"
            RUNTIME_MODEL_SUPPORTED=true
            RUNTIME_YOLO_FLAG="--yolo"
            ;;
        copilot)
            RUNTIME_ID="copilot"
            RUNTIME_SHORT_NAME="Copilot"
            RUNTIME_LABEL="GitHub Copilot"
            RUNTIME_CMD="${COPILOT_CMD:-copilot}"
            RUNTIME_MODEL="${COPILOT_MODEL:-claude-opus-4.6}"
            RUNTIME_MODEL_SUPPORTED=true
            RUNTIME_YOLO_FLAG="--allow-all-tools"
            ;;
        *)
            echo -e "${RED}Error: unsupported runtime: $runtime${NC}" >&2
            echo "Supported runtimes: claude, codex, gemini, copilot" >&2
            return 1
            ;;
    esac

    RUNTIME_SESSION_PREFIX="ralph_${RUNTIME_ID}"
    RUNTIME_ITER_PREFIX="ralph_${RUNTIME_ID}"

    if [[ -n "$model_override" ]]; then
        if [[ "$RUNTIME_MODEL_SUPPORTED" = true ]]; then
            RUNTIME_MODEL="$model_override"
        else
            RUNTIME_MODEL_NOTE="Runtime '$RUNTIME_ID' ignores --model in this wrapper; use provider-native config if you need a non-default model."
        fi
    fi
}

validate_runtime_requirements() {
    case "$RUNTIME_ID" in
        claude)
            if ! command -v "$RUNTIME_CMD" >/dev/null 2>&1; then
                echo -e "${RED}Error: Claude CLI not found${NC}"
                echo ""
                echo "Install Claude Code CLI and authenticate first."
                echo "https://claude.ai/code"
                return 1
            fi
            ;;
        codex)
            if ! command -v "$RUNTIME_CMD" >/dev/null 2>&1; then
                echo -e "${RED}Error: Codex CLI not found${NC}"
                echo ""
                echo "Install Codex CLI:"
                echo "  npm install -g @openai/codex"
                echo ""
                echo "Then authenticate:"
                echo "  codex login"
                return 1
            fi
            ;;
        gemini)
            if ! command -v "$RUNTIME_CMD" >/dev/null 2>&1; then
                echo -e "${RED}Error: Gemini CLI not found${NC}"
                echo ""
                echo "Install Gemini CLI:"
                echo "  npm install -g @google/gemini-cli"
                echo ""
                echo "Then authenticate by running once interactively:"
                echo "  gemini"
                return 1
            fi
            ;;
        copilot)
            if [[ -d "/opt/nodejs24/bin" ]]; then
                export PATH="/opt/nodejs24/bin:$PATH"
            fi

            if ! command -v gh >/dev/null 2>&1; then
                echo -e "${YELLOW}Warning: GitHub CLI (gh) not found${NC}"
                echo -e "${YELLOW}Git push operations may fail. Install from: https://cli.github.com/${NC}"
                echo ""
            elif ! gh auth status >/dev/null 2>&1; then
                echo -e "${YELLOW}Warning: Not authenticated with GitHub CLI${NC}"
                echo -e "${YELLOW}Git push operations may fail. Run: gh auth login${NC}"
                echo ""
            fi

            if ! command -v "$RUNTIME_CMD" >/dev/null 2>&1; then
                echo -e "${RED}Error: GitHub Copilot CLI not found${NC}"
                echo ""
                echo "Install GitHub Copilot CLI first:"
                echo "  brew install copilot-cli"
                echo "  npm install -g @github/copilot"
                echo "  curl -fsSL https://gh.io/copilot-install | bash"
                echo ""
                echo "Then authenticate:"
                echo "  copilot    # and use /login command"
                return 1
            fi
            ;;
    esac

    if [[ -n "$RUNTIME_MODEL_NOTE" ]]; then
        echo -e "${YELLOW}Note:${NC} $RUNTIME_MODEL_NOTE"
        echo ""
    fi

    return 0
}

run_runtime_command() {
    local prompt_file="$1"
    local log_file="$2"
    local log_dir="$3"
    local mode="$4"
    local iteration="$5"
    local yolo_enabled="$6"
    local prompt_content=""
    local cmd=()

    RUNTIME_OUTPUT_FILE=""

    case "$RUNTIME_ID" in
        claude)
            cmd=("$RUNTIME_CMD" "-p")
            if [[ "$yolo_enabled" = true ]]; then
                cmd+=("$RUNTIME_YOLO_FLAG")
            fi
            cat "$prompt_file" | "${cmd[@]}" 2>&1 | tee "$log_file"
            ;;
        codex)
            RUNTIME_OUTPUT_FILE="$log_dir/ralph_codex_output_iter_${iteration}_$(date '+%Y%m%d_%H%M%S').txt"
            cmd=("$RUNTIME_CMD" "exec")
            if [[ "$yolo_enabled" = true ]]; then
                cmd+=("$RUNTIME_YOLO_FLAG")
            fi
            cmd+=("-" "--output-last-message" "$RUNTIME_OUTPUT_FILE")
            cat "$prompt_file" | "${cmd[@]}" 2>&1 | tee "$log_file"
            ;;
        gemini)
            cmd=("$RUNTIME_CMD" "-p" "" "-m" "$RUNTIME_MODEL")
            if [[ "$yolo_enabled" = true ]]; then
                cmd+=("$RUNTIME_YOLO_FLAG")
            fi
            cat "$prompt_file" | "${cmd[@]}" 2>&1 | tee "$log_file"
            ;;
        copilot)
            prompt_content=$(cat "$prompt_file")
            cmd=("$RUNTIME_CMD" "-p" "$prompt_content" "--model" "$RUNTIME_MODEL")
            if [[ "$yolo_enabled" = true ]]; then
                cmd+=("$RUNTIME_YOLO_FLAG")
            fi
            "${cmd[@]}" 2>&1 | tee "$log_file"
            ;;
        *)
            echo -e "${RED}Error: runtime '$RUNTIME_ID' is not configured${NC}" >&2
            return 1
            ;;
    esac
}

detect_runtime_promise_signal() {
    local log_file="$1"

    if [[ -n "$RUNTIME_OUTPUT_FILE" ]]; then
        detect_promise_signal_from_files "$RUNTIME_OUTPUT_FILE" "$log_file"
    else
        detect_promise_signal_from_files "$log_file"
    fi
}
