# PRD: Dual-Engine Forge Workflows

**Version:** 1.2
**Status:** Approved
**Author:** Codex + Pablo
**Created:** 2026-08-26
**Last Updated:** 2026-08-27

---

## 1. Overview

Forge will provide one coherent software-engineering harness that works from both Claude
Code and Codex. A project has no permanent main agent: whichever host starts or resumes a
workflow is the active main agent, while review and Engineering Council work use the
other engine when available and visibly fall back to fresh same-engine runs when needed.

Developers can authoritatively migrate an existing Forge project with a supported
full-refresh setup mode, use the complete workflow surface from either host, and switch
hosts between phases in the same worktree without manual harness copying or loss of
workflow continuity. Migration removes obsolete Forge-owned duplicates so the installed
project has one coherent harness rather than competing legacy and dual-engine policies.

## 2. Goals & Success Metrics

### Goals

- Make Claude Code and Codex first-class hosts for every Forge workflow in v1.
- Support all four main-agent/reviewer combinations with one equivalent gate contract.
- Allow cooperative cross-host resume through shared project and workflow artifacts.
- Preserve independent review and council behavior when only one engine is usable.
- Upgrade downstream projects to the dual-engine harness without destroying project-owned
  instructions, state, memories, secrets, or configuration.
- Support capability-expanded investigative reviewers and dual-engine autonomous goals.
- Make plan, code, and review-repair loops explicitly resource-disciplined so agents stop at
  diminishing returns instead of pursuing speculative edge cases or unattainable perfection.

### Success Metrics

| Metric | Target | How Measured |
| --- | --- | --- |
| Host workflow parity | 100% of installed Forge workflows launchable from both hosts | Cross-host contract suite over the installed command surface |
| Main/reviewer matrix | All four combinations complete plan and code review gates | Matrix acceptance tests with engine dispatch fixtures |
| Missing-engine continuity | 100% of unavailable/failed other-engine cases continue through visible fresh same-engine fallback | Failure-injection tests and evidence receipts |
| Cross-host resume | Claude-to-Codex and Codex-to-Claude resume at every persisted workflow phase | Worktree handoff acceptance scenarios |
| Upgrade completeness | One supported full-refresh setup run removes obsolete Forge-owned duplicates and installs one compatible dual-host harness | Clean and legacy-install fixture comparisons plus managed-file inventory |
| Protected-content safety | 0 unauthorized changes to protected project-owned files and state | Before/after fingerprints in upgrade tests |
| Stale-policy elimination | 0 known legacy Forge-managed policy copies remain after successful migration | Post-migration managed-artifact inventory and parity checks |
| Council topology | Intended 3-main/2-other advisor split plus other-engine chairman, with complete six-seat fallback | Council dispatch and failure-injection tests |
| Goal parity | Both native `/goal` surfaces can drive the same Forge lifecycle to the same evidence-defined stop | Claude and Codex autonomous-run acceptance tests |
| Review resource discipline | No loop continues for P3-only, cosmetic, speculative, or unchanged-candidate findings; one broad review plus bounded closure is the default | Workflow/prompt contract tests and revision-loop fixtures |

### Non-Goals (Explicitly Out of Scope)

- ❌ Locking a worktree to one engine or detecting simultaneous Claude/Codex edits.
- ❌ Requiring a formal handoff command before another host may resume work.
- ❌ Guaranteeing launch of an engine that is missing, unauthenticated, or failing.
- ❌ Maintaining separate independently authored workflow policies for each host.
- ❌ Deleting unrecognized project files or custom host extensions during migration.
- ❌ Requiring filesystem symlinks as part of the user-visible contract.
- ❌ Allowing investigative reviewers to mutate external systems without explicit,
  bounded user authorization.
- ❌ Weakening or omitting workflow gates because one host exposes different native UI
  or invocation mechanics.

## 3. User Personas

### Forge Developer

- **Role:** Installs or upgrades Forge in a software project and executes development
  workflows from Claude Code, Codex, or both.
- **Permissions:** May run workflows, edit the worktree, select reviewer behavior, invoke
  councils and investigations, and authorize externally mutating actions.
- **Goals:** Use either preferred agent at any phase without losing state, quality gates,
  or review independence.

