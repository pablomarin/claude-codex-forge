#!/bin/bash
# tests/template/test-migrate.sh — fixtures for scripts/migrate-continuity.sh
# Invoked via: bash tests/template/test-migrate.sh
# CI must have a PowerShell runtime for the cross-platform parity portion of
# test-contracts.sh — this file itself is bash-only (tests bash migration).

set -u  # unset-var detection; do NOT set -e (lib.sh handles failures via counters)

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

# ---------------------------------------------------------------------------
# Inline fixture helpers (mirror test-fixtures.sh; kept inline to avoid
# sourcing test-fixtures.sh which would re-run its own test cases here).
# ---------------------------------------------------------------------------
make_legacy_continuity_for_migration() {
    local scratch="$1"
    cat > "$scratch/CONTINUITY.md" <<'EOF'
# CONTINUITY

## Goal

Build a thing that does the thing.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Database | PostgreSQL | ACID; pgvector |
| Auth     | OAuth2 + JWT | Industry standard |

## State

### Done (recent 2-3 only)

- 2026-04-01: oldest entry (should be trimmed by tail -3)
- 2026-04-02: shipped feature X
- 2026-04-03: shipped feature Y
- 2026-04-04: shipped feature Z (most recent, should be kept)

### Now

Working on the migration assistant.

### Next

- ship PR #2
- write CHANGELOG entry

EOF
    # Also drop a CLAUDE.md with the dangling @-import.
    cat > "$scratch/CLAUDE.md" <<'EOF'
@CONTINUITY.md

# CLAUDE.md - Test Project

## Project Overview

A test project.
EOF
}

# Helper: assert that string $1 contains literal substring $2.
# (lib.sh's assert_contains takes a file path; we use string semantics here.)
assert_str_contains() {
    local haystack="$1" needle="$2" msg="${3:-string contains '$2'}"
    if echo "$haystack" | grep -qF -- "$needle"; then
        pass "$msg"
    else
        fail "$msg (not found in output)"
    fi
}

run_migrate() {
    local scratch="$1"
    # Pre-install state.template.md so the helper has somewhere to write Now/Next.
    mkdir -p "$scratch/.claude/local"
    if [ ! -f "$scratch/.claude/local/state.md" ]; then
        tail -n +2 "$REPO_ROOT/state.template.md" > "$scratch/.claude/local/state.md"
    fi
    ( cd "$scratch" && bash "$REPO_ROOT/scripts/migrate-continuity.sh" 2>&1 )
}

start_test "test_migrate_extracts_goal"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
out=$(run_migrate "$scratch")
assert_str_contains "$out" "Goal" "summary mentions Goal migration"
if grep -qF "Build a thing that does the thing." "$scratch/CLAUDE.md"; then
    pass "goal text appended to CLAUDE.md"
else
    fail "goal text not appended to CLAUDE.md"
fi
rm -rf "$scratch"

start_test "test_migrate_creates_adrs_from_decisions_table"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
if compgen -G "$scratch/docs/adr/*-database.md" >/dev/null; then pass "Database ADR created"; else fail "Database ADR missing"; fi
if compgen -G "$scratch/docs/adr/*-auth.md" >/dev/null; then pass "Auth ADR created"; else fail "Auth ADR missing"; fi
rm -rf "$scratch"

start_test "test_migrate_trims_done_to_last_3"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
# Extract ONLY the ### Done block from state.md, then count bullets — not all bullets in the file.
done_count=$(awk '/^### Done/{f=1;next} f && /^### /{f=0} f && /^- /{n++} END{print n+0}' "$scratch/.forge/local/state.md")
if [ "$done_count" -le 3 ]; then pass "Done block has $done_count entries (≤ 3)"; else fail "Done has $done_count entries, expected ≤ 3"; fi
# Verify it kept the LAST entries, not the first (Codex P1: tail vs head).
# Fixture has 4 dated entries; tail -3 should keep 02, 03, 04 and drop 01.
if grep -qF "2026-04-01: oldest entry" "$scratch/.forge/local/state.md"; then
    fail "Done kept the OLDEST entry — should have used tail, not head"
else
    pass "Done dropped the oldest entry (correct tail behavior)"
