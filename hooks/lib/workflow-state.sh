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
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        workflow_state_die "SHA-256 tool is unavailable"
        return $?
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
    workflow_state_validate_shape "$state" || {
        workflow_state_die "invalid canonical Forge V6 state"
        return $?
    }
    printf '%s\n' "$state"
}

workflow_state_value() {
    local path="$1" wanted_section="$2" wanted_key="$3"
    awk -F '|' -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
        { sub(/\r$/, "") }
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
    local path="$1" item section key first_count
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
    first_count=$(awk -F '|' '
        { sub(/\r$/, "") }
        /^## / { section=$0; sub(/^## /, "", section); next }
        section == "Receipts" && /^\|/ {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key == "First certified iteration") count++
        }
        END { print count + 0 }
    ' "$path")
    [ "$first_count" -le 1 ]
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
    workflow_state_validate_cell "task slug" "$task" || return $?
    [ ${#task} -le 64 ] || {
        workflow_state_die "task slug is too long"
        return $?
    }
    printf '%s\n' "$task" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' || {
        workflow_state_die "invalid task slug: $task"
        return $?
    }
}

workflow_state_optional_first_certified() {
    local state="$1" count
    count=$(awk -F '|' '
        { sub(/\r$/, "") }
        /^## / { section=$0; sub(/^## /, "", section); next }
        section == "Receipts" && /^\|/ {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key == "First certified iteration") count++
        }
        END { print count + 0 }
    ' "$state")
    case "$count" in
        0) printf 'none\n' ;;
        1) workflow_state_value "$state" Receipts 'First certified iteration' ;;
        *) workflow_state_die "state must contain at most one Receipts/First certified iteration row"; return $? ;;
    esac
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

