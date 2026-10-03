#!/usr/bin/env bash
# Manifest-driven Forge v6 materializer. Bash 3.2 compatible.

set -e

FORGE_BEGIN='<!-- forge:begin v6 -->'
FORGE_END='<!-- forge:end v6 -->'

hash_file_materializer() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

safe_relative_materializer_path() {
    case "$1" in ""|/*|~*|\\*|[A-Za-z]:*|*\\*|*/../*|../*|*/..|.|..|*//* ) return 1 ;; esac
    return 0
}

materializer_state_value() {
    local state="$1" wanted_section="$2" wanted_key="$3"
    awk -F '|' -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^## / {
            section = $0
            sub(/\r$/, "", section)
            sub(/^## /, "", section)
            next
        }
        /^\|/ {
            key = trim($2)
            if (section == wanted_section && key == wanted_key && NF >= 4) {
                count++
                value = trim($3)
            }
        }
        END {
            if (count != 1) exit 2
            print value
        }
    ' "$state"
}

report_normal_project_workflows() {
    local target="$1" state="$1/.forge/local/state.md"
    local command phase next_step state_root state_common base_ref base_sha
    local git_common current_head resolved_ref action

    if [ ! -e "$state" ]; then
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        return 0
    fi
    if [ -L "$state" ] || [ ! -f "$state" ]; then
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=canonical-state-not-regular action=workflow-state-show"
        return 0
    fi
    if ! command=$(materializer_state_value "$state" Workflow Command) \
        || ! phase=$(materializer_state_value "$state" Workflow Phase) \
        || ! next_step=$(materializer_state_value "$state" Workflow 'Next step') \
        || ! state_root=$(materializer_state_value "$state" Identity 'Worktree root') \
        || ! state_common=$(materializer_state_value "$state" Identity 'Git common directory') \
        || ! base_ref=$(materializer_state_value "$state" Identity 'Workflow base ref') \
        || ! base_sha=$(materializer_state_value "$state" Identity 'Workflow base SHA'); then
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=canonical-state-unreadable action=workflow-state-show"
        return 0
    fi
    case "$command" in none|''|-|'—') ;; *) echo "NORMAL_PROJECT_WORKFLOWS: READY"; return 0 ;; esac
    printf '%s\n' "$base_sha" | grep -qE '^[0-9a-f]{40}([0-9a-f]{24})?$' || {
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        return 0
    }
    if [ -n "$phase" ] || [ -n "$next_step" ]; then
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-state-invalid action=workflow-state-show"
        return 0
    fi
    git_common=$(git -C "$target" rev-parse --git-common-dir 2>/dev/null) || {
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-git-unavailable action=workflow-state-show"
        return 0
    }
    case "$git_common" in
        /*) git_common=$(cd "$git_common" 2>/dev/null && pwd -P) || git_common='' ;;
        *) git_common=$(cd "$target/$git_common" 2>/dev/null && pwd -P) || git_common='' ;;
    esac
    if [ "$state_root" != "$target" ] || [ -z "$git_common" ] || [ "$state_common" != "$git_common" ]; then
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-identity-mismatch action=workflow-state-show"
        return 0
    fi
    current_head=$(git -C "$target" rev-parse --verify HEAD 2>/dev/null) || {
        echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-head-unavailable action=workflow-state-show"
        return 0
    }
    if [ "$current_head" = "$base_sha" ]; then
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        return 0
    fi
    action=workflow-state-show
    resolved_ref=$(git -C "$target" rev-parse --verify "${base_ref}^{commit}" 2>/dev/null || true)
    if [ "$resolved_ref" = "$current_head" ] \
        && git -C "$target" merge-base --is-ancestor "$base_sha" "$current_head" 2>/dev/null; then
        action=workflow-state-rebind
    fi
    echo "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-head-mismatch action=$action base_ref=$base_ref base_sha=$base_sha head=$current_head"
}

load_managed_manifest() {
    local manifest="$1" line=0 kind source destination platform host scope ownership canonical revision extra
    [ -f "$manifest" ] || { echo "BLOCKED: managed manifest not found: $manifest" >&2; return 1; }
    while IFS=$'\t' read -r kind source destination platform host scope ownership canonical revision extra; do
        line=$((line + 1))
        case "$kind" in ""|'#'*) continue ;; esac
        [ -z "$extra" ] || { echo "BLOCKED: manifest row $line has extra fields" >&2; return 1; }
        safe_relative_materializer_path "$destination" || { echo "BLOCKED: unsafe manifest destination on row $line" >&2; return 1; }
        case "$platform" in all|unix|windows) ;; *) return 1 ;; esac
        [ "$scope" = project ] || { echo "BLOCKED: active managed manifest contains non-project scope" >&2; return 1; }
        case "$kind" in canonical|adapter|merge|marker|protected|tombstone) ;; *) return 1 ;; esac
    done < "$manifest"
}

assert_no_link_ancestors() {
    local root="$1" relative="$2" old_ifs="$IFS" part current
    current="$root"
    IFS='/'
    for part in $relative; do
        current="$current/$part"
        [ ! -L "$current" ] || { IFS="$old_ifs"; echo "BLOCKED: symlinked managed path: $current" >&2; return 1; }
    done
    IFS="$old_ifs"
}

install_canonical_file() {
    local source="$1" destination="$2"
    [ -f "$source" ] || { echo "BLOCKED: canonical source missing: $source" >&2; return 1; }
    assert_no_link_ancestors "$MATERIALIZE_TARGET" "${destination#$MATERIALIZE_TARGET/}"
    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
    case "$destination" in *.sh|*/bin/*|*/verify-runtime|*/qualify-*) chmod +x "$destination" 2>/dev/null || true ;; esac
}

