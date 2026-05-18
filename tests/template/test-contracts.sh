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
# Report
# ---------------------------------------------------------------------------
report "test-contracts.sh"
