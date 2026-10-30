#!/usr/bin/env bash
# Deterministic native-event/process context contracts. These fixtures are not native-host qualification.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
SCRATCH=$(scratch_dir worktree-context)
SCRATCH=$(cd "$SCRATCH" && pwd -P)
_SCRATCH_DIRS+=("$SCRATCH")
mkdir -p "$SCRATCH/repos" "$SCRATCH/logs"
PRIMARY="$SCRATCH/repos/main"
LINKED="$SCRATCH/repos/linked space-é"
SIBLING="$SCRATCH/repos/sibling"
UNRELATED="$SCRATCH/repos/unrelated"
SHADOW="$SCRATCH/repos/shadow-module"
ALIAS="$SCRATCH/linked-alias"

make_repo() {
    local root="$1"
    mkdir -p "$root"
    git -C "$root" init -q --initial-branch=main
    git -C "$root" config user.email forge-context@example.invalid
    git -C "$root" config user.name 'Forge Context Fixture'
    printf 'fixture\n' > "$root/tracked.txt"
    git -C "$root" add tracked.txt
    git -C "$root" commit -qm fixture
}
make_repo "$PRIMARY"
git -C "$PRIMARY" worktree add -qb fix/context-linked "$LINKED"
git -C "$PRIMARY" worktree add -qb fix/context-sibling "$SIBLING"
make_repo "$UNRELATED"
make_repo "$SHADOW"
ln -s "$LINKED" "$ALIAS"
for root in "$PRIMARY" "$LINKED" "$SIBLING" "$UNRELATED" "$SHADOW"; do
    mkdir -p "$root/.forge/local/reviews" "$root/.forge/memory" "$root/nested"
    cp -R "$REPO_ROOT/hooks" "$root/.forge/hooks"
    cp -R "$REPO_ROOT/hooks" "$root/hooks"
    printf 'preserved local state\n' > "$root/.forge/local/state.md"
    printf 'preserved receipt\n' > "$root/.forge/local/reviews/sentinel.receipt"
    printf 'preserved fingerprint\n' > "$root/.forge/local/forge-goal-last-fingerprint"
    printf 'preserved durable memory\n' > "$root/.forge/memory/MEMORY.md"
done
printf 'raise RuntimeError("fixture project json.py was imported")\n' > "$SHADOW/json.py"
mkdir -p "$SCRATCH/failing-python"
printf '#!/bin/sh\nprintf "fixture python failure\\n" >&2\nexit 1\n' > "$SCRATCH/failing-python/python3"
chmod +x "$SCRATCH/failing-python/python3"

hex_root() {
    python3 - "$1" <<'PY'
import sys
print(sys.argv[1].encode('utf-8').hex())
PY
}
LINKED_HEX=$(hex_root "$LINKED")
PRIMARY_HEX=$(hex_root "$PRIMARY")
SHADOW_HEX=$(hex_root "$SHADOW")
SEQ=0
LAST_OUT=""
LAST_ERR=""
LAST_RC=0
run_gate() {
    local host="$1" process_root="$2" event_cwd="$3" command="$4" path="${5:-.forge/hooks/check-workflow-gates.sh}" command_path="${6:-$PATH}"
    SEQ=$((SEQ + 1))
    LAST_OUT="$SCRATCH/logs/$SEQ.out"; LAST_ERR="$SCRATCH/logs/$SEQ.err"
    python3 - "$host" "$event_cwd" "$command" > "$SCRATCH/logs/$SEQ.input.json" <<'PY'
import json, sys
event = {'host':sys.argv[1], 'hook_event_name':'PreToolUse', 'tool_name':'Bash',
         'tool_input':{'command':sys.argv[3]}}
if sys.argv[2] != '<missing>':
    event['cwd'] = sys.argv[2]
json.dump(event, sys.stdout)
PY
    (cd "$process_root" && PATH="$command_path" bash "$path" < "$SCRATCH/logs/$SEQ.input.json") > "$LAST_OUT" 2> "$LAST_ERR"
    LAST_RC=$?
}
assert_native_match() {
    local label="$1"
    assert_equals "$LAST_RC" 2 "$label intentionally denies the diagnostic probe"
    assert_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT: MATCH' "$label reports native event agreement visibly"
    assert_contains "$LAST_ERR" "$LINKED" "$label identifies the matched worktree"
    assert_not_contains "$LAST_OUT" 'permissionDecision' "$label grants no tool permission"
}
snapshot() {
    python3 - "$SCRATCH/repos" <<'PY'
import hashlib, os, pathlib, sys
root = pathlib.Path(sys.argv[1]); result = hashlib.sha256()
for path in sorted(root.rglob('*')):
    result.update(str(path.relative_to(root)).encode('utf-8') + b'\0')
    if path.is_symlink(): result.update(b'link\0' + os.readlink(path).encode('utf-8'))
    elif path.is_file(): result.update(b'file\0' + path.read_bytes())
    else: result.update(b'dir\0')
print(result.hexdigest())
PY
}
BEFORE=$(snapshot)

