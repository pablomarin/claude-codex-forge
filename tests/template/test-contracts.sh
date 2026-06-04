#!/usr/bin/env bash
# tests/template/test-contracts.sh — cross-file consistency checks.
#
# Catches stringly-typed contracts that span files: e.g., the verify-e2e
# agent's response header defines VERDICT values, and the callers in
# commands/new-feature.md and commands/fix-bug.md must branch on those
# same values. These are exactly the regressions that are easy to ship
# and costly to catch in code review — a contract test makes the link
# between cooperating files explicit and machine-verifiable.
#
# Run from repo root:  bash tests/template/test-contracts.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

# ---------------------------------------------------------------------------
# Contract 1: verify-e2e VERDICT values must match caller branches
# ---------------------------------------------------------------------------
start_test "verify-e2e VERDICT header ↔ caller branch labels"

VE2E="$REPO_ROOT/agents/verify-e2e.md"
NF="$REPO_ROOT/commands/new-feature.md"
FB="$REPO_ROOT/commands/fix-bug.md"

for f in "$VE2E" "$NF" "$FB"; do
    assert_file_exists "$f" "file exists: $f"
done

# Pull the set of VERDICT values defined in verify-e2e.md.
# Looks for lines like: VERDICT: PASS | FAIL | PARTIAL
VERDICT_LINE=$(grep -E "^VERDICT:\s*(PASS|FAIL|PARTIAL)" "$VE2E" | head -1)
if [[ -z "$VERDICT_LINE" ]]; then
    fail "could not find VERDICT: header definition in verify-e2e.md"
else
    pass "found VERDICT header in verify-e2e.md"
fi

# Extract the named values (PASS, FAIL, PARTIAL) from the header line.
# Treat this as the authoritative vocabulary.
VERDICT_VALUES=$(echo "$VERDICT_LINE" | grep -oE "(PASS|FAIL|PARTIAL)" | sort -u)

# For each value in the authoritative set, the callers should have
# branching logic that references it (we look for 'VERDICT: <VAL>' which
# is how the caller docs reference each branch).
for val in $VERDICT_VALUES; do
    if grep -qF "VERDICT: $val" "$NF"; then
        pass "commands/new-feature.md branches on VERDICT: $val"
    else
        fail "commands/new-feature.md missing branch for VERDICT: $val"
    fi
    if grep -qF "VERDICT: $val" "$FB"; then
        pass "commands/fix-bug.md branches on VERDICT: $val"
    else
        fail "commands/fix-bug.md missing branch for VERDICT: $val"
    fi
done

# Reverse check: the callers must NOT branch on values that aren't in the
# agent's vocabulary (catches the bug Codex found where callers still
# branched on FAIL_BUG/FAIL_STALE/FAIL_INFRA after the header was reduced
# to PASS/FAIL/PARTIAL).
# FAIL_BUG etc. are legitimate per-UC classification labels that appear
# IN THE BODY. They just shouldn't be used as VERDICT: branch names.
#
# macOS sed -E does NOT support \s; use [[:space:]] for portability.
# Also: `grep -o` across multiple files prefixes output with `file:`, so
# the sed pattern strips everything up through `VERDICT: ` literally.
UNKNOWN_BRANCHES=$(grep -oE 'VERDICT: [A-Z_]+' "$NF" "$FB" \
    | sed -E 's/.*VERDICT:[[:space:]]+//' \
    | sort -u \
    | grep -vE '^(PASS|FAIL|PARTIAL)$' || true)

if [[ -z "$UNKNOWN_BRANCHES" ]]; then
    pass "callers reference only valid VERDICT values (PASS/FAIL/PARTIAL)"
else
    while read -r bad; do
        fail "caller references unknown VERDICT: '$bad' (not in agent header)"
    done <<< "$UNKNOWN_BRANCHES"
fi

# ---------------------------------------------------------------------------
# Contract 2: SUGGESTED_PATH header must be consumed by callers
# ---------------------------------------------------------------------------
start_test "SUGGESTED_PATH header ↔ caller persistence instructions"

# Agent defines SUGGESTED_PATH in its response header.
assert_contains "$VE2E" "SUGGESTED_PATH:" \
    "agent response defines SUGGESTED_PATH"

# Callers must reference it to know where to persist the report.
assert_contains "$NF" "SUGGESTED_PATH" \
    "commands/new-feature.md references SUGGESTED_PATH"
assert_contains "$FB" "SUGGESTED_PATH" \
    "commands/fix-bug.md references SUGGESTED_PATH"

# And both callers must mkdir the reports dir (otherwise Write fails on
# first run).
assert_contains "$NF" "mkdir -p tests/e2e/reports" \
    "commands/new-feature.md creates reports dir"
assert_contains "$FB" "mkdir -p tests/e2e/reports" \
    "commands/fix-bug.md creates reports dir"

# ---------------------------------------------------------------------------
# Contract 2b: per-UC failure classifications ↔ caller handling
#
# Surfaced 2026-05-18 (v5.31): adding FAIL_INVALID_USE_CASE without updating
# both callers would silently drop the new classification — callers wouldn't
# know to rewrite the UC vs fix product code. Mirrors Contract 1 (VERDICT
# vocabulary) but at the per-UC level.
#
# Authoritative source: the FAIL_* labels in verify-e2e.md's "Classification
# rules" section. Each FAIL_* label must be mentioned by name in BOTH
# new-feature.md and fix-bug.md so caller branching exists for it.
# ---------------------------------------------------------------------------
start_test "per-UC FAIL_* classifications ↔ caller handling"

# Extract every FAIL_* label that appears as a bolded definition in the
# Classification rules section. The Markdown formatter normalizes the
# bolded labels to put the trailing colon INSIDE the bold span:
#   - **FAIL_BUG:** ...
#   - **FAIL_STALE:** ...
#   - **FAIL_INVALID_USE_CASE:** ...
# Regex anchors on '- **' start; colon is inside the close-bold token.
FAIL_LABELS=$(grep -oE '^\- \*\*FAIL_[A-Z_]+:\*\*' "$VE2E" \
    | sed -E 's/^\- \*\*//; s/:\*\*$//' \
    | sort -u)

if [[ -z "$FAIL_LABELS" ]]; then
    fail "could not find any FAIL_* classification labels in verify-e2e.md Classification rules"
else
    pass "found $(echo "$FAIL_LABELS" | wc -l | tr -d ' ') FAIL_* classifications in verify-e2e.md"
fi

# Each FAIL_* must be referenced by name in both caller files (caller
# branching exists). We match the bare label (e.g. FAIL_BUG) — callers
# reference it inline in their verdict-handling prose, not in a bolded
# form. Grep for the literal token with word-ish boundary.
for label in $FAIL_LABELS; do
    if grep -qE "\b${label}\b" "$NF"; then
        pass "commands/new-feature.md handles $label"
    else
        fail "commands/new-feature.md missing handling for $label"
    fi
    if grep -qE "\b${label}\b" "$FB"; then
        pass "commands/fix-bug.md handles $label"
    else
        fail "commands/fix-bug.md missing handling for $label"
    fi
done

# Reverse check: callers must not reference FAIL_* labels that aren't in
# the agent's vocabulary. Catches stale references after a label rename.
CALLER_LABELS=$(grep -hoE '\bFAIL_[A-Z_]+\b' "$NF" "$FB" | sort -u)
for label in $CALLER_LABELS; do
    if echo "$FAIL_LABELS" | grep -qxF "$label"; then
        :  # known label — already covered above
    else
        fail "caller references unknown FAIL_* label: '$label' (not in agent vocabulary)"
    fi
done
[[ -n "$CALLER_LABELS" ]] && pass "all caller-referenced FAIL_* labels are in the agent vocabulary"

# ---------------------------------------------------------------------------
# Contract 2c: surface coverage audit vocabulary
#
# Surfaced 2026-05-18 (v5.33): msai-v2 soak found that the agent designed
# UI+API UCs while skipping CLI even though the project's CLI exposes the
# same capability area. Fix: (1) Phase 3.2b requires a "Surface coverage
# decision" sub-block; (2) verify-e2e Step 2c emits SURFACE_COVERAGE_WARNING.
#
# The keyword `SURFACE_COVERAGE_WARNING` is the canonical marker that all
# four files (rules + 2 commands + agent) must reference for the loop to
# wire correctly. Drift in any one file breaks the audit silently.
# ---------------------------------------------------------------------------
start_test "Surface coverage audit — canonical vocabulary across files"

SURFACE_KEY="SURFACE_COVERAGE_WARNING"
SURFACE_DECISION_KEY="Surface coverage decision"
RULES_TESTING="$REPO_ROOT/rules/testing.md"

# Producer (agent) must define BOTH the warning marker AND the decision
# sub-block name (Codex P2-4 fix v5.33): the agent reads the decision
# sub-block to recognize pre-justified N/A lines, so the sub-block name
# must be locked here too.
assert_contains "$VE2E" "$SURFACE_KEY" \
    "verify-e2e.md defines $SURFACE_KEY"
assert_contains "$VE2E" "$SURFACE_DECISION_KEY" \
    "verify-e2e.md references the Surface coverage decision sub-block (reads it for pre-justified N/A)"
assert_contains "$VE2E" "Step 2c" \
    "verify-e2e.md has Step 2c surface coverage check"
assert_contains "$VE2E" "feature mode" \
    "verify-e2e.md gates Step 2c to feature mode only (Codex P2-3 v5.33)"

# Consumers (callers + rules) must reference the decision sub-block AND the
# warning marker so the flow is wired.
for f in "$NF" "$FB"; do
    base=$(basename "$f")
    assert_contains "$f" "$SURFACE_DECISION_KEY" \
        "$base mentions Surface coverage decision sub-block"
    assert_contains "$f" "$SURFACE_KEY" \
        "$base references $SURFACE_KEY (cross-file wiring)"
done

# rules/testing.md must define the "Multi-surface coverage" section AND
# the canonical SURFACE_COVERAGE_WARNING marker (Codex P2-4 fix v5.33):
# the marker name could drift in rules/testing.md silently if not asserted.
assert_contains "$RULES_TESTING" "Multi-surface coverage" \
    "rules/testing.md has Multi-surface coverage subsection"
assert_contains "$RULES_TESTING" "$SURFACE_DECISION_KEY" \
    "rules/testing.md defines Surface coverage decision vocabulary"
assert_contains "$RULES_TESTING" "$SURFACE_KEY" \
    "rules/testing.md references the canonical $SURFACE_KEY marker (locked across all 4 files)"

# Negative-justification regression guard: the disqualifying phrase must
# appear in BOTH commands so future drift doesn't silently re-enable the
# bad pattern.
DISQUALIFIED='no CLI changes in my diff'
assert_contains "$NF" "$DISQUALIFIED" \
    "new-feature.md flags the disqualified N/A pattern"
assert_contains "$FB" "$DISQUALIFIED" \
    "fix-bug.md flags the disqualified N/A pattern"

# Codex P2-1 (v5.33): callers must explicitly scan for SURFACE_COVERAGE_WARNING
# after parsing the verdict. Without this post-report check, a PASS verdict
# silently swallows the warning and the autonomous loop proceeds.
assert_contains "$NF" "Step 4b" \
    "new-feature.md has Step 4b SURFACE_COVERAGE_WARNING scan"
assert_contains "$FB" "Step 4b" \
    "fix-bug.md has Step 4b SURFACE_COVERAGE_WARNING scan"

# ---------------------------------------------------------------------------
# Contract 2d: user-journey UC shape — Actor + Scenario + surface-specific
# Verification rubric (v5.34).
#
# Pablo's complaint 2026-05-25: agent keeps drafting code-shaped UCs even
# with v5.31's smell test. Codex pinpointed root cause: examples still
# modeled generic "User creates …" phrasing, and Step 2b's prefer-valid
# bias let borderline UCs slide. v5.34 adds:
#   - Required Actor field (rejects bare "user" via MISSING_ACTOR)
#   - Required Scenario field (1-2 sentences, no biography fluff)
#   - Surface-specific Verification language rubric per UI/CLI/API
#   - Setup-cheat detection (CHEAT_SETUP)
#   - Hard gates vs judgment calls split in Step 2b
#   - GOOD examples rewritten to model the new shape
#
# This contract locks the new reason codes + the surface verbs across
# rules + agent + both commands.
# ---------------------------------------------------------------------------
start_test "v5.34 — user-journey UC shape vocabulary across files"

# The new reason codes introduced by v5.34. Each must be referenced in
# verify-e2e.md (the agent emits them) AND in both command callers (the
# callers tell the agent what to do with each). NOT_USER_JOURNEY and
# WRONG_INTERFACE already shipped in v5.31; the rest are v5.34.
V534_REASONS=(
    "MISSING_ACTOR"
    "MISSING_SCENARIO"
    "SCENARIO_FLUFF"
    "CHEAT_SETUP"
    "THIN_VERIFICATION"
    "MISSING_PERSISTENCE"
    "TOO_SHALLOW"
)
for reason in "${V534_REASONS[@]}"; do
    assert_contains "$VE2E" "$reason" \
        "verify-e2e.md defines $reason reason code"
    assert_contains "$NF" "$reason" \
        "new-feature.md references $reason in caller handling"
    assert_contains "$FB" "$reason" \
        "fix-bug.md references $reason in caller handling"
done

# Required UC fields (Actor + Scenario) must be in rules/testing.md as
# canonical AND in both commands' Phase 3.2b inline checklist so authoring
# guidance matches the verifier.
for field in "Actor" "Scenario"; do
    assert_contains "$RULES_TESTING" "**$field**" \
        "rules/testing.md defines required $field field"
    assert_contains "$NF" "**$field**" \
        "new-feature.md Phase 3.2b requires $field field"
    assert_contains "$FB" "**$field**" \
        "fix-bug.md Phase 3.2b requires $field field"
done

# Surface-specific Verification rubric: the rules file must contain the
# canonical verb sets for UI, CLI, and API verification language so the
# agent has a reference. The agent must mirror them in Step 2b gate logic.
assert_contains "$RULES_TESTING" "Verification language — surface-specific" \
    "rules/testing.md has Verification language section"
assert_contains "$RULES_TESTING" "sees, appears, is shown" \
    "rules/testing.md lists UI Verification verbs"
assert_contains "$RULES_TESTING" "stdout shows, stderr explains" \
    "rules/testing.md lists CLI Verification verbs"
assert_contains "$RULES_TESTING" "receives, response includes" \
    "rules/testing.md lists API Verification verbs"

