# Autonomous Goal Mode (`/forge-goal`)

> **TL;DR** — After your PRD is written and approved, the Forge offers you a choice: drive the rest of the feature **manually**, phase by phase, or paste **one `/goal` command** and let the agent run the whole lifecycle — plan → review → implement → review → verify → E2E → PR — **autonomously**, escalating hard calls to the Engineering Council instead of stopping to ask you. Either way, you stay in the chair: watch the run and steer it any time by typing in the prompt.

## What it is

`/forge-goal` is the Forge's autonomous execution loop. It turns an approved PRD into an open pull request without you hand-driving each of the 14 workflow phases. It is **not** a separate command you install — it's the Claude Code built-in `/goal`, invoked with a Forge-composed instruction that `/new-feature` (or `/fix-bug`) hands you at the right checkpoint. The behavior of the agent _during_ an autonomous run is governed by `rules/workflow.md` ("Council During `/forge-goal` Autonomous Run").

## It is optional — and it starts only after the PRD

This is the single most important thing to understand. The autonomous loop is **opt-in and PRD-gated**:

1. You run `/new-feature <name>` and work through **Phase 1: the PRD** — interactively, with `/prd:discuss` and `/prd:create`. This is the part the Forge will _not_ automate, by design.
2. **The PRD is your spec, and making it bulletproof is your job.** The autonomous run is only as good as the PRD that drives it — a vague PRD produces a vague feature, autonomously. Be specific: concrete acceptance criteria, edge cases, out-of-scope notes, the works. The sharper the PRD, the more reliably the loop lands what you actually want.
3. **Once the PRD exists and you approve it**, the Forge gives you the option. It prints a ready-to-paste `/goal` command. You decide:
   - **Paste it** → the agent runs autonomously to PR-ready.
   - **Decline ("no")** → you continue the workflow manually, phase by phase, exactly as before.

There is no autonomous behavior before this point, and no surprise escalation of access. The Forge offers; you choose.

## What runs without you — and what still stops for you

During an autonomous run the agent's pause-for-user discipline inverts. Instead of stopping to ask you about every fork, it makes progress and routes judgment calls to the **Engineering Council** (the multi-advisor panel with a Codex chairman — see [The Engineering Council](engineering-council.md)). Concretely:

- **Big decisions → Council, not you.** An ambiguous product/technical choice, a reviewer recommending a plan revision, a high-impact fork — the agent invokes `/council`, applies the chairman's verdict, and continues. No prompt.
- **The plan-review and code-review loops run to convergence** on their own (Claude + Codex; Codex + PR-toolkit), with the per-iteration clean-evidence gates from v5.39 enforcing that "PASS" actually means clean.
- **The ONE hard human gate is PR creation.** Before `gh pr create`, the agent stops and asks you to authorize — that single `AskUserQuestion` is the only human-authority signal in the loop. It will not open a PR without your yes.
- **If something genuinely can't proceed** (the council itself fails, a tool repeatedly errors, an investigation needs write access), the loop **halts and writes a blocker** to `.claude/local/state.md` — it does not guess or force its way through. You take over.

## You should watch — and you can always steer

Autonomous is not unattended. **The recommended way to run `/goal` is to watch it work and steer when you see it drift** — and you steer the simplest possible way: **just type in the prompt.** A sentence of course-correction ("no, use the existing PortfolioRun path", "that edge case matters, don't skip it") redirects the run immediately. You are a pilot with autopilot engaged, not a passenger.

This holds in **both** scenarios:

- **Autonomous (`/goal`)** — watch the council verdicts and the review loops scroll by; jump in to steer or to answer the PR-creation gate.
- **Manual** — you're driving each phase, so you're inherently watching; the same steer-by-prompt applies.

The Forge's whole value is _discipline by construction_ — the autonomous loop extends that, it doesn't replace your judgment. Treat `/goal` as a powerful accelerator that you supervise, and the PRD as the contract you're holding it to.

## When to use which

| Situation                                                   | Recommendation                                       |
| ----------------------------------------------------------- | ---------------------------------------------------- |
| Substantial feature, sharp PRD, you want speed              | `/goal` — paste it, watch, steer, authorize the PR   |
| Exploratory work, fuzzy requirements, learning the codebase | Manual — drive it phase by phase                     |
| You're not yet confident the PRD is bulletproof             | Tighten the PRD first; the loop inherits its quality |

Either path lands at the same place — an open PR through all 14 enforced phases. `/goal` just removes the hand-driving between PRD and PR while keeping you in the loop where it counts.
