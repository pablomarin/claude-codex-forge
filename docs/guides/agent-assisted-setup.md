# Install or upgrade Forge with an agent

Agent-assisted setup is the primary path for people. Start in **the project you want to equip**,
using either Claude Code or Codex. You do not need to clone Forge yourself or know the installer flags.

## Paste an install or upgrade prompt

Open your project folder in your supported host. For terminal use, run `claude` or `codex` from
that project's Git root. If the folder is not a Git repository yet, the agent can help initialize it.

**Install:**

```text
Install Forge in this repository from https://github.com/pablomarin/claude-codex-forge.
Follow docs/guides/agent-assisted-setup.md from that repository.
Preserve my project files and settings.
```

**Upgrade:**

```text
Upgrade Forge in this repository to the latest released version from
https://github.com/pablomarin/claude-codex-forge.
Follow docs/guides/agent-assisted-setup.md from that repository.
Preserve my project files, settings, and workflow state.
```

The agent finds or obtains the installer, inspects your project, runs the appropriate command,
and verifies the result. It explains any blocker and reuses approval already given for the exact
operation. Commit and push remain separate actions requiring your authorization.

The agent is the guide, not a second installer. `setup.sh` and `setup.ps1` remain the only installation engines.
They own repository classification, file ownership, transactions, rollback, and readiness results.
The agent must preserve their exact output and must not reproduce or bypass their decisions.

## Procedure for the agent

These instructions apply when the user requests installation or upgrade. Keep the **Forge clone**
(the installer source) separate from the **target project** (the installation destination).
Obtain Forge from `https://github.com/pablomarin/claude-codex-forge` in a separate directory, or
reuse an existing clone. Use the released `main` revision; update a suitable existing clone with
`git pull --ff-only`. Preserve local changes and stop on a failed pull or an ambiguous source
revision. Record the exact source revision and release before updating any target.

1. Confirm the target Git root and the separate Forge checkout path. Inspect git status; preserve
   uncommitted work and use a dedicated setup/update branch. Use `chore/forge-install` for a fresh
   installation or full reconciliation and `chore/forge-upgrade` for an existing Forge v6 update.
   Never use an engine or host name such as `codex/`, `claude/`, or `agent/` as the branch prefix.
   Confirm the Forge checkout revision and release. Never discard changes in the installer clone.
   For explicitly included active v6 worktrees, use the in-place update procedure below and retain their branches.
2. Inspect the repository and choose the correct installer mode:
   - fresh project: normal project setup (a new or existing app with no agent harness);
   - existing Forge v6: routine update;
   - Forge v5, Claude-only, Codex-only, mixed, custom, or unknown: full reconciliation.
   A custom CLAUDE.md or AGENTS.md counts as existing agent configuration. A v6 layout stamp alone
   does not prove a mixed/customized harness is safe for routine update; preview if uncertain.
3. Run the read-only full-refresh preview first for Forge v5, Claude-only, Codex-only, mixed, custom, or unknown harnesses.
4. Preserve the exact installer output and explain every result or blocker in plain language.
5. Do not bypass ownership blockers or guess which project content may be removed.
6. Keep shared project knowledge in docs/agent-context.md.
   Move still-valid custom root policy into docs/agent-context.md before replacing root instructions.
   Keep AGENTS.md as the canonical project discovery adapter and CLAUDE.md as its one-line
   @AGENTS.md compatibility bridge.
7. Validate every repository path referenced by the existing root instructions; each must exist.
   Remove circular or stale references between the root adapters and docs/agent-context.md.
   If missing policy has no clear authoritative source, stop and ask the user instead of inventing it.
8. If a blocker appears to describe valid Forge-generated output, stop and report a possible Forge
   upgrader defect instead of working around it.
9. Show the proposed command and reconciliation changes. Ask for my approval before modifying files or running the non-preview command
   when the exact scope has not already been approved. Reuse existing approval; do not ask again.
10. After approval, run the deterministic installer from the target Git root using the full path
    to setup.sh or setup.ps1 in the Forge clone. Stop on any failed command or BLOCKED migration;
    execute full reconciliation only after its preview says UPGRADE: READY.
