#!/usr/bin/env bash
# Human review decisions permit exact approved trees without fabricating reviews.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
S=$(scratch_dir human-review-waiver)
S=$(cd "$S" && pwd -P)
_SCRATCH_DIRS+=("$S")
VR="$REPO_ROOT/hooks/lib/verification-receipt.sh"
FP="$REPO_ROOT/hooks/lib/candidate-fingerprint.sh"
GATE="$REPO_ROOT/hooks/check-workflow-gates.sh"
DECISION='Skip code review for this exact change; finish the approved branch.'
PROVENANCE='Explicit developer instruction in the current conversation, turn 7.'

freeze() {
    (cd "$P" && bash "$FP" freeze --artifact git:working-tree --workflow-base-ref main \
        --workflow-base-sha "$BASE" --output .forge/local/evidence/candidate.receipt) > "$S/freeze.log" 2>&1
}
check() { (cd "$P" && bash "$VR" check --state .forge/local/state.md) > "$S/check.log" 2>&1; }
record_waiver() {
    (cd "$P" && bash "$VR" record-review-waiver --state .forge/local/state.md \
        --decision "${1-$DECISION}" --provenance "${2-$PROVENANCE}") > "$S/record.log" 2>&1
}
check_waiver() {
    (cd "$P" && bash "$VR" check-review-waiver --state .forge/local/state.md) > "$S/waiver.log" 2>&1
}
ps_waiver() {
    local mode="$1"
    shift
    (cd "$P" && pwsh -NoProfile -File "$REPO_ROOT/hooks/lib/verification-receipt.ps1" \
        -Mode "$mode" -State .forge/local/state.md "$@") > "$S/ps-waiver.log" 2>&1
}
gate() {
    local payload
    payload=$(python3 - "$P" "$MAIN" "$1" <<'PY'
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'host': sys.argv[2], 'tool_input': {'command': sys.argv[3]}}))
PY
)
    (cd "$P" && printf '%s' "$payload" | bash "$GATE") > "$S/gate.log" 2>&1
}
gate_without_jq() (
    # Keep all ordinary fixture tools available while exercising the hook's
    # supported no-jq fallback. Define the shim in the wrapper itself: importing
    # a shadow command function can corrupt BASH_SOURCE on macOS Bash 3.2.
    FORGE_TEST_NOJQ_GATE="$GATE"; export FORGE_TEST_NOJQ_GATE
    GATE="$S/no-jq-wrapper.sh"
    cat > "$GATE" <<'SH'
command() {
    if [ "${1:-}:${2:-}" = -v:jq ]; then return 1; fi
    builtin command "$@"
}
source "$FORGE_TEST_NOJQ_GATE"
SH
    gate "$1"
)
replace_state() {
    python3 - "$P/.forge/local/state.md" "$1" "$2" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
assert sys.argv[2] in text
p.write_text(text.replace(sys.argv[2], sys.argv[3]))
PY
}
replace_field() {
    python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
prefix = sys.argv[2] + '='
lines = p.read_text().splitlines()
assert sum(line.startswith(prefix) for line in lines) == 1
p.write_text('\n'.join(prefix + sys.argv[3] if line.startswith(prefix) else line for line in lines) + '\n')
PY
}
verification() {
    local kind="$1" result="${2:-PASS}" status="${3:-0}"
    printf 'VERDICT: %s\nControlled focused verification fixture.\n' "$result" > "$P/.forge/local/evidence/$kind.report"
    if [ "$result" = N/A ]; then
        printf 'N/A_REASON: this controlled change has no user-facing browser flow.\n' >> "$P/.forge/local/evidence/$kind.report"
    fi
    (cd "$P" && bash "$VR" write --kind "$kind" --candidate .forge/local/evidence/candidate.receipt \
        --command "controlled direct $kind check" --profile focused --report ".forge/local/evidence/$kind.report" \
        --result "$result" --exit-status "$status" --output ".forge/local/evidence/$kind.receipt") > "$S/write.log" 2>&1
}
fixture() {
    local name="$1" mode="${2:-code}" e2e="${3:-PASS}"
    P="$S/$name"; mkdir -p "$P/.forge/local/evidence" "$P/.forge/local/reviews" "$P/docs" "$P/tests"
    P=$(cd "$P" && pwd -P)
    git -C "$P" init -q --initial-branch=main
    git -C "$P" config user.name ForgeTest
    git -C "$P" config user.email forge-test@example.invalid
    printf '.forge/\n' > "$P/.gitignore"
    printf 'base app\n' > "$P/app.txt"
    printf '# Changes\n\n- Shared entry.\n' > "$P/docs/CHANGELOG.md"
    git -C "$P" add -A
    git -C "$P" commit -qm base || return 1
    BASE=$(git -C "$P" rev-parse HEAD)
    COMMON=$(cd "$P" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
    git -C "$P" checkout -qb fix/review-waiver
    printf 'changed application behavior\n' > "$P/app.txt"
    if [ "$mode" = merge ]; then
        printf '# Changes\n\n- Feature entry.\n' > "$P/docs/CHANGELOG.md"
        git -C "$P" add -A
        git -C "$P" commit -qm feature || return 1
        git -C "$P" checkout -q main
        printf '# Changes\n\n- Main entry.\n' > "$P/docs/CHANGELOG.md"
        printf 'dependency update\n' > "$P/package.txt"
        printf 'repaired unit test\n' > "$P/tests/unit.txt"
        git -C "$P" add -A
        git -C "$P" commit -qm 'main package and test changes' || return 1
        git -C "$P" checkout -q fix/review-waiver
        git -C "$P" merge --no-edit main > "$S/merge.log" 2>&1
        [ "$?" -eq 1 ] || return 1
        [ "$(git -C "$P" diff --name-only --diff-filter=U)" = docs/CHANGELOG.md ] || return 1
        printf '# Changes\n\n- Feature entry.\n- Main entry.\n- Shared entry.\n' > "$P/docs/CHANGELOG.md"
    fi
    git -C "$P" add -A
    cat > "$P/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
## Identity
| Worktree root | $P |
| Git common directory | $COMMON |
| Last active host | $MAIN |
| Workflow base ref | main |
| Workflow base SHA | $BASE |
## Workflow
| Command | /fix-bug review-waiver |
| Phase | finalize |
| Next step | commit the approved candidate |
### Checklist
- [ ] Code review loop
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified
## /goal session
| nonce | <uuid-v4-lowercase> |
## PR authorization
## Receipts
| Review iteration | 1 |
| First certified iteration | none |
| Candidate receipt | .forge/local/evidence/candidate.receipt |
| Spec review receipt | .forge/local/reviews/code-spec.receipt |
| Quality review receipt | .forge/local/reviews/code-quality.receipt |
| Verify app receipt | .forge/local/evidence/verify-app.receipt |
| E2E receipt | .forge/local/evidence/e2e.receipt |
| Promotion receipt | .forge/local/evidence/promotion.receipt |
EOF
    # Deliberately invalid historical fixtures: a waiver must not rewrite them
    # or turn them into fresh independent review evidence.
    printf 'schema_version=0\nhistorical_review=spec\n' > "$P/.forge/local/reviews/code-spec.receipt"
    printf 'schema_version=0\nhistorical_review=quality\n' > "$P/.forge/local/reviews/code-quality.receipt"
    freeze && verification verify-app && verification e2e "$e2e"
}

if [ "${FORGE_WAIVER_EXTENSION_ONLY:-0}" != 1 ]; then
for MAIN in claude codex; do
    for mode in code merge; do
        start_test "$MAIN main: explicit decision covers $mode and exact normal commit/push"
        result=PASS; [ "$mode" != merge ] || result=N/A
        fixture "$MAIN-$mode" "$mode" "$result" || { fail 'current candidate fixture failed'; continue; }
        old_head=$(git -C "$P" rev-parse HEAD)
        tree=$(git -C "$P" write-tree)
        parents="$old_head"
        [ "$mode" != merge ] || parents="$parents $(git -C "$P" rev-parse MERGE_HEAD)"
        review_hash=$(hash_file "$P/.forge/local/reviews/code-spec.receipt")
        state_hash=$(hash_file "$P/.forge/local/state.md")
        gate 'git commit --no-edit'; assert_equals "$?" 2 'without explicit waiver review gate blocks commit'
        check; assert_equals "$?" 2 'ordinary certification rejects historical review fixtures'
        assert_contains "$S/check.log" 'REVIEWS_VALID:false' 'review status is truthful before waiver'
        record_waiver; assert_equals "$?" 0 'agent records actual human decision after current verification'
        check_waiver; assert_equals "$?" 0 'exact staged candidate has valid human review waiver'
        assert_contains "$S/waiver.log" 'REVIEW_WAIVER_VALID:true' 'waiver validity has its own status'
        assert_contains "$S/waiver.log" 'REVIEW_STATUS:human-waived' 'accepted human decision is not a passing review'
        assert_contains "$S/waiver.log" 'REVIEW_WAIVER_STATE:precommit' 'approval distinguishes staged tree from published HEAD'
        gate 'git push origin fix/review-waiver'; assert_equals "$?" 2 'staged approval cannot authorize pushing the old HEAD'
        gate 'gh pr create --title approved --body approved'; assert_equals "$?" 2 'staged approval cannot authorize a PR for the old HEAD'
        if [ "$MAIN:$mode" = codex:merge ] && command -v pwsh >/dev/null 2>&1; then
            ps_waiver check-review-waiver; assert_equals "$?" 0 'PowerShell reads Bash-recorded precommit waiver'
            ps_waiver record-review-waiver -Decision "$DECISION" -Provenance "$PROVENANCE"
            assert_equals "$?" 0 'PowerShell writes interoperable waiver for the same candidate'
            check_waiver; assert_equals "$?" 0 'Bash reads PowerShell-recorded precommit waiver'
        fi
        assert_file_exists "$P/.forge/local/evidence/candidate.receipt.review-waiver" 'waiver has a separate candidate sidecar'
        assert_hash_equals "$P/.forge/local/state.md" "$state_hash" 'waiver does not mark checklist or certification complete'
        check; assert_equals "$?" 2 'waiver never claims full ordinary certification'
        assert_contains "$S/check.log" 'REVIEWS_VALID:false' 'waiver leaves independent review validity false'
        if [ "$MAIN:$mode" = codex:merge ]; then
            cat > "$P/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
: > "$(git rev-parse --git-path forge-waiver-hook-ran)"
HOOK
            chmod +x "$P/.git/hooks/pre-commit"
            git init --bare -q "$S/waiver-remote.git"
            git -C "$P" remote add origin "$S/waiver-remote.git"
        fi
        if [ "$mode" = merge ]; then
            gate 'git commit --no-edit'; assert_equals "$?" 0 'waiver skips only missing code review at commit boundary'
            (cd "$P" && git commit --no-edit) > "$S/commit.log" 2>&1
        else
            gate 'git commit -m approved'; assert_equals "$?" 0 'waiver skips only missing code review at commit boundary'
            (cd "$P" && git commit -m approved) > "$S/commit.log" 2>&1
        fi
        assert_equals "$?" 0 'ordinary Git commit succeeds without special promotion or hook bypass'
        assert_equals "$(git -C "$P" rev-parse 'HEAD^{tree}')" "$tree" 'commit preserves approved tree'
        actual_parents=$(git -C "$P" rev-list --parents -n 1 HEAD | cut -d' ' -f2-)
        assert_equals "$actual_parents" "$parents" 'commit preserves every approved parent in order'
        check_waiver; assert_equals "$?" 0 'exact ordinary commit retains approved waiver'
        assert_contains "$S/waiver.log" 'REVIEW_WAIVER_STATE:postcommit' 'committed state is distinct from precommit approval'
        gate 'git commit -m another'; assert_equals "$?" 2 'postcommit waiver cannot authorize another commit'
        gate 'git push origin fix/review-waiver'; assert_equals "$?" 0 'push gate accepts exact committed tree without network'
        if [ "$MAIN:$mode" = codex:merge ]; then
            assert_file_exists "$P/.git/forge-waiver-hook-ran" 'gate-admitted ordinary commit executes repository hooks'
            (cd "$P" && git push origin fix/review-waiver) > "$S/push.log" 2>&1
            assert_equals "$?" 0 'gate-admitted command pushes to a disposable local bare remote'
            assert_equals "$(git --git-dir="$S/waiver-remote.git" rev-parse refs/heads/fix/review-waiver)" \
                "$(git -C "$P" rev-parse HEAD)" 'remote receives exactly the approved merge commit'
        fi
        if [ "$MAIN:$mode" = codex:merge ] && command -v pwsh >/dev/null 2>&1; then
            ps_waiver check-review-waiver; assert_equals "$?" 0 'PowerShell reads the exact committed merge waiver'
            assert_contains "$S/ps-waiver.log" 'REVIEW_WAIVER_STATE:postcommit' 'both readers recognize the same committed boundary'
        fi
        assert_hash_equals "$P/.forge/local/reviews/code-spec.receipt" "$review_hash" 'historical independent review is unchanged'
        check; assert_equals "$?" 2 'postcommit waiver still does not manufacture ordinary certification'
        git -C "$P" commit --allow-empty -qm 'unapproved extra commit'
        check_waiver; assert_equals "$?" 2 'even same-tree extra commit invalidates approved parent boundary'
        gate 'git push origin fix/review-waiver'; assert_equals "$?" 2 'extra unapproved commit cannot use waiver to push'
    done
done

MAIN=codex
for missing in decision provenance whitespace-decision whitespace-provenance; do
    start_test "recording rejects $missing"
    fixture "missing-$missing" || { fail 'fixture failed'; continue; }
    case "$missing" in
        decision) record_waiver '' "$PROVENANCE" ;;
        provenance) record_waiver "$DECISION" '' ;;
        whitespace-decision) record_waiver '   ' "$PROVENANCE" ;;
        whitespace-provenance) record_waiver "$DECISION" '   ' ;;
    esac
    assert_equals "$?" 2 'human decision and provenance must be nonempty'
    assert_file_missing "$P/.forge/local/evidence/candidate.receipt.review-waiver" 'invalid decision cannot publish waiver'