render_adapter() {
    local template="$1" destination="$2" canonical_path="$3" revision="$4"
    local stem name description capabilities model tmp rendered
    stem=$(basename "$destination")
    stem=${stem%.md}; stem=${stem%.toml}
    case "$destination" in
        */SKILL.md) name=$(basename "$(dirname "$destination")") ;;
        *) name="$stem" ;;
    esac
    description="Forge adapter for $name"
    case "$canonical_path" in
        .forge/workflows/opinion.md|.forge/workflows/new-feature.md|.forge/workflows/fix-bug.md|.forge/workflows/review-pr-comments.md|.forge/skills/council/SKILL.template.md)
            description="$description. Standing human approval covers ordinary-review transport of the bounded immutable candidate, prompt, and evidence, including sensitive tracked or in-scope non-ignored files, to the configured Claude Code/Codex reviewer services, and full-agent investigation selected from task needs. No extra Forge consent question. Ordinary review stays hermetic; investigate uses normal config, tools, network, and real-worktree write access. Host security and external/destructive mutation boundaries still apply."
            ;;
    esac
    capabilities=$(awk '
        NR == 1 && /^---\r?$/ { frontmatter=1; next }
        frontmatter && /^---\r?$/ { exit }
        frontmatter && /^(tools|disallowedTools):([[:space:]]|$)/ { capture=1; print; next }
        capture && /^[[:space:]]/ { print; next }
        { capture=0 }
    ' "$MATERIALIZE_TARGET/$canonical_path")
    [ -n "$capabilities" ] || capabilities='tools: "Read, Grep, Glob, Bash"'
    model="inherit"
    mkdir -p "$(dirname "$destination")"
    tmp="$destination.forge-tmp.$$"
    rendered="$tmp.rendered"
    sed \
        -e "s|{{CANONICAL_PATH}}|$canonical_path|g" \
        -e "s|{{CANONICAL_REVISION}}|$revision|g" \
        -e "s|{{REVISION}}|$revision|g" \
        -e "s|{{NAME}}|$name|g" \
        -e "s|{{DESCRIPTION}}|$description|g" \
        -e "s|{{MODEL}}|$model|g" \
        "$template" > "$rendered"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = '{{CAPABILITIES}}' ]; then
            printf '%s\n' "$capabilities"
        else
            printf '%s\n' "$line"
        fi
    done < "$rendered" > "$tmp"
    rm -f "$rendered"
    mv "$tmp" "$destination"
}

