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
# No-code carve-out: a `git commit` that stages ONLY documentation skips the
# code-quality gates for that commit WITHOUT mutating state.md (the gates stay
# `- [ ]` so the real-code ship still enforces). Scope = commit only; push/PR
# always enforce. See the "No-code carve-out" block below for the docs predicate.
#
# Input (JSON via stdin): {session_id, cwd, tool_name, tool_input: {command}}
# Block: exit 2 + message on stderr
# Allow: exit 0
#
# Requirements: jq (recommended, grep fallback)

INPUT=$(cat)

# --- Parse command ---
if command -v jq &> /dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
    COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
fi

[ -z "$COMMAND" ] && exit 0

# --- Only gate ship actions ---
# Ship-verb detection tolerant of two common, fully-legitimate invocation forms
# that a plain `^git commit` anchor misses:
#   - env-assignment prefix:  GIT_AUTHOR_NAME=x git commit ...   /  FOO=bar git push
#   - git global options:     git -C <dir> commit ...           /  git -c k=v push
# matched at BOTH the command start AND after a separator (&&, ||, ;, |).
#
# KNOWN RESIDUAL (accepted, fail-safe — conscious scope decision 2026-05-26):
# exotic wrappers — subshell `(git push)`, control-flow `if true; then git push; fi`,
# and command-substitution `$(git push)` — are NOT matched here. They are rare,
# non-idiomatic ways to ship; missing them yields a non-block (exit 0), never a
# crash. Robust shell-command parsing is out of scope for this gate. Pushes/PRs
# also re-enter this hook at push/PR time against the stable HEAD.
# env-assignment prefix: NAME=VALUE followed by whitespace, zero or more times.
# VALUE may be bare, 'single-quoted', "double-quoted" (may contain spaces), or
# empty — covering forms like `GIT_AUTHOR_NAME='Pablo Marin' git commit` and
# `FOO= git push`. Double-quoted bash string: single quotes are literal, the
# inner double quotes are escaped.
_ENVP="([A-Za-z_][A-Za-z0-9_]*=('[^']*'|\"[^\"]*\"|[^[:space:]]*)[[:space:]]+)*"
_GITOPT='([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*'
_SHIP_VERB="${_ENVP}(git${_GITOPT}[[:space:]]+(commit|push)\b|gh[[:space:]]+pr[[:space:]]+create\b)"

# Normalize command separators ONCE, BEFORE ship detection: real newlines, CRs,
# AND (no-jq fallback) literal \n / \r escape sequences all become `;`. A
# multi-line or escaped-multiline tool call (`echo ok<newline>git push`,
# `git commit -m x\ngit push`) must surface its later ship verbs to BOTH the
# ship-detection and the compound guard — else a second ship action slips through
# ungated (Codex P1/P2). jq decodes \n → real newline; the grep fallback leaves
# literal \n, so handle both. False positives (a literal `\n`/`;` inside a commit
# message) only ask the user to split the command — fail-safe.
COMMAND_NORM=$(printf '%s' "$COMMAND" | sed -E 's/\\[nr]/;/g' | tr '\n\r' ';;')

IS_SHIP=false
echo "$COMMAND_NORM" | grep -qE "^[[:space:]]*${_SHIP_VERB}" && IS_SHIP=true
echo "$COMMAND_NORM" | grep -qE "[&|;]+[[:space:]]*${_SHIP_VERB}" && IS_SHIP=true

# Not a ship action — allow immediately
$IS_SHIP || exit 0