# GOOD examples must model the new shape — at least one Actor: line in
# the GOOD blocks. This catches the v5.31 mistake where the rules said
# "be specific" but the examples still used generic phrasing.
assert_contains "$RULES_TESTING" "Actor:         Signed-in customer" \
    "rules/testing.md GOOD UI example uses concrete Actor"
assert_contains "$RULES_TESTING" "Actor:         API integrator" \
    "rules/testing.md GOOD API example uses concrete Actor"
assert_contains "$RULES_TESTING" "Actor:         Operator running the CLI" \
    "rules/testing.md GOOD CLI example uses concrete Actor"

# ---------------------------------------------------------------------------
# Contract 2e: Step 2b hard gates feature-mode-only (v5.35).
#
# v5.34 introduced strict hard gates (MISSING_ACTOR, MISSING_SCENARIO, etc.)
# that were mode-agnostic. That retroactively breaks regression suites that
# accumulated UCs under earlier rules — a UC graduated under v5.31 with no
# Actor field would fail v5.34's hard gate on every regression run.
#
# v5.35 mirrors v5.33's Step 2c gating: hard gates run in feature mode only.
# In regression/smoke modes, hard-gate misses fall back to the prefer-valid
# bias used by the judgment calls.
#
# Lock the gating across verify-e2e + both Phase 5.4b verdict-handling
# blocks so future drift can't silently re-introduce the breaking change.
# ---------------------------------------------------------------------------
start_test "v5.35 — Step 2b hard gates gated to feature mode only"

# Agent: Step 2b must explicitly state the mode gating.
assert_contains "$VE2E" "Mode gating for hard gates" \
    "verify-e2e.md Step 2b documents the mode gating"
assert_contains "$VE2E" "feature mode only" \
    "verify-e2e.md Step 2b mentions 'feature mode only' (Step 2b hard gates)"

# The Hard gates header must NAME feature mode (not just the prose before it).
# This catches a partial edit that updates the rationale but leaves the
# header generic.
assert_contains "$VE2E" "Hard gates (feature mode only" \
    "verify-e2e.md Step 2b Hard gates header names feature-mode gating"

# Both Phase 5.4b verdict-handling blocks must reference FAIL_INVALID_USE_CASE
# AND distinguish hard-SHAPE (skipped in regression) from judgment (still
# fires by design). Catches the graduation-bug case AND ensures the
# intentional-surfacing-of-legacy-bad-UCs framing stays explicit (v5.37).
assert_contains "$NF" "FAIL_INVALID_USE_CASE (agent only)" \
    "new-feature.md Phase 5.4b handles FAIL_INVALID_USE_CASE"
assert_contains "$FB" "FAIL_INVALID_USE_CASE (agent only)" \
    "fix-bug.md Phase 5.4b handles FAIL_INVALID_USE_CASE"
# Both commands must split hard-SHAPE vs judgment-call reasons explicitly.
assert_contains "$NF" "Hard-SHAPE reasons" \
    "new-feature.md Phase 5.4b names Hard-SHAPE reasons bucket"
assert_contains "$FB" "Hard-SHAPE reasons" \
    "fix-bug.md Phase 5.4b names Hard-SHAPE reasons bucket"
assert_contains "$NF" "Judgment-call reasons" \
    "new-feature.md Phase 5.4b names Judgment-call reasons bucket"
assert_contains "$FB" "Judgment-call reasons" \
    "fix-bug.md Phase 5.4b names Judgment-call reasons bucket"
# v5.37 framing: NOT_USER_JOURNEY firing in regression is BY DESIGN, not
# a residual risk. Lock the "by design" wording so it doesn't drift back
# to "still applies"/"residual" framing.
assert_contains "$NF" "DO fire in regression mode by design" \
    "new-feature.md Phase 5.4b frames judgment-call firing as intentional design"
assert_contains "$FB" "DO fire in regression mode by design" \
    "fix-bug.md Phase 5.4b frames judgment-call firing as intentional design"

# Codex final-pass gap (v5.38): the AGENT must also state the by-design
# intent in its own Step 2b mode-gating note. Without this assertion the
# caller text could keep saying "by design" while the agent drifts.
assert_contains "$VE2E" "fire in" \
    "verify-e2e.md mode-gating note still asserts judgment calls fire across modes"
assert_contains "$VE2E" "by design" \
    "verify-e2e.md mode-gating note frames legacy-UC surfacing as intentional"

# v5.38: NOT_USER_JOURNEY now has TWO triggers — Intent shape (existing)
# AND whole-UC shape (new). Lock the whole-UC shape vocabulary so future
# drift can't silently narrow it back to Intent-only.
assert_contains "$VE2E" "overall UC journey shape" \
    "verify-e2e.md NOT_USER_JOURNEY definition expanded beyond Intent shape"
assert_contains "$VE2E" "Whole-UC shape" \
    "verify-e2e.md names the whole-UC shape trigger (v5.38)"

# v5.38: rules/testing.md Failure Classification reason list must enumerate
# all 9 reason codes (was stale, only listed NOT_USER_JOURNEY + WRONG_INTERFACE).
# Catches the codex final-pass finding that the rules file lagged the agent.
for reason in MISSING_ACTOR MISSING_SCENARIO SCENARIO_FLUFF CHEAT_SETUP THIN_VERIFICATION MISSING_PERSISTENCE TOO_SHALLOW; do
    assert_contains "$RULES_TESTING" "**\`$reason\`**" \
        "rules/testing.md Failure Classification lists $reason (v5.38 sync)"
done
# And the canonical Hard-SHAPE / Judgment-call bucket labels must be in the
# rules file too (not just the commands).
assert_contains "$RULES_TESTING" "Hard-SHAPE reasons" \
    "rules/testing.md uses Hard-SHAPE reasons bucket vocabulary"
assert_contains "$RULES_TESTING" "Judgment-call reasons" \
    "rules/testing.md uses Judgment-call reasons bucket vocabulary"

# Stale-text guard: the old NOT_USER_JOURNEY definition that said "no
# Persistence step" must be gone from rules/testing.md. Missing persistence
# is now MISSING_PERSISTENCE (a hard gate), not a NOT_USER_JOURNEY trigger.
if grep -qF 'or has no Persistence step' "$RULES_TESTING"; then
    fail "rules/testing.md still says NOT_USER_JOURNEY includes 'no Persistence step' — that's MISSING_PERSISTENCE now (v5.38 fix #2 missing)"
else
    pass "rules/testing.md NOT_USER_JOURNEY no longer claims missing-Persistence (correctly handed off to MISSING_PERSISTENCE)"
fi

# ---------------------------------------------------------------------------
# Contract 2f: v5.36 — Codex review fixes to v5.34/v5.35.
#
# Codex flagged: (1) stale 6-field intro lines contradicting the new 8-field
# shape, (2) "in this order" rigidity, (3) Persistence: N/A escape hatch
# needs narrow whitelist, (4) "objective" claim too strong for SCENARIO_FLUFF/
# CHEAT_SETUP/non-bare THIN_VERIFICATION, (5) Phase 5.4b should say "hard
# SHAPE gates" to clarify NOT_USER_JOURNEY can still fire on legacy UCs.
#
# Lock all five so future drift doesn't regress.
# ---------------------------------------------------------------------------
start_test "v5.36 — Codex review fixes hold across files"

# Fix 1: stale 6-field intro lines MUST be gone from both commands. The
# canonical intro now names all 8 fields including Actor + Scenario.
STALE_INTRO='Each UC must include **Intent**, **Interface**, **Setup**, **Steps**, **Verification**, and **Persistence**'
if grep -qF "$STALE_INTRO" "$NF"; then
    fail "new-feature.md still contains the stale 6-field intro (v5.36 fix #1 missing)"
else
    pass "new-feature.md does NOT contain the stale 6-field intro"
fi
if grep -qF "$STALE_INTRO" "$FB"; then
    fail "fix-bug.md still contains the stale 6-field intro (v5.36 fix #1 missing)"
else
    pass "fix-bug.md does NOT contain the stale 6-field intro"
fi
# And the new 8-field intro MUST be present in both.
NEW_INTRO='Each UC must include **Actor**, **Scenario**, **Interface**, **Intent**, **Setup**, **Steps**, **Verification**, and **Persistence**'
assert_contains "$NF" "$NEW_INTRO" \
    "new-feature.md has the canonical 8-field intro naming Actor + Scenario"
assert_contains "$FB" "$NEW_INTRO" \
    "fix-bug.md has the canonical 8-field intro naming Actor + Scenario"

# Fix 2: "in this order" rigidity must be gone.
if grep -qF "in this order" "$NF"; then
    fail "new-feature.md still has 'in this order' rigidity (v5.36 fix #2 missing)"
else
    pass "new-feature.md no longer has 'in this order' rigidity"
fi
if grep -qF "in this order" "$FB"; then
    fail "fix-bug.md still has 'in this order' rigidity"
else
    pass "fix-bug.md no longer has 'in this order' rigidity"
fi

# Fix 3: Persistence: N/A whitelist must be narrow — both rules and agent
# must mention "stateless" outcomes as the only valid N/A case.
assert_contains "$RULES_TESTING" "narrow" \
    "rules/testing.md describes Persistence: N/A as narrow"
assert_contains "$RULES_TESTING" "stateless" \
    "rules/testing.md restricts N/A to stateless outcomes"
assert_contains "$VE2E" "narrow" \
    "verify-e2e.md describes Persistence: N/A as narrow"

# Fix 4: "objective" claim about hard gates must be softened —
# acknowledge mechanical vs policy.
assert_contains "$VE2E" "Mechanical vs policy gates" \
    "verify-e2e.md splits hard gates into mechanical vs policy"

# Fix 5: Phase 5.4b regression promise must distinguish shape (hard, skipped
# in regression) from journey (judgment, fires by design). v5.37 promoted
# this from a one-liner to a two-bullet bucket split — the canonical phrasing
# is now "Hard-SHAPE reasons" vs "Judgment-call reasons" (asserted above in
# the v5.37 block). Just verify the bucket vocabulary is present here.
assert_contains "$NF" "skipped in regression mode" \
    "new-feature.md Phase 5.4b explains hard-SHAPE skip in regression"
assert_contains "$FB" "skipped in regression mode" \
    "fix-bug.md Phase 5.4b explains hard-SHAPE skip in regression"

# ---------------------------------------------------------------------------
# Contract 3: --playwright-dir marker file ↔ command consumers
# setup.sh writes .claude/playwright-dir. Commands must read it.
# ---------------------------------------------------------------------------
start_test ".claude/playwright-dir marker ↔ command consumers"

assert_contains "$REPO_ROOT/setup.sh" ".claude/playwright-dir" \
    "setup.sh writes marker file"
assert_contains "$REPO_ROOT/setup.ps1" "playwright-dir" \
    "setup.ps1 writes marker file (Windows parity)"
assert_contains "$NF" ".claude/playwright-dir" \
    "commands/new-feature.md reads marker file"
assert_contains "$FB" ".claude/playwright-dir" \
    "commands/fix-bug.md reads marker file"

# ---------------------------------------------------------------------------
# Contract 3b: settings.template.json Stop hook ordering
#
# v5.32 split build-evidence into its own Stop hook (was inline call from
# check-state-updated). The two hooks MUST be registered in this order in
# settings.template.json (and the Windows mirror) — build-evidence FIRST,
# check-state-updated SECOND — because build-evidence writes the
# fingerprint side-channel file that check-state-updated's stuck-detection
# reads. Reversing the order breaks stuck-detection silently.
# ---------------------------------------------------------------------------
start_test "Stop hook ordering — build-evidence before check-state-updated"

UNIX_SETTINGS="$REPO_ROOT/settings/settings.template.json"
WIN_SETTINGS="$REPO_ROOT/settings/settings-windows.template.json"
assert_file_exists "$UNIX_SETTINGS" "settings template exists"
assert_file_exists "$WIN_SETTINGS" "settings-windows template exists"

