#!/usr/bin/env bash
# Qualify repository-local native Goal accounting. Deterministic qualification
# never calls an engine; live qualification is explicit and authenticated by the
# native client itself.
set -eu

usage() {
    echo "Usage: qualify-goal-feasibility.sh --project DIR --evidence-dir DIR --live none|claude|codex [--live-evidence FILE]" >&2
    exit 2
}

hash_file() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'
    fi
}

hash_text() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else sha256sum | awk '{print $1}'
    fi
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

physical_dir() { (cd "$1" && pwd -P); }
evidence_field() {
    local file="$1" key="$2" count
    count=$(awk -F= -v k="$key" '$1==k{n++} END{print n+0}' "$file")
    [ "$count" -eq 1 ] || return 1
    awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$file"
}

project=""
evidence_dir=""
live=""
live_evidence=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) [ "$#" -ge 2 ] || usage; project="$2"; shift 2 ;;
        --evidence-dir) [ "$#" -ge 2 ] || usage; evidence_dir="$2"; shift 2 ;;
        --live) [ "$#" -ge 2 ] || usage; live="$2"; shift 2 ;;
        --live-evidence) [ "$#" -ge 2 ] || usage; live_evidence="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$live" in none|claude|codex) ;; *) usage ;; esac
[ "$live" != none ] || [ -z "$live_evidence" ] || usage
[ -n "$project" ] && [ -d "$project/.forge" ] && [ ! -L "$project" ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=materialized-project-required" >&2
    exit 3
}
project=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null) || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=git-project-required" >&2
    exit 3
}
project=$(physical_dir "$project")

case "$evidence_dir" in
    "") usage ;;
    /*) ;;
    *) evidence_dir="$project/$evidence_dir" ;;
esac
mkdir -p "$evidence_dir"
[ -d "$evidence_dir" ] && [ ! -L "$evidence_dir" ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=evidence-directory-invalid" >&2
    exit 3
}
evidence_dir=$(physical_dir "$evidence_dir")

self_dir=$(cd "$(dirname "$0")" && pwd -P)
case "$self_dir" in
    */.forge/bin) ledger="${self_dir%/.forge/bin}/.forge/hooks/lib/goal-ledger.sh" ;;
    *) ledger="$(cd "$self_dir/.." && pwd -P)/hooks/lib/goal-ledger.sh" ;;
esac
[ -f "$ledger" ] && [ ! -L "$ledger" ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=repository-ledger-helper-missing" >&2
    exit 3
}

nonce=11111111-1111-4111-8111-111111111111
activation=22222222-2222-4222-8222-222222222222
objective=$(printf '%s' 'forge-project-only-goal-qualification-v1' | hash_text)
run_dir="$evidence_dir/deterministic-$(date -u +%Y%m%dT%H%M%SZ)-$$"
primary="$run_dir/project"
linked="$run_dir/linked"
mkdir -p "$primary"
git -C "$primary" init -q
git -C "$primary" config user.email forge@example.invalid
git -C "$primary" config user.name Forge
printf 'qualification\n' > "$primary/app.txt"
git -C "$primary" add app.txt
git -C "$primary" commit -qm base
git -C "$primary" branch linked
git -C "$primary" worktree add -q "$linked" linked

write_state() {
    root="$1"
    count="$2"
    mkdir -p "$root/.forge/local"
    cat > "$root/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
# Goal qualification

## Workflow

| Field | Value |
| --- | --- |
| Command | /new-feature project-only-goal-qualification |
| Phase | verification |
| Next step | verify deterministic Goal accounting |

## /goal session

| Field | Value |
| --- | --- |
| nonce | $nonce |
| objective_hash | $objective |
| activation_id | $activation |
| activation_host | claude |
| activated_at | 2026-09-29T00:00:00Z |
| workflow_command | /new-feature project-only-goal-qualification |
| turn_count | $count |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/goal-qualification.json |
EOF
}

charge() {
    root="$1"
    turn="$2"
    printf '{"host":"claude","session_id":"qualification","turn_id":"q%s"}' "$turn" |
        bash "$ledger" charge --project "$root" --state "$root/.forge/local/state.md" --event-json -
}

write_state "$primary" 0
write_state "$linked" 0
bash "$ledger" activate --project "$primary" --state "$primary/.forge/local/state.md"
charge "$primary" 1
charge "$linked" 1
n=2
while [ "$n" -le 20 ]; do
    write_state "$primary" "$((n - 1))"
    charge "$primary" "$n" >/dev/null 2>&1
    n=$((n + 1))
done

