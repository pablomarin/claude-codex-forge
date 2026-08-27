#!/usr/bin/env bash
# tests/template/test-dual-layout.sh — static v6 canonical-layout contracts.
#
# Run from repo root: bash tests/template/test-dual-layout.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

MANIFEST="$REPO_ROOT/manifests/managed-v6.tsv"
LEGACY="$REPO_ROOT/manifests/legacy-v5.tsv"
RELEASES="$REPO_ROOT/manifests/legacy-v5-releases.tsv"
FINGERPRINTS="$REPO_ROOT/manifests/legacy-v5-fingerprints.tsv"
REGIONS="$REPO_ROOT/manifests/legacy-v5-regions.tsv"

safe_relative_path() {
    local path="$1" old_ifs component
    case "$path" in
        ""|/*|~*|\\*|[A-Za-z]:*|*\\*|*'*'*|*'?'*|*'['*|*/|*//*) return 1 ;;
    esac
    old_ifs="$IFS"
    IFS='/'
    for component in $path; do
        case "$component" in ""|.|..) IFS="$old_ifs"; return 1 ;; esac
    done
    IFS="$old_ifs"
}

hash_stdin() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        sha256sum | awk '{print $1}'
    fi
}

fingerprint_hash_for() {
    local fingerprints="$1" fingerprint_set="$2" source="$3" destination="$4" scope="$5"
    awk -F '\t' -v set="$fingerprint_set" -v source="$source" -v destination="$destination" -v scope="$scope" '
        function selected(selector, wanted, values, count, i) {
            count=split(selector, values, ",")
            for (i=1; i<=count; i++) if (values[i] == wanted) return 1
            return 0
        }
        !/^#/ && $2 == source && $3 == destination && $4 == scope && selected($1, set) {print $5; found++}
        END {exit found == 1 ? 0 : 1}
    ' "$fingerprints"
}

release_map_is_valid() {
    local releases="$1" fingerprints="$2" regions="$3" expected_versions actual_versions
    local version release_commit stamp_mode fingerprint_set region_set extra changelog_version
    expected_versions="5.50 5.51 5.52 5.53 5.54 5.55 5.56 5.57 5.58 5.59 5.60 5.61"
    [ -f "$releases" ] && [ -f "$fingerprints" ] && [ -f "$regions" ] || return 1
    actual_versions=$(awk -F '\t' '!/^#/ && NF {print $1}' "$releases" | paste -sd ' ' -)
    [ "$actual_versions" = "$expected_versions" ] || return 1
    awk -F '\t' '!/^#/ && NF {if (NF != 5 || seen[$1]++) bad=1} END {exit bad ? 1 : 0}' "$releases" || return 1

    while IFS=$'\t' read -r version release_commit stamp_mode fingerprint_set region_set extra; do
        case "$version" in ""|'#'*) continue ;; esac
        [ -z "$extra" ] || return 1
        [ "${#release_commit}" -eq 40 ] || return 1
        case "$release_commit" in *[!0-9a-f]*) return 1 ;; esac
        git cat-file -e "$release_commit^{commit}" 2>/dev/null || return 1
        git cat-file -e "$release_commit:setup.sh" 2>/dev/null || return 1
        git cat-file -e "$release_commit:setup.ps1" 2>/dev/null || return 1
        changelog_version=$(git show "$release_commit:docs/CHANGELOG.md" | awk '$1 == "##" {print $2; exit}') || return 1
        [ "$changelog_version" = "$version" ] || return 1
        case "$stamp_mode" in
            pre-stamp)
                git show "$release_commit:setup.sh" | grep -qF '.claude/.forge-version' && return 1
                git show "$release_commit:setup.ps1" | grep -qF '.claude/.forge-version' && return 1
                ;;
            stamped)
                git show "$release_commit:setup.sh" | grep -qF '.claude/.forge-version' || return 1
                git show "$release_commit:setup.ps1" | grep -qF '.claude/.forge-version' || return 1
                ;;
            *) return 1 ;;
        esac
        awk -F '\t' -v set="$fingerprint_set" '
            function selected(selector, wanted, values, count, i) {count=split(selector, values, ","); for (i=1; i<=count; i++) if (values[i] == wanted) return 1; return 0}
            !/^#/ && selected($1, set) {found=1} END {exit found ? 0 : 1}
        ' "$fingerprints" || return 1
        awk -F '\t' -v set="$region_set" '$1 == set {found=1} END {exit found ? 0 : 1}' "$regions" || return 1
    done < "$releases"
}

release_fixture_is_supported() {
    local version="$1" stamp="$2" release_row release_commit stamp_mode fingerprint_set region_set
    local expected actual
    [ -f "$RELEASES" ] || return 1
    release_row=$(awk -F '\t' -v version="$version" '$1 == version {print; count++} END {if (count != 1) exit 1}' "$RELEASES") || return 1
    release_commit=$(printf '%s\n' "$release_row" | awk -F '\t' '{print $2}')
    stamp_mode=$(printf '%s\n' "$release_row" | awk -F '\t' '{print $3}')
    fingerprint_set=$(printf '%s\n' "$release_row" | awk -F '\t' '{print $4}')
    region_set=$(printf '%s\n' "$release_row" | awk -F '\t' '{print $5}')
    case "$stamp_mode" in
        pre-stamp) [ "$stamp" = "ABSENT" ] || return 1 ;;
        stamped) [ "$stamp" = "$version" ] || return 1 ;;
        *) return 1 ;;
    esac
    expected=$(fingerprint_hash_for "$FINGERPRINTS" "$fingerprint_set" "state.template.md" ".claude/state.template.md" "project") || return 1
    actual=$(git show "$release_commit:state.template.md" | hash_stdin) || return 1
    [ "$actual" = "$expected" ] || return 1
    awk -F '\t' -v set="$region_set" '$1 == set && $5 == "managed" {found++} END {exit found == 4 ? 0 : 1}' "$REGIONS"
}

