#!/usr/bin/env bash
# One command evaluator shared by Claude and Codex v6 subagent producers.
set -u

INPUT=$(cat 2>/dev/null)
json_value() {
    local expr="$1"
    if command -v jq >/dev/null 2>&1; then printf '%s' "$INPUT" | jq -r "$expr // \"\"" 2>/dev/null || true
    else printf '%s' "$INPUT" | sed -nE "s/.*\"${expr#.}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -1
    fi
}
CWD=$(json_value '.cwd')
AGENT_TYPE=$(json_value '.agent_type')
TASK_ID=$(json_value '.agent_id')
[ -n "$TASK_ID" ] || TASK_ID=$(json_value '.task_id')

# Unconverted producers remain under the legacy Claude prompt evaluator through
# Task 9. The command hook is authoritative only for an agent type positively
# bound to the installed capability marker.
[ "$AGENT_TYPE" = forge-v6-producer ] || { printf '{}\n'; exit 0; }
[ -n "$CWD" ] && [ -d "$CWD" ] || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: missing trusted cwd" >&2; exit 2; }
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] && ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: cwd outside Git" >&2; exit 2; }
CAP="$ROOT/.forge/workflow-capabilities.tsv"
grep -q $'^forge\tsubagent-review-receipt\t'"$AGENT_TYPE"$'\tforge\t.*\tforge-subagent-review-v1\tclaude,codex$' "$CAP" 2>/dev/null \
    || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: v6 producer schema is not installed" >&2; exit 2; }
case "$TASK_ID" in ''|*[!A-Za-z0-9._-]*) echo "FORGE_SUBAGENT_REVIEW_BLOCKED: invalid task id" >&2; exit 2 ;; esac
RECEIPT_DIR="$ROOT/.forge/local/reviews/$TASK_ID"
case "$RECEIPT_DIR" in "$ROOT"/.forge/local/reviews/*) ;; *) exit 2 ;; esac
for ancestor in "$ROOT/.forge" "$ROOT/.forge/local" "$ROOT/.forge/local/reviews" "$RECEIPT_DIR"; do
    [ ! -L "$ancestor" ] || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: aliased receipt path" >&2; exit 2; }
done
[ -d "$RECEIPT_DIR" ] || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: missing receipt directory for $TASK_ID" >&2; exit 2; }
PHYSICAL_RECEIPT_DIR=$(cd "$RECEIPT_DIR" 2>/dev/null && pwd -P)
case "$PHYSICAL_RECEIPT_DIR" in "$ROOT"/.forge/local/reviews/*) ;; *) echo "FORGE_SUBAGENT_REVIEW_BLOCKED: receipt path escapes project-local storage" >&2; exit 2 ;; esac
HEAD_SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
[ -n "$HEAD_SHA" ] || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: no current HEAD" >&2; exit 2; }

value() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }
for kind in spec quality; do
    receipt="$RECEIPT_DIR/$kind.receipt"
    [ -f "$receipt" ] && [ ! -L "$receipt" ] \
        || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: missing $kind receipt for $TASK_ID" >&2; exit 2; }
    [ "$(value "$receipt" format)" = forge-subagent-review-v1 ] \
        && [ "$(value "$receipt" task_id)" = "$TASK_ID" ] \
        && [ "$(value "$receipt" kind)" = "$kind" ] \
        && [ "$(value "$receipt" verdict)" = clean ] \
        && [ "$(value "$receipt" head)" = "$HEAD_SHA" ] \
        || { echo "FORGE_SUBAGENT_REVIEW_BLOCKED: stale, malformed, or non-clean $kind receipt for $TASK_ID" >&2; exit 2; }
done
printf '{}\n'
exit 0
