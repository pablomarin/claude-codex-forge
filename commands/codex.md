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
- **Investigate Mode**: The task needs reach a hermetic sandbox denies — it requires ANY of: project credentials, network access, external systems (DB / cloud / API), live data, or non-hermetic execution. Detected by **capability-need, not by guessing intent** — e.g. "have Codex dig into the data", "give Codex DB access to find the cause", "let Codex actually run X against the live system". Check this BEFORE falling through to General.
- **General Mode**: Everything else (give opinion, analyze code, brainstorm, ask a question) — stays hermetic (read-only, no network)

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
  -c developer_instructions="Focus on: correctness, security vulnerabilities, performance bottlenecks, error handling gaps, and maintainability. Flag anything that could break in production. If the PR body is a Developer Demo, verify every Mermaid diagram edge traces to a real file:line in its Evidence table — an unsupported or wrong diagram edge (Gate 2 / claimed-current-behavior) is a P1 finding; Gate-1 plan Briefing edges labeled planned/inferred are exempt." \
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
  -c developer_instructions="Focus on: correctness, security vulnerabilities, performance bottlenecks, error handling gaps, and maintainability. Flag anything that could break in production. If the PR body is a Developer Demo, verify every Mermaid diagram edge traces to a real file:line in its Evidence table — an unsupported or wrong diagram edge (Gate 2 / claimed-current-behavior) is a P1 finding; Gate-1 plan Briefing edges labeled planned/inferred are exempt." \
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

## D) Investigate Mode

The ONLY mode that enables network + execution. A deliberate escalation — used
when the task needs to reach real systems (debug, reverse-engineer, data-spelunk),
so Codex can be a peer investigator with real hands on the data instead of reading
code in a sandbox vacuum. It is never the default; the hermetic modes (A/B/C) stay
read-only + no-network by contract.

> **Decision rationale** (see `docs/adr/` for the ADR): Investigate is gated by
> **capability-need, not task-type**, and its repo boundary is enforced by the
> **Codex sandbox, not by prompt text** — because Codex itself may be steered by
> malicious content in the data it reads.

### Three hard constraints — NON-NEGOTIABLE

1. **Sandbox-confined to the repo.** Launch with `--sandbox workspace-write`
   `-c sandbox_workspace_write.network_access=true` and `-C "$(pwd)"`. NEVER
   `--sandbox danger-full-access`. This flag — not a sentence in the prompt — is
   what prevents prompt-injected writes to `~/.ssh`, shell profiles, or global
   config. The boundary must be the sandbox because Codex may be injected by the
   very data it inspects.
2. **Never prompt the user.** YOU (Claude) provision Codex from what you already
   have. The credentials are already in the project's `.env`/config; handing the
   SAME read-only access to Codex is lateral, not a new escalation, so it needs no
   fresh consent. Do NOT use `AskUserQuestion`. **This is critical inside a
   `/forge-goal` `/goal` run** (`## /goal session` has a non-empty nonce): a prompt
   would break the autonomous loop, where `AskUserQuestion` is reserved solely for
   PR creation (see `rules/workflow.md`).
3. **Read-only / never mutate** external systems — use the narrowest role available
   (e.g. a SELECT-only DB role). This mode investigates; it never changes things. A
   task that needs to mutate is implementation, not investigation — route it through
   the normal `/new-feature` or `/fix-bug` workflow.

### Step 1: Provision Codex with this project's connection surface

YOU are the agent that already knows how this project reaches its systems. Equip
Codex the way you would operate yourself — the mechanism is project-specific and
you choose it: an MCP server, a project CLI, or a thin `.env`-sourced runner;
whatever this repo uses. Rules:

- **Credentials come from `.env`/config — NEVER in argv, the prompt, or anything
  that lands in logs.** A small runner that reads `.env` itself is the safe pattern.
- **Write the brief + any runner + Codex's output ONLY to a gitignored in-repo
  path** (e.g. `.claude/local/investigate/`). The autonomous loop already writes
  there without prompting, and it keeps everything inside the sandbox boundary.