fingerprints_are_release_bound() {
    local fingerprints="$1" releases="$2" version release_commit stamp_mode fingerprint_set region_set extra
    local kind source destination scope platform host ownership selector proof expected actual
    awk -F '\t' '
        /^#/ || /^[[:space:]]*$/ {next}
        NF != 5 || $1 == "" || $2 == "" || $3 == "" || $4 !~ /^(project|global)$/ || length($5) != 64 || $5 ~ /[^0-9a-f]/ {bad=1; next}
        {
            count=split($1, values, ","); for (key in seen) delete seen[key]
            for (i=1; i<=count; i++) if (values[i] !~ /^fp-5\.[0-9][0-9]$/ || seen[values[i]]++) bad=1
        }
        END {exit bad ? 1 : 0}
    ' "$fingerprints" || return 1

    while IFS=$'\t' read -r selectors source destination scope expected extra; do
        case "$selectors" in ""|'#'*) continue ;; esac
        [ -z "$extra" ] || return 1
        if ! awk -F '\t' -v source="$source" -v destination="$destination" -v scope="$scope" '$1 == "legacy" && $2 == source && $3 == destination && $4 == scope && $7 == "whole-file" {found=1} END {exit found ? 0 : 1}' "$LEGACY"; then
            return 1
        fi
        local old_ifs="$IFS" selected_set
        IFS=','
        for selected_set in $selectors; do
            if ! awk -F '\t' -v set="$selected_set" '$4 == set {found=1} END {exit found ? 0 : 1}' "$releases"; then
                IFS="$old_ifs"; return 1
            fi
        done
        IFS="$old_ifs"
    done < "$fingerprints"

    while IFS=$'\t' read -r version release_commit stamp_mode fingerprint_set region_set extra; do
        case "$version" in ""|'#'*) continue ;; esac
        while IFS=$'\t' read -r kind source destination scope platform host ownership selector proof; do
            [ "$kind" = "legacy" ] && [ "$ownership" = "whole-file" ] || continue
            if git cat-file -e "$release_commit:$source" 2>/dev/null; then
                expected=$(fingerprint_hash_for "$fingerprints" "$fingerprint_set" "$source" "$destination" "$scope") || return 1
                actual=$(git show "$release_commit:$source" | hash_stdin) || return 1
                [ "$actual" = "$expected" ] || return 1
            elif fingerprint_hash_for "$fingerprints" "$fingerprint_set" "$source" "$destination" "$scope" >/dev/null 2>&1; then
                return 1
            fi
        done < "$LEGACY"
    done < "$releases"
}

regions_are_release_bound() {
    local regions="$1" releases="$2" version release_commit stamp_mode fingerprint_set region_set extra
    local row_set scope destination sequence ownership region_id start_anchor end_anchor expected
    local source slice actual managed_count
    awk -F '\t' '!/^#/ && NF && NF != 9 {bad=1} END {exit bad ? 1 : 0}' "$regions" || return 1

    while IFS=$'\t' read -r row_set scope destination sequence ownership region_id start_anchor end_anchor expected extra; do
        case "$row_set" in ""|'#'*) continue ;; esac
        if ! awk -F '\t' -v set="$row_set" '$5 == set {found=1} END {exit found ? 0 : 1}' "$releases"; then return 1; fi
    done < "$regions"

    while IFS=$'\t' read -r version release_commit stamp_mode fingerprint_set region_set extra; do
        case "$version" in ""|'#'*) continue ;; esac
        managed_count=0
        while IFS=$'\t' read -r row_set scope destination sequence ownership region_id start_anchor end_anchor expected extra; do
            [ "$row_set" = "$region_set" ] && [ "$ownership" = "managed" ] || continue
            managed_count=$((managed_count + 1))
            case "$region_id" in
                project-prefix)
                    [ "$scope:$destination:$start_anchor:$end_anchor" = "project:CLAUDE.md:after:generated-field:before:project-overview" ] || return 1
                    source="CLAUDE.template.md"; slice='2,4p'
                    ;;
                research-enforcement)
                    [ "$scope:$destination:$start_anchor:$end_anchor" = "project:CLAUDE.md:### Research Enforcement:### Key Commands" ] || return 1
                    source="CLAUDE.template.md"; slice='107,112p'
                    ;;
                managed-policy-tail)
                    [ "$scope:$destination:$start_anchor:$end_anchor" = "project:CLAUDE.md:---:EOF" ] || return 1
                    source="CLAUDE.template.md"; slice='132,$p'
                    ;;
                global-policy-prefix)
                    [ "$scope:$destination:$start_anchor:$end_anchor" = "global:.claude/CLAUDE.md:BOF:## Personal Preferences" ] || return 1
                    source="GLOBAL-CLAUDE.template.md"; slice='1,53p'
                    ;;
                *) return 1 ;;
            esac
            actual=$(git show "$release_commit:$source" | sed -n "$slice" | hash_stdin) || return 1
            [ "$actual" = "$expected" ] || return 1
        done < "$regions"
        [ "$managed_count" -eq 4 ] || return 1
    done < "$releases"
}

