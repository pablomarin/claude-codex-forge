# Premium UI design and browser QA

User-authorized scope: improve Forge's UI skill for every website and app, restore
21st.dev-first discovery, require contemporary visual quality and concise UI copy,
preserve implicit skill discovery, and introduce independent browser UI QA.

Base: main, b30c026824a6352cf4afb322809a2b6dc9bffab8.

## Implementation

1. Preserve the canonical UI skill's meaningful discovery description in Claude and
   Codex wrappers on Bash and PowerShell. Exercise installed output, including
   generated UI QA agent registration and user-owned agent collision preservation.
2. Revise the canonical UI skill, frontend rule and relevant references: design
   brief with visual references and tokens; 21st.dev-first component search with
   source URLs, compatible reuse, honest offline/quota fallback; premium app and
   Trust-First visuals; concise copy and progressive disclosure; motion,
   transparency and backgrounds chosen deliberately with readable static fallbacks.
3. Add one engine-neutral forge-ui-qa role with both host adapters through the managed
   manifest. Use the existing browser capabilities rather than adding a service.
   Caller supplies URL, persona, established or documented design brief/visual references, route
   matrix, candidate identity, already signed-in browser and safe write scope.
   Judge the rendered UI independently of implementation. Require screenshots,
   desktop/phone, task clarity, visual quality, copy, component/motion states,
   and PASS/FAIL/BLOCKED. Passing task tests never substitutes for visual approval.
4. Wire the frontend rule and canonical instruction entrypoint to load ui-design
   for all UI work. Wire new-feature/fix-bug and verify-e2e to run independent
   forge-ui-qa before final freeze and against the final candidate. Aggregate its result
   into the existing candidate-bound E2E report/receipt; do not create a parallel
   shipping receipt system. No browser/signed-in session means BLOCKED for UI
   acceptance. In E2E vocabulary, UI QA FAIL maps to FAIL; missing/BLOCKED maps to
   PARTIAL, before every E2E exit including empty regression/smoke collections.
   Determine applicability from candidate scope, not the presence of UI cases.
   Non-UI changes retain N/A with a concrete reason. This is workflow acceptance
   through existing evidence, not a new hook-level visual judgment system.
5. Add focused contract/installation tests with Bash/PowerShell coverage, update
   user customization docs, release/badge/changelog to 6.5.0. Run focused suites
   and run-fast, independent review, then report exact limits. Do not deploy,
   alter sibling apps, create a PR, or claim live-host visual qualification.

## Acceptance

- Both generated host skill wrappers explain when UI design applies; generic
  adapter text no longer hides the UI trigger.
- All three design modes require premium visual quality, intentional color,
  layered surfaces/backgrounds, considered motion, modern components, and concise
  copy. Trust/accessibility constraints tune treatment rather than waive quality.
- 21st.dev discovery precedes custom standard components; no blind installs,
  paid purchases or framework migrations. An unavailable source is recorded.
- UI QA is installed on both hosts, checks rendered screenshots and actual tasks,
  and a failed/blocked required UI audit prevents the E2E report from passing.
- Existing project-owned ui-qa definitions are preserved by the separate
  forge-ui-qa managed name; no new collision reconciliation machinery is added.
- Fresh installation and upgrade preserve canonical references and agent parity.

## Verification boundaries

Observe a failing installed-description regression test before the adapter repair.
Use focused deterministic install tests and policy contracts for the new role and
workflow linkage. Forward-test the skill with realistic app and trust workflows
in an isolated temporary workspace; distinguish these model decisions from native
Claude/Codex runtime and live visual QA. Run fast gate and git diff --check.

## Rendered trial follow-up

The user requested a real design demonstration, then authorized continuation of
the independent browser qualification, finalization and project-upgrade preparation.
One matched V5/revised-skill Tide prototype trial favored the revised initial
screen, but both were conservative. A directed refinement improved the rendered
identity and copy; it is not evidence of automatic skill superiority. Preserve
the private reports and original builds outside the repository.

Make premium-brief fidelity explicit across affected main, detail, form, phone,
theme and motion states. A craft score alone cannot satisfy unmet visual criteria.
Requalify installation and run a fresh independent browser audit in one complete
session; a lost or unavailable reviewer browser remains BLOCKED. Distinguish a
Desktop tool-backed audit from native CLI qualification and do not fabricate
runtime evidence for either host. Keep release publication and sibling-project
mutations at their actual human-authorized boundaries.
