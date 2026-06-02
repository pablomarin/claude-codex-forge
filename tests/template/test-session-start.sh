#!/usr/bin/env bash
# tests/template/test-session-start.sh — fixture tests for SessionStart drift detection.
#
# Verifies:
#   - source=clear|compact → NO fetch attempted, branch-only context
#   - source=startup → fetch attempted, behind-warning when applicable
#   - fetch failure (bad remote) → silent degrade to branch-only context
#   - additionalContext stays under 2KB
#   - JSON output is valid (parseable by jq)
#
# Run from repo root: bash tests/template/test-session-start.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

HOOK_SH="$REPO_ROOT/hooks/session-start.sh"
HOOK_PS="$REPO_ROOT/hooks/session-start.ps1"
LIB_SH="$REPO_ROOT/hooks/lib/default-branch.sh"
LIB_PS="$REPO_ROOT/hooks/lib/default-branch.ps1"

# ---------------------------------------------------------------------------
# Fixture builder: minimal git repo with `main` checked out + bare remote
# whose HEAD points at main + remote ahead by `behind_count` commits so the
# local repo is "behind by N" after a successful fetch.
#
# Critical: we MUST `git symbolic-ref HEAD refs/heads/main` on the bare repo
# before cloning, otherwise the bare's default HEAD points at the nonexistent
# `master` and the clone leaves no branch checked out (commit loop fails).
# ---------------------------------------------------------------------------
make_behind_repo() {
    local scratch="$1" behind_count="${2:-3}"
    mkdir -p "$scratch/repo" "$scratch/remote.git"
    git init -q --bare "$scratch/remote.git"
    # Set bare HEAD to main BEFORE the first clone — this is the portability fix.
    git -C "$scratch/remote.git" symbolic-ref HEAD refs/heads/main

    (
        cd "$scratch/repo" || exit 1
        git init -q
        git config user.email t@t && git config user.name t
        git checkout -q -b main
        git commit --allow-empty -q -m "c1"
        git remote add origin "$scratch/remote.git"
        git push -q -u origin main
        # Set local origin/HEAD so the helper can detect "main" via Method 1.
        git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null

        if [ "$behind_count" -gt 0 ]; then
            local tmp="$scratch/tmp-clone"
            git clone -q -b main "$scratch/remote.git" "$tmp"
            (
                cd "$tmp" || exit 1
                git config user.email t@t && git config user.name t
                local i
                for ((i=2; i<=behind_count+1; i++)); do
                    git commit --allow-empty -q -m "remote-c$i"
                done
                git push -q origin main
            )
            rm -rf "$tmp"
        fi
    )
}

# Copy the hook + lib into a hooks-relative layout so BASH_SOURCE resolution
# finds the lib. Mirror the layout downstream installs use.
prepare_hook_repo() {
    local repo="$1"
    mkdir -p "$repo/.hooks/lib"
    cp "$HOOK_SH" "$repo/.hooks/session-start.sh"
    cp "$LIB_SH" "$repo/.hooks/lib/default-branch.sh"
    chmod +x "$repo/.hooks/session-start.sh" "$repo/.hooks/lib/default-branch.sh"
}

prepare_hook_repo_ps() {
    local repo="$1"
    mkdir -p "$repo/.hooks/lib"
    cp "$HOOK_PS" "$repo/.hooks/session-start.ps1"
    cp "$LIB_PS" "$repo/.hooks/lib/default-branch.ps1"
}

# Run the bash hook with a synthetic stdin payload, write stdout to a file
# so we can use lib.sh's file-path-taking assertions (assert_contains etc.).
# Echoes the OUTPUT FILE PATH on stdout so callers can pass it to assertions.
run_session_start_sh() {
    local repo="$1" source_val="$2"
    local out="$repo/.session-out"
    (cd "$repo" && printf '{"source":"%s","session_id":"test","cwd":"%s"}' \
        "$source_val" "$repo" | bash ./.hooks/session-start.sh) > "$out" 2>"$repo/.session-err"
    echo "$out"
}

