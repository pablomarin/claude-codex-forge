#!/usr/bin/env bash
# Behavioral contract for the six-seat council topology. Uses a PATH fake;
# never calls a live model.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

DISPATCH="$REPO_ROOT/hooks/lib/council-dispatch.sh"

make_fixture() {
    local name="$1" include_other="$2" root repo lib fakebin
    root=$(mktemp -d "${TMPDIR:-/tmp}/council-$name.XXXXXX"); _SCRATCH_DIRS+=("$root")
    repo="$root/repo"; lib="$repo/.forge/hooks/lib"; fakebin="$root/bin"
    mkdir -p "$lib" "$repo/.forge" "$fakebin"
    cp "$DISPATCH" "$lib/council-dispatch.sh"
    printf '%s\n' \
      $'model-council-advisor\tclaude\tqualified' $'model-council-chair\tclaude\tqualified' \
      $'model-council-advisor\tcodex\tqualified' $'model-council-chair\tcodex\tqualified' > "$repo/.forge/host-capabilities.tsv"
    cat > "$lib/agent-dispatch.sh" <<'FAKE'
#!/usr/bin/env bash
# Task-5 exact transport markers used by council preflight: resume) session_id
shift
engine= role= seat= conversation= prompt= output= session_out= session_id=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --engine) engine=$2; shift 2 ;; --role) role=$2; shift 2 ;; --seat-id) seat=$2; shift 2 ;;
    --conversation) conversation=$2; shift 2 ;; --prompt-file) prompt=$2; shift 2 ;; --output) output=$2; shift 2 ;;
    --session-id-output) session_out=$2; shift 2 ;; --session-id) session_id=$2; shift 2 ;;
    --fallback-policy|--profile|--artifact|--workflow-base-sha|--workflow-base-ref|--timeout-seconds) shift 2 ;;
    *) printf 'unexpected fake argument: %s\n' "$1" >&2; exit 90 ;;
  esac
done
printf '%s|%s|%s|%s|%s\n' "$engine" "$role" "$seat" "$conversation" "$session_id" >> "$FAKE_LOG"
attempt=$(dirname "$output")
printf 'start|%s|%s|%s\n' "$attempt" "$conversation" "$seat" >> "$FAKE_DIR/events.log"
if [ "${FAKE_PARALLEL_PROBE:-}" = yes ] && [ "$role" = council-advisor ]; then
  : > "$attempt/$seat-$conversation.started"
  # A serial dispatcher cannot satisfy this rendezvous. Bound the failed probe.
  for tick in {1..40}; do
    count=$(find "$attempt" -name "*-$conversation.started" | wc -l | tr -d ' ')
    [ "$count" -eq 5 ] && break
    sleep 0.05
  done
  [ "$count" -eq 5 ] || exit 21
fi
if [ "$conversation" = resume ] && [ "${FAKE_PARALLEL_PROBE:-}" = yes ]; then
  [ "$(find "$attempt" -name '*-new.done' | wc -l | tr -d ' ')" -eq 5 ] || exit 22
  ! grep -Fq "### Advisor $(case "$seat" in simplifier) echo A;; scalability_hawk) echo B;; pragmatist) echo C;; contrarian) echo D;; maintainer) echo E;; esac)" "$prompt" || exit 23
fi
if [ "${FAKE_DELAY:-}" = yes ]; then sleep 0.1; fi
match="$engine:$seat:$conversation"
if [ "${FAKE_FAIL_MATCH:-}" = "$match" ] && [ ! -e "$FAKE_DIR/failure-used" ]; then : > "$FAKE_DIR/failure-used"; printf 'end|%s|%s|%s\n' "$attempt" "$conversation" "$seat" >> "$FAKE_DIR/events.log"; printf 'injected failure: %s\n' "$match" >&2; exit 17; fi
if [ "${FAKE_MAIN_FAIL:-}" = yes ] && [ "$match" = claude:simplifier:new ]; then exit 17; fi
if [ "$conversation" = new ]; then printf 'sid-%s\n' "$seat" > "$session_out"; fi
if [ "$conversation" = resume ] && [ "$session_id" != "sid-$seat" ]; then exit 18; fi
if [ "$role" = council-chair ]; then
  if [ "${FAKE_PARALLEL_PROBE:-}" = yes ]; then
    [ "$(find "$attempt" -name '*-resume.done' | wc -l | tr -d ' ')" -eq 5 ] || exit 24
  fi
  grep -Fq 'Anonymous peer reviews:' "$prompt" || exit 19
  grep -Fq 'Minority reports are mandatory.' "$prompt" || exit 20
