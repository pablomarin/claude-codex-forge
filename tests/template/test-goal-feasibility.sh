#!/usr/bin/env bash
# Deterministic authorization-boundary fixtures. Does not call either engine.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

start_test "global setup owns the only operator goal authorization writer"
S=$(scratch_dir goal-feasibility)
H="$S/home"
mkdir -p "$S/project"
(cd "$S/project" && git init -q)
HOME="$H" "$REPO_ROOT/setup.sh" --global > "$S/global.log" 2>&1
WRITER=$(cd "$H/.forge/bin" && printf '%s/%s\n' "$(pwd -P)" forge-goal-authorize)
CAPTURE=$(cd "$H/.forge/bin" && printf '%s/%s\n' "$(pwd -P)" forge-goal-capture)
H=$(cd "$H" && pwd -P)
assert_file_exists "$WRITER" "operator writer installed outside project"
assert_file_exists "$CAPTURE" "operator TUI capture helper installed outside project"
CODEX_IDENTITY="$H/.forge/bin/codex.identity"
assert_file_exists "$CODEX_IDENTITY" "global setup records the independently selected Codex identity"
assert_file_exists "$CODEX_IDENTITY.sha256" "Codex identity has a no-write integrity sidecar"

start_test "installed Claude profiles protect the complete global helper and identity boundary"
PROFILE_PROJECT="$S/profile-project"
mkdir -p "$PROFILE_PROJECT"
(cd "$PROFILE_PROJECT" && git init -q && HOME="$H" "$REPO_ROOT/setup.sh" > "$S/profile-project.log" 2>&1)
ln -s "$H/.forge/bin" "$PROFILE_PROJECT/global-bin-alias"
python3 - "$H" "$H/.claude/settings.json" "$PROFILE_PROJECT/.claude/settings.json" \
  "$REPO_ROOT/settings/settings-windows.template.json" "$PROFILE_PROJECT/global-bin-alias" <<'PY' > "$S/bin-profile.out" 2>&1
import json, os, pathlib, sys
home = pathlib.Path(sys.argv[1]).resolve()
alias = pathlib.Path(sys.argv[5]).resolve()
targets = [
    home / ".forge/bin/forge-goal-authorize",
    home / ".forge/bin/forge-goal-authorize.sha256",
    home / ".forge/bin/forge-goal-capture",
    home / ".forge/bin/forge-goal-capture.sha256",
    home / ".forge/bin/codex.identity",
    home / ".forge/bin/codex.identity.sha256",
    alias / "forge-goal-authorize",
    alias / "forge-goal-authorize.sha256",
    alias / "forge-goal-capture",
    alias / "forge-goal-capture.sha256",
    alias / "codex.identity",
    alias / "codex.identity.sha256",
]
for settings_path in map(pathlib.Path, sys.argv[2:5]):
    settings = json.loads(settings_path.read_text())
    denied = settings["permissions"]["deny"]
    assert "Write(~/.forge/bin/**)" in denied, (settings_path, denied)
    assert "Edit(~/.forge/bin/**)" in denied, (settings_path, denied)
    assert any(rule.startswith("Bash(") and ".forge/bin" in rule for rule in denied), (settings_path, denied)
    sandbox = settings["sandbox"]
    assert sandbox["enabled"] is True and sandbox["failIfUnavailable"] is True
    roots = [pathlib.Path(p.replace("~/", str(home) + os.sep)).resolve(strict=False)
             for p in sandbox["filesystem"]["denyWrite"]]
    for target in targets:
        resolved = target.resolve(strict=False)
        assert any(resolved == root or root in resolved.parents for root in roots), (settings_path, resolved, roots)
print("protected")
PY
assert_equals "$(cat "$S/bin-profile.out")" "protected" "Unix project, Windows project, and global profiles block helper/seal mutation through direct, variable, and alias paths"
assert_contains "$PROFILE_PROJECT/.codex/config.toml" 'writable_roots = [".forge/local"]' "Codex workspace sandbox exposes only the project-local Forge state root"
assert_not_contains "$PROFILE_PROJECT/.codex/config.toml" '.forge/bin' "Codex workspace sandbox never adds the global helper boundary"

