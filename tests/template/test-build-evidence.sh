#!/usr/bin/env bash
# tests/template/test-build-evidence.sh — runtime tests for hooks/build-evidence.sh.
#
# Parses .claude/local/state.md and emits unified evidence JSON between
# FORGE_GOAL_EVIDENCE_BEGIN/END markers. Tests verify schema, markers, and
# basic JSON structure in the skeleton phase.
#
# Run from repo root: bash tests/template/test-build-evidence.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

start_test "build-evidence.sh emits markers + valid JSON on empty state.md"

scratch=$(scratch_dir bevidence)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1
EXIT=$?

assert_equals "$EXIT" "0" "exit code is 0"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "begin marker present"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_END" "end marker present"
assert_contains "$OUT" '"type":"forge_goal_evidence"' "type field present"
assert_contains "$OUT" '"schema_version":1' "schema_version is 1"

start_test "build-evidence.sh parses ## /goal session section (Markdown table)"

scratch=$(scratch_dir bevidence-goalsession)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/with-goal-session.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"session_nonce":"00000000-0000-0000-0000-000000000001"' \
    "session_nonce extracted from table"
assert_contains "$OUT" '"workflow_command":"/new-feature foo"' \
    "workflow_command extracted from table"

start_test "build-evidence.sh emits null session_nonce when ## /goal session missing"

scratch=$(scratch_dir bevidence-noses)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"session_nonce":null' "session_nonce null when section missing"
assert_contains "$OUT" '"workflow_command":null' "workflow_command null when section missing"

start_test "build-evidence.sh parses workflow checklist counts and reviewer rows"

scratch=$(scratch_dir bevidence-workflow)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/mid-workflow.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"phase":"1 — Research"' "phase parsed from Workflow table"
assert_contains "$OUT" '"next_step":"Run research-first"' "next_step parsed from Workflow table"
assert_contains "$OUT" '"checklist_total":8' "total count = 8 (8 items in fixture)"
assert_contains "$OUT" '"checklist_done":4' "done count = 4 (first 4 checked)"
# reviewer rows in mid-workflow.md use head=`deadbeef` which won't match real git HEAD
assert_contains "$OUT" '"reviewer_gate":{"clean_same_iteration":false' \
    "reviewer gate not clean (head mismatch — deadbeef ≠ real HEAD)"

start_test "build-evidence.sh handles CRLF line endings in state.md (Codex P1.7 regression guard)"

scratch=$(scratch_dir bevidence-crlf)
mkdir -p "$scratch/.claude/local"
# Convert the fixture to CRLF line endings using sed (POSIX-portable).
sed 's/$/\r/' \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/with-goal-session.md" \
    > "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

# Without CRLF normalization, ## /goal session anchor fails and session_nonce stays null.
# With the fix, parsing succeeds even on CRLF input.
assert_contains "$OUT" '"session_nonce":"00000000-0000-0000-0000-000000000001"' \
    "session_nonce parsed despite CRLF (Codex P1.7 regression guard)"
assert_contains "$OUT" '"phase":"1 — Research"' \
    "phase parsed despite CRLF (Codex P1.7 regression guard)"

start_test "build-evidence.sh extracts git head_sha + branch"

scratch=$(scratch_dir bevidence-git)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "test@test"
    git config user.name "Test"
    echo x > a.txt
    git add a.txt
    git commit -q -m "init"
    EXPECTED_HEAD=$(git rev-parse HEAD)
    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
    echo "$EXPECTED_HEAD" > "$scratch/.expected_head"
    exit $?
)
EXIT=$?
EXPECTED_HEAD=$(cat "$scratch/.expected_head" 2>/dev/null || echo "")

assert_equals "$EXIT" "0" "exit 0 even in a fresh repo"
assert_contains "$OUT" "\"head_sha\":\"$EXPECTED_HEAD\"" "head_sha matches git"
assert_contains "$OUT" '"branch":"main"' "branch is main"

start_test "build-evidence.sh handles gh pr view absence gracefully (pr_state.exists=false)"

scratch=$(scratch_dir bevidence-nopr)
mkdir -p "$scratch/.claude/local" "$scratch/fake-bin"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"
# Create a fake gh that always exits 1 (simulates "gh not installed / no PR").
# This approach is more portable than stripping PATH (which would also remove git).
printf '#!/bin/sh\nexit 1\n' > "$scratch/fake-bin/gh"
chmod +x "$scratch/fake-bin/gh"

OUT="$scratch/.out"
(
    cd "$scratch"
    git init -q >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm "init"
    # Prepend fake-bin so the stub gh takes priority over the real one
    PATH="$scratch/fake-bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
)
EXIT=$?

assert_equals "$EXIT" "0" "exit 0 when gh is missing"
assert_contains "$OUT" '"pr_state":{"exists":false' "pr_state.exists=false when no PR/gh"

start_test "build-evidence.sh detects fresh E2E report on feature branch"

