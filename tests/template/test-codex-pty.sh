#!/usr/bin/env bash
# tests/template/test-codex-pty.sh — fixture tests for hooks/lib/codex-pty.sh.
#
# Verifies the shim's strict contract:
#   - Bypass env var skips PTY wrapping (direct exec, no python3 in tree)
#   - Default Unix path uses python3 pty.fork (child sees isatty=true)
#   - Real pty.fork integration works against a non-codex binary
#   - Stdin from /dev/null does not hang
#   - Bad first arg exits 2
#   - codex binary missing exits 127
#   - Shell metacharacters in args reach codex verbatim
#   - Header references the issue and env var contract
#
# Run from repo root:  bash tests/template/test-codex-pty.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

SHIM="$REPO_ROOT/hooks/lib/codex-pty.sh"

# ---------------------------------------------------------------------------
# Scratch fixture: builds a scratch dir with a mock `codex` binary that
# records its argv + isatty(stdin) into a result file. Returns the result.
#
# Args: $1 = result file path (mock codex writes here)
#       $2 = exit code mock codex should return
#
# Returns: prints the scratch dir path; caller is responsible for cleanup.
# ---------------------------------------------------------------------------
make_mock_codex() {
    local resultfile="$1" exitcode="${2:-0}"
    local scratch
    scratch=$(mktemp -d -t codex-pty-XXXXXX)
    cat > "$scratch/codex" <<EOF
#!/usr/bin/env bash
# mock codex
# Capture isatty status BEFORE redirecting stdout to the result file,
# otherwise [ -t 1 ] would test the redirected fd. Avoid \$(...) — the
# subshell's fd 1 is a pipe, not the parent's fd 1.
if [ -t 0 ]; then ATTY0=true; else ATTY0=false; fi
if [ -t 1 ]; then ATTY1=true; else ATTY1=false; fi
{
    printf 'argv='
    printf '%s\\n' "\$*"
    printf 'isatty_stdin=%s\\n' "\$ATTY0"
    printf 'isatty_stdout=%s\\n' "\$ATTY1"
} > '$resultfile'
exit $exitcode
EOF
    chmod +x "$scratch/codex"
    printf '%s' "$scratch"
}

cleanup_scratch() {
    [[ -n "${1:-}" && -d "$1" ]] && rm -rf "$1"
}

# ===========================================================================
# Section 1: Static contract — shim file structure
# ===========================================================================

start_test "shim file exists"
assert_file_exists "$SHIM"

start_test "shim has bash shebang"
assert_matches "$SHIM" "^#!/usr/bin/env bash"

start_test "shim header references openai/codex#19945"
assert_contains "$SHIM" "openai/codex#19945"

start_test "shim defines bypass env var by name"
assert_contains "$SHIM" "CLAUDE_FORGE_CODEX_PTY_BYPASS"

start_test "shim defines wsl opt-in env var by name"
# WSL is a Windows-side concern but Unix shim should still document the
# cross-shim env var contract for parity.
assert_contains "$SHIM" "CLAUDE_FORGE_CODEX_PTY_VIA_WSL"

start_test "shim references python3 pty.fork (the corrected primitive)"
# Shim header documents that the helper uses pty.fork() not pty.spawn();
# the helper file itself is asserted in the helper-direct tests below.
assert_contains "$SHIM" "pty.fork"

start_test "shim does NOT use bash printf %q quoting (would be \$SHELL-dependent)"
# After the iter-2 P1 correction, we don't use script(1)+%q anymore.
assert_not_contains "$SHIM" "printf '%q "

# ===========================================================================
# Section 2: Behavioral — bypass env var
# ===========================================================================

start_test "bypass env var skips pty wrapping (mock codex sees no tty)"
RESULT=$(mktemp)
SCRATCH=$(make_mock_codex "$RESULT" 0)
trap "cleanup_scratch '$SCRATCH'; rm -f '$RESULT'" EXIT
PATH="$SCRATCH:$PATH" CLAUDE_FORGE_CODEX_PTY_BYPASS=1 bash "$SHIM" exec --foo bar </dev/null >/dev/null 2>&1
exit_code=$?
if [[ -f "$RESULT" ]]; then
    if grep -q '^argv=exec --foo bar$' "$RESULT"; then
        pass "mock codex received argv verbatim"
    else
        fail "mock codex argv mismatch: $(cat "$RESULT")"
    fi
    if grep -q '^isatty_stdin=false$' "$RESULT"; then
        pass "stdin not a tty (bypass means no PTY allocation)"
    else
        fail "expected isatty_stdin=false under bypass, got: $(grep isatty_stdin "$RESULT")"
    fi
