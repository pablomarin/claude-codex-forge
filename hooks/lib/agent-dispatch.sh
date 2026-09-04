#!/usr/bin/env bash
# Forge v6 stable fresh-agent dispatcher. Deterministic selection; visible degradation.
set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
FORGE_ROOT=$(cd "$SELF_DIR/../.." && pwd -P)
CAPABILITIES_FILE="$FORGE_ROOT/host-capabilities.tsv"
[ -f "$CAPABILITIES_FILE" ] || CAPABILITIES_FILE="$FORGE_ROOT/manifests/host-capabilities.tsv"
FINGERPRINT="$SELF_DIR/candidate-fingerprint.sh"
RENDER_CONFIG="$FORGE_ROOT/bin/render-dispatch-config"
[ -x "$RENDER_CONFIG" ] || RENDER_CONFIG="$FORGE_ROOT/../scripts/render-dispatch-config.sh"
[ -x "$RENDER_CONFIG" ] || RENDER_CONFIG=$(cd "$SELF_DIR/../.." && printf '%s/scripts/render-dispatch-config.sh' "$(pwd -P)")

hash_stream_dispatch() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
hash_file_dispatch() { [ -f "$1" ] && hash_stream_dispatch < "$1" || printf 'MISSING'; }
die_dispatch() { printf 'BLOCKED[%s]: %s\n' "${1:-invariant}" "${2:-dispatcher failure}" >&2; exit 2; }
scalar_dispatch() { case "$2" in *$'\n'*|*$'\r'*) die_dispatch invariant "$1 contains a newline" ;; esac; }
kv_dispatch() { local f="$1" k="$2"; awk -F= -v key="$k" '$1==key {sub(/^[^=]*=/,""); print; exit}' "$f"; }
escape_dispatch() { printf '%s' "$1" | sed 's/%/%25/g; s/\t/%09/g; s/\r/%0D/g; s/\n/%0A/g; s/=/\%3D/g'; }
now_dispatch() { date -u +%Y-%m-%dT%H:%M:%SZ; }
new_id_dispatch() { printf '%s-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "${RANDOM:-0}"; }
new_uuid_dispatch() {
    local hex
    if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr '[:upper:]' '[:lower:]'; return; fi
    hex=$(printf '%s|%s|%s|%s' "$(now_dispatch)" "$$" "${RANDOM:-0}" "$(pwd -P)" | hash_stream_dispatch)
    printf '%s-%s-4%s-8%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "${hex:17:3}" "${hex:20:12}"
}
strict_kv_dispatch() {
    local file="$1" key="$2" count
    count=$(awk -F= -v k="$key" '$1==k {n++} END {print n+0}' "$file")
    [ "$count" -eq 1 ] || die_dispatch invariant "session metadata key $key must occur exactly once"
    kv_dispatch "$file" "$key"
}
safe_session_id_dispatch() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; *) return 0 ;; esac; }
ensure_reserved_review_dir_dispatch() {
    local relative="$1" create="${2:-false}" cursor="$reviews_dir" part old_ifs
    case "$relative" in ''|/*|../*|*/../*|*/..) return 1 ;; esac
    old_ifs=$IFS; IFS=/
    for part in $relative; do
        IFS=$old_ifs
        [ -n "$part" ] && [ "$part" != . ] && [ "$part" != .. ] || return 1
        cursor="$cursor/$part"
        if [ -e "$cursor" ] || [ -L "$cursor" ]; then
            [ -d "$cursor" ] && [ ! -L "$cursor" ] || return 1
        else
            [ "$create" = true ] && mkdir "$cursor" || return 1
        fi
        IFS=/
    done
    IFS=$old_ifs
    printf '%s\n' "$cursor"
}

