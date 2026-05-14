# PRD: /forge-goal — Autonomous PRD-to-PR-Ready Workflow

**Version:** 1.2
**Status:** Draft (revised after Codex second grounding audit)
**Author:** Claude (Opus 4.7, 1M ctx) + Pablo Marin
**Created:** 2026-05-14
**Last Updated:** 2026-05-14

---

## 1. Overview

The claude-codex-forge harness today requires the user to manually advance Claude through every workflow phase (Research → Plan → Plan-review → Implement → Code-review → E2E → PR). This is the babysitting tax. This PRD specifies a capability that, after an interactive PRD discussion completes, lets the user type ONE command and the agent autonomously drives the workflow end-to-end until the PR is ready for human authorization. The Engineering Council substitutes the user for autonomous judgment moments encountered during the run (except final PR creation, which always requires human approval). The intent is to eliminate babysitting after PRD approval while preserving every existing gate, evidence requirement, and discipline rule the forge already enforces.

## 1a. Scope Reality Check (per discussion)

Per Pablo's discussion answer 14: **most of the workflow machinery already exists** in `/new-feature` and `/fix-bug` — research, plan, plan-review-loop (Claude + Codex), TDD discipline, code-review-loop (Codex + PR-toolkit), E2E with `verify-e2e` agent. This PRD does NOT redesign that machinery. The work in v1 is, in essence:

1. Add an evidence primitive so a verifier can deterministically check gate satisfaction from transcript evidence.
2. Have `/goal` drive existing phases end-to-end (replacing manual phase-advance).
3. Substitute human-pause moments with council invocation at the agent's discretion.
4. Add an explicit human-authorization gate at PR creation.

## 2. Goals & Success Metrics

### Goals

- **Primary:** After PRD approval, the user types ONE command and walks away; the agent autonomously reaches PR-ready (PR open + reviewers clean + E2E report present) without further phase-by-phase intervention.
- **Secondary:** Council judgment replaces the user during the autonomous run for every "ask the user" moment except final PR creation authorization.
- **Tertiary:** The interactive PRD phase becomes a structured Claude + Codex (on-demand) + user collaboration, producing a higher-quality PRD than ad-hoc `/new-feature` kickoff.

### Success Metrics

| Metric | Target | How Measured |
|---|---|---|
| User intervention turns between PRD-approval and PR-ready | 0 (except the PR-create gate) | Count user messages in the autonomous segment of a `/new-feature` or `/fix-bug` run |
| Workflow gate skip rate | 0 | Hook-enforced; verifier confirms every checklist item with on-disk evidence |
| Council invocations per autonomous run | Pattern observed and logged during v1 dogfooding (threshold calibrated empirically) | Per-fire log entry |
| First-pass success on dogfooded forge feature | Calibrated empirically during v1 testing | Manual observation |
| Downstream smoke (msai-v2) | Pass | One manual run by Pablo confirms `/forge-goal` capability works in downstream install |

### Non-Goals (Explicitly Out of Scope)

- ❌ A new `/forge-goal` slash command — `/new-feature` and `/fix-bug` print the `/goal` command at the relevant checkpoint instead.
- ❌ Mechanical replacement of "Ask the user" calls in `workflow.md` — council fires at the agent's discretion, not via instrumented call sites.
- ❌ CI status gating on PR-ready — CI runs in parallel; the "PR open + reviewers clean + E2E report present" bar does not wait for CI.
- ❌ Durable counter persistence across `--resume`.
- ❌ Multiple `/goal` per session — one per session is the rule.
- ❌ Autonomous Codex during PRD phase — user invokes `/codex` on-demand only.
- ❌ `/quick-fix` integration — trivial changes do not need autonomous loops.
- ❌ Hard auto-abort on stuck detection — soft warning only.
- ❌ Opt-in flag for downstream installs — every Forge install gets the capability automatically after upgrade.

## 3. User Personas

### Forge User (Primary)

