#!/usr/bin/env bash
# Real installed CLI fixtures. Main-host identities are synthetic preservation
# inputs; authenticated reviewer/opinion/council qualification is a separate seam.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
TMP=$(mktemp -d "${TMPDIR:-/tmp}/forge-worktrees.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
_SCRATCH_DIRS+=("$TMP")
RELEASE=$(sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$REPO_ROOT/docs/CHANGELOG.md" | head -1)
REAL_GIT=$(command -v git)
# Deterministic, unauthenticated host probes keep setup verification independent
# of the developer's native installation. Final host qualification is separate.
mkdir -p "$TMP/fixture-bin"
for host in claude codex; do
    printf '#!/bin/sh\nexit 127\n' > "$TMP/fixture-bin/$host"
    chmod +x "$TMP/fixture-bin/$host"
done
export PATH="$TMP/fixture-bin:$PATH"

fixture() {
    PRIMARY="$1/primary project"; LINK="$1/linked café"; SIBLING="$1/other checkout"
    mkdir -p "$PRIMARY"
    git -C "$PRIMARY" init -q
    git -C "$PRIMARY" config user.name Fixture
    git -C "$PRIMARY" config user.email fixture@example.invalid
    printf 'application\n' > "$PRIMARY/app.txt"
    printf '{"name":"fixture"}\n' > "$PRIMARY/package.json"
    git -C "$PRIMARY" add .
    git -C "$PRIMARY" commit -qm seed
    git -C "$PRIMARY" worktree add -qb fixture-link "$LINK"
    git -C "$PRIMARY" worktree add -qb fixture-sibling "$SIBLING"
}
setup_at() { local root="$1" log="$2"; shift 2; (cd "$root" && bash "$REPO_ROOT/setup.sh" "$@") > "$log" 2>&1; }
snapshot() {
    python3 - "$1" <<'PY'
import hashlib, os, sys
h=hashlib.sha256()
for root, dirs, files in os.walk(sys.argv[1]):
    dirs.sort()
    for name in sorted(files):
        p=os.path.join(root,name)
        h.update(os.path.relpath(p,sys.argv[1]).encode());h.update(open(p,'rb').read())
print(h.hexdigest())
PY
}
canonical() {
    python3 - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys
s,t=map(Path,sys.argv[1:])
for line in (s/'manifests/managed-v6.tsv').read_text().splitlines():
    if not line or line.startswith('#'): continue
    kind,src,dest,platform,*_=line.split('\t')
    if kind=='canonical' and platform in ('all','unix'):
        assert (t/dest).read_bytes()==(s/src).read_bytes(), dest
PY
}

for main in claude codex; do
    start_test "$main-main fixture: linked invocation installs every checkout primary first"
    fixture "$TMP/$main"
    roots=("$PRIMARY" "$LINK" "$SIBLING")
    for root in "${roots[@]}"; do
        mkdir -p "$root/.forge/local/memory" "$root/.forge/memory" "$root/.claude" "$root/.codex"
        cp "$REPO_ROOT/state.template.md" "$root/.forge/local/state.md"
        printf '\nhost=%s\nactive workflow bytes\n' "$main" >> "$root/.forge/local/state.md"
        printf 'local memory\n' > "$root/.forge/local/memory/notes.md"
        printf 'durable memory\n' > "$root/.forge/memory/notes.md"
        printf 'user instructions\n' > "$root/AGENTS.md"
        printf 'dirty application\n' >> "$root/app.txt"
    done
    head_before=$(git -C "$PRIMARY" rev-parse HEAD)
    branches_before=$(git -C "$PRIMARY" for-each-ref --format='%(refname) %(objectname)' refs/heads)
    setup_at "$LINK" "$TMP/$main-install.log" -p 'Shared café project' -t typescript --with-playwright
    assert_equals "$?" 0 "default mode succeeds from linked checkout"
    first_result=$(awk '/WORKTREE_RESULT/{print; exit}' "$TMP/$main-install.log")
    [[ "$first_result" == *"$PRIMARY"* ]] && pass "primary result comes first" || fail "primary result comes first"
    for root in "${roots[@]}"; do
        assert_file_exists "$root/.forge/version" "installed: $root"
        assert_equals "$(cat "$root/.forge/version" 2>/dev/null)" "$RELEASE" "exact source release"
        canonical "$root" && pass "all canonical bytes match source" || fail "canonical bytes match source"
        assert_contains "$root/.forge/local/state.md" "host=$main" "main-host state preserved"
        assert_contains "$root/.forge/local/memory/notes.md" 'local memory' "local memory preserved"
        assert_contains "$root/.forge/memory/notes.md" 'durable memory' "durable memory preserved"
        assert_contains "$root/AGENTS.md" 'user instructions' "project instructions preserved"
        assert_contains "$root/docs/CHANGELOG.md" 'Shared café project' "public project argument forwarded"
        assert_file_exists "$root/playwright.config.ts" "public Playwright and tech options forwarded"
        assert_contains "$root/app.txt" 'dirty application' "app edit preserved"
    done
    assert_equals "$(git -C "$PRIMARY" for-each-ref --format='%(refname) %(objectname)' refs/heads)" "$branches_before" "branches and HEADs preserved"
    assert_equals "$(git -C "$PRIMARY" rev-parse HEAD)" "$head_before" "primary HEAD preserved"
    for root in "${roots[@]}"; do
        printf '{"userEntry": "keep"}\n' > "$root/.claude/settings.json"
        printf '[profiles.fixture]\nmodel = "gpt-6-astra"\n' > "$root/.codex/config.toml"
    done
    # Canonical materialization refreshes default mode without treating it as upgrade.
    printf '// customized sibling scaffold\n' > "$SIBLING/playwright.config.ts"
    printf 'stale canonical hook\n' > "$SIBLING/.forge/hooks/session-start.sh"
    setup_at "$LINK" "$TMP/$main-default.log" -t typescript --with-playwright
    assert_equals "$?" 0 "repeated default mode succeeds"
    assert_contains "$SIBLING/playwright.config.ts" 'customized sibling scaffold' "default does not become upgrade/force"
    canonical "$SIBLING" && pass "default refreshes canonical managed hook" || fail "default canonical refresh"
    for root in "${roots[@]}"; do
        git -C "$root" add .
        git -C "$root" -c core.hooksPath=/dev/null commit -qm installed
        printf 'uncommitted app work\n' >> "$root/app.txt"
        printf 'stale canonical hook\n' > "$root/.forge/hooks/session-start.sh"
    done
    branches_before=$(git -C "$PRIMARY" for-each-ref --format='%(refname) %(objectname)' refs/heads)
    setup_at "$LINK" "$TMP/$main-upgrade.log" --upgrade
    assert_equals "$?" 0 "upgrade propagates from linked checkout"
    for root in "${roots[@]}"; do
        canonical "$root" && pass "upgrade source equivalence: $root" || fail "upgrade source equivalence"
        assert_contains "$root/app.txt" 'uncommitted app work' "upgrade preserves dirty app"
        assert_contains "$root/.claude/settings.json" 'userEntry' "Claude user config preserved"
        assert_contains "$root/.codex/config.toml" 'model = "gpt-6-astra"' "Codex user config preserved"
    done
    assert_equals "$(git -C "$PRIMARY" for-each-ref --format='%(refname) %(objectname)' refs/heads)" "$branches_before" "upgrade preserves all branches/HEADs"
    assert_file_exists "$PRIMARY/.codex/hooks.json" "primary has Codex hook registration"
    assert_contains "$TMP/$main-install.log" 'CODEX_HOOKS: MATERIALIZED primary worktree registration' "primary registration materialized first"
    assert_contains "$TMP/$main-install.log" 'CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration' "linked setup respects primary registration"
    before=$(snapshot "$TMP/$main")
    setup_at "$LINK" "$TMP/$main-preview.log" --force --dry-run
    assert_equals "$?" 0 "preview covers repository"
    assert_equals "$(snapshot "$TMP/$main")" "$before" "preview preserves every checkout and Git metadata byte"
    assert_contains "$TMP/$main-preview.log" "outcome=preview" "preview outcome reported"
    printf 'stale only primary\n' > "$PRIMARY/.forge/hooks/session-start.sh"
    before=$(snapshot "$PRIMARY")
    setup_at "$LINK" "$TMP/$main-optout.log" --upgrade --this-checkout-only
    assert_equals "$?" 0 "checkout-only upgrade succeeds"
    assert_equals "$(snapshot "$PRIMARY")" "$before" "opt-out leaves sibling byte-identical"
    setup_at "$LINK" "$TMP/$main-force.log" --force
    assert_equals "$?" 0 "force forwards to every target"
    canonical "$PRIMARY" && pass "force repairs primary" || fail "force repairs primary"
    mkdir -p "$LINK/subdir"
    before=$(snapshot "$TMP/$main")
    setup_at "$LINK/subdir" "$TMP/$main-subdir.log" --upgrade
    [[ $? -ne 0 ]] && pass "subdirectory safely fails" || fail "subdirectory safely fails"
    assert_equals "$(snapshot "$TMP/$main")" "$before" "subdirectory stops before sibling writes"
done

start_test 'independent targets continue after an ownership-blocked checkout'
fixture "$TMP/partial"
mkdir -p "$LINK/.claude/hooks"
printf 'custom user hook\n' > "$LINK/.claude/hooks/session-start.sh"
before=$(snapshot "$LINK")
setup_at "$PRIMARY" "$TMP/partial.log"
[[ $? -ne 0 ]] && pass "blocked target makes overall exit fail" || fail "overall failure required"
assert_equals "$(snapshot "$LINK")" "$before" "blocked checkout bytes preserved"
assert_file_exists "$PRIMARY/.forge/version" "primary completes before failure"
assert_file_exists "$SIBLING/.forge/version" "independent target completes after failure"
assert_contains "$TMP/partial.log" "path=$LINK release=$RELEASE outcome=blocked" "blocked target truthful outcome"
assert_contains "$TMP/partial.log" "path=$SIBLING release=$RELEASE outcome=materialized" "successful target truthful outcome"

start_test 'missing registered checkout stays a failure and never gets recreated'
rm -rf "$LINK"
setup_at "$PRIMARY" "$TMP/missing.log" --upgrade
[[ $? -ne 0 ]] && pass "missing target makes overall exit fail" || fail "missing target overall failure"
assert_file_missing "$LINK" "missing checkout not recreated"
assert_contains "$TMP/missing.log" "path=$LINK release=$RELEASE outcome=missing" "missing path identified"
assert_contains "$TMP/missing.log" "path=$SIBLING release=$RELEASE outcome=materialized" "later target still processed"

start_test 'registered directory without Git identity and unrelated replacement stay untouched'
mkdir -p "$LINK"
printf 'registered checkout sentinel\n' > "$LINK/sentinel"
before=$(snapshot "$LINK")
setup_at "$PRIMARY" "$TMP/no-git.log" --upgrade
[[ $? -ne 0 ]] && pass "unavailable checkout fails overall" || fail "unavailable checkout overall failure"
assert_equals "$(snapshot "$LINK")" "$before" "unavailable registered directory not initialized or installed"
assert_contains "$TMP/no-git.log" "path=$SIBLING release=$RELEASE outcome=materialized" "independent checkout still processes"
git -C "$LINK" init -q
before=$(snapshot "$LINK")
setup_at "$PRIMARY" "$TMP/unrelated.log" --upgrade
[[ $? -ne 0 ]] && pass "unrelated replacement fails overall" || fail "unrelated replacement overall failure"
assert_equals "$(snapshot "$LINK")" "$before" "unrelated replacement not installed"

start_test 'help, invalid options and global retirement stay outside automatic worktree flow'
before=$(snapshot "$TMP/partial")
setup_at "$PRIMARY" "$TMP/help.log" --help
assert_equals "$?" 0 "help succeeds without discovery"
assert_not_contains "$TMP/help.log" 'WORKTREE_RESULT' "help stays single-purpose"
setup_at "$PRIMARY" "$TMP/invalid.log" --unknown-option
[[ $? -ne 0 ]] && pass "invalid option rejected" || fail "invalid option rejected"
setup_at "$PRIMARY" "$TMP/global.log" --global
[[ $? -ne 0 ]] && pass "retired global option rejected" || fail "retired global option rejected"
assert_equals "$(snapshot "$TMP/partial")" "$before" "help/invalid/global options preserve repository bytes"

start_test 'Git discovery failure never silently narrows scope'
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1" == worktree && "$2" == list ]]; then echo 'simulated discovery failure' >&2; exit 23; fi
exec "$FORGE_TEST_REAL_GIT" "$@"
SHIM
chmod +x "$TMP/bin/git"
before=$(snapshot "$PRIMARY")
PATH="$TMP/bin:$PATH" FORGE_TEST_REAL_GIT="$REAL_GIT" setup_at "$PRIMARY" "$TMP/discovery.log" --upgrade
[[ $? -ne 0 ]] && pass "listing failure blocks setup" || fail "listing failure blocks setup"
assert_equals "$(snapshot "$PRIMARY")" "$before" "discovery failure changes no files"

start_test 'bare metadata entry is skipped while actual linked checkouts install'
git clone -q --bare "$PRIMARY" "$TMP/bare.git"
git -C "$TMP/bare.git" worktree add -qb bare-link "$TMP/bare-linked"
setup_at "$TMP/bare-linked" "$TMP/bare.log" --upgrade
assert_equals "$?" 0 "bare metadata entry skipped"
assert_file_exists "$TMP/bare-linked/.forge/version" "actual checkout installed"
assert_file_missing "$TMP/bare.git/.forge" "bare metadata never installed"
report 'test-setup-worktrees.sh'