HOME="$H" "$WRITER" --project "$S/project" --objective-hash obj123 \
    --nonce 11111111-1111-4111-8111-111111111111 --ceiling 3 > "$S/write.log" 2>&1
assert_equals "$?" "0" "direct physical separate-terminal authorization succeeds without a fabricated prereceipt"
assert_contains "$S/write.log" 'AUTHORIZED:' "writer reports the exact owned record"
AUTH=$(find "$H/.forge/goal-authorizations" -type f | head -1)
assert_file_exists "$AUTH" "authorization record lives in trusted global tree"
assert_contains "$AUTH" 'objective_hash=obj123' "authorization binds objective hash"
assert_contains "$AUTH" 'ceiling=3' "authorization binds immutable ceiling"
assert_contains "$AUTH" 'approval_channel=physical-operator-action' "authorization records the physical operator action"
if grep -Eq '^writer_revision=[0-9a-f]{64}$' "$AUTH"; then
    pass "authorization binds the exact writer source revision"
else
    fail "authorization writer revision is not a SHA-256 source identity"
fi
assert_contains "$REPO_ROOT/settings/settings.template.json" 'Bash(*.forge/goal-authorizations*:*)' "Claude denies shell indirection into authorization records"
assert_contains "$REPO_ROOT/settings/global-settings.template.json" 'Bash(*.forge/goal-authorizations*:*)' "global Claude profile denies shell indirection into authorization records"

start_test "authorization nonce is no-clobber under replay and concurrency"
AUTH_HASH=$(hash_file "$AUTH")
HOME="$H" "$WRITER" --project "$S/project" --objective-hash replacement \
    --nonce 11111111-1111-4111-8111-111111111111 --ceiling 99 > "$S/replay.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "replay/ceiling replacement is rejected" || fail "replay replaced an existing authorization"
assert_hash_equals "$AUTH" "$AUTH_HASH" "replay leaves the original authorization byte-identical"

CONCURRENT_NONCE=44444444-4444-4444-8444-444444444444
(HOME="$H" "$WRITER" --project "$S/project" --objective-hash concurrent \
    --nonce "$CONCURRENT_NONCE" --ceiling 2 > "$S/concurrent-1.log" 2>&1; printf '%s\n' "$?" > "$S/concurrent-1.rc") &
p1=$!
(HOME="$H" "$WRITER" --project "$S/project" --objective-hash concurrent \
    --nonce "$CONCURRENT_NONCE" --ceiling 2 > "$S/concurrent-2.log" 2>&1; printf '%s\n' "$?" > "$S/concurrent-2.rc") &
p2=$!
wait "$p1"; wait "$p2"
CONCURRENT_SUCCESS=$(grep -hxc '0' "$S/concurrent-1.rc" "$S/concurrent-2.rc" | awk '{s+=$1} END {print s+0}')
assert_equals "$CONCURRENT_SUCCESS" "1" "exactly one concurrent operator authorization wins"
CONCURRENT_RECORDS=$(find "$H/.forge/goal-authorizations" -name "$CONCURRENT_NONCE.auth" -type f | wc -l | tr -d ' ')
assert_equals "$CONCURRENT_RECORDS" "1" "concurrent issue creates one immutable authorization record"

start_test "writer rejects aliases, indirection, alternate roots, and copied-helper invocation"
HOME="$H" "$WRITER" --root "$S/project" --project "$S/project" --objective-hash obj \
    --nonce 22222222-2222-4222-8222-222222222222 --ceiling 1 > "$S/root.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "alternate authorization root is rejected" || fail "alternate authorization root was accepted"
