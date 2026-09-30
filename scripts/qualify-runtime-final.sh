#!/usr/bin/env bash
# Thin release-attestation wrapper over the existing dispatch and native-goal
# qualifiers. Live work is opt-in; fixture/inventory receipts never certify.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DISPATCH="$ROOT/scripts/qualify-dispatch-isolation.sh"
GOAL="$ROOT/scripts/qualify-goal-feasibility.sh"

usage() {
    echo "Usage: qualify-runtime-final.sh (--fixture-mode|--inventory|--live) --project-root DIR --output FILE [--engine-dir DIR] [--claude-goal-evidence FILE] [--codex-goal-evidence FILE] [--windows-attestation FILE] [--qualification-timeout-seconds N]" >&2
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
candidate_clean() { [ -z "$(git -C "$1" status --porcelain --untracked-files=all)" ]; }
write_blocked_child() {
    mkdir -p "$(dirname "$1")"
    printf '{"schema":"%s","status":"BLOCKED","reason":"%s","evidence_mode":"authenticated","source_class":"forge-runtime-qualifier"}\n' "$2" "$3" > "$1"
}
signal_qualification_tree() {
    local signal="$1" group="$2"
    kill "-$signal" -- "-$group" 2>/dev/null || true
}
run_qualification_child() {
    local seconds="$1" receipt="$2" schema="$3" child elapsed rc; shift 3
    python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1],sys.argv[1:])' "$@" >/dev/null 2>&1 & child=$!
    elapsed=0
    while kill -0 "$child" 2>/dev/null; do
        if [ "$elapsed" -ge "$((seconds * 10))" ]; then
            signal_qualification_tree TERM "$child"; sleep 0.2
            signal_qualification_tree KILL "$child"; wait "$child" 2>/dev/null || true
            write_blocked_child "$receipt" "$schema" 'qualification child timeout'
            return 124
        fi
        sleep 0.1; elapsed=$((elapsed + 1))
    done
    wait "$child"; rc=$?
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || write_blocked_child "$receipt" "$schema" 'qualification child exited without receipt'
    return "$rc"
}

validate_child() {
    local path="$1" schema="$2" status hash
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    hash=$(hash_file "$path"); [ "$hash" = "$3" ] || return 1
    [ "$(json_field "$path" schema)" = "$schema" ] || return 1
    status=$(json_field "$path" status); case "$status" in PASS|BLOCKED) ;; *) return 1 ;; esac
}

validate_receipt() {
    local input="$1" project candidate mode overall engine kind path sha bin bin_sha status head tree runtime
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
            else validate_child "$path" forge.goal-feasibility.v2 "$sha" || return 1
            fi
        done
        runtime=$(field "$input" "${engine}_native_goal_runtime")
        case "$runtime" in READY|BLOCKED|NOT_TESTED) ;; *) return 1 ;; esac
    done
    status=$(field "$input" windows_status); case "$status" in PASS|PENDING) ;; *) return 1 ;; esac
    if [ "$status" = PASS ]; then
        path=$(field "$input" windows_attestation_path); sha=$(field "$input" windows_attestation_sha256)
        [ -f "$path" ] && [ ! -L "$path" ] && [ "$(hash_file "$path")" = "$sha" ] || return 1
        [ "$(field "$path" format)" = forge-windows-deterministic-v1 ] \
          && [ "$(field "$path" powershell_major)" = 5 ] \
          && [ "$(field "$path" powershell_minor)" = 1 ] \
          && [ "$(field "$path" status)" = PASS ] \
          && [ "$(field "$path" candidate_clean)" = true ] \
          && [ "$(field "$path" git_head)" = "$head" ] \
          && [ "$(field "$path" tree_sha)" = "$tree" ] \
          && candidate_clean "$project" || return 1
    fi
    if [ "$overall" = PASS ]; then
        [ "$mode" = authenticated ] && [ "$status" = PASS ] || return 1
        for engine in claude codex; do
            [ "$(field "$input" "${engine}_native_goal_runtime")" = READY ] || return 1
            path=$(field "$input" "${engine}_dispatch_path")
            [ "$(json_field "$path" status)" = PASS ] || return 1
            path=$(field "$input" "${engine}_goal_path")
            [ "$(json_field "$path" status)" = PASS ] \
              && [ "$(json_field "$path" live_host)" = "$engine" ] \
              && [ "$(json_field "$path" live_status)" = READY ] || return 1
        done
    fi
    return 0
}

mode=""; project=""; output=""; input=""; engine_dir=""; windows=""; qualification_timeout=1200
claude_goal_evidence=""; codex_goal_evidence=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --fixture-mode) [ -z "$mode" ] || usage; mode=fixture; shift ;;
        --inventory) [ -z "$mode" ] || usage; mode=inventory; shift ;;
        --live) [ -z "$mode" ] || usage; mode=authenticated; shift ;;
        --validate) [ -z "$mode" ] || usage; mode=validate; shift ;;
        --project-root) project="$2"; shift 2 ;; --output) output="$2"; shift 2 ;;
        --input) input="$2"; shift 2 ;; --engine-dir) engine_dir="$2"; shift 2 ;;
        --claude-goal-evidence) claude_goal_evidence="$2"; shift 2 ;;
        --codex-goal-evidence) codex_goal_evidence="$2"; shift 2 ;;
        --windows-attestation) windows="$2"; shift 2 ;;
        --qualification-timeout-seconds) qualification_timeout="$2"; shift 2 ;;
        *) usage ;;
    esac
