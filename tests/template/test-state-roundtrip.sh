#!/usr/bin/env bash
# tests/template/test-state-roundtrip.sh — EXECUTABLE tests for the state-continuity
# round-trip (v5.52). The contract suite (test-contracts.sh) statically pins that the
# scaffold/prose exist; THIS suite executes the load-bearing logic so a wrong awk or a
# wrong divergence decision fails CI even though the marker strings are still present.
#
#   Level 1 — extract_foldable behavior over the real state.md layouts.
#   Level 2 — the actual finish-branch.md 2.2b guarded fold-back block, run inside a
#             REAL git worktree, asserting the FOLD_* sentinel for each case.
#
# Both the extract_foldable function and the 2.2b block are EXTRACTED FROM THE SHIPPED
# command files (not reimplemented), so this tests what actually ships.
#
# Run from repo root:  bash tests/template/test-state-roundtrip.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

NF="$REPO_ROOT/commands/new-feature.md"
FBR="$REPO_ROOT/commands/finish-branch.md"

# --- Load the REAL extract_foldable from the shipped new-feature.md (between markers) ---
EF_SRC="$(sed -n '/# EXTRACT-FOLDABLE-BEGIN/,/# EXTRACT-FOLDABLE-END/p' "$NF")"
if [ -z "$EF_SRC" ]; then
    fail "could not extract EXTRACT-FOLDABLE block from new-feature.md"
    report "test-state-roundtrip.sh"; exit 1
fi
eval "$EF_SRC"   # defines extract_foldable()

# --- Extract the REAL 2.2b fold-back bash block from finish-branch.md ---
FOLD_BLOCK="$(awk '
    /^### 2\.2b Fold continuity/ { s=1 }
    /^### 2\.3 / { s=0 }
    s && /^```bash$/ { f=1; next }
    f && /^```$/ { f=0 }
    f { print }
' "$FBR")"
FOLD_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/foldblock.XXXXXX")"
printf '%s\n' "$FOLD_BLOCK" > "$FOLD_SCRIPT"

# Fixture state.md writer. Args: <done> <now> <blockers> [with_update_rules=yes|no]
write_state() {
    local f="$1" done_item="$2" now_item="$3" blocker="$4" with_rules="${5:-no}"
    {
        echo "# Project State"
        echo
        echo "## Workflow"
        echo
        echo "| Field | Value |"
        echo "| Command | none |"
        echo
        echo "## /goal session"
        echo
        echo "## PR authorization"
        echo
        echo "## State"
        echo
        echo "### Done (recent 2-3 only)"
        echo
        echo "- $done_item"
        echo
        echo "### Now"
        echo
        echo "- $now_item"
        echo
        echo "### Next"
        echo
        echo "- (what's queued)"
        echo
        echo "### Deferred"
        echo
        echo "- (parked items)"
        echo
        echo "---"
        echo
        echo "## Open Questions"
        echo
        echo "- (none)"
        echo
        echo "## Blockers"
        echo
        echo "- $blocker"
        if [ "$with_rules" = "yes" ]; then
            echo
            echo "---"
            echo
            echo "## Update Rules"
            echo
            echo "RULES_BODY_SHOULD_NOT_BE_FOLDABLE"
        fi
    } > "$f"
}

# Substring assertions on a STRING (lib.sh's assert_contains/assert_not_contains
# operate on a FILE; these operate on captured stdout held in a variable).
assert_not_contains_str() { case "$2" in *"$1"*) fail "$3";; *) pass "$3";; esac; }
assert_contains_str()     { case "$2" in *"$1"*) pass "$3";; *) fail "$3";; esac; }

# ===========================================================================
# Level 1 — extract_foldable behavior
# ===========================================================================
SC1="$(scratch_dir roundtrip-l1)"

write_state "$SC1/a.md" "DONE_ALPHA" "ACTIVE_NOW_WORK" "BLOCKER_ONE" no
write_state "$SC1/a_now.md" "DONE_ALPHA" "DIFFERENT_NOW_WORK" "BLOCKER_ONE" no
write_state "$SC1/a_done.md" "DONE_BETA" "ACTIVE_NOW_WORK" "BLOCKER_ONE" no
write_state "$SC1/a_rules.md" "DONE_ALPHA" "ACTIVE_NOW_WORK" "BLOCKER_ONE" yes

start_test "extract_foldable blanks the Now body but keeps headings + foldable content"
out_a="$(extract_foldable "$SC1/a.md")"
assert_not_contains_str "ACTIVE_NOW_WORK" "$out_a" "Now body is blanked out of the foldable extraction"
assert_contains_str     "### Now"          "$out_a" "the ### Now heading is preserved"
assert_contains_str     "DONE_ALPHA"       "$out_a" "Done content is captured"
assert_contains_str     "BLOCKER_ONE"      "$out_a" "Blockers content is captured"
assert_contains_str     "## Open Questions" "$out_a" "Open Questions section is captured"

start_test "extract_foldable is immune to a Now-only change (no false divergence)"
out_a_now="$(extract_foldable "$SC1/a_now.md")"
assert_equals "$out_a" "$out_a_now" "a Now-only change produces identical foldable extraction"

start_test "extract_foldable detects a real Done change (divergence)"
out_a_done="$(extract_foldable "$SC1/a_done.md")"
if [ "$out_a" != "$out_a_done" ]; then pass "a Done change produces different foldable extraction"
else fail "a Done change should change the foldable extraction but did not"; fi