manifest_is_valid() {
    local manifest="$1" project_root="${2:-$REPO_ROOT}" global_root="${3:-${2:-$REPO_ROOT}}"
    [ -f "$manifest" ] || return 1

    awk -F '\t' '
        /^#/ || /^[[:space:]]*$/ { next }
        NF != 9 { bad=1; next }
        $1 !~ /^(canonical|adapter|merge|marker|protected|tombstone|legacy)$/ { bad=1 }
        $4 !~ /^(all|unix|windows)$/ { bad=1 }
        $5 !~ /^(shared|claude|codex)$/ { bad=1 }
        $6 !~ /^(project|global)$/ { bad=1 }
        $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "" || $8 == "" || $9 == "" { bad=1 }
        END { exit bad ? 1 : 0 }
    ' "$manifest" || return 1

    awk -F '\t' '
        /^#/ || /^[[:space:]]*$/ { next }
        {
            key=$6 SUBSEP $3
            if ($4 == "all") {
                if (any[key]) bad=1
                all_platforms[key]=1
            } else {
                if (all_platforms[key] || seen_platform[key SUBSEP $4]) bad=1
                seen_platform[key SUBSEP $4]=1
            }
            any[key]=1
        }
        END { exit bad ? 1 : 0 }
    ' "$manifest" || return 1

    while IFS=$'\t' read -r kind source destination platform host scope ownership canonical_path revision extra; do
        case "$kind" in ""|'#'*) continue ;; esac
        [ -z "$extra" ] || return 1
        safe_relative_path "$destination" || return 1
        case "$kind:$source" in
            canonical:skills/CLAUDE.md|canonical:skills/AGENTS.md|canonical:skills/MEMORY.md|canonical:skills/*/CLAUDE.md|canonical:skills/*/AGENTS.md|canonical:skills/*/MEMORY.md) return 1 ;;
        esac

        local old_ifs="$IFS" component current
        case "$scope" in project) current="$project_root" ;; global) current="$global_root" ;; *) return 1 ;; esac
        IFS='/'
        for component in $destination; do
            current="$current/$component"
            [ ! -L "$current" ] || { IFS="$old_ifs"; return 1; }
        done
        IFS="$old_ifs"

        if [ "$kind" = "canonical" ] || [ "$kind" = "adapter" ] || [ "$kind" = "merge" ] || [ "$kind" = "marker" ]; then
            [ "$source" != "-" ] && [ -f "$REPO_ROOT/$source" ] || return 1
        fi
        if [ "$kind" = "adapter" ]; then
            [ "$ownership" = "forge-generated" ] || return 1
            safe_relative_path "$canonical_path" || return 1
            case "$canonical_path" in .forge/*) ;; *) return 1 ;; esac
            [ "$revision" = "v6" ] || return 1
        fi
    done < "$manifest"
}

assert_manifest_valid() {
    local manifest="$1" message="$2"
    if manifest_is_valid "$manifest"; then pass "$message"; else fail "$message"; fi
}

start_test "v6 manifest and staged template inventory exists"
for relative in \
    manifests/managed-v6.tsv \
    manifests/legacy-v5.tsv \
    manifests/legacy-v5-releases.tsv \
    manifests/legacy-v5-fingerprints.tsv \
    manifests/legacy-v5-regions.tsv \
    manifests/host-capabilities.tsv \
    manifests/workflow-capabilities.tsv \
    templates/adapters/claude-command.template.md \
    templates/adapters/claude-skill.template.md \
    templates/adapters/codex-skill.template.md \
    templates/adapters/claude-agent.template.md \
    templates/adapters/codex-agent.template.toml \
    templates/adapters/CLAUDE.block.template.md \
    templates/adapters/AGENTS.block.template.md \
    FORGE.template.md \
    GLOBAL-FORGE.template.md \
    GLOBAL-AGENTS.template.md; do
    assert_file_exists "$REPO_ROOT/$relative" "staged v6 artifact exists: $relative"
done

start_test "genuine pre-stamp and older stamped v5 releases are recognized"
if release_map_is_valid "$RELEASES" "$FINGERPRINTS" "$REGIONS"; then
    pass "release map binds supported versions to real commits and observed stamp modes"
else
    fail "release map does not match repository release/stamp history"
fi
if release_fixture_is_supported "5.50" "ABSENT"; then
    pass "genuine v5.50 pre-stamp fixture resolves to checked ownership data"
else
    fail "genuine v5.50 pre-stamp fixture is unsupported"
fi
if release_fixture_is_supported "5.51" "5.51"; then
    pass "genuine v5.51 stamped fixture resolves to checked ownership data"
else
    fail "genuine v5.51 stamped fixture is unsupported"
fi
ALL_STAMPS_SUPPORTED=1
for historical_stamp in 5.51 5.52 5.53 5.54 5.55 5.56 5.57 5.58 5.59 5.60 5.61; do
    release_fixture_is_supported "$historical_stamp" "$historical_stamp" || ALL_STAMPS_SUPPORTED=0
done
[ "$ALL_STAMPS_SUPPORTED" -eq 1 ] && pass "every valid historical project stamp resolves exactly" || fail "one or more valid historical project stamps are unsupported"
if ! release_fixture_is_supported "5.49" "ABSENT"; then
    pass "unsupported pre-stamp release is rejected"
else
    fail "unsupported pre-stamp release was accepted"
fi
if ! release_fixture_is_supported "5.51" "5.61"; then
    pass "mismatched historical stamp is rejected"
else
    fail "mismatched historical stamp was accepted"
fi
if [ -f "$RELEASES" ]; then
    RELEASE_MUTATION_DIR=$(scratch_dir legacy-release-mutations)
    DUPLICATE_RELEASE="$RELEASE_MUTATION_DIR/duplicate.tsv"
    WRONG_STAMP_MODE="$RELEASE_MUTATION_DIR/stamp-mode.tsv"
    WRONG_FINGERPRINT_SET="$RELEASE_MUTATION_DIR/fingerprint-set.tsv"
    awk '1; $1 == "5.50" {print}' "$RELEASES" > "$DUPLICATE_RELEASE"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "5.50" {$3="stamped"} {print}' "$RELEASES" > "$WRONG_STAMP_MODE"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "5.50" {$4="fp-5.51"} {print}' "$RELEASES" > "$WRONG_FINGERPRINT_SET"
    if ! release_map_is_valid "$DUPLICATE_RELEASE" "$FINGERPRINTS" "$REGIONS"; then
        pass "ambiguous duplicate release mapping is rejected"
    else
        fail "ambiguous duplicate release mapping was accepted"
    fi
    if ! release_map_is_valid "$WRONG_STAMP_MODE" "$FINGERPRINTS" "$REGIONS"; then
        pass "release map stamp mode must match historical setup bytes"
    else
        fail "historically false stamp mode was accepted"
    fi
    if ! fingerprints_are_release_bound "$FINGERPRINTS" "$WRONG_FINGERPRINT_SET"; then
        pass "release mapping to the wrong existing fingerprint set is rejected"
    else
        fail "release mapping to the wrong existing fingerprint set was accepted"
    fi
    assert_contains "$RELEASES" $'5.58\tcc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34\tstamped\tfp-5.57\tregions-5.50' "unchanged v5.58 ownership data is explicitly aliased"
fi

start_test "managed-v6 schema, destinations, ownership, and no-follow contract"
assert_manifest_valid "$MANIFEST" "managed-v6 records satisfy the nine-field schema"

if [ -f "$MANIFEST" ]; then
    if awk -F '\t' '!/^#/ && NF {print $6 "\t" $3}' "$MANIFEST" | sort -u | grep -q $'project\t.forge/instructions.md' \
        && awk -F '\t' '!/^#/ && NF {print $6 "\t" $3}' "$MANIFEST" | sort -u | grep -q $'global\t.forge/instructions.md'; then
        pass "project and global scopes may own the same relative destination"
    else
        fail "scope-aware destination ownership lacks project/global canonical roots"
    fi

    EXPECTED=$(scratch_dir dual-layout-inventory)/expected
    ACTUAL="${EXPECTED}.actual"
    (
        cd "$REPO_ROOT" || exit 1
        find commands rules skills agents hooks -type f -print \
            | grep -Ev '^skills/(.*/)?(CLAUDE|AGENTS|MEMORY)\.md$' \
            | LC_ALL=C sort
    ) > "$EXPECTED"
    awk -F '\t' '$1 == "canonical" && ($2 ~ /^(commands|rules|skills|agents|hooks)\//) {print $2}' "$MANIFEST" \
        | LC_ALL=C sort > "$ACTUAL"
    if diff -u "$EXPECTED" "$ACTUAL" >/dev/null 2>&1; then
        pass "every workflow/rule/skill/reference/agent/hook source has exactly one canonical record"
    else
        fail "canonical source inventory differs from repository source inventory"
        diff -u "$EXPECTED" "$ACTUAL" >&2 || true
    fi

    BAD_PREFIXES=$(awk -F '\t' '
        $1 == "canonical" && $2 ~ /^commands\// && $3 !~ /^\.forge\/workflows\// {print $2 " -> " $3}
        $1 == "canonical" && $2 ~ /^rules\// && $3 !~ /^\.forge\/rules\// {print $2 " -> " $3}
        $1 == "canonical" && $2 ~ /^skills\// && $3 !~ /^\.forge\/skills\// {print $2 " -> " $3}
        $1 == "canonical" && $2 ~ /^agents\// && $3 !~ /^\.forge\/agents\// {print $2 " -> " $3}
        $1 == "canonical" && $2 ~ /^hooks\// && $3 !~ /^\.forge\/hooks\// {print $2 " -> " $3}
    ' "$MANIFEST")
    [ -z "$BAD_PREFIXES" ] && pass "canonical destinations stay in their .forge namespace" || fail "bad canonical destinations: $BAD_PREFIXES"

    CANONICAL_DUPES=$(awk -F '\t' '$1 == "canonical" {print $2}' "$MANIFEST" | sort | uniq -d)
    [ -z "$CANONICAL_DUPES" ] && pass "canonical sources resolve exactly once" || fail "duplicate canonical sources: $CANONICAL_DUPES"

    MISSING_TARGETS=0
    while IFS=$'\t' read -r kind _ _ _ _ scope _ canonical_path _; do
        [ "$kind" = "adapter" ] || continue
        if ! awk -F '\t' -v target="$canonical_path" -v scope="$scope" '$1 == "canonical" && $3 == target && $6 == scope {found=1} END {exit found ? 0 : 1}' "$MANIFEST"; then
            fail "adapter canonical target has no canonical record in $scope scope: $canonical_path"
            MISSING_TARGETS=1
        fi
    done < "$MANIFEST"
    [ "$MISSING_TARGETS" -eq 0 ] && pass "every adapter points to a declared canonical destination"
fi

start_test "global ownership and platform-specific settings sources are explicit"
if [ -f "$MANIFEST" ]; then
    assert_contains "$MANIFEST" $'canonical\tGLOBAL-FORGE.template.md\t.forge/instructions.md\tall\tshared\tglobal\tforge-canonical\t.forge/instructions.md\tv6' "global canonical instructions are Forge-owned"
    assert_contains "$MANIFEST" $'marker\tGLOBAL-AGENTS.template.md\t.codex/AGENTS.md\tall\tcodex\tglobal\tforge-marker\t.forge/instructions.md\tv6' "global Codex marker targets global canonical instructions"
    assert_contains "$MANIFEST" $'merge\tsettings/settings.template.json\t.claude/settings.json\tunix\tclaude\tproject\tforge-managed-entries\t-\tv6' "Unix Claude settings use the Unix template"
    assert_contains "$MANIFEST" $'merge\tsettings/settings-windows.template.json\t.claude/settings.json\twindows\tclaude\tproject\tforge-managed-entries\t-\tv6' "Windows Claude settings use the Windows template"
    assert_contains "$MANIFEST" $'canonical\tmanifests/legacy-v5-releases.tsv\t.forge/migrations/legacy-v5-releases.tsv\tall\tshared\tproject' "supported legacy release map is installed canonically"
    if awk -F '\t' '$1 == "canonical" && $2 ~ /^skills\/(.*\/)?(CLAUDE|AGENTS|MEMORY)\.md$/ {bad=1} END {exit bad ? 0 : 1}' "$MANIFEST"; then
        fail "host-memory sentinel is declared as a canonical skill"
    else
        pass "host-memory sentinel files are excluded from canonical skills"
    fi
fi

start_test "manifest validator rejects stale revisions, unsafe paths, sentinels, and link ancestors"
if [ -f "$MANIFEST" ]; then
    MUTATION_DIR=$(scratch_dir dual-layout-mutations)
    STALE="$MUTATION_DIR/stale.tsv"
    TRAVERSAL="$MUTATION_DIR/traversal.tsv"
    DRIVE_DEST="$MUTATION_DIR/drive-destination.tsv"
    ADAPTER_TRAVERSAL="$MUTATION_DIR/adapter-traversal.tsv"
    ADAPTER_DRIVE="$MUTATION_DIR/adapter-drive.tsv"
    SENTINEL="$MUTATION_DIR/sentinel.tsv"
    DUPLICATE="$MUTATION_DIR/duplicate.tsv"
    PROJECT_ROOT="$MUTATION_DIR/project-root"
    GLOBAL_ROOT="$MUTATION_DIR/global-root"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "adapter" && !done {$9="v5"; done=1} {print}' "$MANIFEST" > "$STALE"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "canonical" && !done {$3="../escape"; done=1} {print}' "$MANIFEST" > "$TRAVERSAL"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "canonical" && !done {$3="C:/escape"; done=1} {print}' "$MANIFEST" > "$DRIVE_DEST"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "adapter" && !done {$8=".forge/../escape"; done=1} {print}' "$MANIFEST" > "$ADAPTER_TRAVERSAL"
    awk -F '\t' 'BEGIN{OFS="\t"} $1 == "adapter" && !done {$8="C:/escape"; done=1} {print}' "$MANIFEST" > "$ADAPTER_DRIVE"
    awk -F '\t' 'BEGIN{OFS="\t"} {print} END {print "canonical", "skills/CLAUDE.md", ".forge/skills/CLAUDE.md", "all", "shared", "project", "forge-canonical", ".forge/skills/CLAUDE.md", "v6"}' "$MANIFEST" > "$SENTINEL"
    awk '1; !/^#/ && !done {print; done=1}' "$MANIFEST" > "$DUPLICATE"
    mkdir -p "$PROJECT_ROOT" "$GLOBAL_ROOT"
    ln -s "$MUTATION_DIR" "$GLOBAL_ROOT/.forge"
    if ! manifest_is_valid "$STALE"; then pass "stale adapter revision is rejected"; else fail "stale adapter revision was accepted"; fi
    if ! manifest_is_valid "$TRAVERSAL"; then pass "parent-traversal destination is rejected"; else fail "parent-traversal destination was accepted"; fi
    if ! manifest_is_valid "$DRIVE_DEST"; then pass "Windows drive-qualified destination is rejected"; else fail "Windows drive-qualified destination was accepted"; fi
    if ! manifest_is_valid "$ADAPTER_TRAVERSAL"; then pass "adapter canonical-path traversal is rejected"; else fail "adapter canonical-path traversal was accepted"; fi
    if ! manifest_is_valid "$ADAPTER_DRIVE"; then pass "adapter Windows drive-qualified canonical path is rejected"; else fail "adapter Windows drive-qualified canonical path was accepted"; fi
    if ! manifest_is_valid "$SENTINEL"; then pass "canonical host-memory sentinel skill is rejected"; else fail "canonical host-memory sentinel skill was accepted"; fi
    if ! manifest_is_valid "$DUPLICATE"; then pass "overlapping destination ownership in one scope is rejected"; else fail "overlapping destination ownership in one scope was accepted"; fi
    if ! manifest_is_valid "$MANIFEST" "$PROJECT_ROOT" "$GLOBAL_ROOT"; then pass "symlinked global installed ancestor is rejected"; else fail "symlinked global installed ancestor was accepted"; fi
else
    fail "mutation checks require managed-v6.tsv"
fi

start_test "adapter templates are thin, revisioned, canonical readers"
for relative in \
    templates/adapters/claude-command.template.md \
    templates/adapters/claude-skill.template.md \
    templates/adapters/codex-skill.template.md \
    templates/adapters/claude-agent.template.md \
    templates/adapters/codex-agent.template.toml \
    templates/adapters/CLAUDE.block.template.md \
    templates/adapters/AGENTS.block.template.md; do
    file="$REPO_ROOT/$relative"
    [ -f "$file" ] || continue
    assert_contains "$file" "forge-generated" "$relative declares forge-generated"
    assert_contains "$file" "canonical-path" "$relative declares canonical-path"
    assert_contains "$file" "canonical-revision" "$relative declares canonical-revision"
    assert_matches "$file" '[Rr]ead.*canonical.*completely|@\.forge/instructions\.md' "$relative requires complete canonical loading"
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -le 36 ]; then pass "$relative stays thin ($lines lines)"; else fail "$relative embeds too much policy ($lines lines)"; fi
done