### Investigating Developer

- **Role:** Uses Forge to diagnose defects or understand systems through code, queries,
  project tools, network resources, and live evidence.
- **Permissions:** May grant an investigative reviewer worktree writes and live read
  access; remains the authority for external mutations.
- **Goals:** Let an independent agent gather and reproduce evidence with enough capability
  to answer the real question.

### Forge Maintainer

- **Role:** Evolves the Forge template and publishes upgrades to downstream projects.
- **Permissions:** Defines Forge-managed artifacts and their installation contract.
- **Goals:** Author shared behavior once, preserve cross-platform parity, and upgrade both
  host surfaces without clobbering project-owned content.

## 4. User Stories

### US-001: Authoritatively Install or Migrate the Complete Dual-Engine Harness

**As a** Forge developer
**I want** a supported full-refresh setup mode to replace the legacy managed harness with
the canonical dual-engine harness and both host surfaces
**So that** Claude Code and Codex work immediately without competing policy copies.

**Scenario:**

```gherkin
Given a clean project or an existing Forge installation
When the developer runs the supported full-refresh setup mode
Then obsolete Forge-owned legacy duplicates are removed
And the canonical harness and both thin host surfaces are installed or refreshed
And protected project-owned instructions, state, memories, secrets, and configuration are preserved
```

**Acceptance Criteria:**

- [x] Setup does not ask for or store a permanent main agent.
- [x] Both host surfaces are materialized even if only one engine is currently usable.
- [x] A successful migration leaves one authoritative Forge workflow contract rather
  than legacy full copies competing with the canonical harness.
- [x] Obsolete files are deleted only when positively identified as Forge-managed legacy
  artifacts.
- [x] Forge-managed commands, rules, hooks, skills, agents, settings, and evidence support
  are refreshed to a mutually compatible version.
- [x] Protected user/project content retains its documented overwrite or merge semantics.
- [x] Unknown project files and custom host extensions are preserved.
- [x] Setup reports managed artifacts created, rewritten, deleted, preserved, or blocked.
- [x] Setup reports detected engine availability without treating a missing engine as an
  installation failure.
- [ ] Unix and Windows setup paths provide equivalent results.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Only Claude Code is installed | Both host surfaces install; runtime work uses Claude and fresh-Claude fallbacks until Codex becomes usable |
| Only Codex is installed | Both host surfaces install; runtime work uses Codex and fresh-Codex fallbacks until Claude becomes usable |
| Neither binary is detected | Harness installs and reports that an engine must become usable before workflows can run |
| Existing managed files are stale | Supported full-refresh migration rewrites them as one compatible harness version |
| Protected local state exists | Upgrade preserves it byte-for-byte unless its ownership contract explicitly defines a safe migration |
| A legacy Forge-managed duplicate is known | Full-refresh removes it after its ownership is confirmed |
| A file resembles a legacy artifact but ownership is unknown | Preserve it and report that manual reconciliation may be required |
| Migration cannot complete one required rewrite | Report partial migration as blocked; do not claim the dual harness is ready |

**Priority:** Must Have

---

### US-002: Select the Main Agent by the Host in Use

**As a** Forge developer
**I want** the host from which I run a workflow to become its active main agent
**So that** I can choose Claude Code or Codex naturally without project reconfiguration.

**Scenario:**

```gherkin
Given the dual-engine harness is installed
When the developer starts or resumes a Forge workflow from Codex
Then Codex performs the main-agent work from the current workflow checkpoint
And Claude is the preferred independent reviewer when usable
```

**Acceptance Criteria:**

- [x] No project-level main-agent lock or preference is required.
- [x] Starting from Claude makes Claude the current main agent.
- [x] Starting from Codex makes Codex the current main agent.
- [x] Runtime evidence identifies the host that performed each material workflow action.
- [x] The active host does not receive a reduced command, skill, hook, or gate surface.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Both engines are installed | The invoked host is main; the other is preferred reviewer |
| Other engine is unavailable | The invoked host remains main; review falls back visibly to a fresh same-engine run |
| Availability changes during a workflow | The next dispatch reevaluates availability and records the actual engine used |

**Priority:** Must Have

---

### US-003: Resume a Workflow from the Other Host