python3 - "$H/.claude/settings.json" "$WRITER" <<'PY' > "$S/variable.log" 2>&1
import json, pathlib, sys
settings = json.loads(pathlib.Path(sys.argv[1]).read_text())
command = pathlib.Path(sys.argv[2]).resolve()
denied = settings["permissions"]["deny"]
assert any("forge-goal-authorize" in rule and rule.startswith("Bash(") for rule in denied), denied
assert command.name == "forge-goal-authorize"
print("blocked-before-exec")
PY
assert_equals "$(cat "$S/variable.log")" "blocked-before-exec" "real installed agent profile rejects variable-indirected writer before execution"
assert_file_missing "$H/.forge/goal-authorizations/$(dirname "${AUTH#$H/.forge/goal-authorizations/}")/55555555-5555-4555-8555-555555555555.auth" "agent-profile variable attempt creates no record"

mv "$WRITER" "$H/.forge/bin/writer-real"
ln -s writer-real "$WRITER"
HOME="$H" "$WRITER" \
    --project "$S/project" --objective-hash symlink \
    --nonce 66666666-6666-4666-8666-666666666666 --ceiling 1 > "$S/symlink.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "symlinked writer is rejected even with a matching receipt" || fail "symlinked writer bypassed physical-path validation"
rm "$WRITER"
mv "$H/.forge/bin/writer-real" "$WRITER"

cp "$WRITER" "$S/project/copied-writer"
chmod +x "$S/project/copied-writer"
HOME="$H" "$S/project/copied-writer" --project "$S/project" --objective-hash obj \
    --nonce 33333333-3333-4333-8333-333333333333 --ceiling 1 > "$S/copied.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "copied writer outside trusted bin is rejected" || fail "copied writer was accepted"

ln -s "$H/.forge/goal-authorizations" "$S/project/direct-record-alias"
python3 - "$H/.claude/settings.json" "$H" "$S/project/direct-record-alias/forged.auth" <<'PY' > "$S/profile.out" 2>&1
import json, os, pathlib, sys
settings = json.loads(pathlib.Path(sys.argv[1]).read_text())
home = pathlib.Path(sys.argv[2]).resolve()
candidate = pathlib.Path(sys.argv[3]).resolve(strict=False)
sandbox = settings["sandbox"]
assert sandbox["enabled"] is True
assert sandbox["failIfUnavailable"] is True
assert sandbox["allowUnsandboxedCommands"] is False
denied = [pathlib.Path(p.replace("~/", str(home) + os.sep)).resolve(strict=False)
          for p in sandbox["filesystem"]["denyWrite"]]
assert any(candidate == root or root in candidate.parents for root in denied), (candidate, denied)
print("blocked")
PY
assert_equals "$(cat "$S/profile.out")" "blocked" "installed OS sandbox profile resolves a direct-record symlink alias into the denied tree"

start_test "project setup reports global goal boundary instead of creating it"
P="$S/project-only"
mkdir -p "$P"
(cd "$P" && git init -q)
(cd "$P" && HOME="$S/empty-home" "$REPO_ROOT/setup.sh" > "$S/project.log" 2>&1)
assert_contains "$S/project.log" 'GOAL_OVERLAY: BLOCKED' "project setup reports goal boundary blocked"
assert_contains "$S/project.log" 'setup.sh --global' "project setup prints exact global remediation"
assert_file_missing "$P/.forge/bin/forge-goal-authorize" "project setup does not install authorization writer"

start_test "operator capture rejects arbitrary CLIs and exposes only setup-bound structural eligibility"
OPERATOR_INPUT="$S/operator-input"
mkdir -p "$OPERATOR_INPUT" "$S/operator-bin"
FAKE_CODEX="$S/operator-bin/codex"
cat > "$FAKE_CODEX" <<'EOF'
#!/bin/sh
case "$*" in
  --version) echo 'codex-cli 9.9.1'; exit 0 ;;
  --help|'exec --help') echo '--ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir'; exit 0 ;;
