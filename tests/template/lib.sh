#!/usr/bin/env bash
# tests/template/lib.sh — shared helpers for template self-tests.
#
# Source this from each test-*.sh. Provides:
#   - Color output helpers (auto-disabled if stdout isn't a TTY)
#   - assert_* functions that return 0/1 and increment pass/fail counters
#   - scratch_dir / cleanup trap with KEEP_TMP_ON_FAIL support
#   - run_setup wrapper that captures stdout+stderr+exit code
#
# Convention: tests run from repo root. Helpers resolve paths relative
# to the REPO_ROOT env var (set by run-all.sh or each individual script).

set -u  # fail on unset variables; intentionally NOT set -e so individual
        # assertion failures don't abort the whole script.

# ---------------------------------------------------------------------------
# Color output (no colors when piping to file or under CI without TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_DIM=""
    C_RESET=""
fi

# ---------------------------------------------------------------------------
# Counters (each test script resets via init_counters)
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
CURRENT_TEST=""

init_counters() {
    PASS_COUNT=0
    FAIL_COUNT=0
}

start_test() {
    CURRENT_TEST="$1"
    printf "\n%s▶ %s%s\n" "$C_BLUE" "$CURRENT_TEST" "$C_RESET"
}

pass() {
    local msg="${1:-}"
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$msg"
}

fail() {
    local msg="${1:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$msg" >&2
}

