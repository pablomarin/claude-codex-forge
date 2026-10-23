#!/usr/bin/env bash
# Actual materialization contracts for UI skill discovery and the independent UI QA role.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
CASE=$(scratch_dir ui-design-install)
_SCRATCH_DIRS+=("$CASE")
PROJECT="$CASE/project"
MATERIALIZE_SOURCE="$REPO_ROOT"
mkdir -p "$PROJECT/.claude/agents" "$PROJECT/.codex/agents"
printf 'project UI QA instructions\n' > "$PROJECT/.claude/agents/ui-qa.md"
printf 'name = "ui-qa"\ndescription = "project UI QA config"\ndeveloper_instructions = "Project-owned role"\n' > "$PROJECT/.codex/agents/ui-qa.toml"
materialize() {
    PATH=/usr/bin:/bin:/usr/sbin:/sbin FORGE_ENGINE_IDENTITY_FIXTURE=1 \
        bash "$REPO_ROOT/scripts/materialize-adapters.sh" --repo-root "$MATERIALIZE_SOURCE" \
        --target "$PROJECT" --scope project --release-version 6.0.0 > "$CASE/install.log" 2>&1
}
# Independent expected value: canonical descriptions use plain or folded YAML scalars.
expected_description() {
    python3 - "$1" <<'PY'
import pathlib, re, sys
front = pathlib.Path(sys.argv[1]).read_text().split('---', 2)[1]
match = re.search(r'^description:[ \t]*(.*)(?:\n|$)', front, re.M)
value = match[1]
if re.fullmatch(r'>[-+]?', value):
    following = front[match.end():].splitlines()
    continuation = []
    for line in following:
        if not line.startswith((' ', '\t')):
            break
        continuation.append(line.strip())
    value = ' '.join(continuation)
print(value.strip())
PY
}
assert_description() {
    local path="$1" expected="$2" message="$3"
    if python3 - "$path" "$expected" <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'^description\s*[:=]\s*(".*")$', text, re.M)
assert match and json.loads(match[1]) == sys.argv[2]
PY
    then pass "$message"; else fail "$message"; fi
}
start_test 'UI skill discovery keeps the semantic canonical trigger in both hosts'
materialize
assert_equals "$?" 0 'materializer succeeds'
expected=$(expected_description "$REPO_ROOT/skills/ui-design/SKILL.template.md")
assert_description "$PROJECT/.claude/skills/ui-design/SKILL.md" "$expected" 'Claude preserves the complete UI design trigger'
assert_description "$PROJECT/.agents/skills/ui-design/SKILL.md" "$expected" 'Codex preserves the complete UI design trigger'

start_test 'UI QA is installed with browser capabilities and canonical role discovery'
assert_file_exists "$PROJECT/.forge/agents/forge-ui-qa.md" 'shared role installed'
if [ -f "$REPO_ROOT/agents/forge-ui-qa.md" ]; then
    expected=$(expected_description "$REPO_ROOT/agents/forge-ui-qa.md")
    assert_description "$PROJECT/.claude/agents/forge-ui-qa.md" "$expected" 'Claude UI QA discovery uses role description'
    assert_description "$PROJECT/.codex/agents/forge-ui-qa.toml" "$expected" 'Codex UI QA discovery uses role description'
fi
assert_contains "$PROJECT/.claude/agents/forge-ui-qa.md" 'mcp__playwright__browser_take_screenshot' 'Claude UI QA can capture visual evidence'
assert_contains "$PROJECT/.claude/agents/forge-ui-qa.md" 'mcp__playwright__browser_resize' 'Claude UI QA can inspect phone and desktop layouts'
assert_not_contains "$PROJECT/.claude/agents/forge-ui-qa.md" '  - Bash' 'Claude UI QA has no source-reading shell capability'
assert_not_contains "$PROJECT/.claude/agents/forge-ui-qa.md" 'mcp__playwright__browser_evaluate' 'Claude UI QA cannot execute arbitrary page code'
assert_contains "$PROJECT/.codex/agents/forge-ui-qa.toml" 'name = "forge-ui-qa"' 'Codex discovers the standalone named role'
assert_contains "$PROJECT/.codex/config.toml" '[mcp_servers.forge_playwright]' 'Codex UI QA inherits browser MCP from the parent'
assert_contains "$PROJECT/.codex/agents/forge-ui-qa.toml" '.forge/agents/forge-ui-qa.md' 'Codex role loads canonical contract'
assert_contains "$PROJECT/.claude/agents/ui-qa.md" 'project UI QA instructions' 'project-owned Claude UI QA survives'
assert_contains "$PROJECT/.codex/agents/ui-qa.toml" 'project UI QA config' 'project-owned Codex UI QA survives'

start_test 'repeat upgrade leaves UI adapters and project QA content stable'
for relative in .claude/skills/ui-design/SKILL.md .agents/skills/ui-design/SKILL.md .claude/agents/forge-ui-qa.md .codex/agents/forge-ui-qa.toml .codex/config.toml; do
    if [ -f "$PROJECT/$relative" ]; then printf '%s\t%s\n' "$relative" "$(hash_file "$PROJECT/$relative")"; fi
done > "$CASE/hashes.tsv"
materialize
assert_equals "$?" 0 'repeat upgrade succeeds'
while IFS=$'\t' read -r relative expected; do assert_hash_equals "$PROJECT/$relative" "$expected" "$relative is stable"; done < "$CASE/hashes.tsv"
assert_contains "$PROJECT/.claude/agents/ui-qa.md" 'project UI QA instructions' 'upgrade preserves project-owned Claude QA'
assert_contains "$PROJECT/.codex/agents/ui-qa.toml" 'project UI QA config' 'upgrade preserves project-owned Codex QA'
start_test 'folded canonical descriptions safely carry quotes, ampersands, pipes and backslashes'
MATERIALIZE_SOURCE="$CASE/source"
python3 - "$REPO_ROOT" "$MATERIALIZE_SOURCE" <<'PYFIXTURE'
import pathlib, shutil, sys
source, target = map(pathlib.Path, sys.argv[1:])
shutil.copytree(source, target, ignore=shutil.ignore_patterns('.git', '.forge', '.worktrees'))
for relative in ('skills/ui-design/SKILL.template.md', 'agents/forge-ui-qa.md'):
    path = target / relative
    text = path.read_text()
    front, body = text.split('---', 2)[1:]
    lines = front.strip().splitlines()
    keep, capture = [], False
    for line in lines:
        if line.startswith('description:'):
            capture = True
            continue
        if capture and line[:1].isspace():
            continue
        capture = False
        keep.append(line)
    keep[1:1] = ['description: >-', '  Inspect "premium" UI & movement | contrast \\ clarity.', '  Use for every user-facing interface.']
    path.write_text('---\n' + '\n'.join(keep) + '\n---' + body)
PYFIXTURE
materialize
assert_equals "$?" 0 'metadata fixture upgrade succeeds'
expected='Inspect "premium" UI & movement | contrast \ clarity. Use for every user-facing interface.'
for relative in .claude/skills/ui-design/SKILL.md .agents/skills/ui-design/SKILL.md .claude/agents/forge-ui-qa.md .codex/agents/forge-ui-qa.toml; do
    assert_description "$PROJECT/$relative" "$expected" "$relative round-trips escaped metadata"
done
report 'ui-design-install'
