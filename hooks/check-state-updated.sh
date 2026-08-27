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

# Receipt-v2 Stop advisory: surface invalidation immediately after any tracked,
# index, or in-scope untracked mutation. Shipping remains enforced by the
# PreToolUse gate; Stop does not turn this reminder into a second policy engine.
if [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ]; then
    _candidate_receipt=$(tr -d '\r' < "$STATE_MD" | awk -F'|' '{k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if(k=="Candidate receipt"){v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit}}')
    case "$_candidate_receipt" in ''|*'<'*) ;; *)
        _vr="$HOOK_DIR/lib/verification-receipt.sh"
        [ -f "$_vr" ] || _vr="hooks/lib/verification-receipt.sh"
        if [ ! -f "$_vr" ] || ! bash "$_vr" check --state "$STATE_MD" >/dev/null 2>&1; then
            echo "FORGE_FINAL_EVIDENCE_STALE: candidate-bound review, verify-app, and E2E receipts no longer certify the current staged-clean candidate." >&2
        fi
        ;;
    esac
fi

_forge_goal_authorization_tampered() {
    echo "FORGE_GOAL_AUTHORIZATION_TAMPERED: $1" >&2
    exit 2
}

_FORGE_GOAL_LOCK=""
_forge_goal_release_lock() { [ -z "$_FORGE_GOAL_LOCK" ] || rmdir "$_FORGE_GOAL_LOCK" 2>/dev/null || true; }
_forge_goal_require_dir() {
    local path="$1" prefix="$2" physical
    [ -d "$path" ] && [ ! -L "$path" ] || _forge_goal_authorization_tampered "missing or aliased ledger ancestor: $path"
    physical=$(cd "$path" 2>/dev/null && pwd -P) || _forge_goal_authorization_tampered "unresolvable ledger ancestor: $path"
    case "$physical" in "$prefix"|"$prefix"/*) ;; *) _forge_goal_authorization_tampered "ledger ancestor escapes trusted root: $path" ;; esac
}
_forge_goal_value() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }
_forge_goal_publish_no_clobber() {
    local destination="$1" source="$2" label="$3" source_hash
    source_hash=$(_forge_hash_file "$source") || _forge_goal_authorization_tampered "$label hash unavailable"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$source" "$destination" \
            || _forge_goal_authorization_tampered "$label already exists with different or invalid content"
    else
        ln "$source" "$destination" 2>/dev/null || {
            [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$source" "$destination" \
                || _forge_goal_authorization_tampered "$label no-clobber publication failed"
        }
    fi
    [ -f "$destination" ] && [ ! -L "$destination" ] \
        && [ "$(_forge_hash_file "$destination")" = "$source_hash" ] && cmp -s "$source" "$destination" \
        || _forge_goal_authorization_tampered "$label read verification failed"
    chmod 444 "$destination" 2>/dev/null || true
}

# Charge one authenticated turn. The required local Task-2 contract is mirrored
# by a protected external monotonic ledger. Any count/name/content divergence
# blocks rather than letting editable project state reset the budget.
_forge_goal_charge_turn() {
    [ "$STATE_LOCAL_DIR" = .forge/local ] && [ -f "$STATE_MD" ] || return 0
    local goal_block nonce objective workflow phase next host session turn_id root common project_id
    local home_forge writer_path writer_seal writer_expected writer_actual auth_root auth_root_physical auth_project auth auth_nonce auth_objective ceiling approval issue writer
    local counter local_turns external_turns ledger binding binding_tmp turn_key record_tmp external_record local_record external_count
    local checkpoint checkpoint_tmp checkpoint_hash marker marker_tmp lock attempt _p _file _name
    goal_block=$(tr -d '\r' < "$STATE_MD" | awk '/^## \/goal session$/{f=1;next} f&&/^## /{f=0} f')
    nonce=$(printf '%s\n' "$goal_block" | awk -F'|' 'tolower($2) ~ /^[[:space:]]*nonce[[:space:]]*$/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3; exit}')
    [ -n "$nonce" ] || return 0
    [ "$nonce" = "<uuid-v4-lowercase>" ] && return 0
    objective=$(printf '%s\n' "$goal_block" | awk -F'|' 'tolower($2) ~ /^[[:space:]]*objective_hash[[:space:]]*$/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3; exit}')
    workflow=$(printf '%s\n' "$goal_block" | awk -F'|' 'tolower($2) ~ /^[[:space:]]*workflow_command[[:space:]]*$/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3; exit}')
    case "$nonce" in ????????-????-4???-[89abAB]???-????????????) ;; *) _forge_goal_authorization_tampered "invalid active nonce"; return 0 ;; esac
    case "$objective" in ''|*[!A-Za-z0-9._-]*) _forge_goal_authorization_tampered "missing or invalid objective hash"; return 0 ;; esac

    if command -v jq >/dev/null 2>&1; then
        turn_id=$(printf '%s' "$INPUT" | jq -r '.turn_id // .hook_turn_id // .assistant_message_id // ""' 2>/dev/null || true)
        session=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
        host=$(printf '%s' "$INPUT" | jq -r '.host // .engine // "unknown"' 2>/dev/null || echo unknown)
        if [ -z "$turn_id" ]; then
            _last=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)
            [ -n "$_last" ] && turn_id=$(printf '%s\n%s\n' "$session" "$_last" | _forge_hash_text)
        fi
    else turn_id=""; session=unknown; host=unknown
    fi
    # Old hosts without a stable turn identity remain uncharged rather than
    # double-charging duplicate Stop delivery. v6 adapters provide turn_id.
    [ -n "$turn_id" ] || return 0
    case "$turn_id" in *[!A-Za-z0-9._-]*) turn_key=$(printf '%s' "$turn_id" | _forge_hash_text) ;; *) turn_key="$turn_id" ;; esac
    case "$host" in claude|codex) ;; *) host=unknown ;; esac

    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0; root=$(cd "$root" && pwd -P)
    common=$(git rev-parse --git-common-dir 2>/dev/null) || return 0; case "$common" in /*) ;; *) common="$root/$common" ;; esac; common=$(cd "$common" && pwd -P)
    project_id=$(printf '%s\n%s\n' "$root" "$common" | _forge_hash_text)
    [ -n "${HOME:-}" ] || _forge_goal_authorization_tampered "trusted home unavailable"
    home_forge="$HOME/.forge"
    _forge_goal_require_dir "$home_forge" "$(cd "$HOME" 2>/dev/null && pwd -P)"
    _forge_goal_require_dir "$home_forge/bin" "$(cd "$home_forge" && pwd -P)"
    writer_path="$home_forge/bin/forge-goal-authorize"; writer_seal="$writer_path.sha256"
    [ -f "$writer_path" ] && [ ! -L "$writer_path" ] && [ -f "$writer_seal" ] && [ ! -L "$writer_seal" ] \
        || _forge_goal_authorization_tampered "sealed authorization writer unavailable or aliased"
    writer_actual=$(_forge_hash_file "$writer_path")
    [ "$(tr -d '[:space:]' < "$writer_seal")" = "$writer_actual" ] \
        || _forge_goal_authorization_tampered "authorization writer revision seal mismatch"
    writer_expected=$(sed -n "s/^WRITER_REVISION='\([^']*\)'.*/\1/p" "$writer_path" | head -1)
    case "$writer_expected" in ????????????????????????????????????????????????????????????????) ;; *) _forge_goal_authorization_tampered "installed writer identity is unsealed" ;; esac

    auth_root="$home_forge/goal-authorizations"
    _forge_goal_require_dir "$auth_root" "$(cd "$home_forge" && pwd -P)"
    auth_root_physical=$(cd "$auth_root" && pwd -P)
    case "$auth_root_physical" in "$root"|"$root"/*|"$common"|"$common"/*) _forge_goal_authorization_tampered "authorization root overlaps project authority" ;; esac
    auth_project="$auth_root/$project_id"; _forge_goal_require_dir "$auth_project" "$auth_root_physical"
    auth="$auth_project/$nonce.auth"; [ -f "$auth" ] && [ ! -L "$auth" ] || _forge_goal_authorization_tampered "authorization record missing or aliased"
    _av() { sed -n "s/^$1=//p" "$auth" | head -1; }
    auth_nonce=$(_av nonce); auth_objective=$(_av objective_hash); ceiling=$(_av ceiling); approval=$(_av approval_channel); issue=$(_av issue_id); writer=$(_av writer_revision)
    [ "$(_av format)" = forge-goal-authorization-v1 ] && [ "$(_av project_root)" = "$root" ] \
        && [ "$(_av git_common_dir)" = "$common" ] && [ "$(_av project_id)" = "$project_id" ] \
        && [ "$auth_nonce" = "$nonce" ] && [ "$auth_objective" = "$objective" ] \
        && [ "$approval" = physical-operator-action ] && [ -n "$issue" ] \
        || _forge_goal_authorization_tampered "state/authorization binding mismatch"
    case "$ceiling" in ''|*[!0-9]*|0) _forge_goal_authorization_tampered "invalid external ceiling" ;; esac
    [ "$writer" = "$writer_expected" ] || _forge_goal_authorization_tampered "authorization writer revision does not match sealed installed writer"

    counter="$root/.forge/local/goal-counters/$nonce"
    local_turns="$counter/turns"
    ledger="$auth_project/$nonce.ledger"
    external_turns="$ledger/turns"
    _forge_goal_require_dir "$root/.forge" "$root"
    _forge_goal_require_dir "$root/.forge/local" "$root"
    for _p in "$root/.forge/local/goal-counters" "$counter" "$local_turns"; do
        [ ! -L "$_p" ] || _forge_goal_authorization_tampered "aliased turn ledger"
        mkdir -p "$_p" 2>/dev/null || _forge_goal_authorization_tampered "turn ledger unavailable"
        _forge_goal_require_dir "$_p" "$root"
    done
    for _p in "$ledger" "$external_turns"; do
        [ ! -L "$_p" ] || _forge_goal_authorization_tampered "aliased protected ledger"
        mkdir -p "$_p" 2>/dev/null || _forge_goal_authorization_tampered "protected turn ledger unavailable"
        _forge_goal_require_dir "$_p" "$auth_root_physical"
    done

    lock="$counter/.goal-charge.lock"; attempt=0
    while ! mkdir "$lock" 2>/dev/null; do
        [ -L "$lock" ] && _forge_goal_authorization_tampered "aliased checkpoint lock"
        attempt=$((attempt + 1)); [ "$attempt" -lt 200 ] || _forge_goal_authorization_tampered "checkpoint publication lock unavailable"
        sleep 0.01
    done
    _FORGE_GOAL_LOCK="$lock"; trap '_forge_goal_release_lock' EXIT HUP INT TERM
    _forge_goal_require_dir "$lock" "$root"

    # Freeze the exact user-owned authorization at first charge. This protected
    # binding means a later valid-shaped ceiling/objective/issue replacement is
    # still detected even though the project-local mirror is fully editable.
    binding="$ledger/authorization.binding"
    binding_tmp="$ledger/.authorization.binding.$$"
    { printf 'format=forge-goal-ledger-v1\nauthorization_sha256=%s\nnonce=%s\nobjective_hash=%s\nceiling=%s\nissue_id=%s\nwriter_revision=%s\nproject_id=%s\n' \
        "$(_forge_hash_file "$auth")" "$nonce" "$objective" "$ceiling" "$issue" "$writer" "$project_id"; } > "$binding_tmp" \
        || _forge_goal_authorization_tampered "authorization binding unavailable"
    if [ ! -f "$binding" ]; then
        if find "$external_turns" -maxdepth 1 -type f -print -quit 2>/dev/null | grep -q .; then
            rm -f "$binding_tmp"; _forge_goal_authorization_tampered "authorization binding deleted after charging"
        fi
        ln "$binding_tmp" "$binding" 2>/dev/null || true
    fi
    if [ ! -f "$binding" ] || [ -L "$binding" ] || ! cmp -s "$binding_tmp" "$binding"; then
        rm -f "$binding_tmp"; _forge_goal_authorization_tampered "authorization record changed after activation"
    fi
    rm -f "$binding_tmp"; chmod 444 "$binding" 2>/dev/null || true

    # Protected authority is monotonic. Missing local mirrors are recoverable;
    # extra/divergent local records and any malformed protected record block.
    while IFS= read -r -d '' _file; do
        _name=$(basename "$_file"); case "$_name" in ''|*[!A-Za-z0-9._-]*) _forge_goal_authorization_tampered "invalid protected turn name" ;; esac
        [ -f "$_file" ] && [ ! -L "$_file" ] || _forge_goal_authorization_tampered "invalid protected turn entry"
        [ "$(_forge_goal_value "$_file" format)" = forge-goal-turn-v1 ] \
            && [ "$(_forge_goal_value "$_file" nonce)" = "$nonce" ] \
            && [ "$(_forge_goal_value "$_file" objective_hash)" = "$objective" ] \
            && [ -n "$(_forge_goal_value "$_file" turn_id)" ] \
            || _forge_goal_authorization_tampered "malformed protected turn record"
        if [ -e "$local_turns/$_name" ] || [ -L "$local_turns/$_name" ]; then
            [ -f "$local_turns/$_name" ] && [ ! -L "$local_turns/$_name" ] && cmp -s "$_file" "$local_turns/$_name" \
                || _forge_goal_authorization_tampered "turn record content diverged"
        else
            cp "$_file" "$local_turns/.$_name.recover.$$" 2>/dev/null \
                || _forge_goal_authorization_tampered "local turn recovery write failed"
            [ "$(_forge_hash_file "$_file")" = "$(_forge_hash_file "$local_turns/.$_name.recover.$$")" ] \
                || _forge_goal_authorization_tampered "local turn recovery verification failed"
            ln "$local_turns/.$_name.recover.$$" "$local_turns/$_name" 2>/dev/null \
                || _forge_goal_authorization_tampered "local turn recovery collision"
            rm -f "$local_turns/.$_name.recover.$$"; chmod 444 "$local_turns/$_name" 2>/dev/null || true
        fi
    done < <(find "$external_turns" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    while IFS= read -r -d '' _file; do
        _name=$(basename "$_file")
        [ -f "$_file" ] && [ ! -L "$_file" ] && [ -f "$external_turns/$_name" ] && [ ! -L "$external_turns/$_name" ] \
            && cmp -s "$_file" "$external_turns/$_name" || _forge_goal_authorization_tampered "local and protected turn ledgers diverged"
    done < <(find "$local_turns" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    external_count=$(find "$external_turns" -maxdepth 1 -type f | wc -l | tr -d ' ')
    checkpoint="$counter/checkpoint"; marker="$counter/budget-exhausted.marker"
    if [ -e "$checkpoint" ] || [ -L "$checkpoint" ] || [ -e "$marker" ] || [ -L "$marker" ]; then
        [ -f "$checkpoint" ] && [ ! -L "$checkpoint" ] && [ -f "$marker" ] && [ ! -L "$marker" ] \
            || _forge_goal_authorization_tampered "partial or aliased exhaustion publication"
        [ "$(_forge_goal_value "$checkpoint" format)" = forge-goal-checkpoint-v1 ] \
            && [ "$(_forge_goal_value "$checkpoint" nonce)" = "$nonce" ] \
            && [ "$(_forge_goal_value "$checkpoint" objective_hash)" = "$objective" ] \
            && [ "$(_forge_goal_value "$checkpoint" turn_count)" = "$external_count" ] \
            && [ "$(_forge_goal_value "$checkpoint" turn_ceiling)" = "$ceiling" ] \
            && [ "$external_count" -ge "$ceiling" ] \
            || _forge_goal_authorization_tampered "checkpoint authority mismatch"
        [ "$(head -1 "$marker" 2>/dev/null)" = FORGE_GOAL_BUDGET_EXHAUSTED ] \
            && [ "$(_forge_goal_value "$marker" nonce)" = "$nonce" ] \
            && [ "$(_forge_goal_value "$marker" turn_count)" = "$external_count" ] \
            && [ "$(_forge_goal_value "$marker" turn_ceiling)" = "$ceiling" ] \
            && [ "$(_forge_goal_value "$marker" checkpoint)" = "$checkpoint" ] \
            && [ "$(_forge_goal_value "$marker" checkpoint_sha256)" = "$(_forge_hash_file "$checkpoint")" ] \
            || _forge_goal_authorization_tampered "marker/checkpoint binding mismatch"
        echo "FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$checkpoint" >&2
        _forge_goal_release_lock; _FORGE_GOAL_LOCK=""; trap - EXIT HUP INT TERM
        return 0
    fi

    phase=$(tr -d '\r' < "$STATE_MD" | awk -F'|' 'tolower($2) ~ /^[[:space:]]*phase[[:space:]]*$/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3; exit}')
    next=$(tr -d '\r' < "$STATE_MD" | awk -F'|' 'tolower($2) ~ /^[[:space:]]*next step[[:space:]]*$/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3; exit}')
    external_record="$external_turns/$turn_key"; local_record="$local_turns/$turn_key"
    if [ ! -f "$external_record" ]; then
        record_tmp="$auth_project/.$nonce.$turn_key.$$"
        umask 077
        (umask 077; set -C; printf 'format=forge-goal-turn-v1\nnonce=%s\nobjective_hash=%s\nturn_id=%s\nhost=%s\nsession_id=%s\nstate_sha256=%s\nnext_step=%s\n' \
            "$nonce" "$objective" "$turn_id" "$host" "$session" "$(_forge_hash_file "$STATE_MD")" "$next" > "$record_tmp") \
            || _forge_goal_authorization_tampered "protected turn staging failed"
        if ln "$record_tmp" "$external_record" 2>/dev/null; then
            chmod 444 "$external_record" 2>/dev/null || true
            cp "$external_record" "$local_record.tmp.$$" 2>/dev/null || { rm -f "$record_tmp"; _forge_goal_authorization_tampered "local turn mirror write failed"; }
            if ! ln "$local_record.tmp.$$" "$local_record" 2>/dev/null; then rm -f "$local_record.tmp.$$" "$record_tmp"; _forge_goal_authorization_tampered "local turn replay or collision"; fi
            rm -f "$local_record.tmp.$$"; chmod 444 "$local_record" 2>/dev/null || true
        fi
        rm -f "$record_tmp"
    fi
    [ -f "$external_record" ] && [ ! -L "$external_record" ] || _forge_goal_authorization_tampered "protected turn publication incomplete"
    if [ ! -f "$local_record" ]; then
        cp "$external_record" "$local_record.tmp.$$" 2>/dev/null && ln "$local_record.tmp.$$" "$local_record" 2>/dev/null || true
        rm -f "$local_record.tmp.$$"
    fi
    [ -f "$local_record" ] && [ ! -L "$local_record" ] && cmp -s "$external_record" "$local_record" \
        || _forge_goal_authorization_tampered "turn mirror incomplete"
    external_count=$(find "$external_turns" -maxdepth 1 -type f | wc -l | tr -d ' ')

    if [ "$external_count" -lt "$ceiling" ]; then
        { [ ! -e "$checkpoint" ] && [ ! -L "$checkpoint" ] && [ ! -e "$marker" ] && [ ! -L "$marker" ]; } \
            || _forge_goal_authorization_tampered "premature checkpoint or marker exists"
        _forge_goal_release_lock; _FORGE_GOAL_LOCK=""; trap - EXIT HUP INT TERM
        return 0
    fi

    checkpoint_tmp="$counter/.checkpoint.$turn_key.$$"
    (umask 077; set -C; printf 'format=forge-goal-checkpoint-v1\nnonce=%s\nobjective_hash=%s\nturn_count=%s\nturn_ceiling=%s\nturn_id=%s\nhost=%s\nworkflow_command=%s\nphase=%s\nnext_step=%s\nstate_sha256=%s\n' \
        "$nonce" "$objective" "$external_count" "$ceiling" "$turn_id" "$host" "$workflow" "$phase" "$next" "$(_forge_hash_file "$STATE_MD")" > "$checkpoint_tmp") \
        || _forge_goal_authorization_tampered "checkpoint staging failed"
    _forge_goal_publish_no_clobber "$checkpoint" "$checkpoint_tmp" checkpoint
    checkpoint_hash=$(_forge_hash_file "$checkpoint")
    rm -f "$checkpoint_tmp"
    if [ "$external_count" -ge "$ceiling" ]; then
        marker_tmp="$counter/.budget-exhausted.$turn_key.$$"
        (umask 077; set -C; printf 'FORGE_GOAL_BUDGET_EXHAUSTED\npaused=true\nnext_step=%s\nnonce=%s\nturn_count=%s\nturn_ceiling=%s\ncheckpoint=%s\ncheckpoint_sha256=%s\n' \
            "$next" "$nonce" "$external_count" "$ceiling" "$checkpoint" "$checkpoint_hash" > "$marker_tmp") \
            || _forge_goal_authorization_tampered "marker staging failed"
        _forge_goal_publish_no_clobber "$marker" "$marker_tmp" marker
        rm -f "$marker_tmp"
        [ "$(_forge_goal_value "$marker" checkpoint_sha256)" = "$(_forge_hash_file "$checkpoint")" ] \
            || _forge_goal_authorization_tampered "marker/checkpoint binding mismatch"
        echo "FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$checkpoint" >&2
    fi
    _forge_goal_release_lock; _FORGE_GOAL_LOCK=""; trap - EXIT HUP INT TERM
}

_forge_goal_charge_turn

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
        echo "FORGE_GOAL_STUCK_WARNING: no measurable progress for $new_count consecutive turns (fingerprint unchanged). Consider invoking /council, checkpointing state.md, or surfacing a blocker. Loop continues — this is informational only." >&2
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

# Advisory: remind about active workflow even when no issues (non-blocking)
if [ -n "$WORKFLOW_REMINDER" ]; then
    echo "$WORKFLOW_REMINDER" >&2
fi

# All good, allow stop
forge_allow
