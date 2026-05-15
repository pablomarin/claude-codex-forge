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

# lib.sh's EXIT trap prints the summary; no explicit call needed.
report "build-evidence.sh" >&2
