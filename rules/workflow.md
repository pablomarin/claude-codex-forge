# Workflow Rules

## Choose the Smallest Matching Workflow

| Need | Canonical workflow |
|---|---|
| New capability | `/new-feature <name>` |
| Reproduce and fix a defect | `/fix-bug <name>` |
| Trivial, low-risk change under the quick-fix limits | `/quick-fix <name>` |
| Fresh second opinion or code review | Claude: `/opinion <request>`; Codex: `$opinion <request>` |
| Investigation with disposable write/network capability | Claude: `/opinion investigate <request>`; Codex: `$opinion investigate <request>` |
| Resolve engineering ambiguity | `/council <question>` |
| Process PR feedback | `/review-pr-comments` |
| Merge and clean up after approval | `/finish-branch` |

The current host is the main agent for the session. Resolve it through the installed host adapter;
never persist a permanent main-engine preference. Reviewer `auto` selects the other installed
engine and automatically falls back to a fresh same-engine reviewer when launch/capability failure
occurs. A finding is a review result, not a fallback reason.

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
P2 means a concrete material maintainability, reliability, performance, or test risk, not a merely
imaginable rare case. Rare but catastrophic security or data loss triggers remain P0/P1. Resource
discipline never excuses reachable security failure, data loss, incorrect supported behavior, or an
explicit acceptance criterion.

During repair, run focused owning checks. Run one complete aggregate after the final bytes freeze;
do not mechanically restart unrelated verification. A mutation invalidates only evidence whose
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
workflow control rows: use `workflow-state.sh activate` once in a new task worktree and
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

Every development workflow follows this state machine; receipt population records progress and
never activates a mode:

1. **Activate:** resolve and persist the immutable workflow base ref/SHA, create one task-local
   `.forge/local/` evidence directory, populate every receipt path, and set `Review iteration` to
   `0`. Invoke `.forge/hooks/lib/workflow-state.sh activate --host <claude|codex> --workflow
   <new-feature|fix-bug|quick-fix> --task <slug> --base-ref <ref-or-sha> --phase <phase>
   --next-step '<exact next step>'` before any discretionary investigation or tracked mutation.
   The active V6 schema selects structured evidence immediately. An identical in-flight V6.1
   placeholder bundle is adopted by this activation; partial or conflicting bundles fail closed.
2. **Plan before code:** for planned feature and bug work, obtain clean candidate-bound plan evidence
   before production implementation. Quick fixes must record their acceptance check before editing.
3. **Exercise early:** run preliminary E2E while mutation is still allowed, or record why no
   supported user journey exists; this is not final certification.
4. **Freeze:** finish TDD, documentation, and simplification; stage the intended tree and freeze one
   staged-clean candidate.
5. **Review:** invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex> --phase
   review --next-step '<exact next step>' --begin-review` before dispatch, then run distinct fresh
   `code-spec` and `code-quality` lenses against the same candidate and iteration.
6. **Verify:** run `verify-app` and E2E against that same candidate and write their structured
   receipts. E2E N/A requires its candidate-bound report and reason.
7. **Invalidate on change:** Any candidate mutation invalidates the final review and verifier
   receipts. Restage, freeze a new candidate, increment the iteration before review, and rerun the
   affected final gates.
8. **Promote:** revalidate the complete receipt set and promote only the exact certified tree.

At every other durable boundary, invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host
<claude|codex> --phase <phase> --next-step '<exact next step>'`. End a completed workflow with the
exact terminal transition `workflow-state.sh checkpoint --host <claude|codex> --phase complete
--next-step none`; only that terminal pair permits a new activation. On Windows, use the `.ps1`
twin with the same action and arguments.

- Research current documentation before design when a library, API, or provider is involved.
- Compare viable approaches and send genuine ambiguity to `/council`.
- Freeze the exact staged-clean candidate before final review or verification.
- Dispatch fresh independent `plan`, `code-spec`, and `code-quality` roles through the installed
  structured dispatcher. Automatic fallback is visible in its receipt.
- Code review requires distinct clean `code-spec` and `code-quality` receipts for the same candidate.
- `verify-app` and `verify-e2e` each write a candidate-bound verification receipt. Missing execution
  or access is `BLOCKED`/`UNVERIFIED`, never PASS.
- Any candidate mutation invalidates affected receipts and restarts from staging/freeze.

The compatibility reader may consume genuine unmigrated v5 state. Every active canonical V6
workflow uses the current structured receipts; legacy prose never certifies a migrated gate.

## Autonomous Goal Composition

Forge composes the active host's native `/goal`; it does not install or shadow a native goal
command/skill and does not claim native sessions transfer. `.forge/local/state.md` is authoritative
for the objective, nonce, persistent budget ceiling, consumed durable turns, checklist, next step,
candidate, evidence, authorization, and terminal status. Native counters may reset; Forge counters
may not.

The council resolves non-destructive workflow judgment without pausing. Stop autonomy for:

- explicit user input or authorization/cancellation;
- PR creation or any other new external mutation requiring human authority;
- a security-sensitive or irreversible action;
- a broken invariant, exhausted persistent budget, or unresolved convergence blocker.

PR creation requires a human-created authorization record bound to the active nonce and candidate.
Ordinary reviewer/council engine failure uses automatic same-engine fallback and does not stop the
workflow. If the active host cannot compose every Must goal behavior, mark runtime readiness
`BLOCKED` rather than silently reducing the contract.

### Council During Autonomous Goal

Use `/council` for non-PR doubts. PR creation authorization remains human-only. Ask-tier commands stall autonomous runs, so surface the deterministic action and pause instead of hiding a prompt.

### Severity and Convergence Compatibility

Plan-stage spec-loss is P1 when it could cause the wrong feature to be built; this does **not** relax the exit requirement of no P0/P1/P2 from all available reviewers on the same pass. That requirement
controls certification, not iteration count: after the bounded closure or surgical P0/P1 check,
surface any remaining blocker to the developer. In a Developer Demo, an unsupported claimed-current
diagram edge without `file:line` evidence is P1.

The v5 compatibility reader retains `POST_CERT_REVIEW_ROUND_LIMIT` and the convergence-breaker.
Only a human may record `Post-certification tail adjudicated by human`. A compatibility N/A after a
counted loop preserves its count as `Code review loop (<N> iterations) — N/A:`; migrated workflows
use candidate-bound structured receipts instead.

## Finalization Order

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
