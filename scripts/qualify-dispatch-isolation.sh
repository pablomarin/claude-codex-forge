#!/usr/bin/env bash
# Opt-in authenticated dispatch qualification. --fixture-mode and
# --test-live-driver are deterministic CI paths and never authenticate.
set -eu

usage() {
    echo "Usage: qualify-dispatch-isolation.sh --engine claude|codex --project-root DIR --output FILE [--fixture-mode | --test-live-driver --engine-path FILE]" >&2
    exit 2
}
json_escape_qualification() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'; }
hash_qualification_stream() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
hash_qualification_text() { printf '%s' "$1" | hash_qualification_stream; }

engine=""; project_root=""; output=""; fixture_mode=false; test_live_driver=false; engine_path=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --engine) engine="$2"; shift 2 ;;
        --project-root) project_root="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        --fixture-mode) fixture_mode=true; shift ;;
        --test-live-driver) test_live_driver=true; shift ;;
        --engine-path) engine_path="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$engine" in claude|codex) ;; *) usage ;; esac
[ -d "$project_root/.forge" ] || { echo "BLOCKED: materialized project is required" >&2; exit 3; }
[ -n "$output" ] || usage
[ "$fixture_mode" = false ] || [ "$test_live_driver" = false ] || usage
if [ "$test_live_driver" = true ]; then [ -x "$engine_path" ] || usage; binary=$(cd "$(dirname "$engine_path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$engine_path")"); else binary=$(command -v "$engine" 2>/dev/null || true); fi
mkdir -p "$(dirname "$output")"

version=""; status=BLOCKED; ephemeral=BLOCKED; council_resume=BLOCKED; investigation_replay=BLOCKED
reason="binary unavailable"; qualification_scratch=""
cleanup_qualification() { [ -z "$qualification_scratch" ] || rm -rf "$qualification_scratch"; }
trap cleanup_qualification EXIT HUP INT TERM

candidate_identity_qualification() {
    local root="$1"
    {
        git -C "$root" rev-parse HEAD
        git -C "$root" status --porcelain=v2 --untracked-files=all
        git -C "$root" diff --binary HEAD
        find "$root" -type f ! -path "$root/.git/*" -print | LC_ALL=C sort | while IFS= read -r file; do
            printf '%s\t' "${file#$root/}"
            if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$file" | awk '{print $1}'; else sha256sum "$file" | awk '{print $1}'; fi
        done
    } | hash_qualification_stream
}

seed_frozen_candidate() {
    local root="$1"
    mkdir -p "$root/.agents/skills/canary"
    git -C "$root" init -q
    git -C "$root" config user.email forge@example.invalid
    git -C "$root" config user.name Forge
    printf 'keep-base\n' > "$root/keep.txt"
    printf 'delete-base\n' > "$root/delete.txt"
    printf 'rename-base\n' > "$root/rename-old.txt"
    printf '#!/bin/sh\necho base\n' > "$root/script.sh"
    chmod +x "$root/script.sh"
    git -C "$root" add keep.txt delete.txt rename-old.txt script.sh
    git -C "$root" commit -qm base
    printf 'keep-candidate\n' > "$root/keep.txt"
    rm "$root/delete.txt"
    git -C "$root" mv rename-old.txt rename-new.txt
    printf 'FORGE_CANARY_CANDIDATE_INSTRUCTION\n' > "$root/AGENTS.md"
    printf '%s\n' '---' 'name: canary' 'description: FORGE_CANARY_SKILL' '---' > "$root/.agents/skills/canary/SKILL.md"
}

validate_bound_response() {
    local file="$1" session="$2" seat="$3" config="$4"
    grep -qF "$session" "$file" \
        && grep -qF "$seat" "$file" \
        && grep -qF "$config" "$file" \
        && grep -Eq 'canary_observed["= :]+false' "$file" \
        && ! grep -qF FORGE_CANARY_ "$file"
}