else
    fail "mock codex was never invoked (resultfile absent); shim exit=$exit_code"
fi

# ===========================================================================
# Section 3: Behavioral — default path uses python3 pty.fork
# ===========================================================================

start_test "default path on Darwin/Linux: mock codex sees isatty=true (PTY allocated)"
RESULT=$(mktemp)
SCRATCH=$(make_mock_codex "$RESULT" 0)
PATH="$SCRATCH:$PATH" bash "$SHIM" exec --foo bar </dev/null >/dev/null 2>&1
exit_code=$?
if [[ -f "$RESULT" ]]; then
    if grep -q '^argv=exec --foo bar$' "$RESULT"; then
        pass "mock codex received argv verbatim under PTY wrap"
    else
        fail "mock codex argv mismatch: $(cat "$RESULT")"
    fi
    if grep -q '^isatty_stdin=true$' "$RESULT"; then
        pass "stdin IS a tty (PTY allocation succeeded)"
    else
        fail "expected isatty_stdin=true under PTY wrap, got: $(grep isatty_stdin "$RESULT")"
    fi
    if grep -q '^isatty_stdout=true$' "$RESULT"; then
        pass "stdout IS a tty (PTY allocation succeeded)"
    else
        fail "expected isatty_stdout=true under PTY wrap, got: $(grep isatty_stdout "$RESULT")"
    fi
else
    fail "mock codex was never invoked under default path (resultfile absent); shim exit=$exit_code"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

# ===========================================================================
# Section 4: Behavioral — exit code propagation
# ===========================================================================

start_test "shim propagates mock codex exit 42"
RESULT=$(mktemp)
SCRATCH=$(make_mock_codex "$RESULT" 42)
set +e
PATH="$SCRATCH:$PATH" bash "$SHIM" exec </dev/null >/dev/null 2>&1
shim_exit=$?
set -e 2>/dev/null || true
assert_equals "$shim_exit" "42" "exit code 42 propagated through pty.fork"
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

# ===========================================================================
# Section 5: Behavioral — bad first arg
# ===========================================================================

start_test "first arg must be 'exec' — anything else exits 2"
set +e
bash "$SHIM" notexec --whatever </dev/null >/dev/null 2>/tmp/codex-pty-stderr.$$
shim_exit=$?
set -e 2>/dev/null || true
assert_equals "$shim_exit" "2" "exit 2 on bad first arg"
assert_matches "/tmp/codex-pty-stderr.$$" "codex-pty:.*usage" "stderr matches 'codex-pty: ...usage...'"
rm -f "/tmp/codex-pty-stderr.$$"

# ===========================================================================
# Section 6: Behavioral — codex binary missing
# ===========================================================================

start_test "codex not on PATH exits 127"
# Use empty PATH inside an inner bash invocation (outer bash is still located).
set +e
/bin/bash -c "PATH=/nonexistent /bin/bash '$SHIM' exec --whatever </dev/null >/dev/null 2>/tmp/codex-pty-127.$$"
shim_exit=$?
set -e 2>/dev/null || true
assert_equals "$shim_exit" "127" "exit 127 when codex binary not found"
assert_matches "/tmp/codex-pty-127.$$" "codex-pty:.*codex.*not found" "stderr matches 'codex-pty: codex not found'"
rm -f "/tmp/codex-pty-127.$$"

# ===========================================================================
# Section 7: Real-pty integration (iter-2 codex P2 fix — no codex mocked,
# real python3 + real pty.fork against /bin/echo)
# ===========================================================================

start_test "real pty.fork integration: shim wraps /bin/echo via mock 'codex' (data-path round-trip)"
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-real-XXXXXX)
# Mock codex that just exec's /bin/echo so we go through real pty.fork machinery.
cat > "$SCRATCH/codex" <<'EOF'
#!/usr/bin/env bash
# This mock proxies to /bin/echo to exercise real pty.fork end-to-end.
shift  # drop "exec"
exec /bin/echo "$@"
EOF
chmod +x "$SCRATCH/codex"
PATH="$SCRATCH:$PATH" bash "$SHIM" exec hello world </dev/null >"$RESULT" 2>&1
shim_exit=$?
# PTY translates \n → \r\n. Strip CR for matching.
output_clean=$(tr -d '\r' < "$RESULT")
if [[ "$shim_exit" -eq 0 ]] && grep -q '^hello world$' <<<"$output_clean"; then
    pass "real pty.fork round-trip ok (output=$(printf '%q' "$output_clean"), exit=$shim_exit)"
