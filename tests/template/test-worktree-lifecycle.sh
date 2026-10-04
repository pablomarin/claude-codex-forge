#!/usr/bin/env bash
# Executable v6 linked-worktree seed/fold contract.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

HELPER="$REPO_ROOT/hooks/lib/worktree-lifecycle.sh"

write_state() {
    local path="$1" command="$2" done="$3" now="$4" next="$5"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
<!-- forge:state-schema v6 -->
## Identity
| Field | Value |
| Worktree root | fixture |

## Workflow
| Field | Value |
| Command | $command |
| Phase | fixture |
| Next step | fixture |

## /goal session
none

## PR authorization
none

## State

### Done (recent 2-3 only)

- $done

### Now
${now:+
- $now}

### Next

- $next

### Deferred

- deferred-primary

## Open Questions

- question-primary

## Blockers

- blocker-primary

## Update Rules
fixture rules
EOF
}

start_test "v6 helper creates exact fix branch and bootstraps private harness"
BASE=$(scratch_dir lifecycle)
PRIMARY="$BASE/project"
TARGET="$PRIMARY/.worktrees/bug-one"
mkdir -p "$PRIMARY"
(
    cd "$PRIMARY" || exit 1
    git init -q --initial-branch=main
    git config user.email t@t
    git config user.name t
    printf 'tracked\n' > app.txt
    printf 'tracked-owned\n' > owned.txt
    git add app.txt owned.txt
    git commit -q -m base
)
BASE_SHA=$(git -C "$PRIMARY" rev-parse HEAD)
printf 'primary-local-change\n' > "$PRIMARY/owned.txt"
mkdir -p "$PRIMARY/.forge/hooks/lib" "$PRIMARY/.forge/local/memory" \
    "$PRIMARY/.claude" "$PRIMARY/.codex" "$PRIMARY/docs"
printf '6\n' > "$PRIMARY/.forge/version"
cp "$REPO_ROOT/state.template.md" "$PRIMARY/.forge/state.template.md"
printf 'private policy\n' > "$PRIMARY/.forge/instructions.md"
printf 'claude settings\n' > "$PRIMARY/.claude/settings.json"
printf 'codex config\n' > "$PRIMARY/.codex/config.toml"
printf 'codex hooks stay primary\n' > "$PRIMARY/.codex/hooks.json"
printf 'shared project context\n' > "$PRIMARY/docs/agent-context.md"
printf 'must-not-copy\n' > "$PRIMARY/.forge/local/memory/private.md"
write_state "$PRIMARY/.forge/local/state.md" "/fix-bug prior" "done-primary" "now-primary" "next-primary"
mkdir -p "$PRIMARY/.git/hooks"
cat > "$PRIMARY/.git/hooks/post-checkout" <<EOF
#!/usr/bin/env bash
printf 'post-checkout-ran\n' >> "$BASE/post-checkout.log"
exit 1
EOF
chmod +x "$PRIMARY/.git/hooks/post-checkout"
cat > "$PRIMARY/.forge/installed-files.tsv" <<'EOF'
.forge/state.template.md	fixture	v6
.forge/instructions.md	fixture	v6
docs/agent-context.md	fixture	v6
owned.txt	fixture	v6
EOF
printf '%s\n' '.forge/' '.claude/' '.codex/' 'docs/agent-context.md' '.worktrees/' >> "$PRIMARY/.git/info/exclude"

if [ -x "$HELPER" ]; then
    (cd "$PRIMARY" && "$HELPER" create --kind fix --name bug-one --base HEAD) \
        > "$BASE/create.out" 2> "$BASE/create.err"
    CREATE_RC=$?
else
    CREATE_RC=127
fi
assert_equals "$CREATE_RC" "0" "create succeeds"
assert_file_missing "$BASE/post-checkout.log" "canonical worktree creation does not execute post-checkout hooks"
assert_equals "$(git -C "$TARGET" branch --show-current 2>/dev/null || true)" "fix/bug-one" \
    "fix workflow uses fix/<slug>, not a host prefix"