replace_marker_block() {
    local template="$1" destination="$2" begin_count end_count tmp begin_offset end_offset end_after
    local block_size last_hex previous_hex destination_last_hex destination_size
    begin_count=$(grep -aoF "$FORGE_BEGIN" "$template" 2>/dev/null | wc -l | tr -d ' ')
    end_count=$(grep -aoF "$FORGE_END" "$template" 2>/dev/null | wc -l | tr -d ' ')
    [ "$begin_count" = 1 ] && [ "$end_count" = 1 ] || {
        echo "BLOCKED: marker template has malformed Forge boundaries: $template" >&2
        return 1
    }
    mkdir -p "$(dirname "$destination")"
    if [ ! -f "$destination" ]; then
        cp "$template" "$destination"
        return 0
    fi
    begin_count=$(grep -aoF "$FORGE_BEGIN" "$destination" 2>/dev/null | wc -l | tr -d ' ')
    end_count=$(grep -aoF "$FORGE_END" "$destination" 2>/dev/null | wc -l | tr -d ' ')
    case "$begin_count:$end_count" in
        0:0)
            tmp=$(mktemp "$destination.forge-tmp.XXXXXX")
            if [ "$(basename "$destination")" = CLAUDE.md ] && awk '
                {
                    sub(/\r$/, "")
                    if ($0 ~ /^[[:space:]]*$/) next
                    meaningful++
                    if ($0 != "@AGENTS.md") invalid=1
                }
                END { exit (meaningful == 1 && !invalid) ? 0 : 1 }
            ' "$destination"; then
                cp "$template" "$tmp"
                if cmp -s "$destination" "$tmp"; then rm -f "$tmp"; else mv "$tmp" "$destination"; fi
                return 0
            fi
            cat "$destination" > "$tmp"
            destination_size=$(wc -c < "$destination" | tr -d ' ')
            if [ "$destination_size" -gt 0 ]; then
                destination_last_hex=$(tail -c 1 "$destination" | od -An -tx1 | tr -d ' \n')
                if [ "$destination_last_hex" = 0a ]; then printf '\n' >> "$tmp"; else printf '\n\n' >> "$tmp"; fi
            fi
            cat "$template" >> "$tmp"
            if cmp -s "$destination" "$tmp"; then rm -f "$tmp"; else mv "$tmp" "$destination"; fi
            ;;
        1:1)
            begin_offset=$(grep -aobF "$FORGE_BEGIN" "$destination" | cut -d: -f1)
            end_offset=$(grep -aobF "$FORGE_END" "$destination" | cut -d: -f1)
            [ "$end_offset" -ge "$begin_offset" ] || { echo "BLOCKED: Forge end marker precedes begin marker in $destination" >&2; return 1; }
            end_after=$((end_offset + ${#FORGE_END}))
            block_size=$(wc -c < "$template" | tr -d ' ')
            if [ "$block_size" -gt 0 ]; then
                last_hex=$(tail -c 1 "$template" | od -An -tx1 | tr -d ' \n')
                [ "$last_hex" != 0a ] || block_size=$((block_size - 1))
            fi
            if [ "$block_size" -gt 0 ]; then
                previous_hex=$(dd if="$template" bs=1 skip=$((block_size - 1)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
                [ "$previous_hex" != 0d ] || block_size=$((block_size - 1))
            fi
            tmp=$(mktemp "$destination.forge-tmp.XXXXXX")
            dd if="$destination" of="$tmp" bs=1 count="$begin_offset" 2>/dev/null
            dd if="$template" bs=1 count="$block_size" 2>/dev/null >> "$tmp"
            dd if="$destination" bs=1 skip="$end_after" 2>/dev/null >> "$tmp"
            if cmp -s "$destination" "$tmp"; then rm -f "$tmp"; else mv "$tmp" "$destination"; fi
            ;;
        *)
            echo "BLOCKED: malformed or duplicate Forge marker in $destination" >&2
            return 1
            ;;
    esac
}

detect_engines() {
    local host binary version help missing
    for host in claude codex; do
        binary=$(command -v "$host" 2>/dev/null || true)
        if [ -z "$binary" ]; then
            printf '%s\tABSENT\t-\t-\n' "$host"
            continue
        fi
        version=$($binary --version 2>/dev/null | head -1 || true)
        [ -n "$version" ] || version=$($binary --version 2>&1 | tail -1 || true)
        if [ "$host" = codex ]; then
            help="$($binary --help 2>&1 || true)
$($binary exec --help 2>&1 || true)"
        else
            help=$($binary --help 2>&1 || true)
        fi
        missing=""
        if [ "$host" = claude ]; then
            for flag in --safe-mode --strict-mcp-config --session-id --resume; do
                case "$help" in *"$flag"*) ;; *) missing="$missing $flag" ;; esac
            done
        else
            for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do
                case "$help" in *"$flag"*) ;; *) missing="$missing $flag" ;; esac
            done
        fi
        if [ -n "$missing" ]; then
            printf '%s\tPRESENT_CAPABILITY_GAP\t%s\t%s\tmissing:%s\n' "$host" "$binary" "$version" "$missing"
        else
            printf '%s\tPRESENT\t%s\t%s\n' "$host" "$binary" "$version"
        fi
    done
}