fi
# And the most-recent entry MUST be present (regression guard for P1-1:
# multi-line awk silently dropped Done content, leaving the placeholder).
if grep -qF "2026-04-04: shipped feature Z" "$scratch/.forge/local/state.md"; then
    pass "Done kept the most-recent entry (real content, not placeholder)"
else
    fail "Done is missing the most-recent entry (P1-1 regression: awk dropped content?)"
fi
rm -rf "$scratch"

start_test "test_migrate_byte_preserves_original"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
before=$(hash_file "$scratch/CONTINUITY.md")
run_migrate "$scratch" >/dev/null
after=$(hash_file "$scratch/CONTINUITY.md")
assert_equals "$before" "$after" "CONTINUITY.md byte-preserved through --migrate"
rm -rf "$scratch"

start_test "test_migrate_writes_state_translation_receipt_bound_to_source_and_target"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
receipt="$scratch/.forge/local/migration-evidence/continuity-state-v5-v6.json"
assert_file_exists "$receipt" "continuity migration writes protected canonical evidence"
if [ -f "$receipt" ]; then
    receipt_schema=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["schema"])' "$receipt")
    receipt_source=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$receipt")
    receipt_target=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target_hash"])' "$receipt")
    assert_equals "$receipt_schema" "forge-continuity-state-translation-v1" \
        "continuity receipt declares its versioned schema"
    assert_equals "$receipt_source" "$(hash_file "$scratch/.claude/local/state.md")" \
        "continuity receipt binds the exact surviving legacy source"
    assert_equals "$receipt_target" "$(hash_file "$scratch/.forge/local/state.md")" \
        "continuity receipt binds the final canonical target after migration edits"
fi
rm -rf "$scratch"

start_test "test_migrate_idempotent_state_md"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
before_state=$(hash_file "$scratch/.forge/local/state.md")
run_migrate "$scratch" >/dev/null  # second run — should detect sentinel and no-op
after_state=$(hash_file "$scratch/.forge/local/state.md")
assert_equals "$before_state" "$after_state" "state.md unchanged on second run (sentinel detected)"
rm -rf "$scratch"

start_test "test_migrate_idempotent_claude_md"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
before_claude=$(hash_file "$scratch/CLAUDE.md")
run_migrate "$scratch" >/dev/null
after_claude=$(hash_file "$scratch/CLAUDE.md")
assert_equals "$before_claude" "$after_claude" "CLAUDE.md unchanged on second run (sentinel detected)"
rm -rf "$scratch"