workflow_state_reviews_valid() {
    local state="$1" verifier output
    verifier="$WORKFLOW_STATE_DIR/verification-receipt.sh"
    [ -f "$verifier" ] || return 1
    output=$(bash "$verifier" check --state "$state" 2>/dev/null || true)
    [ "$(printf '%s\n' "$output" | sed -n 's/^REVIEWS_VALID://p' | tail -1)" = true ]
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

workflow_state_transform_rebind() {
    local state="$1" next="$2" base_sha="$3"
    FORGE_WS_BASE_SHA="$base_sha" awk -F '|' '
        BEGIN { base_sha=ENVIRON["FORGE_WS_BASE_SHA"] }
        { sub(/\r$/, "") }
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        /^## / { section=$0; sub(/^## /, "", section) }
        section == "Identity" && /^\|/ && trim($2) == "Workflow base SHA" {
            print "| Workflow base SHA    | " base_sha " |"
            next
        }
        { print }
    ' "$state" > "$next"
}

workflow_state_transform_activate() {
    local state="$1" next="$2" mode="$3" root="$4" common="$5" host="$6"
    local base_ref="$7" base_sha="$8" command="$9"
    shift 9
    local phase="$1" next_step="$2" task="$3"
    FORGE_WS_MODE="$mode" FORGE_WS_ROOT="$root" FORGE_WS_COMMON="$common" \
    FORGE_WS_HOST="$host" FORGE_WS_BASE_REF="$base_ref" FORGE_WS_BASE_SHA="$base_sha" \
    FORGE_WS_COMMAND="$command" FORGE_WS_PHASE="$phase" FORGE_WS_NEXT="$next_step" \
    FORGE_WS_TASK="$task" awk -F '|' '
        BEGIN {
            mode=ENVIRON["FORGE_WS_MODE"]
            root=ENVIRON["FORGE_WS_ROOT"]
            common=ENVIRON["FORGE_WS_COMMON"]
            host=ENVIRON["FORGE_WS_HOST"]
            base_ref=ENVIRON["FORGE_WS_BASE_REF"]
            base_sha=ENVIRON["FORGE_WS_BASE_SHA"]
            command=ENVIRON["FORGE_WS_COMMAND"]
            phase_value=ENVIRON["FORGE_WS_PHASE"]
            next_value=ENVIRON["FORGE_WS_NEXT"]
            task=ENVIRON["FORGE_WS_TASK"]
        }
        { sub(/\r$/, "") }
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        section == "Receipts" && receipts_table && !first_seen && $0 !~ /^\|/ {
            print "| First certified iteration | none |"
            first_seen=1
        }
        /^## / {
            if (section == "Receipts" && !first_seen) {
                print "| First certified iteration | none |"
                first_seen=1
            }
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
        mode != "resume" && section == "Workflow" && /^\|/ {
            key=trim($2)
            if (key == "Command") { print "| Command   | " command " |"; next }
            if (key == "Phase") { print "| Phase     | " phase_value " |"; next }
            if (key == "Next step") { print "| Next step | " next_value " |"; next }
        }
        section == "Receipts" && /^\|/ {
            key=trim($2)
            if (key == "Review iteration") receipts_table=1
            if (key == "First certified iteration") {
                first_seen=1
                if (mode != "resume") print "| First certified iteration | none |"
                else print
                next
            }
            if (mode != "resume") {
                if (key == "Review iteration") { print "| Review iteration       | 0 |"; next }
                if (key == "Candidate receipt") { print "| Candidate receipt      | .forge/local/evidence/" task "/candidate.receipt |"; next }
                if (key == "Spec review receipt") { print "| Spec review receipt    | .forge/local/reviews/" task "/spec.receipt |"; next }
                if (key == "Quality review receipt") { print "| Quality review receipt | .forge/local/reviews/" task "/quality.receipt |"; next }
                if (key == "Verify app receipt") { print "| Verify app receipt     | .forge/local/evidence/" task "/verify-app.receipt |"; next }
                if (key == "E2E receipt") { print "| E2E receipt            | .forge/local/evidence/" task "/e2e.receipt |"; next }
                if (key == "Promotion receipt") { print "| Promotion receipt      | .forge/local/evidence/" task "/promotion.receipt |"; next }
            }
        }
        { print }
        END {
            if (section == "Receipts" && !first_seen) print "| First certified iteration | none |"
        }
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
    local first_certified="$7"
    FORGE_WS_HOST="$host" FORGE_WS_PHASE="$phase" FORGE_WS_NEXT="$next_step" \
    FORGE_WS_ITERATION="$iteration" FORGE_WS_FIRST_CERTIFIED="$first_certified" awk -F '|' '
        BEGIN {
            host=ENVIRON["FORGE_WS_HOST"]
            phase_value=ENVIRON["FORGE_WS_PHASE"]
            next_value=ENVIRON["FORGE_WS_NEXT"]
            iteration=ENVIRON["FORGE_WS_ITERATION"]
            first_certified=ENVIRON["FORGE_WS_FIRST_CERTIFIED"]
        }
        { sub(/\r$/, "") }
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        section == "Receipts" && receipts_table && !first_seen && $0 !~ /^\|/ {
            print "| First certified iteration | " first_certified " |"
            first_seen=1
        }
        /^## / {
            if (section == "Receipts" && !first_seen) {
                print "| First certified iteration | " first_certified " |"
                first_seen=1
            }
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
            receipts_table=1
            print "| Review iteration       | " iteration " |"
            next
        }
        section == "Receipts" && /^\|/ && trim($2) == "First certified iteration" {
            print "| First certified iteration | " first_certified " |"
            first_seen=1
            next
        }
        { print }
        END {
            if (section == "Receipts" && !first_seen) {
                print "| First certified iteration | " first_certified " |"
            }
        }
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

workflow_state_rebind() {
    local base_ref="" expected_base_sha="" seen_base=false seen_expected=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --base-ref)
                [ "$seen_base" = false ] || { workflow_state_die "duplicate rebind option: --base-ref"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --base-ref"; return $?; }
                base_ref="$2"; seen_base=true; shift 2 ;;
            --expected-base-sha)
                [ "$seen_expected" = false ] || { workflow_state_die "duplicate rebind option: --expected-base-sha"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --expected-base-sha"; return $?; }
                expected_base_sha="$2"; seen_expected=true; shift 2 ;;
            *) workflow_state_die "unsupported rebind option: $1"; return $? ;;
        esac
    done
    [ "$seen_base" = true ] && [ "$seen_expected" = true ] || {
        workflow_state_die "rebind requires base-ref and expected-base-sha"
        return $?
    }
    workflow_state_validate_ref "$base_ref" || return $?
    printf '%s\n' "$expected_base_sha" | grep -qE '^[0-9a-f]{40}([0-9a-f]{24})?$' || {
        workflow_state_die "expected base SHA must be a full lowercase Git object id"
        return $?
    }

    local root common state state_hash current_root current_common current_base_ref current_base_sha
    local current_command current_phase current_next current_iteration current_candidate current_spec
    local current_quality current_app current_e2e current_promotion current_council first_certified goal_nonce
    local current_head resolved_base tmp
    root=$(workflow_state_root) || { workflow_state_die "not inside a Git worktree"; return $?; }
    common=$(workflow_state_common_dir "$root") || { workflow_state_die "cannot resolve Git common directory"; return $?; }
    state=$(workflow_state_canonical "$root") || return 2
    state_hash=$(workflow_state_hash "$state") || return 2
    current_root=$(workflow_state_value "$state" Identity 'Worktree root') || return 2
    current_common=$(workflow_state_value "$state" Identity 'Git common directory') || return 2
    current_base_ref=$(workflow_state_value "$state" Identity 'Workflow base ref') || return 2
    current_base_sha=$(workflow_state_value "$state" Identity 'Workflow base SHA') || return 2
    current_command=$(workflow_state_value "$state" Workflow Command) || return 2
    current_phase=$(workflow_state_value "$state" Workflow Phase) || return 2
    current_next=$(workflow_state_value "$state" Workflow 'Next step') || return 2
    current_iteration=$(workflow_state_value "$state" Receipts 'Review iteration') || return 2
    current_candidate=$(workflow_state_value "$state" Receipts 'Candidate receipt') || return 2
    current_spec=$(workflow_state_value "$state" Receipts 'Spec review receipt') || return 2
    current_quality=$(workflow_state_value "$state" Receipts 'Quality review receipt') || return 2
    current_app=$(workflow_state_value "$state" Receipts 'Verify app receipt') || return 2
    current_e2e=$(workflow_state_value "$state" Receipts 'E2E receipt') || return 2
    current_promotion=$(workflow_state_value "$state" Receipts 'Promotion receipt') || return 2
    current_council=$(workflow_state_value "$state" Receipts 'Council receipt') || return 2
    first_certified=$(workflow_state_optional_first_certified "$state") || return 2
    goal_nonce=$(workflow_state_value "$state" '/goal session' nonce 2>/dev/null || true)

    [ "$current_root" = "$root" ] && [ "$current_common" = "$common" ] \
        && [ "$current_base_ref" = "$base_ref" ] || {
        workflow_state_die "rebind identity differs from the inactive worktree binding"
        return $?
    }
    [ "$current_base_sha" = "$expected_base_sha" ] || {
        workflow_state_die "inactive workflow base changed; rerun show before rebind"
        return $?
    }
    { [ -z "$current_command" ] || [ "$current_command" = none ] \
        || [ "$current_command" = - ] || [ "$current_command" = '—' ]; } \
        && [ -z "$current_phase" ] && [ -z "$current_next" ] || {
        workflow_state_die "rebind requires an inactive workflow with no phase or next step"
        return $?
    }
    { [ "$current_iteration" = 0 ] || [ "$current_iteration" = '<integer>' ]; } \
        && [ "$current_candidate" = '.forge/local/evidence/<task-id>/candidate.receipt' ] \
        && [ "$current_spec" = '.forge/local/reviews/<task-id>/spec.receipt' ] \
        && [ "$current_quality" = '.forge/local/reviews/<task-id>/quality.receipt' ] \
        && [ "$current_app" = '.forge/local/evidence/<task-id>/verify-app.receipt' ] \
        && [ "$current_e2e" = '.forge/local/evidence/<task-id>/e2e.receipt' ] \
        && [ "$current_promotion" = '.forge/local/evidence/<task-id>/promotion.receipt' ] \
        && [ "$current_council" = '.forge/local/council/<council-id>/receipt.json' ] \
        && [ "$first_certified" = none ] || {
        workflow_state_die "rebind refuses workflow or review evidence"
        return $?
    }
    case "$goal_nonce" in ''|'<uuid-v4-lowercase>') ;; *)
        workflow_state_die "rebind refuses an active or malformed Goal session"
        return $? ;;
    esac
    if grep -qE '^- \[x\] PR creation authorized — `[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$state"; then
        workflow_state_die "rebind refuses existing PR authorization"
        return $?
    fi
    git -C "$root" cat-file -e "${current_base_sha}^{commit}" 2>/dev/null || {
        workflow_state_die "inactive workflow base does not resolve to a commit"
        return $?
    }
    resolved_base=$(git -C "$root" rev-parse --verify "${base_ref}^{commit}" 2>/dev/null) || {
        workflow_state_die "base ref does not resolve to a commit: $base_ref"
        return $?
    }
    current_head=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null) || {
        workflow_state_die "cannot resolve worktree HEAD"
        return $?
    }
    [ "$resolved_base" = "$current_head" ] || {
        workflow_state_die "rebind target must resolve to current worktree HEAD"
        return $?
    }
    [ "$current_base_sha" != "$current_head" ] || {
        workflow_state_die "inactive workflow base already matches current HEAD"
        return $?
    }
    git -C "$root" merge-base --is-ancestor "$current_base_sha" "$current_head" 2>/dev/null || {
        workflow_state_die "rebind refuses a non-descendant worktree HEAD"
        return $?
    }

    tmp=$(mktemp "$state.tmp.XXXXXX") || return 2
    workflow_state_transform_rebind "$state" "$tmp" "$current_head" || {
        rm -f "$tmp"
        return 2
    }
    workflow_state_validate_shape "$tmp" || {
        rm -f "$tmp"
        workflow_state_die "rebind produced invalid state"
        return $?
    }
    forge_workflow_state_publish "$state" "$tmp" "$state_hash" || {
        rm -f "$tmp"
        return 2
    }
    printf 'REBOUND: base_ref=%s old=%s new=%s\n' "$base_ref" "$current_base_sha" "$current_head"
}

