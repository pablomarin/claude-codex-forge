#!/usr/bin/env bash
# Real installer boundaries: short native names and ownership-safe v6 migration.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
RELEASE=$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' "$REPO_ROOT/docs/CHANGELOG.md" | head -1)
CASE=$(scratch_dir codex-workflow-names)
PROJECT="$CASE/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
NAMES='finish-branch fix-bug new-feature prd-create prd-discuss quick-fix review-pr-comments'
materialize() {
    PATH=/usr/bin:/bin:/usr/sbin:/sbin FORGE_ENGINE_IDENTITY_FIXTURE=1 \
        bash "$REPO_ROOT/scripts/materialize-adapters.sh" --repo-root "$REPO_ROOT" \
        --target "$PROJECT" --scope project \
        --release-version "$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' "$REPO_ROOT/docs/CHANGELOG.md" | head -1)" > "$CASE/install.log" 2>&1
}
seed_old() {
    local name canonical path
    for name in $NAMES; do
        canonical="$name"
        case "$name" in prd-*) canonical="prd/${name#prd-}" ;; esac
        path=".agents/skills/workflow-$name/SKILL.md"
        mkdir -p "$PROJECT/$(dirname "$path")"
        printf '%s\n' '---' "name: \"workflow-$name\"" 'forge-generated: true' \
            "canonical-path: \".forge/workflows/$canonical.md\"" '---' \
            "Read .forge/workflows/$canonical.md completely." > "$PROJECT/$path"
        printf '%s\t%s\t-\n' "$path" "$(hash_file "$PROJECT/$path")" >> "$PROJECT/.forge/installed-files.tsv"
    done
}
start_test 'fresh install exposes short names with unchanged workflow targets'
materialize
assert_equals "$?" 0 'materializer succeeds'
for name in $NAMES; do
    assert_contains "$PROJECT/.agents/skills/$name/SKILL.md" "name: \"$name\"" "$name is directly invocable"
    assert_file_missing "$PROJECT/.agents/skills/workflow-$name/SKILL.md" "$name has no redundant alias"
done
assert_contains "$PROJECT/.agents/skills/fix-bug/SKILL.md" '.forge/workflows/fix-bug.md' 'same canonical workflow'

start_test 'upgrade retires proven old wrappers and preserves sibling content'
seed_old
printf 'custom sibling\n' > "$PROJECT/.agents/skills/workflow-fix-bug/notes.md"
materialize
assert_equals "$?" 0 'upgrade succeeds'
for name in $NAMES; do
    assert_file_missing "$PROJECT/.agents/skills/workflow-$name/SKILL.md" "old $name retired"
done
assert_contains "$PROJECT/.agents/skills/workflow-fix-bug/notes.md" 'custom sibling' 'sibling survives'
short_hash=$(hash_file "$PROJECT/.agents/skills/fix-bug/SKILL.md")
materialize
assert_equals "$?" 0 'repeat install is idempotent'
assert_equals "$(hash_file "$PROJECT/.agents/skills/fix-bug/SKILL.md")" "$short_hash" 'repeat install preserves wrapper bytes'

start_test 'modified old adapter is preserved and reported'
seed_old
printf '\nCustom instructions\n' >> "$PROJECT/.agents/skills/workflow-fix-bug/SKILL.md"
materialize
assert_equals "$?" 0 'upgrade preserves modified old adapter'
assert_contains "$PROJECT/.agents/skills/workflow-fix-bug/SKILL.md" 'Custom instructions' 'old custom bytes survive'
assert_contains "$CASE/install.log" 'PRESERVED_COMPAT: .agents/skills/workflow-fix-bug/SKILL.md' 'preservation is visible'

start_test 'new-name collision blocks before managed files are overwritten'
mkdir -p "$PROJECT/.agents/skills/fix-bug"
printf 'My custom fix-bug skill\n' > "$PROJECT/.agents/skills/fix-bug/SKILL.md"
printf 'canonical sentinel\n' > "$PROJECT/.forge/workflows/fix-bug.md"
materialize
if [ "$?" -ne 0 ]; then pass 'custom short-name collision blocks'; else fail 'custom short-name collision blocks'; fi
assert_contains "$PROJECT/.agents/skills/fix-bug/SKILL.md" 'My custom fix-bug skill' 'custom destination survives'
assert_contains "$PROJECT/.forge/workflows/fix-bug.md" 'canonical sentinel' 'preflight precedes canonical writes'

start_test 'full refresh preview blocks the same collision'
PATH=/usr/bin:/bin:/usr/sbin:/sbin FORGE_ENGINE_IDENTITY_FIXTURE=1 \
    bash "$REPO_ROOT/scripts/full-refresh.sh" --target "$PROJECT" --release-version "$RELEASE" --dry-run > "$CASE/preview.log" 2>&1
if [ "$?" -ne 0 ]; then pass 'full refresh cannot overwrite custom short name'; else fail 'full refresh cannot overwrite custom short name'; fi
assert_contains "$PROJECT/.agents/skills/fix-bug/SKILL.md" 'My custom fix-bug skill' 'preview is read-only'

start_test 'full refresh previews then removes proven old wrappers'
# Only fixture-owned collision paths are removed to resume the test.
rm "$PROJECT/.agents/skills/fix-bug/SKILL.md"
materialize
seed_old
PATH=/usr/bin:/bin:/usr/sbin:/sbin FORGE_ENGINE_IDENTITY_FIXTURE=1 \
    bash "$REPO_ROOT/scripts/full-refresh.sh" --target "$PROJECT" --release-version "$RELEASE" --dry-run > "$CASE/preview.log" 2>&1
assert_equals "$?" 0 'refresh preview succeeds'
assert_file_exists "$PROJECT/.agents/skills/workflow-fix-bug/SKILL.md" 'preview does not delete old wrapper'
PATH=/usr/bin:/bin:/usr/sbin:/sbin FORGE_ENGINE_IDENTITY_FIXTURE=1 \
    bash "$REPO_ROOT/scripts/full-refresh.sh" --target "$PROJECT" --release-version "$RELEASE" > "$CASE/refresh.log" 2>&1
assert_equals "$?" 0 'refresh apply succeeds'
for name in $NAMES; do
    assert_file_exists "$PROJECT/.agents/skills/$name/SKILL.md" "refresh installs $name"
    assert_file_missing "$PROJECT/.agents/skills/workflow-$name/SKILL.md" "refresh retires old $name"
done
report 'test-codex-workflow-names.sh'
