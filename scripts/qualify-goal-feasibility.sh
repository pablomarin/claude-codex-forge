#!/usr/bin/env bash
# Opt-in native /goal feasibility attestation. Deterministic fixture/driver
# modes never authenticate and cannot certify the Codex native TUI row.
set -eu

usage() {
    echo "Usage: qualify-goal-feasibility.sh --engine claude|codex --project-root DIR --output FILE [--fixture-mode | --test-live-driver --engine-path FILE --authorization FILE | --trusted-capture FILE]" >&2
    exit 2
}
json_escape_goal() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'; }
hash_goal_file() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
hash_goal_text() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'; else printf '%s' "$1" | sha256sum | awk '{print $1}'; fi; }
receipt_goal_value() { sed -n "s/^$2=//p" "$1" | head -1; }
physical_goal_file() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
resolve_goal_cli() {
    local path="$1" target
    case "$path" in /*) ;; *) path=$(physical_goal_file "$path") ;; esac
    while [ -L "$path" ]; do target=$(readlink "$path") || return 1; case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac; done
    physical_goal_file "$path"
}
hash_goal_capability() {
    local binary="$1" root_help exec_help flag state
    root_help=$($binary --help 2>&1 || true); exec_help=$($binary exec --help 2>&1 || true)
    if command -v shasum >/dev/null 2>&1; then { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | shasum -a 256 | awk '{print $1}'; else { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | sha256sum | awk '{print $1}'; fi
}

engine=""; project_root=""; output=""; fixture_mode=false; test_live_driver=false; engine_path=""; trusted_capture=""; authorization=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --engine) engine="$2"; shift 2 ;;
        --project-root) project_root="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        --fixture-mode) fixture_mode=true; shift ;;
        --test-live-driver) test_live_driver=true; shift ;;
        --engine-path) engine_path="$2"; shift 2 ;;
        --trusted-capture) trusted_capture="$2"; shift 2 ;;
        --authorization) authorization="$2"; shift 2 ;;
        --manual-receipt) echo "BLOCKED: workspace/manual receipts are retired; use the sealed operator capture helper" >&2; exit 2 ;;
        *) usage ;;
    esac
done
case "$engine" in claude|codex) ;; *) usage ;; esac
[ -d "$project_root/.forge" ] || { echo "BLOCKED: materialized project is required" >&2; exit 3; }
[ -n "$output" ] || usage
project_root=$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null) || { echo "BLOCKED: project is not a Git worktree" >&2; exit 3; }
project_root=$(cd "$project_root" && pwd -P)
mkdir -p "$(dirname "$output")"

goal_project_identity() {
    local common identity
    common=$(git -C "$project_root" rev-parse --git-common-dir); case "$common" in /*) ;; *) common="$project_root/$common" ;; esac; common=$(cd "$common" && pwd -P)
    if command -v shasum >/dev/null 2>&1; then identity=$(printf '%s\n%s\n' "$project_root" "$common" | shasum -a 256 | awk '{print $1}'); else identity=$(printf '%s\n%s\n' "$project_root" "$common" | sha256sum | awk '{print $1}'); fi
    printf '%s\t%s\t%s\n' "$project_root" "$common" "$identity"
}
goal_identity=$(goal_project_identity); goal_common=$(printf '%s' "$goal_identity" | cut -f2); project_id=$(printf '%s' "$goal_identity" | cut -f3)

regular_external_file() {
    local file="$1" root="$2" physical
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    physical=$(cd "$(dirname "$file")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$file")")
    case "$physical" in "$root/"*) ;; *) return 1 ;; esac
    case "$physical" in "$project_root/"*|"$goal_common/"*) return 1 ;; esac
}

validate_authorization() {
    local receipt="$1" root expected_writer_revision
    root="${HOME:-}/.forge/goal-authorizations"
    [ -d "$root" ] && [ ! -L "$root" ] && regular_external_file "$receipt" "$root" || return 1
    [ "$(receipt_goal_value "$receipt" format)" = forge-goal-authorization-v1 ] || return 1
    [ "$(receipt_goal_value "$receipt" project_root)" = "$project_root" ] \
        && [ "$(receipt_goal_value "$receipt" git_common_dir)" = "$goal_common" ] \
        && [ "$(receipt_goal_value "$receipt" project_id)" = "$project_id" ] || return 1
    [ "$(receipt_goal_value "$receipt" approval_channel)" = physical-operator-action ] || return 1
    case "$(receipt_goal_value "$receipt" nonce)" in ????????-????-4???-[89abAB]???-????????????) ;; *) return 1 ;; esac
    case "$(receipt_goal_value "$receipt" ceiling)" in ""|*[!0-9]*|0) return 1 ;; esac
    expected_writer_revision=$(sed -n "s/^WRITER_REVISION='\([^']*\)'.*/\1/p" "${HOME:-}/.forge/bin/forge-goal-authorize" | head -1)
    [ -n "$expected_writer_revision" ] && [ "$(receipt_goal_value "$receipt" writer_revision)" = "$expected_writer_revision" ]
}