done

for mutation in staged unstaged untracked candidate verifier-report verifier-receipt failed-app stale-app failed-e2e missing-e2e workflow base goal-nonce parents branch worktree missing-provenance; do
    start_test "waiver rejects $mutation"
    mode=code; [ "$mutation" != parents ] || mode=merge
    fixture "reject-$mutation" "$mode" || { fail 'fixture failed'; continue; }
    record_waiver; assert_equals "$?" 0 'control has recorded waiver before mutation'
    case "$mutation" in
        staged) printf 'another change\n' >> "$P/app.txt"; git -C "$P" add app.txt ;;
        unstaged) printf 'not staged\n' >> "$P/app.txt" ;;
        untracked) printf 'new file\n' > "$P/untracked.txt" ;;
        candidate) printf 'unrecorded_metadata=changed\n' >> "$P/.forge/local/evidence/candidate.receipt" ;;
        verifier-report) printf 'report changed\n' >> "$P/.forge/local/evidence/verify-app.report" ;;
        verifier-receipt) printf 'unrecorded_metadata=changed\n' >> "$P/.forge/local/evidence/verify-app.receipt" ;;
        failed-app) verification verify-app FAIL 1 ;;
        stale-app) replace_field "$P/.forge/local/evidence/verify-app.receipt" ended_at 2000-01-01T00:00:00Z ;;
        failed-e2e) verification e2e FAIL 1 ;;
        missing-e2e) rm "$P/.forge/local/evidence/e2e.receipt" ;;
        workflow) replace_state '/fix-bug review-waiver' '/fix-bug different-task' ;;
        base) replace_state "| Workflow base SHA | $BASE |" "| Workflow base SHA | $(git -C "$P" rev-parse 'HEAD^{tree}') |" ;;
        goal-nonce) replace_state '<uuid-v4-lowercase>' 'different-active-goal' ;;
        parents) printf '%s\n' "$BASE" > "$(git -C "$P" rev-parse --absolute-git-dir)/MERGE_HEAD" ;;
        branch) git -C "$P" checkout -qb fix/different-approved-target ;;
        worktree) replace_state "| Worktree root | $P |" "| Worktree root | $S/another-worktree |" ;;
        missing-provenance)
            if [ -f "$P/.forge/local/evidence/candidate.receipt.review-waiver" ]; then
                sed '/^provenance=/d' "$P/.forge/local/evidence/candidate.receipt.review-waiver" > "$S/waiver-edited"
                cp "$S/waiver-edited" "$P/.forge/local/evidence/candidate.receipt.review-waiver"
            fi ;;
    esac
    check_waiver; assert_equals "$?" 2 "$mutation invalidates recorded scope or verification"
    gate 'git commit --no-edit'; assert_equals "$?" 2 "$mutation cannot bypass the precommit gate"