report() {
    local name="$1"
    printf "\n%s── %s: %d passed, %d failed ──%s\n" \
        "$C_DIM" "$name" "$PASS_COUNT" "$FAIL_COUNT" "$C_RESET"
    [[ "$FAIL_COUNT" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Assertion helpers
# Each returns 0 on pass, 1 on fail, and updates counters.
# ---------------------------------------------------------------------------
assert_file_exists() {
    local path="$1" msg="${2:-file exists: $1}"
    if [[ -f "$path" ]]; then
        pass "$msg"
    else
        fail "$msg (not found: $path)"
    fi
}

assert_file_missing() {
    local path="$1" msg="${2:-file absent: $1}"
    if [[ ! -e "$path" ]]; then
        pass "$msg"
    else
        fail "$msg (unexpectedly present: $path)"
    fi
}

assert_dir_exists() {
    local path="$1" msg="${2:-dir exists: $1}"
    if [[ -d "$path" ]]; then
        pass "$msg"
    else
        fail "$msg (not a directory: $path)"
    fi
}

# Literal substring match. Use this for fingerprints that should appear verbatim.
assert_contains() {
    local path="$1" needle="$2" msg="${3:-contains: $2}"
    if [[ ! -f "$path" ]]; then
        fail "$msg (file missing: $path)"
        return
    fi
    if grep -qF -- "$needle" "$path"; then
        pass "$msg"
    else
        fail "$msg (not found in $path)"
    fi
}

assert_not_contains() {
    local path="$1" needle="$2" msg="${3:-does not contain: $2}"
    if [[ ! -f "$path" ]]; then
        fail "$msg (file missing: $path)"
        return
    fi
    if ! grep -qF -- "$needle" "$path"; then
        pass "$msg"
    else
        fail "$msg (unexpectedly found in $path)"
    fi
}

# Regex substring match. Use for fuzzier fingerprints.
assert_matches() {
    local path="$1" pattern="$2" msg="${3:-matches /$2/}"
    if [[ ! -f "$path" ]]; then
        fail "$msg (file missing: $path)"
        return
    fi
    if grep -qE -- "$pattern" "$path"; then
        pass "$msg"
    else
        fail "$msg (pattern not matched in $path)"
    fi
}

# Exact file-content equality by hash (stable across idempotency runs)
hash_file() {
    local path="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    else
        sha256sum "$path" | awk '{print $1}'
    fi
}

assert_hash_equals() {
    local path="$1" expected_hash="$2" msg="${3:-hash stable: $1}"
    if [[ ! -f "$path" ]]; then
        fail "$msg (file missing: $path)"
        return
    fi
    local actual
    actual=$(hash_file "$path")
    if [[ "$actual" == "$expected_hash" ]]; then
        pass "$msg"
    else
        fail "$msg (expected $expected_hash, got $actual)"
    fi
}

assert_equals() {
    local actual="$1" expected="$2" msg="${3:-value equals}"
    if [[ "$actual" == "$expected" ]]; then
        pass "$msg"
    else
        fail "$msg (expected '$expected', got '$actual')"
    fi
}

# ---------------------------------------------------------------------------
# Scratch-dir lifecycle
# ---------------------------------------------------------------------------
# Declare as empty array. With `set -u`, expanding an empty array with
# "${arr[@]}" is an unbound-variable error in bash <= 4.3, so we gate
# every expansion on a length check.
_SCRATCH_DIRS=()

scratch_dir() {
    # Create a temp dir, register it for cleanup, echo its path.
    local prefix="${1:-forge}"
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    _SCRATCH_DIRS+=("$dir")
    echo "$dir"
}

cleanup_scratch_dirs() {
    # Called from EXIT trap. Preserves dirs if the script is exiting with
    # non-zero AND KEEP_TMP_ON_FAIL=1 is set. Also preserves if KEEP_TMP=1.
    local rc=$?
    # Guard against empty-array expansion under `set -u` on older bash.
    local count=${#_SCRATCH_DIRS[@]}
    [[ $count -eq 0 ]] && return
    if [[ "${KEEP_TMP:-0}" == "1" ]] || ( [[ "$rc" -ne 0 ]] && [[ "${KEEP_TMP_ON_FAIL:-0}" == "1" ]] ); then
        printf "%s(scratch dirs preserved for post-mortem):%s\n" "$C_YELLOW" "$C_RESET" >&2
        for d in "${_SCRATCH_DIRS[@]}"; do
            printf "  %s\n" "$d" >&2
        done
        return
    fi
    for d in "${_SCRATCH_DIRS[@]}"; do
        [[ -d "$d" ]] && rm -rf "$d"
    done
}

trap cleanup_scratch_dirs EXIT

# ---------------------------------------------------------------------------
# setup.sh invocation wrapper
# Captures stdout+stderr to a file; returns exit code in $? without aborting.
# ---------------------------------------------------------------------------
run_setup() {
    # Usage: run_setup <scratch_dir> <output_log_path> <setup.sh args...>
    # Confine HOME to a per-scratch fake home so setup's global writes (e.g. the
    # machine-stamp ~/.claude/.forge-version) never touch the real test runner's
    # ~/.claude. Tests that need to inspect the machine stamp read "$scratch/.fakehome".
    local scratch="$1" logfile="$2"
    shift 2
    mkdir -p "$scratch/.fakehome"
    (cd "$scratch" && HOME="$scratch/.fakehome" "${REPO_ROOT}/setup.sh" "$@") >"$logfile" 2>&1
    return $?
}

# ---------------------------------------------------------------------------
# Helper: generate the per-iter Code review clean lines for a given iter + head
# Used by existing E2E-gate tests to remain compatible with the v5.39 gate.
#
# Usage: make_code_review_clean_lines <N> <head_sha>
# Echoes 2 lines (one codex clean, one pr-toolkit clean) for iteration N.
# ---------------------------------------------------------------------------
make_code_review_clean_lines() {
    local n="$1" head="$2"
    printf -- '- [x] Code review iteration %s — codex clean — head=`%s`\n' "$n" "$head"
    printf -- '- [x] Code review iteration %s — pr-toolkit clean — head=`%s`\n' "$n" "$head"
}

# ---------------------------------------------------------------------------
# Helper: skip_test — record a no-op pass with a "skipped" message.
# Used by conditional tests (e.g., codex-availability-dependent) so the test
# count stays symmetric whether or not the precondition holds.
# ---------------------------------------------------------------------------
skip_test() {
    local msg="${1:-skipped}"
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  %s·%s skipped: %s\n" "$C_DIM" "$C_RESET" "$msg"
}