prepare_session_dispatch() {
    SESSION_FINAL_ID=""; SESSION_META=""; SESSION_STORE=""; SESSION_SNAPSHOT=""; SESSION_SNAPSHOT_HASH=""; SESSION_CANARY_HASH=""; SESSION_SEAT_HASH=""
    [ "$conversation" != ephemeral ] || return 0
    [ "$fallback_policy" = none ] || die_dispatch capability 'multi-turn council transport requires fallback_policy=none'
    if [ "$conversation" = new ]; then
        [ -n "$session_id_output" ] || die_dispatch invariant 'new council transport requires --session-id-output'
        [ ! -L "$session_id_output" ] || die_dispatch invariant 'session id output cannot be a symlink'
        session_output_dir=$(dirname "$session_id_output"); mkdir -p "$session_output_dir"
        session_output_dir=$(cd "$session_output_dir" && pwd -P) || die_dispatch invariant 'cannot canonicalize session id output'
        case "$session_output_dir/$(basename "$session_id_output")" in "$root"/.forge/local/*) ;; *) die_dispatch invariant 'session id output must be under .forge/local' ;; esac
        SESSION_PROVISIONAL_ID=$(new_uuid_dispatch)
        SESSION_STORE=$(ensure_reserved_review_dir_dispatch "session-stores/$invocation_id" true) || die_dispatch invariant 'private council session store path is unsafe'
        umask 077
        ensure_reserved_review_dir_dispatch "session-stores/$invocation_id/home" true >/dev/null || die_dispatch invariant 'cannot create private council session home'
        ensure_reserved_review_dir_dispatch "session-stores/$invocation_id/codex-home" true >/dev/null || die_dispatch invariant 'cannot create private Codex session home'
        chmod 700 "$SESSION_STORE" 2>/dev/null || true
        return 0
    fi
    safe_session_id_dispatch "$session_id" || die_dispatch invariant 'unsafe exact session id'
    ensure_reserved_review_dir_dispatch sessions false >/dev/null || die_dispatch invariant 'private council session metadata path is unsafe'
    SESSION_META="$reviews_dir/sessions/$session_id.meta"
    [ -f "$SESSION_META" ] && [ ! -L "$SESSION_META" ] || die_dispatch invariant 'exact council session metadata is unavailable'
    [ "$(strict_kv_dispatch "$SESSION_META" schema_version)" = 1 ] || die_dispatch invariant 'unsupported council session metadata'
    [ "$(strict_kv_dispatch "$SESSION_META" completed)" = false ] || die_dispatch invariant 'council session is already completed'
    [ "$(strict_kv_dispatch "$SESSION_META" session_id)" = "$session_id" ] || die_dispatch invariant 'session metadata id mismatch'
    [ "$(strict_kv_dispatch "$SESSION_META" engine)" = "$first" ] || die_dispatch invariant 'cross-engine council resume rejected'
    [ "$(strict_kv_dispatch "$SESSION_META" role)" = "$role" ] || die_dispatch invariant 'cross-role council resume rejected'
    [ "$(strict_kv_dispatch "$SESSION_META" seat_id)" = "$seat_id" ] || die_dispatch invariant 'cross-seat council resume rejected'
    [ "$(strict_kv_dispatch "$SESSION_META" question_hash)" = "$question_hash" ] || die_dispatch invariant 'council resume question mismatch'
    [ "$(strict_kv_dispatch "$SESSION_META" active_host)" = "$active_host" ] || die_dispatch invariant 'council resume host mismatch'
    [ "$(strict_kv_dispatch "$SESSION_META" artifact_hash)" = "$artifact_hash" ] || die_dispatch artifact 'council resume candidate mismatch'
    [ "$(strict_kv_dispatch "$SESSION_META" worktree_identity)" = "$worktree_identity" ] || die_dispatch invariant 'council resume worktree mismatch'
    [ "$(strict_kv_dispatch "$SESSION_META" qualification_revision)" = "$qualification_revision" ] || die_dispatch capability 'council resume qualification changed'
    store_id=$(strict_kv_dispatch "$SESSION_META" store_id); safe_session_id_dispatch "$store_id" || die_dispatch invariant 'unsafe council session store id'
    SESSION_STORE=$(ensure_reserved_review_dir_dispatch "session-stores/$store_id" false) || die_dispatch invariant 'private council session store is unavailable'
    SESSION_SNAPSHOT=$(strict_kv_dispatch "$SESSION_META" snapshot_path); [ -d "$SESSION_SNAPSHOT" ] && [ ! -L "$SESSION_SNAPSHOT" ] || die_dispatch artifact 'bound council snapshot is unavailable'
    SESSION_SNAPSHOT_HASH=$(strict_kv_dispatch "$SESSION_META" snapshot_manifest_hash)
    SESSION_CANARY_HASH=$(strict_kv_dispatch "$SESSION_META" canary_hash); SESSION_SEAT_HASH=$(strict_kv_dispatch "$SESSION_META" seat_hash)
    SESSION_FINAL_ID="$session_id"
}

write_session_metadata_dispatch() {
    local snapshot_hash meta_dir tmp
    SESSION_FINAL_ID="$ATTEMPT_SESSION_ID"; safe_session_id_dispatch "$SESSION_FINAL_ID" || return 2
    snapshot_hash=$(hash_file_dispatch "$ATTEMPT_SNAPSHOT_BEFORE")
    meta_dir=$(ensure_reserved_review_dir_dispatch sessions true) || return 2; chmod 700 "$meta_dir" 2>/dev/null || true
    SESSION_META="$meta_dir/$SESSION_FINAL_ID.meta"; [ ! -e "$SESSION_META" ] && [ ! -L "$SESSION_META" ] || return 2
    tmp="$SESSION_META.tmp.$$"; umask 077
    {
      printf 'schema_version=1\ncompleted=false\nsession_id=%s\nengine=%s\nrole=%s\nseat_id=%s\nquestion_hash=%s\nactive_host=%s\nartifact_hash=%s\nworktree_identity=%s\nturn_prompt_hash=%s\nconfig_hash=%s\ncanary_hash=%s\nseat_hash=%s\nqualification_revision=%s\nstore_id=%s\nsnapshot_path=%s\nsnapshot_manifest_hash=%s\n' \
        "$SESSION_FINAL_ID" "$actual" "$role" "$seat_id" "$question_hash" "$active_host" "$artifact_hash" "$worktree_identity" "$prompt_hash" "$ATTEMPT_CONFIG_HASH" "$ATTEMPT_CANARY_HASH" "$ATTEMPT_SEAT_HASH" "$qualification_revision" "$invocation_id" "$ATTEMPT_SNAPSHOT" "$snapshot_hash"
    } > "$tmp" || return 2
    chmod 600 "$tmp" 2>/dev/null || true; mv "$tmp" "$SESSION_META" || return 2
    output_tmp="$meta_dir/$SESSION_FINAL_ID.session-id.$$"; printf '%s\n' "$SESSION_FINAL_ID" > "$output_tmp" || return 2; chmod 600 "$output_tmp" 2>/dev/null || true
    publish_owned_review_file_dispatch "$output_tmp" "$session_id_output" 'session id output'; rm -f "$output_tmp"
}

complete_session_dispatch() {
    local tmp
    [ "$conversation" = resume ] || return 0
    tmp="$SESSION_META.tmp.$$"; awk -F= '$1=="completed" {print "completed=true"; next} {print}' "$SESSION_META" > "$tmp" || return 2
    chmod 600 "$tmp" 2>/dev/null || true; mv "$tmp" "$SESSION_META" || return 2
    case "$SESSION_STORE" in "$reviews_dir"/session-stores/*) ;; *) return 2 ;; esac
    ensure_reserved_review_dir_dispatch "session-stores/$(basename "$SESSION_STORE")" false >/dev/null || return 2
    find -P "$SESSION_STORE" -depth -mindepth 1 -delete 2>/dev/null || return 2
    rmdir "$SESSION_STORE" 2>/dev/null || return 2
}

write_early_receipt() {
    local class="$1" reason="$2"
    mkdir -p "$reviews_dir"
    receipt="$reviews_dir/$invocation_id.receipt"
    {
      printf 'schema_version=1\ninvocation_id=%s\ntimestamp=%s\nmain_host=%s\nrequested_engine=%s\nfirst_attempted_engine=none\nactual_engine=none\nfallback=false\nfallback_reason=%s\nattempted_engines=none\nrole=%s\nprofile=%s\nreview_iteration=%s\nfresh_process=false\nsemantic_verdict=BLOCKED\nmax_severity=NONE\nblocked_class=%s\nresult_schema_version=none\n' \
        "$invocation_id" "$(now_dispatch)" "${active_host:-UNBOUND}" "${engine:-UNBOUND}" "$(escape_dispatch "$reason")" "${role:-UNBOUND}" "${profile:-UNBOUND}" "${review_iteration:-none}" "$class"
    } > "$receipt"
}

validate_envelope_dispatch() {
    # Sets RESULT_*; schema/contradictions are dispatcher-observed engine failures.
    local file="$1" schema verdict severity blocked findings bad finding_severity
    RESULT_CLASS=engine; RESULT_REASON=malformed-result; RESULT_VERDICT=BLOCKED; RESULT_SEVERITY=NONE; RESULT_FINDINGS_DIGEST=MISSING; RESULT_SCHEMA=none
    [ -s "$file" ] || { RESULT_REASON=empty-result; return 1; }
    schema=$(kv_dispatch "$file" schema_version); verdict=$(kv_dispatch "$file" verdict); severity=$(kv_dispatch "$file" max_severity); blocked=$(kv_dispatch "$file" blocked_class)
    [ "$schema" = 1 ] || return 1
    case "$verdict" in CLEAN|FINDINGS|BLOCKED) ;; *) return 1 ;; esac
    case "$severity" in NONE|P0|P1|P2|P3) ;; *) return 1 ;; esac
    case "$blocked" in none|engine|capability|artifact|authorization|invariant) ;; *) return 1 ;; esac
    bad=false; findings=$(awk -F= '$1=="finding" {sub(/^[^=]*=/,""); print}' "$file")
    while IFS= read -r finding; do
      [ -n "$finding" ] || continue; finding_severity=$(printf '%s' "$finding" | awk -F'|' '{print $2}')
      case "$finding_severity" in P0|P1|P2|P3) ;; *) bad=true ;; esac
    done <<EOF
$findings
EOF
    [ "$bad" = false ] || return 1
    case "$verdict" in
      CLEAN)
        [ "$blocked" = none ] || return 1
        case "$severity" in NONE|P3) ;; *) return 1 ;; esac
        printf '%s\n' "$findings" | grep -Eq '\|(P0|P1|P2)\|' && return 1
        ;;
      FINDINGS)
        [ "$blocked" = none ] || return 1; [ -n "$findings" ] || return 1
        case "$severity" in P0|P1|P2|P3) ;; *) return 1 ;; esac
        ;;
      BLOCKED)
        [ "$blocked" != none ] || return 1; [ -z "$findings" ] || return 1
        ;;
    esac
    RESULT_SCHEMA=1; RESULT_VERDICT="$verdict"; RESULT_SEVERITY="$severity"; RESULT_CLASS="$blocked"; RESULT_REASON=semantic-result
    RESULT_FINDINGS_DIGEST=$(printf '%s' "$findings" | hash_stream_dispatch)
    return 0
}

observe_claude_identity_dispatch() {
    local source="$1" requested="$2" row
    OBSERVED_CLAUDE_PROVIDER=""; OBSERVED_CLAUDE_MODEL=""
    command -v jq >/dev/null 2>&1 || return 1
    row=$(jq -r --arg requested "$requested" '
      [(.modelUsage // {} | to_entries[]
        | . + {model: (.value.canonicalModel // .key)}
        | select(if $requested == "opus" then (.model | test("(^|-)opus($|-)")) else (.model == $requested or .key == $requested) end))]
      | if length == 1 then [.[0].value.provider, .[0].model] | @tsv else empty end
    ' "$source" 2>/dev/null || true)
    [ -n "$row" ] || return 1
    OBSERVED_CLAUDE_PROVIDER=${row%%$'\t'*}; OBSERVED_CLAUDE_MODEL=${row#*$'\t'}
    [ -n "$OBSERVED_CLAUDE_PROVIDER" ] && [ -n "$OBSERVED_CLAUDE_MODEL" ]
}

claude_identity_matches_dispatch() {
    local expected_provider="$1" expected_model="$2" actual_provider="$3" actual_model="$4" provider_match=false
    [ "$actual_provider" = "$expected_provider" ] && provider_match=true
    [ "$expected_provider:$actual_provider" != anthropic:firstParty ] || provider_match=true
    [ "$provider_match" = true ] || return 1
    case "$expected_model:$actual_model" in "$expected_model:$expected_model"|opus:claude-opus-*) return 0 ;; *) return 1 ;; esac
}

observation_matches_dispatch() {
    local file="$1" key="$2" expected="$3"
    awk -F= -v key="$key" -v expected="$expected" '
      $1==key { count++; value=substr($0, length(key)+2); if (value != expected) bad=1 }
      END { exit !(count >= 1 && !bad) }
    ' "$file"
}

capability_row_dispatch() {
    local selected="$1" role_name="$2" capability=model-certifying
    [ "$role_name" = council-advisor ] && capability=model-council-advisor
    [ "$role_name" = council-chair ] && capability=model-council-chair
    awk -F'\t' -v c="$capability" -v h="$selected" '$1==c && $2==h {print; exit}' "$CAPABILITIES_FILE"
}

run_with_timeout_dispatch() {
    local seconds="$1" stdout="$2" stderr="$3" working_dir="$4"; shift 4
    (cd "$working_dir" && exec "$@") > "$stdout" 2> "$stderr" & child=$!
    elapsed=0
    while kill -0 "$child" 2>/dev/null; do
      if [ "$elapsed" -ge "$((seconds * 10))" ]; then
        pkill -TERM -P "$child" 2>/dev/null || true; kill -TERM "$child" 2>/dev/null || true; sleep 0.2
        pkill -KILL -P "$child" 2>/dev/null || true; kill -KILL "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true
        return 124
      fi
      sleep 0.1; elapsed=$((elapsed + 1))
    done
    wait "$child"; return $?
}

validate_owned_review_path_dispatch() {
    local requested="$1" label="$2" canonical cursor relative parent_relative part logical_root logical_reviews
    [ -n "$requested" ] || die_dispatch invariant "$label is required"
    logical_root=$(git rev-parse --show-toplevel 2>/dev/null) || die_dispatch invariant 'Git worktree required'; logical_reviews="$logical_root/.forge/local/reviews"
    if [ -d "$(dirname "$requested")" ] && [ ! -L "$(dirname "$requested")" ]; then canonical="$(cd "$(dirname "$requested")" && pwd -P)/$(basename "$requested")"
    else case "$requested" in "$logical_reviews"/*) canonical="$reviews_dir/${requested#"$logical_reviews"/}" ;; /*) canonical="$requested" ;; *) canonical="$(pwd -P)/$requested" ;; esac; fi
    case "$canonical" in *$'\n'*|*$'\r'*|*/../*|*/./*) die_dispatch invariant "$label contains an unsafe path component" ;; esac
    case "$canonical" in "$reviews_dir"/*) ;; *) die_dispatch invariant "$label must stay under .forge/local/reviews" ;; esac
    relative=${canonical#"$reviews_dir"/}
    case "$relative" in sessions/*|session-stores/*|*.receipt|*.candidate|*.recheck|*.manifest) die_dispatch invariant "$label targets a dispatcher-reserved path" ;; esac
    [ -d "$reviews_dir" ] && [ ! -L "$reviews_dir" ] || die_dispatch invariant 'review storage must be a no-follow directory'
    cursor="$reviews_dir"; parent_relative=${relative%/*}; [ "$parent_relative" != "$relative" ] || parent_relative=""
    while [ -n "$parent_relative" ]; do
      case "$parent_relative" in */*) part=${parent_relative%%/*}; parent_relative=${parent_relative#*/} ;; *) part=$parent_relative; parent_relative="" ;; esac
      [ -n "$part" ] || continue; cursor="$cursor/$part"
      if [ -e "$cursor" ] || [ -L "$cursor" ]; then [ -d "$cursor" ] && [ ! -L "$cursor" ] || die_dispatch invariant "$label ancestor must be a no-follow directory"
      else mkdir "$cursor" || die_dispatch invariant "cannot create $label directory"; fi
    done
    [ ! -e "$canonical" ] && [ ! -L "$canonical" ] || die_dispatch invariant "$label already exists or is linked"
    umask 077; (set -C; : > "$canonical") 2>/dev/null || die_dispatch invariant "$label cannot be reserved without clobbering"
    VALID_REVIEW_PATH="$canonical"
}

