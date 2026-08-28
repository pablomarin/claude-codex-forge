# Why a Harness, Not a Template

A template is files you copy once. A harness is a system that runs continuously around your work — catching slip-ups, enforcing discipline, compounding knowledge. Claude Codex Forge started as a template and grew into a harness through months of production iteration.

## Why two coding agents?

One coding agent will confidently ship the wrong thing. Two will disagree — and disagreement is the signal.

The harness uses **Claude Code** (Anthropic) and **OpenAI's Codex** together:

- **The current host is main.** Claude Code or Codex proposes plans, writes code, and explains tradeoffs.
- **A fresh reviewer checks independently.** Forge prefers the other engine and visibly falls back to a fresh same-engine reviewer on launch/capability failure.
- **Engineering Council adjudicates ambiguity.** A healthy council runs three main-engine advisors, two other-engine advisors, and an other-engine chairman; an unavailable other engine triggers one all-main attempt.

This is not "more review is better." It's independent context and, when healthy, two engines with
different failure modes. When the other engine is unavailable, Forge uses a visible fresh
same-engine reviewer or all-main council rather than pretending diversity.

## Discipline by construction

You can skip good practice when it feels optional. The harness makes it structural:

- `/new-feature` and `/fix-bug` commands bake in TDD, research-before-design, approach comparison, and a contrarian gate — you follow them or you don't ship
- `check-workflow-gates.sh` blocks `git commit`, `git push`, and `gh pr create` until `.forge/local/state.md` contains candidate-bound review and verification evidence
- `check-bash-safety.sh` blocks dangerous Bash patterns before they run (pipe-to-shell, reverse shells, credential exfiltration)
- `ConfigChange` hook logs every modification to `.claude/settings.json` so permission escalation is auditable
- Every Stop turn reminds the current host to update state; `check-state-updated.sh` is advisory (gating moved to PreToolUse) but still warns if state goes stale and gates `docs/CHANGELOG.md` updates when 4+ files have changed

Discipline is guided by commands and **guarded by hooks**. You can still override (it's your machine) but every override is explicit.

## Continuous memory

Sessions end. State doesn't.

- **Auto-memory** persists locally across sessions and context compaction (the `PreCompact` hook rescues learnings _before_ compression, so nothing gets dropped silently)
- **`.forge/local/state.md`** — host-neutral workflow, goal, and evidence checkpoint; gitignored per-developer/worktree state (hooks read on demand)
- **`docs/adr/`** — architecture decisions, append-only, travels with the repo
- **`docs/CHANGELOG.md`** — historical record, travels with the repo
- **`docs/solutions/`** — bug root causes + patterns, indexed by problem type, travels with the repo via git

Three of those travel with the repo. Auto-memory and `.forge/local/state.md` stay local/per-worktree (they don't sync across teammates), but the git-tracked files mean every root cause, decision, and pattern compounds across weeks and teammates. The same bug never needs to be debugged twice.

## Team-scale by default

One GitHub repo becomes the hub:

- Shared `CLAUDE.md` — project description, tech stack, commands
- Shared `.forge/rules/` — canonical coding standards, workflow rules, security baseline
- Shared `.forge/workflows/` — canonical workflows used through each host's adapters
- Shared hooks — consistent quality gates across the team

Multiple developers run parallel Claude Code or Codex sessions via **auto-created git worktrees**
(`/new-feature` and `/fix-bug` spawn them). Each worktree has its own branch, filesystem, and
`.forge/local/` state. Forge warns against simultaneous editing of one worktree and adds no locks.

## Inheritance

Started from [Boris Cherny's workflow](https://www.anthropic.com/engineering/claude-code-best-practices) (Claude Code's creator), Anthropic's official best practices, and [OpenClaw's pre-compaction memory patterns](https://github.com/openclaw/openclaw/discussions/6038). Evolved into a dual-agent harness through ongoing iteration.

Boris's key insight drives the whole system:

> "Probably the most important thing to get great results out of Claude Code — **give Claude a way to verify its work**. If Claude has that feedback loop, it will **2-3x the quality** of the final result."

Every phase of the workflow is a verification loop. Research verifies assumptions against current docs. Plan review verifies design against the codebase. TDD verifies implementation against tests. Code review loops verify correctness against two reviewers. `/simplify`, `verify-app`, `verify-e2e` — each one another loop. That accumulated verification is what makes the output reliable.
