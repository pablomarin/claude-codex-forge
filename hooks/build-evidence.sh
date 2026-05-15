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

parse_workflow() {
    # Output (printed to stdout, pipe-friendly key|value lines):
    #   PHASE|<phase>
    #   NEXT|<next_step>
    #   TOTAL|<int>
    #   DONE|<int>
    [ -f "$STATE_MD" ] || return 0

    awk '
        BEGIN { phase=""; next_step=""; total=0; done=0; in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }
        # Markdown table: |  Phase  | <value> |
        in_workflow && /\|[[:space:]]*Phase[[:space:]]*\|/ {
            n=split($0,a,"|"); phase=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",phase)
        }
        in_workflow && /\|[[:space:]]*Next step[[:space:]]*\|/ {
            n=split($0,a,"|"); next_step=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",next_step)
        }
        in_workflow && in_checklist && /^- \[x\]/ { done++; total++ }
        in_workflow && in_checklist && /^- \[ \]/ { total++ }
        END {
            print "PHASE|" phase
            print "NEXT|" next_step
            print "TOTAL|" total
            print "DONE|" done
        }
    ' "$STATE_MD"
}

compute_reviewer_gate() {
    # Args: $1 = current HEAD sha
    # Output: "clean_same_iteration|matched_iteration|matched_head"
    local head_sha="$1"
    [ -f "$STATE_MD" ] || { echo "false||"; return 0; }
    [ -z "$head_sha" ] && { echo "false||"; return 0; }

    # Single awk pass: scope to ## Workflow / ### Checklist, extract reviewer rows
    # matching head_sha, track per-iteration which tools cleared. When both
    # codex AND pr-toolkit have cleared the same iteration at head_sha, emit
    # the iteration number and stop. Output: "<iter>" or empty.
    local matched
    matched=$(awk -v head="$head_sha" '
        BEGIN { in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }
        in_workflow && in_checklist && /^- \[x\][[:space:]]+Code review iteration [0-9]+ — / {
            # Parse: - [x] Code review iteration <iter> — <tool> clean — head=`<sha>`
            line=$0
            if (match(line, /iteration [0-9]+/)) {
                iter=substr(line, RSTART+10, RLENGTH-10)
            } else { next }
            if (line ~ /codex clean/)           { tool="codex" }
            else if (line ~ /pr-toolkit clean/) { tool="pr-toolkit" }
            else { next }
            if (match(line, /head=`[0-9a-f]+`/)) {
                sha=substr(line, RSTART+6, RLENGTH-7)
            } else { next }
            if (sha != head) { next }

            # Track via flat key (no assoc arrays — Bash 3.2 / gawk-portable)
            key=iter "|" tool
            seen[key]=1

            codex_key=iter "|codex"
            tk_key=iter "|pr-toolkit"
            if (seen[codex_key] && seen[tk_key]) { print iter; exit 0 }
        }
    ' "$STATE_MD")

    if [ -n "$matched" ]; then
        echo "true|${matched}|${head_sha}"
    else
        echo "false||"
    fi
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

# Parse ## Workflow section (checklist counts).
WF=$(parse_workflow)
PHASE=$(echo "$WF"       | grep '^PHASE|' | head -1 | cut -d'|' -f2-)
NEXT_STEP=$(echo "$WF"   | grep '^NEXT|'  | head -1 | cut -d'|' -f2-)
TOTAL_COUNT=$(echo "$WF" | grep '^TOTAL|' | head -1 | cut -d'|' -f2-)
DONE_COUNT=$(echo "$WF"  | grep '^DONE|'  | head -1 | cut -d'|' -f2-)
TOTAL_COUNT=${TOTAL_COUNT:-0}
DONE_COUNT=${DONE_COUNT:-0}

# Parse reviewer gate (code-review iteration rows in Checklist).
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
RG_RESULT=$(compute_reviewer_gate "$HEAD_SHA")
RG_CLEAN="${RG_RESULT%%|*}"
RG_REST="${RG_RESULT#*|}"
RG_ITER="${RG_REST%%|*}"
RG_HEAD="${RG_REST##*|}"

# Emit evidence JSON. Tasks 5-7 add more fields.
{
    echo "FORGE_GOAL_EVIDENCE_BEGIN"
    printf '{'
    printf '"type":"forge_goal_evidence",'
    printf '"schema_version":1,'
    printf '"produced_at_unix":%d,' "$NOW_UNIX"
    printf '%s,' "$SESSION_NONCE_JSON"
    printf '%s,' "$WORKFLOW_CMD_JSON"
    printf '"state":{"phase":"%s","next_step":"%s","checklist_total":%d,"checklist_done":%d},' \
        "$PHASE" "$NEXT_STEP" "$TOTAL_COUNT" "$DONE_COUNT"
    printf '"reviewer_gate":{"clean_same_iteration":%s,"matched_iteration":"%s","matched_head":"%s"},' \
        "$RG_CLEAN" "$RG_ITER" "$RG_HEAD"
    printf '"warnings":[],'
    printf '"errors":[]'
    printf '}\n'
    echo "FORGE_GOAL_EVIDENCE_END"
} >&2

exit 0
