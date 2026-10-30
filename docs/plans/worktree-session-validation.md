# Native session/worktree validation

## Scope and root cause

Base: `main` at `a135d8d1890b3cca9f70a8f8e4ca244d69e52cf4`.

Ocean's native Codex push targeted a linked worktree and followed a successful local
preflight, but its native hook evaluated the primary checkout's missing historical
candidate receipt. The task's receipt set still validates. Codex's event `cwd` is
the session directory and does not reliably include the per-call execution directory.
Claude's shared gate similarly evaluates event `cwd`, including when command text
targets another checkout. Both behaviors predate 6.5.2. A local process check or
manually constructed hook payload cannot certify native alignment.

The user authorized fixing this shared Forge behavior and will handle Ocean shipping
separately. Do not modify downstream repositories, their receipts, or their releases.

## Minimal change

1. Extend the existing `host-context` helper with a read-only probe preparation and
   process check, preserving its compatibility `hook` no-op and fixed review launcher.
   Preparation resolves the intended physical Git worktree and prints two canonical
   harmless commands to execute separately: `probe <hex-root>` and `check-process
   <hex-root>`. Encode its expected absolute root as a strict hexadecimal literal so
   neither shell interprets arbitrary paths or commands. Use the existing source or
   installed helper path. On Windows, canonicalize physical Git roots to forward-slash,
   case-insensitive drive/UNC paths; Git Bash and PowerShell must produce the same token.
2. Recognize only that fixed probe grammar in the existing PreToolUse workflow gate,
   before its non-shipping return. Compare the actual event's physical Git root and
   common-directory identity with the intended checkout. An absent, malformed, invalid,
   or mismatched event blocks with actual/expected roots and native recovery guidance.
   The recognized native probe ALWAYS exits 2 with a visible stderr diagnostic:
   `FORGE_NATIVE_CONTEXT: MATCH` or `MISMATCH`. MATCH is an intentional diagnostic
   denial, not permission to execute the probe. If the probe process actually runs,
   it reports `UNVERIFIED` (the native hook was not observed) and fails. The separate
   `check-process` command compares its process root and reports
   `FORGE_PROCESS_CONTEXT: MATCH`. Require both observations; neither grants shipping
   authority. Do not rely on allowed-hook stdout or stderr reaching the agent.
   Both gates recognize both fixed Bash and PowerShell command grammars, including
   Claude Windows Bash commands handled by a PowerShell gate. Require an exact
   whole-input, single-line match: reject CR/LF/NUL, odd or non-lowercase hex, 00 bytes,
   excessive length, extra tokens and compound commands. A malformed probe must block,
   never short-circuit shipping enforcement. Compare the decoded canonical root as a
   string to the resolved event root; do not execute Git in an untrusted decoded path.
3. Report the physical event root, common directory, and correct event-root branch in
   SessionStart context. Do not read the branch from an unrelated process directory.
4. Require the actual native probe after create/adopt/select, before activation or
   resumed task work, after a host/session switch, and immediately before shipping.
   Prefer supported native creation/attachment that binds the chat to the existing
   target. On mismatch, rebind/open that existing worktree through the native host,
   then repeat the probe. This replaces the old unconditional current-session/tool-cwd
   continuation default in workflow rules, command docs, parallel-session guidance,
   hook reference and contract tests. Codex CLI may require starting a session at the
   existing checkout when it cannot rebind; supported Desktop attachment can retain the
   current chat. Do not create another worktree or reconstruct state. Existing valid
   task evidence and publication approval survive a context-only recovery.
5. Keep normal routing, shipping gates, approval and candidate checks unchanged. Do
   not parse arbitrary shell commands to choose a checkout; no new registry, session
   lease, cached authority, copied receipts, hook bypass, or persistent probe receipt.
   Manual JSON and fixture success are deterministic coverage only. The native probe
   is a workflow precondition, not a persistent gate receipt: skipping it leaves the
   existing event-cwd routing limitation in place, including primary inactive state
   allowing a command aimed elsewhere. This change detects the mismatch when the
   documented probe runs; it does not claim to infer every shell command's target.
6. Publish matching Bash and PowerShell behavior; document the native host boundary,
   update focused workflow contracts, and bump the source release to 6.5.3.

## Owned paths

- `hooks/lib/host-context.{sh,ps1}`: probe preparation, process and event comparison.
- `hooks/check-workflow-gates.{sh,ps1}`: narrow probe dispatch before normal gate flow.
- `hooks/session-start.{sh,ps1}`: consistent event context reporting.
- `rules/workflow.md`, `rules/worktree-policy.md`, `commands/fix-bug.md`,
  `commands/new-feature.md`, `docs/reference/hooks.md`, `docs/guides/parallel-sessions.md`,
  and native qualification notes: replace unconditional current-session continuation
  and its old contract tokens with observable startup/shipping checks and recovery.
- Focused Bash/PowerShell context tests, existing contracts and fast suite integration.
- `docs/CHANGELOG.md` and README version badge: 6.5.3 release record.

No installed layout or hook registration command changes are intended.

## Acceptance and verification

Meaningful RED must demonstrate that the old gate silently allows the probe even when
its actual native event points to primary while the intended/process root is linked.
It must not fail merely because a new helper mode is absent.

Exercise both host-shaped inputs and platform twins: aligned linked root; event and
process disagreement; nested directory normalization; sibling and unrelated repository
mismatch; malformed/missing/relative/nonexistent metadata; malformed probe command;
source and installed helpers; missing native hook observation; repeated checks without
state. Assert no changes to workflow state, receipts, fingerprints, indexes or refs.
Existing shipping and no-op host-context behavior must remain intact.
Include cross-pair recognition (Bash probe through PowerShell gate and its converse),
Git Bash/PowerShell Windows canonical path equivalence, UNC/space/Unicode paths,
multiline or compound probe-plus-push attempts, and intentional MATCH denial versus
an actually executed UNVERIFIED probe. Native Windows remains a separate qualification
boundary when only PowerShell 7 on macOS is available.

Run focused owning suites then `tests/template/run-fast.sh`, not exhaustive run-all.
Run actual harmless tool probes through authenticated Claude and Codex in disposable
repositories with primary and linked checkouts; preserve host-event and command evidence
separately from synthetic fixtures. Report CLI, Desktop and native Windows boundaries
independently. Do not substitute fake host events or a manual local gate for native PASS.

Use one independent plan review before production edits, then paired final code reviews
and independent verification on the frozen candidate. No product UI changes: rendered
UI QA is not applicable. No push, PR, merge, deployment or downstream rollout is included.