# --- Block compound ship commands ---
# A compound like `git commit -m x && git push` validates evidence against the
# pre-commit HEAD, passes, then the chained push ships the new (unreviewed)
# HEAD with no second gate check. Detect a ship verb that appears AFTER a
# command separator (&&, ||, ;, |) and block — force the user to run each
# ship action individually so every one gets its own gate evaluation.
#
# Heuristic: strip everything up to and including the FIRST separator, then
# look for a ship verb in the remainder. Robust enough for the common case;
# quoted separators inside a commit message are a rare false positive and a
# false positive only asks the user to split the command (fail-safe).
# Operates on COMMAND_NORM (built above), so newline-separated and escaped-
# newline ship chains are treated as compound too — a docs-commit carve-out
# below must not exit 0 and let a chained push ship unreviewed code (Codex P1).
COMPOUND_TAIL=$(echo "$COMMAND_NORM" | sed -E 's/^[^&|;]*([&|;]+)//')
if [ "$COMPOUND_TAIL" != "$COMMAND_NORM" ]; then
    if echo "$COMPOUND_TAIL" | grep -qE "$_SHIP_VERB"; then
        echo "WORKFLOW GATE: compound ship command blocked." >&2
        echo "" >&2
        echo "This command chains a ship action (git commit / git push / gh pr create)" >&2
        echo "with another command via &&, ||, ;, or |. Each ship action must be run" >&2
        echo "individually so the workflow gate can validate evidence against the exact" >&2
        echo "HEAD being shipped. A chained 'git commit && git push' would ship a new," >&2
        echo "unreviewed HEAD past the gate." >&2
        echo "" >&2
        echo "Run each ship action as its own command." >&2
        exit 2
    fi
fi

# --- Resolve repo context (bug d) ---
# The hook reads state.md + runs git relative to its process CWD, which can be
# the WRONG repo in worktree sessions. Fix: cd to the harness-provided stdin
# `cwd` (the dir the command actually runs in — trustworthy, NOT parsed from the
# command text), then normalize to the git worktree ROOT so state.md, git, and
# all repo-relative reads resolve in the right repo.
#
# We deliberately do NOT parse `-C <dir>` out of the command for repo context.
# Doing so reliably is impossible with regex — a `-C` can hide inside a quoted
# `-m` message, a `-c key='… -C … '` config value, or a `gh --title`, and every
# attempt opened a fail-open path (cd to a bogus dir → no state.md → exit 0 past
# the gate). A `git -C <other> commit` is therefore evaluated against the session
# cwd (the agent's working repo); that NEVER bypasses the cwd repo's gates, which
# is the safe and correct behavior. (`git -C` is still recognized as a ship verb
# by the detection above — only the repo-context resolution ignores it.)
# Fail-safe: if cwd is absent / not a dir / not in a repo, stay in the current
# CWD. Existing tests pass no `cwd`, so the process CWD governs as before.
if command -v jq &> /dev/null; then
    HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