fi
printf 'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nengine=%s\nauthor=%s\n' "$engine" "$seat" > "$output"
if [ "${FAKE_NO_FINAL_NEWLINE:-}" = yes ]; then printf 'recommendation=reply-%s' "$seat" >> "$output"; fi
: > "$attempt/$seat-$conversation.done"
printf 'end|%s|%s|%s\n' "$attempt" "$conversation" "$seat" >> "$FAKE_DIR/events.log"
FAKE
    chmod +x "$lib/"*.sh
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fakebin/claude"; chmod +x "$fakebin/claude"
    if [ "$include_other" = yes ]; then cp "$fakebin/claude" "$fakebin/codex"; fi
    (cd "$repo" && git init -q)
    printf 'Should Forge choose this design?\n' > "$repo/question.txt"; printf 'candidate\n' > "$repo/artifact.txt"
    FIXTURE_ROOT="$root"; FIXTURE_REPO="$repo"; FIXTURE_BIN="$fakebin"; FIXTURE_LOG="$root/calls.log"; : > "$FIXTURE_LOG"; : > "$root/events.log"
}

run_fixture() {
    local output="$FIXTURE_ROOT/run.out"
    (cd "$FIXTURE_REPO" && env PATH="$FIXTURE_BIN:/usr/bin:/bin" FORGE_NATIVE_HOST=claude FAKE_LOG="$FIXTURE_LOG" FAKE_DIR="$FIXTURE_ROOT" FAKE_FAIL_MATCH="${FAKE_FAIL_MATCH:-}" FAKE_PARALLEL_PROBE="${FAKE_PARALLEL_PROBE:-}" FAKE_DELAY="${FAKE_DELAY:-}" FAKE_MAIN_FAIL="${FAKE_MAIN_FAIL:-}" FAKE_NO_FINAL_NEWLINE="${FAKE_NO_FINAL_NEWLINE:-}" \
      bash .forge/hooks/lib/council-dispatch.sh --question-file question.txt --artifact artifact.txt --workflow-base-sha deadbeef --workflow-base-ref refs/heads/main "$@") > "$output" 2>&1
    RUN_RC=$?; RUN_OUTPUT="$output"; RECEIPT=$(sed -n 's/^Council receipt: //p' "$output" | tail -1)
}

start_test "healthy council uses six sessions and eleven bound turns"
make_fixture healthy yes
FAKE_FAIL_MATCH= run_fixture
assert_equals "$RUN_RC" 0 "healthy topology succeeds"
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 11 "healthy topology dispatches eleven turns"
assert_equals "$(awk -F'|' '$4=="new"{n++} END{print n+0}' "$FIXTURE_LOG")" 5 "five advisor sessions start fresh"
assert_equals "$(awk -F'|' '$4=="resume"{n++} END{print n+0}' "$FIXTURE_LOG")" 5 "five peer turns resume exact sessions"
assert_equals "$(awk -F'|' '$4=="ephemeral"{n++} END{print n+0}' "$FIXTURE_LOG")" 1 "chairman is the sixth fresh session"
assert_contains "$RECEIPT" "topology_mode=mixed" "receipt records mixed topology"
assert_contains "$RECEIPT" "main_host=claude" "receipt records declared main host metadata"
assert_contains "$RECEIPT" "turn_results=11" "receipt binds all turn results"
assert_contains "$RECEIPT" "session_id.simplifier=sid-simplifier" "receipt binds exact session ids"
peer_bundle="$(dirname "$RECEIPT")/anonymous-peer-reviews.txt"
assert_contains "$peer_bundle" "### Peer review A" "peer bundle uses opaque labels"
assert_not_contains "$peer_bundle" "simplifier" "peer bundle does not reveal persona seat names"