write_install_manifest() {
    local destination="$MATERIALIZE_TARGET/.forge/installed-files.tsv" temporary relative canonical_revision revision
    mkdir -p "$(dirname "$destination")"
    temporary=$(mktemp "$destination.tmp.XXXXXX")
    while IFS=$'\t' read -r relative canonical_revision; do
        if [ "$relative" = .forge/version ]; then
            if command -v shasum >/dev/null 2>&1; then
                revision=$(printf '%s\n' "$MATERIALIZE_RELEASE_VERSION" | shasum -a 256 | awk '{print $1}')
            else
                revision=$(printf '%s\n' "$MATERIALIZE_RELEASE_VERSION" | sha256sum | awk '{print $1}')
            fi
        elif [ -f "$MATERIALIZE_TARGET/$relative" ]; then
            revision=$(hash_file_materializer "$MATERIALIZE_TARGET/$relative")
        else
            continue
        fi
        printf '%s\t%s\t%s\n' "$relative" "$revision" "$canonical_revision" >> "$temporary"
    done < "$MATERIALIZE_INSTALLED_LIST"
    mv "$temporary" "$destination"
}

legacy_state_skeleton() {
    awk '
        { sub(/\r$/, "") }
        /^## (State|Open Questions|Blockers)$/ {
            print
            print "<forge-preserved-narrative>"
            narrative=1
            next
        }
        /^## / { narrative=0 }
        narrative { next }
        /^<!-- forge:migrated [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] -->$/ {
            print "<!-- forge:migrated <date> -->"
            next
        }
        /^\|[ \t]*Command[ \t]*\|/ { print "| Command | <inactive> |"; next }
        /^\|[ \t]*Phase[ \t]*\|/ { print "| Phase | <inactive> |"; next }
        /^\|[ \t]*Next step[ \t]*\|/ { print "| Next step | <inactive> |"; next }
        { print }
    ' "$1"
}

extract_legacy_state_section() {
    local source="$1" heading="$2" destination="$3"
    awk -v heading="$heading" '
        { line=$0; normalized=$0; sub(/\r$/, "", normalized) }
        normalized == heading { capture=1 }
        capture && normalized ~ /^## / && normalized != heading { exit }
        capture { print line }
    ' "$source" > "$destination"
}

