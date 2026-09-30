#!/usr/bin/env bash
# Repository-local, worktree-shared accounting for native /goal activations.

set -u

TRANCHE=20
LOCK_PATH=""

die() {
    printf 'FORGE_GOAL_LEDGER_TAMPERED: %s\n' "$1" >&2
    exit 2
}

hash_text() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else sha256sum | awk '{print $1}'
    fi
}

hash_file() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'
    fi
}

value() {
    sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

state_value() {
    local section="$1" key="$2"
    tr -d '\r' < "$STATE" | awk -F'|' -v section="$section" -v wanted="$key" '
        $0 == section { active=1; next }
        active && /^## / { active=0 }
        active {
            key=$2
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (tolower(key) == tolower(wanted)) {
                value=$3
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
            }
        }
    '
}

one_state_value() {
    local section="$1" key="$2" found count
    found=$(state_value "$section" "$key")
    count=$(printf '%s\n' "$found" | awk 'NF { n++ } END { print n+0 }')
    [ "$count" -eq 1 ] || die "state field '$key' is missing or duplicated"
    printf '%s\n' "$found"
}

release_lock() {
    [ -z "$LOCK_PATH" ] || rmdir "$LOCK_PATH" 2>/dev/null || true
    LOCK_PATH=""
}

acquire_lock() {
    local attempt=0
    while ! mkdir "$LOCK" 2>/dev/null; do
        [ -L "$LOCK" ] && die "ledger lock is aliased"
        attempt=$((attempt + 1))
        [ "$attempt" -lt 300 ] || die "ledger lock is abandoned or unavailable"
        sleep 0.01
    done
    LOCK_PATH="$LOCK"
    trap 'release_lock' EXIT HUP INT TERM
}

ensure_plain_dir() {
    local path="$1"
    [ ! -L "$path" ] || die "ledger ancestor is aliased: $path"
    if [ ! -e "$path" ]; then
        mkdir "$path" 2>/dev/null || die "cannot create ledger directory: $path"
    fi
    [ -d "$path" ] && [ ! -L "$path" ] || die "invalid ledger directory: $path"
}

publish() {
    local destination="$1" content="$2" label="$3" tmp
    tmp="${destination}.tmp.$$.$RANDOM"
    (umask 077; set -C; printf '%s\n' "$content" > "$tmp") \
        || die "$label staging failed"
    if ! ln "$tmp" "$destination" 2>/dev/null; then
        [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$tmp" "$destination" \
            || { rm -f "$tmp"; die "$label no-clobber publication failed"; }
    fi
    rm -f "$tmp"
    [ -f "$destination" ] && [ ! -L "$destination" ] || die "$label publication is invalid"
    chmod 444 "$destination" 2>/dev/null || true
}

validate_file_shape() {
    local file="$1" expected_lines="$2" label="$3"
    [ -f "$file" ] && [ ! -L "$file" ] || die "$label is missing or aliased"
    [ "$(awk 'END { print NR+0 }' "$file")" -eq "$expected_lines" ] \
        || die "$label has malformed content"
}

validate_binding() {
    validate_file_shape "$BINDING" 5 binding
    [ "$(value "$BINDING" format)" = forge-goal-ledger-v2 ] \
        && [ "$(value "$BINDING" project_id)" = "$PROJECT_ID" ] \
        && [ "$(value "$BINDING" nonce)" = "$NONCE" ] \
        && [ "$(value "$BINDING" objective_hash)" = "$OBJECTIVE" ] \
        && [ "$(value "$BINDING" turn_tranche)" = "$TRANCHE" ] \
        || die "state/binding mismatch"
}

validate_activations() {
    local expected=1 entry name count=0 sequence aid seen="|"
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        name=$(basename "$entry")
        case "$name" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "invalid activation entry: $name" ;; esac
        [ "$name" = "$(printf '%08d' "$expected")" ] || die "activation sequence has a gap"
        validate_file_shape "$entry" 9 "activation $name"
        sequence=$(value "$entry" sequence)
        aid=$(value "$entry" activation_id)
        [ "$(value "$entry" format)" = forge-goal-activation-v2 ] \
            && [ "$sequence" = "$expected" ] \
            && [ "$(value "$entry" nonce)" = "$NONCE" ] \
            && [ "$(value "$entry" objective_hash)" = "$OBJECTIVE" ] \
            && [ -n "$aid" ] \
            && [ -n "$(value "$entry" activation_host)" ] \
            && [ -n "$(value "$entry" activated_at)" ] \
            && [ -n "$(value "$entry" workflow_command)" ] \
            && [ -n "$(value "$entry" state_sha256)" ] \
            || die "activation $name is malformed"
        case "$seen" in *"|$aid|"*) die "activation id is duplicated" ;; esac
        seen="${seen}${aid}|"
        count=$expected
        expected=$((expected + 1))
    done < <(find "$ACTIVATIONS" -mindepth 1 -maxdepth 1 -print 2>/dev/null | LC_ALL=C sort)
    ACTIVATION_RECORD_COUNT=$count
}

validate_turns() {
    local expected=1 entry name count=0 sequence key seen="|"
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        name=$(basename "$entry")
        case "$name" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "invalid turn entry: $name" ;; esac
        [ "$name" = "$(printf '%08d' "$expected")" ] || die "turn sequence has a gap"
        validate_file_shape "$entry" 12 "turn $name"
        sequence=$(value "$entry" sequence)
        key=$(value "$entry" turn_key)
        [ "$(value "$entry" format)" = forge-goal-turn-v2 ] \
            && [ "$sequence" = "$expected" ] \
            && [ "$(value "$entry" nonce)" = "$NONCE" ] \
            && [ "$(value "$entry" objective_hash)" = "$OBJECTIVE" ] \
            && [ -n "$(value "$entry" activation_count)" ] \
            && [ -n "$(value "$entry" turn_id)" ] \
            && [ -n "$key" ] \
            && [ -n "$(value "$entry" state_sha256)" ] \
            || die "turn $name is malformed"
        case "$seen" in *"|$key|"*) die "turn identity is duplicated" ;; esac
        seen="${seen}${key}|"
        count=$expected
        expected=$((expected + 1))
    done < <(find "$TURNS" -mindepth 1 -maxdepth 1 -print 2>/dev/null | LC_ALL=C sort)
    TURN_RECORD_COUNT=$count
}