done

start_test 'waiver permits ordinary commit arguments but never content or parent selection'
fixture commit-arguments || fail 'fixture failed'
record_waiver; assert_equals "$?" 0 'commit argument fixture has valid review waiver'
for arguments in '-m approved' '-F .forge/local/message.txt' '--no-edit' '-m "approved change"' '--message="approved change"' "-m 'approved change'" '-m approved,-n'; do
    gate "git commit $arguments"; assert_equals "$?" 0 "$arguments preserves normal approved-tree commit"
done
for arguments in '--amend --no-edit' '-a -m approved' '--all -m approved' '--only app.txt' '--include app.txt' '-p' '--patch' '-i app.txt' '--interactive' '-n -m approved' '--no-verify -m approved' 'app.txt'; do
    gate "git commit $arguments"; assert_equals "$?" 2 "$arguments cannot change approved content or ancestry"
done
for command in 'git -c core.hooksPath=/tmp/absent commit -m approved' 'GIT_CONFIG_COUNT=0 git commit -m approved' 'git -C . commit -m approved'; do
    gate "$command"; assert_equals "$?" 2 'waiver declines global Git options and environment-prefixed commands'
done
for command in 'git commit -m --% -m -n' 'git commit -m @message' "git commit -m 'a’ --no-verify ‘b'" 'git commit -m "a” --no-verify “b"' $'git commit -m ok\necho done'; do
    gate "$command"; assert_equals "$?" 2 'waiver declines shell syntax that can escape literal commit arguments'
