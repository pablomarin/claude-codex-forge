#!/usr/bin/env bash
# Deterministic project-only native Goal qualification. Live cases use only
# deliberately unavailable binaries and never authenticate.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

start_test "repository-local ledger remains the native Goal accounting contract"
bash "$REPO_ROOT/tests/template/test-goal-ledger.sh"

start_test "global Goal runtime helpers are retired from active Forge"
for retired in \
  scripts/forge-goal-authorize.sh scripts/forge-goal-authorize.ps1 \
  scripts/forge-goal-capture.sh scripts/forge-goal-capture.ps1; do
    assert_file_missing "$REPO_ROOT/$retired" "$retired is not an active runtime helper"
done
assert_not_contains "$REPO_ROOT/manifests/managed-v6.tsv" 'goal-authorize' \
    "active manifest installs no global authorizer"
assert_not_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" 'goal-authorizations' \
    "qualification has no home authorization directory"
assert_not_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" 'goal-captures' \
    "qualification has no home capture directory"

start_test "clean-home project install qualifies deterministically without a global harness"
S=$(scratch_dir project-only-goal-qualification)
P="$S/project"
mkdir -p "$P" "$S/home"
git -C "$P" init -q
git -C "$P" config user.email forge@example.invalid
git -C "$P" config user.name Forge
printf 'project\n' > "$P/app.txt"
git -C "$P" add app.txt
git -C "$P" commit -qm base
(cd "$P" && HOME="$S/home" bash "$REPO_ROOT/setup.sh" > "$S/setup.log" 2>&1)
set +e
HOME="$S/home" bash "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" \
    --project "$P" --evidence-dir "$P/.forge/local/evidence/project-only-goal" \
    --live none > "$S/qualify.log" 2>&1
qualify_rc=$?
set -e
assert_equals "$qualify_rc" "0" "deterministic project-only qualification succeeds"
assert_contains "$S/qualify.log" 'GOAL_DETERMINISTIC: PASS' \
    "deterministic Goal ledger qualification passes"
assert_contains "$S/qualify.log" 'GLOBAL_HARNESS: NOT_REQUIRED' \
    "qualification explicitly needs no machine-global harness"
assert_file_missing "$S/home/.forge" "clean HOME remains free of Forge runtime state"

start_test "unavailable live host blocks truthfully"
set +e
PATH=/usr/bin:/bin HOME="$S/home" /bin/bash "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" \
    --project "$P" --evidence-dir "$P/.forge/local/evidence/unavailable-codex" \
    --live codex > "$S/live-blocked.log" 2>&1
live_rc=$?
set -e
[ "$live_rc" -ne 0 ] && pass "unavailable live host returns nonzero" || fail "unavailable live host returned success"
assert_contains "$S/live-blocked.log" 'GOAL_LIVE: BLOCKED host=codex reason=' \
    "unavailable host reports a concrete live blocker"

report "test-goal-feasibility.sh"
