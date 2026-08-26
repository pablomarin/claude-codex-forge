#!/usr/bin/env bash
# Deterministic identity/discovery checks plus an explicitly opt-in live sentinel.
set -e

json_escape_runtime() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

identity_mode() {
    local host="" fixture="" invocation_hash="" requested_model="" model provider
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host) host="$2"; shift 2 ;;
            --fixture) fixture="$2"; shift 2 ;;
            --invocation-hash) invocation_hash="$2"; shift 2 ;;
            --requested-model) requested_model="$2"; shift 2 ;;
            *) echo "unknown identity option: $1" >&2; return 2 ;;
        esac
    done
    [ -f "$fixture" ] && [ -n "$invocation_hash" ] || return 2
    case "$host" in
        claude)
            case "$requested_model" in ""|opus|claude-opus-4-1) ;; *) echo "BLOCKED: unsupported Claude model profile" >&2; return 3 ;; esac
            model=$(sed -nE '/"modelUsage"/{n; s/^[[:space:]]*"([^"]+)".*/\1/p;}' "$fixture" | head -1)
            provider=$(sed -nE 's/^[[:space:]]*"provider":[[:space:]]*"([^"]+)".*/\1/p' "$fixture" | head -1)
            [ -n "$model" ] && [ -n "$provider" ] || { echo "BLOCKED: Claude fixture lacks observable modelUsage identity" >&2; return 4; }
            printf '{"host":"claude","actual_provider":"%s","actual_model":"%s","invocation_hash":"%s"}\n' \
                "$(json_escape_runtime "$provider")" "$(json_escape_runtime "$model")" "$(json_escape_runtime "$invocation_hash")"
            ;;
        codex)
            case "$requested_model" in ""|gpt-5.6-sol) ;; *) echo "BLOCKED: unsupported Codex model profile" >&2; return 3 ;; esac
            grep -q '"type":"thread.started"' "$fixture" || { echo "BLOCKED: Codex fixture lacks thread.started" >&2; return 4; }
            # Current structured output exposes no provider/model/effort. Bind
            # only the explicit invocation hash; never synthesize actual_*.
            printf '{"host":"codex","invocation_hash":"%s"}\n' "$(json_escape_runtime "$invocation_hash")"
            ;;
        *) return 2 ;;
    esac
}

discovery_mode() {
    local root="" count duplicates relative base seen_file
    while [ "$#" -gt 0 ]; do
        case "$1" in --project-root) root="$2"; shift 2 ;; *) return 2 ;; esac
    done
    [ -d "$root/.forge/rules" ] && [ -f "$root/CLAUDE.md" ] && [ -f "$root/AGENTS.md" ] || return 3
    grep -qF '.forge/instructions.md' "$root/CLAUDE.md" || return 4
    grep -qF '.forge/instructions.md' "$root/AGENTS.md" || return 4
    count=$(find "$root/.forge/rules" -type f -name '*.md' | wc -l | tr -d ' ')
    seen_file=$(mktemp "${TMPDIR:-/tmp}/forge-rules.XXXXXX")
    # Host adapters import .forge/rules; adapter skills and workflows may share
    # filenames without duplicating rule policy. Count only discoverable rule
    # policy locations here.
    find "$root/.forge/rules" "$root/.claude/rules" -type f -name '*.md' 2>/dev/null \
        | while IFS= read -r relative; do basename "$relative"; done | sort | uniq -d > "$seen_file"
    duplicates=$(wc -l < "$seen_file" | tr -d ' ')
    rm -f "$seen_file"
    printf 'canonical_rule_count=%s\nduplicate_rule_count=%s\n' "$count" "$duplicates"
    [ "$duplicates" = 0 ]
}

live_mode() {
    local root="" host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in --project-root) root="$2"; shift 2 ;; --host) host="$2"; shift 2 ;; *) return 2 ;; esac
    done
    [ "${FORGE_LIVE_QUALIFICATION:-0}" = 1 ] || {
        echo "BLOCKED: live runtime qualification requires FORGE_LIVE_QUALIFICATION=1"
        return 10
    }
    command -v "$host" >/dev/null 2>&1 || { echo "BLOCKED: $host binary unavailable"; return 11; }
    [ -d "$root/.forge" ] || { echo "BLOCKED: materialized project missing"; return 12; }
    echo "BLOCKED: host-specific authenticated sentinel is owned by qualify-dispatch-isolation; inventory alone is not RUNTIME_READY"
    return 13
}

mode="${1:-}"
[ "$#" -gt 0 ] && shift
case "$mode" in
    identity) identity_mode "$@" ;;
    discovery) discovery_mode "$@" ;;
    live) live_mode "$@" ;;
    *) echo "Usage: verify-runtime.sh identity|discovery|live ..." >&2; exit 2 ;;
esac
