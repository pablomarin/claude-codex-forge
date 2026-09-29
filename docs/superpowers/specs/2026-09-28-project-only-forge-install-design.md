# Design: Project-Only Forge Installation

**Date:** 2026-09-28
**Status:** Review Requested

## Problem

Forge currently separates project installation from a machine-wide `--global` installation. A
project receives the ordinary workflows, but native `/goal` support depends on authorization and
capture helpers under `~/.forge`. Global setup also inserts Forge policy into personal Claude Code
and Codex configuration. This makes a selected project incomplete without invisible machine state
and can affect repositories where the developer never chose to install Forge.

The split also creates instruction drift. `GLOBAL-FORGE.template.md` contains grounding, memory,
and host-neutrality policy that a project-only installation does not own as one complete local
contract. Claude Code and Codex have separate root adapter templates that restate some Forge policy,
even though the intended architecture is one canonical engine-neutral instruction source.

Forge must become complete, explicit, and versioned per repository. Installing Forge in Project A
must not activate Forge in Project B. Removing the global runtime must not discard any useful global
instruction or weaken native-goal, external-mutation, evidence, or user-content safeguards.

## User Intent and Success Boundary

The developer chooses each repository that uses Forge. One project setup command provides all
supported workflows and safeguards, including governed composition with each host's native
`/goal`. One project upgrade command changes only that repository. No supported runtime path reads
or writes Forge-owned files under the developer's home directory.

The change succeeds when:

1. a clean disposable project has the complete Forge harness with no `~/.forge`;
2. an unrelated project remains unchanged;
3. Claude Code and Codex consume one canonical project policy;
4. native goal work can resume across supported host changes without resetting Forge progress;
5. every instruction from the former global policy remains represented locally;
6. an existing global installation can be retired without deleting personal or ambiguous bytes;
7. Unix and Windows make equivalent decisions; and
8. installation and upgrade each have one obvious project-local command.

## Research Basis

- Claude Code's native `/goal` owns the continuation loop, accepts a measurable completion
  condition and an explicit turn/time clause, survives supported session resume routes, and does
  not change the host's permission mode. See
  <https://code.claude.com/docs/en/goal>.
- Codex Goals are user-controlled, thread-scoped completion contracts with lifecycle and budget
  state. See
  <https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex>.
- Claude Code can consume `AGENTS.md` directly in current versions. A small `CLAUDE.md` containing
  `@AGENTS.md` remains the documented compatibility-sharing pattern and prevents independently
  maintained policy copies. See <https://code.claude.com/docs/en/memory#agentsmd>.

Forge relies on those native products for goal activation and continuation. It does not replace,
shadow, or claim to cryptographically authenticate their internal session state.

## Goals

1. Remove `--global` / `-Global` as an installation mode and remove every downstream runtime
   dependency on `~/.forge`.
2. Make the project installation contain the complete canonical policy, workflows, rules, skills,
   roles, hooks, state helpers, and supported native-goal composition.
3. Preserve all useful policy currently found in `GLOBAL-FORGE.template.md`.
4. Make KISS and YAGNI explicit in the always-loaded project instructions and reinforce them in the
   principles and critical-rules surfaces.
5. Make `AGENTS.md` the canonical project adapter and `CLAUDE.md` a compatibility import only.
6. Preserve project-specific `docs/agent-context.md` as optional project-owned content.
7. Provide conservative preview-first retirement of historical global Forge material.
8. Preserve candidate-bound evidence and separate authorization for every external mutation.

## Non-goals

- A hidden or renamed machine-wide Forge runtime.
- Automatic activation in uninstalled repositories.
- Replacing Claude Code or Codex native Goals.
- Synchronizing either host's private memory.
- Cryptographically proving native host session state when the host exposes no such interface.
- Automatically generating project-specific domain knowledge.
- Refactoring unrelated setup, review, worktree, or verification behavior.

## Selected Approach

Use host-native goal authority plus a repository-local Forge checkpoint and monotonic ledger. Keep
all active policy and runtime files in the selected project. Retain a separate cleanup-only legacy
inventory so existing global installations can be retired safely without preserving global setup as
a supported operating mode.

