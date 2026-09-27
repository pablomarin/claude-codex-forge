#!/usr/bin/env bash
# Behavioral contract for the bounded cross-engine workflow-state command.

set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

GROUP="all"
if [ "${1:-}" = "--group" ]; then
    GROUP="${2:-}"
    shift 2
fi
case "$GROUP" in
    all|show-activate) ;;
    *) echo "usage: test-workflow-state.sh [--group show-activate|all]" >&2; exit 2 ;;
esac

HELPER_SH="$REPO_ROOT/hooks/lib/workflow-state.sh"
HELPER_PS1="$REPO_ROOT/hooks/lib/workflow-state.ps1"

make_repo() {
    local root
    root=$(scratch_dir workflow-state)
    root=$(cd "$root" && pwd -P)
    mkdir -p "$root/.forge/local"
    git -C "$root" init -q --initial-branch=main
    git -C "$root" config user.email "forge-test@example.com"
    git -C "$root" config user.name "Forge Test"
    printf '6\n' > "$root/.forge/version"
    printf 'fixture\n' > "$root/README.md"
    git -C "$root" add .forge/version README.md
    git -C "$root" commit -q -m init
    cp "$REPO_ROOT/state.template.md" "$root/.forge/local/state.md"
    printf '%s\n' "$root"
}

run_sh() {
    local root="$1"
    shift
    (cd "$root" && bash "$HELPER_SH" "$@") > "$root/helper.out" 2> "$root/helper.err"
}

assert_rejected_unchanged() {
    local root="$1" description="$2" before rc
    shift 2
    before=$(hash_file "$root/.forge/local/state.md")
    run_sh "$root" "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then pass "$description is rejected"; else fail "$description should be rejected"; fi
    assert_hash_equals "$root/.forge/local/state.md" "$before" "$description leaves state unchanged"
}

activate_fixture() {
    local root="$1"
    run_sh "$root" activate --host claude --workflow quick-fix --task handoff-smoke \
        --base-ref main --phase diagnosis --next-step 'write RED test'
}

checkpoint_fixture() {
    local root="$1"
    shift
    run_sh "$root" checkpoint --host codex --phase implementation \
        --next-step 'make GREEN' "$@"
}

capture_checkpoint_invariants() {
    local state="$1" output="$2"
    grep -E '^\| (Worktree root|Git common directory|Workflow base ref|Workflow base SHA|Command|Candidate receipt|Spec review receipt|Quality review receipt|Verify app receipt|E2E receipt|Promotion receipt|Council receipt) ' \
        "$state" > "$output"
}

start_test "show returns canonical V6 state without mutation"
SHOW_REPO=$(make_repo)
SHOW_BEFORE=$(hash_file "$SHOW_REPO/.forge/local/state.md")
run_sh "$SHOW_REPO" show
SHOW_RC=$?
assert_equals "$SHOW_RC" "0" "show exits zero"
if [ -f "$SHOW_REPO/helper.out" ] && cmp -s "$SHOW_REPO/helper.out" "$SHOW_REPO/.forge/local/state.md"; then
    pass "show emits the exact canonical state"
else
    fail "show must emit the exact canonical state"
fi
assert_hash_equals "$SHOW_REPO/.forge/local/state.md" "$SHOW_BEFORE" "show does not mutate state"

start_test "activate derives identity and initializes bounded task state"
ACT_REPO=$(make_repo)
ACT_BASE=$(git -C "$ACT_REPO" rev-parse main)
activate_fixture "$ACT_REPO"
ACT_RC=$?
assert_equals "$ACT_RC" "0" "activate exits zero"
assert_contains "$ACT_REPO/.forge/local/state.md" "| Worktree root        | $ACT_REPO |" \
    "activate records the physical worktree"
assert_contains "$ACT_REPO/.forge/local/state.md" "| Git common directory | $ACT_REPO/.git |" \
    "activate records the physical Git-common directory"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Last active host     | claude |' \
    "activate records the host"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Workflow base ref    | main |' \
    "activate records the base ref"