- **Role:** Software engineer using the claude-codex-forge harness to build features and fix bugs.
- **Permissions:** Project owner OR team contributor in a downstream install. Sole authority for PR creation authorization.
- **Goals:** Reach PR-ready state with high confidence in code quality, minimal manual phase-shepherding, and clear visibility when their judgment is genuinely required.

### Council (System Actor)

- **Role:** Existing multi-perspective AI judgment board (5 advisors + deciding chairman). Substitutes the user for autonomous decision moments during the run.
- **Permissions:** Can return verdicts on any non-PR-creation question the agent raises during the autonomous loop.
- **Goals:** Resolve ambiguity without human pause; produce a chairman-resolved verdict the agent applies.

### Codex (System Actor, PRD phase only)

- **Role:** Peer reviewer invoked on-demand during the PRD phase. Existing role in plan-review-loop and code-review-loop continues unchanged.
- **Permissions:** Responds to user-initiated `/codex` invocations during PRD discussion.
- **Goals:** Stress-test PRD drafts; surface gaps the user might miss.

## 4. User Stories

### US-001: Interactive PRD Phase

**As a** forge user
**I want** an interactive PRD discussion when I start `/new-feature` or `/fix-bug`
**So that** requirements are refined collaboratively before any code is written

**Scenario:**

```gherkin
Given I run /new-feature add-tagging
When the PRD phase begins
Then Claude asks me targeted questions about personas, scope, and error cases
And I can invoke /codex on-demand to stress-test my answers
And the result is a refined PRD with user stories, non-goals, and acceptance criteria
And the PRD file is saved at docs/prds/{feature}.md
```

**Acceptance Criteria:**

- [ ] `/new-feature` and `/fix-bug` trigger an interactive PRD discussion phase before plan creation
- [ ] User can invoke `/codex` on-demand during the PRD phase; Codex does NOT auto-fire
- [ ] PRD phase produces a refined PRD file in `docs/prds/{feature}.md` with overview, goals, personas, user stories with acceptance criteria, and non-goals
- [ ] PRD phase exit transitions cleanly to the autonomous-loop checkpoint (where the `/goal` command is printed)

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| User skips `/codex` invocation entirely | PRD still produced; quality is on user |

**Priority:** Must Have

---

### US-002: Forge Prints the `/goal` Command at PRD-Complete Checkpoint

**As a** forge user
**I want** the forge to print the exact `/goal` command for me to copy-paste right after the PRD is approved
**So that** I can type ONE command and the autonomous loop drives plan creation, plan-review, implementation, code-review, E2E, and PR-ready without me babysitting

**Scenario:**

```gherkin
Given the PRD phase has completed
When the workflow reaches the autonomous-loop checkpoint
Then the agent prints a complete /goal command with the required completion condition
And typing it kicks off an autonomous loop that drives plan → plan-review → implementation → code-review → E2E → PR-ready
```

**Acceptance Criteria:**