validate_trusted_capture() {
    local receipt="$1" root transcript result session_dir capture_revision writer_revision cli_path cli_version actual_version
    local identity identity_seal identity_hash invocation_path cli_sha capability_revision actual_capability capture_helper writer_helper
    root="${HOME:-}/.forge/goal-captures"
    [ -d "$root" ] && [ ! -L "$root" ] && regular_external_file "$receipt" "$root" || return 1
    [ "$(receipt_goal_value "$receipt" format)" = forge-codex-goal-tui-capture-v3 ] \
        && [ "$(receipt_goal_value "$receipt" engine)" = codex ] \
        && [ "$(receipt_goal_value "$receipt" command)" = /goal ] \
        && [ "$(receipt_goal_value "$receipt" capture_channel)" = physical-operator-action ] \
        && [ "$(receipt_goal_value "$receipt" fixture_only)" = false ] || return 1
    [ "$(receipt_goal_value "$receipt" project_root)" = "$project_root" ] \
        && [ "$(receipt_goal_value "$receipt" git_common_dir)" = "$goal_common" ] \
        && [ "$(receipt_goal_value "$receipt" project_id)" = "$project_id" ] || return 1
    session_dir=$(cd "$(dirname "$receipt")" && pwd -P)
    transcript=$(receipt_goal_value "$receipt" transcript_path); result=$(receipt_goal_value "$receipt" result_path)
    regular_external_file "$transcript" "$session_dir" && regular_external_file "$result" "$session_dir" || return 1
    [ "$(hash_goal_file "$transcript")" = "$(receipt_goal_value "$receipt" transcript_sha256)" ] \
        && [ "$(hash_goal_file "$result")" = "$(receipt_goal_value "$receipt" result_sha256)" ] || return 1
    capture_helper="${HOME:-}/.forge/bin/forge-goal-capture"; writer_helper="${HOME:-}/.forge/bin/forge-goal-authorize"
    [ -f "$capture_helper" ] && [ ! -L "$capture_helper" ] && [ -f "$capture_helper.sha256" ] && [ ! -L "$capture_helper.sha256" ] && [ "$(cat "$capture_helper.sha256")" = "$(hash_goal_file "$capture_helper")" ] || return 1
    [ -f "$writer_helper" ] && [ ! -L "$writer_helper" ] && [ -f "$writer_helper.sha256" ] && [ ! -L "$writer_helper.sha256" ] && [ "$(cat "$writer_helper.sha256")" = "$(hash_goal_file "$writer_helper")" ] || return 1
    capture_revision=$(sed -n "s/^CAPTURE_REVISION='\([^']*\)'.*/\1/p" "$capture_helper" | head -1)
    writer_revision=$(sed -n "s/^WRITER_REVISION='\([^']*\)'.*/\1/p" "$writer_helper" | head -1)
    [ -n "$capture_revision" ] && [ -n "$writer_revision" ] \
        && [ "$(receipt_goal_value "$receipt" capture_revision)" = "$capture_revision" ] \
        && [ "$(receipt_goal_value "$receipt" writer_revision)" = "$writer_revision" ] || return 1
    identity="${HOME:-}/.forge/bin/codex.identity"; identity_seal="$identity.sha256"
    [ -f "$identity" ] && [ ! -L "$identity" ] && [ -f "$identity_seal" ] && [ ! -L "$identity_seal" ] || return 1
    identity_hash=$(hash_goal_file "$identity"); [ "$(cat "$identity_seal")" = "$identity_hash" ] || return 1
    [ "$(receipt_goal_value "$identity" format)" = forge-codex-identity-v1 ] \
        && [ "$(receipt_goal_value "$identity" engine)" = codex ] \
        && [ "$(receipt_goal_value "$identity" identity_class)" = operator-setup ] \
        && [ "$(receipt_goal_value "$identity" status)" = QUALIFIED ] \
        && [ "$(receipt_goal_value "$identity" capture_revision)" = "$capture_revision" ] \
        && [ "$(receipt_goal_value "$identity" writer_revision)" = "$writer_revision" ] || return 1
    [ "$(receipt_goal_value "$receipt" identity_path)" = "$identity" ] && [ "$(receipt_goal_value "$receipt" identity_sha256)" = "$identity_hash" ] || return 1
    invocation_path=$(receipt_goal_value "$identity" invocation_path); cli_path=$(receipt_goal_value "$identity" binary_path)
    cli_sha=$(receipt_goal_value "$identity" binary_sha256); cli_version=$(receipt_goal_value "$identity" version); capability_revision=$(receipt_goal_value "$identity" capability_revision)
    [ "$(receipt_goal_value "$receipt" cli_path)" = "$cli_path" ] \
        && [ "$(receipt_goal_value "$receipt" cli_sha256)" = "$cli_sha" ] \
        && [ "$(receipt_goal_value "$receipt" cli_version)" = "$cli_version" ] \
        && [ "$(receipt_goal_value "$receipt" capability_revision)" = "$capability_revision" ] || return 1
    [ -x "$invocation_path" ] && [ -x "$cli_path" ] && [ ! -L "$cli_path" ] || return 1
    [ "$(resolve_goal_cli "$invocation_path")" = "$cli_path" ] && [ "$(resolve_goal_cli "$cli_path")" = "$cli_path" ] || return 1
    [ "$(hash_goal_file "$cli_path")" = "$cli_sha" ] || return 1
    actual_version=$($cli_path --version 2>/dev/null | head -1); [ "$actual_version" = "$cli_version" ] || return 1
    actual_capability=$(hash_goal_capability "$cli_path"); [ "$actual_capability" = "$capability_revision" ] || return 1
    for exact in "capture_channel=operator-codex-tui" "identity_sha256=$identity_hash" "cli_path=$cli_path" "cli_sha256=$cli_sha" "cli_version=$cli_version" "capability_revision=$capability_revision" "session_id=$(receipt_goal_value "$receipt" session_id)" "project_root=$project_root" "command=/goal" "/goal activated" "status captured" "pause captured" "checkpoint resumed" FORGE_GOAL_BUDGET_EXHAUSTED FORGE_GOAL_STUCK_WARNING; do grep -qxF "$exact" "$transcript" || return 1; done
    for exact in native_activation=PASS checkpoint_resume=PASS budget_oracle=PASS stuck_oracle=PASS; do grep -qxF "$exact" "$result" || return 1; done
}

