#!/usr/bin/env bash
# Installed Stop contracts with each main host and event-cwd worktree routing.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
SCRATCH=$(scratch_dir stop-workflow)
SCRATCH=$(cd "$SCRATCH" && pwd -P)
_SCRATCH_DIRS+=("$SCRATCH")

install_hooks() {
    local root="$1"
    mkdir -p "$root/.forge/local" "$root/.claude" "$root/.codex" "$root/bin"
    printf '#!/bin/sh\nexit 1\n' > "$root/bin/gh"
    chmod +x "$root/bin/gh"
    cp -R "$REPO_ROOT/hooks" "$root/.forge/hooks"
    chmod +x "$root/.forge/hooks/"*.sh "$root/.forge/hooks/lib/"*.sh
    cp "$REPO_ROOT/settings/settings.template.json" "$root/.claude/settings.json"
    cp "$REPO_ROOT/settings/codex-hooks.template.json" "$root/.codex/hooks.json"
    cp "$REPO_ROOT/state.template.md" "$root/.forge/local/state.md"
    printf '6\n' > "$root/.forge/version"
}
make_repo() {
    local root="$1" workflow="$2" host="$3" prefix
    mkdir -p "$root/docs"
    git -C "$root" init -q --initial-branch=main
    git -C "$root" config user.email forge-test@example.com
    git -C "$root" config user.name 'Forge Test'
    printf '.forge/\n.claude/\n.codex/\nbin/\n*.out\n*.err\n' > "$root/.gitignore"
    printf 'fixture\n' > "$root/README.md"
    printf 'fixture\n' > "$root/docs/CHANGELOG.md"
    git -C "$root" add .
    git -C "$root" commit -qm init
    case "$workflow" in quick-fix) prefix=quick-fix ;; new-feature) prefix=feat ;; fix-bug) prefix=fix ;; esac
    git -C "$root" switch -qc "$prefix/stop-smoke"
    install_hooks "$root"
    (cd "$root" && bash .forge/hooks/lib/workflow-state.sh activate --host "$host" \
        --workflow "$workflow" --task stop-smoke --base-ref main --phase implementation --next-step 'finish smoke') >/dev/null
}
complete() {
    (cd "$1" && bash .forge/hooks/lib/workflow-state.sh checkpoint --host "$2" \
        --phase complete --next-step 'await new work') >/dev/null
}
run_stop() {
    local registered="$1" event="$2" host="$3" active="${4:-false}" turn="${5:-}" hook="${6:-check-state-updated.sh}" command payload
    command=$(python3 - "$registered" "$host" "$hook" <<'PY'
import json, pathlib, sys
root, host = pathlib.Path(sys.argv[1]), sys.argv[2]
settings = root / ('.codex/hooks.json' if host == 'codex' else '.claude/settings.json')
commands = [h['command'] for g in json.loads(settings.read_text())['hooks']['Stop'] for h in g['hooks']]
print(next(c for c in commands if sys.argv[3] in c))
PY
)
    payload=$(printf '{"cwd":"%s","host":"%s","hook_event_name":"Stop","stop_hook_active":%s,"session_id":"stop-smoke","turn_id":"%s"}' "$event" "$host" "$active" "$turn")
    (cd "$registered" && printf '%s' "$payload" | PATH="$registered/bin:$PATH" CLAUDE_PROJECT_DIR="$registered" bash -c "$command") \
        > "$registered/stop.out" 2> "$registered/stop.err"
}
inactive_goal() {
    python3 - "$1/.forge/local/state.md" "$2" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); text = p.read_text()
if sys.argv[2] == 'missing':
    text = re.sub(r'(?ms)^## /goal session\n.*?(?=^## |\Z)', '', text)
elif sys.argv[2] == 'empty':
    text = text.replace('<uuid-v4-lowercase>', '', 1)
p.write_text(text)
PY
}
assert_no_goal_output() {
    local root="$1" host="$2" label="$3" status="${4:-0}"
    assert_not_contains "$root/stop.err" FORGE_GOAL_EVIDENCE "$label emits no Goal markers"
    assert_not_contains "$root/stop.err" '"session_nonce"' "$label emits no inactive Goal JSON"
    if python3 - "$root/stop.out" "$host" "$status" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1]).read_text().strip()
