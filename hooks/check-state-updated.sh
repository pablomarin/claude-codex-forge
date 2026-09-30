#!/bin/bash
# .claude/hooks/check-state-updated.sh
# This hook runs when Claude is about to stop responding.
#
# THREE CONCERNS — only ONE blocks:
#
#   1. state.md missing breadcrumb (advisory, stderr only, exit 0).
#      Fires only when legacy CONTINUITY.md is present (signals upgraded
#      install that still needs full-refresh reconciliation). Suppressed otherwise to
#      avoid spamming every Stop event.
#
#   2. Workflow checkpoint (v6 only).
#      An unchanged canonical state hash continues the model once with the
#      current command/phase/next step; changed state stops normally.
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
forge_allow() {
    printf '%s' "$INPUT" | grep -qE '"host"[[:space:]]*:[[:space:]]*"codex"' && printf '{}\n'
    exit 0
}

# Parse stop_hook_active (jq preferred, grep fallback)
if command -v jq &> /dev/null; then
    STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
else
    STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' | head -1)
    [ -n "$STOP_HOOK_ACTIVE" ] && STOP_HOOK_ACTIVE="true" || STOP_HOOK_ACTIVE="false"
fi

# ---------------------------------------------------------------------------
# Worktree CWD fix (v5.32) — same rationale as build-evidence.sh. CC's Stop
# hook runs with CWD=$CLAUDE_PROJECT_DIR (the parent project in worktree
# sessions), but the user's actual session CWD lives in the stdin JSON.
# cd there so relative state.md reads and git ops target the worktree.
# ---------------------------------------------------------------------------
if command -v jq &> /dev/null; then
    HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
else
    HOOK_CWD=$(printf '%s' "$INPUT" \
        | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 \
        | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)
fi
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    # Normalize to repo/worktree root in case stdin.cwd points at a subdirectory
    # (Codex P2-1, v5.32 review). Without this, relative paths would miss.
    NORMALIZED=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$NORMALIZED" ] && [ -d "$NORMALIZED" ]; then
        cd "$NORMALIZED" 2>/dev/null || true
    else
        cd "$HOOK_CWD" 2>/dev/null || true
    fi
elif TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$TOPLEVEL" ]; then
    cd "$TOPLEVEL" 2>/dev/null || true
fi

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
STATE_HELPER="$HOOK_DIR/lib/state-path.sh"
[ -f "$STATE_HELPER" ] || STATE_HELPER="hooks/lib/state-path.sh"
STATE_MD=""
if [ -f "$STATE_HELPER" ]; then
    # shellcheck disable=SC1090
    . "$STATE_HELPER"
    if ! STATE_MD=$(forge_state_path "$(pwd)" read); then
        if [ -e .forge/version ] || [ -L .forge/version ] \
            || [ -e .forge/local/state.md ] || [ -L .forge/local/state.md ] \
            || [ -e .forge/local ] || [ -L .forge/local ] || [ -L .forge ]; then
            echo "FORGE_STATE_INVALID: canonical v6 state could not be resolved" >&2
            exit 2
        fi
        STATE_MD=""
    fi
fi
STATE_LOCAL_DIR=".forge/local"
case "$STATE_MD" in */.claude/local/state.md) STATE_LOCAL_DIR=".claude/local" ;; esac

_forge_hash_text() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else sha256sum | awk '{print $1}'
    fi
}
_forge_hash_file() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'
    fi
}

# Stop is self-sufficient: if the evidence side channel is absent or older than
# canonical state, build it now. Atomic publication in build-evidence prevents a
# concurrent Codex Stop from exposing a partial fingerprint.
if [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ]; then
    _fp="$STATE_LOCAL_DIR/forge-goal-last-fingerprint"
    if [ ! -f "$_fp" ] || [ "$STATE_MD" -nt "$_fp" ]; then
        _builder="$HOOK_DIR/build-evidence.sh"
        [ -f "$_builder" ] && printf '%s' "$INPUT" | bash "$_builder" >&2 || true
    fi
fi

