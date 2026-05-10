# New Feature Workflow

> **This workflow is MANDATORY. Follow every step in order.**
> **If any required command/skill fails with "Unknown skill", STOP and alert the user.**

## Required Plugins

This workflow requires the following plugins to be **installed AND enabled**:

| Plugin                                      | Skills/Commands Used                                                                                                                                                                                           |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `superpowers@claude-plugins-official`       | `/superpowers:brainstorming`, `/superpowers:writing-plans`, `/superpowers:subagent-driven-development` (default executor), `/superpowers:executing-plans` (headless mode), `/superpowers:systematic-debugging` |
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

> ⚠️ **ALWAYS create a worktree**, even if on a feature branch. Being on "a feature branch" doesn't mean it's the right branch for THIS feature. Worktrees ensure parallel sessions never mix work.

```bash
FEATURE_NAME="$ARGUMENTS"
WORKTREE_PATH=".worktrees/$FEATURE_NAME"

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
elif git show-ref --quiet "refs/heads/feat/$FEATURE_NAME" 2>/dev/null; then
  git worktree add "$WORKTREE_PATH" "feat/$FEATURE_NAME"
  echo "✓ Created worktree for existing branch at $WORKTREE_PATH"
else
  git worktree add "$WORKTREE_PATH" -b "feat/$FEATURE_NAME" "$BASE"
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

- All file paths are relative to the worktree (e.g., `src/main.py`, not `.worktrees/auth/src/main.py`)
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

| Field     | Value                   |
| --------- | ----------------------- |
| Command   | /new-feature $ARGUMENTS |
| Phase     | Pre-Flight              |
| Next step | Verify plugins          |

### Checklist

- [x] Worktree created
- [x] Project state read
- [ ] Plugins verified
- [ ] PRD created
- [ ] Research artifact produced (`docs/research/` — via research-first agent)
- [ ] Design guidance loaded (if UI)
- [ ] Brainstorming complete
- [ ] Approach comparison filled
- [ ] Contrarian gate passed (skip | spike | council)
- [ ] Council verdict (if triggered) — verdict persisted in plan file, not here
- [ ] Plan written
- [ ] Plan review loop (0 iterations) — iterate until no P0/P1/P2
- [ ] TDD execution complete
- [ ] Code review loop (0 iterations) — iterate until no P0/P1/P2
- [ ] Simplified
- [ ] Verified (tests/lint/types)
- [ ] E2E use cases designed (Phase 3.2b)
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] E2E regression passed (Phase 5.4b)
- [ ] E2E use cases graduated to tests/e2e/use-cases/ (Phase 6.2b)
- [ ] E2E specs graduated to tests/e2e/specs/ (Phase 6.2c — if Playwright framework installed)
- [ ] Learnings documented (if any)
- [ ] State files updated
- [ ] Committed and pushed
- [ ] PR created
- [ ] PR reviews addressed
- [ ] Branch finished
```

### 4. Verify required plugins are available (test ONE skill)

```
/superpowers:brainstorming
```

**If "Unknown skill" error:**

- STOP immediately
- Tell user: "Required plugins not loaded. Please enable in ~/.claude/settings.json and restart Claude Code."
- Do NOT proceed with workarounds or skip mandatory steps

**Checkpoint:** Check off "Plugins verified" in .claude/local/state.md and set Next step to "PRD created".

### 5. Worktree Policy Reminder

**DO NOT create additional worktrees** during this workflow. If `/superpowers:brainstorming` or other skills attempt to create a worktree, **SKIP that step** - you're already isolated.

---

## Phase 1: Requirements

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `1 — Requirements`, Next step: `PRD discuss`.

Run the PRD workflow:

```
/prd:discuss
```

Then create the PRD:

```
/prd:create
```

---

## Phase 2: Research (MANDATORY — agent-enforced)

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `2 — Research`, check off "PRD created".

Before writing ANY design, research every external library and API this feature touches. This is enforced via the `research-first` agent — not optional guidance.

### 2.1 Dispatch research-first agent

