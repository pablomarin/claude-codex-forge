#!/usr/bin/env bash
# Deterministic tests for the final runtime-attestation wrapper. Never authenticates.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

RUNNER="$REPO_ROOT/scripts/qualify-runtime-final.sh"
RUNNER_PS="$REPO_ROOT/scripts/qualify-runtime-final.ps1"

start_test "runtime qualification wrappers exist but deterministic runners never invoke live hosts"
assert_file_exists "$RUNNER" "Bash final qualifier exists"
assert_file_exists "$RUNNER_PS" "PowerShell final qualifier exists"
assert_not_contains "$REPO_ROOT/tests/template/run-all.sh" 'qualify-runtime-final' "run-all never launches final live qualification"

if [[ ! -f "$RUNNER" ]]; then
    report "test-runtime-qualification-schema.sh"
    exit $?
fi

start_test "fixture attestation is valid but can never certify runtime readiness"
S=$(scratch_dir runtime-schema)
P="$S/project"; B="$S/bin"; OUT="$S/final.receipt"
mkdir -p "$P/.forge" "$B"
git -C "$P" init -q
git -C "$P" config user.email forge@example.invalid
git -C "$P" config user.name Forge
printf 'candidate\n' > "$P/app.txt"
git -C "$P" add app.txt
git -C "$P" commit -qm base
cat > "$B/runtime-fake" <<'EOF'
#!/usr/bin/env bash
set -eu
case "${1:-}" in --version) echo "${FORGE_FAKE_ENGINE_NAME:-engine} fixture 1"; exit 0 ;; esac
if [[ -n "${FORGE_DISPATCH_FIXTURE_ACTION:-}" ]]; then
  case "$FORGE_DISPATCH_FIXTURE_ACTION" in
    ephemeral) echo "ephemeral:${FORGE_DISPATCH_SENTINEL}:canary=false" ;;
    council-start) mkdir -p "$FORGE_DISPATCH_SESSION_STORE"; printf '%s\n' "$FORGE_DISPATCH_SEAT_HASH" > "$FORGE_DISPATCH_SESSION_STORE/$FORGE_DISPATCH_SESSION_ID" ;;
    council-resume) test "$(cat "$FORGE_DISPATCH_SESSION_STORE/$FORGE_DISPATCH_SESSION_ID")" = "$FORGE_DISPATCH_SEAT_HASH" ;;
    investigate) mkdir -p "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts"; printf 'bounded-reproduction\n' > "$FORGE_DISPATCH_INVESTIGATION_ROOT/artifacts/qualification.txt" ;;
  esac
  exit 0
fi
case "${FORGE_GOAL_FIXTURE_ACTION:-}" in
  activate) printf 'phase=implementation\nnext_step=resume-verification\nsession_id=%s\n' "$FORGE_GOAL_SESSION_ID" > "$FORGE_GOAL_FIXTURE_DIR/checkpoint"; echo "native-activation:$FORGE_GOAL_SESSION_ID" ;;
  resume) printf 'phase=verification\nnext_step=budget-check\nsession_id=%s\n' "$FORGE_GOAL_SESSION_ID" > "$FORGE_GOAL_FIXTURE_DIR/checkpoint"; echo "checkpoint-resume:$FORGE_GOAL_SESSION_ID" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$B/runtime-fake"
cp "$B/runtime-fake" "$B/claude"; cp "$B/runtime-fake" "$B/codex"
set +e
bash "$RUNNER" --fixture-mode --project-root "$P" --output "$OUT" \
    --engine-dir "$B" > "$S/run.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "fixture qualification stays non-certifying" || fail "fixture qualification falsely returned release-ready"
assert_contains "$OUT" 'evidence_mode=fixture' "attestation labels fake evidence"
assert_contains "$OUT" 'overall_status=BLOCKED' "fake evidence cannot become PASS"
if bash "$RUNNER" --validate --input "$OUT" >/dev/null 2>&1; then
    pass "fixture receipt validates structurally"
else
    fail "fixture receipt should validate structurally"
fi

start_test "unattributed, stale, hash-mismatched, and fake PASS evidence are rejected"
grep -v '^source_class=' "$OUT" > "$S/unattributed.receipt"
if bash "$RUNNER" --validate --input "$S/unattributed.receipt" >/dev/null 2>&1; then fail "unattributed receipt was accepted"; else pass "missing owning-qualifier source is rejected"; fi
sed 's/^candidate_sha256=./candidate_sha256=x/' "$OUT" > "$S/tampered.receipt"
if bash "$RUNNER" --validate --input "$S/tampered.receipt" >/dev/null 2>&1; then fail "stale candidate receipt was accepted"; else pass "stale candidate binding is rejected"; fi
child=$(sed -n 's/^claude_dispatch_path=//p' "$OUT")
cp "$child" "$S/child.backup"; printf '\n' >> "$child"
if bash "$RUNNER" --validate --input "$OUT" >/dev/null 2>&1; then fail "child hash mismatch was accepted"; else pass "child hash mismatch is rejected"; fi
mv "$S/child.backup" "$child"
sed 's/^overall_status=BLOCKED$/overall_status=PASS/' "$OUT" > "$S/fake-pass.receipt"
if bash "$RUNNER" --validate --input "$S/fake-pass.receipt" >/dev/null 2>&1; then fail "fixture PASS was accepted"; else pass "fixture source cannot certify PASS"; fi
cp "$B/claude" "$S/claude.before"; printf '\n' >> "$B/claude"
if bash "$RUNNER" --validate --input "$OUT" >/dev/null 2>&1; then fail "stale engine binary was accepted"; else pass "stale engine binary hash is rejected"; fi
mv "$S/claude.before" "$B/claude"; chmod +x "$B/claude"

report "test-runtime-qualification-schema.sh"