done
for command in 'git commit -m approved' 'git commit -m "approved" --no-verify'; do
    gate_without_jq "$command"; assert_equals "$?" 2 'waiver requires successful exact JSON decoding before command acceptance'
    assert_contains "$S/gate.log" 'Code review loop' 'no-jq fallback retains ordinary review requirement'
    assert_not_contains "$S/gate.log" 'human-waived review' 'fallback never claims waiver acceptance'
done

for failed in failed-app failed-e2e stale-app unstaged; do
    start_test "recording requires fresh passing verification: $failed"
    fixture "record-$failed" || { fail 'fixture failed'; continue; }
    case "$failed" in
        failed-app) verification verify-app FAIL 1 ;;
        failed-e2e) verification e2e FAIL 1 ;;
        stale-app) replace_field "$P/.forge/local/evidence/verify-app.receipt" ended_at 2000-01-01T00:00:00Z ;;
        unstaged) printf 'not staged\n' >> "$P/app.txt" ;;
    esac
    record_waiver; assert_equals "$?" 2 'waiver cannot be recorded over missing current verification'
done

for boundary in simplified verified e2e compound pr-authorization config breaker; do
    start_test "waiver preserves $boundary boundary"
    fixture "boundary-$boundary" || { fail 'fixture failed'; continue; }
    if [ "$boundary" = pr-authorization ]; then replace_state '<uuid-v4-lowercase>' '11111111-1111-4111-8111-111111111111'; fi
    record_waiver; assert_equals "$?" 0 'boundary fixture has valid review waiver'
    command='git commit -m approved'
    case "$boundary" in
        simplified) replace_state '- [x] Simplified' '- [ ] Simplified' ;;
        verified) replace_state '- [x] Verified (tests/lint/types)' '- [ ] Verified (tests/lint/types)' ;;
        e2e) replace_state '- [x] E2E verified' '- [ ] E2E verified' ;;
        compound) command='git commit -m approved && git push origin fix/review-waiver' ;;
        pr-authorization)
            git -C "$P" commit -qm 'approved before separately authorized PR'
            command='gh pr create --title approved --body approved' ;;
        config) printf '6\n' > "$P/.forge/version" ;;
        breaker)
            replace_state '| First certified iteration | none |' '| First certified iteration | 1 |'
            replace_state '| Review iteration | 1 |' '| Review iteration | 5 |' ;;
    esac
    gate "$command"; assert_equals "$?" 2 "$boundary remains required despite explicit review waiver"
    case "$boundary" in
        simplified|verified|e2e) assert_contains "$S/gate.log" '1 required quality gate(s) incomplete' 'waiver clears only review while the separate gate remains required' ;;
        compound) assert_contains "$S/gate.log" 'compound ship command blocked' 'compound guard is the blocker' ;;
        pr-authorization) assert_contains "$S/gate.log" 'PR authorization' 'shipping decision remains separate' ;;
        config) assert_contains "$S/gate.log" FORGE_CONFIG_TAMPERED 'managed configuration guard remains active' ;;
        breaker) assert_contains "$S/gate.log" 'convergence breaker' 'review waiver does not self-adjudicate breaker' ;;
    esac