if command -v python3 >/dev/null 2>&1; then
    # Use Python to parse and assert order — avoids brittle line-grep that
    # would break on whitespace reformatting.
    for f in "$UNIX_SETTINGS" "$WIN_SETTINGS"; do
        order_out=$(python3 -c "
import json, sys
with open('$f') as fh:
    s = json.load(fh)
stop = s.get('hooks', {}).get('Stop', [])
cmds = []
for block in stop:
    for h in block.get('hooks', []):
        cmds.append(h.get('command', ''))
for c in cmds:
    print(c)
")
        # Find indices of build-evidence and check-state-updated in command list
        be_idx=$(echo "$order_out" | grep -n "build-evidence" | head -1 | cut -d: -f1)
        cs_idx=$(echo "$order_out" | grep -n "check-state-updated" | head -1 | cut -d: -f1)
        if [[ -z "$be_idx" ]]; then
            fail "$(basename "$f"): build-evidence NOT registered in Stop hooks"
        elif [[ -z "$cs_idx" ]]; then
            fail "$(basename "$f"): check-state-updated NOT registered in Stop hooks"
        elif (( be_idx < cs_idx )); then
            pass "$(basename "$f"): build-evidence ($be_idx) registered before check-state-updated ($cs_idx)"
        else
            fail "$(basename "$f"): WRONG order — build-evidence ($be_idx) must come before check-state-updated ($cs_idx)"
        fi
    done
else
    pass "python3 not available — Stop hook ordering test skipped (not a failure)"
fi

# ---------------------------------------------------------------------------
# Contract 3c: cache-delete permissions (ask-tier-cache-deletes, v5.53)
#
# The general recursive-delete rail (`Bash(rm -rf:*)` in ask) MUST stay — it is
# what stops an autonomous /goal loop from self-approving a recursive delete.
# Alongside it, three EXACT-match allows (no `:*` suffix — a prefix allow like
# `rm -rf .mypy_cache:*` would also match `rm -rf .mypy_cache /`, riding
# trailing arguments through the allow) let known-safe tool-cache deletes pass
# without stalling autonomous runs. Both settings templates must agree.
# ---------------------------------------------------------------------------
start_test "cache-delete permissions — exact allows + rm -rf rail intact in both settings templates"
if command -v python3 >/dev/null 2>&1; then
    for f in "$UNIX_SETTINGS" "$WIN_SETTINGS"; do
        perm_out=$(python3 -c "
import json
with open('$f') as fh:
    s = json.load(fh)
p = s.get('permissions', {})
allow = p.get('allow', [])
ask = p.get('ask', [])
checks = [
    ('Bash(rm -rf .mypy_cache)' in allow,   'allow-mypy-exact'),
    ('Bash(rm -rf .pytest_cache)' in allow, 'allow-pytest-exact'),
    ('Bash(rm -rf .ruff_cache)' in allow,   'allow-ruff-exact'),
    (not any(r.startswith('Bash(rm -rf .') and r.endswith(':*)') for r in allow), 'no-prefix-cache-allow'),
    ('Bash(rm -rf:*)' in ask,               'ask-rail-intact'),
]
for okv, name in checks:
    print(('OK' if okv else 'BAD') + ' ' + name)
")
        bn=$(basename "$f")
        if echo "$perm_out" | grep -q "^BAD"; then
            fail "$bn cache-delete permission contract violated: $(echo "$perm_out" | grep '^BAD' | tr '\n' ' ')"
        else
            pass "$bn has the 3 exact cache-delete allows, no prefix cache allows, and the rm -rf ask rail"
        fi
    done
else
    pass "python3 not available — cache-delete permission test skipped (not a failure)"
fi

# The rules guidance must exist so agents reach for flags, not rm -rf.
assert_contains "$REPO_ROOT/rules/python-style.md" "mypy --no-incremental"  "python-style documents the mypy cache flag"
assert_contains "$REPO_ROOT/rules/python-style.md" "pytest --cache-clear"   "python-style documents the pytest cache flag"
assert_contains "$REPO_ROOT/rules/python-style.md" "ruff check --no-cache"  "python-style documents the ruff cache flag"
assert_contains "$REPO_ROOT/rules/workflow.md" "Ask-tier commands stall autonomous runs" "workflow.md warns that ask-tier commands stall /goal runs"

# ---------------------------------------------------------------------------
# Contract 6: E2E verified gate — canonical marker vocabulary
#
# The "E2E verified" gate string is the single source of truth for the
# workflow-gates hook regex. It's referenced in command checklists, rules
# docs, and the hook itself — contract these together so they can't drift.
# ---------------------------------------------------------------------------
start_test "E2E verified gate — canonical marker across files"

# The marker stem that the hook regex matches on — this is the single
# source of truth. Any other file that references the gate must use it.
CANONICAL_STEM="E2E verified"

# Both hook implementations must grep/match for the canonical stem
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh" "$CANONICAL_STEM" \
    "check-workflow-gates.sh references '$CANONICAL_STEM'"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "$CANONICAL_STEM" \
    "check-workflow-gates.ps1 references '$CANONICAL_STEM'"

# Workflow command checklists must use the canonical stem (checked or unchecked)
assert_contains "$REPO_ROOT/commands/new-feature.md" "$CANONICAL_STEM" \
    "new-feature.md checklist uses '$CANONICAL_STEM'"
assert_contains "$REPO_ROOT/commands/fix-bug.md" "$CANONICAL_STEM" \
    "fix-bug.md checklist uses '$CANONICAL_STEM'"

# The canonical N/A escape form must match exactly in both commands + rules
# Form: `- [x] E2E verified — N/A: <reason>` (em-dash "—", not double-hyphen)
CANONICAL_NA="E2E verified — N/A:"
assert_contains "$REPO_ROOT/commands/new-feature.md" "$CANONICAL_NA" \
    "new-feature.md uses canonical N/A form ('$CANONICAL_NA')"
assert_contains "$REPO_ROOT/commands/fix-bug.md" "$CANONICAL_NA" \
    "fix-bug.md uses canonical N/A form"
assert_contains "$REPO_ROOT/rules/testing.md" "$CANONICAL_NA" \
    "rules/testing.md uses canonical N/A form"

# rules/testing.md must be the canonical documentation — hook stderr
# points there, so the anchor must exist
assert_contains "$REPO_ROOT/rules/testing.md" "Canonical E2E gate vocabulary" \
    "rules/testing.md has the Canonical E2E gate vocabulary section"

# Negative assertion: only "E2E verified" is a valid gate marker — no other
# variant string should function as one anywhere in the project.
assert_not_contains "$REPO_ROOT/rules/testing.md" 'E2E use cases tested — N/A' \
    "rules/testing.md uses only the canonical 'E2E verified' marker"

# ---------------------------------------------------------------------------
# Contract 5: runtime preflight parity — both installers check the same files
# and document the same canonical guide. Prevents one platform from silently
# diverging.
# ---------------------------------------------------------------------------
start_test "Runtime preflight parity — setup.sh ↔ setup.ps1"

for file in ".python-version" ".nvmrc" "package.json" "multi-project-isolation.md"; do
    assert_contains "$REPO_ROOT/setup.sh" "$file" \
        "setup.sh references $file"
    assert_contains "$REPO_ROOT/setup.ps1" "$file" \
        "setup.ps1 references $file"
done

# The guide itself must exist (warnings point to it)
assert_file_exists "$REPO_ROOT/docs/guides/multi-project-isolation.md" \
    "canonical isolation guide exists"

# ---------------------------------------------------------------------------
# Contract 7: Soft "ask Claude to reconcile" tip + upgrade-summary parity
#
# Both installers must ship the same end-of-summary soft tip AND the same four
# boolean-gated final-summary variants. Without this contract, setup.ps1 can
# silently diverge from setup.sh (bash tests don't execute PowerShell).
#
# 5.17: replaced the per-file inline "Template may have drifted ... git diff
# --no-index" hint (cry-wolf — fired every upgrade regardless of actual drift)
# with a single end-of-summary soft tip that recommends the full Variant B
# "ask Claude to reconcile" prompt (matches the migration script's wording,
# including the @CONTINUITY.md dangling-import cleanup clause).
# ---------------------------------------------------------------------------
start_test "Soft reconcile tip + upgrade-summary parity"

SETUP_SH="$REPO_ROOT/setup.sh"
SETUP_PS1="$REPO_ROOT/setup.ps1"

# (i) Legacy cry-wolf drift-hint string MUST be absent from both installers
# (5.17 regression guard). The literal "Template may have drifted" must not
# appear anywhere in setup.{sh,ps1} — including comments — to make the regression
# guard unambiguous. Comments referencing the legacy hint use a paraphrased form.
assert_not_contains "$SETUP_SH"  "Template may have drifted" \
    "setup.sh does NOT contain legacy 'Template may have drifted' cry-wolf hint (5.17)"
assert_not_contains "$SETUP_PS1" "Template may have drifted" \
    "setup.ps1 does NOT contain legacy 'Template may have drifted' cry-wolf hint (5.17)"

# (i-bis) Drift-hint helpers must be removed (no orphaned definitions or callsites)
assert_not_contains "$SETUP_SH"  "print_template_drift_hint" \
    "setup.sh does NOT contain print_template_drift_hint helper or callsites (5.17)"
assert_not_contains "$SETUP_PS1" "Write-TemplateDriftHint" \
    "setup.ps1 does NOT contain Write-TemplateDriftHint helper or callsites (5.17)"

# (ii) Template filenames referenced
# Post PR #2: CONTINUITY.template.md no longer ships, so it must NOT be
# referenced from setup.{sh,ps1}. CLAUDE.template.md remains the source for
# the preserved-CLAUDE soft reconcile tip.
assert_contains     "$SETUP_SH"  "CLAUDE.template.md"      "setup.sh references CLAUDE.template.md"
assert_not_contains "$SETUP_SH"  "CONTINUITY.template.md"  "setup.sh does NOT reference CONTINUITY.template.md (deleted in PR #2)"
assert_contains     "$SETUP_PS1" "CLAUDE.template.md"      "setup.ps1 references CLAUDE.template.md"
assert_not_contains "$SETUP_PS1" "CONTINUITY.template.md"  "setup.ps1 does NOT reference CONTINUITY.template.md (deleted in PR #2)"

# (iii) Soft tip is present in both installers (5.17). The "Tip:" prefix +
# "ask Claude to reconcile" anchor are the user-visible identity of the new tip.
assert_contains "$SETUP_SH"  "ask Claude to reconcile your CLAUDE.md against the latest template" \
    "setup.sh contains soft 'ask Claude to reconcile' tip (5.17)"
assert_contains "$SETUP_PS1" "ask Claude to reconcile your CLAUDE.md against the latest template" \
    "setup.ps1 contains soft 'ask Claude to reconcile' tip (5.17)"

# (iv) Soft tip MUST include the full Variant B prompt with the @CONTINUITY.md
# dangling-import cleanup clause (matches migration script wording from 5.16).
# Codex-flagged P2 #1 from the v1 attempt: dropping this clause leaves users on
# a non-migrate path without instructions to remove the dangling import.
# 5.18: prompt expanded to enumerate ALL CONTINUITY reference types (tree
# diagrams, prose pointers, labels). Field bug origin: msai-v2 retained
# line-102 tree-diagram and line-212 prose-pointer references after running
# the v5.17 prompt because the prior wording only addressed the @-import line.
# Lock in the broader scope so it cannot silently regress.
assert_contains "$SETUP_SH"  "Reconcile my CLAUDE.md against" \
    "setup.sh soft tip includes Variant B 'Reconcile my CLAUDE.md against' prompt"
assert_contains "$SETUP_SH"  "@CONTINUITY.md import lines" \
    "setup.sh soft tip includes @CONTINUITY.md cleanup clause (5.18 wording)"
assert_contains "$SETUP_SH"  "dangling" \
    "setup.sh soft tip describes leftover CONTINUITY refs as dangling"
assert_contains "$SETUP_SH"  "scan the ENTIRE file" \
    "setup.sh soft tip instructs full-file scan (5.18)"
assert_contains "$SETUP_SH"  "File-tree diagrams" \
    "setup.sh soft tip names tree-diagram references as a target (5.18)"
assert_contains "$SETUP_SH"  "stale infrastructure references" \
    "setup.sh soft tip frames CONTINUITY refs as not-user-content (5.18)"
assert_contains "$SETUP_PS1" "Reconcile my CLAUDE.md against" \
    "setup.ps1 soft tip includes Variant B 'Reconcile my CLAUDE.md against' prompt"
assert_contains "$SETUP_PS1" "@CONTINUITY.md import lines" \
    "setup.ps1 soft tip includes @CONTINUITY.md cleanup clause (5.18 wording)"
assert_contains "$SETUP_PS1" "dangling" \
    "setup.ps1 soft tip describes leftover CONTINUITY refs as dangling"
assert_contains "$SETUP_PS1" "scan the ENTIRE file" \
    "setup.ps1 soft tip instructs full-file scan (5.18)"
assert_contains "$SETUP_PS1" "File-tree diagrams" \
    "setup.ps1 soft tip names tree-diagram references as a target (5.18)"
assert_contains "$SETUP_PS1" "stale infrastructure references" \
    "setup.ps1 soft tip frames CONTINUITY refs as not-user-content (5.18)"

# (v) "Full guide" reference uses absolute path semantics ($SCRIPT_DIR / $ScriptDir)
# so the link resolves to the Forge clone's docs/guides/upgrading.md, not the
# user's project (where the guide doesn't exist). Codex-flagged P2 #2 from v1.
assert_contains "$SETUP_SH"  '(Full guide: $SCRIPT_DIR/docs/guides/upgrading.md)' \
    "setup.sh 'Full guide' reference uses \$SCRIPT_DIR absolute path (5.17)"
assert_contains "$SETUP_PS1" '(Full guide: $ScriptDir/docs/guides/upgrading.md)' \
    "setup.ps1 'Full guide' reference uses \$ScriptDir absolute path (5.17)"

# (iv-bis) Migration prompt — both installers must surface --migrate (sh) /
# -Migrate (ps1) when a legacy CONTINUITY.md is detected.
assert_contains "$SETUP_SH"  "./setup.sh --migrate"  "setup.sh prompts --migrate for legacy CONTINUITY.md"
assert_contains "$SETUP_PS1" "-Migrate"              "setup.ps1 prompts -Migrate for legacy CONTINUITY.md"

# (v) Final-summary parity: three positive variants + negative legacy guard.
# Post PR #2: when CONTINUITY.md is preserved the variant prompts the user to
# run --migrate; when only CLAUDE.md is preserved the original "(user content)"
# wording stays.
BOTH_VARIANT_SH="Your CLAUDE.md and CONTINUITY.md were preserved (run --migrate to move content to the new structure)"
BOTH_VARIANT_PS1="Your CLAUDE.md and CONTINUITY.md were preserved (run -Migrate to move content to the new structure)"
CLAUDE_VARIANT="Your CLAUDE.md was preserved (user content)"
CONTINUITY_VARIANT_SH="Your CONTINUITY.md was preserved (run --migrate to move content to the new structure)"
CONTINUITY_VARIANT_PS1="Your CONTINUITY.md was preserved (run -Migrate to move content to the new structure)"
LEGACY_STRING="were not modified"

assert_contains "$SETUP_SH"  "$BOTH_VARIANT_SH"       "setup.sh has both-preserved final variant"
assert_contains "$SETUP_SH"  "$CLAUDE_VARIANT"        "setup.sh has only-CLAUDE final variant"
assert_contains "$SETUP_SH"  "$CONTINUITY_VARIANT_SH" "setup.sh has only-CONTINUITY final variant"
assert_not_contains "$SETUP_SH" "$LEGACY_STRING"      "setup.sh removed legacy 'were not modified'"

assert_contains "$SETUP_PS1" "$BOTH_VARIANT_PS1"       "setup.ps1 has both-preserved final variant"
assert_contains "$SETUP_PS1" "$CLAUDE_VARIANT"         "setup.ps1 has only-CLAUDE final variant"
assert_contains "$SETUP_PS1" "$CONTINUITY_VARIANT_PS1" "setup.ps1 has only-CONTINUITY final variant"
assert_not_contains "$SETUP_PS1" "$LEGACY_STRING"      "setup.ps1 removed legacy 'were not modified'"

# (v-bis) Sentinel-aware "already migrated" banner (v5.48). Once a prior
# --migrate / -Migrate has stamped the `<!-- forge:migrated DATE -->` sentinel into
# CLAUDE.md, CONTINUITY.md is preserved on disk but redundant — the banner drops the
# unsatisfiable "run --migrate" nag and points at removal (gated on the user
# confirming the content landed; NOT an unconditional "safe to delete"). Detection is
# gated on the CLAUDE.md sentinel only, so the migrated banner always implies CLAUDE.md
# was preserved — there is no reachable "CONTINUITY-only migrated" variant. The date is
# spliced via a guarded paren var (empty when the sentinel carries no valid date).
MIGRATED_BOTH_SH="Your CLAUDE.md was preserved. CONTINUITY.md already migrated"
MIGRATED_BOTH_PS1="Your CLAUDE.md was preserved. CONTINUITY.md already migrated"

assert_contains "$SETUP_SH"  "$MIGRATED_BOTH_SH"  "setup.sh has migrated removal banner (5.48)"
assert_contains "$SETUP_SH"  "content landed"     "setup.sh migrated banner gates removal on 'content landed' (5.48)"
assert_contains "$SETUP_PS1" "$MIGRATED_BOTH_PS1" "setup.ps1 has migrated removal banner (5.48)"
assert_contains "$SETUP_PS1" "content landed"     "setup.ps1 migrated banner gates removal on 'content landed' (5.48)"
# Guard against re-introducing an unconditional "safe to delete" assertion: the
# migrate helper can stamp the sentinel yet skip content (Codex P2, iter 3), so the
# banner must NOT promise unverified deletion safety.
assert_not_contains "$SETUP_SH"  "— safe to delete." "setup.sh banner does NOT assert unconditional safe-to-delete (5.48)"
assert_not_contains "$SETUP_PS1" "— safe to delete." "setup.ps1 banner does NOT assert unconditional safe-to-delete (5.48)"

# Both installers must detect the sentinel by the SAME bare prefix the migrate helper
# writes (SENTINEL_PREFIX) — pinned across all three files so a future rename of the
# wire-format string can't silently desync the installers from the helper and
# re-introduce the unsatisfiable nag.
MIGRATE_SH="$REPO_ROOT/scripts/migrate-continuity.sh"
MIGRATE_PS1="$REPO_ROOT/scripts/migrate-continuity.ps1"
assert_contains "$MIGRATE_SH"  "<!-- forge:migrated" "migrate-continuity.sh defines the forge:migrated sentinel prefix"
assert_contains "$SETUP_SH"    "<!-- forge:migrated" "setup.sh detects the same forge:migrated prefix (5.48)"
assert_contains "$SETUP_PS1"   "<!-- forge:migrated" "setup.ps1 detects the same forge:migrated prefix (5.48)"
# Both must guard the date with a YYYY-MM-DD check so a malformed sentinel can't
# splice a garbage date into the removal banner.
assert_contains "$SETUP_SH"  '[0-9]{4}-[0-9]{2}-[0-9]{2}' "setup.sh guards the migrated date format (5.48)"
assert_contains "$SETUP_PS1" '[0-9]{4}-[0-9]{2}-[0-9]{2}' "setup.ps1 guards the migrated date format (5.48)"

# ---------------------------------------------------------------------------
# Contract: Forge version stamp + advisory drift warning (v5.51) — parity.
# Both installers write `.claude/.forge-version` (project pin) + a machine stamp,
# read the version from the CHANGELOG top line, and warn (advisory) on mismatch.
# Both session-start hooks emit a direction-aware drift line. Advisory only:
# the version logic must NOT introduce a blocking exit/throw. PowerShell must use
# a numeric ([version]) compare, not a string compare (else 5.50 vs 5.9 reverses).
# ---------------------------------------------------------------------------
start_test "Forge version-stamp + drift advisory parity (setup + session-start, sh ↔ ps1)"
SS_SH="$REPO_ROOT/hooks/session-start.sh"
SS_PS1="$REPO_ROOT/hooks/session-start.ps1"
fv_ok=1
# Both installers reference the stamp file + read the CHANGELOG version line.
for f in "$SETUP_SH" "$SETUP_PS1"; do
    grep -qF -- ".forge-version" "$f" || { fail "$(basename "$f") missing .forge-version stamp write (5.51)"; fv_ok=0; }
    grep -qF -- 'CHANGELOG.md' "$f"   || { fail "$(basename "$f") missing CHANGELOG version source (5.51)"; fv_ok=0; }
done
# Both session-start hooks carry the drift advisory (stable phrase) + read the stamp.
for f in "$SS_SH" "$SS_PS1"; do
    grep -qF -- "pins Forge" "$f"      || { fail "$(basename "$f") missing drift advisory phrase 'pins Forge' (5.51)"; fv_ok=0; }
    grep -qF -- ".forge-version" "$f"  || { fail "$(basename "$f") missing .forge-version read (5.51)"; fv_ok=0; }
done
# PowerShell numeric compare (NOT string) in BOTH ps1 files — guards 5.50 vs 5.9.
for f in "$SETUP_PS1" "$SS_PS1"; do
    grep -qF -- "[version]" "$f" || { fail "$(basename "$f") must use a [version] numeric compare for the stamp (5.51)"; fv_ok=0; }
done
# Advisory-only guard: the drift hooks must never block — no real `exit 2` STATEMENT
# (line-anchored so the "exit 2 is advisory" explanatory comment doesn't false-match).
for f in "$SS_SH" "$SS_PS1"; do
    grep -qE '^[[:space:]]*exit[[:space:]]+2([[:space:]]|$)' "$f" && { fail "$(basename "$f") has a real 'exit 2' — drift signal must stay advisory (5.51)"; fv_ok=0; }
done
[ "$fv_ok" = "1" ] && pass "version-stamp + drift advisory present in all 4 files, numeric PS compare, advisory-only"

# ---------------------------------------------------------------------------
# Contract 4: CI template placeholder ↔ setup.sh substitution
# ---------------------------------------------------------------------------
start_test "__PLAYWRIGHT_DIR__ placeholder ↔ setup.sh substitution"

CI_TEMPLATE="$REPO_ROOT/templates/ci-workflows/e2e.yml"
assert_contains "$CI_TEMPLATE" "__PLAYWRIGHT_DIR__" \
    "CI template contains placeholder"
assert_contains "$REPO_ROOT/setup.sh" "__PLAYWRIGHT_DIR__" \
    "setup.sh references placeholder"
assert_contains "$REPO_ROOT/setup.ps1" "__PLAYWRIGHT_DIR__" \
    "setup.ps1 references placeholder"

# ---------------------------------------------------------------------------
# Contract: no migrated-pattern 'main' references in hooks/* outside the lib helper
#
# SCOPE: this catches ONLY the specific patterns drift-hygiene PR #1 migrated:
#   - `git merge-base main HEAD` (the original hardcoded form in check-state-updated)
#   - `origin/main` referenced as a literal default
#
# It intentionally does NOT catch every possible 'main' reference — e.g., the
# `git merge-base HEAD main` ordering used elsewhere in hooks/* is OUT OF SCOPE
# for PR #1 (different reverse-merge-base computation, different consumer). If a
# future PR migrates more hooks to the helper, tighten this regex (or split into
# per-pattern contracts) at that time.
# ---------------------------------------------------------------------------
start_test "no migrated-pattern 'main' references in hooks/* (outside hooks/lib/)"

HARDCODED=$(grep -rE "merge-base[[:space:]]+main[[:space:]]+HEAD|origin/main[^A-Za-z_]" \
    "$REPO_ROOT/hooks/" 2>/dev/null \
    | grep -v "^$REPO_ROOT/hooks/lib/" || true)

if [[ -z "$HARDCODED" ]]; then
    pass "no migrated-pattern 'main' references in hooks/* (outside lib/)"
else
    while IFS= read -r line; do
        fail "migrated-pattern 'main' detected (should use default-branch helper): $line"
    done <<< "$HARDCODED"
fi

# ---------------------------------------------------------------------------
# Contract: DRIFT-PREFLIGHT-NEW blocks in new-feature.md and fix-bug.md byte-identical
# ---------------------------------------------------------------------------
start_test "DRIFT-PREFLIGHT-NEW blocks byte-identical across new-feature.md and fix-bug.md"

NF="$REPO_ROOT/commands/new-feature.md"
FB="$REPO_ROOT/commands/fix-bug.md"

for f in "$NF" "$FB"; do
    [ -f "$f" ] || { fail "missing command file: $f"; }
done

NF_NEW=$(sed -n '/^# DRIFT-PREFLIGHT-NEW-BEGIN/,/^# DRIFT-PREFLIGHT-NEW-END/p' "$NF")
FB_NEW=$(sed -n '/^# DRIFT-PREFLIGHT-NEW-BEGIN/,/^# DRIFT-PREFLIGHT-NEW-END/p' "$FB")

if [[ -z "$NF_NEW" ]] || [[ -z "$FB_NEW" ]]; then
    fail "DRIFT-PREFLIGHT-NEW markers missing from one or both command files"
elif [[ "$NF_NEW" == "$FB_NEW" ]]; then
    pass "DRIFT-PREFLIGHT-NEW blocks byte-identical"
else
    fail "DRIFT-PREFLIGHT-NEW blocks differ between new-feature.md and fix-bug.md"
    diff <(printf '%s' "$NF_NEW") <(printf '%s' "$FB_NEW") | head -10
fi

# ---------------------------------------------------------------------------
# Contract: DRIFT-PREFLIGHT-ALREADY blocks in new-feature.md and fix-bug.md byte-identical
# ---------------------------------------------------------------------------
start_test "DRIFT-PREFLIGHT-ALREADY blocks byte-identical across new-feature.md and fix-bug.md"

NF_AL=$(sed -n '/^# DRIFT-PREFLIGHT-ALREADY-BEGIN/,/^# DRIFT-PREFLIGHT-ALREADY-END/p' "$NF")
FB_AL=$(sed -n '/^# DRIFT-PREFLIGHT-ALREADY-BEGIN/,/^# DRIFT-PREFLIGHT-ALREADY-END/p' "$FB")

if [[ -z "$NF_AL" ]] || [[ -z "$FB_AL" ]]; then
    fail "DRIFT-PREFLIGHT-ALREADY markers missing from one or both command files"
elif [[ "$NF_AL" == "$FB_AL" ]]; then
    pass "DRIFT-PREFLIGHT-ALREADY blocks byte-identical"
else
    fail "DRIFT-PREFLIGHT-ALREADY blocks differ between new-feature.md and fix-bug.md"
    diff <(printf '%s' "$NF_AL") <(printf '%s' "$FB_AL") | head -10
fi

# ---------------------------------------------------------------------------
# Contract: session-start drift-warning string parity — .sh ↔ .ps1
#
# The drift warning injected into additionalContext is independently composed
# in session-start.sh and session-start.ps1. If the canonical phrasing
# diverges, Windows users see a different warning than macOS/Linux users —
# a silent cross-platform inconsistency. This contract asserts both files
# share the same canonical substrings so the user experience is identical.
# ---------------------------------------------------------------------------
start_test "session-start drift-warning string parity — .sh ↔ .ps1"

SS_SH="$REPO_ROOT/hooks/session-start.sh"
SS_PS1="$REPO_ROOT/hooks/session-start.ps1"

for f in "$SS_SH" "$SS_PS1"; do
    assert_file_exists "$f" "file exists: $f"
done

# Both files must contain the trailing structural phrase that ends the warning.
PULL_PHRASE="pull before starting work"
assert_contains "$SS_SH"  "$PULL_PHRASE" \
    "session-start.sh contains '$PULL_PHRASE'"
assert_contains "$SS_PS1" "$PULL_PHRASE" \
    "session-start.ps1 contains '$PULL_PHRASE'"

# Both files must contain the em-dash + structural phrase that precedes the count.
BEHIND_PHRASE="commits behind origin —"
assert_contains "$SS_SH"  "$BEHIND_PHRASE" \
    "session-start.sh contains '$BEHIND_PHRASE'"
assert_contains "$SS_PS1" "$BEHIND_PHRASE" \
    "session-start.ps1 contains '$BEHIND_PHRASE'"

# ---------------------------------------------------------------------------
# CONTINUITY-split contracts (PR #2)
# ---------------------------------------------------------------------------

# Helper — find a usable PowerShell runtime; skip parity test if none.
detect_pwsh() {
    if command -v pwsh >/dev/null 2>&1; then echo "pwsh"; return 0; fi
    if command -v powershell >/dev/null 2>&1; then echo "powershell"; return 0; fi
    if command -v powershell.exe >/dev/null 2>&1; then echo "powershell.exe"; return 0; fi
    return 1
}

# Helper — count CONTINUITY.md hits in a path that indicate an actual
# operational dependency on CONTINUITY.md (reading state from it, gating
# workflows on it, falling back to it). Excludes:
#   - Comment lines (sh `#`, ps1 `#`)
#   - User-facing message lines: echo / printf / Write-Output / Write-Host /
#     Write-Error / Write-Warning / [Console]::*::Write* — CONTINUITY.md
#     appearing inside a quoted string in these contexts is just a breadcrumb,
#     not a code path that depends on the file.
#   - Existence-probe gates: `[ -f / -e CONTINUITY.md ]`, `[[ -f / -e ... ]]`,
#     `Test-Path "CONTINUITY.md"` — these intentionally probe for the legacy
#     file ONLY to decide whether to print the migration breadcrumb. They are
#     part of the migration UX, not a state dependency.
#   - Allowlisted historical references in docs (CHANGELOG, upgrading guide,
#     troubleshooting migration section).
#
# What WILL be counted (and should fail the contract):
#   - `cat CONTINUITY.md`, `grep ... CONTINUITY.md`, `< CONTINUITY.md`
#   - `Get-Content CONTINUITY.md`, `Select-String ... CONTINUITY.md`
#   - any other code path that reads from or writes to CONTINUITY.md as state.
count_continuity_refs_excluding_allowlist() {
    local search_path="$1"
    grep -rn "CONTINUITY\.md" "$search_path" 2>/dev/null \
        | grep -vE ':(docs/CHANGELOG\.md|docs/guides/upgrading\.md|docs/troubleshooting\.md):' \
        | grep -vE ':[[:space:]]*#' \
        | grep -vE '(echo|printf|Write-Output|Write-Host|Write-Error|Write-Warning|\[Console\]::[A-Za-z]+\.Write[A-Za-z]*)' \
        | grep -vE '(\[[[:space:]]*!?[[:space:]]*-[fe][[:space:]]+"?CONTINUITY\.md"?[[:space:]]*\]|Test-Path[[:space:]]+"?CONTINUITY\.md"?)' \
        | wc -l | tr -d ' '
}

start_test "no-CONTINUITY-in-hooks"
hits=$(count_continuity_refs_excluding_allowlist "$REPO_ROOT/hooks")
assert_equals "$hits" "0" "no CONTINUITY.md references in hooks/"

start_test "no-CONTINUITY-in-commands"
hits=$(count_continuity_refs_excluding_allowlist "$REPO_ROOT/commands")
assert_equals "$hits" "0" "no CONTINUITY.md references in commands/"

start_test "no-CONTINUITY-in-rules-agents-settings"
total=0
for d in rules agents settings; do
    h=$(count_continuity_refs_excluding_allowlist "$REPO_ROOT/$d")
    total=$((total + h))
done
assert_equals "$total" "0" "no CONTINUITY.md references in rules/, agents/, settings/"

# AC-3 broadened — also cover root templates (Codex P1 finding).
start_test "no-CONTINUITY-in-root-templates"
total=0
for f in CLAUDE.template.md GLOBAL-CLAUDE.template.md state.template.md; do
    [ -f "$REPO_ROOT/$f" ] || continue
    # `grep -c` always prints a count to stdout; rc=1 when 0 matches.
    # Don't chain with `|| echo 0` — that produces double-output and breaks arith.
    n=$(grep -c "CONTINUITY\.md" "$REPO_ROOT/$f" 2>/dev/null)
    [ -z "$n" ] && n=0
    total=$((total + n))
done
assert_equals "$total" "0" "no CONTINUITY.md in root templates (CLAUDE.template.md, GLOBAL-CLAUDE.template.md, state.template.md)"

start_test "hooks-parity-missing-state"
ps_runner=$(detect_pwsh)
if [ -z "$ps_runner" ]; then
    pass "ℹ no PowerShell runtime found (pwsh / powershell / powershell.exe); skipping bash/PS parity test"
else
    scratch=$(mktemp -d)
    ( cd "$scratch" && git init -q )
    sh_out=$(cd "$scratch" && echo '{"tool_input":{"command":"git commit -m x"}}' | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" 2>&1)
    ps_out=$(cd "$scratch" && echo '{"tool_input":{"command":"git commit -m x"}}' | "$ps_runner" -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" 2>&1)
    assert_equals "$sh_out" "$ps_out" "bash and PS check-workflow-gates emit byte-equivalent missing-state breadcrumb"
    rm -rf "$scratch"

    # AC-4 broadened — also cover check-state-updated parity.
    scratch=$(mktemp -d)
    ( cd "$scratch" && git init -q )
    sh_out=$(cd "$scratch" && bash "$REPO_ROOT/hooks/check-state-updated.sh" < /dev/null 2>&1)
    ps_out=$(cd "$scratch" && "$ps_runner" -NoProfile -File "$REPO_ROOT/hooks/check-state-updated.ps1" < /dev/null 2>&1)
    assert_equals "$sh_out" "$ps_out" "bash and PS check-state-updated emit byte-equivalent missing-state breadcrumb"
    rm -rf "$scratch"

    # AC-4 malformed-file parity (state.md exists but missing Command field).
    scratch=$(mktemp -d)
    (
        cd "$scratch" && git init -q && mkdir -p .claude/local && cat > .claude/local/state.md <<'EOF'
# state without Command field
## Workflow
| Field | Value |
| Phase | 3 |
EOF
    )
    sh_out=$(cd "$scratch" && bash "$REPO_ROOT/hooks/check-state-updated.sh" < /dev/null 2>&1)
    ps_out=$(cd "$scratch" && "$ps_runner" -NoProfile -File "$REPO_ROOT/hooks/check-state-updated.ps1" < /dev/null 2>&1)
    assert_equals "$sh_out" "$ps_out" "bash and PS check-state-updated handle malformed state.md identically"
    rm -rf "$scratch"
fi

start_test "adr-template-canonical-5-sections"
headers=$(grep -E "^## " "$REPO_ROOT/docs/adr/template.md" | sort -u)
# Note: sort puts 'Consequences' before 'Considered' (e < i at position 5).
expected="## Consequences
## Considered Options
## Context
## Decision
## Status"
if [ "$headers" = "$expected" ]; then
    pass "ADR template has the canonical 5 sections"
else
    fail "ADR template headers don't match canonical 5: got '$headers'"
fi

start_test "adr-seed-files-canonical-5-sections"
all_ok=true
for f in "$REPO_ROOT"/docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    for h in "## Status" "## Context" "## Considered Options" "## Decision" "## Consequences"; do
        if ! grep -qF "$h" "$f"; then
            fail "$(basename "$f") missing $h"
            all_ok=false
        fi
    done
done
$all_ok && pass "all docs/adr/NNNN-*.md have the canonical 5 sections"

# AC-2 verification: state.template.md has the canonical schema headers.
start_test "state-template-canonical-schema"
required_headers=(
    "## Workflow"
    "### Checklist"
    "## State"
    "### Done"
    "### Now"
    "### Next"
    "### Deferred"
    "## Open Questions"
    "## Blockers"
    "## Update Rules"
)
all_ok=true
for h in "${required_headers[@]}"; do
    if ! grep -qF "$h" "$REPO_ROOT/state.template.md"; then
        fail "state.template.md missing canonical header: '$h'"
        all_ok=false
    fi
done
# Default Command value must be 'none'.
if grep -qE '\|\s*Command\s*\|\s*none\s*\|' "$REPO_ROOT/state.template.md"; then
    pass "state.template.md default Command is 'none'"
else
    fail "state.template.md default Command is not 'none' (AC-2 violation)"
fi
$all_ok && pass "state.template.md has all canonical schema headers (AC-2)"

# P2-7: bash/PS migration-helper parity. Run both migrate-continuity scripts
# on the same fixture, compare stdout + state.md + ADR file content. Skips
# gracefully when no PowerShell runtime is installed.
start_test "migration-parity-bash-vs-ps"
ps_runner=$(detect_pwsh)
if [ -z "$ps_runner" ]; then
    pass "ℹ no PowerShell runtime found; skipping migration bash/PS parity test"
else
    # Build a shared fixture directory layout. Both runs need identical inputs.
    make_fixture() {
        local d="$1"
        mkdir -p "$d/.claude/local"
        cp "$REPO_ROOT/state.template.md" "$d/.claude/local/state.md"
        cat > "$d/CONTINUITY.md" <<'EOF'
# CONTINUITY

## Goal

Build a thing.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| DB | Postgres | ACID |

## State

### Done (recent 2-3 only)

- 2026-04-01: shipped feature X
- 2026-04-02: shipped feature Y
- 2026-04-03: shipped feature Z

### Now

Working on the migration assistant.

### Next

- ship PR #2

EOF
        cat > "$d/CLAUDE.md" <<'EOF'
# CLAUDE.md - Test Project

## Project Overview

A test project.
EOF
    }

    sh_dir=$(mktemp -d)
    ps_dir=$(mktemp -d)
    make_fixture "$sh_dir"
    make_fixture "$ps_dir"

    sh_out=$(cd "$sh_dir" && bash "$REPO_ROOT/scripts/migrate-continuity.sh" 2>&1)
    ps_out=$(cd "$ps_dir" && "$ps_runner" -NoProfile -File "$REPO_ROOT/scripts/migrate-continuity.ps1" 2>&1)

    # Stdout: byte-equivalent.
    if [ "$sh_out" = "$ps_out" ]; then
        pass "bash and PS migrate-continuity emit byte-equivalent stdout"
    else
        fail "stdout differs between bash and PS migrate-continuity"
        diff <(printf '%s' "$sh_out") <(printf '%s' "$ps_out") | head -20
    fi

    # state.md content: byte-equivalent.
    if cmp -s "$sh_dir/.claude/local/state.md" "$ps_dir/.claude/local/state.md"; then
        pass "state.md content byte-equivalent across bash and PS"
    else
        fail "state.md content differs between bash and PS migrate-continuity"
        diff "$sh_dir/.claude/local/state.md" "$ps_dir/.claude/local/state.md" | head -20
    fi

    # Sentinel placement: line 1 of both state.md AND CLAUDE.md, in BOTH runs.
    for d in "$sh_dir" "$ps_dir"; do
        first_state=$(head -1 "$d/.claude/local/state.md")
        first_claude=$(head -1 "$d/CLAUDE.md")
        case "$first_state" in
            "<!-- forge:migrated "*"-->") : ;;
            *)  fail "sentinel NOT on line 1 of $d/.claude/local/state.md (got: $first_state)" ;;
        esac
        case "$first_claude" in
            "<!-- forge:migrated "*"-->") : ;;
            *)  fail "sentinel NOT on line 1 of $d/CLAUDE.md (got: $first_claude)" ;;
        esac
    done
    pass "sentinel on line 1 of state.md AND CLAUDE.md in both bash and PS runs"

    # ADR content: at least one ADR was created in both, and contents match.
    sh_adr=$(find "$sh_dir/docs/adr" -name "*-db.md" -o -name "*-database.md" 2>/dev/null | head -1)
    ps_adr=$(find "$ps_dir/docs/adr" -name "*-db.md" -o -name "*-database.md" 2>/dev/null | head -1)
    if [ -n "$sh_adr" ] && [ -n "$ps_adr" ]; then
        if cmp -s "$sh_adr" "$ps_adr"; then
            pass "ADR file content byte-equivalent across bash and PS"
        else
            fail "ADR file content differs between bash and PS"
            diff "$sh_adr" "$ps_adr" | head -20
        fi
    else
        fail "ADR file missing in one or both runs (sh: '$sh_adr', ps: '$ps_adr')"
    fi

    # CLAUDE.md content: byte-equivalent (Goal injection should produce same output).
    if cmp -s "$sh_dir/CLAUDE.md" "$ps_dir/CLAUDE.md"; then
        pass "CLAUDE.md content byte-equivalent after migration (bash vs PS)"
    else
        fail "CLAUDE.md content differs between bash and PS migrate-continuity"
        diff "$sh_dir/CLAUDE.md" "$ps_dir/CLAUDE.md" | head -20
    fi

    rm -rf "$sh_dir" "$ps_dir"
