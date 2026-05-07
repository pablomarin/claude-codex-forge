---
name: council
description: >
  Engineering Council — multi-perspective decision analysis using model diversity
  (Claude subagents + Codex CLI). Spawns 3-5 advisors with different thinking styles,
  runs anonymous peer review, and synthesizes a verdict with mandatory minority reports.
  Use when facing architectural decisions, approach trade-offs, or any fork-in-the-road
  where being wrong is expensive. Invoke with "/council <question>" or triggered
  automatically during brainstorming when genuine ambiguity is detected.
  Also triggers on: "council this", "get multiple perspectives", "should we use X or Y",
  "what's the best approach", "I'm torn between", "need a second opinion on architecture".
argument-hint: <question or decision to analyze>
---

# Engineering Council

> Fight sycophancy with model diversity. 5 advisors argue, a chairman from a different model synthesizes, disagreement is preserved.

## Step 0: Detect Mode and Check Prerequisites

**Mode detection from `$ARGUMENTS`:**

- If `$ARGUMENTS` contains a question/decision → **Standalone mode** (full 5 advisors)
- If called from within `/new-feature` or `/fix-bug` with approach comparison data → **Auto-trigger mode** (3-then-5 escalation)

**Check Codex availability:**

```bash
command -v codex &>/dev/null && echo "CODEX_AVAILABLE" || echo "CODEX_UNAVAILABLE"
```

**If CODEX_UNAVAILABLE:**

- Claude advisors still run
- Contrarian gate → user validates instead
- Chairman → user is chairman (raw outputs shown, user decides)
- Announce: "Codex not installed. Running Claude advisors only — you'll be the chairman."

## Step 1: Gather Context

Run these in parallel:

```bash
git diff --stat
git status --short
```

Read any files referenced in the question. If an approach comparison table exists (auto-trigger mode), include it.

## Step 2: Load Advisor Profiles

Read `references/advisors.md` to get the 5 advisor personas and their engine assignments.

**For standalone mode:** Use all 5 advisors. If Codex is unavailable, use only the Claude-engine advisors (Simplifier, Scalability Hawk, Pragmatist).
**For auto-trigger mode:** Start with the 3 quick-council advisors (Simplifier, Contrarian, Pragmatist). If Codex is unavailable, use Simplifier + Pragmatist only (skip Contrarian — user validates instead).

## Step 3: Dispatch Advisors IN PARALLEL

**CRITICAL: All advisors must dispatch simultaneously.**

**Claude advisors:** Use the Task tool with `subagent_type: "council-advisor"`. Send ALL Claude advisor Task calls in a SINGLE message (parallel execution). Each prompt includes:

1. The persona text from `advisors.md`
2. The question/decision + context
3. Instruction to follow the output schema from `references/output-schema.md`

**Codex advisors:** Use `.claude/hooks/lib/codex-pty.sh exec` (the PTY shim — works around openai/codex#19945) via the Bash tool with `run_in_background: true`. On Windows, use `.claude/hooks/lib/codex-pty.ps1` instead. Each call includes:

1. The persona text
2. The question/decision + context
3. The output schema instructions

See `references/peer-review-protocol.md` for exact dispatch commands.

**Wait for ALL advisors to complete before proceeding.**

## Step 4: Evaluate Responses (Auto-Trigger Mode Only)

If in auto-trigger mode with 3 advisors, check escalation triggers:

- Any advisor returned OBJECT → escalate to 5
- Any advisor reports low confidence → escalate to 5
- Decision affects irreversible surface (see `references/peer-review-protocol.md` for canonical list) → escalate to 5
- No majority verdict → escalate to 5

If escalating: dispatch the 2 remaining advisors (Scalability Hawk + Maintainer) in parallel. Wait for completion.

## Step 5: Chairman Synthesis

**If Codex available:**

Construct the chairman prompt with:

- All raw advisor outputs (complete, unedited)
- The original question/decision
- Relevant codebase context (file list, git status)
- Instruction to produce the Chairman Output Format from `references/output-schema.md`
- Explicit instruction: "You MUST include a Minority Report section if any advisor OBJECTed"

Run via `.claude/hooks/lib/codex-pty.sh exec` with `reasoning_effort=xhigh`. Timeout: 1200000ms.

See `references/peer-review-protocol.md` for the exact chairman command.

**If Codex unavailable:**

Skip synthesis. Present raw outputs to user (see Step 6).

## Step 6: Present Results

**With Codex chairman:**

Display the chairman's output VERBATIM (do not rewrite, summarize, or editorialize). Then show raw advisor outputs in a collapsible section:

```markdown
## Council Result

[Chairman output — verbatim]

<details>
<summary>Individual Advisor Responses (N)</summary>

[All raw advisor outputs]

</details>
```

**Without Codex (user is chairman):**

Display all raw advisor outputs prominently (not collapsed):

```markdown
## Council Perspectives

### The Simplifier (Claude)

[full response]

### The Pragmatist (Claude)

[full response]

---

**You are the chairman.** Based on these perspectives:

1. Which approach do you want to proceed with?
2. Are there any blocking objections you want addressed first?
```

## Auto-Trigger Integration (called from workflows)

When called from `/new-feature` or `/fix-bug` Phase 3.1, the approach comparison has already been filled. The flow is:

1. **Contrarian Gate** — Single Codex call validates the "default wins" claim (see `references/peer-review-protocol.md`)
2. **If VALIDATE** → return "Contrarian validated. Proceeding with default approach."
3. **If OBJECT** → check cheapest falsifying test:
   - If < 30 min → return "Run spike first: [test description]"
   - If ≥ 30 min AND high-impact surface → fire 3-advisor council (Steps 3-6)
   - If ≥ 30 min AND NOT high-impact → return "Proceed with default. Trade-off documented."
4. **If INSUFFICIENT** → fire 3-advisor council (Steps 3-6)

**High-impact surfaces** (canonical list — defined in `references/peer-review-protocol.md`):
schema/migration, public API contract, authentication/permissions, payment/billing, configuration defaults affecting all users, rollout/deployment strategy, architecture boundaries (service boundaries, shared libraries, database ownership).
