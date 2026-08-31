#!/usr/bin/env bash
# tests/template/test-fixtures.sh — fingerprint checks on template source files.
#
# Catches regressions in the text content of templates without needing to
# actually run setup.sh. Uses literal grep (grep -F) for all substring
# matches, and has a block-comment-aware check for the storageState
# credential-leak case (which has a false-positive risk because the
# insecure pattern intentionally exists inside a /* ... */ block).
#
# Run from repo root:  bash tests/template/test-fixtures.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

# ---------------------------------------------------------------------------
# Test 1: playwright.config.template.ts — secure defaults + no branding leak
# ---------------------------------------------------------------------------
start_test "playwright.config.template.ts fingerprints"

PWCFG="$REPO_ROOT/templates/playwright/playwright.config.template.ts"
assert_file_exists "$PWCFG" "playwright config template exists"

# Branding leak regression
assert_not_contains "$PWCFG" "claude-codex-forge E2E" \
    "no 'claude-codex-forge E2E' in template header (Copilot #3)"

# Trace/video OFF in CI by default (Copilot #8)
assert_contains "$PWCFG" "process.env.CI" \
    "config branches on process.env.CI"
assert_matches "$PWCFG" 'trace:\s*process\.env\.CI' \
    "trace: is gated on process.env.CI"
assert_matches "$PWCFG" 'video:\s*process\.env\.CI' \
    "video: is gated on process.env.CI"
assert_contains "$PWCFG" 'PLAYWRIGHT_CI_TRACE' \
    "opt-in env var for CI trace is documented"

# ---------------------------------------------------------------------------
# Test 2: auth.fixture.template.ts — cookie default, API-key demoted
# (comment-aware: we explicitly want 'localStorage.setItem' to exist in the
# file INSIDE a block comment but NOT as live code)
# ---------------------------------------------------------------------------
start_test "auth.fixture.template.ts — cookie-default + block-commented insecure path"

AUTH="$REPO_ROOT/templates/playwright/auth.fixture.template.ts"
assert_file_exists "$AUTH" "auth fixture template exists"

# Loud security warning
assert_contains "$AUTH" "SECURITY WARNING" \
    "security warning header present"
assert_contains "$AUTH" "INSECURE ALTERNATIVE" \
    "API-key path labeled INSECURE ALTERNATIVE"

# Active (non-commented) path must use the cookie flow via context.request
# Look for the signature call — it should NOT be inside a /* */ block.
assert_contains "$AUTH" "context.request.post" \
    "cookie auth path uses context.request.post"