common_raw=$(git -C "$primary" rev-parse --git-common-dir)
case "$common_raw" in /*) ;; *) common_raw="$primary/$common_raw" ;; esac
common=$(physical_dir "$common_raw")
goal_root="$common/forge-goals/$nonce"
turn_count=$(find "$goal_root/turns" -mindepth 1 -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' | wc -l | tr -d ' ')
[ "$turn_count" = 20 ] && [ -f "$goal_root/checkpoint" ] && [ -f "$goal_root/exhausted" ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=ledger-ceiling-or-checkpoint-failed" >&2
    exit 4
}
[ "$(find "$goal_root/activations" -type f -name '00000001' | wc -l | tr -d ' ')" = 1 ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=linked-worktree-activation-binding-failed" >&2
    exit 4
}

stop_hook="$(dirname "$(dirname "$ledger")")/check-state-updated.sh"
[ -f "$stop_hook" ] || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=stop-hook-missing" >&2
    exit 4
}
write_state "$primary" 20
printf '%064d\n' 0 > "$primary/.forge/local/forge-goal-last-fingerprint"
stuck_log="$run_dir/stuck-warning.log"
: > "$stuck_log"
n=1
while [ "$n" -le 5 ]; do
    printf '{"cwd":"%s","host":"claude","stop_hook_active":true}' "$primary" |
        bash "$stop_hook" >> "$stuck_log" 2>&1
    n=$((n + 1))
done
grep -qF FORGE_GOAL_STUCK_WARNING "$stuck_log" || {
    echo "GOAL_DETERMINISTIC: BLOCKED reason=stuck-warning-failed" >&2
    exit 4
}

binding_sha=$(hash_file "$goal_root/binding")
checkpoint_sha=$(hash_file "$goal_root/checkpoint")
receipt="$evidence_dir/goal-qualification.json"
status=PASS
live_status=NOT_REQUESTED
reason=deterministic-project-ledger-pass
engine_path=""
engine_version=""
live_output_sha=""
operator_evidence_path=""

if [ "$live" != none ]; then
    engine_path=$(command -v "$live" 2>/dev/null || true)
    if [ -z "$engine_path" ]; then
        status=BLOCKED
        live_status=BLOCKED
        reason=binary-unavailable
    else
        engine_version=$($engine_path --version 2>/dev/null | head -1 || true)
        if [ -z "$live_evidence" ]; then
            status=BLOCKED
            live_status=BLOCKED
            reason=interactive-native-goal-evidence-required
        elif [ ! -f "$live_evidence" ] || [ -L "$live_evidence" ]; then
            status=BLOCKED
            live_status=BLOCKED
            reason=operator-evidence-invalid
        else
            operator_evidence_path=$(cd "$(dirname "$live_evidence")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$live_evidence")")
            evidence_head=$(git -C "$project" rev-parse HEAD)
            evidence_tree=$(git -C "$project" rev-parse 'HEAD^{tree}')
            if [ "$(evidence_field "$operator_evidence_path" schema 2>/dev/null || true)" = forge.native-goal-operator-evidence.v1 ] \
                && [ "$(evidence_field "$operator_evidence_path" evidence_mode 2>/dev/null || true)" = operator-observed ] \
                && [ "$(evidence_field "$operator_evidence_path" result 2>/dev/null || true)" = PASS ] \
                && [ "$(evidence_field "$operator_evidence_path" host 2>/dev/null || true)" = "$live" ] \
                && [ "$(evidence_field "$operator_evidence_path" project_root 2>/dev/null || true)" = "$project" ] \
                && [ "$(evidence_field "$operator_evidence_path" git_head 2>/dev/null || true)" = "$evidence_head" ] \
                && [ "$(evidence_field "$operator_evidence_path" tree_sha 2>/dev/null || true)" = "$evidence_tree" ] \
                && [ "$(evidence_field "$operator_evidence_path" activation_observed 2>/dev/null || true)" = true ] \
                && [ "$(evidence_field "$operator_evidence_path" progress_observed 2>/dev/null || true)" = true ] \
                && [ "$(evidence_field "$operator_evidence_path" stop_observed 2>/dev/null || true)" = true ]; then
                live_status=READY
                reason=operator-observed-native-goal-pass
                live_output_sha=$(hash_file "$operator_evidence_path")
            else
                status=BLOCKED
                live_status=BLOCKED
                reason=operator-evidence-invalid
            fi
        fi
    fi
fi

cat > "$receipt" <<EOF
{"schema":"forge.goal-feasibility.v2","status":"$status","project":"$(json_escape "$project")","objective_hash":"$objective","deterministic":"PASS","global_harness":"NOT_REQUIRED","live_host":"$live","live_status":"$live_status","reason":"$reason","engine_path":"$(json_escape "$engine_path")","engine_version":"$(json_escape "$engine_version")","operator_evidence_path":"$(json_escape "$operator_evidence_path")","ledger_binding_sha256":"$binding_sha","checkpoint_sha256":"$checkpoint_sha","live_output_sha256":"$live_output_sha"}
EOF

echo "GOAL_DETERMINISTIC: PASS evidence=$receipt"
echo "GLOBAL_HARNESS: NOT_REQUIRED"
if [ "$live" != none ]; then
    if [ "$live_status" = READY ]; then
        echo "GOAL_LIVE: READY host=$live evidence=$receipt"
    else
        echo "GOAL_LIVE: BLOCKED host=$live reason=$reason evidence=$receipt"
    fi
fi
[ "$status" = PASS ]
