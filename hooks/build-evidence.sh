#!/usr/bin/env bash
# hooks/build-evidence.sh — emit FORGE_GOAL_EVIDENCE JSON to STDERR.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers.
# Stop hook (check-state-updated.sh) invokes this each turn so the Haiku
# verifier inside an active /goal sees the evidence in the transcript.

set -u

NOW_UNIX=$(date +%s)

STATE_MD=".claude/local/state.md"

parse_goal_session() {
    # Echo "nonce|workflow_command" or empty if section missing.
    # Section format: Markdown table under `## /goal session` heading.
    [ -f "$STATE_MD" ] || return 0

    # CRLF normalize FIRST, then awk-scope (Codex P1.7 fix from plan-review).
    local block
    block=$(tr -d '\r' < "$STATE_MD" \
            | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag')

    local nonce cmd
    nonce=$(echo "$block" | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
            | head -1 | awk -F'|' '{print $3}' | xargs)
    cmd=$(echo "$block" | grep -E '\|[[:space:]]*workflow_command[[:space:]]*\|' \
            | head -1 | awk -F'|' '{print $3}' | xargs)

    printf '%s|%s' "$nonce" "$cmd"
}

json_str_field() {
    # Usage: json_str_field "key" "value" — value can be empty (becomes null).
    local key="$1"
    local val="$2"
    if [ -z "$val" ]; then
        printf '"%s":null' "$key"
    else
        # Minimal escaping — backslash and double-quote only. State.md doesn't
        # carry control chars in these fields by convention.
        local esc="${val//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        printf '"%s":"%s"' "$key" "$esc"
    fi
}

# Parse ## /goal session section.
GOAL_PARSED=$(parse_goal_session)
GOAL_NONCE="${GOAL_PARSED%%|*}"
GOAL_CMD="${GOAL_PARSED##*|}"

SESSION_NONCE_JSON=$(json_str_field "session_nonce" "$GOAL_NONCE")
WORKFLOW_CMD_JSON=$(json_str_field "workflow_command" "$GOAL_CMD")

# Emit evidence JSON. Tasks 4-7 add more fields.
{
    echo "FORGE_GOAL_EVIDENCE_BEGIN"
    printf '{'
    printf '"type":"forge_goal_evidence",'
    printf '"schema_version":1,'
    printf '"produced_at_unix":%d,' "$NOW_UNIX"
    printf '%s,' "$SESSION_NONCE_JSON"
    printf '%s,' "$WORKFLOW_CMD_JSON"
    printf '"warnings":[],'
    printf '"errors":[]'
    printf '}\n'
    echo "FORGE_GOAL_EVIDENCE_END"
} >&2

exit 0