# The dangerous localStorage.setItem pattern MUST only appear inside a block
# comment. Strip /* ... */ blocks and then assert absence in the remaining
# live code. Use Python for robust multi-line block-comment stripping
# (sed is a pain with multi-line patterns across shells).
if command -v python3 >/dev/null 2>&1; then
    # Remove /* ... */ blocks (non-greedy, across newlines), then check.
    LIVE_CODE=$(python3 -c '
import re, sys
with open(sys.argv[1]) as f:
    src = f.read()
# Strip /* ... */ blocks (the file uses the classic pattern, non-nested).
stripped = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
sys.stdout.write(stripped)
' "$AUTH")
    if echo "$LIVE_CODE" | grep -qF "localStorage.setItem"; then
        fail "localStorage.setItem appears in live code (not just in block comment)"
    else
        pass "localStorage.setItem only appears inside /* … */ comment"
    fi
else
    # Fallback: weaker check — fail loud but don't block the whole suite.
    fail "python3 not available; cannot do block-comment-aware check" || true
    pass "(skipped block-comment check — needs python3)"
fi

# ---------------------------------------------------------------------------
# Test 3: verify-e2e.md — structured response header
# ---------------------------------------------------------------------------
start_test "verify-e2e.md — structured response format"

VE2E="$REPO_ROOT/agents/verify-e2e.md"
assert_file_exists "$VE2E" "verify-e2e agent definition exists"

assert_contains "$VE2E" "VERDICT: PASS | FAIL | PARTIAL" \
    "header documents VERDICT values"
assert_contains "$VE2E" "SUGGESTED_PATH:" \
    "header documents SUGGESTED_PATH field"

# Read-only invariant: frontmatter tools list must NOT include Write/Edit
# (frontmatter is lines between opening '---' and next '---'). Extract it
# and assert.
FM=$(awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f' "$VE2E")
if echo "$FM" | grep -qE '^\s*-\s*(Write|Edit)\s*$'; then
    fail "Write or Edit tool listed in frontmatter (breaks read-only invariant)"
else
    pass "no Write/Edit in frontmatter tools list"
fi

# ---------------------------------------------------------------------------
# Test 4: post-tool-format.sh — no hardcoded src/ shortcut
# ---------------------------------------------------------------------------
start_test "post-tool-format.sh — monorepo walk-up"

HOOK="$REPO_ROOT/hooks/post-tool-format.sh"
assert_file_exists "$HOOK" "post-tool-format.sh exists"

# Regression guard: the old buggy version hardcoded $CLAUDE_PROJECT_DIR/src.
# The new version walks up looking for pyproject.toml.
assert_contains "$HOOK" 'pyproject.toml' \
    "walks for pyproject.toml"
assert_not_contains "$HOOK" 'CLAUDE_PROJECT_DIR/src' \
    "no hardcoded CLAUDE_PROJECT_DIR/src shortcut"
# Both ruff commands must be present (regression: --fix was silently dropped)
assert_contains "$HOOK" 'ruff check --fix' \
    "runs ruff check --fix"
assert_contains "$HOOK" 'ruff format' \
    "runs ruff format"

# ---------------------------------------------------------------------------
# Test 5: prd/create.md — fence balance
# ---------------------------------------------------------------------------
start_test "prd/create.md — fence balance"

PRD="$REPO_ROOT/commands/prd/create.md"
assert_file_exists "$PRD" "prd/create.md exists"

# Count fences. Balanced file: each ``` and ```` opens exactly one block
# and closes exactly one block — so the total count should be even.
# Pattern ^```[a-zA-Z]*$ matches both closes (bare ```) and opens (```lang).
# The grep -E semantics mean `^...$` is per-line, excluding 4+ backticks
# (``` + another backtick doesn't match `[a-zA-Z]*$`).
COUNT_3=$(grep -cE '^```[a-zA-Z]*$' "$PRD" || true)
COUNT_4=$(grep -cE '^````[a-zA-Z]*$' "$PRD" || true)
# The file uses a FOUR-backtick outer block with nested THREE-backtick blocks.
# A balanced file has: (count of ```` == 2) AND (count of ``` pairs is even).
assert_equals "$COUNT_4" "2" "exactly 2 four-backtick fences (open + close outer template)"
if (( COUNT_3 % 2 == 0 )); then
    pass "three-backtick fences balanced (count: $COUNT_3)"
else
    fail "three-backtick fences unbalanced (count: $COUNT_3, must be even)"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
report "test-fixtures.sh"

# ---------------------------------------------------------------------------
# Shared fixture helpers (sourced by other test-*.sh)
#
# These helpers are appended after `report` so they don't run as test cases
# in this file but ARE defined in the shell scope when other test files
# `source "$REPO_ROOT/tests/template/test-fixtures.sh"`.
# ---------------------------------------------------------------------------

# make_state_md <scratch-dir> <command> [phase] [next] [unchecked-gates...]
# Writes a minimal .claude/local/state.md with the given Workflow fields.
# Default: command=/new-feature foo, no unchecked gates (empty checklist).
make_state_md() {
    local scratch="$1"
    local cmd="${2:-/new-feature foo}"
    local phase="${3:-3 — Design}"
    local next="${4:-Plan written}"
    shift 4
    mkdir -p "$scratch/.claude/local"
    {
        echo "## Workflow"
        echo ""
        echo "| Field     | Value |"
        echo "| --------- | ----- |"
        echo "| Command   | $cmd  |"
        echo "| Phase     | $phase |"
        echo "| Next step | $next |"
        echo ""
        echo "### Checklist"
        echo ""
        for item in "$@"; do
            echo "- [ ] $item"
        done
    } > "$scratch/.claude/local/state.md"
}

# make_legacy_continuity_for_migration <scratch-dir>
# Writes a canonical legacy CONTINUITY.md fixture for full-refresh inventory tests.
make_legacy_continuity_for_migration() {
    local scratch="$1"
    cat > "$scratch/CONTINUITY.md" <<'EOF'
# CONTINUITY

## Goal

Build a thing that does the thing.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Database | PostgreSQL | ACID; pgvector |
| Auth     | OAuth2 + JWT | Industry standard |

## State

### Done (recent 2-3 only)

- 2026-04-01: shipped feature X
- 2026-04-02: shipped feature Y
- 2026-04-03: shipped feature Z (older legacy entry)
- 2026-04-04: ancient entry (also trimmed)

### Now

Working on the migration assistant.

### Next

- ship PR #2
- write CHANGELOG entry

EOF
    # Also drop a CLAUDE.md with the dangling @-import.
    cat > "$scratch/CLAUDE.md" <<'EOF'
@CONTINUITY.md

# CLAUDE.md - Test Project

## Project Overview

A test project.
EOF
}
