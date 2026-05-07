# Codex Second Opinion

> **Get a second opinion from OpenAI's Codex CLI.**
> Use for code reviews, design plan reviews, architecture feedback, or general questions.
> For multi-perspective analysis with 5 advisors, use `/council <question>` instead.

---

## Prerequisites

- **Codex CLI** installed: `npm i -g @openai/codex` or `brew install --cask codex`
- **Codex authenticated**: `codex login` (requires ChatGPT Plus/Pro/Business or API key)
- Verify: `codex --version` (requires v0.114.0+)

> **Use `.claude/hooks/lib/codex-pty.sh exec` for all Codex invocations** (Windows: `.claude/hooks/lib/codex-pty.ps1 exec`). Do not call bare `codex exec` from Claude Code.

---

## Mode Detection

Analyze `$ARGUMENTS` to determine the mode:

- **Code Review Mode**: Arguments match review-related keywords — "review code", "code review", "review changes", "review diff", "review PR", or bare "review"
- **Design Review Mode**: Arguments reference a plan, design, or architecture — "review the plan", "review the design", "review architecture"
- **General Mode**: Everything else (give opinion, analyze code, brainstorm, ask a question)

---

## A) Code Review Mode

Triggered when `$ARGUMENTS` matches review-related keywords.

### Step 1: Ask what to review

Use `AskUserQuestion` with these options:

| Option                                  | Flag                                |
| --------------------------------------- | ----------------------------------- |
| Uncommitted changes (staged + unstaged) | `--uncommitted`                     |
| Changes vs main branch                  | `--base main`                       |
| A specific commit                       | `--commit <SHA>` (ask user for SHA) |

### Step 2: Run Codex review

> **IMPORTANT:** `codex exec review` preset flags (`--uncommitted`, `--base`, `--commit`) cannot be combined with a custom prompt argument. Use `-c developer_instructions=` to inject focus areas instead.
>
> **NOTE:** The `exec review` subcommand does NOT accept `--sandbox` or `--color` flags (reviews are inherently read-only). These flags are only valid on `codex exec` (general mode).

```bash
.claude/hooks/lib/codex-pty.sh exec review \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  -c web_search="live" \
  -c developer_instructions="Focus on: correctness, security vulnerabilities, performance bottlenecks, error handling gaps, and maintainability. Flag anything that could break in production." \
  --ephemeral \
  [--uncommitted | --base main | --commit SHA]
```

**If reviewing a branch**, add `--title` for context:

```bash
.claude/hooks/lib/codex-pty.sh exec review \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  -c web_search="live" \
  -c developer_instructions="Focus on: correctness, security vulnerabilities, performance bottlenecks, error handling gaps, and maintainability. Flag anything that could break in production." \
  --ephemeral \
  --base main \
  --title "feat: add user authentication"
```

**Timeout: 1200000ms (20 minutes)** — Codex reasoning can take time.

### Step 3: Display output

Display Codex's output verbatim to the user. Do not summarize or edit it.

---

## B) Design Review Mode

Triggered when `$ARGUMENTS` references a plan, design, or architecture document.

This is used during the **mandatory design review step** (Phase 3.3 of `/new-feature` and `/fix-bug`).

### Step 1: Identify the plan

Check for the most recent plan file:

```bash
ls -t docs/plans/ 2>/dev/null | head -1
```

Also check if there's a plan in the current conversation context. If the user specified a file, use that.

### Step 2: Run Codex exec with the plan

```bash
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  -c web_search="live" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  "Review the implementation plan in [plan file path]. Evaluate:
  1. ARCHITECTURE: Are there design flaws or over-engineering?
  2. RISK: What could go wrong? What edge cases are missing?
  3. IMPLEMENTATION: Does the plan account for what the code actually looks like today?
  4. DEPENDENCIES: Are there breaking changes or version conflicts?
  5. TESTING: Is the plan testable? What's hard to test?
  Flag any concerns that should be addressed BEFORE implementation begins.
  Note: If an Engineering Council already validated the approach, focus on implementation correctness rather than revisiting the strategic choice."
```