- [ ] At the PRD-complete checkpoint (BEFORE plan creation), `/new-feature` and `/fix-bug` print a `/goal <condition>` command for the user to copy-paste
- [ ] The autonomous loop the `/goal` kicks off encompasses plan creation, plan-review-loop, implementation, code-review-loop, E2E, and PR-creation gate
- [ ] The condition is sufficient to express PR-ready completion (PR open + reviewers clean + E2E report present) and to prevent stale-evidence rubber-stamping (exact phrasing is a design-phase decision)
- [ ] The user can type the printed command verbatim to start the autonomous loop
- [ ] The forge does NOT attempt to auto-invoke `/goal` (experiment EXP 1 confirmed this isn't possible)

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| User skips this step and types something else | No autonomous loop runs; the workflow stays in manual-phase mode |

**Priority:** Must Have

---

### US-003: Autonomous Loop Execution

**As a** forge user
**I want** the agent to autonomously drive Phase 4 (implement) → Phase 5 (review) → Phase 6 (PR-ready) without phase-by-phase prompting from me
**So that** I can step away after typing the `/goal` command and return to a PR-ready state

**Scenario:**

```gherkin
Given I have typed the printed /goal command
When the autonomous loop is running
Then the agent advances through implementation, code-review-loop iterations, and E2E verification
And each phase transition occurs without me prompting the agent
And on-disk evidence is produced at each gate (reviewer pass artifacts, E2E report, etc.)
And the loop continues until PR-ready or budget exhaustion or my interruption
```

**Acceptance Criteria:**

- [ ] After the `/goal` command is set, no user prompting is required to advance from Phase 4 to Phase 5 to Phase 6
- [ ] All existing phase gates (TDD discipline, code-review-loop pass-on-same-iteration, NO BUGS LEFT BEHIND, E2E report mtime, etc.) are enforced unchanged
- [ ] The agent produces on-disk evidence for each completed gate (what the verifier observes is the evidence, not agent assertions)
- [ ] State.md is updated as each checklist item is satisfied with verifiable evidence

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| Plan-review-loop iterations (Claude + Codex back-and-forth on the plan) | Unchanged from today's flow; council does NOT fire for routine reviewer iterations |
| Code-review-loop iterations find P1/P2 (Codex + PR-toolkit + Claude) | Existing fix-then-retry loop runs autonomously |
| Agent recognizes a moment where it would normally pause for the user | Council fires (see US-004) |

**Priority:** Must Have

---

### US-004: Council Substitutes Human Judgment During the Loop

**As a** forge user
**I want** the Engineering Council to fire automatically when the agent encounters a question that would normally require my input
**So that** the loop doesn't pause for me except at the final PR creation gate

**Scenario:**

```gherkin
Given the autonomous loop is running
When the agent encounters a moment that would, under the existing workflow, pause for user input
Then the agent invokes the council
And the council's chairman returns a verdict
And the agent auto-implements the verdict
And the loop continues without my involvement
```

**Acceptance Criteria:**

- [ ] The agent invokes council at its own discretion when it judges human input would otherwise be required
- [ ] Council verdicts are auto-implemented by the agent — no human confirmation step
- [ ] Council deadlock does not block the loop (the existing chairman role resolves)
- [ ] Council does NOT fire for routine plan-review-loop or code-review-loop iterations
- [ ] Council does NOT have authority over PR creation
- [ ] Each council fire is logged (timestamp, question, verdict, action taken)

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| Agent over-fires or under-fires council | Pattern calibrated during v1 dogfooding; corrective rules added in v1.x |

**Priority:** Must Have

---

### US-005: PR-Creation Gate with Summary

**As a** forge user
**I want** the loop to pause and show me a summary before creating the PR
**So that** I can authorize the PR creation with full context on what was built

**Scenario:**

```gherkin
Given the autonomous loop has reached the PR-creation gate
When the agent is ready to run `gh pr create`
Then I see an AskUserQuestion modal asking "Authorize PR creation?"
And the modal includes a summary: files changed, tests added, reviewer status per tool
And on YES, the agent runs `gh pr create` and the goal advances
And on NO, the loop pauses for my direction
```

**Acceptance Criteria:**

- [ ] The agent calls `AskUserQuestion` before `gh pr create`
- [ ] The modal includes a summary of the work: changed files, tests added, reviewer pass/fail per tool (Codex, PR-toolkit, council if invoked)
- [ ] On YES, the agent produces an auditable on-disk authorization signal so the verifier observes the authorization in a verifiable form (exact mechanism is a design-phase decision)
- [ ] On NO, the loop pauses for user direction (it does not auto-retry)
- [ ] The AskUserQuestion answer alone does NOT clear the goal (experiment EXP 4 confirmed this is unreliable); the authorization signal is the gate

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| User answers NO | Loop pauses gracefully; state.md preserved for manual takeover |
| Summary is empty or incomplete | The agent regenerates the summary before asking; never empty |

**Priority:** Must Have

---

### US-006: "PR-Ready" Definition

**As a** forge user
**I want** "PR-ready" to mean PR is open AND all reviewers passed clean on the same iteration AND an E2E report is present
**So that** the autonomous loop's completion gate matches what I consider shipped-quality work

**Scenario:**

```gherkin
Given the autonomous loop is checking for completion
When all three conditions hold:
  - PR is open
  - Codex + PR-toolkit reviewer runs both report "clean" against the latest committed state
  - E2E report file exists from the current branch's work
Then the goal clears and the loop ends
And CI green is NOT required for the goal to clear (CI runs in parallel)
```

**Acceptance Criteria:**

- [ ] The completion condition is satisfied only when all three artifacts are confirmed present and current
- [ ] Reviewer-pass artifacts must reflect the latest committed state (no stale passes from before the last fix count)
- [ ] E2E report must be from the current branch's work (no stale report from another branch counts)
- [ ] CI status is informational only — not part of the gate
- [ ] PR-open is a precondition; if the PR is closed before all artifacts are confirmed, the goal does NOT clear

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| One reviewer pass is older than the latest commit | Treated as NOT clean; agent must re-run reviewers |
| E2E report is older than the branch's latest commit | Treated as missing; agent must re-run `verify-e2e` |
| PR is closed (merged or abandoned) before goal-completion | Goal does NOT clear; loop reports failure |

**Priority:** Must Have

---

### US-007: Budget Exhaustion Behavior

**As a** forge user
**I want** clear messaging and a state-checkpoint when `/goal` runs out of turn/token budget before PR-ready
**So that** I can take over the work manually without losing progress

**Scenario:**

```gherkin
Given the autonomous loop has consumed its budget
When /goal's exhaustion fires
Then state.md is checkpointed with the current Phase, checklist state, and last action
And I see a clear message: "stopped at Phase X, checklist Y at item Z; please take over manually"
And NO silent retry or auto-restart occurs
```

**Acceptance Criteria:**

- [ ] On budget exhaustion, state.md captures the current Phase and checklist progress
- [ ] The user-facing message names exactly where the loop stopped and what's done vs. pending
- [ ] No automatic restart of `/goal` with the same condition
- [ ] User can resume manually by continuing from the checkpointed phase

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| Budget exhausts mid-phase (e.g., middle of code-review-loop) | State.md captures partial state; user picks up at the exact point |

**Priority:** Must Have

---

### US-008: Stuck-Detection Soft Warning

**As a** forge user
**I want** the agent to emit a soft warning when it appears stuck (no measurable progress for N turns)
**So that** I can intervene if needed without the loop hard-aborting on me

**Scenario:**

```gherkin
Given the autonomous loop has run N turns without state.md checklist progress
When the stuck threshold is exceeded
Then a soft warning appears in the transcript: "no measurable progress for N turns, consider intervening"
And the loop continues working
And no auto-abort occurs
```

**Acceptance Criteria:**

- [ ] Stuck detection emits a warning at a calibrated turn threshold (N to be set in design phase)
- [ ] The warning is informational — does NOT abort the loop
- [ ] If the loop continues to make no progress, budget exhaustion eventually triggers (US-007)

**Priority:** Should Have

---

### US-009: Observability During the Run

**As a** forge user
**I want** to watch the autonomous run without disrupting it
**So that** I can monitor progress and intervene only when I genuinely want to

**Scenario:**

```gherkin
Given the autonomous loop is running
When I scroll the conversation or read state.md from a different terminal
Then the loop is not affected
And when I type a user message in the same session
Then the loop terminates autonomy (matches native /goal behavior — any user input ends autonomy)
```

**Acceptance Criteria:**

- [ ] Scrolling the conversation does not affect the loop
- [ ] Reading state.md externally does not affect the loop
- [ ] Typing any user message in the session ends autonomy (this is native `/goal` behavior; the forge inherits it)
- [ ] State.md is updated as each gate is satisfied so external observers can monitor progress

**Edge Cases:**

| Condition | Expected Behavior |
|---|---|
| User responds to the AskUserQuestion modal at PR-create | The answer flows through AskUserQuestion as intended (this is the designed interaction) |

**Priority:** Must Have

---

### US-010: Resume After Interruption

**As a** forge user
**I want** to be able to `--resume` or `--continue` a session whose autonomous loop was interrupted
**So that** I don't lose work to a laptop close or network drop

**Scenario:**

```gherkin
Given an autonomous loop was running and the session was interrupted
When I run `claude --resume` or `claude --continue`
Then the /goal condition is restored
And the loop continues from where it left off
And it is acceptable that the elapsed/turns/tokens counters reset
```

**Acceptance Criteria:**

- [ ] `--resume`/`--continue` restores the active `/goal` (per Anthropic's documented behavior)
- [ ] State.md persists across the interruption (it's on disk; not in session memory)
- [ ] Counter reset is acceptable and documented

**Priority:** Should Have

---

### US-011: Downstream Auto-Availability

**As a** forge user on a downstream install (msai-v2 etc.)
**I want** `/forge-goal`'s capability to be available automatically after I upgrade the Forge
**So that** I don't need to flip a flag or run setup with special arguments

**Scenario:**

```gherkin
Given I have a downstream Forge install on msai-v2
When I run `./setup.sh --upgrade` to pick up the new Forge version
Then the autonomous-loop capability is available immediately
And /new-feature and /fix-bug print the /goal command at the PRD checkpoint
And no opt-in flag is required
```

**Acceptance Criteria:**

- [ ] `./setup.sh --upgrade` brings the autonomous-loop capability to downstream installs
- [ ] No opt-in flag in CLAUDE.md or settings.json
- [ ] Layer 1 (evidence primitive) and Layer 2 (the rest) ship with PowerShell parity for v1
- [ ] Windows users get the same capability

**Priority:** Must Have

---

## 5. Constraints & Policies

### Delivery Layers (per discussion Q14)

V1 ships in two distinct layers:

- **Layer 1:** Evidence primitive (`build-evidence.sh` + PowerShell parity). Useful to the forge regardless of `/forge-goal`. Ships first as a standalone improvement to existing gate hooks.
- **Layer 2:** Everything else — together. Includes the printed `/goal` command from `/new-feature` and `/fix-bug`, council-on-doubt behavior (the agent invokes council whenever a workflow moment would otherwise pause for the user, with the recognition mechanism decided in design), and the AskUserQuestion + authorization-signal pattern at the PR-creation gate.

### Business / Compliance Constraints

- The forge's existing rules continue to apply unchanged: NO BUGS LEFT BEHIND, plan-review-loop, code-review-loop, evidence-based E2E gate, etc. The autonomous loop is an ENVELOPE around these rules, not a replacement.

### Platform / Operational Constraints

- **Requires Claude Code 2.1.139 or newer** (uses native `/goal`).
- **Cross-platform parity is required:** Bash (`.sh`) and PowerShell (`.ps1`) versions of every new script must ship together (existing forge rule).
- **No new MCP servers, SDKs, or external services required.** The capability uses existing Claude Code primitives; specific primitives chosen during design phase.
- **One `/goal` per session.**

### Dependencies & Required Integrations

- **Requires:** the existing forge workflow commands (`/new-feature`, `/fix-bug`) and their phase structure.
- **Requires:** the existing council command and its 5-advisor + chairman architecture.
- **Requires:** the existing Codex CLI integration (forge-meta and downstream).
- **Requires:** the existing PR-toolkit reviewer.
- **Requires:** the existing `verify-e2e` agent and `tests/e2e/reports/` evidence convention.
- **Named capabilities (scope, not mechanism):**
  - Must use Anthropic's `/goal` command as the autonomous-loop driver (HYBRID architecture per the experiment record at `docs/plans/2026-05-13-forge-goal-experiments.md`).
  - Must integrate with `gh` CLI for PR creation.

## 6. Security Outcomes Required

- **Who can access what:** Only the forge user can authorize PR creation. Council can decide on any non-PR-creation question.
- **What must never happen:** Council MUST NOT be able to authorize PR creation. The AskUserQuestion + authorization-signal pattern at the PR gate is a hard boundary that the autonomous loop cannot bypass.
- **What must be auditable:** Every council invocation during an autonomous run must be logged with timestamp, question, verdict, and resulting action. Every gate satisfaction must be backed by on-disk evidence (file existence, freshness, commit currency) — no agent-only assertions count.
- **What must not be rubber-stamped:** Stale evidence (evidence from before the current goal was set, or from before the most recent human-input gate) must NOT count toward gate satisfaction. The mechanism for staleness checks is a design-phase decision; the outcome required is that the autonomous loop cannot complete on stale evidence.
- **User-supplied content:** No user-supplied content (PRD body, plan body) is executed as code or shell commands. The autonomous loop only runs commands that are part of the existing approved workflow phases.

## 7. Open Questions

These remain for the design/implementation phase:

- [ ] **Stuck-detection N default value** — initial proposal: 5 turns without state.md checklist progress. To be validated empirically during v1 dogfooding.
- [ ] **Stale-evidence mechanism** — exact form of the "evidence freshness" check. Design-phase decision; the outcome required is set in §6.
- [ ] **Council failure handling** — if the council itself errors (network, advisor timeout, chairman missing), behavior is undefined. To be decided in design.
- [ ] **`gh pr create` failure handling** — retry policy, max attempts, fallback to user pause; needs precise definition in design.
- [ ] **Stuck-detection signal mechanism** — does the Stop hook track checklist progress over the last N turns, or does the agent self-report?
- [ ] **Summary content at PR-create gate** — generated by agent self-summary vs. by `build-evidence.sh` enrichment? Trade-off: agent self-summary is richer but uses tokens; script-generated is deterministic but limited.
- [ ] **Council "discretion" trigger** — does Claude self-prompt "should I council this?" at recognized decision points, or pure judgment with no structured prompt? Affects how reliable the council-invocation behavior is.

## 8. References

- **Discussion Log:** `docs/prds/forge-goal-discussion.md`
- **Experiment record (mechanic discovery + EXP 1/2/4/5 results):** `docs/plans/2026-05-13-forge-goal-experiments.md`
- **Anthropic /goal documentation:** [https://code.claude.com/docs/en/goal](https://code.claude.com/docs/en/goal)
- **Existing council architecture:** `.claude/skills/council/SKILL.md`
- **Existing workflow rules:** `.claude/rules/workflow.md`, `.claude/rules/critical-rules.md`, `.claude/rules/testing.md`

---

## Appendix A: Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-05-14 | Claude + Pablo | Initial PRD generated from `/prd:discuss` Rounds 1–4 |
| 1.1 | 2026-05-14 | Claude + Pablo (Codex grounding audit) | Fixed Codex's 5 categories: removed ungrounded metrics; aligned council/PR-ready/persona with discussion answers; added explicit Delivery Layers section; trimmed unconfirmed edge cases; moved implementation details to design-phase open questions |
| 1.2 | 2026-05-14 | Claude + Pablo (Codex second audit residuals) | US-002: `/goal` is printed at PRD-complete (not after plan-approval) and drives plan creation onward; Layer 2 no longer names `PLAN_REVISION_REQUIRED` reviewer schema specifically (council-on-doubt is the outcome; recognition mechanism is design); removed "session nonce, timestamp anchor" mechanism examples from Open Questions |

## Appendix B: Approval

- [ ] Product Owner approval (Pablo)
- [ ] Technical Lead approval (Pablo)
- [ ] Ready for technical design — proceed to `/superpowers:brainstorming` for solution exploration
