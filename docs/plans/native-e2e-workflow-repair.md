# Native E2E workflow repair

## Scope and approval

The developer approved repairing four failures observed in the real Pocket Tasks
workflow matrix. This continues the existing isolated repair worktree; preserve the
staged reviewer-proxy fix and the immutable failed baseline at
`/private/tmp/forge-app-e2e.B9XAhU/observer/`. No push, PR, or merge is authorized.

Immutable base ref recorded by the active workflow: `HEAD`.
Immutable base SHA: `8c63954b5fd1f67f2a3ae21ea0cd82f2c9777ccc`.

## Reproduction and proven causes

1. Five completed native cases promoted the exact frozen tree, but subsequent
   verification rejected the changed HEAD. `verification-receipt` only compares
   the current fingerprint; it never consumes the existing promotion linkage.
2. Claude performed discretionary investigation before activation. Its prescribed
   shell worktree creation then hit protected native configuration paths, leaving
   no active task checkpoint. A shell permission denial is not permission to
   reconstruct native files through a different transport.
3. Both materializers hard-code `Read, Grep, Glob, Bash` for every Claude agent.
   This removes the producer's canonical Write/Edit tools and excludes all browser
   MCP tools from the verifier.
4. The outer ship hook parses legacy review wording before validating V6 receipts.
   An A3 checked review line without the literal PASS was rejected despite valid
   candidate-bound evidence. Checklist presentation must not be a second V6
   certification authority.

## Minimal changes and RED/GREEN checks

### 1. Consume the existing promotion receipt

Extend only final receipt **checking** to accept either the current frozen
candidate or its strictly validated promotion. Keep receipt writing and new
review capture bound to a current staged-clean candidate. Never rewrite old
evidence to pretend it reviewed a new HEAD.

Validate the unique state-linked, Forge-local promotion receipt: schema, old
candidate ID, old HEAD, worktree identity, new commit, temporary commit, exact
tree, successful/no post-commit hook, and clean post-commit status. Recompute
the old candidate ID. Require current HEAD to equal the promotion commit with
exactly one parent equal to the old HEAD. Current worktree identity, base,
index tree, and clean tracked/untracked state must still match. Existing review
freshness, iteration, report hashes, and distinct-lens checks remain mandatory.

Extend the actual promotion tests, not a mocked fingerprint. Before the fix,
assert the observed post-promotion check fails; after it, assert SHIP_READY and
the non-publishing simulated ship hook pass. Negative controls cover missing or
wrong promotion linkage, extra commits, dirty/staged/untracked changes, altered
reports, and failed post-commit hooks. Bash and PowerShell implementations mirror
one contract; exercise PowerShell runtime only if available and disclose otherwise.

### 2. Receipt-native outer gate

Use canonical V6 state/active workflow to select structured certification, not
presence of a candidate path. Bypass only legacy **code-review PASS wording and
code-review HEAD evidence** parsing for V6. Retain the existing unchecked workflow
gates, especially Simplified (no receipt equivalent), plan review plan_sha binding,
authorization, and convergence checks. Missing or malformed V6 receipt linkage
must fail closed. Keep existing legacy behavior for any supported legacy path.
Test ordinary alternate checked code-review prose with valid receipts, and the
same prose with missing or mutated evidence. Keep incomplete simplification blocked.

Preserve convergence using the existing unique V6 `Review iteration` and
helper-owned `First certified iteration`, rather than a count embedded in
checklist prose. After certification, absent, ambiguous, invalid, or backward
canonical counts must block. Keep the existing limit and head-bound human
adjudication; retain legacy counting only for pre-V6 state. No new counter or
state writer is needed.

### 3. Canonical Claude agent capabilities

Have Bash and PowerShell materializers derive agent capability frontmatter from
the canonical agent source rather than another role-specific policy table.
Producer tools remain exactly its declared Read/Grep/Glob/Bash/Edit/Write set.
When neither tools nor disallowedTools is declared, preserve the existing default
Read/Grep/Glob/Bash set: verify-app and research-first therefore retain exactly
their current adapters, with no Write/Edit or implicit MCP expansion. Existing
explicit canonical tool restrictions remain authoritative. Give verify-e2e documented access to
host-provided browser tools without implementation-edit tools; use Claude's
supported tool inheritance/disallow semantics where browser MCP names vary.
Add canonical disallowedTools for Write, Edit, and NotebookEdit to verify-e2e,
leaving tools absent to request inheritance for this role only. This does not
make Bash or browser MCP a technical read-only sandbox: no source modification
remains the canonical verifier's behavioral rule under the host's normal security
controls. Do not claim stronger enforcement than the tool policy provides.
Do not change permissionMode or reviewer approval/security controls.