done

start_test 'fresh waiver can renew an already committed merge after expiry'
fixture renew-committed merge N/A || fail 'fixture failed'
record_waiver; assert_equals "$?" 0 'original pending merge has explicit review approval'
(cd "$P" && git commit --no-edit) > "$S/commit.log" 2>&1
assert_equals "$?" 0 'approved merge commits normally before evidence expires'
replace_field "$P/.forge/local/evidence/candidate.receipt.review-waiver" recorded_at 2000-01-01T00:00:00Z
replace_field "$P/.forge/local/evidence/verify-app.receipt" ended_at 2000-01-01T00:00:00Z
check_waiver; assert_equals "$?" 2 'expired waiver and verification cannot ship'
freeze && verification verify-app && verification e2e N/A
assert_equals "$?" 0 'existing clean HEAD can be frozen and verified again'
record_waiver; assert_equals "$?" 0 'actual human decision can renew approval of existing HEAD'
check_waiver; assert_equals "$?" 0 'renewed approval validates exact existing commit'
assert_contains "$S/waiver.log" 'REVIEW_WAIVER_STATE:postcommit' 'already committed approval grants the shipping boundary'
gate 'git push origin fix/review-waiver'; assert_equals "$?" 0 'renewed existing commit can push without another commit'
gate 'gh pr create --title approved --body approved'; assert_equals "$?" 0 'renewed existing commit can reach separately checked PR creation'
gate 'git commit -m another'; assert_equals "$?" 2 'renewed existing commit cannot authorize another commit'
check; assert_equals "$?" 2 'renewal still does not manufacture passing independent review'
git -C "$P" commit --allow-empty -qm 'unapproved same-tree child'
check_waiver; assert_equals "$?" 2 'renewed approval cannot authorize a same-tree child'
gate 'git push origin fix/review-waiver'; assert_equals "$?" 2 'same-tree child cannot reuse approval to ship'

start_test 'pending same-tree merge still needs its approved commit'
fixture pending-same-tree-merge || fail 'fixture failed'
git -C "$P" commit -qm 'initial tree'
same_tree_side=$(printf 'same-tree merge source\n' | git -C "$P" commit-tree 'HEAD^{tree}' -p HEAD)
git -C "$P" merge --no-ff --no-commit "$same_tree_side" > "$S/merge-same-tree.log" 2>&1
assert_equals "$?" 0 'real same-tree merge is pending'
freeze && verification verify-app && verification e2e
record_waiver; assert_equals "$?" 0 'same-tree pending merge can record approval'
check_waiver; assert_equals "$?" 0 'same-tree merge candidate has exact current approval'
assert_contains "$S/waiver.log" 'REVIEW_WAIVER_STATE:precommit' 'MERGE_HEAD distinguishes pending merge from an existing commit'
gate 'git push origin fix/review-waiver'; assert_equals "$?" 2 'pending same-tree merge cannot ship old HEAD'
gate 'git commit --no-edit'; assert_equals "$?" 0 'pending same-tree merge may commit'
(cd "$P" && git commit --no-edit) > "$S/commit.log" 2>&1
assert_equals "$?" 0 'ordinary same-tree merge commit succeeds'
check_waiver; assert_equals "$?" 0 'exact same-tree merge retains approval'
assert_contains "$S/waiver.log" 'REVIEW_WAIVER_STATE:postcommit' 'same-tree merge reaches committed state'