start_test "Claude and Codex wrapper names cover the same workflows, skills, and agents"
if [ -f "$MANIFEST" ]; then
    PARITY_DIR=$(scratch_dir dual-layout-parity)
    awk -F '\t' '$1 == "adapter" && $5 == "claude" && $3 ~ /^\.claude\/commands\// {name=$3; sub(/^\.claude\/commands\//,"",name); sub(/\.md$/,"",name); gsub(/\//,"-",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/claude-workflows"
    awk -F '\t' '$1 == "adapter" && $5 == "codex" && $3 ~ /^\.agents\/skills\/workflow-/ {name=$3; sub(/^\.agents\/skills\/workflow-/,"",name); sub(/\/SKILL\.md$/,"",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/codex-workflows"
    if diff -u "$PARITY_DIR/claude-workflows" "$PARITY_DIR/codex-workflows" >/dev/null 2>&1; then pass "workflow wrapper names have Claude/Codex parity"; else fail "workflow wrapper parity mismatch"; fi

    awk -F '\t' '$1 == "adapter" && $5 == "claude" && $3 ~ /^\.claude\/skills\// {name=$3; sub(/^\.claude\/skills\//,"",name); sub(/\/SKILL\.md$/,"",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/claude-skills"
    awk -F '\t' '$1 == "adapter" && $5 == "codex" && $3 ~ /^\.agents\/skills\// && $3 !~ /^\.agents\/skills\/workflow-/ && $3 != ".agents/skills/opinion/SKILL.md" {name=$3; sub(/^\.agents\/skills\//,"",name); sub(/\/SKILL\.md$/,"",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/codex-skills"
    if diff -u "$PARITY_DIR/claude-skills" "$PARITY_DIR/codex-skills" >/dev/null 2>&1; then pass "skill wrapper names have Claude/Codex parity"; else fail "skill wrapper parity mismatch"; fi

    awk -F '\t' '$1 == "adapter" && $5 == "claude" && $3 ~ /^\.claude\/agents\// {name=$3; sub(/^\.claude\/agents\//,"",name); sub(/\.md$/,"",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/claude-agents"
    awk -F '\t' '$1 == "adapter" && $5 == "codex" && $3 ~ /^\.codex\/agents\// {name=$3; sub(/^\.codex\/agents\//,"",name); sub(/\.toml$/,"",name); print name}' "$MANIFEST" | sort > "$PARITY_DIR/codex-agents"
    if diff -u "$PARITY_DIR/claude-agents" "$PARITY_DIR/codex-agents" >/dev/null 2>&1; then pass "agent wrapper names have Claude/Codex parity"; else fail "agent wrapper parity mismatch"; fi