find_turn_key() {
    local entry
    FOUND_TURN=""
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if [ "$(value "$entry" turn_key)" = "$TURN_KEY" ]; then
            FOUND_TURN="$entry"
            return 0
        fi
    done < <(find "$TURNS" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | LC_ALL=C sort)
    return 1
}

publish_exhaustion() {
    local checkpoint_content exhausted_content checkpoint_hash
    checkpoint_content=$(printf 'format=forge-goal-checkpoint-v2\nnonce=%s\nobjective_hash=%s\nturn_count=%s\nturn_ceiling=%s\nworkflow_command=%s\nphase=%s\nnext_step=%s\nstate_sha256=%s\n' \
        "$NONCE" "$OBJECTIVE" "$TURN_RECORD_COUNT" "$TURN_CEILING" "$WORKFLOW" "$PHASE" "$NEXT_STEP" "$(hash_file "$STATE")")
    publish "$CHECKPOINT" "$checkpoint_content" checkpoint
    checkpoint_hash=$(hash_file "$CHECKPOINT")
    exhausted_content=$(printf 'FORGE_GOAL_BUDGET_EXHAUSTED\nformat=forge-goal-exhausted-v2\nnonce=%s\nobjective_hash=%s\nturn_count=%s\nturn_ceiling=%s\ncheckpoint=%s\ncheckpoint_sha256=%s\n' \
        "$NONCE" "$OBJECTIVE" "$TURN_RECORD_COUNT" "$TURN_CEILING" "$CHECKPOINT" "$checkpoint_hash")
    publish "$EXHAUSTED" "$exhausted_content" exhausted-marker
}

