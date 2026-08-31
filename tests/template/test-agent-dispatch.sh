#!/usr/bin/env bash
# Deterministic behavioral contract for Task 5 dispatch. Never calls a live model.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

DISPATCH="$REPO_ROOT/hooks/lib/agent-dispatch.sh"
HOST_CONTEXT="$REPO_ROOT/hooks/lib/host-context.sh"
FINGERPRINT="$REPO_ROOT/hooks/lib/candidate-fingerprint.sh"
FAKES="$REPO_ROOT/tests/template/fixtures/fake-engines"
DISPATCH_SEQ=0

make_repo() {
    local dir="$1"
    mkdir -p "$dir/.forge/local/reviews" "$dir/.forge"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name ForgeTest
    printf 'base\n' > "$dir/app.txt"
    cp "$REPO_ROOT/manifests/managed-v6.tsv" "$dir/.forge/managed-files.tsv"
    git -C "$dir" add app.txt .forge/managed-files.tsv
    git -C "$dir" commit -qm base
    write_state "$dir" "$(git -C "$dir" rev-parse HEAD)" refs/heads/test-base
}

write_state() {
    local dir="$1" base="$2" ref="$3" common
    common=$(git -C "$dir" rev-parse --git-common-dir); common=$(cd "$dir" && cd "$common" && pwd -P)
    mkdir -p "$dir/.forge/local"
    {
      printf '<!-- forge:state-schema v6 -->\n# Project State\n\n## Identity\n\n'
      printf '| Field | Value |\n| --- | --- |\n'
      printf '| Worktree root | %s |\n| Git common directory | %s |\n' "$(cd "$dir" && pwd -P)" "$common"
      printf '| Last active host | claude |\n| Workflow base ref | %s |\n| Workflow base SHA | %s |\n\n## Workflow\n\n## Receipts\n| Field | Value |\n| Review iteration | 1 |\n' "$ref" "$base"
    } > "$dir/.forge/local/state.md"
}

capture_context() {
    local dir="$1" host="$2" session="$3"
    (cd "$dir" && FORGE_HOST_CONTEXT_TEST_MODE=1 FORGE_HOST_CONTEXT_TEST_ROOT="$dir/.forge/local/test-host-authority" \
      FORGE_HOST_CONTEXT_TEST_LAUNCHER="$DISPATCH" bash "$HOST_CONTEXT" issue-test --host "$host" --session-id "$session") >/dev/null
    # Deliberately workspace-authored legacy context used only by direct-call rejection rows.
    printf 'schema_version=1\nactive_host=%s\nsession_id=%s\n' "$host" "$session" > "$dir/.forge/local/host.ctx"
}

launch_dispatch() {
    local dir="$1" host="$2"; shift 2
    (cd "$dir" && PATH="$FAKES:$PATH" FORGE_HOST_CONTEXT_TEST_MODE=1 FORGE_HOST_CONTEXT_TEST_ROOT="$dir/.forge/local/test-host-authority" \
      FORGE_HOST_CONTEXT_TEST_LAUNCHER="$DISPATCH" FORGE_DISPATCH_TEST_MODE=1 \
      bash "$HOST_CONTEXT" launch --host "$host" -- "$DISPATCH" "$@")
}

run_dispatch() {
    local dir="$1" host="$2" session="$3" engine="$4" role="${5:-general}" fallback="${6:-automatic}"
    local base output dispatch_profile=review
    base=$(awk -F'|' '$2 ~ /Workflow base SHA/ {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit}' "$dir/.forge/local/state.md")
    DISPATCH_SEQ=$((DISPATCH_SEQ + 1)); output="$dir/.forge/local/reviews/result-$role-$DISPATCH_SEQ.txt"
    case "$role" in investigation|investigation-repro) dispatch_profile=investigate ;; esac
    launch_dispatch "$dir" "$host" run --engine "$engine" --fallback-policy "$fallback" --role "$role" \
      --profile "$dispatch_profile" --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base \
      --prompt-file "$dir/prompt.txt" --output "$output" --timeout-seconds 2
}

assert_receipt_value() {
    local dir="$1" key="$2" want="$3" receipt got
    receipt=$(find "$dir/.forge/local/reviews" -name '*.receipt' -type f | sort | tail -1)
    got=$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$receipt")
    assert_equals "$got" "$want" "$key=$want"
}

start_test "four main/reviewer modes and deterministic auto selection"
for tuple in 'claude codex codex false' 'codex claude claude false' 'claude claude claude false' 'codex codex codex false'; do
    set -- $tuple; host="$1" requested="$2" actual="$3" fallback="$4"
    S=$(scratch_dir "dispatch-$host-$requested"); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" "$host" sid
    if run_dispatch "$S" "$host" sid "$requested" >/dev/null 2>&1; then pass "$host main can select $requested reviewer"; else fail "$host main failed $requested reviewer"; fi
    assert_receipt_value "$S" actual_engine "$actual"
    assert_receipt_value "$S" fallback "$fallback"
done
for tuple in 'claude codex' 'codex claude'; do
    set -- $tuple; host="$1" actual="$2"
    S=$(scratch_dir "dispatch-auto-$host"); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" "$host" sid
    run_dispatch "$S" "$host" sid auto >/dev/null 2>&1
    assert_receipt_value "$S" actual_engine "$actual"
done