fi

start_test "legacy v5 inventory is exact, bounded, and fingerprintable"
for manifest in "$LEGACY" "$FINGERPRINTS" "$REGIONS"; do
    [ -f "$manifest" ] || continue
    if awk -F '\t' '!/^#/ && NF && ($3 ~ /(^|\/)(local|memory)(\/|$)/ || $3 ~ /secret|\*|\?/) {bad=1} END {exit bad ? 0 : 1}' "$manifest"; then
        fail "$(basename "$manifest") inventories a protected destination or wildcard"
    else
        pass "$(basename "$manifest") excludes protected destinations and wildcards"
    fi
done
if [ -f "$LEGACY" ]; then
    assert_contains "$LEGACY" $'legacy\tCLAUDE.template.md\tCLAUDE.md\tproject' "legacy inventory declares mixed project root"
    assert_contains "$LEGACY" $'legacy\tGLOBAL-CLAUDE.template.md\t.claude/CLAUDE.md\tglobal' "legacy inventory declares global root"
    assert_contains "$LEGACY" $'merge\tsettings/settings.template.json\t.claude/settings.json\tproject' "legacy inventory declares project settings merge"
    assert_contains "$LEGACY" $'merge\tmcp.template.json\t.mcp.json\tproject' "legacy inventory declares MCP merge"
    assert_contains "$LEGACY" $'legacy\tmanifests/legacy-v5-releases.tsv\t.claude/.forge-version\tproject\tall\tclaude\tgenerated-value\tsupported-stamped-version\trelease-map-exact-value' "legacy project stamp recognizes only mapped historical values"
