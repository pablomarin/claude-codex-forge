#!/usr/bin/env bash
# Deterministic captured-event contracts. Never invokes a live model or network.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

VERIFY="$REPO_ROOT/scripts/verify-runtime.sh"
FIXTURES="$REPO_ROOT/tests/template/fixtures/host-events"

start_test "Claude captured identity exposes provider/model but not actual effort"
bash "$VERIFY" identity --host claude --fixture "$FIXTURES/claude-2.1.237.json" \
    --invocation-hash fixture-claude > /tmp/forge-runtime-claude.$$ 2>&1
assert_equals "$?" "0" "Claude identity fixture parses"
assert_contains /tmp/forge-runtime-claude.$$ '"actual_provider":"anthropic"' "Claude provider is observable"
assert_contains /tmp/forge-runtime-claude.$$ '"actual_model":"claude-opus-4-1"' "Claude canonical model is observable"
assert_not_contains /tmp/forge-runtime-claude.$$ '"actual_effort"' "Claude effort is not invented"

start_test "Codex captured identity invents no actual provider/model/effort"
bash "$VERIFY" identity --host codex --fixture "$FIXTURES/codex-0.144.1.jsonl" \
    --invocation-hash fixture-codex > /tmp/forge-runtime-codex.$$ 2>&1
assert_equals "$?" "0" "Codex identity fixture parses"
assert_contains /tmp/forge-runtime-codex.$$ '"invocation_hash":"fixture-codex"' "Codex receipt binds requested invocation"
assert_not_contains /tmp/forge-runtime-codex.$$ '"actual_provider"' "Codex provider is not invented"
assert_not_contains /tmp/forge-runtime-codex.$$ '"actual_model"' "Codex model is not invented"
assert_not_contains /tmp/forge-runtime-codex.$$ '"actual_effort"' "Codex effort is not invented"

start_test "unsupported requested identity is rejected before launch"
bash "$VERIFY" identity --host codex --fixture "$FIXTURES/codex-0.144.1.jsonl" \
    --requested-model unsupported-model --invocation-hash bad > /tmp/forge-runtime-bad.$$ 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "unsupported model exits nonzero" || fail "unsupported model was accepted"

start_test "root and nested discovery enumerate each canonical rule once"
S=$(scratch_dir runtime-discovery)
mkdir -p "$S/project/nested/deeper" "$S/project/.forge/rules"
printf 'one\n' > "$S/project/.forge/rules/one.md"
printf 'two\n' > "$S/project/.forge/rules/two.md"
printf '<!-- forge:begin v6 -->\nRead .forge/instructions.md completely.\n<!-- forge:end v6 -->\n' > "$S/project/CLAUDE.md"
cp "$S/project/CLAUDE.md" "$S/project/AGENTS.md"
for cwd in "$S/project" "$S/project/nested/deeper"; do
    (cd "$cwd" && bash "$VERIFY" discovery --project-root "$S/project") > "$S/discovery.$(basename "$cwd")" 2>&1
    assert_equals "$?" "0" "discovery succeeds from $(basename "$cwd")"
    assert_contains "$S/discovery.$(basename "$cwd")" 'canonical_rule_count=2' "$(basename "$cwd") sees both canonical rules"
    assert_contains "$S/discovery.$(basename "$cwd")" 'duplicate_rule_count=0' "$(basename "$cwd") sees no duplicate rule policy"
done

start_test "deterministic dispatch qualification proves isolation, exact resume, and bounded replay"
Q="$S/qualification"
mkdir -p "$Q/bin" "$Q/project/.forge"
(cd "$Q/project" && git init -q && git config user.email forge@example.invalid && git config user.name Forge && printf 'caller\n' > caller.txt && git add caller.txt && git commit -qm caller)
cat > "$Q/bin/forge-dispatch-engine" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) echo "${FORGE_FAKE_ENGINE_NAME:-fake} 1.0"; exit 0 ;;
  --help) echo '--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable'; exit 0 ;;
esac
case "${FORGE_DISPATCH_FIXTURE_ACTION:-}" in
  ephemeral)
    [ "${FORGE_FAKE_CANARY_LEAK:-0}" = 0 ] || { printf 'FORGE_CANARY_LEAK\n'; exit 0; }
    printf 'ephemeral:%s:canary=false\n' "$FORGE_DISPATCH_SENTINEL"
    ;;
  council-start)
    mkdir -p "$FORGE_DISPATCH_SESSION_STORE"
    printf '%s\n' "$FORGE_DISPATCH_SEAT_HASH" > "$FORGE_DISPATCH_SESSION_STORE/$FORGE_DISPATCH_SESSION_ID"
    printf 'thread.started:%s\n' "$FORGE_DISPATCH_SESSION_ID"
    ;;
  council-resume)
    [ -f "$FORGE_DISPATCH_SESSION_STORE/$FORGE_DISPATCH_SESSION_ID" ] || exit 74
    [ "$(cat "$FORGE_DISPATCH_SESSION_STORE/$FORGE_DISPATCH_SESSION_ID")" = "$FORGE_DISPATCH_SEAT_HASH" ] || exit 75
    printf 'thread.resumed:%s\n' "$FORGE_DISPATCH_SESSION_ID"
    ;;
  investigate)
    mkdir -p "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts"
    printf 'bounded-reproduction\n' > "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts/qualification.txt"
    ;;
  *) exit 76 ;;
