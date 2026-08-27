#!/bin/bash
# .claude/hooks/check-bash-safety.sh
# PreToolUse hook for Bash: audit logging + dangerous pattern blocking.
#
# Fires BEFORE every Bash command. Logs all commands to ~/.claude/audit.log.
# Blocks commands matching high-risk patterns (exit 2 + stderr).
#
# Input (JSON via stdin): {session_id, cwd, tool_name, tool_input: {command}}
# Block: exit 2 + message on stderr
# Allow: exit 0
#
# Requirements: jq (recommended for robust parsing, grep fallback)

INPUT=$(cat)
forge_allow() {
    printf '%s' "$INPUT" | grep -qE '"host"[[:space:]]*:[[:space:]]*"codex"' && printf '{}\n'
    exit 0
}

# --- Parse input ---
if command -v jq &> /dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
    CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
else
    # grep fallback: extract command value (handles simple cases)
    COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
    SESSION_ID="unknown"
    CWD="unknown"
fi

# Skip empty commands
[ -z "$COMMAND" ] && forge_allow

# --- Audit log (always, before any blocking) ---
AUDIT_LOG="${HOME}/.claude/audit.log"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
# Redact potential secrets from logged commands (API keys, tokens, passwords)
SAFE_COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  's/(export\s+\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)\w*=)[^ ]*/\1[REDACTED]/gi; s/(sk-|ghp_|gho_|github_pat_|xoxb-|xoxp-)[A-Za-z0-9_-]+/\1[REDACTED]/g')
printf '[%s] session=%s cwd=%s cmd=%s\n' "$TIMESTAMP" "$SESSION_ID" "$CWD" "$SAFE_COMMAND" >> "$AUDIT_LOG" 2>/dev/null

# --- High-risk pattern detection ---
# Each check is a separate function for clarity and testability.
# Only flag patterns that are clearly dangerous — minimize false positives.

REASON=""

# 1. Piping remote content to shell (curl/wget ... | sh/bash/zsh)
if echo "$COMMAND" | grep -qE 'curl\s.*\|\s*(sh|bash|zsh)' 2>/dev/null; then
    REASON="Piping remote script to shell (curl | sh)"
elif echo "$COMMAND" | grep -qE 'wget\s.*\|\s*(sh|bash|zsh)' 2>/dev/null; then
    REASON="Piping remote script to shell (wget | sh)"

# 2. Base64 decode piped to shell
elif echo "$COMMAND" | grep -qE 'base64\s.*-d.*\|\s*(sh|bash|zsh|eval)' 2>/dev/null; then
    REASON="Base64-decoded content piped to shell"

# 3. Reverse shell patterns
elif echo "$COMMAND" | grep -qE '/dev/tcp/' 2>/dev/null; then
    REASON="Potential reverse shell (/dev/tcp)"
elif echo "$COMMAND" | grep -qE 'bash\s+-i\s+>&' 2>/dev/null; then
    REASON="Potential reverse shell (bash -i)"
elif echo "$COMMAND" | grep -qE 'nc\s.*-e\s*(sh|bash|/bin)' 2>/dev/null; then
    REASON="Potential reverse shell (netcat)"

# 4. Exfiltration of credentials via network
elif echo "$COMMAND" | grep -qE 'cat.*(id_rsa|id_ed25519|\.ssh/|\.gnupg/|\.aws/credentials|\.env).*\|\s*curl' 2>/dev/null; then
    REASON="Exfiltrating credential files via network"
elif echo "$COMMAND" | grep -qE 'curl.*-d\s*@.*(id_rsa|id_ed25519|\.ssh/|\.env|\.aws/)' 2>/dev/null; then
    REASON="Uploading credential files via curl"

# 5. Mass deletion outside project (already in deny list, but catch variants)
elif echo "$COMMAND" | grep -qE 'rm\s+-[rf]*\s+/' 2>/dev/null && ! echo "$COMMAND" | grep -qE 'rm\s+-[rf]*\s+\./|rm\s+-[rf]*\s+[^/]' 2>/dev/null; then
    REASON="Recursive deletion targeting root filesystem"

# 6. Modifying Claude Code's own config via Bash (defense in depth with ConfigChange hook)
elif echo "$COMMAND" | grep -qE '(sed|awk|echo|tee|printf)[^;|&]*\.claude/(settings|config)' 2>/dev/null; then
    REASON="Attempting to modify Claude Code configuration via Bash"

# 7. Global package installs (supply chain attack vector — see Clinejection)
elif echo "$COMMAND" | grep -qE 'npm\s+(install|i)\s+(-g|--global)|npm\s+(-g|--global)\s+(install|i)' 2>/dev/null; then
    REASON="Global npm package install detected (supply chain risk)"
elif echo "$COMMAND" | grep -qE 'yarn\s+global\s+add' 2>/dev/null; then
    REASON="Global yarn package install detected (supply chain risk)"
elif echo "$COMMAND" | grep -qE 'pnpm\s+(add|install|i)\s+(-g|--global)|pnpm\s+(-g|--global)\s+(add|install|i)' 2>/dev/null; then
    REASON="Global pnpm package install detected (supply chain risk)"
