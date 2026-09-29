#!/usr/bin/env bash
# Repository-local native-goal ledger contract. Does not call either engine.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

LEDGER="$REPO_ROOT/hooks/lib/goal-ledger.sh"
NONCE=11111111-1111-4111-8111-111111111111
ACTIVATION1=22222222-2222-4222-8222-222222222222
ACTIVATION2=33333333-3333-4333-8333-333333333333

write_state() {
    local project="$1" activation_id="$2" activation_count="$3" turn_count="$4" objective="${5:-obj123}"
    mkdir -p "$project/.forge/local"
    cat > "$project/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
# State

## Workflow

| Field | Value |
| --- | --- |
| Command | /new-feature smoke |
| Phase | implementation |
| Next step | continue smoke |

## /goal session

| Field | Value |
| --- | --- |
| nonce | $NONCE |
| objective_hash | $objective |
| activation_id | $activation_id |
| activation_host | claude |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature smoke |
| turn_count | $turn_count |
| turn_ceiling | $((20 * activation_count)) |
| activation_count | $activation_count |
| evidence_path | .forge/local/evidence/latest.json |
EOF
}

charge() {
    local project="$1" turn_id="$2" session="${3:-s1}" host="${4:-claude}"
    printf '{"host":"%s","session_id":"%s","turn_id":"%s"}' "$host" "$session" "$turn_id" |
        bash "$LEDGER" charge --project "$project" \
            --state "$project/.forge/local/state.md" --event-json -
}

ledger_count() {
    find "$1" -mindepth 1 -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' \
        | wc -l | tr -d ' '
}