goal_scratch=""
cleanup_goal() { [ -z "$goal_scratch" ] || rm -rf "$goal_scratch"; }
trap cleanup_goal EXIT HUP INT TERM
run_goal_fixture() {
    local binary="$1" session checkpoint turns count
    goal_scratch=$(mktemp -d "${TMPDIR:-/tmp}/forge-goal-fixture.XXXXXX")
    checkpoint="$goal_scratch/checkpoint"; session="22222222-2222-4222-8222-$(printf '%012d' $$ | tail -c 13)"
    FORGE_GOAL_FIXTURE_ACTION=activate FORGE_GOAL_FIXTURE_DIR="$goal_scratch" FORGE_GOAL_SESSION_ID="$session" "$binary" --fixture-native-goal-start > "$goal_scratch/start.out" 2>&1 \
        && grep -qF "native-activation:$session" "$goal_scratch/start.out" && grep -qxF "session_id=$session" "$checkpoint" || { reason="deterministic native /goal activation failed"; return 1; }
    native_activation=PASS
    FORGE_GOAL_FIXTURE_ACTION=resume FORGE_GOAL_FIXTURE_DIR="$goal_scratch" FORGE_GOAL_SESSION_ID="$session" "$binary" --fixture-native-goal-resume > "$goal_scratch/resume.out" 2>&1 \
        && grep -qF "checkpoint-resume:$session" "$goal_scratch/resume.out" && grep -qxF phase=verification "$checkpoint" && grep -qxF next_step=budget-check "$checkpoint" || { reason="deterministic exact-checkpoint resume failed"; return 1; }
    checkpoint_resume=PASS
    turns="$goal_scratch/turns"; mkdir "$turns"; printf 'charged\n' > "$goal_scratch/turn.tmp"; ln "$goal_scratch/turn.tmp" "$turns/turn-1" || return 1
    if ln "$goal_scratch/turn.tmp" "$turns/turn-1" 2>/dev/null; then return 1; fi
    count=$(find "$turns" -type f | wc -l | tr -d ' '); [ "$count" = 1 ] || return 1
    printf 'FORGE_GOAL_BUDGET_EXHAUSTED\npaused=true\n' > "$goal_scratch/budget"; budget_oracle=PASS
    printf 'fingerprint-a\n' > "$goal_scratch/progress-1"; cp "$goal_scratch/progress-1" "$goal_scratch/progress-2"; cmp -s "$goal_scratch/progress-1" "$goal_scratch/progress-2" || return 1
    printf 'FORGE_GOAL_STUCK_WARNING\n' > "$goal_scratch/stuck"; stuck_oracle=PASS
    status=PASS; reason="deterministic disposable checkpoint/resume, budget, and stuck oracle passed; no live host certified"
}

