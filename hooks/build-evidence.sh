#!/usr/bin/env bash
# hooks/build-evidence.sh — emit FORGE_GOAL_EVIDENCE JSON to STDERR.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers.
# Registered as its own Stop hook (settings.template.json) so its STDERR
# output is shown as informational `Ran stop hook` rather than being merged
# into check-state-updated's exit-2 output (which CC labels "Stop hook error").
# Always exits 0 — never blocks.

set -u

NOW_UNIX=$(date +%s)

# ---------------------------------------------------------------------------
# Worktree CWD fix (v5.32) — surfaced 2026-05-18 in msai-v2 portfolio-backtest
# soak: evidence reported `session_nonce:null, phase:null` even though the
# worktree state.md was populated. Root cause: CC's Stop hook ran with
# CWD=$CLAUDE_PROJECT_DIR (the parent project), not the worktree where the
# /goal session was actually active.
#
# Claude Code sends the session's real CWD in the Stop hook stdin JSON.
# Parse it and cd there before doing any relative-path reads (state.md,
# .claude/local/forge-goal-last-fingerprint) or git operations (which are
# also CWD-sensitive — wrong CWD → wrong branch, wrong merge-base).
#
# Fallback chain: stdin cwd → $(git rev-parse --show-toplevel) → current cwd.
# ---------------------------------------------------------------------------
INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null || true)
fi
HOOK_CWD=""
if [ -n "$INPUT" ]; then
    if command -v jq >/dev/null 2>&1; then
        HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
    else
        # Grep fallback when jq is unavailable. Match `"cwd":"..."` allowing
        # whitespace and stopping at the closing quote.
        HOOK_CWD=$(printf '%s' "$INPUT" \
            | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | head -1 \
            | sed -E 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)
    fi
fi
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    # Normalize to repo/worktree root in case stdin.cwd points at a subdirectory
    # (e.g., CC was launched from apps/web). Without this, relative paths like
    # .claude/local/state.md and tests/e2e/reports would silently miss.
    NORMALIZED=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$NORMALIZED" ] && [ -d "$NORMALIZED" ]; then
        cd "$NORMALIZED" 2>/dev/null || true
    else
        cd "$HOOK_CWD" 2>/dev/null || true
    fi
elif TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$TOPLEVEL" ]; then
    cd "$TOPLEVEL" 2>/dev/null || true
fi

STATE_MD=".claude/local/state.md"

# ---------------------------------------------------------------------------
# Git state queries (read-only, best-effort — failures produce empty strings)
# ---------------------------------------------------------------------------
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
TREE_SHA=$(git rev-parse HEAD^{tree} 2>/dev/null || echo "")
DIRTY="false"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then DIRTY="true"; fi

BRANCH_OFF=$(git merge-base HEAD main 2>/dev/null \
             || git merge-base HEAD master 2>/dev/null \
             || echo "")

# If HEAD itself IS the branch-off point (user is on main/master directly,
# not a feature branch), there is no meaningful "produced on this branch"
# comparison. Force the skip path so E2E freshness is not wrongly evaluated.
# Mirrors check-workflow-gates.sh lines 139-142 exactly.
if [ -n "$BRANCH_OFF" ] && [ -n "$HEAD_SHA" ] && [ "$BRANCH_OFF" = "$HEAD_SHA" ]; then
    BRANCH_OFF=""
fi