else
    fail "real pty.fork round-trip failed (output=$(printf '%q' "$output_clean"), exit=$shim_exit)"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

start_test "data-path round-trip via PTY: child stdout reaches parent stdout (iter-2 fix — was missing assertion)"
# Section 7 above could pass if /bin/echo got a regular pipe instead of a PTY,
# because /bin/echo writes the same bytes either way. This test asserts that
# bytes specifically written to the child's *stdout* arrive at the parent's
# captured stdout — proving the master_fd → STDOUT_FILENO data path works.
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-roundtrip-XXXXXX)
cat > "$SCRATCH/codex" <<'EOF'
#!/usr/bin/env bash
# Print a unique sentinel to stdout. If the parent captures it, the PTY
# data path is intact.
printf 'PTY_DATA_PATH_OK\n'
exit 0
EOF
chmod +x "$SCRATCH/codex"
PATH="$SCRATCH:$PATH" bash "$SHIM" exec </dev/null >"$RESULT" 2>&1
output_clean=$(tr -d '\r' < "$RESULT")
if grep -q '^PTY_DATA_PATH_OK$' <<<"$output_clean"; then
    pass "child stdout flows through pty master to parent stdout"
else
    fail "child stdout NOT received: $(printf '%q' "$output_clean")"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

start_test "long prompt regression test: 4KB argv survives PTY transit (#19945 repro)"
# The bug requires BOTH no-tty AND non-trivial prompt. Earlier tests covered
# no-tty with short args; this exercises the long-prompt trigger explicitly.
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-long-XXXXXX)
cat > "$SCRATCH/codex" <<'EOF'
#!/usr/bin/env bash
shift  # drop "exec"
# Echo back length of first arg so we can verify byte-count round-trip.
printf 'arg1_len=%d\n' ${#1}
EOF
chmod +x "$SCRATCH/codex"
LONG_PROMPT=$(printf 'x%.0s' $(seq 1 4096))
PATH="$SCRATCH:$PATH" bash "$SHIM" exec "$LONG_PROMPT" </dev/null >"$RESULT" 2>&1
shim_exit=$?
output_clean=$(tr -d '\r' < "$RESULT")
if [[ "$shim_exit" -eq 0 ]] && grep -q '^arg1_len=4096$' <<<"$output_clean"; then
    pass "4KB prompt round-tripped intact (out=$output_clean, exit=$shim_exit)"
else
    fail "long-prompt PTY transit failed (out=$(printf '%q' "$output_clean"), exit=$shim_exit)"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

start_test "signal-killed child returns 128+signum (SIGTERM=15 → 143)"
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-sig-XXXXXX)
cat > "$SCRATCH/codex" <<'EOF'
#!/usr/bin/env bash
kill -TERM $$
EOF
chmod +x "$SCRATCH/codex"
set +e
PATH="$SCRATCH:$PATH" bash "$SHIM" exec </dev/null >/dev/null 2>&1
shim_exit=$?
set -e 2>/dev/null || true
assert_equals "$shim_exit" "143" "exit 143 (=128+SIGTERM) for signal-killed child"
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

# ===========================================================================
# Section 8: Stdin from /dev/null does not hang (iter-2 codex P2 fix —
# pty.fork liveness gap)
# ===========================================================================

start_test "piped stdin EOF propagates to child (iter-3 smoke P1 fix — codex found this)"
# When parent's stdin is a pipe that closes, the child needs to see EOF on
# its end of the pty too. Without writing EOT to master, children that read
# stdin (e.g., /bin/cat with piped input) hang forever waiting for more data.
# Bug found by codex review of the v5.22 PR (iter-3 mcpgateway smoke).
HELPER="$REPO_ROOT/hooks/lib/codex-pty-helper.py"
RESULT=$(mktemp)
(
    printf 'hello-from-stdin\n' | python3 "$HELPER" /bin/cat > "$RESULT" 2>&1 &
    inner=$!
    ( sleep 5 && kill -9 $inner 2>/dev/null ) &
    watchdog=$!
    wait $inner 2>/dev/null
    rc=$?
    kill $watchdog 2>/dev/null
    exit $rc
)
piped_exit=$?
output_clean=$(tr -d '\r' < "$RESULT")
if [[ "$piped_exit" -eq 0 ]] && grep -q "^hello-from-stdin$" <<<"$output_clean"; then
    pass "piped stdin EOF cleanly propagated; child saw 'hello-from-stdin' and exited"