fi

# AC-2 byte-identical STATE-INIT contract: the bash block in commands/new-feature.md
# and commands/fix-bug.md between # STATE-INIT-BEGIN and # STATE-INIT-END markers
# must be byte-identical (mirrors the existing DRIFT-PREFLIGHT-NEW contract from PR #1).
start_test "state-init-block-byte-identical-across-commands"
extract_state_init() {
    awk '/^# STATE-INIT-BEGIN/{flag=1} flag{print} /^# STATE-INIT-END/{flag=0}' "$1"
}
nf_block=$(extract_state_init "$REPO_ROOT/commands/new-feature.md")
fb_block=$(extract_state_init "$REPO_ROOT/commands/fix-bug.md")
if [ -z "$nf_block" ]; then fail "STATE-INIT-BEGIN/END markers not found in commands/new-feature.md"
elif [ -z "$fb_block" ]; then fail "STATE-INIT-BEGIN/END markers not found in commands/fix-bug.md"
elif ! echo "$nf_block" | grep -q "state.md"; then fail "STATE-INIT block in new-feature.md doesn't reference state.md (sanity check)"
elif [ "$nf_block" = "$fb_block" ]; then pass "STATE-INIT block byte-identical across new-feature.md and fix-bug.md"
else fail "STATE-INIT block diverges between new-feature.md and fix-bug.md"
fi

