#!/usr/bin/env bash
# Candidate-bound review and verification receipt contract (Forge v6).
# Bash 3.2 compatible; line-oriented data is parsed, never sourced.
set -u

vr_die() { printf 'BLOCKED[evidence]: %s\n' "$*" >&2; exit 2; }
vr_hash_stream() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
vr_hash_file() { vr_hash_stream < "$1"; }
vr_scalar() { case "$2" in *$'\n'*|*$'\r'*) vr_die "$1 contains a newline" ;; esac; }
vr_kv() {
    local file="$1" key="$2" count
    count=$(awk -F= -v k="$key" '$1==k{n++} END{print n+0}' "$file")
    [ "$count" -eq 1 ] || return 1
    awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$file"
}
vr_state_value() {
    local file="$1" key="$2" count
    count=$(awk -F'|' -v k="$key" '{f=$2; gsub(/^[ \t]+|[ \t]+$/, "", f); if(f==k)n++} END{print n+0}' "$file")
    [ "$count" -eq 1 ] || return 1
    awk -F'|' -v k="$key" '{f=$2; gsub(/^[ \t]+|[ \t]+$/, "", f); if(f==k){v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit}}' "$file"
}
vr_owned_path() {
    local raw="$1" must_exist="${2:-true}" candidate parent
    vr_scalar path "$raw"
    case "$raw" in /*) candidate="$raw" ;; *) candidate="$VR_ROOT/$raw" ;; esac
    if [ "$must_exist" = true ]; then
        [ -f "$candidate" ] && [ ! -L "$candidate" ] || return 1
    else
        mkdir -p "$(dirname "$candidate")" || return 1
        [ ! -L "$candidate" ] || return 1
    fi
    parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
    candidate="$parent/$(basename "$candidate")"
    case "$candidate" in "$VR_ROOT/.forge/local"/*) printf '%s\n' "$candidate" ;; *) return 1 ;; esac
}
vr_iso_epoch() {
    local value="$1" epoch
    epoch=$(date -u -d "$value" +%s 2>/dev/null || true)
    [ -n "$epoch" ] || epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$value" +%s 2>/dev/null || true)
    [ -n "$epoch" ] || return 1
    printf '%s\n' "$epoch"
}
vr_fresh() {
    local value="$1" epoch now age
    epoch=$(vr_iso_epoch "$value") || return 1
    now=$(date +%s); age=$((now - epoch))
    [ "$age" -ge -300 ] && [ "$age" -le "${FORGE_RECEIPT_MAX_AGE_SECONDS:-86400}" ]
}
vr_report_verdict() {
    local report="$1" kind="$2" verdict
    verdict=$(sed -n '1{s/\r$//;s/^VERDICT: //p;}' "$report")
    case "$kind:$verdict" in verify-app:PASS|verify-app:FAIL|verify-app:BLOCKED|e2e:PASS|e2e:FAIL|e2e:PARTIAL) printf '%s\n' "$verdict" ;; *) return 1 ;; esac
}
vr_candidate_current() {
    local receipt="$1" tmp key expected actual base base_ref helper
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 1
    [ "$(vr_kv "$receipt" schema_version 2>/dev/null || true)" = 2 ] || return 1
    [ "$(vr_kv "$receipt" candidate_state 2>/dev/null || true)" = staged-clean ] || return 1
    base=$(vr_kv "$receipt" workflow_base_sha 2>/dev/null) || return 1
    base_ref=$(vr_kv "$receipt" workflow_base_ref 2>/dev/null) || return 1
    helper="$VR_SCRIPT_DIR/candidate-fingerprint.sh"
    [ -f "$helper" ] || helper="$VR_ROOT/hooks/lib/candidate-fingerprint.sh"
    [ -f "$helper" ] || return 1
    tmp=$(mktemp "${TMPDIR:-/tmp}/forge-current-candidate.XXXXXX") || return 1
    if ! bash "$helper" freeze --artifact git:working-tree --workflow-base-sha "$base" \
        --workflow-base-ref "$base_ref" --output "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; return 1; fi
    for key in candidate_id worktree_identity git_head workflow_base_sha index_tree candidate_state; do
        expected=$(vr_kv "$receipt" "$key" 2>/dev/null) || { rm -f "$tmp"; return 1; }
        actual=$(vr_kv "$tmp" "$key" 2>/dev/null) || { rm -f "$tmp"; return 1; }
        [ "$expected" = "$actual" ] || { rm -f "$tmp"; return 1; }
    done
    rm -f "$tmp"
    return 0
}
vr_validate_review() {
    local receipt="$1" role="$2" candidate="$3" iteration="$4" key candidate_id worktree head base output fallback reason requested actual digest
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 1
    for key in schema_version invocation_id timestamp main_host requested_engine actual_engine fallback fallback_reason role profile review_iteration fresh_process artifact_kind artifact_hash worktree_identity git_head workflow_base_sha output_path output_hash process_exit_status semantic_verdict max_severity findings_digest result_schema_version blocked_class; do
        vr_kv "$receipt" "$key" >/dev/null 2>&1 || return 1
    done
    [ "$(vr_kv "$receipt" schema_version)" = 1 ] || return 1
    [ "$(vr_kv "$receipt" role)" = "$role" ] || return 1
    [ "$(vr_kv "$receipt" profile)" = review ] || return 1
    [ "$(vr_kv "$receipt" review_iteration)" = "$iteration" ] || return 1
    [ "$(vr_kv "$receipt" fresh_process)" = true ] || return 1
    vr_fresh "$(vr_kv "$receipt" timestamp)" || return 1
    [ "$(vr_kv "$receipt" artifact_kind)" = git-working-tree ] || return 1
    candidate_id=$(vr_kv "$candidate" candidate_id) || return 1
    worktree=$(vr_kv "$candidate" worktree_identity) || return 1
    head=$(vr_kv "$candidate" git_head) || return 1
    base=$(vr_kv "$candidate" workflow_base_sha) || return 1
    [ "$(vr_kv "$receipt" artifact_hash)" = "$candidate_id" ] || return 1
    [ "$(vr_kv "$receipt" worktree_identity)" = "$worktree" ] || return 1
    [ "$(vr_kv "$receipt" git_head)" = "$head" ] || return 1
    [ "$(vr_kv "$receipt" workflow_base_sha)" = "$base" ] || return 1
    [ "$(vr_kv "$receipt" process_exit_status)" = 0 ] || return 1
    [ "$(vr_kv "$receipt" semantic_verdict)" = CLEAN ] || return 1
    case "$(vr_kv "$receipt" max_severity)" in NONE|P3) ;; *) return 1 ;; esac
    [ "$(vr_kv "$receipt" blocked_class)" = none ] || return 1
    digest=$(vr_kv "$receipt" findings_digest)
    [ "${#digest}" -eq 64 ] || return 1
    case "$digest" in *[!0-9a-fA-F]*) return 1 ;; esac
    output=$(vr_owned_path "$(vr_kv "$receipt" output_path)" true) || return 1
    [ "$(vr_hash_file "$output")" = "$(vr_kv "$receipt" output_hash)" ] || return 1
    requested=$(vr_kv "$receipt" requested_engine); actual=$(vr_kv "$receipt" actual_engine)
    case "$requested" in auto|claude|codex) ;; *) return 1 ;; esac
    case "$actual" in claude|codex) ;; *) return 1 ;; esac
    fallback=$(vr_kv "$receipt" fallback); reason=$(vr_kv "$receipt" fallback_reason)
    case "$fallback" in
        false) [ "$reason" = none ] || return 1; [ "$requested" = auto ] || [ "$requested" = "$actual" ] || return 1 ;;
        true) [ -n "$reason" ] && [ "$reason" != none ] || return 1 ;;
        *) return 1 ;;
    esac
    return 0
}
vr_validate_verifier() {
    local receipt="$1" kind="$2" candidate="$3" key report candidate_id report_verdict
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 1
    for key in schema_version receipt_kind invocation_id started_at ended_at candidate_id worktree_identity git_head workflow_base_sha index_tree command_hash profile exit_status report_path report_hash report_verdict result; do
        vr_kv "$receipt" "$key" >/dev/null 2>&1 || return 1
    done
    [ "$(vr_kv "$receipt" schema_version)" = 2 ] || return 1
    [ "$(vr_kv "$receipt" receipt_kind)" = "$kind" ] || return 1
    vr_fresh "$(vr_kv "$receipt" ended_at)" || return 1
    [ "$(vr_kv "$receipt" exit_status)" = 0 ] || return 1
    [ "$(vr_kv "$receipt" result)" = PASS ] || return 1
    [ "$(vr_kv "$receipt" report_verdict)" = PASS ] || return 1
    candidate_id=$(vr_kv "$candidate" candidate_id) || return 1
    for key in candidate_id worktree_identity git_head workflow_base_sha index_tree; do
        [ "$(vr_kv "$receipt" "$key")" = "$(vr_kv "$candidate" "$key")" ] || return 1
    done
    report=$(vr_owned_path "$(vr_kv "$receipt" report_path)" true) || return 1
    [ "$(vr_hash_file "$report")" = "$(vr_kv "$receipt" report_hash)" ] || return 1
    report_verdict=$(vr_report_verdict "$report" "$kind") || return 1
    [ "$report_verdict" = "$(vr_kv "$receipt" report_verdict)" ] || return 1
    return 0
}

VR_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 2
VR_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || vr_die 'Git worktree required'
VR_ROOT=$(cd "$VR_ROOT" && pwd -P)
mode="${1:-}"; [ "$#" -gt 0 ] && shift

if [ "$mode" = write ]; then
    kind=""; candidate=""; command_text=""; profile=""; report=""; result=""; status=""; output=""; started=""; ended=""
    while [ "$#" -gt 0 ]; do case "$1" in
        --kind) kind="${2:-}"; shift 2 ;; --candidate) candidate="${2:-}"; shift 2 ;;
        --command) command_text="${2:-}"; shift 2 ;; --profile) profile="${2:-}"; shift 2 ;;
        --report) report="${2:-}"; shift 2 ;; --result) result="${2:-}"; shift 2 ;;
        --exit-status) status="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;;
        --started-at) started="${2:-}"; shift 2 ;; --ended-at) ended="${2:-}"; shift 2 ;;
        *) vr_die "unknown write argument $1" ;; esac; done
    case "$kind" in verify-app|e2e) ;; *) vr_die 'kind must be verify-app or e2e' ;; esac
    case "$result" in PASS|FAIL|BLOCKED|PARTIAL) ;; *) vr_die 'invalid verifier result' ;; esac
    case "$status" in ''|*[!0-9]*) vr_die 'numeric exit status is required' ;; esac
    vr_scalar command "$command_text"; vr_scalar profile "$profile"
    candidate=$(vr_owned_path "$candidate" true) || vr_die 'candidate receipt must be Forge-local'
    vr_candidate_current "$candidate" || vr_die 'candidate is not the current staged-clean identity'
    report=$(vr_owned_path "$report" true) || vr_die 'report must be a Forge-local regular file'
    report_verdict=$(vr_report_verdict "$report" "$kind") || vr_die 'report must begin with a canonical VERDICT header for its verifier kind'
    [ "$report_verdict" = "$result" ] || vr_die 'report verdict and requested receipt result differ'
    output=$(vr_owned_path "$output" false) || vr_die 'receipt output must be Forge-local'
    [ -n "$started" ] || started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    [ -n "$ended" ] || ended=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    vr_fresh "$started" && vr_fresh "$ended" || vr_die 'verifier timestamps are invalid or stale'
    invocation=$(printf '%s|%s|%s|%s|%s\n' "$kind" "$started" "$$" "$command_text" "$(vr_kv "$candidate" candidate_id)" | vr_hash_stream)
    tmp="$output.tmp.$$"
    {
        printf 'schema_version=2\nreceipt_kind=%s\ninvocation_id=%s\nstarted_at=%s\nended_at=%s\n' "$kind" "$invocation" "$started" "$ended"
        for key in candidate_id worktree_identity git_head workflow_base_sha index_tree; do printf '%s=%s\n' "$key" "$(vr_kv "$candidate" "$key")"; done
        printf 'command_hash=%s\nprofile=%s\nexit_status=%s\nreport_path=%s\nreport_hash=%s\nreport_verdict=%s\nresult=%s\n' \
            "$(printf '%s' "$command_text" | vr_hash_stream)" "$profile" "$status" "$report" "$(vr_hash_file "$report")" "$report_verdict" "$result"
    } > "$tmp" || vr_die 'cannot write verifier receipt'
    mv "$tmp" "$output" || vr_die 'cannot publish verifier receipt'
    printf 'RECEIPT:%s\n' "$output"
    exit 0
fi

[ "$mode" = check ] || vr_die 'usage: verification-receipt.sh write|check ...'
state=""
while [ "$#" -gt 0 ]; do case "$1" in --state) state="${2:-}"; shift 2 ;; *) vr_die "unknown check argument $1" ;; esac; done
[ -n "$state" ] || state=.forge/local/state.md
case "$state" in /*) ;; *) state="$VR_ROOT/$state" ;; esac
[ -f "$state" ] && [ ! -L "$state" ] || vr_die 'canonical state is required'
[ "$(sed -n '1p' "$state")" = '<!-- forge:state-schema v6 -->' ] || vr_die 'receipt-v2 requires canonical v6 state'
candidate=$(vr_state_value "$state" 'Candidate receipt' 2>/dev/null) || vr_die 'Candidate receipt state linkage is missing'
spec=$(vr_state_value "$state" 'Spec review receipt' 2>/dev/null) || vr_die 'Spec review receipt state linkage is missing'
quality=$(vr_state_value "$state" 'Quality review receipt' 2>/dev/null) || vr_die 'Quality review receipt state linkage is missing'
verify_app=$(vr_state_value "$state" 'Verify app receipt' 2>/dev/null) || vr_die 'Verify app receipt state linkage is missing'
e2e=$(vr_state_value "$state" 'E2E receipt' 2>/dev/null) || vr_die 'E2E receipt state linkage is missing'
iteration=$(vr_state_value "$state" 'Review iteration' 2>/dev/null) || vr_die 'Review iteration state linkage is missing'
case "$iteration" in ''|*[!0-9]*) vr_die 'Review iteration must be numeric' ;; esac
candidate=$(vr_owned_path "$candidate" true) || vr_die 'candidate receipt path is invalid'
spec=$(vr_owned_path "$spec" true) || vr_die 'spec receipt path is invalid'
quality=$(vr_owned_path "$quality" true) || vr_die 'quality receipt path is invalid'
verify_app=$(vr_owned_path "$verify_app" true) || vr_die 'verify-app receipt path is invalid'
e2e=$(vr_owned_path "$e2e" true) || vr_die 'E2E receipt path is invalid'
candidate_ok=false; reviews_ok=false; app_ok=false; e2e_ok=false
vr_candidate_current "$candidate" && candidate_ok=true
if [ "$candidate_ok" = true ] && vr_validate_review "$spec" code-spec "$candidate" "$iteration" && vr_validate_review "$quality" code-quality "$candidate" "$iteration"; then
    spec_id=$(vr_kv "$spec" invocation_id); quality_id=$(vr_kv "$quality" invocation_id)
    [ "$spec_id" != "$quality_id" ] && reviews_ok=true
fi
[ "$candidate_ok" = true ] && vr_validate_verifier "$verify_app" verify-app "$candidate" && app_ok=true
[ "$candidate_ok" = true ] && vr_validate_verifier "$e2e" e2e "$candidate" && e2e_ok=true
ship=false; [ "$candidate_ok:$reviews_ok:$app_ok:$e2e_ok" = true:true:true:true ] && ship=true
printf 'CANDIDATE_VALID:%s\nREVIEWS_VALID:%s\nVERIFY_APP_VALID:%s\nE2E_VALID:%s\nREVIEW_ITERATION:%s\nCANDIDATE_ID:%s\nSHIP_READY:%s\n' \
    "$candidate_ok" "$reviews_ok" "$app_ok" "$e2e_ok" "$iteration" "$(vr_kv "$candidate" candidate_id 2>/dev/null || true)" "$ship"
[ "$ship" = true ] || exit 2
exit 0
