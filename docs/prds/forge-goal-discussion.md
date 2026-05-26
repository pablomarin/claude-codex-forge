# PRD Discussion: forge-goal

**Status:** Complete (2026-05-14)
**Started:** 2026-05-13
**Participants:** User (Pablo), Claude (Opus 4.7), Codex (advisory)

## Original User Stories

Pablo's articulated vision (2026-05-13):

> Ideally, what I want is what the user should have. It's the process of creating the PRD.
> 1. The process of ideation of user stories
> 2. Research
> 3. Creating the PRD file and Claude and Codex should interact with the user in the creation of the best PRD possible
>
> After that, it's creating the coding plan and the implementation, and all that, including the creation of a plan iteration with Codex to review the plan, and then implementing the plan, and then the code review and all that should be done automatically. When there is a question of what to do, it should be resolved by the council. Really, after PRD creation, everything else should be under the goal command, so it never stops until the PR is ready to be created.

## Architecture context (already decided)

See `docs/plans/2026-05-13-forge-goal-experiments.md` for the full design exploration. Summary:

- **HYBRID architecture chosen:** native Anthropic `/goal` as the loop driver + forge-shipped `build-evidence.sh` for deterministic transcript evidence.
- **EXP 1 FAIL:** `/goal` cannot be auto-invoked from a slash command — forge instructs user to type it manually after PRD.
- **EXP 4 WEAK PASS:** AskUserQuestion answers don't reliably auto-clear `/goal` — pattern is AskUserQuestion-as-trigger, file/Bash output as gate.
- **EXP 5 PASS:** subagent dispatch works cleanly inside `/goal` — council/verify-e2e fan-out is viable.
- **Codex's REFINE:** add session_nonce + produced_at to every evidence JSON to prevent stale-evidence rubber-stamping.

## Derived user stories (Claude's interpretation, to be confirmed)

- **US-001:** As a forge user, when I run `/new-feature foo`, I want an interactive PRD discussion (Claude + Codex + me) that produces a refined PRD before any code is written.
- **US-002:** As a forge user, once the PRD is approved, I want to type ONE command and have the agent autonomously run plan → plan-review → implement → code-review-loop → E2E → PR-ready without babysitting each phase.
- **US-003:** As a forge user, I want the autonomous loop to stop ONLY at decisions where my judgment is required (PR creation, council questions on ambiguous direction).
- **US-004:** As a forge user, when the loop is stuck or fails, I want clear messaging — not silent hang.
- **US-005:** As a forge user, when judgment is needed mid-loop, the council should fire automatically without me manually invoking it.
- **US-006:** As a forge user, I want the autonomous loop to be reliable — no rubber-stamping of incomplete work, no skipping of gates.

## Discussion Log

### Round 1 (2026-05-13) — Scope, completion, error paths

**Q1: Which workflows does `/forge-goal` apply to?**
**A:** Both `/new-feature` AND `/fix-bug`. (Autonomous bug-fix loop is in scope.)

**Q2: Downstream support in v1?**
**A:** Yes — must work on `msai-v2` and similar downstream installs from v1. (Implies PowerShell parity and downstream smoke-test required from day 1.)

**Q3: If forced to pick 2 of 4 (PRD-with-Codex / autonomous-loop / council-auto-fire / AskUserQuestion-gated-PR), which 2?**
**A:** All four. None are MVP-cuttable. (V1 scope is BIG — no minimum viable cut.)

**Q4: What counts as "PR-ready"?**
**A:** (c) — PR open + all reviewers passed clean on same iteration + E2E report present in `tests/e2e/reports/`. **CI green is NOT required** (runs in parallel; checked manually after).

**Q5: PR-create pause UX — what user sees before clicking YES?**
**A:** Modal + summary (files changed, tests added, reviewer status).

**Q6: If a reviewer raises P0/P1 requiring plan revision (not just patch), what happens?**
**A:** (b) — auto-spawn `/council`, get verdict, continue with revised plan. (No human pause; council decides autonomously.)

**Q7: Budget exhaustion behavior?**
**A:** (a) + (c) combined — checkpoint state.md (preserve progress for takeover) AND fail clearly with snapshot in the message. Don't silently continue, don't lose state.

### Round 2 (2026-05-13) — Refinement follow-ups