**As a** Forge developer
**I want** to move from Claude Code to Codex or from Codex to Claude between phases
**So that** I can use either engine for the part of the workflow I prefer.

**Scenario:**

```gherkin
Given Claude Code has completed and recorded an approved plan in a feature worktree
When the developer opens Codex in the same worktree and continues the workflow
Then Codex reads the shared checkpoint and starts at the next incomplete step
And completed gates and valid evidence are neither lost nor falsely repeated
```

**Acceptance Criteria:**

- [x] Both hosts read and update the same canonical workflow checkpoint.
- [x] Plans, decisions, blockers, evidence, and next-step state survive a host switch.
- [x] Evidence remains valid only while its existing artifact-freshness rules hold.
- [x] Switching hosts does not itself invalidate valid evidence or complete an unchecked
  gate.
- [x] No lock, lease, concurrency detector, or mandatory handoff command is introduced.
- [x] Documentation warns developers not to edit the same files simultaneously from two
  active agents.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Outgoing host stopped without a special command | Incoming host resumes from the last durable repository/state checkpoint |
| A file changed after review | Existing artifact-freshness rules invalidate the affected review regardless of host |
| Both agents edit simultaneously | Forge provides no coordination guarantee; ordinary filesystem and Git behavior applies |

**Priority:** Must Have

---

### US-004: Dispatch an Independent Reviewer with Visible Fallback

**As a** Forge developer
**I want** review to prefer the other engine and continue with a fresh same-engine reviewer when necessary
**So that** unavailable tooling does not block a safe workflow.

**Scenario:**

```gherkin
Given Claude is the active main agent and Codex is unavailable
When a plan or code review is required
Then Forge announces the Codex-to-Claude fallback
And launches a fresh independent Claude reviewer
And records the requested engine, actual engine, fallback reason, and reviewed artifact
```

**Acceptance Criteria:**

- [x] All four main/reviewer engine combinations are supported.
- [x] Automatic selection prefers the other engine when it is usable.
- [x] An explicit unavailable reviewer selection also falls back instead of stopping.
- [x] Every fallback is visible before or with the reviewer result.
- [x] Same-engine review uses a fresh run with bounded review context.
- [x] Clean evidence records requested engine, actual engine, fresh-run identity, review
  role, artifact identity, and relevant capability profile.
- [x] Material artifact mutation invalidates evidence according to the existing gate rules.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Other engine executable is missing | Announce and dispatch fresh same-engine reviewer |
| Other engine authentication or launch fails | Announce the failure reason and dispatch fresh same-engine reviewer |
| Explicit reviewer equals main engine | Launch a fresh same-engine reviewer without treating the selection as degraded |
| Fallback reviewer also fails | Surface a real reviewer failure and blocker; never fabricate clean evidence |

**Priority:** Must Have

---

### US-005: Run a Capability-Expanded Investigation

**As an** investigating developer
**I want** a fresh investigative reviewer to use network, executable queries, project tools, and permitted writes
**So that** it can gather real evidence rather than review code in isolation.

**Scenario:**

```gherkin
Given an investigation requires live data and a worktree evidence artifact
When Forge dispatches an investigative reviewer
Then Forge launches a fresh full-capability engine in the real worktree with normal host/project configuration
And the reviewer may use the network, query, execution, MCP, and worktree-write capabilities normally available to that host
And unattended Claude uses native safety-classified auto mode rather than bypassing permission checks
And non-interactive Codex uses full host access with native on-request approval rather than its read-only default
And any external mutation occurs only after the developer explicitly authorizes a bounded target and operation
```

**Acceptance Criteria:**

- [x] Investigative capability is independent of reviewer-engine selection.
- [x] Either engine can serve as investigative reviewer or same-engine fallback.
- [x] Investigation shares the real worktree, canonical state, durable/local memory, normal host
  config, skills, MCP, and credentials without a Forge-specific sandbox or tool allowlist.
- [x] Internet access, live read queries, project execution, and worktree evidence writes
  can be granted without misclassifying the reviewer as non-independent.
- [x] External mutations require explicit user authorization naming a bounded target and
  operation.
- [x] Authorization for one mutation scope does not silently authorize unrelated targets
  or future investigations.