This is the smallest design that satisfies isolation and completeness. Keeping even a small global
authorization helper would retain the dependency the change is intended to remove. Treating an
agent-editable `.forge/local` file as independent authorization would add only the appearance of a
security boundary. Forge instead trusts the native product to decide whether a Goal is active and
uses project evidence to constrain and audit the work performed under it.

## Architecture

### 1. Project-only installation

The supported commands become:

```bash
cd /path/to/project
/path/to/forge/setup.sh
/path/to/forge/setup.sh --upgrade
```

```powershell
Set-Location C:\path\to\project
& C:\path\to\forge\setup.ps1
& C:\path\to\forge\setup.ps1 -Upgrade
```

Both installers require the canonical Git root and materialize only project-scoped entries from the
active manifest. They do not inspect, require, refresh, or repair a home-directory Forge harness.
Legacy/mixed project ownership continues to use the existing preview-first full-refresh path.

The old `--global` and `-Global` spellings become non-mutating diagnostics. They explain that global
installation is retired and point to either project setup or the explicit legacy-global retirement
command. They never silently reinterpret a global request as a project installation.

Project setup reports one of these native-goal outcomes:

- `NATIVE_GOAL_RUNTIME: PENDING` when deterministic installation is complete but live host
  qualification has not been demonstrated;
- `NATIVE_GOAL_RUNTIME: READY` only after the current qualification owner has valid evidence; or
- `NATIVE_GOAL_RUNTIME: BLOCKED` with the concrete missing host capability.

No diagnostic mentions global setup as remediation.

### 2. Complete local policy and KISS/YAGNI

`FORGE.template.md`, installed as `.forge/instructions.md`, becomes the complete always-loaded Forge
contract. `GLOBAL-FORGE.template.md` is retired only after contract tests prove the following policy
mapping:

| Former global policy | Project-local canonical outcome |
| --- | --- |
| Ground Your Claims | Keep the stronger `FORGE.template.md` section and its exact-candidate evidence boundary |
| Memory Management | Add the concise mandatory behavior to `FORGE.template.md`; retain operational detail in `rules/memory.md` |
| Host Neutrality | Keep the project Working Contract and reviewer-fallback rules as the canonical version |
| Do not save secrets or speculation | State explicitly in project instructions and `rules/memory.md` |
| Preserve useful learning before compaction/end | State explicitly in project instructions and `rules/memory.md` |

The three simplicity surfaces receive an explicit shared primitive:

> Apply KISS and YAGNI: build the smallest correct solution required by current evidence and
> acceptance criteria. Do not add speculative abstractions, compatibility layers, hardening, or
> edge-case machinery without a concrete supported need.

The placement is intentional:

- `FORGE.template.md`: short mandatory directive loaded in every Forge session;
- `rules/principles.md`: rationale and normal engineering application; and
- `rules/critical-rules.md`: compact critical reminder.

Tests compare policy outcomes rather than preserving redundant prose. The global template cannot be
deleted while any mapped outcome is absent.

The local memory directive preserves the former global intent while using project ownership: save
reusable project patterns, verified architecture decisions, root causes, and stable preferences in
the appropriate `.forge/local/memory/` or reviewed `.forge/memory/` layer; keep current progress in
`.forge/local/state.md`; never save secrets or speculation; and preserve a useful durable learning
before compaction or the end of substantial work. Native private host memory remains optional and is
never a Forge runtime dependency.

### 3. One root adapter

The installed root relationship is:

```text
AGENTS.md
├── read .forge/instructions.md completely
└── if docs/agent-context.md exists, read it as project-owned context

CLAUDE.md
└── @AGENTS.md
```

`templates/adapters/AGENTS.block.template.md` contains only discovery instructions and generated
metadata. It does not restate goal, reviewer, workflow, or engineering policy.

`templates/adapters/CLAUDE.block.template.md` contains only the bounded `@AGENTS.md` compatibility
import and generated marker metadata. Because the project `CLAUDE.md` imports `AGENTS.md`, Claude
receives the same adapter on versions where an existing `CLAUDE.md` would otherwise take precedence.
Codex reads `AGENTS.md` directly. There is one real adapter and one compatibility bridge.

