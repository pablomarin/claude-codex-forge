# Workflow Rules

## Choose the Smallest Matching Workflow

| Need | Canonical workflow |
|---|---|
| New capability | `/new-feature <name>` |
| Reproduce and fix a defect | `/fix-bug <name>` |
| Trivial, low-risk change under the quick-fix limits | `/quick-fix <name>` |
| Fresh second opinion or code review | Claude: `/opinion <request>`; Codex: `$opinion <request>` |
| Investigation requiring live project tools, network, or real-worktree writes | Claude: `/opinion investigate <request>`; Codex: `$opinion investigate <request>` |
| Resolve an explicitly requested or still-unresolved high-impact architectural fork | `/council <question>` |
| Process PR feedback | `/review-pr-comments` |
| Merge and clean up after approval | `/finish-branch` |

The current host is the main agent for the session. Resolve it through the installed host adapter;
never persist a permanent main-engine preference. Reviewer `auto` selects the other installed
engine and automatically falls back to a fresh same-engine reviewer when launch/capability failure
occurs. A finding is a review result, not a fallback reason.

Ordinary reviews use an immutable disposable candidate. Select full-agent investigation from the
task's actual need for live project capabilities, under the standing Human-Approved Reviews policy;
explain the mode without another Forge consent question. Investigation runs in the real worktree
with normal host/project capabilities. A permission denial or timeout alone must never switch an
ordinary review or its fallback to investigation. Native host security and the existing destructive
and external-mutation boundaries remain in force.

## Reviewer authentication recovery

The dispatcher preserves automatic fallback. A usable fallback review (including findings)
needs no login interruption. When neither attempt completes and the receipt says
`auth_recovery_engine=claude`, the `AUTH_REQUIRED` handoff belongs to the **main agent**, not
the isolated reviewer. `failure_reason` records the final attempt; `fallback_reason` records
the first failure. Authentication is an engine failure, not missing reviewer-transport consent.

1. Collect the completed parallel review calls before recovery. Preserve their outputs and
   receipts, including failures. Coalesce same-provider failures into one recovery cycle; keep
   clean lenses and independent verification. Record a narrative recovery entry under
   `.forge/local/` with candidate hash, iteration, failed receipt paths, unfinished roles,
   each role's original engine selection and fallback policy, preserved regular prompt
   path and SHA-256 matching its failed receipt's
   `prompt_hash`, and `recovery_cycles=1` **before** starting recovery. Keep those prompt
   bytes under `.forge/local/reviews/`. Check this entry on host handoff:
   a new session does not reset the cycle or retry budget. Use `workflow-state checkpoint`
   for the exact durable next step, not direct writes to control rows.
2. Distinguish credential access from expired login. Use the same CLI binary and operator
   credential context as the reviewer. A sandboxed `claude auth status` reporting logged out
   does not establish that the normal host is logged out; desktop sign-in does not prove CLI
   access either. If a host restriction is evidenced, use its normal approval mechanism for
   a bounded no-project, no-tool authentication probe. A denied boundary remains blocked;
   never copy credentials, broaden reviewer permissions, or bypass the restriction.
   A successful probe skips login and proceeds to the one review retry in step 4.
3. When login recovery is needed, open a developer-visible interactive terminal and start the
   official `claude auth login` with that CLI and credential context. Tell the developer:
   “The Claude reviewer needs you to finish sign-in in the terminal/browser I opened.
   Your work and completed reviews are saved; I’ll retry only the unfinished review afterward.”
   Pause for the human authentication step. The human enters credentials and completes MFA;
   never ask them to paste tokens or authorization codes into chat. Record no secrets or
   raw login output in project evidence. If an interactive terminal cannot be opened, provide
   the exact command and explain that limitation. Do not run login inside the hermetic reviewer,
   automatically log out, mint a long-lived token, or change the provider/billing method.
4. After successful login (or the successful context probe), mark `review_retry_consumed=true`
   in the recovery entry before dispatch. Verify each saved prompt still matches its
   recorded hash and failed receipt. Missing or changed prompts are an evidence blocker;
   checkpoint and stop instead of reconstructing instructions from conversation memory.
   Recheck the candidate fingerprint. If unchanged,
   invoke only the unfinished ordinary review roles once, with the same base, candidate,
   iteration, prompt, engine selection, and fallback policy, and fresh output/receipt paths.
   Revalidate the completed lens when assembling the pair. If the candidate changed, stop
   this retry and follow normal refreeze/invalidation; never relabel old evidence or reset
   the consumed recovery budget merely by changing candidate bytes.
5. If login is cancelled/fails or the retry is still blocked, checkpoint the exact reason and
   remaining role(s), then stop and tell the developer what action is required. A second
   recovery cycle requires explicit user direction. Never treat login success as review
   certification or loop through repeated login/review attempts.

