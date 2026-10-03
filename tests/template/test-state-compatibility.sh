#!/usr/bin/env bash
# Focused routine-upgrade compatibility tests for pre-Identity/Receipts V6 state.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

new_case() {
    local name="$1" target
    target=$(scratch_dir "state-compat-$name")
    git -C "$target" init -q
    mkdir -p "$target/.forge/local" "$target/home"
    printf '6\n' > "$target/.forge/version"
    cp "$REPO_ROOT/tests/template/fixtures/state-v6-transitional-inactive.md" \
        "$target/.forge/local/state.md"
    printf '%s\n' "$target"
}

run_materializer() {
    local target="$1" log="$2"
    shift 2
    (cd "$target" && HOME="$target/home" "$@" bash \
        "$REPO_ROOT/scripts/materialize-adapters.sh" \
        --repo-root "$REPO_ROOT" --target "$target" --scope project \
        --platform unix --release-version 6.4.1) > "$log" 2>&1
}

insert_after_now() {
    local path="$1" inserted="$2" temporary="$1.tmp"
    awk -v inserted="$inserted" '{ print; if ($0 == "- TRANSITIONAL_NOW_TOKEN") print inserted }' \
        "$path" > "$temporary"
    mv "$temporary" "$path"
}

assert_preserved() {
    local target="$1" expected="$2" label="$3"
    assert_hash_equals "$target/.forge/local/state.md" "$expected" "$label remains byte-identical"
    if find "$target/.forge/local" -maxdepth 1 -name 'state.md.bak.*' -print -quit | grep -q .; then
        fail "$label creates no migration backup"
    else
        pass "$label creates no migration backup"
    fi
}

if [ "${STATE_COMPAT_ONLY:-all}" != symlink ]; then
start_test "CRLF inactive state migrates but CRLF active state is preserved"
CRLF_INACTIVE=$(new_case crlf-inactive)
awk '{ printf "%s\r\n", $0 }' "$CRLF_INACTIVE/.forge/local/state.md" > "$CRLF_INACTIVE/state.crlf"
mv "$CRLF_INACTIVE/state.crlf" "$CRLF_INACTIVE/.forge/local/state.md"
CRLF_INACTIVE_HASH=$(hash_file "$CRLF_INACTIVE/.forge/local/state.md")
run_materializer "$CRLF_INACTIVE" "$CRLF_INACTIVE/run.log" env
assert_equals "$?" "0" "CRLF inactive transition completes"
assert_contains "$CRLF_INACTIVE/run.log" "STATE_COMPATIBILITY: MIGRATED" "CRLF inactive state is recognized"
assert_hash_equals "$CRLF_INACTIVE/.forge/local/state.md.bak.$CRLF_INACTIVE_HASH" "$CRLF_INACTIVE_HASH" \
    "CRLF migration backup preserves exact source bytes"

CRLF_ACTIVE=$(new_case crlf-active)
sed -i.bak 's/| Command   | none  |/| Command   | \/fix-bug held |/' "$CRLF_ACTIVE/.forge/local/state.md"
rm "$CRLF_ACTIVE/.forge/local/state.md.bak"
awk '{ printf "%s\r\n", $0 }' "$CRLF_ACTIVE/.forge/local/state.md" > "$CRLF_ACTIVE/state.crlf"
mv "$CRLF_ACTIVE/state.crlf" "$CRLF_ACTIVE/.forge/local/state.md"
CRLF_ACTIVE_HASH=$(hash_file "$CRLF_ACTIVE/.forge/local/state.md")
run_materializer "$CRLF_ACTIVE" "$CRLF_ACTIVE/run.log" env
assert_equals "$?" "0" "CRLF active transition does not fail installation"
assert_preserved "$CRLF_ACTIVE" "$CRLF_ACTIVE_HASH" "CRLF active state"
assert_contains "$CRLF_ACTIVE/run.log" "STATE_COMPATIBILITY: BLOCKED" "CRLF active state is visibly blocked"
assert_contains "$CRLF_ACTIVE/run.log" "NORMAL_PROJECT_WORKFLOWS: BLOCKED" "CRLF active state blocks normal workflows"