start_test 'waiver scope stays bound to canonical state and original commit ancestry'
fixture scope-boundaries || fail 'fixture failed'
record_waiver; assert_equals "$?" 0 'scope control has a valid recorded waiver'
replace_state '<uuid-v4-lowercase>' 'none'
check_waiver; assert_equals "$?" 2 'active nonce none cannot collide with inactive sentinel'
replace_state '| nonce | none |' '| nonce | <uuid-v4-lowercase> |'
cp "$P/.forge/local/state.md" "$S/external-state.md"
(cd "$P" && bash "$VR" record-review-waiver --state "$S/external-state.md" \
    --decision "$DECISION" --provenance "$PROVENANCE") > "$S/external-state.log" 2>&1
assert_equals "$?" 2 'review waiver refuses state outside Forge-local ownership'
git -C "$P" commit -qm approved
git -C "$P" commit --allow-empty -qm extra
replace_field "$P/.forge/local/evidence/candidate.receipt.review-waiver" parents "$(git -C "$P" rev-parse HEAD^)"
check_waiver; assert_equals "$?" 2 'edited parents cannot detach authorization from original candidate HEAD'
python3 - "$VR" "$P" <<'PY_ARGS'
import subprocess, sys
try:
    result = subprocess.run(['bash', sys.argv[1], 'record-review-waiver', '--decision'],
                            cwd=sys.argv[2], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=5)
except subprocess.TimeoutExpired:
    raise SystemExit(1)
raise SystemExit(0 if result.returncode == 2 else 1)
PY_ARGS
assert_equals "$?" 0 'missing decision argument fails promptly instead of looping'

fi

record_workflow() {
    (cd "$P" && bash "$VR" record-workflow-waiver --state .forge/local/state.md --skip "$1" \
        --decision "${2:-Skip the explicitly named remaining checks for this completed change.}" \
        --provenance "$PROVENANCE") > "$S/record-workflow.log" 2>&1
}
check_workflow() {
    (cd "$P" && bash "$VR" check-workflow-waiver --state .forge/local/state.md) > "$S/workflow-waiver.log" 2>&1
}
stop_gate() {
    (cd "$P" && printf '{"host":"codex"}' | bash "$REPO_ROOT/hooks/check-state-updated.sh") > "$S/stop.log" 2>&1
}
kv() { awk -F= -v key="$2" '$1==key{sub(/^[^=]*=/, ""); print; exit}' "$1"; }
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
for MAIN in claude codex; do
    OTHER=claude
    start_test "$MAIN: developer can skip E2E alone while other evidence stays required"
    fixture "extension-e2e-$MAIN" || fail 'fixture failed'
    review_fixture code-spec claude false; review_fixture code-quality claude false
    replace_state '- [ ] Code review loop' '- [x] Code review loop'
    replace_state '- [x] E2E verified' '- [ ] E2E verified'
    rm "$P/.forge/local/evidence/e2e.receipt" "$P/.forge/local/evidence/e2e.report"
    record_workflow e2e; assert_equals "$?" 0 'explicit E2E skip needs no E2E receipt'
    check_workflow; assert_equals "$?" 0 'E2E-only exemption validates other evidence'
    assert_contains "$S/workflow-waiver.log" 'WAIVED_GATES:e2e' 'only requested scope is recorded'
    gate 'git commit -m approved'; assert_equals "$?" 0 'unchecked explicitly waived E2E does not block commit'
    check; assert_equals "$?" 2 'skipped E2E never becomes full certification'
    verification verify-app FAIL 1
    check_workflow; assert_equals "$?" 2 'unwaived failed app check still blocks'
    verification verify-app
    record_workflow e2e
    printf 'changed review\n' >> "$P/.forge/local/reviews/code-quality.report"
    check_workflow; assert_equals "$?" 2 'unwaived review receipt mutation still blocks'

    start_test "$MAIN: skip all after review repairs preserves normal merge hooks and exact scope"
    fixture "extension-all-$MAIN" merge || fail 'fixture failed'
    for stem in 'Simplified' 'Verified (tests/lint/types)' 'E2E verified'; do replace_state "- [x] $stem" "- [ ] $stem"; done
    replace_state '| First certified iteration | none |' '| First certified iteration | 1 |'
    replace_state '| Review iteration | 1 |' '| Review iteration | 5 |'
    replace_state '## /goal session' $'- [x] Plan review loop — FAIL\n## /goal session'
    rm "$P/.forge/local/evidence/verify-app.receipt" "$P/.forge/local/evidence/e2e.receipt"
    state_hash=$(hash_file "$P/.forge/local/state.md")
    old_review=$(hash_file "$P/.forge/local/reviews/code-quality.receipt")
    parents="$(git -C "$P" rev-parse HEAD) $(git -C "$P" rev-parse MERGE_HEAD)"
    record_workflow all; assert_equals "$?" 0 'all remaining checks may be explicitly waived without results'
    check_workflow; assert_equals "$?" 0 'all-scope approval is valid for exact completed tree'
    assert_hash_equals "$P/.forge/local/state.md" "$state_hash" 'exemption preserves all unchecked boxes and counters'
    assert_hash_equals "$P/.forge/local/reviews/code-quality.receipt" "$old_review" 'exemption preserves historical findings'
    if command -v pwsh >/dev/null 2>&1; then
        ps_waiver check-workflow-waiver; assert_equals "$?" 0 'PowerShell reads Bash workflow waiver'
        ps_waiver record-workflow-waiver -Skip all -Decision "$DECISION" -Provenance "$PROVENANCE"
        assert_equals "$?" 0 'PowerShell records interoperable workflow exemption'
        check_workflow; assert_equals "$?" 0 'Bash reads PowerShell workflow waiver'
    fi
    printf '#!/bin/sh\n: > "$(git rev-parse --git-path extension-hook-ran)"\n' > "$P/.git/hooks/pre-commit"
    chmod +x "$P/.git/hooks/pre-commit"
    gate 'git commit --no-edit'; assert_equals "$?" 0 'all skips release checklist, old plan and convergence checks'
    (cd "$P" && git commit --no-edit) > "$S/extension-commit.log" 2>&1
    assert_equals "$?" 0 'ordinary merge commits without disabling hooks'
    assert_file_exists "$P/.git/extension-hook-ran" 'repository hook executes'
    assert_equals "$(git -C "$P" rev-list --parents -n 1 HEAD | cut -d' ' -f2-)" "$parents" 'all skips preserve both ordered merge parents'
    gate 'git push origin fix/review-waiver'; assert_equals "$?" 0 'exact committed candidate can reach authorized push'
    check; assert_equals "$?" 2 'all skips never claim full certification'
    gate 'git commit -m another'; assert_equals "$?" 2 'all skips cannot authorize another commit'
    gate 'git commit -n -m approved'; assert_equals "$?" 2 'all skips do not disable repository hooks'
    gate 'git push origin x && git commit -m y'; assert_equals "$?" 2 'all skips retain separate command boundaries'
    printf 'new development\n' >> "$P/app.txt"
    check_workflow; assert_equals "$?" 2 'subsequent development invalidates all-scope decision'
