# Bug Fix Workflow

> **This workflow is MANDATORY. Follow every step in order.**
> **If any required command/skill fails with "Unknown skill", STOP and alert the user.**

## Required Plugins

This workflow requires the following plugins to be **installed AND enabled**:

| Plugin                                      | Skills/Commands Used                                                                                                                                                                                           |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `superpowers@claude-plugins-official`       | `/superpowers:systematic-debugging`, `/superpowers:brainstorming`, `/superpowers:writing-plans`, `/superpowers:subagent-driven-development` (default executor), `/superpowers:executing-plans` (headless mode) |
| `pr-review-toolkit@claude-plugins-official` | `code-simplifier` agent, `code-reviewer` agent, `/pr-review-toolkit:review-pr`                                                                                                                                 |

**To enable plugins**, add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "pr-review-toolkit@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": true
  }
}
```

---

## Pre-Flight Checks

### 1. Create Isolated Workspace (MANDATORY)

**Check if already in a worktree:**

```bash
if [[ "$(pwd)" == *".worktrees/"* ]]; then
  echo "STATE: ALREADY_IN_WORKTREE"
else
  echo "STATE: NEEDS_WORKTREE"
fi
```

**If ALREADY_IN_WORKTREE:**

- You're already isolated — continue with current workspace
- Surface drift on the parent default branch (advisory; no auto-FF from inside a worktree)

```bash
# DRIFT-PREFLIGHT-ALREADY-BEGIN (byte-identical with commands/fix-bug.md — enforced by test-contracts.sh)
ROOT="$(git rev-parse --show-toplevel)"
LIB="$ROOT/.claude/hooks/lib/default-branch.sh"
[ ! -f "$LIB" ] && LIB="$ROOT/hooks/lib/default-branch.sh"
DEFAULT_BRANCH=$(bash "$LIB" 2>/dev/null) \
    || { DEFAULT_BRANCH="main"; echo "  ⚠ default-branch helper bailed; assuming 'main' (drift check may be wrong on non-main repos)" >&2; }
ALREADY_FETCH_OK=true
git fetch origin --quiet 2>/dev/null || ALREADY_FETCH_OK=false
# Behind-check: only if FETCH succeeded AND both refs exist. Skipping on fetch failure
# prevents reporting drift against a stale origin/* ref. Also guards rev-list exit-128.
if [ "$ALREADY_FETCH_OK" = "true" ] \
   && git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1 \
   && git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
  BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo "")
  if [[ "$BEHIND" =~ ^[0-9]+$ ]] && [ "$BEHIND" -gt 0 ]; then
    echo "  ⚠ Parent '$DEFAULT_BRANCH' is $BEHIND commits behind origin (skipping auto-FF from worktree)"
  fi
fi
# DRIFT-PREFLIGHT-ALREADY-END
```

**If NEEDS_WORKTREE → Create worktree and cd into it:**

> ⚠️ **ALWAYS create a worktree**, even if on a feature branch. Being on "a feature branch" doesn't mean it's the right branch for THIS fix. Worktrees ensure parallel sessions never mix work.

```bash
FIX_NAME="$ARGUMENTS"
WORKTREE_PATH=".worktrees/$FIX_NAME"

# Ensure .worktrees exists and is gitignored
mkdir -p .worktrees
grep -qxF '.worktrees/' .gitignore 2>/dev/null || echo '.worktrees/' >> .gitignore

# DRIFT-PREFLIGHT-NEW-BEGIN (byte-identical with commands/fix-bug.md — enforced by test-contracts.sh)
# Resolve default branch, fetch origin (track success), and base the new worktree on
# current origin/<default> when fetch succeeded — else local <default>. If local <default>
# is behind origin AND we're on default with a clean tree, fast-forward; otherwise warn.
ROOT="$(git rev-parse --show-toplevel)"
LIB="$ROOT/.claude/hooks/lib/default-branch.sh"
[ ! -f "$LIB" ] && LIB="$ROOT/hooks/lib/default-branch.sh"
DEFAULT_BRANCH=$(bash "$LIB" 2>/dev/null) \
    || { DEFAULT_BRANCH="main"; echo "  ⚠ default-branch helper bailed; assuming 'main' (worktree base may be wrong on non-main repos)" >&2; }

FETCH_OK=true
git fetch origin --quiet 2>/dev/null || { FETCH_OK=false; echo "  ⚠ git fetch failed — proceeding with local refs (origin may be stale)"; }

# Behind-check: only if FETCH succeeded AND both local <default> and origin/<default>
# refs exist. Skipping when fetch failed prevents (a) reporting drift against a stale
# origin/* ref, and (b) `git pull` triggering a second network call after we said we'd
# "proceed with local refs". Also guards rev-list exit-128 when local default is missing.
if [ "$FETCH_OK" = "true" ] \
   && git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1 \
   && git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
  BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo "")
  if [[ "$BEHIND" =~ ^[0-9]+$ ]] && [ "$BEHIND" -gt 0 ]; then
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
      # On default → eligible for FF, but FF is OPTIONAL polish. The worktree itself
      # bases from origin/<default> (BASE below) which is independent of the caller's
      # checkout state, so dirty-tree / diverged-history are warnings, not blockers —
      # `git worktree add` does not modify the current checkout.
      # Under user's `set -o pipefail`, grep -v on a clean tree (no input) exits 1
      # and DIRTY becomes empty — symmetric with BEHIND, validate before integer compare.
      DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | wc -l | tr -d ' ' || echo 0)
      [[ "$DIRTY" =~ ^[0-9]+$ ]] || DIRTY=0
      if [ "$DIRTY" -gt 0 ]; then
        echo "  ⚠ Local '$DEFAULT_BRANCH' is $BEHIND commits behind origin AND working tree is dirty — skipping auto-FF (your local default stays as-is; new worktree still bases from origin/$DEFAULT_BRANCH)"
      elif git pull --ff-only origin "$DEFAULT_BRANCH"; then
        echo "✓ Updated local '$DEFAULT_BRANCH' from origin (was $BEHIND commits behind)"
      else
        echo "  ⚠ git pull --ff-only failed (diverged?) — skipping auto-FF (new worktree still bases from origin/$DEFAULT_BRANCH)"
      fi
    else
      # Not on default → no FF attempted. Dirty changes on a feature branch are fine
      # (they stay in this checkout; the new worktree gets its own working tree).
      echo "  ⚠ Local '$DEFAULT_BRANCH' is $BEHIND commits behind origin (you're on '$CURRENT_BRANCH', skipping auto-FF)"
    fi
  fi