assert json.loads(out) == {} if sys.argv[2] == 'codex' and sys.argv[3] == '0' else out == ''
PY
    then pass "$label preserves host allow output"; else fail "$label preserves host allow output"; fi
}
non_goal_builder() {
    local registered="$1" event="$2" host="$3" label="$4"
    run_stop "$registered" "$event" "$host" false '' build-evidence.sh
    assert_equals "$?" 0 "$label registered builder allows Stop"
    assert_no_goal_output "$registered" "$host" "$label registered builder"
}
assert_goal_output() {
    if python3 - "$1/stop.err" "$2" <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'FORGE_GOAL_EVIDENCE_BEGIN\s*(.*?)\s*FORGE_GOAL_EVIDENCE_END', text, re.S)
assert match and json.loads(match[1])['session_nonce'] == sys.argv[2]
PY
    then pass "$3 retains active Goal JSON"; else fail "$3 retains active Goal JSON"; fi
}
crlf_state() {
    python3 - "$1/.forge/local/state.md" <<'PY_CRLF'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))
PY_CRLF
}
quiet_stop() {
    local root="$1" host="$2" label="$3"
    run_stop "$root" "$root" "$host"
    assert_equals "$?" 0 "$label allows Stop"
    assert_not_contains "$root/stop.err" 'FORGE_FINAL_EVIDENCE_STALE' "$label suppresses historical receipt warning"
    assert_not_contains "$root/stop.err" 'WORKFLOW:' "$label suppresses completed-workflow continuation"
    assert_no_goal_output "$root" "$host" "$label inline/check-state"
    non_goal_builder "$root" "$root" "$host" "$label"
    assert_file_exists "$root/.forge/local/forge-goal-last-fingerprint" "$label keeps fingerprint publication"
}
for host in claude codex; do
    for workflow in quick-fix new-feature fix-bug; do
      for nonce_mode in missing empty template; do
        start_test "$host main: $workflow with $nonce_mode Goal nonce repeats Stop quietly"
        root="$SCRATCH/$host-$workflow-$nonce_mode"
        make_repo "$root" "$workflow" "$host"
        inactive_goal "$root" "$nonce_mode"
        # Seed the active checkpoint hash so completion must not reuse its continuation path.
        run_stop "$root" "$root" "$host"
        assert_equals "$?" 0 'first active checkpoint stops normally'
        assert_no_goal_output "$root" "$host" 'first active inline/check-state'
        non_goal_builder "$root" "$root" "$host" 'first active'
        assert_file_exists "$root/.forge/local/forge-goal-last-fingerprint" 'non-Goal active fingerprint remains published'
        complete "$root" "$host"
        rm -f "$root/.forge/local/forge-goal-last-fingerprint"
        for delivery in 1 2 3; do quiet_stop "$root" "$host" "completed delivery $delivery"; done
      done
    done
    start_test "$host main: CRLF active/completed controls preserve independent gates"
    root="$SCRATCH/$host-active"
    make_repo "$root" new-feature "$host"
    crlf_state "$root"
    run_stop "$root" "$root" "$host"
    assert_equals "$?" 0 'changed active checkpoint allows Stop'
    assert_contains "$root/stop.err" FORGE_FINAL_EVIDENCE_STALE 'active missing receipts still warn'
    assert_no_goal_output "$root" "$host" 'CRLF active inline/check-state'
    non_goal_builder "$root" "$root" "$host" 'CRLF active'
    run_stop "$root" "$root" "$host"
    assert_equals "$?" 2 'unchanged active checkpoint continues'
    assert_contains "$root/stop.err" '/new-feature stop-smoke' 'active continuation names its workflow'
    assert_no_goal_output "$root" "$host" 'CRLF unchanged active check-state' 2
    run_stop "$root" "$root" "$host" true
    assert_equals "$?" 0 'continuation-loop guard remains effective'
    assert_not_contains "$root/stop.err" 'WORKFLOW:' 'guard prevents another continuation'
    complete "$root" "$host"
    crlf_state "$root"
    quiet_stop "$root" "$host" "CRLF completed first Stop"
    quiet_stop "$root" "$host" "CRLF completed repeated Stop"
    # No open PR: keep this fixture deterministic and prevent network probes.
    for file in one two three four; do printf 'before\n' > "$root/$file"; done
    git -C "$root" add one two three four
    git -C "$root" commit -qm fixture
    run_stop "$root" "$root" "$host"
    assert_equals "$?" 2 'completed workflow retains changelog gate'
    assert_contains "$root/stop.err" 'Update docs/CHANGELOG.md' 'changelog failure remains visible'
    printf 'updated\n' >> "$root/docs/CHANGELOG.md"
    payload=$(printf '{"cwd":"%s","host":"%s","tool_name":"Bash","tool_input":{"command":"git push origin HEAD"}}' "$root" "$host")
    gate_command=$(python3 - "$root" "$host" <<'PY_GATE'
import json, pathlib, sys
root, host = pathlib.Path(sys.argv[1]), sys.argv[2]
settings = root / ('.codex/hooks.json' if host == 'codex' else '.claude/settings.json')
commands = [h['command'] for g in json.loads(settings.read_text())['hooks']['PreToolUse'] for h in g['hooks']]
print(next(c for c in commands if 'check-workflow-gates.sh' in c))
PY_GATE
)
    (cd "$root" && printf '%s' "$payload" | PATH="$root/bin:$PATH" CLAUDE_PROJECT_DIR="$root" bash -c "$gate_command") > "$root/gate.out" 2> "$root/gate.err"
    assert_equals "$?" 2 'registered shipping gate preserves blocking status 2'
    # Invalid canonical shape remains a hard failure even with complete phase.
    printf '\n## Workflow\n| Command | none |\n' >> "$root/.forge/local/state.md"
    run_stop "$root" "$root" "$host"
    assert_equals "$?" 2 'completed state still requires valid canonical shape'
    assert_contains "$root/stop.err" FORGE_STATE_INVALID 'invalid state diagnostic is preserved'

    start_test "$host main: event cwd keeps primary quick-fix and linked feature independent"
    primary="$SCRATCH/$host-primary"
    linked="$SCRATCH/$host-linked"
    make_repo "$primary" quick-fix "$host"
    complete "$primary" "$host"
    git -C "$primary" worktree add -qb feat/linked-smoke "$linked" main
    install_hooks "$linked"
    (cd "$linked" && bash .forge/hooks/lib/workflow-state.sh activate --host "$host" \
        --workflow new-feature --task linked-smoke --base-ref main --phase implementation --next-step 'finish linked smoke') >/dev/null
    mkdir -p "$linked/nested"
    primary_hash=$(hash_file "$primary/.forge/local/state.md")
    run_stop "$primary" "$linked/nested" "$host"
    assert_equals "$?" 0 'linked first checkpoint stops normally'
    assert_no_goal_output "$primary" "$host" 'linked first inline/check-state'
    non_goal_builder "$primary" "$linked/nested" "$host" 'linked first'
    run_stop "$primary" "$linked/nested" "$host"
    assert_equals "$?" 2 'linked active feature continues independently'
    assert_contains "$primary/stop.err" '/new-feature linked-smoke' 'event worktree feature is named'
    assert_not_contains "$primary/stop.err" '/quick-fix' 'primary quick-fix is absent from linked feedback'
    assert_no_goal_output "$primary" "$host" 'linked active check-state' 2
    assert_file_exists "$linked/.forge/local/forge-goal-last-fingerprint" 'feature fingerprint is published in the event worktree'
    primary_leak=false
    for path in "$primary"/.forge/local/forge-goal-last-fingerprint* "$primary"/.forge/local/.state-last-stop.*; do
        [ ! -e "$path" ] || primary_leak=true
    done
    assert_equals "$primary_leak" false 'linked native I/O leaves no primary fingerprint or temp file'
    assert_hash_equals "$primary/.forge/local/state.md" "$primary_hash" 'linked Stop preserves primary state'
    quiet_stop "$primary" "$host" 'primary completed quick-fix'
    assert_file_exists "$linked/.forge/local/state-last-stop.sha256" 'checkpoint sidecar is worktree local'
    complete "$linked" "$host"
    run_stop "$primary" "$linked/nested" "$host"
    assert_equals "$?" 0 'linked completed feature stops normally'
    assert_not_contains "$primary/stop.err" FORGE_FINAL_EVIDENCE_STALE 'linked completion suppresses stale receipts'
    assert_not_contains "$primary/stop.err" WORKFLOW: 'linked completion suppresses continuation'
    assert_no_goal_output "$primary" "$host" 'linked completed inline/check-state'
    non_goal_builder "$primary" "$linked/nested" "$host" 'linked completed'
    # An activated linked Goal must keep the fingerprint and stuck counter local.
    cat >> "$linked/.forge/local/state.md" <<LINKED_GOAL