esac
EOF
chmod +x "$Q/bin/forge-dispatch-engine"
ln -s forge-dispatch-engine "$Q/bin/claude"
ln -s forge-dispatch-engine "$Q/bin/codex"

for engine in claude codex; do
    FORGE_FAKE_ENGINE_NAME="$engine" PATH="$Q/bin:/usr/bin:/bin" \
        "$REPO_ROOT/scripts/qualify-dispatch-isolation.sh" --fixture-mode \
        --engine "$engine" --project-root "$Q/project" --output "$Q/$engine.json" > "$Q/$engine.log" 2>&1
    assert_equals "$?" "0" "$engine deterministic dispatch fixture exits zero"
    assert_contains "$Q/$engine.json" '"status":"PASS"' "$engine deterministic dispatch fixture attests PASS"
    assert_contains "$Q/$engine.json" '"ephemeral":"PASS"' "$engine canary isolation is proven"
    assert_contains "$Q/$engine.json" '"council_resume":"PASS"' "$engine exact-id council resume is proven"
    assert_contains "$Q/$engine.json" '"investigation_replay":"PASS"' "$engine bounded investigation replay is proven"
done

FORGE_FAKE_ENGINE_NAME=codex FORGE_FAKE_CANARY_LEAK=1 PATH="$Q/bin:/usr/bin:/bin" \
    "$REPO_ROOT/scripts/qualify-dispatch-isolation.sh" --fixture-mode \
    --engine codex --project-root "$Q/project" --output "$Q/codex-leak.json" > "$Q/codex-leak.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] && pass "canary leak makes deterministic dispatch qualification fail" || fail "canary leak was accepted"
assert_contains "$Q/codex-leak.json" '"status":"BLOCKED"' "canary leak produces a truthful BLOCKED receipt"

start_test "fake drivers exercise the guarded live command, exact resume id, and replay boundary"
LIVE="$S/live-dispatch"
mkdir -p "$LIVE/bin"
cat > "$LIVE/bin/forge-live-engine" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) echo "${FORGE_FAKE_ENGINE_NAME:-fake} 9.9"; exit 0 ;;
  --help) echo '--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable'; exit 0 ;;
esac
printf 'engine=%s home=%s user=%s logname=%s argv=%s\n' \
  "${FORGE_FAKE_ENGINE_NAME:-fake}" "${HOME:-}" "${USER:-}" "${LOGNAME:-}" "$*" >> "$FORGE_FAKE_ARGV_LOG"
case "$*" in
  *FORGE_INVESTIGATION*)
    case "${FORGE_FAKE_DISPATCH_FAILURE:-}" in
      path-escape) ln -s "$FORGE_FAKE_ESCAPE_TARGET" "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts" ;;
      undeclared) mkdir -p "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts"; printf 'bad\n' > "$FORGE_DISPATCH_INVESTIGATION_ROOT/not-declared.txt" ;;
      no-clobber) mkdir -p "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts" "$FORGE_DISPATCH_REPLAY_TARGET/artifacts"; printf 'bounded-reproduction\n' > "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts/qualification.txt"; printf 'keep\n' > "$FORGE_DISPATCH_REPLAY_TARGET/artifacts/qualification.txt" ;;
      *) mkdir -p "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts"; printf 'bounded-reproduction\n' > "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts/qualification.txt" ;;
    esac
    candidate_id="$FORGE_DISPATCH_CANDIDATE_ID"; [ "${FORGE_FAKE_DISPATCH_FAILURE:-}" = candidate ] && candidate_id=wrong-candidate
    printf 'candidate_id=%s\ncanary_observed=false\n' "$candidate_id"
    exit 0 ;;
