#!/usr/bin/env bash
# Six-seat Engineering Council topology.  Seat failures are surfaced to this
# orchestrator; it is the only layer permitted to select the all-main rerun.
set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$SELF_DIR/../.." && pwd -P)
AGENT_DISPATCH="$SELF_DIR/agent-dispatch.sh"
CAPABILITIES="$ROOT/host-capabilities.tsv"
[ -f "$CAPABILITIES" ] || CAPABILITIES="$ROOT/manifests/host-capabilities.tsv"
hash_stream() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
die() { printf 'BLOCKED[council]: %s\n' "$*" >&2; exit 2; }
usage() { cat <<'EOF'
usage: council-dispatch.sh --question-file FILE --artifact ARTIFACT --workflow-base-sha SHA --workflow-base-ref REF [--seat-engine SEAT=claude|codex|main|other]

Runs five two-turn advisor seats and one chairman. A non-main failure discards
the started mixed topology and reruns all eleven turns on the protected main
host (topology_mode=same-engine-fallback). Per-seat fallback is never used.
EOF
}

question_file=""; artifact=""; base_sha=""; base_ref=""; timeout=1200; overrides=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --question-file) question_file="${2:-}"; shift 2 ;;
    --artifact) artifact="${2:-}"; shift 2 ;;
    --workflow-base-sha) base_sha="${2:-}"; shift 2 ;;
    --workflow-base-ref) base_ref="${2:-}"; shift 2 ;;
    --timeout-seconds) timeout="${2:-}"; shift 2 ;;
    --seat-engine) overrides+=("${2:-}"); shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[ -f "$question_file" ] && [ ! -L "$question_file" ] || die 'regular --question-file is required'
[ -n "$artifact" ] && [ -n "$base_sha" ] && [ -n "$base_ref" ] || die 'artifact and workflow base are required'
case "$timeout" in ''|*[!0-9]*) die 'timeout must be positive' ;; esac

main=${FORGE_NATIVE_HOST:-}
case "$main" in claude|codex) ;; *) die 'declared main host must be claude or codex' ;; esac
other=claude; [ "$main" = claude ] && other=codex
declare -a seats=(simplifier scalability_hawk pragmatist contrarian maintainer)
engine_simplifier=$main; engine_scalability_hawk=$main; engine_pragmatist=$main
engine_contrarian=$other; engine_maintainer=$other; engine_chair=$other
persona_for() { case "$1" in simplifier) printf '%s' 'The Simplifier' ;; scalability_hawk) printf '%s' 'The Scalability Hawk' ;; pragmatist) printf '%s' 'The Pragmatist' ;; contrarian) printf '%s' 'The Contrarian' ;; maintainer) printf '%s' 'The Maintainer' ;; *) printf '%s' 'Council Chairman' ;; esac; }
label_for() { case "$1" in simplifier) printf A ;; scalability_hawk) printf B ;; pragmatist) printf C ;; contrarian) printf D ;; maintainer) printf E ;; *) printf Chair ;; esac; }
engine_for() { case "$1" in simplifier) printf '%s' "$engine_simplifier" ;; scalability_hawk) printf '%s' "$engine_scalability_hawk" ;; pragmatist) printf '%s' "$engine_pragmatist" ;; contrarian) printf '%s' "$engine_contrarian" ;; maintainer) printf '%s' "$engine_maintainer" ;; chair) printf '%s' "$engine_chair" ;; esac; }
set_engine() { case "$1" in simplifier) engine_simplifier=$2 ;; scalability_hawk) engine_scalability_hawk=$2 ;; pragmatist) engine_pragmatist=$2 ;; contrarian) engine_contrarian=$2 ;; maintainer) engine_maintainer=$2 ;; chair) engine_chair=$2 ;; esac; }
custom=false
if [ "${#overrides[@]}" -gt 0 ]; then
  for override in "${overrides[@]}"; do
    name=${override%%=*}; value=${override#*=}; [ "$name" != "$override" ] || die 'seat override must be SEAT=ENGINE'
    case "$name" in simplifier|scalability_hawk|pragmatist|contrarian|maintainer|chair) ;; *) die "unknown council seat $name" ;; esac
    case "$value" in main) value=$main ;; other) value=$other ;; claude|codex) ;; *) die "invalid engine for $name" ;; esac
    set_engine "$name" "$value"; custom=true
  done
fi

qhash=$(hash_stream < "$question_file")
workroot=$(git rev-parse --show-toplevel 2>/dev/null) || die 'Git worktree required'
workroot=$(cd "$workroot" && pwd -P) || die 'cannot resolve Git worktree'
review_root="$workroot/.forge/local/reviews/council-$qhash"
reviews_root="$workroot/.forge/local/reviews"
cursor="$workroot"
for part in .forge local reviews "council-$qhash"; do
  cursor="$cursor/$part"
  if [ -e "$cursor" ] || [ -L "$cursor" ]; then
    [ -d "$cursor" ] && [ ! -L "$cursor" ] || die 'council receipt storage ancestors must be no-follow directories'
  else
    mkdir "$cursor" || die 'cannot create council receipt storage'
  fi
