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
    case "$kind:$verdict" in verify-app:PASS|verify-app:FAIL|verify-app:BLOCKED|e2e:PASS|e2e:FAIL|e2e:PARTIAL|e2e:N/A) printf '%s\n' "$verdict" ;; *) return 1 ;; esac
}
vr_e2e_na_reason() {
    local report="$1" reason
    reason=$(sed -n '3{s/\r$//;s/^N\/A_REASON: //p;}' "$report")
    [ -n "$(printf '%s' "$reason" | tr -d '[:space:]')" ] || return 1
    printf '%s\n' "$reason"
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
    if ! bash "$helper" identity --artifact git:working-tree --workflow-base-sha "$base" \
        --workflow-base-ref "$base_ref" --output "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; return 1; fi
    for key in candidate_id worktree_identity git_head workflow_base_sha index_tree candidate_state; do
        expected=$(vr_kv "$receipt" "$key" 2>/dev/null) || { rm -f "$tmp"; return 1; }
        actual=$(vr_kv "$tmp" "$key" 2>/dev/null) || { rm -f "$tmp"; return 1; }
        [ "$expected" = "$actual" ] || { rm -f "$tmp"; return 1; }
    done
    rm -f "$tmp"
    return 0
}
vr_candidate_promoted() {
    local candidate="$1" promotion="$2" tmp key base base_ref old_id old_head tree worktree helper
    local current_head temporary branch_commit branch_tree post_status post_dirty expected_id parent_line
    [ -f "$promotion" ] && [ ! -L "$promotion" ] || return 1
    for key in schema_version old_candidate_id old_head temporary_commit new_branch_commit new_branch_tree worktree_identity post_commit_status post_commit_dirty; do
        vr_kv "$promotion" "$key" >/dev/null 2>&1 || return 1
    done
    [ "$(vr_kv "$promotion" schema_version)" = 2 ] || return 1
    [ "$(vr_kv "$candidate" schema_version 2>/dev/null || true)" = 2 ] || return 1
    [ "$(vr_kv "$candidate" candidate_state 2>/dev/null || true)" = staged-clean ] || return 1
    old_id=$(vr_kv "$candidate" candidate_id) || return 1
    old_head=$(vr_kv "$candidate" git_head) || return 1
    base=$(vr_kv "$candidate" workflow_base_sha) || return 1
    base_ref=$(vr_kv "$candidate" workflow_base_ref) || return 1
    tree=$(vr_kv "$candidate" index_tree) || return 1
    worktree=$(vr_kv "$candidate" worktree_identity) || return 1
    expected_id=$(printf '%s\n' "$base" "$old_head" "$tree" "$worktree" | vr_hash_stream)
    [ "$old_id" = "$expected_id" ] || return 1
    [ "$(vr_kv "$promotion" old_candidate_id)" = "$old_id" ] || return 1
    [ "$(vr_kv "$promotion" old_head)" = "$old_head" ] || return 1
    [ "$(vr_kv "$promotion" worktree_identity)" = "$worktree" ] || return 1
    temporary=$(vr_kv "$promotion" temporary_commit) || return 1
    branch_commit=$(vr_kv "$promotion" new_branch_commit) || return 1
    branch_tree=$(vr_kv "$promotion" new_branch_tree) || return 1
    current_head=$(git -C "$VR_ROOT" rev-parse HEAD 2>/dev/null) || return 1
    [ "$temporary" = "$branch_commit" ] && [ "$branch_commit" = "$current_head" ] || return 1
    [ "$branch_tree" = "$tree" ] || return 1
    [ "$(git -C "$VR_ROOT" rev-parse "$current_head^{tree}" 2>/dev/null)" = "$tree" ] || return 1
    parent_line=$(git -C "$VR_ROOT" rev-list --parents -n 1 "$current_head" 2>/dev/null) || return 1
    [ "$(printf '%s\n' "$parent_line" | awk '{print NF}')" -eq 2 ] || return 1
    [ "$(printf '%s\n' "$parent_line" | awk '{print $2}')" = "$old_head" ] || return 1
    post_status=$(vr_kv "$promotion" post_commit_status) || return 1
    case "$post_status" in pass|not-run) ;; *) return 1 ;; esac
    post_dirty=$(vr_kv "$promotion" post_commit_dirty) || return 1
    [ "$post_dirty" = false ] || return 1
    tmp=$(mktemp "${TMPDIR:-/tmp}/forge-promoted-candidate.XXXXXX") || return 1
    helper="$VR_SCRIPT_DIR/candidate-fingerprint.sh"
    [ -f "$helper" ] || helper="$VR_ROOT/hooks/lib/candidate-fingerprint.sh"
    [ -f "$helper" ] || { rm -f "$tmp"; return 1; }
    if ! bash "$helper" identity --artifact git:working-tree --workflow-base-sha "$base" \
        --workflow-base-ref "$base_ref" --output "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; return 1; fi
    [ "$(vr_kv "$tmp" git_head 2>/dev/null || true)" = "$current_head" ] || { rm -f "$tmp"; return 1; }
    for key in worktree_identity workflow_base_sha index_tree candidate_state; do
        [ "$(vr_kv "$tmp" "$key" 2>/dev/null || true)" = "$(vr_kv "$candidate" "$key" 2>/dev/null || true)" ] \
            || { rm -f "$tmp"; return 1; }
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
    case "$(vr_kv "$receipt" semantic_verdict):$(vr_kv "$receipt" max_severity)" in
        CLEAN:NONE|CLEAN:P3|FINDINGS:P3) ;; *) return 1 ;;
    esac
    [ "$(vr_kv "$receipt" blocked_class)" = none ] || return 1
    digest=$(vr_kv "$receipt" findings_digest)
    [ "${#digest}" -eq 64 ] || return 1
    case "$digest" in *[!0-9a-fA-F]*) return 1 ;; esac
    output=$(vr_owned_path "$(vr_kv "$receipt" output_path)" true) || return 1
    [ "$(vr_hash_file "$output")" = "$(vr_kv "$receipt" output_hash)" ] || return 1
    [ "$(vr_kv "$output" schema_version)" = 1 ] && [ "$(vr_kv "$output" blocked_class)" = none ] || return 1
    [ "$(vr_kv "$output" verdict)" = "$(vr_kv "$receipt" semantic_verdict)" ] \
        && [ "$(vr_kv "$output" max_severity)" = "$(vr_kv "$receipt" max_severity)" ] || return 1
    # A P3 label cannot conceal a material finding in the hash-bound output.
    awk -F= -v verdict="$(vr_kv "$output" verdict)" '
        $1=="finding" { n++; sub(/^[^=]*=/, ""); split($0, fields, "|"); if(fields[2]!="P3") bad=1 }
        END { exit (bad || (verdict=="FINDINGS" && !n)) ? 1 : 0 }
    ' "$output" || return 1
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
    local receipt="$1" kind="$2" candidate="$3" key report candidate_id report_verdict result actual_verdict
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 1
    for key in schema_version receipt_kind invocation_id started_at ended_at candidate_id worktree_identity git_head workflow_base_sha index_tree command_hash profile exit_status report_path report_hash report_verdict result; do
        vr_kv "$receipt" "$key" >/dev/null 2>&1 || return 1
    done
    [ "$(vr_kv "$receipt" schema_version)" = 2 ] || return 1
    [ "$(vr_kv "$receipt" receipt_kind)" = "$kind" ] || return 1
    vr_fresh "$(vr_kv "$receipt" ended_at)" || return 1
    [ "$(vr_kv "$receipt" exit_status)" = 0 ] || return 1
    candidate_id=$(vr_kv "$candidate" candidate_id) || return 1
    for key in candidate_id worktree_identity git_head workflow_base_sha index_tree; do
        [ "$(vr_kv "$receipt" "$key")" = "$(vr_kv "$candidate" "$key")" ] || return 1
    done
    report=$(vr_owned_path "$(vr_kv "$receipt" report_path)" true) || return 1
    [ "$(vr_hash_file "$report")" = "$(vr_kv "$receipt" report_hash)" ] || return 1
    actual_verdict=$(vr_report_verdict "$report" "$kind") || return 1
    report_verdict=$(vr_kv "$receipt" report_verdict)
    result=$(vr_kv "$receipt" result)
    [ "$actual_verdict" = "$report_verdict" ] || return 1
    case "$kind:$result:$report_verdict" in
        verify-app:PASS:PASS|e2e:PASS:PASS) ;;
        e2e:N/A:N/A) vr_e2e_na_reason "$report" >/dev/null || return 1 ;;
        *) return 1 ;;
    esac
    return 0
}