run_session_start_ps() {
    local repo="$1" source_val="$2"
    local out="$repo/.session-out"
    if ! command -v pwsh >/dev/null 2>&1; then
        echo ""  # signal "skip"
        return
    fi
    (cd "$repo" && printf '{"source":"%s","session_id":"test","cwd":"%s"}' \
        "$source_val" "$repo" | pwsh -NoProfile -File ./.hooks/session-start.ps1) > "$out" 2>"$repo/.session-err"
    echo "$out"
}

# ===========================================================================
# Test 1: source=clear → no fetch, branch-only context
# ===========================================================================
start_test "source=clear → branch only, no fetch attempted"
S1=$(scratch_dir)
make_behind_repo "$S1" 3
prepare_hook_repo "$S1/repo"
OUTFILE=$(run_session_start_sh "$S1/repo" "clear")
assert_contains "$OUTFILE" "Current branch:" "context starts with branch"
assert_not_contains "$OUTFILE" "behind origin" "no behind warning on /clear"

# ===========================================================================
# Test 2: source=compact → no fetch, branch-only context
# ===========================================================================
start_test "source=compact → branch only, no fetch attempted"
S2=$(scratch_dir)
make_behind_repo "$S2" 3
prepare_hook_repo "$S2/repo"
OUTFILE=$(run_session_start_sh "$S2/repo" "compact")
assert_not_contains "$OUTFILE" "behind origin" "no behind warning on /compact"

# ===========================================================================
# Test 3: source=startup + behind=3 → behind warning in context
# ===========================================================================
start_test "source=startup + behind by 3 → warning included"
S3=$(scratch_dir)
make_behind_repo "$S3" 3
prepare_hook_repo "$S3/repo"
OUTFILE=$(run_session_start_sh "$S3/repo" "startup")
assert_contains "$OUTFILE" "behind origin" "behind warning present"
assert_contains "$OUTFILE" "3 commits" "behind count = 3"

# ===========================================================================
# Test 4: source=resume + behind=0 → no warning, branch only
# ===========================================================================
start_test "source=resume + up-to-date → no warning"
S4=$(scratch_dir)
make_behind_repo "$S4" 0
prepare_hook_repo "$S4/repo"
OUTFILE=$(run_session_start_sh "$S4/repo" "resume")
assert_contains "$OUTFILE" "Current branch:" "branch present"
assert_not_contains "$OUTFILE" "behind origin" "no warning when up-to-date"

# ===========================================================================
# Test 5: bad remote (fetch fails) + source=startup → silent degrade
# Uses a NONEXISTENT LOCAL path (not a bad URL) so the fetch fails immediately
# without DNS lookup. This keeps the test deterministic on hosts without
# `gtimeout`/`timeout` (the council-accepted macOS degraded case) — the bash
# hook would otherwise stall up to ~75s on a network-targeted bad URL.
# ===========================================================================
start_test "fetch fails → silent degrade to branch-only"
S5=$(scratch_dir)
mkdir -p "$S5/repo"
(
    cd "$S5/repo" || exit 1
    git init -q
    git config user.email t@t && git config user.name t
    git checkout -q -b main
    git commit --allow-empty -q -m "c1"
    git remote add origin "$S5/nonexistent-remote.git"  # local path, never created
)
prepare_hook_repo "$S5/repo"
OUTFILE=$(run_session_start_sh "$S5/repo" "startup")
assert_contains "$OUTFILE" "Current branch:" "branch context emitted"
assert_not_contains "$OUTFILE" "behind origin" "no false warning when fetch failed"

# ===========================================================================
# Test 6: additionalContext stays under 2KB on the worst realistic case
# ===========================================================================
start_test "additionalContext < 2KB"
S6=$(scratch_dir)
make_behind_repo "$S6" 999  # large but realistic; well under 99999
prepare_hook_repo "$S6/repo"
OUTFILE=$(run_session_start_sh "$S6/repo" "startup")
LEN=$(wc -c < "$OUTFILE" | tr -d ' ')
if [ "$LEN" -lt 2048 ]; then
    pass "additionalContext output is $LEN bytes (< 2048)"