fi

# Resolve worktree base. Prefer origin/<default> ONLY if fetch succeeded AND ref exists
# locally. If fetch failed, prefer local <default> (don't trust the now-stale origin ref).
if [ "$FETCH_OK" = "true" ] && git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
  BASE="origin/$DEFAULT_BRANCH"
elif git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
  BASE="$DEFAULT_BRANCH"
else
  # Last-resort: neither origin/<default> (fetch failed or ref absent) nor local <default>
  # exists. Surface this — the worktree will be based on whatever is currently checked
  # out, which may be a feature branch, a tag, or a detached HEAD. Reachable when the
  # helper bailed AND the assumed fallback "main" doesn't exist locally either.
  BASE="HEAD"
  echo "  ⚠ Could not resolve any default-branch ref; basing worktree on HEAD ($(git rev-parse --short HEAD 2>/dev/null || echo '???')) — verify this is intentional" >&2
fi
# DRIFT-PREFLIGHT-NEW-END

if [ -d "$WORKTREE_PATH" ]; then
  echo "✓ Worktree exists - reusing $WORKTREE_PATH"
elif git show-ref --quiet "refs/heads/fix/$FIX_NAME" 2>/dev/null; then
  git worktree add "$WORKTREE_PATH" "fix/$FIX_NAME"
  echo "✓ Created worktree for existing branch at $WORKTREE_PATH"
else
  git worktree add "$WORKTREE_PATH" -b "fix/$FIX_NAME" "$BASE"
  echo "✓ Created new worktree at $WORKTREE_PATH (based on $BASE)"
fi

# Symlink environment files (not copy) so rotated secrets propagate and .env can't be accidentally committed
for f in .env .env.local .env.development .env.test; do
  [ -f "$f" ] && ln -sf "$(pwd)/$f" "$WORKTREE_PATH/$f"
done
```

**Then cd into the worktree:**

```bash
cd "$WORKTREE_PATH"
```

**Install dependencies (if needed):**

```bash
# Build the Node candidate list: read the marker file setup.sh wrote at
# scaffold time (honors --playwright-dir), falling back to a default set.
NODE_DIRS=". frontend apps/web web client"
[ -f .claude/playwright-dir ] && NODE_DIRS="$(cat .claude/playwright-dir) $NODE_DIRS"

# Node.js — dedupe and install in each dir that has package.json
seen=""
for d in $NODE_DIRS; do
  case " $seen " in *" $d "*) continue;; esac
  seen="$seen $d"
  if [ -f "$d/package.json" ] && [ ! -d "$d/node_modules" ]; then
    (cd "$d" && (pnpm install --silent 2>/dev/null || npm install --silent 2>/dev/null || yarn install --silent 2>/dev/null))
  fi
done

# Python — checks repo root AND common monorepo subdirectories
for d in . backend apps/api api server; do
  if [ -f "$d/pyproject.toml" ]; then
    (cd "$d" && (uv sync 2>/dev/null || pip install -e . 2>/dev/null || echo "Run 'uv sync' manually in $d"))
  fi
done
```

**⚠️ IMPORTANT: You are now working inside the worktree.**

- All file paths are relative to the worktree (e.g., `src/main.py`, not `.worktrees/fix-name/src/main.py`)
- All git commands operate on the worktree's branch
- Hooks will automatically check the correct files

### 2. Read project state

`.claude/local/state.md` is per-developer and gitignored — it may not exist yet on a fresh checkout. Initialize it from the installed template if missing, then read it.

**Step 2a: locate template + decide whether init is needed.** This block is **read-only** — no filesystem writes; it just emits a sentinel line for step 2b to act on.

```bash
# STATE-INIT-BEGIN (byte-identical between commands/new-feature.md and commands/fix-bug.md - enforced by test-contracts.sh)
# Read-only: locate state template + check whether state.md needs initialization.
# All writes are deferred to step 2b's Read+Write tool calls (auto-approved by the
# v5.21 PermissionRequest hook on .claude/local/**). The Write tool creates missing
# parent dirs in one call — verified empirically against Claude Code 2.1.138.
ROOT="$(git rev-parse --show-toplevel)"
# Resolve parent working tree (== ROOT in main repo; == main repo working tree from
# a worktree). git rev-parse --git-common-dir returns ".git" (relative) in main repo,
# and absolute path to main repo's .git dir from inside a worktree. Strip trailing
# /.git only when the path is absolute — relative ".git" means we're already in main.
COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || true)"
case "$COMMON_DIR" in
    /*) PARENT_ROOT="${COMMON_DIR%/.git}" ;;
    *)  PARENT_ROOT="$ROOT" ;;
esac
TEMPLATE="$ROOT/.claude/state.template.md"
[ ! -f "$TEMPLATE" ] && TEMPLATE="$ROOT/state.template.md"  # Forge-internal fallback
if [ -f "$ROOT/.claude/local/state.md" ]; then
    echo "STATE_EXISTS"
elif [ -f "$TEMPLATE" ]; then
    echo "STATE_NEEDS_INIT_FROM:$TEMPLATE"
elif [ -f "$PARENT_ROOT/.gitignore" ] && grep -qE '^[[:space:]]*/?\.claude/?[[:space:]]*$' "$PARENT_ROOT/.gitignore"; then
    echo "STATE_TEMPLATE_DOWNSTREAM_GITIGNORED:$PARENT_ROOT"
    echo "  ⚠ .claude/ is gitignored in $PARENT_ROOT/.gitignore — Forge files never reach worktrees." >&2