# This is the owning regression: the OLD gate sees a non-shipping command and
# silently exits zero. It does not execute the probe helper, so RED cannot be
# explained by the new helper mode being absent.
for host in claude codex; do
    start_test "$host: native primary event cannot certify a linked task"
    run_gate "$host" "$LINKED" "$PRIMARY" "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX"
    assert_equals "$LAST_RC" 2 'mismatched native event rejects before probe execution'
    assert_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT: MISMATCH' 'mismatch is diagnosed as native context'
    assert_contains "$LAST_ERR" "$PRIMARY" 'diagnostic identifies actual primary event root'
    assert_contains "$LAST_ERR" "$LINKED" 'diagnostic identifies intended linked task root'
    assert_not_contains "$LAST_OUT" 'FORGE_NATIVE_CONTEXT: MATCH' 'mismatch emits no native match'

    start_test "$host: event identity governs independently of hook process directory"
    for helper in .forge/hooks/lib/host-context.sh hooks/lib/host-context.sh; do
        run_gate "$host" "$PRIMARY" "$LINKED" "bash $helper probe $LINKED_HEX"
        assert_native_match "$helper aligned linked event"
        run_gate "$host" "$PRIMARY" "$LINKED/nested" "bash $helper probe $LINKED_HEX"
        assert_native_match "$helper nested event"
    done
    run_gate "$host" "$PRIMARY" "$ALIAS/nested" "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX"
    assert_native_match 'symlink alias event normalizes to the physical linked root'
    for engine in powershell.exe pwsh; do
        for helper in .forge/hooks/lib/host-context.ps1 hooks/lib/host-context.ps1; do
            run_gate "$host" "$PRIMARY" "$LINKED" "$engine -NoProfile -ExecutionPolicy Bypass -File $helper -Mode probe -ExpectedRootHex $LINKED_HEX"
            assert_native_match "$engine fixed probe through Bash gate"
        done
    done

    start_test "$host: a sibling and an unrelated repository are not the intended worktree"
    for event in "$SIBLING" "$UNRELATED"; do
        run_gate "$host" "$LINKED" "$event" "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX"
        assert_equals "$LAST_RC" 2 'a different physical worktree is rejected'
        assert_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT: MISMATCH' 'different worktree gets an alignment diagnostic'
    done

    start_test "$host: missing and invalid native metadata cannot certify alignment"
    for event in '<missing>' '' relative/path "$SCRATCH/absent"; do
        run_gate "$host" "$LINKED" "$event" "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX"
        assert_equals "$LAST_RC" 2 'missing/invalid event cwd is blocked'
        assert_not_contains "$LAST_OUT" 'FORGE_NATIVE_CONTEXT: MATCH' 'invalid event emits no match'
    done

    start_test "$host: malformed fixed-probe commands fail closed"
    UPPER_HEX=$(printf '%s' "$LINKED_HEX" | tr 'a-f' 'A-F')
    for token in '' 2 2g ff 00 "$UPPER_HEX" "$(hex_root relative/path)" "$(hex_root "$SCRATCH/absent")"; do
        run_gate "$host" "$LINKED" "$LINKED" "bash .forge/hooks/lib/host-context.sh probe $token"
        assert_equals "$LAST_RC" 2 'invalid expected-root encoding/path is blocked'
        assert_not_contains "$LAST_OUT" 'FORGE_NATIVE_CONTEXT: MATCH' 'invalid expected root emits no match'
    done
    for suffix in ' extra' '; true' ' && git push origin HEAD' $'\ngit push origin HEAD' $'\r'; do
        run_gate "$host" "$LINKED" "$LINKED" "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX$suffix"
        assert_equals "$LAST_RC" 2 'extra argument/compound probe is rejected'
    done
    run_gate "$host" "$LINKED" "$LINKED" "bash .forge/hooks/lib/host-context.sh probe $(python3 -c 'print("2f" * 8193)')"
    assert_equals "$LAST_RC" 2 'excessive expected-root token is rejected'

    start_test "$host: malformed JSON, NUL and non-string native cwd cannot become a match"
    for malformed in nul-command raw-nul number-cwd null-cwd duplicate-cwd case-variant-cwd event-array input-array invalid-json; do
        SEQ=$((SEQ + 1)); LAST_OUT="$SCRATCH/logs/$SEQ.out"; LAST_ERR="$SCRATCH/logs/$SEQ.err"
        python3 - "$host" "$LINKED" "$LINKED_HEX" "$malformed" > "$SCRATCH/logs/$SEQ.input.json" <<'PY'
