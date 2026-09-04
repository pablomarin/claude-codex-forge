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

- $now

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

start_test "fold replaces narrative only when primary still matches the seed"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-worktree" "active-worktree" "next-worktree"
if [ -x "$HELPER" ]; then
    "$HELPER" fold --worktree "$TARGET" > "$BASE/fold.out" 2> "$BASE/fold.err"
    FOLD_RC=$?
else
    FOLD_RC=127
fi
assert_equals "$FOLD_RC" "0" "unchanged primary narrative folds successfully"
assert_contains "$PRIMARY/.forge/local/state.md" 'done-worktree' "worktree Done reaches primary"
assert_contains "$PRIMARY/.forge/local/state.md" 'next-worktree' "worktree Next reaches primary"
assert_not_contains "$PRIMARY/.forge/local/state.md" 'active-worktree' "fold clears worktree Now"
assert_contains "$PRIMARY/.forge/local/state.md" '| Command | /fix-bug prior |' \
    "primary workflow authority remains untouched"

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

start_test "fold safe-stops without overwriting a diverged primary narrative"
# Re-seed the exact baseline manually, then change primary independently.
cp "$TARGET/.forge/local/.state-seed-snapshot.md" "$BASE/original-snapshot"
write_state "$TARGET/.forge/local/state.md" "/fix-bug bug-one" "done-worktree" "active-worktree" "next-worktree"
write_state "$PRIMARY/.forge/local/state.md" "/fix-bug prior" "independent-main" "main-active" "next-primary"
PRIMARY_BEFORE=$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')
if [ -x "$HELPER" ]; then
    "$HELPER" fold --worktree "$TARGET" > "$BASE/diverged.out" 2> "$BASE/diverged.err"
    DIVERGED_RC=$?
else
    DIVERGED_RC=127
fi
if [ "$DIVERGED_RC" -ne 0 ]; then pass "diverged fold exits nonzero"; else fail "diverged fold must exit nonzero"; fi
assert_contains "$BASE/diverged.err" 'FOLD_DIVERGED' "divergence is explained"
assert_equals "$(shasum -a 256 "$PRIMARY/.forge/local/state.md" | awk '{print $1}')" "$PRIMARY_BEFORE" \
    "diverged primary bytes are preserved"

report "test-worktree-lifecycle.sh"
