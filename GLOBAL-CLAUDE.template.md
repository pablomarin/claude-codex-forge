# Global Claude Code Instructions

> This file lives at `~/.claude/CLAUDE.md` and applies to ALL projects on this machine.
> Project-specific instructions go in each project's `CLAUDE.md` file.

---

## Ground Your Claims

**State what you verified, not what you assume.** Before asserting anything about code or files, read them — don't pattern-match from a name or from memory. Separate fact from inference and say which: cite the `file:line` you actually read, run behavior before claiming it works, and say "I haven't checked X" rather than guessing fluently. Confident guessing is a defect. When in doubt, check — or flag it.

---

## Memory Management

**You have persistent memory.** Use it actively. Your auto memory directory persists across sessions.

### When to Save to Memory

Save to your auto memory (`MEMORY.md` or topic files) when you:

- Discover a **project pattern** (build commands, test conventions, code style)
- Solve a **tricky bug** and find the root cause
- Learn a **user preference** (tool choices, workflow habits, communication style)
- Identify **architecture decisions** (key files, module relationships, abstractions)
- Find a **reusable solution** that could apply to future sessions

### How to Save

- **Short notes** (preferences, commands, patterns): Write directly to `MEMORY.md`
- **Detailed notes** (debugging walkthroughs, architecture deep-dives): Create topic files (e.g., `debugging.md`, `patterns.md`) and reference them from `MEMORY.md`
- **Keep `MEMORY.md` under 200 lines** — it's loaded into every session (first 200 lines). Move details to topic files.

### When NOT to Save

- Session-specific state (current task, in-progress work) — use `.claude/local/state.md` instead
- Information that duplicates the project's `CLAUDE.md`
- Speculative or unverified conclusions

### Before Stopping

Before each response where you've done substantial work, ask yourself:

> "Did I learn anything worth remembering for next time?"

If yes, update your auto memory. This is how you get smarter over time.

### On Context Compaction

When context is about to be compacted, save any important learnings from the current session to your auto memory before they're lost. The PreCompact hook will remind you.

---

## Personal Preferences

<!-- Add your personal preferences below. Examples: -->
<!-- - Always use uv for Python package management -->
<!-- - Prefer concise commit messages -->
<!-- - Use pnpm over npm for Node.js projects -->
<!-- - Default to TypeScript for new JavaScript projects -->

---

## Cross-Project Conventions

<!-- Add conventions you follow across all projects. Examples: -->
<!-- - Use conventional commits (feat:, fix:, chore:) -->
<!-- - Always add type annotations in Python -->
<!-- - Run tests before committing -->

---

## Personal Rules

For detailed rules that apply to all your projects, add `.md` files to `~/.claude/rules/`.
These are auto-loaded by Claude Code before project rules.

<!-- Example: ~/.claude/rules/preferences.md with your coding preferences -->
<!-- Example: ~/.claude/rules/workflows.md with your preferred workflows -->
