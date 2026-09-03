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
match="$engine:$seat:$conversation"
if [ "${FAKE_FAIL_MATCH:-}" = "$match" ] && [ ! -e "$FAKE_DIR/failure-used" ]; then : > "$FAKE_DIR/failure-used"; exit 17; fi
if [ "$conversation" = new ]; then printf 'sid-%s\n' "$seat" > "$session_out"; fi
if [ "$conversation" = resume ] && [ "$session_id" != "sid-$seat" ]; then exit 18; fi
if [ "$role" = council-chair ]; then
  grep -Fq 'Anonymous peer reviews:' "$prompt" || exit 19
  grep -Fq 'Minority reports are mandatory.' "$prompt" || exit 20
fi
printf 'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nengine=%s\nauthor=%s\n' "$engine" "$seat" > "$output"
FAKE
    chmod +x "$lib/"*.sh
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fakebin/claude"; chmod +x "$fakebin/claude"
    if [ "$include_other" = yes ]; then cp "$fakebin/claude" "$fakebin/codex"; fi
    (cd "$repo" && git init -q)
    printf 'Should Forge choose this design?\n' > "$repo/question.txt"; printf 'candidate\n' > "$repo/artifact.txt"
    FIXTURE_ROOT="$root"; FIXTURE_REPO="$repo"; FIXTURE_BIN="$fakebin"; FIXTURE_LOG="$root/calls.log"; : > "$FIXTURE_LOG"
}

run_fixture() {
    local output="$FIXTURE_ROOT/run.out"
    (cd "$FIXTURE_REPO" && env PATH="$FIXTURE_BIN:/usr/bin:/bin" FORGE_NATIVE_HOST=claude FAKE_LOG="$FIXTURE_LOG" FAKE_DIR="$FIXTURE_ROOT" FAKE_FAIL_MATCH="${FAKE_FAIL_MATCH:-}" \
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
    assert_equals "$(find "$(dirname "$(dirname "$RECEIPT")")" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" 1 "failed $match attempt artifacts are discarded"
    assert_equals "$(tail -11 "$FIXTURE_LOG" | awk -F'|' '$1!="claude"{n++} END{print n+0}')" 0 "fallback after $match reruns every turn on main"
done

start_test "main-engine failures block instead of fabricating a verdict"
make_fixture main-failure yes; FAKE_FAIL_MATCH=claude:simplifier:new; run_fixture
if [ "$RUN_RC" -ne 0 ]; then pass "main advisor failure blocks"; else fail "main advisor failure must block"; fi
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 1 "main failure does not start fallback"
make_fixture main-chair yes; FAKE_FAIL_MATCH=claude:chair:ephemeral; run_fixture --seat-engine chair=main
if [ "$RUN_RC" -ne 0 ]; then pass "custom main chairman failure blocks"; else fail "custom main chairman failure must block"; fi
assert_equals "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" 11 "custom main chairman failure does not rerun"

start_test "council receipt root rejects a linked council ancestor"
make_fixture linked-root yes
qhash=$(shasum -a 256 "$FIXTURE_REPO/question.txt" | awk '{print $1}')
mkdir -p "$FIXTURE_REPO/.forge/local/reviews" "$FIXTURE_ROOT/outside-council"
ln -s "$FIXTURE_ROOT/outside-council" "$FIXTURE_REPO/.forge/local/reviews/council-$qhash"
FAKE_FAIL_MATCH= run_fixture
if [ "$RUN_RC" -ne 0 ]; then pass "linked council receipt root blocks before dispatch"; else fail "linked council receipt root was followed"; fi
assert_equals "$(find "$FIXTURE_ROOT/outside-council" -mindepth 1 | wc -l | tr -d ' ')" 0 \
  "linked council target remains untouched"

start_test "PowerShell council uses the installed capability path and suppresses dispatcher stdout"
if grep -Fq '$capabilities = Join-Path $root '\''host-capabilities.tsv'\''' "$REPO_ROOT/hooks/lib/council-dispatch.ps1"; then
    pass "PowerShell council reads the installed capability location"
else
    fail "PowerShell council must read .forge/host-capabilities.tsv"
fi
if [ "$(grep -Fc '$null = & $agent' "$REPO_ROOT/hooks/lib/council-dispatch.ps1")" -ge 2 ]; then
    pass "PowerShell council keeps dispatcher stdout out of function return values"
else
    fail "PowerShell council must suppress advisor and chairman dispatcher stdout"
fi

report "test-council-dispatch.sh"
