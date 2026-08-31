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

start_test "Windows PASS requires an explicitly clean current candidate"
head=$(git -C "$P" rev-parse HEAD); tree=$(git -C "$P" rev-parse 'HEAD^{tree}')
WIN_NO_CLEAN="$S/windows-no-clean.receipt"
printf 'format=forge-windows-deterministic-v1\nstatus=PASS\npowershell_major=5\npowershell_minor=1\ngit_head=%s\ntree_sha=%s\n' "$head" "$tree" > "$WIN_NO_CLEAN"
OUT_NO_CLEAN="$S/no-clean-final.receipt"
set +e; bash "$RUNNER" --fixture-mode --project-root "$P" --output "$OUT_NO_CLEAN" --engine-dir "$B" --windows-attestation "$WIN_NO_CLEAN" >/dev/null 2>&1; set -e
assert_contains "$OUT_NO_CLEAN" 'windows_status=PENDING' "Windows attestation without candidate_clean cannot pass"

WIN="$S/windows-clean.receipt"
printf 'format=forge-windows-deterministic-v1\nstatus=PASS\npowershell_major=5\npowershell_minor=1\ncandidate_clean=true\ngit_head=%s\ntree_sha=%s\n' "$head" "$tree" > "$WIN"
OUT_CLEAN="$S/clean-final.receipt"
set +e; bash "$RUNNER" --fixture-mode --project-root "$P" --output "$OUT_CLEAN" --engine-dir "$B" --windows-attestation "$WIN" >/dev/null 2>&1; set -e
assert_contains "$OUT_CLEAN" 'windows_status=PASS' "clean candidate accepts a bound Windows attestation"

printf 'dirty tracked\n' >> "$P/app.txt"
OUT_DIRTY="$S/dirty-final.receipt"
set +e; bash "$RUNNER" --fixture-mode --project-root "$P" --output "$OUT_DIRTY" --engine-dir "$B" --windows-attestation "$WIN" >/dev/null 2>&1; set -e
assert_contains "$OUT_DIRTY" 'windows_status=PENDING' "tracked dirtiness rejects Windows PASS"
win_hash=$(if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$WIN" | awk '{print $1}'; else sha256sum "$WIN" | awk '{print $1}'; fi)
awk -v p="$WIN" -v h="$win_hash" 'BEGIN{FS=OFS="="} $1=="windows_status"{$2="PASS"} $1=="windows_attestation_path"{$2=p} $1=="windows_attestation_sha256"{$2=h} {print}' "$OUT_DIRTY" > "$S/forged-dirty-windows.receipt"
if bash "$RUNNER" --validate --input "$S/forged-dirty-windows.receipt" >/dev/null 2>&1; then fail "validator accepted Windows PASS on a dirty candidate"; else pass "validator rejects Windows PASS on a dirty candidate"; fi
printf 'candidate\n' > "$P/app.txt"
printf 'untracked\n' > "$P/untracked.txt"
OUT_UNTRACKED="$S/untracked-final.receipt"
set +e; bash "$RUNNER" --fixture-mode --project-root "$P" --output "$OUT_UNTRACKED" --engine-dir "$B" --windows-attestation "$WIN" >/dev/null 2>&1; set -e
assert_contains "$OUT_UNTRACKED" 'windows_status=PENDING' "untracked dirtiness rejects Windows PASS"
rm "$P/untracked.txt"

start_test "authenticated child qualification has a bounded timeout"
H="$S/hanging-bin"; mkdir "$H"
cat > "$H/runtime-hang" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo 'runtime hang 1'; exit 0 ;;
  --help) echo '--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable'; exit 0 ;;
  exec) [ "${2:-}" != --help ] || { echo '--add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable'; exit 0; } ;;
esac
if [ "$(basename "$0")" = claude ] && [ ! -e "$FORGE_RUNTIME_HANG_MARKER" ]; then
  : > "$FORGE_RUNTIME_HANG_MARKER"
  sleep 10 & nested=$!
  printf '%s\n' "$nested" > "$FORGE_RUNTIME_SLEEP_PID_FILE"
  wait "$nested"
fi
exit 23
EOF
chmod +x "$H/runtime-hang"; cp "$H/runtime-hang" "$H/claude"; cp "$H/runtime-hang" "$H/codex"
TIMEOUT_OUT="$S/timeout-final.receipt"; started=$(date +%s)
set +e
PATH="$H:$PATH" FORGE_RUNTIME_HANG_MARKER="$S/hang-used" FORGE_RUNTIME_SLEEP_PID_FILE="$S/nested-sleep.pid" bash "$RUNNER" --live --project-root "$P" --output "$TIMEOUT_OUT" --engine-dir "$H" --qualification-timeout-seconds 1 >/dev/null 2>&1
timeout_rc=$?
set -e
elapsed=$(($(date +%s) - started))
if [ "$timeout_rc" -ne 0 ]; then pass "timed-out authenticated qualification remains BLOCKED"; else fail "timed-out authenticated qualification returned PASS"; fi
[ "$elapsed" -lt 8 ] && pass "authenticated child timeout is bounded" || fail "authenticated child timeout exceeded its bound ($elapsed seconds)"
assert_contains "$TIMEOUT_OUT.d/claude-dispatch.json" 'qualification child timeout' "timed-out child emits a truthful BLOCKED receipt"
nested_pid=$(cat "$S/nested-sleep.pid")
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$nested_pid" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$nested_pid" 2>/dev/null; then fail "timed-out qualification left nested child $nested_pid alive"; kill -KILL "$nested_pid" 2>/dev/null || true; else pass "timed-out qualification terminates the complete descendant tree"; fi
assert_contains "$REPO_ROOT/scripts/qualify-runtime-final.ps1" 'QualificationTimeoutSeconds' "PowerShell final qualifier exposes the same bounded timeout"

report "test-runtime-qualification-schema.sh"