done
[ "$(cd "$review_root" && pwd -P)" = "$review_root" ] || die 'council receipt storage ancestor is linked'

preflight_other() {
  # A known absent other engine must avoid launching any partial mixed council.
  command -v "$other" >/dev/null 2>&1 || return 1
  return 0
}

preflight_engine() {
  local selected="$1"
  command -v "$selected" >/dev/null 2>&1 || return 1
  awk -F'\t' -v h="$selected" '$1=="model-council-advisor" && $2==h {a=1} $1=="model-council-chair" && $2==h {c=1} END {exit !(a&&c)}' "$CAPABILITIES" || return 1
  # Task 5 owns the qualified exact-id transport. Refuse to start a council if
  # that transport is absent rather than creating a fresh substitute peer turn.
  grep -Fq 'resume)' "$AGENT_DISPATCH" && grep -Fq 'session_id' "$AGENT_DISPATCH"
}

write_prompt() {
  local path="$1" phase="$2" seat="$3" bundle="${4:-}"
  { printf 'question_hash=%s\nrequires_read_only_channel=false\n' "$qhash"
    printf 'Council phase: %s\nSeat: %s\nPersona: %s\nOriginal question:\n' "$phase" "$(label_for "$seat")" "$(persona_for "$seat")"
    cat "$question_file"
    [ -z "$bundle" ] || { printf '\nAnonymous peer bundle (other seats only):\n'; cat "$bundle"; }
    printf '\nReturn the required council envelope and schema.\n'; } > "$path"
}

FAILED_ENGINE=""
call_advisor() {
  local dir="$1" seat="$2" phase="$3" bundle="${4:-}" sid="${5:-}"
  local prompt="$dir/$seat-$phase.prompt" output="$dir/$seat-$phase.out" session_file="$dir/$seat.session" selected_engine
  write_prompt "$prompt" "$phase" "$seat" "$bundle"
  local conv=new; local extra=(--session-id-output "$session_file")
  if [ "$phase" = peer ]; then conv=resume; extra=(--session-id "$sid"); fi
  selected_engine=$(engine_for "$seat")
  FAILED_ENGINE="$selected_engine"
  bash "$AGENT_DISPATCH" run --engine "$selected_engine" --fallback-policy none --role council-advisor --profile review \
    --artifact "$artifact" --workflow-base-sha "$base_sha" --workflow-base-ref "$base_ref" --prompt-file "$prompt" --output "$output" \
    --conversation "$conv" --seat-id "$seat" --timeout-seconds "$timeout" "${extra[@]}"
}