elif [[ "$piped_exit" -eq 137 ]]; then
    fail "shim hung on stdin EOF (regression — child never saw EOF). watchdog SIGKILL'd."
else
    fail "unexpected: exit=$piped_exit output=$(printf '%q' "$output_clean")"
fi
rm -f "$RESULT"

start_test "stdin EOF doesn't busy-loop (CPU regression test — iter-3 council P1 fix)"
# Contrarian + Maintainer empirically reproduced: before fix, wrapping sleep 2
# with </dev/null caused the helper to consume ~2 CPU-seconds (1.80 sys + 0.20
# user) versus near-zero CPU for plain sleep. Root cause: dup2(/dev/null, 0)
# kept fd 0 in select set; /dev/null is always selectable → busy-loop.
# Fixed by tracking stdin_open and dropping fd 0 from the select set after EOF.
HELPER="$REPO_ROOT/hooks/lib/codex-pty-helper.py"
# Use /usr/bin/time -p with portable POSIX output. Capture user+sys via awk.
# Wall: 1s. Allowed CPU budget: 0.50s (10x buffer over fixed-cost ~0.05s).
# Pre-fix observed: ~1 CPU-second for 1s wall, FAILS this assertion.
TIMING=$(/usr/bin/time -p python3 "$HELPER" /bin/sleep 1 </dev/null >/dev/null 2>&1; \
         /usr/bin/time -p python3 "$HELPER" /bin/sleep 1 </dev/null >/dev/null 2>/tmp/cputest.$$.txt
         cat /tmp/cputest.$$.txt)
rm -f /tmp/cputest.$$.txt
# Sum user + sys
CPU_TIME=$(awk '/^(user|sys) / {sum+=$2} END {print sum}' <<<"$TIMING")
# Compare as float — bash can't, but awk can
WITHIN_BUDGET=$(awk -v c="$CPU_TIME" 'BEGIN { print (c < 0.5) ? 1 : 0 }')
if [[ "$WITHIN_BUDGET" == "1" ]]; then
    pass "stdin-EOF wrap of sleep 1 used ${CPU_TIME}s CPU (well under 0.5s budget)"
else
    fail "stdin-EOF busy-loop regression: ${CPU_TIME}s CPU for 1s wall (was: ~1.0s before iter-3 fix)"
fi

start_test "stdin from /dev/null does not block shim (timeout-bounded)"
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-sleep-XXXXXX)
# Mock that exits quickly regardless of stdin
cat > "$SCRATCH/codex" <<'EOF'
#!/usr/bin/env bash
exec /bin/sleep 0.5
EOF
chmod +x "$SCRATCH/codex"
# Wrap the shim invocation in a bash subshell with our own watchdog.
# If shim runs > 5s, kill it (test fails). If <= 5s, exit code reflects shim's.
(
    PATH="$SCRATCH:$PATH" bash "$SHIM" exec </dev/null >"$RESULT" 2>&1 &
    pid=$!
    # Watchdog
    ( sleep 5 && kill -9 $pid 2>/dev/null && echo "WATCHDOG_KILLED" >&2 ) &
    watchdog=$!
    wait $pid 2>/dev/null
    inner_exit=$?
    kill $watchdog 2>/dev/null
    exit $inner_exit
)
shim_exit=$?
if [[ "$shim_exit" -eq 0 ]]; then
    pass "shim exited cleanly with stdin from /dev/null (no hang)"
elif [[ "$shim_exit" -eq 137 ]]; then  # SIGKILL exit
    fail "shim hung with stdin from /dev/null — watchdog killed it"
else
    pass "shim exited with code $shim_exit but did not hang"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

# ===========================================================================
# Section 9: Shell metacharacters in args reach codex verbatim
# ===========================================================================

