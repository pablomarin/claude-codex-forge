# The Engineering Council

> Fight sycophancy with model diversity. Five advisors argue, a chairman from a different model synthesizes, dissent is preserved.

A single agent — even a careful one — converges on the first plausible answer. Pair-of-eyes review helps but quickly settles on shared blind spots. The Council is the harness's answer to that drift: **structurally forced disagreement** between perspectives that have different incentives, run on models with different training data, before any code gets written.

When it fires, you get five short verdicts in parallel, a synthesized chairman ruling, and — if dissent surfaced (an OBJECT verdict OR a plausible blocking concern raised under any verdict) — a mandatory minority report explaining what was overruled and why. You decide whether to act on it. The Council never decides for you.

---

## The five advisors

Each advisor is a persona prompt, not a separate agent type. The personas are defined in `.claude/skills/council/references/advisors.md` and edited per project.

| Advisor              | Engine | Optimizes for                                                                             | Will say things like                                                   |
| -------------------- | ------ | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Simplifier**       | Claude | Minimal complexity, fewest moving parts, smallest surface area                            | "Does this need to exist? What if we don't build it?"                  |
| **Scalability Hawk** | Claude | Performance, reliability, observability, graceful degradation                             | "What breaks first at 10× load? What's the blast radius?"              |
| **Pragmatist**       | Claude | Clear first steps, unblocked progress, minimal dependencies, realistic scope              | "What's the first concrete action? What's the 'done' line?"            |
| **Contrarian**       | Codex  | Finding what everyone else missed; breaking the plan before production does               | "What assumption, if wrong, makes the whole thing fail?"               |
| **Maintainer**       | Codex  | Readability, clear intent, minimal cognitive load, good error messages, obvious data flow | "Will the test names explain the failure? Are names self-documenting?" |

The full persona texts (thinking style, biases, prompted questions) live in `advisors.md` — that file is the source of truth and the dispatcher injects it into each advisor at runtime.

---

## Why three Claude advisors and two Codex advisors

Diversity isn't aesthetic — it's the whole mechanism. Claude and Codex are independently trained on different data with different fine-tuning histories, so they fail in different directions. Claude tends to be optimistic, agreeable, and verbose; Codex tends to be cautious, terse, and quick to flag what's broken. A council of five Claudes would echo. A council of five Codexes would also echo — just in a different key.

The split matches each persona's role:

- **Simplifier, Scalability Hawk, Pragmatist** are constructive — they evaluate the plan on its own terms. Claude does this well.
- **Contrarian and Maintainer** are adversarial in different ways — the Contrarian looks for fatal flaws, the Maintainer asks whether a future reader can survive the code. Codex's terser, more skeptical default style is a better fit.

When Codex isn't available, the Codex advisors (Contrarian, Maintainer) are **skipped** — only the Claude advisors run — and you become the chairman. The Contrarian _gate_ (the auto-trigger pre-check) is replaced by your manual validation of the "default wins" claim. The workflow degrades gracefully; it just loses the model-diversity guarantee. (See "Without Codex" below for the full degradation map.)

---

## The chairman synthesizes — Codex by default, you as fallback

After the five (or three) advisors return, a chairman synthesizes the result. Codex runs the chairman by default; if Codex isn't installed, the harness skips synthesis and shows you the raw advisor outputs so **you** become the chairman. Either way, the synthesis pass has to be done by a viewpoint that _didn't write any of the advisor responses_ — if Claude wrote three of the five and then synthesized, Claude would risk the same drift the Council is designed to prevent.

### Two output vocabularies — don't conflate them

**Advisors** each return a single-token verdict in their structured response:

- **APPROVE** — the plan as written looks sound
- **CONDITIONAL** — approve if the named conditions are addressed
- **OBJECT** — the plan has a flaw the advisor cannot live with

(See `.claude/skills/council/references/output-schema.md` for the full per-advisor schema.)

**The chairman** produces a structured document, not a single token:

```
## Council Verdict

### Recommendation
[The synthesized decision with rationale grounded in the advisors' arguments — no new claims]

### Consensus Points
[What all/most advisors agreed on]

### Blocking Objections
[Any unresolved objections — cannot be omitted even if the chairman disagrees]

### Minority Report
[See rule below — mandatory under specific conditions]

### Missing Evidence
[Gaps in context, untested assumptions, things that would need a spike to resolve]

### Next Step
[One concrete action the implementer should take next]
```

### The Minority Report rule