start_test "test_migrate_idempotent_no_duplicate_adrs"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
before_count=$(compgen -G "$scratch/docs/adr/*.md" 2>/dev/null | wc -l | tr -d ' ')
run_migrate "$scratch" >/dev/null
after_count=$(compgen -G "$scratch/docs/adr/*.md" 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$before_count" "$after_count" "ADR file count unchanged on second run"
rm -rf "$scratch"

start_test "test_migrate_flags_dangling_at_import"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"  # creates CLAUDE.md with @CONTINUITY.md
out=$(run_migrate "$scratch")
assert_str_contains "$out" "@CONTINUITY.md" "summary flags dangling @-import"
assert_str_contains "$out" "dangling" "summary uses 'dangling' phrasing"
rm -rf "$scratch"

start_test "test_migrate_no_continuity_present"
scratch=$(mktemp -d)
out=$(run_migrate "$scratch")
assert_str_contains "$out" "No CONTINUITY.md" "graceful no-op when no legacy file"
rm -rf "$scratch"

# ---------------------------------------------------------------------------
# P1-1 regression guard: multi-line Done entries with em-dashes, parentheticals,
# embedded URLs, PR refs — the shape of real Forge dogfood content. The original
# `awk -v done_content="$section"` pattern fails with "awk: newline in string"
# and silently drops the section, leaving the placeholder.
# ---------------------------------------------------------------------------
make_legacy_continuity_with_complex_done() {
    local scratch="$1"
    cat > "$scratch/CONTINUITY.md" <<'EOF'
# CONTINUITY

## Goal

Build a real production thing.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| DB       | Postgres | ACID; pgvector |

## State

### Done (recent 2-3 only)
- ARRANGE rule text fixes (PR #512, squash-merged be70a83): 2026-04-20. Closes MSAI field gap where Claude ran `docker exec … psql INSERT` to seed E2E test data. 4 files: `rules/critical-rules.md` (ARRANGE named explicitly in E2E bullet), `rules/testing.md` (line 176 contradiction removed), `agents/verify-e2e.md` (Critical Constraints #2 forbids raw DB in ARRANGE).
- Phase 4 task-DAG dispatch + /compact banner + headless opt-in (PR #524, squash-merged 6bc290d): 2026-04-21. Replaces Phase 4's vague reference with a mandatory task-DAG dispatch plan (continuous dispatch, disjoint `Writes`, default 3 / max 5 concurrent subagents, sequential-override for tightly-coupled plans), optional `/compact` reminder banner, and headless kept as an explicit opt-in phrase.
- Template-drift notice on `setup.sh -f` / `--upgrade` (PR #523, squash-merged dbe6f6f): 2026-04-21. Closes the downstream pain where bumping the harness didn't surface template drift in preserved CLAUDE.md / CONTINUITY.md. New helper + consolidated reminder + four boolean-gated final-summary variants.

### Now

On main, clean.

### Next

- ship PR #2

EOF
    cat > "$scratch/CLAUDE.md" <<'EOF'
# CLAUDE.md - Test Project

## Project Overview

A test project.
EOF
}

start_test "test_migrate_handles_multi_line_done"
scratch=$(mktemp -d)
make_legacy_continuity_with_complex_done "$scratch"
out=$(run_migrate "$scratch" 2>&1)
# state.md must contain the actual content, NOT the placeholder.
if grep -qF "(your most recent completed work)" "$scratch/.forge/local/state.md"; then
    fail "Done section still has placeholder — multi-line content was DROPPED (P1-1 bug)"
else
    pass "Done placeholder replaced by real content"
fi
# The 3 fixture entries are all real Done entries; tail -3 keeps all of them.
# Each must appear in state.md with full content (em-dash + parens + PR ref).
if grep -qF "ARRANGE rule text fixes (PR #512" "$scratch/.forge/local/state.md"; then
    pass "Done preserved entry with parens + em-dash + PR ref (PR #512)"
else
    fail "Done lost entry with parens / em-dash / PR ref (PR #512)"
fi
if grep -qF "Phase 4 task-DAG dispatch" "$scratch/.forge/local/state.md"; then
    pass "Done preserved entry with backticks + PR ref (PR #524)"
else
    fail "Done lost entry (PR #524)"
fi
if grep -qF "Template-drift notice" "$scratch/.forge/local/state.md"; then
    pass "Done preserved most-recent entry (PR #523)"
else
    fail "Done lost most-recent entry (PR #523)"
fi
# No awk error in output.
if echo "$out" | grep -qE "awk:.*newline in string|awk:.*illegal"; then
    fail "awk emitted error — multi-line variable interpolation regressed"
else
    pass "no awk newline/illegal errors on multi-line Done content"
fi
rm -rf "$scratch"

# ---------------------------------------------------------------------------
# AC-10 regression guard: sentinel must land on LINE 1 of CLAUDE.md (not line 2).
# ---------------------------------------------------------------------------
start_test "test_migrate_sentinel_on_line_1_of_claude_md"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
first_line=$(head -1 "$scratch/CLAUDE.md")
case "$first_line" in
    "<!-- forge:migrated "*"-->")
        pass "CLAUDE.md sentinel on line 1 (matches state.md treatment + dogfood result)"
        ;;
    *)
        fail "CLAUDE.md sentinel NOT on line 1 (got: $first_line)"
        ;;
esac
# Canonical state keeps its schema marker on line 1 and the migration sentinel
# on line 2 so every host can validate it before parsing receipts.
state_first=$(head -1 "$scratch/.forge/local/state.md")
state_second=$(sed -n '2p' "$scratch/.forge/local/state.md")
case "$state_first:$state_second" in
    "<!-- forge:state-schema v6 -->:<!-- forge:migrated "*"-->")
        pass "state.md schema remains line 1 and migration sentinel is line 2"
        ;;
    *)
        fail "state.md schema/sentinel ordering invalid (got: $state_first / $state_second)"
        ;;