import json, sys
command = 'bash .forge/hooks/lib/host-context.sh probe ' + sys.argv[3]
event = {'host':sys.argv[1], 'cwd':sys.argv[2], 'tool_input':{'command':command}}
kind = sys.argv[4]
if kind == 'nul-command': event['tool_input']['command'] += '\0'
if kind == 'number-cwd': event['cwd'] = 17
if kind == 'null-cwd': event['cwd'] = None
if kind == 'input-array': event['tool_input'] = [event['tool_input']]
if kind == 'event-array': event = [event]
raw = json.dumps(event)
if kind == 'raw-nul': raw = raw.replace(command, command + '\0')
if kind == 'duplicate-cwd': raw = raw[:-1] + ',"cwd":"/different"}'
if kind == 'case-variant-cwd': raw = raw[:-1] + ',"Cwd":"/different"}'
if kind == 'invalid-json': raw = raw[:-1]
print(raw)
PY
        (cd "$LINKED" && bash .forge/hooks/check-workflow-gates.sh < "$SCRATCH/logs/$SEQ.input.json") > "$LAST_OUT" 2> "$LAST_ERR"
        assert_equals "$?" 2 "$malformed is rejected before any native-match claim"
        assert_not_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT: MATCH' "$malformed emits no matching diagnostic"
    done

    start_test "$host: source gate and existing ordinary commands retain their behavior"
    run_gate "$host" "$PRIMARY" "$LINKED" "bash hooks/lib/host-context.sh probe $LINKED_HEX" hooks/check-workflow-gates.sh
    assert_native_match 'source-layout gate'
    run_gate "$host" "$LINKED" "$LINKED" 'git status --short'
    assert_equals "$LAST_RC" 0 'ordinary read-only command remains allowed'
    assert_not_contains "$LAST_OUT" 'FORGE_NATIVE_CONTEXT: MATCH' 'ordinary success is not native probe evidence'
    for ordinary in "echo 'bash hooks/lib/host-context.sh probe documentation'" "echo 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File hooks/lib/host-context.ps1 -Mode probe examples'"; do
        run_gate "$host" "$LINKED" "$LINKED" "$ordinary"
        assert_equals "$LAST_RC" 0 'incidental quoted probe documentation is an ordinary command'
        assert_not_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT:' 'incidental mention emits no context diagnostic'
    done
    run_gate "$host" "$LINKED" "$LINKED" "git commit -m 'update hooks/lib/host-context.sh probe docs'"
    assert_not_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT:' 'commit message prose is not parsed as a probe'
    run_gate "$host" "$LINKED" "$LINKED" 'git commit -m fixture && git push origin HEAD'
    assert_equals "$LAST_RC" 2 'existing compound-shipping gate remains enforced'
    assert_contains "$LAST_ERR" 'compound ship command blocked' 'existing shipping diagnostic remains intact'

    start_test "$host: helper failure remains a blocking exit for native probes and shipping"
    for command in "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX" \
        "bash .forge/hooks/lib/host-context.sh probe $LINKED_HEX && git push origin HEAD" \
        "git commit -m 'update hooks/lib/host-context.sh probe documentation'"; do
        run_gate "$host" "$LINKED" "$LINKED" "$command" .forge/hooks/check-workflow-gates.sh "$SCRATCH/failing-python:$PATH"
        assert_equals "$LAST_RC" 2 'helper crash cannot become a nonblocking hook status'
        assert_contains "$LAST_ERR" 'fixture python failure' 'test reached the failing helper runtime'
    done

    start_test "$host: a project Python module cannot replace the probe JSON parser"
    run_gate "$host" "$SHADOW" "$SHADOW" "bash .forge/hooks/lib/host-context.sh probe $SHADOW_HEX"
    assert_equals "$LAST_RC" 2 'isolated native probe gives its intentional diagnostic denial'
    assert_contains "$LAST_ERR" 'FORGE_NATIVE_CONTEXT: MATCH' 'native probe uses the standard JSON parser'
    assert_not_contains "$LAST_ERR" 'fixture project json.py was imported' 'project shadow module was not loaded'