migrate_legacy_state_if_safe() {
    local state="$MATERIALIZE_TARGET/.forge/local/state.md" fixture
    local command phase next_step snapshot state_hash backup backup_tmp skeleton fixture_skeleton
    local state_section questions_section blockers_section candidate current_hash
    [ "$MATERIALIZE_SCOPE" = project ] || return 0
    [ "${FORGE_TRANSACTION_STAGE:-0}" != 1 ] || return 0
    [ -e "$state" ] || return 0
    [ -f "$state" ] && [ ! -L "$state" ] || {
        echo "STATE_COMPATIBILITY: BLOCKED reason=canonical-state-not-regular action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
        return 0
    }
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/local/state.md" || return 1
    snapshot=$(mktemp "${TMPDIR:-/tmp}/forge-state-source.XXXXXX")
    cp "$state" "$snapshot"
    state_hash=$(hash_file_materializer "$snapshot")

    # Use the canonical current reader for already-current files. Historical
    # compatibility is deliberately narrower and fixture-bound below.
    if (
        # shellcheck source=../hooks/lib/workflow-state.sh
        source "$MATERIALIZE_REPO/hooks/lib/workflow-state.sh"
        workflow_state_validate_shape "$snapshot"
    ); then
        rm -f "$snapshot"
        return 0
    fi

    fixture="$MATERIALIZE_REPO/tests/template/fixtures/state-v6-transitional-inactive.md"
    if ! command=$(materializer_state_value "$snapshot" Workflow Command 2>/dev/null) \
        || ! phase=$(materializer_state_value "$snapshot" Workflow Phase 2>/dev/null) \
        || ! next_step=$(materializer_state_value "$snapshot" Workflow 'Next step' 2>/dev/null); then
        rm -f "$snapshot"
        echo "STATE_COMPATIBILITY: BLOCKED reason=unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
        return 0
    fi
    case "$command" in ''|none|-|'—') ;; *)
        rm -f "$snapshot"
        echo "STATE_COMPATIBILITY: BLOCKED reason=active-or-unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
        return 0 ;;
    esac
    case "$phase:$next_step" in
        ':'|'-:'|'—:'|':-'|':—'|'-:-'|'-:—'|'—:-'|'—:—') ;;
        *)
            rm -f "$snapshot"
            echo "STATE_COMPATIBILITY: BLOCKED reason=active-or-unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
            return 0 ;;
    esac

    skeleton=$(mktemp "${TMPDIR:-/tmp}/forge-state-skeleton.XXXXXX")
    fixture_skeleton=$(mktemp "${TMPDIR:-/tmp}/forge-state-fixture.XXXXXX")
    legacy_state_skeleton "$snapshot" > "$skeleton"
    legacy_state_skeleton "$fixture" > "$fixture_skeleton"
    if ! cmp -s "$skeleton" "$fixture_skeleton"; then
        rm -f "$snapshot" "$skeleton" "$fixture_skeleton"
        echo "STATE_COMPATIBILITY: BLOCKED reason=unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
        return 0
    fi
    rm -f "$skeleton" "$fixture_skeleton"
    if grep -aEq '^- \[[xX]\]|PR creation authorized|\|[[:space:]]*nonce[[:space:]]*\|[[:space:]]*[0-9a-fA-F]{8}-|Review iteration[[:space:]]*\||Candidate receipt[[:space:]]*\||Spec review receipt[[:space:]]*\||Quality review receipt[[:space:]]*\||Verify app receipt[[:space:]]*\||E2E receipt[[:space:]]*\||Promotion receipt[[:space:]]*\||Council receipt[[:space:]]*\|' "$snapshot"; then
        rm -f "$snapshot"
        echo "STATE_COMPATIBILITY: BLOCKED reason=legacy-state-contains-evidence action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative"
        return 0
    fi

    current_hash=$(hash_file_materializer "$state" 2>/dev/null || true)
    [ "$current_hash" = "$state_hash" ] || {
        rm -f "$snapshot"
        echo "BLOCKED: canonical state changed during compatibility classification" >&2
        return 1
    }
    backup="$state.bak.$state_hash"
    if [ -e "$backup" ]; then
        [ -f "$backup" ] && [ ! -L "$backup" ] && cmp -s "$snapshot" "$backup" || {
            rm -f "$snapshot"
            echo "BLOCKED: canonical state backup collision: $backup" >&2
            return 1
        }
    else
        backup_tmp=$(mktemp "$backup.tmp.XXXXXX")
        cp "$snapshot" "$backup_tmp"
        [ "$(hash_file_materializer "$backup_tmp")" = "$state_hash" ] || {
            rm -f "$snapshot" "$backup_tmp"
            echo "BLOCKED: canonical state backup verification failed" >&2
            return 1
        }
        mv "$backup_tmp" "$backup"
    fi

    state_section=$(mktemp "${TMPDIR:-/tmp}/forge-state-section.XXXXXX")
    questions_section=$(mktemp "${TMPDIR:-/tmp}/forge-questions-section.XXXXXX")
    blockers_section=$(mktemp "${TMPDIR:-/tmp}/forge-blockers-section.XXXXXX")
    candidate=$(mktemp "$state.tmp.XXXXXX")
    extract_legacy_state_section "$snapshot" '## State' "$state_section"
    extract_legacy_state_section "$snapshot" '## Open Questions' "$questions_section"
    extract_legacy_state_section "$snapshot" '## Blockers' "$blockers_section"
    awk -v state_section="$state_section" -v questions_section="$questions_section" -v blockers_section="$blockers_section" '
        function emit(path, line) { while ((getline line < path) > 0) print line; close(path) }
        /^## State$/ { emit(state_section); skip=1; next }
        /^## Open Questions$/ { emit(questions_section); skip=1; next }
        /^## Blockers$/ { emit(blockers_section); skip=1; next }
        /^## / { skip=0 }
        !skip { print }
    ' "$MATERIALIZE_REPO/state.template.md" > "$candidate"
    rm -f "$state_section" "$questions_section" "$blockers_section"
    (
        # shellcheck source=../hooks/lib/workflow-state.sh
        source "$MATERIALIZE_REPO/hooks/lib/workflow-state.sh"
        workflow_state_validate_shape "$candidate"
    ) || {
        rm -f "$snapshot" "$candidate"
        echo "BLOCKED: migrated canonical state failed current shape validation" >&2
        return 1
    }
    current_hash=$(hash_file_materializer "$state")
    [ "$current_hash" = "$state_hash" ] || {
        rm -f "$snapshot" "$candidate"
        echo "BLOCKED: canonical state changed during compatibility migration" >&2
        return 1
    }
    mv "$candidate" "$state"
    rm -f "$snapshot"
    echo "STATE_COMPATIBILITY: MIGRATED backup=$backup"
}