BRANCH_OFF_TS=""
if [ -n "$BRANCH_OFF" ]; then
    BRANCH_OFF_TS=$(git log -1 --format=%ct "$BRANCH_OFF" 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# gh pr view — best-effort; skipped silently if gh not installed or no PR
# ---------------------------------------------------------------------------
PR_EXISTS="false"
PR_NUMBER="null"
PR_URL=""
PR_STATE_VAL=""
PR_HEAD_OID=""
PR_BASE_REF=""
PR_HEAD_REF=""

if command -v gh >/dev/null 2>&1; then
    PR_JSON=$(gh pr view --json number,url,state,headRefOid,baseRefName,headRefName 2>/dev/null || echo "")
    if [ -n "$PR_JSON" ]; then
        PR_EXISTS="true"
        # jq-free field extraction using grep + sed (no extra deps)
        PR_NUMBER=$(echo "$PR_JSON" | grep -o '"number":[0-9]*' | sed 's/.*://')
        PR_URL=$(echo "$PR_JSON" | grep -o '"url":"[^"]*"' | sed 's/.*"url":"//;s/"$//')
        PR_STATE_VAL=$(echo "$PR_JSON" | grep -o '"state":"[^"]*"' | sed 's/.*"state":"//;s/"$//')
        PR_HEAD_OID=$(echo "$PR_JSON" | grep -o '"headRefOid":"[^"]*"' | sed 's/.*"headRefOid":"//;s/"$//')
        PR_BASE_REF=$(echo "$PR_JSON" | grep -o '"baseRefName":"[^"]*"' | sed 's/.*"baseRefName":"//;s/"$//')
        PR_HEAD_REF=$(echo "$PR_JSON" | grep -o '"headRefName":"[^"]*"' | sed 's/.*"headRefName":"//;s/"$//')
        # Guard: empty PR_NUMBER means parsing failed — fall back to null
        [ -z "$PR_NUMBER" ] && PR_NUMBER="null"
    fi
fi

# ---------------------------------------------------------------------------
# E2E report freshness — mirrors the mtime logic in check-workflow-gates.sh
# ---------------------------------------------------------------------------
E2E_PRESENT="false"
E2E_FRESH="false"
E2E_PATH=""
E2E_MTIME=""

if [ -d "tests/e2e/reports" ]; then
    # stat format: GNU uses -c %Y; BSD uses -f %m
    if stat -c %Y /dev/null >/dev/null 2>&1; then
        STAT_CMD='stat -c %Y'
    else
        STAT_CMD='stat -f %m'
    fi

    NEWEST_PATH=""
    NEWEST_MTIME=0
    for r in tests/e2e/reports/*.md; do
        [ -f "$r" ] || continue
        m=$($STAT_CMD "$r" 2>/dev/null || echo 0)
        if [ "$m" -gt "$NEWEST_MTIME" ]; then
            NEWEST_MTIME="$m"
            NEWEST_PATH="$r"
        fi
    done

    if [ -n "$NEWEST_PATH" ]; then
        E2E_PRESENT="true"
        E2E_PATH="$NEWEST_PATH"
        E2E_MTIME="$NEWEST_MTIME"
        if [ -n "$BRANCH_OFF_TS" ] && [ "$NEWEST_MTIME" -gt "$BRANCH_OFF_TS" ]; then
            E2E_FRESH="true"
        fi
    fi
fi

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

    # CRLF normalize BEFORE awk anchors (Codex P1.7 from plan-review).
    tr -d '\r' < "$STATE_MD" | awk '
        BEGIN { phase=""; next_step=""; total=0; done=0; in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }
        # Markdown table: |  Phase  | <value> |
        in_workflow && /\|[[:space:]]*Phase[[:space:]]*\|/ {
            split($0,a,"|"); phase=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",phase)
        }
        in_workflow && /\|[[:space:]]*Next step[[:space:]]*\|/ {
            split($0,a,"|"); next_step=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",next_step)
        }
        in_workflow && in_checklist && /^- \[x\]/ { done++; total++ }
        in_workflow && in_checklist && /^- \[ \]/ { total++ }
        END {
            print "PHASE|" phase
            print "NEXT|" next_step
            print "TOTAL|" total
            print "DONE|" done
        }
    '
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
    # CRLF normalize BEFORE awk anchors (Codex P1.7 from plan-review).
    matched=$(tr -d '\r' < "$STATE_MD" | awk -v head="$head_sha" '
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
    ')

    if [ -n "$matched" ]; then
        echo "true|${matched}|${head_sha}"
    else
        echo "false||"
    fi
}

compute_plan_review_gate() {
    # Output: "clean_same_iteration|matched_iteration|matched_plan_sha"
    # Canonical clean-line stem (referenced by tests/template/test-contracts.sh
    # parity check): Plan review iteration N — codex clean — plan=`<path>` — plan_sha=`<sha>`
    # Canonical code stem: Code review iteration N — codex clean — head=`<sha>`
    # Scope extraction to ## Workflow / ### Checklist (mirror compute_reviewer_gate
    # scoping above). A whole-file grep would pick up stray "Plan review iteration"
    # lines in migrated content or in docs/CHANGELOG.md excerpts pasted into state.md.
    [ -f "$STATE_MD" ] || { echo "false||"; return 0; }

    local checklist
    checklist=$(tr -d '\r' < "$STATE_MD" | awk '
        BEGIN { in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }
        in_workflow && in_checklist { print }
    ')

    # Find the LAST [x] Plan review loop (N iterations) — PASS line within scope
    local pass_line
    pass_line=$(echo "$checklist" \
        | grep -E '^\s*-\s*\[x\]\s+Plan review loop \([0-9]+ iterations\) — PASS' \
        | tail -1)
    [ -z "$pass_line" ] && { echo "false||"; return 0; }

    local n
    n=$(echo "$pass_line" | sed -E 's/.*Plan review loop \(([0-9]+) iterations\).*/\1/')
    [ -z "$n" ] && { echo "false||"; return 0; }

    # Find matching per-iter clean line for iteration n (scoped lookup)
    local clean_line
    clean_line=$(echo "$checklist" \
        | grep -E "^\s*-\s*\[x\]\s+Plan review iteration $n — " \
        | tail -1)
    [ -z "$clean_line" ] && { echo "false||"; return 0; }

    # Match codex clean variant + verify plan_sha (read from file, hash, compare)
    if echo "$clean_line" | grep -q "codex clean"; then
        local plan_path claimed_sha actual_sha
        plan_path=$(echo "$clean_line" | sed -E 's/.*plan=`([^`]+)`.*/\1/')
        claimed_sha=$(echo "$clean_line" | sed -E 's/.*plan_sha=`([^`]+)`.*/\1/')
        { [ -z "$plan_path" ] || [ -z "$claimed_sha" ]; } && { echo "false||"; return 0; }
        [ ! -f "$plan_path" ] && { echo "false||"; return 0; }
        if command -v shasum >/dev/null 2>&1; then
            actual_sha=$(shasum -a 256 "$plan_path" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            actual_sha=$(sha256sum "$plan_path" | awk '{print $1}')
        else
            echo "false||"; return 0
        fi
        # Lowercase both sides before compare (matches Task 3/7 hash casing).
        actual_sha=$(echo "$actual_sha" | tr 'A-Z' 'a-z')
        claimed_sha=$(echo "$claimed_sha" | tr 'A-Z' 'a-z')
        if [ "$actual_sha" = "$claimed_sha" ]; then
            echo "true|$n|$actual_sha"
        else
            echo "false|$n|$claimed_sha"
        fi
    elif echo "$clean_line" | grep -q "codex unavailable, council-confirmed"; then
        # council escape accepted; no plan_sha to bind to
        echo "true|$n|"
    else
        # Other variants (user-confirmed) don't propagate into FORGE_GOAL_EVIDENCE
        # because /goal autonomous mode forbids user-confirmed (see workflow.md).
        echo "false||"
    fi
}

parse_pr_authorization() {
    # Echo "authorized_bool|authorized_at|head_sha_at_auth|nonce_at_auth" or "false|||" if
    # section missing, HEAD_SHA empty, or GOAL_NONCE empty.
    # Section format (single line, one per state.md):
    #   - [x] PR creation authorized — `<timestamp>` — nonce=`<nonce>` — head=`<sha>`
    # Return authorized=true ONLY if extracted nonce matches GOAL_NONCE AND
    # extracted head matches HEAD_SHA. Otherwise authorized=false (but emit values for debugging).

    [ -f "$STATE_MD" ] || { echo "false|||"; return 0; }
    [ -z "$HEAD_SHA" ] && { echo "false|||"; return 0; }
    [ -z "$GOAL_NONCE" ] && { echo "false|||"; return 0; }

    # CRLF normalize BEFORE grep anchors (Codex P1.7 fix).
    local line
    line=$(tr -d '\r' < "$STATE_MD" \
           | grep -E '^-[[:space:]]*\[x\][[:space:]]+PR creation authorized' \
           | head -1)

    if [ -z "$line" ]; then
        echo "false|||"
        return 0
    fi

    # Extract timestamp, nonce, and head from the line via Bash regex.
    # Pattern: - [x] PR creation authorized — `<timestamp>` — nonce=`<nonce>` — head=`<sha>`
    if [[ "$line" =~ \[x\][[:space:]]+PR\ creation\ authorized\ +—\ +\`([^\`]+)\`\ +—\ +nonce=\`([^\`]+)\`\ +—\ +head=\`([^\`]+)\` ]]; then
        local at="${BASH_REMATCH[1]}"
        local nonce="${BASH_REMATCH[2]}"
        local head="${BASH_REMATCH[3]}"

        if [ "$nonce" = "$GOAL_NONCE" ] && [ "$head" = "$HEAD_SHA" ]; then
            echo "true|${at}|${head}|${nonce}"
        else
            echo "false|${at}|${head}|${nonce}"
        fi
    else
        echo "false|||"
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
# HEAD_SHA is already set above in the git-state block; reuse it.
RG_RESULT=$(compute_reviewer_gate "$HEAD_SHA")
RG_CLEAN="${RG_RESULT%%|*}"
RG_REST="${RG_RESULT#*|}"
RG_ITER="${RG_REST%%|*}"
RG_HEAD="${RG_REST##*|}"

# Parse plan-review gate (plan-review iteration rows in Checklist; plan_sha bound).
PRG_RESULT=$(compute_plan_review_gate)
PRG_CLEAN="${PRG_RESULT%%|*}"
PRG_REST="${PRG_RESULT#*|}"
PRG_ITER="${PRG_REST%%|*}"
PRG_SHA="${PRG_REST##*|}"

# Parse ## PR authorization section.
PA_PARSED=$(parse_pr_authorization)
PA_AUTH="${PA_PARSED%%|*}"
PA_REST="${PA_PARSED#*|}"
PA_AT="${PA_REST%%|*}"
PA_REST2="${PA_REST#*|}"
PA_HEAD="${PA_REST2%%|*}"
PA_NONCE="${PA_REST2#*|}"

# Build JSON-safe field values for string fields that need escaping/null handling.
PHASE_JSON=$(json_str_field "phase" "$PHASE")
NEXT_STEP_JSON=$(json_str_field "next_step" "$NEXT_STEP")
RG_ITER_JSON=$(json_str_field "matched_iteration" "$RG_ITER")
RG_HEAD_JSON=$(json_str_field "matched_head" "$RG_HEAD")
PRG_ITER_JSON=$(json_str_field "matched_iteration" "$PRG_ITER")
PRG_SHA_JSON=$(json_str_field "matched_plan_sha" "$PRG_SHA")
PA_AT_JSON=$(json_str_field "authorized_at" "$PA_AT")
PA_HEAD_JSON=$(json_str_field "head_sha_at_authorization" "$PA_HEAD")
PA_NONCE_JSON=$(json_str_field "nonce_at_authorization" "$PA_NONCE")

# ---------------------------------------------------------------------------
# Task 7: Derived fields — pr_ready, all_gates_green, progress_fingerprint
# ---------------------------------------------------------------------------

# pr_ready: PR open AND PR head matches HEAD_SHA AND reviewer gate clean
#           AND E2E fresh AND PR auth accepted.
PR_OPEN="false"
[ "$PR_STATE_VAL" = "OPEN" ] && PR_OPEN="true"

PR_HEAD_MATCH="false"
[ -n "$HEAD_SHA" ] && [ "$PR_HEAD_OID" = "$HEAD_SHA" ] && PR_HEAD_MATCH="true"

PR_READY="false"
if [ "$PR_OPEN" = "true" ] && [ "$PR_HEAD_MATCH" = "true" ] && \
   [ "$RG_CLEAN" = "true" ] && [ "$E2E_FRESH" = "true" ] && \
   [ "$PA_AUTH" = "true" ]; then
    PR_READY="true"
fi

# all_gates_green: every checklist item checked (DONE == TOTAL > 0) AND pr_ready=true.
# Guard against TOTAL=0 to avoid a false positive on empty checklists.
ALL_GATES="false"
if [ "$DONE_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ] && \
   [ "$PR_READY" = "true" ]; then
    ALL_GATES="true"
fi

# progress_fingerprint: deterministic SHA256 of a SCOPED, ORDER-PRESERVING subset.
#
# Design notes (from plan Task 7):
#   1. CRLF normalize BEFORE awk — anchors like /^## Workflow$/ must match even
#      on Windows-edited files. (Codex P1.7 fix — tr-then-awk, not awk-then-tr)
#   2. Scope to ## Workflow / ### Checklist only — stray rows outside the section
#      must NOT pollute the hash.
#   3. Preserve document ORDER — sorting would hide checklist reordering changes.
#   4. Use ASCII Unit Separator (0x1f) as delimiter — never appears in Markdown.
#   5. Include PR authorization line (whole-file OK — there's only ever one).
DELIM=$'\x1f'  # ASCII Unit Separator
FP_TMP="${TMPDIR:-/tmp}/fp.input.$$"
trap 'rm -f "$FP_TMP"' EXIT
{
    printf '%s%s' "$PHASE" "$DELIM"
    printf '%s%s' "$NEXT_STEP" "$DELIM"
    # CRLF normalize FIRST, then Workflow-scoped awk to extract checklist rows
    # in document order.
    tr -d '\r' < "$STATE_MD" 2>/dev/null | awk '
        /^## Workflow$/ { in_w=1; next }
        in_w && /^## / { in_w=0; in_c=0 }
        in_w && /^### Checklist/ { in_c=1; next }
        in_w && /^### / && !/^### Checklist/ { in_c=0 }
        in_w && in_c && /^- \[[ x]\]/ { print }
    ' | tr '\n' "$DELIM"
    # PR authorization line (whole-file OK — singleton). CRLF normalize BEFORE grep.
    tr -d '\r' < "$STATE_MD" 2>/dev/null \
        | grep -E '^- \[[xX]\][[:space:]]+PR creation authorized' \
        | head -1
} > "$FP_TMP" 2>/dev/null

if command -v sha256sum >/dev/null 2>&1; then
    PROGRESS_FP=$(sha256sum "$FP_TMP" 2>/dev/null | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    PROGRESS_FP=$(shasum -a 256 "$FP_TMP" 2>/dev/null | awk '{print $1}')
else
    PROGRESS_FP=""
fi
rm -f "$FP_TMP"

# Side-channel: write fingerprint to .claude/local/forge-goal-last-fingerprint so
# the stuck-detection logic in check-state-updated.sh can read it without
# re-running build-evidence or parsing STDERR. One line — just the SHA256 value.
# Best-effort: failure here must not abort the evidence emission.
FINGERPRINT_SIDECHANNEL=".claude/local/forge-goal-last-fingerprint"
if [ -n "$PROGRESS_FP" ]; then
    mkdir -p ".claude/local" 2>/dev/null || true
    printf '%s\n' "$PROGRESS_FP" > "$FINGERPRINT_SIDECHANNEL" 2>/dev/null || true
fi

# Task 5: git + PR + E2E field strings
BRANCH_JSON=$(json_str_field "branch" "$BRANCH")
HEAD_SHA_JSON=$(json_str_field "head_sha" "$HEAD_SHA")
TREE_SHA_JSON=$(json_str_field "tree_sha" "$TREE_SHA")
BRANCH_OFF_JSON=$(json_str_field "branch_off_commit" "$BRANCH_OFF")
PR_URL_JSON=$(json_str_field "url" "$PR_URL")
PR_STATE_JSON=$(json_str_field "state" "$PR_STATE_VAL")
PR_HEAD_OID_JSON=$(json_str_field "head_oid" "$PR_HEAD_OID")
PR_BASE_REF_JSON=$(json_str_field "base_ref" "$PR_BASE_REF")
PR_HEAD_REF_JSON=$(json_str_field "head_ref" "$PR_HEAD_REF")
E2E_PATH_JSON=$(json_str_field "path" "$E2E_PATH")

# Emit evidence JSON.
{
    echo "FORGE_GOAL_EVIDENCE_BEGIN"
    printf '{'
    printf '"type":"forge_goal_evidence",'
    printf '"schema_version":1,'
    printf '"produced_at_unix":%d,' "$NOW_UNIX"
    printf '%s,' "$SESSION_NONCE_JSON"
    printf '%s,' "$WORKFLOW_CMD_JSON"
    printf '"state":{%s,%s,"checklist_total":%d,"checklist_done":%d},' \
        "$PHASE_JSON" "$NEXT_STEP_JSON" "$TOTAL_COUNT" "$DONE_COUNT"
    printf '"reviewer_gate":{"clean_same_iteration":%s,%s,%s},' \
        "$RG_CLEAN" "$RG_ITER_JSON" "$RG_HEAD_JSON"
    printf '"plan_review_gate":{"clean_same_iteration":%s,%s,%s},' \
        "$PRG_CLEAN" "$PRG_ITER_JSON" "$PRG_SHA_JSON"
    printf '%s,' "$BRANCH_JSON"
    printf '%s,' "$HEAD_SHA_JSON"
    printf '%s,' "$TREE_SHA_JSON"
    printf '%s,' "$BRANCH_OFF_JSON"
    printf '"working_tree_dirty":%s,' "$DIRTY"
    if [ "$PR_EXISTS" = "true" ]; then
        printf '"pr_state":{"exists":true,"number":%s,%s,%s,%s,%s,%s},' \
            "$PR_NUMBER" "$PR_URL_JSON" "$PR_STATE_JSON" "$PR_HEAD_OID_JSON" \
            "$PR_BASE_REF_JSON" "$PR_HEAD_REF_JSON"
    else
        printf '"pr_state":{"exists":false,"number":null,"url":null,"state":null,"head_oid":null,"base_ref":null,"head_ref":null},'
    fi
    if [ "$E2E_PRESENT" = "true" ]; then
        printf '"e2e_report":{"present":true,%s,"mtime_unix":%d,"fresh_for_head":%s},' \
            "$E2E_PATH_JSON" "$E2E_MTIME" "$E2E_FRESH"
    else
        printf '"e2e_report":{"present":false,"path":null,"mtime_unix":null,"fresh_for_head":false},'
    fi
    printf '"pr_authorization":{"authorized":%s,%s,%s,%s},' \
        "$PA_AUTH" "$PA_AT_JSON" "$PA_HEAD_JSON" "$PA_NONCE_JSON"
    printf '"pr_ready":%s,' "$PR_READY"
    printf '"all_gates_green":%s,' "$ALL_GATES"
    printf '"progress_fingerprint":"%s",' "$PROGRESS_FP"
    printf '"warnings":[],'
    printf '"errors":[]'
    printf '}\n'
    echo "FORGE_GOAL_EVIDENCE_END"
} >&2

exit 0
