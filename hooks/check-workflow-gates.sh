#!/bin/bash
# .claude/hooks/check-workflow-gates.sh
# PreToolUse hook for Bash: blocks commit/push/PR if quality gates aren't complete.
#
# Fires BEFORE Bash commands. Only activates when:
# 1. An active workflow exists in .claude/local/state.md (Command != none)
# 2. The command is git commit, git push, or gh pr create
# 3. Always-required quality gate checklist items aren't checked off
#
# Gated markers (canonical vocabulary — see rules/testing.md "Canonical E2E gate vocabulary"):
#   "Code review loop"  — code review must pass
#   "Simplified"        — code simplification must run
#   "Verified (tests"   — unit tests + lint + types + migrations must pass
#   "E2E verified"      — Phase 5.4 E2E must pass OR be explicitly N/A with reason
#
# Non-gated (conditional) items like "E2E use cases designed" and "E2E regression
# passed" stay advisory — the model decides if they apply. The E2E verified gate
# has an explicit N/A escape: `- [x] E2E verified — N/A: <reason>`.
#
# Input (JSON via stdin): {session_id, cwd, tool_name, tool_input: {command}}
# Block: exit 2 + message on stderr
# Allow: exit 0
#
# Requirements: jq (recommended, grep fallback)

INPUT=$(cat)

codex_available() {
    command -v codex >/dev/null 2>&1
}

# --- Parse command ---
if command -v jq &> /dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
    COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
fi

[ -z "$COMMAND" ] && exit 0

# --- Only gate ship actions ---
IS_SHIP=false
echo "$COMMAND" | grep -qE '^\s*git\s+commit\b' && IS_SHIP=true
echo "$COMMAND" | grep -qE '^\s*git\s+push\b' && IS_SHIP=true
echo "$COMMAND" | grep -qE '^\s*gh\s+pr\s+create\b' && IS_SHIP=true

# Not a ship action — allow immediately
$IS_SHIP || exit 0

# --- Check for active workflow (post PR #2: state file is .claude/local/state.md) ---
STATE_FILE=".claude/local/state.md"

if [ ! -f "$STATE_FILE" ]; then
    # Hard-cut: do NOT fall back to CONTINUITY.md.
    # Emit friendly breadcrumb on stderr, exit 0 (don't gate — nothing to enforce).
    echo "ℹ check-workflow-gates: $STATE_FILE not found." >&2
    echo "  If you have a legacy CONTINUITY.md and just upgraded, run setup --migrate" >&2
    exit 0
fi