```
Task tool → subagent_type: "research-first", prompt: "Feature: <feature-name>. PRD: <path-to-PRD-or-inline-description>. Manifests: package.json, pyproject.toml (check which exist). Research all external libraries and APIs this feature will touch."
```

The agent will:

1. Scan the PRD + manifests to identify research targets
2. Query Context7, WebFetch, and WebSearch for each (current docs, breaking changes, best practices)
3. Write a structured brief to `docs/research/YYYY-MM-DD-<feature>.md`
4. Return a summary with findings count and key discovery

### 2.2 Review the brief

Read `docs/research/YYYY-MM-DD-<feature>.md`. Verify:

- Every library/API the feature touches is listed
- Each has ≥ 2 sources with access dates
- "Design impact" and "Test implication" fields are filled (not blank or "N/A" for all)
- "Open Risks" section is present

If the brief is shallow or missing targets, re-dispatch the agent with more specific instructions.

### 2.3 Fallback: if agent dispatch or web tools fail

If the `research-first` agent cannot be dispatched (Task tool unavailable) or web tools are down (Context7/WebSearch/WebFetch all failing):

1. **You (the main agent) perform the research manually:**
   - Query Context7 for each library (if available)
   - Use WebSearch/WebFetch for changelogs and docs
   - If all web tools are down, check lockfile versions + `node_modules/<lib>/CHANGELOG.md` locally
2. **Fill out the research template yourself** and save to `docs/research/YYYY-MM-DD-<feature>.md`
3. **Note in the brief:** "Fallback: main agent performed research (agent dispatch unavailable)"

This is the degraded path, not the skip path. Research still happens — just without the dedicated agent.

### 2.4 Gate: cannot proceed without research artifact

**Phase 3 (Design) MUST NOT start until `docs/research/YYYY-MM-DD-<feature>.md` exists and passes the review above.**

**Gate criteria:**

- If libraries were researched → each researched library must have ≥ 2 sources, a "Design impact" field, and a "Test implication" field. Items explicitly triaged to "Not Researched" (with justification) are exempt.
- If no external libraries/APIs → the agent writes a minimal N/A brief and that counts as passing the gate
- If fallback path was used → the brief must still meet the same criteria

---

## Phase 3: Design + Review Loop (iterates until no P0/P1/P2 issues)

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `3 — Design`, check off "Research artifact produced".

### 3.0 Load Design Guidance (if UI work)

If this feature involves ANY user-facing interface (web pages, components, dashboards, forms, landing pages):

    /ui-design

This loads the full design skill — creative direction, animation techniques, typography and color systems, and the polish checklist. It ensures the **plan** includes visual design decisions, not just technical architecture.

**Skip this step if:** the feature is purely backend with no UI impact, or if `/ui-design` is not available (Python-only projects without the skill installed).

### 3.1 Brainstorm approaches

```
/superpowers:brainstorming
```

### 3.1b Approach Comparison (MANDATORY)

After brainstorming produces 2+ approaches, produce the comparison table **in this conversation**, using the schema below. Do NOT write it to `.claude/local/state.md` — `.claude/local/state.md` is status-only (checklist + phase tracking); design content never goes there.

Phase 3.1c will pass this exact table to the Contrarian gate (verbatim), and Phase 3.2 will persist it into the plan file header. The table lives in your active context between those two phases — keep it intact.

```markdown
## Approach Comparison

### Chosen Default

[The approach you recommend]

### Best Credible Alternative

[The strongest competing approach — not a strawman]

### Scoring (fixed axes)

| Axis                  | Default | Alternative |
| --------------------- | ------- | ----------- |
| Complexity            | L/M/H   | L/M/H       |
| Blast Radius          | L/M/H   | L/M/H       |
| Reversibility         | L/M/H   | L/M/H       |
| Time to Validate      | L/M/H   | L/M/H       |
| User/Correctness Risk | L/M/H   | L/M/H       |

### Cheapest Falsifying Test

[How to resolve ambiguity with a spike or experiment. Estimate: < 30 min or > 30 min.]
```

If brainstorming produced only one viable approach, still run the Contrarian gate — it validates that no alternative was missed. Write "Single viable approach identified" in the Alternative column and let Codex confirm or challenge.

