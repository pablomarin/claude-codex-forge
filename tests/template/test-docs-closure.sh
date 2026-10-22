#!/usr/bin/env bash
# Deterministic receipt fixtures: documentation closure preserves executed evidence.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
S=$(scratch_dir docs-closure)
VR="$REPO_ROOT/hooks/lib/verification-receipt.sh"
FP="$REPO_ROOT/hooks/lib/candidate-fingerprint.sh"
kv() { sed -n "s/^$2=//p" "$1"; }

freeze() {
    (cd "$P" && bash "$FP" freeze --artifact git:working-tree --workflow-base-ref main \
        --workflow-base-sha "$BASE" --output .forge/local/evidence/candidate.receipt) > "$S/freeze.log" 2>&1
}
check() { (cd "$P" && bash "$VR" check --state .forge/local/state.md) > "$S/check.log" 2>&1; }
close_docs() {
    (cd "$P" && bash "$VR" close-docs --state .forge/local/state.md \
        --previous-candidate .forge/local/evidence/original.receipt) > "$S/close.log" 2>&1
}
review_fixture() {
    local role="$1" engine="$2" fallback="$3" candidate="$P/.forge/local/evidence/candidate.receipt"
    local report="$P/.forge/local/reviews/$role.report" reason=none
    [ "$fallback" = false ] || reason=preferred-engine-unavailable
    printf 'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n' > "$report"
    cat > "$P/.forge/local/reviews/$role.receipt" <<EOF
schema_version=1
invocation_id=$role-$MAIN-$fallback
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
main_host=$MAIN
requested_engine=$OTHER
actual_engine=$engine
fallback=$fallback
fallback_reason=$reason
role=$role
profile=review
review_iteration=1
fresh_process=true
artifact_kind=git-working-tree
artifact_hash=$(kv "$candidate" candidate_id)
worktree_identity=$(kv "$candidate" worktree_identity)
git_head=$(kv "$candidate" git_head)
workflow_base_sha=$BASE
output_path=$report
output_hash=$(hash_file "$report")
process_exit_status=0
semantic_verdict=CLEAN
max_severity=NONE
findings_digest=$(printf '' | shasum -a 256 | awk '{print $1}')
result_schema_version=1
blocked_class=none
EOF
}
fixture() {
    local name="$1" scope="${2:-docs/guide.md}" fallback="${3:-false}" policy_mode="${4:-installed}"
    P="$S/$name"; mkdir -p "$P/.forge/local/evidence" "$P/.forge/local/reviews" "$P/docs/plans"
    P=$(cd "$P" && pwd -P)
    git -C "$P" init -q --initial-branch=main
    git -C "$P" config user.name ForgeTest
    git -C "$P" config user.email forge-test@example.invalid
    printf '.forge/local/\n' > "$P/.gitignore"
    printf '# forge:non-runtime-prose v1\nprose\tdocs/guide.md\nprose\tdocs/CHANGELOG.md\n' > "$P/.forge/verification-scope.tsv"
    [ "$scope" = docs/guide.md ] || printf 'prose\t%s\n' "$scope" >> "$P/.forge/verification-scope.tsv"
    if [ "$policy_mode" = source ]; then
        mkdir -p "$P/manifests"
        mv "$P/.forge/verification-scope.tsv" "$P/manifests/verification-scope.tsv"
        printf 'source marker\n' > "$P/FORGE.template.md"
        printf 'source marker\n' > "$P/state.template.md"
        printf 'source marker\n' > "$P/manifests/managed-v6.tsv"
    elif [ "$policy_mode" = missing ]; then rm "$P/.forge/verification-scope.tsv"; fi
    printf 'base app\n' > "$P/app.txt"
    printf '# Guide\nOriginal prose.\n' > "$P/docs/guide.md"
    printf '# Changes\n\n## [1.2.3] - 2026-10-22\n\n- Original prose.\n' > "$P/docs/CHANGELOG.md"
    printf '# Configuration\n' > "$P/docs/config.md"
    printf 'Agent instructions\n' > "$P/CONTRIBUTING.md"
    printf 'Plan requirements\n' > "$P/docs/plans/task.md"
    printf '<Component />\n' > "$P/docs/guide.mdx"
    git -C "$P" add -A; git -C "$P" commit -qm base
    BASE=$(git -C "$P" rev-parse HEAD)
    COMMON=$(cd "$P" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
    git -C "$P" checkout -qb fix/docs-closure
    cat > "$P/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
## Identity
| Worktree root | $P |
| Git common directory | $COMMON |
| Last active host | $MAIN |
| Workflow base ref | main |
| Workflow base SHA | $BASE |
## Workflow
| Command | /fix-bug docs-closure |
| Phase | review |
| Next step | promote |
### Checklist
- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified
## Receipts
| Review iteration | 1 |
| First certified iteration | 1 |
| Candidate receipt | .forge/local/evidence/candidate.receipt |
| Spec review receipt | .forge/local/reviews/code-spec.receipt |
| Quality review receipt | .forge/local/reviews/code-quality.receipt |
| Verify app receipt | .forge/local/evidence/verify-app.receipt |
| E2E receipt | .forge/local/evidence/e2e.receipt |
| Promotion receipt | .forge/local/evidence/promotion.receipt |
EOF
    printf 'fixed app\n' > "$P/app.txt"; git -C "$P" add app.txt
    freeze || return 1
    local engine="$OTHER"; [ "$fallback" = false ] || engine="$MAIN"
    review_fixture code-spec "$engine" "$fallback"; review_fixture code-quality "$engine" "$fallback"
    local kind
    for kind in verify-app e2e; do
        printf 'VERDICT: PASS\nControlled verifier fixture.\n' > "$P/.forge/local/evidence/$kind.report"
        (cd "$P" && bash "$VR" write --kind "$kind" --candidate .forge/local/evidence/candidate.receipt \
            --command "controlled $kind" --profile focused --report ".forge/local/evidence/$kind.report" \
            --result PASS --exit-status 0 --output ".forge/local/evidence/$kind.receipt") > "$S/write.log" 2>&1 || return 1
    done
    cp "$P/.forge/local/evidence/candidate.receipt" "$P/.forge/local/evidence/original.receipt"
    check
}
edit_docs() { printf 'Corrected narrative.\n' >> "$P/docs/guide.md"; git -C "$P" add docs/guide.md; freeze; }

for MAIN in claude codex; do
    OTHER=codex; [ "$MAIN" != codex ] || OTHER=claude
    for fallback in false true; do
        start_test "$MAIN main, $OTHER reviewer, fallback=$fallback: bounded prose tail retains evidence"
        fixture "$MAIN-$fallback" docs/guide.md "$fallback"
        assert_equals "$?" 0 'original four receipts certify the controlled candidate'
        app_hash=$(hash_file "$P/.forge/local/evidence/verify-app.receipt")
        review_hash=$(hash_file "$P/.forge/local/reviews/code-spec.receipt")
        edit_docs
        check; assert_equals "$?" 2 'changed candidate needs closure before shipping'
        close_docs; assert_equals "$?" 0 'declared prose delta closes with a real diff check'
        if [ -f "$P/.forge/local/evidence/candidate.receipt.docs-closure" ]; then
            assert_file_exists "$P/.forge/local/evidence/candidate.receipt.docs-closure" 'closure sidecar is separate evidence'
        else fail 'closure sidecar must be published'; fi
        check; assert_equals "$?" 0 'shared validator accepts exact final candidate and original receipts'
        mv "$P/.forge/local/evidence/original.receipt" "$S/original.saved"
        check; assert_equals "$?" 0 'closure archives its own original candidate rather than relying on caller scratch'
        mv "$S/original.saved" "$P/.forge/local/evidence/original.receipt"
        assert_contains "$S/check.log" 'SHIP_READY:true' 'final candidate is ready after closure'
        assert_hash_equals "$P/.forge/local/evidence/verify-app.receipt" "$app_hash" 'verifier provenance remains byte-for-byte unchanged'
        assert_hash_equals "$P/.forge/local/reviews/code-spec.receipt" "$review_hash" 'review provenance remains byte-for-byte unchanged'
        edit_docs
        check; assert_equals "$?" 2 'another correction invalidates the old closure'
        close_docs; assert_equals "$?" 0 'cumulative delta can close against original certified candidate'
        check; assert_equals "$?" 0 'second closure validates without chaining old closures'
        printf 'docs closure\n' > "$P/.forge/local/evidence/message.txt"
        (cd "$P" && bash "$FP" promote --candidate .forge/local/evidence/candidate.receipt \
            --state .forge/local/state.md --message-file .forge/local/evidence/message.txt \
            --promotion-receipt .forge/local/evidence/promotion.receipt) > "$S/promote.log" 2>&1
        assert_equals "$?" 0 'normal exact-tree promotion consumes the same closure validator'
        check; assert_equals "$?" 0 'post-promotion shipping retains exact final-tree proof'
    done
done
MAIN=claude; OTHER=codex
start_test 'source-only scope fallback requires canonical source markers'
fixture source-policy docs/guide.md false source
edit_docs
close_docs; assert_equals "$?" 0 'canonical source markers select the source-owned scope policy'
check; assert_equals "$?" 0 'source-only scope closure is checked by the same validator'
fixture missing-policy docs/guide.md false missing
edit_docs
close_docs; assert_equals "$?" 2 'missing policy never guesses that Markdown is non-runtime'
start_test 'documentation tail after an exact original promotion preserves promotion provenance'
fixture original-promotion
printf 'original promotion\n' > "$P/.forge/local/evidence/message.txt"
(cd "$P" && bash "$FP" promote --candidate .forge/local/evidence/candidate.receipt \
    --state .forge/local/state.md --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt) > "$S/promote.log" 2>&1
assert_equals "$?" 0 'original fully certified candidate promotes normally'
edit_docs
assert_equals "$(kv "$P/.forge/local/evidence/candidate.receipt" git_head)" \
    "$(kv "$P/.forge/local/evidence/promotion.receipt" new_branch_commit)" \
    'documentation candidate parent is the proven original promotion commit'
close_docs; assert_equals "$?" 0 'proved original promotion permits the documented single parent transition'
(cd "$P" && bash "$FP" promote --candidate .forge/local/evidence/candidate.receipt \
    --state .forge/local/state.md --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt) > "$S/promote.log" 2>&1
assert_equals "$?" 0 'documentation final candidate promotes after original promotion'
check; assert_equals "$?" 0 'closure keeps old promotion proof when active promotion is replaced'
for mutation in code unknown-doc scope-policy release-heading plan instructions config mdx add delete rename symlink binary whitespace mode stale-review report-tamper receipt-tamper sidecar-tamper head unstaged untracked; do
    start_test "closure rejects $mutation"
    scope=docs/guide.md
    case "$mutation" in plan) scope=docs/plans/task.md ;; instructions) scope=CONTRIBUTING.md ;; config) scope=docs/config.md ;; rename) scope=docs/renamed.md ;; mdx) scope=docs/guide.mdx ;; esac
    fixture "reject-$mutation" "$scope" || { fail 'fixture certification failed'; continue; }
    edit_docs
    case "$mutation" in
        code) printf 'other code\n' >> "$P/app.txt" ;;
        unknown-doc) printf 'unknown\n' > "$P/docs/unknown.md" ;;
        scope-policy) printf 'prose\tdocs/unknown.md\n' >> "$P/.forge/verification-scope.tsv" ;;
        release-heading) sed 's/1.2.3/1.2.4/' "$P/docs/CHANGELOG.md" > "$S/changelog"; cp "$S/changelog" "$P/docs/CHANGELOG.md" ;;
        plan) printf 'changed requirements\n' >> "$P/docs/plans/task.md" ;;
        instructions) printf 'changed instructions\n' >> "$P/CONTRIBUTING.md" ;;
        config) printf 'changed config\n' >> "$P/docs/config.md" ;;
        mdx) printf '<Other />\n' >> "$P/docs/guide.mdx" ;;
        add) printf 'new prose\n' > "$P/docs/new.md" ;;
        delete) rm "$P/docs/guide.md" ;;
        rename) git -C "$P" mv docs/guide.md docs/renamed.md ;;
        symlink) rm "$P/docs/guide.md"; ln -s ../app.txt "$P/docs/guide.md" ;;
        binary) printf '%9000s\000' '' >> "$P/docs/guide.md" ;;
        whitespace) printf 'trailing spaces  \n' >> "$P/docs/guide.md" ;;
        mode) chmod +x "$P/docs/guide.md"; git -C "$P" update-index --chmod=+x docs/guide.md ;;
        stale-review) sed 's/^timestamp=.*/timestamp=2000-01-01T00:00:00Z/' "$P/.forge/local/reviews/code-spec.receipt" > "$S/receipt"; cp "$S/receipt" "$P/.forge/local/reviews/code-spec.receipt" ;;
        report-tamper) printf 'tampered\n' >> "$P/.forge/local/evidence/e2e.report" ;;
        receipt-tamper) printf 'result=PASS\n' >> "$P/.forge/local/evidence/verify-app.receipt" ;;
        sidecar-tamper) close_docs; printf 'new_candidate_hash=wrong\n' >> "$P/.forge/local/evidence/candidate.receipt.docs-closure"; check; assert_equals "$?" 2 'tampered sidecar fails closed'; continue ;;
        head) git -C "$P" commit -qm 'unproven direct commit' ;;
        unstaged) printf 'not staged\n' >> "$P/docs/guide.md"; close_docs; assert_equals "$?" 2 'unstaged mutation cannot close'; continue ;;
        untracked) printf 'not tracked\n' > "$P/untracked.txt"; close_docs; assert_equals "$?" 2 'untracked mutation cannot close'; continue ;;
    esac
    git -C "$P" add -A; freeze
    close_docs; assert_equals "$?" 2 "$mutation cannot reuse final receipts"
    check; assert_equals "$?" 2 "$mutation remains blocked by ordinary shipping validation"
