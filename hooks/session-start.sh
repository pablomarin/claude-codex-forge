#!/bin/bash
# SessionStart hook: silently inject git context into Claude.
# Source-gated: git fetch + behind-check ONLY on startup|resume.
# Drift surfaced via additionalContext (SessionStart cannot block — exit 2 is advisory).

set -u

# Read source from stdin JSON; degrade if jq missing or input malformed.
INPUT=$(cat 2>/dev/null)
if command -v jq &>/dev/null; then
    SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // ""' 2>/dev/null)
else
    SOURCE=$(printf '%s' "$INPUT" | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
CONTEXT="Current branch: $BRANCH"

# Fetch + drift check ONLY on startup or resume (not clear/compact).
if [[ "$SOURCE" == "startup" || "$SOURCE" == "resume" ]]; then
    HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    LIB="$HOOK_DIR/lib/default-branch.sh"
    if [[ -f "$LIB" ]]; then
        DEFAULT=$(bash "$LIB" 2>/dev/null) || DEFAULT=""
    else
        DEFAULT=""
    fi

    # Helper-bail breadcrumb: append to additionalContext so Claude sees that drift
    # detection skipped due to helper failure (the only signal path on SessionStart —
    # stderr at exit 0 goes to debug log only, not to user or Claude).
    if [[ -z "$DEFAULT" ]]; then
        CONTEXT="$CONTEXT (drift check skipped — default-branch helper bailed)"
    fi

    if [[ -n "$DEFAULT" ]]; then
        # Pick a timeout binary if available (gtimeout for macOS+brew, timeout for Linux/CI).
        # If neither exists, skip the cap — git's connect timeout (~75s) is the upper bound.
        TIMEOUT_CMD=""
        if command -v gtimeout &>/dev/null; then TIMEOUT_CMD="gtimeout 5"
        elif command -v timeout &>/dev/null; then TIMEOUT_CMD="timeout 5"
        fi

        if $TIMEOUT_CMD git fetch origin --quiet 2>/dev/null; then
            # Verify BOTH refs exist before rev-list — without this, a missing local
            # <default> branch (e.g., shallow/single-branch clone) makes rev-list exit
            # 128 with empty stdout, silently masking a real config problem as "0 behind".
            if git rev-parse --verify "$DEFAULT" >/dev/null 2>&1 \
               && git rev-parse --verify "origin/$DEFAULT" >/dev/null 2>&1; then
                BEHIND=$(git rev-list --count "$DEFAULT..origin/$DEFAULT" 2>/dev/null) || BEHIND=""
                if [[ -n "$BEHIND" && "$BEHIND" =~ ^[0-9]+$ && "$BEHIND" -gt 0 ]]; then
                    CONTEXT="$CONTEXT (default branch '$DEFAULT' is $BEHIND commits behind origin — pull before starting work)"
                fi
            fi
        fi
    fi

    # Forge version drift (advisory): compare the project's pinned version
    # (.claude/.forge-version, committed downstream) against THIS machine's version
    # (~/.claude/.forge-version, written by setup). Direction-aware; fail-open under
    # `set -u` (guard ${HOME:-} / ${CLAUDE_PROJECT_DIR:-}); never blocks.
    PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
    if [[ -n "$PROJ" ]] && [[ -n "${HOME:-}" ]]; then
        # Take only the first line + strip whitespace, then require a clean X.Y on
        # BOTH sides — a malformed/multiline stamp fails open (no advisory) and can
        # never inject a newline into the emitted context (Codex code-review P2-2).
        PIN=$(head -1 "$PROJ/.claude/.forge-version" 2>/dev/null | tr -d '[:space:]')
        MINE=$(head -1 "$HOME/.claude/.forge-version" 2>/dev/null | tr -d '[:space:]')
        if [[ "$PIN" =~ ^[0-9]+\.[0-9]+$ ]] && [[ "$MINE" =~ ^[0-9]+\.[0-9]+$ ]] && [[ "$PIN" != "$MINE" ]]; then
            # Portable numeric compare (no GNU-only `sort -V`; Codex iter-3 P2). Both
            # validated X.Y; 10# forces base-10. "mine older" → warn against upgrading.
            if [ "$((10#${MINE%%.*}))" -lt "$((10#${PIN%%.*}))" ] \
               || { [ "$((10#${MINE%%.*}))" -eq "$((10#${PIN%%.*}))" ] && [ "$((10#${MINE#*.}))" -lt "$((10#${PIN#*.}))" ]; }; then
                CONTEXT="$CONTEXT (this project pins Forge $PIN; you're on $MINE — don't run setup --upgrade here unless you're the designated upgrader)"
            else
                CONTEXT="$CONTEXT (this project pins Forge $PIN; you're on $MINE — fine to work; only upgrade the project as a deliberate PR)"
            fi
        fi
    fi
fi

# Emit JSON
if command -v jq &>/dev/null; then
    jq -n --arg ctx "$CONTEXT" \
      '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
else
    SAFE_CTX=$(printf '%s' "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$SAFE_CTX"
fi
exit 0