### 3.1c Contrarian Gate (MANDATORY)

The Contrarian/Codex validates the "default wins" claim. **Claude cannot self-certify the skip.**

Immediately invoke `/council` in auto-trigger mode — ideally in the same turn as Phase 3.1b so the comparison table is still in active context. Build the `/council` argument from the EXACT `## Approach Comparison` block you just produced in Phase 3.1b and paste that block **VERBATIM** into the request — including `### Chosen Default`, `### Best Credible Alternative`, the full 5-axis scoring table, and `### Cheapest Falsifying Test`. Do NOT summarize, paraphrase, or re-score when you have the block in context.

**Compaction recovery (rare).** If compaction or `/clear` has removed the exact 3.1b block before you reach this step, do NOT reconstruct it from a fragmentary recollection — that loses fidelity. Instead: re-run the 3.1b brainstorming step explicitly (or ask the user to restate the approach they chose), produce a fresh `## Approach Comparison`, then continue here. The durable home for this comparison is the plan file (persisted in Phase 3.2); the 3.1b → 3.1c → 3.2 window is the only fragile span, and it typically fits in one conversational turn. If that span repeatedly spans compactions in your project, consider filing an issue to revisit in-context handling vs a scratch file.

Invocation template — begin the `/council` argument with the explicit gate directive below so the skill's auto-trigger detection fires (per `.claude/skills/council/SKILL.md` Step 0 + `references/peer-review-protocol.md` "Contrarian Gate" + "Auto-Trigger Integration"), NOT the standalone 5-advisor path. The skill runs its internal Contrarian-then-maybe-spike-then-maybe-council flow and returns the workflow's next action (VALIDATE, SPIKE, or COUNCIL):

```
/council Phase 3.1c Contrarian Gate — auto-trigger mode per references/peer-review-protocol.md "Auto-Trigger Integration" section. Run the Contrarian → optional-spike → optional-escalation flow and return the workflow's final decision: VALIDATE (proceed), SPIKE (run the test first), or COUNCIL (fire full council). Do NOT return a standalone 5-advisor chairman verdict unless the internal flow actually escalated to the full council. Approach comparison to evaluate (verbatim from Phase 3.1b):

## Approach Comparison

### Chosen Default
[exact text from 3.1b]

### Best Credible Alternative
[exact text from 3.1b]

### Scoring (fixed axes)
| Axis                  | Default | Alternative |
|-----------------------|---------|-------------|
| Complexity            | L/M/H   | L/M/H       |
| Blast Radius          | L/M/H   | L/M/H       |
| Reversibility         | L/M/H   | L/M/H       |
| Time to Validate      | L/M/H   | L/M/H       |
| User/Correctness Risk | L/M/H   | L/M/H       |

### Cheapest Falsifying Test
[exact text from 3.1b]
```

The council skill currently emits its decision as **prose**, not as a clean token. Translate its response into one of `{VALIDATE, SPIKE, COUNCIL}` using this mapping, then proceed per the outcome table below:

| Skill response (prose)                                                                       | Workflow token                                                                                                                                                                                                                  |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Contrarian validated. Proceeding with default approach."                                    | VALIDATE                                                                                                                                                                                                                        |
| "Proceed with default. Trade-off documented." (OBJECT + low-impact surface + expensive test) | VALIDATE (with the trade-off noted in Phase 3.2's Contrarian Verdict section)                                                                                                                                                   |
| "Run spike first: [test description]"                                                        | SPIKE — run the test. Update the Approach Comparison with the spike's findings (may change `### Chosen Default` / `### Best Credible Alternative` / scoring) BEFORE re-invoking 3.1c. Do NOT re-send the stale pre-spike block. |
| Full `## Council Verdict` block with 3–5 advisors and chairman synthesis                     | COUNCIL — the chairman's `### Recommendation` supersedes the 3.1b default; update the Approach Comparison accordingly in Phase 3.2                                                                                              |
| Raw "INSUFFICIENT" (per `references/peer-review-protocol.md`)                                | COUNCIL — fire the full council; the protocol defines INSUFFICIENT as "ambiguity = risk, escalate"                                                                                                                              |
| Raw "OBJECT" without spike-or-council decision                                               | COUNCIL — escalate per protocol (OBJECT + no cheap test ⇒ council)                                                                                                                                                              |
| Anything else unrecognizable                                                                 | Escalate to the user: "/council returned X, should I treat as VALIDATE, SPIKE, or COUNCIL?"                                                                                                                                     |

The council skill handles the gate:

- **VALIDATE** → skip council, proceed to 3.2
- **SPIKE** → run the cheapest falsifying test first, then re-evaluate
- **COUNCIL** → full council runs, verdict picks the approach, proceed to 3.2

If Codex unavailable: present the approach comparison to the user and ask them to validate.

Check off in .claude/local/state.md: `- [x] Contrarian gate passed (skip | spike | council)` — this checkbox is status, which is fine. The verdict text itself stays in-context (and ultimately lands in the plan file per Phase 3.2).

### 3.2 Write the implementation plan

Invoke `/superpowers:writing-plans` to create the plan file. **Respect `writing-plans`'s required header shape** — it produces the plan with an H1 banner plus the `**Goal:**`, `**Architecture:**`, `**Tech Stack:**` block at the top (see `writing-plans/SKILL.md`). Do NOT move or replace that header.

After `writing-plans` produces the base plan, persist the **final** Approach Comparison into the plan file — "final" means the one that won Phase 3.1c:

1. **Determine the final comparison:**
   - If 3.1c returned **VALIDATE**: the Phase 3.1b table IS the final (unchanged).
   - If 3.1c returned **SPIKE → re-evaluated**: the spike may have confirmed the default or swung the choice. Update the table's `### Chosen Default` / `### Best Credible Alternative` to reflect what actually won. Add a one-line spike-result note.
   - If 3.1c returned **COUNCIL**: the council verdict's Recommendation becomes `### Chosen Default`. Swap the alternative to match. Do NOT preserve the pre-council table unchanged.
2. **Insert** the final `## Approach Comparison` block into the plan file **immediately after** `writing-plans`'s Goal/Architecture/Tech Stack header, **before** any Files / Tasks / Implementation Notes sections. If `writing-plans` doesn't include it, Edit the file to insert it there.
3. **Append** a `## Contrarian Verdict` subsection below the Approach Comparison recording the gate result (`VALIDATE` / `SPIKE` / `COUNCIL`) plus a one-sentence rationale from 3.1c.
4. The `**Architecture:**` field that `writing-plans` produces in the required header (inline field — not a heading) should be a 2–3-sentence recap referencing the Approach Comparison — not a restatement.

This is the single moment design content leaves your in-memory context and becomes durable in the plan file at `docs/plans/<feature>.md`. The per-developer `.claude/local/state.md` keeps only the workflow checkbox — the design rationale lives in the plan file from here on.

```
/superpowers:writing-plans
```

### 3.2b Design E2E Use Cases (if user-facing)

If this feature changes any user-facing behavior (UI, API, flows, forms, navigation, permissions), design E2E use cases NOW — before implementation, not after.

Write use cases in the plan file under a `#### E2E Use Cases` heading, using the template from `rules/testing.md`. Each use case declares its **Interface** (API / UI / CLI / API+UI) based on the project-type matrix in `rules/testing.md` — and includes **Setup** (sanctioned method per the ARRANGE/VERIFY boundary), **Steps**, **Verification**, and **Persistence**.

**Project type scope** (from `CLAUDE.md` `## E2E Configuration`):

- **fullstack:** API use cases + UI use cases (API-first ordering for execution)
- **api:** API use cases only
- **cli:** CLI use cases only
- **hybrid:** declare per use case

Think like a user, not a developer:

- What will the user try to do with this feature?
- What's the happy path? What are the error paths?
- What existing flows could this break?

**Minimum:** 1 happy-path use case + 1 error/edge case. Complex features need more.

**If purely internal (no user-facing impact):** Write "E2E: N/A — [reason]" in the plan.

### 3.3 Plan Review Loop (MANDATORY)

Go back to the implementation plan and check everything proposed against the actual code. All available reviewers run **in parallel**, iterating until clean.

**Per iteration:**

**Step A — Run both reviews in parallel:**

**a) Claude (you) reviews the plan against the codebase:**