merge_json_config() {
    local template="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    if [ ! -f "$destination" ]; then
        cp "$template" "$destination"
    elif command -v python3 >/dev/null 2>&1; then
        python3 "$MATERIALIZE_REPO/scripts/merge-settings.py" "$template" "$destination"
    else
        echo "CONFIG_READINESS: BLOCKED: python3 unavailable to merge existing JSON: $destination"
        return 1
    fi
}

legacy_alias_candidates_exist() {
    local selectors source destination scope digest extra
    while IFS=$'\t' read -r selectors source destination scope digest extra; do
        case "$selectors" in ""|'#'*) continue ;; esac
        [ "$scope" = project ] || continue
        if [ -e "$MATERIALIZE_TARGET/$destination" ] || [ -L "$MATERIALIZE_TARGET/$destination" ]; then
            return 0
        fi
    done < "$MATERIALIZE_REPO/manifests/legacy-v5-aliases.tsv"
    if [ -f "$MATERIALIZE_TARGET/.codex/hooks.json" ] \
        && grep -Eq '\.codex[/\\]hooks[/\\]|COMPACTION IMMINENT' "$MATERIALIZE_TARGET/.codex/hooks.json"; then
        return 0
    fi
    return 1
}

legacy_alias_cleanup() {
    local mode="$1"
    [ "$MATERIALIZE_SCOPE" = project ] || return 0
    [ "${FORGE_TRANSACTION_STAGE:-0}" != 1 ] || return 0
    if command -v python3 >/dev/null 2>&1; then
        python3 "$MATERIALIZE_REPO/scripts/merge-settings.py" cleanup-legacy-aliases \
            --repo-root "$MATERIALIZE_REPO" --target "$MATERIALIZE_TARGET" --mode "$mode"
    elif legacy_alias_candidates_exist; then
        echo "BLOCKED: Python 3 is required to reconcile legacy cross-host compatibility files safely" >&2
        return 1
    fi
}

workflow_skill_cleanup() {
    [ "$MATERIALIZE_SCOPE" = project ] || return 0
    if command -v python3 >/dev/null 2>&1; then
        python3 "$MATERIALIZE_REPO/scripts/merge-settings.py" cleanup-workflow-skills \
            --repo-root "$MATERIALIZE_REPO" --target "$MATERIALIZE_TARGET" --mode "$1"
    else
        [ "$1" = check ] || return 0
        local kind source destination platform host scope ownership canonical revision
        while IFS=$'\t' read -r kind source destination platform host scope ownership canonical revision; do
            [ "$kind:$host:$ownership" = tombstone:codex:forge-generated ] || continue
            for destination in "$destination" "${destination/\/workflow-/\/}"; do
                assert_no_link_ancestors "$MATERIALIZE_TARGET" "$destination" || return 1
                if [ -e "$MATERIALIZE_TARGET/$destination" ]; then
                    echo 'BLOCKED: Python 3 is required to reconcile existing Codex workflow skills safely' >&2
                    return 1
                fi
            done
        done < "$MATERIALIZE_MANIFEST"
    fi
}

primary_checkout_for() {
    git -C "$1" worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}'
}

materialize_project_config() {
    local codex_binary codex_doctor_help
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".claude/settings.json"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".mcp.json"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".codex/hooks.json"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".codex/config.toml"
    merge_json_config "$MATERIALIZE_REPO/settings/settings.template.json" "$MATERIALIZE_TARGET/.claude/settings.json"
    merge_json_config "$MATERIALIZE_REPO/mcp.template.json" "$MATERIALIZE_TARGET/.mcp.json"
    merge_json_config "$MATERIALIZE_REPO/settings/codex-hooks.template.json" "$MATERIALIZE_TARGET/.codex/hooks.json"
    if command -v python3 >/dev/null 2>&1; then
        codex_binary=$(command -v codex 2>/dev/null || true)
        codex_doctor_help=""
        [ -z "$codex_binary" ] || codex_doctor_help=$($codex_binary doctor --help 2>&1 || true)
        if [ -n "$codex_binary" ] && printf '%s' "$codex_doctor_help" | grep -q -- '--json'; then
            python3 "$MATERIALIZE_REPO/scripts/render-codex-config.py" \
                --template "$MATERIALIZE_REPO/settings/codex-config.template.toml" \
                --existing "$MATERIALIZE_TARGET/.codex/config.toml" \
                --output "$MATERIALIZE_TARGET/.codex/config.toml" \
                --mcp-json "$MATERIALIZE_TARGET/.mcp.json" \
                --codex-validator "$codex_binary"
        else
            python3 "$MATERIALIZE_REPO/scripts/render-codex-config.py" \
                --template "$MATERIALIZE_REPO/settings/codex-config.template.toml" \
                --existing "$MATERIALIZE_TARGET/.codex/config.toml" \
                --output "$MATERIALIZE_TARGET/.codex/config.toml" \
                --mcp-json "$MATERIALIZE_TARGET/.mcp.json"
        fi
    elif [ ! -f "$MATERIALIZE_TARGET/.codex/config.toml" ]; then
        cp "$MATERIALIZE_REPO/settings/codex-config.template.toml" "$MATERIALIZE_TARGET/.codex/config.toml"
        echo "CODEX_CONFIG_READINESS: BLOCKED: python3 unavailable for staged validation/translation"
        return 1
    else
        echo "CODEX_CONFIG_READINESS: BLOCKED: python3 unavailable to preserve and merge existing TOML"
        return 1
    fi
}

