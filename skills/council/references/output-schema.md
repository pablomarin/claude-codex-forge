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
