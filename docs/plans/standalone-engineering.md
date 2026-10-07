# Standalone Forge engineering practices

## Problem and immutable baseline

Base ref `main`, SHA `6f98ea53c4f4f9391d08a8ba764d01cae2167c94`.
Forge v6 declares the external workflow conversion complete but both Claude settings
templates enable `frontend-design@claude-plugins-official` by default. Full refresh
classifies the same enabled plugin as compatibility-blocked. Current workflow
explanations still invoke Superpowers, despite canonical workflows owning those phases.
The real settings merger reproduced the default on Unix and Windows templates;
explicit developer `false` entries are preserved. No downstream project was changed.

## Scope and source comparison

Keep one canonical Forge owner for TDD, debugging, review, and UI design. Compare public
Superpowers revision `8ca22dba9a94f28898bbce59f2537ff4d87c747d` as source material,
not executable policy. Preserve a thorough parallel comparison outside this repository.
Adapt only concrete improvements: correct-reason RED; independently derived expected
results and realistic failure sensitivity; boundary-based diagnosis with redacted
evidence; bounded condition-based waiting; independently verified completion claims.
Preserve focused verification, human authority, receipt/counter rules, and user work.
Do not add duplicate portable skills, new gate machinery, or automatic plugin removal.

## Implementation

1. Remove automatic plugin enablement from the Unix and Windows settings templates.
   Replace both installers' fresh-install banners so they describe canonical Forge
   capabilities without falsely claiming frontend-design was enabled.
   Add executable settings/installer regression coverage for fresh defaults and upgrade
   preservation of developer-owned enabled/disabled plugin choices and unrelated settings.
   Keep full-refresh compatibility diagnostics for retained overlap; routine upgrade
   preserves settings without that diagnostic. Explain this boundary; readiness is not installation.
2. Correct current workflow documentation and the worktree rule's obsolete required-plugin
   implication. Explain v5 dependencies versus v6 canonical replacements in README/setup
   guidance. Do not rewrite historical changelog entries.
   Correct active troubleshooting instructions that currently recommend enabling the
   three overlapping plugins; retain guidance for developer-owned optional integrations.
3. Strengthen existing testing/debugging/producer/reviewer instructions in place. Tests
   must exercise observable behavior; exact text/schema assertions remain appropriate
   for actual public wire/discovery contracts. Production changes require a behavior
   test failing for the intended reason; never destroy user changes to reenact TDD.
   Diagnostic logging must exclude secrets. Repeated failed fixes trigger reanalysis
   within existing review/resource budgets, not new counters or an automatic rewrite.
4. Use existing pressure qualification machinery for focused scenarios. Distinguish
   fixture/schema correctness from authenticated agent behavior. If native executions
   are unavailable or lack trustworthy outcome evidence, report that boundary unverified;
   no synthetic/native-equivalence claim or false replacement-parity claim.
5. Release metadata prepared for 6.4.10, one changelog entry and matching README badge.

## Verification and acceptance

- Observe the owning regression fail on both current platform templates before repair.
- Fresh materialization installs no competing plugin by default; repeated routine upgrade
  and full reconciliation preserve explicit true/false and unrelated user settings.
  Both fresh-install banners must match that behavior. Active user documentation must
  not recommend enabling plugins that full refresh classifies as compatibility-blocked.
- Installed Claude and Codex adapters discover the same canonical TDD/debugging policy
  with Superpowers disabled; public instruction dependencies are internally resolvable.
- Focused installed CLI/migration acceptance, owning deterministic suites, static platform
  parity, and `run-fast.sh`; no exhaustive local `run-all` authorization is inferred.
- Fresh plan review; fresh distinct final code-spec/code-quality reviews and actual app/
  installed-E2E reports bound to the unchanged staged candidate. Native Windows and actual
  native-host behavior are reported separately from portable/synthetic checks.
- No changes to mcpgateway, msai-v2, vivi-hospitality-suite or global plugin installation.
  No push, PR, merge, downstream upgrade or deployment without applicable human authority.

## Risk limits

Removing a default must not delete existing developer plugin settings or hide a retained
overlap. Guidance improvements must not turn routine work into perpetual reviews or require
the whole local suite. A prompt containing desired words is not evidence that an agent
obeys them. Parallel research may inform scope before final freeze; new mechanisms or
large unrelated changes require a separate decision rather than expanding this repair.

## Human-authorized local PowerShell and native CI improvement

The developer explicitly requested stronger local feedback and faster native Windows CI
after run37657898124 failed. This extends the same unmerged 6.4.10 change; immutable
workflow base remains main6f98ea53c4f4f9391d08a8ba764d01cae2167c94. Current published
parent is d14e4dd94ae3ee95c31c1c8979f20ccd12dc0f78. Prior certification is archived and
cannot certify the changed source. No downstream upgrades or VM installation.