scratch=$(scratch_dir bevidence-e2e)
mkdir -p "$scratch/.claude/local" "$scratch/fake-bin"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"
# Stub gh (same pattern as the no-pr test above)
printf '#!/bin/sh\nexit 1\n' > "$scratch/fake-bin/gh"
chmod +x "$scratch/fake-bin/gh"

OUT="$scratch/.out"
BRANCH_OFF_TS_FILE="$scratch/.branch_off_ts"
(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm "init"  # this becomes branch-off
    BRANCH_OFF_TS=$(git log -1 --format=%ct HEAD)
    echo "$BRANCH_OFF_TS" > "$BRANCH_OFF_TS_FILE"

    git checkout -q -b feature
    echo y > b
    git add b
    git commit -qm "feature"

    mkdir -p tests/e2e/reports
    REPORT=tests/e2e/reports/2026-05-15-test.md
    echo "report content" > "$REPORT"
    # Force mtime to be strictly LATER than branch-off (avoids same-second flakes).
    FUTURE_TS=$(( BRANCH_OFF_TS + 60 ))
    # Try GNU date first, then BSD date, then crude sleep fallback
    if touch -t "$(date -d "@$FUTURE_TS" +%Y%m%d%H%M.%S 2>/dev/null)" "$REPORT" 2>/dev/null; then
        :  # GNU date succeeded
    elif touch -t "$(date -r "$FUTURE_TS" +%Y%m%d%H%M.%S 2>/dev/null)" "$REPORT" 2>/dev/null; then
        :  # BSD date succeeded
    else
        sleep 2 && touch "$REPORT"  # crude but reliable fallback
    fi

    PATH="$scratch/fake-bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
)
EXIT=$?

assert_equals "$EXIT" "0" "exit 0 with e2e report present"
assert_contains "$OUT" '"e2e_report":{"present":true' "e2e present"
assert_contains "$OUT" '"fresh_for_head":true' "e2e fresh for head"

start_test "build-evidence.sh accepts PR authorization when nonce + head match"

scratch=$(scratch_dir bevidence-pa-accepted)
mkdir -p "$scratch/.claude/local"

(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm init

    EXPECTED_HEAD=$(git rev-parse HEAD)
    echo "$EXPECTED_HEAD" > "$scratch/.expected_head"

    # Replace the placeholder abc123def in pr-authorized.md with the real HEAD.
    # Fixture has nonce 00000000-0000-0000-0000-000000000004 in BOTH /goal session
    # and PR authorization line — they already match.
    sed "s/abc123def/$EXPECTED_HEAD/g" \
        "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
        > .claude/local/state.md

    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out" 2>&1
)

OUT="$scratch/.out"
EXPECTED_HEAD=$(cat "$scratch/.expected_head")

assert_contains "$OUT" '"pr_authorization":{"authorized":true' "authorized=true when nonce + head match"
assert_contains "$OUT" "\"head_sha_at_authorization\":\"$EXPECTED_HEAD\"" "head matches real HEAD"

start_test "build-evidence.sh rejects PR authorization when head is stale"

scratch=$(scratch_dir bevidence-pa-stale)
mkdir -p "$scratch/.claude/local"

(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm init

    # Use pr-authorized.md as-is: PR authorization line has head=abc123def which
    # won't match the real HEAD (since we just committed an unrelated commit).
    cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
       .claude/local/state.md

    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out" 2>&1
)

OUT="$scratch/.out"

assert_contains "$OUT" '"pr_authorization":{"authorized":false' "authorized=false when head stale"

# ---------------------------------------------------------------------------
# Task 7: pr_ready, all_gates_green, progress_fingerprint
# ---------------------------------------------------------------------------

start_test "build-evidence.sh computes pr_ready=true when all conditions met"

scratch=$(scratch_dir bevidence-prready)
mkdir -p "$scratch/.claude/local" "$scratch/bin"

(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm init   # branch-off
    BRANCH_OFF_TS=$(git log -1 --format=%ct HEAD)
    git checkout -q -b feature
    echo y > b
    git add b
    git commit -qm feature

    EXPECTED_HEAD=$(git rev-parse HEAD)
    echo "$EXPECTED_HEAD" > "$scratch/.expected_head"

    mkdir -p tests/e2e/reports

    # Force E2E report mtime to be LATER than branch-off (avoid same-second flakes)
    REPORT=tests/e2e/reports/2026-05-15-test.md
    echo "report" > "$REPORT"
    FUTURE_TS=$(( BRANCH_OFF_TS + 60 ))
    # GNU/BSD date fallback chain
    if touch -t "$(date -d "@$FUTURE_TS" +%Y%m%d%H%M.%S 2>/dev/null)" "$REPORT" 2>/dev/null; then
        :  # GNU date succeeded
    elif touch -t "$(date -r "$FUTURE_TS" +%Y%m%d%H%M.%S 2>/dev/null)" "$REPORT" 2>/dev/null; then
        :  # BSD date succeeded
    else
        sleep 2 && touch "$REPORT"  # crude but reliable fallback
    fi

    # gh stub validating ALL 6 required --json fields (per Codex P2.2 from plan-review)
    cat > bin/gh <<'STUB'
#!/usr/bin/env bash
if [ "$1" != "pr" ] || [ "$2" != "view" ] || [ "$3" != "--json" ]; then
    echo "FAKE GH: unexpected args: $*" >&2
    exit 99
fi
for required in number url state headRefOid baseRefName headRefName; do
    case ",$4," in
        *,"$required",*) ;;
        *) echo "FAKE GH: missing required json field: $required (got: $4)" >&2; exit 99 ;;
    esac