fi
if [ -f "$FINGERPRINTS" ]; then
    BAD_HASHES=$(awk -F '\t' '!/^#/ && NF && (NF != 5 || length($5) != 64 || $5 ~ /[^0-9a-f]/) {print NR}' "$FINGERPRINTS")
    [ -z "$BAD_HASHES" ] && pass "legacy fingerprint-set rows contain exact SHA-256 records" || fail "bad legacy fingerprint rows: $BAD_HASHES"
    COVERAGE_DIR=$(scratch_dir legacy-fingerprint-coverage)
    awk -F '\t' '$1 == "legacy" && $9 == "sha256" {print $2 "\t" $3 "\t" $4}' "$LEGACY" | sort -u > "$COVERAGE_DIR/required"
    awk -F '\t' '!/^#/ && NF {print $2 "\t" $3 "\t" $4}' "$FINGERPRINTS" | sort -u > "$COVERAGE_DIR/actual"
    if diff -u "$COVERAGE_DIR/required" "$COVERAGE_DIR/actual" >/dev/null 2>&1; then
        pass "every historical whole-file path has at least one release fingerprint"
    else
        fail "legacy fingerprint coverage differs from the released whole-file inventory"
    fi
    if fingerprints_are_release_bound "$FINGERPRINTS" "$RELEASES"; then
        pass "whole-file fingerprints recompute for every mapped v5.50-v5.61 release"
    else
        fail "whole-file fingerprints do not match mapped historical release bytes"
    fi
    PROVENANCE_DIR=$(scratch_dir legacy-provenance-mutations)
    BAD_FINGERPRINT="$PROVENANCE_DIR/fingerprints.tsv"
    awk -F '\t' 'BEGIN{OFS="\t"} !/^#/ && !done {$5="0000000000000000000000000000000000000000000000000000000000000000"; done=1} {print}' "$FINGERPRINTS" > "$BAD_FINGERPRINT"
    if ! fingerprints_are_release_bound "$BAD_FINGERPRINT" "$RELEASES"; then
        pass "mutated whole-file release fingerprint is rejected"
    else
        fail "mutated whole-file release fingerprint was accepted"
    fi
