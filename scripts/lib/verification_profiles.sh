#!/bin/bash
#
# Verification profile definitions for the Ralph Loop.
#
# Each profile defines the validation stack an agent should run
# after implementing a work item.  These definitions are used to:
#   1. Inform build-mode prompts so agents know what to verify.
#   2. Provide structured summaries in logs and startup banners.
#   3. Assist planning mode in populating work-items.json correctly.
#

# Profile constants (mirrors preflight.sh; sourced independently so this file
# is usable without preflight.sh if needed).
VERIFICATION_PROFILE_WEB="web"
VERIFICATION_PROFILE_EXPO="expo"
VERIFICATION_PROFILE_BACKEND="backend"
VERIFICATION_PROFILE_LIBRARY="library"
VERIFICATION_PROFILE_UNKNOWN="unknown"

# Output a compact, one-line summary of the verification stack for a profile.
# Usage: verification_stack_summary <profile>
verification_stack_summary() {
    local profile="$1"
    case "$profile" in
        web)      echo "lint → typecheck → unit tests → build → [e2e/browser]" ;;
        expo)     echo "expo-doctor → Metro export → typecheck → unit tests → [simulator] → [Maestro] → [device MCP/agent skill]" ;;
        backend)  echo "lint → typecheck/static-analysis → unit tests → [integration tests] → build" ;;
        library)  echo "lint → typecheck → unit tests → build → package-exports" ;;
        *)        echo "lint → typecheck → tests → build (where applicable)" ;;
    esac
}

# Output a human-readable bullet list of verification steps for a profile.
# Usage: describe_verification_steps <profile>
describe_verification_steps() {
    local profile="$1"
    case "$profile" in
        web)
            cat <<'EOF'
- **Lint**: `npm run lint` (or `eslint .`)
- **Typecheck**: `npm run typecheck` or `tsc --noEmit`
- **Unit tests**: `npm test` or `npm run test:unit`
- **Build**: `npm run build`
- **E2E / browser tests** (when configured): Playwright (`npx playwright test`), Cypress (`npx cypress run`), etc.
- **Screenshots** (when relevant): validate visual output via browser test screenshots
EOF
            ;;
        expo)
            cat <<'EOF'
- **expo-doctor**: `npx expo-doctor` — dependency and config health check
- **Metro export**: `npx expo export --dump-assetmap` — Metro bundler smoke test
- **Typecheck**: `tsc --noEmit` (if `tsconfig.json` present)
- **Unit tests**: `jest` or `npm test`
- **Simulator smoke test** (optional): `npx expo run:ios` or `npx expo run:android`
- **Maestro flows** (when present): `maestro test .maestro/`
- **Device / MCP testing** (when configured): run your configured device automation
  through MCP tools or agent-device skills
EOF
            ;;
        backend)
            cat <<'EOF'
- **Lint**: `npm run lint` / `ruff check .` / `golint ./...` / `rubocop`
- **Typecheck / static analysis**: `tsc --noEmit` / `mypy .` / `go vet ./...`
- **Unit tests**: `npm test` / `pytest` / `go test ./...` / `bundle exec rspec`
- **Integration tests** (when configured)
- **Build / compile**: `npm run build` / `go build ./...` / `mvn package`
EOF
            ;;
        library)
            cat <<'EOF'
- **Lint**: `npm run lint` (or language-specific linter)
- **Typecheck**: `tsc --noEmit` (if `tsconfig.json` present)
- **Unit tests**: `npm test`
- **Build + type declarations**: `npm run build`
- **Package exports sanity check**: verify `main`/`exports` fields resolve correctly
EOF
            ;;
        *)
            cat <<'EOF'
- Run lint if configured
- Run typecheck if applicable
- Run unit tests if present
- Run build check if applicable
EOF
            ;;
    esac
}

# Output the JSON array of verification steps suitable for work-items.json.
# Usage: verification_steps_json <profile>
verification_steps_json() {
    local profile="$1"
    case "$profile" in
        web)
            cat <<'EOF'
["lint", "typecheck", "unit-tests", "build", "e2e"]
EOF
            ;;
        expo)
            cat <<'EOF'
["expo-doctor", "metro-export", "typecheck", "unit-tests", "simulator-smoke-test", "maestro-flows", "device-mcp", "agent-device-skills"]
EOF
            ;;
        backend)
            cat <<'EOF'
["lint", "typecheck", "unit-tests", "integration-tests", "build"]
EOF
            ;;
        library)
            cat <<'EOF'
["lint", "typecheck", "unit-tests", "build", "package-exports"]
EOF
            ;;
        *)
            cat <<'EOF'
["lint", "typecheck", "tests", "build"]
EOF
            ;;
    esac
}

# Print a formatted verification profile block for use in the startup banner.
# Usage: print_verification_profile_banner <profile>
print_verification_profile_banner() {
    local profile="$1"
    local stack
    stack=$(verification_stack_summary "$profile")

    echo -e "${BLUE}Verification:${NC}"
    echo -e "  ${BLUE}Profile:${NC} $profile"
    echo -e "  ${BLUE}Stack:${NC}   $stack"
}
