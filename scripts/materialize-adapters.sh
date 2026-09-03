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

physical_file_materializer() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }

resolve_cli_materializer() {
    local path="$1" target
    case "$path" in /*) ;; *) path=$(physical_file_materializer "$path") ;; esac
    while [ -L "$path" ]; do
        target=$(readlink "$path") || return 1
        case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac
    done
    physical_file_materializer "$path"
}

hash_codex_capability_materializer() {
    local binary="$1" root_help exec_help flag state
    root_help=$($binary --help 2>&1 || true)
    exec_help=$($binary exec --help 2>&1 || true)
    if command -v shasum >/dev/null 2>&1; then
        { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | shasum -a 256 | awk '{print $1}'
    else
        { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | sha256sum | awk '{print $1}'
    fi
}

write_codex_identity_materializer() {
    local writer_revision="$1" capture_revision="$2" identity invocation binary version root_help exec_help missing status identity_class tmp
    identity="$MATERIALIZE_TARGET/.forge/bin/codex.identity"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/bin/codex.identity"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/bin/codex.identity.sha256"
    mkdir -p "$(dirname "$identity")"
    invocation=$(command -v codex 2>/dev/null || true)
    binary=""; version=""; capability_revision=""; binary_sha256=""; missing=" binary-unavailable"; status=BLOCKED
    identity_class=operator-setup
    [ "${FORGE_ENGINE_IDENTITY_FIXTURE:-0}" != 1 ] || identity_class=fixture-only
    if [ -n "$invocation" ]; then
        case "$invocation" in /*) ;; *) invocation=$(physical_file_materializer "$invocation") ;; esac
        binary=$(resolve_cli_materializer "$invocation" 2>/dev/null || true)
        if [ -n "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ]; then
            version=$($binary --version 2>/dev/null | head -1 || true)
            root_help=$($binary --help 2>&1 || true); exec_help=$($binary exec --help 2>&1 || true); missing=""
            for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do
                case "$root_help$exec_help" in *"$flag"*) ;; *) missing="$missing $flag" ;; esac
            done
            binary_sha256=$(hash_file_materializer "$binary")
            capability_revision=$(hash_codex_capability_materializer "$binary")
            if [ -z "$missing" ] && [ -n "$version" ]; then status=QUALIFIED; fi
        fi
    fi
    tmp="$identity.tmp.$$"
    {
        printf 'format=forge-codex-identity-v1\nengine=codex\nidentity_class=%s\nstatus=%s\n' "$identity_class" "$status"
        printf 'invocation_path=%s\nbinary_path=%s\nbinary_sha256=%s\nversion=%s\ncapability_revision=%s\n' "$invocation" "$binary" "$binary_sha256" "$version" "$capability_revision"
        printf 'capture_revision=%s\nwriter_revision=%s\ndiagnostic=%s\n' "$capture_revision" "$writer_revision" "${missing# }"
    } > "$tmp"
    if [ -f "$identity" ] && cmp -s "$identity" "$tmp"; then rm -f "$tmp"; else mv "$tmp" "$identity"; fi
    hash_file_materializer "$identity" > "$identity.sha256"
}

safe_relative_materializer_path() {
    case "$1" in ""|/*|~*|\\*|[A-Za-z]:*|*\\*|*/../*|../*|*/..|.|..|*//* ) return 1 ;; esac
    return 0
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
        case "$scope" in project|global) ;; *) return 1 ;; esac
        case "$kind" in canonical|adapter|merge|marker|protected|tombstone) ;; *) return 1 ;; esac
    done < "$manifest"
}