Setup preserves every byte outside the Forge marker in an existing `AGENTS.md` or `CLAUDE.md`.
`docs/agent-context.md` is never created, overwritten, or deleted by setup; absence is a supported
state.

### 4. Native goal authority

The developer starts autonomous continuation through the active host's native `/goal` surface. That
native action authorizes only work toward the stated bounded objective. Forge does not install
`.claude/commands/goal.md` or `.agents/skills/goal/SKILL.md` and does not ask the user to run a second
global authorization program.

For Claude Code, the user-entered goal condition is the authority. For Codex, the native Goal or an
explicit user request to create one is the authority under Codex's lifecycle contract. Agent-written
project state is not authority to start a host Goal. Conversely, an agent that writes project goal
state without a native Goal gains no continuation capability because continuation remains owned by
the host.

When native goal work begins, Forge records in `.forge/local/state.md`:

- a UUIDv4 nonce;
- a normalized objective hash;
- native activation host and timestamp;
- workflow command, immutable base ref, and base SHA;
- consumed Forge turn count and ceiling;
- checklist, exact next step, status, and evidence paths; and
- the repository-local ledger identity.

The default Forge ceiling is 20 charged turns per human goal activation. This mirrors the bounded
turn-clause pattern documented for Claude Goals and gives both hosts one deterministic project
budget. A developer may activate another native Goal to continue after exhaustion; that action adds
another 20-turn tranche to the existing ceiling while preserving the original nonce, objective, and
consumed count. It never resets progress to zero. Changing the objective starts a new nonce and does
not inherit authorization for any external mutation.

The goal condition and Forge workflow both require the engine to stop substantive work when the
Forge ceiling is reached, persist the exact checkpoint, and surface the next useful step. Native
token, timer, or turn counters remain telemetry and may reset across host sessions.

### 5. Repository-local monotonic ledger

The Stop hook stores turn records under:

```text
<git-common-dir>/forge-goals/<nonce>/
├── binding
├── turns/
├── checkpoint
└── exhausted
```

The Git common directory is repository-local, shared by linked worktrees, untracked, and preserved
when one worktree is closed. Hook and settings policy deny ordinary agent tools from modifying this
ledger directly; the hook owns no-clobber turn publication. Unix and PowerShell implement the same
record schema and validation.

The ledger binds repository identity, nonce, objective hash, ceiling, and turn records. State shows
the derived count, but state alone cannot lower the ledger count or ceiling. Missing, malformed,
aliased, divergent, or backward records fail closed with a concrete tamper diagnostic.

This ledger is budget accounting and cross-worktree continuity, not proof that the native host Goal
is active. Forge makes no stronger claim than the host interface supports.

### 6. External mutation boundary

Native goal activation does not authorize:

- PR creation or merge;
- push, publication, deployment, or release;
- destructive or security-sensitive changes;
- secret access or credential changes;
- messages or mutations in external systems; or
- expansion to another repository or materially different objective.

Existing candidate, review, verification, PR-authorization, and promotion gates remain bound to the
exact worktree and candidate. A host change resumes the checkpoint but never transfers or fabricates
native conversational context. Reviewer transport keeps its existing disclosed standing-consent
contract and authentication-recovery behavior.

### 7. Legacy global retirement

Global cleanup is a separate, explicit operation:

```bash
# Read-only preview
/path/to/forge/setup.sh --retire-global

# Apply the exact displayed plan digest
/path/to/forge/setup.sh --retire-global --apply --confirm <plan-digest>
```

```powershell
# Read-only preview
& C:\path\to\forge\setup.ps1 -RetireGlobal

# Apply the exact displayed plan digest
& C:\path\to\forge\setup.ps1 -RetireGlobal -Apply -Confirm <plan-digest>
```

Project install and upgrade never invoke this operation. The active project manifest contains no
global rows. A cleanup-only `manifests/legacy-v6-global.tsv` retains the ownership knowledge needed
to recognize historical global material without making it an active runtime.

The preview classifies every candidate as:

- `REMOVE`: exact Forge-owned canonical file, generated record, marker block, or managed entry;
- `PRESERVE`: personal or unrelated content outside Forge ownership;
- `BLOCKED`: ambiguous, modified, aliased, or unknown content requiring human resolution; or
- `ABSENT`: expected historical material is not present.