else
    fail "additionalContext output is $LEN bytes (>= 2048 — way too large)"
fi

# ===========================================================================
# Test 7: JSON output is parseable
# ===========================================================================
start_test "output is valid JSON (parseable by jq)"
S7=$(scratch_dir)
make_behind_repo "$S7" 1
prepare_hook_repo "$S7/repo"
OUTFILE=$(run_session_start_sh "$S7/repo" "startup")
if command -v jq &>/dev/null; then
    if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' < "$OUTFILE" >/dev/null; then
        pass "valid JSON, hookEventName == SessionStart"
    else
        fail "JSON parse failed or hookEventName mismatch"
    fi
else
    printf "  %s·%s skipped: jq not available\n" "$C_DIM" "$C_RESET"
fi

# ===========================================================================
# Test 8: TIMEOUT_CMD selection — no timeout binary available → hook still
# exits 0 and emits valid JSON.
#
# Isolation: $scratch/empty-bin is an empty directory (no executables). We
# prepend it to PATH, then append enough of the real PATH to keep git
# reachable (so fetch runs), but exclude any directory that provides
# `gtimeout` or `timeout`. This exercises the empty-TIMEOUT_CMD branch:
#   `$TIMEOUT_CMD git fetch …` with TIMEOUT_CMD="" expands to just
#   `git fetch …` — the hook's intended no-timeout fallback.
# ===========================================================================
start_test "no timeout binary available → exits 0, valid JSON (empty-TIMEOUT_CMD path)"
S8=$(scratch_dir)
make_behind_repo "$S8" 2
prepare_hook_repo "$S8/repo"

# Build a PATH that contains git but NOT gtimeout or timeout.
# Strategy: iterate real PATH segments; skip any segment that houses a
# `timeout` or `gtimeout` binary. Always add $S8/empty-bin first so any
# stub we might want later lives at front, but we leave it empty here.
mkdir -p "$S8/empty-bin"
FILTERED_PATH="$S8/empty-bin"
IFS=':' read -ra _PATH_SEGS <<< "$PATH"
for _seg in "${_PATH_SEGS[@]}"; do
    # Skip segments that host timeout or gtimeout (the binaries we're hiding).
    if [[ -x "$_seg/timeout" ]] || [[ -x "$_seg/gtimeout" ]]; then
        continue
    fi
    FILTERED_PATH="$FILTERED_PATH:$_seg"
done

# Run the hook with the filtered PATH, capturing stdout and exit code.
S8_OUT="$S8/repo/.session-out"
(
    cd "$S8/repo"
    printf '{"source":"startup","session_id":"test","cwd":"%s"}' "$S8/repo" \
        | PATH="$FILTERED_PATH" bash ./.hooks/session-start.sh
) >"$S8_OUT" 2>"$S8/repo/.session-err"
S8_RC=$?

if [[ $S8_RC -eq 0 ]]; then
    pass "hook exits 0 when no timeout binary is available"
else
    fail "hook exited $S8_RC (expected 0)"
fi
assert_contains "$S8_OUT" "Current branch:" "branch context emitted without timeout binary"
# Verify the JSON shape is valid (hook should not crash on empty TIMEOUT_CMD).
if command -v jq &>/dev/null; then
    if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' < "$S8_OUT" >/dev/null 2>&1; then
        pass "valid JSON output even without timeout binary"
    else
        fail "JSON invalid or hookEventName mismatch when no timeout binary"
    fi
fi

# ===========================================================================
# Test 9: source="" (empty) → no fetch, branch context still emitted
#
# The gate is: [[ "$SOURCE" == "startup" || "$SOURCE" == "resume" ]]
# An empty SOURCE must NOT trigger fetch, but the hook must still emit
# the branch context and exit 0 (fail-closed gate).
# ===========================================================================
start_test "source='' (empty) → no fetch, branch context emitted"
S9=$(scratch_dir)
make_behind_repo "$S9" 3
prepare_hook_repo "$S9/repo"
# Use run_session_start_sh with empty string as source value.
OUTFILE=$(run_session_start_sh "$S9/repo" "")
assert_contains "$OUTFILE" "Current branch:" "branch context present for empty source"
assert_not_contains "$OUTFILE" "behind origin" "no behind warning for empty source (gate skips fetch)"