assert_no_link_ancestors() {
    local root="$1" relative="$2" old_ifs="$IFS" part current="$root"
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
    local stem name description tools model tmp
    stem=$(basename "$destination")
    stem=${stem%.md}; stem=${stem%.toml}
    case "$destination" in
        */SKILL.md) name=$(basename "$(dirname "$destination")") ;;
        *) name="$stem" ;;
    esac
    description="Forge adapter for $name"
    tools="Read, Grep, Glob, Bash"
    model="inherit"
    mkdir -p "$(dirname "$destination")"
    tmp="$destination.forge-tmp.$$"
    sed \
        -e "s|{{CANONICAL_PATH}}|$canonical_path|g" \
        -e "s|{{CANONICAL_REVISION}}|$revision|g" \
        -e "s|{{REVISION}}|$revision|g" \
        -e "s|{{NAME}}|$name|g" \
        -e "s|{{DESCRIPTION}}|$description|g" \
        -e "s|{{TOOLS}}|$tools|g" \
        -e "s|{{MODEL}}|$model|g" \
        "$template" > "$tmp"
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
    local destination="$MATERIALIZE_TARGET/.forge/installed-files.tsv" relative canonical_revision
    mkdir -p "$(dirname "$destination")"
    : > "$destination"
    while IFS=$'\t' read -r relative canonical_revision; do
        [ -f "$MATERIALIZE_TARGET/$relative" ] || continue
        printf '%s\t%s\t%s\n' "$relative" "$(hash_file_materializer "$MATERIALIZE_TARGET/$relative")" "$canonical_revision" >> "$destination"
    done < "$MATERIALIZE_INSTALLED_LIST"
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
    else
        echo "CODEX_CONFIG_READINESS: BLOCKED: python3 unavailable to preserve and merge existing TOML"
    fi
}

materialize_global_config() {
    local codex_binary codex_doctor_help
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".claude/settings.json"
    assert_no_link_ancestors "$MATERIALIZE_TARGET" ".codex/config.toml"
    merge_json_config "$MATERIALIZE_REPO/settings/global-settings.template.json" "$MATERIALIZE_TARGET/.claude/settings.json"
    if command -v python3 >/dev/null 2>&1; then
        codex_binary=$(command -v codex 2>/dev/null || true)
        codex_doctor_help=""
        [ -z "$codex_binary" ] || codex_doctor_help=$($codex_binary doctor --help 2>&1 || true)
        if [ -n "$codex_binary" ] && printf '%s' "$codex_doctor_help" | grep -q -- '--json'; then
            python3 "$MATERIALIZE_REPO/scripts/render-codex-config.py" \
                --template "$MATERIALIZE_REPO/settings/codex-config.template.toml" \
                --existing "$MATERIALIZE_TARGET/.codex/config.toml" \
                --output "$MATERIALIZE_TARGET/.codex/config.toml" \
                --codex-validator "$codex_binary"
        else
            python3 "$MATERIALIZE_REPO/scripts/render-codex-config.py" \
                --template "$MATERIALIZE_REPO/settings/codex-config.template.toml" \
                --existing "$MATERIALIZE_TARGET/.codex/config.toml" \
                --output "$MATERIALIZE_TARGET/.codex/config.toml"
        fi
    elif [ ! -f "$MATERIALIZE_TARGET/.codex/config.toml" ]; then
        cp "$MATERIALIZE_REPO/settings/codex-config.template.toml" "$MATERIALIZE_TARGET/.codex/config.toml"
        echo "CODEX_CONFIG_READINESS: BLOCKED: python3 unavailable for staged validation"
    fi
}