workflow_state_activate() {
    local host="" workflow="" task="" base_ref="" phase="" next_step=""
    local seen_host=false seen_workflow=false seen_task=false seen_base=false seen_phase=false seen_next=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --host)
                [ "$seen_host" = false ] || { workflow_state_die "duplicate activate option: --host"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --host"; return $?; }
                host="$2"; seen_host=true; shift 2 ;;
            --workflow)
                [ "$seen_workflow" = false ] || { workflow_state_die "duplicate activate option: --workflow"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --workflow"; return $?; }
                workflow="$2"; seen_workflow=true; shift 2 ;;
            --task)
                [ "$seen_task" = false ] || { workflow_state_die "duplicate activate option: --task"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --task"; return $?; }
                task="$2"; seen_task=true; shift 2 ;;
            --base-ref)
                [ "$seen_base" = false ] || { workflow_state_die "duplicate activate option: --base-ref"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --base-ref"; return $?; }
                base_ref="$2"; seen_base=true; shift 2 ;;
            --phase)
                [ "$seen_phase" = false ] || { workflow_state_die "duplicate activate option: --phase"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --phase"; return $?; }
                phase="$2"; seen_phase=true; shift 2 ;;
            --next-step)
                [ "$seen_next" = false ] || { workflow_state_die "duplicate activate option: --next-step"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --next-step"; return $?; }
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

    local root common state base_sha state_hash current_command current_phase current_next current_head bound_mode
    local current_root current_common current_base_ref current_base_sha current_iteration command mode
    local current_candidate current_spec current_quality current_app current_e2e current_promotion
    local expected_candidate expected_spec expected_quality expected_app expected_e2e expected_promotion
    local evidence_dir review_dir candidate tmp
    root=$(workflow_state_root) || { workflow_state_die "not inside a Git worktree"; return $?; }
    common=$(workflow_state_common_dir "$root") || { workflow_state_die "cannot resolve Git common directory"; return $?; }
    state=$(workflow_state_canonical "$root") || return 2
    state_hash=$(workflow_state_hash "$state") || return 2
    current_command=$(workflow_state_value "$state" Workflow Command) || return 2
    current_phase=$(workflow_state_value "$state" Workflow Phase) || return 2
    current_next=$(workflow_state_value "$state" Workflow 'Next step') || return 2
    current_root=$(workflow_state_value "$state" Identity 'Worktree root') || return 2
    current_common=$(workflow_state_value "$state" Identity 'Git common directory') || return 2
    current_base_ref=$(workflow_state_value "$state" Identity 'Workflow base ref') || return 2
    current_base_sha=$(workflow_state_value "$state" Identity 'Workflow base SHA') || return 2
    current_iteration=$(workflow_state_value "$state" Receipts 'Review iteration') || return 2
    current_candidate=$(workflow_state_value "$state" Receipts 'Candidate receipt') || return 2
    current_spec=$(workflow_state_value "$state" Receipts 'Spec review receipt') || return 2
    current_quality=$(workflow_state_value "$state" Receipts 'Quality review receipt') || return 2
    current_app=$(workflow_state_value "$state" Receipts 'Verify app receipt') || return 2
    current_e2e=$(workflow_state_value "$state" Receipts 'E2E receipt') || return 2
    current_promotion=$(workflow_state_value "$state" Receipts 'Promotion receipt') || return 2
    bound_mode=none
    if printf '%s\n' "$current_base_sha" | grep -qE '^[0-9a-f]{40}([0-9a-f]{24})?$'; then
        if [ -n "$current_command" ] && [ "$current_command" != none ] \
            && [ "$current_command" != - ] && [ "$current_command" != '—' ] \
            && ! { [ "$current_phase" = complete ] && [ "$current_next" = none ]; }; then
            bound_mode=active
        elif [ -z "$current_command" ] || [ "$current_command" = none ] \
            || [ "$current_command" = - ] || [ "$current_command" = '—' ]; then
            bound_mode=prebound
        fi
    fi
    if [ "$bound_mode" != none ]; then
        [ "$current_root" = "$root" ] \
            && [ "$current_common" = "$common" ] \
            && [ "$current_base_ref" = "$base_ref" ] \
            && git -C "$root" cat-file -e "${current_base_sha}^{commit}" 2>/dev/null || {
                workflow_state_die "bound worktree identity differs from requested activation"
                return $?
            }
        current_head=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null) || {
            workflow_state_die "cannot resolve bound worktree HEAD"
            return $?
        }
        if [ "$bound_mode" = prebound ]; then
            [ "$current_head" = "$current_base_sha" ] || {
                workflow_state_die "prebound worktree HEAD differs from its adopted base; inspect with show, then use workflow-state rebind only for the approved descendant base"
                return $?
            }
        else
            git -C "$root" merge-base --is-ancestor "$current_base_sha" "$current_head" 2>/dev/null || {
                workflow_state_die "active workflow base is not an ancestor of HEAD"
                return $?
            }
        fi
        base_sha=$current_base_sha
    else
        base_sha=$(git -C "$root" rev-parse --verify "${base_ref}^{commit}" 2>/dev/null) || {
            workflow_state_die "base ref does not resolve to a commit: $base_ref"
            return $?
        }
    fi
    command="/$workflow $task"
    expected_candidate=".forge/local/evidence/$task/candidate.receipt"
    expected_spec=".forge/local/reviews/$task/spec.receipt"
    expected_quality=".forge/local/reviews/$task/quality.receipt"
    expected_app=".forge/local/evidence/$task/verify-app.receipt"
    expected_e2e=".forge/local/evidence/$task/e2e.receipt"
    expected_promotion=".forge/local/evidence/$task/promotion.receipt"

    mode=new
    if [ -n "$current_command" ] && [ "$current_command" != none ] \
        && [ "$current_command" != - ] && [ "$current_command" != '—' ] \
        && ! { [ "$current_phase" = complete ] && [ "$current_next" = none ]; }; then
        [ "$current_command" = "$command" ] \
            && [ "$current_root" = "$root" ] \
            && [ "$current_common" = "$common" ] \
            && [ "$current_base_ref" = "$base_ref" ] \
            && [ "$current_base_sha" = "$base_sha" ] \
            && [ "$current_phase" = "$phase" ] \
            && [ "$current_next" = "$next_step" ] || {
                workflow_state_die "a different or inconsistent workflow is already active"
                return $?
            }
        if printf '%s\n' "$current_iteration" | grep -qE '^[0-9]+$' \
            && [ "$current_candidate" = "$expected_candidate" ] \
            && [ "$current_spec" = "$expected_spec" ] \
            && [ "$current_quality" = "$expected_quality" ] \
            && [ "$current_app" = "$expected_app" ] \
            && [ "$current_e2e" = "$expected_e2e" ] \
            && [ "$current_promotion" = "$expected_promotion" ]; then
            mode=resume
        elif [ "$current_iteration" = '<integer>' ] \
            && [ "$current_candidate" = '.forge/local/evidence/<task-id>/candidate.receipt' ] \
            && [ "$current_spec" = '.forge/local/reviews/<task-id>/spec.receipt' ] \
            && [ "$current_quality" = '.forge/local/reviews/<task-id>/quality.receipt' ] \
            && [ "$current_app" = '.forge/local/evidence/<task-id>/verify-app.receipt' ] \
            && [ "$current_e2e" = '.forge/local/evidence/<task-id>/e2e.receipt' ] \
            && [ "$current_promotion" = '.forge/local/evidence/<task-id>/promotion.receipt' ]; then
            mode=adopt
        else
            workflow_state_die "a different or inconsistent workflow is already active"
            return $?
        fi
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
                [ "$seen_host" = false ] || { workflow_state_die "duplicate checkpoint option: --host"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --host"; return $?; }
                host="$2"; seen_host=true; shift 2 ;;
            --phase)
                [ "$seen_phase" = false ] || { workflow_state_die "duplicate checkpoint option: --phase"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --phase"; return $?; }
                phase="$2"; seen_phase=true; shift 2 ;;
            --next-step)
                [ "$seen_next" = false ] || { workflow_state_die "duplicate checkpoint option: --next-step"; return $?; }
                [ $# -ge 2 ] || { workflow_state_die "option requires a value: --next-step"; return $?; }
                next_step="$2"; seen_next=true; shift 2 ;;
            --begin-review)
                [ "$seen_begin" = false ] || { workflow_state_die "duplicate checkpoint option: --begin-review"; return $?; }
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

    local root common state state_hash command recorded_root recorded_common iteration next_iteration
    local first_certified tmp
    root=$(workflow_state_root) || { workflow_state_die "not inside a Git worktree"; return $?; }
    common=$(workflow_state_common_dir "$root") || { workflow_state_die "cannot resolve Git common directory"; return $?; }
    state=$(workflow_state_canonical "$root") || return 2
    state_hash=$(workflow_state_hash "$state") || return 2
    command=$(workflow_state_value "$state" Workflow Command) || return 2
    recorded_root=$(workflow_state_value "$state" Identity 'Worktree root') || return 2
    recorded_common=$(workflow_state_value "$state" Identity 'Git common directory') || return 2
    iteration=$(workflow_state_value "$state" Receipts 'Review iteration') || return 2
    first_certified=$(workflow_state_optional_first_certified "$state") || return 2
    printf '%s\n' "$command" | grep -qE '^/(new-feature|fix-bug|quick-fix) [a-z0-9]+(-[a-z0-9]+)*$' \
        && [ "$recorded_root" = "$root" ] && [ "$recorded_common" = "$common" ] || {
            workflow_state_die "checkpoint requires an active workflow in this worktree"
            return $?
        }
    printf '%s\n' "$iteration" | grep -qE '^(0|[1-9][0-9]*)$' || {
        workflow_state_die "review iteration must be a non-negative integer"
        return $?
    }
    case "$first_certified" in
        none) ;;
        ''|0|*[!0-9]*)
            workflow_state_die "first certified iteration must be none or a positive integer"
            return $?
            ;;
    esac
    if [ "$first_certified" = none ] && [ "$iteration" != 0 ] \
        && workflow_state_reviews_valid "$state"; then
        first_certified="$iteration"
    fi
    next_iteration="$iteration"
    if [ "$begin_review" = true ]; then
        next_iteration=$(workflow_state_increment_decimal "$iteration") || return 2
    fi

    tmp=$(mktemp "$state.tmp.XXXXXX") || return 2
    workflow_state_transform_checkpoint "$state" "$tmp" "$host" "$phase" "$next_step" \
        "$next_iteration" "$first_certified" || {
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
        rebind) workflow_state_rebind "$@" ;;
        activate) workflow_state_activate "$@" ;;
        checkpoint) workflow_state_checkpoint "$@" ;;
        *) workflow_state_die "usage: workflow-state show|rebind|activate|checkpoint" ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    workflow_state_main "$@"
    exit $?
fi
