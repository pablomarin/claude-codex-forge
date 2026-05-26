#!/usr/bin/env bash
# tests/template/test-hooks.sh — runtime fixture tests for check-workflow-gates.
#
# Feeds synthetic CONTINUITY.md fixtures + JSON stdin into the workflow-gate
# hooks (.sh and .ps1) and asserts exit codes match expectations. Catches the
# "marker text drifted silently, gate passes everything" class of regression
# that the Scalability Hawk flagged during Council.
#
# Run from repo root: bash tests/template/test-hooks.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

# Note: not sourcing test-fixtures.sh here — it runs its own tests at top
# level. Helpers we need (make_state_md) are inlined locally where used.
init_counters

# Local helper (mirrors make_state_md from test-fixtures.sh; kept inline to
# avoid sourcing test-fixtures.sh which would re-run its own test cases).
_make_state_md() {
    local scratch="$1"
    local cmd="${2:-/new-feature foo}"
    local phase="${3:-3 — Design}"
    local next="${4:-Plan written}"
    shift 4
    mkdir -p "$scratch/.claude/local"
    {
        echo "## Workflow"
        echo ""
        echo "| Field     | Value |"
        echo "| --------- | ----- |"
        echo "| Command   | $cmd  |"
        echo "| Phase     | $phase |"
        echo "| Next step | $next |"
        echo ""
        echo "### Checklist"
        echo ""
        for item in "$@"; do
            echo "- [ ] $item"
        done
    } > "$scratch/.claude/local/state.md"
}

HOOK_SH="$REPO_ROOT/hooks/check-workflow-gates.sh"
HOOK_PS="$REPO_ROOT/hooks/check-workflow-gates.ps1"

# ---------------------------------------------------------------------------
# Fixture helper: write a CONTINUITY.md with a Workflow table + checklist in
# a scratch dir, run the hook there with a synthetic tool_input JSON, capture
# exit code + stderr.
#
# Usage:
#   run_hook_sh <scratch_dir> <ship_command> <continuity_checklist_body>
#
# `continuity_checklist_body` is everything between "### Checklist" and the
# next "## " heading — pass the checkbox lines only.
# ---------------------------------------------------------------------------
run_hook_sh() {
    local scratch="$1" command="$2" checklist="$3"
    mkdir -p "$scratch/.claude/local"
    cat > "$scratch/.claude/local/state.md" <<EOF
## Workflow

| Field     | Value              |
| --------- | ------------------ |
| Command   | /new-feature test  |
| Phase     | 5 — Quality Gates  |
| Next step | ship               |

### Checklist

$checklist

## State

### Done

### Now

### Next
EOF
    printf '{"tool_input":{"command":"%s"}}' "$(printf '%s' "$command" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')" > "$scratch/.hook-input.json"
    # Hook expects to run in the dir that has .claude/local/state.md
    (cd "$scratch" && bash "$HOOK_SH" < "$scratch/.hook-input.json") > "$scratch/.hook-stdout" 2> "$scratch/.hook-stderr"
    echo "$?"
}

run_hook_ps() {
    local scratch="$1" command="$2" checklist="$3"
    if ! command -v pwsh >/dev/null 2>&1; then
        echo "SKIP"
        return
    fi
    mkdir -p "$scratch/.claude/local"
    cat > "$scratch/.claude/local/state.md" <<EOF
## Workflow

| Field     | Value              |
| --------- | ------------------ |
| Command   | /new-feature test  |
| Phase     | 5 — Quality Gates  |
| Next step | ship               |

### Checklist

$checklist

## State

### Done

### Now

### Next
EOF
    printf '{"tool_input":{"command":"%s"}}' "$(printf '%s' "$command" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')" > "$scratch/.hook-input.json"
    (cd "$scratch" && pwsh -NoProfile -File "$HOOK_PS" < "$scratch/.hook-input.json") > "$scratch/.hook-stdout" 2> "$scratch/.hook-stderr"
    echo "$?"
}

# ===========================================================================
# Test 1: all gates checked → hook passes (exit 0)
# ===========================================================================
start_test "all gates checked [x] → exit 0"

CHECKLIST_ALL_CHECKED='- [x] Code review loop (2 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified via verify-e2e agent (Phase 5.4)'

S1=$(scratch_dir hooks-allchecked)
rc=$(run_hook_sh "$S1" 'git commit -m "ship it"' "$CHECKLIST_ALL_CHECKED")
assert_equals "$rc" "0" ".sh passes when all gates are [x]"

# ===========================================================================
# Test 2: E2E verified unchecked → hook blocks (exit 2)
# This is the msai-v2 root cause — the whole reason this suite exists.
# ===========================================================================
start_test "E2E verified [ ] unchecked → exit 2 (blocks ship)"

CHECKLIST_E2E_UNCHECKED='- [x] Code review loop (2 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [ ] E2E verified via verify-e2e agent (Phase 5.4)'

S2=$(scratch_dir hooks-e2e-unchecked)
rc=$(run_hook_sh "$S2" 'git commit -m "ship it"' "$CHECKLIST_E2E_UNCHECKED")
assert_equals "$rc" "2" ".sh blocks when E2E verified is unchecked"
assert_contains "$S2/.hook-stderr" "E2E verified" \
    "stderr names the missing gate"
assert_contains "$S2/.hook-stderr" "rules/testing.md" \
    "stderr points to canonical doc"
assert_contains "$S2/.hook-stderr" "verify-e2e agent" \
    "stderr tells user how to clear the gate"

# ===========================================================================
# Test 3: E2E verified checked with N/A reason → hook passes (exit 0)
# Verifies the escape valve works as documented.
# ===========================================================================
start_test "E2E verified [x] — N/A: <reason> → exit 0"

CHECKLIST_E2E_NA='- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: internal migration, no user-facing changes'

S3=$(scratch_dir hooks-e2e-na)
rc=$(run_hook_sh "$S3" 'git commit -m "shipit"' "$CHECKLIST_E2E_NA")
assert_equals "$rc" "0" ".sh passes when E2E verified is [x] with N/A"

# ===========================================================================
# Test 4: multiple gates unchecked → stderr enumerates all of them
# ===========================================================================
start_test "multiple gates unchecked → all listed in stderr"

CHECKLIST_MULTI='- [ ] Code review loop
- [x] Simplified
- [ ] Verified (tests/lint/types)
- [ ] E2E verified via verify-e2e agent (Phase 5.4)'

S4=$(scratch_dir hooks-multi)
rc=$(run_hook_sh "$S4" 'gh pr create' "$CHECKLIST_MULTI")
assert_equals "$rc" "2" ".sh blocks when 3 gates unchecked"
assert_contains "$S4/.hook-stderr" "Code review loop" \
    "stderr lists 'Code review loop'"
assert_contains "$S4/.hook-stderr" "Verified" \
    "stderr lists 'Verified'"
assert_contains "$S4/.hook-stderr" "E2E verified" \
    "stderr lists 'E2E verified'"

# ===========================================================================
# Test 5: non-ship command (e.g., 'ls -la') → hook allows immediately
# (regression guard: adding the E2E gate didn't widen the ship-detection)
# ===========================================================================
start_test "non-ship command → exit 0 regardless of checklist"

S5=$(scratch_dir hooks-nonship)
rc=$(run_hook_sh "$S5" 'ls -la' "$CHECKLIST_E2E_UNCHECKED")
assert_equals "$rc" "0" ".sh allows 'ls -la' even with gates unchecked"

# ===========================================================================
# Test 6: no active workflow (Command=none) → hook allows
# ===========================================================================
start_test "Command=none → hook passes even with unchecked gates"

S6=$(scratch_dir hooks-noworkflow)
mkdir -p "$S6/.claude/local"
cat > "$S6/.claude/local/state.md" <<EOF
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |

### Checklist

- [ ] E2E verified via verify-e2e agent (Phase 5.4)

## State
EOF
printf '{"tool_input":{"command":"git commit -m test"}}' > "$S6/.hook-input.json"
(cd "$S6" && bash "$HOOK_SH" < "$S6/.hook-input.json") > "$S6/.hook-stdout" 2> "$S6/.hook-stderr"
assert_equals "$?" "0" ".sh passes when workflow is inactive (Command=none)"

# ===========================================================================
# Test 7: non-gate items that contain similar words → NOT gated
# "PR reviews addressed", "Plugins verified", "Plan review loop",
# "E2E use cases designed", "E2E regression passed"
# ===========================================================================
start_test "non-gate items with similar words are NOT gated"

