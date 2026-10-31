#!/bin/bash
# Shared Stop checks for Claude Code and Codex.
# Preserve canonical state validation, Goal accounting and final-evidence
# advisories. Ordinary replies never require a state edit or changelog update;
# those belong to durable workflow checkpoints and finalization respectively.
# Blocking integrity failures use exit 2 with stderr diagnostics.

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

# A Stop-only human decision must not wait for unrelated final evidence.
# Keep budgets/state integrity independent and preserve full-certification truth.
_WORKFLOW_WAIVED_GATES=""
_WORKFLOW_WAIVER_HELPER="$HOOK_DIR/lib/verification-receipt.sh"
[ -f "$_WORKFLOW_WAIVER_HELPER" ] || _WORKFLOW_WAIVER_HELPER=hooks/lib/verification-receipt.sh
# With no decision sidecar, ordinary development must not invoke receipt checks.
_WORKFLOW_HAS_WAIVER=false
if [ -f "$STATE_MD" ]; then
    _WORKFLOW_WAIVER_CANDIDATE=$(tr -d '\r' < "$STATE_MD" | awk -F'|' '
        { key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key) }
        key=="Candidate receipt" { n++; value=$3; gsub(/^[ \t]+|[ \t]+$/, "", value) }
        END { if(n==1) print value }
    ')
    case "$_WORKFLOW_WAIVER_CANDIDATE" in
        '') ;;
        *)
            for _suffix in workflow-waiver review-waiver; do
                if [ -e "$_WORKFLOW_WAIVER_CANDIDATE.$_suffix" ] || [ -L "$_WORKFLOW_WAIVER_CANDIDATE.$_suffix" ]; then
                    _WORKFLOW_HAS_WAIVER=true
                fi
            done ;;
    esac
fi
if [ "$_WORKFLOW_HAS_WAIVER" = true ] && [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ] && [ -f "$_WORKFLOW_WAIVER_HELPER" ]; then
    if _WORKFLOW_WAIVER_OUT=$(bash "$_WORKFLOW_WAIVER_HELPER" check-workflow-waiver --boundary stop --state "$STATE_MD" 2>/dev/null); then
        _WORKFLOW_WAIVED_GATES=$(printf '%s\n' "$_WORKFLOW_WAIVER_OUT" | sed -n 's/^WAIVED_GATES://p')
        echo "FORGE_WORKFLOW_WAIVED: $_WORKFLOW_WAIVED_GATES; unwaived shipping checks remain required." >&2
    fi
fi

# Receipt-v2 Stop advisory belongs to finalization. Development checkpoints do
# not need final receipts; avoid repeated checks and stale warnings while the
# candidate is still being built. Shipping remains enforced by PreToolUse.
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
    _workflow_phase=$(tr -d '\r' < "$STATE_MD" | awk -F'|' '
        /^## Workflow$/ { in_workflow=1; next }
        in_workflow && /^## / { in_workflow=0 }
        in_workflow {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key == "Phase") {
                value=$3; gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                exit
            }
        }
    ')
    case "$_workflow_phase" in
    review|verify|verification|finalize|finalization|promote|promotion|ship|shipping)
        case "$_workflow_command" in ''|none|-|'—') ;;
        *)
            if ! printf '%s\n' "$_workflow_command" | grep -qE '^/quick-fix [a-z0-9]+(-[a-z0-9]+)*$'; then
                _vr="$HOOK_DIR/lib/verification-receipt.sh"
                [ -f "$_vr" ] || _vr="hooks/lib/verification-receipt.sh"
                if [ -z "$_WORKFLOW_WAIVED_GATES" ] && { [ ! -f "$_vr" ] || ! bash "$_vr" check --state "$STATE_MD" >/dev/null 2>&1; }; then
                    echo "FORGE_FINAL_EVIDENCE_STALE: candidate-bound review, verify-app, and E2E receipts no longer certify the current staged-clean candidate." >&2
                fi
            fi
            ;;
        esac
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

# --- Workflow state tracking ---
# State file is gitignored. Emit breadcrumb only when a legacy CONTINUITY.md
# is present (signals user upgraded but hasn't migrated yet) — avoids spamming
# every Stop event in repos that never had CONTINUITY.md.
if [ ! -f "$STATE_MD" ] && [ -f "CONTINUITY.md" ]; then
    echo "ℹ check-state-updated: Forge state.md not found, but CONTINUITY.md exists." >&2
    echo "  Run setup -f --dry-run, resolve every reported blocker, then run setup -f." >&2
fi

# All good, allow stop
forge_allow