run_fixture_dispatch() {
    local candidate investigation replay sentinel response session seat before after artifact
    [ -n "$binary" ] || return 1
    qualification_scratch=$(mktemp -d "${TMPDIR:-/tmp}/forge-dispatch-fixture.XXXXXX")
    candidate="$qualification_scratch/candidate"; investigation="$qualification_scratch/investigation"; replay="$qualification_scratch/replay"
    mkdir -p "$candidate" "$qualification_scratch/sessions" "$replay"
    seed_frozen_candidate "$candidate"
    before=$(candidate_identity_qualification "$candidate")
    sentinel="FORGE_DISPATCH_FIXTURE_${engine}_$$"; response="$qualification_scratch/ephemeral.out"
    FORGE_DISPATCH_FIXTURE_ACTION=ephemeral FORGE_DISPATCH_SENTINEL="$sentinel" "$binary" --fixture-ephemeral > "$response" 2>&1 || { reason="deterministic ephemeral fixture failed"; return 1; }
    grep -qF "ephemeral:$sentinel:canary=false" "$response" && ! grep -qF FORGE_CANARY_ "$response" || { reason="deterministic ephemeral canary isolation failed"; return 1; }
    ephemeral=PASS
    session="11111111-1111-4111-8111-$(printf '%012d' $$ | tail -c 13)"; seat=$(hash_qualification_text "$engine\n$before\n$sentinel\n")
    FORGE_DISPATCH_FIXTURE_ACTION=council-start FORGE_DISPATCH_SESSION_STORE="$qualification_scratch/sessions" FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" "$binary" --fixture-council-start > "$qualification_scratch/start.out" 2>&1 || return 1
    FORGE_DISPATCH_FIXTURE_ACTION=council-resume FORGE_DISPATCH_SESSION_STORE="$qualification_scratch/sessions" FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" "$binary" --fixture-council-resume > "$qualification_scratch/resume.out" 2>&1 || return 1
    if FORGE_DISPATCH_FIXTURE_ACTION=council-resume FORGE_DISPATCH_SESSION_STORE="$qualification_scratch/sessions" FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="wrong-$seat" "$binary" --fixture-council-resume > "$qualification_scratch/wrong.out" 2>&1; then reason="deterministic council resume accepted a cross-seat hash"; return 1; fi
    council_resume=PASS
    cp -R "$candidate" "$investigation"
    FORGE_DISPATCH_FIXTURE_ACTION=investigate FORGE_DISPATCH_INVESTIGATION_ROOT="$investigation" "$binary" --fixture-investigate > "$qualification_scratch/investigate.out" 2>&1 || return 1
    after=$(candidate_identity_qualification "$candidate"); [ "$after" = "$before" ] || return 1
    artifact="$investigation/artifacts/qualification.txt"
    [ -f "$artifact" ] && [ ! -L "$artifact" ] && [ "$(wc -c < "$artifact" | tr -d ' ')" -le 65536 ] || return 1
    mkdir -p "$replay/artifacts"; cp "$artifact" "$replay/artifacts/qualification.txt"
    grep -qxF bounded-reproduction "$replay/artifacts/qualification.txt" || return 1
    investigation_replay=PASS; status=PASS
    reason="deterministic fake-engine isolation, exact-id resume, and bounded replay passed"
}