# A docs closure carries original evidence; it never changes what a receipt tested.
vr_docs_bundle() {
    vr_validate_review "$spec" code-spec "$1" "$iteration" && \
        vr_validate_review "$quality" code-quality "$1" "$iteration" && \
        [ "$(vr_kv "$spec" invocation_id)" != "$(vr_kv "$quality" invocation_id)" ] && \
        vr_validate_verifier "$verify_app" verify-app "$1" && vr_validate_verifier "$e2e" e2e "$1"
}
vr_docs_identity() {
    local source="$1" target="$2" key base head tree worktree
    [ "$(vr_kv "$source" schema_version)" = 2 ] && [ "$(vr_kv "$source" candidate_state)" = staged-clean ] || return 1
    for key in workflow_base_ref workflow_base_sha worktree_identity; do
        [ "$(vr_kv "$source" "$key")" = "$(vr_kv "$target" "$key")" ] || return 1
    done
    base=$(vr_kv "$source" workflow_base_sha); head=$(vr_kv "$source" git_head)
    tree=$(vr_kv "$source" index_tree); worktree=$(vr_kv "$source" worktree_identity)
    case "$base$head$tree" in *[!0-9a-f]*) return 1 ;; esac
    [ -n "$base" ] && [ -n "$head" ] && [ -n "$tree" ] || return 1
    [ "$(vr_kv "$source" candidate_id)" = "$(printf '%s\n' "$base" "$head" "$tree" "$worktree" | vr_hash_stream)" ] || return 1
    git -C "$VR_ROOT" cat-file -e "$head^{commit}" 2>/dev/null && git -C "$VR_ROOT" cat-file -e "$tree^{tree}" 2>/dev/null
}
vr_docs_parent() {
    local source="$1" target="$2" promotion="$3" head commit parents key
    head=$(vr_kv "$source" git_head); commit=$(vr_kv "$target" git_head)
    if [ "$head" = "$commit" ]; then [ "$promotion" = none ]; return $?; fi
    [ "$promotion" != none ] && [ -f "$promotion" ] && [ ! -L "$promotion" ] || return 1
    [ "$(vr_kv "$promotion" schema_version)" = 2 ] || return 1
    [ "$(vr_kv "$promotion" old_candidate_id)" = "$(vr_kv "$source" candidate_id)" ] && \
        [ "$(vr_kv "$promotion" old_head)" = "$head" ] && \
        [ "$(vr_kv "$promotion" worktree_identity)" = "$(vr_kv "$source" worktree_identity)" ] && \
        [ "$(vr_kv "$promotion" temporary_commit)" = "$commit" ] && \
        [ "$(vr_kv "$promotion" new_branch_commit)" = "$commit" ] && \
        [ "$(vr_kv "$promotion" new_branch_tree)" = "$(vr_kv "$source" index_tree)" ] && \
        [ "$(vr_kv "$promotion" post_commit_dirty)" = false ] || return 1
    case "$(vr_kv "$promotion" post_commit_status)" in pass|not-run) ;; *) return 1 ;; esac
    [ "$(git -C "$VR_ROOT" rev-parse "$commit^{tree}" 2>/dev/null)" = "$(vr_kv "$source" index_tree)" ] || return 1
    parents=$(git -C "$VR_ROOT" rev-list --parents -n 1 "$commit" 2>/dev/null) || return 1
    [ "$parents" = "$commit $head" ]
}
vr_docs_path() {
    local path="$1" lower base
    case "$path" in /*|*'..'*|*'\'*|*'*'*|*'?'*|*'['*|*']'*) return 1 ;; esac
    lower=$(printf '%s' "$path" | LC_ALL=C tr '[:upper:]' '[:lower:]'); base=${lower##*/}
    case "$lower" in docs/*|changelog.md) ;; *) return 1 ;; esac
    case "$lower" in */plans/*|*/requirements/*|*/.forge/*|*/.claude/*|*/.codex/*|*/.agents/*|*/commands/*|*/rules/*|*/skills/*|*/agents/*|*/hooks/*|*/scripts/*|*/settings/*|*/templates/*|*/manifests/*|*/tests/*) return 1 ;; esac
    case "$base" in agents.*|claude.*|forge.template.*|contributing*|agent-context.*|policy*|instructions*|requirements*|prd.*|design.*|config*|plan.*) return 1 ;; esac
    case "$base" in *.md|*.markdown) return 0 ;; *) return 1 ;; esac
}
vr_docs_blob() {
    local entry
    entry=$(git -C "$VR_ROOT" ls-tree "$1" -- "$2" 2>/dev/null) || return 1
    [ "${entry%% *}" = 100644 ] || return 1
    printf '%s\n' "$entry" | awk '{print $3}'
}
vr_docs_delta() (
    # Only this opt-in tail pays for a tree diff; ordinary gates stay unchanged.
    local source="$1" target="$2" old new policy old_blob new_blob marker tmp meta path extra count=0 tab key
    old=$(vr_kv "$source" index_tree); new=$(vr_kv "$target" index_tree)
    policy=.forge/verification-scope.tsv
    if ! git -C "$VR_ROOT" cat-file -e "$old:$policy" 2>/dev/null && ! git -C "$VR_ROOT" cat-file -e "$new:$policy" 2>/dev/null; then
        for marker in FORGE.template.md state.template.md manifests/managed-v6.tsv; do
            vr_docs_blob "$old" "$marker" >/dev/null && vr_docs_blob "$new" "$marker" >/dev/null || return 1
        done
        policy=manifests/verification-scope.tsv
    fi
    old_blob=$(vr_docs_blob "$old" "$policy") && new_blob=$(vr_docs_blob "$new" "$policy") || return 1
    [ -n "$old_blob" ] && [ "$old_blob" = "$new_blob" ] || return 1
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/forge-docs-delta.XXXXXX") || return 1
    trap 'rm -f "$tmp/policy" "$tmp/raw" "$tmp/blob" "$tmp/old-heading" "$tmp/new-heading"; rmdir "$tmp" 2>/dev/null || true' EXIT
    git -C "$VR_ROOT" show "$old:$policy" | sed 's/\r$//' > "$tmp/policy" || return 1
    [ "$(sed -n '1p' "$tmp/policy")" = '# forge:non-runtime-prose v1' ] || return 1
    awk -F'\t' 'NR==1 || /^#/ || /^$/ {next} NF!=2 || $1!="prose" || $2=="" || substr($2,1,1)=="/" || index($2,"..") || index($2,"*") || index($2,"?") || index($2,"[") || index($2,"]") || $2 ~ /[[:cntrl:]]/ || seen[$2]++ {exit 1}' "$tmp/policy" || return 1
    git -C "$VR_ROOT" -c core.quotePath=true diff --raw --no-abbrev --no-renames --no-ext-diff --no-textconv "$old" "$new" -- > "$tmp/raw" || return 1
    tab=$(printf '\t')
    while IFS="$tab" read -r meta path extra; do
        [ -n "$path" ] && [ -z "$extra" ] || return 1
        set -- $meta
        [ "$#" -eq 5 ] && [ "$1" = :100644 ] && [ "$2" = 100644 ] && [ "$5" = M ] || return 1
        vr_docs_path "$path" && grep -Fqx -- "prose$tab$path" "$tmp/policy" || return 1
        for key in "$old" "$new"; do
            git -C "$VR_ROOT" show "$key:$path" > "$tmp/blob" || return 1
            [ "$(wc -c < "$tmp/blob" | tr -d '[:space:]')" = "$(LC_ALL=C tr -d '\000' < "$tmp/blob" | wc -c | tr -d '[:space:]')" ] || return 1
        done
        case "$(printf '%s' "${path##*/}" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in changelog.md|changelog.markdown)
            git -C "$VR_ROOT" show "$old:$path" | sed -n '/^##[[:space:]]/{p;q;}' > "$tmp/old-heading"
            git -C "$VR_ROOT" show "$new:$path" | sed -n '/^##[[:space:]]/{p;q;}' > "$tmp/new-heading"
            [ -s "$tmp/old-heading" ] && cmp -s "$tmp/old-heading" "$tmp/new-heading" || return 1 ;;
        esac
        count=$((count + 1))
    done < "$tmp/raw"
    [ "$count" -gt 0 ] || return 1
    git -C "$VR_ROOT" diff --no-ext-diff --no-textconv --check "$old" "$new" -- >/dev/null 2>&1 || return 1
    printf 'policy_path=%s\npolicy_blob=%s\ndelta_hash=%s\n' "$policy" "$old_blob" "$(vr_hash_file "$tmp/raw")"
)
vr_docs_archive() {
    local input="$1" output="$2"
    output=$(vr_owned_path "$output" false) || return 1
    if [ -e "$output" ]; then [ "$(vr_hash_file "$input")" = "$(vr_hash_file "$output")" ] || return 1
    else
        vr_owned_path "$output.tmp.$$" false >/dev/null || return 1
        cp "$input" "$output.tmp.$$" && mv "$output.tmp.$$" "$output" || return 1
    fi
    printf '%s\n' "$output"
}
vr_docs_validate() {
    local closure="$candidate.docs-closure" source promotion metadata key input expected
    closure=$(vr_owned_path "$closure" true) || return 1
    [ "$(vr_kv "$closure" schema_version)" = 1 ] && [ "$(vr_kv "$closure" receipt_kind)" = docs-closure ] && \
        [ "$(vr_kv "$closure" docs_check)" = PASS ] && [ "$(vr_kv "$closure" review_iteration)" = "$iteration" ] || return 1
    vr_fresh "$(vr_kv "$closure" closed_at)" || return 1
    [ "$(vr_kv "$closure" new_candidate_hash)" = "$(vr_hash_file "$candidate")" ] && \
        [ "$(vr_kv "$closure" new_candidate_id)" = "$(vr_kv "$candidate" candidate_id)" ] || return 1
    source=$(vr_owned_path "$(vr_kv "$closure" original_candidate_path)" true) || return 1
    [ "$(vr_kv "$closure" original_candidate_hash)" = "$(vr_hash_file "$source")" ] && vr_docs_identity "$source" "$candidate" || return 1
    promotion=$(vr_kv "$closure" source_promotion_path) || return 1
    if [ "$promotion" != none ]; then
        promotion=$(vr_owned_path "$promotion" true) || return 1
        [ "$(vr_hash_file "$promotion")" = "$(vr_kv "$closure" source_promotion_hash)" ] || return 1
    else [ "$(vr_kv "$closure" source_promotion_hash)" = none ] || return 1; fi
    vr_docs_parent "$source" "$candidate" "$promotion" || return 1
    for key in spec quality verify_app e2e; do
        case "$key" in spec) input="$spec" ;; quality) input="$quality" ;; verify_app) input="$verify_app" ;; e2e) input="$e2e" ;; esac
        [ "$(vr_hash_file "$input")" = "$(vr_kv "$closure" "${key}_receipt_hash")" ] || return 1
    done
    vr_docs_bundle "$source" || return 1
    metadata=$(vr_docs_delta "$source" "$candidate") || return 1
    for key in policy_path policy_blob delta_hash; do
        expected=$(printf '%s\n' "$metadata" | sed -n "s/^$key=//p")
        [ "$expected" = "$(vr_kv "$closure" "$key")" ] || return 1
    done
}
vr_docs_close() {
    local source="$1" promotion=none archived metadata closure tmp key input promotion_hash=none
    vr_candidate_current "$candidate" || vr_die 'docs closure needs the current staged-clean final candidate'
    source=$(vr_owned_path "$source" true) || vr_die 'previous candidate must be Forge-local'
    vr_docs_identity "$source" "$candidate" && vr_docs_bundle "$source" || vr_die 'original candidate lacks a complete fresh passing receipt set'
    if [ "$(vr_kv "$source" git_head)" != "$(vr_kv "$candidate" git_head)" ]; then
        promotion=$(vr_owned_path "$(vr_state_value "$state" 'Promotion receipt')" true) || vr_die 'original exact promotion provenance is missing'
    fi
    vr_docs_parent "$source" "$candidate" "$promotion" || vr_die 'candidate parent changed outside the original exact Forge promotion'
    metadata=$(vr_docs_delta "$source" "$candidate") || vr_die 'delta is outside the declared non-runtime prose contract or fails its focused check'
    archived=$(vr_docs_archive "$source" "$candidate.docs-original-$(vr_kv "$source" candidate_id).receipt") || vr_die 'cannot preserve original candidate'
    if [ "$promotion" != none ]; then
        promotion_hash=$(vr_hash_file "$promotion")
        promotion=$(vr_docs_archive "$promotion" "$candidate.docs-promotion-$promotion_hash.receipt") || vr_die 'cannot preserve original promotion'
    fi
    vr_candidate_current "$candidate" && vr_docs_bundle "$archived" && vr_docs_parent "$archived" "$candidate" "$promotion" \
        && [ "$metadata" = "$(vr_docs_delta "$archived" "$candidate")" ] || vr_die 'candidate or original evidence changed during docs closure'
    closure=$(vr_owned_path "$candidate.docs-closure" false) || vr_die 'invalid closure output'
    tmp=$(vr_owned_path "$closure.tmp.$$" false) || vr_die 'invalid temporary closure output'
    {
        printf 'schema_version=1\nreceipt_kind=docs-closure\nclosed_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'original_candidate_path=%s\noriginal_candidate_hash=%s\nnew_candidate_id=%s\nnew_candidate_hash=%s\n' "$archived" "$(vr_hash_file "$archived")" "$(vr_kv "$candidate" candidate_id)" "$(vr_hash_file "$candidate")"
        printf 'source_promotion_path=%s\nsource_promotion_hash=%s\nreview_iteration=%s\n' "$promotion" "$promotion_hash" "$iteration"
        for key in spec quality verify_app e2e; do
            case "$key" in spec) input="$spec" ;; quality) input="$quality" ;; verify_app) input="$verify_app" ;; e2e) input="$e2e" ;; esac
            printf '%s_receipt_hash=%s\n' "$key" "$(vr_hash_file "$input")"
        done
        printf '%s\ndocs_check=PASS\n' "$metadata"
    } > "$tmp" && mv "$tmp" "$closure" || vr_die 'cannot publish docs closure'
    printf 'DOCS_CLOSURE:%s\n' "$closure"
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
    case "$result" in PASS|FAIL|BLOCKED|PARTIAL|N/A) ;; *) vr_die 'invalid verifier result' ;; esac
    case "$status" in ''|*[!0-9]*) vr_die 'numeric exit status is required' ;; esac
    vr_scalar command "$command_text"; vr_scalar profile "$profile"
    candidate=$(vr_owned_path "$candidate" true) || vr_die 'candidate receipt must be Forge-local'
    vr_candidate_current "$candidate" || vr_die 'candidate is not the current staged-clean identity'
    report=$(vr_owned_path "$report" true) || vr_die 'report must be a Forge-local regular file'
    report_verdict=$(vr_report_verdict "$report" "$kind") || vr_die 'report must begin with a canonical VERDICT header for its verifier kind'
    [ "$report_verdict" = "$result" ] || vr_die 'report verdict and requested receipt result differ'
    if [ "$result" = N/A ]; then
        [ "$kind" = e2e ] && [ "$status" = 0 ] || vr_die 'N/A is valid only for a successful E2E scope decision'
        vr_e2e_na_reason "$report" >/dev/null || vr_die 'E2E N/A report requires a concrete line-3 N/A_REASON'
    fi
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