Read every file the plan proposes to modify. For each change, ask:

- Does the plan account for what the code actually looks like today?
- Are there existing utilities, patterns, or abstractions the plan should use instead of creating new ones?
- Are there correctness issues, missing edge cases, or integration problems?
- Is the testing strategy adequate?

> **Note:** "Is there a simpler approach?" is no longer asked here — the Approach Comparison + Contrarian Gate (3.1b/3.1c) already settled the strategic choice. This review validates the HOW, not the WHAT.

Document your findings as a severity-tagged list (P0/P1/P2/P3).

**b) Codex reviews independently:**

Check if Codex CLI is available:

```bash
command -v codex &>/dev/null && echo "Codex available" || echo "Codex not installed"
```

If available:

```
/codex review the implementation plan and check everything we're proposing versus the code — is this the simplest, fastest, best way to do it? Flag any architectural concerns.
```

Note: The `/codex` command's Design Review Mode uses its own fixed prompt — it may not return P0/P1/P2/P3 tags directly. After receiving Codex's output, classify each finding into P0/P1/P2/P3 using the severity rubric before evaluating exit criteria.

If Codex is NOT available:

- Present your own review findings plus a summary of the plan to the user
- Ask: "Does this design approach look right before I start implementing?"
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

> **Why mandatory?** Fixing a design flaw after implementation is 10x more expensive than catching it here. Two independent reviewers checking the plan against the actual code catches things a single pass misses.

---

## Phase 4: Execute

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `4 — Execute`, check off design items (brainstorming, plan, review).
>
> **Optional before starting:** Run `/compact` if the session is heavy with brainstorm + plan-review discussion. Consolidates prior phases into a structured summary and frees budget for execution. Reminder, not a gate.

### Trivial plans (≤3 tasks)

No dispatch plan needed. Use `superpowers:subagent-driven-development` and execute the plan's tasks sequentially in order. Proceed to Phase 5 when done.

### Full plans (4+ tasks)

#### 4.0 Dispatch Plan (MANDATORY before dispatching any subagent)

Append a `## Dispatch Plan` heading to the plan file with one row per task:

| Task ID | Depends on | Writes (concrete file paths)                           |
| ------- | ---------- | ------------------------------------------------------ |
| B1      | —          | `alembic/versions/2026_04_22_add_series.py`            |
| B2      | B1         | `schemas/backtest.py`                                  |
| B3      | —          | `analytics_math/deduplicate.py`, `tests/test_dedup.py` |

**`Writes` must list concrete file paths** — not directories, not globs. New files use their final intended path. Conflict detection is per physical file.

**Scheduling — serial is the default; parallel requires proven independence:**