CHECKLIST_NEAR_MISS='- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: pure refactor
- [ ] E2E use cases designed (Phase 3.2b)
- [ ] E2E regression passed (Phase 5.4b)
- [ ] PR reviews addressed
- [ ] Plugins verified
- [ ] Plan review loop (0 iterations)'

S7=$(scratch_dir hooks-near-miss)
rc=$(run_hook_sh "$S7" 'git push' "$CHECKLIST_NEAR_MISS")
assert_equals "$rc" "0" "non-gate items don't trigger the gate"

# ===========================================================================
# Test 8: PowerShell parity — same fixtures, same expected exit codes
# (skipped if pwsh not installed, so this doesn't break macOS/Linux CI
# boxes without PowerShell)
# ===========================================================================
start_test "PowerShell parity (.ps1 matches .sh on the same fixtures)"

if command -v pwsh >/dev/null 2>&1; then
    S8a=$(scratch_dir hooks-ps-allchecked)
    rc=$(run_hook_ps "$S8a" 'git commit -m x' "$CHECKLIST_ALL_CHECKED")
    assert_equals "$rc" "0" ".ps1 passes when all gates [x]"

    S8b=$(scratch_dir hooks-ps-e2e-unchecked)
    rc=$(run_hook_ps "$S8b" 'git commit -m x' "$CHECKLIST_E2E_UNCHECKED")
    assert_equals "$rc" "2" ".ps1 blocks when E2E verified unchecked"
    assert_contains "$S8b/.hook-stderr" "E2E verified" \
        ".ps1 stderr names the missing gate"

    S8c=$(scratch_dir hooks-ps-e2e-na)
    rc=$(run_hook_ps "$S8c" 'git commit -m x' "$CHECKLIST_E2E_NA")
    assert_equals "$rc" "0" ".ps1 passes when E2E verified [x] — N/A"
else
    printf "  %s·%s skipped: pwsh not installed\n" "$C_DIM" "$C_RESET"
fi

# ===========================================================================
# Evidence-gate scenarios (Phase 2 — closes the paperwork-not-evidence loophole)
# These require a real git repo with a branch-off point, so each test sets up
# a scratch repo with main + feature branch before invoking the hook.
# ===========================================================================

# Helper: build a scratch git repo with main + feature branch.
# Feature branch's HEAD is where we're "at"; main's last commit is the
# branch-off point whose timestamp the hook compares against.
# Echoes the scratch dir path.
setup_git_scratch() {
    local dir
    dir=$(scratch_dir e2e-evidence)
    local head
    (
        cd "$dir" || exit 1
        git init -q --initial-branch=main
        git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial-on-main"
        # Wait a second so branch-off timestamp is strictly less than
        # any files we create post-checkout (avoids flaky == comparisons
        # on fast CPUs).
        sleep 1
        git checkout -q -b feature/test
        # Real feature branches have at least one commit beyond the
        # branch-off point. Without this, HEAD == merge-base and the
        # evidence check would (correctly) skip as "on main directly"
        # — making the feature-branch tests no-ops.
        git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "feature work"
    )
    # Capture the post-feature-commit HEAD so callers can bind per-iter
    # Code-review clean lines to it (required by the v5.39 evidence gate).
    head=$(cd "$dir" && git rev-parse HEAD)
    echo "$dir|$head"
}

# Helper: inject an E2E verified [x] entry into the checklist template.
# These are now functions (not constants) because the v5.39 code-review
# evidence gate requires per-iter clean lines bound to the actual HEAD.
checklist_e2e_checked_no_na() {
    local head="$1"
    cat <<EOF
- [x] Code review loop (1 iterations) — PASS
$(make_code_review_clean_lines 1 "$head")
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF
}

checklist_e2e_checked_na() {
    local head="$1"
    cat <<EOF
- [x] Code review loop (1 iterations) — PASS
$(make_code_review_clean_lines 1 "$head")
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: internal migration, no user-facing changes
EOF
}

# ===========================================================================
# Test 9: [x] E2E verified without N/A + fresh report → exit 0
# ===========================================================================
start_test "[x] E2E verified + fresh report → exit 0 (evidence satisfied)"

result=$(setup_git_scratch)
S9=$(echo "$result" | cut -d'|' -f1)
HEAD9=$(echo "$result" | cut -d'|' -f2)
mkdir -p "$S9/tests/e2e/reports"
# Create a report file AFTER branch-off (its mtime is > branch-off-ts)
echo "# E2E report" > "$S9/tests/e2e/reports/2026-04-19-10-00-feature.md"
rc=$(run_hook_sh "$S9" 'git commit -m x' "$(checklist_e2e_checked_no_na "$HEAD9")")
assert_equals "$rc" "0" "fresh report present → hook passes"

# ===========================================================================
# Test 10: [x] E2E verified without N/A + no report → exit 2
# ===========================================================================
start_test "[x] E2E verified + no report → exit 2 (evidence missing)"

result=$(setup_git_scratch)
S10=$(echo "$result" | cut -d'|' -f1)
HEAD10=$(echo "$result" | cut -d'|' -f2)
# No tests/e2e/reports/ directory at all
rc=$(run_hook_sh "$S10" 'git commit -m x' "$(checklist_e2e_checked_no_na "$HEAD10")")
assert_equals "$rc" "2" "no reports dir → hook blocks"
assert_contains "$S10/.hook-stderr" "no fresh report was found" \
    "stderr explains the evidence gap"
assert_contains "$S10/.hook-stderr" "verify-e2e agent was never actually run" \
    "stderr explains the likely cause"
assert_contains "$S10/.hook-stderr" "E2E verified — N/A:" \
    "stderr shows the N/A escape syntax"

# ===========================================================================
# Test 11: [x] E2E verified without N/A + STALE report (pre-branch-off) → exit 2
# ===========================================================================
start_test "[x] E2E verified + only stale reports → exit 2"

result=$(setup_git_scratch)
S11=$(echo "$result" | cut -d'|' -f1)
HEAD11=$(echo "$result" | cut -d'|' -f2)
mkdir -p "$S11/tests/e2e/reports"
echo "# old report" > "$S11/tests/e2e/reports/2024-01-01-old.md"
# Force mtime to 2024-01-01 — definitely before any branch-off we just made
touch -t 202401010000.00 "$S11/tests/e2e/reports/2024-01-01-old.md"
rc=$(run_hook_sh "$S11" 'git commit -m x' "$(checklist_e2e_checked_no_na "$HEAD11")")
assert_equals "$rc" "2" "only stale reports → hook blocks"

# ===========================================================================
# Test 12: [x] E2E verified — N/A: reason → exit 0 (no evidence needed)
# ===========================================================================
start_test "[x] E2E verified — N/A: reason → exit 0 (N/A bypasses evidence check)"

result=$(setup_git_scratch)
S12=$(echo "$result" | cut -d'|' -f1)
HEAD12=$(echo "$result" | cut -d'|' -f2)
# No reports directory — N/A should bypass the evidence check entirely
rc=$(run_hook_sh "$S12" 'git commit -m x' "$(checklist_e2e_checked_na "$HEAD12")")
assert_equals "$rc" "0" "N/A form skips evidence check even without a report"

# ===========================================================================
# Test 13: No merge-base (repo without main) → skip evidence check gracefully
# ===========================================================================
start_test "no merge-base available → skip evidence check (degraded env)"

S13=$(scratch_dir e2e-nomaster)
(
    cd "$S13" || exit 1
    git init -q --initial-branch=weird
    git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"
)
# Capture the inline HEAD so the per-iter code-review clean line binds to it
# (the v5.39 code-review evidence gate sees a real HEAD here).
HEAD13=$(cd "$S13" && git rev-parse HEAD)
# No main, no master. Hook can't compute merge-base; should skip evidence
# rather than fail. User gets no protection here — documented as a
# degraded env, not a policy violation.
rc=$(run_hook_sh "$S13" 'git commit -m x' "$(checklist_e2e_checked_no_na "$HEAD13")")
assert_equals "$rc" "0" "degraded env (no main/master) → hook passes with warning"

# ===========================================================================
# Test 14: On main itself → skip evidence check (trunk-based workflow)
# Regression guard for Codex's P1: git merge-base HEAD main returns HEAD
# when on main, which is NOT empty. Without special-case handling, the
# hook would require reports newer than HEAD — which is usually impossible
# because reports are produced AFTER HEAD, not before.
# ===========================================================================
start_test "user on main → skip evidence check (trunk-based)"