else
    HOOK_CWD=$(echo "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
fi
[ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD" 2>/dev/null || true
# --show-toplevel is a no-op at the root and fails silently outside a repo.
_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$_TOPLEVEL" ] && [ -d "$_TOPLEVEL" ] && cd "$_TOPLEVEL" 2>/dev/null || true

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
# CRLF normalize BEFORE the awk anchors. A CRLF-encoded state.md (Windows
# checkout) would leave a trailing \r so `^## Workflow$` never matches → empty
# block → hook bails exit 0 → ALL gates silently bypassed. Strip \r first.
WORKFLOW_BLOCK=$(tr -d '\r' < "$STATE_FILE" 2>/dev/null \
    | awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag')

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
# Env-prefix-aware (matches `FOO=bar gh pr create`) so the broadened IS_SHIP
# detection above can't route an env-prefixed PR-create past this auth guard.
if echo "$COMMAND" | grep -qE "^[[:space:]]*${_ENVP}gh[[:space:]]+pr[[:space:]]+create\b"; then
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

# --- Convergence breaker (hook-enforced backstop; ADR 0009) ---
# Placement: BEFORE the docs-only commit carve-out and OUTSIDE the PASS-evidence
# branch — neither a docs-only staged diff, a `Code review loop — N/A:` escape,
# nor an unchecked loop line may bypass it. Runs on every gated ship action.
# ADJUDICATED is the helper's own head-bound detection of the human adjudication
# line (single-sourced parser). For non-workflow repos / uncertified branches the
# helper emits BREAKER:ok, so this block is inert.
RS="$_TOPLEVEL/.claude/hooks/lib/review-scope.sh"
[ ! -f "$RS" ] && RS="$_TOPLEVEL/hooks/lib/review-scope.sh"
BRK_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")
if [ -n "$BRK_HEAD" ] && [ -f "$RS" ] && [ -f "$STATE_FILE" ]; then
    RS_OUT2=$(bash "$RS" "$STATE_FILE" 2>/dev/null)
    if echo "$RS_OUT2" | grep -q "BREAKER:tripped" && echo "$RS_OUT2" | grep -q "ADJUDICATED:no"; then
        echo "WORKFLOW GATE: convergence breaker — POST_CERT_REVIEW_ROUND_LIMIT exceeded." >&2
        echo "$RS_OUT2" | grep -E "POST_CERT_ROUNDS|LAST_CLEAN_HEAD" >&2
        echo "" >&2
        echo "The review loop is not converging. STOP and surface the open tail" >&2
        echo "(severities + in-delta vs certified-unchanged) to the human. Ship is" >&2
        echo "blocked until the human records:" >&2
        echo "  - [x] Post-certification tail adjudicated by human — <decision> — head=\`$BRK_HEAD\` — ts=\`<ISO8601>\`" >&2
        exit 2
    fi
fi

# ---------------------------------------------------------------------------
# No-code carve-out (git commit only) — closes the integrity hole
#
# Before this existed, landing a docs-only checkpoint commit mid-workflow forced
# the operator to mark the 4 ship gates `- [x] N/A`. Nothing ever re-opened them,
# so the later real-code ship could pass with no review evidence. This carve-out
# removes that dance: when a `git commit` stages ONLY documentation, skip the
# code-quality gates for THIS commit WITHOUT writing anything to state.md — the
# boxes stay `- [ ]`, so the real-code commit and the push/PR gate still enforce.
#
# Scope = `git commit` ONLY. push / gh pr create always enforce: their changed-
# file base is unsafe to infer (`--base release/x`, missing upstream), and
# because the carve-out never mutates state, any under-gating at commit time is
# still caught at push/PR (boxes remain unchecked). That push/PR backstop is what
# makes the residual edges below safe.
#
# docs predicate (path ∩ extension, fail-safe): curated doc basenames anywhere
# (README*, CHANGELOG*, LICENSE*, NOTICE, AUTHORS, CONTRIBUTORS*, CONTRIBUTING*,
# CODE_OF_CONDUCT*) OR a prose extension (.md/.mdx/.markdown/.rst) UNDER a docs/
# dir. Everything else is code — incl. docs/foo.py, requirements.txt, and bare
# *.md outside docs/ (so this repo's own commands/*.md, rules/*.md stay gated).
# ---------------------------------------------------------------------------
_is_doc_path() {
    local p="$1" base
    base="${p##*/}"
    # Curated doc files: ONLY extensionless (e.g. LICENSE) or carrying a prose /
    # .txt extension. A curated PREFIX with a code extension (README.py,
    # CHANGELOG.sh) is NOT docs (Codex P2) — it must stay gated.
    case "$base" in
        README|CHANGELOG|LICENSE|NOTICE|AUTHORS|CONTRIBUTORS|CONTRIBUTING|CODE_OF_CONDUCT) return 0 ;;
    esac
    # Prefix glob is intentional: README-dev.md / CHANGELOG-2.md etc. are docs.
    # It can only WIDEN the docs set, which is fail-safe here — the carve-out is
    # commit-only, never mutates state, and is backstopped by the push/PR gate.
    case "$base" in
        README*|CHANGELOG*|LICENSE*|CONTRIBUTORS*|CONTRIBUTING*|CODE_OF_CONDUCT*)
            case "$base" in
                *.md|*.mdx|*.markdown|*.rst|*.txt) return 0 ;;
            esac ;;
    esac
    # Under a docs/ dir AND a prose extension (.txt excluded here so
    # docs/requirements.txt-style manifests stay gated).
    case "$p" in
        docs/*|*/docs/*)
            case "$base" in
                *.md|*.mdx|*.markdown|*.rst) return 0 ;;
            esac ;;
    esac
    return 1
}

# Plain `git commit` only. Decline (→ enforce) when the command uses
# -a/--all/--include/--only/--amend/-p/--patch/-i/--interactive: those commit
# content NOT visible in `git diff --cached` at PreToolUse time, so the staged
# diff can't prove docs-only.
#
# RESIDUAL (accepted, fail-safe): a bare pathspec commit (`git commit -m x src/y.py`,
# docs staged) can't be reliably parsed apart from `-m`'s quoted value, so it may
# skip the COMMIT gate. This is NOT a shipping hole: the carve-out never mutates
# state.md, so the gate boxes stay `- [ ]` and the push/PR gate still blocks the
# branch — the code is reviewed before it can ship. The interactive/-a/-amend
# declines above cover the common "sweeps in extra content" modes.
if echo "$COMMAND" | grep -qE "^[[:space:]]*${_ENVP}git${_GITOPT}[[:space:]]+commit\b" \
   && ! echo "$COMMAND" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[apio][a-zA-Z]*|--all|--include|--only|--amend|--patch|--interactive)([[:space:]]|=|$)'; then
    # --no-renames so a code→docs rename surfaces the old (code) path too.
    STAGED_PATHS=$(git diff --cached --name-status --no-renames 2>/dev/null | awk -F'\t' 'NF>=2{print $2}')
    if [ -n "$STAGED_PATHS" ]; then
        _ALL_DOCS=1
        while IFS= read -r _f; do
            [ -z "$_f" ] && continue
            _is_doc_path "$_f" || { _ALL_DOCS=0; break; }
        done <<EOF
$STAGED_PATHS
EOF
        if [ "$_ALL_DOCS" = "1" ]; then
            exit 0  # docs-only commit — skip code-quality gates, NO state mutation
        fi
    fi
    # Empty staged diff → can't prove docs-only → fall through and enforce (fail-safe).
fi

# --- Active workflow: check always-required quality gates ---
# Extract the Checklist section: from `### Checklist` up to (but not including)
# the NEXT `### ` heading inside the Workflow block. Stopping at the next `### `
# (not just `## `) matches build-evidence's compute_reviewer_gate scoping — so
# evidence lines under a DIFFERENT `### ` subsection of `## Workflow` cannot
# satisfy the hook.
CHECKLIST=$(echo "$WORKFLOW_BLOCK" | awk '
    /^### Checklist/ { flag=1; next }
    flag && /^### / { flag=0 }
    flag { print }
')

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
# ANCHORED: the unchecked marker `- [ ]` must be at line start (modulo leading
# whitespace) AND immediately followed by a gate stem. A two-stage match
# (`grep '- [ ]' | grep <stem>`) false-positives twice: (1) a literal `- [ ]`
# appearing in the *prose* of an already-[x] line (e.g. an N/A justification
# reading "re-opens with `- [ ]` later") re-arms the gate, and (2) an unrelated
# unchecked item whose prose merely mentions a gate name gets counted. Anchoring
# the checkbox + stem together closes both. Keep this single anchored regex.
UNCHECKED=$(echo "$CHECKLIST" | grep -iE '^[[:space:]]*- \[ \][[:space:]]+(Code review loop|Simplified|Verified \(tests|E2E verified)' || true)

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
# Codex is MANDATORY in this repo (Claude × Codex dual-engine). The ONLY escape
# is an N/A justification on the loop line (mirrors the E2E verified — N/A:
# gate). There is no "codex unavailable" escape: if Codex is genuinely down,
# /goal halts and a human takes over.
#
# N/A escape: if the `Plan review loop (N iterations) — PASS` line OR a
# dedicated `- [x] Plan review loop — N/A: <reason>` line carries `N/A:`, the
# evidence check is skipped. Human reviewers catch lazy N/A justifications.
#
#   - No `[x] Plan review loop` at all → gate inert (simple-fix path)
# ---------------------------------------------------------------------------
# N/A escape: any `[x] Plan review loop ... N/A:` line skips the evidence check.
PLAN_NA_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Plan review loop' \
    | grep -E 'N/A:' \
    | head -1)

PLAN_PASS_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Plan review loop \([0-9]+ iterations\) — PASS' \
    | tail -1)

# Any checked `Plan review loop` line — used to detect a checked line that is
# neither a well-formed PASS nor an N/A escape (malformed, bug b).
PLAN_CHECKED_ANY=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Plan review loop' \
    | tail -1)

# PASS-before-N/A (bug a): if a well-formed PASS line exists, its evidence is
# ALWAYS required — a stale `N/A:` line can never mask it. Only when there is no
# PASS line does an N/A escape apply. A checked loop line that is neither → block
# as malformed (bug b: today such a line silently passes).
if [ -n "$PLAN_PASS_LINE" ]; then
    : # enforce evidence below (PASS wins over any N/A line)
elif [ -n "$PLAN_NA_LINE" ]; then
    : # N/A justification present and no PASS line — skip plan-review evidence check
elif [ -n "$PLAN_CHECKED_ANY" ]; then
    echo "WORKFLOW GATE: malformed '[x] Plan review loop' line." >&2
    echo "A checked Plan review loop line must be either:" >&2
    echo "  - [x] Plan review loop (N iterations) — PASS   (with per-iter evidence), OR" >&2
    echo "  - [x] Plan review loop — N/A: <reason>" >&2
    echo "Got: $PLAN_CHECKED_ANY" >&2
    exit 2
fi

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

    # Branch on the clean-line variant. Match the canonical delimited form
    # (— codex clean —), not a bare substring, so "not-codex clean" can't pass.
    # Codex is mandatory: only `codex clean`
    # (plan_sha bound) is accepted. No "codex unavailable" escapes.
    if echo "$PLAN_CLEAN" | grep -qF -- "— codex clean —"; then
        # Presence check BEFORE sed extraction. `sed -E 's/.*plan=`...`.*/\1/'`
        # returns the WHOLE line on no-match, so a clean line missing the
        # plan=/plan_sha= tokens would slip past a non-empty check and hit a
        # garbled "missing file" error. Guard explicitly (mirrors the code-review
        # gate's `grep -qE 'head=`[0-9a-f]+`'` presence check).
        if ! echo "$PLAN_CLEAN" | grep -qE 'plan=`[^`]+`.*plan_sha=`[^`]+`'; then
            echo "WORKFLOW GATE: Plan review iteration $PLAN_N clean line is malformed." >&2
            echo "Expected format: codex clean — plan=\`<path>\` — plan_sha=\`<sha256>\` — ts=\`<ts>\`" >&2
            echo "Got: $PLAN_CLEAN" >&2
            exit 2
        fi

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
    else
        echo "WORKFLOW GATE: Plan review iteration $PLAN_N clean line variant not recognized." >&2
        echo "Got: $PLAN_CLEAN" >&2
        echo "" >&2
        echo "Codex is mandatory in this repo. Accepted forms (see rules/workflow.md):" >&2
        echo "  - codex clean — plan=\`<path>\` — plan_sha=\`<sha>\` — ts=\`<ts>\`" >&2
        echo "  - mark the loop N/A:  - [x] Plan review loop — N/A: <reason>" >&2
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
# Codex is mandatory — no "tool unavailable" escapes. The only escape is an
# N/A justification on the loop line (mirrors the plan-review + E2E gates).
#
# Canonical clean-line stem (referenced by tests/template/test-contracts.sh
# parity check): Code review iteration N — codex clean — head=`<sha>`
# ---------------------------------------------------------------------------
# N/A escape: any `[x] Code review loop ... N/A:` line skips the evidence check.
CODE_NA_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Code review loop' \
    | grep -E 'N/A:' \
    | head -1)

CODE_PASS_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Code review loop \([0-9]+ iterations\) — PASS' \
    | tail -1)

# Any checked `Code review loop` line — for malformed detection (bug b).
CODE_CHECKED_ANY=$(echo "$CHECKLIST" | tr -d '\r' \
    | grep -E '^\s*-\s*\[x\]\s+Code review loop' \
    | tail -1)

HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
# Degraded env (no git repo) → skip code-review evidence check entirely.
# Mirrors existing E2E gate pattern at check-workflow-gates.sh:259-263.
# The hook fires on git commit/push/gh pr create — if those work, HEAD exists.
# If git is unavailable, the ship action itself can't succeed, so the gate is moot.
#
# PASS-before-N/A (bug a): a well-formed PASS line ALWAYS requires its evidence —
# a stale `N/A:` line can never mask it. N/A applies only when there is no PASS
# line (clear CODE_PASS_LINE so the evidence block below is skipped). A checked
# loop line that is neither PASS nor N/A is malformed (bug b) → block.
if [ -n "$CODE_PASS_LINE" ]; then
    : # enforce evidence below (when git is available); PASS wins over any N/A
elif [ -n "$CODE_NA_LINE" ]; then
    CODE_PASS_LINE=""  # no PASS line — N/A escape applies; skip evidence
elif [ -n "$CODE_CHECKED_ANY" ]; then
    echo "WORKFLOW GATE: malformed '[x] Code review loop' line." >&2
    echo "A checked Code review loop line must be either:" >&2
    echo "  - [x] Code review loop (N iterations) — PASS   (with per-iter evidence), OR" >&2
    echo "  - [x] Code review loop — N/A: <reason>" >&2
    echo "Got: $CODE_CHECKED_ANY" >&2
    exit 2
fi

if [ -n "$CODE_PASS_LINE" ] && [ -n "$HEAD_SHA" ]; then
    CODE_N=$(echo "$CODE_PASS_LINE" | sed -E 's/.*Code review loop \(([0-9]+) iterations\).*/\1/')

    # --- v5.54 scoped-review-certification (ADR 0009) ---------------------------
    # $RS was resolved by the convergence-breaker block above (installed path,
    # then forge-internal source path). A mechanical re-stamp row CAN satisfy
    # iteration N WITHOUT an engine pair — it is the evidence by design — so
    # compute MECH_LINE FIRST and gate the legacy pair checks on its absence.
    MECH_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Code review iteration $CODE_N — mechanical re-stamp — scope=mechanical — " | tail -1)

    # Prior-chain context: helper computed EXCLUDING the current iteration's rows,
    # so LAST_CLEAN_HEAD/CERTIFIED describe the state this iteration must chain from.
    RS_PRIOR=$([ -f "$RS" ] && bash "$RS" "$STATE_FILE" --before "$CODE_N" 2>/dev/null || echo "")
    PRIOR_CERTIFIED=$(echo "$RS_PRIOR" | grep -c "CERTIFIED:yes" || true)
    PRIOR_CLEAN_HEAD=$(echo "$RS_PRIOR" | sed -n 's/^LAST_CLEAN_HEAD://p')

    # Validate codex side (last-line semantics — defensive against stale duplicates).
    # Exclude the deliberate deep-pass row (`— codex deep-pass clean —`): it is a
    # SEPARATE tool recorded at the same iteration and must not be tailed into the
    # `— codex clean —` variant check (false-block on the certified happy path).
    CODEX_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Code review iteration $CODE_N — codex " \
        | grep -v -- "— codex deep-pass" \
        | tail -1)
    TOOLKIT_LINE=$(echo "$CHECKLIST" | tr -d '\r' \
        | grep -E "^\s*-\s*\[x\]\s+Code review iteration $CODE_N — pr-toolkit " \
        | tail -1)

    # The engine pair is required ONLY when there is no mechanical re-stamp for
    # this iteration. When MECH_LINE exists, the mechanical line IS the evidence
    # (validated in the scoped branch below) and the pair is absent by design.
    if [ -z "$MECH_LINE" ]; then
        if [ -z "$CODEX_LINE" ] || [ -z "$TOOLKIT_LINE" ]; then
            echo "WORKFLOW GATE: [x] Code review loop ($CODE_N iterations) — PASS lacks per-iter clean evidence." >&2
            echo "" >&2
            echo "Required: matching lines in state.md (### Checklist):" >&2
            echo "  - [x] Code review iteration $CODE_N — codex clean — scope=full — base=\`<merge-base>\` — head=\`$HEAD_SHA\`" >&2
            echo "  - [x] Code review iteration $CODE_N — pr-toolkit clean — scope=full — base=\`<merge-base>\` — head=\`$HEAD_SHA\`" >&2
            echo "  (legacy form codex clean — head=\`<sha>\` is back-compat — certification only)" >&2
            echo "" >&2
            echo "Run iter-$CODE_N reviewers + append both clean lines, OR uncheck the loop." >&2
            exit 2
        fi

        # Per-line validation: head match required, then both must be `<tool> clean`.
        # Codex is mandatory — no "tool unavailable" escapes.
        for tool_line in "codex:$CODEX_LINE" "pr-toolkit:$TOOLKIT_LINE"; do
            TOOL=$(echo "$tool_line" | cut -d: -f1)
            LINE=$(echo "$tool_line" | cut -d: -f2-)

            # Every line must carry head=`<sha>` matching current HEAD —
            # binds the clean claim to the exact HEAD being shipped.
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

            if echo "$LINE" | grep -qF -- "— $TOOL clean —"; then
                : # clean variant — head already verified above
            else
                echo "WORKFLOW GATE: Code review iteration $CODE_N $TOOL line variant not recognized." >&2
                echo "Got: $LINE" >&2
                echo "" >&2
                echo "Codex is mandatory in this repo. Required: $TOOL clean — scope=full — base=\`<merge-base>\` — head=\`<sha>\`," >&2
                echo "or the legacy form $TOOL clean — head=\`<sha>\` (legacy back-compat — certification only)," >&2
                echo "or mark the loop N/A:  - [x] Code review loop — N/A: <reason>" >&2
                exit 2
            fi
        done
    fi

    if [ -n "$MECH_LINE" ]; then
        # A mechanical re-stamp claims no review was needed. NEVER trust it —
        # it requires an existing certification, a correct chain base, AND the
        # helper's own recomputation agreeing for the current head.
        M_HEAD=$(echo "$MECH_LINE" | sed -E 's/.*head=`([0-9a-f]+)`.*/\1/')
        M_BASE=$(echo "$MECH_LINE" | sed -E 's/.*base=`([0-9a-f]+)`.*/\1/')
        if [ ! -f "$RS" ] || [ "$M_HEAD" != "$HEAD_SHA" ] || [ "$PRIOR_CERTIFIED" -eq 0 ] \
           || [ -z "$M_BASE" ] || [ "$M_BASE" != "$PRIOR_CLEAN_HEAD" ]; then
            echo "WORKFLOW GATE: mechanical re-stamp invalid (requires certification, base=prior clean head \`${PRIOR_CLEAN_HEAD:-<none>}\`, head=current HEAD)." >&2
            echo "Got: $MECH_LINE" >&2; exit 2
        fi
        # Recompute with the CURRENT iteration's rows EXCLUDED (--before $CODE_N,
        # i.e. $RS_PRIOR) — a full-state run would let the mechanical row advance
        # LAST_CLEAN_HEAD to its own head and validate itself (Codex iter-2 P1).
        if ! echo "$RS_PRIOR" | grep -q "SCOPE_REQUIRED:mechanical"; then
            echo "WORKFLOW GATE: mechanical claim rejected — recomputation says a review is required:" >&2
            echo "$RS_PRIOR" | grep -E "PR_OWNED_DELTA|UPSTREAM_FILES|SCOPE_REQUIRED|ANCESTOR_OK" >&2
            echo "Run the required review scope and record real evidence." >&2; exit 2
        fi
    else
        # Engine-pair path (existing loop already validated head + clean variant).
        # Collect per-line scope/base, then validate the PAIR — both engines must
        # have reviewed the SAME thing (iter-3 P1: a mixed full/delta pair, or two
        # delta lines with different bases, is not a coherent review round).
        C_SCOPE=""; C_BASE=""; T_SCOPE=""; T_BASE=""
        for tool_line in "codex:$CODEX_LINE" "pr-toolkit:$TOOLKIT_LINE"; do
            TOOL=$(echo "$tool_line" | cut -d: -f1)
            LINE=$(echo "$tool_line" | cut -d: -f2-)
            if echo "$LINE" | grep -q "scope="; then
                # Any scoped line must carry a well-formed base (full grammar).
                # Delimiter-bound value: scope=fullish must NOT pass as full.
                echo "$LINE" | grep -qE "scope=(full|delta)([[:space:]]|$)" || {
                    echo "WORKFLOW GATE: unknown scope value on iteration $CODE_N line." >&2
                    echo "Got: $LINE" >&2; exit 2; }
                echo "$LINE" | grep -qE 'base=`[0-9a-f]+`' || {
                    echo "WORKFLOW GATE: scoped iteration $CODE_N line missing base=\`<sha>\`." >&2
                    echo "Got: $LINE" >&2; exit 2; }
                L_SCOPE=$(echo "$LINE" | sed -E 's/.*scope=(full|delta)([[:space:]]|$).*/\1/')
                L_BASE=$(echo "$LINE" | sed -E 's/.*base=`([0-9a-f]+)`.*/\1/')
            else
                # Scope-less LEGACY pair: valid ONLY as certification evidence —
                # i.e., when no certification existed before this iteration. After
                # certification, every re-review must be scoped (spec: legacy lines
                # "never satisfy a rebind").
                if [ "$PRIOR_CERTIFIED" -gt 0 ]; then
                    echo "WORKFLOW GATE: post-certification evidence must be scoped (scope=full|delta or a mechanical re-stamp)." >&2
                    echo "Got legacy scope-less line: $LINE" >&2; exit 2
                fi
                L_SCOPE="legacy"; L_BASE=""
            fi
            if [ "$TOOL" = "codex" ]; then C_SCOPE="$L_SCOPE"; C_BASE="$L_BASE"
            else T_SCOPE="$L_SCOPE"; T_BASE="$L_BASE"; fi
        done
        if [ "$C_SCOPE" != "$T_SCOPE" ] || [ "$C_BASE" != "$T_BASE" ]; then
            echo "WORKFLOW GATE: incoherent reviewer pair on iteration $CODE_N — both engines must review the same scope from the same base." >&2
            echo "  codex:      scope=$C_SCOPE base=${C_BASE:-<none>}" >&2
            echo "  pr-toolkit: scope=$T_SCOPE base=${T_BASE:-<none>}" >&2; exit 2
        fi
        if [ "$C_SCOPE" = "delta" ]; then
            if [ "$PRIOR_CERTIFIED" -eq 0 ] || [ -z "$PRIOR_CLEAN_HEAD" ] || [ "$C_BASE" != "$PRIOR_CLEAN_HEAD" ]; then
                echo "WORKFLOW GATE: scope=delta base chain broken on iteration $CODE_N." >&2
                echo "  Claimed base: $C_BASE   Prior clean head: ${PRIOR_CLEAN_HEAD:-<none>}" >&2
                echo "A delta review must chain from the previous clean evidence head." >&2; exit 2
            fi
            # A delta claim is only as good as the identity computation behind it:
            # after a rebase/amend the helper says ANCESTOR_OK:no + SCOPE_REQUIRED:full —
            # a forged delta from the old clean head must not pass (iter-4 P1).
            if ! echo "$RS_PRIOR" | grep -q "ANCESTOR_OK:yes" \
               || echo "$RS_PRIOR" | grep -q "SCOPE_REQUIRED:full"; then
                echo "WORKFLOW GATE: scope=delta rejected — recomputation requires a FULL review here:" >&2
                echo "$RS_PRIOR" | grep -E "ANCESTOR_OK|SCOPE_REQUIRED|LAST_CLEAN_HEAD" >&2
                echo "(history was rewritten or identity is unestablishable — fail-closed to full)" >&2; exit 2
            fi
        elif [ "$C_SCOPE" = "full" ]; then
            # A scope=full base must be the TRUE merge-base for the current head
            # (same DEFAULT_REF resolution as review-scope.sh — fabrication guard).
            # Deliberately re-derived here rather than emitted by the helper: the
            # consumers stay self-contained validators (a helper-output change can
            # never silently weaken the full-base check).
            GATE_DB=$(bash "${RS%/*}/default-branch.sh" 2>/dev/null || echo main)
            GATE_REF="$GATE_DB"
            git rev-parse --verify "origin/$GATE_DB" >/dev/null 2>&1 && GATE_REF="origin/$GATE_DB"
            GATE_MB=$(git merge-base "$GATE_REF" "$HEAD_SHA" 2>/dev/null || echo "")
            if [ -z "$GATE_MB" ] || [ "$C_BASE" != "$GATE_MB" ]; then
                echo "WORKFLOW GATE: scope=full base on iteration $CODE_N is not the merge-base for this head." >&2
                echo "  Claimed base: $C_BASE   Merge-base($GATE_REF, HEAD): ${GATE_MB:-<unresolvable>}" >&2; exit 2
            fi
        fi
    fi
fi

exit 0
