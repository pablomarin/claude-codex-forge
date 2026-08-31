# Engineering Council — Output Schema

> Structured formats for advisor and chairman outputs. The council skill enforces these.

---

## Advisor Output Format

Every advisor MUST use this structure (enforced by the council-advisor agent):

```
## [Advisor Name]

### Position
[One sentence: what this advisor recommends and why]

### Analysis
[2-5 bullet points grounded in actual code/constraints]

### Blocking Objections
[Issues that MUST be resolved. "None" if clean.]

### Risks Accepted
[Trade-offs this approach knowingly accepts]

### Verdict
APPROVE | OBJECT | CONDITIONAL
```

---

## Chairman Output Format

The Codex chairman MUST produce this structure:

```
## Council Verdict

### Recommendation
[The synthesized decision with rationale]

### Consensus Points
[What all/most advisors agreed on]

### Blocking Objections
[Any unresolved objections from any advisor — CANNOT be omitted even if chairman disagrees]

### Minority Report (MANDATORY)
[MANDATORY. At least one named dissenting view whenever any advisor OBJECTed
or raised a plausible blocking concern.
- WHO objected (advisor name)
- WHAT they said (the specific concern)
- WHY overruled or deferred (chairman's reasoning)
"No minority objections" ONLY if every advisor returned APPROVE.]

### Missing Evidence
[What the council couldn't assess — gaps in context, untested assumptions,
things that would need a spike or experiment to resolve]

### Next Step
[One concrete action the implementer should take next]
```

---

## Presentation Format

The user always sees BOTH raw outputs and synthesis:

```
## Council Result

[Chairman synthesis — shown first, prominently]

<details>
<summary>Individual Advisor Responses (N)</summary>

### Advisor A: The Simplifier (Claude)
[full raw response]

### Advisor B: The Contrarian (Codex)
[full raw response]

[... all advisors ...]
</details>
```

**Without Codex (user-as-chairman):**

Raw advisor outputs shown prominently (NOT collapsed), followed by:

> "You are the chairman. Based on these perspectives, what's your verdict?"

---

## Approach Comparison Format

Used during auto-trigger detection (not for standalone `/council`):

```
## Approach Comparison

### Chosen Default
[The approach Claude recommends]

### Best Credible Alternative
[The strongest competing approach — not a strawman]

### Scoring (fixed axes)
| Axis                  | Default | Alternative |
|-----------------------|---------|-------------|
| Complexity            |  L/M/H  |   L/M/H     |
| Blast Radius          |  L/M/H  |   L/M/H     |
| Reversibility         |  L/M/H  |   L/M/H     |
| Time to Validate      |  L/M/H  |   L/M/H     |
| User/Correctness Risk |  L/M/H  |   L/M/H     |

### Cheapest Falsifying Test
[How to resolve ambiguity with a spike, benchmark, or code-reading test.
Estimate: < 30 min or > 30 min.]
```