# ---------------------------------------------------------------------------
# Contract: seed-on-create (state-continuity-roundtrip, v5.52)
# STATE-INIT must emit SEED_FROM_MAIN; step 2b must seed the narrative + write
# the seed snapshot via extract_foldable. Asserted in BOTH command files.
# ---------------------------------------------------------------------------
start_test "seed-on-create: SEED_FROM_MAIN sentinel + snapshot + extract_foldable present in both commands"
for f in "$NF" "$FB"; do
    bn=$(basename "$f")
    assert_contains "$f" "SEED_FROM_MAIN"                          "$bn STATE-INIT emits SEED_FROM_MAIN"
    assert_contains "$f" ".claude/local/.state-seed-snapshot.md"   "$bn references the seed snapshot path"
    assert_contains "$f" "extract_foldable"                        "$bn defines/uses extract_foldable"
    # Bind the promised seed behaviors (plan Unit 5): Now reset to empty + gate sections NOT seeded.
    assert_contains "$f" "empty placeholder"                       "$bn seed resets Now to its empty placeholder"
    assert_contains "$f" "gate sections are NOT seeded"            "$bn seed excludes gate sections"
done

# ---------------------------------------------------------------------------
# Contract: guarded fold-back (state-continuity-roundtrip, v5.52)
# finish-branch.md must fold narrative into main BEFORE worktree removal,
# guarded by the seed snapshot, section-scoped, fail-loud on divergence.
# ---------------------------------------------------------------------------
FBR="$REPO_ROOT/commands/finish-branch.md"
start_test "fold-back: guarded narrative fold present and ordered before worktree removal"
assert_contains "$FBR" "extract_foldable"               "finish-branch defines/uses extract_foldable"
assert_contains "$FBR" ".state-seed-snapshot.md"        "finish-branch reads the seed snapshot"
assert_contains "$FBR" "## State"                       "finish-branch fold names the State narrative section"
assert_contains "$FBR" "## Open Questions"              "finish-branch fold names Open Questions"
assert_contains "$FBR" "## Blockers"                    "finish-branch fold names Blockers"
# Ordering: the fold step text must appear BEFORE the `git worktree remove` line.
fold_line=$(grep -n "Fold continuity narrative" "$FBR" | head -1 | cut -d: -f1)
remove_line=$(grep -n "git worktree remove" "$FBR" | head -1 | cut -d: -f1)
if [ -n "$fold_line" ] && [ -n "$remove_line" ] && [ "$fold_line" -lt "$remove_line" ]; then
    pass "fold-back step precedes 'git worktree remove' ($fold_line < $remove_line)"
else
    fail "fold-back step must precede 'git worktree remove' (fold=$fold_line remove=$remove_line)"
fi
# Safety: fail-loud on divergence / missing, gate sections preserved, explicit STOP, structural guard.
assert_contains "$FBR" "FOLD_DIVERGED"                  "finish-branch fold handles divergence"
assert_contains "$FBR" "Do NOT replace"                 "finish-branch fold refuses overwrite on divergence"
assert_contains "$FBR" "STOP cleanup"                   "finish-branch fold STOPs cleanup on safe-stop (no fall-through to worktree remove)"
assert_contains "$FBR" "foldable_is_valid"              "finish-branch fold has the structural-validity guard"
# Bind to the actual gate-exclusion clause, not a coincidental ## Workflow heading elsewhere in the file.
assert_contains "$FBR" "Do NOT touch"                   "finish-branch fold action explicitly excludes the gate sections (Do NOT touch)"
assert_contains "$FBR" "## /goal session"              "finish-branch fold names the gate sections it must not touch"