start_test "materialized native hook context and fixed launcher invoke the installed dispatcher"
S=$(scratch_dir "dispatch installed path"); make_repo "$S"
bash "$REPO_ROOT/scripts/materialize-adapters.sh" --repo-root "$REPO_ROOT" --target "$S" --scope project --platform unix > "$S/install.log" 2>&1
mkdir -p "$S/.forge/local/reviews"
printf 'installed review\n' > "$S/.forge/local/reviews/prompt.txt"
mkdir -p "$S/home"
(cd "$S" && printf '{"session_id":"installed-session","cwd":"%s"}' "$S" | HOME="$S/home" bash .forge/hooks/lib/host-context.sh hook --host claude)
base=$(git -C "$S" rev-parse HEAD)
write_state "$S" "$base" refs/heads/installed-base
if (cd "$S" && HOME="$S/home" PATH="$FAKES:$PATH" FORGE_DISPATCH_TEST_MODE=1 \
    bash .forge/hooks/lib/host-context.sh launch --host claude -- .forge/hooks/lib/agent-dispatch.sh run \
      --engine auto --fallback-policy automatic --role general --profile review --artifact git:working-tree \
      --workflow-base-sha "$base" --workflow-base-ref refs/heads/installed-base \
      --prompt-file "$S/.forge/local/reviews/prompt.txt" --output "$S/.forge/local/reviews/installed-result.txt" --timeout-seconds 2) >/dev/null 2>&1; then
    pass "installed fixed launcher reaches installed dispatcher"
else
    fail "installed fixed launcher failed"
fi
assert_contains "$S/.forge/local/reviews/installed-result.txt" "verdict=CLEAN" \
    "installed dispatcher emits the machine envelope"
if (cd "$S" && HOME="$S/home" \
    bash .forge/hooks/lib/host-context.sh launch --host claude -- \
      .forge/hooks/lib/council-dispatch.sh --help) >/dev/null 2>&1; then
    pass "installed fixed launcher reaches the exact council dispatcher"
else
    fail "installed fixed launcher must reach the exact council dispatcher"
fi

start_test "launch/schema failures visibly fall back but semantic findings do not"
S=$(scratch_dir dispatch-fallback); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
FAKE_CODEX_BEHAVIOR=malformed FAKE_CLAUDE_BEHAVIOR=clean run_dispatch "$S" claude sid auto >"$S/stdout" 2>"$S/stderr"
assert_receipt_value "$S" actual_engine claude
assert_receipt_value "$S" fallback true
assert_receipt_value "$S" fallback_reason malformed-result
assert_contains "$S/stdout" "visible fallback" "fallback is visible on stdout"

S=$(scratch_dir dispatch-findings); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
FAKE_CODEX_BEHAVIOR=findings FAKE_CLAUDE_BEHAVIOR=clean run_dispatch "$S" claude sid auto >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" semantic_verdict FINDINGS
assert_receipt_value "$S" fallback false

for behavior in empty contradictory exit timeout; do
    S=$(scratch_dir "dispatch-$behavior"); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
    set +e
    FAKE_CODEX_BEHAVIOR="$behavior" FAKE_CLAUDE_BEHAVIOR=clean run_dispatch "$S" claude sid auto general automatic >/dev/null 2>&1
    rc=$?
    set -e
    assert_equals "$rc" "0" "$behavior failure falls back successfully"
    assert_receipt_value "$S" actual_engine claude
    assert_receipt_value "$S" fallback true
done

S=$(scratch_dir dispatch-explicit-unavailable); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
FORGE_TEST_DISABLE_ENGINE=claude FAKE_CODEX_BEHAVIOR=clean run_dispatch "$S" claude sid claude >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback true

S=$(scratch_dir dispatch-capability-gap); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
FORGE_TEST_DISABLE_CAPABILITY=codex FAKE_CLAUDE_BEHAVIOR=clean run_dispatch "$S" claude sid auto >/dev/null 2>&1
assert_receipt_value "$S" actual_engine claude
assert_receipt_value "$S" fallback_reason missing-required-capability

S=$(scratch_dir dispatch-identity-mismatch); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
FAKE_CLAUDE_BEHAVIOR=identity-mismatch FAKE_CODEX_BEHAVIOR=clean run_dispatch "$S" codex sid auto >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback_reason observable-identity-mismatch

start_test "artifact/authorization/invariant blocks never trigger fallback; council fallback none"
S=$(scratch_dir dispatch-artifact); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
set +e; FAKE_CODEX_BEHAVIOR=blocked-artifact FAKE_CLAUDE_BEHAVIOR=clean run_dispatch "$S" claude sid auto >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "artifact block is non-certifying"
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback false
assert_receipt_value "$S" blocked_class artifact

S=$(scratch_dir dispatch-council); make_repo "$S"; question_hash=$(printf council | shasum -a 256 | awk '{print $1}'); printf 'question_hash=%s\nreview\n' "$question_hash" > "$S/prompt.txt"; capture_context "$S" claude sid; base=$(git -C "$S" rev-parse HEAD)
set +e; FAKE_CODEX_BEHAVIOR=blocked-engine FAKE_CLAUDE_BEHAVIOR=clean launch_dispatch "$S" claude run --engine codex --fallback-policy none --role council-advisor --profile review --seat-id advisor-1 --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/council.txt" --timeout-seconds 2 >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "fallback_policy none returns failure to council"
assert_receipt_value "$S" fallback false
assert_receipt_value "$S" attempted_engines codex

start_test "council-advisor exact-id new/resume binds seat and stable question while allowing a critique prompt"
S=$(scratch_dir dispatch-resume); make_repo "$S"; council_prompt="$S/.forge/local/reviews/council-prompt.txt"; question_hash=$(printf 'same council question' | shasum -a 256 | awk '{print $1}'); printf 'question_hash=%s\nfirst advisor prompt\n' "$question_hash" > "$council_prompt"; capture_context "$S" claude sid
base=$(git -C "$S" rev-parse HEAD)
write_state "$S" "$base" refs/heads/council-base
claude_log="$S/.forge/local/reviews/claude.log"
set +e
FAKE_CLAUDE_LOG="$claude_log" launch_dispatch "$S" claude run --engine claude --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/council-new.txt" \
  --conversation new --seat-id advisor-1 --session-id-output "$S/.forge/local/reviews/session.id" --timeout-seconds 2 >/dev/null 2>&1
