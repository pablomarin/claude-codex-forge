# Codex Second Opinion

> **Get a second opinion from OpenAI's Codex CLI.**
> Use for code reviews, design plan reviews, architecture feedback, or general questions.
> For multi-perspective analysis with 5 advisors, use `/council <question>` instead.

---

## Prerequisites

- **Codex CLI** installed: `npm i -g @openai/codex` or `brew install --cask codex`
- **Codex authenticated**: `codex login` (requires ChatGPT Plus/Pro/Business or API key)
- Verify: `codex --version` (requires v0.114.0+)

> **PTY shim — work around openai/codex#19945.** All `codex exec` invocations below
> go through `.claude/hooks/lib/codex-pty.sh exec ...` (or `.ps1` on Windows). The
> shim allocates a pseudo-terminal so `codex exec` produces real output — without it,
> codex 0.124–0.12X.0 silently exits 0 with empty stdout under Claude Code's no-TTY
> Bash tool. To bypass the shim (e.g., to confirm upstream fix), set
> `CLAUDE_FORGE_CODEX_PTY_BYPASS=1`.

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
- **Empty output**: Report that Codex returned no output and suggest rephrasing

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

## Powerful `-c` Config Overrides

These work on **both** `codex exec` and `codex exec review`:

| Config key                | Purpose                                                    | Example                                                                 |
| ------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------- |
| `model`                   | Override the session model                                 | `-c model="gpt-5.5"`                                                    |
| `model_reasoning_effort`  | Depth of reasoning                                         | `-c model_reasoning_effort="xhigh"` (minimal\|low\|medium\|high\|xhigh) |
| `model_reasoning_summary` | Reasoning output detail                                    | `-c model_reasoning_summary="detailed"` (auto\|concise\|detailed\|none) |
| `developer_instructions`  | Inject guidance (works WITH preset review flags)           | `-c developer_instructions="Focus on SQL injection"`                    |
| `review_model`            | Model override just for `/review`                          | `-c review_model="gpt-5.5"`                                             |
| `web_search`              | Allow live docs lookup during review                       | `-c web_search=live` (disabled\|cached\|live)                           |
| `service_tier`            | Processing tier                                            | `-c service_tier="fast"` (flex\|fast)                                   |
| `approval_policy`         | When to pause for confirmation (plain `exec` only)         | `-c approval_policy="on-request"` (untrusted\|on-request\|never)        |
| `sandbox_mode`            | Sandbox policy as config (alternative to `--sandbox` flag) | `-c sandbox_mode="read-only"`                                           |

## Other Useful Flags

| Flag                              | Purpose                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| `--ephemeral`                     | Don't persist session files (use for one-shot reviews)         |
| `-o/--output-last-message <FILE>` | Write just the final message to a file — great for scripting   |
| `--json`                          | Emit JSONL events for downstream automation                    |
| `--full-auto`                     | Low-friction preset: `-a on-request --sandbox workspace-write` |
| `--title "description"`           | Label the review in the summary (review subcommand only)       |
| `--skip-git-repo-check`           | Allow running outside a Git repository                         |
