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

# ---------------------------------------------------------------------------
# Task 8: /forge-goal stuck-detection soft warning.
#
# Fires after build-evidence (which writes .claude/local/forge-goal-last-fingerprint
# as a side-channel). After 5 consecutive identical progress_fingerprint values,
# emits FORGE_GOAL_STUCK_WARNING to STDERR. Informational only — does NOT abort.
# Fires even when stop_hook_active=true (inside the active /goal loop — where
# it's most useful). Counter lives in .claude/local/forge-goal-stuck-count:
# format "<count>|<fingerprint_sha256>".
# ---------------------------------------------------------------------------
_forge_goal_stuck_check() {
    local state_md=".claude/local/state.md"
    local fp_file=".claude/local/forge-goal-last-fingerprint"
    local counter_file=".claude/local/forge-goal-stuck-count"

    # Only proceed if /forge-goal is active: state.md must have a non-empty
    # nonce in the ## /goal session table. Best-effort: if missing, skip silently.
    [ -f "$state_md" ] || return 0

    local nonce
    nonce=$(tr -d '\r' < "$state_md" \
        | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag' \
        | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
        | head -1 | awk -F'|' '{print $3}' | xargs 2>/dev/null)
    [ -n "$nonce" ] || return 0

    # Read the current fingerprint written by build-evidence.sh.
    [ -f "$fp_file" ] || return 0
    local current_fp
    current_fp=$(tr -d '[:space:]' < "$fp_file" 2>/dev/null)
    [ -n "$current_fp" ] || return 0

    # Read previous counter state.
    local prev_count=0
    local prev_fp=""
    if [ -f "$counter_file" ]; then
        local raw
        raw=$(cat "$counter_file" 2>/dev/null)
        prev_count="${raw%%|*}"
        prev_fp="${raw##*|}"
        # Validate that prev_count is a non-negative integer.
        case "$prev_count" in
            ''|*[!0-9]*) prev_count=0; prev_fp="" ;;
        esac
    fi

    # Update counter: increment if fingerprint unchanged, reset if changed.
    local new_count
    if [ "$current_fp" = "$prev_fp" ]; then
        new_count=$((prev_count + 1))
    else
        new_count=1
    fi

    # Persist updated counter.
    mkdir -p ".claude/local" 2>/dev/null || true
    printf '%s|%s\n' "$new_count" "$current_fp" > "$counter_file" 2>/dev/null || true

    # Emit warning if threshold reached (>= 5 consecutive identical fingerprints).
    if [ "$new_count" -ge 5 ]; then
        echo "FORGE_GOAL_STUCK_WARNING: no measurable progress for $new_count consecutive turns (fingerprint unchanged). Consider invoking /council, checkpointing state.md, or surfacing a blocker. Loop continues — this is informational only." >&2
    fi
    return 0
}
_forge_goal_stuck_check

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

# Block: 3+ files changed on branch but CHANGELOG.md never updated.
# "files changed on branch vs $DEFAULT_BRANCH" — count is committed + uncommitted
# diff vs the merge-base, NOT files-this-turn.
if [ "$TOTAL_CHANGED" -gt 3 ] && [ "$CHANGELOG_IN_BRANCH" -eq 0 ] && [ "$CHANGELOG_MODIFIED" -eq 0 ]; then
    ISSUES="${ISSUES:+$ISSUES }Update docs/CHANGELOG.md ($TOTAL_CHANGED files changed on branch vs $DEFAULT_BRANCH)."
fi

# Block using exit code 2 + stderr (robust — immune to shell profile stdout pollution)
if [ -n "$ISSUES" ]; then
    # Prepend workflow reminder if active (so model always sees current phase)
    [ -n "$WORKFLOW_REMINDER" ] && ISSUES="[$WORKFLOW_REMINDER] $ISSUES"
    echo "$ISSUES" >&2

    # Detect open PR for current branch. Once a PR is open, the CHANGELOG gate
    # downgrades from blocking (exit 2) to advisory (exit 0): the human reviewer
    # carries the signal, and per-turn blocking during CI wait is just noise.
    # gh availability and network are best-effort; on failure, default to "no
    # open PR" so the original blocking behavior is preserved.
    # Probe only runs when ISSUES is non-empty — clean stops pay no gh-API cost.
    PR_OPEN=false
    if command -v gh >/dev/null 2>&1; then
        PR_STATE=$(gh pr view --json state -q .state 2>/dev/null || echo "")
        [ "$PR_STATE" = "OPEN" ] && PR_OPEN=true
    fi

    if [ "$PR_OPEN" = "true" ]; then
        # Advisory only — PR already open. Exit 0 so the message is informational
        # and the build-evidence STDERR dump is not labeled "Stop hook error".
        exit 0
    fi
    exit 2
fi

# Advisory: remind about active workflow even when no issues (non-blocking)
if [ -n "$WORKFLOW_REMINDER" ]; then
    echo "$WORKFLOW_REMINDER" >&2
fi

# All good, allow stop
exit 0