done
echo "{\"number\":42,\"url\":\"https://x/pr/42\",\"state\":\"OPEN\",\"headRefOid\":\"__HEAD__\",\"baseRefName\":\"main\",\"headRefName\":\"feature\"}"
STUB
    # Substitute the real HEAD SHA into the stub output
    sed -i.bak "s/__HEAD__/$EXPECTED_HEAD/g" bin/gh && rm -f bin/gh.bak
    chmod +x bin/gh

    # Substitute __HEAD_SHA__ placeholder with real HEAD (reviewer rows + PR auth line).
    # Use all-green.md: all 8 items checked, reviewer rows [x], PR auth section present.
    sed "s/__HEAD_SHA__/$EXPECTED_HEAD/g" \
        "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/all-green.md" \
        > .claude/local/state.md

    PATH="$scratch/bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out" 2>&1
)

OUT="$scratch/.out"
assert_contains "$OUT" '"pr_ready":true' "pr_ready=true with full state"
# all-green.md has ALL 8 items checked → DONE_COUNT==TOTAL_COUNT==8 AND pr_ready=true
assert_contains "$OUT" '"all_gates_green":true' "all_gates_green=true (all items checked + pr_ready)"

start_test "build-evidence.sh computes pr_ready=false when E2E report missing"

scratch=$(scratch_dir bevidence-prnoe2e)
mkdir -p "$scratch/.claude/local"

(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm init

    cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
       .claude/local/state.md

    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out" 2>&1
)

OUT="$scratch/.out"
assert_contains "$OUT" '"pr_ready":false' "pr_ready=false when E2E missing + no PR open"
assert_contains "$OUT" '"all_gates_green":false' "all_gates_green=false when pr_ready=false"

start_test "build-evidence.sh emits stable progress_fingerprint across identical runs"

scratch=$(scratch_dir bevidence-fp)
mkdir -p "$scratch/.claude/local"

(
    cd "$scratch"
    git init -q -b main >/dev/null 2>&1
    git config user.email "t@t"
    git config user.name "t"
    echo x > a
    git add a
    git commit -qm init

    cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/mid-workflow.md" \
       .claude/local/state.md

    # Run twice on identical state
    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out1" 2>&1
    bash "$REPO_ROOT/hooks/build-evidence.sh" >"$scratch/.out2" 2>&1
)

# Assert fingerprint is 64-char SHA256 (strict pattern check)
assert_matches "$scratch/.out1" '"progress_fingerprint":"[a-f0-9]{64}"' \
    "fingerprint is 64-char SHA256 (run 1)"
assert_matches "$scratch/.out2" '"progress_fingerprint":"[a-f0-9]{64}"' \
    "fingerprint is 64-char SHA256 (run 2)"

# Extract fingerprint from each run, expect identical
FP1=$(grep -o '"progress_fingerprint":"[a-f0-9]*"' "$scratch/.out1" | head -1)
FP2=$(grep -o '"progress_fingerprint":"[a-f0-9]*"' "$scratch/.out2" | head -1)
assert_equals "$FP1" "$FP2" "fingerprint stable across identical runs"

# --- PowerShell parity smoke (only runs if pwsh is on PATH) ---
if command -v pwsh >/dev/null 2>&1; then
    start_test "build-evidence.ps1 emits markers + valid JSON (Bash-driven smoke)"

    scratch=$(scratch_dir bevidence-ps)
    mkdir -p "$scratch/.claude/local"
    cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
       "$scratch/.claude/local/state.md"

    OUT="$scratch/.out"
    ( cd "$scratch" && pwsh -NoProfile -File "$REPO_ROOT/hooks/build-evidence.ps1" ) >"$OUT" 2>&1
    EXIT=$?

    assert_equals "$EXIT" "0" "ps1 exit code is 0"
    assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "ps1 begin marker present"
    assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_END"   "ps1 end marker present"
    assert_contains "$OUT" '"type":"forge_goal_evidence"' "ps1 type field present"
else
    start_test "build-evidence.ps1 smoke (skipped — pwsh not installed)"
    pass "skipped (no pwsh)"
fi

# lib.sh's EXIT trap prints the summary; no explicit call needed.
report "build-evidence.sh" >&2
