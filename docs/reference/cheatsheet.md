# Quick Reference Card

Copy-paste friendly cheatsheet for the full daily workflow.

```
┌─────────────────────────────────────────────────────────────┐
│ FIRST TIME SETUP (once per machine)                         │
├─────────────────────────────────────────────────────────────┤
│ macOS/Linux:                                                │
│   git clone ...claude-codex-forge ~/claude-codex-forge      │
│   chmod +x ~/claude-codex-forge/setup.sh                    │
│   ~/claude-codex-forge/setup.sh --global                    │
│                                                             │
│ Windows (PowerShell):                                       │
│   git clone ...claude-codex-forge $HOME\claude-codex-forge  │
│   & $HOME\claude-codex-forge\setup.ps1 -Global              │
├─────────────────────────────────────────────────────────────┤
│ ADD TO ANY PROJECT                                          │
├─────────────────────────────────────────────────────────────┤
│ macOS/Linux:                                                │
│   cd /your/project                                          │
│   ~/claude-codex-forge/setup.sh -p "Project Name"           │
│                                                             │
│ Windows (PowerShell):                                       │
│   cd C:\your\project                                        │
│   & $HOME\claude-codex-forge\setup.ps1 -p "Project Name"    │
│                                                             │
│ # Same harness is installed for Claude Code and Codex       │
├─────────────────────────────────────────────────────────────┤
│ UPGRADE EXISTING PROJECT                                    │
├─────────────────────────────────────────────────────────────┤
│ cd ~/claude-codex-forge && git pull                         │
│ cd /your/project                                            │
│ ~/claude-codex-forge/setup.sh -F                            │
│                                                             │
│ → Reconciles canonical .forge + generated host adapters    │
│ → Preserves user text outside bounded Forge marker blocks  │
├─────────────────────────────────────────────────────────────┤
│ DAILY WORKFLOW (Hooks enforce this!)                        │
├─────────────────────────────────────────────────────────────┤
│ START:                                                      │
│   claude                               ← Start Claude Code  │
│   codex                                ← Or start Codex     │
│   Hooks read .forge/local/state.md     ← shared checkpoint │
│                                                             │
│ THEN RUN ONE OF THESE COMMANDS:                             │
│   Claude uses /...; Codex uses matching $workflow-* skills  │
│   /new-feature <name>  ← Full workflow (Research→PRD→Plan)  │
│   /fix-bug <name>      ← Debugging workflow (Systematic)    │
│   /quick-fix <name>    ← Trivial only (< 3 files)           │
│   /finish-branch       ← Merge PR + cleanup + restart       │
│                                                             │
│ DECISION ANALYSIS:                                          │
│   Claude: /council; Codex: $council ← dynamic topology      │
│   Claude: /opinion     ← Fresh opinion (other engine first) │
│   Codex:  $opinion     ← Same canonical opinion workflow   │
│   Claude: /opinion investigate; Codex: $opinion investigate    │
│   /review is reserved by both hosts                            │
│                                                             │
│ QUALITY GATES (in order):                                   │
│   Simplification       ← Forge-owned cleanup phase          │
│   Claude /opinion | Codex $opinion ← Frozen review receipts │
│   verify-app           ← Run tests, lint, types (agent)     │
│   verify-e2e           ← User-journey E2E (agent)           │
│   /review-pr-comments  ← Address PR comments (post)         │
│   Stop: 1 broad review → 1 repair → 1 closure              │
│   P3/speculative stops; reachable P0/P1 still blocks           │
│                                                             │
│ MEMORY COMMANDS:                                            │
│   .forge/local/memory/ ← Volatile per-worktree drafts       │
│   .forge/memory/       ← Durable reviewed project memory    │
├─────────────────────────────────────────────────────────────┤
│ SHORTCUTS                                                   │
├─────────────────────────────────────────────────────────────┤
│ Shift+Tab  → Toggle auto-accept mode                        │
│ /clear     → Fresh context (rules re-loaded from disk)      │
│ /compact   → Compact context (triggers PreCompact hook)     │
│ /cost      → Check token usage                              │
│ Escape     → Interrupt the active host                      │
└─────────────────────────────────────────────────────────────┘
```

The default bound is one broad review, one repair and one closure; reopen only for a reachable
P0/P1 security, correctness, or data-integrity risk.