assert_contains "$ACT_REPO/.forge/local/state.md" "| Workflow base SHA    | $ACT_BASE |" \
    "activate resolves the immutable base SHA"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Command   | /quick-fix handoff-smoke |' \
    "activate records the workflow command"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Phase     | diagnosis |' \
    "activate records phase"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Next step | write RED test |' \
    "activate records exact next step"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Review iteration       | 0 |' \
    "activate initializes review iteration zero"
assert_contains "$ACT_REPO/.forge/local/state.md" '| First certified iteration | none |' \
    "activate initializes the helper-owned certification anchor"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Candidate receipt      | .forge/local/evidence/handoff-smoke/candidate.receipt |' \
    "activate initializes candidate receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Spec review receipt    | .forge/local/reviews/handoff-smoke/spec.receipt |' \
    "activate initializes spec receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Quality review receipt | .forge/local/reviews/handoff-smoke/quality.receipt |' \
    "activate initializes quality receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Verify app receipt     | .forge/local/evidence/handoff-smoke/verify-app.receipt |' \
    "activate initializes verify-app receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| E2E receipt            | .forge/local/evidence/handoff-smoke/e2e.receipt |' \
    "activate initializes E2E receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Promotion receipt      | .forge/local/evidence/handoff-smoke/promotion.receipt |' \
    "activate initializes promotion receipt path"
assert_contains "$ACT_REPO/.forge/local/state.md" \
    '| Council receipt        | .forge/local/council/<council-id>/receipt.json |' \
    "activate leaves Council receipt independently allocated"
assert_dir_exists "$ACT_REPO/.forge/local/evidence/handoff-smoke" \
    "activate creates the task evidence directory"
assert_dir_exists "$ACT_REPO/.forge/local/reviews/handoff-smoke" \
    "activate creates the task review directory"
assert_file_missing "$ACT_REPO/.forge/local/council" \
    "activate does not allocate a Council directory"

start_test "non-terminal identical activation preserves review progress"
awk '{ if ($0 == "| Review iteration       | 0 |") print "| Review iteration       | 2 |"; else print }' \
    "$ACT_REPO/.forge/local/state.md" > "$ACT_REPO/.forge/local/state.next"
mv "$ACT_REPO/.forge/local/state.next" "$ACT_REPO/.forge/local/state.md"
activate_fixture "$ACT_REPO"
assert_equals "$?" "0" "identical activation remains idempotent"
assert_contains "$ACT_REPO/.forge/local/state.md" '| Review iteration       | 2 |' \
    "identical activation preserves later review iteration"

start_test "activate rejects conflicting or unsafe inputs atomically"
assert_rejected_unchanged "$ACT_REPO" "different active task" activate --host codex \
    --workflow quick-fix --task other-task --base-ref main --phase diagnosis --next-step 'write RED test'
assert_rejected_unchanged "$ACT_REPO" "invalid host" activate --host other \
    --workflow quick-fix --task handoff-smoke --base-ref main --phase diagnosis --next-step 'write RED test'
assert_rejected_unchanged "$ACT_REPO" "invalid workflow" activate --host claude \
    --workflow deploy --task handoff-smoke --base-ref main --phase diagnosis --next-step 'write RED test'
assert_rejected_unchanged "$ACT_REPO" "path task slug" activate --host claude \
    --workflow quick-fix --task ../handoff --base-ref main --phase diagnosis --next-step 'write RED test'
NEWLINE_TASK_REPO=$(make_repo)
assert_rejected_unchanged "$NEWLINE_TASK_REPO" "newline task slug" activate --host claude \
    --workflow quick-fix --task $'ok\n../../escape' --base-ref main --phase diagnosis --next-step 'write RED test'
assert_file_missing "$NEWLINE_TASK_REPO/.forge/local/escape" \
    "newline task slug cannot escape its task directory"
assert_rejected_unchanged "$ACT_REPO" "option-like base ref" activate --host claude \
    --workflow quick-fix --task handoff-smoke --base-ref --help --phase diagnosis --next-step 'write RED test'
