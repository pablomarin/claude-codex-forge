#!/usr/bin/env bash
# tests/template/test-forge-workflow.sh — runtime phase-gate controller tests.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

FW_SH="$REPO_ROOT/hooks/lib/forge-workflow.sh"
FW_PS="$REPO_ROOT/hooks/lib/forge-workflow.ps1"
HOOK_SH="$REPO_ROOT/hooks/check-phase-gates.sh"

make_runtime_repo() {
    local dir="$1"
    mkdir -p "$dir"
    (cd "$dir" && git init -q)
    mkdir -p "$dir/.claude/local" "$dir/docs/plans" "$dir/.claude/hooks/lib" "$dir/.claude/hooks"
    cp "$FW_SH" "$dir/.claude/hooks/lib/forge-workflow.sh"
    cp "$HOOK_SH" "$dir/.claude/hooks/check-phase-gates.sh"
    chmod +x "$dir/.claude/hooks/lib/forge-workflow.sh" "$dir/.claude/hooks/check-phase-gates.sh"
    cat > "$dir/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature test |
| Phase     | 3 — Design        |
| Next step | Plan review       |

### Checklist
EOF
}

json_value() {
    local file="$1" expr="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r "$expr" "$file"
    else
        grep -o '"status":"[^"]*"' "$file" | head -1 | cut -d: -f2 | tr -d '"'
    fi
}

