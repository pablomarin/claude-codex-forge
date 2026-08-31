# Customize Your Project

Files you should review and edit after running the setup script.

## 1. Add project-specific instructions

Keep user-owned root instructions concise. Canonical Forge workflow rules, coding standards, and
principles live in setup-managed `.forge/instructions.md` and `.forge/rules/`; bounded `CLAUDE.md`
and `AGENTS.md` adapters point both hosts at them.

Put shared project facts in one team-owned tracked document, for example `docs/agent-context.md`:

**Why this matters:** When you run the authoritative `setup.sh -F`, user text outside bounded Forge
marker blocks is preserved while canonical `.forge/` content and generated host adapters are
reconciled with ownership checks.

```markdown
# Project Context

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

Point each host to it once, outside the bounded Forge marker:

```markdown
# CLAUDE.md user-owned section
@docs/agent-context.md

# AGENTS.md user-owned section
Read `docs/agent-context.md` before making project changes.
```

From then on, edit only `docs/agent-context.md` for shared guidance. Keep genuinely Claude-only or
Codex-only instructions in the corresponding root file. Setup preserves those user-owned pointers
and never tries to synchronize their surrounding text.

> **Why so slim?** Host root instructions stay focused while canonical shared policy lives in
> `.forge/instructions.md` and `.forge/rules/`.

## 2. Per-developer state file (`.forge/local/state.md`)

`setup.sh` installs a starter `.forge/local/state.md` for host-neutral workflow, goal, and evidence
state. The path is gitignored; Claude Code and Codex hooks read it on demand to resume the exact next
step and gate `git commit`, `git push`, and `gh pr create`.

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

Project goals and facts live in user-owned project documentation, not inside the managed Forge
block. Architecture decisions live as per-file ADRs in `docs/adr/NNNN-*.md` (one file per decision;
`docs/adr/template.md` is the starter).

**When a native `/goal` run composed with Forge is active**, additional sections appear in `.forge/local/state.md`:

- `## /goal session` — table with the autonomous-loop session nonce, originating workflow command, and issued-at timestamp. Absent when no loop is active; written by the workflow command checkpoint and REPLACED (not appended) on each new kickoff.
- `## PR authorization` — single authorization line written when the user authorizes PR creation via the `AskUserQuestion` modal at the PR-create gate. Contains the timestamp, session nonce, and HEAD SHA at the moment of authorization. REPLACED (not appended) on each re-authorization.
- `### Checklist` rows for reviewer iterations include `head=<sha>` so the evidence script can verify both reviewers cleared at the same iteration and the same HEAD.

**REPLACE semantics are critical:** both `/goal session` and `## PR authorization` are managed as singletons. The workflow commands always overwrite existing content, never append. Appending would cause Layer 1's parsers (which use `head -1` on matching lines) to pick up stale data from previous sessions.

## 3. Release PR Skill (All Tech Stacks)

The release skill creates structured release PRs between environment branches. Claude Code uses
`/release`; Codex uses `$release`:

```
/release test    — Create PR from dev → test
/release prod    — Create PR from test → prod
$release test    — Same canonical workflow from Codex
$release prod
```

It fetches the latest branch state, reads all commits between the two branches, categorizes changes (Features, Fixes, Improvements, Chores), and creates a well-formatted PR with a dated title (`TEST 03/16` or `PROD 03/16`). Requires `gh` CLI and `dev`/`test`/`prod` branches.

## 4. Frontend Design Quality (TypeScript/Fullstack)

Forge v6 installs the canonical UI skill and rules for every declared profile; `-t` does not prune
the v6 rule/skill inventory. For UI work:

- **Claude Code:** `/ui-design`
- **Codex:** `$ui-design`
- **Canonical source:** `.forge/skills/ui-design/` and `.forge/rules/frontend-design.md`

Host-specific third-party plugins are optional and are not part of the Forge contract. Audit any
one you add against `.forge/rules/skill-audit.md` and keep its policy out of the canonical harness.

## 5. Optional MCP Add-ons

The default `.mcp.json` includes Playwright and Context7. For web projects, you may want:

**AI Image Generation** (shipped with template — no MCP server needed):

Claude Code uses `/generate-image`; Codex uses `$generate-image`. Both load the same canonical skill,
which calls Google's Gemini API directly and checks the official documentation for current model
identifiers before generation.

**Setup** (one time only; needed only for the shipped image-generation skill):

```bash
# 1. Get a free API key (no credit card required):
#    Go to https://aistudio.google.com → click "Get API Key"

# 2. Add to your shell profile (one time — loads automatically in every future session):
echo 'export GEMINI_API_KEY="your-key-here"' >> ~/.zshrc   # macOS/Linux
source ~/.zshrc

# Windows (PowerShell — one time, persists across sessions):
[System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your-key-here", "User")
```

The selected host reads the key from its environment when the skill runs. Without it, the skill asks
you to configure it. Everything else in Forge works without a Gemini key.

The canonical UI skill's `references/media-assets.md` provides prompting practices and workflow
patterns for generated and stock images.

Add shared project MCP definitions to `.mcp.json`. Host-specific permission/trust settings remain in
that host's native configuration (`.claude/settings.json` or `.codex/config.toml`); do not copy one
host's syntax into the other.

## 6. Automated PR Reviews (Recommended)

The review-comments workflow processes comments already present on a GitHub pull request. Configure
the human or automated reviewers your repository trusts; Forge does not require a specific vendor.

Once configured, the workflow becomes: create PR → automated reviewers leave comments → Claude
`/review-pr-comments` or Codex `$workflow-review-pr-comments` processes them → push fixes → merge.

> **No automated reviewers?** The workflow still works — you just skip `/review-pr-comments`.
> Pre-PR gates still include fresh opinion review, simplification, verify-app, and verify-e2e.

## 7. Verify Setup

Run the deterministic discovery check from the project root:

```bash
~/claude-codex-forge/scripts/verify-runtime.sh discovery --project-root "$(pwd -P)"
```

```powershell
& $HOME\claude-codex-forge\scripts\verify-runtime.ps1 discovery -ProjectRoot (Get-Location).Path
```

Then open each host you plan to use, accept its native project-trust prompt, and confirm its own
help/hooks or skill discovery. Setup can be `MATERIALIZED` while an unauthenticated or untrusted host
is still not `RUNTIME_READY`.