done

start_test 'installed Codex router preserves the native mismatch rather than selecting the process worktree'
SEQ=$((SEQ + 1)); ROUTE_OUT="$SCRATCH/logs/$SEQ.out"; ROUTE_ERR="$SCRATCH/logs/$SEQ.err"
python3 - "$PRIMARY" "$LINKED_HEX" > "$SCRATCH/logs/$SEQ.input.json" <<'PY'
import json, sys
json.dump({'cwd':sys.argv[1], 'host':'codex', 'hook_event_name':'PreToolUse', 'tool_name':'Bash',
           'tool_input':{'command':'bash .forge/hooks/lib/host-context.sh probe ' + sys.argv[2]}}, sys.stdout)
PY
(cd "$LINKED" && bash "$PRIMARY/.forge/hooks/lib/codex-worktree-dispatch.sh" check-workflow-gates.sh \
    < "$SCRATCH/logs/$SEQ.input.json") > "$ROUTE_OUT" 2> "$ROUTE_ERR"
assert_equals "$?" 2 'primary router rejects a native-primary/task-linked mismatch'
assert_contains "$ROUTE_ERR" 'FORGE_NATIVE_CONTEXT: MISMATCH' 'router propagates the actual alignment failure'

start_test 'preparation emits exact shell-safe source/installed commands without state'
for helper in .forge/hooks/lib/host-context.sh hooks/lib/host-context.sh; do
    (cd "$LINKED" && bash "$helper" prepare-context --worktree "$LINKED/nested") > "$SCRATCH/logs/prepare.out" 2> "$SCRATCH/logs/prepare.err"
    assert_equals "$?" 0 "$helper preparation succeeds for a nested target"
    expected_commands=$(printf 'bash %s probe %s\nbash %s check-process %s' "$helper" "$LINKED_HEX" "$helper" "$LINKED_HEX")
    assert_equals "$(cat "$SCRATCH/logs/prepare.out")" "$expected_commands" "$helper preparation emits two separate commands for the physical root"
    (cd "$LINKED" && bash "$helper" prepare-context --worktree "$ALIAS/nested") > "$SCRATCH/logs/prepare.out" 2> "$SCRATCH/logs/prepare.err"
    assert_equals "$?" 0 "$helper preparation accepts a symlink alias"
    assert_equals "$(cat "$SCRATCH/logs/prepare.out")" "$expected_commands" "$helper alias preparation encodes the physical root"
