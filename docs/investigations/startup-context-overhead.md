# Startup Context Overhead Investigation

## Purpose

Measure and reduce the context tokens present at the start of a fresh Forge-enabled Claude Code session before meaningful work begins.

This is separate from `docs/investigations/context-efficiency.md`, which focuses on workflow context growth during `/new-feature` and `/fix-bug` runs.

Action plan for the largest proven rule lever: `docs/investigations/testing-progressive-disclosure-plan.md`.

## Problem statement

A fresh session in a Forge-enabled repo can start with a large context floor. In PartsBot, a new session after only `hi` measured roughly:

```text
input_tokens: 9,639
cache_read_input_tokens: 18,829
cache_creation_input_tokens: 34,003
total context_tokens: 62,471
output_tokens: 17
```

This means significant token budget is spent before any task-specific work starts. Even if much of it is cached, it still contributes to context-rot risk because it is prompt context the model must attend around.

## Scope

Focus on startup overhead that is **introduced, amplified, or shaped by Forge**.

Classify sources by control level:

| Class | Examples | Forge control level |
| --- | --- | --- |
| Direct Forge | `CLAUDE.template.md`, `.claude/rules/*.md`, hook outputs, state template | High |
| Forge-enabled | required plugins, skill listings, superpowers bootstrap | Medium |
| Downstream project | project-specific `CLAUDE.md`, accumulated local memory | Partial |
| Claude Code baseline | system prompt, tool schemas, core runtime context | Low |

## Baseline measurements

### Minimal non-Forge empty folder

Repo/folder inspected: `/home/aescala82/projects/forge-empty`

User-visible Claude Code meter after `hi`: `30.0k/1.0M (3%)`

Transcript measurement:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-forge-empty/abe7a33e-63f1-4743-8437-a8c8e6058f6b.jsonl
first assistant usage:
  input_tokens: 8,205
  cache_read_input_tokens: 18,526
  cache_creation_input_tokens: 3,299
  context_tokens: 30,030
  output_tokens: 28