start_test "ambiguous encodings, controls, evidence, and layouts never migrate"
for variant in bom phase-none lowercase-key missing-closing-pipe checked-row pr-auth nonce receipt duplicate-heading unknown-heading; do
    CASE=$(new_case "$variant")
    case "$variant" in
        bom)
            { printf '\357\273\277'; cat "$CASE/.forge/local/state.md"; } > "$CASE/state.bom"
            mv "$CASE/state.bom" "$CASE/.forge/local/state.md"
            ;;
        phase-none) sed -i.bak 's/| Phase     | —     |/| Phase     | none  |/' "$CASE/.forge/local/state.md"; rm "$CASE/.forge/local/state.md.bak" ;;
        lowercase-key) sed -i.bak 's/| Command   | none  |/| command   | none  |/' "$CASE/.forge/local/state.md"; rm "$CASE/.forge/local/state.md.bak" ;;
        missing-closing-pipe) sed -i.bak 's/| Command   | none  |/| Command   | none/' "$CASE/.forge/local/state.md"; rm "$CASE/.forge/local/state.md.bak" ;;
        checked-row) insert_after_now "$CASE/.forge/local/state.md" '- [x] historical review passed' ;;
        pr-auth) insert_after_now "$CASE/.forge/local/state.md" '- PR creation authorized 2026-01-01' ;;
        nonce) insert_after_now "$CASE/.forge/local/state.md" '| nonce | 00000000-0000-4000-8000-000000000001 |' ;;
        receipt) insert_after_now "$CASE/.forge/local/state.md" '| Candidate receipt | .forge/local/evidence/old.receipt |' ;;
        duplicate-heading) printf '\n## Workflow\n' >> "$CASE/.forge/local/state.md" ;;
        unknown-heading) printf '\n## Custom Control\n\nproject-owned\n' >> "$CASE/.forge/local/state.md" ;;
    esac
    BEFORE=$(hash_file "$CASE/.forge/local/state.md")
    run_materializer "$CASE" "$CASE/run.log" env
    assert_equals "$?" "0" "$variant state does not fail installation"
    assert_preserved "$CASE" "$BEFORE" "$variant state"
    assert_contains "$CASE/run.log" "STATE_COMPATIBILITY: BLOCKED" "$variant state is visibly blocked"
done

start_test "state races preserve concurrent bytes and stop before managed publication"
REAL_CMP=$(command -v cmp)
CLASSIFY_RACE=$(new_case classification-race)
mkdir -p "$CLASSIFY_RACE/shim"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "\\nCONCURRENT_CLASSIFICATION_EDIT\\n" >> "$FORGE_RACE_STATE"' \
    'exec "$FORGE_REAL_CMP" "$@"' \
    > "$CLASSIFY_RACE/shim/cmp"
chmod +x "$CLASSIFY_RACE/shim/cmp"
CLASSIFY_VERSION_HASH=$(hash_file "$CLASSIFY_RACE/.forge/version")
run_materializer "$CLASSIFY_RACE" "$CLASSIFY_RACE/run.log" env \
    PATH="$CLASSIFY_RACE/shim:$PATH" FORGE_RACE_STATE="$CLASSIFY_RACE/.forge/local/state.md" FORGE_REAL_CMP="$REAL_CMP"
if [ "$?" -ne 0 ]; then pass "classification race stops materialization"; else fail "classification race stops materialization"; fi
assert_contains "$CLASSIFY_RACE/.forge/local/state.md" "CONCURRENT_CLASSIFICATION_EDIT" "classification race preserves concurrent state edit"
assert_not_contains "$CLASSIFY_RACE/run.log" "STATE_COMPATIBILITY: MIGRATED" "classification race never publishes migrated state"
assert_hash_equals "$CLASSIFY_RACE/.forge/version" "$CLASSIFY_VERSION_HASH" "classification race leaves version unchanged"
if [ -e "$CLASSIFY_RACE/.forge/installed-files.tsv" ]; then fail "classification race writes no installed ledger"; else pass "classification race writes no installed ledger"; fi
if find "$CLASSIFY_RACE/.forge/local" -maxdepth 1 -name 'state.md.bak.*' -print -quit | grep -q .; then
    fail "classification race writes no backup"
else
    pass "classification race writes no backup"