publish_owned_review_file_dispatch() {
    local source="$1" destination="$2" label="$3" relative parent_relative cursor part temporary physical_parent
    [ -f "$source" ] && [ ! -L "$source" ] || die_dispatch artifact "$label source must be a no-follow regular file"
    case "$destination" in "$reviews_dir"/*) ;; *) die_dispatch invariant "$label escaped review storage" ;; esac
    relative=${destination#"$reviews_dir"/}; parent_relative=${relative%/*}; [ "$parent_relative" != "$relative" ] || parent_relative=""
    cursor="$reviews_dir"
    while [ -n "$parent_relative" ]; do
      case "$parent_relative" in */*) part=${parent_relative%%/*}; parent_relative=${parent_relative#*/} ;; *) part=$parent_relative; parent_relative="" ;; esac
      [ -n "$part" ] || continue; cursor="$cursor/$part"
      [ -d "$cursor" ] && [ ! -L "$cursor" ] || die_dispatch invariant "$label ancestor changed before publication"
    done
    physical_parent=$(cd "$(dirname "$destination")" 2>/dev/null && pwd -P) || die_dispatch invariant "$label parent cannot be resolved"
    [ "$physical_parent/$(basename "$destination")" = "$destination" ] || die_dispatch invariant "$label parent changed before publication"
    temporary="$destination.publish.$invocation_id"
    [ ! -e "$temporary" ] && [ ! -L "$temporary" ] || die_dispatch invariant "$label publication temporary already exists"
    umask 077; (set -C; : > "$temporary") 2>/dev/null || die_dispatch invariant "$label publication temporary cannot be reserved"
    cp "$source" "$temporary" || { rm -f "$temporary"; die_dispatch artifact "$label publication copy failed"; }
    [ -f "$temporary" ] && [ ! -L "$temporary" ] || { rm -f "$temporary"; die_dispatch invariant "$label publication temporary changed"; }
    [ -d "$(dirname "$destination")" ] && [ ! -L "$(dirname "$destination")" ] || { rm -f "$temporary"; die_dispatch invariant "$label parent changed during publication"; }
    physical_parent=$(cd "$(dirname "$destination")" 2>/dev/null && pwd -P) || { rm -f "$temporary"; die_dispatch invariant "$label parent cannot be revalidated"; }
    [ "$physical_parent/$(basename "$destination")" = "$destination" ] || { rm -f "$temporary"; die_dispatch invariant "$label parent changed during publication"; }
    mv -f "$temporary" "$destination" || { rm -f "$temporary"; die_dispatch invariant "$label atomic publication failed"; }
    [ -f "$destination" ] && [ ! -L "$destination" ] || die_dispatch invariant "$label publication is not a regular file"
}