assert_file_exists "$TARGET/.forge/instructions.md" "ignored canonical harness is copied"
assert_file_exists "$TARGET/.forge/version" "generated v6 stamp is copied"
assert_file_exists "$TARGET/.forge/installed-files.tsv" "generated installation ledger is copied"
assert_file_exists "$TARGET/.claude/settings.json" "merge-owned Claude host adapter is copied outside the canonical ledger"
assert_file_exists "$TARGET/.codex/config.toml" "merge-owned Codex config is copied outside the canonical ledger"
assert_file_exists "$TARGET/.codex/hooks.json" "Codex hook validation mirror is copied outside the canonical ledger"
assert_file_exists "$TARGET/docs/agent-context.md" "ignored shared project context is copied"
assert_equals "$(cat "$TARGET/owned.txt")" "tracked-owned" "bootstrap never overwrites an existing worktree file"
assert_file_missing "$TARGET/.forge/local/memory/private.md" "volatile local memory is never copied"
assert_file_exists "$TARGET/.forge/local/.state-seed-snapshot.md" "exact narrative baseline is recorded"
assert_contains "$TARGET/.forge/local/state.md" 'done-primary' "foldable Done narrative is seeded"
assert_contains "$TARGET/.forge/local/state.md" 'next-primary' "foldable Next narrative is seeded"
assert_not_contains "$TARGET/.forge/local/state.md" 'now-primary' "volatile Now is cleared when seeding"
assert_not_contains "$TARGET/.forge/local/state.md" '/fix-bug prior' "workflow authority is not copied"
TARGET_PHYSICAL=$(cd "$TARGET" && pwd -P)
assert_contains "$TARGET/.forge/local/state.md" "| Worktree root | $TARGET_PHYSICAL |" \
    "create binds the exact worktree path in state"
assert_contains "$TARGET/.forge/local/state.md" "| Workflow base SHA | $BASE_SHA |" \
    "create freezes the resolved base SHA in state"

start_test "v6 helper adopts a clean host-native worktree onto the exact feature branch"
NATIVE_BASE=$(scratch_dir lifecycle-native)
NATIVE_PRIMARY="$NATIVE_BASE/project"
NATIVE_TARGET="$NATIVE_PRIMARY/.claude/worktrees/native-feature"
mkdir -p "$NATIVE_PRIMARY"
(
    cd "$NATIVE_PRIMARY" || exit 1
    git init -q --initial-branch=main
    git config user.email t@t
    git config user.name t
    printf 'tracked\n' > app.txt
    git add app.txt
    git commit -q -m base
)
NATIVE_BASE_SHA=$(git -C "$NATIVE_PRIMARY" rev-parse HEAD)
mkdir -p "$NATIVE_PRIMARY/.forge/local"
cp "$REPO_ROOT/state.template.md" "$NATIVE_PRIMARY/.forge/state.template.md"
printf '6.4.0\n' > "$NATIVE_PRIMARY/.forge/version"
printf 'private policy\n' > "$NATIVE_PRIMARY/.forge/instructions.md"
printf '.forge/state.template.md\tfixture\tv6\n.forge/instructions.md\tfixture\tv6\n' \
    > "$NATIVE_PRIMARY/.forge/installed-files.tsv"
write_state "$NATIVE_PRIMARY/.forge/local/state.md" "none" "native-done" "native-now" "native-next"
printf '%s\n' '.forge/' '.claude/' >> "$NATIVE_PRIMARY/.git/info/exclude"
git -C "$NATIVE_PRIMARY" worktree add -q -b claude/native-feature "$NATIVE_TARGET" "$NATIVE_BASE_SHA"
git -C "$NATIVE_PRIMARY" config branch.claude/native-feature.description 'host-native metadata'
NATIVE_CONFIG_HASH=$(shasum -a 256 "$NATIVE_PRIMARY/.git/config" | awk '{print $1}')
if "$HELPER" adopt --kind feat --name native-feature --base main --worktree "$NATIVE_TARGET" \
    > "$NATIVE_BASE/adopt.out" 2> "$NATIVE_BASE/adopt.err"; then
    NATIVE_ADOPT_RC=0
