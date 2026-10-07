# Worktree shipping guidance

Human approved the independent opinion's minimal documentation/contract repair. Base ref `fix/automatic-worktree-setup`, immutable SHA `d384894dba7a18872183595870e9dbf9d1d65f1b`. This separate task preserves the installer PR's head.

## Reproduction and root cause

An agent in a primary-checkout Codex chat completed a linked-worktree feature, obtained exact publication approval, then stopped solely because the chat workspace was primary. Both canonical workflows conditionally say to open a task-worktree session before commit/push/PR. The wording conflates direct ship-hook context with all work and normal promotion. Promotion validates the worktree receipts itself; its success does not prove a later host hook checked that worktree. Shipping hooks use host event cwd, not parsed command text or an assumed tool workdir.

## Minimal repair

Change commands/new-feature.md, commands/fix-bug.md, rules/workflow.md, docs/guides/parallel-sessions.md, docs/reference/hooks.md, and their owning assertions in tests/template/test-contracts.sh, plus README.md release badge and docs/CHANGELOG.md metadata. The guide is not installed, so put the one authoritative preflight procedure in existing rules/workflow.md (installed as .forge/rules/workflow.md); both workflow links to ../rules/workflow.md#shipping-from-the-current-session then work in source and installed layouts. Guide/reference summarize and link to that source-of-truth section instead of owning duplicate rules. No new file, manifest entry or runtime mechanism. Align guidance: continue current-chat work, reviews, verification, approval recording, and receipt-validating promotion. For direct git commit/push/gh pr create, use correct native event context when available. Continue in the current session unless the developer chooses to switch; do not ask another workspace-choice question after valid shipping approval.

Before accepting a local preflight, set the tool process working directory to the verified physical task-worktree root and run that worktree's workflow-state show. Require the expected task/workflow and worktree/common-directory identity; missing, inactive, mismatched or unreadable state is a blocker, not an exit-0 success. Construct the exact shipping-command input with cwd equal to that verified root, verify that equality (never infer it from command text), then invoke that worktree's existing shipping gate with both process cwd and input cwd at the same root. Require exit 0, keep normal native hooks and authorization, report any native-session context mismatch, and stop on any real denial. This is explicit local verification, never a fabricated native event or authenticated native-context claim. Revalidate unchanged candidate/HEAD and approval immediately before execution. No parsing, registries, custom shipping wrapper, new approval records or runtime changes.

Existing standing review approval and exact-scope publication continuation remain unchanged; host restrictions remain real boundaries. Record the docs-only patch as 6.4.9 in README badge and CHANGELOG per source release policy. Keep pending 6.4.8 changes intact.

## Verification

First update the owning contracts and observe failure of old guidance. Then implement wording and observe green; keep exact installed-source materialization coverage for both Claude/Codex adapters. Run existing hook-cwd coverage and a bounded actual-linked-worktree explicit-preflight check for both Claude/Codex main metadata and Bash/PowerShell, with passing approved/complete state and blocked missing-receipt controls. Include absent or wrong input cwd: absent falls back to the verified task process cwd and must still block missing receipts; mismatched input/state/root must be rejected by the required preflight validation before relying on a gate result. Fixture events are synthetic local checks, not authenticated native execution. No new broad runtime suite unless a missing contract is demonstrated. Run run-fast.sh, link/diff checks. No application UI change or live app journey is introduced; installed guidance/materialization and exact gate preflight are the applicable E2E acceptance. Native Windows5.1 remains CI-owned.

## Acceptance

- No blanket workspace/session prerequisite for local work or normal promotion.
- Before direct shipping, exact task gate preflight succeeds and normal host hooks remain enabled; any failed gate or authorization blocks execution.
- Preflight never grants authority or claims native event routing changed; candidate mutation invalidates prior evidence as before.
- No repeated approval for exact still-current publication scope or already-covered review transport.
- Canonical workflows, guide, generated native adapters and focused owning contracts agree.
- No downstream active state or existing PR head changed; no publication/merge without its exact authorization.

## Integration after installer merge

PR1102 is merged into main at `b0c280cefd12fff811243cc278fcad920d30d891`. Its reviewed head `7d973ec0d8df7b486ea55b9da15ecc18728c87f8` passed all 18 native Windows PowerShell5.1 suites, including setup143/143 and transport15/15; the CI test-merge attestation tree matches the reviewed tree. These deterministic checks do not qualify authenticated native agents or Goal execution.

Reconcile this existing guidance branch with that supported installer source. Preserve the 6.4.9 guidance changelog section and take main's 6.4.8 section, installer plan and PowerShell setup test unchanged. Import main's explicit UTF-8 Git canonical-root decoding, its real-entrypoint Unicode/non-UTF8 regression controls, and transport control. Keep the shipping guidance, ownership, authorization, routing and all owning setup assertions intact. The already-integrated 90-minute CI diagnostic allowance, suite timing runner and portable runner regression also remain byte-identical to main; no additional timeout change is proposed. Compare every non-guidance path with main before certification. A private-index preview of the resolved linear descendant merges cleanly against main; normal exact-tree promotion remains the publication path. The original workflow base and canonical review counters remain immutable.

Review this updated plan, freeze the resolved candidate, then obtain fresh paired specification/quality reviews, all ten fast suites, focused both-platform shipping preflight controls and a fresh installed Bash/portable PowerShell guidance journey for both recorded mains. Reuse no prior candidate receipts. Promote normally, retarget PR1103 to resolved default main before pushing, then push the fresh reviewed head to trigger native Windows CI against main. Require all-suite/Unicode success and an attestation tree whose test-merge parents include that exact head and resolved main before its authorized merge. A retarget-only event or rerun of the old-base run cannot qualify the integration. Run no exhaustive local suite. Cleanup follows only after both PRs actually merge.
