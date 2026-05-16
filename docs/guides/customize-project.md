# Customize Your Project

Files you should review and edit after running the setup script.

## 1. Edit CLAUDE.md

Your `CLAUDE.md` is **intentionally short** (~50 lines) — just your project description, tech stack, and commands. All workflow rules, coding standards, and principles live in `.claude/rules/` files that are auto-loaded by Claude Code with the same priority.

**Why this matters:** When you run `setup.sh --upgrade`, your `CLAUDE.md` is preserved (never overwritten), `settings.json` is intelligently merged (your custom permissions kept), and `.claude/rules/` files are safely updated to the latest standards.

Fill in the placeholders:

```markdown
## Project Overview

My Awesome App - Description of what it does

### Tech Stack

- **Backend:** Python 3.12+ / FastAPI
- **Frontend:** Next.js 15 / React
- **Database:** PostgreSQL

### Key Commands

cd src && uv run pytest # Run tests
cd frontend && pnpm build # Build frontend
```

> **Why so slim?** Official best practices recommend keeping CLAUDE.md under 60-100 lines. Shorter files = better Claude performance. Everything else lives in `.claude/rules/` which loads automatically.

## 2. Per-developer state file (`.claude/local/state.md`)

`setup.sh` installs a starter `.claude/local/state.md` for your current developer state — Workflow row, Done / Now / Next, Open Questions, Blockers. The path is gitignored and **not** auto-loaded into Claude's context; hooks read it on demand to remind you to keep it current and to gate `git commit` / `git push` / `gh pr create`.

You don't normally edit this file by hand — `/new-feature`, `/fix-bug`, and `/quick-fix` rewrite the Workflow section as part of Pre-Flight, and the Stop hook nudges you to update Done / Now / Next at the end of each turn. The starter content is:

```markdown
## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |
| Phase     | —     |
| Next step | —     |

## State

### Done

(latest 2–3 only)

### Now

(what you're actively doing)

### Next

(top of the queue)
```

Project goal lives in `CLAUDE.md` under the `## Project Overview` → `### Goal` subsection. Architecture decisions live as per-file ADRs in `docs/adr/NNNN-*.md` (one file per decision; `docs/adr/template.md` is the starter).

**When a `/forge-goal`-driven workflow is active**, additional sections appear in `.claude/local/state.md`:

- `## /goal session` — table with the autonomous-loop session nonce, originating workflow command, and issued-at timestamp. Absent when no loop is active; written by the workflow command checkpoint and REPLACED (not appended) on each new kickoff.
- `## PR authorization` — single authorization line written when the user authorizes PR creation via the `AskUserQuestion` modal at the PR-create gate. Contains the timestamp, session nonce, and HEAD SHA at the moment of authorization. REPLACED (not appended) on each re-authorization.
- `### Checklist` rows for reviewer iterations include `head=`<sha>`` so the evidence script can verify both reviewers cleared at the same iteration AND at the same HEAD.

**REPLACE semantics are critical:** both `/goal session` and `## PR authorization` are managed as singletons. The workflow commands always overwrite existing content, never append. Appending would cause Layer 1's parsers (which use `head -1` on matching lines) to pick up stale data from previous sessions.

## 3. Release PR Skill (All Tech Stacks)

The `/release` skill creates structured release PRs between environment branches:

```
/release test    — Create PR from dev → test
/release prod    — Create PR from test → prod
```

It fetches the latest branch state, reads all commits between the two branches, categorizes changes (Features, Fixes, Improvements, Chores), and creates a well-formatted PR with a dated title (`TEST 03/16` or `PROD 03/16`). Requires `gh` CLI and `dev`/`test`/`prod` branches.

## 4. Frontend Design Quality (TypeScript/Fullstack)

For TypeScript and fullstack projects, the setup installs:

- **`frontend-design` plugin** (built-in) — Auto-triggers creative direction for UI work
- **`/ui-design` skill** (shipped with template) — Three-mode design router that auto-selects **Marketing/Expressive** (5 visual systems, animations, conversion patterns), **Product UI** (dashboards, tables, app shells, dense layouts), or **Trust-First** (healthcare/finance/legal — calm aesthetic, AAA accessibility, data masking). Includes 10 reference files: animation techniques, typography with 12 curated font pairings, 12 industry color palettes, UX anti-patterns, landing page conversion patterns, product UI patterns, trust-first patterns, 21st.dev component search via Playwright, platform size reference, and a mode-aware polish checklist. Auto-triggers when building UI, or invoke manually
- **`rules/frontend-design.md`** — Slim defensive baseline: accessibility, responsive, semantic HTML

**Optional plugin enhancements** (audited — see `rules/skill-audit.md` for the checklist):