assert_rejected_unchanged "$ACT_REPO" "pipe in phase" activate --host claude \
    --workflow quick-fix --task handoff-smoke --base-ref main --phase 'diag|nosis' --next-step 'write RED test'
assert_rejected_unchanged "$ACT_REPO" "newline in next step" activate --host claude \
    --workflow quick-fix --task handoff-smoke --base-ref main --phase diagnosis --next-step $'write\nRED test'
assert_rejected_unchanged "$ACT_REPO" "outer whitespace" activate --host claude \
    --workflow quick-fix --task handoff-smoke --base-ref main --phase ' diagnosis' --next-step 'write RED test'
run_sh "$ACT_REPO" activate --host claude --host codex --workflow quick-fix \
    --task handoff-smoke --base-ref main --phase diagnosis --next-step 'write RED test'
if [ "$?" -ne 0 ]; then pass "duplicate activate option is rejected"; else fail "duplicate activate option must be rejected"; fi
assert_contains "$ACT_REPO/helper.err" 'duplicate activate option: --host' \
    "duplicate activate option has actionable Bash/PowerShell-parity guidance"

start_test "activate repairs an identical in-flight V6.1 placeholder state"
UPGRADE_REPO=$(make_repo)
activate_fixture "$UPGRADE_REPO"
awk '
    $0 == "| Review iteration       | 0 |" { print "| Review iteration       | <integer> |"; next }
    $0 ~ /^\| (Candidate|Spec review|Quality review|Verify app|E2E|Promotion) receipt/ {
        gsub(/handoff-smoke/, "<task-id>")
    }
    $0 !~ /^\| First certified iteration /
' "$UPGRADE_REPO/.forge/local/state.md" > "$UPGRADE_REPO/.forge/local/state.next"
mv "$UPGRADE_REPO/.forge/local/state.next" "$UPGRADE_REPO/.forge/local/state.md"
activate_fixture "$UPGRADE_REPO"
assert_equals "$?" "0" "identical V6.1 workflow is adopted"
assert_contains "$UPGRADE_REPO/.forge/local/state.md" '| Review iteration       | 0 |' \
    "V6.1 adoption initializes review iteration zero"
assert_contains "$UPGRADE_REPO/.forge/local/state.md" '| First certified iteration | none |' \
    "V6.1 adoption initializes the certification anchor"
assert_equals "$(awk '$0 == "| First certified iteration | none |" { getline; if ($0 == "") print "table"; exit }' "$UPGRADE_REPO/.forge/local/state.md")" \
    'table' \
    "V6.1 adoption inserts the anchor inside the Receipts table"
assert_contains "$UPGRADE_REPO/.forge/local/state.md" \
    '| Candidate receipt      | .forge/local/evidence/handoff-smoke/candidate.receipt |' \
    "V6.1 adoption initializes task receipt paths"

start_test "show and activate reject non-canonical state"
MALFORMED=$(make_repo)
printf '%s\n' '<!-- forge:state-schema v6 -->' '## Workflow' '| Field | Value |' '| Command | none |' \
    '| Command | duplicate |' > "$MALFORMED/.forge/local/state.md"
assert_rejected_unchanged "$MALFORMED" "malformed duplicate state" show

LEGACY=$(make_repo)
mkdir -p "$LEGACY/.claude/local"
mv "$LEGACY/.forge/local/state.md" "$LEGACY/.claude/local/state.md"
rm "$LEGACY/.forge/version"
run_sh "$LEGACY" show
if [ "$?" -ne 0 ]; then pass "legacy-only state is rejected"; else fail "legacy-only state must be rejected"; fi

SYMLINKED=$(make_repo)
mv "$SYMLINKED/.forge/local/state.md" "$SYMLINKED/state-target.md"
ln -s "$SYMLINKED/state-target.md" "$SYMLINKED/.forge/local/state.md"
run_sh "$SYMLINKED" show
if [ "$?" -ne 0 ]; then pass "symlinked canonical state is rejected"; else fail "symlinked state must be rejected"; fi

start_test "PowerShell show/activate runtime parity"
PWSH=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)
if [ -z "$PWSH" ]; then
    skip_test "no pwsh/powershell on PATH; runtime parity remains externally required"
