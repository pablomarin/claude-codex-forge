# Autonomous Goal Mode (`/forge-goal`)

> **TL;DR** — After your PRD is approved, Forge can compose the current host's native `/goal`
> over the shared workflow state. It runs toward PR-ready autonomously while human-only authority
> boundaries still pause.

## What it is

`/forge-goal` is Forge's composition contract for the native `/goal` provided by Claude Code or
Codex. Forge does not install or shadow `/goal`; `/new-feature` or `/fix-bug` offers it at the right
checkpoint, and `.forge/workflows/goal.md` defines the shared behavior.
Both hosts resume the same native `/goal` composition contract from canonical Forge state, while
the host-native session itself remains fresh.

## It is optional — and it starts only after the PRD

This is the single most important thing to understand. The autonomous loop is **opt-in and PRD-gated**:

1. You run `/new-feature <name>` and work through **Phase 1: the PRD** — interactively, with `/prd:discuss` and `/prd:create`. This is the part the Forge will _not_ automate, by design.
2. **The PRD is your spec, and making it bulletproof is your job.** The autonomous run is only as good as the PRD that drives it — a vague PRD produces a vague feature, autonomously. Be specific: concrete acceptance criteria, edge cases, out-of-scope notes, the works. The sharper the PRD, the more reliably the loop lands what you actually want.
3. **Once the PRD exists and you approve it**, the Forge gives you the option. It prints a ready-to-paste `/goal` command. You decide:
   - **Paste it** → the agent runs autonomously to PR-ready.
   - **Decline ("no")** → you continue the workflow manually, phase by phase, exactly as before.

There is no autonomous behavior before this point, and no surprise escalation of access. The Forge offers; you choose.

## What runs without you — and what still stops for you

During an autonomous run the agent makes progress and routes non-destructive judgment calls to the
**Engineering Council** (whose chairman runs on the other engine when both are healthy — see
[The Engineering Council](engineering-council.md)). Concretely:

- **Big decisions → Council, not you.** An ambiguous product/technical choice, a reviewer recommending a plan revision, a high-impact fork — the agent invokes `/council`, applies the chairman's verdict, and continues. No prompt.
- **Review is bounded.** Each candidate gets one broad review, one repair, and one closure review;
  P3 or speculative concerns do not keep autonomy open. Reachable P0/P1 security, correctness, or
  data-integrity defects still block.
- **Human-authority gates remain human.** PR creation, merge, deploy, publish, destructive work,
  secrets, and every new external mutation pause for explicit authorization.
- **If something genuinely can't proceed**, the loop halts and writes the exact blocker and next
  step to `.forge/local/state.md`; it does not guess or force its way through.
- **Host switches preserve the Forge objective, nonce, durable budget, and next step, not the native
  session.** The other host starts a fresh native session from shared state.

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