start_test "args with shell metachars (\$ ' \" ;) reach mock codex unchanged"
RESULT=$(mktemp)
SCRATCH=$(make_mock_codex "$RESULT" 0)
# Construct an arg with awkward chars. We compare argv literally via grep -F.
TRICKY="prompt with \$VAR 'single' \"double\" ;semi"
PATH="$SCRATCH:$PATH" bash "$SHIM" exec "$TRICKY" </dev/null >/dev/null 2>&1
if [[ -f "$RESULT" ]]; then
    # Mock prints argv space-joined. We expect to see TRICKY verbatim in argv.
    if grep -qF -- "$TRICKY" "$RESULT"; then
        pass "tricky arg preserved through pty.fork"
    else
        fail "tricky arg corrupted: expected $(printf '%q' "$TRICKY"), got argv=$(grep '^argv=' "$RESULT")"
    fi
else
    fail "mock codex never invoked"
fi
cleanup_scratch "$SCRATCH"; rm -f "$RESULT"

# ===========================================================================
# Section 10: Helper-direct unit tests (iter-2 codex P2 fix —
# codex-pty-helper.py was previously exercised only transitively)
# ===========================================================================

HELPER="$REPO_ROOT/hooks/lib/codex-pty-helper.py"

start_test "helper: missing argv exits 2"
set +e
python3 "$HELPER" </dev/null >/dev/null 2>/tmp/helper-stderr.$$
helper_exit=$?
set -e 2>/dev/null || true
assert_equals "$helper_exit" "2" "helper exits 2 with no command argv"
assert_matches "/tmp/helper-stderr.$$" "codex-pty-helper:.*usage" "helper stderr matches usage"
rm -f "/tmp/helper-stderr.$$"

start_test "helper: command not found exits 127 with diagnostic"
set +e
python3 "$HELPER" /nonexistent/binary-name </dev/null >/tmp/helper-127.$$ 2>&1
helper_exit=$?
set -e 2>/dev/null || true
assert_equals "$helper_exit" "127" "helper propagates exit 127 for FileNotFoundError"
output_clean=$(tr -d '\r' < "/tmp/helper-127.$$")
if grep -q "command not found" <<<"$output_clean"; then
    pass "helper emits 'command not found' diagnostic on FileNotFoundError"
else
    fail "helper did not emit FileNotFoundError diagnostic: $(printf '%q' "$output_clean")"
fi
rm -f "/tmp/helper-127.$$"

start_test "helper: signal-killed child returns 128+signum"
SCRATCH=$(mktemp -d -t codex-pty-helpsig-XXXXXX)
cat > "$SCRATCH/suicide" <<'EOF'
#!/usr/bin/env bash
kill -TERM $$
EOF
chmod +x "$SCRATCH/suicide"
set +e
python3 "$HELPER" "$SCRATCH/suicide" </dev/null >/dev/null 2>&1
helper_exit=$?
set -e 2>/dev/null || true
assert_equals "$helper_exit" "143" "helper returns 128+SIGTERM (=143) for signal-killed child"
cleanup_scratch "$SCRATCH"

# ===========================================================================
# Section 11: Fallback paths (iter-2 codex P2 fix — was 100% uncovered)
# ===========================================================================

start_test "fallback: helper file missing → return 3 with installation-defect diagnostic"
RESULT=$(mktemp)
SCRATCH=$(mktemp -d -t codex-pty-nohelp-XXXXXX)
SCRATCH_BIN="$SCRATCH/bin"
mkdir -p "$SCRATCH_BIN"
# Mock codex (so codex availability check passes)
cat > "$SCRATCH_BIN/codex" <<'EOF'
#!/usr/bin/env bash
echo "MOCK_CODEX_RAN_DIRECTLY"
exit 0
EOF
chmod +x "$SCRATCH_BIN/codex"
# Copy shim WITHOUT the helper sibling
cp "$SHIM" "$SCRATCH/codex-pty.sh"
set +e
PATH="$SCRATCH_BIN:$PATH" bash "$SCRATCH/codex-pty.sh" exec --foo </dev/null >/dev/null 2>"/tmp/nohelp-stderr.$$"
shim_exit=$?
set -e 2>/dev/null || true
assert_equals "$shim_exit" "3" "shim exits 3 (installation defect) when helper missing"
assert_matches "/tmp/nohelp-stderr.$$" "codex-pty:.*helper not found" "stderr matches 'codex-pty: helper not found'"
assert_matches "/tmp/nohelp-stderr.$$" "installation defect" "stderr names it as installation defect"
cleanup_scratch "$SCRATCH"; rm -f "$RESULT" "/tmp/nohelp-stderr.$$"

# ===========================================================================
report "test-codex-pty.sh"