```

Autoload/source sizes:

```text
~/.claude/CLAUDE.md                              ~780 rough tokens
project CLAUDE.md                               none
project .claude/rules/*.md                      none
project MEMORY.md                               none
```

Startup transcript attachment rough sizes:

```text
SessionStart superpowers bootstrap              ~1,497 rough tokens
caveman startup                                 ~923 rough tokens
SessionStart additional context                 ~1,473 rough tokens
skill_listing                                   ~3,532 rough tokens
UserPromptSubmit caveman context                ~31 rough tokens
```

30k baseline contributor inventory:

| Contributor | Evidence | Approx size / status | Control level |
| --- | --- | ---: | --- |
| Claude Code core system prompt + tool schemas + runtime protocol | Not directly visible in JSONL as text; inferred remainder after visible payloads | ~20k+ context tokens | Low |
| Global `~/.claude/CLAUDE.md` | File size | ~780 rough tokens | Medium |
| Superpowers startup / `using-superpowers` context | `SessionStart` hook output + `hook_additional_context` | ~1.5k rough tokens actual injected; hook log duplicates appear in transcript | Medium/low if Forge depends on superpowers |
| Caveman startup mode | `SessionStart` hook output | ~923 rough tokens | Medium |
| Caveman per-prompt reinforcement | `UserPromptSubmit` additional context | ~31 rough tokens/turn | Medium |
| Skill listing | `skill_listing` attachment, 50 entries | ~3.5k rough tokens | Medium; depends on installed skills/plugins |
| Project `CLAUDE.md` | Absent in empty folder | 0 | High for downstream projects |
| Project `.claude/rules/*.md` | Absent in empty folder | 0 | High for Forge installs |
| Project memory `MEMORY.md` | Missing | 0 | Medium |
| Metadata (`mode`, `permission-mode`, `file-history-snapshot`, empty tool deltas) | JSONL records | negligible visible payload | Low |

Initial conclusion: on this machine, an empty non-Forge folder already starts around **30k context tokens**. The visible/global contributors explain only part of that floor; a large opaque Claude Code/system/tool baseline remains. This is not Forge project-template overhead, but Forge can still amplify it through enabled plugins/skills and global setup.

### Minimal Forge-installed repo

Repo/folder inspected: `/home/aescala82/projects/forge-empty`

Installed from this checkout:

```text
FORGE_VERSION=5.54
FORGE_SOURCE_DIR=/home/aescala82/projects/forge-dev
FORGE_SOURCE_REVISION=582ba29-dirty
```

User-visible Claude Code meter after `hi`: `56.0k/1.0M (6%)`

Transcript measurement:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-forge-empty/1946951e-795a-4906-a2b9-e9fb8019fc43.jsonl
first assistant usage:
  input_tokens: 9,488
  cache_read_input_tokens: 18,829
  cache_creation_input_tokens: 27,705
  context_tokens: 56,022
  output_tokens: 44
```

Autoload/source sizes:

```text
~/.claude/CLAUDE.md                              ~780 rough tokens
forge-empty/CLAUDE.md                         ~1,849 rough tokens
forge-empty/.claude/rules/*.md total          ~16,951 rough tokens
project MEMORY.md                               none
```

Largest direct Forge rule contributors:

```text
testing.md      ~7,852 rough tokens
workflow.md     ~2,812 rough tokens
security.md     ~1,222 rough tokens
skill-audit.md  ~1,073 rough tokens
database.md       ~951 rough tokens
```

Startup transcript attachment rough sizes:

```text
SessionStart superpowers bootstrap              ~1,497 rough tokens
SessionStart Forge branch context                 ~44 rough tokens
caveman startup                                  ~923 rough tokens
SessionStart additional context                 ~1,493 rough tokens
skill_listing                                   ~3,956 rough tokens
UserPromptSubmit caveman context                  ~31 rough tokens
```

Delta from empty non-Forge baseline:

```text
56,022 - 30,030 = 25,992 additional startup context tokens
```

Initial conclusion: a fresh Forge install adds roughly **26k context tokens** over the same empty folder's non-Forge baseline on this machine. The rough file-size attribution (~18.8k tokens from project `CLAUDE.md` + `.claude/rules`) explains most of the delta; the rest is likely cache-tokenization/system/tool effects from the additional installed settings/hooks/plugins.

### Minimal Forge with caveman disabled repo-locally

Repo/folder inspected: `/home/aescala82/projects/forge-empty`

Change tested:

```json
"enabledPlugins": {
  "caveman@caveman": false
}
```

User-visible Claude Code meter after `hi`: `54.6k/1.0M (5%)`

Transcript measurement:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-forge-empty/e2381f2c-1332-4c02-9779-4043b396319e.jsonl
first assistant usage:
  input_tokens: 8,065
  cache_read_input_tokens: 46,534
  cache_creation_input_tokens: 0
  context_tokens: 54,599
  output_tokens: 267
```

Startup transcript attachment change:

```text
Removed:
  CAVEMAN MODE ACTIVE SessionStart body        ~923 rough tokens
  UserPromptSubmit caveman reminder             ~31 rough tokens

Still present:
  skill_listing includes caveman entry        ~3,531 rough tokens total listing
```

Delta from minimal Forge with caveman active:

```text
56,022 - 54,599 = 1,423 fewer startup context tokens
```

Initial conclusion: repo-local plugin override successfully disables caveman behavior and removes caveman hook context, but the savings are modest (~1.4k context tokens). The caveman skill still appears in the generic skill listing, so disabling the plugin hook does not remove all caveman-related availability/listing overhead.

### Minimal Forge with caveman disabled and `workflow.md` removed

Repo/folder inspected: `/home/aescala82/projects/forge-empty`

Change tested:

```text
Move .claude/rules/workflow.md out of .claude/rules/
Keep caveman disabled repo-locally.
Keep testing.md present.
```

User-visible Claude Code meter after `hi`: `50.4k/1.0M (5%)`

Transcript measurement:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-forge-empty/550b87de-7d25-4ac8-bb96-ccf5d1ffcadd.jsonl
first assistant usage:
  input_tokens: 8,065
  cache_read_input_tokens: 18,829
  cache_creation_input_tokens: 23,505
  context_tokens: 50,399
  output_tokens: 280
```

Delta from minimal Forge with caveman disabled:

```text
54,599 - 50,399 = 4,200 fewer startup context tokens
```

Initial conclusion: `workflow.md` is also a meaningful startup lever, but smaller than `testing.md`. Its rough file size is ~2.8k tokens; measured savings were ~4.2k context tokens.

### Minimal Forge with caveman disabled and `testing.md` removed

Repo/folder inspected: `/home/aescala82/projects/forge-empty`

Change tested:

```text
Move .claude/rules/testing.md out of .claude/rules/
Keep caveman disabled repo-locally.
```

User-visible Claude Code meter after `hi`: `43.6k/1.0M (4%)`

Transcript measurement:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-forge-empty/dd570ef7-6088-4d70-adb2-7f5807be092c.jsonl
first assistant usage:
  input_tokens: 8,065
  cache_read_input_tokens: 18,829
  cache_creation_input_tokens: 16,662
  context_tokens: 43,556
  output_tokens: 286
```

Remaining autoload/source sizes:

```text
~/.claude/CLAUDE.md                              ~780 rough tokens
forge-empty/CLAUDE.md                         ~1,849 rough tokens
forge-empty/.claude/rules/*.md total          ~9,099 rough tokens (without testing.md)
project MEMORY.md                               none
```

Delta from minimal Forge with caveman disabled:

```text
54,599 - 43,556 = 11,043 fewer startup context tokens
```

Delta from minimal Forge with caveman active:

```text
56,022 - 43,556 = 12,466 fewer startup context tokens
```

Initial conclusion: `testing.md` is a major startup lever. Its rough file size is ~7.9k tokens, but removing it reduced measured startup context by ~11k tokens, likely due to tokenizer/cache/system effects around autoloaded rule content. This strongly supports progressive disclosure for testing rules.

### PartsBot Forge repo

Repo inspected: `/home/aescala82/projects/partsbot`

Fresh `hi` session transcript:

```text
transcript: ~/.claude/projects/-home-aescala82-projects-partsbot/bcfb9929-0c17-45a8-84d0-00f1e063b7b7.jsonl
first assistant usage:
  input_tokens: 9,639
  cache_read_input_tokens: 18,829
  cache_creation_input_tokens: 34,003
  context_tokens: 62,471
```

Approximate autoload/source sizes from PartsBot:

```text
~/.claude/CLAUDE.md                              ~780 rough tokens
partsbot/CLAUDE.md                             ~4,850 rough tokens
partsbot/.claude/rules/*.md total             ~16,950 rough tokens
partsbot MEMORY.md                              ~369 rough tokens
```

Largest direct Forge rule contributors:

```text
testing.md      ~7,852 rough tokens
workflow.md     ~2,812 rough tokens
security.md     ~1,222 rough tokens
skill-audit.md  ~1,073 rough tokens
```

Startup transcript attachment rough sizes:

```text
skill_listing                         ~4,350 rough tokens
SessionStart superpowers/caveman      ~2,400–3,000 rough tokens
```

## Initial conclusions

- The non-Forge startup baseline on this machine is already about 30k context tokens after a trivial `hi`.
- A minimal Forge install starts at about 56k context tokens after `hi`, adding roughly 26k tokens over the non-Forge baseline.
- Disabling caveman repo-locally drops minimal Forge startup to about 54.6k, saving only about 1.4k context tokens.
- Removing `workflow.md` from autoload drops minimal Forge+caveman-disabled startup to about 50.4k, saving about 4.2k context tokens.
- Removing `testing.md` from autoload drops minimal Forge+caveman-disabled startup to about 43.6k, saving about 11k context tokens.
- PartsBot's startup floor is real: about 62.5k context tokens after a trivial `hi`.
- PartsBot's downstream/project-specific marginal overhead over minimal Forge is roughly 6.5k context tokens; its total Forge/downstream marginal overhead over the empty-folder baseline is roughly 32.4k context tokens.
- Auto memory is **not** the main culprit in this case; `MEMORY.md` is small and index-like.
- The biggest Forge-shaped contributors appear to be:
  - autoloaded project/rule files
  - heavy universal rules, especially `testing.md`
  - plugin/skill startup/listing overhead
  - project `CLAUDE.md` size
- Claude Code baseline/tool schemas account for a large fixed floor that Forge may not control directly.

## Related bug surfaced during PartsBot inspection

Status: fixed in source templates/hooks after this investigation. The active-session guards now require a lowercase UUID-shaped nonce, and `state.template.md` no longer contains a parseable placeholder nonce table.

PartsBot `.claude/local/state.md` still contained the template placeholder `/goal session` table:

```markdown
| nonce            | <uuid-v4-lowercase>                    |
| workflow_command | /new-feature <name> OR /fix-bug <name> |
```

Current hooks appeared to treat the placeholder nonce as an active `/goal` session, causing Stop output after a trivial `hi`:

```text
FORGE_GOAL_STUCK_WARNING: no measurable progress for 41 consecutive turns...
FORGE_GOAL_EVIDENCE_BEGIN ...
```

This is not the cause of the first-turn 62.5k startup floor, but it creates per-turn noise and should be fixed. Placeholder/sample state must not count as an active `/goal` session.

## Measurement plan

For each Forge-enabled repo tested:

1. Start a fresh session and send only `hi`.
2. Inspect the first assistant usage row in:

   ```text
   ~/.claude/projects/<project-key>/*.jsonl
   ```

3. Record:

   ```text
   startup_context_tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
   startup_output_tokens
   startup attachment sizes
   source rough sizes for CLAUDE.md, rules, memory
   enabled plugins
   ```

4. Separate:
   - Forge-controlled files
   - project-specific files
   - plugin/skill overhead
   - unknown Claude Code baseline

## Candidate reductions

### Tier S0 — Startup metrics and attribution

- Extend or complement `scripts/context-metrics.py` with a startup-focused report. Done via:

  ```bash
  scripts/context-metrics.py --project-root /home/aescala82/projects/forge-empty --startup
  scripts/context-metrics.py --project-root /home/aescala82/projects/forge-empty --startup --all-sessions
  ```

- Report first-turn context tokens per session.
- Report largest pre-first-turn attachments.
- Report rough token sizes for autoloaded files.

### Tier S1 — Fix false active `/goal` detection

- Hooks should treat placeholder nonce values like `<uuid-v4-lowercase>` as inactive.
- `state.template.md` may also avoid including table rows that look parseable as active state.
- Maintain `.sh` / `.ps1` parity.

### Tier S2 — Slim universal autoloaded rules

- Keep only always-needed invariants in autoloaded rules.
- Move long phase-specific guidance into command files, skills, or referenced docs loaded on demand.
- Prime candidates:
  - `rules/testing.md`
  - `rules/workflow.md`
  - `rules/security.md`
  - `rules/skill-audit.md`

### Tier S3 — Slim project `CLAUDE.template.md`

- Keep project overview, hard invariants, and navigation.
- Move long reference lists and examples into docs.
- Preserve enough context for safe first actions.

### Tier S4 — Progressive disclosure for Forge docs/rules

- Convert large rules to index + targeted references.
- Load detailed rules only when phase/task requires them:
  - testing details during test design and verification
  - security details for auth/secrets/payment/data surfaces
  - frontend details for UI work
  - database details for schema/migration work

### Tier S5 — Plugin/skill startup overhead review

- Identify which enabled plugins inject startup content or large skill listings.
- Determine what Forge controls through `settings.template.json` and what is Claude Code/plugin behavior.
- Avoid disabling quality-critical plugins blindly; measure first.

## Guardrails

- Do not remove safety-critical rules without replacing them with reliable on-demand loading.
- Do not weaken workflow gates or evidence contracts.
- Preserve first-turn safety for dangerous operations, secrets, worktrees, and branch hygiene.
- Maintain Bash + PowerShell parity for hook fixes.
- Distinguish Forge overhead from downstream project-specific bloat before changing templates.

## Open questions

- Which autoload surfaces are controlled by Claude Code vs Forge templates?
- Are `.claude/rules/*.md` always loaded in full, or can they be selectively loaded by naming/config?
- Can Forge use a small always-loaded rule index that instructs agents to read detailed rules only when needed?
- How much startup floor remains in a minimal non-Forge repo on the same machine?
- How much comes from enabled plugin skill listing, and can it be reduced without losing required workflows?

## Progress log

- [x] Created startup-overhead investigation document.
- [x] Measured minimal non-Forge empty-folder baseline on same machine (~30.0k context tokens).
- [x] Measured minimal Forge-installed baseline on same folder (~56.0k context tokens).
- [x] Measured minimal Forge with caveman disabled repo-locally (~54.6k context tokens).
- [x] Measured minimal Forge with caveman disabled and `workflow.md` removed from autoload (~50.4k context tokens).
- [x] Measured minimal Forge with caveman disabled and `testing.md` removed from autoload (~43.6k context tokens).
- [x] Captured initial PartsBot fresh-session measurement (~62.5k context tokens).
- [x] Verified PartsBot memory is small and not the main startup source.
- [x] Identified false active `/goal` placeholder issue.
- [x] Add startup-focused metrics/reporting (`scripts/context-metrics.py --startup`).
- [ ] Measure Forge repo after disabling/removing candidate autoload sources in controlled experiments.
- [x] Fix placeholder `/goal` active-session detection.
- [ ] Evaluate rule/progressive-disclosure redesign.
