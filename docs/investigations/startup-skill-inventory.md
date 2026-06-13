# Startup Skill Inventory

Source: `skill_listing` attachment from the empty non-Forge baseline transcript:

```text
~/.claude/projects/-home-aescala82-projects-forge-empty/abe7a33e-63f1-4743-8437-a8c8e6058f6b.jsonl
```

Total visible listing size: ~3,532 rough tokens, 50 entries.

This inventory lists skills/commands visible to Claude at startup. Some are required by Forge workflows; others are general-purpose or optional and may be candidates for disabling, making project-scoped, or loading on demand.

## Currently visible at startup

| # | Skill / command | Rough listing tokens | Notes |
| ---: | --- | ---: | --- |
| 1 | `caveman` | 68 | User/global skill; optional style compression. |
| 2 | `diagnose` | 78 | General debugging skill. |
| 3 | `find-skills` | 79 | Skill discovery/install helper. |
| 4 | `grill-me` | 60 | Planning/design interrogation. |
| 5 | `grill-with-docs` | 74 | Planning/design interrogation with docs updates. |
| 6 | `handoff` | 24 | Conversation handoff compaction. |
| 7 | `humanizer` | 22 | User-installed skill at `~/.claude/skills/humanizer`. |
| 8 | `impeccable` | 227 | UI/design skill; large listing entry. |
| 9 | `improve-codebase-architecture` | 80 | Architecture/refactoring skill. |
| 10 | `prototype` | 110 | Throwaway prototype skill. |
| 11 | `tdd` | 53 | Test-driven development skill. |
| 12 | `to-issues` | 63 | Convert plan/spec to issues. |
| 13 | `to-prd` | 41 | Create PRD from context. |
| 14 | `triage` | 56 | Issue triage workflow. |
| 15 | `write-a-skill` | 42 | Create new agent skills. |
| 16 | `deep-research` | 122 | Multi-source research. |
| 17 | `pr-review-toolkit:review-pr` | 19 | **Forge-required** code review gate plugin. |
| 18 | `frontend-design:frontend-design` | 67 | Forge-enabled plugin; UI-specific. |
| 19 | `caveman:caveman` | 102 | Caveman plugin command; optional. |
| 20 | `caveman:caveman-commit` | 93 | Caveman commit messages; optional. |
| 21 | `caveman:caveman-help` | 54 | Caveman help; optional. |
| 22 | `caveman:caveman-review` | 84 | Caveman review comments; optional. |
| 23 | `caveman:compress` | 89 | Caveman memory compression; optional. |
| 24 | `superpowers:brainstorming` | 56 | **Forge-required** for `/new-feature` and complex `/fix-bug`. |
| 25 | `superpowers:dispatching-parallel-agents` | 37 | Related to orchestration; likely useful. |
| 26 | `superpowers:executing-plans` | 33 | **Forge-required** headless/walk-away mode. |
| 27 | `superpowers:finishing-a-development-branch` | 61 | Related to branch finish workflow. |
| 28 | `superpowers:receiving-code-review` | 67 | Code review feedback discipline. |
| 29 | `superpowers:requesting-code-review` | 36 | Review request discipline. |
| 30 | `superpowers:subagent-driven-development` | 32 | **Forge-required** implementation execution. |
| 31 | `superpowers:systematic-debugging` | 31 | **Forge-required** for `/fix-bug`. |
| 32 | `superpowers:test-driven-development` | 29 | TDD discipline; Forge workflows rely on TDD. |
| 33 | `superpowers:using-git-worktrees` | 57 | Worktree discipline; overlaps Forge workflow commands. |
| 34 | `superpowers:using-superpowers` | 48 | Startup bootstrap; currently auto-injected. |
| 35 | `superpowers:verification-before-completion` | 67 | Completion verification discipline. |
| 36 | `superpowers:writing-plans` | 28 | **Forge-required** plan writing. |
| 37 | `superpowers:writing-skills` | 31 | Skill authoring; optional for normal Forge workflows. |
| 38 | `update-config` | 176 | Harness/settings configuration; large listing entry. |
| 39 | `keybindings-help` | 62 | Keybinding customization; optional. |
| 40 | `verify` | 65 | Manual verification helper; optional/possibly useful. |
| 41 | `code-review` | 102 | Generic code review; Forge uses `/codex` + PR toolkit instead. |
| 42 | `simplify` | 47 | Forge Phase 5.2 uses `/simplify`; likely required. |
| 43 | `fewer-permission-prompts` | 47 | Settings helper; optional. |
| 44 | `loop` | 86 | Recurring prompt/command helper; optional. |
| 45 | `schedule` | 95 | Scheduled cloud agents; optional. |
| 46 | `claude-api` | 41 | Anthropic API reference; optional but useful for LLM work. |
| 47 | `run` | 92 | Launch/drive app; optional but useful. |
| 48 | `init` | 16 | Initialize CLAUDE.md; optional. |
| 49 | `review` | 7 | PR review command; generic. |
| 50 | `security-review` | 22 | Security review command; optional/conditional. |

## Grouped view

### Forge-required or Forge-core

- `pr-review-toolkit:review-pr`
- `superpowers:brainstorming`
- `superpowers:executing-plans`
- `superpowers:subagent-driven-development`
- `superpowers:systematic-debugging`
- `superpowers:writing-plans`
- `simplify`

These are not good removal candidates unless Forge workflows are redesigned.

### Forge-enabled but conditional

- `frontend-design:frontend-design` — only needed for UI work.
- `superpowers:dispatching-parallel-agents`
- `superpowers:finishing-a-development-branch`
- `superpowers:receiving-code-review`
- `superpowers:requesting-code-review`
- `superpowers:test-driven-development`
- `superpowers:using-git-worktrees`
- `superpowers:verification-before-completion`

These may be hard to disable independently because they ship with the Superpowers plugin, which Forge needs.

### Optional / candidate for disabling or project-scoping

- Caveman plugin family:
  - `caveman`
  - `caveman:caveman`
  - `caveman:caveman-commit`
  - `caveman:caveman-help`
  - `caveman:caveman-review`
  - `caveman:compress`
- General-purpose user skills:
  - `find-skills`
  - `grill-me`
  - `grill-with-docs`
  - `handoff`
  - `humanizer`
  - `impeccable`
  - `improve-codebase-architecture`
  - `prototype`
  - `to-issues`
  - `to-prd`
  - `triage`
  - `write-a-skill`
  - `deep-research`
- Claude Code helpers:
  - `update-config`
  - `keybindings-help`
  - `verify`
  - `code-review`
  - `fewer-permission-prompts`
  - `loop`
  - `schedule`
  - `claude-api`
  - `run`
  - `init`
  - `review`
  - `security-review`

## Installed plugin state observed

From `~/.claude/plugins/installed_plugins.json`:

- `caveman@caveman` — user scope
- `superpowers@claude-plugins-official` — user scope
- `frontend-design@claude-plugins-official` — project scope for PartsBot; enabled by Forge templates where configured
- `pr-review-toolkit@claude-plugins-official` — project scope for PartsBot; enabled by Forge templates where configured
- `pyright-lsp@claude-plugins-official` — project scope for another repo (`ccs-integration`)

## Notes

- Disabling `caveman@caveman` repo-locally removed caveman hook context and saved ~1.4k startup context tokens in `forge-empty`, but the generic `skill_listing` still included caveman entries.
- Superpowers appears necessary for Forge workflows and should not be removed during normal Forge startup-overhead work.
- The skill listing itself is a visible ~3.5k rough-token contributor. Meaningful reduction probably requires reducing globally available skills/plugins, not only disabling hook behavior.
