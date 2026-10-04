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

If the matching task is already active in this physical worktree, checkpoint the displayed host,
phase, and exact next step, then resume that step in the same directory.
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
boundary it can affect, while exact-candidate receipts still require the same final fingerprint.
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

## Plan, Review, and Evidence

### Canonical V6 state transitions

Feature and bug-fix workflows follow this full-certification state machine; receipt population
records progress and never activates a mode:

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
8. **Invalidate on change:** Any candidate mutation invalidates the final review and verifier
   receipts. Restage, freeze a new candidate, increment the iteration before review, and rerun the
   affected final gates.
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
- Code review requires distinct clean `code-spec` and `code-quality` receipts for the same candidate.
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

## Finalization Order

### Final-review repair

Before changing production code to address a final-review finding, reapply the
[canonical TDD rule](critical-rules.md): write and observe the regression test fail,
then make the minimal fix and observe GREEN. Earlier passing tests, a reviewer's
description, and post-edit checks do not substitute for that pre-edit RED.
Then restage/refreeze and rerun the affected final gates; never relabel old receipts.

1. Implement with TDD; update solution and changelog material.
2. Design E2E use cases and run a preliminary feature E2E pass while fixes are allowed.
3. Graduate committed use cases and generate/run any tracked specs.
4. Simplify using the Forge-owned workflow phase and apply changes.
5. Force-stage only the workflow's explicitly approved ignored artifacts, then `git add -A`.
6. Freeze the staged-clean candidate.
7. Run final review, `verify-app`, and the complete feature/regression E2E matrix read-only against
   that same candidate.
8. Commit only through candidate promotion. PR creation remains a separate human pause.

Human-readable reports and receipts remain local under `.forge/local/`; do not mutate tracked source
after the final gates. A mutation returns to step 5 and repeats all affected final gates.