materialize_scope() {
    local kind source destination platform host scope ownership canonical revision extra selected canonical_file actual_revision marker_template version_tmp
    migrate_legacy_state_if_safe
    MATERIALIZE_INSTALLED_LIST=$(mktemp "${TMPDIR:-/tmp}/forge-installed.XXXXXX")
    trap 'rm -f "$MATERIALIZE_INSTALLED_LIST"' EXIT HUP INT TERM
    while IFS=$'\t' read -r kind source destination platform host scope ownership canonical revision extra; do
        case "$kind" in ""|'#'*) continue ;; esac
        [ "$scope" = "$MATERIALIZE_SCOPE" ] || continue
        case "$platform" in all|"$MATERIALIZE_PLATFORM") ;; *) continue ;; esac
        case "$kind" in canonical|adapter|marker) assert_no_link_ancestors "$MATERIALIZE_TARGET" "$destination" ;; esac
        case "$kind" in
            canonical)
                install_canonical_file "$MATERIALIZE_REPO/$source" "$MATERIALIZE_TARGET/$destination"
                printf '%s\t%s\n' "$destination" "$(hash_file_materializer "$MATERIALIZE_TARGET/$destination")" >> "$MATERIALIZE_INSTALLED_LIST"
                ;;
            adapter)
                canonical_file="$MATERIALIZE_TARGET/$canonical"
                [ -f "$canonical_file" ] || { echo "BLOCKED: adapter target missing: $canonical" >&2; return 1; }
                actual_revision=$(hash_file_materializer "$canonical_file")
                render_adapter "$MATERIALIZE_REPO/$source" "$MATERIALIZE_TARGET/$destination" "$canonical" "$actual_revision"
                printf '%s\t%s\n' "$destination" "$actual_revision" >> "$MATERIALIZE_INSTALLED_LIST"
                ;;
            marker)
                canonical_file="$MATERIALIZE_TARGET/$canonical"
                [ -f "$canonical_file" ] || { echo "BLOCKED: marker target missing: $canonical" >&2; return 1; }
                actual_revision=$(hash_file_materializer "$canonical_file")
                marker_template=$(mktemp "${TMPDIR:-/tmp}/forge-marker.XXXXXX")
                sed "s/{{CANONICAL_REVISION}}/$actual_revision/g" "$MATERIALIZE_REPO/$source" > "$marker_template"
                replace_marker_block "$marker_template" "$MATERIALIZE_TARGET/$destination"
                rm -f "$marker_template"
                printf '%s\t%s\n' "$destination" "$actual_revision" >> "$MATERIALIZE_INSTALLED_LIST"
                ;;
        esac
    done < "$MATERIALIZE_MANIFEST"

        assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/local/state.md"
        mkdir -p "$MATERIALIZE_TARGET/.forge/local" "$MATERIALIZE_TARGET/.forge/memory"
        [ -f "$MATERIALIZE_TARGET/.forge/local/state.md" ] || cp "$MATERIALIZE_REPO/state.template.md" "$MATERIALIZE_TARGET/.forge/local/state.md"
        materialize_project_config
        legacy_alias_cleanup apply
        workflow_skill_cleanup apply
    printf '.forge/version\t-\n' >> "$MATERIALIZE_INSTALLED_LIST"
    write_install_manifest
    version_tmp=$(mktemp "$MATERIALIZE_TARGET/.forge/version.tmp.XXXXXX")
    printf '%s\n' "$MATERIALIZE_RELEASE_VERSION" > "$version_tmp"
    mv "$version_tmp" "$MATERIALIZE_TARGET/.forge/version"
    echo "FORGE_VERSION: $MATERIALIZE_RELEASE_VERSION"
}