new_rc=$?
set -e
assert_equals "$new_rc" "0" "Claude council first turn succeeds"
session=$(cat "$S/.forge/local/reviews/session.id" 2>/dev/null || true)
if [ -n "$session" ]; then pass "new council turn records an exact session id"; else fail "new council turn emitted no session id"; fi
set +e
FAKE_CLAUDE_LOG="$claude_log" launch_dispatch "$S" claude run --engine claude --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/council-resume.txt" \
  --conversation resume --seat-id advisor-1 --session-id "$session" --timeout-seconds 2 >/dev/null 2>&1
resume_rc=$?
set -e
assert_equals "$resume_rc" "0" "Claude council exact-id resume succeeds"
assert_contains "$claude_log" "--session-id $session" "first council turn binds exact Claude session id"
assert_contains "$claude_log" "--resume $session" "critique turn resumes the exact Claude session id"
assert_contains "$claude_log" "home=$HOME user=${USER:-} logname=${LOGNAME:-${USER:-}}" "Claude child preserves the authenticated operator identity"

S=$(scratch_dir dispatch-codex-resume); make_repo "$S"; council_prompt="$S/.forge/local/reviews/council-prompt.txt"; question_hash=$(printf 'same council question' | shasum -a 256 | awk '{print $1}'); printf 'question_hash=%s\nfirst advisor prompt\n' "$question_hash" > "$council_prompt"; capture_context "$S" claude sid
base=$(git -C "$S" rev-parse HEAD); codex_log="$S/.forge/local/reviews/codex.log"
write_state "$S" "$base" refs/heads/council-base
set +e
FAKE_CODEX_LOG="$codex_log" launch_dispatch "$S" claude run --engine codex --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/codex-new.txt" \
  --conversation new --seat-id advisor-2 --session-id-output "$S/.forge/local/reviews/codex-session.id" --timeout-seconds 2 >/dev/null 2>&1
codex_new_rc=$?
set -e
assert_equals "$codex_new_rc" "0" "Codex council first turn succeeds"
codex_session=$(cat "$S/.forge/local/reviews/codex-session.id" 2>/dev/null || true)
other_question_hash=$(printf 'different council question' | shasum -a 256 | awk '{print $1}'); printf 'question_hash=%s\nother question\n' "$other_question_hash" > "$council_prompt"
set +e
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/codex-wrong-question.txt" \
  --conversation resume --seat-id advisor-2 --session-id "$codex_session" --timeout-seconds 2 >/dev/null 2>&1
wrong_question_rc=$?
set -e
assert_equals "$wrong_question_rc" "2" "resume rejects a changed council question instead of falling back"

printf 'question_hash=%s\ncross seat\n' "$question_hash" > "$council_prompt"
set +e
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/codex-cross-seat.txt" \
  --conversation resume --seat-id advisor-3 --session-id "$codex_session" --timeout-seconds 2 >/dev/null 2>&1
cross_seat_rc=$?
set -e
assert_equals "$cross_seat_rc" "2" "resume rejects a different council seat without fallback"

printf 'question_hash=%s\ndistinct critique prompt\n' "$question_hash" > "$council_prompt"
set +e
FAKE_CODEX_LOG="$codex_log" launch_dispatch "$S" claude run --engine codex --fallback-policy none --role council-advisor --profile review --artifact git:working-tree \
  --workflow-base-sha "$base" --workflow-base-ref refs/heads/council-base --prompt-file "$council_prompt" --output "$S/.forge/local/reviews/codex-critique.txt" \
  --conversation resume --seat-id advisor-2 --session-id "$codex_session" --timeout-seconds 2 >/dev/null 2>&1
critique_rc=$?
set -e
assert_equals "$critique_rc" "0" "resume accepts a distinct critique prompt for the same seat and question"
assert_contains "$codex_log" "exec resume" "Codex critique uses the exact-id resume transport"
assert_contains "$codex_log" "-a never --sandbox read-only exec resume" "Codex resume places the sandbox option at the supported global boundary"
assert_contains "$codex_log" "$codex_session" "Codex critique resumes the captured structured thread id"