S14=$(scratch_dir e2e-on-main)
(
    cd "$S14" || exit 1
    git init -q --initial-branch=main
    git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"
    # STAY on main — no feature branch checkout.
)
# Capture the inline HEAD so the per-iter code-review clean line binds to it.
HEAD14=$(cd "$S14" && git rev-parse HEAD)
# [x] E2E verified without N/A + no reports. Without the HEAD==branch-off
# fix, this would block. With the fix, it should pass (skip evidence).
rc=$(run_hook_sh "$S14" 'git commit -m x' "$(checklist_e2e_checked_no_na "$HEAD14")")
assert_equals "$rc" "0" "on main directly → evidence check skipped (trunk-based workflow supported)"

# ===========================================================================
# Test 15: check-state-updated.sh master-default repo — CHANGELOG gate fires
# correctly when default branch is "master" (not "main").
#
# Regression guard for the pre-migration hook (hardcoded `main`):
#   - Pre-migration: `git merge-base main HEAD` → empty (no main branch)
#     → BRANCH_BASE falls back to HEAD~10 → wrong baseline → count wrong
#   - Post-migration: default-branch.sh detects "master" → correct
#     merge-base → BRANCH_CHANGED >= 4 → CHANGELOG gate fires (exit 2)
# ===========================================================================
start_test "check-state-updated.sh: master-default repo → CHANGELOG gate fires (exit 2)"

HOOK_STATE="$REPO_ROOT/hooks/check-state-updated.sh"

# Build a scratch repo with master as the default branch, no main branch.
# Feature branch has 4 committed files in subdirs → BRANCH_CHANGED = 4 > 3.
# No CHANGELOG entry anywhere → gate fires.
S15=$(scratch_dir state-master-default)
(
    cd "$S15" || exit 1
    git init -q
    git -c user.email=test@test -c user.name=test checkout -q -b master
    git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial on master"
    git -c user.email=test@test -c user.name=test checkout -q -b feature/x
    # Add 4 files in subdirs (not gitignored) as tracked+committed on the feature branch.
    # git status --porcelain on these committed files shows nothing (already clean),
    # but git diff --name-only master..HEAD counts all 4 for BRANCH_CHANGED.
    mkdir -p src/a src/b
    printf 'x' > src/a/file1.txt
    printf 'x' > src/a/file2.txt
    printf 'x' > src/b/file3.txt
    printf 'x' > src/b/file4.txt
    git add src/
    git -c user.email=test@test -c user.name=test commit -q -m "feature work: 4 files"
)

# Write a minimal state.md (no active workflow, no CHANGELOG entry).
mkdir -p "$S15/.claude/local"
cat > "$S15/.claude/local/state.md" <<'CONT'
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |

## State

### Done
- Some work done

### Now
Working on feature/x

### Next
Nothing
CONT

# Run check-state-updated.sh from the scratch repo.
# stdin: '{"stop_hook_active":false}' (mirrors real Stop hook input).
rc15=$(printf '{"stop_hook_active":false}' | (cd "$S15" && bash "$HOOK_STATE") 2>"$S15/.state-stderr"; echo "$?")
assert_equals "$rc15" "2" "CHANGELOG gate fires on master-default repo (exit 2)"
assert_contains "$S15/.state-stderr" "CHANGELOG" \
    "stderr mentions CHANGELOG threshold"
assert_contains "$S15/.state-stderr" "on branch vs master" \
    "stderr wording reflects branch-vs-default-branch (not 'this session')"

# ===========================================================================
# Test 15b: check-state-updated.sh — CHANGELOG gate downgrades to advisory
# (exit 0) when an OPEN PR already exists for the branch.
#
# Surfaced 2026-05-18 during /forge-goal v1.0 soak in msai-v2:
# the per-turn exit-2 nag during CI wait label-prefixed the build-evidence
# STDERR dump as "Stop hook error", flooding the transcript every Stop.
# Once the PR is open the human reviewer carries the signal — gate becomes
# advisory.
# ===========================================================================
start_test "check-state-updated.sh: open PR → CHANGELOG gate downgrades to advisory (exit 0)"

S15B=$(scratch_dir state-pr-open-advisory)
(
    cd "$S15B" || exit 1
    git init -q
    git -c user.email=test@test -c user.name=test checkout -q -b main
    git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"
    git -c user.email=test@test -c user.name=test checkout -q -b feature/x
    mkdir -p src/a src/b
    printf 'x' > src/a/file1.txt
    printf 'x' > src/a/file2.txt
    printf 'x' > src/b/file3.txt
    printf 'x' > src/b/file4.txt
    git add src/
    git -c user.email=test@test -c user.name=test commit -q -m "feature work: 4 files"
)

mkdir -p "$S15B/.claude/local"
cat > "$S15B/.claude/local/state.md" <<'CONT'
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |

## State

### Done
- Some work done

### Now
Working on feature/x

### Next
Nothing
CONT

# Build a fake `gh` on PATH that returns "OPEN" for `gh pr view --json state -q .state`.
# Use a sibling stub dir so the real gh is shadowed only for this test.
GH_STUB_DIR="$S15B/.bin"
mkdir -p "$GH_STUB_DIR"
cat > "$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stub matches the exact subcommand the hook uses.
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    echo "OPEN"
    exit 0
fi
exit 1
STUB
chmod +x "$GH_STUB_DIR/gh"

rc15b=$(printf '{"stop_hook_active":false}' | (cd "$S15B" && PATH="$GH_STUB_DIR:$PATH" bash "$HOOK_STATE") 2>"$S15B/.state-stderr"; echo "$?")
assert_equals "$rc15b" "0" "open PR → exit 0 (advisory, not blocking)"
assert_contains "$S15B/.state-stderr" "CHANGELOG" \
    "stderr still mentions CHANGELOG so the human sees the advisory"

# ===========================================================================
# Test 15c: regression guard — gh pr view probe MUST NOT fire on clean Stops.
#
# Surfaced by Codex review of v5.30 (P2): the first cut of the fix called
# `gh pr view` unconditionally whenever gh was installed, adding an API call
# to every Stop hook in every repo (~250ms+ on offline/slow networks). Probe
# must be lazy: only run when CHANGELOG block would fire.
#
# Test strategy: wire a gh stub that writes a tripwire file if invoked. Run
# the hook on a clean repo (no CHANGELOG block trigger). Assert: exit 0 and
# tripwire file does NOT exist (i.e. stub was never called).
# ===========================================================================
start_test "check-state-updated.sh: gh pr view probe is lazy — not called on clean Stops"

S15C=$(scratch_dir state-clean-stop-no-gh-probe)
(
    cd "$S15C" || exit 1
    git init -q
    git -c user.email=test@test -c user.name=test checkout -q -b main
    git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"
    # NO feature branch with 4+ files. Working tree clean. CHANGELOG block will not fire.
)

mkdir -p "$S15C/.claude/local"
cat > "$S15C/.claude/local/state.md" <<'CONT'
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |

## State

### Done
- Clean
CONT

# Tripwire stub: any invocation writes a marker file, then returns OPEN.
TRIPWIRE="$S15C/.gh-was-called"
GH_STUB_DIR_C="$S15C/.bin"
mkdir -p "$GH_STUB_DIR_C"
cat > "$GH_STUB_DIR_C/gh" <<STUB
#!/usr/bin/env bash
touch "$TRIPWIRE"
echo "OPEN"
exit 0
STUB
chmod +x "$GH_STUB_DIR_C/gh"

rc15c=$(printf '{"stop_hook_active":false}' | (cd "$S15C" && PATH="$GH_STUB_DIR_C:$PATH" bash "$HOOK_STATE") 2>"$S15C/.state-stderr"; echo "$?")
assert_equals "$rc15c" "0" "clean Stop → exit 0"
assert_file_missing "$TRIPWIRE" \
    "gh pr view probe is lazy — tripwire NOT touched on clean Stop"

# ===========================================================================
# Hard-cut test: state.md missing + legacy CONTINUITY.md present →
# check-workflow-gates.sh must NOT fall back to CONTINUITY.md (post PR #2).
# Hook should exit 0 (no gating without state.md) and emit a breadcrumb.
# ===========================================================================
start_test "hard-cut: state.md missing + CONTINUITY.md present → exit 0, no gating"

S_HC=$(scratch_dir hard-cut-no-fallback)
( cd "$S_HC" && git init -q && git checkout -q -b main )
# User has CONTINUITY.md with unchecked gates BUT no state.md.
cat > "$S_HC/CONTINUITY.md" <<'EOF'
## Workflow
| Field | Value |
| Command | /new-feature foo |
### Checklist
- [ ] Code review loop
EOF
out_hc=$(cd "$S_HC" && echo '{"tool_input":{"command":"git commit -m foo"}}' | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>&1)
rc_hc=$?

