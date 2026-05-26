#!/usr/bin/env bash
# tests/template/test-merge-settings.sh — unit tests for scripts/merge-settings.py
#
# v5.32: deep-merge for hooks. Old shallow merge skipped entire hook events
# if they existed in user settings, which meant new hook commands added to
# the template (e.g., build-evidence.sh as a parallel Stop hook) never
# reached existing installs via --upgrade. This suite asserts that:
#
#   1. New top-level hook events still get added (existing behavior)
#   2. New COMMANDS inside existing matcher-blocks now get added (v5.32)
#   3. Existing commands are never duplicated (idempotent)
#   4. Permissions arrays still merge (existing behavior, regression guard)
#   5. enabledPlugins still merge (existing behavior, regression guard)

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

MERGE="$REPO_ROOT/scripts/merge-settings.py"

if ! command -v python3 >/dev/null 2>&1; then
    start_test "merge-settings.py — python3 not available, skipping"
    pass "python3 not on PATH — skip (not a failure)"
    report "test-merge-settings.sh"
    exit 0
fi

# ---------------------------------------------------------------------------
# Test 1: new command added to existing Stop matcher-block (v5.32 core case)
# ---------------------------------------------------------------------------
start_test "deep-merge: new command added to existing Stop matcher-block"

S1=$(scratch_dir merge-stop-new-command)

cat > "$S1/template.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/build-evidence.sh" },
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-state-updated.sh" }
        ]
      }
    ]
  }
}
EOF

# User has the OLD shape: only check-state-updated registered.
cat > "$S1/user.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-state-updated.sh" }
        ]
      }
    ]
  }
}
EOF

python3 "$MERGE" "$S1/template.json" "$S1/user.json" > "$S1/.out" 2>&1
rc1=$?
assert_equals "$rc1" "0" "merge exits 0"

# Use python to assert both commands present in user.json post-merge.
python3 -c "
import json, sys
with open('$S1/user.json') as f:
    s = json.load(f)
cmds = [h['command'] for b in s['hooks']['Stop'] for h in b['hooks']]
expected_be = '\$CLAUDE_PROJECT_DIR/.claude/hooks/build-evidence.sh'
expected_cs = '\$CLAUDE_PROJECT_DIR/.claude/hooks/check-state-updated.sh'
assert expected_be in cmds, f'build-evidence missing from merged user settings: {cmds}'
assert expected_cs in cmds, f'check-state-updated missing from merged user settings: {cmds}'
# build-evidence MUST come first (ordering matters for fingerprint side-channel)
be_idx = cmds.index(expected_be)
cs_idx = cmds.index(expected_cs)
assert be_idx < cs_idx, f'build-evidence ({be_idx}) must come before check-state-updated ({cs_idx})'
print('ok')
" > "$S1/.assert" 2>&1
if [[ "$(cat "$S1/.assert")" == "ok" ]]; then
    pass "user.json contains both commands in correct order"
else
    fail "post-merge assertion failed: $(cat "$S1/.assert")"
fi

# ---------------------------------------------------------------------------
# Test 2: idempotent — re-running merge does not duplicate commands
# ---------------------------------------------------------------------------
start_test "deep-merge idempotent — re-running does not duplicate commands"

# Run merge a second time. Should be a no-op.
python3 "$MERGE" "$S1/template.json" "$S1/user.json" > "$S1/.out2" 2>&1
rc2=$?
assert_equals "$rc2" "0" "second merge exits 0"

python3 -c "
import json
with open('$S1/user.json') as f:
    s = json.load(f)
cmds = [h['command'] for b in s['hooks']['Stop'] for h in b['hooks']]
be = '\$CLAUDE_PROJECT_DIR/.claude/hooks/build-evidence.sh'
cs = '\$CLAUDE_PROJECT_DIR/.claude/hooks/check-state-updated.sh'
assert cmds.count(be) == 1, f'build-evidence duplicated: {cmds}'
assert cmds.count(cs) == 1, f'check-state-updated duplicated: {cmds}'
print('ok')
" > "$S1/.assert2" 2>&1
if [[ "$(cat "$S1/.assert2")" == "ok" ]]; then
    pass "no duplication on re-merge"
else
    fail "idempotency check failed: $(cat "$S1/.assert2")"
fi

# ---------------------------------------------------------------------------
# Test 3: new top-level hook event (e.g., PreCompact) still gets added
#         (existing behavior — regression guard)
# ---------------------------------------------------------------------------
start_test "merge: new top-level hook event still added (regression guard)"