run_guarded_dispatch() {
    local scratch primary candidate investigation replay empty_mcp schema sentinel before after config seat session start_session artifact moved
    local ephemeral_out start_out resume_out investigation_out
    qualification_scratch=$(mktemp -d "${TMPDIR:-/tmp}/forge-dispatch-live.XXXXXX")
    scratch="$qualification_scratch"; primary="$scratch/primary"; candidate="$scratch/candidate"; investigation="$scratch/investigation"; replay="$scratch/replay"
    mkdir -p "$primary" "$candidate" "$scratch/session-store" "$scratch/codex-home" "$replay"
    git -C "$primary" init -q; seed_frozen_candidate "$candidate"
    printf 'FORGE_CANARY_USER_INSTRUCTION\n' > "$primary/CLAUDE.md"
    printf 'FORGE_CANARY_USER_INSTRUCTION\n' > "$scratch/codex-home/AGENTS.md"
    empty_mcp="$scratch/empty-mcp.json"; printf '{"mcpServers":{}}\n' > "$empty_mcp"
    schema="$scratch/schema.json"; printf '%s\n' '{"type":"object","additionalProperties":true}' > "$schema"
    if [ "$engine" = codex ] && [ "$test_live_driver" = false ]; then cp "$FORGE_CODEX_AUTH_FILE" "$scratch/codex-home/auth.json"; chmod 600 "$scratch/codex-home/auth.json"; fi
    before=$(candidate_identity_qualification "$candidate")
    sentinel="FORGE_ISOLATION_OK_${engine}_$$"; config=$(hash_qualification_text "$engine\nqualified-v1\n$before\n"); seat=$(hash_qualification_text "$engine\n$config\n$sentinel\n")
    session="11111111-1111-4111-8111-$(printf '%012d' $$ | tail -c 13)"
    ephemeral_out="$scratch/ephemeral.out"; start_out="$scratch/start.out"; resume_out="$scratch/resume.out"; investigation_out="$scratch/investigation.out"
    if [ "$engine" = claude ]; then
        (cd "$primary" && FORGE_DISPATCH_SENTINEL="$sentinel" "$binary" -p --safe-mode --no-session-persistence --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools '' --permission-mode dontAsk --output-format json --system-prompt "Return sentinel=$sentinel and canary_observed=false." "$sentinel") > "$ephemeral_out" 2> "$scratch/ephemeral.err" || { reason="Claude ephemeral isolation invocation failed"; return 1; }
    else
        CODEX_HOME="$scratch/codex-home" FORGE_DISPATCH_SENTINEL="$sentinel" "$binary" -a never exec --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use -C "$primary" --add-dir "$candidate" --ignore-user-config --ignore-rules --ephemeral --sandbox read-only --json --output-schema "$schema" "Return sentinel=$sentinel and canary_observed=false." > "$ephemeral_out" 2> "$scratch/ephemeral.err" || { reason="Codex ephemeral isolation invocation failed"; return 1; }
    fi
    grep -qF "$sentinel" "$ephemeral_out" && grep -Eq 'canary_observed["= :]+false' "$ephemeral_out" && ! grep -qF FORGE_CANARY_ "$ephemeral_out" || { reason="ephemeral response leaked a canary or missed the sentinel"; return 1; }
    ephemeral=PASS

    if [ "$engine" = claude ]; then
        (cd "$primary" && FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" FORGE_DISPATCH_CONFIG_HASH="$config" "$binary" -p --safe-mode --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools '' --permission-mode dontAsk --output-format json --session-id "$session" --system-prompt "Return exactly these four key=value lines and nothing else: session_id=$session, seat_hash=$seat, config_hash=$config, canary_observed=false." "FORGE_COUNCIL_START") > "$start_out" 2> "$scratch/start.err" || { reason="Claude council first turn failed"; return 1; }
        validate_bound_response "$start_out" "$session" "$seat" "$config" || { reason="Claude council first turn identity mismatch"; return 1; }
        (cd "$primary" && FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" FORGE_DISPATCH_CONFIG_HASH="$config" "$binary" -p --safe-mode --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools '' --permission-mode dontAsk --output-format json --resume "$session" --system-prompt "Return exactly these four key=value lines and nothing else: session_id=$session, seat_hash=$seat, config_hash=$config, canary_observed=false." "FORGE_COUNCIL_RESUME") > "$resume_out" 2> "$scratch/resume.err" || { reason="Claude exact-id resume failed"; return 1; }
    else
        CODEX_HOME="$scratch/codex-home" FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" FORGE_DISPATCH_CONFIG_HASH="$config" "$binary" -a never exec --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use -C "$primary" --add-dir "$candidate" --ignore-user-config --ignore-rules --sandbox read-only --json --output-schema "$schema" "FORGE_COUNCIL_START seat_hash=$seat config_hash=$config canary_observed=false" > "$start_out" 2> "$scratch/start.err" || { reason="Codex council first turn failed"; return 1; }
        start_session=$(sed -n 's/.*"type":"thread.started".*"thread_id":"\([^"]*\)".*/\1/p' "$start_out" | head -1)
        [ -n "$start_session" ] || { reason="Codex council first turn emitted no thread.started id"; return 1; }
        if [ "$test_live_driver" = true ]; then [ "$start_session" = "$session" ] || { reason="Codex fake driver returned unexpected thread id"; return 1; }; else session="$start_session"; fi
        validate_bound_response "$start_out" "$session" "$seat" "$config" || { reason="Codex council first turn identity mismatch"; return 1; }
        CODEX_HOME="$scratch/codex-home" FORGE_DISPATCH_SESSION_ID="$session" FORGE_DISPATCH_SEAT_HASH="$seat" FORGE_DISPATCH_CONFIG_HASH="$config" "$binary" -a never exec resume --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use --ignore-user-config --ignore-rules --sandbox read-only --json --output-schema "$schema" "$session" "FORGE_COUNCIL_RESUME exact session_id=$session seat_hash=$seat config_hash=$config canary_observed=false" > "$resume_out" 2> "$scratch/resume.err" || { reason="Codex exact-id resume failed"; return 1; }
    fi
    validate_bound_response "$resume_out" "$session" "$seat" "$config" || { reason="council resume rejected cross-seat, stale config, or canary evidence"; return 1; }
    council_resume=PASS

    cp -R "$candidate" "$investigation"
    if [ "$engine" = claude ]; then
        (cd "$investigation" && FORGE_DISPATCH_INVESTIGATION_ROOT="$investigation" FORGE_DISPATCH_REPLAY_TARGET="$replay" FORGE_DISPATCH_CANDIDATE_ID="$before" "$binary" -p --safe-mode --no-session-persistence --strict-mcp-config --mcp-config "$empty_mcp" --setting-sources '' --tools 'Read,Write,Edit,Bash' --permission-mode dontAsk --output-format json --system-prompt "FORGE_INVESTIGATION candidate_id=$before. Write only artifacts/qualification.txt, text <=65536 bytes. Then return exactly these two key=value lines and nothing else: candidate_id=$before, canary_observed=false." "FORGE_INVESTIGATION") > "$investigation_out" 2> "$scratch/investigation.err" || { reason="Claude investigation invocation failed"; return 1; }
    else
        CODEX_HOME="$scratch/codex-home" FORGE_DISPATCH_INVESTIGATION_ROOT="$investigation" FORGE_DISPATCH_REPLAY_TARGET="$replay" FORGE_DISPATCH_CANDIDATE_ID="$before" "$binary" -a never exec --disable hooks --disable plugins --disable plugin_sharing --disable apps --disable remote_plugin --disable in_app_browser --disable browser_use --disable computer_use -C "$primary" --add-dir "$investigation" --ignore-user-config --ignore-rules --ephemeral --sandbox workspace-write --json "FORGE_INVESTIGATION candidate_id=$before. Work only in the sibling and write only artifacts/qualification.txt, text <=65536 bytes. Respond candidate_id=$before and canary_observed=false." > "$investigation_out" 2> "$scratch/investigation.err" || { reason="Codex investigation invocation failed"; return 1; }
    fi
    grep -qF "candidate_id=$before" "$investigation_out" && grep -Eq 'canary_observed["= :]+false' "$investigation_out" && ! grep -qF FORGE_CANARY_ "$investigation_out" || { reason="investigation response did not bind the frozen candidate or leaked a canary"; return 1; }
    after=$(candidate_identity_qualification "$candidate"); [ "$after" = "$before" ] || { reason="frozen candidate identity changed during investigation"; return 1; }
    artifact="$investigation/artifacts/qualification.txt"
    [ -d "$investigation/artifacts" ] && [ ! -L "$investigation/artifacts" ] && [ -f "$artifact" ] && [ ! -L "$artifact" ] || { reason="investigation path escaped, linked, or omitted its declared artifact"; return 1; }
    [ "$(wc -c < "$artifact" | tr -d ' ')" -le 65536 ] && LC_ALL=C grep -Iq . "$artifact" || { reason="investigation artifact is binary or oversized"; return 1; }
    moved="$scratch/qualification.txt"; mv "$artifact" "$moved"; rmdir "$investigation/artifacts" 2>/dev/null || { reason="investigation produced undeclared output"; return 1; }
    [ "$(candidate_identity_qualification "$investigation")" = "$before" ] || { reason="investigation modified undeclared candidate paths"; return 1; }
    [ ! -e "$replay/artifacts" ] && [ ! -L "$replay/artifacts" ] || { reason="replay refused to clobber an existing destination"; return 1; }
    mkdir "$replay/artifacts"; [ ! -e "$replay/artifacts/qualification.txt" ] || return 1
    cp "$moved" "$replay/artifacts/qualification.txt"
    grep -qxF bounded-reproduction "$replay/artifacts/qualification.txt" || { reason="declared replay content mismatch"; return 1; }
    investigation_replay=PASS; status=PASS
    reason="authenticated guarded isolation, exact-id resume, and frozen-candidate replay passed"
}

if [ "$fixture_mode" = true ]; then
    [ -z "$binary" ] || version=$($binary --version 2>/dev/null | head -1 || true)
    run_fixture_dispatch || status=BLOCKED
elif [ -n "$binary" ]; then
    version=$($binary --version 2>/dev/null | head -1 || true)
    help=$($binary --help 2>&1 || true); missing=""
    if [ "$engine" = claude ]; then required="--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence"; else required="--add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable"; help="$help $($binary exec --help 2>&1 || true)"; fi
    for flag in $required; do case "$help" in *"$flag"*) ;; *) missing="$missing $flag" ;; esac; done
    if [ -n "$missing" ]; then reason="qualified CLI lacks required isolation flags:$missing"
    elif [ "$test_live_driver" = false ] && [ "${FORGE_LIVE_QUALIFICATION:-0}" != 1 ]; then reason="set FORGE_LIVE_QUALIFICATION=1 to authorize the authenticated sentinel"
    elif [ "$engine" = codex ] && [ "$test_live_driver" = false ] && { [ -z "${FORGE_CODEX_AUTH_FILE:-}" ] || [ ! -f "$FORGE_CODEX_AUTH_FILE" ]; }; then reason="set FORGE_CODEX_AUTH_FILE to an operator-owned auth file for disposable CODEX_HOME"
    else run_guarded_dispatch || status=BLOCKED
    fi
fi

cat > "$output" <<EOF
{"schema":"forge.dispatch-isolation.v1","engine":"$(json_escape_qualification "$engine")","version":"$(json_escape_qualification "$version")","status":"$status","ephemeral":"$ephemeral","council_resume":"$council_resume","investigation_replay":"$investigation_replay","reason":"$(json_escape_qualification "$reason")"}
EOF
cat "$output"
[ "$status" = PASS ]
