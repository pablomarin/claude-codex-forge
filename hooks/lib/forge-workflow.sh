#!/usr/bin/env bash
# hooks/lib/forge-workflow.sh — Forge runtime workflow controller.
#
# Durable local state for deterministic workflow gates. v1 intentionally only
# enforces the Phase 3 -> Phase 4 implementation handoff seam.

set -u

STATE_FILE=".claude/local/workflow-run.json"
EVENTS_FILE=".claude/local/workflow-events.jsonl"
GATE_PHASE_3_4="phase-3-4"
ALLOWED_MODES="same-context compact fresh-session"

_now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

_json_escape() {
    # Constrained JSON string escaping for paths/reasons we write ourselves.
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_repo_root_from_cwd() {
    local cwd="${1:-}"
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
        cd "$cwd" 2>/dev/null || true
    fi
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$top" ] && [ -d "$top" ]; then
        cd "$top" 2>/dev/null || true
    fi
}

_read_stdin() {
    if [ ! -t 0 ]; then
        cat 2>/dev/null || true
    fi
}

_json_get() {
    # _json_get <json> <jq-expr> <fallback-key>
    local json="$1" jq_expr="$2" fallback_key="$3"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r "$jq_expr // empty" 2>/dev/null || true
        return
    fi
    printf '%s' "$json" \
        | sed -nE "s/.*\"$fallback_key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" \
        | head -1
}

_parse_stdin_field() {
    # _parse_stdin_field <json> <jq-expr> <fallback-key>
    _json_get "$1" "$2" "$3"
}

_current_workflow_command() {
    local state_md=".claude/local/state.md"
    [ -f "$state_md" ] || { printf 'unknown'; return; }
    tr -d '\r' < "$state_md" 2>/dev/null \
        | awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag' \
        | grep -iE '\|[[:space:]]*Command[[:space:]]*\|' \
        | head -1 | awk -F'|' '{print $3}' | xargs 2>/dev/null || printf 'unknown'
}

_gate_status() {
    local gate="$1"
    [ -f "$STATE_FILE" ] || return 0
    local raw
    raw=$(cat "$STATE_FILE" 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -r --arg gate "$gate" '.gates[$gate].status // empty' 2>/dev/null || true
    else
        # State is written as compact one-line JSON by this controller.
        printf '%s' "$raw" | sed -nE "s/.*\"$gate\"[[:space:]]*:[[:space:]]*\{[^}]*\"status\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p"
    fi
}

_state_plan_file() {
    [ -f "$STATE_FILE" ] || return 0
    local raw
    raw=$(cat "$STATE_FILE" 2>/dev/null || true)
    _json_get "$raw" '.plan_file' 'plan_file'
}

_state_selected_mode() {
    local gate="$1"
    [ -f "$STATE_FILE" ] || return 0
    local raw
    raw=$(cat "$STATE_FILE" 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -r --arg gate "$gate" '.gates[$gate].selected_mode // empty' 2>/dev/null || true
    else
        printf '%s' "$raw" | sed -nE "s/.*\"$gate\"[[:space:]]*:[[:space:]]*\{[^}]*\"selected_mode\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p"
    fi
}

_append_event() {
    local event="$1" gate="$2" plan="$3" mode="${4:-}"
    mkdir -p .claude/local
    local ts event_e gate_e plan_e mode_e
    ts=$(_now_utc)
    event_e=$(_json_escape "$event")
    gate_e=$(_json_escape "$gate")
    plan_e=$(_json_escape "$plan")
    if [ -n "$mode" ]; then
        mode_e=$(_json_escape "$mode")
        printf '{"ts":"%s","event":"%s","gate":"%s","plan_file":"%s","mode":"%s"}\n' \
            "$ts" "$event_e" "$gate_e" "$plan_e" "$mode_e" >> "$EVENTS_FILE"
    else
        printf '{"ts":"%s","event":"%s","gate":"%s","plan_file":"%s"}\n' \
            "$ts" "$event_e" "$gate_e" "$plan_e" >> "$EVENTS_FILE"
    fi
}

_write_state() {
    local workflow="$1" phase="$2" next_step="$3" plan="$4" gate="$5" status="$6" opened_at="$7" selected_mode="$8" approved_at="$9"
    mkdir -p .claude/local
    local workflow_e phase_e next_e plan_e gate_e opened_e mode_json approved_json
    workflow_e=$(_json_escape "$workflow")
    phase_e=$(_json_escape "$phase")
    next_e=$(_json_escape "$next_step")
    plan_e=$(_json_escape "$plan")
    gate_e=$(_json_escape "$gate")
    opened_e=$(_json_escape "$opened_at")
    if [ -n "$selected_mode" ]; then
        mode_json="\"$(_json_escape "$selected_mode")\""
    else
        mode_json="null"
    fi
    if [ -n "$approved_at" ]; then
        approved_json="\"$(_json_escape "$approved_at")\""
    else
        approved_json="null"
    fi
    printf '{"version":1,"workflow":"%s","phase":"%s","next_step":"%s","plan_file":"%s","gates":{"%s":{"status":"%s","opened_at":"%s","reason":"Implementation Handoff complete; choose same-context, compact, or fresh-session before implementation.","allowed_modes":["same-context","compact","fresh-session"],"selected_mode":%s,"approved_at":%s}}}\n' \
        "$workflow_e" "$phase_e" "$next_e" "$plan_e" "$gate_e" "$status" "$opened_e" "$mode_json" "$approved_json" > "$STATE_FILE"
}

_open_gate() {
    local gate="${1:-}" plan=""
    shift || true
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --plan) plan="${2:-}"; shift 2 ;;
            *) echo "forge-workflow: unknown open-gate argument: $1" >&2; return 2 ;;
        esac
    done
    if [ "$gate" != "$GATE_PHASE_3_4" ]; then
        echo "forge-workflow: unsupported gate: $gate" >&2
        return 2
    fi
    if [ -z "$plan" ]; then
        echo "forge-workflow: open-gate requires --plan <path>" >&2
        return 2
    fi

    local existing_status existing_plan
    existing_status=$(_gate_status "$gate")
    existing_plan=$(_state_plan_file)
    if [ "$existing_status" = "pending" ] && [ "$existing_plan" = "$plan" ]; then
        echo "Gate already pending: $gate ($plan)"
        return 0
    fi
    if [ "$existing_status" = "approved" ] && [ "$existing_plan" = "$plan" ]; then
        echo "Gate already approved: $gate ($plan)"
        return 0
    fi

    local opened workflow
    opened=$(_now_utc)
    workflow=$(_current_workflow_command)
    _write_state "$workflow" "3 — Design" "Implementation Handoff" "$plan" "$gate" "pending" "$opened" "" ""
    _append_event "gate_opened" "$gate" "$plan"
    echo "Gate opened: $gate ($plan)"
}

_valid_mode() {
    case " $ALLOWED_MODES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

_approve_gate() {
    local gate="${1:-}" mode=""
    shift || true
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode) mode="${2:-}"; shift 2 ;;
            *) echo "forge-workflow: unknown approve-gate argument: $1" >&2; return 2 ;;
        esac
    done
    if [ "$gate" != "$GATE_PHASE_3_4" ]; then
        echo "forge-workflow: unsupported gate: $gate" >&2
        return 2
    fi
    if ! _valid_mode "$mode"; then
        echo "forge-workflow: invalid mode '$mode' (expected: same-context|compact|fresh-session)" >&2
        return 2
    fi
    [ -f "$STATE_FILE" ] || { echo "forge-workflow: no workflow run state to approve" >&2; return 2; }

    local status plan selected opened workflow
    status=$(_gate_status "$gate")
    plan=$(_state_plan_file)
    selected=$(_state_selected_mode "$gate")
    if [ "$status" = "approved" ] && [ "$selected" = "$mode" ]; then
        echo "Gate already approved: $gate ($mode)"
        return 0
    fi
    if [ "$status" != "pending" ]; then
        echo "forge-workflow: gate '$gate' is not pending (status: ${status:-missing})" >&2
        return 2
    fi
    opened=$(_json_get "$(cat "$STATE_FILE" 2>/dev/null || true)" ".gates[\"$gate\"].opened_at" 'opened_at')
    [ -n "$opened" ] || opened=$(_now_utc)
    workflow=$(_json_get "$(cat "$STATE_FILE" 2>/dev/null || true)" '.workflow' 'workflow')
    [ -n "$workflow" ] || workflow=$(_current_workflow_command)

    _write_state "$workflow" "4 — Execute" "Implementation may start" "$plan" "$gate" "approved" "$opened" "$mode" "$(_now_utc)"
    _append_event "gate_approved" "$gate" "$plan" "$mode"
    echo "Gate approved: $gate ($mode)"
}