# Receipt-v2 Stop advisory: every active V6 workflow needs a complete current
# receipt set. Warn even while task-scoped paths are still placeholders so a
# fresh engine cannot mistake an unreviewed checkpoint for final evidence.
# Shipping remains enforced by the PreToolUse gate; Stop does not turn this
# reminder into a second policy engine.
if [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ]; then
    _workflow_command=$(tr -d '\r' < "$STATE_MD" | awk -F'|' '
        /^## Workflow$/ { in_workflow=1; next }
        in_workflow && /^## / { in_workflow=0 }
        in_workflow {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key == "Command") {
                value=$3; gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                exit
            }
        }
    ')
    case "$_workflow_command" in ''|none|-|'—') ;; *)
        _vr="$HOOK_DIR/lib/verification-receipt.sh"
        [ -f "$_vr" ] || _vr="hooks/lib/verification-receipt.sh"
        if [ ! -f "$_vr" ] || ! bash "$_vr" check --state "$STATE_MD" >/dev/null 2>&1; then
            echo "FORGE_FINAL_EVIDENCE_STALE: candidate-bound review, verify-app, and E2E receipts no longer certify the current staged-clean candidate." >&2
        fi
        ;;
    esac
fi

# Native Goal accounting is repository-local and shared through Git's common
# directory, so the same objective continues across linked worktrees and engines.
if [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ]; then
    _goal_nonce=$(tr -d '\r' < "$STATE_MD" | awk -F'|' '
        /^## \/goal session$/ { active=1; next }
        active && /^## / { active=0 }
        active {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (tolower(key) == "nonce") {
                value=$3; gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value; exit
            }
        }
    ')
    case "$_goal_nonce" in ''|'<uuid-v4-lowercase>') ;; *)
        if command -v jq >/dev/null 2>&1; then
            _goal_event_id=$(printf '%s' "$INPUT" | jq -r \
                '.turn_id // .hook_turn_id // .assistant_message_id // .last_assistant_message // ""' \
                2>/dev/null || true)
        else
            _goal_event_id=$(printf '%s' "$INPUT" | grep -Eo \
                '"(turn_id|hook_turn_id|assistant_message_id|last_assistant_message)"[[:space:]]*:[[:space:]]*"[^"]+"' \
                | head -1 || true)
        fi
        if [ -n "$_goal_event_id" ]; then
            _goal_ledger="$HOOK_DIR/lib/goal-ledger.sh"
            [ -f "$_goal_ledger" ] || {
                echo "FORGE_GOAL_LEDGER_TAMPERED: repository-local goal ledger helper is missing" >&2
                exit 2
            }
            printf '%s' "$INPUT" | bash "$_goal_ledger" charge --project "$(pwd -P)" --state "$STATE_MD" --event-json -
            _goal_rc=$?
            [ "$_goal_rc" -eq 0 ] || exit "$_goal_rc"
        fi
        ;;
    esac
fi

# Note: build-evidence is no longer invoked inline. It runs as its own Stop
# hook entry (registered in settings.template.json) BEFORE this one — so its
# STDERR output is rendered as informational hook output rather than being
# concatenated with our exit-2 stderr and labeled "Stop hook error" by CC.
# build-evidence still writes the fingerprint side-channel file that the
# stuck-detection logic below reads.

# ---------------------------------------------------------------------------
# Task 8: /forge-goal stuck-detection soft warning.
#
# build-evidence.sh runs as a separate Stop hook entry BEFORE this one (per
# settings.template.json hook ordering) and writes the current
# progress_fingerprint to .claude/local/forge-goal-last-fingerprint as a
# side-channel. We read it here. After 5 consecutive identical fingerprints,
# emit FORGE_GOAL_STUCK_WARNING to STDERR. Informational only — does NOT abort.
# Fires even when stop_hook_active=true (inside the active /goal loop — where
# it's most useful). Counter lives in .claude/local/forge-goal-stuck-count:
# format "<count>|<fingerprint_sha256>".
# ---------------------------------------------------------------------------
_forge_goal_stuck_check() {
    local state_md="$STATE_MD"
    local fp_file="$STATE_LOCAL_DIR/forge-goal-last-fingerprint"
    local counter_file="$STATE_LOCAL_DIR/forge-goal-stuck-count"

    # Only proceed if /forge-goal is active: state.md must have a non-empty
    # nonce in the ## /goal session table. Best-effort: if missing, skip silently.
    [ -f "$state_md" ] || return 0

    local nonce
    nonce=$(tr -d '\r' < "$state_md" \
        | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag' \
        | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
        | head -1 | awk -F'|' '{print $3}' | xargs 2>/dev/null)
    [ -n "$nonce" ] || return 0
    [ "$nonce" = "<uuid-v4-lowercase>" ] && return 0

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
    mkdir -p "$STATE_LOCAL_DIR" 2>/dev/null || true
    printf '%s|%s\n' "$new_count" "$current_fp" > "$counter_file" 2>/dev/null || true

    # Emit warning if threshold reached (>= 5 consecutive identical fingerprints).
    if [ "$new_count" -ge 5 ]; then
        echo "FORGE_GOAL_STUCK_WARNING: no measurable progress for $new_count consecutive turns (fingerprint unchanged). If progress is blocked because a genuine non-destructive decision is required to continue the active native Goal, invoke /council; otherwise checkpoint state.md or surface a blocker. Loop continues — this is informational only." >&2
    fi
    return 0
}
_forge_goal_stuck_check