Apply repeats discovery and refuses cleanup if the classification changed. It may:

- delete a canonical file only when its current hash matches its recorded install-manifest hash or
  another explicitly recognized released hash;
- remove only the exact Forge marker block from personal `CLAUDE.md` or `AGENTS.md` files;
- remove only exact Forge-managed JSON/TOML entries while preserving every other entry;
- delete recognized Forge-generated authorization, ledger, identity, and capture records that were
  shown in preview; and
- remove a directory only after it becomes empty.

Preview prints a deterministic digest over the canonical target paths, classifications, expected
hashes, and managed-entry identities. It writes no receipt or other persistent state. Apply requires
that digest through `--confirm` / `-Confirm`, recomputes the plan, and refuses to mutate when the
digest differs. The extra token exists only on this destructive one-time legacy cleanup; normal
project installation and upgrade remain single commands.

Unknown files, modified canonical bytes, unexpected marker structure, symlink/reparse traversal, or
unrecognized settings values block that item rather than being deleted. Cleanup reports remaining
preserved or blocked material and never claims the global harness is fully retired while an active
Forge registration remains.

### 8. Qualification evidence is development evidence

The current goal authorizer and capture helpers are removed from downstream manifests and runtime
checks. Native-goal qualification remains in the Forge source repository as deterministic fixtures
plus authenticated live release evidence. Qualification output belongs under the source workflow's
`.forge/local/evidence/` or another explicit disposable test root, not under a downstream user's
home directory.

`scripts/qualify-goal-feasibility.*` is redesigned to exercise a disposable project-only install.
It proves native activation, progress, checkpoint resume, budget exhaustion, stuck warning, and host
handoff without manufacturing an operator receipt. If a host is unavailable, unauthenticated, or
does not expose a required capability, the result is `BLOCKED`, never a synthetic pass.

## Data Flow

### Fresh install

```text
canonical Git root
  -> setup
  -> project manifest
  -> .forge + host adapters/settings
  -> deterministic validation
  -> live qualification remains an explicit readiness fact
```

No step reads or writes `~/.forge`.

### Native goal

```text
human native /goal activation
  -> host owns continuation and lifecycle
  -> Forge records objective/checkpoint in .forge/local/state.md
  -> Stop hook appends one no-clobber repository-ledger turn
  -> evidence/checklist determines next step
  -> complete, blocked, user pause, or Forge ceiling exhaustion
```

### Host handoff

```text
Host A checkpoints exact next step
  -> same worktree + Git common ledger
  -> Host B reads AGENTS.md and .forge/instructions.md
  -> Host B reads state and existing count
  -> human activates Host B native Goal if autonomous continuation is wanted
  -> count continues; native session context does not transfer
```

## Error Handling

Forge stops without partial mutation when:

- setup is outside the canonical Git root;
- project ownership or a root marker is ambiguous;
- a required native capability is unavailable;
- goal state and the repository ledger diverge;
- the persistent ceiling is exhausted;
- global-retirement preview and apply see different material;
- global cleanup encounters modified, unknown, or aliased content; or
- an external mutation lacks its separate authorization.

Messages identify the failing surface and one concrete next action. They do not recommend global
installation, silently weaken the contract, or describe unqualified runtime behavior as ready.

## Source Surfaces

The implementation plan must account for at least:

- `setup.sh` and `setup.ps1`;
- `manifests/managed-v6.tsv`, the new cleanup-only legacy-global inventory, and legacy manifests;
- `scripts/materialize-adapters.sh` and `.ps1`;
- `scripts/merge-settings.py` and bounded inverse-removal support;
- `FORGE.template.md`, `GLOBAL-FORGE.template.md`, `rules/principles.md`,
  `rules/critical-rules.md`, and `rules/memory.md`;
- `templates/adapters/AGENTS.block.template.md` and `CLAUDE.block.template.md`;
- `commands/forge-goal.md`, workflow commands, and `state.template.md`;
- `hooks/check-state-updated.sh` and `.ps1`, plus ship/evidence consumers of goal state;
- project and global settings templates, removing obsolete home-goal denies;
- goal qualification scripts and fixtures;
- setup, refresh, contract, parity, hook, goal, Unix, and Windows tests; and
- README, getting-started, upgrade, setup-scenario, command-reference, troubleshooting, and
  changelog documentation.