materialize_scope() {
    local kind source destination platform host scope ownership canonical revision extra selected canonical_file actual_revision marker_template
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

    if [ "$MATERIALIZE_SCOPE" = project ]; then
        assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/local/state.md"
        mkdir -p "$MATERIALIZE_TARGET/.forge/local" "$MATERIALIZE_TARGET/.forge/memory"
        [ -f "$MATERIALIZE_TARGET/.forge/local/state.md" ] || cp "$MATERIALIZE_REPO/state.template.md" "$MATERIALIZE_TARGET/.forge/local/state.md"
        materialize_project_config
        legacy_alias_cleanup apply
    else
        assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/goal-authorizations"
        assert_no_link_ancestors "$MATERIALIZE_TARGET" ".forge/goal-captures"
        mkdir -p "$MATERIALIZE_TARGET/.forge/goal-authorizations" "$MATERIALIZE_TARGET/.forge/goal-captures"
        writer_revision=$(hash_file_materializer "$MATERIALIZE_REPO/scripts/forge-goal-authorize.sh")
        capture_revision=$(hash_file_materializer "$MATERIALIZE_REPO/scripts/forge-goal-capture.sh")
        writer="$MATERIALIZE_TARGET/.forge/bin/forge-goal-authorize"
        auth_root="$MATERIALIZE_TARGET/.forge/goal-authorizations"
        if [ -f "$writer" ]; then
            escaped_writer=${writer//\\/\\\\}; escaped_writer=${escaped_writer//&/\\&}; escaped_writer=${escaped_writer//|/\\|}
            escaped_auth=${auth_root//\\/\\\\}; escaped_auth=${escaped_auth//&/\\&}; escaped_auth=${escaped_auth//|/\\|}
            sed -e "s|__FORGE_WRITER_PATH__|$escaped_writer|g" \
                -e "s|__FORGE_AUTHORIZATION_ROOT__|$escaped_auth|g" \
                -e "s|__FORGE_WRITER_REVISION__|$writer_revision|g" "$writer" > "$writer.tmp.$$"
            mv "$writer.tmp.$$" "$writer"
            chmod +x "$writer"
            hash_file_materializer "$writer" > "$writer.sha256"
        fi
        write_codex_identity_materializer "$writer_revision" "$capture_revision"
        printf '.forge/bin/codex.identity\t-\n.forge/bin/codex.identity.sha256\t-\n' >> "$MATERIALIZE_INSTALLED_LIST"
        capture="$MATERIALIZE_TARGET/.forge/bin/forge-goal-capture"
        if [ -f "$capture" ]; then
            capture_root="$MATERIALIZE_TARGET/.forge/goal-captures"
            codex_identity="$MATERIALIZE_TARGET/.forge/bin/codex.identity"
            escaped_capture=${capture//\\/\\\\}; escaped_capture=${escaped_capture//&/\\&}; escaped_capture=${escaped_capture//|/\\|}
            escaped_capture_root=${capture_root//\\/\\\\}; escaped_capture_root=${escaped_capture_root//&/\\&}; escaped_capture_root=${escaped_capture_root//|/\\|}
            escaped_codex_identity=${codex_identity//\\/\\\\}; escaped_codex_identity=${escaped_codex_identity//&/\\&}; escaped_codex_identity=${escaped_codex_identity//|/\\|}
            sed -e "s|__FORGE_CAPTURE_PATH__|$escaped_capture|g" \
                -e "s|__FORGE_CAPTURE_ROOT__|$escaped_capture_root|g" \
                -e "s|__FORGE_CODEX_IDENTITY__|$escaped_codex_identity|g" \
                -e "s|__FORGE_CAPTURE_REVISION__|$capture_revision|g" \
                -e "s|__FORGE_WRITER_REVISION__|$writer_revision|g" "$capture" > "$capture.tmp.$$"
            mv "$capture.tmp.$$" "$capture"
            chmod +x "$capture"
            hash_file_materializer "$capture" > "$capture.sha256"
        fi
        materialize_global_config
    fi
    printf '6\n' > "$MATERIALIZE_TARGET/.forge/version"
    printf '.forge/version\t-\n' >> "$MATERIALIZE_INSTALLED_LIST"
    write_install_manifest
}

MATERIALIZE_REPO=""
MATERIALIZE_TARGET=""
MATERIALIZE_SCOPE=project
MATERIALIZE_PLATFORM=unix
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-root) MATERIALIZE_REPO="$2"; shift 2 ;;
        --target) MATERIALIZE_TARGET="$2"; shift 2 ;;
        --scope) MATERIALIZE_SCOPE="$2"; shift 2 ;;
        --platform) MATERIALIZE_PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown materializer option: $1" >&2; exit 2 ;;
    esac
done

[ -n "$MATERIALIZE_REPO" ] && [ -n "$MATERIALIZE_TARGET" ] || {
    echo "Usage: materialize-adapters.sh --repo-root DIR --target DIR --scope project|global" >&2
    exit 2
}
mkdir -p "$MATERIALIZE_TARGET"
MATERIALIZE_REPO=$(cd "$MATERIALIZE_REPO" && pwd -P)
MATERIALIZE_TARGET=$(cd "$MATERIALIZE_TARGET" && pwd -P)
MATERIALIZE_DIAGNOSTIC_TARGET=${FORGE_DIAGNOSTIC_TARGET:-$MATERIALIZE_TARGET}
MATERIALIZE_DIAGNOSTIC_TARGET=$(cd "$MATERIALIZE_DIAGNOSTIC_TARGET" && pwd -P)
MATERIALIZE_DIAGNOSTIC_HOME=${FORGE_DIAGNOSTIC_HOME:-${HOME:-}}
MATERIALIZE_MANIFEST="$MATERIALIZE_REPO/manifests/managed-v6.tsv"
load_managed_manifest "$MATERIALIZE_MANIFEST"
legacy_alias_cleanup check
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
            echo "$engine RUNTIME_READY: BLOCKED pending opt-in authenticated verify-runtime sentinel ($binary; $version)"
            ;;
    esac
done

if [ "$MATERIALIZE_SCOPE" = project ]; then
    primary=$(primary_checkout_for "$MATERIALIZE_DIAGNOSTIC_TARGET" || true)
    current=$MATERIALIZE_DIAGNOSTIC_TARGET
    if [ -n "$primary" ] && [ "$(cd "$primary" 2>/dev/null && pwd -P)" != "$current" ]; then
        echo "CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration"
        echo "Run: cd '$primary' && '$MATERIALIZE_REPO/setup.sh'"
    else
        echo "CODEX_HOOKS: MATERIALIZED primary worktree registration; trust remains unverified"
    fi
    global_version="$MATERIALIZE_DIAGNOSTIC_HOME/.forge/version"
    global_authorizer="$MATERIALIZE_DIAGNOSTIC_HOME/.forge/bin/forge-goal-authorize"
    global_version_ready=false
    if [ -f "$global_version" ] && [ ! -L "$global_version" ] \
        && [ "$(tr -d '\r\n' < "$global_version")" = 6 ]; then
        global_version_ready=true
    fi
    if [ "$global_version_ready" = true ] && [ -x "$global_authorizer" ] && [ ! -L "$global_authorizer" ]; then
        echo "GLOBAL_HARNESS: MATERIALIZED"
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        echo "NATIVE_GOAL_RUNTIME: PENDING qualification via scripts/qualify-goal-feasibility.sh"
    elif [ -e "$global_version" ] || [ -L "$global_version" ] \
        || [ -e "$global_authorizer" ] || [ -L "$global_authorizer" ]; then
        echo "GLOBAL_HARNESS: PARTIAL canonical version stamp or goal authorization helper missing or invalid"
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        echo "NATIVE_GOAL_RUNTIME: NOT_AVAILABLE optional; preview repair with '$MATERIALIZE_REPO/setup.sh --global -F --dry-run'"
    else
        echo "GLOBAL_HARNESS: NOT_INSTALLED optional"
        echo "NORMAL_PROJECT_WORKFLOWS: READY"
        echo "NATIVE_GOAL_RUNTIME: NOT_AVAILABLE optional; run '$MATERIALIZE_REPO/setup.sh --global' from a separate terminal to install protected native /goal support"
    fi
    echo "VERIFY_RUNTIME: '$MATERIALIZE_DIAGNOSTIC_TARGET/.forge/bin/verify-runtime' live --project-root '$MATERIALIZE_DIAGNOSTIC_TARGET'"
fi