run_claude_live_goal() {
    local binary="$1" session empty_mcp start resume nonce ceiling turn_dir checkpoint
    validate_authorization "$authorization" || { reason="authorization is absent, stale, aliased, or outside the sealed root"; return 1; }
    goal_scratch=$(mktemp -d "${TMPDIR:-/tmp}/forge-goal-live.XXXXXX")
    mkdir -p "$goal_scratch/project"; git -C "$goal_scratch/project" init -q
    empty_mcp="$goal_scratch/empty-mcp.json"; printf '{"mcpServers":{}}\n' > "$empty_mcp"
    session="22222222-2222-4222-8222-$(printf '%012d' $$ | tail -c 13)"; start="$goal_scratch/start.out"; resume="$goal_scratch/resume.out"
    (cd "$goal_scratch/project" && FORGE_GOAL_SESSION_ID="$session" "$binary" -p --safe-mode --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools '' --permission-mode dontAsk --output-format text --session-id "$session" --system-prompt "This is the disposable Forge native goal oracle. Emit only the requested key/value proof." "/goal Activate the disposable Forge proving fixture. Emit native_activation=PASS, phase=implementation, next_step=resume-verification, progress=fingerprint-a, session_id=$session.") > "$start" 2> "$goal_scratch/start.err" || { reason="authenticated Claude native /goal activation failed"; return 1; }
    for exact in native_activation=PASS phase=implementation next_step=resume-verification progress=fingerprint-a "session_id=$session"; do grep -qF "$exact" "$start" || { reason="Claude native activation omitted $exact"; return 1; }; done
    native_activation=PASS
    checkpoint="$goal_scratch/checkpoint"; printf 'phase=implementation\nnext_step=resume-verification\nprogress=fingerprint-a\nsession_id=%s\n' "$session" > "$checkpoint"
    (cd "$goal_scratch/project" && FORGE_GOAL_SESSION_ID="$session" "$binary" -p --safe-mode --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools '' --permission-mode dontAsk --output-format text --resume "$session" --system-prompt "Resume the exact disposable Forge goal checkpoint and emit only the requested proof." "Report status, exhaust the Forge turn budget, pause, and show unchanged-progress stuck behavior. Emit checkpoint_resume=PASS, phase=verification, next_step=budget-check, progress=fingerprint-a, session_id=$session, FORGE_GOAL_BUDGET_EXHAUSTED, paused=true, FORGE_GOAL_STUCK_WARNING.") > "$resume" 2> "$goal_scratch/resume.err" || { reason="authenticated Claude exact checkpoint resume failed"; return 1; }
    for exact in checkpoint_resume=PASS phase=verification next_step=budget-check progress=fingerprint-a "session_id=$session" FORGE_GOAL_BUDGET_EXHAUSTED paused=true FORGE_GOAL_STUCK_WARNING; do grep -qF "$exact" "$resume" || { reason="Claude goal resume omitted $exact"; return 1; }; done
    checkpoint_resume=PASS
    nonce=$(receipt_goal_value "$authorization" nonce); ceiling=$(receipt_goal_value "$authorization" ceiling); [ "$ceiling" = 1 ] || { reason="disposable live oracle requires an operator ceiling of one"; return 1; }
    turn_dir="$goal_scratch/goal-counters/$nonce/turns"; mkdir -p "$turn_dir"; printf 'session_id=%s\ncheckpoint_hash=%s\n' "$session" "$(hash_goal_file "$checkpoint")" > "$goal_scratch/turn.tmp"; ln "$goal_scratch/turn.tmp" "$turn_dir/turn-1" || return 1
    if ln "$goal_scratch/turn.tmp" "$turn_dir/turn-1" 2>/dev/null; then reason="duplicate turn charge clobbered the oracle"; return 1; fi
    budget_oracle=PASS
    [ "$(grep -cF progress=fingerprint-a "$start")" -ge 1 ] && [ "$(grep -cF progress=fingerprint-a "$resume")" -ge 1 ] || return 1
    stuck_oracle=PASS; status=PASS; reason="authenticated Claude native /goal activation, exact resume, budget pause, and stuck oracle passed"
}