esac
echo 'codex exec is not a native /goal activation' >&2
exit 72
EOF
chmod +x "$FAKE_CODEX"
FAKE_CODEX=$(cd "$(dirname "$FAKE_CODEX")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$FAKE_CODEX")")
PROJECT_ROOT=$(cd "$P" && pwd -P)
SESSION=77777777-7777-4777-8777-777777777777
cat > "$OPERATOR_INPUT/codex.tui" <<EOF
capture_channel=operator-codex-tui
cli_path=$FAKE_CODEX
cli_version=codex-cli 9.9.1
session_id=$SESSION
project_root=$PROJECT_ROOT
command=/goal
/goal activated
status captured
pause captured
checkpoint resumed
FORGE_GOAL_BUDGET_EXHAUSTED
FORGE_GOAL_STUCK_WARNING
EOF
cat > "$OPERATOR_INPUT/codex.result" <<'EOF'
native_activation=PASS
checkpoint_resume=PASS
budget_oracle=PASS
stuck_oracle=PASS
EOF
HOME="$H" "$CAPTURE" --project "$P" --cli "$FAKE_CODEX" --session-id "$SESSION" \
  --transcript "$OPERATOR_INPUT/codex.tui" --result "$OPERATOR_INPUT/codex.result" > "$S/capture-fake.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "capture helper rejects arbitrary fake-marker --cli authority" || fail "fake-marker CLI minted a live/manual capture"
CAPTURE_COUNT=$(find "$H/.forge/goal-captures" -name capture.receipt -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$CAPTURE_COUNT" "0" "fake-marker CLI creates no trusted receipt"

FIXTURE_HOME="$S/fixture-home"
HOME="$FIXTURE_HOME" PATH="$S/operator-bin:$PATH" FORGE_ENGINE_IDENTITY_FIXTURE=1 \
  "$REPO_ROOT/setup.sh" --global > "$S/fixture-global.log" 2>&1
FIXTURE_IDENTITY="$FIXTURE_HOME/.forge/bin/codex.identity"
assert_contains "$FIXTURE_IDENTITY" 'identity_class=fixture-only' "deterministic fake-engine setup labels its identity fixture-only"
assert_contains "$FIXTURE_IDENTITY" 'status=QUALIFIED' "fixture identity can exercise the complete capability schema"
HOME="$FIXTURE_HOME" "$FIXTURE_HOME/.forge/bin/forge-goal-capture" --validate-binding --project "$P" > "$S/fixture-binding.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "fixture-only setup identity can never become a live/manual capture authority" || fail "fixture-only identity became structurally eligible"
FIXTURE_CAPTURE_COUNT=$(find "$FIXTURE_HOME/.forge/goal-captures" -name capture.receipt -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$FIXTURE_CAPTURE_COUNT" "0" "fixture-only validation creates no live/manual receipt"

IDENTITY_CLASS=$(sed -n 's/^identity_class=//p' "$CODEX_IDENTITY")
IDENTITY_STATUS=$(sed -n 's/^status=//p' "$CODEX_IDENTITY")
HOME="$H" "$CAPTURE" --validate-binding --project "$P" > "$S/binding.log" 2>&1
rc=$?
if [ "$IDENTITY_CLASS" = operator-setup ] && [ "$IDENTITY_STATUS" = QUALIFIED ]; then
    assert_equals "$rc" "0" "setup-bound non-fixture Codex identity is structurally eligible"
    assert_contains "$S/binding.log" 'STRUCTURALLY_ELIGIBLE:' "binding probe makes no authenticated TUI claim"
else
    [ "$rc" -ne 0 ] && pass "absent or fixture-only Codex identity remains structurally ineligible" || fail "fixture/absent identity became structurally eligible"
fi
CAPTURE_COUNT=$(find "$H/.forge/goal-captures" -name capture.receipt -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$CAPTURE_COUNT" "0" "structural binding probe never fabricates authenticated TUI evidence"

cp "$CODEX_IDENTITY" "$S/codex.identity.saved"
printf '\ntampered=true\n' >> "$CODEX_IDENTITY"
HOME="$H" "$CAPTURE" --validate-binding --project "$P" > "$S/tampered-identity.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "changed setup-recorded Codex identity is rejected by its exact hash" || fail "tampered Codex identity remained eligible"
cp "$S/codex.identity.saved" "$CODEX_IDENTITY"

cat > "$P/fake-codex-exec.receipt" <<EOF
format=forge-codex-goal-tui-capture-v3
engine=codex
command=/goal
capture_channel=physical-operator-action
project_root=$PROJECT_ROOT
cli_path=$FAKE_CODEX
fixture_only=true
EOF
HOME="$H" "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" --engine codex --project-root "$P" \
  --trusted-capture "$P/fake-codex-exec.receipt" --output "$S/codex-exec-rejected.json" > "$S/codex-exec-rejected.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "workspace-authored or fake codex exec receipt cannot certify native /goal" || fail "workspace fake receipt certified native /goal"
assert_contains "$S/codex-exec-rejected.json" '"status":"BLOCKED"' "workspace/fake-schema receipt remains BLOCKED"

start_test "fake Claude driver exercises the authenticated native goal start and exact resume oracle"
FAKE_CLAUDE="$S/operator-bin/claude"
cat > "$FAKE_CLAUDE" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) echo 'claude-code 9.9.1'; exit 0 ;;
  --help) echo '--safe-mode --strict-mcp-config --setting-sources --session-id --resume'; exit 0 ;;
esac
printf '%s\n' "$*" >> "$FORGE_FAKE_GOAL_ARGV_LOG"
session="$FORGE_GOAL_SESSION_ID"
case "$*" in
  *--session-id*) printf 'native_activation=PASS\nphase=implementation\nnext_step=resume-verification\nprogress=fingerprint-a\nsession_id=%s\n' "$session" ;;
  *--resume*)
    [ "${FORGE_FAKE_GOAL_FAILURE:-}" != stale-session ] || session=wrong-session
    printf 'checkpoint_resume=PASS\nphase=verification\nnext_step=budget-check\nprogress=fingerprint-a\nsession_id=%s\nFORGE_GOAL_BUDGET_EXHAUSTED\npaused=true\nFORGE_GOAL_STUCK_WARNING\n' "$session" ;;
  *) exit 73 ;;
