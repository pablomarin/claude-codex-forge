#!/usr/bin/env bash
# Human-executed external action renderer. This file intentionally has no execute subcommand.
set -u
die_action() { printf 'BLOCKED[authorization]: %s\n' "$*" >&2; exit 2; }
hash_stream_action() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
escape_action() { printf '%s' "$1" | sed 's/%/%25/g; s/=/\%3D/g; s/\t/%09/g; s/\r/%0D/g; s/\n/%0A/g'; }
scalar_action() { case "$2" in *$'\n'*|*$'\r'*) die_action "$1 contains a newline" ;; esac; }
value_action() {
  local count
  count=$(awk -F= -v key="$2" '$1==key {n++} END {print n+0}' "$1")
  [ "$count" -eq 1 ] || die_action "action key $2 must occur exactly once"
  awk -F= -v key="$2" '$1==key {sub(/^[^=]*=/,""); print; exit}' "$1"
}
identity_action() { local root common; root=$(git rev-parse --show-toplevel 2>/dev/null) || die_action 'Git worktree required'; root=$(cd "$root" && pwd -P); common=$(git rev-parse --git-common-dir); common=$(cd "$root" && cd "$common" && pwd -P); printf '%s|%s\n' "$root" "$common" | hash_stream_action; }
local_action_path() {
  local requested="$1" root actions canonical cursor relative parent_relative part logical_root logical_actions
  [ -n "$requested" ] || die_action 'local action output required'
  logical_root=$(git rev-parse --show-toplevel 2>/dev/null) || die_action 'Git worktree required'
  root=$(cd "$logical_root" && pwd -P); actions="$root/.forge/local/actions"; logical_actions="$logical_root/.forge/local/actions"
  for owned_dir in "$root/.forge" "$root/.forge/local" "$actions"; do
    if [ -e "$owned_dir" ] || [ -L "$owned_dir" ]; then [ -d "$owned_dir" ] && [ ! -L "$owned_dir" ] || die_action 'linked action path rejected'
    else mkdir "$owned_dir" || die_action 'cannot create actions directory'; fi
  done
  if [ -d "$(dirname "$requested")" ] && [ ! -L "$(dirname "$requested")" ]; then canonical="$(cd "$(dirname "$requested")" && pwd -P)/$(basename "$requested")"
  else case "$requested" in "$logical_actions"/*) canonical="$actions/${requested#"$logical_actions"/}" ;; /*) canonical="$requested" ;; *) canonical="$(pwd -P)/$requested" ;; esac; fi
  case "$canonical" in *$'\n'*|*$'\r'*|*/../*|*/./*) die_action 'unsafe action output path component' ;; esac
  case "$canonical" in "$actions"/*) ;; *) die_action 'action record must stay under .forge/local/actions' ;; esac
  relative=${canonical#"$actions"/}; cursor="$actions"; parent_relative=${relative%/*}; [ "$parent_relative" != "$relative" ] || parent_relative=""
  while [ -n "$parent_relative" ]; do
    case "$parent_relative" in */*) part=${parent_relative%%/*}; parent_relative=${parent_relative#*/} ;; *) part=$parent_relative; parent_relative="" ;; esac
    [ -n "$part" ] || continue; cursor="$cursor/$part"
    if [ -e "$cursor" ] || [ -L "$cursor" ]; then [ -d "$cursor" ] && [ ! -L "$cursor" ] || die_action 'linked action path rejected'
    else mkdir "$cursor" || die_action 'cannot create action output directory'; fi
  done
  [ ! -e "$canonical" ] && [ ! -L "$canonical" ] || die_action 'action output already exists or is linked'
  ACTION_PATH="$canonical"
}