# ===========================================================================
# Test 10: source="unknown_future_value" → no fetch, branch context emitted
#
# Forward-compatibility: any value other than startup/resume must not trigger
# fetch. This prevents a new source subtype from accidentally revealing stale
# drift warnings before the user has initiated a real session start.
# ===========================================================================
start_test "source='unknown_future_value' → no fetch, branch context emitted"
S10=$(scratch_dir)
make_behind_repo "$S10" 3
prepare_hook_repo "$S10/repo"
OUTFILE=$(run_session_start_sh "$S10/repo" "unknown_future_value")
assert_contains "$OUTFILE" "Current branch:" "branch context present for unknown source"
assert_not_contains "$OUTFILE" "behind origin" "no behind warning for unknown source (gate fail-closed)"

# ===========================================================================
# PowerShell parity (skipped if pwsh unavailable; uses pwsh for cross-platform
# fixture testing — the SHIPPED hook runs under powershell.exe on Windows via
# settings-windows.template.json, but pwsh is the cross-host way to test the
# .ps1 file from bash on macOS/Linux/CI)
# ===========================================================================
if command -v pwsh >/dev/null 2>&1; then
    start_test "pwsh: source=clear → branch only"
    S8=$(scratch_dir)
    make_behind_repo "$S8" 2
    prepare_hook_repo_ps "$S8/repo"
    OUTFILE=$(run_session_start_ps "$S8/repo" "clear")
    assert_not_contains "$OUTFILE" "behind origin" "pwsh: no warning on clear"

    start_test "pwsh: source=startup + behind by 2 → warning"
    S9=$(scratch_dir)
    make_behind_repo "$S9" 2
    prepare_hook_repo_ps "$S9/repo"
    OUTFILE=$(run_session_start_ps "$S9/repo" "startup")
    assert_contains "$OUTFILE" "behind origin" "pwsh: warning present"
fi

# ===========================================================================
# Forge version drift advisory (v5.51): project pin vs machine stamp.
# Seeds .claude/.forge-version in the repo (pin) and in a fake HOME (machine),
# runs the hook with HOME + CLAUDE_PROJECT_DIR controlled.
# ===========================================================================
# Runner: source, project pin, machine version → output file path.
run_ss_drift() {
    local repo="$1" src="$2" home="$3"
    local out="$repo/.session-out"
    ( cd "$repo" && printf '{"source":"%s","session_id":"t","cwd":"%s"}' "$src" "$repo" \
        | env HOME="$home" CLAUDE_PROJECT_DIR="$repo" bash ./.hooks/session-start.sh ) \
        > "$out" 2>"$repo/.session-err"
    echo "$out"
}
# Build a minimal hook repo + seed both stamps. Args: pin machine → echoes repo path.
seed_drift_repo() {
    local pin="$1" machine="$2"
    local base; base=$(scratch_dir drift)
    local repo="$base/repo"; mkdir -p "$repo"; ( cd "$repo" && git init -q )
    prepare_hook_repo "$repo"
    mkdir -p "$repo/.claude" "$base/home/.claude"
    [ -n "$pin" ] && printf '%s\n' "$pin" > "$repo/.claude/.forge-version"
    [ -n "$machine" ] && printf '%s\n' "$machine" > "$base/home/.claude/.forge-version"
    echo "$repo"
}

# Machine OLDER than project pin → factual "you may want to upgrade yours to match".
start_test "drift: machine older than project pin → upgrade-yours advisory"
R=$(seed_drift_repo "5.50" "5.40")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_contains "$OUTFILE" "this project pins Forge 5.50" "drift: names the project pin"
assert_contains "$OUTFILE" "upgrade yours to match" "drift: older machine told the project is newer"

# Machine NEWER than project pin → factual "your Forge is newer".
start_test "drift: machine newer than project pin → benign advisory"
R=$(seed_drift_repo "5.40" "5.50")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_contains "$OUTFILE" "your Forge is newer" "drift: newer machine told its Forge is newer"

