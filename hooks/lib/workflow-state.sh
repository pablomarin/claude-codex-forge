#!/usr/bin/env bash
# Bounded cross-engine workflow state transitions. Bash 3.2 compatible.

set -u

WORKFLOW_STATE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=state-path.sh
source "$WORKFLOW_STATE_DIR/state-path.sh"

workflow_state_die() {
    echo "BLOCKED: $*" >&2
    return 2
}

workflow_state_hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

workflow_state_root() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    (cd "$root" 2>/dev/null && pwd -P)
}

workflow_state_canonical() {
    local root="$1" state
    state=$(forge_state_path "$root" read) || return 1
    [ "$state" = "$root/.forge/local/state.md" ] || {
        echo "BLOCKED: workflow-state supports canonical Forge V6 state only" >&2
        return 1
    }
    workflow_state_validate_shape "$state" || return 1
    printf '%s\n' "$state"
}

workflow_state_value() {
    local path="$1" wanted_section="$2" wanted_key="$3"
    awk -F '|' -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        /^## / {
            section=$0
            sub(/^## /, "", section)
            next
        }
        section == wanted_section && /^\|/ {
            key=trim($2)
            if (key == wanted_key) {
                count++
                value=trim($3)
            }
        }
        END {
            if (count != 1) exit 1
            print value
        }
    ' "$path"
}

workflow_state_validate_shape() {
    local path="$1" item section key
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    forge_state_v6_valid "$path" || return 1
    for item in \
        'Identity:Worktree root' \
        'Identity:Git common directory' \
        'Identity:Last active host' \
        'Identity:Workflow base ref' \
        'Identity:Workflow base SHA' \
        'Workflow:Command' \
        'Workflow:Phase' \
        'Workflow:Next step' \
        'Receipts:Review iteration' \
        'Receipts:Candidate receipt' \
        'Receipts:Spec review receipt' \
        'Receipts:Quality review receipt' \
        'Receipts:Verify app receipt' \
        'Receipts:E2E receipt' \
        'Receipts:Promotion receipt' \
        'Receipts:Council receipt'; do
        section=${item%%:*}
        key=${item#*:}
        workflow_state_value "$path" "$section" "$key" >/dev/null || return 1
    done
}

workflow_state_validate_cell() {
    local label="$1" value="$2" trimmed
    [ -n "$value" ] || {
        workflow_state_die "$label must not be empty"
        return $?
    }
    case "$value" in
        *'|'*|*$'\r'*|*$'\n'*)
            workflow_state_die "$label must be one Markdown-safe line"
            return $?
            ;;
    esac
    trimmed=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ "$trimmed" = "$value" ] || {
        workflow_state_die "$label must not have outer whitespace"
        return $?
    }
}

workflow_state_validate_task() {
    local task="$1"
    [ ${#task} -le 64 ] || {
        workflow_state_die "task slug is too long"
        return $?
    }
    printf '%s\n' "$task" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' || {
        workflow_state_die "invalid task slug: $task"
        return $?
    }
}

workflow_state_validate_ref() {
    local ref="$1"
    workflow_state_validate_cell "base ref" "$ref" || return $?
    case "$ref" in
        -*|*..*|*'@{'*|*'~'*|*'^'*|*':'*|*'?'*|*'*'*|*'['*|*'\'*)
            workflow_state_die "invalid base ref: $ref"
            return $?
            ;;
    esac
}