done

start_test 'process check is isolated from project Python module names'
(cd "$SHADOW" && bash .forge/hooks/lib/host-context.sh check-process "$SHADOW_HEX") > "$SCRATCH/logs/shadow-process.out" 2> "$SCRATCH/logs/shadow-process.err"
assert_equals "$?" 0 'process check works in a repository containing json.py'
assert_contains "$SCRATCH/logs/shadow-process.out" 'FORGE_PROCESS_CONTEXT: MATCH' 'process check uses its isolated standard library'

start_test 'process checks are independent and cannot manufacture native-hook evidence'
for helper in .forge/hooks/lib/host-context.sh hooks/lib/host-context.sh; do
    (cd "$LINKED/nested" && bash "$LINKED/$helper" check-process "$LINKED_HEX") > "$SCRATCH/logs/process.out" 2> "$SCRATCH/logs/process.err"
    assert_equals "$?" 0 "$helper process matches its expected root"
    assert_contains "$SCRATCH/logs/process.out" 'FORGE_PROCESS_CONTEXT: MATCH' 'process emits only its own context result'
    assert_not_contains "$SCRATCH/logs/process.out" 'FORGE_NATIVE_CONTEXT: MATCH' 'manual command cannot self-certify native execution'
    (cd "$PRIMARY" && bash "$LINKED/$helper" check-process "$LINKED_HEX") > "$SCRATCH/logs/process.out" 2> "$SCRATCH/logs/process.err"
    assert_equals "$?" 2 "$helper process mismatch is independently rejected"
    (cd "$LINKED" && bash "$LINKED/$helper" probe "$LINKED_HEX") > "$SCRATCH/logs/process.out" 2> "$SCRATCH/logs/process.err"
    assert_equals "$?" 2 "$helper actually executed native probe fails"
    assert_contains "$SCRATCH/logs/process.err" 'UNVERIFIED' 'actually executed probe reports missing native-hook observation'
    assert_not_contains "$SCRATCH/logs/process.err" 'FORGE_NATIVE_CONTEXT: MATCH' 'direct probe execution cannot claim native MATCH'
done

start_test 'compatibility hook remains a no-op and repeated probes leave all fixture data unchanged'
for host in claude codex; do
    (cd "$LINKED" && printf '{"cwd":"%s","session_id":"fixture-only"}' "$LINKED" | bash .forge/hooks/lib/host-context.sh hook --host "$host") > "$SCRATCH/logs/compat.out" 2> "$SCRATCH/logs/compat.err"
    assert_equals "$?" 0 "$host compatibility hook remains successful"
    assert_equals "$(cat "$SCRATCH/logs/compat.out")" '' "$host compatibility hook remains silent"
done
assert_equals "$(snapshot)" "$BEFORE" 'state, memory, receipts, fingerprints, indexes, refs and files remain byte-identical'

start_test 'PowerShell context parity when its portable runtime is available'
if [ "${FORGE_CONTEXT_SKIP_PWSH:-0}" = 1 ]; then
    skip_test 'PowerShell context parity explicitly deferred for concurrent development'
elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -File "$REPO_ROOT/tests/template/test-worktree-context.ps1" > "$SCRATCH/logs/powershell.log" 2>&1
    parity_rc=$?
    if [ "$parity_rc" -eq 0 ]; then
        pass 'PowerShell context behavioral suite passes'
    else
        cat "$SCRATCH/logs/powershell.log" >&2
        fail "PowerShell context behavioral suite failed (exit $parity_rc)"
    fi
else
    skip_test 'PowerShell context parity requires pwsh; native Windows remains separately qualified'
fi
report 'Worktree context'
