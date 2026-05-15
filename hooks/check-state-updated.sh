#!/bin/bash
# .claude/hooks/check-state-updated.sh
# This hook runs when Claude is about to stop responding.
#
# THREE CONCERNS — only ONE blocks:
#
#   1. state.md missing breadcrumb (advisory, stderr only, exit 0).
#      Fires only when legacy CONTINUITY.md is present (signals upgraded
#      install that hasn't run --migrate yet). Suppressed otherwise to
#      avoid spamming every Stop event.
#
#   2. Workflow reminder (advisory, stderr only, exit 0).
#      Reads .claude/local/state.md ## Workflow table; emits
#      "WORKFLOW: <cmd> | Phase: <n> | Next: <step>" so the model always
#      sees current phase even when no issues fire.
#
#   3. CHANGELOG threshold gate (BLOCKS via exit 2).
#      If 4+ files changed on branch (committed + uncommitted) but
#      docs/CHANGELOG.md was never modified, hook blocks the stop with
#      a stderr message. This is the ONLY blocking concern.
#
# Uses exit code 2 + stderr to block (avoids JSON stdout parsing issues
# caused by shell profile echo statements polluting stdout).
#
# Requirements: git
# Optional: jq (recommended for robust JSON parsing, falls back to grep)

# Note: NOT using `set -e` here. Arithmetic expansions like `$((0 + 0))` (which fire
# whenever both BRANCH_CHANGED and UNCOMMITTED_FILES are 0 — i.e., a clean session)
# return exit status 1, which would silently exit the entire hook with status 1
# under set -e. Every external command below that can fail is already guarded with
# `2>/dev/null` and an explicit `|| fallback`, so set -e was redundant defense
# but produced a real silent-failure under normal clean-session conditions.
INPUT=$(cat)

# Parse stop_hook_active (jq preferred, grep fallback)
if command -v jq &> /dev/null; then
    STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
else
    STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' | head -1)
    [ -n "$STOP_HOOK_ACTIVE" ] && STOP_HOOK_ACTIVE="true" || STOP_HOOK_ACTIVE="false"
fi
# Emit FORGE_GOAL evidence FIRST — must run on every Stop call,
# including those with stop_hook_active=true (active /goal loop),
# so the /goal verifier sees the current evidence in transcript.
EVIDENCE_SCRIPT="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/build-evidence.sh"
if [ -x "$EVIDENCE_SCRIPT" ]; then
    bash "$EVIDENCE_SCRIPT" || true   # non-blocking; stderr passes through naturally
fi