else
    NATIVE_ADOPT_RC=$?
fi
assert_equals "$NATIVE_ADOPT_RC" "0" "clean native worktree adoption succeeds"
assert_equals "$(git -C "$NATIVE_TARGET" branch --show-current 2>/dev/null || true)" "feat/native-feature" \
    "native host prefix is normalized to feat/<slug>"
assert_file_exists "$NATIVE_TARGET/.forge/local/.state-seed-snapshot.md" \
    "native adoption seeds the fold baseline"
assert_contains "$NATIVE_TARGET/.forge/local/state.md" "| Workflow base SHA | $NATIVE_BASE_SHA |" \
    "native adoption freezes the verified base SHA"
assert_contains "$NATIVE_BASE/adopt.out" "ADOPT_OK: branch=feat/native-feature" \
    "native adoption reports the canonical branch"
assert_equals "$(shasum -a 256 "$NATIVE_PRIMARY/.git/config" | awk '{print $1}')" "$NATIVE_CONFIG_HASH" \
    "native adoption never writes shared Git config"

start_test "native adoption rejects dirty work without renaming its branch"
DIRTY_TARGET="$NATIVE_PRIMARY/.claude/worktrees/dirty-feature"
git -C "$NATIVE_PRIMARY" worktree add -q -b claude/dirty-feature "$DIRTY_TARGET" "$NATIVE_BASE_SHA"
printf 'dirty\n' >> "$DIRTY_TARGET/app.txt"
if "$HELPER" adopt --kind feat --name dirty-feature --base main --worktree "$DIRTY_TARGET" \
    > "$NATIVE_BASE/dirty.out" 2> "$NATIVE_BASE/dirty.err"; then
    DIRTY_ADOPT_RC=0
else
    DIRTY_ADOPT_RC=$?
fi
if [ "$DIRTY_ADOPT_RC" -ne 0 ]; then pass "dirty native adoption exits nonzero"; else fail "dirty native adoption must exit nonzero"; fi
assert_contains "$NATIVE_BASE/dirty.err" "ADOPT_BLOCKED: native worktree must be clean" \
    "dirty native adoption explains the safe stop"
assert_equals "$(git -C "$DIRTY_TARGET" branch --show-current 2>/dev/null || true)" "claude/dirty-feature" \
    "dirty native branch is not renamed"

start_test "Forge source checkout seeds from the tracked root state template"
SOURCE_BASE=$(scratch_dir lifecycle-source)
SOURCE_PRIMARY="$SOURCE_BASE/project"
SOURCE_TARGET="$SOURCE_PRIMARY/.worktrees/source-bug"
mkdir -p "$SOURCE_PRIMARY/manifests"
cp "$REPO_ROOT/state.template.md" "$SOURCE_PRIMARY/state.template.md"
printf 'state.template.md\ttracked\tv6\n' > "$SOURCE_PRIMARY/manifests/managed-v6.tsv"
printf 'source\n' > "$SOURCE_PRIMARY/app.txt"
(
    cd "$SOURCE_PRIMARY" || exit 1
    git init -q --initial-branch=main
    git config user.email t@t
    git config user.name t
    git add app.txt state.template.md manifests/managed-v6.tsv
    git commit -q -m base
)
mkdir -p "$SOURCE_PRIMARY/.forge/local"
printf '%s\n' '.forge/local/' '.worktrees/' >> "$SOURCE_PRIMARY/.git/info/exclude"
write_state "$SOURCE_PRIMARY/.forge/local/state.md" "/fix-bug prior" "source-done" "source-now" "source-next"
if (cd "$SOURCE_PRIMARY" && "$HELPER" create --kind fix --name source-bug --base HEAD) \
    > "$SOURCE_BASE/create.out" 2> "$SOURCE_BASE/create.err"; then
    SOURCE_CREATE_RC=0
else
    SOURCE_CREATE_RC=$?
fi
assert_equals "$SOURCE_CREATE_RC" "0" "source-mode create succeeds without an installed-files ledger"
assert_file_exists "$SOURCE_TARGET/.forge/local/state.md" "source-mode state is seeded from state.template.md"
assert_contains "$SOURCE_TARGET/.forge/local/state.md" 'source-done' "source-mode seed carries continuity narrative"

