# Explicit developer workflow decisions

Extend the unpublished 6.5.2 change on fix/human-review-waiver. Immutable workflow
base remains ref `0f844f0`, SHA `0f844f0d601a86008ea4abe5c7f619028ca2e0fe`.
The prior local implementation is commit `50cda751ad7a829912e774f36ea83dd7dca57f1d`.

The developer clarified that discipline remains the default, but the actual
developer may skip any remaining development workflow step, including E2E, after
development or review repairs. The current helper always requires successful app
and E2E receipts, so an explicit skip cannot be honored.

## Minimal design

- Extend the existing verification helper with record-workflow-waiver and
  check-workflow-waiver. Keep legacy record-review-waiver/check-review-waiver and
  their schema-1 sidecars working unchanged.
- The new command takes an explicit comma-separated --skip list (PowerShell
  -Skip). Supported process gates: review, verify-app, e2e, simplification,
  plan-review, convergence, changelog, continuation. `all` expands to that list.
  Subchecks use verify-app:<slug> or e2e:<slug>; the whole aggregate remains
  required for all other checks. Unknown, duplicate, overlapping or empty scopes fail; normalized scope is written in a
  schema-2 .workflow-waiver sidecar, alongside actual decision and conversation
  provenance. No blanket environment flag or implicit exemption.
- Reuse exact frozen candidate, branch, workflow, nonce and ordered parent
  binding, freshness, safe plain Git syntax, existing-HEAD renewal and later-child
  refusal. A waiver is for this completed candidate, not future development.
- Recording binds only the actual decision, normalized omissions and exact current
  candidate/context, not the availability of unwaived results. Default shipping
  validation checks all unwaived evidence live against the same candidate: two
  distinct current review receipts, app PASS, and E2E PASS or legitimate N/A.
  Stop uses `check-workflow-waiver --boundary stop`, validating the same decision
  and exact candidate identity without requiring shipping evidence. Missing or
  expired unwaived evidence still blocks shipping, not a separately waived Stop
  step. No checker claims full certification for a waived candidate.
- For a subcheck omission, require an actual focused report and existing verifier
  receipt for the remaining aggregate checks. Its PASS means the executed subset
  passed; canonical line 3 `HUMAN_WAIVED_CHECKS: <sorted comma-separated slugs>`
  names the exact omitted subchecks and is hash-bound by the existing receipt.
  Normal full certification rejects reports carrying this marker. Only workflow
  validation with exactly matching scoped omissions accepts that report; an
  absent report, unmatched omission, or failed remaining check still blocks.
  Do not convert a subcheck request into an aggregate-gate omission.
- Explicitly waived aggregate evidence is not required, relabeled, rewritten or
  converted to a fabricated PASS/N/A. Preserve all previous results, reports,
  checkboxes and review counters. A new passing unwaived result on the same
  candidate may satisfy live validation without recording the human decision
  again. Candidate edits still require a new applicable scoped decision.
- Ordinary full certification remains strict. New checker reports named waived
  gates and precommit/postcommit state separately. Without a valid new sidecar,
  fall back to the existing review-only waiver, never to a malformed new one.
- Shipping hooks validate the decision after configuration/context and separate
  PR authority, before convergence. Skip only named checklist/evidence/process
  gates. Revalidate at final allow. Existing command/ancestry/context integrity
  checks and native host controls are execution boundaries, not development
  quality steps. Separate external action authorization remains necessary.
- Stop hooks respect explicit changelog/continuation skips for the exact current
  candidate and report waived final evidence accurately. Goal turn budgets and
  native controls retain their independent authority.
- build-evidence emits the validated workflow decision and unwaived-evidence
  readiness as separate JSON fields, leaving review/E2E/full-certification
  fields truthful. Native Goal may complete using candidate-bound human-waived
  evidence plus successful unwaived gates and authorized actions; it need not
  claim all_gates_green. Budget and native host limits remain authoritative.

## Regression and acceptance

Use existing disposable fixture helpers and both host metadata contexts. Add
focused extension-only test selection to the owning Bash/PowerShell suites; the
ordinary owning runs and fast gate still include old and new cases.

1. E2E-only waiver with valid app/review evidence admits ordinary commit/push
   with no E2E report, preserves unchecked E2E, and leaves full certification
   false. Review-only still refuses missing E2E.
2. Selected review+E2E skip still rejects missing/failed app verification and
   unchecked simplification. Unwaived review failure cannot use E2E-only approval.
3. All skips admit the exact candidate with all quality boxes incomplete,
   absent/failed evidence, old plan findings and tripped convergence. Actual
   commit runs its repository hook, preserves both merge parents and can push
   to a disposable local bare remote. No reports or counters are rewritten.
4. A narrower skip cannot waive convergence, plan, changelog or continuation;
   all/named relevant scopes can. Stale/edited candidate, workflow, nonce,
   branch, parents and unwaived evidence invalidate the waiver. Changed waived
   report content does not retroactively claim that report passed.
5. Missing provenance, invalid scopes, malformed sidecars, compound commands,
   hook-skipping or content-selection syntax and absent separate PR authority
   still fail. Bash/PowerShell read each other's new sidecars.
6. Unit-tests-only and UI-QA-only omissions still require actual reports for
   remaining app/E2E checks, reject mismatched omission markers, and never obtain
   ordinary full certification. Changelog-only and continuation-only decisions
   can be recorded before final reviews; they release only their Stop behavior,
   and shipping still refuses missing unwaived evidence.
7. Installed CLI acceptance reproduces explicit skip E2E and skip all after
   review repairs, using actual Git/hooks/local remote under both host metadata.
   Synthetic metadata is not authenticated native-host qualification.

Run RED before production edits, focused GREEN, final owning Bash/portable PS7
and fast17 after final freeze. One independent plan challenge precedes production;
one final broad spec/quality pair, bounded repair and named closure only if needed.
Native Windows5.1 remains CI-owned. No publication or downstream update is part
of this extension. Update current 6.5.2 release and user guidance, not a second
version for this unpublished changeset.

## Independent design challenge disposition

The broad design review found two concrete P2s, both adopted: scoped subchecks
must not waive their whole aggregate; Stop-only omissions must not wait for
shipping evidence. The first review's artifact check noticed concurrent test
edits; keep its findings, do not claim it certified the snapshot. Freeze all
source edits during the named closure. Also adopt the P3 Goal evidence distinction
without changing certified-green fields. Closure checks these named repairs only.

Closure completed CLEAN/P3 with no blocking design findings. Adopt the two advisory
clarifications: a HUMAN_WAIVED_CHECKS marker applies only to PASS subsets; current
unmarked full PASS or legitimate E2E N/A may satisfy a scoped permission without
pretending the human required tests to be omitted retroactively. Slugs use
`[a-z0-9]+(-[a-z0-9]+)*`, an open vocabulary for actual named checks. These are
contract clarifications, not another broad design cycle.
