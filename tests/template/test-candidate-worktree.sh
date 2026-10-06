#!/usr/bin/env bash
# Candidate identity/freeze on lifecycle-created primary and linked worktrees.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
S=$(scratch_dir candidate-worktree)
P="$S/project"; H="$S/home"
mkdir -p "$P" "$H"
P=$(cd "$P" && pwd -P)
git -C "$P" init -q --initial-branch=main
git -C "$P" config user.name ForgeTest
git -C "$P" config user.email test@example.invalid
printf 'base\n' > "$P/app.txt"
git -C "$P" add app.txt
git -C "$P" commit -qm base
(cd "$P" && PATH=/usr/bin:/bin HOME="$H" bash "$REPO_ROOT/setup.sh" -p Candidate -t fullstack) > "$S/setup.log" 2>&1
assert_equals "$?" 0 'real setup creates canonical primary state'
git -C "$P" add -A
git -C "$P" commit -qm installed
base=$(git -C "$P" rev-parse HEAD)
printf '.worktrees/\n' >> "$P/.git/info/exclude"
(cd "$P" && bash "$REPO_ROOT/hooks/lib/worktree-lifecycle.sh" create --kind fix --name candidate-linked --base main) > "$S/lifecycle.log" 2>&1
assert_equals "$?" 0 'sanctioned lifecycle creates linked state'
L=$(cd "$P/.worktrees/candidate-linked" && pwd -P)
git -C "$P" checkout -qb fix/candidate-primary
case "$(git -C "$P" rev-parse --git-common-dir)" in .git) pass 'primary Git common directory is relative' ;; *) fail 'expected primary relative Git common directory' ;; esac
case "$(git -C "$L" rev-parse --git-common-dir)" in /*) pass 'linked Git common directory is absolute' ;; *) fail 'expected linked absolute Git common directory' ;; esac
for worktree in "$P" "$L"; do
    printf 'staged candidate\n' > "$worktree/app.txt"
    git -C "$worktree" add app.txt
done
kv() { sed -n "s/^$2=//p" "$1"; }
for main in claude codex; do
    primary_identity= linked_identity=
    for worktree in "$P" "$L"; do
        task=candidate-primary; [ "$worktree" = "$P" ] || task=candidate-linked
        before=$(hash_file "$P/.forge/local/state.md")
        (cd "$worktree" && bash "$REPO_ROOT/hooks/lib/workflow-state.sh" activate --host "$main" --workflow fix-bug --task "$task" --base-ref main --phase implementation --next-step verify) > "$S/activate.log" 2>&1
        assert_equals "$?" 0 "$main activates $task through canonical helper"
        if [ "$worktree" = "$L" ]; then assert_hash_equals "$P/.forge/local/state.md" "$before" "$main linked activation leaves primary state unchanged"; fi
        before=$(hash_file "$P/.forge/local/state.md")
        identity="$worktree/.forge/local/$main.identity"; freeze="$worktree/.forge/local/$main.candidate"
        (cd "$worktree" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" identity --artifact git:working-tree --workflow-base-ref main --workflow-base-sha "$base" --output "$identity") > "$S/identity.log" 2>&1
        assert_equals "$?" 0 "$main $task identity succeeds"
        (cd "$worktree" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" freeze --artifact git:working-tree --workflow-base-ref main --workflow-base-sha "$base" --output "$freeze") > "$S/freeze.log" 2>&1
        assert_equals "$?" 0 "$main $task freeze succeeds"
        assert_equals "$(kv "$identity" candidate_id)" "$(kv "$freeze" candidate_id)" "$main $task identity/freeze certify the same candidate"
        assert_equals "$(kv "$freeze" candidate_state)" staged-clean "$main $task freeze verifies staged-clean content"
        assert_hash_equals "$P/.forge/local/state.md" "$before" "$main candidate capture leaves primary state unchanged"
        if [ "$worktree" = "$P" ]; then primary_identity=$(kv "$freeze" worktree_identity); else linked_identity=$(kv "$freeze" worktree_identity); fi
    done
    if [ -n "$primary_identity" ] && [ -n "$linked_identity" ] && [ "$primary_identity" != "$linked_identity" ]; then pass "$main primary and linked candidate identities are distinct"; else fail "$main worktree identities must differ"; fi
done
cp "$L/.forge/local/state.md" "$S/linked-state.md"
cp "$P/.forge/local/state.md" "$L/.forge/local/state.md"
(cd "$L" && bash "$REPO_ROOT/hooks/lib/candidate-fingerprint.sh" identity --artifact git:working-tree --workflow-base-ref main --workflow-base-sha "$base" --output "$L/.forge/local/foreign.identity") > "$S/foreign.log" 2>&1
if [ "$?" -ne 0 ]; then pass 'linked candidate rejects primary checkout state'; else fail 'foreign primary state certified linked candidate'; fi
assert_contains "$S/foreign.log" 'canonical state belongs to another worktree' 'foreign-state rejection names identity boundary'
cp "$S/linked-state.md" "$L/.forge/local/state.md"
report 'test-candidate-worktree.sh'