mode="${1:-}"; [ "$#" -gt 0 ] && shift
case "$mode" in
prepare)
  adapter=""; system=""; operation=""; target=""; effect=""; output=""; args=()
  while [ "$#" -gt 0 ]; do case "$1" in --adapter) adapter="$2"; shift 2 ;; --system) system="$2"; shift 2 ;; --operation) operation="$2"; shift 2 ;; --target) target="$2"; shift 2 ;; --expected-effect) effect="$2"; shift 2 ;; --output) output="$2"; shift 2 ;; --arg) args+=("$2"); shift 2 ;; *) die_action "unknown argument $1" ;; esac; done
  for entry in adapter "$adapter" system "$system" operation "$operation" target "$target" expected-effect "$effect"; do :; done
  scalar_action adapter "$adapter"; scalar_action system "$system"; scalar_action operation "$operation"; scalar_action target "$target"; scalar_action expected-effect "$effect"
  [ -n "$output" ] || die_action 'pending-action output required'; [ -n "$effect" ] || die_action 'expected effect required'
  command_name=""; rendered=""
  case "$adapter:$system:$operation" in
    gh-issue-close:github:close-issue)
      [ "${#args[@]}" -eq 2 ] || die_action 'gh-issue-close requires repository and issue number'
      case "${args[0]}" in *[!A-Za-z0-9_.\/-]*|'') die_action 'invalid GitHub repository' ;; esac
      case "${args[1]}" in *[!0-9]*|'') die_action 'invalid issue number' ;; esac
      command_name=gh; rendered="gh issue close ${args[1]} --repo ${args[0]}" ;;
    kubectl-rollout-restart:kubernetes:rollout-restart)
      [ "${#args[@]}" -eq 2 ] || die_action 'kubectl rollout restart requires namespace and deployment'
      case "${args[0]}${args[1]}" in *[!A-Za-z0-9_.-]*) die_action 'invalid Kubernetes identifier' ;; esac
      command_name=kubectl; rendered="kubectl -n ${args[0]} rollout restart deployment/${args[1]}" ;;
    *) die_action 'adapter/system/operation is not allowlisted; MCP-only mutation remains manual and BLOCKED' ;;
  esac
  local_action_path "$output"; output="$ACTION_PATH"
  nonce="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM:-0}"; action_hash=$(printf '%s\n' "$adapter" "$system" "$operation" "$target" "$rendered" "$effect" | hash_stream_action)
  umask 077
  {
    printf 'schema_version=1\nstatus=PENDING_HUMAN_EXECUTION\nnonce=%s\nworktree_identity=%s\nadapter=%s\nsystem=%s\noperation=%s\ntarget=%s\naction_hash=%s\nexpected_effect=%s\ncommand_executable=%s\ncommand_rendered=%s\ncreated_at=%s\n' \
      "$nonce" "$(identity_action)" "$adapter" "$system" "$operation" "$(escape_action "$target")" "$action_hash" "$(escape_action "$effect")" "$command_name" "$(escape_action "$rendered")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$output"
  printf 'PENDING: developer must execute this exact command in their own terminal, then report the result; Forge will not run it:\n%s\n' "$rendered"
  ;;
report)
  manifest=""; outcome=""; output=""
  while [ "$#" -gt 0 ]; do case "$1" in --manifest) manifest="$2"; shift 2 ;; --outcome) outcome="$2"; shift 2 ;; --output) output="$2"; shift 2 ;; *) die_action "unknown report argument $1" ;; esac; done
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || die_action 'regular pending manifest required'
  [ "$(value_action "$manifest" status)" = PENDING_HUMAN_EXECUTION ] || die_action 'manifest is not pending human execution'
  [ "$(value_action "$manifest" worktree_identity)" = "$(identity_action)" ] || die_action 'pending manifest belongs to another worktree'
  case "$outcome" in SUCCESS|FAILED|UNCERTAIN) ;; *) die_action 'outcome must be SUCCESS, FAILED, or UNCERTAIN' ;; esac
  [ -n "$output" ] || die_action 'audit output required'; local_action_path "$output"; output="$ACTION_PATH"; umask 077
  {
    printf 'schema_version=1\nstatus=REPORTED\nnonce=%s\nworktree_identity=%s\naction_hash=%s\nreported_outcome=%s\nreported_at=%s\nverification=UNVERIFIED\nnext_step=independent-investigation-repro\n' \
      "$(value_action "$manifest" nonce)" "$(identity_action)" "$(value_action "$manifest" action_hash)" "$outcome" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$output"
  ;;
*) die_action 'usage: authorized-action.sh prepare|report (there is deliberately no execute mode)' ;;
esac