**Q8: Build sequence (all-at-once vs layered)?**
**A:** Layered. Ship in iterative layers, each useful alone.

**Q9: Council auto-fire trigger?**
**A:** (b) — explicit `PLAN_REVISION_REQUIRED=true` in reviewer output triggers council. **Crucially expanded scope:** council also fires on ANYTHING Claude has doubts about or needs human input on — EXCEPT PR creation. (Council replaces human judgment everywhere except final PR authorization.)

**Q10: Codex's role in the PRD phase?**
**A:** **On-demand.** The PRD phase is human-driven; user (Pablo) invokes `/codex` explicitly when intervention is wanted. No autonomous Codex firing during PRD.

**Q11: Downstream opt-in mechanism?**
**A:** Auto-available. Every Forge install gets `/forge-goal` after upgrade — no flag needed.

**Q12: Stuck-detection heuristic?**
**A:** (b) Soft signal. Stop hook injects "you've been stuck N turns, consider asking for help" but does not auto-abort. Trust the system to recover via the warning or hit budget exhaustion.

**Q13: Observability during the autonomous run?**
**A:** Watch + manual injection (matches native `/goal` behavior — any user message terminates the loop's autonomy). User can scroll, but typing input ends autonomous mode.

### Round 3 (2026-05-13/14) — Council & layering

**Q14: Layer order?**
**A:** Just **TWO layers**, not six.
- **Layer 1:** `build-evidence.sh` (useful to the forge regardless of `/goal`).
- **Layer 2:** Everything else — together.

**KEY CONTEXT FROM PABLO:** *"Most of this is already done in the current workflows for `/new-feature` and `/fix-bug` commands. I just need `/goal` to run it until the end, and when in doubt use the council to solve it."*

This dramatically tightens the scope. The plan-review-loop, TDD discipline, code-review-loop, E2E, etc., already exist. The work is:
- Add evidence-bundle producer (Layer 1)
- Make `/goal` drive the existing workflows end-to-end without user pauses (Layer 2)
- Substitute existing "pause for user" gates with council invocation (Layer 2)

**Q15: Precise council auto-fire trigger?**
**A:** Council fires ONLY when "during the workflow there is a question that needs a human." Plan-iteration and code-review-iteration are already Claude+Codex (existing flow) — those stay as-is. Council is a substitute for the existing user-pause moments, not a new layer over reviewer outputs.

Implication: ignore my proposed triggers (i)–(v). The trigger is conceptually "would the workflow have paused for the user here? → fire council instead."

**Q16: Council deadlock?**
**A:** Shouldn't happen — the council has a deciding chairman. Skip the deadlock branch.

**Q17: Council verdict — auto-implement or verifier-checked?**
**A:** Auto-implement. Trust the chairman's verdict; the loop applies it and continues.

**Q18: Resume after interruption (counters reset)?**
**A:** Acceptable.

### Round 4 (2026-05-14) — Final clarifications before PRD

**Q19: Where does council substitute human pauses?**
**A:** (b) Agent's discretion. No mechanical replacement of "Ask the user" lines in workflow.md. Claude judges when it's in doubt and invokes council. Trust the agent's judgment.

**Q20: New `/forge-goal` slash command, or printed snippet?**
**A:** (b) No new command. Modify `/new-feature` and `/fix-bug` so they print the `/goal <condition>` command at the PRD-complete / plan-approved checkpoint. User types it manually.

**Q21: Test strategy?**
**A:** (a) + (d) — dogfood on the forge itself first (catch issues cheaply), then manual smoke on `msai-v2` before declaring v1 done.

---

## Refined Understanding

**Status:** Complete (2026-05-14). Ready to proceed to `/prd:create forge-goal`.

### Personas

- **Forge user** — develops features/fixes using the forge harness. Wants autonomous workflow execution after PRD with minimal babysitting. Can be the project owner (Pablo) or a team contributor in downstream repos.
- **Council** — existing multi-perspective AI judgment board (5 advisors + deciding chairman). Substitutes the user for autonomous decision-making during the loop. Gets new invocation triggers but no structural changes.
- **Codex** — peer reviewer (existing). On-demand during PRD phase (user-invoked). Continues to participate in plan-review-loop and code-review-loop as today.

### User Stories (Refined)

- **US-001:** When I run `/new-feature` or `/fix-bug`, I want an interactive PRD discussion (Claude + Codex on-demand + me) that produces a refined PRD before any code is written.
- **US-002:** After PRD approval, I want the forge to **print a `/goal` command** for me to type, that drives the full workflow (plan → plan-review → TDD → code-review-loop → E2E → PR-ready) autonomously.
- **US-003:** During the autonomous loop, the agent invokes council **at its own discretion** whenever a question would normally require human input — EXCEPT PR creation, which always pauses for me.
- **US-004:** Council fires via auto-discretion; verdicts are auto-implemented; deadlock is impossible (chairman resolves).
- **US-005:** At the PR-creation gate, I see a modal asking for authorization plus a **summary** of what was done (files changed, tests added, reviewer status).
- **US-006:** "PR-ready" means PR open + all reviewers passed clean on the same iteration + E2E report present in `tests/e2e/reports/`. **CI green is not required** (parallel concern).
- **US-007:** When the loop runs out of `/goal` budget without reaching PR-ready, I see a clear "stopped at Phase X, checklist Y; please take over manually" message with state.md checkpointed.
- **US-008:** When the loop appears stuck (no progress for N turns), the agent gets a soft signal warning; auto-abort is NOT enforced.
- **US-009:** I can watch the autonomous run without disrupting it (scroll). Typing input terminates autonomy (matches native `/goal`).
- **US-010:** If the session is interrupted, I can `--resume`; the goal restores with counters reset. Acceptable.
- **US-011:** `/forge-goal` capability works on downstream installs (msai-v2 etc.) **automatically after Forge upgrade** — no opt-in flag.

### Non-Goals

- **No new `/forge-goal` slash command** — existing `/new-feature` and `/fix-bug` commands print the `/goal` command directly.
- **No mechanical replacement of "Ask the user" calls in workflow.md** — council fires at Claude's discretion, not via workflow instrumentation.
- **No CI gating of PR-ready** — CI runs in parallel; not blocking.
- **No durable counter persistence across resume** — counter reset on `--resume` is acceptable.
- **No human pause except PR creation** — every other doubt fires council.
- **No `/quick-fix` integration** — trivial changes don't need `/goal`.
- **No multiple `/goal` per session** — lifecycle state bug; one per session.
- **No autonomous Codex during PRD phase** — user invokes `/codex` on-demand.

### Key Decisions

1. **HYBRID architecture** — native Anthropic `/goal` as loop driver; forge ships `build-evidence.sh` for transcript evidence.
2. **Two-layer build:**
   - **Layer 1:** `build-evidence.sh` (independently useful, useful regardless of `/goal`).
   - **Layer 2:** Everything else (printed `/goal` from existing workflow commands + reviewer schema with `PLAN_REVISION_REQUIRED` + council auto-discretion + AskUserQuestion + file-evidence pattern for PR-create).
3. **AskUserQuestion + file-evidence pattern** for the PR-creation gate (EXP 4 proved answer alone doesn't auto-clear `/goal`; agent runs `touch <file>` after answer).
4. **`session_nonce` + `produced_at`** in every build-evidence JSON blob to prevent stale-evidence rubber-stamping (Codex REFINE).
5. **Council at agent discretion** — no mechanical instrumentation; Claude judges when to fire.
6. **Test plan:** dogfood on forge first, then manual msai-v2 smoke before v1 ships.

### Open Questions (Remaining — for PRD or follow-up)

- Stuck-detection N — default value for the "stuck N turns" soft warning (suggest: 5 turns without state.md checklist progress)
- Exact wording of the printed `/goal` command (forge prints it; precise template to be drafted in PRD)
- `session_nonce` generation source — forge-injected env var? UUID written to state.md?
- "Agent's discretion" for council — does Claude need a structured self-prompt at known decision points ("am I in doubt here? if yes, council"), or pure judgment?
- Failure handling if council ITSELF fails (network error, advisor timeout) — pause for user? Retry?
- Stuck-detection signal: does the Stop hook track checklist progress, or is it agent self-reporting?
- "Files changed / tests added / reviewer status" summary at PR-create gate — generated by what mechanism (agent self-summary vs. build-evidence script)?
