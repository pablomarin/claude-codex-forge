# File Structure

After setup, your project should have:

```
your-project/
├── CLAUDE.md                          # Project description (slim, user-owned)
├── .mcp.json                          # MCP servers (Playwright + Context7)
├── docs/
│   ├── CHANGELOG.md                   # Historical record
│   ├── adr/                           # Architecture Decision Records (per-file, append-only)
│   │   ├── README.md                  # Index
│   │   ├── template.md                # Blank ADR starter
│   │   └── NNNN-*.md                  # One file per decision
│   ├── prds/                          # Product requirements
│   │   ├── {feature}.md               # Structured PRD
│   │   └── {feature}-discussion.md    # Refinement conversation log
│   ├── plans/                         # Design docs from Superpowers
│   │   └── YYYY-MM-DD-{feature}.md
│   └── solutions/                     # Compounded learnings (searchable)
│       ├── build-errors/
│       ├── test-failures/
│       ├── runtime-errors/
│       ├── performance-issues/
│       ├── database-issues/
│       ├── security-issues/
│       ├── ui-bugs/
│       ├── integration-issues/
│       ├── logic-errors/
│       └── patterns/                  # Consolidated when 3+ similar
├── .claude/
│   ├── settings.json                  # Permissions + Hooks (NOT MCP servers)
│   ├── local/                         # Per-developer, gitignored
│   │   └── state.md                   # Workflow + Done/Now/Next (NOT auto-loaded)
│   ├── hooks/
│   │   ├── lib/
│   │   │   ├── default-branch.sh      # Shared helper: detect repo's default branch (.ps1 on Windows)
│   │   │   ├── codex-pty.sh           # PTY shim wrapping `codex exec` (workaround for openai/codex#19945; .ps1 on Windows)
│   │   │   └── codex-pty-helper.py    # Python pty.fork + waitpid helper invoked by codex-pty.sh
│   │   ├── session-start.sh           # SessionStart: branch context + drift warning (.ps1 on Windows)
│   │   ├── check-state-updated.sh     # Stop: enforce state updates (.ps1 on Windows)
│   │   ├── check-bash-safety.sh       # PreToolUse: audit log + block dangerous patterns (.ps1 on Windows)
│   │   ├── post-tool-format.sh        # PostToolUse: auto-format on save (.ps1 on Windows)
│   │   ├── pre-compact-memory.sh      # PreCompact: save learnings (.ps1 on Windows)
│   │   └── check-config-change.sh     # ConfigChange: log config modifications (.ps1 on Windows)
│   ├── agents/                        # Custom subagents
│   │   ├── verify-app.md              # Unit tests + lint + types + migrations
│   │   ├── verify-e2e.md              # User-journey E2E (API / UI / CLI) + regression suite
│   │   ├── research-first.md          # Pre-design library/API research (Context7 + official docs)
│   │   └── council-advisor.md         # Engineering Council advisor (persona via prompt)
│   ├── commands/                      # Custom slash commands (ENFORCED)
│   │   ├── new-feature.md             # /new-feature - Full feature workflow
│   │   ├── fix-bug.md                 # /fix-bug - Bug fix workflow
│   │   ├── quick-fix.md               # /quick-fix - Trivial changes only
│   │   ├── finish-branch.md           # /finish-branch - Merge PR + cleanup workflow
│   │   ├── codex.md                   # /codex - Second opinion via Codex CLI
│   │   ├── review-pr-comments.md      # /review-pr-comments - Process PR feedback
│   │   └── prd/
│   │       ├── discuss.md             # /prd:discuss command
│   │       └── create.md              # /prd:create command
│   ├── rules/                         # Auto-loaded standards (safe to overwrite)
│   │   ├── principles.md              # Top-level principles + design philosophy
│   │   ├── workflow.md                # Decision matrix for choosing commands
│   │   ├── worktree-policy.md         # Git worktree isolation rules
│   │   ├── critical-rules.md          # Non-negotiable rules (branch safety, TDD)
│   │   ├── memory.md                  # How to use persistent memory
│   │   ├── security.md                # Security standards
│   │   ├── testing.md                 # Testing standards
│   │   ├── api-design.md              # API design standards
│   │   ├── python-style.md            # Python coding style
│   │   ├── typescript-style.md        # TypeScript coding style
│   │   ├── frontend-design.md         # Frontend design baseline (TS/fullstack)
│   │   ├── database.md                # Database conventions
│   │   └── skill-audit.md             # Third-party skill security checklist
│   └── skills/                        # Skills (release for all, ui-design for TS/fullstack)
│       ├── release/                   # /release — environment promotion PRs
│       │   └── SKILL.md               # Create release PRs (dev→test, test→prod)
│       ├── council/                   # /council — multi-perspective decisions
│       │   ├── SKILL.md               # Orchestrator: dispatch, gate, synthesis
│       │   └── references/            # 3 reference guides (loaded on demand)
│       │       ├── advisors.md              # 5 advisor profiles with engine assignments
│       │       ├── output-schema.md         # Structured output for advisors + chairman
│       │       └── peer-review-protocol.md  # Dispatch, escalation, minority reports
│       └── ui-design/                 # /ui-design — full design system
│           ├── SKILL.md               # Core: design thinking + creative direction
│           └── references/            # Loaded on demand
│               ├── animation-techniques.md  # SVG waves, particles, Framer Motion, GSAP
│               ├── typography-and-color.md  # Fluid clamp, OKLCH, dark mode
│               ├── polish-checklist.md      # Post-build quality audit
│               └── media-assets.md          # Stock photos, AI image gen, video
└── ...
```

## Global files (created by `setup.sh --global`)

```
~/.claude/
├── CLAUDE.md                          # Global instructions + memory management
├── settings.json                      # Global hooks (PreCompact, Stop)
└── hooks/
    ├── pre-compact-memory.sh          # PreCompact script (macOS/Linux)
    └── pre-compact-memory.ps1         # PreCompact script (Windows)

~/.claude/projects/<project>/memory/   # Auto memory (Claude writes this)
├── MEMORY.md                          # Index (first 200 lines loaded every session)
├── debugging.md                       # Debugging patterns (on-demand)
├── patterns.md                        # Code patterns (on-demand)
└── ...                                # Other topic files Claude creates
```
