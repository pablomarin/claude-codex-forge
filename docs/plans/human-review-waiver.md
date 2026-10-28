# Explicit human review waiver

Status: implementation following one broad design challenge and one closure.
Missing waiver APIs were reproduced before production edits. The final review
must verify the implemented command-decoding condition identified in closure.

The developer reported that Ganadoven PR #27 could not finish after an approved
changelog conflict resolution. Merging main also changed package/test files, so
the existing predeclared prose closure could not apply. The agent required the
human to commit/push manually despite explicit instructions to skip re-review.
The developer clarified that the remedy must cover any explicitly approved change.

Base: `0f844f0d601a86008ea4abe5c7f619028ca2e0fe` (ref `0f844f0`).

## Root cause and minimal repair

The shipping hook requires a fresh complete candidate receipt set. Human
adjudication only releases the convergence breaker. There is no truthful route
for a human to waive independent code review. Exact candidate promotion also
creates only one parent and cannot replace an ordinary merge commit.

Add `record-review-waiver` and `check-review-waiver` to the existing Bash and
PowerShell verification-receipt helpers. Keep normal `check`, docs closure,
review receipts and certification counters unchanged. The waiver is separate
authorization, never a passed review or `SHIP_READY:true` certification.

Recording requires an actual human instruction and conversation provenance,
the current staged-clean frozen candidate, fresh successful verify-app and E2E
receipts (including supported E2E N/A). The main agent may run and record these
focused checks directly; a waiver does not justify a fabricated PASS or N/A.
The helper records a local sidecar at the candidate receipt plus `.review-waiver`,
binding candidate bytes/identity, branch ref, workflow command/base, active Goal nonce,
HEAD/tree, ordered HEAD plus MERGE_HEAD parents, timestamp, human decision,
provenance, and verification receipt hashes. Reuse existing strict parsing,
local path, hash and verifier validation helpers.

Before commit, require the same staged-clean candidate and ordered parents.
After an ordinary commit, require clean HEAD with exactly the approved tree and
ordered parents, preserving merge ancestry. Another edit, commit, workflow,
nonce, worktree or altered evidence invalidates the waiver. No blanket flag or
hook disabling is introduced. Do not route this through candidate promotion.
When the frozen candidate is already committed at clean HEAD, its tree equals
HEAD's tree and no MERGE_HEAD exists, record its existing HEAD binding and report
postcommit immediately. Only push/PR may consume it; commit is rejected and any
later child, even with the same tree, invalidates it. This permits fresh
verification and a new scoped waiver after expiry, a manually committed merge,
or a pre-commit hook that changed the successfully committed tree. Do not relabel
expired receipts or require an empty/amended commit. No new schema or state row.
Allow only plain `git commit` with `--no-edit`, message/file options with literal
values, and optional quiet/signoff flags. Decline the waiver for all other forms,
including amend, pathspec/content selection, `--no-verify`/`-n`, environment
prefixes, global `-c`/`-C` options and hook-path overrides. Execute from the exact
task cwd. Command syntax is printable ASCII; Unicode commit-message contents use
`-F` with an ASCII file path. Do not weaken existing normal gates for rejected forms. This admits
ordinary repository-hook execution while preserving approved tree and parents.
Bash may apply the waiver only when jq successfully decodes the complete event
JSON; its legacy grep fallback cannot establish waiver command eligibility.
PowerShell uses its native JSON decoder. Cover missing jq with a rejection test.
Expose precommit/postcommit waiver state: only commit may consume precommit;
push/PR may consume only the exact resulting postcommit. A waiver never approves
pushing the old HEAD while the candidate remains staged.

The shipping hooks validate the waiver after configuration, command, PR authority
and convergence checks. Only the review checklist item and final independent
review requirement may be waived; other checklist gates and verification remain.
The valid waiver path is visibly reported as human-waived review. It cannot
authorize PR creation, merge, publication, deletion or override native controls.

## Files and acceptance

- `hooks/lib/verification-receipt.{sh,ps1}`: record and validate the bounded waiver.
- `hooks/check-workflow-gates.{sh,ps1}`: consume it without changing normal gates.
- `tests/template/test-human-review-waiver.{sh,ps1}` and suite registration:
  reproduce the blocked merge before implementation; verify commit/push afterward.