MATERIALIZE_REPO=""
MATERIALIZE_TARGET=""
MATERIALIZE_SCOPE=project
MATERIALIZE_PLATFORM=unix
MATERIALIZE_RELEASE_VERSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-root) MATERIALIZE_REPO="$2"; shift 2 ;;
        --target) MATERIALIZE_TARGET="$2"; shift 2 ;;
        --scope) MATERIALIZE_SCOPE="$2"; shift 2 ;;
        --platform) MATERIALIZE_PLATFORM="$2"; shift 2 ;;
        --release-version) MATERIALIZE_RELEASE_VERSION="$2"; shift 2 ;;
        *) echo "Unknown materializer option: $1" >&2; exit 2 ;;
    esac
done

[ -n "$MATERIALIZE_REPO" ] && [ -n "$MATERIALIZE_TARGET" ] || {
    echo "Usage: materialize-adapters.sh --repo-root DIR --target DIR --scope project --release-version MAJOR.MINOR.PATCH" >&2
    exit 2
}
[ "$MATERIALIZE_SCOPE" = project ] || {
    echo "BLOCKED: active Forge materialization is project-only" >&2
    exit 1
}
[[ "$MATERIALIZE_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "BLOCKED: invalid release version" >&2
    exit 2
}
case "$MATERIALIZE_PLATFORM" in
    unix|windows) ;;
    *)
        echo "BLOCKED: invalid materializer platform '$MATERIALIZE_PLATFORM' (expected unix or windows)" >&2
        exit 2
        ;;
esac
if [ "$MATERIALIZE_PLATFORM" = unix ] && ! command -v python3 >/dev/null 2>&1; then
    echo "CONFIG_READINESS: BLOCKED: python3 is required before Forge materialization" >&2
    exit 1
fi
mkdir -p "$MATERIALIZE_TARGET"
MATERIALIZE_REPO=$(cd "$MATERIALIZE_REPO" && pwd -P)
MATERIALIZE_TARGET=$(cd "$MATERIALIZE_TARGET" && pwd -P)
MATERIALIZE_DIAGNOSTIC_TARGET=${FORGE_DIAGNOSTIC_TARGET:-$MATERIALIZE_TARGET}
MATERIALIZE_DIAGNOSTIC_TARGET=$(cd "$MATERIALIZE_DIAGNOSTIC_TARGET" && pwd -P)
MATERIALIZE_MANIFEST="$MATERIALIZE_REPO/manifests/managed-v6.tsv"
load_managed_manifest "$MATERIALIZE_MANIFEST"
legacy_alias_cleanup check
workflow_skill_cleanup check
materialize_scope

echo "INSTALLATION: MATERIALIZED"
detect_engines | while IFS=$'\t' read -r engine availability binary version diagnostic; do
    case "$availability" in
        ABSENT)
            echo "$engine RUNTIME_READY: BLOCKED binary unavailable; host surface remains materialized"
            ;;
        PRESENT_CAPABILITY_GAP)
            echo "$engine RUNTIME_READY: BLOCKED $diagnostic"
            ;;
        *)
            echo "$engine RUNTIME_READY: BLOCKED pending authenticated final runtime qualification ($binary; $version)"
            ;;
    esac
done

primary=$(primary_checkout_for "$MATERIALIZE_DIAGNOSTIC_TARGET" || true)
current=$MATERIALIZE_DIAGNOSTIC_TARGET
if [ -n "$primary" ] && [ "$(cd "$primary" 2>/dev/null && pwd -P)" != "$current" ]; then
    echo "CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration"
    echo "Run: cd '$primary' && '$MATERIALIZE_REPO/setup.sh'"
else
    echo "CODEX_HOOKS: MATERIALIZED primary worktree registration; trust remains unverified"
fi
report_normal_project_workflows "$MATERIALIZE_DIAGNOSTIC_TARGET"
echo "NATIVE_GOAL_RUNTIME: PENDING reason=live-qualification-not-run"
echo "RUNTIME_QUALIFICATION: final owner '$MATERIALIZE_REPO/scripts/qualify-runtime-final.sh'; live project '$MATERIALIZE_DIAGNOSTIC_TARGET'; command and required operator evidence: '$MATERIALIZE_REPO/docs/qualification/agent-mode-selection.md'"