validate_exhaustion() {
    [ -e "$CHECKPOINT" ] || [ -L "$CHECKPOINT" ] || [ -e "$EXHAUSTED" ] || [ -L "$EXHAUSTED" ] || return 1
    validate_file_shape "$CHECKPOINT" 9 checkpoint
    validate_file_shape "$EXHAUSTED" 8 exhausted-marker
    [ "$(value "$CHECKPOINT" format)" = forge-goal-checkpoint-v2 ] \
        && [ "$(value "$CHECKPOINT" nonce)" = "$NONCE" ] \
        && [ "$(value "$CHECKPOINT" objective_hash)" = "$OBJECTIVE" ] \
        && [ "$(value "$CHECKPOINT" turn_count)" = "$TURN_RECORD_COUNT" ] \
        && [ "$(value "$CHECKPOINT" turn_ceiling)" = "$TURN_CEILING" ] \
        && [ "$(head -1 "$EXHAUSTED")" = FORGE_GOAL_BUDGET_EXHAUSTED ] \
        && [ "$(value "$EXHAUSTED" format)" = forge-goal-exhausted-v2 ] \
        && [ "$(value "$EXHAUSTED" nonce)" = "$NONCE" ] \
        && [ "$(value "$EXHAUSTED" objective_hash)" = "$OBJECTIVE" ] \
        && [ "$(value "$EXHAUSTED" turn_count)" = "$TURN_RECORD_COUNT" ] \
        && [ "$(value "$EXHAUSTED" turn_ceiling)" = "$TURN_CEILING" ] \
        && [ "$(value "$EXHAUSTED" checkpoint)" = "$CHECKPOINT" ] \
        && [ "$(value "$EXHAUSTED" checkpoint_sha256)" = "$(hash_file "$CHECKPOINT")" ] \
        || die "checkpoint/exhausted binding mismatch"
    return 0
}

ACTION="${1:-}"
[ "$ACTION" = activate ] || [ "$ACTION" = charge ] || die "usage: goal-ledger.sh activate|charge --project PATH --state PATH [--event-json -]"
shift || true
PROJECT=""
STATE=""
EVENT_JSON=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) [ "$#" -ge 2 ] || die "--project requires a path"; PROJECT="$2"; shift 2 ;;
        --state) [ "$#" -ge 2 ] || die "--state requires a path"; STATE="$2"; shift 2 ;;
        --event-json) [ "$#" -ge 2 ] || die "--event-json requires a value"; EVENT_JSON="$2"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$PROJECT" ] && [ -d "$PROJECT" ] && [ ! -L "$PROJECT" ] || die "project root is missing or aliased"