fi
if [ -f "$REGIONS" ]; then
    assert_contains "$REGIONS" $'generated-field\t# CLAUDE.md - [Project Name]' "legacy recognizer permits generated project-name field"
    for owner in project-overview project-commands; do
        if awk -F '\t' -v owner="$owner" '$5 == "user" && $6 == owner {found=1} END {exit found ? 0 : 1}' "$REGIONS"; then
            pass "legacy region table explicitly preserves $owner bytes"
        else
            fail "legacy region table lacks user-owned $owner region"
        fi
    done
    if awk -F '\t' '$5 == "managed" && $9 ~ /^[0-9a-f]{64}$/ {found=1} END {exit found ? 0 : 1}' "$REGIONS"; then
        pass "legacy managed bodies are identified by exact hashes"
    else
        fail "legacy region table lacks exact managed body hashes"
    fi
    BAD_SEQUENCE=$(awk -F '\t' '!/^#/ && NF {key=$1 FS $2 FS $3 FS $4; if (seen[key]++) print key}' "$REGIONS")
    [ -z "$BAD_SEQUENCE" ] && pass "legacy region sequence keys are unique per region-set/scope/file" || fail "duplicate legacy region sequence keys: $BAD_SEQUENCE"
    if regions_are_release_bound "$REGIONS" "$RELEASES"; then
        pass "managed-region fingerprints recompute for every mapped historical release"
    else
        fail "managed-region fingerprints do not match mapped historical release slices"
    fi
    PROVENANCE_DIR=${PROVENANCE_DIR:-$(scratch_dir legacy-provenance-mutations)}
    BAD_REGION="$PROVENANCE_DIR/regions.tsv"
    awk -F '\t' 'BEGIN{OFS="\t"} $5 == "managed" && !done {$9="0000000000000000000000000000000000000000000000000000000000000000"; done=1} {print}' "$REGIONS" > "$BAD_REGION"
    if ! regions_are_release_bound "$BAD_REGION" "$RELEASES"; then
        pass "mutated managed-region release fingerprint is rejected"
    else
        fail "mutated managed-region release fingerprint was accepted"
    fi
fi