version=""; status=BLOCKED; native_activation=BLOCKED; checkpoint_resume=BLOCKED; budget_oracle=BLOCKED; stuck_oracle=BLOCKED; reason="$engine binary unavailable"
if [ "$test_live_driver" = true ]; then [ -x "$engine_path" ] || usage; binary=$(cd "$(dirname "$engine_path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$engine_path")"); else binary=$(command -v "$engine" 2>/dev/null || true); fi
if [ "$fixture_mode" = true ]; then
    if [ -n "$binary" ]; then version=$($binary --version 2>/dev/null | head -1 || true); run_goal_fixture "$binary" || status=BLOCKED; fi
elif [ "$engine" = codex ] && [ -n "$trusted_capture" ]; then
    if validate_trusted_capture "$trusted_capture"; then status=PASS; native_activation=PASS; checkpoint_resume=PASS; budget_oracle=PASS; stuck_oracle=PASS; reason="validated sealed physical operator Codex TUI capture"; else reason="trusted Codex TUI capture is unsealed, stale, workspace-authored, or hash-invalid"; fi
elif [ "$engine" = codex ]; then
    reason="native Codex /goal requires --trusted-capture produced by the global physical operator helper; codex exec cannot certify it"
elif [ -n "$binary" ]; then
    version=$($binary --version 2>/dev/null | head -1 || true); help=$($binary --help 2>&1 || true); missing=""
    for flag in --safe-mode --strict-mcp-config --setting-sources --session-id --resume; do case "$help" in *"$flag"*) ;; *) missing="$missing $flag" ;; esac; done
    if [ -n "$missing" ]; then reason="Claude CLI lacks native goal proving flags:$missing"
    elif [ "$test_live_driver" = false ] && [ "${FORGE_LIVE_QUALIFICATION:-0}" != 1 ]; then reason="set FORGE_LIVE_QUALIFICATION=1 before the authenticated native Claude /goal fixture"
    else run_claude_live_goal "$binary" || status=BLOCKED
    fi
fi

cat > "$output" <<EOF
{"schema":"forge.goal-feasibility.v1","engine":"$(json_escape_goal "$engine")","version":"$(json_escape_goal "$version")","status":"$status","native_activation":"$native_activation","checkpoint_resume":"$checkpoint_resume","budget_oracle":"$budget_oracle","stuck_oracle":"$stuck_oracle","reason":"$(json_escape_goal "$reason")"}
EOF
cat "$output"
[ "$status" = PASS ]
