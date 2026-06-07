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
- A convergence-breaker (non-convergence) halt — human-only by design: write the Blockers line and stop; council may be invoked BY the human afterward, never as the autonomous risk-acceptor.
- Any moment that doesn't actually require human-level judgment

**Council failure handling:** If `/council` itself fails (network, advisor timeout, missing chairman verdict), the autonomous loop pauses and writes a blocker line to `.claude/local/state.md` (`## Blockers`). The user takes over.

**Audit:** Each council invocation during an autonomous run is durable in the conversation transcript — the agent's response naming the council outcome and the applied action is the record. No separate audit log file.

**Ask-tier commands stall autonomous runs.** Any `rm -rf` / `rm -r` is ask-tier in Forge settings (`Bash(rm -rf:*)` / `Bash(rm -r:*)`) — a `/goal` loop and its subagents CANNOT self-approve the permission prompt, so the run silently hangs until a human notices. Never construct an ask-tier command when a prompt-free alternative exists: tool cache flags (`mypy --no-incremental`, `pytest --cache-clear`, `ruff check --no-cache` — see `rules/python-style.md`), `: >` truncate instead of `rm` for temp files. If a recursive delete is genuinely unavoidable, say so explicitly before running it so the pause is expected, not silent.

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
Codex is mandatory (this repo is Claude × Codex dual-engine). If Codex is unavailable, `/goal` halts and a human takes over; the loop cannot self-complete without real Codex evidence. The only ship escape is `- [x] Plan review loop — N/A: <reason>` for degraded interactive use, caught at PR review.
Note: `/fix-bug` skips Phase 3 for simple fixes (1-2 files) UNLESS the fix touches a high-impact surface (see canonical list in `references/peer-review-protocol.md`).

**Plan-stage severity — spec-loss is P1:** at the plan stage, an omission that could cause the **wrong feature to be built** is a **P1**, not a P2. This is because implementation subagents build FROM the plan's task list + test stubs, so a gap propagates and Gate 2 (code review) can only see code that is internally consistent with the _incomplete_ plan — plan-level spec-loss is invisible downstream. Classify as P1: missing required behavior, missing edge-case handling, a missing acceptance criterion needed to disambiguate implementation, or a missing test stub for a known-important behavior. Pure wording, organization, or maintainability smell stays P2. This sharpens classification only — it does **not** relax the exit; the loop still exits only on no P0/P1/P2.

**Approach comparison** (Phase 3, after brainstorming): Claude fills comparison table with fixed axes (Complexity, Blast Radius, Reversibility, Time to Validate, User/Correctness Risk). Contrarian/Codex validates the "default wins" claim. Council fires on OBJECT + high-impact surface. Spike first if cheapest falsifying test < 30 min.
If Codex unavailable: user validates skip.

**Code review loop** (Phase 5): Codex + PR Review Toolkit review the implementation.
Exit when: no P0/P1/P2 from all available reviewers on the same pass.
Codex is mandatory (this repo is Claude × Codex dual-engine). If Codex is unavailable, `/goal` halts and a human takes over; the loop cannot self-complete without real Codex evidence. The only ship escape is `- [x] Code review loop — N/A: <reason>` for degraded interactive use, caught at PR review.
Developer Demo honesty: when the PR body is a Developer Demo, an unsupported or wrong **diagram edge** — one that doesn't trace to a real `file:line` in the Evidence table (Gate 2 / claimed-current-behavior) — is a P1 finding. Gate-1 plan Briefing edges labeled `planned`/`inferred` are exempt.

**Convergence breaker (v5.54).** The code-review loop gets a hard stopping rule so it can never grind unbounded after a clean result:

1. **Certification** = the first iteration where BOTH engines record clean evidence at the same head.
2. **Round counting** = the `Code review loop (N iterations)` counter line is authoritative (rounds with findings write no clean rows but DO bump the counter). Rounds past certification = `N − certification iteration`.
3. **Trip condition** = more than `POST_CERT_REVIEW_ROUND_LIMIT` (= 3, canonical in `hooks/lib/review-breaker.sh`) rounds past certification. The `check-workflow-gates` hook then blocks `git commit` / `git push` / `gh pr create` — the breaker check runs on EVERY gated ship action, before the docs-only commit carve-out, so neither an N/A escape nor a docs-only commit bypasses it.
4. **Release** = ONLY a human records, in `### Checklist`:
   `- [x] Post-certification tail adjudicated by human — <decision> — head=\`<sha>\` — ts=\`<ISO8601>\``
   The line is head-bound (a new commit invalidates it) and the agent NEVER writes it on its own initiative. In a `/goal` run the breaker halts for the human — never substitute `/council`.
5. **N/A is count-preserving after certification:** if the loop line carries an iteration count, an N/A escape must keep it — `- [x] Code review loop (<N> iterations) — N/A: <reason>`. A count-less `Code review loop — N/A:` line after certification reads as counter erasure and trips the breaker (fail-closed).

**Recovery / diagnosis:** to see why the breaker tripped, run the helper directly — `bash .claude/hooks/lib/review-breaker.sh .claude/local/state.md` — it prints `CERTIFIED / POST_CERT_ROUNDS / BREAKER / ADJUDICATED`. To release a legitimate block, surface the open findings to the human and let THEM write the adjudication line above. There is nothing else to configure or disable: an untripped breaker is inert, and an uncertified branch can never trip it.

Never check a loop box until all available reviewers pass clean on the same iteration.

**Per-iteration clean evidence (enforced by `check-workflow-gates` hook on ship actions):**

For each loop, the agent MUST append a per-iteration clean line to `### Checklist` in `.claude/local/state.md`:

- **Plan review:** `- [x] Plan review iteration <N> — codex clean — plan=\`<path>\` — plan_sha=\`<sha256>\` — ts=\`<ts>\``
- **Code review:** `- [x] Code review iteration <N> — codex clean — head=\`<sha>\``AND`- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\``

The `[x] Plan review loop (N iterations) — PASS` / `[x] Code review loop (N iterations) — PASS` checkbox is checked ONLY AFTER all available reviewers report clean AND the per-iter line(s) are written. The hook blocks `git commit`, `git push`, and `gh pr create` if the loop checkbox is PASS without matching per-iter evidence.

**The only escape is N/A.** Codex is mandatory — there is no "codex unavailable" escape. For degraded interactive use only, the loop may be marked N/A:

- `- [x] Plan review loop — N/A: <reason>`
- `- [x] Code review loop — N/A: <reason>`

An N/A line skips the per-iter evidence check on ship actions (mirrors the `E2E verified — N/A:` gate) and is caught by human reviewers at PR time. An N/A escape does NOT set the evidence gate clean in `build-evidence` — so a `/forge-goal`-driven `/goal` cannot self-complete on N/A; it halts for a human if Codex is genuinely unavailable.
