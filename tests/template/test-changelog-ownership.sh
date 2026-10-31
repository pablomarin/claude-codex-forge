#!/usr/bin/env bash
# Customer release histories are not installer output.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
TMP=$(scratch_dir changelog-ownership)
_SCRATCH_DIRS+=("$TMP")
mkdir -p "$TMP/bin"
for host in claude codex; do
    printf '#!/bin/sh\nexit 127\n' > "$TMP/bin/$host"
    chmod +x "$TMP/bin/$host"
done
export PATH="$TMP/bin:$PATH"

for layout in none nested root-and-nested; do
    start_test "installer preserves $layout customer changelog layout"
    project="$TMP/$layout"
    mkdir -p "$project"
    git -C "$project" init -q
    printf '{"name":"customer-project"}\n' > "$project/package.json"
    if [ "$layout" != none ]; then
        mkdir -p "$project/apps/customer/docs"
        printf '# Customer history\r\n\r\nExisting release: café.\r\n' > "$project/apps/customer/docs/CHANGELOG.md"
        nested_hash=$(hash_file "$project/apps/customer/docs/CHANGELOG.md")
    fi
    if [ "$layout" = root-and-nested ]; then
        mkdir -p "$project/docs"
        printf '# Tooling history\n\nExisting customer-owned root history.\n' > "$project/docs/CHANGELOG.md"
        root_hash=$(hash_file "$project/docs/CHANGELOG.md")
    fi
    for mode in install upgrade refresh; do
        case "$mode" in
            install) args=(--this-checkout-only) ;;
            upgrade) args=(--this-checkout-only --upgrade) ;;
            refresh) args=(--this-checkout-only --force) ;;
        esac
        run_setup "$project" "$TMP/$layout-$mode.log" "${args[@]}"
        assert_equals "$?" 0 "$mode succeeds for $layout"
        assert_file_exists "$project/.forge/version" "$mode retains installed Forge version metadata"
        if [ "$layout" = root-and-nested ]; then
            assert_hash_equals "$project/docs/CHANGELOG.md" "$root_hash" "$mode preserves existing root history bytes"
        else
            assert_file_missing "$project/docs/CHANGELOG.md" "$mode does not create a root changelog"
        fi
        if [ "$layout" != none ]; then
            assert_hash_equals "$project/apps/customer/docs/CHANGELOG.md" "$nested_hash" "$mode preserves existing nested history bytes"
        fi
    done
done
report 'Changelog ownership'