start_test "stale, copied, and caller-overridden host contexts block"
S=$(scratch_dir dispatch-context); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid-good
base=$(git -C "$S" rev-parse HEAD)
set +e; (cd "$S" && PATH="$FAKES:$PATH" FORGE_NATIVE_HOST=claude FORGE_NATIVE_SESSION_ID=sid-wrong FORGE_HOST_CONTEXT_FILE="$S/.forge/local/host.ctx" FORGE_DISPATCH_TEST_MODE=1 bash "$DISPATCH" run --engine auto --fallback-policy automatic --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/wrong-session.txt" --timeout-seconds 2) >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "wrong native session id blocks"
S2=$(scratch_dir dispatch-context-copy); make_repo "$S2"; printf 'review\n' > "$S2/prompt.txt"; mkdir -p "$S2/.forge/local"; cp "$S/.forge/local/host.ctx" "$S2/.forge/local/host.ctx"
set +e; run_dispatch "$S2" claude sid-good auto >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "context copied to another worktree blocks"

start_test "workspace-authored and stale wrong-host contexts cannot launch a reviewer"
S=$(scratch_dir dispatch-context-authority); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude synthesized
base=$(git -C "$S" rev-parse HEAD)
set +e
(cd "$S" && PATH="$FAKES:$PATH" FORGE_NATIVE_HOST=claude FORGE_NATIVE_SESSION_ID=synthesized FORGE_HOST_CONTEXT_FILE="$S/.forge/local/host.ctx" FORGE_DISPATCH_TEST_MODE=1 bash "$DISPATCH" run --engine auto --fallback-policy automatic --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/synthesized.txt" --timeout-seconds 2) >/dev/null 2>&1
synthesized_rc=$?
set -e
assert_equals "$synthesized_rc" "2" "direct dispatcher call cannot promote a workspace-authored context"

S=$(scratch_dir dispatch-context-launcher); make_repo "$S"
bash "$REPO_ROOT/scripts/materialize-adapters.sh" --repo-root "$REPO_ROOT" --target "$S" --scope project --platform unix >/dev/null 2>&1
mkdir -p "$S/home"
(cd "$S" && printf '{"thread_id":"codex-old"}' | HOME="$S/home" FORGE_HOST_CONTEXT_TTL_SECONDS=0 bash .forge/hooks/lib/host-context.sh hook --host codex) >/dev/null 2>&1
sleep 1
(cd "$S" && printf '{"session_id":"claude-current"}' | HOME="$S/home" bash .forge/hooks/lib/host-context.sh hook --host claude) >/dev/null 2>&1
set +e
(cd "$S" && HOME="$S/home" bash .forge/hooks/lib/host-context.sh launch --host codex -- .forge/hooks/lib/agent-dispatch.sh) >/dev/null 2>&1
stale_host_rc=$?
(cd "$S" && HOME="$S/home" bash .forge/hooks/lib/host-context.sh launch --host claude -- /usr/bin/true) >/dev/null 2>&1
wrong_launcher_rc=$?
set -e
assert_equals "$stale_host_rc" "2" "expired Codex receipt cannot launch after a newer Claude session starts"
assert_equals "$wrong_launcher_rc" "2" "host receipt rejects a launcher whose hash is not bound"
assert_contains "$REPO_ROOT/hooks/lib/host-context.ps1" "council_path" \
    "PowerShell protected receipt binds the council dispatcher path"
assert_contains "$REPO_ROOT/hooks/lib/host-context.ps1" "council_hash" \
    "PowerShell protected receipt binds the council dispatcher hash"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" "@('-a', 'never', '--sandbox', \$sandbox, 'exec', 'resume')" \
    "PowerShell Codex resume places sandbox before the exec subcommand"

start_test "simultaneous native host sessions retain independent fixed launchers"
S=$(scratch_dir dispatch-context-ambiguous); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"
capture_context "$S" claude claude-live
capture_context "$S" codex codex-live
set +e
run_dispatch "$S" codex codex-live auto >/dev/null 2>"$S/codex.err"
codex_live_rc=$?
run_dispatch "$S" claude claude-live auto >/dev/null 2>"$S/claude.err"
claude_live_rc=$?
set -e
assert_equals "$codex_live_rc" "0" "current Codex session can launch while Claude is also active"
assert_equals "$claude_live_rc" "0" "current Claude session can launch while Codex is also active"

start_test "candidate fingerprint binds immutable base through committed and working changes"
S=$(scratch_dir dispatch-fingerprint); make_repo "$S"; base=$(git -C "$S" rev-parse HEAD)
write_state "$S" "$base" refs/heads/original
printf 'feature commit\n' >> "$S/app.txt"; git -C "$S" add app.txt; git -C "$S" commit -qm feature
printf 'staged\n' >> "$S/app.txt"; git -C "$S" add app.txt; printf 'working\n' >> "$S/app.txt"; printf 'untracked\n' > "$S/new file.txt"
if (cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/original --output "$S/fingerprint") >/dev/null 2>&1; then pass "captures complete base-to-working-tree candidate"; else fail "candidate capture failed"; fi
assert_contains "$S/fingerprint" "workflow_base_sha=$base" "base SHA is persisted, not recomputed"
assert_contains "$S/fingerprint" "untracked_count=1" "untracked manifest is bound"
snapshot=$(awk -F= '$1=="snapshot_path" {sub(/^[^=]*=/,""); print}' "$S/fingerprint")
assert_contains "$snapshot/app.txt" "feature commit" "snapshot includes earlier committed feature work"
assert_contains "$snapshot/app.txt" "working" "snapshot includes exact working delta"

start_test "candidate base and worktree binding come from canonical state, not caller choice"
S=$(scratch_dir dispatch-state-base); make_repo "$S"; workflow_base=$(git -C "$S" rev-parse HEAD)
printf 'feature scope\n' >> "$S/app.txt"; git -C "$S" add app.txt; git -C "$S" commit -qm feature
head_now=$(git -C "$S" rev-parse HEAD)
set +e
(cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$head_now" --workflow-base-ref refs/heads/test-base --output "$S/fingerprint-drift") >/dev/null 2>&1
state_base_rc=$?
set -e
assert_equals "$state_base_rc" "2" "caller cannot shrink scope to HEAD when canonical state freezes an earlier base"
(cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$workflow_base" --workflow-base-ref refs/heads/test-base --output "$S/fingerprint-full") >/dev/null 2>&1
state_snapshot=$(awk -F= '$1=="snapshot_path" {sub(/^[^=]*=/,""); print}' "$S/fingerprint-full")
assert_contains "$state_snapshot/app.txt" "feature scope" "canonical base capture retains earlier feature commits"

start_test "tracked symlinks are inert bytes in the snapshot and source races cannot certify"
S=$(scratch_dir dispatch-tracked-link); make_repo "$S"; base=$(git -C "$S" rev-parse HEAD)
write_state "$S" "$base" refs/heads/link-base
ln -s app.txt "$S/tracked-link"; git -C "$S" add tracked-link; git -C "$S" commit -qm link
(cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/link-base --output "$S/fingerprint") >/dev/null 2>&1
snapshot=$(awk -F= '$1=="snapshot_path" {sub(/^[^=]*=/,""); print}' "$S/fingerprint")
if [ -f "$snapshot/tracked-link" ] && [ ! -L "$snapshot/tracked-link" ]; then pass "tracked symlink is materialized as inert target bytes"; else fail "tracked symlink remained followable in snapshot"; fi
assert_contains "$snapshot/tracked-link" "app.txt" "inert tracked-link bytes preserve the Git target"

S=$(scratch_dir dispatch-race); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
candidate_before=$(hash_file "$S/app.txt")
set +e
FAKE_CODEX_BEHAVIOR=clean FAKE_MUTATE_REAL="$S/app.txt" run_dispatch "$S" claude sid codex >/dev/null 2>&1
race_rc=$?
set -e
assert_equals "$race_rc" "0" "real candidate mutation path is not exposed to reviewer child"
assert_hash_equals "$S/app.txt" "$candidate_before" "reviewer child cannot mutate real candidate"

start_test "unsafe untracked filesystem objects are rejected without following"
S=$(scratch_dir dispatch-nofollow); make_repo "$S"; base=$(git -C "$S" rev-parse HEAD); ln -s /etc/passwd "$S/escape-link"
write_state "$S" "$base" x
set +e; (cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref x --output "$S/fp") >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "untracked symlink rejected"
unlink "$S/escape-link"; mkfifo "$S/pipe"
set +e; (cd "$S" && bash "$FINGERPRINT" capture --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref x --output "$S/fp") >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "untracked FIFO rejected"

start_test "Claude review is isolated from the real cwd and real Forge-local writes"
S=$(scratch_dir dispatch-claude-isolation); make_repo "$S"; mkdir -p "$S/.claude"; printf 'AMBIENT_CANARY\n' > "$S/.claude/CLAUDE.md"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
claude_log="$S/.forge/local/reviews/claude-isolation.log"
FAKE_CLAUDE_BEHAVIOR=assert-isolated FAKE_CLAUDE_LOG="$claude_log" run_dispatch "$S" codex sid claude >/dev/null 2>&1
assert_not_contains "$claude_log" "cwd=$(cd "$S" && pwd -P) " "Claude child cwd is a clean scratch primary"
state_before=$(hash_file "$S/.forge/local/state.md")
set +e
FAKE_CLAUDE_BEHAVIOR=clean FAKE_MUTATE_REAL="$S/.forge/local/state.md" run_dispatch "$S" codex sid claude >/dev/null 2>&1
mutation_rc=$?
set -e
assert_equals "$mutation_rc" "0" "real Forge-local mutation path is not exposed to Claude child"
assert_hash_equals "$S/.forge/local/state.md" "$state_before" "Claude child cannot mutate real Forge-local state"

start_test "qualified identity, canary, config, and Codex auth are mandatory per attempt"
S=$(scratch_dir dispatch-identity-required); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
FAKE_CLAUDE_BEHAVIOR=identity-missing FAKE_CODEX_BEHAVIOR=clean run_dispatch "$S" codex sid claude >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback_reason observable-identity-missing
S=$(scratch_dir dispatch-canary-required); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
FAKE_CLAUDE_BEHAVIOR=canary-missing FAKE_CODEX_BEHAVIOR=clean run_dispatch "$S" codex sid claude >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback_reason isolation-canary-missing
S=$(scratch_dir dispatch-canary-duplicate); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
FAKE_CLAUDE_BEHAVIOR=duplicate-canary run_dispatch "$S" codex sid claude >/dev/null 2>&1
assert_receipt_value "$S" actual_engine claude
assert_receipt_value "$S" fallback false
S=$(scratch_dir dispatch-canary-conflict); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" codex sid
FAKE_CLAUDE_BEHAVIOR=conflicting-canary FAKE_CODEX_BEHAVIOR=clean run_dispatch "$S" codex sid claude >/dev/null 2>&1
assert_receipt_value "$S" actual_engine codex
assert_receipt_value "$S" fallback_reason isolation-canary-mismatch
S=$(scratch_dir dispatch-codex-auth); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid; printf '{"token":"protected"}\n' > "$S/protected-auth.json"
set +e
FORGE_CODEX_AUTH_FILE="$S/protected-auth.json" FAKE_CODEX_BEHAVIOR=require-auth run_dispatch "$S" claude sid codex general none >/dev/null 2>&1
auth_rc=$?
set -e
assert_equals "$auth_rc" "0" "ephemeral Codex attempt receives protected auth in scratch CODEX_HOME"

start_test "fallback starts from a pristine independent candidate"
S=$(scratch_dir dispatch-pristine-fallback); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
set +e
FAKE_CODEX_BEHAVIOR=mutate-malformed FAKE_CLAUDE_BEHAVIOR=reject-dirty-candidate run_dispatch "$S" claude sid auto >/dev/null 2>&1
pristine_rc=$?
set -e
assert_equals "$pristine_rc" "0" "fallback reviewer never sees failed attempt candidate writes"

start_test "review output and council session paths are confined, no-follow, and no-clobber"
S=$(scratch_dir dispatch-output-boundary); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid; state_before=$(hash_file "$S/.forge/local/state.md"); base=$(git -C "$S" rev-parse HEAD)
set +e
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/state.md" --timeout-seconds 2 >/dev/null 2>&1
reserved_output_rc=$?
mkdir -p "$S/.forge/local/reviews"; ln -s ../state.md "$S/.forge/local/reviews/link-output"
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/link-output" --timeout-seconds 2 >/dev/null 2>&1
linked_output_rc=$?
printf 'owner\n' > "$S/.forge/local/reviews/existing-output"
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/existing-output" --timeout-seconds 2 >/dev/null 2>&1
clobber_rc=$?
set -e
assert_equals "$reserved_output_rc" "2" "review output cannot target canonical state"
assert_equals "$linked_output_rc" "2" "review output symlink is rejected without following"
assert_equals "$clobber_rc" "2" "existing review output is never clobbered"
assert_hash_equals "$S/.forge/local/state.md" "$state_before" "rejected output paths leave canonical state byte-identical"

printf 'question_hash=%s\nnew council turn\n' "$(printf question | shasum -a 256 | awk '{print $1}')" > "$S/prompt.txt"
set +e
launch_dispatch "$S" claude run --engine claude --fallback-policy none --role council-advisor --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/council-output" --conversation new --session-id-output "$S/.forge/local/state.md" --timeout-seconds 2 >"$S/session-path.out" 2>"$S/session-path.err"
session_path_rc=$?
set -e
assert_equals "$session_path_rc" "2" "session id output cannot target canonical state"
assert_contains "$S/session-path.err" "session id output" "session output rejection is the path boundary, not an unrelated council check"
assert_hash_equals "$S/.forge/local/state.md" "$state_before" "rejected session output leaves canonical state byte-identical"

start_test "council session metadata and stores reject linked reserved ancestors"
for reserved in sessions session-stores; do
    S=$(scratch_dir "dispatch-linked-$reserved"); make_repo "$S"; capture_context "$S" claude sid
    outside="$S/outside-$reserved"; mkdir "$outside"
    ln -s "$outside" "$S/.forge/local/reviews/$reserved"
    printf 'question_hash=%s\nlinked reserved path\n' "$(printf question | shasum -a 256 | awk '{print $1}')" > "$S/prompt.txt"
    base=$(git -C "$S" rev-parse HEAD)
    set +e
    launch_dispatch "$S" claude run --engine claude --fallback-policy none --role council-advisor --profile review \
      --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base \
      --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/council-output" --conversation new \
      --session-id-output "$S/.forge/local/reviews/session.id" --seat-id advisor-1 --timeout-seconds 2 >/dev/null 2>&1
    linked_reserved_rc=$?
    set -e
    assert_equals "$linked_reserved_rc" "2" "$reserved symlink ancestor is rejected"
    assert_equals "$(find "$outside" -mindepth 1 | wc -l | tr -d ' ')" "0" "$reserved symlink target remains untouched"
done

start_test "reserved output publication atomically replaces a swapped leaf without following it"
S=$(scratch_dir dispatch-output-race); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid; base=$(git -C "$S" rev-parse HEAD)
protected="$S/.forge/local/protected-output"; printf 'protected\n' > "$protected"; protected_before=$(hash_file "$protected")
raced_output="$S/.forge/local/reviews/raced-output"
set +e
FAKE_CODEX_BEHAVIOR=delayed-clean launch_dispatch "$S" claude run --engine codex --fallback-policy none --role general --profile review --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$raced_output" --timeout-seconds 2 >/dev/null 2>&1 &
dispatch_pid=$!
while [ ! -e "$raced_output" ] && [ ! -L "$raced_output" ] && kill -0 "$dispatch_pid" 2>/dev/null; do sleep 0.01; done
rm -f "$raced_output"; ln -s "$protected" "$raced_output"
wait "$dispatch_pid"; output_race_rc=$?
set -e
assert_equals "$output_race_rc" "0" "output publication completes after a leaf swap"
assert_hash_equals "$protected" "$protected_before" "atomic publication never follows a swapped output symlink"
if [ -f "$raced_output" ] && [ ! -L "$raced_output" ]; then pass "published output is a regular invocation-owned file"; else fail "published output remained linked or absent"; fi

start_test "investigation launches a fresh full agent in the real worktree"
for tuple in 'claude codex' 'codex claude'; do
    set -- $tuple; selected="$1"; host="$2"
    S=$(scratch_dir "dispatch-full-investigation-$selected"); make_repo "$S"; capture_context "$S" "$host" sid
    mkdir -p "$S/.forge/memory" "$S/.forge/local/memory"
    printf 'shared durable memory\n' > "$S/.forge/memory/shared.md"
    printf 'shared local memory\n' > "$S/.forge/local/memory/session.md"
    printf 'inspect with normal project tools and configuration\n' > "$S/prompt.txt"
    log="$S/.forge/local/reviews/$selected-full-agent.log"
    set +e
    if [ "$selected" = claude ]; then
      FAKE_REAL_ROOT="$S" FORGE_FULL_AGENT_PROBE=visible FAKE_CLAUDE_BEHAVIOR=full-investigation FAKE_CLAUDE_LOG="$log" \
        run_dispatch "$S" "$host" sid "$selected" investigation none >/dev/null 2>&1
    else
      FAKE_REAL_ROOT="$S" FORGE_FULL_AGENT_PROBE=visible FAKE_CODEX_BEHAVIOR=full-investigation FAKE_CODEX_LOG="$log" \
        run_dispatch "$S" "$host" sid "$selected" investigation none >/dev/null 2>&1
    fi
    investigation_rc=$?
    set -e
    assert_equals "$investigation_rc" "0" "$selected investigation completes in the real worktree"
    assert_contains "$S/.forge/local/investigation-artifacts/$selected.txt" "$selected full agent" "$selected investigation can write shared local state"
    assert_contains "$log" "cwd=$(cd "$S" && pwd -P)" "$selected investigation cwd is the real worktree"
    assert_not_contains "$log" "--safe-mode" "$selected investigation is not placed in Forge safe mode"
    assert_not_contains "$log" "--setting-sources" "$selected investigation keeps normal host configuration"
    assert_not_contains "$log" "--ignore-user-config" "$selected investigation keeps normal user configuration"
    assert_not_contains "$log" "--ignore-rules" "$selected investigation keeps normal project instructions"
    assert_not_contains "$log" "--add-dir" "$selected investigation does not use a disposable candidate"
    if [ "$selected" = codex ]; then
      assert_contains "$log" "-a on-request --search exec" "Codex investigation preserves native on-request approval with web search"
      assert_contains "$log" "--sandbox danger-full-access" "Codex investigation selects the full-capability sandbox mode"
    else
      assert_contains "$log" "--permission-mode auto" "Claude investigation uses non-interactive safety-classified full-agent mode"
      assert_not_contains "$log" "--sandbox" "Claude investigation is not assigned a Forge sandbox override"
    fi
    assert_receipt_value "$S" investigation_mode full-agent-worktree
    assert_receipt_value "$S" investigation_replay NONE
done

start_test "investigation role mapping, read-only channel, and dispatcher-owned reproduction are enforced"
S=$(scratch_dir dispatch-role-profile); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid; base=$(git -C "$S" rev-parse HEAD)
set +e
launch_dispatch "$S" claude run --engine codex --fallback-policy none --role general --profile investigate --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/general-investigate" --timeout-seconds 2 >/dev/null 2>&1
role_profile_rc=$?
set -e
assert_equals "$role_profile_rc" "2" "general role cannot acquire investigation permissions"

printf 'requires_read_only_channel=true\ninvestigate query with normal host capabilities\n' > "$S/prompt.txt"; readonly_log="$S/.forge/local/reviews/readonly.log"
set +e
FAKE_CODEX_LOG="$readonly_log" launch_dispatch "$S" claude run --engine codex --fallback-policy none --role investigation --profile investigate --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref refs/heads/test-base --prompt-file "$S/prompt.txt" --output "$S/.forge/local/reviews/full-investigation" --timeout-seconds 2 >/dev/null 2>&1
readonly_rc=$?
set -e
assert_equals "$readonly_rc" "0" "full investigation ignores the legacy declared-channel restriction"
assert_not_contains "$readonly_log" "mcp_servers.context7" "Forge does not replace normal investigation MCP configuration"

make_repro_fixture() {
  local dir="$1"
  mkdir -p "$dir/tests/repro"
  {
    printf '#!/usr/bin/env bash\nset -u\ncase "$1" in correct) printf "MATCH\\n" ;; wrong) printf "EMPTY\\n" ;; control) printf "CONTROL\\n" ;; *) exit 9 ;; esac\n'
  } > "$dir/tests/repro/check.sh"
  chmod +x "$dir/tests/repro/check.sh"
}
match_hash=$(printf 'MATCH\n' | shasum -a 256 | awk '{print $1}'); control_hash=$(printf 'CONTROL\n' | shasum -a 256 | awk '{print $1}')
S=$(scratch_dir dispatch-repro-wrong-filter); make_repo "$S"; make_repro_fixture "$S"; capture_context "$S" claude sid
cat > "$S/prompt.txt" <<EOF
schema_version=1
hypothesis=wrong date filter reproduces finding
primary_program=tests/repro/check.sh
primary_arg=wrong
primary_expected_exit=0
primary_expected_output_hash=$match_hash
control_program=tests/repro/check.sh
control_arg=control
control_expected_exit=0
control_expected_output_hash=$control_hash
EOF
set +e; FAKE_CODEX_BEHAVIOR=repro run_dispatch "$S" claude sid codex investigation-repro none >"$S/repro.out" 2>"$S/repro.err"; repro_wrong_rc=$?; set -e
assert_equals "$repro_wrong_rc" "0" "dispatcher completes an independently failed primary check"
assert_receipt_value "$S" reproduction_status FAILED

S=$(scratch_dir dispatch-repro-no-control); make_repo "$S"; make_repro_fixture "$S"; capture_context "$S" claude sid
cat > "$S/prompt.txt" <<EOF
schema_version=1
hypothesis=primary-only result is not independently controlled
primary_program=tests/repro/check.sh
primary_arg=correct
primary_expected_exit=0
primary_expected_output_hash=$match_hash
EOF
set +e; run_dispatch "$S" claude sid codex investigation-repro none >/dev/null 2>&1; repro_no_control_rc=$?; set -e
assert_equals "$repro_no_control_rc" "0" "missing independent control records an unverifiable result"
assert_receipt_value "$S" reproduction_status UNVERIFIED

S=$(scratch_dir dispatch-repro-independent); make_repo "$S"; make_repro_fixture "$S"; capture_context "$S" claude sid
cat > "$S/prompt.txt" <<EOF
schema_version=1
hypothesis=correct filter reproduces finding
primary_program=tests/repro/check.sh
primary_arg=correct
primary_expected_exit=0
primary_expected_output_hash=$match_hash
control_program=tests/repro/check.sh
control_arg=control
control_expected_exit=0
control_expected_output_hash=$control_hash
EOF
set +e; FAKE_CODEX_BEHAVIOR=repro run_dispatch "$S" claude sid codex investigation-repro none >"$S/repro.out" 2>"$S/repro.err"; repro_correct_rc=$?; set -e
assert_equals "$repro_correct_rc" "0" "dispatcher completes matching primary and control checks"
assert_receipt_value "$S" reproduction_status REPRODUCED
repro_receipt=$(find "$S/.forge/local/reviews" -name '*.receipt' -type f | sort | tail -1)
assert_not_contains "$repro_receipt" "primary_check_hash=primary-literal" "reproduction hashes are computed by dispatcher, not copied from child"

start_test "investigation reproduction reuses the qualified no-network candidate boundary"
S=$(scratch_dir dispatch-repro-boundary); make_repo "$S"; capture_context "$S" claude sid
printf 'protected-auth\n' > "$S/protected-auth.json"; state_before=$(hash_file "$S/.forge/local/state.md"); auth_before=$(hash_file "$S/protected-auth.json")
outside="$S/../repro-external-$RANDOM"; rm -f "$outside"; mkdir -p "$S/tests/repro"
cat > "$S/tests/repro/boundary.sh" <<EOF
#!/usr/bin/env bash
if [ "\${FORGE_REPRO_NO_NETWORK:-0}" != 1 ]; then
  printf 'escaped\n' >> "$S/.forge/local/state.md"
  printf 'escaped\n' >> "$S/protected-auth.json"
  printf 'escaped\n' > "$outside"
fi
case "\$1" in primary) printf 'MATCH\n' ;; control) printf 'CONTROL\n' ;; *) exit 9 ;; esac
EOF
chmod +x "$S/tests/repro/boundary.sh"
cat > "$S/prompt.txt" <<EOF
schema_version=1
hypothesis=qualified reproduction boundary blocks external effects
primary_program=tests/repro/boundary.sh
primary_arg=primary
primary_expected_exit=0
primary_expected_output_hash=$match_hash
control_program=tests/repro/boundary.sh
control_arg=control
control_expected_exit=0
control_expected_output_hash=$control_hash
EOF
repro_boundary_log="$S/.forge/local/reviews/repro-boundary.log"
set +e
FORGE_CODEX_AUTH_FILE="$S/protected-auth.json" FAKE_CODEX_BEHAVIOR=repro-boundary FAKE_CODEX_LOG="$repro_boundary_log" run_dispatch "$S" claude sid codex investigation-repro none >/dev/null 2>&1
repro_boundary_rc=$?
set -e
assert_equals "$repro_boundary_rc" "0" "qualified engine boundary completes primary and control"
assert_receipt_value "$S" reproduction_status REPRODUCED
assert_hash_equals "$S/.forge/local/state.md" "$state_before" "reproduction leaves protected Forge state byte-identical"
assert_hash_equals "$S/protected-auth.json" "$auth_before" "reproduction leaves protected auth byte-identical"
if [ ! -e "$outside" ] && [ ! -L "$outside" ]; then pass "reproduction cannot write outside its disposable candidate"; else fail "reproduction escaped its disposable candidate"; fi
assert_contains "$repro_boundary_log" "--sandbox workspace-write" "reproduction uses the existing qualified no-network workspace boundary"

start_test "hostile ambient config is excluded and only declared read-only query channel survives"
S=$(scratch_dir dispatch-hostile); make_repo "$S"; mkdir -p "$S/.claude/plugins"; printf 'FORGE_HOSTILE_HOOK\n' > "$S/.claude/settings.json"; printf 'FORGE_WRITE_MCP\n' > "$S/.mcp.json"
C="$S/private config"; bash "$REPO_ROOT/scripts/render-dispatch-config.sh" --engine claude --profile review --output-dir "$C" --read-only-server context7 > "$S/config.receipt"
assert_not_contains "$C/claude-settings.json" "FORGE_HOSTILE_HOOK" "ambient project hooks excluded"
assert_not_contains "$C/mcp.json" "FORGE_WRITE_MCP" "ambient write-capable MCP excluded"
assert_contains "$C/mcp.json" '"context7"' "declared read-only query server retained"

start_test "code certification needs distinct same-candidate spec and quality receipts"
S=$(scratch_dir dispatch-pair); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; capture_context "$S" claude sid
run_dispatch "$S" claude sid codex code-spec >/dev/null 2>&1; spec=$(find "$S/.forge/local/reviews" -name '*.receipt' | sort | tail -1)
run_dispatch "$S" claude sid codex code-quality >/dev/null 2>&1; quality=$(find "$S/.forge/local/reviews" -name '*.receipt' | sort | tail -1)
assert_equals "$(awk -F= '$1=="review_iteration"{print $2}' "$spec")" "1" "spec receipt records the current review iteration"
assert_equals "$(awk -F= '$1=="review_iteration"{print $2}' "$quality")" "1" "quality receipt records the current review iteration"
if bash "$DISPATCH" verify-pair --code-spec-receipt "$spec" --code-quality-receipt "$quality" >/dev/null 2>&1; then pass "two distinct lenses certify one candidate"; else fail "valid review pair rejected"; fi
set +e; bash "$DISPATCH" verify-pair --code-spec-receipt "$spec" --code-quality-receipt "$spec" >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "duplicate invocation cannot certify"
printf 'mutated candidate\n' >> "$S/app.txt"
set +e; bash "$DISPATCH" verify-pair --code-spec-receipt "$spec" --code-quality-receipt "$quality" >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "candidate mutation invalidates the review pair"
printf 'base\n' > "$S/app.txt"
quality_output=$(awk -F= '$1=="output_path"{sub(/^[^=]*=/,"");print;exit}' "$quality")
cp "$quality_output" "$S/.forge/local/quality-output.backup"; printf 'mutated output\n' >> "$quality_output"
set +e; bash "$DISPATCH" verify-pair --code-spec-receipt "$spec" --code-quality-receipt "$quality" >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "review output mutation invalidates the review pair"
mv "$S/.forge/local/quality-output.backup" "$quality_output"
sed -i.bak 's/| Review iteration | 1 |/| Review iteration | 2 |/' "$S/.forge/local/state.md"
set +e; bash "$DISPATCH" verify-pair --code-spec-receipt "$spec" --code-quality-receipt "$quality" >/dev/null 2>&1; rc=$?; set -e
assert_equals "$rc" "2" "state iteration relabel cannot certify stale review receipts"

start_test "PowerShell process serialization preserves explicit empty Claude arguments"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" 'if ($Value.Length -eq 0)' \
  "PowerShell argument serializer treats an empty argv value explicitly"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" "'FAKE_CLAUDE_ARGV_LOG'" \
  "PowerShell test-mode whitelist propagates the exact argv log"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" 'Assert-NoFollowSessionMetadata $SessionMeta' \
  "PowerShell resume rechecks the session metadata leaf"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" "InvestigationMode = 'full-agent-worktree'" \
  "PowerShell investigation records the full-agent worktree mode"
assert_contains "$REPO_ROOT/hooks/lib/agent-dispatch.ps1" "if (\$Role -eq 'investigation')" \
  "PowerShell dispatcher has a distinct unrestricted investigation branch"
assert_contains "$REPO_ROOT/scripts/materialize-adapters.ps1" '".forge/hooks/lib/host-context.ps1", "-Mode", "hook", "-Host", "codex"' \
  "PowerShell materializer renders Codex host context as a direct invocation"

start_test "child review cannot mutate canonical state or authorization records"
S=$(scratch_dir dispatch-state); make_repo "$S"; printf 'review\n' > "$S/prompt.txt"; printf 'auth\n' > "$S/.forge/local/authorization-record"; capture_context "$S" claude sid
before=$(hash_file "$S/.forge/local/state.md"); auth_before=$(hash_file "$S/.forge/local/authorization-record")
run_dispatch "$S" claude sid auto >/dev/null 2>&1
assert_hash_equals "$S/.forge/local/state.md" "$before" "review leaves state byte-identical"
assert_hash_equals "$S/.forge/local/authorization-record" "$auth_before" "review leaves authorization byte-identical"

report "agent dispatch"