# Numeric correctness: pin 5.50, machine 5.9 → 5.9 is OLDER (string compare would reverse).
start_test "drift: 5.9 vs 5.50 ordered numerically (machine 5.9 is older)"
R=$(seed_drift_repo "5.50" "5.9")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_contains "$OUTFILE" "upgrade yours to match" "drift: 5.9 correctly treated as older than 5.50"

# Equal versions → no drift line.
start_test "drift: equal versions → no advisory"
R=$(seed_drift_repo "5.50" "5.50")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_not_contains "$OUTFILE" "this project pins Forge" "drift: no advisory when versions match"

# Missing machine stamp → fail-open, no drift line, exit 0.
start_test "drift: missing machine stamp → fail-open (no advisory)"
R=$(seed_drift_repo "5.50" "")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_not_contains "$OUTFILE" "this project pins Forge" "drift: no advisory when machine stamp absent"
assert_contains "$OUTFILE" "Current branch:" "drift: still emits normal context (fail-open)"

# Malformed project pin → fail-open, no advisory (stamps validated as X.Y first).
start_test "drift: malformed pin → fail-open (no advisory)"
R=$(seed_drift_repo "garbage" "5.40")
OUTFILE=$(run_ss_drift "$R" "startup" "$(dirname "$R")/home")
assert_not_contains "$OUTFILE" "this project pins Forge" "drift: malformed pin → no advisory (fail-open)"
assert_contains "$OUTFILE" "Current branch:" "drift: still emits normal context on malformed pin"

# Gated to startup|resume: on compact, no drift line even with a real mismatch.
start_test "drift: source=compact → no advisory (gated to startup|resume)"
R=$(seed_drift_repo "5.50" "5.40")
OUTFILE=$(run_ss_drift "$R" "compact" "$(dirname "$R")/home")
assert_not_contains "$OUTFILE" "this project pins Forge" "drift: not shown on compact"

# PowerShell parity (pwsh-gated): 5.9 machine vs 5.50 pin → numeric, machine older.
if command -v pwsh >/dev/null 2>&1; then
    start_test "pwsh drift: 5.9 vs 5.50 numeric (machine older → upgrade-warning)"
    base=$(scratch_dir driftps); repo="$base/repo"; mkdir -p "$repo"; ( cd "$repo" && git init -q )
    prepare_hook_repo_ps "$repo"
    mkdir -p "$repo/.claude" "$base/home/.claude"
    printf '5.50\n' > "$repo/.claude/.forge-version"
    printf '5.9\n' > "$base/home/.claude/.forge-version"
    out="$repo/.session-out"
    ( cd "$repo" && printf '{"source":"startup","session_id":"t","cwd":"%s"}' "$repo" \
        | env HOME="$base/home" CLAUDE_PROJECT_DIR="$repo" pwsh -NoProfile -File ./.hooks/session-start.ps1 ) \
        > "$out" 2>"$repo/.session-err"
    assert_contains "$out" "upgrade yours to match" "pwsh drift: 5.9 correctly older than 5.50"

    # Newer-Forge direction (machine 5.50 > pin 5.40) — covers the ps1 else-branch so a
    # stale/inverted newer-Forge string can't pass on parity (Codex review P3).
    start_test "pwsh drift: machine newer than project pin → your-Forge-is-newer advisory"
    printf '5.40\n' > "$repo/.claude/.forge-version"
    printf '5.50\n' > "$base/home/.claude/.forge-version"
    out2="$repo/.session-out2"
    ( cd "$repo" && printf '{"source":"startup","session_id":"t","cwd":"%s"}' "$repo" \
        | env HOME="$base/home" CLAUDE_PROJECT_DIR="$repo" pwsh -NoProfile -File ./.hooks/session-start.ps1 ) \
        > "$out2" 2>"$repo/.session-err2"
    assert_contains "$out2" "your Forge is newer" "pwsh drift: machine 5.50 newer than pin 5.40"
fi

report "test-session-start.sh"