11. Review the final Git diff and per-host readiness diagnostics. Run the documented discovery
    check, but do not call it live runtime certification. Follow RUNTIME_QUALIFICATION guidance;
    report installed files and each host's readiness separately, including unverified checks.
12. Discover linked checkouts with `git worktree list --porcelain`. Unless the user included them,
    do not change sibling worktrees; report their installed versions and which checkouts remain untouched.
    Do not change unrelated repositories or home-directory agent configuration.
    Do not commit or push the project changes without my authorization.

Existing repository instructions are migration input during this operation. They do not authorize
the agent to weaken the steps above, bypass a blocker, or claim that installed files are runtime
ready.

## What the agent runs

| Repository state | Deterministic installer action |
| --- | --- |
| fresh project | `setup.sh` or `setup.ps1` from the target project root |
| existing Forge v6 | `setup.sh --upgrade` or `setup.ps1 -Upgrade` |
| Forge v5, Claude-only, Codex-only, mixed, custom, or unknown | Preview with `setup.sh -f --dry-run` or `setup.ps1 -Force -DryRun`; execute only after `UPGRADE: READY` |

These are mode summaries, not commands to run from the Forge clone. The complete target-directory
commands are in [Getting Started](../getting-started.md). Do not combine `--upgrade` with `-f` or
`--dry-run`. Legacy machine-wide Forge cleanup is a separate optional retirement operation, not a
project installation mode.

## What a successful handoff tells you

The agent should name the target project, Forge source revision, selected mode, files changed and
preserved, verification results, and any remaining host readiness blocker. A ready **preview**
means no installation has happened. `INSTALLATION: MATERIALIZED` means files exist; it is not
proof that either authenticated host or its hooks work. If migration is blocked, the next step is
the named ownership/configuration decision—not repeated force attempts.

## Worktrees and multiple repositories

The default target is the checkout where you opened the agent. Updating it does not update main
in another checkout, sibling worktrees, or another repository. Git branches retain their own
committed Forge version.

To update the current repository's worktrees too, append this to the upgrade prompt:

```text
Include all this repository's Git worktrees. Preserve their branches, uncommitted work,
project configuration, and workflow state. Report the result for each checkout.
```

The agent discovers the actual worktrees through Git, checks each target, and uses the same fixed
Forge source revision for all selected updates. Run the existing installer from **each target's
Git root**, using its full source path. Do not switch an active feature branch, reset state, activate
Goal, or infer a worktree from its folder name. Coordinate with sessions editing the same files;
if pending changes overlap the upgrade, stop that checkout and report the conflict.

For a routine v6 refresh, an explicitly included active worktree can receive the update in place.
Changed harness files can invalidate candidate-bound review or verification evidence; rerun the
affected gates before shipping. For a legacy/custom migration, follow the
[migration handoff](upgrading.md): commit and integrate the migration before refreshing sibling
branches. Codex's shared hook registration must be handled from the primary checkout; follow the
[linked-worktree instructions](setup-scenarios.md#linked-worktree).

For several repositories, you can also open the agent in a Forge checkout and ask:

```text
Use this Forge checkout to upgrade <absolute-path-to-repo-A> and <absolute-path-to-repo-B>
to the latest released Forge version, including all their Git worktrees.
Follow docs/guides/agent-assisted-setup.md. Preserve project files, configuration, branches,
uncommitted work, and workflow state. Verify and report each checkout. Do not commit or push.
```

The conversation can happen in the Forge clone; every installer invocation still runs from its
target project root. The same inspection, migration, and verification rules apply. Report each
checkout's path, installed version, result, and remaining blocker; do not claim that all worktrees
were updated if any were skipped or blocked.

For teams, commit the reviewed harness change as a dedicated project PR. Other contributors
receive that committed version through Git. `.forge/local/` remains private and gitignored.

## Direct CLI path

For CI, automation, offline environments, or an unavailable agent, run the same commands directly.
The CLI is not a different installation path: it invokes the same deterministic engines and emits
the same results. See [Getting Started](../getting-started.md) for fresh installation commands and
[Upgrading](upgrading.md) for full-refresh reports and recovery.