esac
case "${FORGE_FAKE_ENGINE_NAME:-}" in
  claude)
    case "$*" in
      *--no-session-persistence*) printf 'sentinel=%s\ncanary_observed=%s\n' "$FORGE_DISPATCH_SENTINEL" "${FORGE_FAKE_CANARY_RESULT:-false}" ;;
      *--session-id*) printf 'session_id=%s\nseat_hash=%s\nconfig_hash=%s\ncanary_observed=false\n' "$FORGE_DISPATCH_SESSION_ID" "$FORGE_DISPATCH_SEAT_HASH" "$FORGE_DISPATCH_CONFIG_HASH" ;;
      *--resume*)
        seat="$FORGE_DISPATCH_SEAT_HASH"; [ "${FORGE_FAKE_DISPATCH_FAILURE:-}" = cross-seat ] && seat=wrong-seat
        printf 'session_id=%s\nseat_hash=%s\nconfig_hash=%s\ncanary_observed=false\n' "$FORGE_DISPATCH_SESSION_ID" "$seat" "$FORGE_DISPATCH_CONFIG_HASH" ;;
      *) exit 70 ;;
    esac ;;
  codex)
    case "$*" in
      *--ephemeral*) printf '{"type":"item.completed","sentinel":"%s","canary_observed":%s}\n' "$FORGE_DISPATCH_SENTINEL" "${FORGE_FAKE_CANARY_RESULT:-false}" ;;
      *'exec resume '*)
        seat="$FORGE_DISPATCH_SEAT_HASH"; [ "${FORGE_FAKE_DISPATCH_FAILURE:-}" = cross-seat ] && seat=wrong-seat
        printf '{"type":"turn.completed","thread_id":"%s","seat_hash":"%s","config_hash":"%s","canary_observed":false}\n' "$FORGE_DISPATCH_SESSION_ID" "$seat" "$FORGE_DISPATCH_CONFIG_HASH" ;;
      *FORGE_COUNCIL_START*) printf '{"type":"thread.started","thread_id":"%s"}\n{"type":"turn.completed","thread_id":"%s","seat_hash":"%s","config_hash":"%s","canary_observed":false}\n' "$FORGE_DISPATCH_SESSION_ID" "$FORGE_DISPATCH_SESSION_ID" "$FORGE_DISPATCH_SEAT_HASH" "$FORGE_DISPATCH_CONFIG_HASH" ;;
      *) exit 71 ;;
    esac ;;
esac
EOF
chmod +x "$LIVE/bin/forge-live-engine"
for engine in claude codex; do
    cp "$LIVE/bin/forge-live-engine" "$LIVE/bin/$engine"
    chmod +x "$LIVE/bin/$engine"
    : > "$LIVE/$engine.argv"
    FORGE_FAKE_ENGINE_NAME="$engine" FORGE_FAKE_ARGV_LOG="$LIVE/$engine.argv" \
      "$REPO_ROOT/scripts/qualify-dispatch-isolation.sh" --test-live-driver \
      --engine-path "$LIVE/bin/$engine" --engine "$engine" --project-root "$Q/project" \
      --output "$LIVE/$engine.json" > "$LIVE/$engine.log" 2>&1
    assert_equals "$?" "0" "$engine guarded live driver exits zero"
    assert_contains "$LIVE/$engine.json" '"status":"PASS"' "$engine guarded live driver can reach PASS"
    assert_contains "$LIVE/$engine.argv" 'FORGE_COUNCIL_START' "$engine constructs a persistent first council turn"
    assert_contains "$LIVE/$engine.argv" 'FORGE_INVESTIGATION' "$engine invokes the writable disposable investigation"
    if [ "$engine" = claude ]; then
        assert_contains "$LIVE/$engine.argv" "home=$HOME user=${USER:-} logname=${LOGNAME:-${USER:-}}" "Claude live qualifier preserves the authenticated operator identity"
        assert_contains "$LIVE/$engine.argv" 'Return exactly these four key=value lines and nothing else' "Claude council prompt requires the machine-bound response shape"
        assert_contains "$LIVE/$engine.argv" 'return exactly these two key=value lines and nothing else' "Claude investigation prompt requires the machine-bound response shape"
        assert_contains "$LIVE/$engine.argv" '--safe-mode --no-session-persistence --strict-mcp-config' "Claude ephemeral turn repeats isolated flags"
        assert_contains "$LIVE/$engine.argv" '--resume 11111111-1111-4111-8111-' "Claude resumes the exact declared session"
        assert_not_contains "$LIVE/$engine.argv" '--resume 11111111-1111-4111-8111-.*--no-session-persistence' "Claude resume remains persistent"
    else
        assert_contains "$LIVE/$engine.argv" 'exec resume --disable hooks' "Codex resumes through exec resume with repeated disables"
        assert_contains "$LIVE/$engine.argv" '--ignore-user-config --ignore-rules' "Codex repeats discovery isolation"
    fi
done

for failure in cross-seat canary candidate undeclared path-escape no-clobber; do
    : > "$LIVE/fail-$failure.argv"
    extra=""
    [ "$failure" = canary ] && extra=FORGE_FAKE_CANARY_RESULT=true
    env FORGE_FAKE_ENGINE_NAME=codex FORGE_FAKE_ARGV_LOG="$LIVE/fail-$failure.argv" \
      FORGE_FAKE_DISPATCH_FAILURE="$failure" FORGE_FAKE_ESCAPE_TARGET="$Q/project" $extra \
      "$REPO_ROOT/scripts/qualify-dispatch-isolation.sh" --test-live-driver \
      --engine-path "$LIVE/bin/codex" --engine codex --project-root "$Q/project" \
      --output "$LIVE/fail-$failure.json" > "$LIVE/fail-$failure.log" 2>&1
    rc=$?
    [ "$rc" -ne 0 ] && pass "$failure is rejected by the live qualification boundary" || fail "$failure was accepted by live qualification"
    assert_contains "$LIVE/fail-$failure.json" '"status":"BLOCKED"' "$failure produces a truthful BLOCKED live receipt"
done

rm -f /tmp/forge-runtime-claude.$$ /tmp/forge-runtime-codex.$$ /tmp/forge-runtime-bad.$$
report "test-runtime-identity.sh"
