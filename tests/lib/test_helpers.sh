#!/bin/bash
#
# Shared assertion helpers for Ralph loop shell tests.
#

_TESTS_PASSED=0
_TESTS_FAILED=0
_TESTS_SKIPPED=0
_CURRENT_SUITE=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

suite() {
    _CURRENT_SUITE="$1"
    echo ""
    echo -e "${BLUE}▶ Suite: $_CURRENT_SUITE${NC}"
}

pass() {
    local msg="$1"
    _TESTS_PASSED=$((_TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} $msg"
}

fail() {
    local msg="$1"
    _TESTS_FAILED=$((_TESTS_FAILED + 1))
    echo -e "  ${RED}✗${NC} $msg"
}

skip() {
    local msg="$1"
    _TESTS_SKIPPED=$((_TESTS_SKIPPED + 1))
    echo -e "  ${YELLOW}○${NC} $msg (skipped)"
}

assert_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" = "$actual" ]]; then
        pass "$label"
    else
        fail "$label — expected '${expected}', got '${actual}'"
    fi
}

assert_not_equals() {
    local label="$1"
    local unexpected="$2"
    local actual="$3"
    if [[ "$unexpected" != "$actual" ]]; then
        pass "$label"
    else
        fail "$label — expected value to differ from '${unexpected}', but they matched"
    fi
}

assert_true() {
    local label="$1"
    local result="$2"
    if [[ "$result" = "0" || "$result" = "true" ]]; then
        pass "$label"
    else
        fail "$label — expected true/0, got '$result'"
    fi
}

assert_false() {
    local label="$1"
    local result="$2"
    if [[ "$result" != "0" && "$result" != "true" ]]; then
        pass "$label"
    else
        fail "$label — expected false/non-zero, got '$result'"
    fi
}

assert_contains() {
    local label="$1"
    local needle="$2"
    local haystack="$3"
    # Use -- to prevent grep treating needle as a flag (e.g. --runtime)
    if echo "$haystack" | grep -qF -- "$needle"; then
        pass "$label"
    else
        fail "$label — expected output to contain '${needle}'"
    fi
}

assert_file_exists() {
    local label="$1"
    local path="$2"
    if [[ -f "$path" ]]; then
        pass "$label"
    else
        fail "$label — file not found: $path"
    fi
}

assert_cmd_succeeds() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label — command failed: $*"
    fi
}

assert_cmd_fails() {
    local label="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label — expected command to fail: $*"
    fi
}

# Print a final summary and exit with code 1 if any tests failed.
print_test_summary() {
    local total=$((_TESTS_PASSED + _TESTS_FAILED + _TESTS_SKIPPED))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Test Results${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total:   $total"
    echo -e "  ${GREEN}Passed:${NC}  $_TESTS_PASSED"
    if [[ $_TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:${NC}  $_TESTS_FAILED"
    fi
    if [[ $_TESTS_SKIPPED -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped:${NC} $_TESTS_SKIPPED"
    fi
    echo ""
    if [[ $_TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed.${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}$_TESTS_FAILED test(s) failed.${NC}"
        echo ""
        return 1
    fi
}

# Create a temporary directory for tests.
#
# Keep this side-effect free: many test scripts capture the result with command
# substitution, which would install any cleanup trap in a subshell and delete the
# directory before the caller can use it.
make_tmpdir() {
    mktemp -d
}