start_test "failed create removes its partial worktree and branch"
BROKEN_BASE=$(scratch_dir lifecycle-broken)
BROKEN_PRIMARY="$BROKEN_BASE/project"
BROKEN_TARGET="$BROKEN_PRIMARY/.worktrees/broken"
mkdir -p "$BROKEN_PRIMARY"
(
    cd "$BROKEN_PRIMARY" || exit 1
    git init -q --initial-branch=main
    git config user.email t@t
    git config user.name t
    printf 'tracked\n' > app.txt
    git add app.txt
    git commit -q -m base
)
if (cd "$BROKEN_PRIMARY" && "$HELPER" create --kind fix --name broken --base HEAD) \
    > "$BROKEN_BASE/create.out" 2> "$BROKEN_BASE/create.err"; then
    BROKEN_CREATE_RC=0
else
    BROKEN_CREATE_RC=$?
fi
if [ "$BROKEN_CREATE_RC" -ne 0 ]; then pass "invalid source create exits nonzero"; else fail "invalid source create must exit nonzero"; fi
assert_file_missing "$BROKEN_TARGET" "failed create removes the partial linked worktree"
if git -C "$BROKEN_PRIMARY" show-ref --verify --quiet refs/heads/fix/broken; then
    fail "failed create must remove its partial branch"
else
    pass "failed create removes the partial branch"
fi

start_test "fold refuses to drop work still listed under the worktree Now"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-worktree" "active-worktree" "next-worktree"
PRIMARY_BEFORE=$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')
if "$HELPER" fold --worktree "$TARGET" > "$BASE/fold-now.out" 2> "$BASE/fold-now.err"; then
    FOLD_NOW_RC=0
else
    FOLD_NOW_RC=$?
fi
if [ "$FOLD_NOW_RC" -ne 0 ]; then pass "non-empty worktree Now exits nonzero"; else fail "non-empty worktree Now must exit nonzero"; fi
assert_contains "$BASE/fold-now.err" 'FOLD_SAFE_STOP: worktree ### Now still lists work' \
    "non-empty worktree Now explains how to record the status first"
assert_equals "$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$PRIMARY_BEFORE" \
    "non-empty worktree Now leaves primary bytes unchanged"

start_test "fold refuses a case-variant Now heading instead of dropping its work"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-worktree" "unfinished-work" "next-worktree"
sed 's/^### Now$/### NOW/' "$TARGET/.forge/local/state.md" > "$BASE/case-now.md"
mv "$BASE/case-now.md" "$TARGET/.forge/local/state.md"
if "$HELPER" fold --worktree "$TARGET" > "$BASE/case-now.out" 2> "$BASE/case-now.err"; then
    CASE_NOW_RC=0
else
    CASE_NOW_RC=$?
fi
if [ "$CASE_NOW_RC" -ne 0 ]; then pass "case-variant Now heading exits nonzero"; else fail "case-variant Now heading must exit nonzero"; fi
assert_equals "$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$PRIMARY_BEFORE" \
    "case-variant Now heading leaves primary bytes unchanged"

start_test "fold replaces narrative when primary still matches the seed"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-worktree" "" "next-worktree"
if [ -x "$HELPER" ]; then
    "$HELPER" fold --worktree "$TARGET" > "$BASE/fold.out" 2> "$BASE/fold.err"
    FOLD_RC=$?
else
    FOLD_RC=127
fi
assert_equals "$FOLD_RC" "0" "unchanged primary narrative folds successfully"
assert_contains "$BASE/fold.out" 'FOLD_OK: worktree=' "replace fold reports success"
assert_contains "$BASE/fold.out" 'mode=replace' "unchanged primary uses the exact replace path"
assert_contains "$PRIMARY/.forge/local/state.md" 'done-worktree' "worktree Done reaches primary"
assert_contains "$PRIMARY/.forge/local/state.md" 'next-worktree' "worktree Next reaches primary"
assert_not_contains "$PRIMARY/.forge/local/state.md" 'now-primary' "fold clears primary Now"
assert_contains "$PRIMARY/.forge/local/state.md" '| Command | /fix-bug prior |' \
    "primary workflow authority remains untouched"