if echo "$out_hc" | grep -qF "state.md not found"; then
    pass "hook emits state.md missing breadcrumb"
else
    fail "hook did not emit 'state.md not found' breadcrumb (got: $out_hc)"
fi
# P2-5: breadcrumb must name the migration command. Without this, AC-4
# byte-parity could break (one platform changes the wording, the other
# doesn't) before AC-13 catches it.
if echo "$out_hc" | grep -qF "setup --migrate"; then
    pass "breadcrumb names migration command ('setup --migrate')"
else
    fail "breadcrumb does NOT name migration command (got: $out_hc)"
fi
assert_equals "$rc_hc" "0" "hook exits 0 (does NOT gate even with CONTINUITY.md present)"

# ===========================================================================
# Stop-hook advisory test: uncommitted changes + state.md unchanged should
# emit advisory reminder but exit 0 (post PR #2 — no CONTINUITY-style block).
# ===========================================================================
start_test "Stop hook is advisory-only (state.md unchanged → exit 0)"

S_AD=$(scratch_dir stop-advisory)
(
    cd "$S_AD" || exit 1
    git init -q
    git -c user.email=test@test -c user.name=test checkout -q -b main
    touch a
    git add a
    git -c user.email=test@test -c user.name=test commit -q -m init
)
# Uncommitted changes + state.md unchanged should NOT block.
( cd "$S_AD" && echo "uncommitted" > new.txt )
_make_state_md "$S_AD"

out_ad=$(cd "$S_AD" && bash "$REPO_ROOT/hooks/check-state-updated.sh" < /dev/null 2>&1)
rc_ad=$?

if echo "$out_ad" | grep -qE "WORKFLOW:.*Phase:.*Next:"; then
    pass "advisory reminder on stderr (WORKFLOW: phase/next-step present)"
else
    fail "advisory reminder missing (got: $out_ad)"
fi
assert_equals "$rc_ad" "0" "Stop hook always exits 0 (advisory-only)"

# ===========================================================================
# Regression: stray Workflow-shaped tables in state.md must NOT poison the
# Stop hook's WORKFLOW reminder.
#
# Pre-fix bug: hooks/check-state-updated.sh did `grep | awk | xargs` over the
# WHOLE state.md, then xargs joined N matches with spaces. When migrated
# content (e.g., from `setup.sh --migrate` ingesting an old CONTINUITY.md
# Done entry that quoted a prior workflow scaffold) carried a stray
# `| Command | … |` line in `### Done`, the reminder became garbage like:
#   "WORKFLOW: none /lifecycle | Phase: n/a shipping | Next: n/a Fix #654 …"
# Fix: scope extraction to ONLY the `## Workflow` section, then head -1.
# ===========================================================================
start_test "regression: stray Workflow tables in Done section don't poison reminder"

S_STRAY=$(scratch_dir state-stray-tables)
mkdir -p "$S_STRAY/.claude/local"
cat > "$S_STRAY/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |
| Phase     | n/a   |
| Next step | n/a   |

### Checklist

## State

### Done
- Phase 4 task-DAG: 2026-04-21. Updated table:
  | Field     | Value             |
  | Command   | /lifecycle        |
  | Phase     | shipping          |
  | Next step | Fix #654 findings |
  Council-reviewed and merged.

### Now
On main, clean.
EOF

# stop_hook_active=false to mirror real Stop hook input.
out_stray=$(cd "$S_STRAY" && printf '{"stop_hook_active":false}' | bash "$REPO_ROOT/hooks/check-state-updated.sh" 2>&1)
rc_stray=$?

# Canonical Command is `none` → no advisory should fire at all.
if echo "$out_stray" | grep -qE "WORKFLOW:"; then
    fail "stray-table fixture leaked a WORKFLOW reminder (got: $out_stray)"
else
    pass "Command=none in canonical scaffold → no WORKFLOW reminder despite stray tables"
fi
# Specifically guard against the garbage shape: 'none /lifecycle' joined-by-space.
if echo "$out_stray" | grep -qF "none /lifecycle"; then
    fail "regression: WORKFLOW reminder contains joined garbage 'none /lifecycle'"
else
    pass "no joined-garbage shape ('none /lifecycle') in stderr"
fi
assert_equals "$rc_stray" "0" "Stop hook exits 0 even with stray tables"

# Companion case: stray table appears BEFORE the canonical `## Workflow` heading.
# Pre-fix, `head -1` (PowerShell `Select-Object -First 1`) would pick the stray.
start_test "regression: stray Workflow tables BEFORE canonical heading don't poison reminder"

S_STRAY2=$(scratch_dir state-stray-before)
mkdir -p "$S_STRAY2/.claude/local"
cat > "$S_STRAY2/.claude/local/state.md" <<'EOF'
# State

Some preamble describing migration.

### Done
- Stray table mention from migrated content:
  | Field     | Value             |
  | Command   | /new-feature foo  |
  | Phase     | shipping          |
  | Next step | Fix things        |

## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |
| Phase     | n/a   |
| Next step | n/a   |

### Checklist
EOF

out_stray2=$(cd "$S_STRAY2" && printf '{"stop_hook_active":false}' | bash "$REPO_ROOT/hooks/check-state-updated.sh" 2>&1)
rc_stray2=$?

if echo "$out_stray2" | grep -qE "WORKFLOW:"; then
    fail "stray-before-canonical fixture leaked a WORKFLOW reminder (got: $out_stray2)"
else
    pass "stray table BEFORE canonical scaffold ignored; canonical Command=none wins"
fi
assert_equals "$rc_stray2" "0" "Stop hook exits 0 with stray-before fixture"

# ===========================================================================
# Regression: same bug class in check-workflow-gates.sh — stray tables must
# not change which Workflow scaffold is read for ship-action gating.
#
# Pre-fix: grep over whole file with `head -1` could pick a stray
# `| Command | /foo |` line in migrated Done content (when stray appears
# BEFORE the canonical scaffold), causing the gate to treat the workflow
# as active and block ship even when the canonical Command is `none`.
# ===========================================================================
start_test "regression: check-workflow-gates ignores stray tables before canonical"

S_GATE=$(scratch_dir gates-stray-before)
mkdir -p "$S_GATE/.claude/local"
cat > "$S_GATE/.claude/local/state.md" <<'EOF'
# State

### Done
- Old finished feature, table snippet:
  | Field     | Value             |
  | Command   | /new-feature foo  |
  | Phase     | shipping          |

## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |

### Checklist

- [ ] E2E verified via verify-e2e agent (Phase 5.4)
EOF