## /goal session
| Field | Value |
| nonce | 66666666-6666-4666-8666-666666666666 |
| objective_hash | linked-objective |
| activation_id | 55555555-5555-4555-8555-555555555555 |
| activation_host | $host |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature linked-smoke |
| turn_count | 0 |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/latest.json |
LINKED_GOAL
    python3 - "$linked/.forge/local/state.md" <<'PY_LINKED_GOAL'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); text = p.read_text(); a = text.index('## /goal session'); b = text.find('\n## ', a + 1)
if b >= 0: p.write_text(text[:a] + text[b:])
PY_LINKED_GOAL
    bash "$linked/.forge/hooks/lib/goal-ledger.sh" activate --project "$linked" --state "$linked/.forge/local/state.md" >/dev/null
    assert_equals "$?" 0 'linked native Goal activates'
    # Seed the counter from a real feature-process build, independently of
    # the Stop publication checked above.
    payload=$(printf '{"cwd":"%s","host":"%s","stop_hook_active":true}' "$linked/nested" "$host")
    run_stop "$linked" "$linked/nested" "$host" true '' build-evidence.sh
    assert_equals "$?" 0 'feature fingerprint seeds the counter control'
    assert_goal_output "$linked" 66666666-6666-4666-8666-666666666666 'linked registered builder'
    primary_fp=$(hash_file "$primary/.forge/local/forge-goal-last-fingerprint")
    for delivery in 1 2; do
        run_stop "$primary" "$linked/nested" "$host" true linked-goal-turn
        assert_equals "$?" 0 'linked native Goal Stop allows completion'
    done
    linked_fp=$(tr -d '[:space:]' < "$linked/.forge/local/forge-goal-last-fingerprint")
    assert_contains "$linked/.forge/local/forge-goal-stuck-count" "2|$linked_fp" 'linked stuck counter advances against its own fingerprint'
    assert_file_missing "$primary/.forge/local/forge-goal-stuck-count" 'linked stuck counter does not leak into primary'
    assert_hash_equals "$primary/.forge/local/forge-goal-last-fingerprint" "$primary_fp" 'linked Goal preserves primary fingerprint'
    primary_leak=false
    for path in "$primary"/.forge/local/forge-goal-last-fingerprint.tmp.*; do
        [ ! -e "$path" ] || primary_leak=true
    done
    assert_equals "$primary_leak" false 'linked Goal leaves no primary fingerprint temp file'

    start_test "$host main: completed workflow still charges native Goal"
    root="$SCRATCH/$host-goal"
    make_repo "$root" new-feature "$host"
    complete "$root" "$host"
    nonce=88888888-8888-4888-8888-888888888888
    cat >> "$root/.forge/local/state.md" <<GOAL