For multi-turn council calls, the council orchestrator still owns whole-topology fallback.
Do not independently restart a failed seat or mix recovered sessions into an existing panel.
Network, quota, permission, missing capability, and artifact failures retain their own
remediation; a generic HTTP error or review text mentioning authentication is not a login signal.

## Startup boundary

Before activation, read only the Forge instructions and bounded state, then perform deterministic
checks of the actual host, physical worktree, current branch, intended base, and installed harness.
Do not investigate the app, run tests, explore source, or begin implementation before activation.

After selecting the intended physical worktree, complete the
[native session/worktree probe](#native-sessionworktree-probe) before activation or resumed task
work, including after create/adopt and any host/session switch. If the matching task is already
active there, checkpoint the displayed host, phase and exact next step, then resume that step.
Quick-fix never creates a worktree: confirm its current branch is non-protected, then activate there.
Only `/new-feature` and `/fix-bug` require worktree creation when they are not already isolated. A prepared native worktree
is existing isolation: never create another worktree for a same-directory handoff. For those two
isolated workflows, the ordinary `worktree-lifecycle` shell helper remains the portable creation
path where the host permits it. Native creation or adoption is an option only when the actual host
exposes that capability and the intended base and installed Forge harness are verified in the
resulting worktree before activation. Before activating in a fresh host-native worktree, run
`worktree-lifecycle.sh adopt --kind <feat|fix> --name <slug> --base <ref-or-sha> --worktree <path>`
(or the PowerShell twin). The helper requires an exact-base, clean, unpublished linked worktree,
then seeds Forge state and replaces a host-generated branch name such as `claude/...` or `codex/...`
with the required `feat/...` or `fix/...` name. It never renames a protected, dirty, shared, or
published branch. Never silently substitute a host's default base.

If worktree creation, adoption, seeding, or harness setup is denied, stop before task work and
report the exact target, missing prerequisite, and next supported setup action. Do not fabricate activation.
Do not overwrite another primary active workflow to manufacture a checkpoint, copy all of
`.forge/local/`, create unmanaged worktree-include policy, reconstruct protected files, change
permissions, or retry a denied protected write through another transport. Prompt changes do not by
themselves prove that native setup works; that requires a later native E2E run.

## Resource Discipline

Optimize for the smallest correct solution; developer time, session length, tokens, and money are
finite engineering resources. Do not pursue perfection, cosmetic polish, speculative hardening, or
edge cases without a concrete supported trigger, stated acceptance criterion, material likelihood,
security impact, or data-integrity impact.

For each artifact revision, allow one broad review, one repair pass, and one closure review. Closure
checks only the named findings and direct regressions; a reviewer may not start a second broad scan.
One still-open reachable P0/P1 may receive one surgical repair plus a surgical verification of only
that finding, then Forge surfaces the blocker to the developer instead of iterating indefinitely.

P3, naming, cosmetic, purely theoretical, and unchanged candidate concerns never keep a loop open.
Schema-valid `FINDINGS/P3` is advisory and certifying, just like `CLEAN/P3`; preserve
the notes without repairing or reopening review solely for them. Any P0/P1/P2
finding row still blocks certification regardless of the reported maximum severity.
Stop the review cycle when further iterations have diminishing returns or the remaining proposals
would violate KISS or YAGNI. Preserve those advisory findings and surface them to the developer;
do not spend another broad review on speculative improvements. This stop rule never waives a
reachable P0/P1, a concrete material P2, or an explicit acceptance criterion.
P2 means a concrete material maintainability, reliability, performance, or test risk, not a merely
imaginable rare case. Rare but catastrophic security or data loss triggers remain P0/P1. Resource
discipline never excuses reachable security failure, data loss, incorrect supported behavior, or an
explicit acceptance criterion.

During repair, run focused owning checks. After the final bytes freeze, use the project's fast local gate
and applicable focused acceptance checks, not an exhaustive aggregate of unrelated suites.
Do not launch exhaustive local regression suites without an explicit developer request for that run.
For Forge source development, use `tests/template/run-fast.sh`; `run-all.sh` and `run-all.ps1` are
CI/release coverage, not automatic local gates. A workflow invocation, candidate freeze, version bump,
release, or integration boundary is not permission to launch them locally. Report unexecuted coverage
honestly; required feature-specific acceptance and user-journey checks remain applicable.
Do not mechanically restart unrelated verification. A mutation invalidates only evidence whose
boundary it can affect. Exact-candidate receipts require the same final fingerprint or the explicit
recomputed documentation closure below. During diagnosis, planning, implementation, repair and
preliminary E2E, missing final receipts are expected: preserve progress and run focused checks.
Stop's final-evidence advisory belongs to finalization phases and never requests new reviews or
verifier runs by itself. Actual shipping enforces ordinary certification or the bounded
human workflow-waiver route below, with fresh evidence for every unwaived requirement.
Environment-only Windows, authenticated, and manual gates remain honest final gates; they do not
trigger implementation loops or authorize fake evidence.

## Host-Analyzable Commands

Shell approval is a host security control; Forge instructions cannot override it. Use one primary
program per shell tool call with literal arguments for routine build, test, packaging, parity,
boundary, staging, and fingerprint work. Run from the active worktree and use a command's own path
or output flags instead of wrapping several phases in one shell program.

Do not introduce `set -e`, shell variables, brace expansion, control flow, or heredocs. Do not
introduce command substitutions, generated command strings, redirects, pipelines, or chains merely
to combine actions.
Use the host's structured read/write tools for file content. When genuine multi-step logic is
needed, put it in a bounded, reviewable project script and invoke that script separately with
literal arguments; do not hide the same shell program behind `bash -c`, `sh -c`, or an interpreter
string.

Prefer a fresh unique output or temporary directory over deleting and rebuilding an existing one.
Keep package creation, parity comparison, staging, repository-boundary validation, and candidate
freeze as separate calls. Never combine recursive deletion with verification, packaging, staging,
boundary checking, or freezing. If an exact generated path truly must be removed, resolve it first
and perform the real destructive action as a separate host approval; do not bypass, weaken, or
obfuscate that gate. A host may still request approval after these precautions, which is an honest
runtime result rather than permission to claim the workflow is prompt-free.

## Durable State and Host Switching

Run `.forge/hooks/lib/workflow-state.sh show` before every workflow action (PowerShell:
`.forge/hooks/lib/workflow-state.ps1 show`). The bounded helper is the only canonical interface for
workflow control rows. If an inactive pre-bound worktree was fast-forwarded to the exact intended
base, run `workflow-state.sh rebind --base-ref <ref> --expected-base-sha <recorded-sha>` before
activation (use the `.ps1` twin on Windows). Rebind is atomic and fail-closed: the recorded base
must be an ancestor, the requested ref must equal current `HEAD`, and no active workflow, Goal,
review, or PR-authorization evidence may exist. Never edit workflow control rows manually. Use
`workflow-state.sh activate` once in a new task worktree and
`workflow-state.sh checkpoint` for later host, phase, next-step, and review-iteration transitions.
The helper alone derives the first receipt-certified iteration and preserves it for convergence
accounting; neither host may set or advance that anchor directly.
Use host-native file tools only for checklist and narrative content. A host switch resumes the exact
next step in the same branch/worktree. Forge creates no edit lock: concurrent sessions are allowed.
Coordinate overlapping writes; if any session mutates the candidate, candidate-bound evidence becomes stale.
Do not introduce locks, leases, or a permanent session owner.

Developer state, review receipts, verification receipts, and local memories live under
`.forge/local/`; project-owned durable memory lives under `.forge/memory/`. Use the active host's
file capabilities for local evidence. Never infer a clean gate from a successful process exit.

## Native Session/Worktree Probe

Selecting a tool working directory does not establish the native hook directory. After selecting,
creating or adopting a worktree, and after a host/session switch, verify both before task work:

1. Run `bash .forge/hooks/lib/host-context.sh prepare-context --worktree <absolute-task-root>`.
   PowerShell: `host-context.ps1 -Mode prepare-context -Worktree <absolute-task-root>`.
   In the Forge source checkout only, use `hooks/lib/host-context.sh` or `.ps1` when the
   installed helper is absent; follow its `CONTRIBUTING.md` source-mode native-context exception
   when that source checkout intentionally has no registered hooks. This never exempts an
   installed project with missing/disabled hooks. Preparation prints two exact commands with the physical root
   encoded as hex. It checks no native event and grants no authority.
2. Execute the first printed command, `probe`, as one standalone call through the normal native
   shell tool, with its process working directory set to the intended root. Do not wrap it in
   `cd`, environment prefixes, pipelines or compound commands. The existing workflow hook
   intentionally denies this harmless diagnostic command with exit 2. Require the actual native
   tool response to contain `FORGE_NATIVE_CONTEXT: MATCH` and the expected root. This particular
   MATCH denial is the expected result; do not retry or bypass the denied probe command.
3. Execute the separately printed `check-process` command through the same normal tool at that
   root. Require exit 0 and `FORGE_PROCESS_CONTEXT: MATCH`. This verifies only process context.
   A probe process that actually runs reports `UNVERIFIED`: the native hook was not observed.
   Missing native output, untrusted/disabled hooks, malformed metadata or either mismatch leaves
   alignment UNVERIFIED and blocks task work. Synthetic hook JSON and manual hook invocation
   exercise fixtures only; they cannot stand in for this native observation.
4. On mismatch, use the host's supported attachment/rebind action for the **existing worktree**,
   then repeat both commands. If the host cannot change session cwd (for example, a CLI session
   that remains rooted in primary), open a session at that existing checkout and resume the exact
   next step. Report actual and expected roots and the required native action. Do not create
   another worktree, copy receipts/state, edit trust stores or reconstruct workflow evidence.

SessionStart reports its event root, Git common directory and branch as context; it does not know
the intended task and therefore reports UNVERIFIED until the probe runs. The probe stores no
receipt, lock or session authority. Use only normal host trust/setup when hooks are unavailable.
Skipping this required workflow step leaves the existing event-cwd routing limitation in place;
Forge does not infer every shell command's target from its text. In particular, inactive primary
state can still allow a command aimed elsewhere if the required native probe is skipped.

## Shipping from the Current Session

Continue in the current session when the native probe matches. Use that verified task context for
local edits, reviews, verification, approval recording and normal receipt-validating promotion.
Promotion validates task receipts; it does not prove a later native event used the same context.

Immediately before direct `git commit`, `git push` or `gh pr create`, repeat the native probe and
process check above, then perform this explicit local preflight:

1. Set the tool process working directory to the verified physical task-worktree root. Run that
   worktree's `.forge/hooks/lib/workflow-state.sh show` (PowerShell: `workflow-state.ps1 show`).
   Require the expected active task and workflow identity, and verify the worktree root and
   Git common-directory identity against the intended task.
   A matching recorded task remains valid at phase `complete`.
   Completion does not waive shipping receipts or invalidate unchanged publication approval.
   Inactive here means no matching recorded task workflow, rather than a completed phase.
   Missing, inactive, mismatched or unreadable state
   blocks shipping; an exit-0 gate result cannot substitute for this validation.
2. Construct JSON input for the exact single shipping command, with an explicit `cwd` equal to
   that verified root and `tool_input.command` equal to the planned command. Verify the `cwd`
   equality directly; never infer it from command text. An absent or different input `cwd` fails
   this preflight requirement.
3. Invoke that worktree's existing `.forge/hooks/check-workflow-gates.sh` or
   `.forge/hooks/check-workflow-gates.ps1` as a process, supplying the JSON on standard input with
   both process cwd and input cwd at the same verified root. Require exit 0 after the state and
   identity checks above. Any preflight failure blocks execution.
4. Immediately before executing that exact command through the normal host tool, revalidate the
   unchanged candidate, HEAD and approval. Any mutation invalidates the corresponding evidence;
   follow the existing refreeze, review, verification and authorization rules before proceeding.

The explicit JSON preflight is local verification, not a native event. It does not grant shipping authority or certify
native authentication. Keep normal native hooks enabled and preserve existing human authorization
requirements. Report any native-session context mismatch: the host's event `cwd` may differ from
the tool working directory. Stop on any real denial; never bypass a host or hook restriction.
Existing standing review approval and still-current exact-scope shipping approval remain valid.
Do not ask another workspace-choice question or repeat a valid approval solely for a context-only
recovery. Rebind to the already-selected task worktree where supported; if a user action is required,
explain the exact native limitation and preserve the next step and still-valid evidence.

## Plan, Review, and Evidence

### Canonical V6 state transitions

Feature and bug-fix workflows ordinarily follow this full-certification state machine; receipt
population records progress and never activates a mode. An actual developer instruction to omit
named remaining steps uses the workflow waiver below in place of only those steps:

1. **Recover inactive binding when required:** if `show` reports that an inactive pre-bound
   worktree no longer matches `HEAD`, use the bounded `workflow-state.sh rebind` transition above.
   This is a one-time recovery before activation, not an active-workflow base mutation.
2. **Activate:** resolve and persist the immutable workflow base ref/SHA, create one task-local
   `.forge/local/` evidence directory, populate every receipt path, and set `Review iteration` to
   `0`. Invoke `.forge/hooks/lib/workflow-state.sh activate --host <claude|codex> --workflow
   <new-feature|fix-bug> --task <slug> --base-ref <ref-or-sha> --phase <phase>
   --next-step '<exact next step>'` before any discretionary investigation or tracked mutation.
   The active V6 schema selects structured evidence immediately. An identical in-flight V6.1
   placeholder bundle is adopted by this activation; partial or conflicting bundles fail closed.
3. **Plan before code:** obtain clean candidate-bound plan evidence before production implementation.
4. **Exercise early:** run preliminary E2E while mutation is still allowed, or record why no
   supported user journey exists; this is not final certification.
5. **Freeze:** finish TDD, documentation, and simplification; stage the intended tree and freeze one
   staged-clean candidate.
6. **Review:** invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex> --phase
   review --next-step '<exact next step>' --begin-review` before dispatch, then run distinct fresh
   `code-spec` and `code-quality` lenses against the same candidate and iteration.
7. **Verify:** run `verify-app` and E2E against that same candidate and write their structured
   receipts. E2E N/A requires its candidate-bound report and reason.
8. **Invalidate on functional change:** Restage, freeze a new candidate, increment the iteration
   before fresh paired review, and rerun the affected final gates. An eligible non-runtime prose
   correction may instead use the documentation closure below without another paired-review round.
   A human may separately waive independent review for an explicitly approved changed candidate.
9. **Promote:** revalidate the complete receipt set and promote only the exact certified tree.

Quick-fix is deliberately separate. It requires a clean exact-base activation, a clearly understood
low-risk non-user-facing change, at most three implementation paths, and one direct focused check by
the main agent. Exact `README.md` and `docs/CHANGELOG.md` release metadata does not consume that path
budget. It dispatches no plan, `code-spec`, `code-quality`, `verify-app`, or `verify-e2e` role; does
not freeze a candidate or create final receipts; and ships only when the hook revalidates its single
recorded ancestral base and complete changed-path scope. Any ambiguity, higher risk, user-facing
behavior, architecture choice, or scope overflow must restart as `/fix-bug` or `/new-feature`.

At every other durable boundary, invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host
<claude|codex> --phase <phase> --next-step '<exact next step>'`. End a completed workflow with the
exact terminal transition `workflow-state.sh checkpoint --host <claude|codex> --phase complete
--next-step none`; only that terminal pair permits a new activation. On Windows, use the `.ps1`
twin with the same action and arguments.

- Research current documentation before design when a library, API, or provider is involved.
- Compare viable approaches and run the cheapest safe falsifying check first. Do not invoke /council
  as a routine planning, review, or implementation step. Invoke it only when the developer explicitly requests it
  or a concrete high-impact architectural fork remains unresolved after that check.
- For `/fix-bug` and `/new-feature`, freeze the exact staged-clean candidate before final review or verification.
- Dispatch fresh independent `plan`, `code-spec`, and `code-quality` roles through the installed
  structured dispatcher. Automatic fallback is visible in its receipt.
- Ordinary code-review certification requires distinct clean `code-spec` and `code-quality`
  receipts for the same candidate. A human waiver does not produce that certification.
- `verify-app` and `verify-e2e` each write a candidate-bound verification receipt. Missing execution
  or access is `BLOCKED`/`UNVERIFIED`, never PASS.
- Any candidate mutation invalidates affected receipts and restarts from staging/freeze.

The compatibility reader may consume genuine unmigrated v5 state. Active canonical V6 feature and
bug-fix workflows use the current structured receipts; the exact bounded quick-fix flow uses direct
base/scope enforcement instead. Legacy prose never certifies a migrated gate.

## Autonomous Goal Composition

Forge composes the active host's native `/goal`; it does not install or shadow a native goal
command/skill and does not claim native sessions transfer. `.forge/local/state.md` is authoritative
for the objective, nonce, persistent budget ceiling, consumed durable turns, checklist, next step,
candidate, evidence, authorization, and terminal status. Native counters may reset; Forge counters
may not.

Ordinary non-destructive workflow judgment stays inside the owning bounded workflow. Stop autonomy
for:

- explicit user input or authorization/cancellation;
- PR creation or any other new external mutation requiring human authority;
- a security-sensitive or irreversible action;
- a broken invariant, exhausted persistent budget, or unresolved convergence blocker.

PR creation requires explicit human approval bound to the active nonce and candidate. The agent records the decision and executes the approved action; the human need not edit state or run a command.
Ordinary reviewer/council engine failure uses automatic same-engine fallback and does not stop the
workflow. If the active host cannot compose every Must goal behavior, mark runtime readiness
`BLOCKED` rather than silently reducing the contract.

### Council During Autonomous Goal

Do not invoke /council as a routine response to non-PR doubts, reviewer findings, soft warnings, or
implementation choices. During an active native Goal,
Council may resolve a genuine non-destructive decision. It must concern product or engineering
judgment and be required to
continue the active native Goal. First run the cheapest safe falsifying check; if it produces a
deterministic smallest answer, use that answer instead. Otherwise apply the chairman's verdict and
continue the owning workflow. Council also remains available when the developer explicitly requests
it or a concrete high-impact architectural fork remains unresolved after that check.

The decision requirement is the trigger: an ordinary plan/code-review finding, a soft E2E warning,
an engine failure, or a convergence limit is not a council trigger by itself. Reviewer engine
failure uses automatic fallback; unresolved convergence and every action requiring human authority
still pause for the developer.
PR creation authorization remains human-only. Ask-tier commands stall autonomous runs, so surface the
deterministic action for the human decision, then record and execute it through normal host controls. Do not ask again for a still-valid approval.

### Severity and Convergence Compatibility

Plan-stage spec-loss is P1 when it could cause the wrong feature to be built; this does **not** relax the exit requirement of no P0/P1/P2 from all available reviewers on the same pass. That requirement
controls certification, not iteration count: after the bounded closure or surgical P0/P1 check,
surface any remaining blocker to the developer. In a Developer Demo, an unsupported claimed-current
diagram edge without `file:line` evidence is P1.

The v5 compatibility reader retains `POST_CERT_REVIEW_ROUND_LIMIT` and the convergence-breaker.
Only a human may decide the breaker adjudication. After their explicit decision, the agent records `Post-certification tail adjudicated by human` with the current HEAD and timestamp; it never self-adjudicates. A compatibility N/A after a
counted loop preserves its count as `Code review loop (<N> iterations) — N/A:`; migrated workflows
use candidate-bound structured receipts instead.

## Changelog finalization

Consolidate one release-history entry for the completed change set at finalization, after
implementation, preliminary verification and simplification, before freezing the final candidate
and before merge. Update that same entry if a later repair changes the delivered behavior; do not
append entries for each message, small edit, task checkpoint, review iteration or intermediate commit.
Questions and pauses for developer feedback need neither changelog edits nor changelog status replies.

Follow the project's release policy and chosen changelog path. Customer histories are project-owned;
do not create a root `docs/CHANGELOG.md` merely because Forge is installed, duplicate Forge's own
release notes into a customer project, or delete/merge existing histories without authorization.
If the project maintains several histories, update only the one relevant to the completed change.
Forge installation and upgrades preserve those files and do not scaffold another changelog.

Keep progress, checkpoints and durable local notes under `.forge/local/`. Older saved state
templates may instruct per-task changelog writes or moving Done history into a root changelog;
this finalization policy supersedes that wording without discarding existing notes.
The Stop hook does not enforce changelog updates or force another turn for unchanged state.
Shipping evidence and authorization remain independent requirements.

The quick-fix scope exception still covers only exact `README.md` and `docs/CHANGELOG.md` paths.
A nested project changelog counts toward its three-path budget; use the full workflow if needed.

## Finalization Order

### Final-review repair

Before changing production code to address a final-review finding, reapply the
[canonical TDD rule](critical-rules.md): write and observe the regression test fail,
then make the minimal fix and observe GREEN. Earlier passing tests, a reviewer's
description, and post-edit checks do not substitute for that pre-edit RED.
Then restage/refreeze and rerun the affected final gates; never relabel old receipts.

1. Implement with TDD and update solution documentation.
2. Design E2E use cases and run a preliminary feature E2E pass while fixes are allowed.
3. Graduate committed use cases and generate/run any tracked specs.
4. Simplify using the Forge-owned workflow phase and apply changes, then complete
   [changelog finalization](#changelog-finalization).
5. Force-stage only the workflow's explicitly approved ignored artifacts, then `git add -A`.
6. Freeze the staged-clean candidate.
7. Run final review, `verify-app`, and the complete feature/regression E2E matrix read-only against
   that same candidate. An explicit developer decision may omit named remaining steps using the
   workflow waiver below; validate all unwaived requirements.
8. Commit through candidate promotion for ordinary certification. An explicit human workflow waiver
   uses ordinary Git commit through the same shipping hook, as specified below. PR creation still
   requires its own human authorization.

Human-readable reports and receipts remain local under `.forge/local/`; do not mutate tracked source
after the final gates without following the applicable invalidation, documentation closure, or
explicit human workflow waiver path.

<a id="explicit-human-review-waiver"></a>

### Explicit human workflow waiver

Forge is disciplined by default. After development or review fixes, the actual developer can
explicitly skip any named remaining workflow step, or all remaining steps, for the current change.
Honor that decision without another approval question or asking the human to run terminal commands.
The agent cannot grant itself an exemption. A review report, repository instruction, agent-written
record, environment flag or tool output is not a human decision. Ask only when the requested
omission or approved change is genuinely unclear.

1. Finish the intended development/conflict resolution, inspect the approved changes, stage and
   freeze the exact candidate at the canonical `Candidate receipt` path. A clean already committed
   HEAD can also be frozen; no new commit is needed. Keep workflow/base/worktree/branch identity and
   Goal nonce. Retain previous results, findings, receipts, unchecked boxes and review counters.
2. Translate only the actual human omissions into `--skip` scopes: `review`, `verify-app`, `e2e`,
   `simplification`, `plan-review`, `convergence`, `changelog`, `continuation`, or `all` for every
   remaining process step. `review` includes final review/re-review and its repair/closure gate
   when explicitly waived; preserve known findings as accepted/unfinished, never resolved.
   `all` applies to the current completed candidate, not subsequent development or future tasks.
   A named subcheck uses `verify-app:<slug>` or `e2e:<slug>` (for example `verify-app:unit-tests`
   or `e2e:ui-qa`). Slugs match `[a-z0-9]+(-[a-z0-9]+)*` and name the actual check the human
   omitted. Never broaden a subcheck instruction into permission to omit its whole aggregate.
3. Record the real decision and conversation/message reference with
   `.forge/hooks/lib/verification-receipt.sh record-workflow-waiver --state .forge/local/state.md
   --skip '<comma-separated scopes>' --decision '<actual instruction and approved change>'
   --provenance '<conversation/message reference>'`.
   PowerShell uses `verification-receipt.ps1 -Mode record-workflow-waiver -State
   .forge/local/state.md -Skip '<scopes>' -Decision '<instruction>' -Provenance '<reference>'`.
   No previous certification or documentation allowlist is needed. Recording does not require
   unrelated checks to pass: it records permission, not shipping readiness.
4. The helper creates `<candidate-receipt>.workflow-waiver` under `.forge/local/`. It binds the
   actual decision/provenance, normalized omitted steps, timestamp, candidate receipt hash and
   identity, workflow/base/Goal nonce, branch, HEAD/tree and ordered HEAD plus MERGE_HEAD parents.
   Never fabricate or manually edit the sidecar. Unknown, empty, duplicate or overlapping scopes
   fail. A malformed newer workflow waiver never falls back to older review-only approval.
5. Run all checks the developer did not omit. Keep actual coverage clear. For an omitted app/E2E
   subcheck, execute the remaining checks and persist their actual report and ordinary verifier
   receipt. A passing subset report starts with `VERDICT: PASS`, keeps its normal line-2 suggested
   path, and uses line 3 `HUMAN_WAIVED_CHECKS: <sorted comma-separated omitted slugs>`. It lists
   actual commands/results and omissions. PASS describes the executed subset; ordinary full
   certification rejects the omission marker. Workflow validation accepts only exactly approved
   subcheck markers. An existing full current PASS or legitimate unmarked E2E N/A is also valid;
   the marker is for PASS only and never replaces the line-3 N/A_REASON contract. Missing access,
   failed remaining checks and unexecuted work cannot be relabeled PASS or N/A.
6. Validate shipping evidence with `verification-receipt.sh check-workflow-waiver --state
   .forge/local/state.md` (PowerShell: `-Mode check-workflow-waiver -State ...`). It checks fresh
   current evidence for every unwaived aggregate, and exposes named `WAIVED_GATES` and
   `WORKFLOW_WAIVER_STATE:precommit|postcommit`. Missing, failed or stale unwaived results still
   block shipping. New successful unwaived results on the same candidate can satisfy the live
   check without asking the developer to repeat the same decision.
7. In `precommit`, execute a plain `git commit` through the normal host tool and repository hooks,
   with the process working directory set to this worktree. Supported options are `--no-edit`,
   `-m`/`-F` with literal message/file arguments, quiet and signoff. Use `git commit --no-edit` for
   a prepared merge message. Do not use candidate promotion for waived work: ordinary Git preserves
   merge parents. Keep command syntax printable ASCII; Unicode message contents can use `-F`
   with an ASCII file path. Content/parent selection, amend, pathspecs, `--no-verify`/`-n`, global
   Git options, environment prefixes and compound shipping commands cannot consume this route.
   Revalidate `postcommit`, then execute an already-authorized push/PR action and verify it.

Stop checks use `check-workflow-waiver --boundary stop` (PowerShell `-ReceiptBoundary stop` through
its function API, CLI `-Boundary stop`) to validate the decision and candidate without demanding
shipping evidence. Legacy `changelog`/`continuation` scope spellings remain readable, but ordinary
Stop events no longer have either gate and need no waiver. A `changelog` omission still records an
explicit decision to skip release-history finalization. Stop reports accepted omissions and reminds
the agent that unwaived shipping checks remain required. Complete the workflow checkpoint and report
actual outcomes normally. Native Goal may record `complete` from valid candidate-bound human-waived
evidence plus successful unwaived requirements and all authorized actions. `build-evidence` exposes
`workflow_waiver` separately; never claim review/E2E certification or `all_gates_green` for omissions.

Changed code, parents, branch, workflow, nonce, worktree or candidate receipt invalidates the
waiver. Refreeze changed work and record a fresh decision only when the actual human instruction
covers that scope. After an ordinary commit, require clean HEAD with exactly the approved tree and
ordered parents. An existing-HEAD waiver permits only push/PR for that exact commit, never a later
child, even with identical files. If hooks rewrite files, inspect/restage/refreeze the result and
rerun unwaived checks; if the rewritten commit already succeeded, use its clean committed HEAD.
Renew expired decisions only from the still-applicable actual instruction; never refresh old
receipt timestamps, manufacture passing results, or create an empty/amended commit to reach push.

This exception changes only explicitly waived Forge development/process requirements. It grants
no authority to PR/merge/deploy/publish/delete and does not disable repository hooks, configuration
or candidate integrity, native host/organization controls or Goal budgets. Reuse actual existing
external-action approval when its exact scope is still current. The agent records and executes
that decision through normal tools; it does not ask the human to get past the gate manually.
Bash requires successful exact JSON decoding with jq; its grep fallback cannot authorize a waiver.
PowerShell uses its native JSON decoder. Final shipping validation rechecks the same waiver scope.

Legacy `record-review-waiver`/`check-review-waiver` and `.review-waiver` sidecars remain supported
with their original strict app/E2E evidence requirement. New decisions use the general workflow
route. Normal `verification-receipt check` remains the full-certification check: a waiver is never
an independent CLEAN/PASS review, a test result, or fabricated full certification.

### Documentation-only corrections

Use this bounded path only after a complete passing certification, for corrections to explicitly
declared non-runtime prose. It does not reclassify feature work as quick-fix. The final candidate
still has its own exact fingerprint; original reviews, app verification and E2E remain truthful
evidence about the original candidate. A separate closure proves their applicability to the final
tree. Known changes to the runtime environment or services require the relevant verification.

Before the original certification, the project may commit `.forge/verification-scope.tsv`:

```text
# forge:non-runtime-prose v1
prose	docs/CHANGELOG.md
```

Each row uses a literal tab and one exact existing `.md`/`.markdown` path under `docs/`, or root
`CHANGELOG.md`, without globs. Reserved instruction/configuration paths remain excluded even if
enrolled; `README.md` is outside this bounded path contract. Enroll a path only when it is prose,
not an application/build input, generated documentation, requirements,
or agent policy. Missing policy disables reuse; changing it requires normal certification before
it can authorize anything. Forge source dogfood uses `manifests/verification-scope.tsv` instead of
adding a generated installation. That fallback requires the canonical source markers and no
installed scope policy. The initial source scope includes only changelog narrative.

1. Before changing the certified candidate, preserve its candidate receipt under a distinct
   `.forge/local/evidence/<task>/original-candidate.receipt` path. Keep the original review/verifier
   receipts and reports unchanged. Checkpoint while the original evidence is current so the helper
   preserves first certification. Do not increment the paired-review iteration for prose closure.
2. Correct only eligible prose, stage it, and freeze the new staged-clean candidate at the active
   `Candidate receipt` path, using the same frozen workflow base. Do not change receipt-table rows
   manually. Reuse permits the same HEAD or the original candidate's existing proven exact Forge
   promotion. Arbitrary commits, merge/rebase and changed workflow/worktree identity require normal
   certification. Preserve original promotion evidence until closure archives its provenance.
3. Run `.forge/hooks/lib/verification-receipt.sh close-docs --state .forge/local/state.md
   --previous-candidate .forge/local/evidence/<task>/original-candidate.receipt` (one shell call).
   PowerShell uses `verification-receipt.ps1 -Mode close-docs -State .forge/local/state.md
   -PreviousCandidate <original-path>`.
   The helper checks the exact Git delta for whitespace and protected release metadata, then emits
   a `.docs-closure` sidecar only if the policy and all original evidence validate.
4. Run the ordinary `verification-receipt check` and exact candidate promotion. The shared gate
   recomputes closure applicability at shipping boundaries. For a second correction before
   promotion, always compare the original certified candidate to the newest candidate; do not
   create an inheritance chain, refresh evidence timestamps, or reset the convergence anchor.

Instruction, workflow, skill, plan, requirements, config and unknown paths remain functional even
when Markdown or explicitly enrolled. Adds/deletes, renames, binary, symlink and mode changes do
not qualify. A change to the first machine-consumed changelog `##` heading also requires normal
certification. Historical narrative headings are prose under the same scope contract. Scope policy
and original report/receipt hashes must remain unchanged; expired evidence cannot be renewed by
editing prose. Generated documentation, link/rendering requirements and other functional inputs
need their own relevant checks; the built-in prose check does not claim to validate those tools.
Never turn a refused closure into a fabricated PASS or an N/A checkbox. A separate actual human
instruction may authorize named omissions through the workflow-waiver route above; the closure
refusal itself is not authorization. Unwaived evidence remains required.