Test generated adapters from a real disposable materialization, including
verify-app/research-first non-expansion controls, an explicitly restricted agent,
and verifier restriction/inheritance. Official contracts:
[Claude subagents](https://code.claude.com/docs/en/subagents) documents explicit
tools versus inherited tools/MCP and disallowedTools. Native browser availability
still requires a live session check; textual frontmatter is not browser E2E proof.

### 4. Activation-first native startup

Keep one canonical startup procedure shared by new-feature, fix-bug, and
quick-fix. Restrict pre-activation activity to instruction/state discovery and
deterministic branch/base setup; no symptom investigation, app reads, or task
implementation before activation. Prefer an already isolated exact worktree;
never create another on handoff. Only new-feature and fix-bug require worktree
creation when isolation is absent; quick-fix retains its non-protected branch
policy without creating a worktree. Support only documented native worktree
creation/adoption where the host provides it, followed by the existing seed and
activation contract. If native protection prevents setup, stop before task work
and preserve an honest setup blocker/next action without fabricating active state
or bypassing denied writes. No new orchestrator, permission bypass, duplicate
state store, or hidden-config migration is in scope.

Check the current official [Claude Desktop documentation](https://code.claude.com/docs/en/desktop)
and record concrete native capabilities before changing this procedure. Any
required new harness ownership/copying mechanism is a separate design decision,
not an inferred repair. Use focused startup contract tests plus fresh native
sessions to determine whether the environmental blocker is actually resolved.

## Expected changed paths

- `hooks/lib/verification-receipt.{sh,ps1}` and owning receipt/promotion tests.
- `hooks/check-workflow-gates.{sh,ps1}` and owning hook/receipt integration tests.
- `hooks/lib/review-breaker.{sh,ps1}`, existing counter contract prose, and focused
  convergence controls.
- `scripts/materialize-adapters.{sh,ps1}`, Claude agent template, canonical
  verifier capability frontmatter, and owning materialization tests.
- `rules/workflow.md`, thin workflow startup references, and focused contract
  tests as justified by the native startup research.
- This plan, the bounded research brief, and `docs/CHANGELOG.md`.

## Verification and user journeys

Run fresh plan review against git:working-tree before implementation. Use small
RED/GREEN tests for each failure, a bounded producer invocation, then owning
suites and a single full aggregate after final bytes freeze. Preserve prior
proxy tests. Final paired reviews and verify-app must name one final candidate.

Rerun new-feature, fix-bug, and quick-fix in both Claude-to-Codex and
Codex-to-Claude directions in new disposable copies. Use ordinary Pocket Tasks
requests, installed workflows, and fresh native sessions, not receipt coaching.
Observe browser journeys sequentially to avoid shared UI/profile/port contention.
Verify task persistence, completion across reload, and the requested label change;
record activation order, handoff continuity, review/tool availability, exact-tree
promotion, post-promotion gate, and mutation invalidation. Never execute a push
as a negative gate test. Keep deterministic checks separate from native E2E
results and environment limitations; do not claim full E2E if any case is blocked.

## Broad plan review disposition

- F-1/P2: narrowed the outer bypass to code-review wording/HEAD only; preserve
  Simplified, plan binding, authorization, convergence and unchecked gates.
- F-2/P2: explicitly preserve restricted defaults for verify-app/research-first.
- F-3/P3: document that inherited Bash/MCP is not a read-only security sandbox.
- F-4/P3: add actual post-promotion simulated push and post-mutation hook checks.
- F-5/P3: add a conditional PowerShell runtime check to the existing Bash fixture
  so a Windows PowerShell runner exercises the promoted receipt path; unavailable Windows runtime
  remains a disclosed runtime verification gap, not a claimed PASS.
- F-6/P3: add wrong-worktree and wrong-old-candidate-id promotion controls.

Closure review is limited to these findings and their direct regressions.

## Final review and integration repair boundary

The first final paired review found three material closure items: the V6
convergence count still depended on legacy prose, PowerShell's missing-promotion
fallback omitted normal false status output, and shared startup contradicted
quick-fix worktree policy. Repair those within the existing primitives above.
The first aggregate also exposed five stale assertions and fixture reporting
whose exit status was overwritten by helper definitions. Correct the assertions
without weakening rejection, and make the existing fixture report return its
actual status. Preserve that failed run and both original review outputs.

After the bounded repair, run focused and fast checks, freeze the revised
candidate, and obtain one scoped paired closure before the final aggregate and
new native matrix. Static PowerShell parity is not Windows runtime proof.

## Approved repair after the six-case a919c166 matrix

The developer approved these four bounded repairs after the completed matrix
returned one workflow PASS and five FAIL. Preserve that candidate's report and
receipts unchanged under `.forge/local/evidence/reviewer-proxy-handoff/` and the
observer directory `/private/tmp/forge-app-e2e-repaired.UJt8ON/observer/`.
The base SHA above is unchanged. No new framework, permission expansion, source
commit, push, PR, or merge is authorized.

1. Engine-neutral plan evidence: accept a delimited actual `claude clean` or
   `codex clean` label, including ordinary indented Markdown continuation lines.
   Preserve iteration and current plan SHA checks, missing/malformed/stale evidence
   rejection, and all structured final gates. Update the canonical state example
   to require the actual reviewer engine; never relabel existing receipts. Exercise
   both valid labels and wrapped rows through the real outer gate, with stale-hash
   and malformed-label controls. Include the same consumer in
   `hooks/build-evidence.{sh,ps1}` and its owning test. A folded row must never
   import evidence from another checklist row, iteration or section. Mirror Bash
   and PowerShell.
2. Read-only receipt identity: use the existing fingerprint `identity` operation
   for current and promoted candidate validation. Keep schema-v2/staged-clean input
   checks and every identity/promotion linkage comparison. Freeze remains the
   explicit candidate-writing operation. Test with source Git object writes denied,
   using the real fingerprint and verifier, before and after promotion; checkpoint
   must latch the first certified iteration. Existing mutation rejection remains.
3. Non-blocking P3: preserve reviewer envelopes and findings rather than rewriting
   old evidence. Both CLEAN/NONE, CLEAN/P3 and schema-valid FINDINGS/P3 are certifying
   outcomes; FINDINGS/P0/P1/P2, BLOCKED and malformed results are not. Make dispatcher
   pair validation, final receipt validation and canonical reviewer/controller
   instructions agree. Retain all candidate, output-hash and severity consistency
   checks. Explicitly reject FINDINGS/P3 envelopes containing any P0/P1/P2 finding
   at ingestion and at both pair and final receipt validation, inspecting the
   hash-bound output rather than trusting its maximum-severity label. Require at
   least one P3 finding for FINDINGS/P3; missing or contradictory output blocks.
   Pair validation must explicitly enforce the certifying set (repair the Bash
   short-circuited guard), not merely widen its condition. Mirror repairs 2 and 3
   in PowerShell as well. Tests exercise the real dispatch/verification boundaries
   with controlled reviewer output; no fallback is permitted merely because a
   valid finding exists.
4. Final-review production repairs: at the shared repair transition explicitly
   reapply canonical TDD (observe the regression fail before production edits),
   with thin references from workflows if needed. B1's native missed RED is the
   baseline; validate the changed prompt with a fresh native repair scenario.
   No text-grep assertion is a substitute for that behavioral test.

Use focused owning checks for each change, then one aggregate on frozen final
bytes, paired final reviews and affected native regression cases. Keep Windows
runtime and Codex GUI unverified unless actually executed. Preferred Codex reviewer
qualification remains a separate unresolved investigation, not part of these fixes.

## Approved Codex reviewer compatibility follow-up

The developer authorized this bounded follow-up after the fresh Claude repair
control. Both Codex review attempts returned BLOCKED/capability with all three
observations `unobserved`; the dispatcher reported `isolation-canary-mismatch`.
The shared prompt incorrectly says shell access is absent although Codex retains
its read-only command tools. Claude instead receives Read/Grep/Glob. V5.61 used
native `codex exec review` and did not impose that contradictory instruction.

A controlled replay keeps the frozen Pocket Tasks snapshot, model, effort,
read-only sandbox and review request unchanged, varying only that sentence.
The old prompt passed on replay: the failure is intermittent, so this does not
prove that wording alone caused the original failures. Preserve both historical
failures and both fresh outcomes; do not claim a deterministic prompt RED/GREEN.
Evidence directory: `/private/tmp/forge-codex-read-probe.N4Z28p/`.

Smallest repair, with unchanged base SHA and no permission expansion:

- In `hooks/lib/agent-dispatch.{sh,ps1}`, remove the inaccurate shared no-shell
  claim. For Codex ordinary reviews, explicitly direct read-only inspection via
  its available command tool, limited to the primary and candidate root, with no
  edits or network commands. Keep Claude's existing tool allowlist and all engine
  flags, sandbox, candidate and observation checks unchanged. Do not contradict
  the separate dispatcher-owned reproduction runner instruction.
- Classify literal `unobserved` canary evidence as `isolation-canary-unobserved`,
  still a capability failure eligible for the existing fallback. Missing or wrong
  observations continue to fail closed; a claimed CLEAN with unobserved evidence
  cannot certify. Preserve raw reviewer output; do not fabricate observations.
- Extend the existing deterministic dispatcher suite and external-engine fixture
  to replay the actual BLOCKED/unobserved envelope. Observe the diagnostic
  assertion fail before the implementation. Cover automatic fallback and no-
  fallback failure, plus wrong-canary and false-CLEAN controls. Add equivalent
  PowerShell cases; Windows execution remains unverified locally.
- Test the prompt with the real consuming Codex process, not text-grep assertions.
  Run a fresh real dispatcher review after implementation to confirm accepted
  observed evidence without fallback, and a Claude control for non-regression.
  This is reviewer integration testing, not a new six-case native GUI matrix.

Run focused dispatcher and static parity checks, then the fast suite. Review the
scoped final changes and preserve stale prior candidate receipts. Do not claim
branch SHIP_READY or commit/push/PR; full branch recertification remains pending.