run_gate_hook() {
    local dir="$1" payload="$2"
    (cd "$dir" && printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$dir" bash "$dir/.claude/hooks/check-phase-gates.sh") > "$dir/.hook-out" 2> "$dir/.hook-err"
    echo "$?"
}

# ---------------------------------------------------------------------------
start_test "open-gate creates state and event"
S1=$(scratch_dir forge-runtime-open)
make_runtime_repo "$S1"
(cd "$S1" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md > .out)
assert_file_exists "$S1/.claude/local/workflow-run.json" "workflow-run.json created"
assert_file_exists "$S1/.claude/local/workflow-events.jsonl" "workflow-events.jsonl created"
assert_equals "$(json_value "$S1/.claude/local/workflow-run.json" '.gates["phase-3-4"].status')" "pending" "gate status is pending"
assert_equals "$(json_value "$S1/.claude/local/workflow-run.json" '.plan_file')" "docs/plans/test.md" "plan_file stored"
assert_contains "$S1/.claude/local/workflow-events.jsonl" '"event":"gate_opened"' "gate_opened event appended"

# ---------------------------------------------------------------------------
start_test "open-gate is idempotent for same plan/gate"
(cd "$S1" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md > .out2)
event_count=$(grep -c '"event":"gate_opened"' "$S1/.claude/local/workflow-events.jsonl")
assert_equals "$event_count" "1" "second same open-gate does not duplicate event"

# ---------------------------------------------------------------------------
start_test "approve-gate validates mode and records approval"
S2=$(scratch_dir forge-runtime-approve)
make_runtime_repo "$S2"
(cd "$S2" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md >/dev/null)
(cd "$S2" && .claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode banana > .bad 2> .baderr)
assert_equals "$?" "2" "invalid mode exits 2"
assert_contains "$S2/.baderr" "invalid mode" "invalid mode explains failure"
(cd "$S2" && .claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode fresh-session > .good)
assert_equals "$(json_value "$S2/.claude/local/workflow-run.json" '.gates["phase-3-4"].status')" "approved" "gate status is approved"
assert_equals "$(json_value "$S2/.claude/local/workflow-run.json" '.gates["phase-3-4"].selected_mode')" "fresh-session" "selected mode stored"
assert_contains "$S2/.claude/local/workflow-events.jsonl" '"event":"gate_approved"' "gate_approved event appended"
(cd "$S2" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md > .reopen)
assert_equals "$(json_value "$S2/.claude/local/workflow-run.json" '.gates["phase-3-4"].status')" "approved" "open-gate does not reopen an approved gate for same plan"

# ---------------------------------------------------------------------------
start_test "pending gate blocks implementation Bash and allows read/status Bash"
S3=$(scratch_dir forge-runtime-bash)
make_runtime_repo "$S3"
(cd "$S3" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md >/dev/null)
rc=$(run_gate_hook "$S3" "{\"tool_name\":\"Bash\",\"cwd\":\"$S3\",\"tool_input\":{\"command\":\"python tiny_notes.py add x\"}}")
assert_equals "$rc" "2" "implementation Bash is blocked"
assert_contains "$S3/.hook-err" "PHASE_GATE_PENDING: phase-3-4" "blocker has stable prefix"
rc=$(run_gate_hook "$S3" "{\"tool_name\":\"Bash\",\"cwd\":\"$S3\",\"tool_input\":{\"command\":\"git status --short\"}}")
assert_equals "$rc" "0" "git status is allowed"
rc=$(run_gate_hook "$S3" "{\"tool_name\":\"Bash\",\"cwd\":\"$S3\",\"tool_input\":{\"command\":\"git status --short && pytest\"}}")
assert_equals "$rc" "2" "chained read-then-implementation Bash is blocked"
rc=$(run_gate_hook "$S3" "{\"tool_name\":\"Bash\",\"cwd\":\"$S3\",\"tool_input\":{\"command\":\"git diff > /tmp/patch.diff\"}}")
assert_equals "$rc" "2" "redirecting read output to a file is blocked"
rc=$(run_gate_hook "$S3" "{\"tool_name\":\"Bash\",\"cwd\":\"$S3\",\"tool_input\":{\"command\":\".claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode same-context\"}}")
assert_equals "$rc" "0" "approve-gate command is allowed while pending"

# ---------------------------------------------------------------------------
start_test "pending gate blocks source writes and allows .claude/local writes"
S4=$(scratch_dir forge-runtime-write)
make_runtime_repo "$S4"
(cd "$S4" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md >/dev/null)
rc=$(run_gate_hook "$S4" "{\"tool_name\":\"Write\",\"cwd\":\"$S4\",\"tool_input\":{\"file_path\":\"src/app.py\"}}")
assert_equals "$rc" "2" "source Write is blocked"
rc=$(run_gate_hook "$S4" "{\"tool_name\":\"Edit\",\"cwd\":\"$S4\",\"tool_input\":{\"file_path\":\".claude/local/state.md\"}}")
assert_equals "$rc" "0" ".claude/local Edit is allowed"

# ---------------------------------------------------------------------------
start_test "approved gate allows implementation"
S5=$(scratch_dir forge-runtime-approved)
make_runtime_repo "$S5"
(cd "$S5" && .claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/test.md >/dev/null)
(cd "$S5" && .claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode same-context >/dev/null)
rc=$(run_gate_hook "$S5" "{\"tool_name\":\"Bash\",\"cwd\":\"$S5\",\"tool_input\":{\"command\":\"pytest\"}}")
assert_equals "$rc" "0" "approved gate allows Bash implementation"
rc=$(run_gate_hook "$S5" "{\"tool_name\":\"Write\",\"cwd\":\"$S5\",\"tool_input\":{\"file_path\":\"src/app.py\"}}")
assert_equals "$rc" "0" "approved gate allows Write implementation"

# ---------------------------------------------------------------------------
start_test "settings and installers wire phase gate hooks"
assert_contains "$REPO_ROOT/settings/settings.template.json" "check-phase-gates.sh" "Unix settings register check-phase-gates"
assert_contains "$REPO_ROOT/settings/settings-windows.template.json" "check-phase-gates.ps1" "Windows settings register check-phase-gates"
assert_contains "$REPO_ROOT/setup.sh" "check-phase-gates.sh" "setup.sh installs check-phase-gates.sh"
assert_contains "$REPO_ROOT/setup.ps1" "check-phase-gates.ps1" "setup.ps1 installs check-phase-gates.ps1"
assert_contains "$REPO_ROOT/setup.sh" "forge-workflow.sh" "setup.sh installs forge-workflow.sh"
assert_contains "$REPO_ROOT/setup.ps1" "forge-workflow.ps1" "setup.ps1 installs forge-workflow.ps1"
assert_contains "$REPO_ROOT/commands/new-feature.md" "open-gate phase-3-4" "new-feature opens phase gate"
assert_contains "$REPO_ROOT/commands/fix-bug.md" "open-gate phase-3-4" "fix-bug opens phase gate"
for key in "phase-3-4" "PHASE_GATE_PENDING" "same-context" "compact" "fresh-session"; do
    assert_contains "$FW_SH" "$key" "forge-workflow.sh references $key"
    assert_contains "$FW_PS" "$key" "forge-workflow.ps1 references $key"
done
assert_file_exists "$REPO_ROOT/tests/template/fixtures/workflow-runtime/pending-phase-3-4.json" "pending workflow-runtime fixture exists"
assert_file_exists "$REPO_ROOT/tests/template/fixtures/workflow-runtime/approved-phase-3-4.json" "approved workflow-runtime fixture exists"

# Optional PowerShell parity smoke when pwsh is available.
start_test "PowerShell controller smoke (optional)"
if command -v pwsh >/dev/null 2>&1; then
    S6=$(scratch_dir forge-runtime-ps)
    make_runtime_repo "$S6"
    cp "$FW_PS" "$S6/.claude/hooks/lib/forge-workflow.ps1"
    (cd "$S6" && pwsh -NoProfile -File .claude/hooks/lib/forge-workflow.ps1 open-gate phase-3-4 --plan docs/plans/test.md > .ps-out 2> .ps-err)
    assert_equals "$?" "0" "PowerShell open-gate exits 0"
    assert_equals "$(json_value "$S6/.claude/local/workflow-run.json" '.gates["phase-3-4"].status')" "pending" "PowerShell writes pending status"
else
    pass "pwsh not installed — PowerShell smoke skipped"
fi

report "test-forge-workflow.sh"
