# The Engineering Council

> Five advisors argue, an independent chairman synthesizes, and dissent is preserved.

A single agent — even a careful one — converges on the first plausible answer. Pair-of-eyes review helps but quickly settles on shared blind spots. The Council is the harness's answer to that drift: **structurally forced disagreement** between perspectives that have different incentives, run on models with different training data, before any code gets written.

When it fires, you get five advisor verdicts, five anonymous peer-review turns, a synthesized
chairman ruling, and — if dissent surfaced (an OBJECT verdict OR a plausible blocking concern raised
under any verdict) — a mandatory minority report explaining what was overruled and why. You decide
whether to act on it. The Council never decides for you.

---

## The five advisors

Each advisor is a persona prompt, not a separate agent type. The personas are defined in
`.forge/skills/council/references/advisors.md` and edited per project.

| Advisor              | Engine | Optimizes for                                                                             | Will say things like                                                   |
| -------------------- | ------ | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Simplifier**       | Main  | Minimal complexity, fewest moving parts, smallest surface area                            | "Does this need to exist? What if we don't build it?"                  |
| **Scalability Hawk** | Main  | Performance, reliability, observability, graceful degradation                             | "What breaks first at 10× load? What's the blast radius?"              |
| **Pragmatist**       | Main  | Clear first steps, unblocked progress, minimal dependencies, realistic scope              | "What's the first concrete action? What's the 'done' line?"            |
| **Contrarian**       | Other | Finding what everyone else missed; breaking the plan before production does               | "What assumption, if wrong, makes the whole thing fail?"               |
| **Maintainer**       | Other | Readability, clear intent, minimal cognitive load, good error messages, obvious data flow | "Will the test names explain the failure? Are names self-documenting?" |

The full persona texts (thinking style, biases, prompted questions) live in `advisors.md` — that file is the source of truth and the dispatcher injects it into each advisor at runtime.

---

## Why three main-engine advisors and two other-engine advisors

Diversity isn't aesthetic — it's the whole mechanism. The host in which the developer is working is
main for that council. With both engines healthy, three advisor seats run on main, two advisor seats
run on the other engine, and the chairman also runs on the other engine. Forge supports Claude Code
and Codex today; Grok is a future possibility, not a configured engine or seat.
In short, three advisors use the current host, while two advisors and the chairman use the other.

If the other engine is known unavailable, Forge starts one fresh all-main council. If it fails during
a mixed attempt, Forge discards the partial topology and reruns all five advisors plus chairman fresh
on main. The whole council falls back together; a main-engine failure blocks and seats never fall
back individually.

---

## The chairman synthesizes independently

After the five advisors return and anonymously peer-review one another, a fresh chairman synthesizes
the result. The other engine chairs a healthy mixed council; a fresh main-engine session chairs the
all-main fallback.

The council runs in three waves: five initial advisor calls in parallel, five peer-review calls in
parallel after all initial answers succeed, then the chairman. Each peer resumes its original
session and sees the other four anonymized initial answers. Bundle order stays fixed regardless
of which member finishes first. Normal model-call latency is therefore approximately the slowest
advice call plus the slowest peer call plus the chairman call, rather than the sum of eleven calls.
The number of model turns and token cost are unchanged by parallel scheduling.

If a wave fails, the dispatcher waits for every worker to exit before discarding the mixed attempt
and starting an all-main rerun. A main-engine failure blocks the verdict even when an other-engine
seat also fails in that wave.

### Two output vocabularies — don't conflate them

**Advisors** each return a single-token verdict in their structured response:

- **APPROVE** — the plan as written looks sound
- **CONDITIONAL** — approve if the named conditions are addressed
- **OBJECT** — the plan has a flaw the advisor cannot live with

(See `.forge/skills/council/references/output-schema.md` for the full per-advisor schema.)

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

Council is exceptional rather than a routine review stage.

### Explicit invocation

```
/council <question or decision>
```

Runs all five advisors plus the chairman using the healthy mixed topology or one visible all-main
fallback. Use the command when you're facing a real fork-in-the-road and want a structured second
opinion before committing. Examples that fit:

- "Should we use Approach A or B for the migration?"
- "Is this auth design sound, or am I missing a class of attack?"
- "We're torn between two database schemas — what are we not seeing?"

What doesn't fit: questions with a clear answer, ordinary plan/code-review findings, soft validation
warnings, requests for advice on tactics ("how should I refactor this loop"), or anything where you'd
accept any reasonable answer. The Council is structurally heavy: five advisor starts, five peer
turns, and one chairman. Use it when being wrong is expensive.

### Exceptional workflow invocation

`/new-feature`, `/fix-bug`, and native Goal do not invoke council as a routine contrarian or review
step. They use the fresh plan reviewer and bounded broad-review → repair → focused-closure loop.
Council becomes eligible when the developer explicitly requests it, a concrete high-impact
architectural fork remains unresolved, or an active native Goal cannot continue without a genuine
non-destructive product or engineering decision after the cheapest safe falsifying check. Findings,
soft warnings, and engine failures are not council triggers by themselves.

**High-impact surfaces** (canonical list — `.forge/skills/council/references/peer-review-protocol.md` is the single source of truth; if the two ever drift, that file wins):

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

## When the other engine is unavailable

Forge announces the missing or failed other engine and starts one fresh all-main council, including a
fresh chairman. The receipt records the fallback topology and reason. A failure on main blocks the
verdict rather than producing a partial council.

---

## See also

- `/council <question>` — see [`docs/reference/commands.md`](../reference/commands.md) for invocation details
- Persona definitions — `.forge/skills/council/references/advisors.md` (edit per project)
- Eligibility, topology, and fallback rules — `.forge/skills/council/references/peer-review-protocol.md`
- Output schema — `.forge/skills/council/references/output-schema.md`
- Why two agents at all — [`docs/explanation/harness-philosophy.md`](harness-philosophy.md)