The implementation plan may split code into focused helpers, but must not introduce a daemon,
database, service, package dependency, or replacement configuration framework.

## Test Strategy

### Policy and adapter contracts

1. Every former global instruction outcome maps to project instructions or a named project rule.
2. KISS and YAGNI appear in the top-level instructions, principles, and critical rules.
3. Installed `AGENTS.md` points to `.forge/instructions.md` and optional project context.
4. Installed `CLAUDE.md` imports `@AGENTS.md` without duplicating Forge policy.
5. Existing bytes outside both marker blocks survive install and upgrade.
6. Missing `docs/agent-context.md` is accepted and no speculative file is generated.

### Project installation and isolation

1. Fresh Unix and Windows setup succeeds with an empty home lacking `~/.forge`.
2. All workflows, hooks, roles, skills, reviewers, state helpers, and goal composition are present.
3. Project A installation leaves Project B and home Forge paths byte-for-byte unchanged.
4. Project upgrade changes only proven project-owned surfaces and preserves local state and memory.
5. `--global` / `-Global` exits nonzero without mutation and gives the migration message.

### Goal accounting

1. A native goal creates one project state binding and one repository-local ledger.
2. Duplicate Stop delivery does not double-charge a turn.
3. Linked worktrees and a host handoff see the same monotonic count.
4. State deletion or count reduction cannot reset the ledger.
5. The twentieth charged turn produces the bound exhaustion checkpoint and stops substantive work.
6. A new human native-goal activation extends the same objective by 20 without resetting count.
7. A changed objective receives a new nonce and no stale external authorization.
8. Stuck warnings remain advisory and do not extend the budget.
9. Ordinary non-goal workflows do not create or charge a goal ledger.

### Global retirement

1. Preview is byte-for-byte non-mutating.
2. Apply removes exact canonical files, generated records, marker blocks, and managed entries shown
   by preview.
3. Personal text and unknown JSON/TOML fields survive byte-for-byte or semantically as appropriate.
4. Modified, unknown, aliased, or reparse-point material is preserved and reported blocked.
5. Partial historical installations remove only independently proven items.
6. Unix and Windows produce equivalent classifications and outcomes.
7. Subsequent project setup does not recreate global material.

### Real E2E qualification

In disposable repositories with no global Forge harness:

1. install Forge and run ordinary `new-feature`, `fix-bug`, and `quick-fix` user journeys without
   Forge-specific hints beyond their native entry points;
2. start a bounded native Goal in Claude, checkpoint before implementation, continue in Codex, and
   return to Claude for review and verification;
3. run the reverse Codex-to-Claude handoff;
4. prove the count and ceiling remain monotonic;
5. prove post-certification mutation invalidates evidence;
6. prove PR creation and merge still pause for separate authorization; and
7. prove an uninstalled control project receives no Forge behavior.

The final candidate must also pass the complete deterministic suite and Windows PowerShell 5.1 CI.

## Documentation Contract

The primary README presents only:

```bash
cd /path/to/project
/path/to/forge/setup.sh
```

for installation and:

```bash
cd /path/to/project
/path/to/forge/setup.sh --upgrade
```

for routine upgrade, with PowerShell equivalents adjacent. Global retirement appears in a separate
legacy-cleanup section and is never described as required for normal use. Reference and
troubleshooting documents use the same terminology and command surface.

## Completion Boundary

The change is complete only when:

- all global policy outcomes are proven present project-locally;
- no active project runtime or documentation path requires `~/.forge`;
- project install, upgrade, and cross-project isolation pass on Unix and Windows;
- cleanup preview/apply preservation tests pass;
- exact-candidate reviews and verification are clean;
- real project-only Claude and Codex goal handoffs pass or an explicitly accepted platform
  limitation is documented without claiming readiness; and
- README and setup output make first install and upgrade obvious.

No global compatibility runtime is retained merely to make old tests pass. Historical behavior may
remain in changelog text and cleanup-only ownership data, but not in the supported installation or
runtime architecture.