done
for mutation in manual-same-tree missing-promotion tampered-promotion archived-promotion archived-candidate; do
    start_test "original provenance rejects $mutation"
    fixture "provenance-$mutation"
    if [ "$mutation" = manual-same-tree ]; then
        git -C "$P" commit -qm 'manual same-tree commit'
        assert_equals "$(git -C "$P" rev-parse 'HEAD^{tree}')" "$(kv "$P/.forge/local/evidence/original.receipt" index_tree)" 'manual control uses the exact certified tree'
    else
        printf 'original promotion\n' > "$P/.forge/local/evidence/message.txt"
        (cd "$P" && bash "$FP" promote --candidate .forge/local/evidence/candidate.receipt \
            --state .forge/local/state.md --message-file .forge/local/evidence/message.txt \
            --promotion-receipt .forge/local/evidence/promotion.receipt) > "$S/promote.log" 2>&1
        assert_equals "$?" 0 'control starts from an actual exact Forge promotion'
    fi
    edit_docs
    case "$mutation" in
        missing-promotion) rm "$P/.forge/local/evidence/promotion.receipt" ;;
        tampered-promotion) printf 'old_candidate_id=wrong\n' >> "$P/.forge/local/evidence/promotion.receipt" ;;
        archived-promotion|archived-candidate)
            close_docs; assert_equals "$?" 0 'valid closure exists before archived provenance mutation'
            key=source_promotion_path; [ "$mutation" != archived-candidate ] || key=original_candidate_path
            archived=$(kv "$P/.forge/local/evidence/candidate.receipt.docs-closure" "$key")
            printf 'tampered\n' >> "$archived"
            check; assert_equals "$?" 2 'archived provenance hash is enforced on every ship check'
            continue ;;
    esac
    close_docs; assert_equals "$?" 2 "$mutation cannot prove the original promotion boundary"
done
report 'test-docs-closure.sh' 
