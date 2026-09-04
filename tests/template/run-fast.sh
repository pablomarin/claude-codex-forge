#!/usr/bin/env bash
# Fast deterministic feedback gate for ordinary local iteration.
# Broad engine, evidence, installer, migration, hook, state, and end-to-end
# matrices remain in run-all.sh and should run once at a meaningful boundary.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export REPO_ROOT

# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

SUITES=(
    "$REPO_ROOT/tests/template/test-lint.sh"
    "$REPO_ROOT/tests/template/test-platform-parity.sh"
    "$REPO_ROOT/tests/template/test-contracts.sh"
    "$REPO_ROOT/tests/template/test-worktree-lifecycle.sh"
    "$REPO_ROOT/tests/template/test-merge-settings.sh"
    "$REPO_ROOT/tests/template/test-bash-safety.sh"
)

TOTAL_FAIL=0
FAILED_SUITES=()

printf "%s═══ claude-codex-forge fast test suite ═══%s\n\n" "$C_BLUE" "$C_RESET"

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
printf "%s═══ Fast summary ═══%s\n" "$C_BLUE" "$C_RESET"
if [[ $TOTAL_FAIL -eq 0 ]]; then
    printf "%s✓ All fast suites passed%s\n" "$C_GREEN" "$C_RESET"
    exit 0
fi
printf "%s✗ %d fast suite(s) failed:%s\n" "$C_RED" "$TOTAL_FAIL" "$C_RESET"
for suite in "${FAILED_SUITES[@]}"; do
    printf "    - %s\n" "$suite"
done
exit 1
