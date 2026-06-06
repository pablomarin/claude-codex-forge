#!/usr/bin/env bash
# tests/template/run-all.sh — driver that runs every test-*.sh in sequence.
#
# Exit code: 0 if every suite passed, 1 otherwise.
# Env vars:
#   KEEP_TMP=1              — preserve scratch dirs (test-setup only)
#   KEEP_TMP_ON_FAIL=1      — preserve scratch dirs only when a failure occurs
#   NO_COLOR=1              — disable ANSI color output
#
# Run from repo root:  bash tests/template/run-all.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export REPO_ROOT

# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

SUITES=(
    "$REPO_ROOT/tests/template/test-lint.sh"
    "$REPO_ROOT/tests/template/test-fixtures.sh"
    "$REPO_ROOT/tests/template/test-build-evidence.sh"
    "$REPO_ROOT/tests/template/test-contracts.sh"
    "$REPO_ROOT/tests/template/test-state-roundtrip.sh"
    "$REPO_ROOT/tests/template/test-review-breaker.sh"
    "$REPO_ROOT/tests/template/test-merge-settings.sh"
    "$REPO_ROOT/tests/template/test-hooks.sh"
    "$REPO_ROOT/tests/template/test-default-branch.sh"
    "$REPO_ROOT/tests/template/test-session-start.sh"
    "$REPO_ROOT/tests/template/test-migrate.sh"
    "$REPO_ROOT/tests/template/test-setup.sh"
)

TOTAL_FAIL=0
FAILED_SUITES=()

printf "%s═══ claude-codex-forge template test suite ═══%s\n\n" "$C_BLUE" "$C_RESET"

for suite in "${SUITES[@]}"; do
    if [[ ! -x "$suite" ]] && [[ ! -f "$suite" ]]; then
        printf "%s✗%s suite missing: %s\n" "$C_RED" "$C_RESET" "$suite" >&2
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_SUITES+=("$(basename "$suite")")
        continue
    fi
    bash "$suite"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_SUITES+=("$(basename "$suite")")
    fi
done

echo ""
printf "%s═══ Summary ═══%s\n" "$C_BLUE" "$C_RESET"
if [[ $TOTAL_FAIL -eq 0 ]]; then
    printf "%s✓ All suites passed%s\n" "$C_GREEN" "$C_RESET"
    exit 0
else
    printf "%s✗ %d suite(s) failed:%s\n" "$C_RED" "$TOTAL_FAIL" "$C_RESET"
    for s in "${FAILED_SUITES[@]}"; do
        printf "    - %s\n" "$s"
    done
    exit 1
fi
