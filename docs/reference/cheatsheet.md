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
│ ~/claude-codex-forge/setup.sh --upgrade                     │
│                                                             │
│ → Updates hooks, commands, rules (overwrites)               │
│ → Merges settings.json + .mcp.json (adds new, keeps yours)  │
│ → Never touches CLAUDE.md (your project description)        │
├─────────────────────────────────────────────────────────────┤
│ DAILY WORKFLOW (Hooks enforce this!)                        │
├─────────────────────────────────────────────────────────────┤
│ START:                                                      │
│   claude                               ← Start Claude Code  │
│   Hooks read .claude/local/state.md    ← gitignored state   │
│                                                             │
│ THEN RUN ONE OF THESE COMMANDS:                             │
│   /new-feature <name>  ← Full workflow (Research→PRD→Plan)  │
│   /fix-bug <name>      ← Debugging workflow (Systematic)    │
│   /quick-fix <name>    ← Trivial only (< 3 files)           │
│   /finish-branch       ← Merge PR + cleanup + restart       │
│                                                             │
│ DECISION ANALYSIS:                                          │
│   /council <question>  ← Multi-perspective (5 advisors)     │
│   Claude: /opinion     ← Fresh opinion (other engine first) │
│   Codex:  $opinion     ← Same Forge opinion workflow       │
│   Add: investigate     ← Bounded writable investigation    │
│                                                             │
│ QUALITY GATES (in order):                                   │
│   /opinion | $opinion  ← Code-spec + code-quality receipts  │
│   Simplification       ← Forge-owned cleanup phase          │
│   verify-app           ← Run tests, lint, types (agent)     │
│   verify-e2e           ← User-journey E2E (agent)           │
│   /review-pr-comments  ← Address PR comments (post)         │
│                                                             │
│ MEMORY COMMANDS:                                            │
│   /memory              ← View/edit memory files             │
│   "Remember X"         ← Save to auto memory                │
│   "Forget X"           ← Remove from auto memory            │
├─────────────────────────────────────────────────────────────┤
│ SHORTCUTS                                                   │
├─────────────────────────────────────────────────────────────┤
│ Shift+Tab  → Toggle auto-accept mode                        │
│ /clear     → Fresh context (rules re-loaded from disk)      │
│ /compact   → Compact context (triggers PreCompact hook)     │
│ /cost      → Check token usage                              │
│ Escape     → Interrupt Claude                               │
└─────────────────────────────────────────────────────────────┘
```