# Scope extraction to ONLY the `## Workflow` section. Migrated content (e.g.,
# from `setup.sh --migrate` ingesting old CONTINUITY.md "### Done" entries that
# mention prior workflow scaffolds) can leave stray `| Command |` lines or
# `### Checklist` headings elsewhere in the file. A whole-file grep with
# `head -1` would pick the first match — which can be the stray, not the
# canonical scaffold — and gate (or fail to gate) on bogus content.
WORKFLOW_BLOCK=$(awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag' "$STATE_FILE" 2>/dev/null)

# Use flexible whitespace matching — formatters may pad table cells
WORKFLOW_CMD=$(echo "$WORKFLOW_BLOCK" | grep -iE '\|\s*Command\s*\|' | head -1 | awk -F'|' '{print $3}' | xargs)
# No active workflow — allow
[ -z "$WORKFLOW_CMD" ] && exit 0
[ "$WORKFLOW_CMD" = "none" ] && exit 0
[ "$WORKFLOW_CMD" = "—" ] && exit 0
[ "$WORKFLOW_CMD" = "-" ] && exit 0

# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard
#
# When /forge-goal is active (## /goal session has a non-empty nonce in state.md),
# gh pr create requires an explicit ## PR authorization line with matching nonce +
# current HEAD SHA. The line is written by the workflow agent after the user
# answers YES to the AskUserQuestion PR-create modal.
#
# ACTIVE definition: GOAL_NONCE is non-empty after parsing. An empty nonce cell,
# a missing /goal session section, or missing state.md → guard is a no-op.
#
# LAST-LINE defense: if state.md has multiple PR auth lines (state corruption),
# the guard uses the LAST one. Proper REPLACE semantics keep exactly one line;
# multiple lines surface as a diagnostic in the error message.
#
# When /forge-goal is NOT active, this guard is a no-op and the existing
# checklist-completion guard below runs unchanged.
# ---------------------------------------------------------------------------
if echo "$COMMAND" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create\b'; then
    if [ -f "$STATE_FILE" ]; then
        # CRLF normalize before awk anchors (matches Layer 1 parser pattern)
        GOAL_BLOCK=$(tr -d '\r' < "$STATE_FILE" \
                    | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag')
        GOAL_NONCE=""
        if [ -n "$GOAL_BLOCK" ]; then
            GOAL_NONCE=$(echo "$GOAL_BLOCK" \
                        | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
                        | head -1 | awk -F'|' '{print $3}' | tr -d ' \t')
        fi
        if [ -n "$GOAL_NONCE" ]; then
            # /forge-goal is active (non-empty nonce); enforce PR-auth requirements
            HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

            # Use LAST matching auth line (stale-duplicate defense; REPLACE semantics
            # should keep exactly one, but guard defensively against state corruption)
            PR_AUTH_LINE=$(tr -d '\r' < "$STATE_FILE" \
                          | grep -E '^-[[:space:]]*\[x\][[:space:]]+PR creation authorized' \
                          | tail -1)

            # Count auth lines for diagnostic
            AUTH_LINE_COUNT=$(tr -d '\r' < "$STATE_FILE" \
                             | grep -c '^-[[:space:]]*\[x\][[:space:]]*PR creation authorized' 2>/dev/null || echo 0)

            if [ -z "$PR_AUTH_LINE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md." >&2
                echo "" >&2
                echo "A /forge-goal-driven workflow is active (nonce: $GOAL_NONCE)." >&2
                echo "PR creation requires user authorization via AskUserQuestion." >&2
                echo "On user YES, write (REPLACE any existing ## PR authorization content):" >&2
                echo "  - [x] PR creation authorized — \`<ts>\` — nonce=\`<n>\` — head=\`<sha>\`" >&2
                exit 2
            fi

            if [ "$AUTH_LINE_COUNT" -gt 1 ]; then
                echo "WORKFLOW GATE WARNING: Multiple PR authorization lines found in state.md (count: $AUTH_LINE_COUNT)." >&2
                echo "This indicates state.md corruption — REPLACE semantics should keep exactly one line." >&2
                echo "Using the LAST authorization line for this check. Consider cleaning state.md." >&2
            fi

            # Extract nonce and head from the auth line. Pattern:
            # - [x] PR creation authorized — `<ts>` — nonce=`<nonce>` — head=`<sha>`
            AUTH_NONCE=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*nonce=`([^`]+)`.*/\1/')
            AUTH_HEAD=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*head=`([^`]+)`.*/\1/')

            if [ "$AUTH_NONCE" != "$GOAL_NONCE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch." >&2
                echo "Session nonce:   $GOAL_NONCE" >&2
                echo "Auth line nonce: $AUTH_NONCE" >&2
                echo "Stale authorization from a previous /forge-goal session. Re-authorize via AskUserQuestion." >&2
                echo "  - [x] PR creation authorized — \`<ts>\` — nonce=\`<n>\` — head=\`<sha>\`" >&2
                exit 2
            fi

            if [ -z "$HEAD_SHA" ] || [ "$AUTH_HEAD" != "$HEAD_SHA" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch." >&2
                echo "Current HEAD:   $HEAD_SHA" >&2
                echo "Auth line head: $AUTH_HEAD" >&2
                echo "Commits added since authorization; re-authorize at the new HEAD." >&2
                echo "  - [x] PR creation authorized — \`<ts>\` — nonce=\`<n>\` — head=\`<sha>\`" >&2
                exit 2
            fi

            # All checks passed; fall through to the existing checklist guard
        fi
    fi
fi

# --- Active workflow: check always-required quality gates ---
# Extract the Checklist section (between ### Checklist and next ## or ### heading
# inside the Workflow block — staying scoped prevents stray "### Checklist"
# headings in migrated State content from being picked up).
CHECKLIST=$(echo "$WORKFLOW_BLOCK" | sed -n '/^### Checklist/,$p')

# Only gate on the 4 pre-ship quality gates:
#   "Code review loop" — code review must pass before shipping
#   "Simplified" — code simplification must run before shipping
#   "Verified (tests" — tests/lint/types must pass before shipping
#   "E2E verified" — Phase 5.4 must pass OR be checked [x] with an N/A reason
# Explicitly exclude non-gate items that contain similar words:
#   "PR reviews addressed" — happens AFTER PR, not a pre-ship gate
#   "Plugins verified" — pre-flight check, not a quality gate
#   "Plan review loop" — design phase discipline, not a pre-ship gate
#   "E2E use cases designed" — Phase 3.2b, conditional on user-facing change
#   "E2E regression passed" — Phase 5.4b, conditional on accumulated UCs
#   "E2E use cases graduated" / "E2E specs graduated" — post-PASS housekeeping
UNCHECKED=$(echo "$CHECKLIST" | grep '\- \[ \]' | grep -iE '(Code review loop|Simplified|Verified \(tests|E2E verified)' || true)

if [ -n "$UNCHECKED" ]; then
    UNCHECKED_COUNT=$(echo "$UNCHECKED" | wc -l | tr -d ' ')
    MISSING=$(echo "$UNCHECKED" | sed 's/- \[ \] /  - /')
    echo "WORKFLOW GATE: $UNCHECKED_COUNT required quality gate(s) incomplete." >&2
    echo "Complete these before shipping:" >&2
    echo "$MISSING" >&2
    echo "" >&2
    echo "How to clear each gate:" >&2
    echo "  - Code review loop:  run /codex review + /pr-review-toolkit:review-pr, fix findings" >&2
    echo "  - Simplified:        run /simplify" >&2
    echo "  - Verified (tests):  run the verify-app agent" >&2
    echo "  - E2E verified:      run the verify-e2e agent AND persist its report, OR mark N/A:" >&2
    echo '                         - [x] E2E verified — N/A: <specific reason>' >&2
    echo "  See .claude/rules/testing.md for the canonical gate vocabulary." >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Evidence-based gate for E2E verified
#
# The checklist-only gate above is paperwork enforcement: a bad-faith actor
# can type '[x] E2E verified ...' without actually running the verify-e2e
# agent. This check binds the '[x] E2E verified' claim to a real filesystem
# artifact — a report file in tests/e2e/reports/ with mtime later than the
# branch-off point.
#
# Escape valve: the N/A form ('[x] E2E verified — N/A: <reason>') is trusted
# and skips the evidence check. Human reviewers catch lazy N/A justifications.
#
# Failure modes intentionally accepted:
#   - User on main (no branch) → can't compute merge-base → skip evidence
#   - No git / no main or master branch → skip evidence
#   - Report path writes fail → next commit-attempt catches it
# ---------------------------------------------------------------------------
E2E_CHECKED_LINE=$(echo "$CHECKLIST" | grep -E '^\s*- \[x\]\s+E2E verified' | head -1)

if [ -n "$E2E_CHECKED_LINE" ] && ! echo "$E2E_CHECKED_LINE" | grep -qE 'N/A:'; then
    # [x] E2E verified checked without N/A → require a fresh report file.

    # Find the branch-off commit (try main, fall back to master, else skip).
    BRANCH_OFF=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || true)

    # If HEAD itself IS the branch-off point (i.e., user is on main/master
    # directly, not a feature branch), there's no meaningful "produced on
    # this branch" comparison to make. Skip the evidence check — matches
    # the documented "on main → skip" contract in rules/testing.md.
    HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || true)
    if [ -n "$BRANCH_OFF" ] && [ -n "$HEAD_SHA" ] && [ "$BRANCH_OFF" = "$HEAD_SHA" ]; then
        BRANCH_OFF=""  # Force the skip path below
    fi

    if [ -n "$BRANCH_OFF" ]; then
        BRANCH_OFF_TS=$(git log -1 --format=%ct "$BRANCH_OFF" 2>/dev/null || echo "")
    else
        BRANCH_OFF_TS=""
    fi

    # Detect platform for stat syntax (GNU vs BSD/macOS)
    if stat -c %Y /dev/null >/dev/null 2>&1; then
        STAT_MTIME_CMD='stat -c %Y'
    else
        STAT_MTIME_CMD='stat -f %m'
    fi

    # Look for at least one fresh report. A "fresh" report has mtime greater
    # than the branch-off commit's timestamp — meaning it was produced on
    # THIS branch, not inherited from a previous feature.
    FRESH_REPORT_FOUND=0
    if [ -n "$BRANCH_OFF_TS" ] && [ -d "tests/e2e/reports" ]; then
        for report in tests/e2e/reports/*.md; do
            [ -f "$report" ] || continue
            REPORT_MTIME=$($STAT_MTIME_CMD "$report" 2>/dev/null || echo "0")
            if [ "$REPORT_MTIME" -gt "$BRANCH_OFF_TS" ] 2>/dev/null; then
                FRESH_REPORT_FOUND=1
                break
            fi
        done
    elif [ -z "$BRANCH_OFF_TS" ]; then
        # No merge-base (user on main, or no main/master branch).
        # Skip evidence check rather than fail closed — this is a degraded
        # environment, not a policy violation.
        FRESH_REPORT_FOUND=1
    fi

    if [ "$FRESH_REPORT_FOUND" -eq 0 ]; then
        echo "WORKFLOW GATE: E2E verified is checked, but no fresh report was found." >&2
        echo "" >&2
        echo "The checklist says [x] E2E verified, but tests/e2e/reports/ has no" >&2
        echo "report file newer than this branch's commit off main. That usually means" >&2
        echo "the verify-e2e agent was never actually run on this branch." >&2
        echo "" >&2
        echo "Either:" >&2
        echo "  (a) Run the verify-e2e agent and have the main agent persist its" >&2
        echo "      report to tests/e2e/reports/<YYYY-MM-DD-HH-MM>-<feature>.md," >&2
        echo "  (b) Mark the gate N/A with justification:" >&2
        echo '        - [x] E2E verified — N/A: <specific reason>' >&2
        echo "" >&2
        echo "See .claude/rules/testing.md for the full policy." >&2
        exit 2
    fi
fi

# ---------------------------------------------------------------------------
# Evidence-based gate for Plan review loop PASS
#
# The msai-v2 v5.38 /goal run violated this by ticking [x] Plan review loop
# (6 iterations) — PASS while iter-6 still had 2 P1 findings. Patching the
# plan and skipping iter-7 confirmation is exactly the discipline drift this
# gate prevents.
#
# Required when checkbox is "- [x] Plan review loop (N iterations) — PASS":
#   - a matching per-iter clean line for iteration N
#   - the line's plan_sha matches sha256 of the referenced plan file
#
# Canonical clean-line stem (referenced by tests/template/test-contracts.sh
# parity check): Plan review iteration N — codex clean — plan=`<path>`
#
# Escape valves (graceful failure modes):
#   - "codex unavailable, user-confirmed" — rejected if `command -v codex`
#     succeeds at gate time (prevents inventing consent)
#   - "codex unavailable, council-confirmed — council_nonce=..." — accepted
#     (council provides the human-judgment audit trail)
#   - No `[x] Plan review loop` at all → gate inert (simple-fix path)
# ---------------------------------------------------------------------------
PLAN_PASS_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Plan review loop \([0-9]+ iterations\) — PASS' \
    | tail -1)

if [ -n "$PLAN_PASS_LINE" ]; then
    # Extract N from "Plan review loop (N iterations) — PASS"
    PLAN_N=$(echo "$PLAN_PASS_LINE" | sed -E 's/.*Plan review loop \(([0-9]+) iterations\).*/\1/')

    # Find the per-iter clean line for iteration N (LAST matching line — defensive
    # against stale duplicates, matches PR-authorization pattern at line 115-117).
    PLAN_CLEAN=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Plan review iteration $PLAN_N — " \
        | tail -1)

    if [ -z "$PLAN_CLEAN" ]; then
        echo "WORKFLOW GATE: [x] Plan review loop ($PLAN_N iterations) — PASS lacks per-iter clean evidence." >&2
        echo "" >&2
        echo "Required: a matching line in state.md (### Checklist):" >&2
        echo "  - [x] Plan review iteration $PLAN_N — codex clean — plan=\`<plan-file>\` — plan_sha=\`<sha256>\` — ts=\`<ts>\`" >&2
        echo "" >&2
        echo "Run iter-$PLAN_N reviewers and append the clean line, OR uncheck the loop" >&2
        echo "and run another iteration. See rules/workflow.md Revision Loop Protocol." >&2
        exit 2
    fi

    # Branch on the clean-line variant
    if echo "$PLAN_CLEAN" | grep -q "codex clean"; then
        # Extract plan path + claimed sha
        PLAN_PATH=$(echo "$PLAN_CLEAN" | sed -E 's/.*plan=`([^`]+)`.*/\1/')
        CLAIMED_SHA=$(echo "$PLAN_CLEAN" | sed -E 's/.*plan_sha=`([^`]+)`.*/\1/')

        if [ -z "$PLAN_PATH" ] || [ -z "$CLAIMED_SHA" ]; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N clean line is malformed." >&2
            echo "Expected format: codex clean — plan=\`<path>\` — plan_sha=\`<sha256>\` — ts=\`<ts>\`" >&2
            echo "Got: $PLAN_CLEAN" >&2
            exit 2
        fi

        if [ ! -f "$PLAN_PATH" ]; then
            echo "WORKFLOW GATE: Plan review evidence references missing file: $PLAN_PATH" >&2
            exit 2
        fi

        if command -v shasum >/dev/null 2>&1; then
            ACTUAL_SHA=$(shasum -a 256 "$PLAN_PATH" | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            ACTUAL_SHA=$(sha256sum "$PLAN_PATH" | awk '{print $1}')
        else
            echo "WORKFLOW GATE: cannot verify plan_sha (no shasum or sha256sum command available)." >&2
            echo "Install coreutils or perl-Digest::SHA, OR mark the gate N/A." >&2
            exit 2
        fi

        # Normalize both sides to lowercase before compare. Get-FileHash in
        # PowerShell returns uppercase by default; an agent writing the clean
        # line from a PS host would otherwise mismatch our sha256sum output.
        ACTUAL_SHA=$(echo "$ACTUAL_SHA" | tr 'A-Z' 'a-z')
        CLAIMED_SHA=$(echo "$CLAIMED_SHA" | tr 'A-Z' 'a-z')

        if [ "$ACTUAL_SHA" != "$CLAIMED_SHA" ]; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N plan_sha mismatch." >&2
            echo "  Claimed (state.md): $CLAIMED_SHA" >&2
            echo "  Actual ($PLAN_PATH): $ACTUAL_SHA" >&2
            echo "" >&2
            echo "The plan file changed since iter-$PLAN_N was reviewed. Re-run reviewers." >&2
            exit 2
        fi
    elif echo "$PLAN_CLEAN" | grep -q "codex unavailable, user-confirmed"; then
        # Hard reject if codex is actually available at gate time
        if codex_available; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N claims 'codex unavailable, user-confirmed'" >&2
            echo "but \`codex\` is available on this machine at gate time." >&2
            echo "" >&2
            echo "Re-run the iter-$PLAN_N codex review OR re-mark with the real outcome." >&2
            exit 2
        fi
        # codex genuinely unavailable → accept the user-confirmed escape
    elif echo "$PLAN_CLEAN" | grep -q "codex unavailable, council-confirmed"; then
        # Council escape requires a UUID-format nonce.
        COUNCIL_NONCE=$(echo "$PLAN_CLEAN" | sed -E 's/.*council_nonce=`([^`]+)`.*/\1/')
        if ! echo "$PLAN_CLEAN" | grep -qE 'council_nonce=`[^`]+`'; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N council-confirmed escape missing council_nonce." >&2
            exit 2
        fi
        if ! echo "$COUNCIL_NONCE" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N council_nonce malformed (expected UUID)." >&2
            echo "Got: $COUNCIL_NONCE" >&2
            exit 2
        fi
    else
        echo "WORKFLOW GATE: Plan review iteration $PLAN_N clean line variant not recognized." >&2
        echo "Got: $PLAN_CLEAN" >&2
        echo "" >&2
        echo "Accepted variants (see rules/workflow.md):" >&2
        echo "  - codex clean — plan=\`<path>\` — plan_sha=\`<sha>\` — ts=\`<ts>\`" >&2
        echo "  - codex unavailable, user-confirmed — ts=\`<ts>\`  (only if codex CLI not installed)" >&2
        echo "  - codex unavailable, council-confirmed — council_nonce=\`<n>\` — ts=\`<ts>\`" >&2
        exit 2
    fi
fi

# ---------------------------------------------------------------------------
# Evidence-based gate for Code review loop PASS
#
# Mirrors the plan-review gate but binds to git HEAD (because code-review iters
# commit fixes between rounds — HEAD changes are the natural freshness primitive).
# Codex+PR-toolkit are BOTH required for the same iteration at the current HEAD,
# matching the existing build-evidence.sh:compute_reviewer_gate semantics.
#
# Canonical clean-line stem (referenced by tests/template/test-contracts.sh
# parity check): Code review iteration N — codex clean — head=`<sha>`
# ---------------------------------------------------------------------------
CODE_PASS_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Code review loop \([0-9]+ iterations\) — PASS' \
    | tail -1)

HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
# Degraded env (no git repo) → skip code-review evidence check entirely.
# Mirrors existing E2E gate pattern at check-workflow-gates.sh:259-263.
# The hook fires on git commit/push/gh pr create — if those work, HEAD exists.
# If git is unavailable, the ship action itself can't succeed, so the gate is moot.
if [ -n "$CODE_PASS_LINE" ] && [ -n "$HEAD_SHA" ]; then
    CODE_N=$(echo "$CODE_PASS_LINE" | sed -E 's/.*Code review loop \(([0-9]+) iterations\).*/\1/')

    # Validate codex side (last-line semantics — defensive against stale duplicates)
    CODEX_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Code review iteration $CODE_N — codex " \
        | tail -1)
    TOOLKIT_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Code review iteration $CODE_N — pr-toolkit " \
        | tail -1)

    if [ -z "$CODEX_LINE" ] || [ -z "$TOOLKIT_LINE" ]; then
        echo "WORKFLOW GATE: [x] Code review loop ($CODE_N iterations) — PASS lacks per-iter clean evidence." >&2
        echo "" >&2
        echo "Required: matching lines in state.md (### Checklist):" >&2
        echo "  - [x] Code review iteration $CODE_N — codex clean — head=\`$HEAD_SHA\`" >&2
        echo "  - [x] Code review iteration $CODE_N — pr-toolkit clean — head=\`$HEAD_SHA\`" >&2
        echo "" >&2
        echo "Run iter-$CODE_N reviewers + append both clean lines, OR uncheck the loop." >&2
        exit 2
    fi

    # Per-line validation: head match required for ALL variants (clean + escapes),
    # council_nonce required for council-confirmed escapes.
    for tool_line in "codex:$CODEX_LINE" "pr-toolkit:$TOOLKIT_LINE"; do
        TOOL=$(echo "$tool_line" | cut -d: -f1)
        LINE=$(echo "$tool_line" | cut -d: -f2-)

        # Every variant must carry head=`<sha>` matching current HEAD —
        # prevents stale-HEAD shortcut via unavailable escapes.
        LINE_HEAD=$(echo "$LINE" | sed -E 's/.*head=`([0-9a-f]+)`.*/\1/')
        if ! echo "$LINE" | grep -qE 'head=`[0-9a-f]+`'; then
            echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL line missing head=\`<sha>\`." >&2
            echo "Got: $LINE" >&2
            exit 2
        fi
        if [ "$LINE_HEAD" != "$HEAD_SHA" ]; then
            echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL line is at a stale HEAD (head mismatch)." >&2
            echo "  Line head:    $LINE_HEAD" >&2
            echo "  Current head: $HEAD_SHA" >&2
            echo "" >&2
            echo "New commits landed since iter-$CODE_N. Re-run $TOOL at current head." >&2
            exit 2
        fi

        if echo "$LINE" | grep -q "$TOOL clean"; then
            : # clean variant — head already verified above
        elif echo "$LINE" | grep -q "$TOOL unavailable, user-confirmed"; then
            # Hard reject if the tool is actually available at gate time.
            # (pr-toolkit availability isn't detectable at shell level; we trust
            # user-confirmed for it. Codex catches the primary fakery vector.)
            if [ "$TOOL" = "codex" ] && codex_available; then
                echo "WORKFLOW GATE: Code review iteration $CODE_N claims '$TOOL unavailable, user-confirmed'" >&2
                echo "but \`codex\` is available on this machine at gate time." >&2
                exit 2
            fi
        elif echo "$LINE" | grep -q "$TOOL unavailable, council-confirmed"; then
            # Council escape requires a UUID-format nonce
            COUNCIL_NONCE=$(echo "$LINE" | sed -E 's/.*council_nonce=`([^`]+)`.*/\1/')
            if ! echo "$LINE" | grep -qE 'council_nonce=`[^`]+`'; then
                echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL council-confirmed escape missing council_nonce." >&2
                exit 2
            fi
            if ! echo "$COUNCIL_NONCE" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
                echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL council_nonce malformed (expected UUID)." >&2
                echo "Got: $COUNCIL_NONCE" >&2
                exit 2
            fi
        else
            echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL line variant not recognized." >&2
            echo "Got: $LINE" >&2
            exit 2
        fi
    done
fi

exit 0
