#!/bin/bash
# Validate only Forge-managed config entries. User-owned settings remain outside
# the fingerprint, while removed/changed/duplicated managed hooks fail closed.
set -u

MODE=event
ROOT=""
if [ "${1:-}" = --verify-boundary ]; then MODE=boundary; ROOT="${2:-}"; fi
INPUT=$(cat 2>/dev/null)
if [ -z "$ROOT" ] && command -v jq >/dev/null 2>&1; then ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true); fi
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TOP=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true); [ -n "$TOP" ] && ROOT="$TOP"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { echo "FORGE_CONFIG_TAMPERED: invalid project root" >&2; exit 2; }

if [ "$MODE" = event ]; then
    FILE_PATH=""; SOURCE="unknown"
    if command -v jq >/dev/null 2>&1; then
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.file_path // ""' 2>/dev/null || true)
        SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo unknown)
    fi
    AUDIT_LOG="${HOME:-$ROOT}/.forge/audit.log"; mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
    printf '[%s] CONFIG_CHANGED: %s (source: %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$FILE_PATH" "$SOURCE" >> "$AUDIT_LOG" 2>/dev/null || true
fi

command -v python3 >/dev/null 2>&1 || { echo "FORGE_CONFIG_TAMPERED: python3 unavailable for managed config validation" >&2; exit 2; }
FINGERPRINT=$(python3 - "$ROOT" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])

claude_expected = {
    "session-start": ("SessionStart", "$CLAUDE_PROJECT_DIR/.forge/hooks/session-start.sh"),
    "build-evidence": ("Stop", "$CLAUDE_PROJECT_DIR/.forge/hooks/build-evidence.sh"),
    "state-updated": ("Stop", "$CLAUDE_PROJECT_DIR/.forge/hooks/check-state-updated.sh"),
    "subagent-review-receipt": ("SubagentStop", "$CLAUDE_PROJECT_DIR/.forge/hooks/check-subagent-review.sh"),
    "precompact-memory": ("PreCompact", "$CLAUDE_PROJECT_DIR/.forge/hooks/pre-compact-memory.sh"),
    "config-change": ("ConfigChange", "$CLAUDE_PROJECT_DIR/.forge/hooks/check-config-change.sh"),
    "bash-safety": ("PreToolUse", "$CLAUDE_PROJECT_DIR/.forge/hooks/check-bash-safety.sh"),
    "workflow-gates": ("PreToolUse", "$CLAUDE_PROJECT_DIR/.forge/hooks/check-workflow-gates.sh"),
    "auto-approve-local": ("PermissionRequest", "$CLAUDE_PROJECT_DIR/.forge/hooks/auto-approve-local-writes.sh"),
    "post-format": ("PostToolUse", "$CLAUDE_PROJECT_DIR/.forge/hooks/post-tool-format.sh"),
}
def router(script):
    return f'bash "$(git rev-parse --show-toplevel)/.forge/hooks/lib/codex-worktree-dispatch.sh" {script}'

codex_expected = {
    "host-context": ("SessionStart", 'bash "$(git rev-parse --show-toplevel)/.forge/hooks/lib/host-context.sh" hook --host codex', "host-context.ps1"),
    "session-start": ("SessionStart", router("session-start.sh"), "session-start.ps1"),
    "bash-safety": ("PreToolUse", router("check-bash-safety.sh"), "check-bash-safety.ps1"),
    "workflow-gates": ("PreToolUse", router("check-workflow-gates.sh"), "check-workflow-gates.ps1"),
    "external-mutation-auth": ("PreToolUse", router("check-external-mutation-auth.sh"), "check-external-mutation-auth.ps1"),
    "format": ("PostToolUse", router("post-tool-format.sh"), "post-tool-format.ps1"),
    "subagent-review-receipt": ("SubagentStop", router("check-subagent-review.sh"), "check-subagent-review.ps1"),
    "precompact-memory": ("PreCompact", router("pre-compact-memory.sh"), "pre-compact-memory.ps1"),
    "build-evidence": ("Stop", router("build-evidence.sh"), "build-evidence.ps1"),
    "state-updated": ("Stop", router("check-state-updated.sh"), "check-state-updated.ps1"),
}
codex_tokens = {
    "host-context": "host-context.sh", "session-start": "session-start.sh",
    "bash-safety": "check-bash-safety.sh", "workflow-gates": "check-workflow-gates.sh",
    "external-mutation-auth": "check-external-mutation-auth.sh", "format": "post-tool-format.sh",
    "subagent-review-receipt": "check-subagent-review.sh", "precompact-memory": "pre-compact-memory.sh",
    "build-evidence": "build-evidence.sh", "state-updated": "check-state-updated.sh",
}
try:
    claude = json.loads((root / ".claude/settings.json").read_text())
    codex = json.loads((root / ".codex/hooks.json").read_text())