done

MAIN=codex
for scopes in '' unknown 'review,review' 'all,e2e' 'e2e,'; do
    fixture "extension-invalid-${scopes//[^a-z]/x}" || fail 'fixture failed'
    record_workflow "$scopes"; assert_equals "$?" 2 'empty, duplicate, mixed-all or unknown scopes are rejected'
done
start_test 'Goal evidence keeps developer decisions separate from certification'
fixture extension-evidence || fail 'fixture failed'
record_workflow all
(cd "$P" && printf '{"host":"codex"}' | bash "$REPO_ROOT/hooks/build-evidence.sh" --diagnostic) > "$S/evidence.log" 2>&1
assert_contains "$S/evidence.log" '"workflow_waiver":{"valid":true' 'Goal evidence distinguishes actual human decision'
assert_contains "$S/evidence.log" '"unwaived_evidence_ready":true' 'Goal evidence reports unwaived evidence separately'
assert_contains "$S/evidence.log" '"all_receipts_same_candidate":false' 'waiver never fabricates full certification'

for guard in convergence plan-review; do
    fixture "narrow-$guard" || fail 'fixture failed'
    if [ "$guard" = convergence ]; then
        replace_state '| First certified iteration | none |' '| First certified iteration | 1 |'
        replace_state '| Review iteration | 1 |' '| Review iteration | 5 |'
    else replace_state '## /goal session' $'- [x] Plan review loop — FAIL\n## /goal session'; fi
    record_workflow review,e2e; assert_equals "$?" 0 'narrow decision records without skipping other process gates'
    gate 'git commit -m approved'; assert_equals "$?" 2 "unwaived $guard remains required"
    record_workflow "review,e2e,$guard"; assert_equals "$?" 0 "developer may explicitly omit $guard"
    gate 'git commit -m approved'; assert_equals "$?" 0 "only the named $guard omission releases its gate"
done

start_test 'selected skips do not silently skip other process gates'
fixture extension-selected || fail 'fixture failed'
rm "$P/.forge/local/evidence/e2e.receipt"
record_workflow review,e2e; assert_equals "$?" 0 'selected review/E2E exemptions still use fresh app evidence'
replace_state '- [x] Simplified' '- [ ] Simplified'
gate 'git commit -m approved'; assert_equals "$?" 2 'unrequested simplification remains required'
record_workflow review,e2e,simplification
assert_equals "$?" 0 'developer can explicitly add simplification'
gate 'git commit -m approved'; assert_equals "$?" 0 'only explicit additional skip clears simplification'
verification verify-app FAIL 1
record_workflow review,e2e,simplification; assert_equals "$?" 0 'decision is recordable before unwaived evidence is ready'
check_workflow; assert_equals "$?" 2 'named skips cannot hide unwaived app failure'