# Byte-drift guard: the EXTRACT-FOLDABLE block must be identical (modulo indentation)
# across new-feature.md step 2b, fix-bug.md step 2b, and finish-branch.md 2.2b — a silent
# drift between the seed-snapshot extraction and the fold extraction breaks divergence detection.
start_test "EXTRACT-FOLDABLE block identical (indent-normalized) across the three command files"
norm_ef() { sed -n '/^[[:space:]]*# EXTRACT-FOLDABLE-BEGIN/,/^[[:space:]]*# EXTRACT-FOLDABLE-END/p' "$1" | sed 's/^[[:space:]]*//'; }
ef_nf=$(norm_ef "$NF"); ef_fb=$(norm_ef "$FB"); ef_fbr=$(norm_ef "$FBR")
if [ -z "$ef_nf" ]; then
    fail "EXTRACT-FOLDABLE markers missing from new-feature.md"
elif [ "$ef_nf" = "$ef_fb" ] && [ "$ef_nf" = "$ef_fbr" ]; then
    pass "EXTRACT-FOLDABLE block identical (indent-normalized) across all three command files"
else
    fail "EXTRACT-FOLDABLE block drifted across command files"
    diff <(printf '%s' "$ef_nf") <(printf '%s' "$ef_fbr") | head -10
fi

# Contract: state.template documents the round-trip (state-continuity-roundtrip, v5.52)
start_test "state.template documents the continuity round-trip"
STATE_TMPL="$REPO_ROOT/state.template.md"
assert_contains "$STATE_TMPL" "seed snapshot"  "state.template documents the seed snapshot"
assert_contains "$STATE_TMPL" "round-trip"     "state.template documents the round-trip"

# Contract: ADR 0008 exists for state continuity round-trip (v5.52)
start_test "ADR 0008 exists for state continuity round-trip"
assert_file_exists "$REPO_ROOT/docs/adr/0008-state-continuity-round-trip.md" "ADR 0008 present"

# AC-2b STATE-INIT block must NOT contain Bash writes under .claude/. The state.md
# init was moved off `cp`/`mkdir` to Read+Write tool calls because Bash writes under
# .claude/ unconditionally prompt (Claude Code built-in heuristic, regardless of
# permissions.allow). The Write tool is auto-approved by the v5.21 PermissionRequest
# hook on .claude/local/**. Re-introducing ANY Bash write under .claude/ would
# resurrect the permission prompt that this contract was added to prevent.
#
# This test enumerates all common write patterns. If a future regression invents
# a new way to write files (e.g., `dd of=...`, `python -c 'open(...)'`), we'll
# add it here when we see it.
start_test "state-init-block-has-no-bash-writes-under-dot-claude"
for cmd_file in "$REPO_ROOT/commands/new-feature.md" "$REPO_ROOT/commands/fix-bug.md"; do
    block=$(extract_state_init "$cmd_file")
    name=$(basename "$cmd_file")
    # Strip comment lines (which may legitimately mention `cp` to explain the
    # policy) and string-literal lines (e.g., `echo "STATE_TEMPLATE_NOT_FOUND_AT:..."`)
    # before grep'ing for actual command invocations.
    # ALSO join shell line continuations (trailing `\` then newline) so a wrapped
    # `cp "$T" \\\n  .claude/local/state.md` doesn't slip past the line-oriented regex.
    code=$(echo "$block" | grep -v '^[[:space:]]*#' | awk 'BEGIN{p=""} /\\$/{p=p substr($0,1,length($0)-1) " "; next} {print p $0; p=""}')
    found_violation=""
    # ALL Bash writes under .claude/ are banned. The Write tool creates missing
    # parent directories in one call (verified — see docs/adr/0006-write-tool-creates-missing-parents.md),
    # so step 2b's Read+Write path doesn't need a defensive mkdir.
    #
    # 1. File-creating/modifying commands (cp/mv/ln/install/dd/touch/tee/rm/rmdir/mkdir)
    #    followed by a path containing .claude/. The [^|&]* prevents matching
    #    across pipes and chains.
    if echo "$code" | grep -qE '(^|[[:space:]])(cp|mv|ln|install|dd|touch|tee|rm|rmdir|mkdir)[[:space:]][^|&]*\.claude/'; then
        found_violation="filesystem write command (cp/mv/ln/install/dd/touch/tee/rm/rmdir/mkdir) into .claude/"
    # 2. sed -i targeting .claude/ (in-place edit).
    elif echo "$code" | grep -qE '(^|[[:space:]])sed[[:space:]]+-i[^|&]*\.claude/'; then
        found_violation="sed -i targeting .claude/"
    # 3. Stdout/stderr redirect (>, >>, 2>) followed by ANY path containing
    #    .claude/. Permissive on what comes between the operator and .claude/
    #    so it covers all quoting forms: `> .claude/x`, `> "$VAR/.claude/x"`,
    #    and `> "$VAR"/.claude/x` (the close-quote-then-unquoted-path form).
    #    [^|&]* still stops at pipes/chains. Note: 2>&1 doesn't match (no .claude/).
    #    Anchor: (^|[[:space:]]) before [12]? — same as the cp/mv and sed regexes
    #    above. Without it, any literal `>` (e.g. inside `<placeholder>` syntax in
    #    prose) followed eventually by `.claude/` on the same line falsely matches.
    elif echo "$code" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^|&]*\.claude/'; then
        found_violation="stdout/stderr redirect to .claude/"
    fi
    if [ -n "$found_violation" ]; then
        fail "$name STATE-INIT block has Bash write under .claude/: $found_violation (would prompt — use Read+Write tools instead)"
    else
        pass "$name STATE-INIT block has no Bash writes under .claude/"
    fi
done

# AC-2c Self-test: the AC-2b regex catches the patterns it claims to. Without this,
# a typo in the regex would silently let regressions through. We feed the regex
# block synthetic violation lines and assert each matches.
start_test "state-init-write-detector-catches-known-bad-patterns"
synthetic_violations=(
    # File-creating/modifying commands (mkdir included — banned per ADR 0006)
    'cp $TEMPLATE .claude/local/state.md'
    'mv $TEMPLATE .claude/local/state.md'
    'ln -s $TEMPLATE .claude/local/state.md'
    'install -D $TEMPLATE .claude/local/state.md'
    'mkdir -p .claude/local'
    'touch .claude/local/state.md'
    'tee .claude/local/state.md < $TEMPLATE'
    'rm .claude/local/state.md'
    'rmdir .claude/local'
    'dd if=$TEMPLATE of=.claude/local/state.md'
    # sed -i in-place edit
    'sed -i "s/foo/bar/" .claude/local/state.md'
    # Redirect forms (each quoting variant the codex iter-2 review flagged)
    'cat $TEMPLATE > .claude/local/state.md'
    'cat $TEMPLATE >> .claude/local/state.md'
    'echo something > "$ROOT/.claude/local/state.md"'
    'echo something > "$ROOT"/.claude/local/state.md'
    'cmd 2> .claude/local/error.log'
)
detector_failures=0
for line in "${synthetic_violations[@]}"; do
    matched=""
    if echo "$line" | grep -qE '(^|[[:space:]])(cp|mv|ln|install|dd|touch|tee|rm|rmdir|mkdir)[[:space:]][^|&]*\.claude/'; then matched=1
    elif echo "$line" | grep -qE '(^|[[:space:]])sed[[:space:]]+-i[^|&]*\.claude/'; then matched=1
    elif echo "$line" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^|&]*\.claude/'; then matched=1
    fi
    if [ -z "$matched" ]; then
        fail "AC-2b detector missed known-bad pattern: $line"
        detector_failures=$((detector_failures+1))
    fi
done
[ $detector_failures -eq 0 ] && pass "AC-2b detector catches all ${#synthetic_violations[@]} synthetic violations"

# AC-2d Negative self-test: prose patterns that LOOK like they could trip the
# redirect regex (e.g. `<placeholder>` syntax with `.claude/` later in the line)
# must NOT match. Without the (^|[[:space:]]) anchor on the redirect regex,
# these false positives broke AC-2e. Locked in here so a future regex change
# that drops the anchor surfaces immediately.
start_test "state-init-write-detector-rejects-known-false-positives"
false_positives=(
    # Markdown placeholder syntax where `>` is preceded by alphanumerics,
    # not whitespace — appears legitimately in prose like Step 2b bullets.
    '`STATE_TEMPLATE_DOWNSTREAM_GITIGNORED:<parent_root>` → STOP. Edit `.claude/local/state.md`'
    'worktrees based on `origin/<default-branch>` reach a tree without any Forge files; commit `.claude/`'
)
fp_failures=0
for line in "${false_positives[@]}"; do
    if echo "$line" | grep -qE '(^|[[:space:]])(cp|mv|ln|install|dd|touch|tee|rm|rmdir|mkdir)[[:space:]][^|&]*\.claude/' \
       || echo "$line" | grep -qE '(^|[[:space:]])sed[[:space:]]+-i[^|&]*\.claude/' \
       || echo "$line" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^|&]*\.claude/'; then
        fail "AC-2d detector falsely matched non-violation: $line"
        fp_failures=$((fp_failures+1))
    fi
done
[ $fp_failures -eq 0 ] && pass "AC-2d detector rejects all ${#false_positives[@]} known false positives"

# AC-2e: the Step 2b prose section (after STATE-INIT-END through the next "###"
# subsection or "**Step 2c") must instruct the agent to use Read+Write tools and
# must NOT contain banned Bash write patterns targeting .claude/. Without this,
# someone could revert Step 2b to "cp template state.md" prose without tripping
# AC-2b (which only scans the fenced shell block).
start_test "state-init-step-2b-prose-uses-read-write-tools"
extract_step_2b() {
    # From STATE-INIT-END to the "Step 2c" line (exclusive on Step 2c)
    awk '
        /^# STATE-INIT-END/{flag=1; next}
        /^\*\*Step 2c/{flag=0}
        flag{print}
    ' "$1"
}
for cmd_file in "$REPO_ROOT/commands/new-feature.md" "$REPO_ROOT/commands/fix-bug.md"; do
    name=$(basename "$cmd_file")
    step2b=$(extract_step_2b "$cmd_file")
    if [ -z "$step2b" ]; then
        fail "$name: Step 2b region not found between STATE-INIT-END and Step 2c"
        continue
    fi
    # Positive: must mention Read + Write tools
    if ! echo "$step2b" | grep -q "\*\*Read\*\*"; then
        fail "$name Step 2b doesn't reference the Read tool"
        continue
    fi
    if ! echo "$step2b" | grep -q "\*\*Write\*\*"; then
        fail "$name Step 2b doesn't reference the Write tool"
        continue
    fi
    # Negative: must NOT contain banned write patterns near .claude/.
    # Join line continuations same as AC-2b. Use the SAME regexes as AC-2b
    # (without the backtick wrapper) so that plain-text Bash like
    # `1. Use cp "$TEMPLATE" .claude/local/state.md` is caught — backtick-only
    # matching missed those (codex iter-7 P2 fix).
    step2b_code=$(echo "$step2b" | awk 'BEGIN{p=""} /\\$/{p=p substr($0,1,length($0)-1) " "; next} {print p $0; p=""}')
    if echo "$step2b_code" | grep -qE '(^|[[:space:]])(cp|mv|ln|install|dd|touch|tee|rm|rmdir|mkdir)[[:space:]][^|&]*\.claude/'; then
        fail "$name Step 2b prose contains a banned write command targeting .claude/"
    elif echo "$step2b_code" | grep -qE '(^|[[:space:]])sed[[:space:]]+-i[^|&]*\.claude/'; then
        fail "$name Step 2b prose contains sed -i targeting .claude/"
    elif echo "$step2b_code" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^|&]*\.claude/'; then
        fail "$name Step 2b prose contains a redirect to .claude/"
    else
        pass "$name Step 2b prose uses Read+Write tools, no banned writes"
    fi
done

# ---------------------------------------------------------------------------
# Contract: codex-pty shim — env vars + issue refs + helper present
# Mirrors the cross-shim contract for openai/codex#19945 workaround.
# ---------------------------------------------------------------------------
start_test "codex-pty-shim contract: both .sh and .ps1 reference shared env vars + issue"
PTY_SH="$REPO_ROOT/hooks/lib/codex-pty.sh"
PTY_PS="$REPO_ROOT/hooks/lib/codex-pty.ps1"
PTY_HELPER="$REPO_ROOT/hooks/lib/codex-pty-helper.py"

for f in "$PTY_SH" "$PTY_PS" "$PTY_HELPER"; do
    assert_file_exists "$f" "shim file exists: $(basename "$f")"
done

# Both shim files must reference the env var contract by exact name
for f in "$PTY_SH" "$PTY_PS"; do
    name=$(basename "$f")
    assert_contains "$f" "CLAUDE_FORGE_CODEX_PTY_BYPASS" "$name references CLAUDE_FORGE_CODEX_PTY_BYPASS"
    assert_contains "$f" "CLAUDE_FORGE_CODEX_PTY_VIA_WSL" "$name references CLAUDE_FORGE_CODEX_PTY_VIA_WSL"
    assert_contains "$f" "openai/codex#19945" "$name header references openai/codex#19945"
done

# ---------------------------------------------------------------------------
# Contract: codex-pty callsite migration — no bare `codex exec` lines (start
# of line + whitespace) outside the shim files themselves and out-of-scope
# /research /plans dirs (which document codex usage as artifacts).
# ---------------------------------------------------------------------------
start_test "codex-pty-callsite contract: no bare 'codex exec' in fenced code blocks across templates"

violations=$(grep -REn '^[[:space:]]*codex exec\b' \
    "$REPO_ROOT/commands/" \
    "$REPO_ROOT/skills/" \
    "$REPO_ROOT/agents/" \
    "$REPO_ROOT/hooks/" 2>/dev/null \
    | grep -vE '(hooks/lib/codex-pty\.|hooks/lib/codex-pty-helper)' \
    | grep -vE '/research/|/plans/' \
    || true)

if [[ -z "$violations" ]]; then
    pass "no bare 'codex exec' in templates (all callsites migrated to shim)"
else
    fail "bare 'codex exec' found in templates (callsites must use the shim)"
    while IFS= read -r line; do
        echo "    $line" >&2
    done <<<"$violations"
fi

# ---------------------------------------------------------------------------
# Contract: codex-pty council references — both council files must reference
# the shim path at least once (proves the migration was applied).
# ---------------------------------------------------------------------------
start_test "codex-pty-council contract: SKILL.template.md and peer-review-protocol.md reference the shim"

COUNCIL_SKILL="$REPO_ROOT/skills/council/SKILL.template.md"
COUNCIL_PROTOCOL="$REPO_ROOT/skills/council/references/peer-review-protocol.md"

for f in "$COUNCIL_SKILL" "$COUNCIL_PROTOCOL"; do
    assert_file_exists "$f" "council file exists: $(basename "$f")"
    assert_contains "$f" "codex-pty.sh" "$(basename "$f") references codex-pty.sh shim"
