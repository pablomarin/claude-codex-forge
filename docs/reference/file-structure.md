# File Structure

After a Forge v6 full refresh, the shared harness is canonical under `.forge/`; host directories
contain generated adapters and managed settings, not duplicate policy.
Canonical project instructions live at `.forge/instructions.md`.

```
your-project/
├── CLAUDE.md                          # One-line @AGENTS.md compatibility bridge
├── AGENTS.md                          # Canonical project discovery adapter
├── .mcp.json                          # Shared MCP server definitions
├── docs/
│   ├── agent-context.md               # Optional team-owned shared project knowledge
│   ├── CHANGELOG.md                   # Historical record
│   ├── adr/                           # Architecture Decision Records
│   ├── prds/                          # Product requirements
│   ├── plans/                         # Design plans
│   └── solutions/                     # Compounded learnings
├── .forge/                            # Canonical, engine-neutral harness
│   ├── version                         # Layout version
│   ├── instructions.md                 # Canonical project policy
│   ├── state.template.md               # Canonical state template
│   ├── managed-files.tsv               # Ownership/materialization manifest
│   ├── workflows/                      # Shared workflow definitions
│   │   ├── opinion.md                  # Claude /opinion; Codex $opinion
│   │   ├── goal.md                     # Native /goal composition contract
│   │   ├── new-feature.md
│   │   ├── fix-bug.md
│   │   ├── quick-fix.md
│   │   ├── finish-branch.md
│   │   └── review-pr-comments.md
│   ├── rules/                          # Shared standards
│   ├── agents/                         # Canonical agent role definitions
│   ├── skills/                         # Canonical skills and references
│   ├── hooks/
│   │   ├── lib/
│   │   │   ├── agent-dispatch.sh       # Fresh reviewer selection/fallback (.ps1)
│   │   │   ├── council-dispatch.sh     # Dynamic council topology (.ps1)
│   │   │   ├── codex-worktree-dispatch.sh # Trusted linked-worktree router (.ps1)
│   │   │   ├── codex-pty.sh            # PTY shim wrapping codex exec (.ps1)
│   │   │   ├── codex-pty-helper.py     # Unix pty.fork helper
│   │   │   ├── host-context.sh         # Fixed-target routing metadata adapter (.ps1)
│   │   │   ├── state-path.sh           # Canonical state resolver (.ps1)
│   │   │   ├── workflow-state.sh        # Bounded cross-engine state transitions (.ps1)
│   │   │   └── worktree-lifecycle.sh   # Private harness seed/fold helper (.ps1)
│   │   ├── session-start.sh              # Branch/drift context (.ps1)
│   │   ├── check-workflow-gates.sh       # Candidate evidence gates (.ps1)
│   │   ├── check-external-mutation-auth.sh # Human mutation boundary (.ps1)
│   │   └── pre-compact-memory.sh         # Local memory reminder (.ps1)
│   ├── bin/                            # Runtime checks and trusted helpers
│   ├── local/                          # Per-developer/worktree; gitignored
│   │   ├── state.md                    # Workflow, goal nonce, exact next step
│   │   ├── memory/                     # Volatile memory drafts; optional MEMORY.md index
│   │   ├── reviews/                    # Review prompts, outputs, receipts
│   │   └── evidence/                   # Candidate-bound verification evidence
│   └── memory/                         # Project-owned durable memory; optional MEMORY.md index
├── .claude/                           # Generated Claude Code adapters/settings
│   ├── settings.json
│   ├── commands/                       # Slash-command adapters
│   ├── agents/                         # Claude agent adapters
│   └── skills/                         # Claude skill adapters
├── .agents/                           # Generated Codex skill adapters
│   └── skills/
└── .codex/                            # Managed Codex config, hooks, agent adapters
    ├── config.toml
    ├── hooks.json
    └── agents/
```

The ownership hierarchy is:

```text
.forge/                     Forge-owned engineering policy
docs/agent-context.md       Optional team-owned shared project knowledge
AGENTS.md                   Canonical project discovery adapter
CLAUDE.md                   Compatibility bridge containing only @AGENTS.md
```

Forge creates and refreshes the canonical adapter and bridge, but it does not invent the project's
domain knowledge. When a project needs shared instructions, the team creates
`docs/agent-context.md`; the installed `AGENTS.md` already loads it when present. Shared changes
then happen once in that document.

The Codex hook registration may originate in the primary checkout, but
`codex-worktree-dispatch.{sh,ps1}` validates the event's absolute `cwd`, Git common directory, and
non-symlink canonical hook before routing execution to that linked worktree's `.forge/hooks/`.

There are no required Forge runtime files outside the repository. `.forge/local/` and
`.forge/memory/` are protected ownership boundaries and are never wholesale overwritten.