else
    echo "STATE_TEMPLATE_NOT_FOUND_AT:$TEMPLATE"
    echo "  ⚠ state template not found — workflow tracking cannot proceed without it." >&2
fi
# STATE-INIT-END
```

**Step 2b: act on step 2a's sentinel.**

- `STATE_EXISTS` → skip to step 2c.
- `STATE_NEEDS_INIT_FROM:<path>` →
  1. Use the **Read** tool on `<path>` (the template path from the sentinel line)
  2. Use the **Write** tool to create `.claude/local/state.md` with the template's content. Write creates the missing `.claude/local/` parent directory in the same call. The v5.21 PermissionRequest hook auto-approves writes to `.claude/local/**`, so this won't prompt.
- `STATE_TEMPLATE_DOWNSTREAM_GITIGNORED:<parent_root>` → STOP. The downstream repo at `<parent_root>` gitignores `.claude/` (the entire directory). The Forge convention gitignores only `.claude/local/`, so worktrees based on `origin/<default-branch>` reach a tree without any Forge files. Tell the user to fix the gitignore and commit `.claude/`:
  1. Edit `<parent_root>/.gitignore` — remove the bare `.claude/` line. Keep `.claude/local/` (it should already be there from setup; if not, add it).
  2. `cd <parent_root> && git add .gitignore .claude/ && git commit -m "chore: track .claude/ per Forge convention" && git push origin <default-branch>`
  3. From inside the active worktree: `git fetch origin && git rebase origin/<default-branch>` to pick up the new commit.
  4. Retry `/new-feature` (or `/fix-bug`).
     Don't synthesize a state.md, and don't copy `.claude/` from the parent into the worktree — that's a band-aid that masks the misconfiguration; future worktrees will need the same workaround AND other Forge surfaces (hooks, settings) still won't reach the worktree's tracked tree.
- `STATE_TEMPLATE_NOT_FOUND_AT:<path>` → STOP and tell the user that the Forge state template is missing — their checkout looks incomplete. Tell them to re-run `setup.sh --upgrade` from their Forge clone (typically `~/claude-codex-forge`; on Windows: `setup.ps1 -Upgrade`). Don't synthesize a state.md; the workflow tracking gates depend on the template's structure.

**Step 2c: read state.md** via the Read tool.

### 3. Initialize Workflow Tracking

Write the `## Workflow` section in `.claude/local/state.md`. The file was just initialized in step 2 (from `.claude/state.template.md` on first invocation, or already present from a prior session). Apply these cleanup steps **only if applicable** — on a brand-new state.md they are no-ops:

1. **REPLACE** any existing `## Workflow` section entirely — do not append, do not preserve old checklist items from a previous workflow on this developer's machine.
2. **Delete any stale `## Approach Comparison` blocks** if present. These can only appear on machines whose state.md was migrated from a pre-PR-#2 tracked state file. The current workflow keeps the Approach Comparison in conversation context only, then persists it into the plan file at Phase 3.2; nothing should remain in `.claude/local/state.md`.
3. **Delete orphaned `[x]` / `[ ]` checkbox lines** that drifted outside any user-authored section — lines floating between sections, AND lines inside any stale `## Approach Comparison` blocks you just deleted. Do NOT touch checkbox items inside user sections like `## Blockers` / `## Open Questions` — those are user content.

Then write the new `## Workflow` section:

```markdown
## Workflow

| Field     | Value               |
| --------- | ------------------- |
| Command   | /fix-bug $ARGUMENTS |
| Phase     | Pre-Flight          |
| Next step | Verify plugins      |

### Checklist

- [x] Worktree created
- [x] Project state read
- [ ] Plugins verified
- [ ] Searched existing solutions
- [ ] Systematic debugging complete
- [ ] Library research done (if external dep involved — via research-first agent)
- [ ] Design guidance loaded (if UI fix)
- [ ] Brainstorming complete (if complex)
- [ ] Approach comparison filled (if complex)
- [ ] Contrarian gate passed (skip | spike | council) (if complex)
- [ ] Council verdict (if triggered, complex fixes only) — verdict persisted in plan file, not here
- [ ] Plan written (if complex)
- [ ] Plan review loop (0 iterations, if complex) — iterate until no P0/P1/P2
- [ ] TDD fix execution complete
- [ ] Code review loop (0 iterations) — iterate until no P0/P1/P2
- [ ] Simplified
- [ ] Verified (tests/lint/types)
- [ ] E2E use cases designed (Phase 3.2b plan file, or simple-fix staging at `docs/plans/<bug-name>-use-cases.md`)
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] E2E regression passed (Phase 5.4b)
- [ ] E2E use cases graduated to tests/e2e/use-cases/ (Phase 6.2b)
- [ ] E2E specs graduated to tests/e2e/specs/ (Phase 6.2c — if Playwright framework installed)
- [ ] Learning documented
- [ ] State files updated
- [ ] Committed and pushed
- [ ] PR created
- [ ] PR reviews addressed
- [ ] Branch finished
```

### 4. Verify required plugins are available (test ONE skill)

```
/superpowers:systematic-debugging
```

**If "Unknown skill" error:**

- STOP immediately
- Tell user: "Required plugins not loaded. Please enable in ~/.claude/settings.json and restart Claude Code."
- Do NOT proceed with workarounds or skip mandatory steps

**Checkpoint:** Check off "Plugins verified" in .claude/local/state.md and set Next step to "Search existing solutions".

### 5. Worktree Policy Reminder

**DO NOT create additional worktrees** during this workflow. If `/superpowers:systematic-debugging` or other skills attempt to create a worktree, **SKIP that step** - you're already isolated.

---

## Phase 1: Research Existing Solutions

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `1 — Research`, Next step: `Search existing solutions`.

Before attempting ANY fix, check if this was solved before:

```bash
grep -r "error message or symptom" docs/solutions/
grep -r "related module name" docs/solutions/
ls docs/solutions/
```

If found, review the solution and apply it.

---

## Phase 2: Systematic Debugging (MANDATORY)

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `2 — Debugging`, check off "Searched existing solutions".

**DO NOT guess at fixes.** Run the 4-phase root cause analysis:

```
/superpowers:systematic-debugging
```

This will guide you through:

1. **Reproduce** - Confirm the bug exists
2. **Isolate** - Narrow down the cause
3. **Identify** - Find the root cause
4. **Verify** - Confirm understanding before fixing

> **⚠️ CRITICAL:** If this skill is unavailable, you MUST still follow the 4-phase process manually:
>
> 1. Reproduce the bug consistently
> 2. Isolate by adding logging/tracing at component boundaries
> 3. Identify root cause (not just symptoms)
> 4. Verify your understanding before proposing ANY fix
>
> **NEVER skip this phase. NEVER guess at fixes.**

### 2.5 Targeted Library Research (if external dependency involved)

If the root cause involves an external library, API, or framework (not purely internal logic):

```
Task tool → subagent_type: "research-first", prompt: "Bug fix research. Library: <library-name>. Our version: <version from manifest>. Bug symptom: <what's happening>. Research: current best practices, known issues with our version, breaking changes, recommended migration path if relevant."
```

The agent writes to `docs/research/YYYY-MM-DD-<bug-name>.md` — a lighter brief focused on the specific library involved.

**Skip this step if:** the root cause is purely internal logic (wrong conditional, missing null check, etc.) with no external dependency involvement.

---

## Phase 3: Plan the Fix

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `3 — Plan`, check off "Systematic debugging complete" (and "Library research done" if Phase 2.5 was performed).

### For simple fixes (1-2 files):

Proceed directly to Phase 4 **UNLESS** the fix touches a high-impact surface:

- Schema/database migrations
- Public API contracts
- Authentication or permissions
- Payment or billing logic
- Configuration defaults affecting all users
- Rollout/deployment strategy
- Architecture boundaries (service boundaries, shared libraries, database ownership)

**If high-impact:** Treat as complex — enter Phase 3 below.

### For complex fixes (3+ files or architectural):

#### 3.0 Load Design Guidance (if UI fix)

If this bug fix involves ANY user-facing interface changes:

    /ui-design

This ensures UI fixes maintain visual quality — don't regress the design while fixing functionality.

**Skip this step if:** the fix is purely backend/logic with no UI impact, or if `/ui-design` is not available.

#### 3.1 Brainstorm approaches

```
/superpowers:brainstorming
```

#### 3.1b Approach Comparison (MANDATORY)

Same as `/new-feature` 3.1b — produce the comparison table **in conversation context** (not in `.claude/local/state.md`; `.claude/local/state.md` is status-only). If only one viable fix, still run the Contrarian gate (validates no alternative was missed).

#### 3.1c Contrarian Gate (MANDATORY)

Same as `/new-feature` 3.1c — invoke `/council` with the explicit `"Phase 3.1c Contrarian Gate — auto-trigger mode per references/peer-review-protocol.md 'Auto-Trigger Integration' section. Return VALIDATE / SPIKE / COUNCIL."` directive, followed by the Approach Comparison block pasted **VERBATIM**. Do not summarize, paraphrase, or reconstruct from memory; if the block is no longer in active context, regenerate it explicitly before invoking `/council`. Full invocation template in `/new-feature` 3.1c.

The council skill currently emits its decision as **prose**, not a clean token. Translate its response into one of `{VALIDATE, SPIKE, COUNCIL}` using this mapping:

| Skill response (prose)                                    | Workflow token                                                                                                                                                                                                               |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Contrarian validated. Proceeding with default approach." | VALIDATE                                                                                                                                                                                                                     |
| "Proceed with default. Trade-off documented."             | VALIDATE (note the trade-off in 3.2's Contrarian Verdict section)                                                                                                                                                            |
| "Run spike first: [test]"                                 | SPIKE — run the test, UPDATE the Approach Comparison with the spike's findings (may change `### Chosen Default` / `### Best Credible Alternative` / scoring), THEN re-invoke 3.1c. Do NOT re-send the stale pre-spike block. |
| Full `## Council Verdict` block                           | COUNCIL — chairman's `### Recommendation` supersedes the 3.1b default; update in Phase 3.2                                                                                                                                   |
| Raw "INSUFFICIENT"                                        | COUNCIL — protocol defines INSUFFICIENT as "ambiguity = risk, escalate"                                                                                                                                                      |
| Raw "OBJECT" without a spike-or-council decision          | COUNCIL                                                                                                                                                                                                                      |
| Unrecognizable                                            | Escalate to user: "/council returned X, should I treat as VALIDATE, SPIKE, or COUNCIL?"                                                                                                                                      |

Outcome actions (same as `/new-feature` 3.1c): VALIDATE → proceed to 3.2; SPIKE → run the test, re-evaluate; COUNCIL → full council runs, verdict picks the approach, proceed to 3.2.

#### 3.2 Write the fix plan

Invoke `/superpowers:writing-plans`. Mirroring `/new-feature` 3.2 — respect `writing-plans`' required header (H1 banner + Goal/Architecture/Tech Stack). Insert the **final** Approach Comparison (reflecting whatever won 3.1c's VALIDATE / SPIKE / COUNCIL path) AFTER that required header, followed by a `## Contrarian Verdict` subsection. Do NOT copy a stale 3.1b table if the spike or council changed the choice. The per-developer `.claude/local/state.md` keeps only the checkbox; the design rationale lives in the plan file from here on.

```
/superpowers:writing-plans
```

#### 3.2b Design E2E Use Cases (if user-facing)

If this fix changes any user-facing behavior (UI, API, flows, forms, navigation, permissions), design E2E use cases NOW — before implementation, not after.

Write use cases in the plan file under a `#### E2E Use Cases` heading, using the template from `rules/testing.md`. Each use case declares its **Interface** (API / UI / CLI / API+UI) based on the project-type matrix in `rules/testing.md` — and includes **Setup** (sanctioned method per the ARRANGE/VERIFY boundary), **Steps**, **Verification**, and **Persistence**.

**Project type scope** (from `CLAUDE.md` `## E2E Configuration`):

- **fullstack:** API use cases + UI use cases (API-first ordering for execution)
- **api:** API use cases only
- **cli:** CLI use cases only
- **hybrid:** declare per use case

For bug fixes, think about:

- What was the user doing when the bug occurred? Reproduce that as a use case.
- After the fix, does the happy path still work?
- Could the fix break any adjacent user flow?

**Minimum:** 1 use case that reproduces the original bug through the user's interface and verifies the fix.

**If purely internal (no user-facing impact):** Write "E2E: N/A — [reason]" in the plan.

#### 3.3 Plan Review Loop (MANDATORY)

Go back to the fix plan and check everything proposed against the actual code. All available reviewers run **in parallel**, iterating until clean.

**Per iteration:**

**Step A — Run both reviews in parallel:**

**a) Claude (you) reviews the plan against the codebase:**

Read every file the plan proposes to modify. For each change, ask:

- Does the plan account for what the code actually looks like today?
- Are there existing utilities, patterns, or abstractions the plan should use instead of creating new ones?
- Are there correctness issues, missing edge cases, or integration problems?
- Is the testing strategy adequate?

> **Note:** "Is there a simpler approach?" is no longer asked here — the Approach Comparison + Contrarian Gate (3.1b/3.1c) already settled the strategic choice.

Document your findings as a severity-tagged list (P0/P1/P2/P3).

**b) Codex reviews independently:**

Check if Codex CLI is available:

```bash
command -v codex &>/dev/null && echo "Codex available" || echo "Codex not installed"
```

If available:

```
/codex review the fix plan and check everything we're proposing versus the code — is this the simplest, fastest, best way to do it? Flag any concerns.
```

Note: The `/codex` command's Design Review Mode uses its own fixed prompt — it may not return P0/P1/P2/P3 tags directly. After receiving Codex's output, classify each finding into P0/P1/P2/P3 using the severity rubric before evaluating exit criteria.

If Codex is NOT available:

- Present your own review findings plus a summary of the plan to the user
- Ask: "Does this fix approach look right before I start implementing?"
- User confirmation replaces Codex as the second reviewer

**Step B — Collect findings and evaluate:**

Gather severity-tagged findings from all available reviewers. Use this rubric:

| Level | Meaning                                                                | Action                     |
| ----- | ---------------------------------------------------------------------- | -------------------------- |
| P0    | Broken — will crash, lose data, or create security vulnerability       | Must fix before proceeding |
| P1    | Wrong — incorrect behavior, logic error, missing edge case             | Must fix before proceeding |
| P2    | Poor — code smell, maintainability issue, unclear intent, missing test | Must fix before proceeding |
| P3    | Nit — style, naming, minor suggestion                                  | May fix, does not block    |

**Step C — Exit criteria:**

- **P0/P1/P2 found by any reviewer →** Fix the plan, increment iteration counter in the state.md checklist (`Plan review loop (N iterations)`), go back to Step A.
- **Only P3 or clean from all available reviewers on the same pass →** Check the box in state.md with final count: `- [x] Plan review loop (3 iterations) — PASS`. Proceed to Phase 4.

**Rules:**

- Do NOT check the box until all available reviewers report no P0/P1/P2 on the same pass
- "Available reviewers" = Claude always + Codex if installed, or user if Codex unavailable
- Typically 2-3 iterations
- Do NOT proceed to Phase 4 until the plan is approved

> **Why mandatory?** A wrong fix plan leads to wasted effort and potentially new bugs. Two independent reviewers checking the plan against the actual code catches things a single pass misses.

---

## Phase 4: Execute the Fix

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `4 — Execute`, check off planning items.

### Simple fixes (1-2 files, Phase 3 skipped)

Write a failing test first, then fix. Single-threaded — no dispatch plan needed.

### Complex fixes (3+ files, Phase 3 complete)

> **Optional before starting:** Run `/compact` if the session is heavy with debugging + plan-review discussion.

#### 4.0 Dispatch Plan (MANDATORY before dispatching any subagent)

Append a `## Dispatch Plan` heading to the plan file with one row per task. Format, scheduling rules, and failure semantics are identical to `/new-feature` — see `new-feature.md` in this same `.claude/commands/` directory, Phase 4.0, for the full spec. Key points restated:

- `Writes` lists **concrete file paths**, not directories or globs
- Default concurrency cap: 3 concurrent subagents (max 5 for small, genuinely independent tasks)
- Serial is the default; parallel requires proven independence (all `Depends on` resolved AND disjoint `Writes`)
- **No append-only fast-path** — tasks modifying the same existing file always serialize via `Depends on`
- Shared types/imports → encode as explicit `Depends on`
- Sequential override for tightly-coupled fixes is legitimate (Cognition's counter-position)

#### 4.1 Execute via subagent-driven-development

Use `superpowers:subagent-driven-development`. Per cycle: pick next eligible task → dispatch fresh subagent with TDD discipline → review diff on return → re-evaluate ready set → dispatch next.

**Handling failures:**

- Subagent failure OR diff-review reject → mark the task failed, cancel any in-flight dependents, surface to the user
- Rate limit or timeout → retry once with a fresh subagent; second failure is a real failure
- After each task completes, verify in-flight dependents' assumptions still hold; cancel and re-dispatch if a breaking change landed upstream

**If you encounter bugs during implementation:**

```
/superpowers:systematic-debugging
```

#### 4.2 Headless / Walk-Away Mode (OPT-IN)

Say **"walk-away mode"** or **"headless"** to switch to `/superpowers:executing-plans` in a separate session. Default is in-session subagent-driven.

---

## Phase 5: Quality Gates (ALL REQUIRED)

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `5 — Quality Gates`, check off "TDD fix execution complete".
> **Note:** The PreToolUse hook will block commit/push/PR until review, simplify, and verify are checked off.

> **If any command below fails with "Unknown skill":**
>
> - Alert the user about missing plugins
> - Perform equivalent checks manually (see fallbacks below)
> - Do NOT skip quality gates

### 5.1 Code Review Loop (MANDATORY)

Run all available reviews **in parallel**, iterating until clean.

**Per iteration:**

**Step A — Run both reviews in parallel:**

**a) Second Opinion (Codex CLI):**

Check if Codex CLI is available:

```bash
command -v codex &>/dev/null && echo "Codex available" || echo "Codex not installed"
```

If available:

```
/codex review
```

Note: `/codex review` uses the codex.md command which has its own prompt format. After receiving Codex's output, classify each finding into P0/P1/P2/P3 using the severity rubric before evaluating exit criteria.

**b) Deep Review (PR Review Toolkit):**

```
/pr-review-toolkit:review-pr
```

This runs 6 specialized agents: code-reviewer, silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer, and code-simplifier.

**Tool availability:**

- **Both available (normal):** Run Codex + PR Toolkit in parallel
- **Codex unavailable:** PR Toolkit alone is sufficient
- **PR Toolkit unavailable:** Codex alone is sufficient
- **Neither available:** Alert user, perform manual review, get user sign-off

**Step B — Collect findings and evaluate:**

Gather severity-tagged findings from all available reviewers. Use the same P0–P3 rubric from the plan review loop.

**Step C — Exit criteria:**

- **P0/P1/P2 found by any reviewer →** Fix the issues. If fixes are substantial (3+ files changed), re-run verify-app before next review iteration to catch regressions early. Increment counter in the state.md checklist (`Code review loop (N iterations)`), go back to Step A.
- **Only P3 or clean from all available reviewers on the same pass →** Check the box in state.md with final count: `- [x] Code review loop (3 iterations) — PASS`. Proceed to 5.2.

**Rules:**

- Do NOT check the box until all available reviewers report no P0/P1/P2 on the same pass
- Typically 2-3 iterations
- P3s are acceptable — do not iterate for P3-only findings

### 5.2 Simplify

Run the built-in `/simplify` command on modified code:

```
/simplify
```

**Fallback (older Claude Code versions):** Use the `code-simplifier` agent on modified files.

### 5.3 Verify (USE SUBAGENT - saves context window)

**MUST use the verify-app subagent** - Do NOT run tests yourself.

Using a subagent keeps test output out of your context window, preserving tokens for actual work.

**Invoke the subagent:**

Launch the `verify-app` agent to run all tests, linting, and type checks. Report only the pass/fail verdict back.

```
Task tool → subagent_type: "verify-app", prompt: "Run verification and report pass/fail verdict."
```

**Only use fallback if Task tool fails:**

```bash
pytest && ruff check . && mypy .  # Python
npm test && npm run lint && npm run typecheck  # Node
```

### 5.4 E2E Use Case Tests (MANDATORY if user-facing)

**MUST use the `verify-e2e` subagent** — Do NOT test user flows yourself.

The verify-e2e agent tests as a real user: no database access, no internal endpoints, no source code reading. It executes user journey use cases through the product's actual user-facing interfaces and returns a markdown report in its response. **The agent is read-only — YOU persist the report to disk.**

**⚠ ARRANGE boundary (main agent, read before invoking verify-e2e):** Even when setting up test data for verify-e2e yourself, you are bound by the same ARRANGE rule. **Never** run raw DB writes (`psql -c "INSERT"`, `docker exec … psql -c "INSERT"`, `mysql -e "UPDATE"`, `mongosh --eval db.x.insertOne(…)`), internal/undocumented endpoints, or on-disk file-injection to seed state. Setup must go through the app's public API, signup/login flows, app CLI, UI, or documented seed commands (`make seed-dev`, `manage.py loaddata`). **If the sanctioned setup path is broken** (e.g., the app's seed CLI has a bug), **FIX the bug first** — do not route around it via direct DB writes. This is NO BUGS LEFT BEHIND applied at the E2E boundary.

**Step 0: Ensure use cases exist (simple-fix path only)**

Simple fixes (1-2 files, non-high-impact) skip Phase 3 entirely — so no plan file exists. If you took the simple-fix path AND the change is user-facing:

- Write a lightweight use case set inline (1 happy-path + 1 error case minimum) using the UC template from `rules/testing.md`
- Save to **`docs/plans/<bug-name>-use-cases.md`** as a staging file. **Start the file with a `#### E2E Use Cases` heading** so verify-e2e can extract the UCs correctly.
- **Why a staging file, not tests/e2e/use-cases/ directly?** Writing directly to `tests/e2e/use-cases/` would cause Phase 5.4b regression mode to pick up the new unverified use case alongside accumulated ones. Staging in `docs/plans/` keeps the separation clean. Phase 6.2b then graduates the staged file after PASS.
- Then proceed to Step 1

If you took the complex-fix path (Phase 3), use cases are already in the plan file — skip this step.

**Step 1: Ensure servers are running from this worktree**

If you're in a worktree, dev servers may still be running from the main directory serving OLD code. Restart them from the worktree before invoking verify-e2e.

**Step 2: Invoke verify-e2e**

```
Task tool → subagent_type: "verify-e2e", prompt: "Mode: feature. Plan file: [path to plan file OR docs/plans/<bug-name>-use-cases.md for simple fixes]. Project type: [fullstack|api|cli|hybrid from CLAUDE.md]. Execute all E2E use cases and return a verification report."
```

**Step 3: Persist the report (MANDATORY)**

The agent's response starts with a two-line header:

```
VERDICT: PASS | FAIL | PARTIAL
SUGGESTED_PATH: tests/e2e/reports/YYYY-MM-DD-HH-MM-<feature-or-mode>.md
---
<full markdown report body>
```

Parse the header, then `Write` the report body (everything after `---`) to the suggested path. Create the `tests/e2e/reports/` directory if needed:

```bash
mkdir -p tests/e2e/reports
```

**Step 4: Act on the verdict**

The header's `VERDICT:` line is the top-level outcome. For `FAIL` and `PARTIAL`, inspect the per-UC classifications in the report body (`FAIL_BUG` / `FAIL_STALE` / `FAIL_INFRA`) to decide next action:

- **VERDICT: PASS** — Proceed to Phase 5.4b.
- **VERDICT: FAIL** — At least one UC was classified `FAIL_BUG` in the body. Fix the issue in code, re-run verify-e2e. Do NOT check the box until PASS. (If the body has mixed `FAIL_BUG` + `FAIL_STALE`, fix the bugs first; stale UCs are addressed separately.)
- **VERDICT: PARTIAL** — No `FAIL_BUG` in the body, but at least one `FAIL_STALE` or `FAIL_INFRA`. Look at each failed UC:
  - `FAIL_STALE`: update the stale use case file (interface or selector changed), re-run.
  - `FAIL_INFRA`: retry once manually; if still infra, report to user for decision.

**If purely internal (no user-facing impact):** Check the box with justification:
`- [x] E2E verified — N/A: internal fix, no user-facing changes`

**Non-browser projects** (API-only, CLI): the verify-e2e agent handles these via HTTP/subprocess. The use case template applies; no Playwright needed.

### 5.4b E2E Regression (MANDATORY if tests/e2e/use-cases/ has files)

Run the full regression suite to catch regressions in previously shipped flows.

**Check first:**

```bash
ls tests/e2e/use-cases/*.md 2>/dev/null | head -1
```

If no files (empty directory, or directory missing): check the box with `- [x] E2E regression — N/A: no accumulated use cases yet`.

**Detect which regression path to use.** The framework path is only safe when every markdown UC has a matching spec — otherwise un-spec'd UCs would silently drop out of regression coverage during partial Playwright adoption.

1. **Locate Playwright framework + count unspecced use cases:**

   ```bash
   # Find playwright.config.ts. Prefer the marker file setup.sh wrote at
   # scaffold time (honors --playwright-dir custom paths like apps/dashboard).
   # Fall back to scanning common frontend subdirectories for users who never
   # ran setup.sh or whose marker is missing.
   PW_DIR=""
   if [ -f .claude/playwright-dir ]; then
     candidate=$(cat .claude/playwright-dir)
     [ -f "$candidate/playwright.config.ts" ] && PW_DIR="$candidate"
   fi
   if [ -z "$PW_DIR" ]; then
     for d in . frontend apps/web web client; do
       if [ -f "$d/playwright.config.ts" ]; then
         PW_DIR="$d"
         break
       fi
     done
   fi

   unspecced=0
   if [ -n "$PW_DIR" ]; then
     for md in "$PW_DIR"/tests/e2e/use-cases/*.md tests/e2e/use-cases/*.md; do
       [ -f "$md" ] || continue
       name=$(basename "$md" .md)
       [ -f "$PW_DIR/tests/e2e/specs/$name.spec.ts" ] || unspecced=$((unspecced+1))
     done
   fi

   if [ -n "$PW_DIR" ] && [ "$unspecced" -eq 0 ] && ls "$PW_DIR"/tests/e2e/specs/*.spec.ts >/dev/null 2>&1; then
     echo "FRAMEWORK (playwright at: $PW_DIR)"
   else
     echo AGENT
   fi
   ```

2. **If FRAMEWORK path** (framework installed AND every UC has a matching spec):
   - Run specs directly from the detected Playwright directory (no package.json script needed):
     ```bash
     cd "$PW_DIR" && pnpm exec playwright test
     ```
     For monorepo layouts where Playwright was scaffolded into `frontend/`, `apps/web/`, etc., `$PW_DIR` is set by the detection block above. For flat layouts `$PW_DIR` is `.` and the `cd` is a no-op.
     If pnpm is not the project's package manager, use `npm exec playwright test` or `yarn playwright test`.
   - Exit code 0 = all pass. Non-zero = failures.
   - Review the HTML report: `cd "$PW_DIR" && pnpm exec playwright show-report`
   - Trace viewer for failures: `cd "$PW_DIR" && pnpm exec playwright show-trace <trace.zip>`

3. **If AGENT path** (no framework, no specs yet, OR partial spec coverage):
   Invoke the verify-e2e agent in regression mode — it runs every markdown UC, guaranteeing no un-spec'd UC is missed during migration:
   ```
   Task tool → subagent_type: "verify-e2e", prompt: "Mode: regression. Execute all use cases from tests/e2e/use-cases/. Project type: [fullstack|api|cli|hybrid from CLAUDE.md]."
   ```

**Verdict handling (both paths):**

- **Regression passes:** Check off the box. Proceed to Phase 6.
- **FAIL_BUG (framework: spec failure; agent: FAIL_BUG verdict):** This fix broke something that previously worked. Fix it, then re-run 5.4b (and 5.4 if this fix has its own user-facing E2E scope).
- **FAIL_STALE (agent only):** Update stale use case file and re-run.
- **FAIL_INFRA / flake (both paths):** Retry once. If still failing, report to user for decision.

**Note:** `pnpm exec playwright test` runs the binary directly — no `package.json` script is required. setup.sh does not modify `package.json`; use the binary invocation above.

---

## Phase 6: Finish

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `6 — Finish`, check off quality gate items.

### 6.1 Compound the learning (MANDATORY for bug fixes)

Every bug fix teaches something. Capture it:

1. **Create solution doc** in `docs/solutions/[category]/`:

   ```bash
   mkdir -p docs/solutions/[category]
   # Create docs/solutions/[category]/[descriptive-name].md with:
   # - Problem: What was the symptom
   # - Root Cause: What actually caused it
   # - Solution: How to fix it
   # - Prevention: How to avoid in future
   ```

2. **Save to auto memory** — write key learnings to your MEMORY.md or topic files

This creates a searchable solution so the same bug is never debugged twice.

### 6.2 Update state files

1. **.claude/local/state.md**: Update Done (keep 2-3 recent), Now, Next
2. **docs/CHANGELOG.md**: If 3+ files changed on branch

### 6.2b Graduate E2E Use Cases (MANDATORY if use cases were created)

Move passing use cases to `tests/e2e/use-cases/<bug-name>.md` as permanent regression tests.

**Complex-fix path:** Extract the E2E Use Cases section from the plan file and write as `tests/e2e/use-cases/<bug-name>.md`.

**Simple-fix path:** Move the staging file:

```bash
mkdir -p tests/e2e/use-cases
mv docs/plans/<bug-name>-use-cases.md tests/e2e/use-cases/<bug-name>.md
```

Both paths:

- Keep the same UC format (Interface, Setup, Steps, Verify, Persist)
- Optionally tag critical paths with `@smoke` for fast regression checks

**Skip this step if:** No user-facing changes (Phase 5.4 was N/A).

### 6.2c Graduate to Playwright Specs (OPTIONAL — if framework installed)

If this project has opted into the Playwright framework (`playwright.config.ts` exists at project root), also graduate each passing use case to a deterministic `.spec.ts` file. The graduated spec lives alongside the moved use case file (complex-fix: from the plan; simple-fix: from the staging file moved in 6.2b).

**Check if framework is installed:**

```bash
[ -f playwright.config.ts ] && echo FRAMEWORK || echo SKIP
```

**If SKIP (no framework):** Skip this step entirely. Proceed to 6.3.

**If FRAMEWORK is installed, YOU (the main implementation agent) write the spec file.** The verify-e2e agent does NOT have Write tools and cannot do this. Here's how:

1. **Read the source inputs:**
   - The markdown use case file: `tests/e2e/use-cases/<bug-name>.md` (intent of truth — just moved in 6.2b)
   - The verify-e2e report from Phase 5.4: `tests/e2e/reports/<latest>.md` (contains observed selectors, outcomes per UC)

2. **Reference the example template:** `templates/playwright/example.spec.template.ts` in the claude-codex-forge checkout — this is a skeleton for spec file structure.

3. **Write `tests/e2e/specs/<bug-name>.spec.ts`:**
   - One `test.describe('Fix: <bug-name>', () => {...})` block
   - One `test(...)` per UC that passed verification (at minimum: the regression reproducer)
   - Use selectors from the verify-e2e report's "Observed selectors" section
   - Prefer `getByRole`, `getByLabel`, `getByTestId` over CSS class selectors
   - Tag the reproducer as `@smoke` in the test name so it runs in fast regression checks
   - Do NOT inline auth — use the fixture pattern (see `tests/e2e/fixtures/auth.ts`)
   - Do NOT generate specs for UCs that were FAIL_BUG or FAIL_STALE — skip them

4. **Skip UCs where the verify-e2e report flagged "Selector ambiguity":** Note this in .claude/local/state.md for follow-up; the user can add `data-testid` attributes and regenerate.

5. **Run the spec once locally to verify it's green:**

   ```bash
   pnpm exec playwright test tests/e2e/specs/<bug-name>.spec.ts
   ```

   If it fails, fix the selector ambiguity rather than committing a broken spec.

**Commit the generated spec:** It becomes part of the regression suite and runs in CI for every future PR — locking in the fix so this bug cannot recur.

**Skip this step entirely if:**

- Project doesn't have Playwright framework installed (no `playwright.config.ts`)
- No user-facing changes (Phase 5.4 was N/A)
- All UCs had selector ambiguity (note this and defer until testids are added)

### 6.3 Commit and push

```bash
git add -A
git commit -m "fix: [descriptive message based on changes]"
git push -u origin HEAD
```

### 6.4 Create Pull Request

**Ask the user for confirmation before creating the PR:**

> "Branch pushed. Would you like me to create a PR to main?"

**Wait for explicit user confirmation before proceeding.**

```bash
gh pr create --base main --title "[PR title]" --body "[PR description]"
```

**Show the user the PR URL.**

### 6.5 Wait for PR reviews

Wait for automated reviewers (GitHub Copilot, Claude, Codex) and peer developer reviews to arrive on the PR.

### 6.6 Process PR review comments

```
/review-pr-comments
```

Address all review comments, fix issues, and push fixes.

**After fixing review comments, re-run quality gates** (5.1 Code Review Loop, 5.2 Simplify, 5.3 Verify) on the new changes to ensure no regressions were introduced. Repeat until the PR is approved.

### 6.7 Finish the branch (Merge + Cleanup)

Once the PR is approved:

```
/finish-branch
```

This command will:

1. Merge the PR to main (if not already merged)
2. Delete the remote branch
3. Delete the local branch and remove the worktree
4. Restart development servers from main

---

## ⚠️ IMPORTANT: Never Bypass Mandatory Steps

If any MANDATORY step cannot be completed:

1. **STOP** - Do not continue with workarounds
2. **ALERT** - Tell the user which step failed and why
3. **WAIT** - Get user guidance before proceeding
4. **NEVER** use bash/python scripts to bypass Edit hooks or skip workflow validation

The hooks exist to enforce quality. Bypassing them defeats their purpose.

---

## Checklist

**The live checklist is in `## Workflow` in .claude/local/state.md** — initialized in Pre-Flight step 3.

The Stop hook reminds you of the current phase on every response. The PreToolUse hook blocks commit/push/PR until review, simplify, and verify are checked off. Update the checklist after each step.