REPLACED=$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')
if "$HELPER" fold --worktree "$TARGET" > "$BASE/fold-retry.out" 2> "$BASE/fold-retry.err"; then
    REPLACE_RETRY_RC=0
else
    REPLACE_RETRY_RC=$?
fi
assert_equals "$REPLACE_RETRY_RC" "0" "retrying a replace fold succeeds"
assert_contains "$BASE/fold-retry.out" 'mode=unchanged' "retrying a replace fold reports nothing to fold"
assert_equals "$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$REPLACED" \
    "retrying a replace fold keeps primary bytes"

start_test "fold rejects a complete narrative whose state sections are out of order"
sed -n '/^## State$/,/^## Update Rules$/{ /^## Update Rules$/q; p; }' \
    "$PRIMARY/.forge/local/state.md" > "$TARGET/.forge/local/.state-seed-snapshot.md"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-malformed" "now-malformed" "next-malformed"
sed -e 's/^### Now$/### ORDER-TEMP/' \
    -e 's/^### Next$/### Now/' \
    -e 's/^### ORDER-TEMP$/### Next/' \
    "$TARGET/.forge/local/state.md" > "$BASE/out-of-order-state.md"
mv "$BASE/out-of-order-state.md" "$TARGET/.forge/local/state.md"
PRIMARY_BEFORE=$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')
if "$HELPER" fold --worktree "$TARGET" > "$BASE/out-of-order.out" 2> "$BASE/out-of-order.err"; then
    OUT_OF_ORDER_RC=0
else
    OUT_OF_ORDER_RC=$?
fi
if [ "$OUT_OF_ORDER_RC" -ne 0 ]; then pass "out-of-order narrative exits nonzero"; else fail "out-of-order narrative must exit nonzero"; fi
assert_contains "$BASE/out-of-order.err" 'FOLD_SAFE_STOP' "out-of-order narrative is explained as unsafe"
assert_equals "$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$PRIMARY_BEFORE" \
    "out-of-order narrative leaves primary bytes unchanged"

start_test "fold merges worktree changes into a primary narrative that changed after seed"
# The snapshot now records done-worktree/next-worktree. Primary changes independently
# while the worktree replaces its Done entry; both changes must survive.
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-second" "" "next-worktree"
write_state "$PRIMARY/.forge/local/state.md" "/fix-bug prior" "independent-main" "main-active" "next-main-only"
if "$HELPER" fold --worktree "$TARGET" > "$BASE/diverged.out" 2> "$BASE/diverged.err"; then
    DIVERGED_RC=0
else
    DIVERGED_RC=$?
fi
assert_equals "$DIVERGED_RC" "0" "diverged primary narrative folds by merge"
assert_contains "$BASE/diverged.out" 'mode=merge' "diverged primary uses the three-way merge path"
assert_contains "$PRIMARY/.forge/local/state.md" 'done-second' "worktree Done edit reaches primary"
assert_contains "$PRIMARY/.forge/local/state.md" 'independent-main' "independent primary Done edit survives"
assert_contains "$PRIMARY/.forge/local/state.md" 'next-main-only' "independent primary Next edit survives"
assert_not_contains "$PRIMARY/.forge/local/state.md" 'done-worktree' "line removed by the worktree stays removed"
assert_contains "$PRIMARY/.forge/local/state.md" '| Command | /fix-bug prior |' \
    "merge leaves primary workflow authority untouched"

start_test "fold keeps a primary-only section after the narrative"
awk '$0 == "## Update Rules" { print "## Notes"; print ""; print "- keep my notes"; print "" } { print }' \
    "$PRIMARY/.forge/local/state.md" > "$BASE/notes-state.md"
mv "$BASE/notes-state.md" "$PRIMARY/.forge/local/state.md"
if "$HELPER" fold --worktree "$TARGET" > "$BASE/notes.out" 2> "$BASE/notes.err"; then
    NOTES_RC=0
