#!/usr/bin/env bash
# Thin release-attestation wrapper over the existing dispatch and native-goal
# qualifiers. Live work is opt-in; fixture/inventory receipts never certify.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DISPATCH="$ROOT/scripts/qualify-dispatch-isolation.sh"
GOAL="$ROOT/scripts/qualify-goal-feasibility.sh"

usage() {
    echo "Usage: qualify-runtime-final.sh (--fixture-mode|--inventory|--live) --project-root DIR --output FILE [--engine-dir DIR] [--claude-goal-authorization FILE] [--codex-goal-capture FILE] [--windows-attestation FILE]" >&2
    echo "       qualify-runtime-final.sh --validate --input FILE" >&2
    exit 2
}
hash_file() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
hash_stream() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
physical_file() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
resolve_file() {
    local path="$1" target
    case "$path" in /*) ;; *) path=$(physical_file "$path") ;; esac
    while [ -L "$path" ]; do target=$(readlink "$path") || return 1; case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac; done
    physical_file "$path"
}
field() { sed -n "s/^$2=//p" "$1" | head -1; }
json_field() {
    python3 - "$1" "$2" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], "")
except Exception:
    raise SystemExit(2)
print(value if isinstance(value, (str, int, float)) else "")
PY
}
candidate_hash() {
    local root="$1" common file
    common=$(git -C "$root" rev-parse --git-common-dir); case "$common" in /*) ;; *) common="$root/$common" ;; esac
    common=$(cd "$common" && pwd -P)
    {
        printf 'forge-runtime-candidate-v1\nroot=%s\ncommon=%s\n' "$(cd "$root" && pwd -P)" "$common"
        git -C "$root" rev-parse HEAD
        git -C "$root" status --porcelain=v2 --untracked-files=all
        git -C "$root" diff --binary HEAD
        find "$root" -type f ! -path "$root/.git/*" ! -path "$root/.forge/local/*" -print | LC_ALL=C sort | while IFS= read -r file; do
            printf '%s\t%s\n' "${file#$root/}" "$(hash_file "$file")"
        done
    } | hash_stream
}
binary_path() { local path; if [ -n "$2" ]; then path="$(cd "$2" && pwd -P)/$1"; else path=$(command -v "$1" 2>/dev/null || true); fi; [ -z "$path" ] || resolve_file "$path"; }

validate_child() {
    local path="$1" schema="$2" status hash
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    hash=$(hash_file "$path"); [ "$hash" = "$3" ] || return 1
    [ "$(json_field "$path" schema)" = "$schema" ] || return 1
    status=$(json_field "$path" status); case "$status" in PASS|BLOCKED) ;; *) return 1 ;; esac
}

validate_receipt() {
    local input="$1" project candidate mode overall engine kind path sha bin bin_sha status reason head tree
    [ -f "$input" ] && [ ! -L "$input" ] || return 1
    [ "$(field "$input" format)" = forge-runtime-final-v1 ] || return 1
    [ "$(field "$input" source_class)" = forge-runtime-qualifier ] || return 1
    mode=$(field "$input" evidence_mode); case "$mode" in fixture|inventory|authenticated) ;; *) return 1 ;; esac
    project=$(field "$input" project_root); [ -d "$project/.forge" ] || return 1
    [ "$(cd "$project" && pwd -P)" = "$project" ] || return 1
    candidate=$(field "$input" candidate_sha256); [ "$candidate" = "$(candidate_hash "$project")" ] || return 1
    head=$(git -C "$project" rev-parse HEAD); tree=$(git -C "$project" rev-parse 'HEAD^{tree}')
    [ "$(field "$input" git_head)" = "$head" ] && [ "$(field "$input" tree_sha)" = "$tree" ] || return 1
    overall=$(field "$input" overall_status); case "$overall" in PASS|BLOCKED) ;; *) return 1 ;; esac
    for engine in claude codex; do
        bin=$(field "$input" "${engine}_binary_path")
        bin_sha=$(field "$input" "${engine}_binary_sha256")
        if [ "$bin" = none ]; then [ "$bin_sha" = none ] || return 1; else [ -f "$bin" ] && [ ! -L "$bin" ] && [ "$(hash_file "$bin")" = "$bin_sha" ] || return 1; fi
        for kind in dispatch goal; do
            path=$(field "$input" "${engine}_${kind}_path")
            sha=$(field "$input" "${engine}_${kind}_sha256")
            if [ "$kind" = dispatch ]; then validate_child "$path" forge.dispatch-isolation.v1 "$sha" || return 1
            else validate_child "$path" forge.goal-feasibility.v1 "$sha" || return 1
            fi
        done
    done
    if [ "$overall" = PASS ]; then
        [ "$mode" = authenticated ] && [ "$(field "$input" windows_status)" = PASS ] || return 1
        for engine in claude codex; do
            for kind in dispatch goal; do
                path=$(field "$input" "${engine}_${kind}_path")
                [ "$(json_field "$path" status)" = PASS ] || return 1
                reason=$(json_field "$path" reason)
                case "$engine:$kind:$reason" in
                    'claude:dispatch:authenticated guarded isolation, exact-id resume, and frozen-candidate replay passed'|\
                    'codex:dispatch:authenticated guarded isolation, exact-id resume, and frozen-candidate replay passed'|\
                    'claude:goal:authenticated Claude native /goal activation, exact resume, budget pause, and stuck oracle passed'|\
                    'codex:goal:validated sealed physical operator Codex TUI capture') ;;
                    *) return 1 ;;
                esac
            done
        done
        path=$(field "$input" codex_goal_capture_path); sha=$(field "$input" codex_goal_capture_sha256)
        [ -f "$path" ] && [ ! -L "$path" ] && [ "$(hash_file "$path")" = "$sha" ] || return 1
        path=$(field "$input" windows_attestation_path); sha=$(field "$input" windows_attestation_sha256)
        [ -f "$path" ] && [ ! -L "$path" ] && [ "$(hash_file "$path")" = "$sha" ] || return 1
        [ "$(field "$path" format)" = forge-windows-deterministic-v1 ] \
          && [ "$(field "$path" powershell_major)" = 5 ] \
          && [ "$(field "$path" powershell_minor)" = 1 ] \
          && [ "$(field "$path" status)" = PASS ] \
          && [ "$(field "$path" git_head)" = "$head" ] \
          && [ "$(field "$path" tree_sha)" = "$tree" ] || return 1
    fi
    return 0
}

mode=""; project=""; output=""; input=""; engine_dir=""; claude_auth=""; codex_capture=""; windows=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --fixture-mode) [ -z "$mode" ] || usage; mode=fixture; shift ;;
        --inventory) [ -z "$mode" ] || usage; mode=inventory; shift ;;
        --live) [ -z "$mode" ] || usage; mode=authenticated; shift ;;
        --validate) [ -z "$mode" ] || usage; mode=validate; shift ;;
        --project-root) project="$2"; shift 2 ;; --output) output="$2"; shift 2 ;;
        --input) input="$2"; shift 2 ;; --engine-dir) engine_dir="$2"; shift 2 ;;
        --claude-goal-authorization) claude_auth="$2"; shift 2 ;;
        --codex-goal-capture) codex_capture="$2"; shift 2 ;;
        --windows-attestation) windows="$2"; shift 2 ;;
        *) usage ;;
    esac
done
if [ "$mode" = validate ]; then [ -n "$input" ] || usage; validate_receipt "$input"; exit $?; fi
case "$mode" in fixture|inventory|authenticated) ;; *) usage ;; esac
[ -d "$project/.forge" ] && [ -n "$output" ] || usage
project=$(cd "$project" && pwd -P); output_dir=$(dirname "$output"); mkdir -p "$output_dir"
output=$(cd "$output_dir" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$output")")
bundle="$output.d"; [ ! -e "$bundle" ] || { echo "BLOCKED: output bundle already exists" >&2; exit 3; }; mkdir "$bundle"

candidate=$(candidate_hash "$project")
git_head=$(git -C "$project" rev-parse HEAD); tree_sha=$(git -C "$project" rev-parse 'HEAD^{tree}')
for engine in claude codex; do
    bin=$(binary_path "$engine" "$engine_dir")
    dispatch_out="$bundle/$engine-dispatch.json"; goal_out="$bundle/$engine-goal.json"
    if [ "$mode" = fixture ]; then
        [ -x "$bin" ] || { echo "BLOCKED: fixture engine missing: $engine" >&2; exit 3; }
        FORGE_FAKE_ENGINE_NAME="$engine" "$DISPATCH" --engine "$engine" --project-root "$project" --output "$dispatch_out" --fixture-mode --engine-path "$bin" >/dev/null 2>&1 || true
        FORGE_FAKE_ENGINE_NAME="$engine" "$GOAL" --engine "$engine" --project-root "$project" --output "$goal_out" --fixture-mode --engine-path "$bin" >/dev/null 2>&1 || true
    else
        if [ "$mode" = authenticated ]; then export FORGE_LIVE_QUALIFICATION=1; else unset FORGE_LIVE_QUALIFICATION 2>/dev/null || true; fi
        "$DISPATCH" --engine "$engine" --project-root "$project" --output "$dispatch_out" >/dev/null 2>&1 || true
        if [ "$engine" = claude ] && [ -n "$claude_auth" ]; then
            "$GOAL" --engine claude --project-root "$project" --output "$goal_out" --authorization "$claude_auth" >/dev/null 2>&1 || true
        elif [ "$engine" = codex ] && [ -n "$codex_capture" ]; then
            "$GOAL" --engine codex --project-root "$project" --output "$goal_out" --trusted-capture "$codex_capture" >/dev/null 2>&1 || true
        else
            "$GOAL" --engine "$engine" --project-root "$project" --output "$goal_out" >/dev/null 2>&1 || true
        fi
    fi
    eval "${engine}_bin=\$bin"
    eval "${engine}_dispatch=\$dispatch_out"
    eval "${engine}_goal=\$goal_out"
done

windows_status=PENDING; windows_path=none; windows_sha=none
if [ -n "$windows" ] && [ -f "$windows" ] && [ ! -L "$windows" ] \
   && [ "$(field "$windows" format)" = forge-windows-deterministic-v1 ] \
   && [ "$(field "$windows" powershell_major)" = 5 ] \
   && [ "$(field "$windows" powershell_minor)" = 1 ] \
   && [ "$(field "$windows" status)" = PASS ] \
   && [ "$(field "$windows" git_head)" = "$git_head" ] \
   && [ "$(field "$windows" tree_sha)" = "$tree_sha" ]; then
    windows_status=PASS; windows_path=$(physical_file "$windows"); windows_sha=$(hash_file "$windows")
fi
overall=BLOCKED
if [ "$mode" = authenticated ] && [ "$windows_status" = PASS ]; then
    ready=true
    for child in "$claude_dispatch" "$claude_goal" "$codex_dispatch" "$codex_goal"; do
        [ -f "$child" ] && [ "$(json_field "$child" status 2>/dev/null || true)" = PASS ] || ready=false
    done
    [ "$ready" = false ] || overall=PASS
fi

{
    printf 'format=forge-runtime-final-v1\nsource_class=forge-runtime-qualifier\nevidence_mode=%s\n' "$mode"
    printf 'project_root=%s\ncandidate_sha256=%s\ngit_head=%s\ntree_sha=%s\n' "$project" "$candidate" "$git_head" "$tree_sha"
    for engine in claude codex; do
        eval "bin=\$${engine}_bin"; if [ -n "$bin" ] && [ -f "$bin" ]; then bin=$(physical_file "$bin"); bin_sha=$(hash_file "$bin"); else bin=none; bin_sha=none; fi
        eval "dispatch_out=\$${engine}_dispatch"; eval "goal_out=\$${engine}_goal"
        printf '%s_binary_path=%s\n%s_binary_sha256=%s\n' "$engine" "$bin" "$engine" "$bin_sha"
        printf '%s_dispatch_path=%s\n%s_dispatch_sha256=%s\n' "$engine" "$dispatch_out" "$engine" "$(hash_file "$dispatch_out")"
        printf '%s_goal_path=%s\n%s_goal_sha256=%s\n' "$engine" "$goal_out" "$engine" "$(hash_file "$goal_out")"
    done
    if [ -n "$codex_capture" ] && [ -f "$codex_capture" ]; then printf 'codex_goal_capture_path=%s\ncodex_goal_capture_sha256=%s\n' "$(physical_file "$codex_capture")" "$(hash_file "$codex_capture")"; else printf 'codex_goal_capture_path=none\ncodex_goal_capture_sha256=none\n'; fi
    printf 'windows_status=%s\nwindows_attestation_path=%s\nwindows_attestation_sha256=%s\noverall_status=%s\n' "$windows_status" "$windows_path" "$windows_sha" "$overall"
} > "$output"
validate_receipt "$output" || { echo "BLOCKED: generated final attestation failed schema validation" >&2; exit 4; }
cat "$output"
[ "$overall" = PASS ]