start_test "extract_foldable stops at '## Update Rules' (does not fold trailing template sections)"
out_a_rules="$(extract_foldable "$SC1/a_rules.md")"
assert_not_contains_str "RULES_BODY_SHOULD_NOT_BE_FOLDABLE" "$out_a_rules" "Update Rules body is NOT included in foldable extraction"

# ===========================================================================
# Level 2 — the real 2.2b fold-back decision, executed in a real git worktree
# ===========================================================================
# Build a main repo + linked worktree, plant state.md + snapshot, run the block.
build_wt() {  # build_wt -> sets REPO, WT (caller writes states/snapshot, then runs)
    REPO="$(scratch_dir roundtrip-main)"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email "t@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" commit --allow-empty -qm init
    mkdir -p "$REPO/.claude/local"
    git -C "$REPO" worktree add -q "$REPO/.worktrees/feat" HEAD 2>/dev/null
    WT="$REPO/.worktrees/feat"
    mkdir -p "$WT/.claude/local"
}
run_fold() {  # run the extracted 2.2b block from inside the worktree; echo its stdout
    ( cd "$WT" && bash "$FOLD_SCRIPT" 2>/dev/null )
}

# Case FOLD_OK: faithful seed — snapshot == extract_foldable(main), main unchanged.
start_test "2.2b → FOLD_OK when main is unchanged since seed"
build_wt
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW" "BLOCKER_ONE" no
write_state "$WT/.claude/local/state.md"   "DONE_ALPHA_PLUS_FEATURE" "WT_NOW" "BLOCKER_ONE" no
extract_foldable "$REPO/.claude/local/state.md" > "$WT/.claude/local/.state-seed-snapshot.md"
ok_out="$(run_fold)"
assert_contains_str "FOLD_OK" "$ok_out" "faithful seed yields FOLD_OK"

# Case FOLD_OK survives a Now-only change on main (Now excluded from divergence).
start_test "2.2b → FOLD_OK even if main's Now changed since seed (Now is excluded)"
build_wt
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW" "BLOCKER_ONE" no
write_state "$WT/.claude/local/state.md"   "DONE_ALPHA" "WT_NOW" "BLOCKER_ONE" no
extract_foldable "$REPO/.claude/local/state.md" > "$WT/.claude/local/.state-seed-snapshot.md"
# now mutate ONLY main's Now after the snapshot was taken
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW_CHANGED_LATER" "BLOCKER_ONE" no
nowchg_out="$(run_fold)"
assert_contains_str "FOLD_OK" "$nowchg_out" "a Now-only change on main does not trip divergence"

# Case FOLD_DIVERGED: main's Done changed after the snapshot was taken.
start_test "2.2b → FOLD_DIVERGED when main's foldable narrative changed since seed"
build_wt
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW" "BLOCKER_ONE" no
write_state "$WT/.claude/local/state.md"   "DONE_ALPHA_PLUS_FEATURE" "WT_NOW" "BLOCKER_ONE" no
extract_foldable "$REPO/.claude/local/state.md" > "$WT/.claude/local/.state-seed-snapshot.md"
write_state "$REPO/.claude/local/state.md" "DONE_CHANGED_BY_SIBLING" "MAIN_NOW" "BLOCKER_ONE" no
div_out="$(run_fold)"
assert_contains_str "FOLD_DIVERGED" "$div_out" "a real main change since seed yields FOLD_DIVERGED"

# Case FOLD_SAFE_STOP: snapshot missing.
start_test "2.2b → FOLD_SAFE_STOP when the seed snapshot is missing"
build_wt
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW" "BLOCKER_ONE" no
write_state "$WT/.claude/local/state.md"   "DONE_ALPHA" "WT_NOW" "BLOCKER_ONE" no
# (no snapshot written)
nosnap_out="$(run_fold)"
assert_contains_str "FOLD_SAFE_STOP" "$nosnap_out" "missing snapshot yields FOLD_SAFE_STOP (no overwrite)"

# Case FOLD_ABORT: worktree state.md absent.
start_test "2.2b → FOLD_ABORT when the worktree state.md is absent"
build_wt
write_state "$REPO/.claude/local/state.md" "DONE_ALPHA" "MAIN_NOW" "BLOCKER_ONE" no
extract_foldable "$REPO/.claude/local/state.md" > "$WT/.claude/local/.state-seed-snapshot.md"
# (no worktree state.md written)
noabort_out="$(run_fold)"
assert_contains_str "FOLD_ABORT" "$noabort_out" "absent worktree state.md yields FOLD_ABORT (no silent empty replace)"

# Case FOLD_SAFE_STOP: structurally incomplete (malformed) main narrative.
start_test "2.2b → FOLD_SAFE_STOP when a narrative is structurally incomplete"
build_wt
printf '%s\n' "## State" "### Done" "- x" > "$REPO/.claude/local/state.md"   # missing Open Questions + Blockers
write_state "$WT/.claude/local/state.md" "DONE_ALPHA" "WT_NOW" "BLOCKER_ONE" no
extract_foldable "$REPO/.claude/local/state.md" > "$WT/.claude/local/.state-seed-snapshot.md"
malformed_out="$(run_fold)"
assert_contains_str "FOLD_SAFE_STOP" "$malformed_out" "structurally incomplete narrative yields FOLD_SAFE_STOP"

rm -f "$FOLD_SCRIPT"
cleanup_scratch_dirs
report "test-state-roundtrip.sh"