A **Minority Report** is **MANDATORY** whenever any advisor returned OBJECT _or_ raised a plausible blocking concern under any other verdict (CONDITIONAL or even APPROVE — the schema's three tokens are the only verdicts; the trigger is the substance of the concern, not the verdict label). The report names:

- **Who** dissented (advisor name)
- **What** they said (the specific concern)
- **Why** the chairman overruled or deferred it

"No minority objections" is only valid when every advisor returned APPROVE.

This is the single most important contract in the protocol. Without it, synthesis flattens into consensus and erases the diversity the Council exists to create. If minority dissent exists and the chairman omits it, that's a protocol violation, not a stylistic choice.

---

## When the Council fires

There are two entry points.

### Standalone — you invoke it

```
/council <question or decision>
```

Runs all five advisors when Codex is installed. On machines without Codex, only the three Claude advisors run and you become the chairman (see "Without Codex" below). Use the command when you're facing a real fork-in-the-road and want a structured second opinion before committing. Examples that fit:

- "Should we use Approach A or B for the migration?"
- "Is this auth design sound, or am I missing a class of attack?"
- "We're torn between two database schemas — what are we not seeing?"

What doesn't fit: questions with a clear answer, requests for advice on tactics ("how should I refactor this loop"), or anything where you'd accept any reasonable answer. The Council is structurally heavy — five parallel calls plus a synthesis pass. Use it when being wrong is expensive.

### Auto-trigger — `/new-feature` and `/fix-bug` Phase 3.1c

The workflows fire the Council automatically, but with a cheaper gate first. The flow:

1. **Approach Comparison** (Phase 3.1b) — Claude fills a fixed-axis comparison table for 2-3 candidate approaches and picks a default.
2. **Contrarian Gate** (Phase 3.1c) — a single Codex call validates the "default wins" claim. Returns one of:
   - **VALIDATE** → skip the Council, proceed with default. This is the common case.
   - **OBJECT** → check if there's a falsifying test under 30 minutes; if yes, run the spike instead. If no AND the decision touches a high-impact surface, fire the 3-advisor council.
   - **INSUFFICIENT** → fire the 3-advisor council. Ambiguity = risk.
3. **Quick Council (3 advisors)** — Simplifier + Contrarian + Pragmatist. Escalates to the full council if **any** of these triggers fire:
   - Any advisor returns OBJECT
   - Any advisor reports low confidence
   - Decision affects an irreversible/high-impact surface (list below)
   - No majority verdict (3-way split with no clear winner)
4. **Full Council (5 advisors)** — adds Scalability Hawk + Maintainer.

The 3-then-5 escalation keeps cost proportional to risk: low-stakes calls hit only the Contrarian gate (one Codex call), routine architectural calls fire three advisors, and only genuinely ambiguous high-impact decisions burn all five.

**High-impact surfaces** that automatically force escalation (canonical list — `.claude/skills/council/references/peer-review-protocol.md` is the single source of truth; if the two ever drift, that file wins):

- **Schema/database migrations** — DDL changes, new tables, column alterations
- **Public API contracts** — endpoint additions/removals, request/response shape changes
- **Authentication/permissions** — auth flows, RBAC, token handling, session management
- **Payment/billing** — charge logic, subscription management, refund flows
- **Configuration defaults affecting all users** — feature flags, rate limits, default settings
- **Rollout/deployment strategy** — blue-green, canary, migration ordering
- **Architecture boundaries** — service boundaries, shared libraries, database ownership, message contracts

---

## What you do with the output

The Council returns analysis, not orders. You read the chairman's verdict, scan the minority report (if any), and decide. The harness doesn't gate `git commit` on the Council's verdict — only on the human-driven quality gates (review loop, simplified, verified, E2E).

The chairman's `### Recommendation` will typically land on one of three outcomes (mirroring the advisor vocabulary). A few practical patterns from real use:

- **Recommendation lands on APPROVE, no minority** → take the win, move on.
- **Recommendation lands on CONDITIONAL** → fix the named conditions, then move on. The chairman lists specific things that need to change.
- **Recommendation lands on OBJECT** → don't just override. Read the dissent and the Blocking Objections section. Either rebut them in writing (in the plan or commit message) or rework the approach.
- **A council you disagree with** → that's still useful. The point is to surface the strongest argument against your plan, not to obey one. If you can articulate why the dissent is wrong, you're better positioned to ship; if you can't, that's information.

---

## Without Codex

If `codex` isn't installed, the Council degrades — it doesn't break:

| Component          | Replacement                                          |
| ------------------ | ---------------------------------------------------- |
| Codex advisors     | Skipped — only Claude advisors run                   |
| Contrarian gate    | You validate the "default wins" claim manually       |
| Chairman synthesis | You are the chairman — raw outputs shown, you decide |

You lose the model-diversity guarantee but the structure (parallel perspectives, mandatory dissent capture, explicit verdict) still works. The harness announces "Codex not installed. Running Claude advisors only — you'll be the chairman" so you know what you're getting.

---

## See also

- `/council <question>` — see [`docs/reference/commands.md`](../reference/commands.md) for invocation details
- Persona definitions — `.claude/skills/council/references/advisors.md` (edit per project)
- Dispatch and escalation rules — `.claude/skills/council/references/peer-review-protocol.md`
- Output schema — `.claude/skills/council/references/output-schema.md`
- Why two agents at all — [`docs/explanation/harness-philosophy.md`](harness-philosophy.md)
