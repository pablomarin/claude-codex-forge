#!/usr/bin/env bash
# hooks/build-evidence.sh — emit FORGE_GOAL_EVIDENCE JSON to STDERR.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers.
# Stop hook (check-state-updated.sh) invokes this each turn so the Haiku
# verifier inside an active /goal sees the evidence in the transcript.

set -u

NOW_UNIX=$(date +%s)

# Skeleton emits minimal JSON. Tasks 3-7 fill in real fields.
{
    echo "FORGE_GOAL_EVIDENCE_BEGIN"
    printf '{'
    printf '"type":"forge_goal_evidence",'
    printf '"schema_version":1,'
    printf '"produced_at_unix":%d,' "$NOW_UNIX"
    printf '"session_nonce":null,'
    printf '"workflow_command":null,'
    printf '"warnings":[],'
    printf '"errors":[]'
    printf '}\n'
    echo "FORGE_GOAL_EVIDENCE_END"
} >&2

exit 0
