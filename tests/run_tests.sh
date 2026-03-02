#!/bin/bash
#
# Main test runner for the Ralph loop test suite.
#
# Usage:
#   ./tests/run_tests.sh          # Run all tests
#   ./tests/run_tests.sh smoke    # Run a specific test file by name substring
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FILTER="${1:-}"
TOTAL_SUITES=0
FAILED_SUITES=0
PASSED_SUITES=0

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Ralph Loop Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue

    basename_file=$(basename "$test_file")

    if [[ -n "$FILTER" ]] && [[ "$basename_file" != *"$FILTER"* ]]; then
        continue
    fi

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo ""
    echo -e "${BLUE}━━ $basename_file ━━${NC}"

    bash "$test_file"
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Run Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Test files run: $TOTAL_SUITES"
echo -e "  ${GREEN}Passed:${NC}         $PASSED_SUITES"
if [[ $FAILED_SUITES -gt 0 ]]; then
    echo -e "  ${RED}Failed:${NC}         $FAILED_SUITES"
fi
echo ""

if [[ $FAILED_SUITES -eq 0 ]]; then
    echo -e "${GREEN}All test files passed.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}$FAILED_SUITES test file(s) had failures.${NC}"
    echo ""
    exit 1
fi