start_test "repository ledger is shared by the primary checkout and linked worktrees"
S=$(scratch_dir project-goal-ledger)
P="$S/project"
W="$S/worktree"
mkdir -p "$P"
git -C "$P" init -q
git -C "$P" config user.email forge@example.invalid
git -C "$P" config user.name Forge
printf 'tracked\n' > "$P/tracked.txt"
git -C "$P" add tracked.txt
git -C "$P" commit -qm base
git -C "$P" branch linked
git -C "$P" worktree add -q "$W" linked
write_state "$P" "$ACTIVATION1" 1 0
write_state "$W" "$ACTIVATION1" 1 0
COMMON_RAW=$(git -C "$P" rev-parse --git-common-dir)
case "$COMMON_RAW" in /*) ;; *) COMMON_RAW="$P/$COMMON_RAW" ;; esac
COMMON=$(cd "$COMMON_RAW" && pwd -P)
GOAL_ROOT="$COMMON/forge-goals/$NONCE"
bash "$LEDGER" activate --project "$P" --state "$P/.forge/local/state.md"
assert_equals "$?" "0" "first native activation publishes"
assert_contains "$GOAL_ROOT/binding" 'format=forge-goal-ledger-v2' "binding uses v2 schema"
assert_contains "$GOAL_ROOT/binding" 'turn_tranche=20' "binding fixes the tranche at 20"
assert_file_exists "$GOAL_ROOT/activations/00000001" "activation 1 is immutable and sequential"
charge "$P" t1
assert_equals "$?" "0" "first Stop event charges"
charge "$W" t1
assert_equals "$?" "0" "duplicate Stop from linked worktree is idempotent"
charge "$W" t1 s1 codex > "$S/non-equivalent-duplicate.log" 2>&1
[ "$?" -ne 0 ] && pass "duplicate identity with changed content blocks" || fail "non-equivalent duplicate was accepted"
assert_contains "$S/non-equivalent-duplicate.log" 'FORGE_GOAL_LEDGER_TAMPERED' \
    "non-equivalent duplicate is diagnosed"
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "1" "duplicate Stop delivery charges once"
assert_contains "$GOAL_ROOT/turns/00000001" 'turn_id=t1' "first sequence record binds the turn id"

start_test "concurrent duplicate and unique Stop deliveries are no-clobber"
write_state "$P" "$ACTIVATION1" 1 1
write_state "$W" "$ACTIVATION1" 1 1
(charge "$P" t2 s2 > "$S/t2-a.log" 2>&1; printf '%s\n' "$?" > "$S/t2-a.rc") & a=$!
(charge "$W" t2 s2 > "$S/t2-b.log" 2>&1; printf '%s\n' "$?" > "$S/t2-b.rc") & b=$!
wait "$a"; wait "$b"
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "2" "concurrent duplicate event charges once"
assert_equals "$(grep -hxc 0 "$S/t2-a.rc" "$S/t2-b.rc" | awk '{s+=$1} END{print s+0}')" "2" \
    "both duplicate callers receive idempotent success"
write_state "$P" "$ACTIVATION1" 1 2
write_state "$W" "$ACTIVATION1" 1 2
(charge "$P" t3 s3 > "$S/t3.log" 2>&1; printf '%s\n' "$?" > "$S/t3.rc") & c=$!
(charge "$W" t4 s4 > "$S/t4.log" 2>&1; printf '%s\n' "$?" > "$S/t4.rc") & d=$!
wait "$c"; wait "$d"
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "4" "concurrent unique events receive separate sequences"
assert_file_exists "$GOAL_ROOT/turns/00000003" "sequence 3 exists"
assert_file_exists "$GOAL_ROOT/turns/00000004" "sequence 4 exists"

start_test "one activation exhausts at 20 and reactivation extends to 40"
for n in $(seq 5 20); do
    write_state "$P" "$ACTIVATION1" 1 "$((n - 1))"
    charge "$P" "t$n" "s$n" > "$S/t$n.log" 2>&1
    assert_equals "$?" "0" "turn $n charges"
done
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "20" "first activation stops at its 20-turn ceiling"
assert_file_exists "$GOAL_ROOT/checkpoint" "exhaustion publishes a checkpoint"
assert_file_exists "$GOAL_ROOT/exhausted" "exhaustion publishes an exhausted marker"
assert_contains "$GOAL_ROOT/exhausted" 'turn_ceiling=20' "exhaustion binds the first ceiling"
write_state "$P" "$ACTIVATION1" 1 20
charge "$P" t21 > "$S/pre-reactivation.log" 2>&1
assert_equals "$?" "0" "post-exhaustion Stop returns the existing checkpoint"
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "20" "post-exhaustion Stop cannot exceed the ceiling"

write_state "$P" "$ACTIVATION2" 2 20
bash "$LEDGER" activate --project "$P" --state "$P/.forge/local/state.md"
assert_equals "$?" "0" "same-objective reactivation publishes"
assert_file_exists "$GOAL_ROOT/activations/00000002" "activation 2 is sequential"
assert_file_missing "$GOAL_ROOT/exhausted" "reactivation clears only the derived exhausted marker"
charge "$P" t21 s21
assert_equals "$?" "0" "reactivated objective charges turn 21"
assert_equals "$(ledger_count "$GOAL_ROOT/turns")" "21" "reactivation extends rather than resets the count"

start_test "state rollback, objective drift, deletion, and ledger tamper fail closed"
write_state "$P" "$ACTIVATION2" 2 0
charge "$P" rollback > "$S/rollback.log" 2>&1
[ "$?" -ne 0 ] && pass "state count reduction blocks" || fail "state count reduction was accepted"
assert_contains "$S/rollback.log" 'FORGE_GOAL_LEDGER_TAMPERED' "state rollback is diagnosed"
write_state "$P" "$ACTIVATION2" 2 21 other-objective
charge "$P" objective-drift > "$S/objective.log" 2>&1
[ "$?" -ne 0 ] && pass "objective mismatch blocks" || fail "objective mismatch was accepted"
write_state "$P" "$ACTIVATION2" 2 21
mv "$P/.forge/local/state.md" "$P/.forge/local/state.saved"
printf '{}' | bash "$LEDGER" charge --project "$P" --state "$P/.forge/local/state.md" --event-json - \
    > "$S/missing-state.log" 2>&1
[ "$?" -ne 0 ] && pass "state deletion blocks" || fail "missing active state was accepted"
mv "$P/.forge/local/state.saved" "$P/.forge/local/state.md"
chmod u+w "$GOAL_ROOT/turns/00000001"
printf 'tampered\n' >> "$GOAL_ROOT/turns/00000001"
charge "$P" malformed > "$S/malformed.log" 2>&1
[ "$?" -ne 0 ] && pass "malformed immutable record blocks" || fail "malformed record was accepted"
assert_contains "$S/malformed.log" 'FORGE_GOAL_LEDGER_TAMPERED' "malformed record is diagnosed"

start_test "activation gaps and symlinked ledger roots fail closed"
GAP="$S/gap-project"
mkdir -p "$GAP"
git -C "$GAP" init -q
write_state "$GAP" "$ACTIVATION1" 1 0
GAP_COMMON_RAW=$(git -C "$GAP" rev-parse --git-common-dir)
case "$GAP_COMMON_RAW" in /*) ;; *) GAP_COMMON_RAW="$GAP/$GAP_COMMON_RAW" ;; esac
GAP_COMMON=$(cd "$GAP_COMMON_RAW" && pwd -P)
mkdir -p "$GAP_COMMON/forge-goals/$NONCE/activations"
printf 'bad\n' > "$GAP_COMMON/forge-goals/$NONCE/activations/00000002"
bash "$LEDGER" activate --project "$GAP" --state "$GAP/.forge/local/state.md" > "$S/gap.log" 2>&1
[ "$?" -ne 0 ] && pass "missing activation sequence blocks" || fail "activation gap was accepted"

LINK="$S/link-project"
OUTSIDE="$S/outside-ledger"
mkdir -p "$LINK" "$OUTSIDE"
git -C "$LINK" init -q
write_state "$LINK" "$ACTIVATION1" 1 0
LINK_COMMON_RAW=$(git -C "$LINK" rev-parse --git-common-dir)
case "$LINK_COMMON_RAW" in /*) ;; *) LINK_COMMON_RAW="$LINK/$LINK_COMMON_RAW" ;; esac
LINK_COMMON=$(cd "$LINK_COMMON_RAW" && pwd -P)
ln -s "$OUTSIDE" "$LINK_COMMON/forge-goals"
bash "$LEDGER" activate --project "$LINK" --state "$LINK/.forge/local/state.md" > "$S/link.log" 2>&1
[ "$?" -ne 0 ] && pass "symlinked ledger ancestor blocks" || fail "symlinked ledger root was accepted"

report "test-goal-ledger.sh"
