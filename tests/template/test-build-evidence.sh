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

start_test "build-evidence emits plan_review_gate.clean_same_iteration=true on clean plan-review evidence"

scratch=$(scratch_dir bevidence-plan)
mkdir -p "$scratch/.claude/local" "$scratch/docs/plans"
echo "# Fake plan content" > "$scratch/docs/plans/x.md"
PLAN_SHA=$( (cd "$scratch" && shasum -a 256 docs/plans/x.md 2>/dev/null || sha256sum docs/plans/x.md) | awk '{print $1}')

sed "s/__PLAN_SHA__/$PLAN_SHA/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/plan-review-clean-iter-3.md" \
    > "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"plan_review_gate":{"clean_same_iteration":true' \
    "plan_review_gate.clean_same_iteration is true when evidence is fresh"
assert_contains "$OUT" '"matched_iteration":"3"' \
    "matched_iteration is the loop PASS count"

start_test "build-evidence: plan-review N/A line does NOT set plan_review_gate.clean_same_iteration=true"

# Codex is mandatory: an N/A escape on the plan-review loop must NOT propagate a
# clean gate (mirrors e2e_report). Only real `codex clean` + matching plan_sha
# sets clean=true. This prevents /goal from self-completing without Codex evidence.
scratch=$(scratch_dir bevidence-plan-na)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/plan-review-na.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"plan_review_gate":{"clean_same_iteration":false' \
    "plan_review_gate stays false on an N/A escape (no real Codex evidence)"

# ===========================================================================
# Task 6: scoped-review-certification — reviewer_gate helper-backed validation
# + breaker fields (post_cert_rounds / breaker) + breaker→pr_ready wiring.
#
# These build REAL scratch git repos (pattern: test-review-scope.sh Level 2)
# with the helpers installed under .claude/hooks/lib/ — the dual-path the hook
# resolves RS from. build-evidence must apply the SAME helper-backed validation
# as the ship gate, so /goal readiness is never a weaker parser.
# ===========================================================================

# bev_scope_repo: scratch repo with main + feat branch (mirrors build_repo in
# test-review-scope.sh). Sets R. .claude/ MUST be gitignored so add -A on both
# branches never tracks the helper/state and clobbers it on checkout.
bev_scope_repo() {
    R="$(scratch_dir bev-scope)"
    git -C "$R" init -q -b main
    git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
    mkdir -p "$R/src" "$R/docs"
    echo ".claude/" > "$R/.gitignore"
    echo "base" > "$R/src/app.py"; echo "# doc" > "$R/docs/CHANGELOG.md"
    git -C "$R" add -A; git -C "$R" commit -qm base
    git -C "$R" checkout -qb feat
    echo "feature" >> "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm feat1
}

# bev_install_helpers <repo>: copy the scope helper + default-branch sibling into
# the scratch repo's .claude/hooks/lib/ (the dual-path resolution path). Without
# this, every case silently exercises the fail-open path.
bev_install_helpers() {
    local r="$1"
    mkdir -p "$r/.claude/hooks/lib"
    cp "$REPO_ROOT/hooks/lib/review-scope.sh" "$r/.claude/hooks/lib/"
    cp "$REPO_ROOT/hooks/lib/default-branch.sh" "$r/.claude/hooks/lib/"
}

# bev_state <repo> <checklist-body>: write an active ## Workflow state.md whose
# ### Checklist is the supplied body.
bev_state() {
    local r="$1" body="$2"
    mkdir -p "$r/.claude/local"
    { echo "## Workflow"; echo
      echo "| Field | Value |"
      echo "| Command | /new-feature x |"
      echo
      echo "### Checklist"; echo
      printf '%s\n' "$body"
    } > "$r/.claude/local/state.md"
}

# bev_run <repo>: run build-evidence.sh inside the repo, capture JSON to GATE_OUT.
# (gh absent → pr_state.exists=false, which is fine for clean_same_iteration /
# breaker / post_cert_rounds assertions.)
bev_run() {
    GATE_OUT="$1/.bev.out"
    ( cd "$1" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$GATE_OUT" 2>&1
}

# bev_run_fullgreen <repo>: run build-evidence with a gh stub returning an OPEN
# PR at the current HEAD + a fresh E2E report. Used by the breaker cases that
# must show pr_ready=false WITH all other gates satisfied. Caller must have
# placed a valid PR-authorization line at HEAD in state.md already.
bev_run_fullgreen() {
    local r="$1"
    mkdir -p "$r/bin"
    local head; head="$(git -C "$r" rev-parse HEAD)"
    cat > "$r/bin/gh" <<STUB
#!/usr/bin/env bash
if [ "\$1" != "pr" ] || [ "\$2" != "view" ]; then echo "{}"; exit 0; fi
echo "{\"number\":42,\"url\":\"https://x/pr/42\",\"state\":\"OPEN\",\"headRefOid\":\"${head}\",\"baseRefName\":\"main\",\"headRefName\":\"feat\"}"
STUB
    chmod +x "$r/bin/gh"
    # Fresh E2E report (mtime later than branch-off).
    mkdir -p "$r/tests/e2e/reports"
    local boff_ts future
    boff_ts="$(git -C "$r" log -1 --format=%ct "$(git -C "$r" merge-base main HEAD)")"
    future=$(( boff_ts + 120 ))
    echo "report" > "$r/tests/e2e/reports/r.md"
    if touch -t "$(date -d "@$future" +%Y%m%d%H%M.%S 2>/dev/null)" "$r/tests/e2e/reports/r.md" 2>/dev/null; then :
    elif touch -t "$(date -r "$future" +%Y%m%d%H%M.%S 2>/dev/null)" "$r/tests/e2e/reports/r.md" 2>/dev/null; then :
    else sleep 2 && touch "$r/tests/e2e/reports/r.md"; fi
    GATE_OUT="$r/.bev.out"
    ( cd "$r" && PATH="$r/bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$GATE_OUT" 2>&1
}

# --- Positive 1: valid mechanical re-stamp (docs-only) after certification → clean
start_test "bev scoped: valid mechanical chain after certification → clean_same_iteration true"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "note" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":true' "docs-only mechanical chain → clean"

# --- Positive 2: scoped delta pair, valid chain → clean
start_test "bev scoped: valid delta pair chain → clean_same_iteration true"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":true' "valid delta chain → clean"

# --- Positive 3: a deep-pass row alongside the certifying pair does not poison the gate
start_test "bev scoped: deep-pass row does not poison reviewer_gate → clean_same_iteration true"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
bev_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — codex deep-pass clean — scope=full — base=\`${B}\` — head=\`${H}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":true' "deep-pass row alongside the pair stays clean"

# --- Negative: deep-pass-only codex side (no `codex clean` row) does not satisfy the gate
start_test "bev scoped: deep-pass-only codex side → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
bev_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex deep-pass clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "deep-pass alone is not the codex loop review → not clean"

# --- Negative: delta base ≠ prior clean head → false
start_test "bev scoped: delta base ≠ prior clean head → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${B}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${B}\` — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "wrong-base delta → not clean"

# --- Negative: post-cert REBASE (amend) + delta from old clean head → false
start_test "bev scoped: post-cert amend + delta from stale head → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "rebase fail-closed → not clean"

# --- Negative (delayed poisoning): cert → amend → forged delta → later delta chained from forged head
start_test "bev scoped: delayed poisoning (forged delta then later delta chained from it) → false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"
echo "more" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm more
H3="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (3 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 3 — codex clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`
- [x] Code review iteration 3 — pr-toolkit clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "forged-chain delta → not clean"

# --- Negative: full pair base ≠ merge-base → false
start_test "bev scoped: full pair base ≠ merge-base → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${H}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${H}\` — head=\`${H}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "full base≠merge-base → not clean"

# --- Negative: mechanical over a CODE delta (recompute says delta) → false
start_test "bev scoped: mechanical over code delta → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm "code fix"
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "mechanical-over-code → not clean"

# --- Negative: scope=fullish (unknown value, valid prefix) → false
start_test "bev scoped: scope=fullish unknown value → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
bev_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=fullish — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "scope=fullish → not clean"

# --- Negative: legacy pair at a new head AFTER a scoped certification → false
start_test "bev scoped: legacy pair after scoped certification → clean_same_iteration false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — head=\`${H2}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "post-cert legacy pair → not clean"

# --- Breaker: loop counter 5, cert at 1 → breaker tripped + pr_ready false (all other gates green)
start_test "bev breaker: post-cert rounds > limit → breaker tripped AND pr_ready false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
NONCE="00000000-0000-0000-0000-000000000099"
bev_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
# Append /goal session + PR-authorization so the full-green path can satisfy auth.
{ echo; echo "## /goal session"; echo
  echo "| Field | Value |"
  echo "| nonce | ${NONCE} |"
  echo "| workflow_command | /new-feature x |"
  echo
  echo "- [x] PR creation authorized — \`2026-06-05T00:00:00Z\` — nonce=\`${NONCE}\` — head=\`${H}\`"
} >> "$R/.claude/local/state.md"
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"breaker":"tripped"' "loop 5 − cert 1 = 4 > 3 → tripped"
assert_contains "$GATE_OUT" '"post_cert_rounds":4' "post_cert_rounds = 4"
assert_contains "$GATE_OUT" '"pr_ready":false' "tripped breaker suppresses pr_ready even with all gates green"

# --- Breaker + adjudication at CURRENT head → pr_ready no longer suppressed
start_test "bev breaker: adjudication at current head unblocks pr_ready"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
NONCE="00000000-0000-0000-0000-000000000099"
bev_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-05T00:00:00Z\`"
{ echo; echo "## /goal session"; echo
  echo "| Field | Value |"
  echo "| nonce | ${NONCE} |"
  echo "| workflow_command | /new-feature x |"
  echo
  echo "- [x] PR creation authorized — \`2026-06-05T00:00:00Z\` — nonce=\`${NONCE}\` — head=\`${H}\`"
} >> "$R/.claude/local/state.md"
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"breaker":"tripped"' "breaker still reports tripped (raw count)"
assert_contains "$GATE_OUT" '"pr_ready":true' "current-head adjudication clears the breaker suppression"

# --- Breaker + adjudication at STALE head → still suppressed
start_test "bev breaker: adjudication at STALE head keeps pr_ready false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
STALE="0000000000000000000000000000000000000000"
NONCE="00000000-0000-0000-0000-000000000099"
bev_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${STALE}\` — ts=\`2026-06-05T00:00:00Z\`"
{ echo; echo "## /goal session"; echo
  echo "| Field | Value |"
  echo "| nonce | ${NONCE} |"
  echo "| workflow_command | /new-feature x |"
  echo
  echo "- [x] PR creation authorized — \`2026-06-05T00:00:00Z\` — nonce=\`${NONCE}\` — head=\`${H}\`"
} >> "$R/.claude/local/state.md"
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"pr_ready":false' "stale-head adjudication does not clear the breaker"

# --- Negative (chain poisoning): fabricated mechanical-over-code, later delta chained from it → false
start_test "bev scoped: fabricated mechanical-over-code poisons later delta chain → false"
bev_scope_repo; bev_install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm "code fix"
H2="$(git -C "$R" rev-parse HEAD)"
echo "more" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm "more code"
H3="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (3 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 3 — codex clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`
- [x] Code review iteration 3 — pr-toolkit clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":false' "poisoned mechanical breaks later delta chain"

# --- Helper absent: no installed helper, no source fallback (scratch repo has no hooks/) → fields 0/ok, legacy still computes
start_test "bev scoped: helper absent → post_cert_rounds 0 / breaker ok, legacy pair still clean"
bev_scope_repo   # NOTE: bev_install_helpers intentionally NOT called.
# Scratch repo lives in $TMPDIR, outside the forge tree: $_TOPLEVEL is the scratch
# repo, so neither .claude/hooks/lib/review-scope.sh nor the hooks/lib/ source
# fallback exists here. build-evidence must fail open: 0/"ok" fields, and a
# self-contained legacy pair at HEAD still computes clean.
H="$(git -C "$R" rev-parse HEAD)"
bev_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
bev_run "$R"
assert_contains "$GATE_OUT" '"post_cert_rounds":0' "helper absent → post_cert_rounds 0"
assert_contains "$GATE_OUT" '"breaker":"ok"' "helper absent → breaker ok (fail-open)"
assert_contains "$GATE_OUT" '"reviewer_gate":{"clean_same_iteration":true' "helper absent → legacy pair still computes clean"

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