fi

REAL_AWK=$(command -v awk)
PUBLISH_RACE=$(new_case publication-race)
mkdir -p "$PUBLISH_RACE/shim"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'trigger=false' \
    'for value in "$@"; do [ "$value" = "heading=## State" ] && trigger=true; done' \
    '"$FORGE_REAL_AWK" "$@"' \
    'status=$?' \
    'if [ "$trigger" = true ]; then printf "\\nCONCURRENT_PUBLICATION_EDIT\\n" >> "$FORGE_RACE_STATE"; fi' \
    'exit "$status"' \
    > "$PUBLISH_RACE/shim/awk"
chmod +x "$PUBLISH_RACE/shim/awk"
PUBLISH_SOURCE_HASH=$(hash_file "$PUBLISH_RACE/.forge/local/state.md")
PUBLISH_VERSION_HASH=$(hash_file "$PUBLISH_RACE/.forge/version")
run_materializer "$PUBLISH_RACE" "$PUBLISH_RACE/run.log" env \
    PATH="$PUBLISH_RACE/shim:$PATH" FORGE_RACE_STATE="$PUBLISH_RACE/.forge/local/state.md" FORGE_REAL_AWK="$REAL_AWK"
if [ "$?" -ne 0 ]; then pass "publication race stops materialization"; else fail "publication race stops materialization"; fi
assert_contains "$PUBLISH_RACE/.forge/local/state.md" "CONCURRENT_PUBLICATION_EDIT" "publication race preserves concurrent state edit"
assert_not_contains "$PUBLISH_RACE/run.log" "STATE_COMPATIBILITY: MIGRATED" "publication race never publishes migrated state"
assert_hash_equals "$PUBLISH_RACE/.forge/local/state.md.bak.$PUBLISH_SOURCE_HASH" "$PUBLISH_SOURCE_HASH" "publication race retains exact pre-race backup"
assert_hash_equals "$PUBLISH_RACE/.forge/version" "$PUBLISH_VERSION_HASH" "publication race leaves version unchanged"
if [ -e "$PUBLISH_RACE/.forge/installed-files.tsv" ]; then fail "publication race writes no installed ledger"; else pass "publication race writes no installed ledger"; fi

start_test "transaction staging remains the full-refresh owner"
STAGED=$(new_case transaction-stage)
STAGED_HASH=$(hash_file "$STAGED/.forge/local/state.md")
run_materializer "$STAGED" "$STAGED/run.log" env FORGE_TRANSACTION_STAGE=1
assert_equals "$?" "0" "transaction-stage materialization completes"
assert_preserved "$STAGED" "$STAGED_HASH" "transaction-stage legacy state"
assert_not_contains "$STAGED/run.log" "STATE_COMPATIBILITY: MIGRATED" "transaction stage skips routine state migration"
fi

start_test "symlinked state ancestors block before external bytes change"
LINK_CASE=$(scratch_dir state-compat-linked-ancestor)
LINK_OUTSIDE=$(scratch_dir state-compat-linked-outside)
git -C "$LINK_CASE" init -q
mkdir -p "$LINK_CASE/.forge" "$LINK_CASE/home" "$LINK_OUTSIDE"
cp "$REPO_ROOT/tests/template/fixtures/state-v6-transitional-inactive.md" "$LINK_OUTSIDE/state.md"
ln -s "$LINK_OUTSIDE" "$LINK_CASE/.forge/local"
LINK_HASH=$(hash_file "$LINK_OUTSIDE/state.md")
run_materializer "$LINK_CASE" "$LINK_CASE/run.log" env
if [ "$?" -ne 0 ]; then pass "symlinked state ancestor blocks materialization"; else fail "symlinked state ancestor blocks materialization"; fi
assert_hash_equals "$LINK_OUTSIDE/state.md" "$LINK_HASH" "symlinked ancestor leaves external state unchanged"
if find "$LINK_OUTSIDE" -maxdepth 1 -name 'state.md.bak.*' -print -quit | grep -q .; then
    fail "symlinked ancestor creates no external backup"
else
    pass "symlinked ancestor creates no external backup"
fi

cleanup_scratch_dirs
report "test-state-compatibility.sh"
