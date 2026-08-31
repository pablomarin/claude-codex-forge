#!/usr/bin/env bash
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
ACTION="$REPO_ROOT/hooks/lib/authorized-action.sh"
HOOK="$REPO_ROOT/hooks/check-external-mutation-auth.sh"

make_repo() {
  local dir="$1"; mkdir -p "$dir/.forge/local/actions"; git -C "$dir" init -q; git -C "$dir" config user.email test@example.com; git -C "$dir" config user.name ForgeTest; printf x > "$dir/x"; git -C "$dir" add x; git -C "$dir" commit -qm base
}

start_test "only allowlisted direct adapters render inert argv for human execution"
S=$(scratch_dir action); make_repo "$S"
if (cd "$S" && bash "$ACTION" prepare --adapter gh-issue-close --system github --operation close-issue --target owner/repo#12 --arg owner/repo --arg 12 --expected-effect 'issue closes' --output "$S/.forge/local/actions/pending.action") >"$S/out" 2>"$S/err"; then pass "allowlisted action prepared"; else fail "allowlisted action failed"; fi
assert_contains "$S/.forge/local/actions/pending.action" "status=PENDING_HUMAN_EXECUTION" "manifest cannot unlock an agent runner"
assert_contains "$S/out" "developer must execute" "instructions require human terminal execution"
set +e; (cd "$S" && bash "$ACTION" prepare --adapter shell --system github --operation x --target y --arg '$(touch pwned)' --expected-effect z --output "$S/.forge/local/actions/bad") >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "non-allowlisted adapter rejected"
assert_file_missing "$S/pwned" "nested shell text remains inert"

start_test "agent-written approval or result never executes or verifies mutation"
printf 'approved=true\n' >> "$S/.forge/local/actions/pending.action"
if (cd "$S" && bash "$ACTION" report --manifest "$S/.forge/local/actions/pending.action" --outcome SUCCESS --output "$S/.forge/local/actions/result.receipt") >/dev/null 2>&1; then pass "reported result is recorded for audit"; else fail "could not record result"; fi
assert_contains "$S/.forge/local/actions/result.receipt" "verification=UNVERIFIED" "human report stays unverified pending independent repro"
assert_file_missing "$S/pwned" "no execution path was unlocked"

start_test "pending manifests and report outputs are bound to one worktree and no-follow paths"
S2=$(scratch_dir action-sibling); make_repo "$S2"; mkdir -p "$S2/.forge/local/actions"
cp "$S/.forge/local/actions/pending.action" "$S2/.forge/local/actions/copied.action"
set +e
(cd "$S2" && bash "$ACTION" report --manifest "$S2/.forge/local/actions/copied.action" --outcome SUCCESS --output "$S2/.forge/local/actions/copied.receipt") >/dev/null 2>&1
copied_rc=$?
(cd "$S" && bash "$ACTION" report --manifest "$S/.forge/local/actions/pending.action" --outcome SUCCESS --output "$S/report-outside.receipt") >/dev/null 2>&1
outside_rc=$?
ln -s ../result.receipt "$S/.forge/local/actions/report-link"
(cd "$S" && bash "$ACTION" report --manifest "$S/.forge/local/actions/pending.action" --outcome SUCCESS --output "$S/.forge/local/actions/report-link") >/dev/null 2>&1
linked_rc=$?
printf 'owner\n' > "$S/.forge/local/actions/existing.receipt"
(cd "$S" && bash "$ACTION" report --manifest "$S/.forge/local/actions/pending.action" --outcome SUCCESS --output "$S/.forge/local/actions/existing.receipt") >/dev/null 2>&1
clobber_rc=$?
set -e
assert_equals "$copied_rc" "2" "copied sibling manifest is rejected by worktree identity"
assert_equals "$outside_rc" "2" "report output outside Forge local actions is rejected"
assert_equals "$linked_rc" "2" "symlink report output is rejected without following"
assert_equals "$clobber_rc" "2" "existing report output is never clobbered"
assert_contains "$S/.forge/local/actions/existing.receipt" "owner" "failed report leaves existing output byte-identical"

start_test "external mutation hook is no-op for dispatch and blocks recognizable mutation otherwise"
set +e; printf '{"tool_input":{"command":"gh issue close 12"}}' | bash "$HOOK" >"$S/hook.out" 2>"$S/hook.err"; rc=$?; set -e
assert_equals "$rc" "2" "main agent mutation attempt blocked"
assert_contains "$S/hook.err" "human" "block points to human-executed action"
set +e; printf '{"tool_input":{"command":"gh issue close 12"}}' | FORGE_DISPATCH_MODE=review bash "$HOOK" >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "0" "reviewer hook is a tested no-op"

report "authorized action"