- **Ready set:** tasks whose `Depends on` entries are all completed
- **Dispatch rule:** start any ready task whose `Writes` paths are disjoint from every currently-running task's `Writes`
- **Concurrency cap:** default 3 concurrent subagents; raise to 5 only for small, genuinely independent tasks. (3 is practitioner guidance from Anthropic's [multi-agent research post](https://www.anthropic.com/engineering/multi-agent-research-system), not a hard protocol limit.)
- **Continuous dispatch:** when a subagent returns, re-evaluate the ready set and dispatch immediately. Do not batch into waves.
- **In doubt, serialize.** File-disjointness is necessary but not sufficient — if two tasks share types, schemas, or imports, encode as `Depends on` and serialize.

**No append-only fast-path.** Tasks that both modify the same existing file — barrel exports (`index.ts`, `__init__.py`), migration manifests, shared schemas, `pyproject.toml`, etc. — **must be serialized via `Depends on`**. Same-second timestamp migrations collide on filename and on `alembic_version` head; do not parallelize migration generation. The only case where two tasks may concurrently "add" to a shared space is when each creates a **distinct new file at a different path**, in which case the `Writes` column already lists disjoint paths and the standard dispatch rule applies.

**Sequential override:** if the plan is tightly coupled (most tasks share files or types, or the feature reads as one logical change), note `"sequential mode"` in the dispatch plan and dispatch one subagent at a time. This is Cognition's documented counter-position on multi-agent orchestration and a legitimate choice for high-coupling work — parallelism is not always a win.

#### 4.1 Execute via subagent-driven-development

Use `superpowers:subagent-driven-development`. Per dispatch cycle:

1. Pick next eligible task per 4.0 rules
2. Dispatch fresh subagent with TDD discipline (Red-Green-Refactor)
3. Review diff on return before marking the task done
4. Re-evaluate ready set, dispatch next

**Handling failures:**

- Subagent returns failure, OR diff-review rejects the result → mark the task failed in the dispatch plan, cancel any in-flight dependents, surface to the user before continuing
- Rate limit or timeout → retry once with a fresh subagent; if it fails again, treat as a failure
- After each task completes, verify in-flight dependents' assumptions still hold. If a completed task introduced a breaking change to shared code, cancel the dependent and re-dispatch with updated context

**If you encounter bugs during implementation:**

```
/superpowers:systematic-debugging
```

#### 4.2 Headless / Walk-Away Mode (OPT-IN)

Say **"walk-away mode"** or **"headless"** to switch to `/superpowers:executing-plans` in a separate session. Headless loses the live parallelism of 4.1 but gains context independence — useful for long plans (15+ tasks) or when you want to step away. Default is in-session subagent-driven.

---

## Phase 5: Quality Gates (ALL REQUIRED)

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `5 — Quality Gates`, check off "TDD execution complete".
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

The verify-e2e agent tests as a real user: no database access, no internal endpoints, no source code reading. It executes the use cases from your Phase 3.2b plan through the product's actual user-facing interfaces and returns a markdown report in its response. **The agent is read-only — YOU persist the report to disk.**

**⚠ ARRANGE boundary (main agent, read before invoking verify-e2e):** Even when setting up test data for verify-e2e yourself, you are bound by the same ARRANGE rule. **Never** run raw DB writes (`psql -c "INSERT"`, `docker exec … psql -c "INSERT"`, `mysql -e "UPDATE"`, `mongosh --eval db.x.insertOne(…)`), internal/undocumented endpoints, or on-disk file-injection to seed state. Setup must go through the app's public API, signup/login flows, app CLI, UI, or documented seed commands (`make seed-dev`, `manage.py loaddata`). **If the sanctioned setup path is broken** (e.g., the app's seed CLI has a bug), **FIX the bug first** — do not route around it via direct DB writes. This is NO BUGS LEFT BEHIND applied at the E2E boundary. Routing around a broken sanctioned path is itself a bug to fix.

**Step 1: Ensure servers are running from this worktree**

If you're in a worktree, dev servers may still be running from the main directory serving OLD code. Restart them from the worktree before invoking verify-e2e.

**Step 2: Invoke verify-e2e**

```
Task tool → subagent_type: "verify-e2e", prompt: "Mode: feature. Plan file: [path to your plan file]. Project type: [fullstack|api|cli|hybrid from CLAUDE.md]. Execute all E2E use cases and return a verification report."
```

**Step 3: Persist the report (MANDATORY)**

The agent's response starts with a two-line header:

```
VERDICT: PASS | FAIL | PARTIAL
SUGGESTED_PATH: tests/e2e/reports/YYYY-MM-DD-HH-MM-<feature-or-mode>.md
---
<full markdown report body>
```

Parse the header, then `Write` the report body (everything after `---`) to the suggested path. Create the `tests/e2e/reports/` directory if it doesn't exist:

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
`- [x] E2E verified — N/A: internal migration, no user-facing changes`

**Non-browser projects** (API-only, CLI): the verify-e2e agent handles these via HTTP/subprocess. The use case template applies; no Playwright needed.

### 5.4b E2E Regression (MANDATORY if tests/e2e/use-cases/ has files)

Run the full regression suite to catch regressions in previously shipped flows. This is what prevents your new feature from breaking the features that came before it.

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
- **FAIL_BUG (framework: spec failure; agent: FAIL_BUG verdict):** This feature broke something that previously worked. Fix it, then re-run 5.4b (and 5.4 if this feature has its own user-facing E2E scope).
- **FAIL_STALE (agent only):** Update stale use case file and re-run.
- **FAIL_INFRA / flake (both paths):** Retry once. If still failing, report to user for decision.

