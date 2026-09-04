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

# Older fixtures intentionally keep their historical `.claude/local` spelling.
# Promote a byte-copy to the v6 canonical path before invoking the real hook so
# receipt assertions never accidentally certify legacy evidence.
run_evidence() {
    if [ -f .claude/local/state.md ] && [ ! -f .forge/local/state.md ]; then
        mkdir -p .forge/local
        {
            printf '<!-- forge:state-schema v6 -->\n'
            cat .claude/local/state.md
        } > .forge/local/state.md
        printf '6\n' > .forge/version
    fi
    bash "$REPO_ROOT/hooks/build-evidence.sh"
}

start_test "build-evidence.sh emits markers + valid JSON on empty state.md"

scratch=$(scratch_dir bevidence)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1
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
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

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
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

assert_contains "$OUT" '"session_nonce":null' "session_nonce null when section missing"
assert_contains "$OUT" '"workflow_command":null' "workflow_command null when section missing"

start_test "legacy state remains readable but cannot certify v6 evidence"
scratch=$(scratch_dir bevidence-legacy-noncertifying)
mkdir -p "$scratch/.claude/local" "$scratch/docs/plans"
(
    cd "$scratch"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    printf 'legacy plan\n' > docs/plans/legacy.md
    git add docs/plans/legacy.md
    git commit -qm init
)
LEGACY_HEAD=$(git -C "$scratch" rev-parse HEAD)
LEGACY_PLAN_SHA=$(shasum -a 256 "$scratch/docs/plans/legacy.md" | awk '{print $1}')
cat > "$scratch/.claude/local/state.md" <<EOF
## Workflow
| Field | Value |
| Command | /new-feature legacy |
| Phase | 5 — Quality |
| Next step | ship |
### Checklist
- [x] Plan review loop (1 iterations) — PASS
- [x] Plan review iteration 1 — codex clean — plan=\`docs/plans/legacy.md\` — plan_sha=\`$LEGACY_PLAN_SHA\`
- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`$LEGACY_HEAD\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`$LEGACY_HEAD\`
## /goal session
| Field | Value |
| nonce | 11111111-1111-4111-8111-111111111111 |
| workflow_command | /new-feature legacy |
- [x] PR creation authorized — \`2026-08-27T00:00:00Z\` — nonce=\`11111111-1111-4111-8111-111111111111\` — head=\`$LEGACY_HEAD\`
EOF
(cd "$scratch" && printf '{"cwd":"%s","host":"claude"}' "$scratch" | bash "$REPO_ROOT/hooks/build-evidence.sh") > "$scratch/.out" 2>&1
assert_contains "$scratch/.out" '"phase":"5 — Quality"' "legacy structural workflow context is retained"
assert_contains "$scratch/.out" '"reviewer_gate":{"clean_same_iteration":false' "legacy Code review PASS cannot certify"
assert_contains "$scratch/.out" '"plan_review_gate":{"clean_same_iteration":false' "legacy plan review PASS cannot certify"
assert_contains "$scratch/.out" '"session_nonce":null' "legacy goal evidence is non-certifying"
assert_contains "$scratch/.out" '"pr_authorization":{"authorized":false' "legacy authorization is non-certifying"

start_test "invalid canonical v6 state makes the evidence boundary fail closed"
scratch=$(scratch_dir bevidence-invalid-v6-state)
(cd "$scratch" && git init -q -b main && git config user.email t@t && git config user.name t && git commit -qm init --allow-empty)
mkdir -p "$scratch/.forge/local" "$scratch/outside"
printf '6\n' > "$scratch/.forge/version"
printf '<!-- forge:state-schema v6 -->\n' > "$scratch/outside/state.md"
rmdir "$scratch/.forge/local"
ln -s "$scratch/outside" "$scratch/.forge/local"
(cd "$scratch" && printf '{"cwd":"%s","host":"codex"}' "$scratch" | bash "$REPO_ROOT/hooks/build-evidence.sh") > "$scratch/.out" 2>&1
assert_equals "$?" "2" "v6 state resolver rejection is preserved by build-evidence"
assert_contains "$scratch/.out" 'FORGE_STATE_INVALID' "evidence failure names the invalid canonical state"

start_test "build-evidence.sh parses workflow checklist counts and reviewer rows"

scratch=$(scratch_dir bevidence-workflow)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/mid-workflow.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

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
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

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
    run_evidence >"$OUT" 2>&1
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
    PATH="$scratch/fake-bin:$PATH" run_evidence >"$OUT" 2>&1
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

    PATH="$scratch/fake-bin:$PATH" run_evidence >"$OUT" 2>&1
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

    run_evidence >"$scratch/.out" 2>&1
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

    run_evidence >"$scratch/.out" 2>&1
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

    PATH="$scratch/bin:$PATH" run_evidence >"$scratch/.out" 2>&1
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

    run_evidence >"$scratch/.out" 2>&1
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
    run_evidence >"$scratch/.out1" 2>&1
    run_evidence >"$scratch/.out2" 2>&1
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
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

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
( cd "$scratch" && run_evidence ) >"$OUT" 2>&1

assert_contains "$OUT" '"plan_review_gate":{"clean_same_iteration":false' \
    "plan_review_gate stays false on an N/A escape (no real Codex evidence)"


# ===========================================================================
# Convergence breaker (v5.54, ADR 0009) — post_cert_rounds / breaker fields +
# the breaker→pr_ready suppression. These build REAL scratch git repos with the
# review-breaker.sh helper installed under .claude/hooks/lib/ (the dual-path the
# hook resolves RS from). build-evidence must apply the SAME helper-backed breaker
# as the ship gate, so /goal readiness is never a weaker parser.
# ===========================================================================

# bev_scope_repo: scratch repo with main + feat branch + one feature commit. Sets
# R. .claude/ MUST be gitignored so `add -A` on either branch never tracks the
# helper/state and clobbers them on checkout.
bev_scope_repo() {
    R="$(scratch_dir bev-brk)"
    git -C "$R" init -q -b main
    git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
    mkdir -p "$R/src"
    echo ".claude/" > "$R/.gitignore"
    echo "base" > "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm base
    git -C "$R" checkout -qb feat
    echo "feature" >> "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm feat1
}

# bev_install_helper <repo>: copy ONLY review-breaker.sh into the scratch repo's
# .claude/hooks/lib/ (the dual-path resolution path). The helper does not source
# default-branch.sh, so it is not copied. Without this, every case silently
# exercises the fail-open path.
bev_install_helper() {
    local r="$1"
    mkdir -p "$r/.claude/hooks/lib"
    cp "$REPO_ROOT/hooks/lib/review-breaker.sh" "$r/.claude/hooks/lib/"
}

# bev_run_fullgreen <repo>: run build-evidence with a gh stub returning an OPEN PR
# at the current HEAD + a fresh E2E report. Used by the breaker cases that must
# show pr_ready=false WITH all OTHER gates satisfied. Caller must have placed a
# legacy clean pair at HEAD (RG_CLEAN) + a /goal session + PR-authorization line at
# HEAD (PA_AUTH) in state.md already.
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
    ( cd "$r" && PATH="$r/bin:$PATH" run_evidence ) >"$GATE_OUT" 2>&1
}

# bev_breaker_state <repo> <head> <extra>: active ## Workflow whose breaker is
# tripped (loop 5, certifying legacy pair at iteration 1 at HEAD → post_cert_rounds
# = 4 > limit), with a /goal session + PR-authorization line at HEAD. The certifying
# pair at HEAD also makes the legacy reviewer_gate clean (RG_CLEAN). $3 is appended
# inside the checklist (e.g. an adjudication line).
bev_breaker_state() {
    local r="$1" h="$2" extra="$3"
    local nonce="00000000-0000-0000-0000-000000000099"
    mkdir -p "$r/.claude/local"
    { echo "## Workflow"; echo
      echo "| Field | Value |"
      echo "| Command | /new-feature x |"
      echo
      echo "### Checklist"; echo
      echo "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2"
      echo "- [x] Code review iteration 1 — codex clean — head=\`${h}\`"
      echo "- [x] Code review iteration 1 — pr-toolkit clean — head=\`${h}\`"
      [ -n "$extra" ] && printf '%s\n' "$extra"
      echo
      echo "## /goal session"; echo
      echo "| Field | Value |"
      echo "| nonce | ${nonce} |"
      echo "| workflow_command | /new-feature x |"
      echo
      echo "- [x] PR creation authorized — \`2026-06-06T00:00:00Z\` — nonce=\`${nonce}\` — head=\`${h}\`"
    } > "$r/.claude/local/state.md"
}

# --- Breaker: loop 5 / cert 1 → breaker tripped + pr_ready false (all gates green)
start_test "bev breaker: post-cert rounds > limit → breaker tripped AND pr_ready false"
bev_scope_repo; bev_install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
bev_breaker_state "$R" "$H" ""
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"breaker":"tripped"' "loop 5 − cert 1 = 4 > 3 → tripped"
assert_contains "$GATE_OUT" '"post_cert_rounds":4' "post_cert_rounds = 4"
assert_contains "$GATE_OUT" '"pr_ready":false' "tripped breaker suppresses pr_ready even with all gates green"

# --- Breaker + adjudication at CURRENT head → pr_ready no longer suppressed
start_test "bev breaker: adjudication at current head unblocks pr_ready"
bev_scope_repo; bev_install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
bev_breaker_state "$R" "$H" \
    "- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-06T00:00:00Z\`"
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"breaker":"tripped"' "breaker still reports tripped (raw count)"
assert_contains "$GATE_OUT" '"pr_ready":true' "current-head adjudication clears the breaker suppression"

# --- Breaker + adjudication at STALE head → still suppressed
start_test "bev breaker: adjudication at STALE head keeps pr_ready false"
bev_scope_repo; bev_install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
STALE="0000000000000000000000000000000000000000"
bev_breaker_state "$R" "$H" \
    "- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${STALE}\` — ts=\`2026-06-06T00:00:00Z\`"
bev_run_fullgreen "$R"
assert_contains "$GATE_OUT" '"breaker":"tripped"' "breaker reports tripped"
assert_contains "$GATE_OUT" '"pr_ready":false' "stale-head adjudication does not clear the breaker"

# --- Helper absent: no installed helper, no source fallback (scratch repo outside
#     the forge tree) → fields 0/ok, legacy reviewer_gate still computes clean.
start_test "bev breaker: helper absent → post_cert_rounds 0 / breaker ok, legacy pair still clean"
bev_scope_repo   # NOTE: bev_install_helper intentionally NOT called.
# Scratch repo lives in $TMPDIR, outside the forge tree: $TOPLEVEL is the scratch
# repo, so neither .claude/hooks/lib/review-breaker.sh nor the hooks/lib/ source
# fallback exists here. build-evidence must fail open: 0/"ok" fields, and a
# self-contained legacy pair at HEAD still computes the reviewer_gate clean.
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo
  echo "| Field | Value |"
  echo "| Command | /new-feature x |"
  echo
  echo "### Checklist"; echo
  echo "- [x] Code review loop (1 iterations) — PASS"
  echo "- [x] Code review iteration 1 — codex clean — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
} > "$R/.claude/local/state.md"
GATE_OUT="$R/.bev.out"
( cd "$R" && run_evidence ) >"$GATE_OUT" 2>&1
assert_contains "$GATE_OUT" '"post_cert_rounds":0' "helper absent → post_cert_rounds 0 (fail-open)"
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

start_test "concurrent canonical Stop evidence leaves one complete atomic fingerprint"
CS=$(scratch_dir evidence-concurrent)
mkdir -p "$CS/.forge/local"
printf '6\n' > "$CS/.forge/version"
cat > "$CS/.forge/local/state.md" <<'EOF'
<!-- forge:state-schema v6 -->
## Workflow
| Field | Value |
| Command | /new-feature concurrent-stop |
| Phase | 4 — Implementation |
| Next step | verify-concurrency |
### Checklist
- [ ] Code review loop
EOF
(cd "$CS" && bash "$REPO_ROOT/hooks/build-evidence.sh" > "$CS/one.out" 2>&1) & c1=$!
(cd "$CS" && bash "$REPO_ROOT/hooks/build-evidence.sh" > "$CS/two.out" 2>&1) & c2=$!
wait "$c1"; r1=$?; wait "$c2"; r2=$?
assert_equals "$r1:$r2" "0:0" "either concurrent Stop order completes"
assert_matches "$CS/.forge/local/forge-goal-last-fingerprint" '^[0-9a-f]{64}$' \
    "concurrent evidence publishes only a complete final fingerprint"
assert_contains "$CS/one.out" 'FORGE_GOAL_EVIDENCE_END' "first Stop emits complete evidence"
assert_contains "$CS/two.out" 'FORGE_GOAL_EVIDENCE_END' "second Stop emits the same complete schema"

# ===========================================================================
# Task 8: receipt-v2 final-candidate binding. These tests use Task 5 review
# receipt fields verbatim and add only the verifier/candidate layer owned here.
# ===========================================================================

make_v2_candidate_repo() {
    V2=$(scratch_dir receipt-v2)
    V2=$(cd "$V2" && pwd -P)
    case "$V2" in
        ''|"$REPO_ROOT"|"$REPO_ROOT"/*)
            fail "receipt-v2 fixture escaped its registered scratch root"
            return 1
            ;;
    esac
    mkdir -p "$V2/.forge/local/reviews" "$V2/.forge/local/evidence"
    (
        cd "$V2" || exit 1
        git init -q --initial-branch=main
        git config user.email t@t
        git config user.name t
        printf '.forge/local/\n' > .gitignore
        printf 'base\n' > app.txt
        git add .gitignore app.txt
        git commit -qm base
    )
    V2_HEAD=$(git -C "$V2" rev-parse HEAD)
    V2_COMMON=$(cd "$V2" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
    cat > "$V2/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
## Identity
| Field | Value |
| Worktree root | $V2 |
| Git common directory | $V2_COMMON |
| Last active host | claude |
| Workflow base ref | main |
| Workflow base SHA | $V2_HEAD |
## Workflow
| Field | Value |
| Command | /new-feature receipt-v2 |
| Phase | 5 — Quality |
| Next step | promote |
### Checklist
- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified via verify-e2e agent (Phase 5.4)
## Receipts
| Field | Value |
| Review iteration | 1 |
| Candidate receipt | .forge/local/evidence/candidate.receipt |
| Spec review receipt | .forge/local/reviews/spec.receipt |
| Quality review receipt | .forge/local/reviews/quality.receipt |
| Verify app receipt | .forge/local/evidence/verify-app.receipt |
| E2E receipt | .forge/local/evidence/e2e.receipt |
EOF
    printf 'changed\n' > "$V2/app.txt"
    git -C "$V2" add -A
}

write_v2_review() {
    local role="$1" invocation="$2" actual="$3" fallback="$4" reason="$5" receipt="$6"
    local candidate_id worktree head base output output_hash now empty_digest
    candidate_id=$(awk -F= '$1=="candidate_id"{print $2}' "$V2/.forge/local/evidence/candidate.receipt")
    worktree=$(awk -F= '$1=="worktree_identity"{print $2}' "$V2/.forge/local/evidence/candidate.receipt")
    head=$(awk -F= '$1=="git_head"{print $2}' "$V2/.forge/local/evidence/candidate.receipt")
    base=$(awk -F= '$1=="workflow_base_sha"{print $2}' "$V2/.forge/local/evidence/candidate.receipt")
    output="$V2/.forge/local/reviews/$role.result"
    printf 'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n' > "$output"
    output_hash=$(shasum -a 256 "$output" | awk '{print $1}')
    empty_digest=$(printf '' | shasum -a 256 | awk '{print $1}')
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    cat > "$receipt" <<EOF
schema_version=1
invocation_id=$invocation
timestamp=$now
main_host=claude
requested_engine=$actual
first_attempted_engine=$actual
actual_engine=$actual
fallback=$fallback
fallback_reason=$reason
attempted_engines=$actual
role=$role
profile=review
review_iteration=1
fresh_process=true
artifact_kind=git-working-tree
artifact_identity=$candidate_id
artifact_hash=$candidate_id
worktree_identity=$worktree
git_head=$head
workflow_base_ref=main
workflow_base_sha=$base
output_path=$output
output_hash=$output_hash
process_exit_status=0
semantic_verdict=CLEAN
max_severity=NONE
findings_digest=$empty_digest
result_schema_version=1
blocked_class=none
EOF
}

refresh_v2_final_receipts() {
    (cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" freeze \
        --artifact git:working-tree --workflow-base-sha "$V2_HEAD" --workflow-base-ref main \
        --output .forge/local/evidence/candidate.receipt) || return 1
    write_v2_review code-spec invoke-spec-$$ claude false none "$V2/.forge/local/reviews/spec.receipt"
    write_v2_review code-quality invoke-quality-$$ codex false none "$V2/.forge/local/reviews/quality.receipt"
    printf 'VERDICT: PASS\nverify app report\n' > "$V2/.forge/local/evidence/verify-app.report"
    printf 'VERDICT: PASS\ne2e report\n' > "$V2/.forge/local/evidence/e2e.report"
    (cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind verify-app \
        --candidate .forge/local/evidence/candidate.receipt --command 'focused verify-app' --profile focused \
        --report .forge/local/evidence/verify-app.report --result PASS --exit-status 0 \
        --output .forge/local/evidence/verify-app.receipt >/dev/null) || return 1
    (cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind e2e \
        --candidate .forge/local/evidence/candidate.receipt --command 'focused e2e' --profile regression \
        --report .forge/local/evidence/e2e.report --result PASS --exit-status 0 \
        --output .forge/local/evidence/e2e.receipt >/dev/null) || return 1
}

start_test "receipt-v2: distinct clean same-engine/fallback lenses and verifiers certify one staged-clean candidate"
make_v2_candidate_repo
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" freeze \
    --artifact git:working-tree --workflow-base-sha "$V2_HEAD" --workflow-base-ref main \
    --output .forge/local/evidence/candidate.receipt)
assert_equals "$?" "0" "staged-clean candidate freezes"
write_v2_review code-spec invoke-spec claude false none "$V2/.forge/local/reviews/spec.receipt"
write_v2_review code-quality invoke-quality codex true preferred-engine-unavailable "$V2/.forge/local/reviews/quality.receipt"
printf 'VERDICT: FAIL\nverify app report\n' > "$V2/.forge/local/evidence/verify-app-mismatch.report"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind verify-app \
    --candidate .forge/local/evidence/candidate.receipt --command 'focused verify-app' --profile focused \
    --report .forge/local/evidence/verify-app-mismatch.report --result PASS --exit-status 0 \
    --output .forge/local/evidence/verify-app-mismatch.receipt) >/dev/null 2>&1
assert_equals "$?" "2" "verify-app PASS cannot bind a FAIL report"
printf 'VERDICT: PARTIAL\ne2e report\n' > "$V2/.forge/local/evidence/e2e-mismatch.report"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind e2e \
    --candidate .forge/local/evidence/candidate.receipt --command 'focused e2e' --profile regression \
    --report .forge/local/evidence/e2e-mismatch.report --result PASS --exit-status 0 \
    --output .forge/local/evidence/e2e-mismatch.receipt) >/dev/null 2>&1
assert_equals "$?" "2" "E2E PASS cannot bind a PARTIAL report"
printf 'VERDICT: PASS\nverify app report\n' > "$V2/.forge/local/evidence/verify-app.report"
printf 'VERDICT: PASS\ne2e report\n' > "$V2/.forge/local/evidence/e2e.report"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind verify-app \
    --candidate .forge/local/evidence/candidate.receipt --command 'focused verify-app' --profile focused \
    --report .forge/local/evidence/verify-app.report --result PASS --exit-status 0 \
    --output .forge/local/evidence/verify-app.receipt)
assert_equals "$?" "0" "verify-app result is bound to the frozen candidate"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind e2e \
    --candidate .forge/local/evidence/candidate.receipt --command 'focused e2e' --profile regression \
    --report .forge/local/evidence/e2e.report --result PASS --exit-status 0 \
    --output .forge/local/evidence/e2e.receipt)
assert_equals "$?" "0" "E2E result is bound to the frozen candidate"
assert_contains "$V2/.forge/local/evidence/verify-app.receipt" 'report_verdict=PASS' \
    "verify-app receipt persists the report verdict"
assert_contains "$V2/.forge/local/evidence/e2e.receipt" 'report_verdict=PASS' \
    "E2E receipt persists the report verdict"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check \
    --state .forge/local/state.md) > "$V2/.forge/local/evidence/check.out" 2>&1
assert_equals "$?" "0" "complete receipt set validates"
assert_contains "$V2/.forge/local/evidence/check.out" 'SHIP_READY:true' "all four final gates share one candidate"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/review-breaker.sh" .forge/local/state.md) \
    > "$V2/.forge/local/evidence/breaker-v2.out" 2>&1
assert_contains "$V2/.forge/local/evidence/breaker-v2.out" 'CERTIFIED:yes' \
    "convergence breaker certifies the first clean code-spec/code-quality receipt pair"
(cd "$V2" && run_evidence) > "$V2/.forge/local/evidence/evidence.out" 2>&1
assert_contains "$V2/.forge/local/evidence/evidence.out" '"candidate_gate":{"staged_clean":true' \
    "build evidence exposes the immutable staged-clean candidate"
assert_contains "$V2/.forge/local/evidence/evidence.out" '"reviewer_gate":{"clean_same_iteration":true' \
    "build evidence accepts engine-neutral code-spec/code-quality receipts"
assert_contains "$V2/.forge/local/evidence/evidence.out" '"verification_gate":{"verify_app":true,"e2e":true' \
    "build evidence binds verifier receipts"
printf '{"cwd":"%s","host":"claude","tool_name":"Bash","tool_input":{"command":"git push"}}' "$V2" \
    | (cd "$V2" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") > "$V2/.forge/local/evidence/gate-valid.out" 2>&1
assert_equals "$?" "0" "ship hook accepts the complete current receipt set"

start_test "receipt-v2: semantic/process/identity/iteration mutations fail closed in one compact matrix"
for mutation in duplicate-invocation wrong-role findings stale-output copied-worktree stale-iteration; do
    cp "$V2/.forge/local/reviews/spec.receipt" "$V2/.forge/local/reviews/spec.saved"
    cp "$V2/.forge/local/reviews/quality.receipt" "$V2/.forge/local/reviews/quality.saved"
    case "$mutation" in
        duplicate-invocation) sed -i.bak 's/invocation_id=invoke-quality/invocation_id=invoke-spec/' "$V2/.forge/local/reviews/quality.receipt" ;;
        wrong-role) sed -i.bak 's/role=code-quality/role=general/' "$V2/.forge/local/reviews/quality.receipt" ;;
        findings) sed -i.bak 's/semantic_verdict=CLEAN/semantic_verdict=FINDINGS/;s/max_severity=NONE/max_severity=P1/' "$V2/.forge/local/reviews/quality.receipt" ;;
        stale-output) printf 'mutated\n' >> "$V2/.forge/local/reviews/code-quality.result" ;;
        copied-worktree) sed -i.bak 's/worktree_identity=.*/worktree_identity=0000000000000000000000000000000000000000000000000000000000000000/' "$V2/.forge/local/reviews/quality.receipt" ;;
        stale-iteration) sed -i.bak 's/review_iteration=1/review_iteration=0/' "$V2/.forge/local/reviews/quality.receipt" ;;
    esac
    (cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check --state .forge/local/state.md) > "$V2/.forge/local/evidence/$mutation.out" 2>&1
    assert_equals "$?" "2" "$mutation cannot certify"
    mv "$V2/.forge/local/reviews/spec.saved" "$V2/.forge/local/reviews/spec.receipt"
    mv "$V2/.forge/local/reviews/quality.saved" "$V2/.forge/local/reviews/quality.receipt"
    rm -f "$V2/.forge/local/reviews/"*.bak
    [ "$mutation" != stale-output ] || printf 'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n' > "$V2/.forge/local/reviews/code-quality.result"
done

start_test "receipt-v2: any post-freeze tracked/index/untracked mutation invalidates review, verify-app, and E2E"
printf 'unstaged mutation\n' >> "$V2/app.txt"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check --state .forge/local/state.md) > "$V2/.forge/local/evidence/unstaged.out" 2>&1
assert_equals "$?" "2" "unstaged mutation invalidates all final receipts"
printf '{"cwd":"%s","host":"codex","tool_name":"Bash","tool_input":{"command":"git push"}}' "$V2" \
    | (cd "$V2" && bash "$REPO_ROOT/hooks/check-workflow-gates.sh") > "$V2/.forge/local/evidence/gate-mutated.out" 2>&1
assert_equals "$?" "2" "ship hook blocks after candidate mutation"
printf '{"cwd":"%s","host":"codex","stop_hook_active":false}' "$V2" \
    | (cd "$V2" && bash "$REPO_ROOT/hooks/check-state-updated.sh") > "$V2/.forge/local/evidence/stop-mutated.out" 2>&1
assert_contains "$V2/.forge/local/evidence/stop-mutated.out" 'FORGE_FINAL_EVIDENCE_STALE' \
    "Stop advisory exposes candidate-bound evidence invalidation immediately"
git -C "$V2" checkout -- app.txt
printf 'new untracked\n' > "$V2/new.txt"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check --state .forge/local/state.md) > "$V2/.forge/local/evidence/untracked.out" 2>&1
assert_equals "$?" "2" "in-scope untracked addition invalidates all final receipts"
rm "$V2/new.txt"
printf 'different staged bytes\n' > "$V2/app.txt"
git -C "$V2" add -A
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check --state .forge/local/state.md) > "$V2/.forge/local/evidence/staged.out" 2>&1
assert_equals "$?" "2" "index mutation invalidates all final receipts"

start_test "exact-tree promotion validates standard hooks, CASes once, and runs post-commit on the real branch"
make_v2_candidate_repo
refresh_v2_final_receipts
OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
FROZEN_TREE=$(awk -F= '$1=="index_tree"{print $2}' "$V2/.forge/local/evidence/candidate.receipt")
printf 'Task 8 promotion\n' > "$V2/.forge/local/evidence/message.txt"
mkdir -p "$V2/.git/hooks"
cat > "$V2/.git/hooks/pre-commit" <<EOF
#!/bin/sh
printf 'pre:%s\n' "\$(pwd -P)" >> "$V2/.forge/local/evidence/hook.log"
EOF
cat > "$V2/.git/hooks/post-commit" <<EOF
#!/bin/sh
printf 'post:%s:%s\n' "\$(pwd -P)" "\$(git branch --show-current)" >> "$V2/.forge/local/evidence/hook.log"
EOF
chmod +x "$V2/.git/hooks/pre-commit" "$V2/.git/hooks/post-commit"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 0) \
    > "$V2/.forge/local/evidence/promote.out" 2>&1
assert_equals "$?" "0" "promotion succeeds only after exact candidate validation"
PROMOTED_HEAD=$(git -C "$V2" rev-parse HEAD)
if [ "$PROMOTED_HEAD" != "$OLD_HEAD" ]; then pass "CAS advances the real branch exactly once"; else fail "CAS did not advance the real branch"; fi
assert_equals "$(git -C "$V2" rev-parse HEAD^{tree})" "$FROZEN_TREE" "promoted commit tree is the frozen index tree"
assert_contains "$V2/.forge/local/evidence/hook.log" "post:$V2:main" \
    "post-commit sees the original worktree cwd and real branch"
assert_contains "$V2/.forge/local/evidence/promotion.receipt" "old_candidate_id=" \
    "promotion receipt binds the old candidate"
assert_equals "$(git -C "$V2" status --porcelain | wc -l | tr -d ' ')" "0" \
    "original worktree and index are clean after CAS"

start_test "exact-tree promotion does not execute post-checkout hooks in its disposable worktree"
make_v2_candidate_repo
refresh_v2_final_receipts
OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
printf 'Task 8 post-checkout isolation\n' > "$V2/.forge/local/evidence/message.txt"
mkdir -p "$V2/.git/hooks"
cat > "$V2/.git/hooks/post-checkout" <<EOF
#!/bin/sh
printf 'post-checkout-ran\n' >> "$V2/.forge/local/evidence/post-checkout.log"
exit 1
EOF
chmod +x "$V2/.git/hooks/post-checkout"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 0) \
    > "$V2/.forge/local/evidence/post-checkout-promote.out" 2>&1
assert_equals "$?" "0" "promotion is isolated from unrelated checkout lifecycle hooks"
assert_file_missing "$V2/.forge/local/evidence/post-checkout.log" \
    "disposable promotion never executes the repository post-checkout hook"
if [ "$(git -C "$V2" rev-parse HEAD)" != "$OLD_HEAD" ]; then
    pass "post-checkout isolation still promotes the certified tree"
else
    fail "post-checkout isolation did not advance the certified tree"
fi

start_test "exact-tree promotion replays one bounded auto-fix and requires every final receipt to rerun"
make_v2_candidate_repo
refresh_v2_final_receipts
OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
printf 'Task 8 replay\n' > "$V2/.forge/local/evidence/message.txt"
mkdir -p "$V2/.git/hooks"
cat > "$V2/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
if ! grep -q '^# hook-fixed$' app.txt; then
    printf '# hook-fixed\n' >> app.txt
    git add app.txt
fi
EOF
chmod +x "$V2/.git/hooks/pre-commit"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 0) \
    > "$V2/.forge/local/evidence/replay.out" 2>&1
assert_equals "$?" "3" "first auto-fix is replayed without advancing the branch"
assert_equals "$(git -C "$V2" rev-parse HEAD)" "$OLD_HEAD" "repair cycle leaves the real branch at the expected parent"
assert_contains "$V2/app.txt" '# hook-fixed' "validated hook artifact is replayed into the original worktree"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" check --state .forge/local/state.md) \
    > "$V2/.forge/local/evidence/replay-stale.out" 2>&1
assert_equals "$?" "2" "pre-replay receipts cannot certify the repaired candidate"
refresh_v2_final_receipts
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 1) \
    > "$V2/.forge/local/evidence/replay-promote.out" 2>&1
assert_equals "$?" "0" "idempotent second hook run promotes after fresh final receipts"

start_test "exact-tree promotion rejects a tree mismatch before advancing the branch"
make_v2_candidate_repo
refresh_v2_final_receipts
OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
sed -i.bak 's/index_tree=.*/index_tree=0000000000000000000000000000000000000000/' "$V2/.forge/local/evidence/candidate.receipt"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/verify-app.report \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 0) \
    > "$V2/.forge/local/evidence/tree-mismatch.out" 2>&1
assert_equals "$?" "2" "tree mismatch blocks promotion"
assert_equals "$(git -C "$V2" rev-parse HEAD)" "$OLD_HEAD" "tree mismatch never advances the real branch"

start_test "exact-tree promotion CAS failure preserves the concurrently advanced branch and skips post-commit"
make_v2_candidate_repo
refresh_v2_final_receipts
OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
CONCURRENT=$(printf 'concurrent\n' | git -C "$V2" commit-tree "${OLD_HEAD}^{tree}" -p "$OLD_HEAD")
printf 'Task 8 CAS\n' > "$V2/.forge/local/evidence/message.txt"
mkdir -p "$V2/.git/hooks"
cat > "$V2/.git/hooks/pre-commit" <<EOF
#!/bin/sh
git update-ref refs/heads/main "$CONCURRENT" "$OLD_HEAD"
EOF
cat > "$V2/.git/hooks/post-commit" <<EOF
#!/bin/sh
printf 'ran\n' > "$V2/.forge/local/evidence/post-ran"
EOF
chmod +x "$V2/.git/hooks/pre-commit" "$V2/.git/hooks/post-commit"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
    --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
    --message-file .forge/local/evidence/message.txt \
    --promotion-receipt .forge/local/evidence/promotion.receipt --replay-attempt 0) \
    > "$V2/.forge/local/evidence/cas-failure.out" 2>&1
assert_equals "$?" "2" "compare-and-swap rejects concurrent branch movement"
assert_equals "$(git -C "$V2" rev-parse HEAD)" "$CONCURRENT" "promotion does not overwrite the concurrent winner"
assert_file_missing "$V2/.forge/local/evidence/post-ran" "post-commit never runs after failed CAS"

start_test "exact-tree promotion hook/dependency failure policy is bounded and fail-closed"
for promotion_case in pre-failure repeated-mutation dependency-present dependency-missing dependency-changed post-failure post-mutation; do
    make_v2_candidate_repo
    refresh_v2_final_receipts
    OLD_HEAD=$(git -C "$V2" rev-parse HEAD)
    printf 'Task 8 policy %s\n' "$promotion_case" > "$V2/.forge/local/evidence/message.txt"
    mkdir -p "$V2/.git/hooks"
    DEP_ARG=""
    case "$promotion_case" in
        pre-failure)
            printf '#!/bin/sh\nexit 1\n' > "$V2/.git/hooks/pre-commit"
            chmod +x "$V2/.git/hooks/pre-commit"
            EXPECTED_RC=2; EXPECTED_ADVANCE=no ;;
        repeated-mutation)
            printf '#!/bin/sh\nprintf "again\\n" >> app.txt\ngit add app.txt\n' > "$V2/.git/hooks/pre-commit"
            chmod +x "$V2/.git/hooks/pre-commit"
            EXPECTED_RC=2; EXPECTED_ADVANCE=no ;;
        dependency-present|dependency-changed)
            printf 'hook runtime\n' > "$V2/hook.dep"
            printf 'hook.dep\n' >> "$V2/.gitignore"
            git -C "$V2" add .gitignore
            refresh_v2_final_receipts
            DEP_SHA=$(shasum -a 256 "$V2/hook.dep" | awk '{print $1}')
            printf 'hook.dep\t%s\n' "$DEP_SHA" > "$V2/.forge/local/evidence/dependencies.tsv"
            printf '#!/bin/sh\ntest -f hook.dep\n' > "$V2/.git/hooks/pre-commit"
            chmod +x "$V2/.git/hooks/pre-commit"
            DEP_ARG="--hook-dependencies .forge/local/evidence/dependencies.tsv"
            if [ "$promotion_case" = dependency-changed ]; then printf 'changed\n' >> "$V2/hook.dep"; EXPECTED_RC=2; EXPECTED_ADVANCE=no
            else EXPECTED_RC=0; EXPECTED_ADVANCE=yes; fi ;;
        dependency-missing)
            printf 'missing.dep\t0000000000000000000000000000000000000000000000000000000000000000\n' > "$V2/.forge/local/evidence/dependencies.tsv"
            DEP_ARG="--hook-dependencies .forge/local/evidence/dependencies.tsv"
            EXPECTED_RC=2; EXPECTED_ADVANCE=no ;;
        post-failure)
            printf '#!/bin/sh\nexit 1\n' > "$V2/.git/hooks/post-commit"
            chmod +x "$V2/.git/hooks/post-commit"
            EXPECTED_RC=2; EXPECTED_ADVANCE=yes ;;
        post-mutation)
            printf '#!/bin/sh\nprintf "post dirty\\n" >> app.txt\n' > "$V2/.git/hooks/post-commit"
            chmod +x "$V2/.git/hooks/post-commit"
            EXPECTED_RC=2; EXPECTED_ADVANCE=yes ;;
    esac
    # shellcheck disable=SC2086 -- DEP_ARG intentionally expands to one option pair.
    (cd "$V2" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" promote \
        --candidate .forge/local/evidence/candidate.receipt --state .forge/local/state.md \
        --message-file .forge/local/evidence/message.txt \
        --promotion-receipt .forge/local/evidence/promotion.receipt \
        --replay-attempt "$([ "$promotion_case" = repeated-mutation ] && echo 1 || echo 0)" $DEP_ARG) \
        > "$V2/.forge/local/evidence/$promotion_case.out" 2>&1
    assert_equals "$?" "$EXPECTED_RC" "$promotion_case returns the bounded policy status"
    NEW_HEAD=$(git -C "$V2" rev-parse HEAD)
    if [ "$EXPECTED_ADVANCE" = yes ] && [ "$NEW_HEAD" != "$OLD_HEAD" ]; then pass "$promotion_case advances only at the authorized CAS boundary"
    elif [ "$EXPECTED_ADVANCE" = no ] && [ "$NEW_HEAD" = "$OLD_HEAD" ]; then pass "$promotion_case leaves the real branch untouched"
    else fail "$promotion_case branch-advance policy mismatch"; fi
done

# lib.sh's EXIT trap prints the summary; no explicit call needed.
report "build-evidence.sh" >&2