start_test "advice and peer waves overlap with complete phase barriers"
make_fixture parallel yes
FAKE_PARALLEL_PROBE=yes FAKE_FAIL_MATCH= run_fixture
assert_equals "$RUN_RC" 0 "all five seats rendezvous concurrently in each wave"
if [ "$RUN_RC" -eq 0 ]; then
  assert_equals "$(sed -n 's/^### Advisor //p' "$(dirname "$RECEIPT")/anonymous-advice.txt" | tr '\n' ' ')" 'A B C D E ' "advice is assembled in deterministic seat order"
  assert_equals "$(sed -n 's/^### Peer review //p' "$(dirname "$RECEIPT")/anonymous-peer-reviews.txt" | tr '\n' ' ')" 'A B C D E ' "peer reviews are assembled in deterministic seat order"
fi

start_test "unterminated engine responses preserve bundle boundaries and exclude self"
make_fixture no-final-newline yes
FAKE_NO_FINAL_NEWLINE=yes FAKE_PARALLEL_PROBE=yes FAKE_FAIL_MATCH= run_fixture
assert_equals "$RUN_RC" 0 "council completes with unterminated engine responses"
if [ "$RUN_RC" -eq 0 ]; then
  result_dir=$(dirname "$RECEIPT")
  assert_equals "$(sed -n 's/^### Advisor //p' "$result_dir/anonymous-advice.txt" | tr '\n' ' ')" 'A B C D E ' "unterminated advice retains all five ordered headings"
  assert_equals "$(sed -n 's/^### Peer review //p' "$result_dir/anonymous-peer-reviews.txt" | tr '\n' ' ')" 'A B C D E ' "unterminated peer responses retain all five ordered headings"
  for seat in simplifier scalability_hawk pragmatist contrarian maintainer; do
    assert_not_contains "$result_dir/$seat-others.txt" "recommendation=reply-$seat" "peer $seat excludes its own unterminated answer"
    assert_equals "$(grep -c '^recommendation=reply-' "$result_dir/$seat-others.txt")" 4 "peer $seat receives all four other answers"
  done
fi

start_test "known other absence starts one all-main topology"
make_fixture absent no
FAKE_FAIL_MATCH= run_fixture
assert_equals "$RUN_RC" 0 "known absence degrades without stopping"
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 11 "known absence launches no discarded mixed turns"
assert_equals "$(awk -F'|' '$1!="claude"{n++} END{print n+0}' "$FIXTURE_LOG")" 0 "all known-absence seats use main"
assert_contains "$RECEIPT" "trigger_reason=known-other-unavailable" "known absence is visible"

