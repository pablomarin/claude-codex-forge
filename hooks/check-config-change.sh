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
codex_expected = {
    "session-start": ("session_start", (".forge/hooks/lib/codex-worktree-dispatch.sh", "session-start.sh")),
    "bash-safety": ("pre_tool_use", (".forge/hooks/lib/codex-worktree-dispatch.sh", "check-bash-safety.sh")),
    "workflow-gates": ("pre_tool_use", (".forge/hooks/lib/codex-worktree-dispatch.sh", "check-workflow-gates.sh")),
    "format": ("post_tool_use", (".forge/hooks/lib/codex-worktree-dispatch.sh", "post-tool-format.sh")),
    "subagent-review-receipt": ("subagent_stop", (".forge/hooks/lib/codex-worktree-dispatch.sh", "check-subagent-review.sh")),
    "precompact-memory": ("pre_compact", (".forge/hooks/lib/codex-worktree-dispatch.sh", "pre-compact-memory.sh")),
    "build-evidence": ("stop", (".forge/hooks/lib/codex-worktree-dispatch.sh", "build-evidence.sh")),
    "state-updated": ("stop", (".forge/hooks/lib/codex-worktree-dispatch.sh", "check-state-updated.sh")),
}
try:
    claude = json.loads((root / ".claude/settings.json").read_text())
    codex = json.loads((root / ".codex/hooks.json").read_text())
except Exception as exc:
    raise SystemExit(f"invalid managed JSON: {exc}")

found = []
for event, groups in claude.get("hooks", {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            mid = hook.get("forgeManagedId")
            if mid:
                found.append(("claude", mid, event, hook.get("command", "")))
for event, hooks in codex.get("hooks", {}).items():
    for hook in hooks:
        mid = hook.get("forgeManagedId")
        if mid:
            command = hook.get("command", [])
            found.append(("codex", mid, event, tuple(command) if isinstance(command, list) else command))

for host, expected in (("claude", claude_expected), ("codex", codex_expected)):
    rows = [(mid, event, command) for h, mid, event, command in found if h == host and mid in expected]
    if len(rows) != len(expected) or len({mid for mid, _, _ in rows}) != len(expected):
        raise SystemExit(f"{host} managed hook set missing or duplicated")
    for mid, (want_event, want_command) in expected.items():
        actual = [(event, command) for got, event, command in rows if got == mid]
        if actual != [(want_event, want_command)]:
            raise SystemExit(f"{host} managed hook changed: {mid}")

encoded = json.dumps(sorted((h, m, e, list(c) if isinstance(c, tuple) else c) for h,m,e,c in found), separators=(",", ":"), ensure_ascii=True)
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
