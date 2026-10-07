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