else
    NOTES_RC=$?
fi
assert_equals "$NOTES_RC" "0" "fold succeeds beside a primary-only section"
assert_contains "$PRIMARY/.forge/local/state.md" '- keep my notes' "primary-only section after Blockers survives the fold"
assert_contains "$PRIMARY/.forge/local/state.md" 'fixture rules' "primary Update Rules survive the fold"

start_test "parallel worktrees each fold their finished status into primary state"
PAR_BASE=$(scratch_dir lifecycle-parallel)
PAR_PRIMARY="$PAR_BASE/project"
mkdir -p "$PAR_PRIMARY"
(
    cd "$PAR_PRIMARY" || exit 1
    git init -q --initial-branch=main
    git config user.email t@t
    git config user.name t
    printf 'tracked\n' > app.txt
    git add app.txt
    git commit -q -m base
)
mkdir -p "$PAR_PRIMARY/.forge/local"
cp "$REPO_ROOT/state.template.md" "$PAR_PRIMARY/.forge/state.template.md"
printf '6\n' > "$PAR_PRIMARY/.forge/version"
printf '.forge/state.template.md\tfixture\tv6\n' > "$PAR_PRIMARY/.forge/installed-files.tsv"
printf '%s\n' '.forge/' '.worktrees/' >> "$PAR_PRIMARY/.git/info/exclude"
awk -v queued="- (what's queued)" '
    $0 == "- (your most recent completed work)" { print "- shipped login"; next }
    $0 == queued { print "- build auth"; print "- build billing"; print "- polish docs"; next }
    $0 == "- (questions needing resolution)" { print "- which auth provider?"; print "- billing currency?"; next }
    { print }