esac
EOF
chmod +x "$FAKE_CLAUDE"
HOME="$H" "$WRITER" --project "$P" --objective-hash native-goal \
  --nonce 88888888-8888-4888-8888-888888888888 --ceiling 1 > "$S/native-auth.log" 2>&1
NATIVE_AUTH=$(find "$H/.forge/goal-authorizations" -name '88888888-8888-4888-8888-888888888888.auth' -type f)
: > "$S/claude-live.argv"
HOME="$H" FORGE_FAKE_GOAL_ARGV_LOG="$S/claude-live.argv" \
  "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" --test-live-driver --engine-path "$FAKE_CLAUDE" \
  --authorization "$NATIVE_AUTH" --engine claude --project-root "$P" --output "$S/claude-live.json" > "$S/claude-live.log" 2>&1
assert_equals "$?" "0" "Claude fake driver passes through the real live proving adapter"
assert_contains "$S/claude-live.json" '"status":"PASS"' "Claude live adapter/oracle can reach PASS"
assert_contains "$S/claude-live.argv" '--safe-mode --strict-mcp-config' "Claude goal start uses the isolated safe-mode recipe"
assert_contains "$S/claude-live.argv" '--resume 22222222-2222-4222-8222-' "Claude goal driver resumes the exact session"
FORGE_FAKE_GOAL_FAILURE=stale-session HOME="$H" FORGE_FAKE_GOAL_ARGV_LOG="$S/claude-live.argv" \
  "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" --test-live-driver --engine-path "$FAKE_CLAUDE" \
  --authorization "$NATIVE_AUTH" --engine claude --project-root "$P" --output "$S/claude-stale.json" > "$S/claude-stale.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "Claude stale-session resume evidence is rejected" || fail "Claude stale-session evidence was accepted"