**Timeout: 1200000ms (20 minutes)** — Codex reasoning can take time.

### Step 3: Display output

Display Codex's output verbatim to the user. Do not summarize or edit it.

---

## C) General Mode

Triggered for everything that isn't a code review or design review request.

### Step 1: Gather context

Run these in parallel for situational awareness:

```bash
git diff --stat
```

```bash
git status --short
```

If the user's instruction references a specific file, read that file to include as context.

### Step 2: Run Codex exec

Construct the prompt by combining the user's instruction with the gathered context.

```bash
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  -c web_search="live" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  "{user's instruction with gathered context}"
```

**Timeout: 1200000ms (20 minutes)** — Codex reasoning can take time.

### Step 3: Display output

Display Codex's output verbatim to the user. Do not summarize or edit it.

---

## Error Handling

- **Codex not installed**: Tell the user to run `npm i -g @openai/codex` (or `brew install --cask codex` on macOS) and `codex login`
- **Authentication error**: Tell the user to run `codex login`
- **Timeout**: Inform the user that Codex took too long and suggest simplifying the request
- **Empty output / silent exit**: Treat as a Codex invocation failure, not a useful model response. Do not rephrase the prompt as a workaround. Tell the user Codex returned no output and that the local Codex/PTY wrapper setup needs repair outside this `/codex` run.

---

## Quick Reference

| Use case                   | Command pattern                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| Review uncommitted changes | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --uncommitted`                     |
| Review branch vs main      | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --base main --title "description"` |
| Review a specific commit   | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --commit SHA`                      |
| Review a design plan       | `.claude/hooks/lib/codex-pty.sh exec --sandbox read-only --ephemeral "Review the plan..."` |
| General second opinion     | `.claude/hooks/lib/codex-pty.sh exec --sandbox read-only --ephemeral "Your question..."`   |

---

## Flag Reference — What Works Where

**`codex exec review` (subcommand) flags:**
`-c key=value`, `--uncommitted`, `--base <BRANCH>`, `--commit <SHA>`, `-m/--model`, `--title`, `--ephemeral`, `--json`, `-o/--output-last-message`, `--full-auto`, `--skip-git-repo-check`, `--enable/--disable <FEATURE>`.

**NOT valid on `exec review`** (but valid on plain `codex exec`):
`--sandbox`, `--color`, `-i/--image`, `-C/--cd`, `--add-dir`, `--output-schema`, `-p/--profile`, `--oss`.

**Mutually exclusive on `exec review`:** preset flags (`--uncommitted`, `--base`, `--commit`) cannot be combined with a positional `[PROMPT]`. Pick one:

- **Preset scope + focus via config**: `codex exec review --uncommitted -c developer_instructions="Focus on auth flows"`
- **Custom prompt only** (reviewer picks scope from your wording): `codex exec review "Audit the recent auth middleware changes for token leakage"`

## `-c` config overrides used in this command

These are the only `-c` overrides used by the canonical examples above:

| Config key               | Why this command uses it                                                                                                                                                                                                                            |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `model`                  | Pin the session to gpt-5.5 (overrides whatever the user has as default in `~/.codex`)                                                                                                                                                               |
| `model_reasoning_effort` | `xhigh` — Codex is being used as a serious second opinion, not a quick autocomplete                                                                                                                                                                 |
| `service_tier`           | `fast` — prioritise latency for the review/feedback loop                                                                                                                                                                                            |
| `web_search`             | `live` — make the live web-search tool available to the model when it decides it needs current docs/issue status. Not "always search." Codex's default is documented inconsistently (some sources say `disabled`, others `cached`); set explicitly. |
| `developer_instructions` | Inject focus areas for code-review mode (compatible with `--uncommitted`/`--base` etc.)                                                                                                                                                             |

For other `-c` overrides not listed here, consult `codex --help` rather than improvising.

## Flags used by this command

`--ephemeral`, `--sandbox read-only`, `--color never`, `--skip-git-repo-check`, `--uncommitted` / `--base <BRANCH>` / `--commit <SHA>` / `--title <STR>` (review-mode only). Do not introduce other flags inside `/codex` — they're not part of this command's contract.