[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# All git commands run in current directory (Claude cd's into worktrees)
# Only count tracked modifications (staged + unstaged), NOT untracked files (??)
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ')

# Files modified (uncommitted)
CHANGELOG_MODIFIED=$(git status --porcelain docs/CHANGELOG.md 2>/dev/null | wc -l | tr -d ' ')

# Total files changed on branch (committed + uncommitted) vs default branch
# Resolve the repo's default branch via the shared helper. The helper lives
# alongside this hook at .claude/hooks/lib/default-branch.sh in installed
# downstream repos, and at hooks/lib/default-branch.sh in this template.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# Helper-bail breadcrumb (stderr): if the helper exits non-zero, surface that the
# fallback fired so the user/log has at least one signal. Without this, a master-default
# repo whose helper bailed would silently use "main" → wrong BRANCH_BASE → spurious
# CHANGELOG/CONTINUITY threshold gating, with no clue why.
DEFAULT_BRANCH=$(bash "$HOOK_DIR/lib/default-branch.sh" 2>/dev/null) \
    || { DEFAULT_BRANCH="main"; echo "⚠ check-state-updated: default-branch helper bailed; assuming 'main'" >&2; }
# Merge-base fallback chain: prefer local <default> if it exists; else use
# origin/<default> (single-branch clones may have only the remote-tracking ref);
# else degrade to HEAD~10 (last-resort window for branch-change counting).
if git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
    BRANCH_BASE=$(git merge-base "$DEFAULT_BRANCH" HEAD 2>/dev/null || echo "HEAD~10")
elif git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    BRANCH_BASE=$(git merge-base "origin/$DEFAULT_BRANCH" HEAD 2>/dev/null || echo "HEAD~10")
else
    BRANCH_BASE="HEAD~10"
fi
BRANCH_CHANGED=$(git diff --name-only "$BRANCH_BASE" HEAD 2>/dev/null | wc -l | tr -d ' ')
UNCOMMITTED_FILES=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
TOTAL_CHANGED=$((BRANCH_CHANGED + UNCOMMITTED_FILES))

# Check if CHANGELOG was updated anywhere on branch
CHANGELOG_IN_BRANCH=$(git diff --name-only "$BRANCH_BASE" HEAD 2>/dev/null | grep -c "CHANGELOG.md" || true)

# --- Workflow state tracking ---
# State file is gitignored. Emit breadcrumb only when a legacy CONTINUITY.md
# is present (signals user upgraded but hasn't migrated yet) — avoids spamming
# every Stop event in repos that never had CONTINUITY.md.
if [ ! -f ".claude/local/state.md" ] && [ -f "CONTINUITY.md" ]; then
    echo "ℹ check-state-updated: .claude/local/state.md not found, but CONTINUITY.md exists." >&2
    echo "  Run setup --migrate to move your content to the new structure." >&2
    # Continue to CHANGELOG check — gates are independent.
fi

# If .claude/local/state.md has an active workflow, extract phase/next-step for advisory reminder.
#
# IMPORTANT: scope the extraction to ONLY the `## Workflow` section. Migrated
# content (e.g., from `setup.sh --migrate` ingesting old CONTINUITY.md "### Done"
# entries that mention prior workflow scaffolds) can leave stray `| Command |`
# lines elsewhere in the file. A whole-file grep would match every one of them
# and `xargs` would join them with spaces — yielding garbage like
# "WORKFLOW: none /lifecycle | Phase: n/a shipping". Scope first, then match.
WORKFLOW_REMINDER=""
if [ -f ".claude/local/state.md" ]; then
    WORKFLOW_BLOCK=$(awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag' .claude/local/state.md 2>/dev/null)
    WORKFLOW_CMD=$(echo "$WORKFLOW_BLOCK" | grep -E '\|\s*Command\s*\|' | head -1 | awk -F'|' '{print $3}' | xargs)
    if [ -n "$WORKFLOW_CMD" ] && [ "$WORKFLOW_CMD" != "none" ] && [ "$WORKFLOW_CMD" != "—" ] && [ "$WORKFLOW_CMD" != "-" ]; then
        WORKFLOW_PHASE=$(echo "$WORKFLOW_BLOCK" | grep -E '\|\s*Phase\s*\|' | head -1 | awk -F'|' '{print $3}' | xargs)
        WORKFLOW_NEXT=$(echo "$WORKFLOW_BLOCK" | grep -E '\|\s*Next step\s*\|' | head -1 | awk -F'|' '{print $3}' | xargs)
        WORKFLOW_REMINDER="WORKFLOW: $WORKFLOW_CMD | Phase: $WORKFLOW_PHASE | Next: $WORKFLOW_NEXT"
    fi
fi

ISSUES=""

# Block: 3+ files changed on branch but CHANGELOG.md never updated
if [ "$TOTAL_CHANGED" -gt 3 ] && [ "$CHANGELOG_IN_BRANCH" -eq 0 ] && [ "$CHANGELOG_MODIFIED" -eq 0 ]; then
    ISSUES="${ISSUES:+$ISSUES }Update docs/CHANGELOG.md ($TOTAL_CHANGED files changed this session)."
fi

# Block using exit code 2 + stderr (robust — immune to shell profile stdout pollution)
if [ -n "$ISSUES" ]; then
    # Prepend workflow reminder if active (so model always sees current phase)
    [ -n "$WORKFLOW_REMINDER" ] && ISSUES="[$WORKFLOW_REMINDER] $ISSUES"
    echo "$ISSUES" >&2
    exit 2
fi

# Advisory: remind about active workflow even when no issues (non-blocking)
if [ -n "$WORKFLOW_REMINDER" ]; then
    echo "$WORKFLOW_REMINDER" >&2
fi

# All good, allow stop
exit 0