done

# ---------------------------------------------------------------------------
# Contract: --output-last-message flag — peer-review-protocol.md must use the
# flag in its codex exec invocations so the chairman/advisor response is
# captured to a clean file (avoids the prior misread where Claude couldn't
# extract the response from the verbose stdout capture and falsely reported
# "exited without producing analysis"). v5.27.
# ---------------------------------------------------------------------------
start_test "codex-pty-olm contract: peer-review-protocol.md uses --output-last-message"

assert_contains "$COUNCIL_PROTOCOL" "output-last-message" \
    "peer-review-protocol.md uses --output-last-message flag"

# ---------------------------------------------------------------------------
# Contract: setup.sh + setup.ps1 install the shim files via explicit copy_file
# calls (per plan §2.5 — no auto-traversal).
# ---------------------------------------------------------------------------
start_test "codex-pty-setup contract: setup.sh and setup.ps1 install the shim files"

SETUP_SH="$REPO_ROOT/setup.sh"
SETUP_PS="$REPO_ROOT/setup.ps1"

assert_contains "$SETUP_SH" "codex-pty.sh" "setup.sh installs codex-pty.sh"
assert_contains "$SETUP_SH" "codex-pty-helper.py" "setup.sh installs codex-pty-helper.py"
assert_contains "$SETUP_SH" "codex-pty.ps1" "setup.sh installs codex-pty.ps1 (cross-platform parity)"
assert_contains "$SETUP_PS" "codex-pty.ps1" "setup.ps1 installs codex-pty.ps1"
assert_contains "$SETUP_PS" "codex-pty.sh" "setup.ps1 installs codex-pty.sh (cross-platform parity)"
assert_contains "$SETUP_PS" "codex-pty-helper.py" "setup.ps1 installs codex-pty-helper.py"

# ---------------------------------------------------------------------------
# Contract: FORGE_GOAL_EVIDENCE producer/consumer/schema
#
# (1) Producer markers: both build-evidence.{sh,ps1} contain BEGIN/END markers.
# (2) Consumer ordering: check-state-updated.{sh,ps1} calls build-evidence
#     BEFORE the stop_hook_active early-return (text-order check).
# (3) Schema shape: the producer emits all required top-level JSON keys.
#     Using a string-match on the literal token as it appears in source
#     (same form for both .sh printf strings and .ps1 quoted literals).
# ---------------------------------------------------------------------------
start_test "FORGE_GOAL_EVIDENCE producer/consumer/schema contract"

# (1) Producer markers
for f in "$REPO_ROOT/hooks/build-evidence.sh" "$REPO_ROOT/hooks/build-evidence.ps1"; do
    assert_file_exists "$f" "producer exists: $(basename "$f")"
    assert_contains "$f" "FORGE_GOAL_EVIDENCE_BEGIN" "$(basename "$f") begin marker"
    assert_contains "$f" "FORGE_GOAL_EVIDENCE_END"   "$(basename "$f") end marker"
done

# (2) Consumer ordering: build-evidence invocation must appear BEFORE the
#     stop_hook_active early-return in check-state-updated.{sh,ps1}.
#
#     The early-return takes different forms in each file:
#       .sh  — `[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0` (uppercase var, after parsing)
#       .ps1 — `if ($data.stop_hook_active -eq $true) {`
#     We match on those exact guard patterns (not the comment that mentions
#     stop_hook_active in lowercase, which appears in the parsing block and
#     would give a false earlier line number via tail -1).
#     Note: bash 3.2 (macOS) has no associative arrays — use explicit if/else.
for f in "$REPO_ROOT/hooks/check-state-updated.sh" "$REPO_ROOT/hooks/check-state-updated.ps1"; do
    [ -f "$f" ] || { fail "consumer missing: $f"; continue; }
    case "$(basename "$f")" in
        check-state-updated.sh)  guard_pattern='STOP_HOOK_ACTIVE.*exit 0' ;;
        check-state-updated.ps1) guard_pattern='data\.stop_hook_active' ;;
        *) fail "unexpected consumer file: $(basename "$f")"; continue ;;
    esac
    EVIDENCE_LINE=$(grep -n 'build-evidence' "$f" | head -1 | cut -d: -f1)
    EXIT_LINE=$(grep -En "$guard_pattern" "$f" | tail -1 | cut -d: -f1)
    if [ -n "$EVIDENCE_LINE" ] && [ -n "$EXIT_LINE" ] && [ "$EVIDENCE_LINE" -lt "$EXIT_LINE" ]; then
        pass "$(basename "$f") invokes build-evidence BEFORE stop_hook_active early-return"
    else
        fail "$(basename "$f") consumer ordering wrong (build-evidence line $EVIDENCE_LINE not before early-return line $EXIT_LINE)"
    fi
done

# (3) Schema shape — producer emits required top-level JSON keys.
#     Each key appears as a literal substring in both .sh (printf format string)
#     and .ps1 (PowerShell string concatenation literal). The grep is
#     straightforward because the source uses the exact key token in both files.
REQUIRED_KEYS=(
    '"type":"forge_goal_evidence"'
    '"schema_version":'
    '"produced_at_unix":'
    '"session_nonce"'
    '"pr_ready":'
    '"all_gates_green":'
    '"reviewer_gate":{'
    '"e2e_report":{'
    '"pr_state":{'
    '"pr_authorization":{'
    '"progress_fingerprint":'
)
# Note: "session_nonce" uses the string token without a colon because both
# producers construct it via a helper function (json_str_field / Build-JsonStringField)
# that never appears as the literal "session_nonce": in source. The shorter form
# is sufficient to assert the field exists in the schema.
for key in "${REQUIRED_KEYS[@]}"; do
    assert_contains "$REPO_ROOT/hooks/build-evidence.sh"  "$key" "schema key in build-evidence.sh: $key"
    assert_contains "$REPO_ROOT/hooks/build-evidence.ps1" "$key" "schema key in build-evidence.ps1: $key"
done

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — workflow commands have their checkpoint sections
# ---------------------------------------------------------------------------
start_test "Layer 2 — /new-feature has PRD-Complete Checkpoint with correct content"

NF="$REPO_ROOT/commands/new-feature.md"
assert_file_exists "$NF" "commands/new-feature.md exists"
assert_contains "$NF" "PRD-Complete Checkpoint" "new-feature.md has PRD-complete checkpoint section"
assert_contains "$NF" "FORGE_GOAL_EVIDENCE" "new-feature.md references Layer 1 evidence markers in condition"
assert_contains "$NF" "session_nonce" "new-feature.md references session_nonce in condition"
assert_contains "$NF" "pr_ready=true" "new-feature.md uses pr_ready=true in condition"
assert_contains "$NF" "AskUserQuestion" "new-feature.md references AskUserQuestion at PR-create gate"
# P1.1: all_gates_green must NOT appear in the /goal condition string
if grep -q 'all_gates_green=true' "$NF"; then
    fail "new-feature.md /goal condition contains all_gates_green=true (unsatisfiable — must be absent)"
else
    pass "new-feature.md /goal condition does NOT contain all_gates_green=true (correct)"
fi
# P1.4: REPLACE semantics documented
assert_contains "$NF" "REPLACE" "new-feature.md documents REPLACE semantics for /goal session and PR auth"

start_test "Layer 2 — /fix-bug has Plan-Approved Checkpoint at Phase 3→4 boundary"

FB="$REPO_ROOT/commands/fix-bug.md"
assert_file_exists "$FB" "commands/fix-bug.md exists"
assert_contains "$FB" "Plan-Approved Checkpoint" "fix-bug.md has Plan-Approved checkpoint (not PRD-complete)"
# P1.3: fix-bug must NOT use PRD-complete naming
if grep -q "PRD-Complete Checkpoint" "$FB"; then
    fail "fix-bug.md has PRD-Complete Checkpoint section (incorrect — must be Plan-Approved)"
else
    pass "fix-bug.md does NOT have PRD-Complete Checkpoint naming (correct)"
fi
assert_contains "$FB" "Phase 3" "fix-bug.md checkpoint references Phase 3"
assert_contains "$FB" "Phase 4" "fix-bug.md checkpoint references Phase 4 boundary"
assert_contains "$FB" "session_nonce" "fix-bug.md references session_nonce in condition"
assert_contains "$FB" "pr_ready=true" "fix-bug.md uses pr_ready=true in condition"
# P1.1: all_gates_green must NOT appear in the /goal condition string
if grep -q 'all_gates_green=true' "$FB"; then
    fail "fix-bug.md /goal condition contains all_gates_green=true (unsatisfiable — must be absent)"
else
    pass "fix-bug.md /goal condition does NOT contain all_gates_green=true (correct)"
fi
# P1.4: REPLACE semantics documented
assert_contains "$FB" "REPLACE" "fix-bug.md documents REPLACE semantics for /goal session and PR auth"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — rules/workflow.md has council-during-/goal rule
# ---------------------------------------------------------------------------
start_test "Layer 2 — rules/workflow.md has council-during-/goal trigger rule"

WF_RULE="$REPO_ROOT/rules/workflow.md"
assert_file_exists "$WF_RULE" "rules/workflow.md exists"
assert_contains "$WF_RULE" "Council During" "council section header present"
assert_contains "$WF_RULE" "PR creation authorization" "PR-creation pause exception documented"
assert_contains "$WF_RULE" "/council" "invokes /council for non-PR doubts"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — state.template.md has new section docs (no empty instance)
# ---------------------------------------------------------------------------
start_test "Layer 2 — state.template.md documents /goal session + PR authorization conventions"

ST_TPL="$REPO_ROOT/state.template.md"
assert_file_exists "$ST_TPL" "state.template.md exists"
assert_contains "$ST_TPL" "## /goal session" "/goal session section documented"
assert_contains "$ST_TPL" "## PR authorization" "PR authorization section documented"
assert_contains "$ST_TPL" "Code review iteration" "reviewer-iteration head-SHA convention documented"
assert_contains "$ST_TPL" "REPLACE semantics" "REPLACE semantics documented in state.template.md"
# P1.2: state.template must NOT have a pre-populated empty /goal session table
# (The section documents the FORMAT, not an empty instance.)
# Check that the nonce row, if present, does not have an empty value placeholder
# that would cause the Bash guard to find a block with no actual nonce.
if grep -E '^\|\s*nonce\s*\|\s*\|\s*$' "$ST_TPL" > /dev/null 2>&1; then
    fail "state.template.md has empty nonce row (would cause false-active /goal session detection)"
else
    pass "state.template.md does NOT have empty nonce row (correct — format documented, not instantiated)"
fi

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — check-workflow-gates has PR-auth guard
# ---------------------------------------------------------------------------
start_test "Layer 2 — check-workflow-gates.{sh,ps1} have PR-auth guard with consistent key strings"

# Each guard file must reference the canonical auth line string and the nonce variable
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "PR creation authorized" \
    "check-workflow-gates.sh references PR auth line"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "PR creation authorized" \
    "check-workflow-gates.ps1 references PR auth line"

# P1.2: Bash guard must use non-empty GOAL_NONCE as "active" definition
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh" 'if [ -n "$GOAL_NONCE"' \
    "Bash guard checks non-empty GOAL_NONCE (not just block presence)"
# PS guard must also use non-empty goalNonce
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" 'if ($goalNonce)' \
    "PS guard checks non-empty goalNonce"

# ---------------------------------------------------------------------------
# Contract: workflow-gate-semantics — no-code carve-out present in BOTH hooks
# (the carve-out closes the integrity hole; it must never drift to one platform)
# ---------------------------------------------------------------------------
start_test "carve-out — both hooks have the no-code carve-out + docs predicate"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "No-code carve-out" \
    "check-workflow-gates.sh documents the no-code carve-out"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "No-code carve-out" \
    "check-workflow-gates.ps1 documents the no-code carve-out"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "git diff --cached --name-status --no-renames" \
    "Bash carve-out uses staged --name-status --no-renames (rename-safe)"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "git diff --cached --name-status --no-renames" \
    "PS carve-out uses staged --name-status --no-renames (rename-safe)"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "_is_doc_path" \
    "Bash carve-out has the _is_doc_path predicate"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "Test-IsDocPath" \
    "PS carve-out has the Test-IsDocPath predicate"

# ---------------------------------------------------------------------------
# Contract: workflow-gate-semantics — malformed-loop-line block in BOTH hooks
# ---------------------------------------------------------------------------
start_test "malformed-gate — both hooks block a checked loop line that is neither PASS nor N/A"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "malformed '[x] Code review loop' line" \
    "check-workflow-gates.sh blocks malformed Code review loop line"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "malformed '[x] Code review loop' line" \
    "check-workflow-gates.ps1 blocks malformed Code review loop line"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  "malformed '[x] Plan review loop' line" \
    "check-workflow-gates.sh blocks malformed Plan review loop line"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" "malformed '[x] Plan review loop' line" \
    "check-workflow-gates.ps1 blocks malformed Plan review loop line"

# ---------------------------------------------------------------------------
# Contract: E2E checked-line scan is ANCHORED in both hooks (bug c parity)
# The ps1 mirror previously scanned the whole workflow block with a loose match;
# both must use the anchored `^\s*- [x] E2E verified` form. Static guard so a
# pwsh-less environment still catches a regression of the PowerShell anchoring.
# ---------------------------------------------------------------------------
start_test "E2E scan — both hooks use the anchored '- [x] E2E verified' match"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh"  '^\s*- \[x\]\s+E2E verified' \
    "check-workflow-gates.sh anchors the E2E checked-line scan"
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" '^\s*- \[x\]\s+E2E verified' \
    "check-workflow-gates.ps1 anchors the E2E checked-line scan (parity)"
# And the ps1 scans the scoped checklist, not the whole workflow block, for E2E.
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" 'foreach ($line in $checklistLines)' \
    "check-workflow-gates.ps1 scopes the E2E scan to the checklist"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — stuck-detection in check-state-updated
# ---------------------------------------------------------------------------
start_test "Layer 2 — check-state-updated.{sh,ps1} have stuck-detection code"

assert_contains "$REPO_ROOT/hooks/check-state-updated.sh"  "FORGE_GOAL_STUCK_WARNING" \
    "check-state-updated.sh emits FORGE_GOAL_STUCK_WARNING"
assert_contains "$REPO_ROOT/hooks/check-state-updated.ps1" "FORGE_GOAL_STUCK_WARNING" \
    "check-state-updated.ps1 emits FORGE_GOAL_STUCK_WARNING"
