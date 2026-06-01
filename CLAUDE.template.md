# CLAUDE.md - [Project Name]

## Project Overview

### Goal

[One sentence describing what this project does and who benefits.]

### What Is This?

[PROJECT DESCRIPTION - 2-3 sentences explaining what this project does]

### Tech Stack

[TECH STACK - Fill in per project]

- **Backend:**
- **Frontend:**
- **Database:**
- **Deploy:**

### File Structure

**Replace this example with YOUR project's actual structure. Claude uses this to navigate your codebase.**

```
project/
├── src/              # Backend code
├── frontend/         # Frontend code
├── tests/            # Test files
├── docs/             # Documentation
│   ├── prds/         # Product requirements
│   ├── plans/        # Design documents
│   ├── solutions/    # Compounded learnings (searchable)
│   └── CHANGELOG.md  # Historical record
└── .claude/          # Claude Code configuration
    ├── commands/     # Workflow commands (ENFORCED)
    └── rules/        # Coding standards (auto-loaded)
```

### Design Direction (optional — delete if not needed)

<!-- Remove this comment block and fill in your project's aesthetic:
- Premium, dark-mode-first aesthetic (think Linear.app, Vercel.com)
- Font pairing: Instrument Serif for headlines, Geist for body
- Color palette: deep navy (#0A0E27), electric blue (#3B82F6), warm white (#F8FAFC)
- No generic "AI slop" — avoid Inter, purple gradients, evenly-spaced 3-card grids
-->

### Visual Design Preferences

- Never generate plain static rectangles for hero sections, landing pages, or key visual moments
- Always include at least one dynamic/animated element: SVG waves, Lottie, shader gradients, or canvas particles
- Prefer organic shapes (blobs, curves, clip-paths) over straight edges and 90-degree corners
- Animations must respect `prefers-reduced-motion` — provide static fallbacks

### Deployment (optional — delete if not needed)

<!-- Remove this comment block and fill in your deployment setup:
- Hosted on Vercel, auto-deploys from `main` branch
- Use `vercel --yes` for preview deployments
- Environment variables managed via Vercel dashboard
-->

### E2E Configuration

The `verify-e2e` agent adapts to this project's interfaces. Declare the interface type:

**interface_type:** [fullstack | api | cli | hybrid]

- `fullstack`: API + UI (UI tested via Playwright MCP)
- `api`: API only (HTTP interface, no UI)
- `cli`: Command-line only (stdin/stdout)
- `hybrid`: Use cases declare their own interface

**surfaces** (REQUIRED if your project exposes a CLI alongside fullstack/api, or any combination not exhaustively described by `interface_type`):

The explicit list of user surfaces this project exposes. Used by the verify-e2e Step 2c multi-surface coverage check. If absent, defaults are derived from `interface_type` (fullstack → UI + API, api → API, cli → CLI, hybrid → declared per-UC). **A fullstack project that ALSO has a CLI must declare it here** — otherwise verify-e2e will not warn when UCs miss the CLI surface.

**surfaces:** [UI, API, CLI] _(example for a fullstack-plus-CLI project)_

Valid values: `UI`, `API`, `CLI`. Order does not matter. Omit the line entirely when the `interface_type` default is correct.

**Server URLs** (for fullstack/api):

- API: `http://localhost:8000` (update as needed)
- UI: `http://localhost:3000` (update as needed)

See `.claude/rules/testing.md` for the full interface capability matrix.

### Playwright Framework (optional)

If you enabled Playwright via `setup.sh --with-playwright`, this project has:

- `playwright.config.ts` — at repo root for flat layouts, or inside a frontend subdirectory (`frontend/`, `apps/web/`, etc.) that was detected or passed via `--playwright-dir` at setup time
- `tests/e2e/specs/` — generated spec files (via Phase 6.2c), adjacent to `playwright.config.ts`
- `tests/e2e/fixtures/auth.ts` — auth bypass pattern, adjacent to `playwright.config.ts`
- `docs/ci-templates/e2e.yml` — CI workflow template (copy to `.github/workflows/` to activate); `working-directory` is already stamped to match where Playwright was scaffolded

Run specs locally from wherever `playwright.config.ts` lives:

```bash
pnpm exec playwright test             # flat layout
cd frontend && pnpm exec playwright test   # monorepo layout
```

### Research Enforcement

The `research-first` agent runs in Phase 2 of `/new-feature` (before design begins). It queries Context7, WebSearch, and WebFetch for every external library this feature touches and produces a brief at `docs/research/YYYY-MM-DD-<feature>.md`. The design phase reads this brief to avoid building on stale assumptions.

For bug fixes, targeted research runs after root-cause isolation (Phase 2.5 of `/fix-bug`).

### Key Commands

**Replace the examples below with your project's actual commands:**

```bash
# Workflows (MANDATORY - hooks enforce these)
/new-feature <name>     # Full feature workflow
/fix-bug <name>         # Bug fix with systematic debugging
/quick-fix <name>       # Trivial changes only (< 3 files)
/council <question>     # Multi-perspective decision analysis (5 advisors + chairman)
/codex <instruction>    # Second opinion from OpenAI Codex CLI

# Example project commands (adjust to your layout — backend/ for monorepo, src/ or repo root for flat):
cd backend && uv run pytest                # Run backend tests (or `cd src`, or plain `uv run pytest` for flat repos)
cd backend && uv run ruff check .          # Lint
cd frontend && pnpm test                   # Run frontend tests (only if the project has a frontend)
/finish-branch                             # Merge PR + cleanup worktree
```

---

## No Bugs Left Behind Policy

**NEVER defer known issues "for later."** When a review, test, or tool flags an issue — fix it in the same branch before moving on. This applies to:

- Code bugs found during review
- Deployment/infrastructure issues found during testing
- Configuration mismatches across environments (Docker, K8s, Helm)
- Security findings from any reviewer (Claude, Codex, PR toolkit)
- Test coverage gaps for new code

No "follow-up PRs" for known problems. No "v2" for things that should work in v1. If it's found, it's fixed — or the branch isn't ready.

## Ground Your Claims Policy

**State what you verified, not what you assume.** Before asserting anything about the code, read it — don't pattern-match from a name or from memory. Separate fact from inference, and say which:

- Claims about code → cite the file you actually read (`file.py:42`)
- Claims about behavior → run it, or label the claim unverified
- Uncertain → say "I haven't checked X" instead of guessing fluently

Confident guessing is a defect, the same caliber as a known bug left behind. When in doubt, check — or flag it.

## Detailed Rules

All coding standards, workflow rules, and policies are in `.claude/rules/`.
These files are auto-loaded by Claude Code with the same priority as this file.

**What's in `.claude/rules/`:**

- `principles.md` — Top-level principles and design philosophy
- `workflow.md` — Decision matrix for choosing the right command
- `worktree-policy.md` — Git worktree isolation rules
- `critical-rules.md` — Non-negotiable rules (branch safety, TDD, etc.)
- `memory.md` — How to use persistent memory and save learnings
- `security.md`, `testing.md`, `api-design.md` — Coding standards
- Language-specific: `python-style.md`, `typescript-style.md`, `database.md`, `frontend-design.md`