- [x] Findings record reproducible commands/queries, parameters, results, uncertainty,
  and independent verification status.
- [x] Secrets are not copied into prompts, evidence, command arguments, or tracked files.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Investigation needs only source code | Use the narrower normal-review capability profile |
| Investigation needs a writeable query/script artifact | Permit worktree write according to the host's normal permissions |
| Investigation proposes an external write without authorization | Pause that mutation and request scoped authorization |
| Developer refuses external mutation | Continue read-only investigation where useful or report the bounded blocker |

**Priority:** Must Have

---

### US-006: Preserve the Mixed-Engine Engineering Council

**As a** Forge developer
**I want** the council to use both engines when possible and remain complete when only one works
**So that** decision analysis remains available without engine-availability blockers.

**Scenario:**

```gherkin
Given Codex is the active main engine and Claude is usable
When Forge convenes the Engineering Council
Then three advisors run as fresh Codex instances
And two advisors and the chairman run as fresh Claude instances
And the chairman preserves peer review and minority reports
```

**Acceptance Criteria:**

- [x] Default topology is three main-engine advisors, two other-engine advisors, and an
  other-engine chairman.
- [x] Every seat retains its named persona and structured-output obligation.
- [x] If the other engine is missing or any other-engine dispatch fails, the partial
  mixed council is discarded and all six seats are visibly rerun as fresh main-engine
  instances.
- [x] A fully degraded council still runs five advisors plus a separate chairman.
- [x] Council evidence records intended topology, actual topology, and fallback reasons.
- [x] Advanced configuration may override seat engines without removing required roles,
  anonymous peer review, chairman synthesis, or minority reports.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Other engine absent before dispatch | Start all six fresh runs on the main engine and announce degraded topology |
| One other-engine advisor fails | Discard the partial mixed record and rerun all six seats fresh on the main engine |
| Other-engine chairman fails | Discard the partial mixed record and rerun all six seats fresh on the main engine |
| A same-engine fallback seat fails | Apply ordinary council failure handling; do not fabricate a seat response |

**Priority:** Must Have

---

### US-007: Drive the Forge Lifecycle with Either Native Goal

**As a** Forge developer
**I want** `/goal` to drive the same Forge lifecycle from Claude Code or Codex
**So that** autonomous execution is not tied to one host.

**Scenario:**

```gherkin
Given an approved feature PRD and a valid Forge workflow checkpoint
When the developer starts the Forge-composed goal from either supported host
Then the active host proceeds through planning, review, implementation, verification, and PR authorization
And completion is judged from the same fresh canonical evidence contract
```

**Acceptance Criteria:**

- [x] Claude Code and Codex receive host-appropriate goal instructions for the same
  objective and stopping evidence.
- [x] Goal session identity and workflow evidence are host-neutral and durable in the
  worktree.
- [x] Review and council selection follow the same runtime engine and fallback rules used
  in interactive workflows.
- [x] Missing Codex or Claude does not by itself halt autonomous execution.
- [x] Stale evidence from an earlier goal session or artifact cannot satisfy completion.
- [x] PR creation retains its explicit human-authorization requirement.
- [x] Real tool, reviewer, evidence, or authorization failures remain visible blockers.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Goal starts in Claude | Claude native goal surface drives canonical Forge checkpoints |
| Goal starts in Codex | Codex native goal surface drives the same checkpoints and evidence contract |
| Other reviewer engine becomes unavailable mid-goal | Announce and use fresh same-engine fallback without ending the goal |
| Developer switches hosts mid-workflow | New host may resume manually from durable state; no cross-host native-session transfer is promised |

**Priority:** Must Have

---

### US-008: Provide Full Workflow and Gate Parity

**As a** Forge developer
**I want** every installed workflow to behave equivalently in both hosts
**So that** choosing or switching engines never removes Forge discipline.

**Scenario:**

```gherkin
Given the dual-engine harness is installed
When the developer invokes any supported Forge workflow from either host
Then the workflow exposes the same required phases, approvals, reviewers, evidence, and ship gates
And host-specific mechanics do not change the required outcome
```

**Acceptance Criteria:**