esac
rm -rf "$scratch"

# ---------------------------------------------------------------------------
# P3 nit guard: idempotency message uses "Already migrated on YYYY-MM-DD."
# ---------------------------------------------------------------------------
start_test "test_migrate_idempotency_message_format"
scratch=$(mktemp -d)
make_legacy_continuity_for_migration "$scratch"
run_migrate "$scratch" >/dev/null
out=$(run_migrate "$scratch" 2>&1)
if echo "$out" | grep -qE "Already migrated on [0-9]{4}-[0-9]{2}-[0-9]{2}\."; then
    pass "idempotency message uses 'Already migrated on YYYY-MM-DD.' form"
else
    fail "idempotency message has wrong format (got: $(echo "$out" | head -1))"
fi
rm -rf "$scratch"

# ---------------------------------------------------------------------------
# P1-C regression guard: multi-paragraph Goal content (valid markdown — users
# may have a multi-paragraph project goal with em-dashes, parens, code spans,
# blank lines between paragraphs). The original `awk -v goal="$goal_content"`
# pattern fails with "awk: newline in string" and silently drops the Goal —
# worse, the sentinel was already written, so a rerun is a no-op even though
# the Goal never made it into CLAUDE.md.
# ---------------------------------------------------------------------------
make_legacy_continuity_with_multi_paragraph_goal() {
    local scratch="$1"
    cat > "$scratch/CONTINUITY.md" <<'EOF'
# CONTINUITY

## Goal

Build a production-grade analytics platform — multi-tenant, GDPR-aware, with `pgvector` similarity search.

The platform serves three personas: data analysts (SQL workbench), product managers (no-code dashboards), and engineers (raw `/api/v1/` access). Each persona gets a tailored UX while sharing a single source of truth.

Long-term vision: become the default warehouse for mid-market SaaS (50–500 employees) — replacing the Snowflake + Looker + Segment stack with a single Postgres-backed product.

## State

### Done (recent 2-3 only)

- 2026-04-04: shipped feature Z

### Now

On main, clean.

### Next

- ship PR #2

EOF
    cat > "$scratch/CLAUDE.md" <<'EOF'
# CLAUDE.md - Test Project

## Project Overview

A test project.
EOF
}

start_test "test_migrate_handles_multi_paragraph_goal"
scratch=$(mktemp -d)
make_legacy_continuity_with_multi_paragraph_goal "$scratch"
out=$(run_migrate "$scratch" 2>&1)
# CLAUDE.md must contain ALL three paragraphs of the Goal, not just the first.
if grep -qF "Build a production-grade analytics platform" "$scratch/CLAUDE.md"; then
    pass "Goal first paragraph migrated to CLAUDE.md"
else
    fail "Goal first paragraph missing from CLAUDE.md"
fi
if grep -qF "The platform serves three personas" "$scratch/CLAUDE.md"; then
    pass "Goal second paragraph migrated (multi-paragraph preservation)"
else
    fail "Goal second paragraph DROPPED — P1-C bug: awk -v chokes on newlines"
fi
if grep -qF "Long-term vision: become the default warehouse" "$scratch/CLAUDE.md"; then
    pass "Goal third paragraph migrated (multi-paragraph preservation)"
else
    fail "Goal third paragraph DROPPED — P1-C bug: awk -v chokes on newlines"
fi
# Em-dashes, backticks, parens preserved verbatim.
if grep -qF '`pgvector` similarity search' "$scratch/CLAUDE.md"; then
    pass "Goal preserves backticks/code spans"
else
    fail "Goal lost backticks (`pgvector`) — content corruption"
fi
# No awk error in output.
if echo "$out" | grep -qE "awk:.*newline in string|awk:.*illegal"; then
    fail "awk emitted error on multi-paragraph Goal — P1-C regression"
else
    pass "no awk newline/illegal errors on multi-paragraph Goal"
fi
# Summary line should mention the Goal migration succeeded.
assert_str_contains "$out" "Goal -> CLAUDE.md" "summary reports Goal moved (not skipped)"
rm -rf "$scratch"

report "test-migrate.sh"