_status() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "NO_WORKFLOW_RUN"
    fi
}

_pending_gate() {
    local status
    status=$(_gate_status "$GATE_PHASE_3_4")
    [ "$status" = "pending" ] && printf '%s' "$GATE_PHASE_3_4"
}

_is_local_state_path() {
    local path="$1" root
    [ -n "$path" ] || return 1
    root=$(pwd)
    case "$path" in
        .claude/local/*|./.claude/local/*) return 0 ;;
        "$root"/.claude/local/*) return 0 ;;
        *) return 1 ;;
    esac
}

_is_allowed_bash_while_pending() {
    local command="$1"
    # Gate-control commands must remain possible while the gate is pending.
    if printf '%s' "$command" | grep -Eq '^[[:space:]]*(\./)?\.claude/hooks/lib/forge-workflow\.sh[[:space:]]+(status|approve-gate|open-gate)\b'; then
        return 0
    fi
    # Keep the read/status allowlist single-command only. A chained command like
    # `git status && pytest` or a redirect like `git diff > patch` must not ride
    # through the gate just because the first token is read-only.
    if printf '%s' "$command" | grep -Eq '[;&|<>]'; then
        return 1
    fi
    case "$command" in
        find\ *-delete*|find\ *-exec*|find\ *-ok*) return 1 ;;
    esac
    # Read/status-only commands. Anything that executes tests/apps/package scripts
    # or mutates the tree intentionally falls through to the block.
    case "$command" in
        pwd|pwd\ *|ls|ls\ *|find\ *|rg\ *|grep\ *|wc\ *|head\ *|tail\ *|cat\ *|date|date\ *|uuidgen|uuidgen\ *|shasum\ *|sha256sum\ *) return 0 ;;
        git\ status|git\ status\ *|git\ diff|git\ diff\ *|git\ show\ *|git\ log|git\ log\ *|git\ rev-parse\ *|git\ branch|git\ branch\ *) return 0 ;;
        command\ -v\ *|test\ *|\[*\]) return 0 ;;
        sed\ -n\ *) return 0 ;;
    esac
    return 1
}

_block_message() {
    local gate="$1"
    cat >&2 <<EOF
PHASE_GATE_PENDING: $gate
Implementation Handoff is complete. Choose how to cross the Phase 3→4 seam:
- same-context: approve and continue in this session
- compact: run /compact, then approve
- fresh-session: start a new session in the worktree and approve there
Allowed command: .claude/hooks/lib/forge-workflow.sh approve-gate $gate --mode <mode>
EOF
}

_check_tool() {
    local input cwd tool command file_path gate
    input=$(_read_stdin)
    cwd=$(_parse_stdin_field "$input" '.cwd' 'cwd')
    _repo_root_from_cwd "$cwd"

    gate=$(_pending_gate)
    [ -z "$gate" ] && return 0

    tool=$(_parse_stdin_field "$input" '.tool_name' 'tool_name')
    command=$(_parse_stdin_field "$input" '.tool_input.command' 'command')
    file_path=$(_parse_stdin_field "$input" '.tool_input.file_path' 'file_path')
    [ -z "$tool" ] && [ -n "$command" ] && tool="Bash"

    case "$tool" in
        Bash)
            if _is_allowed_bash_while_pending "$command"; then
                return 0
            fi
            _block_message "$gate"
            return 2
            ;;
        Edit|Write|MultiEdit|NotebookEdit)
            if _is_local_state_path "$file_path"; then
                return 0
            fi
            _block_message "$gate"
            return 2
            ;;
        *)
            return 0
            ;;
    esac
}

_usage() {
    cat <<'EOF'
Usage: forge-workflow <command>

Commands:
  status
  open-gate phase-3-4 --plan <plan-file>
  approve-gate phase-3-4 --mode same-context|compact|fresh-session
  check-tool
EOF
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        status) _status ;;
        open-gate) shift; _open_gate "$@" ;;
        approve-gate) shift; _approve_gate "$@" ;;
        check-tool) _check_tool ;;
        -h|--help|help|"") _usage ;;
        *) echo "forge-workflow: unknown command: $cmd" >&2; _usage >&2; return 2 ;;
    esac
}

main "$@"
