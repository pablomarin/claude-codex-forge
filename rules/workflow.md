# Workflow

**Use workflow commands.** They contain the full process - follow them exactly.

## Decision Matrix

| Scenario                   | Action                                              |
| -------------------------- | --------------------------------------------------- |
| Starting new feature       | Run `/new-feature <name>` (creates worktree)        |
| Fixing a bug               | Run `/fix-bug <name>` (creates worktree)            |
| Trivial change (< 3 files) | Run `/quick-fix <name>` (no worktree)               |
| Want a second opinion      | Run `/codex <instruction>` (code review or general) |
| Multi-perspective analysis | Run `/council <question>` (5 advisors + chairman)   |
| Creating PR to main        | **Ask**                                             |
| Merging PR to main         | **Ask**                                             |
| Skipping tests             | **Never**                                           |

## Workflow Tracking

**When a workflow is active** (`## Workflow` in .claude/local/state.md has Command != `none`):

1. **Before each action**: Read `## Workflow` in .claude/local/state.md — check current Phase and Next step
2. **Execute only** the `Next step` listed
3. **After completing a step**: Check the box in the Checklist and advance `Next step` to the next unchecked item
4. **On phase transition**: Update the `Phase` field

The Stop hook reminds you of the current phase on every response. The PreToolUse hook blocks commit/push/PR if quality gates are incomplete. This rule is re-injected every turn — it survives context compaction.

## Council During `/forge-goal` Autonomous Run

When a `/forge-goal`-driven `/goal` is active (`## /goal session` is populated in `.claude/local/state.md` with a non-empty nonce), the agent's pause-for-user discipline changes:

**Before asking the user any question during the autonomous run, ask yourself:**

> _Is this a PR creation authorization?_

- **If YES:** call `AskUserQuestion` with the PR-create modal. The user's answer is the only human-authority signal in the loop.
- **If NO:** invoke `/council` with the question. Apply the chairman's verdict. Continue the loop.

**Triggers for council** (the agent invokes council at its discretion when):

- An ambiguous product or technical choice would otherwise prompt the user
- A reviewer recommends plan revision (not just code patch)
- A high-impact implementation fork has multiple defensible approaches
- A retried tool/subagent has also failed
- Council/reviewer output is unrecognizable and needs interpretation

**Explicit NON-triggers:**

- Normal plan-review-loop iterations (Claude + Codex back-and-forth on the plan) — these stay as today's reviewer iteration flow
- Normal code-review-loop iterations (Codex + PR-toolkit + Claude fix cycles)
- Any moment that doesn't actually require human-level judgment

**Council failure handling:** If `/council` itself fails (network, advisor timeout, missing chairman verdict), the autonomous loop pauses and writes a blocker line to `.claude/local/state.md` (`## Blockers`). The user takes over.

**Audit:** Each council invocation during an autonomous run is durable in the conversation transcript — the agent's response naming the council outcome and the applied action is the record. No separate audit log file.

## Severity Rubric

| Level | Meaning                                                                | Action                     |
| ----- | ---------------------------------------------------------------------- | -------------------------- |
| P0    | Broken — will crash, lose data, or create security vulnerability       | Must fix before proceeding |
| P1    | Wrong — incorrect behavior, logic error, missing edge case             | Must fix before proceeding |
| P2    | Poor — code smell, maintainability issue, unclear intent, missing test | Must fix before proceeding |
| P3    | Nit — style, naming, minor suggestion                                  | May fix, does not block    |

## Revision Loop Protocol

Two revision loops enforce quality as a discipline protocol. Both follow the same pattern:

1. Run all available reviewers in parallel
2. Collect severity-tagged findings (P0/P1/P2/P3) using the rubric above
3. If P0/P1/P2 found → fix, increment counter in the workflow checklist, repeat
4. If only P3 or clean → check the box with final iteration count, proceed (P3s do not block)

**Plan review loop** (Phase 3, when entered): Claude + Codex review the plan against actual code.
Exit when: no P0/P1/P2 from all available reviewers on the same pass.
If Codex unavailable: Claude + user confirmation is sufficient.
Note: `/fix-bug` skips Phase 3 for simple fixes (1-2 files) UNLESS the fix touches a high-impact surface (see canonical list in `references/peer-review-protocol.md`).

**Approach comparison** (Phase 3, after brainstorming): Claude fills comparison table with fixed axes (Complexity, Blast Radius, Reversibility, Time to Validate, User/Correctness Risk). Contrarian/Codex validates the "default wins" claim. Council fires on OBJECT + high-impact surface. Spike first if cheapest falsifying test < 30 min.
If Codex unavailable: user validates skip.

**Code review loop** (Phase 5): Codex + PR Review Toolkit review the implementation.
Exit when: no P0/P1/P2 from all available reviewers on the same pass.
If Codex unavailable: PR Toolkit alone is sufficient.
If PR Toolkit unavailable: Codex alone is sufficient.
If neither available: alert user, manual review + user sign-off.

Never check a loop box until all available reviewers pass clean on the same iteration.