[ "$STOP_HOOK_ACTIVE" = "true" ] && forge_allow

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
if [ ! -f "$STATE_MD" ] && [ -f "CONTINUITY.md" ]; then
    echo "ℹ check-state-updated: Forge state.md not found, but CONTINUITY.md exists." >&2
    echo "  Run setup -f --dry-run, resolve every reported blocker, then run setup -f." >&2
    # Continue to CHANGELOG check — gates are independent.
fi

# If .claude/local/state.md has an active workflow, extract phase/next-step for advisory reminder.
#
# IMPORTANT: scope the extraction to ONLY the `## Workflow` section. Migrated
# content carried forward from an older Forge state source (for example old "### Done"
# entries that mention prior workflow scaffolds) can leave stray `| Command |`
# lines elsewhere in the file. A whole-file grep would match every one of them
# and `xargs` would join them with spaces — yielding garbage like
# "WORKFLOW: none /lifecycle | Phase: n/a shipping". Scope first, then match.
WORKFLOW_REMINDER=""
if [ -f "$STATE_MD" ]; then
    WORKFLOW_BLOCK=$(tr -d '\r' < "$STATE_MD" | awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag' 2>/dev/null)
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
        forge_allow
    fi
    exit 2
fi

# A changed v6 state checkpoint stops normally. If the exact state hash remains
# unchanged across normal Stops, give the model one visible continuation turn.
# This avoids paying an extra model turn when the workflow already checkpointed.
if [ -n "$WORKFLOW_REMINDER" ]; then
    if [ "$STATE_LOCAL_DIR" != .forge/local ]; then
        echo "$WORKFLOW_REMINDER" >&2
        forge_allow
    fi
    STATE_STOP_HASH=$(_forge_hash_file "$STATE_MD") || {
        echo "FORGE_STATE_INVALID: could not hash canonical state checkpoint" >&2
        exit 2
    }
    STATE_STOP_FILE="$STATE_LOCAL_DIR/state-last-stop.sha256"
    if [ -L "$STATE_STOP_FILE" ] || { [ -e "$STATE_STOP_FILE" ] && [ ! -f "$STATE_STOP_FILE" ]; }; then
        echo "FORGE_STATE_INVALID: invalid state checkpoint sidecar" >&2
        exit 2
    fi
    STATE_STOP_PREVIOUS=$(tr -d '[:space:]' < "$STATE_STOP_FILE" 2>/dev/null || true)
    if [ "$STATE_STOP_PREVIOUS" != "$STATE_STOP_HASH" ]; then
        STATE_STOP_TMP=$(mktemp "$STATE_LOCAL_DIR/.state-last-stop.XXXXXX") || exit 2
        printf '%s\n' "$STATE_STOP_HASH" > "$STATE_STOP_TMP" \
            && mv -f "$STATE_STOP_TMP" "$STATE_STOP_FILE" \
            || { rm -f "$STATE_STOP_TMP"; echo "FORGE_STATE_INVALID: could not publish state checkpoint sidecar" >&2; exit 2; }
        forge_allow
    fi
    echo "$WORKFLOW_REMINDER. Run .forge/hooks/lib/workflow-state.sh show before continuing; use workflow-state.sh checkpoint for its exact next step and record any durable learning in the appropriate Forge memory layer before stopping." >&2
    exit 2
fi

# All good, allow stop
forge_allow
