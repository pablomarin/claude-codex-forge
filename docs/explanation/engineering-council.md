# The Engineering Council

> Fight sycophancy with model diversity. Five advisors argue, a chairman from a different model synthesizes, dissent is preserved.

A single agent — even a careful one — converges on the first plausible answer. Pair-of-eyes review helps but quickly settles on shared blind spots. The Council is the harness's answer to that drift: **structurally forced disagreement** between perspectives that have different incentives, run on models with different training data, before any code gets written.

When it fires, you get five short verdicts in parallel, a synthesized chairman ruling, and — if any advisor objected — a mandatory minority report explaining what was overruled and why. You decide whether to act on it. The Council never decides for you.

---

## The five advisors

Each advisor is a persona prompt, not a separate agent type. The personas are defined in `.claude/skills/council/references/advisors.md` and edited per project.

| Advisor              | Engine | Optimizes for                                                | Will say things like                                                   |
| -------------------- | ------ | ------------------------------------------------------------ | ---------------------------------------------------------------------- |
| **Simplifier**       | Claude | Minimal complexity, fewest moving parts                      | "Does this need to exist? What if we don't build it?"                  |
| **Scalability Hawk** | Claude | Performance, observability, graceful degradation             | "What breaks first at 10× load? What's the blast radius?"              |
| **Pragmatist**       | Claude | Clear first steps, unblocked progress, realistic scope       | "What's the first concrete action? What's the 'done' line?"            |
| **Contrarian**       | Codex  | Finding what everyone else missed                            | "What assumption, if wrong, makes the whole thing fail?"               |
| **Maintainer**       | Codex  | Readability, clear intent, low cognitive load 6 months later | "Will the test names explain the failure? Are names self-documenting?" |

The full persona texts (thinking style, biases, prompted questions) live in `advisors.md` — that file is the source of truth and the dispatcher injects it into each advisor at runtime.

---

## Why three Claude advisors and two Codex advisors

Diversity isn't aesthetic — it's the whole mechanism. Claude and Codex are independently trained on different data with different fine-tuning histories, so they fail in different directions. Claude tends to be optimistic, agreeable, and verbose; Codex tends to be cautious, terse, and quick to flag what's broken. A council of five Claudes would echo. A council of five Codexes would also echo — just in a different key.

The split matches each persona's role:

- **Simplifier, Scalability Hawk, Pragmatist** are constructive — they evaluate the plan on its own terms. Claude does this well.
- **Contrarian and Maintainer** are adversarial in different ways — the Contrarian looks for fatal flaws, the Maintainer asks whether a future reader can survive the code. Codex's terser, more skeptical default style is a better fit.

When Codex isn't available, Claude advisors still run — but you (the human) become the Contrarian/Maintainer/chairman. The workflow degrades gracefully; it just loses the model-diversity guarantee.

---

## The chairman is always Codex

After the five (or three) advisors return, a Codex chairman synthesizes the verdict. Why Codex specifically? Same reason as the persona split: the synthesis pass has to be done by a model that _didn't write any of the advisor responses_. If Claude wrote three of the five, Claude synthesizing them risks the same drift the Council is meant to prevent.

The chairman receives the raw advisor outputs verbatim and produces:

- A bottom-line verdict: **APPROVE**, **CONDITIONAL** (approve if X is changed), or **OBJECT**
- A short rationale grounded in the advisors' arguments (no new claims)
- A **Minority Report** if any advisor returned OBJECT — naming the dissenting advisor, the concern, and why the chairman overruled it

The minority-report rule is the single most important contract in the protocol. Without it, synthesis flattens into consensus and erases the diversity the Council exists to create. The chairman is told this in the prompt; if minority dissent exists and the chairman omits it, that's a protocol violation, not a stylistic choice.

---

## When the Council fires

There are two entry points.

### Standalone — you invoke it

```
/council <question or decision>
```

Always runs all five advisors. Use it when you're facing a real fork-in-the-road and want a structured second opinion before committing. Examples that fit:

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
3. **Quick Council (3 advisors)** — Simplifier + Contrarian + Pragmatist. If any of them OBJECT, low-confidence, or the surface is high-impact, escalate.
4. **Full Council (5 advisors)** — adds Scalability Hawk + Maintainer.

The 3-then-5 escalation keeps cost proportional to risk: low-stakes calls hit only the Contrarian gate (one Codex call), routine architectural calls fire three advisors, and only genuinely ambiguous high-impact decisions burn all five.

**High-impact surfaces** that automatically force escalation (canonical list — see `.claude/skills/council/references/peer-review-protocol.md`):

- Schema/database migrations
- Public API contracts
- Authentication/permissions
- Payment/billing logic
- Configuration defaults affecting all users
- Rollout/deployment strategy
- Architecture boundaries (service boundaries, shared libraries, database ownership)

---

## What you do with the output

The Council returns analysis, not orders. You read the chairman's verdict, scan the minority report (if any), and decide. The harness doesn't gate `git commit` on the Council's verdict — only on the human-driven quality gates (review loop, simplified, verified, E2E).

A few practical patterns from real use:

- **APPROVE without minority** → take the win, move on.
- **CONDITIONAL** → fix the named conditions, then move on. The chairman names specific things that need to change.
- **OBJECT** → don't just override. Read the dissent. Either rebut it in writing (in the plan or commit message) or rework the approach. The minority report is there because someone smart-ish-shaped saw something you didn't.
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