else
    PS_REPO=$(make_repo)
    (cd "$PS_REPO" && "$PWSH" -NoProfile -File "$HELPER_PS1" show) \
        > "$PS_REPO/helper.out" 2> "$PS_REPO/helper.err"
    assert_equals "$?" "0" "PowerShell show exits zero"
    if cmp -s "$PS_REPO/helper.out" "$PS_REPO/.forge/local/state.md"; then
        pass "PowerShell show emits canonical state"
    else
        fail "PowerShell show must emit canonical state"
    fi
    (cd "$PS_REPO" && "$PWSH" -NoProfile -File "$HELPER_PS1" activate --host claude \
        --workflow quick-fix --task handoff-smoke --base-ref main --phase diagnosis \
        --next-step 'write RED test') > "$PS_REPO/helper.out" 2> "$PS_REPO/helper.err"
    assert_equals "$?" "0" "PowerShell activate exits zero"
    assert_contains "$PS_REPO/.forge/local/state.md" '| Command   | /quick-fix handoff-smoke |' \
        "PowerShell activate records the workflow"
fi

if [ "$GROUP" = "all" ]; then
    start_test "checkpoint updates only allowlisted fields"
    CHECK_REPO=$(make_repo)
    activate_fixture "$CHECK_REPO"
    assert_equals "$?" "0" "checkpoint fixture activation exits zero"
    capture_checkpoint_invariants "$CHECK_REPO/.forge/local/state.md" "$CHECK_REPO/invariants.before"
    checkpoint_fixture "$CHECK_REPO"
    assert_equals "$?" "0" "checkpoint exits zero"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Last active host     | codex |' \
        "checkpoint changes the active host"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Phase     | implementation |' \
        "checkpoint changes phase"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Next step | make GREEN |' \
        "checkpoint changes the next step"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Review iteration       | 0 |' \
        "ordinary checkpoint preserves review iteration"
    run_sh "$CHECK_REPO" checkpoint --host codex --phase 'literal \n phase' \
        --next-step 'keep literal \t and \n text'
    assert_equals "$?" "0" "checkpoint accepts literal backslash sequences"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Phase     | literal \n phase |' \
        "checkpoint preserves a literal backslash-n in phase"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Next step | keep literal \t and \n text |' \
        "checkpoint preserves literal backslash sequences in next step"
    capture_checkpoint_invariants "$CHECK_REPO/.forge/local/state.md" "$CHECK_REPO/invariants.after"
    if cmp -s "$CHECK_REPO/invariants.before" "$CHECK_REPO/invariants.after"; then
        pass "checkpoint preserves base identity, command, and receipt paths byte-for-byte"
    else
        fail "checkpoint must preserve base identity, command, and receipt paths"
    fi

    start_test "begin-review increments monotonically without caller control"
    checkpoint_fixture "$CHECK_REPO" --begin-review
    assert_equals "$?" "0" "first begin-review checkpoint exits zero"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Review iteration       | 1 |' \
        "first begin-review increments iteration to one"
    checkpoint_fixture "$CHECK_REPO" --begin-review
    assert_equals "$?" "0" "second begin-review checkpoint exits zero"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Review iteration       | 2 |' \
        "second begin-review increments iteration to two"

    start_test "checkpoint records the first receipt-certified iteration once"
    CERT_REPO=$(make_repo)
    activate_fixture "$CERT_REPO"
    awk '{
        if ($0 == "| Review iteration       | 0 |") {
            print "| Review iteration       | 1 |"
            next
        }
        print
    }' "$CERT_REPO/.forge/local/state.md" > "$CERT_REPO/.forge/local/state.next"
    mv "$CERT_REPO/.forge/local/state.next" "$CERT_REPO/.forge/local/state.md"
    (
        cd "$CERT_REPO" || exit 1
        # shellcheck source=../../hooks/lib/workflow-state.sh
        source "$HELPER_SH"
        workflow_state_reviews_valid() { return 0; }
        workflow_state_checkpoint --host codex --phase verify --next-step 'run final verification'
    ) > "$CERT_REPO/helper.out" 2> "$CERT_REPO/helper.err"
    assert_equals "$?" "0" "certified checkpoint exits zero"
    assert_contains "$CERT_REPO/.forge/local/state.md" '| First certified iteration | 1 |' \
        "first clean paired review iteration is anchored"
    (
        cd "$CERT_REPO" || exit 1
        source "$HELPER_SH"
        workflow_state_reviews_valid() { return 1; }
        workflow_state_checkpoint --host claude --phase review --next-step 'review repaired candidate' --begin-review
    ) > "$CERT_REPO/helper.out" 2> "$CERT_REPO/helper.err"
    assert_equals "$?" "0" "later review checkpoint exits zero"
    assert_contains "$CERT_REPO/.forge/local/state.md" '| Review iteration       | 2 |' \
        "later review increments the current iteration"
    assert_contains "$CERT_REPO/.forge/local/state.md" '| First certified iteration | 1 |' \
        "later reviews preserve the first certification anchor"
    assert_rejected_unchanged "$CHECK_REPO" "caller-selected review iteration" checkpoint \
        --host codex --phase review --next-step 'dispatch reviewers' --review-iteration 9
    assert_rejected_unchanged "$CHECK_REPO" "unknown checkpoint option" checkpoint \
        --host codex --phase review --next-step 'dispatch reviewers' --other value
    run_sh "$CHECK_REPO" checkpoint --host codex --phase review --next-step 'dispatch reviewers' \
        --begin-review --begin-review
    if [ "$?" -ne 0 ]; then pass "duplicate checkpoint option is rejected"; else fail "duplicate checkpoint option must be rejected"; fi
    assert_contains "$CHECK_REPO/helper.err" 'duplicate checkpoint option: --begin-review' \
        "duplicate checkpoint option has actionable Bash/PowerShell-parity guidance"

    start_test "checkpoint normalizes CRLF state for cross-platform handoff"
    CRLF_REPO=$(make_repo)
    sed 's/$/\r/' "$CRLF_REPO/.forge/local/state.md" > "$CRLF_REPO/.forge/local/state.next"
    mv "$CRLF_REPO/.forge/local/state.next" "$CRLF_REPO/.forge/local/state.md"
    activate_fixture "$CRLF_REPO"
    assert_equals "$?" "0" "activate accepts canonical state written with CRLF"
    checkpoint_fixture "$CRLF_REPO"
    assert_equals "$?" "0" "checkpoint resumes CRLF state"
    if LC_ALL=C grep -q "$(printf '\r')" "$CRLF_REPO/.forge/local/state.md"; then
        fail "checkpoint must normalize canonical state to LF"
    else
        pass "checkpoint normalizes canonical state to LF"
    fi

    start_test "checkpoint rejects malformed state atomically"
    DUP_REPO=$(make_repo)
    activate_fixture "$DUP_REPO"
    awk '{ print; if ($0 == "| Review iteration       | 0 |") print }' \
        "$DUP_REPO/.forge/local/state.md" > "$DUP_REPO/.forge/local/state.next"
    mv "$DUP_REPO/.forge/local/state.next" "$DUP_REPO/.forge/local/state.md"
    assert_rejected_unchanged "$DUP_REPO" "duplicate review iteration" checkpoint \
        --host codex --phase review --next-step 'dispatch reviewers' --begin-review

    BLANK_ANCHOR_REPO=$(make_repo)
    activate_fixture "$BLANK_ANCHOR_REPO"
    sed 's/| First certified iteration | none |/| First certified iteration |  |/' \
        "$BLANK_ANCHOR_REPO/.forge/local/state.md" > "$BLANK_ANCHOR_REPO/.forge/local/state.next"
    mv "$BLANK_ANCHOR_REPO/.forge/local/state.next" "$BLANK_ANCHOR_REPO/.forge/local/state.md"
    assert_rejected_unchanged "$BLANK_ANCHOR_REPO" "blank first-certified anchor" checkpoint \
        --host codex --phase review --next-step 'dispatch reviewers'

    MALFORMED_ANCHOR_REPO=$(make_repo)
    activate_fixture "$MALFORMED_ANCHOR_REPO"
    sed 's/| First certified iteration | none |/| First certified iteration | invalid |/' \
        "$MALFORMED_ANCHOR_REPO/.forge/local/state.md" > "$MALFORMED_ANCHOR_REPO/.forge/local/state.next"
    mv "$MALFORMED_ANCHOR_REPO/.forge/local/state.next" "$MALFORMED_ANCHOR_REPO/.forge/local/state.md"
    assert_rejected_unchanged "$MALFORMED_ANCHOR_REPO" "malformed first-certified anchor" checkpoint \
        --host codex --phase review --next-step 'dispatch reviewers'

    start_test "optimistic publication preserves a concurrent edit"
    CONCURRENT_REPO=$(make_repo)
    activate_fixture "$CONCURRENT_REPO"
    CONCURRENT_STATE="$CONCURRENT_REPO/.forge/local/state.md"
    CONCURRENT_NEXT="$CONCURRENT_REPO/.forge/local/state.next"
    CONCURRENT_HASH=$(hash_file "$CONCURRENT_STATE")
    cp "$CONCURRENT_STATE" "$CONCURRENT_NEXT"
    printf '\nconcurrent marker\n' >> "$CONCURRENT_STATE"
    # shellcheck source=../../hooks/lib/workflow-state.sh
    source "$HELPER_SH"
    forge_workflow_state_publish "$CONCURRENT_STATE" "$CONCURRENT_NEXT" "$CONCURRENT_HASH" \
        > "$CONCURRENT_REPO/publish.out" 2> "$CONCURRENT_REPO/publish.err"
    if [ "$?" -ne 0 ]; then pass "stale publication is rejected"; else fail "stale publication must be rejected"; fi
    assert_contains "$CONCURRENT_STATE" 'concurrent marker' \
        "concurrent state edit survives rejected publication"

    start_test "terminal checkpoint permits clean workflow replacement"
    run_sh "$CHECK_REPO" checkpoint --host codex --phase complete --next-step none
    assert_equals "$?" "0" "terminal checkpoint exits zero"
    activate_fixture "$CHECK_REPO"
    assert_equals "$?" "0" "same workflow and task can reactivate after terminal checkpoint"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Review iteration       | 0 |' \
        "same-task reactivation resets review iteration"
    run_sh "$CHECK_REPO" checkpoint --host claude --phase complete --next-step none
    run_sh "$CHECK_REPO" activate --host codex --workflow fix-bug --task replacement-task \
        --base-ref main --phase diagnosis --next-step 'write failing test'
    assert_equals "$?" "0" "different task can activate after terminal checkpoint"
    assert_contains "$CHECK_REPO/.forge/local/state.md" '| Command   | /fix-bug replacement-task |' \
        "terminal replacement records the new workflow"

    start_test "PowerShell checkpoint and publication runtime parity"
    if [ -z "$PWSH" ]; then
        skip_test "no pwsh/powershell on PATH; checkpoint runtime parity remains externally required"
    else
        (cd "$PS_REPO" && "$PWSH" -NoProfile -File "$HELPER_PS1" checkpoint --host codex \
            --phase implementation --next-step 'make GREEN' --begin-review) \
            > "$PS_REPO/helper.out" 2> "$PS_REPO/helper.err"
        assert_equals "$?" "0" "PowerShell checkpoint exits zero"
        assert_contains "$PS_REPO/.forge/local/state.md" '| Review iteration       | 1 |' \
            "PowerShell begin-review increments iteration"
    fi
fi

start_test "PowerShell twin preserves LF bytes and raw show output"
assert_not_contains "$HELPER_PS1" '[IO.File]::WriteAllLines' \
    "PowerShell twin does not rewrite canonical state with platform newlines"
assert_contains "$HELPER_PS1" '[Console]::OpenStandardOutput()' \
    "PowerShell show writes canonical bytes without console transcoding"

cleanup_scratch_dirs
report "test-workflow-state"
