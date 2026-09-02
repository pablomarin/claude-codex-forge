# How Memory Works

Forge has two host-neutral project memory layers with different ownership. Claude Code and Codex
may also keep native private memory, but Forge does not copy or synchronize those stores.

## Memory Architecture

```
┌────────────────────────────────────────────────────────────┐
│                 CANONICAL PROJECT HARNESS                   │
│  .forge/instructions.md  ← engine-neutral policy         │
│  .forge/rules/           ← workflow and coding rules      │
│  .forge/local/state.md   ← shared workflow checkpoint     │
└────────────────────────────────────────────────────────────┘
                             │
             ┌───────────────┴──────────────┐
             ▼                             ▼
┌────────────────────────────┐   ┌────────────────────────────┐
│ VOLATILE, DEVELOPER-LOCAL │   │ DURABLE, PROJECT-OWNED    │
│ .forge/local/memory/      │   │ .forge/memory/            │
│ Gitignored; per-worktree  │   │ Git-tracked and reviewed   │
└────────────────────────────┘   └────────────────────────────┘
```

## Ownership and Lifecycle

| Layer | Who writes it | What it contains | Sharing |
| --- | --- | --- | --- |
| `.forge/local/state.md` | Current host | Workflow, goal nonce, next step, receipts | Same developer/worktree; host-neutral |
| `.forge/local/memory/` | Current host | Volatile drafts and working context | Same developer/worktree only |
| `.forge/memory/` | Project contributors | Vetted, durable learnings | Git-tracked; all hosts/worktrees |
| Native private memory | Claude Code or Codex | Optional host-specific context | Not synchronized or accepted as Forge evidence |
| `docs/adr/` | Project contributors | Architecture decisions, append-only | Git-tracked; read on demand |
| `docs/solutions/` | Project contributors | Bug fixes and reusable patterns | Git-tracked; read on demand |

Session progress belongs in `.forge/local/state.md`, not either memory layer. A host switch resumes
the objective, nonce, checklist, and exact next step from that file; it does not transfer a native
Claude Code or Codex session.

Volatile memory never satisfies another worktree's gates. Promote a learning to `.forge/memory/`
only after vetting it as an ordinary reviewed Git change. Setup never manages, deletes, or
overwrites project-owned durable memory.

## What to Preserve

- Project patterns: build commands, test conventions, and code style
- Bug solutions: verified root causes and owning checks
- Stable preferences: tool and workflow choices
- Architecture notes: key files, boundaries, and relationships
- Debugging insights: reproducible causes and constraints

Do not save secrets, speculative conclusions, candidate receipts, or goal authorization as memory.
PreCompact ensures the local memory directory exists and writes an operator diagnostic, but neither
host treats that successful-hook stderr as model context. If canonical state remains unchanged
across normal active-workflow stops, the Stop checkpoint gives the model one visible continuation
turn to update state/memory; a changed checkpoint stops normally. SessionStart after compaction
points it back to canonical state and concise `MEMORY.md` indexes. Promotion to `.forge/memory/`
remains deliberate.