printf '{"tool_input":{"command":"git commit -m test"}}' > "$S_GATE/.hook-input.json"
(cd "$S_GATE" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh" < "$S_GATE/.hook-input.json") > "$S_GATE/.hook-stdout" 2> "$S_GATE/.hook-stderr"
rc_gate=$?

assert_equals "$rc_gate" "0" \
    "check-workflow-gates: canonical Command=none wins over stray /new-feature in Done"

# ===========================================================================
# Regression: check-workflow-gates also ignores stray Workflow-shaped content
# in `### Done` AFTER the canonical scaffold. Specifically: a stray
# `### Checklist` heading or `- [ ]` items in the Done section must not be
# treated as part of the workflow checklist.
# ===========================================================================
start_test "regression: check-workflow-gates ignores stray checklist items in Done"

S_GATE2=$(scratch_dir gates-stray-checklist)
mkdir -p "$S_GATE2/.claude/local"
cat > "$S_GATE2/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value              |
| --------- | ------------------ |
| Command   | /new-feature test  |
| Phase     | 5 — Quality Gates  |
| Next step | ship               |

### Checklist

- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: refactor

## State

### Done
- Old feature shipped; quoting its checklist for posterity:
  - [ ] Code review loop
  - [ ] E2E verified via verify-e2e agent (Phase 5.4)
EOF

printf '{"tool_input":{"command":"git commit -m test"}}' > "$S_GATE2/.hook-input.json"
(cd "$S_GATE2" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh" < "$S_GATE2/.hook-input.json") > "$S_GATE2/.hook-stdout" 2> "$S_GATE2/.hook-stderr"
rc_gate2=$?

assert_equals "$rc_gate2" "0" \
    "check-workflow-gates: stray '- [ ] Code review loop' in Done does not block ship"

# ===========================================================================
# PowerShell parity for the regression cases (skipped if pwsh not installed)
# ===========================================================================
start_test "PowerShell parity: stray Workflow tables don't poison .ps1 hooks"

if command -v pwsh >/dev/null 2>&1; then
    # Reuse the bash fixtures — same state.md, run the .ps1 hook.
    out_ps_stray=$(cd "$S_STRAY" && printf '{"stop_hook_active":false}' | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-state-updated.ps1" 2>&1)
    if echo "$out_ps_stray" | grep -qE "WORKFLOW:"; then
        fail ".ps1 stray-table fixture leaked a WORKFLOW reminder"
    else
        pass ".ps1 ignores stray tables in Done section"
    fi

    out_ps_stray2=$(cd "$S_STRAY2" && printf '{"stop_hook_active":false}' | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-state-updated.ps1" 2>&1)
    if echo "$out_ps_stray2" | grep -qE "WORKFLOW:"; then
        fail ".ps1 stray-before-canonical fixture leaked a WORKFLOW reminder"
    else
        pass ".ps1 ignores stray tables before canonical heading"
    fi

    (cd "$S_GATE" && pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" < "$S_GATE/.hook-input.json") > "$S_GATE/.hook-ps-stdout" 2> "$S_GATE/.hook-ps-stderr"
    rc_ps_gate=$?
    assert_equals "$rc_ps_gate" "0" \
        ".ps1 check-workflow-gates: canonical Command=none wins over stray /new-feature in Done"

    (cd "$S_GATE2" && pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" < "$S_GATE2/.hook-input.json") > "$S_GATE2/.hook-ps-stdout" 2> "$S_GATE2/.hook-ps-stderr"
    rc_ps_gate2=$?
    assert_equals "$rc_ps_gate2" "0" \
        ".ps1 check-workflow-gates: stray '- [ ]' in Done does not block ship"
else
    printf "  %s·%s skipped: pwsh not installed\n" "$C_DIM" "$C_RESET"
fi

# ===========================================================================
# Test N: check-state-updated emits FORGE_GOAL_EVIDENCE markers even when
# stop_hook_active=true.
#
# Regression guard for the bug where the early-return path (active /goal loop)
# suppressed evidence emission entirely, defeating Layer 1 of /forge-goal.
#
# v5.32 architecture: build-evidence is registered as its own Stop hook
# (BEFORE check-state-updated) in settings.template.json. It always exits 0
# and writes evidence to STDERR regardless of stop_hook_active. This test
# now invokes build-evidence directly with stop_hook_active=true to assert
# evidence still emits inside an active /goal loop.
# ===========================================================================
start_test "build-evidence emits FORGE_GOAL_EVIDENCE markers even when stop_hook_active=true"

HOOK_EVIDENCE_SH="$REPO_ROOT/hooks/build-evidence.sh"

SN=$(scratch_dir checkstateupd-evidence)
mkdir -p "$SN/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$SN/.claude/local/state.md"

OUT_N="$SN/.out"
(
    cd "$SN" || exit 1
    INPUT='{"stop_hook_active":true,"transcript_path":"/tmp/x"}'
    echo "$INPUT" | bash "$HOOK_EVIDENCE_SH" > "$OUT_N" 2>&1
)

assert_contains "$OUT_N" "FORGE_GOAL_EVIDENCE_BEGIN" \
    "evidence begin marker emits despite stop_hook_active=true"
assert_contains "$OUT_N" "FORGE_GOAL_EVIDENCE_END" \
    "evidence end marker emits despite stop_hook_active=true"

# ===========================================================================
# Layer 2: PR-create authorization guard (Task 3)
# These tests exercise the new /forge-goal guard in check-workflow-gates.sh.
# Each test runs inside a subshell to prevent pwd leakage.
# ===========================================================================

# ---------------------------------------------------------------------------
# Test L2-1: /goal session active + no ## PR authorization → blocked (exit 2)
# ---------------------------------------------------------------------------
start_test "check-workflow-gates blocks gh pr create when ## PR authorization missing during active /forge-goal"

scratch=$(scratch_dir wgates-prauth-missing)
mkdir -p "$scratch/.claude/local"
# state.md has /goal session populated with non-empty nonce (forge-goal active)
# but NO PR authorization line.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized

EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "2" "gh pr create BLOCKED when no ## PR authorization line (exit 2)"
assert_contains "$scratch/.out" "PR creation authorized" "hook output mentions the missing authorization"

# ---------------------------------------------------------------------------
# Test L2-2: /goal session active + ## PR authorization with matching nonce + HEAD → allowed (exit 0)
# ---------------------------------------------------------------------------
start_test "check-workflow-gates allows gh pr create when ## PR authorization matches nonce + HEAD"

scratch=$(scratch_dir wgates-prauth-match)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    HEAD_SHA=$(git rev-parse HEAD)

    cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [x] PR authorized

## PR authorization

- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\` — head=\`$HEAD_SHA\`
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "gh pr create ALLOWED when nonce + HEAD match (exit 0)"

# ---------------------------------------------------------------------------
# Test L2-3: /goal session active + ## PR authorization with stale HEAD → blocked (exit 2)
# ---------------------------------------------------------------------------
start_test "check-workflow-gates blocks gh pr create when ## PR authorization head mismatched"

scratch=$(scratch_dir wgates-prauth-stalehead)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    echo y > a; git add a; git commit -qm second  # advance HEAD past authorization point

    cat > .claude/local/state.md <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] PR authorized

## PR authorization

- [x] PR creation authorized — `2026-05-16T10:15:00Z` — nonce=`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` — head=`abc123def_stale_head`
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "2" "gh pr create BLOCKED when authorization head doesn't match current HEAD (exit 2)"
assert_contains "$scratch/.out" "PR creation authorized" "hook output references the stale authorization"

# ---------------------------------------------------------------------------
# Test L2-4: NO /goal session (no non-empty nonce) → guard is a no-op (existing checklist guard runs)
# ---------------------------------------------------------------------------
start_test "check-workflow-gates skips PR-auth guard when no non-empty nonce in /goal session (legacy workflow path)"

scratch=$(scratch_dir wgates-prauth-noforgegoal)
mkdir -p "$scratch/.claude/local"
# state.md WITHOUT ## /goal session — the existing checklist guard runs unchanged.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — Ship          |
| Next step | gh pr create      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "PR-auth guard skipped when no /forge-goal session active"

# ---------------------------------------------------------------------------
# Test L2-5 (P1.2 fix): empty /goal session nonce row → treated as INACTIVE
# ---------------------------------------------------------------------------
start_test "check-workflow-gates treats /goal session with empty nonce row as INACTIVE (no block)"

scratch=$(scratch_dir wgates-prauth-emptynonce)
mkdir -p "$scratch/.claude/local"
# state.md has ## /goal session heading but nonce row has no value — should be INACTIVE.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            |       |
| workflow_command |       |
| issued_at        |       |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — Ship          |
| Next step | gh pr create      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "PR-auth guard INACTIVE when /goal session nonce is empty (exit 0)"

# ---------------------------------------------------------------------------
# Test L2-6 (P1.4 fix): stale-duplicate auth lines → guard uses LAST one
# ---------------------------------------------------------------------------
start_test "check-workflow-gates uses LAST PR authorization line when multiple present (stale-duplicate defense)"

scratch=$(scratch_dir wgates-prauth-duplicate)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    HEAD_SHA=$(git rev-parse HEAD)

    cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — \`2026-05-16T09:00:00Z\` — nonce=\`stale-nonce-old-session\` — head=\`staleshastale\`
- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\` — head=\`$HEAD_SHA\`

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "guard uses LAST auth line (matching nonce+HEAD) and ALLOWS when last line is valid"

# ---------------------------------------------------------------------------
# Test L2-7 (P2 fix): nonce mismatch in auth line → guard blocks (exit 2)
# ---------------------------------------------------------------------------
start_test "check-workflow-gates blocks gh pr create when ## PR authorization nonce mismatches /goal session nonce (stale-session defense)"

scratch=$(scratch_dir wgates-prauth-noncemis)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    HEAD_SHA=$(git rev-parse HEAD)

    cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | session-A-uuid |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)

## PR authorization

- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`session-B-different\` — head=\`$HEAD_SHA\`
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "2" "gh pr create BLOCKED when auth-line nonce doesn't match /goal session nonce (exit 2)"
assert_contains "$scratch/.out" "nonce" "hook output mentions nonce mismatch"

# ===========================================================================
# Layer 2 — Task 8: stuck-detection soft warning
# After 5 consecutive Stop calls with an identical progress_fingerprint,
# check-state-updated.sh must emit FORGE_GOAL_STUCK_WARNING to STDERR.
# Turns 1-4 must NOT emit the warning; turn 5 must.
# ===========================================================================
start_test "Layer 2 — check-state-updated emits FORGE_GOAL_STUCK_WARNING after 5 identical fingerprints"

(
    scratch=$(scratch_dir checkstate-stuck)
    mkdir -p "$scratch/.claude/local" "$scratch/.claude/hooks"
    cp "$REPO_ROOT/hooks/build-evidence.sh" "$scratch/.claude/hooks/build-evidence.sh"
    chmod +x "$scratch/.claude/hooks/build-evidence.sh"

    # state.md with /forge-goal active (non-empty nonce)
    cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | test-nonce-stuck-detection |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Write code        |

### Checklist

- [ ] Item 1
- [ ] Item 2
EOF

    # v5.32: fire BOTH Stop hooks per turn — build-evidence first (writes
    # fingerprint side-channel), then check-state-updated (reads it for
    # stuck-detection). This mirrors the real Stop hook ordering in
    # settings.template.json after the split.
    # stop_hook_active=true keeps the CHANGELOG gate quiet (scratch dir has
    # no git repo). Same state.md every turn → same progress_fingerprint →
    # stuck counter increments.
    INPUT='{"stop_hook_active":true,"transcript_path":"/tmp/x"}'

    (
        cd "$scratch"
        for i in 1 2 3 4 5; do
            echo "$INPUT" | bash "$REPO_ROOT/hooks/build-evidence.sh" > /dev/null 2>&1
            echo "$INPUT" | bash "$REPO_ROOT/hooks/check-state-updated.sh" > "$scratch/.out.$i" 2>&1
        done
    )

    # Turns 1-4 must NOT have the warning; turn 5 MUST.
    assert_not_contains "$scratch/.out.1" "FORGE_GOAL_STUCK_WARNING" "no warning on turn 1"
    assert_not_contains "$scratch/.out.2" "FORGE_GOAL_STUCK_WARNING" "no warning on turn 2"
    assert_not_contains "$scratch/.out.3" "FORGE_GOAL_STUCK_WARNING" "no warning on turn 3"
    assert_not_contains "$scratch/.out.4" "FORGE_GOAL_STUCK_WARNING" "no warning on turn 4"
    assert_contains     "$scratch/.out.5" "FORGE_GOAL_STUCK_WARNING" "warning fires on turn 5 (identical fingerprint)"
)

# ===========================================================================
# v5.32 Test A — Worktree CWD fix: build-evidence MUST read state.md from
# the cwd in the stdin JSON, not from its own CWD.
#
# Surfaced 2026-05-18 in msai-v2 portfolio-backtest soak: evidence reported
# session_nonce:null and phase:null even though the worktree's state.md was
# populated. Root cause: CC's Stop hook runs with CWD=$CLAUDE_PROJECT_DIR
# (the parent project in worktree sessions). build-evidence read state.md
# relative to that CWD → wrong (or missing) state.md.
#
# Test strategy: create TWO scratch dirs. "Main" has empty/no state.md.
# "Worktree" has a state.md with a recognizable nonce. Invoke build-evidence
# WITH CWD=main but stdin.cwd=worktree → assert evidence contains the
# worktree's nonce.
# ===========================================================================
start_test "v5.32 — build-evidence reads state.md from stdin.cwd, not its own CWD"

V32A_MAIN=$(scratch_dir v532-main-repo)
V32A_WORKTREE=$(scratch_dir v532-worktree)
mkdir -p "$V32A_MAIN/.claude/local" "$V32A_WORKTREE/.claude/local"

# Main repo has NO /goal session.
cat > "$V32A_MAIN/.claude/local/state.md" <<'EOF'
## Workflow

| Field   | Value |
| ------- | ----- |
| Command | none  |
EOF

# Worktree has an ACTIVE /goal session with a recognizable nonce.
cat > "$V32A_WORKTREE/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | v532-worktree-nonce-marker |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-18T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Write code        |

### Checklist

- [ ] Item 1
EOF

# Init both as git repos (build-evidence runs git commands too).
( cd "$V32A_MAIN" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
( cd "$V32A_WORKTREE" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# Invoke build-evidence from CWD=main, stdin.cwd=worktree. Assert evidence
# carries the WORKTREE's nonce (proves cwd-redirect happened).
OUT_V32A="$V32A_MAIN/.out"
INPUT_V32A=$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$V32A_WORKTREE")
( cd "$V32A_MAIN" && echo "$INPUT_V32A" | bash "$REPO_ROOT/hooks/build-evidence.sh" > "$OUT_V32A.stdout" 2> "$OUT_V32A.stderr" )

assert_contains "$OUT_V32A.stderr" "v532-worktree-nonce-marker" \
    "build-evidence read state.md from stdin.cwd (worktree), not its own CWD (main)"

# Negative control: same setup but no `cwd` in stdin → build-evidence reads
# state.md from its own CWD (main repo) and the nonce should be null.
OUT_V32A_FALLBACK="$V32A_MAIN/.out-fallback"
INPUT_V32A_NOCWD='{"stop_hook_active":false}'
( cd "$V32A_MAIN" && echo "$INPUT_V32A_NOCWD" | bash "$REPO_ROOT/hooks/build-evidence.sh" > "$OUT_V32A_FALLBACK.stdout" 2> "$OUT_V32A_FALLBACK.stderr" )
if grep -q "v532-worktree-nonce-marker" "$OUT_V32A_FALLBACK.stderr"; then
    fail "negative control failed: evidence picked up worktree nonce without stdin.cwd (should have read main repo's state.md)"
else
    pass "negative control: without stdin.cwd, evidence reads CWD's state.md (no worktree nonce leak)"
fi

# ===========================================================================
# v5.32 Test B — Worktree CWD fix: check-state-updated stuck-detection MUST
# also honor stdin.cwd so it reads the worktree's nonce + fingerprint file.
# ===========================================================================
start_test "v5.32 — check-state-updated stuck-detection honors stdin.cwd"

V32B_MAIN=$(scratch_dir v532-main-repo-b)
V32B_WORKTREE=$(scratch_dir v532-worktree-b)
mkdir -p "$V32B_MAIN/.claude/local" "$V32B_WORKTREE/.claude/local"

# Main has no /goal session.
cat > "$V32B_MAIN/.claude/local/state.md" <<'EOF'
## Workflow
| Field   | Value |
| ------- | ----- |
| Command | none  |
EOF

# Worktree has active session.
cat > "$V32B_WORKTREE/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | v532b-worktree-nonce |
| workflow_command | /new-feature bar |
| issued_at        | 2026-05-18T10:00:00Z |

## Workflow

| Field     | Value           |
| --------- | --------------- |
| Command   | /new-feature bar |
| Phase     | 4 — Execute     |
| Next step | Code            |

### Checklist
- [ ] X
EOF

( cd "$V32B_MAIN" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
( cd "$V32B_WORKTREE" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

INPUT_V32B=$(printf '{"stop_hook_active":true,"cwd":"%s"}' "$V32B_WORKTREE")

# Fire 5 cycles: build-evidence + check-state-updated, both from CWD=main
# with stdin.cwd=worktree. Stuck-detection should accumulate inside the
# WORKTREE's .claude/local (not the main repo's).
for i in 1 2 3 4 5; do
    ( cd "$V32B_MAIN" && echo "$INPUT_V32B" | bash "$REPO_ROOT/hooks/build-evidence.sh" > /dev/null 2>&1 )
    ( cd "$V32B_MAIN" && echo "$INPUT_V32B" | bash "$REPO_ROOT/hooks/check-state-updated.sh" > "$V32B_MAIN/.out.$i" 2>&1 )
done

# Counter file MUST exist inside the worktree, NOT inside main.
assert_file_exists "$V32B_WORKTREE/.claude/local/forge-goal-stuck-count" \
    "stuck-counter file written to worktree (stdin.cwd target)"
assert_file_missing "$V32B_MAIN/.claude/local/forge-goal-stuck-count" \
    "stuck-counter file NOT written to main repo (proves cwd-redirect)"
assert_contains "$V32B_MAIN/.out.5" "FORGE_GOAL_STUCK_WARNING" \
    "stuck-warning fires on turn 5 even with stdin.cwd redirect"

# ===========================================================================
# v5.32 Test C (Codex P2-1 regression guard) — subdirectory cwd MUST be
# normalized to the repo/worktree root.
#
# Scenario: CC session was launched from a subdirectory like `apps/web` or
# `frontend/`. Stop hook stdin.cwd points there. If build-evidence just
# cd's into that subdirectory, then relative reads of `.claude/local/state.md`
# silently miss (the file lives at repo root). Fix: normalize via
# `git -C "$cwd" rev-parse --show-toplevel` before cd.
# ===========================================================================
start_test "v5.32 — subdirectory stdin.cwd normalizes to repo root (P2-1)"

V32C=$(scratch_dir v532-subdir-cwd)
mkdir -p "$V32C/.claude/local" "$V32C/apps/web/src"

cat > "$V32C/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | v532c-subdir-marker |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-18T10:00:00Z |

## Workflow

| Field     | Value           |
| --------- | --------------- |
| Command   | /new-feature foo |
| Phase     | 4 — Execute     |
| Next step | Code            |

### Checklist
- [ ] X
EOF

( cd "$V32C" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# Invoke build-evidence with stdin.cwd pointing at the SUBDIRECTORY apps/web/src.
# The hook must walk up via `git rev-parse --show-toplevel` to the repo root
# before reading state.md.
OUT_V32C="$V32C/.out"
SUBDIR="$V32C/apps/web/src"
INPUT_V32C=$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$SUBDIR")
echo "$INPUT_V32C" | bash "$REPO_ROOT/hooks/build-evidence.sh" > "$OUT_V32C.stdout" 2> "$OUT_V32C.stderr"

assert_contains "$OUT_V32C.stderr" "v532c-subdir-marker" \
    "build-evidence normalized subdirectory cwd to repo root and read state.md"

# ===========================================================================
# v5.39 — Plan review + Code review per-iter clean evidence gate
# Tests 16-24. Closes the same-iteration-clean shortcut surfaced by the
# msai-v2 v5.38 /goal run (iter-6 P1 pending, agent ticked Plan review PASS).
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 16: [x] Plan review loop PASS without per-iter clean evidence → exit 2
# ---------------------------------------------------------------------------
start_test "[x] Plan review loop PASS + no per-iter evidence → exit 2"

S16=$(scratch_dir wgate-plan-noev)
mkdir -p "$S16/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/plan-review-pass-no-evidence.md" \
   "$S16/.claude/local/state.md"
cd "$S16"
git init -q .
git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S16/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "2" "Plan review PASS without evidence is blocked"
assert_contains "$S16/.hook-stderr" "Plan review iteration" \
    "stderr mentions Plan review iteration"
assert_contains "$S16/.hook-stderr" "codex clean" \
    "stderr names the required clean-line tool"

# ---------------------------------------------------------------------------
# Test 17: [x] Plan review loop PASS + valid evidence + matching plan_sha → exit 0
# ---------------------------------------------------------------------------
start_test "[x] Plan review loop PASS + valid plan_sha → exit 0"

S17=$(scratch_dir wgate-plan-ok)
mkdir -p "$S17/.claude/local" "$S17/docs/plans"
echo "# Fake plan" > "$S17/docs/plans/fake-plan.md"

# Compute the real plan_sha and head_sha (init repo + first commit).
cd "$S17"
git init -q . && git add -A && git -c user.email=test@test -c user.name=test commit -q -m init
HEAD_SHA=$(git rev-parse HEAD)
PLAN_SHA=$(shasum -a 256 docs/plans/fake-plan.md 2>/dev/null | awk '{print $1}')
[ -z "$PLAN_SHA" ] && PLAN_SHA=$(sha256sum docs/plans/fake-plan.md | awk '{print $1}')

# Materialize fixture with placeholders replaced.
sed "s/__FAKE_PLAN_SHA__/$PLAN_SHA/g; s/__FAKE_HEAD_SHA__/$HEAD_SHA/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/plan-review-pass-evidence-ok.md" \
    > .claude/local/state.md

echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S17/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "0" "Plan review PASS with valid evidence is allowed"

# ---------------------------------------------------------------------------
# Test 18: [x] Plan review loop PASS + WRONG plan_sha → exit 2
# ---------------------------------------------------------------------------
start_test "[x] Plan review loop PASS + stale plan_sha → exit 2"

S18=$(scratch_dir wgate-plan-stale)
mkdir -p "$S18/.claude/local" "$S18/docs/plans"
echo "# Fake plan" > "$S18/docs/plans/fake-plan.md"
cd "$S18"
git init -q . && git add -A && git -c user.email=test@test -c user.name=test commit -q -m init
cp "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/plan-review-pass-wrong-sha.md" \
   .claude/local/state.md
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S18/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "2" "Plan review PASS with stale plan_sha is blocked"
assert_contains "$S18/.hook-stderr" "plan_sha" \
    "stderr mentions plan_sha mismatch"

# ---------------------------------------------------------------------------
# Test 19: [x] Code review loop PASS without per-iter clean lines → exit 2
# ---------------------------------------------------------------------------
start_test "[x] Code review loop PASS + no per-iter evidence → exit 2"

S19=$(scratch_dir wgate-code-noev)
mkdir -p "$S19/.claude/local"
cd "$S19"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
cp "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/code-review-pass-no-evidence.md" \
   .claude/local/state.md
echo '{"tool_input":{"command":"git push origin HEAD"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S19/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "2" "Code review PASS without evidence is blocked"
assert_contains "$S19/.hook-stderr" "Code review iteration" \
    "stderr names Code review iteration requirement"

# ---------------------------------------------------------------------------
# Test 20: [x] Code review loop PASS + matching codex+pr-toolkit at HEAD → exit 0
# ---------------------------------------------------------------------------
start_test "[x] Code review loop PASS + matching HEAD evidence → exit 0"

S20=$(scratch_dir wgate-code-ok)
mkdir -p "$S20/.claude/local"
cd "$S20"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
HEAD_SHA=$(git rev-parse HEAD)
sed "s/__FAKE_HEAD_SHA__/$HEAD_SHA/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/code-review-pass-evidence-ok.md" \
    > .claude/local/state.md
echo '{"tool_input":{"command":"gh pr create --title test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S20/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "0" "Code review PASS with valid HEAD evidence is allowed"

# ---------------------------------------------------------------------------
# Test 21: [x] Code review loop PASS + STALE HEAD evidence → exit 2
# ---------------------------------------------------------------------------
start_test "[x] Code review loop PASS + stale HEAD evidence → exit 2"

S21=$(scratch_dir wgate-code-stale)
mkdir -p "$S21/.claude/local"
cd "$S21"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
# Add a second commit so HEAD differs from the fixture's literal stale sha
git -c user.email=test@test -c user.name=test commit --allow-empty -m second -q
cp "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/code-review-pass-wrong-head.md" \
   .claude/local/state.md
echo '{"tool_input":{"command":"git commit -m next"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S21/.hook-stderr"
rc=$?
cd "$REPO_ROOT"

assert_equals "$rc" "2" "Code review PASS with stale HEAD is blocked"
assert_contains "$S21/.hook-stderr" "head" "stderr mentions head mismatch"

# ---------------------------------------------------------------------------
# Test 22 (v5.40): N/A escape on Plan review loop → exit 0 (no evidence needed).
# Codex is mandatory — the only escape is an N/A justification on the loop line.
# ---------------------------------------------------------------------------
start_test "[x] Plan review loop — N/A: reason → exit 0 (N/A bypasses evidence)"

S22=$(scratch_dir wgate-plan-na)
mkdir -p "$S22/.claude/local"
cd "$S22"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
HEAD22=$(git rev-parse HEAD)
# Plan review loop marked N/A — no per-iter clean line, no plan file needed.
# (Code review loop still carries real per-iter evidence — only plan is N/A.)
cat > .claude/local/state.md <<EOF
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop — N/A: simple 1-file fix, no plan
- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`$HEAD22\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`$HEAD22\`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S22/.hook-stderr"
rc=$?
cd "$REPO_ROOT"
assert_equals "$rc" "0" "Plan review loop N/A skips per-iter evidence check"

# ---------------------------------------------------------------------------
# Test 23 (v5.40): N/A escape on Code review loop → exit 0 (no evidence needed).
# ---------------------------------------------------------------------------
start_test "[x] Code review loop — N/A: reason → exit 0 (N/A bypasses evidence)"

S23=$(scratch_dir wgate-code-na)
mkdir -p "$S23/.claude/local"
cd "$S23"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
cat > .claude/local/state.md <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop — N/A: docs-only change
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S23/.hook-stderr"
rc=$?
cd "$REPO_ROOT"
assert_equals "$rc" "0" "Code review loop N/A skips per-iter evidence check"

# ---------------------------------------------------------------------------
# Test 23b (FIX 5): malformed plan clean line — plan= present but NO plan_sha=
# → exit 2 with "malformed" (presence check fires before sed extraction).
# ---------------------------------------------------------------------------
start_test "[x] Plan review iteration with plan= but no plan_sha= → exit 2 (malformed)"

S23B=$(scratch_dir wgate-plan-malformed)
mkdir -p "$S23B/.claude/local" "$S23B/docs/plans"
echo "# Fake plan" > "$S23B/docs/plans/fake-plan.md"
cd "$S23B"
git init -q . && git add -A && git -c user.email=test@test -c user.name=test commit -q -m init
cat > .claude/local/state.md <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (2 iterations) — PASS
- [x] Plan review iteration 2 — codex clean — plan=`docs/plans/fake-plan.md` — ts=`2026-05-26T17:00:00Z`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S23B/.hook-stderr"
rc=$?
cd "$REPO_ROOT"
assert_equals "$rc" "2" "plan clean line missing plan_sha= is blocked"
assert_contains "$S23B/.hook-stderr" "malformed" "stderr names the malformed line"

# ---------------------------------------------------------------------------
# Test 23c (FIX 6): plan file referenced by clean line is DELETED → exit 2
# "missing file".
# ---------------------------------------------------------------------------
start_test "[x] Plan review iteration references deleted plan file → exit 2 (missing file)"

S23C=$(scratch_dir wgate-plan-deleted)
mkdir -p "$S23C/.claude/local"
cd "$S23C"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
# Reference a plan file that does NOT exist on disk.
cat > .claude/local/state.md <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (1 iterations) — PASS
- [x] Plan review iteration 1 — codex clean — plan=`docs/plans/ghost.md` — plan_sha=`deadbeef` — ts=`2026-05-26T17:00:00Z`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S23C/.hook-stderr"
rc=$?
cd "$REPO_ROOT"
assert_equals "$rc" "2" "deleted plan file is blocked"
assert_contains "$S23C/.hook-stderr" "missing file" "stderr names the missing file"

# ---------------------------------------------------------------------------
# Test 23d (FIX 6): no git repo → code-review gate skipped (degraded env), but
# the OTHER gates still apply. Here the checklist gates are all checked and
# the Plan review loop is N/A, so the hook should exit 0 even with a
# Code review loop PASS line whose evidence can't be HEAD-validated.
# ---------------------------------------------------------------------------
start_test "no git repo → code-review evidence skipped (degraded env), other gates still apply"

S23D=$(scratch_dir wgate-nogit)
mkdir -p "$S23D/.claude/local"
# Deliberately NO `git init` — degraded environment.
cat > "$S23D/.claude/local/state.md" <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | (cd "$S23D" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") 2>"$S23D/.hook-stderr"
rc=$?
assert_equals "$rc" "0" "no git repo → code-review evidence check skipped, checklist gates still pass"

# Negative companion: in the same degraded env, an UNCHECKED required gate must
# still BLOCK — proves the checklist gate is independent of git availability.
start_test "no git repo → unchecked required gate still blocks (exit 2)"

S23E=$(scratch_dir wgate-nogit-unchecked)
mkdir -p "$S23E/.claude/local"
cat > "$S23E/.claude/local/state.md" <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [ ] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | (cd "$S23E" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") 2>"$S23E/.hook-stderr"
rc=$?
assert_equals "$rc" "2" "no git repo → unchecked Code review loop still blocks"

# ---------------------------------------------------------------------------
# Test 23f (FIX 2): CRLF state.md with an UNCHECKED required gate → hook still
# BLOCKS (exit 2). Pre-fix: a CRLF state.md left a trailing \r so the
# `^## Workflow$` anchor never matched → empty WORKFLOW_BLOCK → hook bailed
# exit 0 → ALL gates silently bypassed.
# ---------------------------------------------------------------------------
start_test "CRLF state.md with unchecked gate → hook still BLOCKS (exit 2)"

S23F=$(scratch_dir wgate-crlf)
mkdir -p "$S23F/.claude/local"
# Build an LF state.md then convert to CRLF.
cat > "$S23F/.state-lf.md" <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [ ] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
sed 's/$/\r/' "$S23F/.state-lf.md" > "$S23F/.claude/local/state.md"
echo '{"tool_input":{"command":"git commit -m test"}}' \
    | (cd "$S23F" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") 2>"$S23F/.hook-stderr"
rc=$?
assert_equals "$rc" "2" "CRLF state.md does NOT silently bypass gates (exit 2)"
assert_contains "$S23F/.hook-stderr" "Code review loop" "stderr names the unchecked gate despite CRLF"

# ---------------------------------------------------------------------------
# Test 23g (FIX 3): compound ship command (git commit && git push) with
# incomplete gates → exit 2 (blocked). And a plain `git commit -m x` with the
# same incomplete gates also blocks via the normal gate (regression: plain
# single commands still work as before).
# ---------------------------------------------------------------------------
start_test "compound ship command (commit && push) → exit 2 (blocked)"

S23G=$(scratch_dir wgate-compound)
mkdir -p "$S23G/.claude/local"
cat > "$S23G/.claude/local/state.md" <<'EOF'
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [ ] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
printf '{"tool_input":{"command":"git commit -m x && git push"}}' \
    | (cd "$S23G" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") 2>"$S23G/.hook-stderr"
rc=$?
assert_equals "$rc" "2" "compound commit && push is blocked"
assert_contains "$S23G/.hook-stderr" "compound ship command" \
    "stderr names the compound-command rule"

start_test "plain 'git commit -m x' still works (single command, gates checked → exit 0)"

S23H=$(scratch_dir wgate-plain)
mkdir -p "$S23H/.claude/local"
cd "$S23H"
git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
HEAD23H=$(git rev-parse HEAD)
cat > .claude/local/state.md <<EOF
## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`$HEAD23H\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`$HEAD23H\`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
EOF
echo '{"tool_input":{"command":"git commit -m x"}}' \
    | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>"$S23H/.hook-stderr"
rc=$?
cd "$REPO_ROOT"
assert_equals "$rc" "0" "plain single git commit with gates satisfied → exit 0 (not flagged as compound)"

# ---------------------------------------------------------------------------
# Test 24: PowerShell parity for the 6 workflow-gate-evidence fixtures.
# Runs each fixture through run_hook_ps and asserts the exit code matches
# the .sh expectation. Skipped if pwsh not installed.
# (v5.40: the codex-unavailable-* fixtures were dropped — Codex is mandatory.)
# ---------------------------------------------------------------------------
start_test "PowerShell parity for evidence-gate fixtures (Tests 16-21)"

if ! command -v pwsh >/dev/null 2>&1; then
    pass "skipped (pwsh not installed)"
else
    for fixture in plan-review-pass-no-evidence plan-review-pass-evidence-ok \
                   plan-review-pass-wrong-sha code-review-pass-no-evidence \
                   code-review-pass-evidence-ok code-review-pass-wrong-head; do
        SP=$(scratch_dir wgate-ps-$fixture)
        mkdir -p "$SP/.claude/local" "$SP/docs/plans"
        echo "# Fake plan" > "$SP/docs/plans/fake-plan.md"
        cd "$SP"
        git init -q . && git -c user.email=test@test -c user.name=test commit -q --allow-empty -m init
        if command -v shasum >/dev/null 2>&1; then
            PSHA=$(shasum -a 256 docs/plans/fake-plan.md | awk '{print $1}')
        else
            PSHA=$(sha256sum docs/plans/fake-plan.md | awk '{print $1}')
        fi
        HSHA=$(git rev-parse HEAD)
        sed "s/__FAKE_PLAN_SHA__/$PSHA/g; s/__FAKE_HEAD_SHA__/$HSHA/g" \
            "$REPO_ROOT/tests/template/fixtures/state-md-workflow-gate-evidence/${fixture}.md" \
            > .claude/local/state.md
        # Extract the checklist body for run_hook_ps. Use awk that handles EOF
        # correctly (fixtures may end at EOF without a trailing `## State`).
        checklist=$(awk '/^### Checklist/{p=1; next} /^## /{p=0} p' .claude/local/state.md)
        rc_ps=$(run_hook_ps "$SP" 'git commit -m x' "$checklist")
        # Mirror expected exit codes from the .sh tests
        case "$fixture" in
            *-evidence-ok) expected=0 ;;
            *) expected=2 ;;
        esac
        assert_equals "$rc_ps" "$expected" ".ps1 parity for $fixture (expected $expected)"
        cd "$REPO_ROOT"
    done
fi

# ===========================================================================
# Report
# ===========================================================================
report "test-hooks.sh"