ROOT=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) || die "project is not a Git checkout"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || die "project root cannot be resolved"
[ -n "$STATE" ] && [ -f "$STATE" ] && [ ! -L "$STATE" ] || die "active state is missing or aliased"
COMMON_RAW=$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null) || die "Git common directory is unavailable"
case "$COMMON_RAW" in /*) ;; *) COMMON_RAW="$ROOT/$COMMON_RAW" ;; esac
[ -d "$COMMON_RAW" ] && [ ! -L "$COMMON_RAW" ] || die "Git common directory is missing or aliased"
COMMON=$(cd "$COMMON_RAW" 2>/dev/null && pwd -P) || die "Git common directory cannot be resolved"

NONCE=$(one_state_value '## /goal session' nonce)
OBJECTIVE=$(one_state_value '## /goal session' objective_hash)
ACTIVATION_ID=$(one_state_value '## /goal session' activation_id)
ACTIVATION_HOST=$(one_state_value '## /goal session' activation_host)
ACTIVATED_AT=$(one_state_value '## /goal session' activated_at)
WORKFLOW=$(one_state_value '## /goal session' workflow_command)
STATE_TURN_COUNT=$(one_state_value '## /goal session' turn_count)
TURN_CEILING=$(one_state_value '## /goal session' turn_ceiling)
ACTIVATION_COUNT=$(one_state_value '## /goal session' activation_count)
PHASE=$(one_state_value '## Workflow' Phase)
NEXT_STEP=$(one_state_value '## Workflow' 'Next step')

case "$NONCE" in ????????-????-4???-[89ab]???-????????????) ;; *) die "invalid active nonce" ;; esac
case "$ACTIVATION_ID" in ????????-????-4???-[89ab]???-????????????) ;; *) die "invalid activation id" ;; esac
case "$OBJECTIVE" in ''|*[!A-Za-z0-9._-]*) die "invalid objective hash" ;; esac
case "$ACTIVATION_COUNT" in ''|*[!0-9]*|0) die "invalid activation count" ;; esac
case "$STATE_TURN_COUNT" in ''|*[!0-9]*) die "invalid state turn count" ;; esac
[ "$TURN_CEILING" = "$((TRANCHE * ACTIVATION_COUNT))" ] || die "turn ceiling does not match activation count"

PROJECT_ID=$(printf '%s' "$COMMON" | hash_text)
FORGE_GOALS="$COMMON/forge-goals"
GOAL_ROOT="$FORGE_GOALS/$NONCE"
ACTIVATIONS="$GOAL_ROOT/activations"
TURNS="$GOAL_ROOT/turns"
BINDING="$GOAL_ROOT/binding"
CHECKPOINT="$GOAL_ROOT/checkpoint"
EXHAUSTED="$GOAL_ROOT/exhausted"
LOCK="$FORGE_GOALS/.$NONCE.lock"

ensure_plain_dir "$FORGE_GOALS"
[ ! -L "$GOAL_ROOT" ] || die "goal ledger root is aliased"
if [ ! -e "$GOAL_ROOT" ]; then mkdir "$GOAL_ROOT" 2>/dev/null || die "cannot create goal ledger root"; fi
ensure_plain_dir "$GOAL_ROOT"
ensure_plain_dir "$ACTIVATIONS"
ensure_plain_dir "$TURNS"
acquire_lock

if [ ! -e "$BINDING" ] && [ ! -L "$BINDING" ]; then
    [ "$ACTION" = activate ] || die "goal activation binding is missing"
    BINDING_CONTENT=$(printf 'format=forge-goal-ledger-v2\nproject_id=%s\nnonce=%s\nobjective_hash=%s\nturn_tranche=%s\n' \
        "$PROJECT_ID" "$NONCE" "$OBJECTIVE" "$TRANCHE")
    publish "$BINDING" "$BINDING_CONTENT" binding
fi
validate_binding
validate_activations
validate_turns

if [ "$ACTION" = activate ]; then
    [ "$STATE_TURN_COUNT" -eq "$TURN_RECORD_COUNT" ] || die "state turn count rolled back or advanced beyond ledger"
    if [ "$ACTIVATION_RECORD_COUNT" -eq "$ACTIVATION_COUNT" ]; then
        existing="$ACTIVATIONS/$(printf '%08d' "$ACTIVATION_COUNT")"
        [ "$(value "$existing" activation_id)" = "$ACTIVATION_ID" ] || die "activation count reuses a different activation id"
    elif [ "$ACTIVATION_RECORD_COUNT" -eq "$((ACTIVATION_COUNT - 1))" ]; then
        record=$(printf 'format=forge-goal-activation-v2\nsequence=%s\nnonce=%s\nobjective_hash=%s\nactivation_id=%s\nactivation_host=%s\nactivated_at=%s\nworkflow_command=%s\nstate_sha256=%s\n' \
            "$ACTIVATION_COUNT" "$NONCE" "$OBJECTIVE" "$ACTIVATION_ID" "$ACTIVATION_HOST" "$ACTIVATED_AT" "$WORKFLOW" "$(hash_file "$STATE")")
        publish "$ACTIVATIONS/$(printf '%08d' "$ACTIVATION_COUNT")" "$record" activation
    else
        die "activation count does not extend the ledger monotonically"
    fi
    validate_activations
    [ "$ACTIVATION_RECORD_COUNT" -eq "$ACTIVATION_COUNT" ] || die "activation publication count mismatch"
    if [ "$ACTIVATION_COUNT" -gt 1 ]; then
        [ ! -L "$CHECKPOINT" ] && [ ! -L "$EXHAUSTED" ] || die "derived exhaustion artifact is aliased"
        rm -f "$CHECKPOINT" "$EXHAUSTED"
    fi
    release_lock
    trap - EXIT HUP INT TERM
    exit 0
fi

[ "$EVENT_JSON" = - ] || die "charge requires --event-json -"
INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
    TURN_ID=$(printf '%s' "$INPUT" | jq -r '.turn_id // .hook_turn_id // .assistant_message_id // ""' 2>/dev/null || true)
    SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || printf unknown)
    HOST=$(printf '%s' "$INPUT" | jq -r '.host // .engine // "unknown"' 2>/dev/null || printf unknown)
    if [ -z "$TURN_ID" ]; then
        LAST_MESSAGE=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)
        [ -n "$LAST_MESSAGE" ] && TURN_ID=$(printf '%s\n%s' "$SESSION" "$LAST_MESSAGE" | hash_text)
    fi
else
    TURN_ID=$(printf '%s' "$INPUT" | sed -n 's/.*"turn_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    HOST=$(printf '%s' "$INPUT" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[ -n "$TURN_ID" ] || die "event has no stable turn id"
case "$TURN_ID" in *[!A-Za-z0-9._-]*) TURN_KEY=$(printf '%s' "$TURN_ID" | hash_text) ;; *) TURN_KEY="$TURN_ID" ;; esac
case "$HOST" in claude|codex) ;; *) HOST=unknown ;; esac
[ -n "$SESSION" ] || SESSION=unknown

[ "$ACTIVATION_RECORD_COUNT" -eq "$ACTIVATION_COUNT" ] || die "state activation count does not match ledger"
[ "$STATE_TURN_COUNT" -le "$TURN_RECORD_COUNT" ] || die "state turn count advances beyond ledger"
[ "$((TURN_RECORD_COUNT - STATE_TURN_COUNT))" -le 1 ] || die "state turn count rolled back"
if find_turn_key; then
    [ "$(value "$FOUND_TURN" turn_id)" = "$TURN_ID" ] \
        && [ "$(value "$FOUND_TURN" activation_count)" = "$ACTIVATION_COUNT" ] \
        && [ "$(value "$FOUND_TURN" host)" = "$HOST" ] \
        && [ "$(value "$FOUND_TURN" session_id)" = "$SESSION" ] \
        && [ "$(value "$FOUND_TURN" state_sha256)" = "$(hash_file "$STATE")" ] \
        && [ "$(value "$FOUND_TURN" phase)" = "$PHASE" ] \
        && [ "$(value "$FOUND_TURN" next_step)" = "$NEXT_STEP" ] \
        || die "duplicate turn identity has non-equivalent content"
    release_lock
    trap - EXIT HUP INT TERM
    exit 0
fi
if validate_exhaustion; then
    printf 'FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=%s\n' "$CHECKPOINT" >&2
    release_lock
    trap - EXIT HUP INT TERM
    exit 0
fi
[ "$TURN_RECORD_COUNT" -lt "$TURN_CEILING" ] || die "turn ceiling reached without valid exhaustion checkpoint"

next_sequence=$((TURN_RECORD_COUNT + 1))
turn_record=$(printf 'format=forge-goal-turn-v2\nsequence=%s\nnonce=%s\nobjective_hash=%s\nactivation_count=%s\nturn_id=%s\nturn_key=%s\nhost=%s\nsession_id=%s\nstate_sha256=%s\nphase=%s\nnext_step=%s\n' \
    "$next_sequence" "$NONCE" "$OBJECTIVE" "$ACTIVATION_COUNT" "$TURN_ID" "$TURN_KEY" "$HOST" "$SESSION" "$(hash_file "$STATE")" "$PHASE" "$NEXT_STEP")
publish "$TURNS/$(printf '%08d' "$next_sequence")" "$turn_record" turn
validate_turns
if [ "$TURN_RECORD_COUNT" -eq "$TURN_CEILING" ]; then
    publish_exhaustion
    printf 'FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=%s\n' "$CHECKPOINT" >&2
fi

release_lock
trap - EXIT HUP INT TERM
exit 0