start_test 'malformed workflow decision cannot fall back to older review-only approval'
fixture extension-malformed || fail 'fixture failed'
record_waiver
record_workflow all
assert_equals "$?" 0 'new decision can supersede older review-only approval'
replace_field "$P/.forge/local/evidence/candidate.receipt.workflow-waiver" waived_gates unknown
check_workflow; assert_equals "$?" 2 'malformed new decision fails closed'
gate 'git commit -m approved'; assert_equals "$?" 2 'older review waiver cannot mask malformed newer workflow decision'

start_test 'workflow decisions require actual decision and provenance'
fixture extension-provenance || fail 'fixture failed'
(cd "$P" && bash "$VR" record-workflow-waiver --skip all --decision "$DECISION" --provenance '') > "$S/missing-provenance.log" 2>&1
assert_equals "$?" 2 'all-scope still requires human provenance'

start_test 'explicit all skips respect separately authorized external actions'
fixture extension-authority || fail 'fixture failed'
replace_state '<uuid-v4-lowercase>' '11111111-1111-4111-8111-111111111111'
record_workflow all
assert_equals "$?" 0 'all-scope decision can bind an active objective'
git -C "$P" commit -qm approved
gate 'gh pr create --title approved --body approved'; assert_equals "$?" 2 'all development skips do not create external-action authority'

start_test 'Stop honors named changelog and continuation decisions without a retry loop'
fixture extension-stop || fail 'fixture failed'
for n in 1 2 3 4; do printf 'completed change\n' > "$P/extra$n.txt"; done
git -C "$P" add -A
git -C "$P" commit -qm 'completed development across five files'
freeze
stop_gate; assert_equals "$?" 2 'without a decision missing changelog still blocks Stop'
record_workflow all
assert_equals "$?" 0 'all-scope decision binds multi-file completed development'
stop_gate; assert_equals "$?" 0 'explicit changelog skip permits Stop'
stop_gate; assert_equals "$?" 0 'explicit continuation skip prevents another forced turn'
assert_not_contains "$S/stop.log" FORGE_FINAL_EVIDENCE_STALE 'Stop reports accepted omissions without demanding fabricated evidence'
printf 'later change\n' >> "$P/app.txt"
check_workflow; assert_equals "$?" 2 'Stop exemption cannot apply to later development'


MAIN=codex; OTHER=claude
for spec in verify-app:unit-tests e2e:ui-qa; do
    kind=${spec%%:*}; omitted=${spec#*:}
    fixture "focused-${kind}" || fail 'fixture failed'
    review_fixture code-spec claude false; review_fixture code-quality claude false
    replace_state '- [ ] Code review loop' '- [x] Code review loop'
    printf 'VERDICT: PASS\nRemaining checks executed successfully in this controlled fixture.\nHUMAN_WAIVED_CHECKS: %s\n' "$omitted" > "$P/.forge/local/evidence/$kind.report"
    (cd "$P" && bash "$VR" write --kind "$kind" --candidate .forge/local/evidence/candidate.receipt \
        --command 'controlled remaining-checks run' --profile focused --report ".forge/local/evidence/$kind.report" \
        --result PASS --exit-status 0 --output ".forge/local/evidence/$kind.receipt") > "$S/focused-write.log" 2>&1
    assert_equals "$?" 0 'actual scoped report can be recorded without fabricating omitted execution'
    record_workflow "$spec"; assert_equals "$?" 0 'developer subcheck decision is recorded precisely'
    check_workflow; assert_equals "$?" 0 'remaining gate requires actual fresh matching scoped report'
    gate 'git commit -m approved'; assert_equals "$?" 0 'precise subcheck omission permits completed remaining checks'
    check; assert_equals "$?" 2 'scoped verification never claims full certification'
    printf 'HUMAN_WAIVED_CHECKS: wrong-check\n' >> "$P/.forge/local/evidence/$kind.report"
    check_workflow; assert_equals "$?" 2 'unrequested or malformed omissions cannot pass'
done
fixture stop-only-context || fail 'fixture failed'
for n in 1 2 3 4; do printf 'completed change\n' > "$P/extra$n.txt"; done
git -C "$P" add -A; git -C "$P" commit -qm 'completed multi-file work'
freeze
record_workflow changelog; assert_equals "$?" 0 'Stop-only decision does not wait for final review evidence'
(cd "$P" && bash "$VR" check-workflow-waiver --boundary stop --state .forge/local/state.md) > "$S/stop-check.log" 2>&1
assert_equals "$?" 0 'Stop validates the exact decision without shipping evidence'
stop_gate; assert_equals "$?" 0 'named changelog omission releases changelog only'
stop_gate; assert_equals "$?" 2 'unwaived continuation remains disciplined'
gate 'git commit -m approved'; assert_equals "$?" 2 'Stop-only decision cannot ship missing independent review'
record_workflow changelog,continuation
assert_equals "$?" 0 'developer can explicitly add continuation omission'
stop_gate; assert_equals "$?" 0 'both named Stop omissions are honored'

report 'test-human-review-waiver.sh'