- [x] V1 parity covers PRD discussion/creation, new feature, bug fix, quick fix, review,
  investigation, council, autonomous goal, review-comment processing, finish branch,
  release, state/memory continuity, hooks, and evidence gates.
- [x] Existing worktree, TDD, verification, E2E, review-convergence, PR authorization,
  and merge-authorization requirements remain enforced.
- [x] Both host surfaces expose equivalent help and user documentation.
- [x] Parity tests detect a missing phase, weakened gate, stale generated surface, or
  engine-specific evidence assumption.
- [x] Host-specific limitations are surfaced explicitly rather than hidden as success.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| A native hook event exists in only one host | Equivalent observable enforcement or a documented host-appropriate mechanism is required |
| A workflow is upgraded while local state is active | Managed behavior refreshes without erasing the active checkpoint |
| A host adapter is stale relative to shared policy | Setup and parity verification detect and refresh the incompatible artifact |

**Priority:** Must Have

---

### US-009: Share Durable Context Without Sharing Invalid Gate State

**As a** Forge developer
**I want** both hosts to see the same durable decisions and current worktree checkpoint
**So that** switching engines preserves context without contaminating another feature.

**Scenario:**

```gherkin
Given two features are running in separate worktrees
When their developers use different main engines
Then each workflow keeps independent mutable gate state
And both hosts can consume the project's shared durable instructions, decisions, and memories
```

**Acceptance Criteria:**

- [x] Mutable workflow and goal state is scoped to its checkout/worktree.
- [x] Durable project guidance and approved memories are accessible from both hosts under
  their documented ownership and synchronization rules.
- [x] Setup does not overwrite active local workflow state or user memory.
- [x] A checkpoint from one worktree cannot satisfy gates in another worktree.
- [x] Evidence identifies the relevant worktree and artifact/session identity.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| Two features run concurrently in separate worktrees | State and evidence remain isolated per worktree |
| One host lacks a host-native memory representation | Durable shared guidance remains available through the canonical project surface |
| Local state predates the dual-engine upgrade | Upgrade preserves it and provides a safe compatible interpretation or explicit migration blocker |

**Priority:** Must Have

---

### US-010: Finish Review Work at the Point of Diminishing Returns

**As a** Forge developer
**I want** resource discipline embedded in planning, implementation, and review loops
**So that** Forge solves the requested problem correctly without wasting session time, tokens, or
money on perfection or edge cases that are not reasonably reachable.

**Scenario:**

```gherkin
Given a plan or code review has reported concrete findings
When the main agent repairs those findings and requests closure review
Then the closure review verifies the named fixes and direct regressions only
And the loop stops when only P3, cosmetic, speculative, or unchanged-candidate concerns remain
```

**Acceptance Criteria:**

- [x] Root instructions state that time, tokens, and money are engineering resources and that the
  smallest correct solution is preferred.
- [x] The plan-review and code-review prompts repeat the resource-discipline rule at each loop.
- [x] A reviewer performs at most one broad scan per artifact revision; closure review verifies
  prior findings and direct regressions instead of opening an unrelated new broad scan.
- [x] P0/P1 remain blocking when they describe reachable supported behavior, security exposure,
  data loss, or a stated acceptance criterion.
- [x] P2 requires a concrete, materially likely maintainability, reliability, or test risk; a
  theoretical rare possibility without evidence is P3 or out of scope.
- [x] P3, naming, cosmetic polish, speculative hardening, and perfection work never keep a loop open.
- [x] Focused owning tests run during repair; the complete suite runs once after final bytes freeze,
  except when a changed high-risk boundary invalidates that evidence.
- [x] Review loops have a bounded repair/closure default and escalate a still-open P0/P1 to the
  developer rather than iterating indefinitely.
- [x] Canonical rules, workflow commands, reviewer instructions, and installed root instructions
  contain no conflicting unconditional instruction to exhaust every possible issue or continue
  until perfection.

**Edge Cases:**

| Condition | Expected Behavior |
| --- | --- |
| A rare case can cause data loss or a security boundary failure | Treat it as reachable risk and fix or block; resource discipline is not an excuse to weaken safety |
| A reviewer invents an unproven theoretical edge after closure | Record it as P3/out of scope and stop the loop |
| Final bytes change after full verification | Rerun the owning focused check and invalidate/re-run the final aggregate only when the changed boundary can affect it |
| An external environment gate cannot run locally | Record the honest external gate and continue independent implementation; do not simulate proof or loop on it |

