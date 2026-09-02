# Hooks Reference

Forge v6 installs canonical hook logic under `.forge/hooks/`. Claude Code and Codex adapters route
their native events into the same policy.

## Hooks (Run Automatically)

| Hook | Trigger | What happens |
| --- | --- | --- |
| `SessionStart` | New/resumed host session, clear, or compaction | Injects current-host, branch, state, and drift context; remote fetch remains source-gated |
| `Stop` | Main host finishes a turn | Builds candidate evidence and reminds the host to keep `.forge/local/state.md` current |
| `PreToolUse` | Before a shell command | Audits commands, blocks dangerous patterns, enforces workflow evidence, and checks protected external-mutation authority |
| `PostToolUse` | After supported file writes | Runs the configured formatter |
| `PreCompact` | Before context compression | Ensures the volatile memory directory exists and logs a diagnostic; it does not claim to inject a save instruction into model context |
| `SubagentStop` | Reviewer/producer finishes | Validates structured, candidate-bound review output |
| `ConfigChange` | Claude Code configuration changes | Audits changes and may block managed deny-rule removal in strict mode |

## Host Routing

Claude Code hooks are registered in `.claude/settings.json`; Codex hooks are registered in
`.codex/hooks.json`. Canonical scripts stay in `.forge/hooks/` and read only the event worktree's
`.forge/local/state.md` for current v6 state.

Codex may register a stable router from the primary checkout. For every linked-worktree event,
`codex-worktree-dispatch.{sh,ps1}` validates an absolute event `cwd`, resolves the event repository,
requires the same Git common directory as the registered checkout, and rejects missing or symlinked
canonical hook targets. It then executes the named hook from that event worktree. This prevents a
primary-checkout registration from reading or enforcing the wrong worktree's state.

## Workflow Gates

`check-workflow-gates.{sh,ps1}` validates structured receipts bound to the frozen candidate before
commit, push, or PR creation. A successful process exit is not a clean gate. PR authorization is
bound to the active goal nonce and candidate.
Artifact-bound review prompts, outputs, and receipts live under `.forge/local/reviews/`.

`check-external-mutation-auth.{sh,ps1}` preserves the v6 human boundary without reducing
investigation to a special sandbox. A full investigator can use the selected host's normal tools,
network, databases, APIs, and write access. When an operation is classified as a protected external
mutation, the hook requires the same current human authorization as the main agent; an agent-written
receipt cannot mint that authority.
