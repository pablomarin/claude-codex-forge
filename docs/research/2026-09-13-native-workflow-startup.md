# Research: Native workflow startup

**Date:** 2026-09-13  
**Feature:** Preserve Forge activation order while using supported host worktree entry.  
**Researcher:** Fresh `research-first` specialist; documentation and read-only source inspection only.

## External surfaces

| Surface | Observed version | Current stable version | Evidence |
| --- | --- | --- | --- |
| Standalone Claude Code CLI | `2.1.237` from `claude --version` | Not independently verified | Local command on 2026-09-13 |
| Claude Desktop embedded engine | Not verified | Not verified | Desktop documentation does not establish this installation's embedded version or available model tools |

Context7 was not available in the enabled tool inventory. Official documentation was searched and
then opened directly; search excerpts differed from the current opened pages, so conclusions below
use opened pages. No claim of a particular version upgrade fixing the baseline is established.

## Current documented facts

### Native entry and ignored files

Claude Code supports `--worktree` and the model-invoked `EnterWorktree`. Native worktrees normally
start under `.claude/worktrees/`; the default base is the remote default branch, with local `HEAD`
fallback under documented conditions. The configurable base mode supports `fresh` or `head`, not
an arbitrary Forge base ref. `.worktreeinclude` copies matching gitignored files into native-created
worktrees, including Desktop worktrees. A `WorktreeCreate` hook replaces creation and must handle
copying itself. After native entry, hook JSON `cwd` follows the target but `CLAUDE_PROJECT_DIR`
remains the original project root. These are host contracts, not proof that Forge's current setup
is compatible. [Official worktree documentation](https://code.claude.com/docs/en/worktrees),
accessed 2026-09-13.

The Desktop new-session interface has a worktree option beside the branch selection. Its default
location is `.claude/worktrees/`, and Desktop settings can change location and branch prefix. The
documentation supports this user-facing creation route; it does not expose this particular
session's model-tool inventory. [Official Desktop documentation](https://code.claude.com/docs/en/desktop),
accessed 2026-09-13.

`EnterWorktree` can create a worktree or adopt an existing one by `path`. Entry to an existing path
outside `.claude/worktrees/` requires approval; native creation and paths under that directory do
not prompt under this specific path rule. Once already inside a worktree session, only the path
form is available and its target must be inside that repository's `.claude/worktrees/`.
[Official tools reference](https://code.claude.com/docs/en/tools-reference), accessed 2026-09-13.

### Permissions are a separate boundary

Protected-path writes receive special handling: auto mode routes them to its classifier, normal
editing modes prompt, and `dontAsk` denies them. An ordinary settings allow rule does not remove
the protected-path check. Prompt instructions cannot promise those writes will be approved. Do not
weaken permissions to make a workflow test pass. [Official permission-mode documentation](https://code.claude.com/docs/en/permission-modes),
accessed 2026-09-13.

## Local findings

Inspected `commands/new-feature.md`, `commands/fix-bug.md`, `rules/worktree-policy.md`,
`hooks/lib/worktree-lifecycle.sh`, the managed manifest, and the observer's failed baseline report
and chronology. No baseline files were changed.

1. Both canonical workflows already prohibit discretionary investigation before activation, but
   activation appears at startup step 6, after creation/bootstrap. The observed Claude starts did
   discretionary inspection earlier. Moving the prohibition to an unmistakable entry boundary is
   a prompt repair; its actual behavioral effect requires an uncoached native rerun.
2. Both workflows currently prescribe shell creation at `.worktrees/<slug>`, then describe simply
   using the linked working directory as sufficient. That does not account for native session
   adoption/configuration and its separate approval boundary.
3. `create` performs Git checkout and then calls `seed`. `seed` first bootstraps missing installed
   files and project discovery/configuration, including `.claude/settings.json`, `.codex/*`,
   `.mcp.json`, and manifest-listed adapters. Replacing only Git creation with native creation does
   not eliminate these later protected-path writes when the harness is ignored.
4. Existing `seed --worktree <path>` supports a linked worktree at an arbitrary same-repository
   path. It refuses an existing target state/snapshot; it is not an unconditional idempotent resume
   operation. Existing active state must be resumed, not reseeded.
5. No `.worktreeinclude` ownership entry was found in the managed manifest. Adding generated
   include content would therefore be an installer/layout change requiring owned-region handling
   and both-platform tests, not merely a prompt change.
6. Forge explicitly excludes workflow state, receipts, authorization, evidence, and local memory
   from cross-worktree seeding. Copying all of `.forge/`, `.claude/`, or the project recursively
   would not meet that boundary. A native copy configuration must select only intended runtime
   artifacts and preserve user-owned entries, not include `.forge/local/` or unrelated secrets.

## Smallest supported route: constraints for the repair

**Inference from the documents and current helper:** accept an already prepared, same-repository
native worktree as isolation instead of requiring another Forge-named worktree. Check actual
physical root, current branch/base, and existing Forge state before activation or resume. Keep the
ordinary shell helper for hosts where it is allowed. This reuses the existing adoption concept;
it does not require session-transfer machinery.

For a Claude session starting in the primary checkout, prefer native creation only when the actual
host exposes that supported capability. The native Desktop new-session worktree option is a
documented alternative setup route. Neither option is sufficient for ignored Forge installations
until intended runtime files are present through supported native copying or separately approved
installation. If creation/bootstrap is refused, stop before discretionary investigation with the
precise setup blocker; do not manually reconstruct protected configuration or claim activation.
Do not overwrite another active primary workflow merely to manufacture a checkpoint.

The requested Forge base must be checked against the native-created base, not replaced silently by
the remote default. Preserve the same exact directory for Codex-to-Claude continuation; do not use
a new native worktree as a substitute for resuming that directory.

## Test implications and open risks

- Test adoption of a prepared native-location worktree, existing active state, and ordinary
  shell-created worktrees; verify no duplicate isolation and no workflow-authority copying.
- Test ignored harness provisioning and protected-path refusal independently from Git creation.
  A plain Git unit test does not prove native permission compatibility.
- Native reruns must observe startup order, actual selected directory/base, runtime tool
  availability, and the first durable activation before app exploration. Record any human
  setup/approval separately from unattended success.
- The real main Desktop session's `EnterWorktree` availability and successful protected harness
  provisioning remain **UNVERIFIED**. This research did not operate the UI, create a session, or
  mutate a test fixture. A standalone CLI version does not prove Desktop behavior.
- Current docs contain behavior introduced after locally installed CLI 2.1.237. Only claimed
  behavior actually exercised on the installed hosts can count as E2E proof.
- Codex product APIs were not researched: this bounded finding does not propose changing them;
  preserving Forge's same-worktree state contract is locally established. Any later Codex-native
  worktree integration needs its own official documentation check.