RESULT_DIR=""; ATTEMPT_DIR=""
run_attempt() {
  local mode="$1" reason="$2" dir final_dir
  dir="$reviews_root/.council-attempt-$(date +%s)-$$-$RANDOM"
  final_dir="$review_root/$mode-$(date +%s)-$$"
  mkdir "$dir" || return 12
  ATTEMPT_DIR="$dir"
  local seat sid bundle="$dir/anonymous-advice.txt" peer_bundle="$dir/anonymous-peer-reviews.txt"
  for seat in "${seats[@]}"; do call_advisor "$dir" "$seat" advice || return 10; done
  : > "$bundle"
  for seat in "${seats[@]}"; do printf '### Advisor %s\n' "$(label_for "$seat")" >> "$bundle"; sed '/^engine=/d;/^author=/d' "$dir/$seat-advice.out" >> "$bundle"; done
  for seat in "${seats[@]}"; do sid=$(tr -d '\r\n' < "$dir/$seat.session") || return 11; [ -n "$sid" ] || return 11
    # Do not reveal this seat's own initial answer during its critique.
    awk -v omit="$(label_for "$seat")" '/^### Advisor / { keep=($3 != omit) } keep { print }' "$bundle" > "$dir/$seat-others.txt"
    call_advisor "$dir" "$seat" peer "$dir/$seat-others.txt" "$sid" || return 10
  done
  : > "$peer_bundle"; for seat in "${seats[@]}"; do printf '### Peer review %s\n' "$(label_for "$seat")" >> "$peer_bundle"; sed '/^engine=/d;/^author=/d' "$dir/$seat-peer.out" >> "$peer_bundle"; done
  local chair_prompt="$dir/chair.prompt" chair_out="$dir/chair.out"
  { printf 'question_hash=%s\nrequires_read_only_channel=false\nOriginal question:\n' "$qhash"; cat "$question_file"; printf '\nAnonymous advice:\n'; cat "$bundle"; printf '\nAnonymous peer reviews:\n'; cat "$peer_bundle"; printf '\nMinority reports are mandatory.\n'; } > "$chair_prompt"
  FAILED_ENGINE=$(engine_for chair)
  bash "$AGENT_DISPATCH" run --engine "$FAILED_ENGINE" --fallback-policy none --role council-chair --profile review --artifact "$artifact" --workflow-base-sha "$base_sha" --workflow-base-ref "$base_ref" --prompt-file "$chair_prompt" --output "$chair_out" --conversation ephemeral --seat-id chair --timeout-seconds "$timeout" || return 10
  local bundle_hash; bundle_hash=$(hash_stream < "$bundle")
  { printf 'schema_version=1\ntopology_mode=%s\ntrigger_reason=%s\nmain_host=%s\nquestion_hash=%s\nanonymized_bundle_hash=%s\nanonymized_peer_bundle_hash=%s\nconfiguration_revision=%s\n' "$mode" "$reason" "$main" "$qhash" "$bundle_hash" "$(hash_stream < "$peer_bundle")" "$(hash_stream < "$CAPABILITIES")"
    for seat in "${seats[@]}"; do
      selected_engine=$(engine_for "$seat"); seat_label=$(label_for "$seat")
      printf 'seat_label.%s=%s\npersona_binding.%s=%s\nintended_engine.%s.advice=%s\nactual_engine.%s.advice=%s\nintended_engine.%s.peer=%s\nactual_engine.%s.peer=%s\nsession_id.%s=%s\nturn_id.%s.advice=%s-advice\nturn_id.%s.peer=%s-peer\nadvisor_output_hash.%s=%s\npeer_output_hash.%s=%s\n' "$seat_label" "$seat_label" "$seat" "$(persona_for "$seat")" "$seat" "$selected_engine" "$seat" "$selected_engine" "$seat" "$selected_engine" "$seat" "$selected_engine" "$seat" "$(tr -d '\r\n' < "$dir/$seat.session")" "$seat" "$seat" "$seat" "$seat" "$seat" "$(hash_stream < "$dir/$seat-advice.out")" "$seat" "$(hash_stream < "$dir/$seat-peer.out")"
    done
    chair_engine=$(engine_for chair)
    printf 'intended_engine.chair=%s\nactual_engine.chair=%s\nchair_session_id=ephemeral\nturn_id.chair=chair-synthesis\nadvisor_turns=5\npeer_turns=5\nchairman_turns=1\nturn_results=11\nminority_reports=mandatory\nchairman_output_hash=%s\nfinal_verdict_path=%s\n' "$chair_engine" "$chair_engine" "$(hash_stream < "$chair_out")" "$final_dir/chair.out"; } > "$dir/topology.receipt"
  mv "$dir" "$final_dir" || return 12
  ATTEMPT_DIR="$final_dir"
  RESULT_DIR="$final_dir"
  return 0
}

mode=mixed; reason=healthy
if [ "$custom" = true ]; then mode=custom; fi
if ! preflight_engine "$main"; then die "main engine $main failed council preflight"; fi
if [ "$custom" = true ]; then
  for seat in "${seats[@]}" chair; do
    if [ "$(engine_for "$seat")" = "$other" ] && ! preflight_engine "$other"; then
      printf 'Council other engine %s is unavailable; starting one all-main attempt.\n' "$other" >&2
      for seat in "${seats[@]}" chair; do set_engine "$seat" "$main"; done
      mode=same-engine-fallback; reason=known-other-unavailable; custom=false
      break
    fi
  done
fi
if [ "$custom" = false ] && ! preflight_engine "$other"; then
  printf 'Council other engine %s is unavailable; starting one all-main attempt.\n' "$other" >&2
  for seat in "${seats[@]}" chair; do set_engine "$seat" "$main"; done
  mode=same-engine-fallback; reason=known-other-unavailable
fi
if run_attempt "$mode" "$reason"; then printf 'Council receipt: %s/topology.receipt\n' "$RESULT_DIR"; exit 0; fi
if [ "$FAILED_ENGINE" = "$other" ]; then
  printf 'Council mixed attempt failed; discarding partial artifacts and rerunning all seats on %s.\n' "$main" >&2
  case "$ATTEMPT_DIR" in "$reviews_root"/.council-attempt-*) rm -rf "$ATTEMPT_DIR" ;; *) die 'failed attempt path escaped council staging' ;; esac
  for seat in "${seats[@]}" chair; do set_engine "$seat" "$main"; done
  run_attempt same-engine-fallback runtime-other-failure || die 'main-engine council failure blocks verdict'
  printf 'Council receipt: %s/topology.receipt\n' "$RESULT_DIR"; exit 0
fi
die 'main-engine or custom council failure blocks verdict'
