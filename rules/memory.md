# Forge Memory

Forge has two host-neutral layers with explicit ownership:

- `.forge/local/memory/` is volatile, per-developer, per-worktree memory. Pre-compact
  reminders may create drafts here. Keep an optional concise `MEMORY.md` index when
  there are multiple entries. It is gitignored, is never copied when a worktree is
  seeded, and never satisfies another worktree's gates.
- `.forge/memory/` is durable, project-owned memory. Promote only a vetted learning as
  an ordinary reviewed Git change. An optional concise `MEMORY.md` index helps both
  hosts find entries after compaction. Setup never manages, deletes, or overwrites it.

Claude and Codex native private memories are optional host context. Forge never copies
or synchronizes them automatically, and neither private store is cross-host evidence.
Session progress belongs in `.forge/local/state.md`, not either memory layer. Update an
existing learning when it evolves and keep durable entries concise and evidence-bound.
`SessionStart` after compaction points the host back to canonical state and existing
indexes; Forge does not pretend a successful PreCompact hook injected text into model context.