| Plugin                            | What it adds                                                                                                                       | Install                                                            |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `freshtechbro/claudedesignskills` | Three.js, GSAP, Framer Motion, Lottie, Babylon.js deep dives (PASS)                                                                | `/plugin marketplace add freshtechbro/claudedesignskills`          |
| `dgreenheck/webgpu-claude-skill`  | WebGPU + Three.js TSL shaders, particle systems (APPROVED)                                                                         | `/skill install webgpu-threejs-tsl@dgreenheck/webgpu-claude-skill` |
| `ibelick/ui-skills`               | Polish layer: baseline-ui, motion-performance, accessibility (CONDITIONAL — copy SKILL.md files manually, skip curl\|sh installer) | Clone repo, copy `skills/*/SKILL.md` to `.claude/skills/`          |

## 5. Optional MCP Add-ons

The default `.mcp.json` includes Playwright and Context7. For web projects, you may want:

**AI Image Generation** (shipped with template — no MCP server needed):

The `/generate-image` skill lets Claude generate images via Google's Gemini API directly. It checks the [official docs](https://ai.google.dev/gemini-api/docs/image-generation) for current model IDs before each generation, so it won't break when Google updates models.

**Setup** (one time only — the only environment variable this template needs):

```bash
# 1. Get a free API key (no credit card required):
#    Go to https://aistudio.google.com → click "Get API Key"

# 2. Add to your shell profile (one time — loads automatically in every future session):
echo 'export GEMINI_API_KEY="your-key-here"' >> ~/.zshrc   # macOS/Linux
source ~/.zshrc

# Windows (PowerShell — one time, persists across sessions):
[System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your-key-here", "User")
```

You do this once and never think about it again. Claude reads the key from your environment automatically whenever it generates images. Without this key, the `/generate-image` skill will prompt you to set it up. Everything else in the template works without any API keys.

**Stock Photography MCP** (optional, free API keys):

| MCP Server             | What it does                                     | API Key                                                           | Install                                                                                             |
| ---------------------- | ------------------------------------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| **Pexels MCP**         | Stock photos AND video search                    | [pexels.com/api](https://www.pexels.com/api/) (free)              | See [garylab/pexels-mcp-server](https://github.com/garylab/pexels-mcp-server)                       |
| **Unsplash Smart MCP** | Context-aware stock photos with auto-attribution | [unsplash.com/developers](https://unsplash.com/developers) (free) | See [drumnation/unsplash-smart-mcp-server](https://github.com/drumnation/unsplash-smart-mcp-server) |

The `/ui-design` skill's `references/media-assets.md` provides prompting best practices and workflow patterns for both generated and stock images.

**Development Tools:**

| MCP Server           | What it does                                    | Install command                                                 |
| -------------------- | ----------------------------------------------- | --------------------------------------------------------------- |
| **Vercel**           | Deploy previews, manage projects, DNS, env vars | `claude mcp add --transport http vercel https://mcp.vercel.com` |
| **Next.js DevTools** | Live runtime/build/type error diagnostics       | `npx next-devtools-mcp@latest init`                             |

After adding any MCP server, add its permission to `.claude/settings.json` → `permissions.allow` (e.g., `"mcp__nano_banana"`) to skip permission prompts.

## 6. Automated PR Reviews (Recommended)

The `/review-pr-comments` command works by processing review comments left on your GitHub pull requests. For it to be useful, you need automated reviewers configured on your repo. Set up **at least one** of these:

| Reviewer                   | How to enable                                                                                                  |
| -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **GitHub Copilot**         | Repo Settings → Code review → Copilot → Enable. Copilot reviews PRs automatically.                             |
| **OpenAI Codex**           | Install the [Codex GitHub App](https://github.com/apps/openai-codex). Configurable via `.codex/` in your repo. |
| **Claude (via Anthropic)** | Install the [Claude GitHub App](https://github.com/apps/claude). Add a `claude-pr-review.yml` workflow.        |

Once configured, the workflow becomes: create PR → automated reviewers leave comments → `/review-pr-comments` processes those comments → push fixes → merge.

> **No automated reviewers?** The workflow still works — you just skip the `/review-pr-comments` step. All pre-PR quality gates (Codex second opinion, deep review, /simplify, verify-app, verify-e2e) still catch issues before the PR is created.

## 7. Verify Setup

```bash
# Restart Claude Code
claude

# Check hooks loaded
/hooks
# Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange

# Check commands available
/help
# Should show: /superpowers:*, /new-feature, /fix-bug, /prd:*

# Test SessionStart hook
/clear
# Should silently inject branch context (no visible output — Claude just knows the branch)

# Check memory
/memory
# Should show auto memory entry + CLAUDE.md files
```