start_test "runtime other failures discard the attempt and rerun all-main"
for spec in 'codex:contrarian:new|' 'codex:contrarian:resume|' 'codex:chair:ephemeral|' 'codex:simplifier:new|custom'; do
    match=${spec%%|*}; mode=${spec#*|}; make_fixture "fallback-${match//:/-}" yes; FAKE_FAIL_MATCH=$match
    if [ "$mode" = custom ]; then run_fixture --seat-engine simplifier=other; else run_fixture; fi
    assert_equals "$RUN_RC" 0 "other failure $match reaches all-main fallback"
    assert_contains "$RECEIPT" "trigger_reason=runtime-other-failure" "other failure $match is disclosed"
    assert_contains "$RUN_OUTPUT" "injected failure: $match" "failed dispatcher diagnostics survive attempt removal"
    assert_equals "$(find "$(dirname "$(dirname "$RECEIPT")")" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" 1 "failed $match attempt artifacts are discarded"
    assert_equals "$(tail -11 "$FIXTURE_LOG" | awk -F'|' '$1!="claude"{n++} END{print n+0}')" 0 "fallback after $match reruns every turn on main"
done

start_test "main-engine failures block instead of fabricating a verdict"
make_fixture main-failure yes; FAKE_FAIL_MATCH=claude:simplifier:new; run_fixture
if [ "$RUN_RC" -ne 0 ]; then pass "main advisor failure blocks"; else fail "main advisor failure must block"; fi
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 5 "main failure drains the advice wave without starting peers or fallback"
make_fixture main-chair yes; FAKE_FAIL_MATCH=claude:chair:ephemeral; run_fixture --seat-engine chair=main
if [ "$RUN_RC" -ne 0 ]; then pass "custom main chairman failure blocks"; else fail "custom main chairman failure must block"; fi
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 11 "custom main chairman failure does not rerun"

start_test "fallback waits for the failed wave and main failure takes precedence"
make_fixture drain yes
FAKE_DELAY=yes FAKE_FAIL_MATCH=codex:contrarian:new run_fixture
assert_equals "$RUN_RC" 0 "delayed failed wave reaches fallback"
if awk -F'|' 'NR==1 {first=$2} $2==first {if($1=="start") active++; else active--} $2!=first && active!=0 {exit 1} END {if(active!=0) exit 1}' "$FIXTURE_ROOT/events.log"; then
  pass "fallback starts only after every failed-attempt worker exits"
else fail "fallback overlapped a failed-attempt worker"; fi
make_fixture simultaneous-failure yes
FAKE_MAIN_FAIL=yes FAKE_FAIL_MATCH=codex:contrarian:new run_fixture
if [ "$RUN_RC" -ne 0 ]; then pass "simultaneous main and other failures block"; else fail "main failure must take precedence over fallback"; fi
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 5 "simultaneous failures do not launch fallback"

start_test "parallel council integrates with real isolated session transport"
integration=$(scratch_dir council-transport)
integration=$(cd "$integration" && pwd -P)
git -C "$integration" init -q
git -C "$integration" config user.email test@example.invalid
git -C "$integration" config user.name ForgeTest
printf 'candidate\n' > "$integration/app.txt"
git -C "$integration" add app.txt
git -C "$integration" commit -qm base
base=$(git -C "$integration" rev-parse HEAD)
mkdir -p "$integration/.forge/local"
printf '<!-- forge:state-schema v6 -->\n# Project State\n\n## Identity\n\n| Field | Value |\n| --- | --- |\n| Worktree root | %s |\n| Git common directory | %s/.git |\n| Last active host | claude |\n| Workflow base ref | main |\n| Workflow base SHA | %s |\n\n## Workflow\n' "$integration" "$integration" "$base" > "$integration/.forge/local/state.md"
printf 'Should Forge parallelize the council?\n' > "$integration/.forge/local/question.txt"
(cd "$integration" && env PATH="$REPO_ROOT/tests/template/fixtures/fake-engines:$PATH" FORGE_NATIVE_HOST=claude FORGE_DISPATCH_TEST_MODE=1 \
  bash "$DISPATCH" --question-file .forge/local/question.txt --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref main --timeout-seconds 5) > "$integration/.forge/local/run.out" 2>&1
integration_rc=$?
assert_equals "$integration_rc" 0 "eleven parallel-orchestrated turns pass real candidate and exact-session checks"
if [ "$integration_rc" -eq 0 ]; then
  assert_equals "$(find "$integration/.forge/local/reviews/sessions" -name '*.meta' | wc -l | tr -d ' ')" 5 "five distinct real session metadata records exist"
  assert_equals "$(grep -l '^completed=true$' "$integration/.forge/local/reviews/sessions/"*.meta | wc -l | tr -d ' ')" 5 "all real advisor sessions complete their peer resumes"
  assert_equals "$(find "$integration/.forge/local/reviews/session-stores" -mindepth 1 | wc -l | tr -d ' ')" 0 "successful peer resumes clean up every private session store"
else
  tail -30 "$integration/.forge/local/run.out"
fi

start_test "failed real advice attempts release only their own sessions"
assert_advisor_snapshots_removed() {
  local record path remaining=0 observed=0
  for record in "$integration/.forge/local/reviews/"*.attempt-1.candidate; do
    # Chair is ephemeral; only new advisor captures have bound session stores.
    invocation=${record##*/}; invocation=${invocation%.attempt-1.candidate}
    [ -f "$integration/.forge/local/reviews/$invocation.receipt" ] || continue
    grep -q '^role=council-advisor$' "$integration/.forge/local/reviews/$invocation.receipt" || continue
    path=$(sed -n 's/^snapshot_path=//p' "$record")
    observed=$((observed + 1))
    [ ! -d "$path" ] || remaining=$((remaining + 1))
  done
  [ "$observed" -gt 0 ] && pass 'advisor candidate snapshots were actually captured' || fail 'missing captured advisor snapshot evidence'
  assert_equals "$remaining" 0 'completed or abandoned advisors leave no private candidate copies'
}
assert_advisor_snapshots_removed
mkdir -p "$integration/.forge/local/reviews/session-stores/unrelated"
printf 'keep unrelated private input\n' > "$integration/.forge/local/reviews/session-stores/unrelated/sentinel"
printf 'schema_version=1\ncompleted=false\nstore_id=unrelated\n' > "$integration/.forge/local/reviews/sessions/unrelated.meta"
for failed_engine in codex claude; do
  behavior_name=FAKE_CODEX_BEHAVIOR; [ "$failed_engine" != claude ] || behavior_name=FAKE_CLAUDE_BEHAVIOR
  (cd "$integration" && env PATH="$REPO_ROOT/tests/template/fixtures/fake-engines:$PATH" FORGE_NATIVE_HOST=claude FORGE_DISPATCH_TEST_MODE=1 \
    "$behavior_name=exit" bash "$DISPATCH" --question-file .forge/local/question.txt --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref main --timeout-seconds 5) > "$integration/.forge/local/failed-$failed_engine.out" 2>&1
  failed_rc=$?
  if [ "$failed_engine" = codex ]; then assert_equals "$failed_rc" 0 "other-engine advice failure completes the all-main rerun"
  elif [ "$failed_rc" -ne 0 ]; then pass "main-engine advice failure blocks without rerun"; else fail "main-engine failure must block"; fi
  assert_equals "$(find "$integration/.forge/local/reviews/session-stores" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 1 "$failed_engine failure leaves no attempt-owned private stores"
  assert_equals "$(grep -l '^completed=false$' "$integration/.forge/local/reviews/sessions/"*.meta | wc -l | tr -d ' ')" 1 "$failed_engine failure leaves no resumable abandoned sessions"
  assert_equals "$(cat "$integration/.forge/local/reviews/session-stores/unrelated/sentinel")" 'keep unrelated private input' "unrelated session survives $failed_engine failure"
  assert_advisor_snapshots_removed
done

start_test "failed real peer resume releases the failed seat store"
peer_bin="$integration/.forge/local/peer-bin"; mkdir -p "$peer_bin"
ln -s "$REPO_ROOT/tests/template/fixtures/fake-engines/claude" "$peer_bin/claude"
# Exercise the production dispatcher; fail only Codex resume, not new advice.
printf '#!/usr/bin/env bash\nfor arg in "$@"; do [ "$arg" != resume ] || export FAKE_CODEX_BEHAVIOR=exit; done\nexec "%s" "$@"\n' "$REPO_ROOT/tests/template/fixtures/fake-engines/codex" > "$peer_bin/codex"
chmod +x "$peer_bin/codex"
(cd "$integration" && env PATH="$peer_bin:$PATH" FORGE_NATIVE_HOST=claude FORGE_DISPATCH_TEST_MODE=1 \
  bash "$DISPATCH" --question-file .forge/local/question.txt --artifact git:working-tree --workflow-base-sha "$base" --workflow-base-ref main --timeout-seconds 5) > "$integration/.forge/local/failed-peer.out" 2>&1
assert_equals "$?" 0 "failed real peer resumes still permit a complete all-main rerun"
assert_equals "$(find "$integration/.forge/local/reviews/session-stores" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 1 "failed peers release their private stores while preserving unrelated sessions"
assert_equals "$(grep -l '^completed=false$' "$integration/.forge/local/reviews/sessions/"*.meta | wc -l | tr -d ' ')" 1 "failed peer sessions are terminal, not resumable"
assert_advisor_snapshots_removed

start_test "council receipt root rejects a linked council ancestor"
make_fixture linked-root yes
qhash=$(shasum -a 256 "$FIXTURE_REPO/question.txt" | awk '{print $1}')
mkdir -p "$FIXTURE_REPO/.forge/local/reviews" "$FIXTURE_ROOT/outside-council"
ln -s "$FIXTURE_ROOT/outside-council" "$FIXTURE_REPO/.forge/local/reviews/council-$qhash"
FAKE_FAIL_MATCH= run_fixture
if [ "$RUN_RC" -ne 0 ]; then pass "linked council receipt root blocks before dispatch"; else fail "linked council receipt root was followed"; fi
assert_equals "$(find "$FIXTURE_ROOT/outside-council" -mindepth 1 | wc -l | tr -d ' ')" 0 \
  "linked council target remains untouched"

start_test "PowerShell council uses the installed capability path"
if grep -Fq '$capabilities = Join-Path $root '\''host-capabilities.tsv'\''' "$REPO_ROOT/hooks/lib/council-dispatch.ps1"; then
    pass "PowerShell council reads the installed capability location"
else
    fail "PowerShell council must read .forge/host-capabilities.tsv"
fi
report "test-council-dispatch.sh"