done
if [ "$mode" = validate ]; then [ -n "$input" ] || usage; validate_receipt "$input"; exit $?; fi
case "$mode" in fixture|inventory|authenticated) ;; *) usage ;; esac
case "$qualification_timeout" in ''|*[!0-9]*|0) usage ;; esac
[ -d "$project/.forge" ] && [ -n "$output" ] || usage
project=$(cd "$project" && pwd -P); output_dir=$(dirname "$output"); mkdir -p "$output_dir"
output=$(cd "$output_dir" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$output")")
bundle="$output.d"; [ ! -e "$bundle" ] || { echo "BLOCKED: output bundle already exists" >&2; exit 3; }; mkdir "$bundle"

candidate=$(candidate_hash "$project")
git_head=$(git -C "$project" rev-parse HEAD); tree_sha=$(git -C "$project" rev-parse 'HEAD^{tree}')
[ "$mode" != authenticated ] || export FORGE_LIVE_QUALIFICATION=1
for engine in claude codex; do
    bin=$(binary_path "$engine" "$engine_dir")
    dispatch_out="$bundle/$engine-dispatch.json"
    goal_dir="$bundle/$engine-goal-evidence"
    goal_out="$goal_dir/goal-qualification.json"
    mkdir -p "$goal_dir"
    if [ "$mode" = fixture ]; then
        [ -x "$bin" ] || { echo "BLOCKED: fixture engine missing: $engine" >&2; exit 3; }
        FORGE_FAKE_ENGINE_NAME="$engine" "$DISPATCH" --engine "$engine" --project-root "$project" --output "$dispatch_out" --fixture-mode --engine-path "$bin" >/dev/null 2>&1 || true
        if [ "$engine" = claude ]; then
            "$GOAL" --project "$project" --evidence-dir "$goal_dir" --live none >/dev/null 2>&1 || true
        else
            cp "$claude_goal" "$goal_out"
        fi
    else
        if [ "$mode" = authenticated ]; then
            dispatch_rc=0
            run_qualification_child "$qualification_timeout" "$dispatch_out" forge.dispatch-isolation.v1 \
                "$DISPATCH" --engine "$engine" --project-root "$project" --output "$dispatch_out" || dispatch_rc=$?
            if [ "$dispatch_rc" -eq 0 ]; then
                case "$engine" in
                    claude) goal_evidence=$claude_goal_evidence ;;
                    codex) goal_evidence=$codex_goal_evidence ;;
                esac
                goal_args=(--project "$project" --evidence-dir "$goal_dir" --live "$engine")
                [ -z "$goal_evidence" ] || goal_args+=(--live-evidence "$goal_evidence")
                run_qualification_child "$qualification_timeout" "$goal_out" forge.goal-feasibility.v2 \
                    "$GOAL" "${goal_args[@]}" || true
            else
                write_blocked_child "$goal_out" forge.goal-feasibility.v2 'dispatch-qualification-blocked'
            fi
        else
            "$DISPATCH" --engine "$engine" --project-root "$project" --output "$dispatch_out" >/dev/null 2>&1 || true
            if [ "$engine" = claude ]; then
                "$GOAL" --project "$project" --evidence-dir "$goal_dir" --live none >/dev/null 2>&1 || true
            else
                cp "$claude_goal" "$goal_out"
            fi
        fi
    fi
    eval "${engine}_bin=\$bin"
    eval "${engine}_dispatch=\$dispatch_out"
    eval "${engine}_goal=\$goal_out"
    goal_status=$(json_field "$goal_out" status 2>/dev/null || true)
    goal_live_status=$(json_field "$goal_out" live_status 2>/dev/null || true)
    if [ "$mode" != authenticated ]; then runtime=NOT_TESTED
    elif [ "$goal_status" = PASS ] && [ "$goal_live_status" = READY ]; then runtime=READY
    else runtime=BLOCKED
    fi
    eval "${engine}_native_goal_runtime=\$runtime"
done

windows_status=PENDING; windows_path=none; windows_sha=none
if [ -n "$windows" ] && [ -f "$windows" ] && [ ! -L "$windows" ] \
   && [ "$(field "$windows" format)" = forge-windows-deterministic-v1 ] \
   && [ "$(field "$windows" powershell_major)" = 5 ] \
   && [ "$(field "$windows" powershell_minor)" = 1 ] \
   && [ "$(field "$windows" status)" = PASS ] \
   && [ "$(field "$windows" candidate_clean)" = true ] \
   && [ "$(field "$windows" git_head)" = "$git_head" ] \
   && [ "$(field "$windows" tree_sha)" = "$tree_sha" ] \
   && candidate_clean "$project"; then
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
        eval "runtime=\$${engine}_native_goal_runtime"
        printf '%s_native_goal_runtime=%s\n' "$engine" "$runtime"
    done
    printf 'windows_status=%s\nwindows_attestation_path=%s\nwindows_attestation_sha256=%s\noverall_status=%s\n' "$windows_status" "$windows_path" "$windows_sha" "$overall"
} > "$output"
validate_receipt "$output" || { echo "BLOCKED: generated final attestation failed schema validation" >&2; exit 4; }
cat "$output"
for engine in claude codex; do
    eval "runtime=\$${engine}_native_goal_runtime"
    eval "goal_out=\$${engine}_goal"
    if [ "$runtime" = READY ]; then
        echo "NATIVE_GOAL_RUNTIME: READY host=$engine evidence=$goal_out"
    elif [ "$mode" = authenticated ]; then
        echo "NATIVE_GOAL_RUNTIME: BLOCKED host=$engine reason=$(json_field "$goal_out" reason 2>/dev/null || printf unavailable)"
    fi
done
[ "$overall" = PASS ]