assert_contains "$REPO_ROOT/hooks/check-state-updated.sh"  "forge-goal-stuck-count" \
    "check-state-updated.sh references the counter file"
assert_contains "$REPO_ROOT/hooks/check-state-updated.ps1" "forge-goal-stuck-count" \
    "check-state-updated.ps1 references the counter file"

# ---------------------------------------------------------------------------
# Runtime parity contract: Bash vs PS guards for nonce-mismatch + empty-inactive
# (conditional on pwsh availability)
# ---------------------------------------------------------------------------
start_test "Layer 2 — PS guard runtime parity with Bash guard (nonce-mismatch + empty-inactive; skipped if pwsh absent)"

if command -v pwsh > /dev/null 2>&1; then
    # Test 1: nonce mismatch → both guards must exit 2 with "nonce mismatch" in stderr
    scratch=$(scratch_dir parity-nonce-mismatch)
    mkdir -p "$scratch/.claude/local"
    cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | correct-session-nonce |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — `2026-05-16T10:15:00Z` — nonce=`stale-different-nonce` — head=`abc123`
EOF

    (
        cd "$scratch"
        INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > "$scratch/.bash_out" 2>&1
        echo $? > "$scratch/.bash_exit"
        echo "$INPUT" | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" > "$scratch/.ps_out" 2>&1
        echo $? > "$scratch/.ps_exit"
    )

    BASH_EXIT=$(cat "$scratch/.bash_exit")
    PS_EXIT=$(cat "$scratch/.ps_exit")
    assert_equals "$BASH_EXIT" "2" "Bash guard exits 2 on nonce mismatch"
    assert_equals "$PS_EXIT" "2" "PS guard exits 2 on nonce mismatch (parity)"
    assert_contains "$scratch/.bash_out" "nonce mismatch" "Bash guard mentions nonce mismatch"
    assert_contains "$scratch/.ps_out" "nonce mismatch" "PS guard mentions nonce mismatch (parity)"

    # Test 2: empty nonce row → both guards treat session as INACTIVE (exit 0)
    scratch2=$(scratch_dir parity-empty-nonce)
    mkdir -p "$scratch2/.claude/local"
    cat > "$scratch2/.claude/local/state.md" <<'EOF'
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

- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

    (
        cd "$scratch2"
        INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > "$scratch2/.bash_out" 2>&1
        echo $? > "$scratch2/.bash_exit"
        echo "$INPUT" | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" > "$scratch2/.ps_out" 2>&1
        echo $? > "$scratch2/.ps_exit"
    )

    BASH_EXIT2=$(cat "$scratch2/.bash_exit")
    PS_EXIT2=$(cat "$scratch2/.ps_exit")
    assert_equals "$BASH_EXIT2" "0" "Bash guard exits 0 on empty nonce (INACTIVE)"
    assert_equals "$PS_EXIT2" "0" "PS guard exits 0 on empty nonce (INACTIVE, parity)"

else
    pass "pwsh not available — PS runtime parity tests skipped (not a failure)"
fi

# ---------------------------------------------------------------------------
# Stale-duplicate auth line contract: Bash guard uses LAST auth line
# ---------------------------------------------------------------------------
start_test "Layer 2 — Bash guard uses LAST PR authorization line when multiple present"

if command -v git > /dev/null 2>&1; then
    scratch=$(scratch_dir stale-dup-contract)
    mkdir -p "$scratch/.claude/local"
    (
        cd "$scratch"
        git init -q -b main >/dev/null 2>&1 || git init -q >/dev/null 2>&1
        git config user.email "t@t"
        git config user.name "t"
        echo x > a; git add a; git commit -qm init >/dev/null 2>&1
        HEAD_SHA=$(git rev-parse HEAD)

        cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | current-nonce |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — \`2026-05-16T09:00:00Z\` — nonce=\`stale-nonce\` — head=\`stalehash\`
- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`current-nonce\` — head=\`$HEAD_SHA\`

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
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > .bash_out 2>&1
        echo $? > .bash_exit
    )

    BASH_EXIT=$(cat "$scratch/.bash_exit")
    assert_equals "$BASH_EXIT" "0" "Bash guard uses LAST auth line (matching) and ALLOWS (exit 0)"
else
    pass "git not available — stale-duplicate contract test skipped"
fi

# ---------------------------------------------------------------------------
# Contract: per-iter clean-line vocabulary parity across files
# state.template.md, rules/workflow.md, commands/new-feature.md, commands/fix-bug.md,
# hooks/check-workflow-gates.{sh,ps1}, hooks/build-evidence.{sh,ps1} must all
# contain the identical canonical stem for the per-iter clean lines, either
# in documentation prose or in error-message/comment text. The hooks use split
# greps for matching (so the literal stem isn't in their PARSING code), but it
# appears in their error messages and in the canonical-stem comment block of
# compute_plan_review_gate.
# ---------------------------------------------------------------------------
start_test "Per-iter clean-line vocabulary parity"

# Canonical stems — changing either side requires changing both files +
# updating this contract.
PLAN_STEM='Plan review iteration .* — codex clean — plan='
CODE_STEM='Code review iteration .* — codex clean — head='

ok=1
for f in state.template.md rules/workflow.md commands/new-feature.md commands/fix-bug.md \
         hooks/check-workflow-gates.sh hooks/check-workflow-gates.ps1 \
         hooks/build-evidence.sh hooks/build-evidence.ps1; do
    grep -qE "$PLAN_STEM" "$REPO_ROOT/$f" \
        || { fail "$f missing canonical Plan review per-iter stem"; ok=0; }
    grep -qE "$CODE_STEM" "$REPO_ROOT/$f" \
        || { fail "$f missing canonical Code review per-iter stem"; ok=0; }
done
[ "$ok" = "1" ] && pass "8 files carry both canonical stems"

# ---------------------------------------------------------------------------
# Contract: "Ground Your Claims" rule parity across its three shipping copies
# ---------------------------------------------------------------------------
# The rule lives canonically in rules/critical-rules.md (sibling of CHALLENGE ME
# / NO BUGS LEFT BEHIND), is mirrored as a headline policy in CLAUDE.template.md
# (matching the No Bugs Left Behind pattern), and ships globally via
# GLOBAL-CLAUDE.template.md. Duplicated prose drifts silently — bind the copies
# on a shared title stem + an exact link phrase so an edit to one fails CI until
# the others follow.
start_test "Ground Your Claims rule parity (critical-rules ↔ CLAUDE template ↔ global)"

# Case-insensitive: critical-rules.md uses the ALL-CAPS bullet convention
# (GROUND YOUR CLAIMS), the templates use Title-Case headings.
GYC_STEM='ground your claims'
GYC_LINK='Confident guessing is a defect'
ok=1
for f in rules/critical-rules.md CLAUDE.template.md GLOBAL-CLAUDE.template.md; do
    grep -qiE "$GYC_STEM" "$REPO_ROOT/$f" \
        || { fail "$f missing 'Ground Your Claims' rule stem"; ok=0; }
    grep -qF "$GYC_LINK" "$REPO_ROOT/$f" \
        || { fail "$f missing canonical '$GYC_LINK' link phrase"; ok=0; }
done
[ "$ok" = "1" ] && pass "3 files carry the Ground Your Claims rule + link phrase"

# ---------------------------------------------------------------------------
# Contract: Developer Demo block parity + Gate-2 diagram-honesty rule
# ---------------------------------------------------------------------------
# The PR-body "Developer Demo" template is INLINED into both workflow commands
# (not a separate templates/ file — that wouldn't ship downstream via setup.sh).
# The two copies live between <!-- DEV-DEMO-BEGIN --> / <!-- DEV-DEMO-END -->
# sentinels and MUST be byte-identical (same pattern as the DRIFT-PREFLIGHT
# blocks). The block must carry its load-bearing stems, and the Gate-2
# diagram-edge honesty rule must appear in commands/codex.md + rules/workflow.md.
start_test "Developer Demo block parity (new-feature ↔ fix-bug) + Gate-2 honesty rule"

extract_demo_block() {
    awk '/<!-- DEV-DEMO-BEGIN/{f=1} f{print} /<!-- DEV-DEMO-END/{f=0}' "$1"
}
NF_DEMO=$(extract_demo_block "$REPO_ROOT/commands/new-feature.md")
FB_DEMO=$(extract_demo_block "$REPO_ROOT/commands/fix-bug.md")

ok=1
[ -n "$NF_DEMO" ] || { fail "commands/new-feature.md missing the DEV-DEMO block (sentinels not found)"; ok=0; }
[ -n "$FB_DEMO" ] || { fail "commands/fix-bug.md missing the DEV-DEMO block (sentinels not found)"; ok=0; }
if [ -n "$NF_DEMO" ] && [ "$NF_DEMO" = "$FB_DEMO" ]; then
    pass "Developer Demo block is byte-identical across both commands"
else
    fail "Developer Demo block differs between new-feature.md and fix-bug.md (must be byte-identical)"
    ok=0
fi

# Load-bearing stems the inlined block must carry.
for stem in "git diff --name-status" "git merge-base" "default-branch.sh" "body-file" "Evidence" "file:line" "Safe-Mermaid"; do
    echo "$NF_DEMO" | grep -qF -- "$stem" || { fail "DEV-DEMO block missing required stem: $stem"; ok=0; }
done

# Gate-2 diagram-honesty rule must be present in both review surfaces, with its
# load-bearing parts (not just the phrase): the rule names "diagram edge", binds
# to "file:line" evidence, and is a "P1" finding.
for surface in commands/codex.md rules/workflow.md; do
    for token in "diagram edge" "file:line" "P1"; do
        grep -qiF -- "$token" "$REPO_ROOT/$surface" \
            || { fail "$surface missing Gate-2 honesty-rule token: $token"; ok=0; }
    done
done

[ "$ok" = "1" ] && pass "DEV-DEMO block carries required stems + Gate-2 honesty rule present in codex.md & workflow.md"

# ---------------------------------------------------------------------------
# Contract: plan-stage "spec-loss is P1" severity rule parity (v5.50)
#
# The plan-review gate keeps its strict no-P0/P1/P2 EXIT, but the severity
# rubric is sharpened so plan omissions that could build the wrong feature are
# P1 (not P2) — because subagents implement FROM the plan and Gate 2 is blind to
# plan-level spec-loss. The rule must appear in all three plan-review surfaces
# and must NOT silently relax the exit. Council-ratified (CHANGE-modified, the
# Hawk/Contrarian-hardened subset that ships #4 only).
# ---------------------------------------------------------------------------
start_test "Plan-stage spec-loss=P1 rule parity (workflow ↔ new-feature ↔ fix-bug)"

ok=1
for surface in rules/workflow.md commands/new-feature.md commands/fix-bug.md; do
    for token in "spec-loss is P1" "wrong feature to be built" "does **not** relax the exit"; do
        grep -qF -- "$token" "$REPO_ROOT/$surface" \
            || { fail "$surface missing plan-stage spec-loss token: $token"; ok=0; }
    done
done
# Regression guard: the strict plan-review EXIT must remain no-P0/P1/P2 in the
# rules (this change sharpens classification, it does NOT relax the gate).
grep -qF -- "no P0/P1/P2 from all available reviewers on the same pass" "$REPO_ROOT/rules/workflow.md" \
    || { fail "rules/workflow.md: plan-review exit criterion was relaxed (must stay no P0/P1/P2)"; ok=0; }
[ "$ok" = "1" ] && pass "plan-stage spec-loss=P1 rule present in all 3 surfaces; strict exit preserved"

# ---------------------------------------------------------------------------
# Contract: /codex hermetic modes capture the verdict via --output-last-message
# ---------------------------------------------------------------------------
# `codex exec [review]` dumps a multi-MB transcript (banner + full diff +
# reasoning) to stdout; the clean verdict is the LAST message. Without
# `--output-last-message`, Claude has to hand-extract the verdict from megabytes
# (the fragile pattern that caused a field misreport — see the council v5.27
# two-file fix in skills/council/references/peer-review-protocol.md). Investigate
# mode (D) already captures the OLM file; this asserts the three hermetic modes
# (A Code Review / B Design Review / C General) do too.
start_test "/codex hermetic modes (A/B/C) capture the verdict via --output-last-message"

CODEX_MD="$REPO_ROOT/commands/codex.md"
# Print the lines of a `## ` section, from its heading to the next `## ` heading.
# index() is a LITERAL match — avoids regex trouble with the ")" in "## A) ...".
codex_section() { awk -v s="$1" 'index($0,s){f=1;next} f&&/^## /{f=0} f' "$CODEX_MD"; }

ok=1
for mode in "## A) Code Review Mode" "## B) Design Review Mode" "## C) General Mode"; do
    sec=$(codex_section "$mode")
    # The clean verdict goes to an OLM file. Match flag+path adjacency (only the
    # COMMAND has "--output-last-message /tmp/codex_response.txt"; the Step-3 prose
    # says "the --output-last-message file (`/tmp/codex_response.txt`)" — flag and
    # path non-adjacent) so a regression dropping the flag from the command is caught.
    echo "$sec" | grep -qF -- "--output-last-message /tmp/codex_response.txt" \
        || { fail "codex.md '$mode' command lacks --output-last-message /tmp/codex_response.txt (no clean verdict file)"; ok=0; }
    # ...AND the verbose stdout is redirected to a forensic log so the multi-MB
    # transcript never enters Claude's context (the half that actually achieves
    # the goal — adding only --output-last-message still streams stdout to Claude).
    # Match the EXACT redirect (only present in the command, not the Step-3 prose
    # that merely names the forensic file) — so the test catches a regression that
    # drops the redirect from the command while keeping the explanatory prose.
    echo "$sec" | grep -qF -- "> /tmp/codex_response_full.txt 2>&1" \
        || { fail "codex.md '$mode' command lacks the '> /tmp/codex_response_full.txt 2>&1' forensic redirect (stdout still dumped to Claude)"; ok=0; }
done
# The stale-OLM clear must use a hook-safe truncate (`: > /tmp/...`), NOT
# `rm -f /tmp/...` — check-bash-safety.sh blocks `rm -[rf]* /<path>` as
# root-targeting, which would block the /codex block at runtime.
if grep -qE 'rm[[:space:]]+-[rf]*[[:space:]]+/tmp/codex_response' "$CODEX_MD"; then
    fail "codex.md uses 'rm -f /tmp/codex_response*' — check-bash-safety blocks it; use ': > /tmp/...' truncate instead"
else
    pass "codex.md clears the stale OLM with a hook-safe truncate (no blocked 'rm -f /tmp/...')"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
report "test-contracts.sh"