workflow_state_common_dir() {
    local root="$1" raw
    raw=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
    case "$raw" in
        /*) (cd "$raw" 2>/dev/null && pwd -P) ;;
        *) (cd "$root/$raw" 2>/dev/null && pwd -P) ;;
    esac
}

forge_workflow_state_publish() {
    local state="$1" next="$2" expected_hash="$3" actual_hash
    [ -f "$next" ] && [ ! -L "$next" ] || {
        workflow_state_die "invalid workflow-state temporary file"
        return $?
    }
    actual_hash=$(workflow_state_hash "$state") || return 2
    [ "$actual_hash" = "$expected_hash" ] || {
        workflow_state_die "workflow state changed concurrently; retry from show"
        return $?
    }
    mv "$next" "$state" || {
        workflow_state_die "could not publish workflow state"
        return $?
    }
}

workflow_state_transform_activate() {
    local state="$1" next="$2" mode="$3" root="$4" common="$5" host="$6"
    local base_ref="$7" base_sha="$8" command="$9"
    shift 9
    local phase="$1" next_step="$2" task="$3"
    awk -F '|' \
        -v mode="$mode" -v root="$root" -v common="$common" -v host="$host" \
        -v base_ref="$base_ref" -v base_sha="$base_sha" -v command="$command" \
        -v phase_value="$phase" -v next_value="$next_step" -v task="$task" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        /^## / {
            section=$0
            sub(/^## /, "", section)
        }
        section == "Identity" && /^\|/ {
            key=trim($2)
            if (key == "Last active host") { print "| Last active host     | " host " |"; next }
            if (mode == "new" && key == "Worktree root") { print "| Worktree root        | " root " |"; next }
            if (mode == "new" && key == "Git common directory") { print "| Git common directory | " common " |"; next }
            if (mode == "new" && key == "Workflow base ref") { print "| Workflow base ref    | " base_ref " |"; next }
            if (mode == "new" && key == "Workflow base SHA") { print "| Workflow base SHA    | " base_sha " |"; next }
        }
        mode == "new" && section == "Workflow" && /^\|/ {
            key=trim($2)
            if (key == "Command") { print "| Command   | " command " |"; next }
            if (key == "Phase") { print "| Phase     | " phase_value " |"; next }
            if (key == "Next step") { print "| Next step | " next_value " |"; next }
        }
        mode == "new" && section == "Receipts" && /^\|/ {
            key=trim($2)
            if (key == "Review iteration") { print "| Review iteration       | 0 |"; next }
            if (key == "Candidate receipt") { print "| Candidate receipt      | .forge/local/evidence/" task "/candidate.receipt |"; next }
            if (key == "Spec review receipt") { print "| Spec review receipt    | .forge/local/reviews/" task "/spec.receipt |"; next }
            if (key == "Quality review receipt") { print "| Quality review receipt | .forge/local/reviews/" task "/quality.receipt |"; next }
            if (key == "Verify app receipt") { print "| Verify app receipt     | .forge/local/evidence/" task "/verify-app.receipt |"; next }
            if (key == "E2E receipt") { print "| E2E receipt            | .forge/local/evidence/" task "/e2e.receipt |"; next }
            if (key == "Promotion receipt") { print "| Promotion receipt      | .forge/local/evidence/" task "/promotion.receipt |"; next }
        }
        { print }
    ' "$state" > "$next"
}

workflow_state_increment_decimal() {
    local value="$1" result="" carry=1 index digit next_digit
    index=$((${#value} - 1))
    while [ "$index" -ge 0 ]; do
        digit=${value:$index:1}
        if [ "$carry" -eq 1 ]; then
            next_digit=$((digit + 1))
            if [ "$next_digit" -eq 10 ]; then
                next_digit=0
            else
                carry=0
            fi
        else
            next_digit=$digit
        fi
        result="$next_digit$result"
        index=$((index - 1))
    done
    [ "$carry" -eq 0 ] || result="1$result"
    printf '%s\n' "$result"
}

workflow_state_transform_checkpoint() {
    local state="$1" next="$2" host="$3" phase="$4" next_step="$5" iteration="$6"
    awk -F '|' -v host="$host" -v phase_value="$phase" -v next_value="$next_step" \
        -v iteration="$iteration" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        /^## / {
            section=$0
            sub(/^## /, "", section)
        }
        section == "Identity" && /^\|/ && trim($2) == "Last active host" {
            print "| Last active host     | " host " |"
            next
        }
        section == "Workflow" && /^\|/ {
            key=trim($2)
            if (key == "Phase") { print "| Phase     | " phase_value " |"; next }
            if (key == "Next step") { print "| Next step | " next_value " |"; next }
        }
        section == "Receipts" && /^\|/ && trim($2) == "Review iteration" {
            print "| Review iteration       | " iteration " |"
            next
        }
        { print }
    ' "$state" > "$next"
}

workflow_state_show() {
    local root state
    root=$(workflow_state_root) || {
        workflow_state_die "not inside a Git worktree"
        return $?
    }
    state=$(workflow_state_canonical "$root") || return 2
    cat "$state"
}

workflow_state_activate() {
    local host="" workflow="" task="" base_ref="" phase="" next_step=""
    local seen_host=false seen_workflow=false seen_task=false seen_base=false seen_phase=false seen_next=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --host)
                [ "$seen_host" = false ] && [ $# -ge 2 ] || return 2
                host="$2"; seen_host=true; shift 2 ;;
            --workflow)
                [ "$seen_workflow" = false ] && [ $# -ge 2 ] || return 2
                workflow="$2"; seen_workflow=true; shift 2 ;;
            --task)
                [ "$seen_task" = false ] && [ $# -ge 2 ] || return 2
                task="$2"; seen_task=true; shift 2 ;;
            --base-ref)
                [ "$seen_base" = false ] && [ $# -ge 2 ] || return 2
                base_ref="$2"; seen_base=true; shift 2 ;;
            --phase)
                [ "$seen_phase" = false ] && [ $# -ge 2 ] || return 2
                phase="$2"; seen_phase=true; shift 2 ;;
            --next-step)
                [ "$seen_next" = false ] && [ $# -ge 2 ] || return 2
                next_step="$2"; seen_next=true; shift 2 ;;
            *) workflow_state_die "unsupported activate option: $1"; return $? ;;
        esac
    done
    [ "$seen_host" = true ] && [ "$seen_workflow" = true ] && [ "$seen_task" = true ] \
        && [ "$seen_base" = true ] && [ "$seen_phase" = true ] && [ "$seen_next" = true ] || {
        workflow_state_die "activate requires host, workflow, task, base-ref, phase, and next-step"
        return $?
    }
    case "$host" in claude|codex) ;; *) workflow_state_die "invalid host: $host"; return $? ;; esac
    case "$workflow" in new-feature|fix-bug|quick-fix) ;; *) workflow_state_die "invalid workflow: $workflow"; return $? ;; esac
    workflow_state_validate_task "$task" || return $?
    workflow_state_validate_ref "$base_ref" || return $?
    workflow_state_validate_cell "phase" "$phase" || return $?
    workflow_state_validate_cell "next step" "$next_step" || return $?

    local root common state base_sha state_hash current_command current_phase current_next
    local current_root current_common current_base_ref current_base_sha current_iteration command mode
    local expected_candidate expected_spec expected_quality expected_app expected_e2e expected_promotion
    local evidence_dir review_dir candidate tmp
    root=$(workflow_state_root) || { workflow_state_die "not inside a Git worktree"; return $?; }
    common=$(workflow_state_common_dir "$root") || { workflow_state_die "cannot resolve Git common directory"; return $?; }
    state=$(workflow_state_canonical "$root") || return 2
    base_sha=$(git -C "$root" rev-parse --verify "${base_ref}^{commit}" 2>/dev/null) || {
        workflow_state_die "base ref does not resolve to a commit: $base_ref"
        return $?
    }
    state_hash=$(workflow_state_hash "$state") || return 2
    current_command=$(workflow_state_value "$state" Workflow Command) || return 2
    current_phase=$(workflow_state_value "$state" Workflow Phase) || return 2
    current_next=$(workflow_state_value "$state" Workflow 'Next step') || return 2
    current_root=$(workflow_state_value "$state" Identity 'Worktree root') || return 2
    current_common=$(workflow_state_value "$state" Identity 'Git common directory') || return 2
    current_base_ref=$(workflow_state_value "$state" Identity 'Workflow base ref') || return 2
    current_base_sha=$(workflow_state_value "$state" Identity 'Workflow base SHA') || return 2
    current_iteration=$(workflow_state_value "$state" Receipts 'Review iteration') || return 2
    command="/$workflow $task"
    expected_candidate=".forge/local/evidence/$task/candidate.receipt"
    expected_spec=".forge/local/reviews/$task/spec.receipt"
    expected_quality=".forge/local/reviews/$task/quality.receipt"
    expected_app=".forge/local/evidence/$task/verify-app.receipt"
    expected_e2e=".forge/local/evidence/$task/e2e.receipt"
    expected_promotion=".forge/local/evidence/$task/promotion.receipt"

    mode=new
    if [ -n "$current_command" ] && [ "$current_command" != none ] \
        && ! { [ "$current_phase" = complete ] && [ "$current_next" = none ]; }; then
        [ "$current_command" = "$command" ] \
            && [ "$current_root" = "$root" ] \
            && [ "$current_common" = "$common" ] \
            && [ "$current_base_ref" = "$base_ref" ] \
            && [ "$current_base_sha" = "$base_sha" ] \
            && [ "$current_phase" = "$phase" ] \
            && [ "$current_next" = "$next_step" ] \
            && printf '%s\n' "$current_iteration" | grep -qE '^[0-9]+$' \
            && [ "$(workflow_state_value "$state" Receipts 'Candidate receipt')" = "$expected_candidate" ] \
            && [ "$(workflow_state_value "$state" Receipts 'Spec review receipt')" = "$expected_spec" ] \
            && [ "$(workflow_state_value "$state" Receipts 'Quality review receipt')" = "$expected_quality" ] \
            && [ "$(workflow_state_value "$state" Receipts 'Verify app receipt')" = "$expected_app" ] \
            && [ "$(workflow_state_value "$state" Receipts 'E2E receipt')" = "$expected_e2e" ] \
            && [ "$(workflow_state_value "$state" Receipts 'Promotion receipt')" = "$expected_promotion" ] || {
                workflow_state_die "a different or inconsistent workflow is already active"
                return $?
            }
        mode=resume
    fi

    evidence_dir="$root/.forge/local/evidence/$task"
    review_dir="$root/.forge/local/reviews/$task"
    for candidate in "$root/.forge/local/evidence" "$evidence_dir" "$root/.forge/local/reviews" "$review_dir"; do
        [ ! -L "$candidate" ] || {
            workflow_state_die "symlinked workflow-state directory: $candidate"
            return $?
        }
    done
    tmp=$(mktemp "$state.tmp.XXXXXX") || return 2
    workflow_state_transform_activate "$state" "$tmp" "$mode" "$root" "$common" "$host" \
        "$base_ref" "$base_sha" "$command" "$phase" "$next_step" "$task" || {
        rm -f "$tmp"
        return 2
    }
    workflow_state_validate_shape "$tmp" || {
        rm -f "$tmp"
        workflow_state_die "activation produced invalid state"
        return $?
    }
    mkdir -p "$evidence_dir" "$review_dir" || {
        rm -f "$tmp"
        workflow_state_die "could not create workflow evidence directories"
        return $?
    }
    forge_workflow_state_publish "$state" "$tmp" "$state_hash" || {
        rm -f "$tmp"
        return 2
    }
}

workflow_state_checkpoint() {
    local host="" phase="" next_step="" begin_review=false
    local seen_host=false seen_phase=false seen_next=false seen_begin=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --host)
                [ "$seen_host" = false ] && [ $# -ge 2 ] || return 2
                host="$2"; seen_host=true; shift 2 ;;
            --phase)
                [ "$seen_phase" = false ] && [ $# -ge 2 ] || return 2
                phase="$2"; seen_phase=true; shift 2 ;;
            --next-step)
                [ "$seen_next" = false ] && [ $# -ge 2 ] || return 2
                next_step="$2"; seen_next=true; shift 2 ;;
            --begin-review)
                [ "$seen_begin" = false ] || return 2
                begin_review=true; seen_begin=true; shift ;;
            *) workflow_state_die "unsupported checkpoint option: $1"; return $? ;;
        esac
    done
    [ "$seen_host" = true ] && [ "$seen_phase" = true ] && [ "$seen_next" = true ] || {
        workflow_state_die "checkpoint requires host, phase, and next-step"
        return $?
    }
    case "$host" in claude|codex) ;; *) workflow_state_die "invalid host: $host"; return $? ;; esac
    workflow_state_validate_cell "phase" "$phase" || return $?
    workflow_state_validate_cell "next step" "$next_step" || return $?

    local root common state state_hash command recorded_root recorded_common iteration next_iteration tmp
    root=$(workflow_state_root) || { workflow_state_die "not inside a Git worktree"; return $?; }
    common=$(workflow_state_common_dir "$root") || { workflow_state_die "cannot resolve Git common directory"; return $?; }
    state=$(workflow_state_canonical "$root") || return 2
    state_hash=$(workflow_state_hash "$state") || return 2
    command=$(workflow_state_value "$state" Workflow Command) || return 2
    recorded_root=$(workflow_state_value "$state" Identity 'Worktree root') || return 2
    recorded_common=$(workflow_state_value "$state" Identity 'Git common directory') || return 2
    iteration=$(workflow_state_value "$state" Receipts 'Review iteration') || return 2
    printf '%s\n' "$command" | grep -qE '^/(new-feature|fix-bug|quick-fix) [a-z0-9]+(-[a-z0-9]+)*$' \
        && [ "$recorded_root" = "$root" ] && [ "$recorded_common" = "$common" ] || {
            workflow_state_die "checkpoint requires an active workflow in this worktree"
            return $?
        }
    printf '%s\n' "$iteration" | grep -qE '^(0|[1-9][0-9]*)$' || {
        workflow_state_die "review iteration must be a non-negative integer"
        return $?
    }
    next_iteration="$iteration"
    if [ "$begin_review" = true ]; then
        next_iteration=$(workflow_state_increment_decimal "$iteration") || return 2
    fi

    tmp=$(mktemp "$state.tmp.XXXXXX") || return 2
    workflow_state_transform_checkpoint "$state" "$tmp" "$host" "$phase" "$next_step" \
        "$next_iteration" || {
        rm -f "$tmp"
        return 2
    }
    workflow_state_validate_shape "$tmp" || {
        rm -f "$tmp"
        workflow_state_die "checkpoint produced invalid state"
        return $?
    }
    forge_workflow_state_publish "$state" "$tmp" "$state_hash" || {
        rm -f "$tmp"
        return 2
    }
}

workflow_state_main() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift
    case "$action" in
        show)
            [ $# -eq 0 ] || { workflow_state_die "show accepts no arguments"; return $?; }
            workflow_state_show
            ;;
        activate) workflow_state_activate "$@" ;;
        checkpoint) workflow_state_checkpoint "$@" ;;
        *) workflow_state_die "usage: workflow-state show|activate|checkpoint" ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    workflow_state_main "$@"
    exit $?
fi
