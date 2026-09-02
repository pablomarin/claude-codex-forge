#!/usr/bin/env bash
# Canonical Forge workflow-state resolver. Source this file, then call:
#   forge_state_path <repository-root> read|write

forge_state_v6_valid() {
    local path="$1"
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    awk '
        { sub(/\r$/, "") }
        NR==1 { if ($0!="<!-- forge:state-schema v6 -->") bad=1 }
        /^## Workflow$/ {
            workflow_count++
            section="workflow"; next
        }
        /^## / { section="other"; next }
        section=="workflow" && /^\|/ {
            split($0, cell, "|"); key=cell[2]
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key=="Command") command_count++
            else if (key=="Phase") phase_count++
            else if (key=="Next step") next_count++
        }
        END {
            if (bad || workflow_count!=1 || command_count!=1 || phase_count>1 || next_count>1) exit 1
        }
    ' "$path" >/dev/null
}

forge_state_path() {
    local requested_root="${1:-.}" mode="${2:-read}" root version canonical legacy candidate version_present
    root=$(cd "$requested_root" 2>/dev/null && pwd -P) || {
        echo "BLOCKED: invalid Forge state root: $requested_root" >&2
        return 1
    }
    canonical="$root/.forge/local/state.md"
    legacy="$root/.claude/local/state.md"

    for candidate in "$root/.forge" "$root/.forge/local" "$canonical"; do
        if [ -L "$candidate" ]; then
            echo "BLOCKED: symlink Forge state path: $candidate" >&2
            return 1
        fi
    done

    case "$mode" in
        write)
            printf '%s\n' "$canonical"
            return 0
            ;;
        read) ;;
        *)
            echo "BLOCKED: invalid forge_state_path mode: $mode" >&2
            return 1
            ;;
    esac

    version=""
    version_present=false
    if [ -e "$root/.forge/version" ] || [ -L "$root/.forge/version" ]; then
        version_present=true
        if [ ! -f "$root/.forge/version" ] || [ -L "$root/.forge/version" ]; then
            echo "BLOCKED: invalid Forge v6 state at $canonical" >&2
            return 1
        fi
        version=$(head -1 "$root/.forge/version" 2>/dev/null | tr -d '[:space:]')
    fi

    # Once a canonical surface or v6 stamp exists, an invalid/missing canonical
    # state is an error. Falling back here could resurrect stale v5 goal/review
    # authorization evidence after migration.
    if [ -e "$canonical" ] || [ "$version_present" = true ]; then
        if { [ "$version_present" = true ] && [ "$version" != 6 ]; } \
            || ! forge_state_v6_valid "$canonical"; then
            echo "BLOCKED: invalid Forge v6 state at $canonical" >&2
            return 1
        fi
        printf '%s\n' "$canonical"
        return 0
    fi

    # The compatibility read exists only before migration. Never follow a
    # symlink and never return v5 state beside a non-v6 Forge stamp.
    if [ -f "$legacy" ] && [ ! -L "$legacy" ]; then
        for candidate in "$root/.claude" "$root/.claude/local"; do
            if [ -L "$candidate" ]; then
                echo "BLOCKED: symlink legacy state path: $candidate" >&2
                return 1
            fi
        done
        printf '%s\n' "$legacy"
        return 0
    fi
    return 1
}