start_test "Task 2 materializer, config, runtime, goal, and router surfaces are manifest-owned"
for relative in \
    scripts/materialize-adapters.sh scripts/materialize-adapters.ps1 \
    scripts/render-codex-config.py scripts/verify-runtime.sh scripts/verify-runtime.ps1 \
    scripts/qualify-dispatch-isolation.sh scripts/qualify-dispatch-isolation.ps1 \
    scripts/qualify-goal-feasibility.sh scripts/qualify-goal-feasibility.ps1 \
    scripts/forge-goal-authorize.sh scripts/forge-goal-authorize.ps1 \
    scripts/forge-goal-capture.sh scripts/forge-goal-capture.ps1 \
    hooks/lib/codex-worktree-dispatch.sh hooks/lib/codex-worktree-dispatch.ps1 \
    settings/codex-config.template.toml settings/codex-hooks.template.json \
    tests/template/test-runtime-identity.sh tests/template/test-runtime-identity.ps1 \
    tests/template/test-goal-feasibility.sh tests/template/test-goal-feasibility.ps1 \
    tests/template/run-all.ps1 .github/workflows/windows-parity.yml; do
    assert_file_exists "$REPO_ROOT/$relative" "Task 2 artifact exists: $relative"
done

if [ -f "$MANIFEST" ]; then
    for row in \
        $'canonical\thooks/lib/codex-worktree-dispatch.sh\t.forge/hooks/lib/codex-worktree-dispatch.sh' \
        $'canonical\thooks/lib/codex-worktree-dispatch.ps1\t.forge/hooks/lib/codex-worktree-dispatch.ps1' \
        $'canonical\tscripts/verify-runtime.sh\t.forge/bin/verify-runtime' \
        $'canonical\tscripts/verify-runtime.ps1\t.forge/bin/verify-runtime.ps1' \
        $'canonical\tscripts/forge-goal-authorize.sh\t.forge/bin/forge-goal-authorize' \
        $'canonical\tscripts/forge-goal-authorize.ps1\t.forge/bin/forge-goal-authorize.ps1' \
        $'canonical\tscripts/forge-goal-capture.sh\t.forge/bin/forge-goal-capture' \
        $'canonical\tscripts/forge-goal-capture.ps1\t.forge/bin/forge-goal-capture.ps1'; do
        assert_contains "$MANIFEST" "$row" "managed-v6 owns shipped helper: ${row#*$'\t'}"
    done
    assert_contains "$MANIFEST" $'merge\tsettings/codex-config.template.toml\t.codex/config.toml' "Codex config template is singular and manifest-owned"
    assert_contains "$MANIFEST" $'merge\tsettings/codex-hooks.template.json\t.codex/hooks.json' "Codex hook registry template is singular and manifest-owned"
    assert_contains "$MANIFEST" $'protected\t-\t.forge/bin/codex.identity\tall\tcodex\tglobal\toperator-setup' "managed-v6 declares the independently recorded Codex identity"
    assert_contains "$MANIFEST" $'protected\t-\t.forge/bin/codex.identity.sha256\tall\tcodex\tglobal\toperator-seal' "managed-v6 declares the Codex identity seal"
fi

start_test "live qualification scripts are separate from deterministic suite discovery"
assert_not_contains "$REPO_ROOT/tests/template/run-all.sh" 'qualify-dispatch-isolation' "Bash deterministic runner never invokes live dispatch qualification"
assert_not_contains "$REPO_ROOT/tests/template/run-all.sh" 'qualify-goal-feasibility' "Bash deterministic runner never invokes live goal qualification"
assert_contains "$REPO_ROOT/tests/template/run-all.sh" 'test-runtime-identity.sh' "Bash runner owns deterministic runtime identity suite"
assert_contains "$REPO_ROOT/tests/template/run-all.sh" 'test-goal-feasibility.sh' "Bash runner owns deterministic goal feasibility suite"

start_test "PowerShell 5.1 materializer and owning runner mirror the Unix contracts"
for function_name in Read-ManagedManifest Install-CanonicalFile Render-Adapter Set-ForgeMarkerBlock Get-EngineAvailability Write-InstallManifest; do
    assert_contains "$REPO_ROOT/scripts/materialize-adapters.ps1" "function $function_name" "PowerShell materializer defines $function_name"
done
assert_contains "$REPO_ROOT/setup.ps1" '-Scope global -Platform windows' "PowerShell global setup delegates with explicit scope/platform"
assert_contains "$REPO_ROOT/setup.ps1" '-Scope project -Platform windows' "PowerShell project setup delegates with explicit scope/platform"
assert_contains "$REPO_ROOT/tests/template/run-all.ps1" 'Get-ChildItem -Path $PSScriptRoot -Filter "test-*.ps1"' "PowerShell runner discovers every owning suite"
assert_not_contains "$REPO_ROOT/tests/template/run-all.ps1" 'ignore' "PowerShell runner has no silent ignore list"
assert_contains "$REPO_ROOT/.github/workflows/windows-parity.yml" 'shell: powershell' "Windows workflow uses Windows PowerShell"

start_test "live root templates are thin v6 marker surfaces"
for template in CLAUDE.template.md GLOBAL-CLAUDE.template.md; do
    lines=$(wc -l < "$REPO_ROOT/$template" | tr -d ' ')
    [ "$lines" -le 20 ] && pass "$template stays thin ($lines lines)" || fail "$template still embeds a second policy body ($lines lines)"
    assert_contains "$REPO_ROOT/$template" '<!-- forge:begin v6 -->' "$template opens bounded v6 block"
    assert_contains "$REPO_ROOT/$template" '<!-- forge:end v6 -->' "$template closes bounded v6 block"
done

report "test-dual-layout.sh"