elif echo "$COMMAND" | grep -qE '(^|\s)pip3?\s+install\s+[^-]' 2>/dev/null && ! echo "$COMMAND" | grep -qE 'pip3?\s+install\s+(-r\s|-e\s|\.\s*$)|uv\s+pip' 2>/dev/null; then
    REASON="Unscoped pip install detected (supply chain risk — use venv or uv)"

# 8. Workflow-safety (NOT security): block Bash read-utilities that read
#    .claude/local/state.md inline. Bash is not a read-only tool in Claude Code,
#    so a Bash read of this sensitive file trips CC's sensitive-file access prompt
#    — which SILENTLY STALLS an autonomous /goal run (no human to answer). The Read
#    tool is prompt-free for in-project files; use it instead. This is a TARGETED
#    guardrail for the common inline form, not a proof recurrence is impossible:
#    the match is per-line (`echo | grep`) and requires the read-utility token and
#    the literal path on the SAME line, so sanctioned flows that read via a shell
#    VARIABLE (EXTRACT-FOLDABLE `awk … "$1"`, finish-branch `"$MAIN_STATE"`/`"$WT_SNAP"`)
#    are structurally exempt, as is the `bash …/review-breaker.sh …/state.md`
#    diagnostic (bash is not a read-utility). Filename terminator keeps state.md.bak
#    from matching. Gates the AGENT's Bash tool only — a human's terminal is unaffected.
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])(/[^[:space:]]*/)?(cat|sed|grep|egrep|fgrep|rg|awk|head|tail|less|more|nl|tac)[[:space:]].*\.forge/local/state\.md([^A-Za-z0-9._-]|$)' 2>/dev/null; then
    REASON="Reading .forge/local/state.md via Bash — use the host read tool instead during autonomous /goal runs"
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])(/[^[:space:]]*/)?(cat|sed|grep|egrep|fgrep|rg|awk|head|tail|less|more|nl|tac)[[:space:]].*\.claude/local/state\.md([^A-Za-z0-9._-]|$)' 2>/dev/null; then
    REASON="Reading .claude/local/state.md via Bash — use the Read tool instead (Bash reads of this sensitive file stall autonomous /goal runs on a permission prompt)"

# 9. Workflow-safety (NOT security): block the COMMON Bash WRITE forms under
#    .claude/local/. CC never auto-approves writes under .claude/ (ADR 0006 /
#    Anthropic docs: protected path, only bypassPermissions skips it), so a Bash
#    write here trips CC's sensitive-file prompt — which SILENTLY STALLS an
#    autonomous /goal run. Use the Write/Edit tools (auto-approved on
#    .claude/local/**, auto-create parent dirs — ADR 0006). Two field instances
#    motivated this: `mkdir -p .claude/local/investigate` and `: > .claude/local/
#    .../finding.txt`. This is a TARGETED guardrail for the common inline form,
#    NOT a shell parser — it covers the common create/redirect commands, and the
#    real fix is that /codex Investigate mode no longer emits any .claude/local
#    write. Deliberately OUT of scope (documented residuals, per v5.56 policy):
#    exotic writers (chmod/truncate/rsync, sed -i, ln/dd), alternate redirect
#    operators (>&/>|), separator-attached forms, and backslash-line-continuation.
#    The redirect target is scoped to its single token ([^[:space:]|&;]*) so a
#    `> /tmp/log .claude/local/x` (real target /tmp) does NOT false-match. A
#    .claude/local path as a plain string ARGUMENT (no shell op) is not matched.
#    Gates the AGENT's Bash tool only — a human's terminal is unaffected.
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])(mkdir|touch|cp|mv|tee|rm)[[:space:]][^|&;]*\.forge/local/' 2>/dev/null; then
    REASON="Writing under .forge/local/ via Bash — use the host Write/Edit tool instead"
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])(mkdir|touch|cp|mv|tee|rm)[[:space:]][^|&;]*\.claude/local/' 2>/dev/null; then
    REASON="Writing under .claude/local/ via Bash — use the Write/Edit tool instead (Bash writes under .claude/ are never auto-approved and stall autonomous /goal runs on a permission prompt; the Write tool auto-creates parent dirs — see ADR 0006)"
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^[:space:]|&;]*\.forge/local/' 2>/dev/null; then
    REASON="Writing under .forge/local/ via Bash (redirect) — use the host Write/Edit tool instead"
elif echo "$COMMAND" | grep -qE '(^|[[:space:]])[12]?>>?[[:space:]]*[^[:space:]|&;]*\.claude/local/' 2>/dev/null; then
    REASON="Writing under .claude/local/ via Bash (redirect) — use the Write/Edit tool instead (Bash writes under .claude/ stall autonomous /goal runs on a permission prompt; see ADR 0006)"
fi

# --- Block or allow ---
if [ -n "$REASON" ]; then
    printf 'BLOCKED: %s\nCommand: %s\n' "$REASON" "$SAFE_COMMAND" >> "$AUDIT_LOG" 2>/dev/null
    echo "BLOCKED by safety hook: $REASON" >&2
    exit 2
fi

forge_allow