- Canonical instructions, workflow rules, finish-branch guidance, current user
  guide, changelog and README release badge: explain the agent-executed route.

Tests cover both host payloads, arbitrary approved code changes, a real
changelog conflict with main-side package/test edits, exact two-parent commit,
normal review certification remaining false, unchanged prior receipts/counters,
and rejection of missing provenance, changed bytes/parents/workflow/nonce,
dirty/untracked work, extra commits, failed or tampered verification, compound
shipping and absent separate PR authority. Cover actual expiry followed by fresh
verification at clean committed HEAD, push/PR-only recovery, and refusal of a later
same-tree child. Existing docs closure remains strict.

Run the owning Bash and available portable PowerShell suites, then run-fast.
Native Windows 5.1 remains CI-owned. No UI changes; the CLI gate/commit/push
sequence in disposable repositories is the supported user journey. No downstream
Ganadoven mutation or external publication is authorized by this source fix.

## Plan review disposition

Initial review found missing production implementation (P1). This is expected at
the required pre-implementation plan/TDD boundary, not a plan defect; tests have
reproduced RED and implementation is explicitly still pending. Its concrete P2
about hook-skipping options is addressed by the conservative plain-command
allowlist above; test rejection of `--no-verify`, `-n`, global hook-path changes,
environment prefixes, and unsupported pathspecs. P3 heading clarity is included
in the draft docs. Existing final-evidence Stop advisories remain truthful about
full certification and must not trigger a waived review; no separate Stop-hook
behavior expansion is needed for this shipping-gate repair.

Closure confirmed the pre-implementation distinction and identified optional jq
fallback truncation as P2. Adopt the exact-decoder prerequisite above and prove
it with the focused no-jq regression during implementation. This closes the design
decision without another broad plan scan; final implementation review must check
that boundary. Strict literal command parsing also excludes trailing backslashes.
Retain the advisory about inherited push/config behavior outside this repair.

#### E2E Use Cases

Actor: A main coding agent finishing a branch with the developer's explicit review waiver.

Scenario: The approved feature branch conflicts with updated main only in its
changelog, while main also brings in package/test changes. The developer wants
the agent to resolve the conflict, commit and push without another code review.

Intent: Finish the approved change without requiring manual human Git commands,
while keeping fresh verification and normal repository hooks.

Interface: CLI — installed Forge helpers/hooks and ordinary Git commands.

Setup: Create disposable Git projects and a local bare remote through Git, install
this candidate with the public setup command, and activate a full workflow with
the documented helper before editing. Exercise Claude and Codex host metadata.
Use a tiny working CLI app so checks execute real behavior; no external review
service or real GitHub mutation is part of the fixture.

Steps:
1. Create the feature/main divergence, merge main, resolve only the changelog
   conflict while retaining all entries, and stage/freeze the resulting tree.
2. Run actual focused app and CLI journey checks, write truthful verification
   reports with the documented receipt helper, and confirm the shipping gate
   refuses commit without a waiver.
3. Record the synthetic developer decision with the public waiver helper;
   confirm the gate admits ordinary commit and Git executes a repository hook.
4. Commit through ordinary Git, validate the committed waiver, and push the
   approved branch to the disposable local remote after a successful push gate.
5. Modify the candidate afterward and confirm stale approval cannot permit it.
6. Restore the deliberate fixture edit and expire the original evidence using a
   real short receipt TTL. Refreeze the clean committed HEAD, rerun actual app/CLI
   checks, and record a fresh waiver for the same synthetic approved scope. Confirm
   push succeeds without another commit, commit is refused, and a later externally
   created same-tree child cannot use that existing-HEAD waiver.

Verification: stdout shows valid human-waived precommit/postcommit state;
stderr explains the review waiver at allowed ship boundaries. Ordinary review
certification stays false. Git shows the approved tree, both ordered merge
parents, and the same commit on the local remote; the repository hook records
its execution. Stale candidate validation explains refusal rather than PASS.
After expiry recovery, stdout reports postcommit for the exact existing HEAD;
its push gate passes, its commit gate refuses, and a later same-tree child's
waiver check and push gate both refuse.

Persistence: Re-invoke waiver validation after commit and inspect the pushed
ref through Git; repeat from both host contexts. Then recheck after mutation.

Surface coverage: CLI only. No rendered UI, database, production service, or
authenticated native host session is claimed; UI QA is not applicable.
