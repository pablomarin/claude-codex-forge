---
name: council
description: >
  Engineering Council — multi-perspective decision analysis using model diversity
  (Claude subagents + Codex CLI). Spawns five advisors with different thinking styles,
  runs anonymous peer review, and synthesizes a verdict with mandatory minority reports.
  Invoke when the developer explicitly asks for a council or when a concrete high-impact
  architectural fork remains unresolved after the cheapest safe falsifying check. During active
  native Goal, it may also resolve a genuine non-destructive decision. That decision must concern
  product or engineering judgment and be required to continue the active native Goal. Do not
  infer invocation from ordinary ambiguity, plan/code-review findings, soft warnings, engine
  failures, or generic decision language.
argument-hint: <question or decision to analyze>
---

# Engineering Council

> Fight sycophancy with model diversity. 5 advisors argue, a chairman from a different model synthesizes, disagreement is preserved.

## Step 0: Confirm Eligibility

Run the council only when one condition is true:

- the developer explicitly requested a council; or
- a concrete high-impact architectural fork remains unresolved after the cheapest safe falsifying
  check; or
- an active native Goal needs a genuine non-destructive product or engineering decision to continue,
  and that check did not produce a deterministic smallest answer.

Do not invoke council for ordinary planning, reviewer findings, soft verification warnings,
implementation choices, engine failures, or generic uncertainty. Keep those inside the owning
bounded workflow. A signal may reveal a decision, but the signal alone is never the trigger.

## Step 1: Gather Context

Run these in parallel:

```bash
git diff --stat
git status --short
```

Read any files referenced in the question. Include any already-produced approach comparison or
falsifying-check evidence; do not manufacture extra prerequisites.

### Live-state fact-finding (when a verdict hinges on real system/data state)

If the question turns on actual system or data state — "is this migration safe given real row counts / distributions?", "does prod actually behave like X?" — gather **verified facts before advisors reason**, instead of having them speculate. Run the Forge opinion workflow's `investigate` profile (`/opinion investigate` in Claude Code; `$opinion investigate` in Codex) through `.forge/workflows/opinion.md`.

The investigation is a fresh full-capability selected-engine process in the real worktree. It uses
the normal host/project state, memory, tools, MCP, network, databases, and APIs. Claude uses native
safety-classified auto mode and Codex uses full host access with native on-request approval;
council does not invent a second credential hand-off. Explicit human
authorization for destructive or externally mutating actions still apply. Independently
cross-verify the finding before it enters the council as fact.

Advisors then reason over **verified facts**, and the chairman cites the evidence packet in the verdict.

## Step 2: Load Advisor Profiles and Dispatch Topology

Read `references/advisors.md` to get the five advisor personas. Engine assignment
is runtime data: invoke `.forge/hooks/lib/host-context.sh launch --host <host> --
.forge/hooks/lib/council-dispatch.sh ...` on Unix, or use `host-context.ps1
-Mode launch -Host <host> -LaunchTarget council -LaunchArgumentsJson ...` on
Windows, with the question, candidate, and workflow base. This is a fixed-target
compatibility launcher: `main_host` is routing metadata, not authenticated
session identity. Candidate and worktree evidence provide the review binding.
The dispatcher uses three main-engine advisors, two other-engine advisors, and an other-engine
chairman when healthy. It creates five fresh advisor sessions, resumes each for
one anonymous peer-review turn, and creates a fresh chairman session.
The executable topology is always the full eleven-turn council: five advisor starts, five
peer-review resumes, and one chairman. There is no quick or three-seat mode.

Every Task 5 dispatch must use `--fallback-policy none`, a distinct `--seat-id`,
the stable question hash, and `--conversation new|resume` exact-id transport.
Never dispatch a single advisor to a different engine after a failure: a
non-main runtime failure discards the complete mixed attempt and reruns all
eleven turns on main. A main-engine failure blocks the council.

## Step 3: Legacy Manual Dispatch Reference (DO NOT EXECUTE)

The canonical dispatch is Step 2's `council-dispatch` topology. The historical
manual/parallel commands below are reference material only and must not be run
in addition to the dispatcher.

**CRITICAL: All advisors must dispatch simultaneously.**

**Claude advisors:** Use the Task tool with `subagent_type: "council-advisor"`. Send ALL Claude advisor Task calls in a SINGLE message (parallel execution). Each prompt includes:

1. The persona text from `advisors.md`
2. The question/decision + context
3. Instruction to follow the output schema from `references/output-schema.md`

**Codex advisors:** Use `.forge/hooks/lib/codex-pty.sh exec` (the PTY shim — works around openai/codex#19945) via the Bash tool with `run_in_background: true`. On Windows, use `.forge/hooks/lib/codex-pty.ps1` instead. Each call includes:

1. The persona text
2. The question/decision + context
3. The output schema instructions

See `references/peer-review-protocol.md` for exact dispatch commands.

**Wait for ALL advisors to complete before proceeding.**

## Step 4: Chairman Synthesis

The canonical dispatcher creates the chairman on the other engine when the mixed topology is
healthy, or on the main engine when whole-topology fallback is required. Construct its prompt with:

- All raw advisor outputs (complete, unedited)
- The original question/decision
- Relevant codebase context (file list, git status)
- Instruction to produce the Chairman Output Format from `references/output-schema.md`
- Explicit instruction: "You MUST include a Minority Report section if any advisor OBJECTed"

The dispatcher owns output capture, identity verification, and failure reporting. Use its chairman
output verbatim in Step 5. A blocked main engine blocks the council; do not synthesize a replacement
in the orchestrating session.

## Step 5: Present Results

Display the chairman's output VERBATIM (do not rewrite, summarize, or editorialize). Then show raw advisor outputs in a collapsible section:

```markdown
## Council Result

[Chairman output — verbatim]

<details>
<summary>Individual Advisor Responses (N)</summary>

[All raw advisor outputs]

</details>
```