## /goal session
| Field | Value |
| nonce | $nonce |
| objective_hash | objective-42 |
| activation_id | 77777777-7777-4777-8777-777777777777 |
| activation_host | $host |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature stop-smoke |
| turn_count | 0 |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/latest.json |
GOAL
    # Replace the template's placeholder Goal block, rather than making duplicate sections.
    python3 - "$root/.forge/local/state.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); text = p.read_text(); a = text.index('## /goal session'); b = text.find('\n## ', a + 1)
if b >= 0: p.write_text(text[:a] + text[b:])
PY
    bash "$root/.forge/hooks/lib/goal-ledger.sh" activate --project "$root" --state "$root/.forge/local/state.md" >/dev/null
    assert_equals "$?" 0 'native Goal activation succeeds'
    run_stop "$root" "$root" "$host" false '' build-evidence.sh
    assert_equals "$?" 0 'active Goal registered builder allows Stop'
    assert_goal_output "$root" "$nonce" 'active Goal registered builder'
    run_stop "$root" "$root" "$host" false goal-turn-1
    assert_equals "$?" 0 'completed workflow allows native Goal Stop'
    run_stop "$root" "$root" "$host" false goal-turn-1
    assert_equals "$?" 0 'duplicate native Goal event remains idempotent'
    turns="$root/.git/forge-goals/$nonce/turns"
    assert_file_exists "$turns/00000001" 'complete phase still publishes the charged turn'
    assert_file_missing "$turns/00000002" 'duplicate Stop charges once'
    assert_contains "$turns/00000001" "host=$host" 'ledger retains main-host attribution'
    # The emission guard must see the first nonce, even when later rows conflict.
    python3 - "$root/.forge/local/state.md" "$nonce" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace('| nonce | ' + sys.argv[2] + ' |', '| Nonce | ' + sys.argv[2] + ' |\n| nonce | <uuid-v4-lowercase> |'))
PY
    run_stop "$root" "$root" "$host" false '' build-evidence.sh
    assert_goal_output "$root" "$nonce" 'uppercase first nonce with later placeholder'
done
report 'Stop workflow'