**Priority:** Must Have

## 5. Constraints & Policies

### Business / Compliance Constraints

- The feature serves local developers and project repositories; it does not introduce a
  multi-tenant orchestration service.
- Explicit human approval remains mandatory for PR creation, merge/promotion actions,
  and newly requested external mutations where the existing workflow requires it.
- Engine fallback is always disclosed; Forge must not imply cross-engine review occurred
  when the actual review was same-engine.

### Platform / Operational Constraints

- Unix Bash and Windows PowerShell installation and hook behavior must remain equivalent.
- Downstream projects must not require manual duplication or hand-editing after a
  successful full-refresh migration.
- Migration deletion authority is limited to positively identified Forge-managed paths;
  broad directory deletion is prohibited.
- The harness remains installable without adding an application build step or mandatory
  long-running service.
- Existing protected-file ownership rules remain effective during upgrades.
- A developer may have both engines, one engine, or later install the missing engine.
- Host switching is cooperative and sequential by convention, not mechanically locked.

### Dependencies & Required Integrations

- **Requires:** usable Claude Code or Codex installation for runtime work.
- **Requires:** existing Forge state, evidence, hook, worktree, review, council, and
  verification contracts to remain supportable.
- **Named integrations:** Claude Code commands/hooks/skills/subagents and Codex
  commands/hooks/skills/subagents, including each host's native `/goal` capability.
- **Blocked by:** none at the requirements stage; host-specific capability gaps must be
  addressed or exposed during design validation.

## 6. Security Outcomes Required

- **Who can access what:** reviewers and council members receive only the context and
  capabilities required by their selected role; investigative expansion is explicit in
  the evidence record.
- **What must never leak:** secrets, credentials, tokens, and protected local state must
  not be copied into prompts, command arguments, tracked evidence, or logs.
- **What must be auditable:** reviewer engine selection and fallback, fresh-run identity,
  reviewed artifact, council topology degradation, investigative capability profile,
  external mutation authorization, and PR authorization.
- **External mutation authority:** an investigative reviewer may not mutate an external
  system until the developer explicitly authorizes a bounded target and operation.
- **Evidence integrity:** stale, cross-worktree, pre-mutation, or mismatched-session
  evidence cannot satisfy a workflow or goal gate.
- **Fallback honesty:** degraded same-engine review or council composition must remain
  visible in user output and evidence.

## 7. Open Questions

- None at PRD creation. Host-specific mechanics, canonical-source layout, generated
  adapters, evidence schema, and upgrade implementation belong to technical design.

## 8. References

- **Discussion Log:** `docs/prds/agent-mode-selection-discussion.md`
- **Existing Investigate decision:** `docs/adr/0007-codex-investigate-mode-capability-gated.md`
- **Existing autonomous-goal PRD:** `docs/prds/forge-goal.md`
- **Existing scoped-review design:** `docs/superpowers/specs/2026-06-04-scoped-review-certification-design.md`
- **Empirical downstream prototype:** sibling MCPGateway project's host-neutral
  `.agent-workflows` implementation
- **Claude Code `/goal`:** <https://code.claude.com/docs/en/goal>
- **Codex `/goal`:** <https://learn.chatgpt.com/docs/developer-commands?surface=cli#set-or-view-a-task-goal-with-goal>
- **Portable Agent Skills:** <https://agentskills.io/home>

---

## Appendix A: Revision History

| Version | Date | Author | Changes |
| --- | --- | --- | --- |
| 1.2 | 2026-08-27 | Codex + Pablo | Add load-bearing resource discipline and diminishing-returns stop rules for plan/code review loops |
| 1.1 | 2026-08-26 | Codex + Pablo | Align council failure rows with the approved complete six-seat same-engine fallback |
| 1.0 | 2026-08-26 | Codex + Pablo | Initial PRD from completed requirements discussion |

## Appendix B: Approval

- [x] Product Owner approval — Pablo — 2026-08-26
- [ ] Technical Lead approval
- [x] Ready for technical design — 2026-08-26