- **Write a brief** (`.claude/local/investigate/CONTEXT.md`): the question, allowed
  data sources, forbidden actions, acceptance criteria, and the expected output
  (finding + reproduction steps + uncertainty + next checks).

### Step 2: Launch Codex with reach

```bash
mkdir -p .claude/local/investigate
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  -c web_search="live" \
  --sandbox workspace-write \
  -c sandbox_workspace_write.network_access=true \
  --ephemeral \
  -C "$(pwd)" \
  --output-last-message .claude/local/investigate/finding.txt \
  "$(cat .claude/local/investigate/CONTEXT.md)"
```

> **Pin the exact network/execution flags against `codex --help`** for your Codex
> version. `--sandbox danger-full-access` removes sandboxing entirely (do NOT use —
> it breaks constraint 1); `workspace-write` + `network_access=true` is the
> repo-confined default that gives network without surrendering the filesystem
> boundary.

**Timeout: 1200000ms (20 minutes)** — investigations iterate; allow time. Run in
the background and poll the output file if the dig is long.

### Step 3: Cross-verify before trusting (MANDATORY)

Codex's finding is a hypothesis until independently reproduced. Codex must return
an **evidence packet**: hypothesis, exact queries/commands, parameters, row
counts / checksums, before-after values, caveats. YOU then reproduce it
independently — ideally with your own separately-written queries — and confirm:
same sources, same filters/window, matching counts (or explained deltas), matching
result within tolerance, plus one control/negative check. Only a finding with
attached reproduction is trusted or acted on. **"Codex said so" is not
verification.**

### Step 4: Display + report

Display Codex's finding verbatim, then state your independent verification result
(reproduced / failed-to-reproduce / partial) BEFORE any recommendation.

> **Accepted residual** (the Forge's threat model per `rules/security.md` is
> single-user, local-only): read-only + network + credentials still carries
> credit-burn, prompt-injection-via-inspected-data, and credential-exposure-via-
> network exposure. This is NOT engineered around — Claude already carries the
> identical exposure when it investigates directly. Do not add budget/egress
> machinery for the single-user case.

---

## Error Handling

- **Codex not installed**: Tell the user to run `npm i -g @openai/codex` (or `brew install --cask codex` on macOS) and `codex login`
- **Authentication error**: Tell the user to run `codex login`
- **Timeout**: Inform the user that Codex took too long and suggest simplifying the request
- **Empty output / silent exit**: Treat as a Codex invocation failure, not a useful model response. Do not rephrase the prompt as a workaround. Tell the user Codex returned no output and that the local Codex/PTY wrapper setup needs repair outside this `/codex` run.

---

## Quick Reference

| Use case                   | Command pattern                                                                                                                                                                      |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Review uncommitted changes | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --uncommitted`                                                                                                               |
| Review branch vs main      | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --base main --title "description"`                                                                                           |
| Review a specific commit   | `.claude/hooks/lib/codex-pty.sh exec review --ephemeral --commit SHA`                                                                                                                |
| Review a design plan       | `.claude/hooks/lib/codex-pty.sh exec --sandbox read-only --ephemeral "Review the plan..."`                                                                                           |
| General second opinion     | `.claude/hooks/lib/codex-pty.sh exec --sandbox read-only --ephemeral "Your question..."`                                                                                             |
| Investigate (live systems) | `.claude/hooks/lib/codex-pty.sh exec --sandbox workspace-write -c sandbox_workspace_write.network_access=true --ephemeral -C "$(pwd)" "$(cat .claude/local/investigate/CONTEXT.md)"` |

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

`--ephemeral`, `--sandbox read-only`, `--color never`, `--skip-git-repo-check`, `--uncommitted` / `--base <BRANCH>` / `--commit <SHA>` / `--title <STR>` (review-mode only).

**Investigate mode only** (Section D): `--sandbox workspace-write`, `-c sandbox_workspace_write.network_access=true`, `-C "$(pwd)"`. `--sandbox danger-full-access` is explicitly forbidden — it breaks the repo-confined boundary that makes Investigate safe.

Do not introduce other flags inside `/codex` — they're not part of this command's contract.