snapshot_manifest_dispatch() {
    local candidate="$1" destination="$2" file rel kind content
    : > "$destination"
    while IFS= read -r -d '' file; do
      rel=${file#"$candidate"/}; case "$rel" in .git|.git/*) continue ;; esac
      if [ -L "$file" ]; then kind=link; content=$(printf '%s' "$(readlink "$file")" | hash_stream_dispatch)
      elif [ -f "$file" ]; then kind=file; content=$(hash_file_dispatch "$file")
      elif [ -d "$file" ]; then continue
      else kind=special; content=REJECTED
      fi
      printf '%s\t%s\t%s\n' "$(printf '%s' "$rel" | hash_stream_dispatch)" "$kind" "$content" >> "$destination"
    done < <(find -P "$candidate" -mindepth 1 -print0 2>/dev/null)
    LC_ALL=C sort "$destination" -o "$destination"
}

reproduction_protected_unchanged_dispatch() {
    [ "$(hash_file_dispatch "$root/.forge/local/state.md")" = "$REPRO_PROTECTED_STATE_HASH" ] || { ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-protected-state-mutated; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; return 2; }
    if [ -n "$REPRO_PROTECTED_AUTH_FILE" ]; then
      [ -f "$REPRO_PROTECTED_AUTH_FILE" ] && [ ! -L "$REPRO_PROTECTED_AUTH_FILE" ] && [ "$(hash_file_dispatch "$REPRO_PROTECTED_AUTH_FILE")" = "$REPRO_PROTECTED_AUTH_HASH" ] \
        || { ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-protected-auth-mutated; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; return 2; }
    fi
}

run_reproduction_pair_dispatch() {
    local selected="$1" attempt_number="$2" check_rc output_hash primary_ok=false control_ok=false
    REPRO_ENGINE_USED=true
    REPRO_CHECK_KIND=primary; REPRO_PROGRAM="$REPRO_PRIMARY_PROGRAM"; REPRO_ARGS=("${REPRO_PRIMARY_ARGS[@]}")
    attempt_engine_dispatch "$selected" "$attempt_number"; check_rc=$?
    reproduction_protected_unchanged_dispatch || return 2
    [ "$check_rc" -eq 0 ] || return "$check_rc"
    output_hash=$(hash_file_dispatch "$ATTEMPT_REPRO_STDOUT")
    [ "$ATTEMPT_REPRO_EXIT" = "$REPRO_PRIMARY_EXPECTED_EXIT" ] && [ "$output_hash" = "$REPRO_PRIMARY_EXPECTED_HASH" ] && primary_ok=true
    REPRO_PRIMARY_HASH=$(printf '%s\n' "$REPRO_PRIMARY_PROGRAM" "${REPRO_PRIMARY_ARGS[@]}" "$ATTEMPT_REPRO_EXIT" "$output_hash" "$(hash_file_dispatch "$ATTEMPT_REPRO_STDERR")" | hash_stream_dispatch)

    REPRO_CHECK_KIND=control; REPRO_PROGRAM="$REPRO_CONTROL_PROGRAM"; REPRO_ARGS=("${REPRO_CONTROL_ARGS[@]}")
    attempt_engine_dispatch "$selected" "$((attempt_number + 1))"; check_rc=$?
    reproduction_protected_unchanged_dispatch || return 2
    [ "$check_rc" -eq 0 ] || return "$check_rc"
    output_hash=$(hash_file_dispatch "$ATTEMPT_REPRO_STDOUT")
    [ "$ATTEMPT_REPRO_EXIT" = "$REPRO_CONTROL_EXPECTED_EXIT" ] && [ "$output_hash" = "$REPRO_CONTROL_EXPECTED_HASH" ] && control_ok=true
    REPRO_CONTROL_HASH=$(printf '%s\n' "$REPRO_CONTROL_PROGRAM" "${REPRO_CONTROL_ARGS[@]}" "$ATTEMPT_REPRO_EXIT" "$output_hash" "$(hash_file_dispatch "$ATTEMPT_REPRO_STDERR")" | hash_stream_dispatch)
    if [ "$primary_ok" = true ] && [ "$control_ok" = true ]; then REPRODUCTION_STATUS=REPRODUCED
    elif [ "$primary_ok" = false ] && [ "$control_ok" = true ]; then REPRODUCTION_STATUS=FAILED
    elif [ "$primary_ok" = true ]; then REPRODUCTION_STATUS=PARTIAL
    else REPRODUCTION_STATUS=UNVERIFIED; fi
    ATTEMPT_CLASS=none; ATTEMPT_REASON=dispatcher-owned-reproduction; ATTEMPT_VERDICT=CLEAN; ATTEMPT_SEVERITY=NONE; ATTEMPT_SCHEMA=1; ATTEMPT_EXIT=0
    return 0
}

run_reproduction_dispatch() {
    local selected="$1" attempt_number="$2" hypothesis key count arg
    REPRO_ENGINE_USED=false; REPRO_PRIMARY_ARGS=(); REPRO_CONTROL_ARGS=()
    for key in schema_version hypothesis primary_program primary_expected_exit primary_expected_output_hash; do
      count=$(awk -F= -v k="$key" '$1==k {n++} END {print n+0}' "$prompt_file"); [ "$count" -eq 1 ] || { REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-spec-incomplete; return 0; }
    done
    [ "$(kv_dispatch "$prompt_file" schema_version)" = 1 ] || { REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-schema-invalid; return 0; }
    hypothesis=$(kv_dispatch "$prompt_file" hypothesis); REPRO_HYPOTHESIS_HASH=$(printf '%s' "$hypothesis" | hash_stream_dispatch)
    REPRO_PRIMARY_PROGRAM=$(kv_dispatch "$prompt_file" primary_program); REPRO_PRIMARY_EXPECTED_EXIT=$(kv_dispatch "$prompt_file" primary_expected_exit); REPRO_PRIMARY_EXPECTED_HASH=$(kv_dispatch "$prompt_file" primary_expected_output_hash)
    while IFS= read -r arg; do scalar_dispatch primary_arg "$arg"; REPRO_PRIMARY_ARGS+=("$arg"); done < <(awk -F= '$1=="primary_arg" {sub(/^[^=]*=/,""); print}' "$prompt_file")
    case "$REPRO_PRIMARY_PROGRAM" in ''|/*|../*|*/../*) ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-program-escape; return 2 ;; esac
    case "$REPRO_PRIMARY_EXPECTED_EXIT" in ''|*[!0-9]*) REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0 ;; esac
    case "$REPRO_PRIMARY_EXPECTED_HASH" in *[!0-9a-fA-F]*|'') REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0 ;; esac
    [ "${#REPRO_PRIMARY_EXPECTED_HASH}" -eq 64 ] || { REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0; }
    for key in control_program control_expected_exit control_expected_output_hash; do
      count=$(awk -F= -v k="$key" '$1==k {n++} END {print n+0}' "$prompt_file"); [ "$count" -eq 1 ] || { REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-control-missing; return 0; }
    done
    REPRO_CONTROL_PROGRAM=$(kv_dispatch "$prompt_file" control_program); REPRO_CONTROL_EXPECTED_EXIT=$(kv_dispatch "$prompt_file" control_expected_exit); REPRO_CONTROL_EXPECTED_HASH=$(kv_dispatch "$prompt_file" control_expected_output_hash)
    while IFS= read -r arg; do scalar_dispatch control_arg "$arg"; REPRO_CONTROL_ARGS+=("$arg"); done < <(awk -F= '$1=="control_arg" {sub(/^[^=]*=/,""); print}' "$prompt_file")
    case "$REPRO_CONTROL_PROGRAM" in ''|/*|../*|*/../*) ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-program-escape; return 2 ;; esac
    case "$REPRO_CONTROL_EXPECTED_EXIT" in ''|*[!0-9]*) REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0 ;; esac
    case "$REPRO_CONTROL_EXPECTED_HASH" in *[!0-9a-fA-F]*|'') REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0 ;; esac
    [ "${#REPRO_CONTROL_EXPECTED_HASH}" -eq 64 ] || { REPRODUCTION_STATUS=UNVERIFIED; ATTEMPT_REASON=reproduction-expectation-invalid; return 0; }
    run_reproduction_pair_dispatch "$selected" "$attempt_number"
}

attempt_full_investigation_dispatch() {
    local selected="$1" binary="$2" provider="$3" model="$4" effort="$5" scratch="$6"
    local raw="$scratch/raw.out" stderr_file="$scratch/stderr.log" bound_output="$scratch/bound.out" rc extracted observed observed_provider identity_match=false
    local -a engine_args
    ATTEMPT_CONFIG_HASH=$(printf '%s|%s|%s|host-managed-full-agent-v1' "$selected" "$root" "$qualification_revision" | hash_stream_dispatch)
    ATTEMPT_CANARY_HASH=NOT_APPLICABLE
    ATTEMPT_SEAT_HASH=$(printf '%s|%s|%s|%s' "$selected" "$role" "$seat_id" "$question_hash" | hash_stream_dispatch)
    ATTEMPT_SNAPSHOT="$root"; ATTEMPT_SNAPSHOT_BEFORE=""; ATTEMPT_SESSION_ID=none
    {
      printf 'You are a fresh full-capability %s investigation agent in the real project worktree %s. Use the normal user and project configuration, shared Forge state and memory, installed tools, MCP servers, network, databases, and APIs available to this host. Forge adds no tool, sandbox, configuration, or write restriction for this investigation. You may inspect and edit the worktree as needed. Return ONLY the Forge line envelope below.\n' "$selected" "$root"
      cat "$prompt_file"
      printf '\nRequired envelope:\nschema_version=1\nverdict=CLEAN|FINDINGS|BLOCKED\nmax_severity=NONE|P0|P1|P2|P3\nblocked_class=none|engine|capability|artifact|authorization|invariant\n'
    } > "$scratch/prompt.txt"
    if [ "$selected" = claude ]; then
      engine_args=(-p --settings '{"fastMode":true}' --permission-mode auto --model "$model" --effort "$effort" --output-format json --no-session-persistence "$(cat "$scratch/prompt.txt")")
      run_with_timeout_dispatch "$timeout_seconds" "$raw" "$stderr_file" "$root" "$binary" "${engine_args[@]}"
      rc=$?; cp "$raw" "$bound_output"
    else
      engine_args=(-a on-request --search exec -C "$root" --sandbox danger-full-access -m "$model" -c "model_reasoning_effort=$effort" -c service_tier=fast --output-last-message "$bound_output" --ephemeral "$(cat "$scratch/prompt.txt")")
      run_with_timeout_dispatch "$timeout_seconds" "$raw" "$stderr_file" "$root" "$binary" "${engine_args[@]}"
      rc=$?
    fi
    ATTEMPT_EXIT="$rc"
    if [ "$rc" -eq 124 ]; then ATTEMPT_REASON=timeout; return 1; fi
    if [ "$rc" -ne 0 ]; then ATTEMPT_REASON=process-exit-$rc; return 1; fi
    if [ -s "$bound_output" ] && [ "$(head -c 1 "$bound_output")" = '{' ] && command -v jq >/dev/null 2>&1; then
      extracted=$(jq -r '.result // empty' "$bound_output" 2>/dev/null || true)
      if [ -n "$extracted" ]; then printf '%s\n' "$extracted" > "$scratch/envelope.out"; bound_output="$scratch/envelope.out"; fi
      if [ "$selected" = claude ]; then
        if observe_claude_identity_dispatch "$scratch/raw.out" "$model"; then
          ATTEMPT_ACTUAL_MODEL="$OBSERVED_CLAUDE_MODEL"; ATTEMPT_ACTUAL_PROVIDER="$OBSERVED_CLAUDE_PROVIDER"
        fi
      fi
    fi
    if [ "$selected" = claude ]; then
      [ "$ATTEMPT_ACTUAL_PROVIDER" != UNOBSERVABLE ] && [ "$ATTEMPT_ACTUAL_MODEL" != UNOBSERVABLE ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=observable-identity-missing; return 1; }
      claude_identity_matches_dispatch "$provider" "$model" "$ATTEMPT_ACTUAL_PROVIDER" "$ATTEMPT_ACTUAL_MODEL" && identity_match=true
      [ "$identity_match" = true ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=observable-identity-mismatch; return 1; }
    fi
    if ! validate_envelope_dispatch "$bound_output"; then ATTEMPT_REASON="$RESULT_REASON"; ATTEMPT_CLASS=engine; return 1; fi
    ATTEMPT_CLASS="$RESULT_CLASS"; ATTEMPT_REASON="$RESULT_REASON"; ATTEMPT_VERDICT="$RESULT_VERDICT"; ATTEMPT_SEVERITY="$RESULT_SEVERITY"; ATTEMPT_SCHEMA="$RESULT_SCHEMA"; ATTEMPT_FINDINGS_DIGEST="$RESULT_FINDINGS_DIGEST"; ATTEMPT_OUTPUT="$bound_output"
    case "$ATTEMPT_VERDICT:$ATTEMPT_CLASS" in CLEAN:none|FINDINGS:none) return 0 ;; BLOCKED:engine|BLOCKED:capability) return 1 ;; BLOCKED:artifact|BLOCKED:authorization|BLOCKED:invariant) return 2 ;; *) ATTEMPT_CLASS=engine; ATTEMPT_REASON=contradictory-result; return 1 ;; esac
}

attempt_engine_dispatch() {
    local selected="$1" attempt_number="$2" binary row provider model effort mechanism observable minout qualified fallback_col help missing flag
    local scratch raw stderr_file prompt bound_output rc snapshot primary config_hash computed_config_hash profile_mode extracted observed observed_provider sandbox tools snapshot_check snapshot_after snapshot_ref snapshot_head captured_thread attempt_fingerprint auth_source executable parent review_patch review_paths
    ATTEMPT_ENGINE="$selected"; ATTEMPT_CLASS=engine; ATTEMPT_REASON=binary-unavailable; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; ATTEMPT_SCHEMA=none; ATTEMPT_FINDINGS_DIGEST=MISSING
    ATTEMPT_REQUESTED_PROVIDER=UNQUALIFIED; ATTEMPT_REQUESTED_MODEL=UNQUALIFIED; ATTEMPT_REQUESTED_EFFORT=UNQUALIFIED
    ATTEMPT_ACTUAL_PROVIDER=UNOBSERVABLE; ATTEMPT_ACTUAL_MODEL=UNOBSERVABLE; ATTEMPT_ACTUAL_EFFORT=UNOBSERVABLE; ATTEMPT_CONFIG_HASH=MISSING; ATTEMPT_SESSION_ID=none; ATTEMPT_EXIT=127
    if [ "${FORGE_DISPATCH_TEST_MODE:-0}" = 1 ] && [ "${FORGE_TEST_DISABLE_ENGINE:-}" = "$selected" ]; then return 1; fi
    if [ "${FORGE_DISPATCH_TEST_MODE:-0}" = 1 ] && [ "${FORGE_TEST_DISABLE_CAPABILITY:-}" = "$selected" ]; then ATTEMPT_CLASS=capability; ATTEMPT_REASON=missing-required-capability; return 1; fi
    binary=$(command -v "$selected" 2>/dev/null || true); [ -n "$binary" ] || return 1
    row=$(capability_row_dispatch "$selected" "$role"); [ -n "$row" ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=unqualified-role; return 1; }
    IFS=$'\t' read -r _ _ _ _ _ provider model effort mechanism observable minout qualified fallback_col <<EOF
$row
EOF
    ATTEMPT_REQUESTED_PROVIDER="$provider"; ATTEMPT_REQUESTED_MODEL="$model"; ATTEMPT_REQUESTED_EFFORT="$effort"
    if [ "${FORGE_DISPATCH_TEST_MODE:-0}" != 1 ]; then
      help=$($binary --help 2>&1 || true); [ "$selected" != codex ] || help="$help $($binary exec --help 2>&1 || true)"
      if [ "$selected" = claude ]; then
        if [ "$role" = investigation ]; then required='-p --settings --permission-mode --model --effort --output-format --no-session-persistence'
        else required='-p --safe-mode --strict-mcp-config --mcp-config --settings --setting-sources --tools --permission-mode --add-dir --model --effort --output-format'; fi
        case "$conversation" in ephemeral) required="$required --no-session-persistence" ;; new) required="$required --session-id" ;; resume) required="$required --resume" ;; esac
      else
        if [ "$role" = investigation ]; then required='-a --search exec --sandbox --output-last-message -C -m -c --ephemeral'
        else required='-a exec --sandbox --add-dir --ignore-user-config --ignore-rules --disable --output-last-message -C -m -c'; fi
        case "$conversation" in ephemeral) required="$required --ephemeral" ;; new) required="$required --json" ;; resume) required="$required resume --json" ;; esac
      fi
      missing=""; for flag in $required; do case "$help" in *"$flag"*) ;; *) missing="$missing,$flag" ;; esac; done
      [ -z "$missing" ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON="missing-capability${missing}"; return 1; }
    fi
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/forge-dispatch-$selected.XXXXXX") || { ATTEMPT_REASON=scratch-unavailable; return 1; }
    if [ "$role" = investigation ]; then attempt_full_investigation_dispatch "$selected" "$binary" "$provider" "$model" "$effort" "$scratch"; return $?; fi
    "$RENDER_CONFIG" --engine "$selected" --profile "$profile" --output-dir "$scratch" ${readonly_server:+--read-only-server "$readonly_server"} > "$scratch/config.receipt" 2> "$scratch/config.err" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=config-render-failed; return 1; }
    [ "$(awk -F= '$1=="config_hash" {n++} END {print n+0}' "$scratch/config.receipt")" -eq 1 ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=config-receipt-invalid; return 1; }
    config_hash=$(kv_dispatch "$scratch/config.receipt" config_hash)
    computed_config_hash="$(hash_file_dispatch "$scratch/claude-settings.json"):$(hash_file_dispatch "$scratch/mcp.json"):$(hash_file_dispatch "$scratch/codex-overrides.tsv")"
    [ "$config_hash" = "$computed_config_hash" ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=config-receipt-hash-mismatch; return 1; }
    ATTEMPT_CONFIG_HASH="$config_hash"; ATTEMPT_CANARY_HASH=$(printf '%s|%s|%s|fresh-isolation-v1' "$selected" "$config_hash" "$qualification_revision" | hash_stream_dispatch); ATTEMPT_SEAT_HASH=$(printf '%s|%s|%s|%s' "$selected" "$role" "$seat_id" "$question_hash" | hash_stream_dispatch)
    if [ "$conversation" = resume ]; then
      [ "$config_hash" = "$(strict_kv_dispatch "$SESSION_META" config_hash)" ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=resume-config-mismatch; return 2; }
      [ "$ATTEMPT_CANARY_HASH" = "$SESSION_CANARY_HASH" ] || { ATTEMPT_CLASS=invariant; ATTEMPT_REASON=resume-canary-mismatch; return 2; }
      [ "$ATTEMPT_SEAT_HASH" = "$SESSION_SEAT_HASH" ] || { ATTEMPT_CLASS=invariant; ATTEMPT_REASON=resume-seat-mismatch; return 2; }
    fi
    raw="$scratch/raw.out"; stderr_file="$scratch/stderr.log"; bound_output="$scratch/bound.out"; primary="$scratch/primary"
    if [ "$conversation" = resume ]; then
      snapshot="$SESSION_SNAPSHOT"; snapshot_check="$scratch/session-snapshot.manifest"; snapshot_manifest_dispatch "$snapshot" "$snapshot_check"
      [ "$(hash_file_dispatch "$snapshot_check")" = "$SESSION_SNAPSHOT_HASH" ] || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=resume-snapshot-mismatch; return 2; }
    else
      attempt_fingerprint="$reviews_dir/$invocation_id.attempt-$attempt_number.candidate"
      if ! bash "$FINGERPRINT" capture --artifact "$artifact" --workflow-base-sha "$workflow_base_sha" --workflow-base-ref "$workflow_base_ref" --output "$attempt_fingerprint" >/dev/null 2>&1; then ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-capture-failed; return 2; fi
      [ "$(kv_dispatch "$attempt_fingerprint" artifact_hash)" = "$artifact_hash" ] && [ "$(kv_dispatch "$attempt_fingerprint" worktree_identity)" = "$worktree_identity" ] || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-binding-mismatch; return 2; }
      snapshot=$(kv_dispatch "$attempt_fingerprint" snapshot_path); [ -d "$snapshot" ] && [ ! -L "$snapshot" ] || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-snapshot-unavailable; return 2; }
    fi
    ATTEMPT_SNAPSHOT="$snapshot"; ATTEMPT_SNAPSHOT_BEFORE="$scratch/snapshot-before.manifest"; snapshot_manifest_dispatch "$snapshot" "$ATTEMPT_SNAPSHOT_BEFORE"
    snapshot_ref=""; snapshot_head=""
    if [ "$artifact_kind" != file ]; then
      snapshot_ref=$(git -C "$snapshot" rev-parse refs/heads/candidate 2>/dev/null) || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-ref-missing; return 2; }
      snapshot_head=$(git -C "$snapshot" rev-parse HEAD 2>/dev/null) || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-head-missing; return 2; }
    fi
    {
      printf 'forge_canary_hash=%s\nforge_config_hash=%s\nforge_qualification_revision=%s\n' "$ATTEMPT_CANARY_HASH" "$config_hash" "$qualification_revision"
    } > "$primary/.forge-dispatch-canary"
    if [ "${REPRO_MODE:-false}" = true ]; then
      executable="$snapshot/$REPRO_PROGRAM"; parent=$(cd "$(dirname "$executable")" 2>/dev/null && pwd -P) || { ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-program-escape; return 2; }
      case "$parent/$(basename "$executable")" in "$snapshot"/*) ;; *) ATTEMPT_CLASS=authorization; ATTEMPT_REASON=reproduction-program-escape; return 2 ;; esac
      [ -f "$executable" ] && [ ! -L "$executable" ] && [ -x "$executable" ] || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=reproduction-program-not-executable; return 2; }
      REPRO_RUNNER="$primary/.forge-reproduction-runner"; ATTEMPT_REPRO_STDOUT="$primary/.forge-reproduction.stdout"; ATTEMPT_REPRO_STDERR="$primary/.forge-reproduction.stderr"; ATTEMPT_REPRO_EXIT_FILE="$primary/.forge-reproduction.exit"
      {
        printf '#!/usr/bin/env bash\nset +e\ncd -- %q || exit 125\nenv -i PATH=%q FORGE_REPRO_NO_NETWORK=1 %q' "$snapshot" "$PATH" "$executable"
        for arg in "${REPRO_ARGS[@]}"; do printf ' %q' "$arg"; done
        printf ' > %q 2> %q\nrc=$?\nprintf "%%s\\n" "$rc" > %q\nexit 0\n' "$ATTEMPT_REPRO_STDOUT" "$ATTEMPT_REPRO_STDERR" "$ATTEMPT_REPRO_EXIT_FILE"
      } > "$REPRO_RUNNER" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=reproduction-runner-render-failed; return 1; }
      chmod 700 "$REPRO_RUNNER" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=reproduction-runner-render-failed; return 1; }
    fi
    {
      printf 'You are a fresh independent %s reviewer. Your cwd is a clean primary. First read .forge-dispatch-canary there and copy its three exact observation lines into the result. ' "$selected"
      if [ "$artifact_kind" = file ]; then
        printf 'The isolated review root is %s and contains only the requested file artifact. Do not assume repository, PRD, or Git access; if the requested review needs absent context, return BLOCKED with blocked_class=artifact. ' "$snapshot"
      else
        review_patch="$primary/.forge-review.patch"; review_paths="$primary/.forge-review-paths"
        git -C "$snapshot" diff --no-ext-diff --binary "$workflow_base_sha..candidate" > "$review_patch" \
          && git -C "$snapshot" diff --no-ext-diff --name-only "$workflow_base_sha..candidate" > "$review_paths" \
          || { ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-diff-unavailable; return 2; }
        printf 'The logical project root is %s. The dispatcher materialized the exact immutable %s..candidate diff at %s and its changed-path list at %s; read those files and the candidate root. Shell access is intentionally absent. ' "$snapshot" "$workflow_base_sha" "$review_patch" "$review_paths"
      fi
      printf 'Ambient instructions, hooks, plugins, skills, and write-capable MCP are absent by contract.\n'
      if [ "${REPRO_MODE:-false}" = true ]; then
        printf 'This is the dispatcher-owned %s reproduction check. Under the already-qualified no-network workspace boundary, execute the exact dispatcher-owned runner %s once. Do not edit it or synthesize its stdout/exit files.\n' "$REPRO_CHECK_KIND" "$REPRO_RUNNER"
      fi
      cat "$prompt_file"
      printf '\nReturn ONLY newline-delimited fields with no Markdown or surrounding prose. Required envelope:\nschema_version=1\nverdict=CLEAN|FINDINGS|BLOCKED\nmax_severity=NONE|P0|P1|P2|P3\nblocked_class=none|engine|capability|artifact|authorization|invariant\nforge_canary_hash=<observed>\nforge_config_hash=<observed>\nforge_qualification_revision=<observed>\nFor FINDINGS add one line per finding: finding=<sequence>|P0|P1|P2|P3|open|<concise evidence>. BLOCKED must contain no finding lines.\n'
    } > "$scratch/prompt.txt"
    profile_mode=review; [ "$profile" = investigate ] && profile_mode=investigate
    if [ "$selected" = claude ]; then
      tools='Read,Grep,Glob'; [ "$profile" = investigate ] && tools='Read,Write,Edit,Bash,WebSearch,WebFetch'; [ "${REPRO_MODE:-false}" != true ] || tools='Read,Write,Edit,Bash'
      claude_args=(-p --safe-mode --strict-mcp-config --mcp-config "$scratch/mcp.json" --settings "$scratch/claude-settings.json" --setting-sources '' --tools "$tools")
      claude_args+=(--permission-mode dontAsk --add-dir "$snapshot" --model "$model" --effort "$effort" --output-format json)
      case "$conversation" in ephemeral) claude_args+=(--no-session-persistence) ;; new) claude_args+=(--session-id "$SESSION_PROVISIONAL_ID") ;; resume) claude_args+=(--resume "$session_id") ;; esac
      claude_args+=("$(cat "$scratch/prompt.txt")")
      run_with_timeout_dispatch "$timeout_seconds" "$raw" "$stderr_file" "$primary" env -i PATH="$PATH" HOME="${HOME:-}" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" TMPDIR="${TMPDIR:-/tmp}" FORGE_DISPATCH_MODE="$profile_mode" FORGE_CANDIDATE_ROOT="$snapshot" FORGE_REPRO_RUNNER="${REPRO_RUNNER:-}" FORGE_DISPATCH_SESSION_ID="${SESSION_PROVISIONAL_ID:-$session_id}" FORGE_DISPATCH_SEAT_HASH="$ATTEMPT_SEAT_HASH" FORGE_DISPATCH_CONFIG_HASH="$config_hash" FORGE_DISPATCH_CANARY_HASH="$ATTEMPT_CANARY_HASH" FORGE_DISPATCH_QUALIFICATION_REVISION="$qualification_revision" FORGE_DISPATCH_TEST_MODE="${FORGE_DISPATCH_TEST_MODE:-0}" FORGE_TEST_DISABLE_ENGINE="${FORGE_TEST_DISABLE_ENGINE:-}" FAKE_CLAUDE_BEHAVIOR="${FAKE_CLAUDE_BEHAVIOR:-clean}" FAKE_CLAUDE_LOG="${FAKE_CLAUDE_LOG:-}" FAKE_CLAUDE_CWD_FILE="${FAKE_CLAUDE_CWD_FILE:-}" FAKE_REAL_ROOT="${FAKE_REAL_ROOT:-}" \
        "$binary" "${claude_args[@]}"
      rc=$?
      cp "$raw" "$bound_output"
      [ "$conversation" != new ] || ATTEMPT_SESSION_ID="$SESSION_PROVISIONAL_ID"
      [ "$conversation" != resume ] || ATTEMPT_SESSION_ID="$session_id"
    else
      sandbox=read-only; [ "$profile" = investigate ] && sandbox=workspace-write
      codex_home="$scratch/codex-home"; [ "$conversation" = ephemeral ] || codex_home="$SESSION_STORE/codex-home"
      auth_source="${FORGE_CODEX_AUTH_FILE:-${CODEX_HOME:-${HOME:-}/.codex}/auth.json}"
      if [ -n "${FORGE_CODEX_AUTH_FILE:-}" ] || { [ -n "$auth_source" ] && [ -e "$auth_source" ]; }; then
        [ -f "$auth_source" ] && [ ! -L "$auth_source" ] || { ATTEMPT_CLASS=authorization; ATTEMPT_REASON=invalid-codex-auth-file; return 2; }
        mkdir -p "$codex_home"; cp "$auth_source" "$codex_home/auth.json" || { ATTEMPT_CLASS=authorization; ATTEMPT_REASON=codex-auth-copy-failed; return 2; }; chmod 600 "$codex_home/auth.json" 2>/dev/null || true
      fi
      if [ "$conversation" = resume ]; then
        codex_args=(-a never --sandbox "$sandbox" exec resume --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use --ignore-user-config --ignore-rules --json -m "$model" -c "model_reasoning_effort=$effort" -c service_tier=fast --output-last-message "$bound_output" "$session_id" "$(cat "$scratch/prompt.txt")")
      else
        codex_args=(-a never exec --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use -C "$primary" --add-dir "$snapshot" --ignore-user-config --ignore-rules --sandbox "$sandbox" -m "$model" -c "model_reasoning_effort=$effort" -c service_tier=fast --output-last-message "$bound_output")
        [ "$readonly_server" != context7 ] || codex_args+=(-c 'mcp_servers.context7.url=https://mcp.context7.com/mcp' -c 'mcp_servers.context7.read_only=true')
        if [ "$conversation" = ephemeral ]; then codex_args+=(--ephemeral); else codex_args+=(--json); fi
        codex_args+=("$(cat "$scratch/prompt.txt")")
      fi
      run_with_timeout_dispatch "$timeout_seconds" "$raw" "$stderr_file" "$primary" env -i PATH="$PATH" HOME="$scratch/home" CODEX_HOME="$codex_home" TMPDIR="${TMPDIR:-/tmp}" FORGE_DISPATCH_MODE="$profile_mode" FORGE_CANDIDATE_ROOT="$snapshot" FORGE_REPRO_RUNNER="${REPRO_RUNNER:-}" FORGE_DISPATCH_SESSION_ID="${SESSION_PROVISIONAL_ID:-$session_id}" FORGE_DISPATCH_SEAT_HASH="$ATTEMPT_SEAT_HASH" FORGE_DISPATCH_CONFIG_HASH="$config_hash" FORGE_DISPATCH_CANARY_HASH="$ATTEMPT_CANARY_HASH" FORGE_DISPATCH_QUALIFICATION_REVISION="$qualification_revision" FORGE_DISPATCH_TEST_MODE="${FORGE_DISPATCH_TEST_MODE:-0}" FORGE_TEST_DISABLE_ENGINE="${FORGE_TEST_DISABLE_ENGINE:-}" FAKE_CODEX_BEHAVIOR="${FAKE_CODEX_BEHAVIOR:-clean}" FAKE_CODEX_LOG="${FAKE_CODEX_LOG:-}" \
        "$binary" "${codex_args[@]}"
      rc=$?
      rm -f "$codex_home/auth.json"
      if [ "$conversation" = new ]; then
        captured_thread=$(sed -nE 's/.*"type"[[:space:]]*:[[:space:]]*"thread.started".*"thread_id"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\1/p' "$raw" | head -1)
        safe_session_id_dispatch "$captured_thread" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=missing-thread-id; return 1; }
        ATTEMPT_SESSION_ID="$captured_thread"
      elif [ "$conversation" = resume ]; then ATTEMPT_SESSION_ID="$session_id"; fi
    fi
    ATTEMPT_EXIT="$rc"
    if [ "$rc" -eq 124 ]; then ATTEMPT_REASON=timeout; return 1; fi
    if [ "$rc" -ne 0 ]; then ATTEMPT_REASON=process-exit-$rc; return 1; fi
    if [ "${REPRO_MODE:-false}" = true ]; then
      [ -f "$ATTEMPT_REPRO_STDOUT" ] && [ ! -L "$ATTEMPT_REPRO_STDOUT" ] && [ -f "$ATTEMPT_REPRO_STDERR" ] && [ ! -L "$ATTEMPT_REPRO_STDERR" ] && [ -f "$ATTEMPT_REPRO_EXIT_FILE" ] && [ ! -L "$ATTEMPT_REPRO_EXIT_FILE" ] \
        || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=reproduction-runner-result-missing; return 1; }
      ATTEMPT_REPRO_EXIT=$(sed -n '1p' "$ATTEMPT_REPRO_EXIT_FILE"); case "$ATTEMPT_REPRO_EXIT" in ''|*[!0-9]*) ATTEMPT_CLASS=capability; ATTEMPT_REASON=reproduction-runner-exit-invalid; return 1 ;; esac
    fi
    # Claude's structured wrapper is load-bearing: it exposes provider/model identity.
    if [ -s "$bound_output" ] && [ "$(head -c 1 "$bound_output")" = '{' ] && command -v jq >/dev/null 2>&1; then
      extracted=$(jq -r '.result // empty' "$bound_output" 2>/dev/null || true)
      if [ -n "$extracted" ]; then printf '%s\n' "$extracted" > "$scratch/envelope.out"; bound_output="$scratch/envelope.out"; fi
      if [ "$selected" = claude ]; then
        if observe_claude_identity_dispatch "$scratch/raw.out" "$model"; then
          ATTEMPT_ACTUAL_MODEL="$OBSERVED_CLAUDE_MODEL"; ATTEMPT_ACTUAL_PROVIDER="$OBSERVED_CLAUDE_PROVIDER"
        fi
      fi
    fi
    if [ "$selected" = claude ]; then
      [ "$ATTEMPT_ACTUAL_PROVIDER" != UNOBSERVABLE ] && [ "$ATTEMPT_ACTUAL_MODEL" != UNOBSERVABLE ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=observable-identity-missing; return 1; }
      identity_match=false
      claude_identity_matches_dispatch "$provider" "$model" "$ATTEMPT_ACTUAL_PROVIDER" "$ATTEMPT_ACTUAL_MODEL" && identity_match=true
      [ "$identity_match" = true ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=observable-identity-mismatch; return 1; }
    fi
    if ! validate_envelope_dispatch "$bound_output"; then ATTEMPT_REASON="$RESULT_REASON"; ATTEMPT_CLASS=engine; return 1; fi
    snapshot_after="$scratch/snapshot-after.manifest"; snapshot_manifest_dispatch "$snapshot" "$snapshot_after"
    if ! cmp -s "$ATTEMPT_SNAPSHOT_BEFORE" "$snapshot_after" \
       || { [ "$artifact_kind" != file ] \
         && { [ "$(git -C "$snapshot" rev-parse refs/heads/candidate 2>/dev/null || true)" != "$snapshot_ref" ] \
           || [ "$(git -C "$snapshot" rev-parse HEAD 2>/dev/null || true)" != "$snapshot_head" ]; }; }; then
      ATTEMPT_CLASS=artifact; ATTEMPT_REASON=candidate-snapshot-mutated; return 2
    fi
    [ "$(awk -F= '$1=="forge_canary_hash" {n++} END {print n+0}' "$bound_output")" -ge 1 ] || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=isolation-canary-missing; return 1; }
    observation_matches_dispatch "$bound_output" forge_canary_hash "$ATTEMPT_CANARY_HASH" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=isolation-canary-mismatch; return 1; }
    observation_matches_dispatch "$bound_output" forge_config_hash "$config_hash" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=observed-config-mismatch; return 1; }
    observation_matches_dispatch "$bound_output" forge_qualification_revision "$qualification_revision" || { ATTEMPT_CLASS=capability; ATTEMPT_REASON=qualification-revision-mismatch; return 1; }
    ATTEMPT_CLASS="$RESULT_CLASS"; ATTEMPT_REASON="$RESULT_REASON"; ATTEMPT_VERDICT="$RESULT_VERDICT"; ATTEMPT_SEVERITY="$RESULT_SEVERITY"; ATTEMPT_SCHEMA="$RESULT_SCHEMA"; ATTEMPT_FINDINGS_DIGEST="$RESULT_FINDINGS_DIGEST"; ATTEMPT_OUTPUT="$bound_output"
    case "$ATTEMPT_VERDICT:$ATTEMPT_CLASS" in CLEAN:none|FINDINGS:none) return 0 ;; BLOCKED:engine|BLOCKED:capability) return 1 ;; BLOCKED:artifact|BLOCKED:authorization|BLOCKED:invariant) return 2 ;; *) ATTEMPT_CLASS=engine; ATTEMPT_REASON=contradictory-result; return 1 ;; esac
}

verify_pair_dispatch() {
    local spec="" quality="" pair_output pair_root pair_state pair_iteration current f key role output_path output_parent output_hash base_sha base_ref
    while [ "$#" -gt 0 ]; do case "$1" in --code-spec-receipt) spec="$2"; shift 2 ;; --code-quality-receipt) quality="$2"; shift 2 ;; *) die_dispatch invariant "unknown pair argument $1" ;; esac; done
    [ -f "$spec" ] && [ -f "$quality" ] && [ ! -L "$spec" ] && [ ! -L "$quality" ] || die_dispatch artifact 'two regular receipts are required'
    [ "$(kv_dispatch "$spec" role)" = code-spec ] && [ "$(kv_dispatch "$quality" role)" = code-quality ] || die_dispatch invariant 'required code lenses are missing or duplicated'
    [ "$(kv_dispatch "$spec" invocation_id)" != "$(kv_dispatch "$quality" invocation_id)" ] || die_dispatch invariant 'review invocation ids must differ'
    for key in artifact_hash worktree_identity workflow_base_sha git_head; do [ "$(kv_dispatch "$spec" "$key")" = "$(kv_dispatch "$quality" "$key")" ] || die_dispatch artifact "mixed or stale candidate pair: $key"; done
    pair_output=$(kv_dispatch "$spec" output_path); case "$pair_output" in */.forge/local/reviews/*) pair_root=${pair_output%/.forge/local/reviews/*} ;; *) die_dispatch invariant 'review receipt output path cannot resolve canonical state' ;; esac
    pair_state="$pair_root/.forge/local/state.md"; [ -f "$pair_state" ] && [ ! -L "$pair_state" ] || die_dispatch invariant 'canonical review state is unavailable'
    pair_iteration=$(awk -F'|' '{k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if(k=="Review iteration"){v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit}}' "$pair_state")
    case "$pair_iteration" in ''|*[!0-9]*) die_dispatch invariant 'current review iteration is invalid' ;; esac
    [ "$(kv_dispatch "$spec" review_iteration)" = "$pair_iteration" ] && [ "$(kv_dispatch "$quality" review_iteration)" = "$pair_iteration" ] || die_dispatch artifact 'review receipt iteration is stale or mixed'
    for f in "$spec" "$quality"; do
        [ "$(kv_dispatch "$f" schema_version)" = 1 ] && [ "$(kv_dispatch "$f" fresh_process)" = true ] \
          && [ "$(kv_dispatch "$f" process_exit_status)" = 0 ] && [ "$(kv_dispatch "$f" blocked_class)" = none ] \
          && [ "$(kv_dispatch "$f" result_schema_version)" = 1 ] || die_dispatch artifact 'review receipt execution schema is not certifying'
        [ "$(kv_dispatch "$f" semantic_verdict)" = CLEAN ] && case "$(kv_dispatch "$f" max_severity)" in NONE|P3) ;; *) die_dispatch artifact 'both review lenses must be certifying clean' ;; esac
        output_path=$(kv_dispatch "$f" output_path)
        case "$output_path" in "$pair_root"/.forge/local/reviews/*) ;; *) die_dispatch invariant 'review output escaped the bound worktree' ;; esac
        [ -f "$output_path" ] && [ ! -L "$output_path" ] || die_dispatch artifact 'review output must be a no-follow regular file'
        output_parent=$(cd "$(dirname "$output_path")" 2>/dev/null && pwd -P) || die_dispatch artifact 'review output parent is unavailable'
        [ "$output_parent" = "$(dirname "$output_path")" ] || die_dispatch artifact 'review output ancestor is linked'
        output_hash=$(kv_dispatch "$f" output_hash)
        [ "$(hash_file_dispatch "$output_path")" = "$output_hash" ] || die_dispatch artifact 'review output hash changed'
    done
    current="$pair_root/.forge/local/reviews/.verify-pair-$$-$RANDOM.candidate"
    base_sha=$(kv_dispatch "$spec" workflow_base_sha); base_ref=$(kv_dispatch "$spec" workflow_base_ref)
    (cd "$pair_root" && bash "$FINGERPRINT" identity --artifact git:working-tree --workflow-base-sha "$base_sha" --workflow-base-ref "$base_ref" --output "$current") >/dev/null 2>&1 \
      || { rm -f "$current"; die_dispatch artifact 'current candidate capture failed'; }
    for f in "$spec" "$quality"; do
        for key in artifact_hash worktree_identity workflow_base_sha git_head; do
            [ "$(kv_dispatch "$f" "$key")" = "$(kv_dispatch "$current" "$key")" ] || { rm -f "$current"; die_dispatch artifact "review pair is stale: $key"; }
        done
    done
    rm -f "$current"
    printf 'CLEAN: distinct code-spec and code-quality receipts certify candidate %s\n' "$(kv_dispatch "$spec" artifact_hash)"
}

subcommand="${1:-}"; [ "$#" -gt 0 ] && shift
if [ "$subcommand" = verify-pair ]; then verify_pair_dispatch "$@"; exit 0; fi
[ "$subcommand" = run ] || die_dispatch invariant 'usage: agent-dispatch run|verify-pair'

engine=""; fallback_policy=""; role=""; profile=""; artifact=""; workflow_base_sha=""; workflow_base_ref=""; prompt_file=""; output=""; conversation=ephemeral; session_id=""; session_id_output=""; seat_id=""; timeout_seconds=1200; readonly_server=""
while [ "$#" -gt 0 ]; do
 case "$1" in
  --engine) engine="${2:-}"; shift 2 ;; --fallback-policy) fallback_policy="${2:-}"; shift 2 ;; --role) role="${2:-}"; shift 2 ;; --profile) profile="${2:-}"; shift 2 ;;
  --artifact) artifact="${2:-}"; shift 2 ;; --workflow-base-sha) workflow_base_sha="${2:-}"; shift 2 ;; --workflow-base-ref) workflow_base_ref="${2:-}"; shift 2 ;;
  --prompt-file) prompt_file="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;; --conversation) conversation="${2:-}"; shift 2 ;;
  --session-id) session_id="${2:-}"; shift 2 ;; --session-id-output) session_id_output="${2:-}"; shift 2 ;; --timeout-seconds) timeout_seconds="${2:-}"; shift 2 ;;
  --seat-id) seat_id="${2:-}"; shift 2 ;;
  --read-only-server) readonly_server="${2:-}"; shift 2 ;; *) die_dispatch invariant "unknown dispatcher argument $1" ;;
 esac
done
case "$engine" in auto|claude|codex) ;; *) die_dispatch invariant 'engine must be auto, claude, or codex' ;; esac
case "$fallback_policy" in automatic|none) ;; *) die_dispatch invariant 'fallback policy must be automatic or none' ;; esac
case "$role" in general|plan|code-spec|code-quality|investigation|investigation-repro|prd|comments|council-advisor|council-chair) ;; *) die_dispatch invariant 'unsupported role' ;; esac
case "$profile" in review|investigate) ;; *) die_dispatch invariant 'unsupported profile' ;; esac
case "$role:$profile" in investigation:investigate|investigation-repro:investigate) ;; investigation:*|investigation-repro:*) die_dispatch authorization 'investigation roles require the investigate profile' ;; *:review) ;; *) die_dispatch authorization 'only investigation roles may use the investigate profile' ;; esac
case "$conversation" in ephemeral|new|resume) ;; *) die_dispatch invariant 'unsupported conversation transport' ;; esac
case "$timeout_seconds" in ''|*[!0-9]*) die_dispatch invariant 'timeout must be a positive integer' ;; esac; [ "$timeout_seconds" -gt 0 ] || die_dispatch invariant 'timeout must be positive'
[ -f "$prompt_file" ] && [ ! -L "$prompt_file" ] || die_dispatch artifact 'regular prompt file required'; [ -n "$output" ] || die_dispatch invariant 'output is required'
[ "$conversation" = ephemeral ] || [ "$role" = council-advisor ] || die_dispatch capability 'only council-advisor supports multi-turn transport'
[ "$conversation" != resume ] || [ -n "$session_id" ] || die_dispatch invariant 'exact session id is required for resume'
[ "$conversation" = ephemeral ] || [ "$fallback_policy" = none ] || die_dispatch capability 'multi-turn council transport forbids per-seat fallback'
scalar_dispatch engine "$engine"; scalar_dispatch role "$role"; scalar_dispatch output "$output"; scalar_dispatch base-ref "$workflow_base_ref"

root=$(git rev-parse --show-toplevel 2>/dev/null) || die_dispatch invariant 'Git worktree required'; root=$(cd "$root" && pwd -P)
reviews_dir="$root/.forge/local/reviews"
review_iteration=none
case "$role" in code-spec|code-quality)
  review_iteration=$(awk -F'|' '{k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if(k=="Review iteration"){v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit}}' "$root/.forge/local/state.md" 2>/dev/null)
  case "$review_iteration" in ''|*[!0-9]*) die_dispatch invariant 'code review requires a numeric current Review iteration' ;; esac
  ;;
esac
for owned_dir in "$root/.forge" "$root/.forge/local" "$reviews_dir"; do
  if [ -e "$owned_dir" ] || [ -L "$owned_dir" ]; then [ -d "$owned_dir" ] && [ ! -L "$owned_dir" ] || die_dispatch invariant 'review storage ancestors must be no-follow directories'
  else mkdir "$owned_dir" || die_dispatch invariant 'cannot create review storage'; fi
done
invocation_id=$(new_id_dispatch); active_host=""
validate_owned_review_path_dispatch "$output" 'review output'; output="$VALID_REVIEW_PATH"
if [ "$conversation" = new ]; then validate_owned_review_path_dispatch "$session_id_output" 'session id output'; session_id_output="$VALID_REVIEW_PATH"; fi
case "$role" in
  council-advisor|council-chair)
    safe_session_id_dispatch "$seat_id" || die_dispatch invariant 'council roles require a safe --seat-id'
    [ "$(awk -F= '$1=="question_hash" {n++} END {print n+0}' "$prompt_file")" -eq 1 ] || die_dispatch invariant 'council prompt requires exactly one question_hash'
    question_hash=$(kv_dispatch "$prompt_file" question_hash); case "$question_hash" in ????????-????-????-????-????????????) ;; esac
    case "$question_hash" in *[!0-9a-fA-F]*|'') die_dispatch invariant 'council question_hash must be hexadecimal' ;; esac
    [ "${#question_hash}" -eq 64 ] || die_dispatch invariant 'council question_hash must be sha256'
    ;;
  *) [ -z "$seat_id" ] || die_dispatch invariant '--seat-id is reserved for council roles'; question_hash=$(hash_file_dispatch "$prompt_file") ;;
esac
if [ "$role" != investigation ]; then
  [ "$(awk -F= '$1=="requires_read_only_channel" && $2=="true" {n++} END {print n+0}' "$prompt_file")" -eq 0 ] || [ -n "$readonly_server" ] || die_dispatch authorization 'required read-only investigation channel was not selected'
fi
active_host=${FORGE_NATIVE_HOST:-}
case "$active_host" in
  claude|codex) ;;
  *) write_early_receipt invariant declared-main-host-missing; printf 'BLOCKED[invariant]: declared main host must be claude or codex; receipt=%s\n' "$receipt" >&2; exit 2 ;;
esac
case "$engine" in auto) [ "$active_host" = claude ] && first=codex || first=claude ;; *) first="$engine" ;; esac
[ "$first" = claude ] && second=codex || second=claude

fingerprint_file="$reviews_dir/$invocation_id.candidate"
if ! bash "$FINGERPRINT" identity --artifact "$artifact" --workflow-base-sha "$workflow_base_sha" --workflow-base-ref "$workflow_base_ref" --output "$fingerprint_file" >/dev/null; then write_early_receipt artifact candidate-capture-failed; exit 2; fi
artifact_hash=$(kv_dispatch "$fingerprint_file" artifact_hash); worktree_identity=$(kv_dispatch "$fingerprint_file" worktree_identity); git_head=$(kv_dispatch "$fingerprint_file" git_head); artifact_kind=$(kv_dispatch "$fingerprint_file" artifact_kind); base_resolved=$(kv_dispatch "$fingerprint_file" workflow_base_sha)
prompt_hash=$(hash_file_dispatch "$prompt_file"); qualification_revision=$(hash_file_dispatch "$CAPABILITIES_FILE")
prepare_session_dispatch
attempted=""; fallback=false; fallback_reason=none; actual=none; first_attempted="$first"; final_rc=2; ATTEMPT_OUTPUT=""; INVESTIGATION_MODE=not-applicable; INVESTIGATION_REPLAY=NONE; REPRODUCTION_STATUS=UNVERIFIED; REPRO_HYPOTHESIS_HASH=MISSING; REPRO_PRIMARY_HASH=MISSING; REPRO_CONTROL_HASH=MISSING; REPRO_MODE=false
[ "$role" != investigation ] || INVESTIGATION_MODE=full-agent-worktree

if [ "$role" = investigation-repro ]; then
  REPRO_MODE=true; ATTEMPT_EXIT=0; ATTEMPT_CLASS=none; ATTEMPT_REASON=dispatcher-owned-reproduction; ATTEMPT_VERDICT=CLEAN; ATTEMPT_SEVERITY=NONE; ATTEMPT_SCHEMA=1; ATTEMPT_FINDINGS_DIGEST=$(printf '' | hash_stream_dispatch)
  REPRO_PROTECTED_STATE_HASH=$(hash_file_dispatch "$root/.forge/local/state.md"); REPRO_PROTECTED_AUTH_FILE=""
  repro_auth_source="${FORGE_CODEX_AUTH_FILE:-${CODEX_HOME:-${HOME:-}/.codex}/auth.json}"
  if [ -e "$repro_auth_source" ] || [ -L "$repro_auth_source" ]; then
    [ -f "$repro_auth_source" ] && [ ! -L "$repro_auth_source" ] || die_dispatch authorization 'protected reproduction auth must be a no-follow regular file'
    REPRO_PROTECTED_AUTH_FILE="$repro_auth_source"; REPRO_PROTECTED_AUTH_HASH=$(hash_file_dispatch "$repro_auth_source")
  fi
  attempted="$first"; run_reproduction_dispatch "$first" 1; repro_rc=$?
  if [ "$REPRO_ENGINE_USED" = false ]; then first_attempted=none; attempted=none; actual=none; [ "$repro_rc" -eq 0 ] && final_rc=0 || final_rc=2
  elif [ "$repro_rc" -eq 0 ]; then actual="$first"; final_rc=0
  elif [ "$repro_rc" -eq 1 ] && [ "$fallback_policy" = automatic ]; then
    fallback=true; fallback_reason="$ATTEMPT_REASON"; printf 'Reproduction boundary %s unavailable (%s); visible fallback to fresh %s boundaries.\n' "$first" "$fallback_reason" "$second"
    attempted="$attempted,$second"; REPRODUCTION_STATUS=UNVERIFIED; run_reproduction_dispatch "$second" 3; repro_rc=$?; actual="$second"; [ "$repro_rc" -eq 0 ] && final_rc=0 || final_rc=2
  else actual="$first"; final_rc=2
  fi
  ATTEMPT_OUTPUT="$reviews_dir/$invocation_id.reproduction-result"
  { printf 'schema_version=1\nverdict=%s\nmax_severity=NONE\nblocked_class=%s\nreproduction_status=%s\nhypothesis_hash=%s\nprimary_check_hash=%s\ncontrol_hash=%s\n' "$ATTEMPT_VERDICT" "$ATTEMPT_CLASS" "$REPRODUCTION_STATUS" "$REPRO_HYPOTHESIS_HASH" "$REPRO_PRIMARY_HASH" "$REPRO_CONTROL_HASH"; } > "$ATTEMPT_OUTPUT"
else
  attempted="$first"; attempt_engine_dispatch "$first" 1; attempt_rc=$?
  if [ "$attempt_rc" -eq 0 ]; then actual="$first"; final_rc=0
  elif [ "$attempt_rc" -eq 2 ]; then actual="$first"; final_rc=2
  elif [ "$fallback_policy" = automatic ]; then
    fallback=true; fallback_reason="$ATTEMPT_REASON"; printf 'Reviewer %s unavailable (%s); visible fallback to fresh %s.\n' "$first" "$fallback_reason" "$second"
    attempted="$attempted,$second"; attempt_engine_dispatch "$second" 2; attempt_rc=$?; actual="$second"; [ "$attempt_rc" -eq 0 ] && final_rc=0 || final_rc=2
  else actual="$first"; final_rc=2
  fi
fi

# Ordinary reviews certify an immutable candidate. A full investigation intentionally works in the live worktree.
if [ "$role" != investigation ]; then
  identity_file="$reviews_dir/$invocation_id.recheck"
  if ! bash "$FINGERPRINT" identity --artifact "$artifact" --workflow-base-sha "$workflow_base_sha" --workflow-base-ref "$workflow_base_ref" --output "$identity_file" >/dev/null 2>&1 \
     || [ "$(kv_dispatch "$identity_file" artifact_hash)" != "$artifact_hash" ]; then
    ATTEMPT_CLASS=artifact; ATTEMPT_REASON=artifact-mutated; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; final_rc=2
  fi
fi

if [ "$final_rc" -eq 0 ] && [ "$conversation" = new ]; then
  if ! write_session_metadata_dispatch; then ATTEMPT_CLASS=invariant; ATTEMPT_REASON=session-metadata-write-failed; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; final_rc=2; fi
fi

if [ -n "${ATTEMPT_OUTPUT:-}" ] && [ -s "$ATTEMPT_OUTPUT" ]; then publish_owned_review_file_dispatch "$ATTEMPT_OUTPUT" "$output" 'review output'; fi
if [ "$final_rc" -eq 0 ] && [ "$conversation" = resume ]; then
  if ! complete_session_dispatch; then ATTEMPT_CLASS=invariant; ATTEMPT_REASON=session-cleanup-failed; ATTEMPT_VERDICT=BLOCKED; ATTEMPT_SEVERITY=NONE; final_rc=2; fi
fi
output_hash=$(hash_file_dispatch "$output"); invocation_config_hash=$(printf '%s\n' "$attempted" "${ATTEMPT_CONFIG_HASH:-MISSING}" "$qualification_revision" "$artifact_hash" "$prompt_hash" "$role" "$profile" | hash_stream_dispatch)
receipt="$reviews_dir/$invocation_id.receipt"
{
 printf 'schema_version=1\ninvocation_id=%s\ntimestamp=%s\nmain_host=%s\nrequested_engine=%s\nfirst_attempted_engine=%s\nactual_engine=%s\nfallback=%s\nfallback_reason=%s\nattempted_engines=%s\nrole=%s\nprofile=%s\nreview_iteration=%s\nfresh_process=true\nconversation=%s\nsession_id=%s\nartifact_kind=%s\nartifact_identity=%s\nartifact_hash=%s\nworktree_identity=%s\ngit_head=%s\nprompt_hash=%s\nworkflow_base_ref=%s\nworkflow_base_sha=%s\noutput_path=%s\noutput_hash=%s\nprocess_exit_status=%s\nsemantic_verdict=%s\nmax_severity=%s\nfindings_digest=%s\nresult_schema_version=%s\nrequested_provider=%s\nrequested_model=%s\nrequested_reasoning_effort=%s\nbound_provider=%s\nbound_model=%s\nbound_reasoning_effort=%s\nactual_provider=%s\nactual_model=%s\nactual_reasoning_effort=%s\ninvocation_config_hash=%s\nmodel_qualification_revision=%s\nblocked_class=%s\ninvestigation_mode=%s\ninvestigation_replay=%s\nreproduction_status=%s\nhypothesis_hash=%s\nprimary_check_hash=%s\ncontrol_hash=%s\n' \
  "$invocation_id" "$(now_dispatch)" "$active_host" "$engine" "$first_attempted" "$actual" "$fallback" "$(escape_dispatch "$fallback_reason")" "$attempted" "$role" "$profile" "$review_iteration" "$conversation" "${ATTEMPT_SESSION_ID:-none}" "$artifact_kind" "$artifact_hash" "$artifact_hash" "$worktree_identity" "$git_head" "$prompt_hash" "$(escape_dispatch "$workflow_base_ref")" "$base_resolved" "$(escape_dispatch "$output")" "$output_hash" "${ATTEMPT_EXIT:-127}" "${ATTEMPT_VERDICT:-BLOCKED}" "${ATTEMPT_SEVERITY:-NONE}" "${ATTEMPT_FINDINGS_DIGEST:-MISSING}" "${ATTEMPT_SCHEMA:-none}" "${ATTEMPT_REQUESTED_PROVIDER:-UNQUALIFIED}" "${ATTEMPT_REQUESTED_MODEL:-UNQUALIFIED}" "${ATTEMPT_REQUESTED_EFFORT:-UNQUALIFIED}" "${ATTEMPT_REQUESTED_PROVIDER:-UNQUALIFIED}" "${ATTEMPT_REQUESTED_MODEL:-UNQUALIFIED}" "${ATTEMPT_REQUESTED_EFFORT:-UNQUALIFIED}" "${ATTEMPT_ACTUAL_PROVIDER:-UNOBSERVABLE}" "${ATTEMPT_ACTUAL_MODEL:-UNOBSERVABLE}" "${ATTEMPT_ACTUAL_EFFORT:-UNOBSERVABLE}" "$invocation_config_hash" "$qualification_revision" "${ATTEMPT_CLASS:-engine}" "$INVESTIGATION_MODE" "$INVESTIGATION_REPLAY" "$REPRODUCTION_STATUS" "${REPRO_HYPOTHESIS_HASH:-MISSING}" "${REPRO_PRIMARY_HASH:-MISSING}" "${REPRO_CONTROL_HASH:-MISSING}"
} > "$receipt"
printf 'Reviewer selection: main=%s requested=%s actual=%s fallback=%s role=%s receipt=%s\n' "$active_host" "$engine" "$actual" "$fallback" "$role" "$receipt"
[ "$final_rc" -eq 0 ] || exit 2
exit 0