' "$REPO_ROOT/state.template.md" > "$PAR_PRIMARY/.forge/local/state.md"
(cd "$PAR_PRIMARY" && "$HELPER" create --kind feat --name auth --base HEAD) > /dev/null 2>&1
(cd "$PAR_PRIMARY" && "$HELPER" create --kind feat --name billing --base HEAD) > /dev/null 2>&1
AUTH_STATE="$PAR_PRIMARY/.worktrees/auth/.forge/local/state.md"
BILLING_STATE="$PAR_PRIMARY/.worktrees/billing/.forge/local/state.md"
assert_file_exists "$AUTH_STATE" "first parallel worktree is seeded"
assert_file_exists "$BILLING_STATE" "second parallel worktree is seeded"
rewrite_state() {
    awk "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
# Main records unrelated progress (for example a quick fix) after both seeds.
rewrite_state "$PAR_PRIMARY/.forge/local/state.md" \
    '$0 == "- polish docs" { print; print "  - include hotfix notes"; print "- main hotfix follow-up"; next } { print }'
# auth finishes: records Done, drops its Next item, resolves a question, parks a follow-up.
rewrite_state "$AUTH_STATE" '
    $0 == "- shipped login" { print "- shipped auth (PR 12)" }
    $0 == "- build auth" || $0 == "- which auth provider?" { next }
    $0 == "- (parked items with reason)" { print "- auth: rotate signing keys later"; next }
    $0 == "### Now" { print; getline; print; print "- finishing auth"; next }
    { print }'
# billing finishes: records Done, drops its Next item, queues a follow-up after polish docs.
rewrite_state "$BILLING_STATE" '
    $0 == "- shipped login" { print "- shipped billing (PR 13)" }
    $0 == "- build billing" { next }
    $0 == "- polish docs" { print; print "- billing: add invoices"; next }
    { print }'

PAR_BEFORE=$(shasum -a 256 "$PAR_PRIMARY/.forge/local/state.md" | awk '{print $1}')
if "$HELPER" fold --worktree "$PAR_PRIMARY/.worktrees/auth" > "$PAR_BASE/auth-now.out" 2> "$PAR_BASE/auth-now.err"; then
    pass_rc=0
else
    pass_rc=$?
fi
if [ "$pass_rc" -ne 0 ]; then pass "auth fold stops while Now still lists work"; else fail "auth fold must stop while Now still lists work"; fi
assert_equals "$(shasum -a 256 "$PAR_PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$PAR_BEFORE" \
    "stopped fold leaves primary bytes unchanged"
rewrite_state "$AUTH_STATE" '$0 == "- finishing auth" { next } { print }'

if "$HELPER" fold --worktree "$PAR_PRIMARY/.worktrees/auth" > "$PAR_BASE/auth.out" 2> "$PAR_BASE/auth.err"; then
    AUTH_RC=0
else
    AUTH_RC=$?
fi
assert_equals "$AUTH_RC" "0" "first parallel fold succeeds after main changed"
assert_contains "$PAR_BASE/auth.out" 'mode=merge' "first parallel fold merges around the main edit"
AUTH_FOLDED=$(shasum -a 256 "$PAR_PRIMARY/.forge/local/state.md" | awk '{print $1}')
if "$HELPER" fold --worktree "$PAR_PRIMARY/.worktrees/auth" > "$PAR_BASE/auth-retry.out" 2> "$PAR_BASE/auth-retry.err"; then
    RETRY_RC=0
else
    RETRY_RC=$?
fi
assert_equals "$RETRY_RC" "0" "retrying a completed fold succeeds"
assert_equals "$(shasum -a 256 "$PAR_PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$AUTH_FOLDED" \
    "retrying a completed fold is idempotent"

if "$HELPER" fold --worktree "$PAR_PRIMARY/.worktrees/billing" > "$PAR_BASE/billing.out" 2> "$PAR_BASE/billing.err"; then
    BILLING_RC=0
else
    BILLING_RC=$?
fi
assert_equals "$BILLING_RC" "0" "second parallel fold succeeds after its sibling folded"
assert_contains "$PAR_BASE/billing.out" 'mode=merge' "second parallel fold merges with its sibling"
cat > "$PAR_BASE/expected-narrative.md" <<'EOF'
## State

### Done (recent 2-3 only)

- shipped billing (PR 13)
- shipped auth (PR 12)
- shipped login

### Now

### Next

- polish docs
  - include hotfix notes
- billing: add invoices
- main hotfix follow-up

### Deferred

- auth: rotate signing keys later

---

## Open Questions

- billing currency?

## Blockers

- (anything blocking forward progress)

---

EOF
sed -n '/^## State$/,/^## Update Rules$/{ /^## Update Rules$/q; p; }' \
    "$PAR_PRIMARY/.forge/local/state.md" > "$PAR_BASE/actual-narrative.md"
if cmp -s "$PAR_BASE/expected-narrative.md" "$PAR_BASE/actual-narrative.md"; then
    pass "primary narrative holds both finished statuses and the main edit, in order"
else
    fail "primary narrative must hold both finished statuses and the main edit, in order"
    diff "$PAR_BASE/expected-narrative.md" "$PAR_BASE/actual-narrative.md" | head -20
fi
assert_contains "$PAR_PRIMARY/.forge/local/state.md" '| Command   | none  |' \
    "parallel folds leave primary workflow control untouched"

start_test "refolding after a post-fold worktree edit applies only that edit"
rewrite_state "$AUTH_STATE" '$0 == "- shipped auth (PR 12)" { print "- shipped auth (PR 12, verified)"; next } { print }'
if "$HELPER" fold --worktree "$PAR_PRIMARY/.worktrees/auth" > "$PAR_BASE/auth-edit.out" 2> "$PAR_BASE/auth-edit.err"; then
    EDIT_RC=0
else
    EDIT_RC=$?
fi
assert_equals "$EDIT_RC" "0" "refold after a worktree edit succeeds"
assert_contains "$PAR_PRIMARY/.forge/local/state.md" '- shipped auth (PR 12, verified)' "post-fold edit reaches primary"
assert_not_contains "$PAR_PRIMARY/.forge/local/state.md" '- shipped auth (PR 12)' "post-fold edit replaces the earlier folded line"
assert_contains "$PAR_PRIMARY/.forge/local/state.md" '- shipped billing (PR 13)' "post-fold edit keeps the sibling fold"

report "test-worktree-lifecycle.sh"