except Exception as exc:
    raise SystemExit(f"invalid managed JSON: {exc}")

claude_found = []
for event, groups in claude.get("hooks", {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            mid = hook.get("forgeManagedId")
            if mid:
                claude_found.append((mid, event, hook.get("command", "")))

codex_found = []
for event, groups in codex.get("hooks", {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            command = hook.get("command", "")
            matches = [mid for mid, token in codex_tokens.items() if f"/{token}" in command or command.endswith(f" {token}")]
            if len(matches) == 1:
                codex_found.append((matches[0], event, command, hook.get("commandWindows", ""), hook.get("type")))

claude_rows = [row for row in claude_found if row[0] in claude_expected]
if len(claude_rows) != len(claude_expected) or len({mid for mid, _, _ in claude_rows}) != len(claude_expected):
    raise SystemExit("claude managed hook set missing or duplicated")
for mid, (want_event, want_command) in claude_expected.items():
    if [(event, command) for got, event, command in claude_rows if got == mid] != [(want_event, want_command)]:
        raise SystemExit(f"claude managed hook changed: {mid}")

if len(codex_found) != len(codex_expected) or len({mid for mid, *_ in codex_found}) != len(codex_expected):
    raise SystemExit("codex managed hook set missing or duplicated")
for mid, (want_event, want_command, want_windows_script) in codex_expected.items():
    actual = [(event, command, windows, kind) for got, event, command, windows, kind in codex_found if got == mid]
    if len(actual) != 1:
        raise SystemExit(f"codex managed hook changed: {mid}")
    event, command, windows, kind = actual[0]
    if event != want_event or command != want_command or kind != "command" or want_windows_script not in windows:
        raise SystemExit(f"codex managed hook changed: {mid}")

encoded = json.dumps({"claude": sorted(claude_found), "codex": sorted(codex_found)}, separators=(",", ":"), ensure_ascii=True)
print(hashlib.sha256(encoded.encode()).hexdigest())
PY
) || { echo "FORGE_CONFIG_TAMPERED: managed config validation failed" >&2; exit 2; }
case "$FINGERPRINT" in ????????????????????????????????????????????????????????????????) ;; *) echo "FORGE_CONFIG_TAMPERED: invalid managed config fingerprint" >&2; exit 2 ;; esac

hash_file() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
INSTALL_FILE="$ROOT/.forge/installed-files.tsv"
INSTALL_HASH="missing"; [ -f "$INSTALL_FILE" ] && INSTALL_HASH=$(hash_file "$INSTALL_FILE")
DEST="$ROOT/.forge/local/managed-config.fingerprint"
mkdir -p "$(dirname "$DEST")" || exit 2
if [ -f "$DEST" ]; then
    OLD_INSTALL=$(sed -n 's/^install=//p' "$DEST" | head -1)
    OLD_CONFIG=$(sed -n 's/^config=//p' "$DEST" | head -1)
    if [ "$OLD_CONFIG" != "$FINGERPRINT" ] && [ "$OLD_INSTALL" = "$INSTALL_HASH" ]; then
        echo "FORGE_CONFIG_TAMPERED: managed hook fingerprint changed without a Forge install" >&2
        exit 2
    fi
fi
TMP="$DEST.tmp.$$"
printf 'format=forge-managed-config-v1\ninstall=%s\nconfig=%s\n' "$INSTALL_HASH" "$FINGERPRINT" > "$TMP" || exit 2
mv "$TMP" "$DEST" || exit 2
[ "$MODE" = boundary ] && printf '{}\n'
exit 0