assert_contains "$S/claude-stale.json" '"status":"BLOCKED"' "stale-session result remains BLOCKED"

start_test "deterministic native goal proving slice passes and fails through fake engines"
FAKE_BIN="$S/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/forge-goal-engine" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) echo "${FORGE_FAKE_ENGINE_NAME:-fake} 1.0"; exit 0 ;;
  --help) echo '--session-id --resume --no-session-persistence'; exit 0 ;;
esac
[ "${FORGE_FAKE_GOAL_FAILURE:-}" != "${FORGE_GOAL_FIXTURE_ACTION:-}" ] || exit 71
case "${FORGE_GOAL_FIXTURE_ACTION:-}" in
  activate)
    printf 'phase=implementation\nnext_step=resume-verification\nprogress=fingerprint-a\nsession_id=%s\n' "$FORGE_GOAL_SESSION_ID" > "$FORGE_GOAL_FIXTURE_DIR/checkpoint"
    printf 'native-activation:%s\n' "$FORGE_GOAL_SESSION_ID"
    ;;
  resume)
    grep -q "session_id=$FORGE_GOAL_SESSION_ID" "$FORGE_GOAL_FIXTURE_DIR/checkpoint" || exit 72
    printf 'phase=verification\nnext_step=budget-check\nprogress=fingerprint-a\nsession_id=%s\n' "$FORGE_GOAL_SESSION_ID" > "$FORGE_GOAL_FIXTURE_DIR/checkpoint"
    printf 'checkpoint-resume:%s\n' "$FORGE_GOAL_SESSION_ID"
    ;;
  manual-tui)
    printf '/goal activated\ncheckpoint resumed\nFORGE_GOAL_BUDGET_EXHAUSTED\nFORGE_GOAL_STUCK_WARNING\n' > "$FORGE_GOAL_TRANSCRIPT"
    printf 'native_activation=PASS\ncheckpoint_resume=PASS\nbudget_oracle=PASS\nstuck_oracle=PASS\n' > "$FORGE_GOAL_RESULT"
    ;;
  *) exit 73 ;;
esac
EOF
chmod +x "$FAKE_BIN/forge-goal-engine"
ln -s forge-goal-engine "$FAKE_BIN/claude"
ln -s forge-goal-engine "$FAKE_BIN/codex"

for engine in claude codex; do
    FORGE_FAKE_ENGINE_NAME="$engine" PATH="$FAKE_BIN:/usr/bin:/bin" \
        "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" --fixture-mode \
        --engine "$engine" --project-root "$P" --output "$S/$engine-goal.json" > "$S/$engine-goal.log" 2>&1
    assert_equals "$?" "0" "$engine fake native goal fixture exits zero"
    assert_contains "$S/$engine-goal.json" '"status":"PASS"' "$engine fake native goal fixture attests PASS"
    assert_contains "$S/$engine-goal.json" '"checkpoint_resume":"PASS"' "$engine exact checkpoint resume is proven"
    assert_contains "$S/$engine-goal.json" '"budget_oracle":"PASS"' "$engine budget exhaustion oracle is proven"
    assert_contains "$S/$engine-goal.json" '"stuck_oracle":"PASS"' "$engine stuck-progress oracle is proven"
done

FORGE_FAKE_ENGINE_NAME=claude FORGE_FAKE_GOAL_FAILURE=resume PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" --fixture-mode \
    --engine claude --project-root "$P" --output "$S/claude-goal-fail.json" > "$S/claude-goal-fail.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "fake goal resume failure exits nonzero" || fail "fake goal resume failure was accepted"
assert_contains "$S/claude-goal-fail.json" '"status":"BLOCKED"' "fake goal failure remains a truthful BLOCKED receipt"

report "test-goal-feasibility.sh"