**Note:** `pnpm exec playwright test` runs the binary directly — no `package.json` script is required. setup.sh does not modify `package.json`; use the binary invocation above.

---

## Phase 6: Finish

> **Checkpoint:** Update `## Workflow` in .claude/local/state.md — Phase: `6 — Finish`, check off quality gate items.

### 6.1 Compound learnings (if any)

If you fixed bugs or discovered patterns, document them:

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

### 6.2 Update state files

1. **.claude/local/state.md**: Update Done (keep 2-3 recent), Now, Next
2. **docs/CHANGELOG.md**: If 3+ files changed on branch

### 6.2b Graduate E2E Use Cases (MANDATORY if use cases were created)

Move passing use cases from the plan file to `tests/e2e/use-cases/<feature-name>.md` as permanent regression tests.

```bash
mkdir -p tests/e2e/use-cases
# Extract the E2E Use Cases section from the plan and write as the feature file.
# Keep the same UC format (Interface, Setup, Steps, Verify, Persist).
```

Optionally tag critical paths with `@smoke` for fast regression checks.

**If no user-facing changes:** Skip this step.

### 6.2c Graduate to Playwright Specs (OPTIONAL — if framework installed)

If this project has opted into the Playwright framework (`playwright.config.ts` exists at project root), also graduate each passing use case to a deterministic `.spec.ts` file.

**Check if framework is installed:**

```bash
[ -f playwright.config.ts ] && echo FRAMEWORK || echo SKIP
```

**If SKIP (no framework):** Skip this step entirely. Proceed to 6.3.

**If FRAMEWORK is installed, YOU (the main implementation agent) write the spec file.** The verify-e2e agent does NOT have Write tools and cannot do this. Here's how:

1. **Read the source inputs:**
   - The markdown use case file: `tests/e2e/use-cases/<feature-name>.md` (intent of truth)
   - The verify-e2e report from Phase 5.4: `tests/e2e/reports/<latest>.md` (contains observed selectors, outcomes per UC)

2. **Reference the example template:** `templates/playwright/example.spec.template.ts` in the claude-codex-forge checkout — this is a skeleton for spec file structure.

3. **Write `tests/e2e/specs/<feature-name>.spec.ts`:**
   - One `test.describe('Feature: <feature-name>', () => {...})` block
   - One `test(...)` per UC that passed verification
   - Use selectors from the verify-e2e report's "Observed selectors" section
   - Prefer `getByRole`, `getByLabel`, `getByTestId` over CSS class selectors
   - Tag critical happy-paths with `@smoke` in the test name (e.g., `test('UC1: User creates a todo @smoke', ...)`)
   - Do NOT inline auth — use the fixture pattern (see `tests/e2e/fixtures/auth.ts`)
   - Do NOT generate specs for UCs that were FAIL_BUG or FAIL_STALE — skip them

4. **Skip UCs where the verify-e2e report flagged "Selector ambiguity":** Note this in .claude/local/state.md for follow-up; the user can add `data-testid` attributes and regenerate.

5. **Run the spec once locally to verify it's green:**

   ```bash
   pnpm exec playwright test tests/e2e/specs/<feature-name>.spec.ts
   ```

   If it fails, fix the selector ambiguity rather than committing a broken spec.

**Commit the generated spec:** It becomes part of the regression suite and runs in CI for every future PR.

**Skip this step entirely if:**

- Project doesn't have Playwright framework installed (no `playwright.config.ts`)
- No user-facing changes (Phase 5.4 was N/A)
- All UCs had selector ambiguity (note this and defer until testids are added)

### 6.3 Commit and push

```bash
git add -A
git commit -m "feat: [descriptive message based on changes]"
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

---

## Checklist

**The live checklist is in `## Workflow` in .claude/local/state.md** — initialized in Pre-Flight step 3.

The Stop hook reminds you of the current phase on every response. The PreToolUse hook blocks commit/push/PR until review, simplify, and verify are checked off. Update the checklist after each step.