[ "$mode" = check ] || [ "$mode" = close-docs ] || vr_die 'usage: verification-receipt.sh write|check|close-docs ...'
state=""; previous_candidate=""
while [ "$#" -gt 0 ]; do case "$1" in --state) state="${2:-}"; shift 2 ;; --previous-candidate) previous_candidate="${2:-}"; shift 2 ;; *) vr_die "unknown check argument $1" ;; esac; done
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
if [ "$mode" = close-docs ]; then vr_docs_close "$previous_candidate"; exit 0; fi
candidate_ok=false; reviews_ok=false; app_ok=false; e2e_ok=false
if vr_candidate_current "$candidate"; then
    candidate_ok=true
else
    promotion=$(vr_state_value "$state" 'Promotion receipt' 2>/dev/null || true)
    promotion=$(vr_owned_path "$promotion" true 2>/dev/null || true)
    [ -n "$promotion" ] && vr_candidate_promoted "$candidate" "$promotion" && candidate_ok=true
fi
if [ "$candidate_ok" = true ] && vr_validate_review "$spec" code-spec "$candidate" "$iteration" && vr_validate_review "$quality" code-quality "$candidate" "$iteration"; then
    spec_id=$(vr_kv "$spec" invocation_id); quality_id=$(vr_kv "$quality" invocation_id)
    [ "$spec_id" != "$quality_id" ] && reviews_ok=true
fi
[ "$candidate_ok" = true ] && vr_validate_verifier "$verify_app" verify-app "$candidate" && app_ok=true
[ "$candidate_ok" = true ] && vr_validate_verifier "$e2e" e2e "$candidate" && e2e_ok=true
if [ "$candidate_ok" = true ] && [ "$reviews_ok:$app_ok:$e2e_ok" != true:true:true ] && vr_docs_validate; then
    reviews_ok=true; app_ok=true; e2e_ok=true
fi
ship=false; [ "$candidate_ok:$reviews_ok:$app_ok:$e2e_ok" = true:true:true:true ] && ship=true
printf 'CANDIDATE_VALID:%s\nREVIEWS_VALID:%s\nVERIFY_APP_VALID:%s\nE2E_VALID:%s\nREVIEW_ITERATION:%s\nCANDIDATE_ID:%s\nSHIP_READY:%s\n' \
    "$candidate_ok" "$reviews_ok" "$app_ok" "$e2e_ok" "$iteration" "$(vr_kv "$candidate" candidate_id 2>/dev/null || true)" "$ship"
[ "$ship" = true ] || exit 2
exit 0