Observed problem: the serial native runner spends about40 minutes on18 suites and
reports a7-minute dispatch failure only after all remaining suites complete. Local
fast checks omit the portable runner regression and actual PowerShell reproduction
boundary. Existing native dispatch failure is unchanged from earlier main revisions;
6/52 observed historical reproduction sections fail at64.9–67.3seconds. A root
portable latency control reproduces exit2/UNVERIFIED with receipt timeout/124, while
the positive control passes. The missing native receipt and actual Windows delay
remain unverified. Do not increase the existing60-second fixture cap or claim a fix.

Implementation task (one bounded CI/testing change):

1. Extend tests/template/run-all.ps1 to list discovered suites as machine-readable
   JSON and execute one exact discovered suite with a structured result. Preserve
   default serial all-suite behavior and its existing exit/timing output. Reject
   unknown/path-escaping selectors. Native results bind actual Git HEAD/tree, clean
   candidate, runtime major/minor/OS, suite name, exit and elapsed time. Result files
   must live outside the checkout so they do not dirty or certify a changed source.
2. Replace the serial Windows workflow with discovery, an isolated per-suite matrix
   (fail-fast:false, bounded max-parallel:6), and the existing powershell-51 aggregate.
   Use unique per-suite artifacts uploaded even on failure. Aggregate runs always;
   it fails on a failed/cancelled/skipped dependency, missing/duplicate/unknown suite,
   nonzero exit, wrong Git identity/tree, nonnative5.1 or dirty-candidate result.
   Only complete successful coverage permits the existing Windows attestation.
   Discover all current18 suites dynamically so new suites cannot be omitted.
   Keep90-minute job ceilings; parallelism is not permission to shorten tests.
3. Add focused executable local PS7 checks to run-fast.sh: existing portable runner
   fixture, existing real setup transport checks, and the real PowerShell dispatcher
   qualified reproduction boundary with positive and deliberately timed-out controls.
   Reuse the inspected disposable macOS harness with explicit POSIX engine/kill shims,
   portable paths, real production files, independent literal MATCH/CONTROL hashes,
   state/auth/outside preservation and actual timeout/124 reason assertions. Avoid
   broad native run-all locally. If pwsh is absent, report portable coverage skipped;
   do not claim Windows qualification. Helpers must not add unintended native suites.
4. Preserve safe reproduction diagnostics before fixture deletion: actual dispatcher
   receipt reason/exit/status, primary/control hashes, child stream sizes, and fake
   runner start/end timing. Include focused inherited-versus-stripped Windows process
   startup/UTF8Encoding probes using the already reviewed diagnostic preview, with
   owned-child cleanup and finite probe deadlines. No secret environment dumps,
   auth file contents, timeout relaxation or skipped existing assertions.
5. Update contributor testing guidance and pending6.4.10 changelog for the new commands,
   portable/native distinction, matrix artifacts and aggregate requirement. Retain
   original standalone engineering change and all preserved failed evidence.

Expected changed paths: .github/workflows/windows-parity.yml; tests/template/run-all.ps1;
tests/template/test-powershell-runner.sh; tests/template/run-fast.sh;
tests/template/test-agent-dispatch.ps1; small focused tests/helpers under tests/template
or tests/support; a small aggregate validator under scripts; CONTRIBUTING.md;
docs/CHANGELOG.md; this plan. No product dispatcher/authorization/ownership changes
without independently proven cause and a reviewed plan amendment.

Acceptance and verification: observe intended RED for unavailable selector/results,
incomplete aggregate coverage and absent fast portable registration; GREEN through
the real runner and validator with disposable suites. Exercise positive complete
coverage plus missing, duplicate, failed, wrong identity, nonnative and dirty results
against independently authored literal expectations. Run the actual portable boundary
positive/control and timeout cases and setup transport; all existing failure assertions
remain intact. Validate YAML and graph, PowerShell5.1-compatible syntax and git diff;
run focused owning checks then updated fast gate. Fresh final paired reviews/app/E2E
bind the complete new candidate. Preserve installed standalone acceptance on both
recorded mains; CI-specific E2E demonstrates discovered-suite to result to aggregate
with disposable suite programs, and invalid coverage never produces attestation.

Publish only through actual current human shipping authority and normal host tools.
The fresh Windows matrix is the first native measurement of this new arrangement;
no speedup or platform repair is claimed before actual completion. Inspect actual
new diagnostics if reproduction fails again and resolve the supported cause before
merge. All current18 native suites plus exact reviewed-tree attestation remain
required. Never reuse d14 certification or its failed run as success.
