#!/usr/bin/env bash
# tests/template/test-lint.sh — syntax/parse checks on shipped artifacts.
#
# Cheap smoke tests that catch the class of bug where a shell script
# has a syntax error that only surfaces when a user runs setup.sh on
# a platform we didn't happen to test.
#
# Run from repo root:  bash tests/template/test-lint.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

# ---------------------------------------------------------------------------
# Bash syntax check (no execution — just parse)
# ---------------------------------------------------------------------------
start_test "Bash syntax (bash -n)"

# Shell scripts we ship that must parse cleanly.
BASH_FILES=(
    "$REPO_ROOT/setup.sh"
    "$REPO_ROOT/hooks/post-tool-format.sh"
    "$REPO_ROOT/hooks/pre-compact-memory.sh"
    "$REPO_ROOT/hooks/session-start.sh"
    "$REPO_ROOT/hooks/check-state-updated.sh"
    "$REPO_ROOT/hooks/check-bash-safety.sh"
    "$REPO_ROOT/hooks/check-config-change.sh"
    "$REPO_ROOT/hooks/check-workflow-gates.sh"
    "$REPO_ROOT/hooks/lib/default-branch.sh"
    "$REPO_ROOT/hooks/lib/review-breaker.sh"
    "$REPO_ROOT/tests/template/test-review-breaker.sh"
    "$REPO_ROOT/tests/template/lib.sh"
    "$REPO_ROOT/tests/template/test-setup.sh"
    "$REPO_ROOT/tests/template/test-fixtures.sh"
    "$REPO_ROOT/tests/template/test-contracts.sh"
    "$REPO_ROOT/tests/template/test-hooks.sh"
    "$REPO_ROOT/tests/template/test-lint.sh"
    "$REPO_ROOT/tests/template/run-all.sh"
    "$REPO_ROOT/tests/template/test-default-branch.sh"
    "$REPO_ROOT/tests/template/test-session-start.sh"
    "$REPO_ROOT/tests/template/test-migrate.sh"
)

for f in "${BASH_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        # Not all hooks are guaranteed to exist across every version;
        # warn via fail, but don't hard-fail for missing optional files.
        printf "  %s·%s skipped (not present): %s\n" \
            "$C_DIM" "$C_RESET" "${f#$REPO_ROOT/}"
        continue
    fi
    if bash -n "$f" 2>/dev/null; then
        pass "parses: ${f#$REPO_ROOT/}"
    else
        # Capture the actual error for the report
        err=$(bash -n "$f" 2>&1 || true)
        fail "syntax error in ${f#$REPO_ROOT/}: $err"
    fi
done

# ---------------------------------------------------------------------------
# PowerShell syntax check (only if pwsh is available)
# ---------------------------------------------------------------------------
start_test "PowerShell syntax"

if command -v pwsh >/dev/null 2>&1; then
    PS_FILES=(
        "$REPO_ROOT/setup.ps1"
        "$REPO_ROOT/hooks/post-tool-format.ps1"
        "$REPO_ROOT/hooks/pre-compact-memory.ps1"
        "$REPO_ROOT/hooks/session-start.ps1"
        "$REPO_ROOT/hooks/check-state-updated.ps1"
        "$REPO_ROOT/hooks/check-bash-safety.ps1"
        "$REPO_ROOT/hooks/check-config-change.ps1"
        "$REPO_ROOT/hooks/check-workflow-gates.ps1"
        "$REPO_ROOT/hooks/lib/default-branch.ps1"
        "$REPO_ROOT/hooks/lib/review-breaker.ps1"
    )
    for f in "${PS_FILES[@]}"; do
        if [[ ! -f "$f" ]]; then
            printf "  %s·%s skipped (not present): %s\n" \
                "$C_DIM" "$C_RESET" "${f#$REPO_ROOT/}"
            continue
        fi
        # Parse-only: feed the file into a PowerShell parser without executing.
        # [System.Management.Automation.Language.Parser]::ParseFile returns
        # errors without side-effects.
        errs=$(pwsh -NoProfile -Command "
            \$errs = \$null
            [void][System.Management.Automation.Language.Parser]::ParseFile('$f', [ref]\$null, [ref]\$errs)
            if (\$errs -and \$errs.Count -gt 0) {
                \$errs | ForEach-Object { Write-Output \$_.Message }
                exit 1
            }
            exit 0
        " 2>&1)
        if [[ $? -eq 0 ]]; then
            pass "parses: ${f#$REPO_ROOT/}"
        else
            fail "PowerShell parse error in ${f#$REPO_ROOT/}: $errs"
        fi
    done
else
    printf "  %s·%s skipped: pwsh not installed (Windows parity check disabled)\n" \
        "$C_DIM" "$C_RESET"
fi

# ---------------------------------------------------------------------------
# JSON templates must parse cleanly
# ---------------------------------------------------------------------------
start_test "JSON templates parse"

if command -v jq >/dev/null 2>&1; then
    # Collect every .json file we ship as a template/config
    while IFS= read -r -d '' f; do
        # Skip files under node_modules/, .git/, .worktrees/, user data
        case "$f" in
            */node_modules/*|*/.git/*|*/.worktrees/*) continue ;;
        esac
        if jq empty "$f" 2>/dev/null; then
            pass "parses: ${f#$REPO_ROOT/}"
        else
            err=$(jq empty "$f" 2>&1 || true)
            fail "JSON parse error in ${f#$REPO_ROOT/}: $err"
        fi
    done < <(find "$REPO_ROOT/settings" "$REPO_ROOT" -maxdepth 2 -name '*.json' -print0 2>/dev/null)
else
    printf "  %s·%s skipped: jq not installed\n" \
        "$C_DIM" "$C_RESET"
fi

# ---------------------------------------------------------------------------
# No __PLACEHOLDER__ leaks in the shipped CI workflow AFTER it's been
# stamped by setup.sh. We can't test that here because we haven't run
# setup — test-setup.sh covers the post-stamp case. But we DO want to
# verify that every __PLACEHOLDER__ in the source template has a
# substitution rule in both setup.sh and setup.ps1 (otherwise new
# placeholders get added and silently leak into user repos).
# ---------------------------------------------------------------------------
start_test "Every __PLACEHOLDER__ in ci-workflows has a substitution rule"

CI_TMPL="$REPO_ROOT/templates/ci-workflows/e2e.yml"
if [[ -f "$CI_TMPL" ]]; then
    # Extract unique __XXX__ placeholders from the template
    PLACEHOLDERS=$(grep -oE '__[A-Z_]+__' "$CI_TMPL" | sort -u)
    for ph in $PLACEHOLDERS; do
        # Must appear in BOTH setup.sh and setup.ps1 (or we ship a leak
        # on one platform).
        if grep -qF "$ph" "$REPO_ROOT/setup.sh"; then
            pass "setup.sh handles $ph"
        else
            fail "setup.sh does NOT substitute $ph (will leak in output)"
        fi
        if grep -qF "$ph" "$REPO_ROOT/setup.ps1"; then
            pass "setup.ps1 handles $ph"
        else
            fail "setup.ps1 does NOT substitute $ph (will leak in output)"
        fi
    done
    if [[ -z "$PLACEHOLDERS" ]]; then
        pass "no placeholders in CI template (nothing to substitute)"
    fi
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
report "test-lint.sh"