S3=$(scratch_dir merge-new-event)
cat > "$S3/template.json" <<'EOF'
{
  "hooks": {
    "PreCompact": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "/path/to/pre-compact.sh" } ] }
    ]
  }
}
EOF
cat > "$S3/user.json" <<'EOF'
{ "hooks": {} }
EOF
python3 "$MERGE" "$S3/template.json" "$S3/user.json" > /dev/null 2>&1
python3 -c "
import json
with open('$S3/user.json') as f: s = json.load(f)
assert 'PreCompact' in s['hooks'], 'PreCompact missing'
print('ok')
" > "$S3/.assert" 2>&1
if [[ "$(cat "$S3/.assert")" == "ok" ]]; then
    pass "new hook event added to user settings"
else
    fail "new-event check failed: $(cat "$S3/.assert")"
fi

# ---------------------------------------------------------------------------
# Test 4: new matcher-block added when template has a matcher user doesn't
# ---------------------------------------------------------------------------
start_test "deep-merge: new matcher-block appended when matcher absent in user"

S4=$(scratch_dir merge-new-matcher)
cat > "$S4/template.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/a.sh" } ] },
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "/b.sh" } ] }
    ]
  }
}
EOF
cat > "$S4/user.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/a.sh" } ] }
    ]
  }
}
EOF
python3 "$MERGE" "$S4/template.json" "$S4/user.json" > /dev/null 2>&1
python3 -c "
import json
with open('$S4/user.json') as f: s = json.load(f)
matchers = [b['matcher'] for b in s['hooks']['PreToolUse']]
assert 'Bash' in matchers and 'Edit' in matchers, f'expected both Bash and Edit, got {matchers}'
print('ok')
" > "$S4/.assert" 2>&1
if [[ "$(cat "$S4/.assert")" == "ok" ]]; then
    pass "new matcher-block (Edit) appended alongside existing (Bash)"
else
    fail "new-matcher check failed: $(cat "$S4/.assert")"
fi

# ---------------------------------------------------------------------------
# Test 5: permissions arrays still merge (regression guard for existing path)
# ---------------------------------------------------------------------------
start_test "merge: permissions arrays still append unique items"

S5=$(scratch_dir merge-permissions)
cat > "$S5/template.json" <<'EOF'
{ "permissions": { "allow": ["Read(*)", "Write(*)"], "deny": ["Bash(rm -rf /)"] } }
EOF
cat > "$S5/user.json" <<'EOF'
{ "permissions": { "allow": ["Read(*)"], "deny": [] } }
EOF
python3 "$MERGE" "$S5/template.json" "$S5/user.json" > /dev/null 2>&1
python3 -c "
import json
with open('$S5/user.json') as f: s = json.load(f)
assert 'Write(*)' in s['permissions']['allow'], 'new allow rule missing'
assert 'Bash(rm -rf /)' in s['permissions']['deny'], 'new deny rule missing'
assert s['permissions']['allow'].count('Read(*)') == 1, 'existing allow duplicated'
print('ok')
" > "$S5/.assert" 2>&1
if [[ "$(cat "$S5/.assert")" == "ok" ]]; then
    pass "permissions merged correctly"
else
    fail "permissions check failed: $(cat "$S5/.assert")"
fi

# ---------------------------------------------------------------------------
# Test 6 (Codex P2-2 regression guard): order-only changes must be persisted.
#
# Scenario: user already has both commands but in WRONG order — e.g., they
# installed an early v5.32 preview where check-state-updated came first, or
# they hand-edited their settings.json. The merge MUST rebuild the list in
# template order AND record the change so main() writes the file (an empty
# change list would silently skip the write, leaving the bad order).
# ---------------------------------------------------------------------------
start_test "deep-merge: order-only changes persist to disk (P2-2 regression)"

S6=$(scratch_dir merge-order-only)

cat > "$S6/template.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/path/A.sh" },
          { "type": "command", "command": "/path/B.sh" }
        ]
      }
    ]
  }
}
EOF

# User has both commands but in REVERSED order.
cat > "$S6/user.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/path/B.sh" },
          { "type": "command", "command": "/path/A.sh" }
        ]
      }
    ]
  }
}
EOF

python3 "$MERGE" "$S6/template.json" "$S6/user.json" > "$S6/.out" 2>&1

assert_contains "$S6/.out" "reordered hooks" \
    "merger recorded an order-only change in output"

python3 -c "
import json
with open('$S6/user.json') as f: s = json.load(f)
cmds = [h['command'] for b in s['hooks']['Stop'] for h in b['hooks']]
assert cmds == ['/path/A.sh', '/path/B.sh'], f'expected A,B order; got {cmds}'
print('ok')
" > "$S6/.assert" 2>&1
if [[ "$(cat "$S6/.assert")" == "ok" ]]; then
    pass "order-only change persisted: hooks list rebuilt as [A, B]"
else
    fail "order-only persistence check failed: $(cat "$S6/.assert")"
fi

report "test-merge-settings.sh"
