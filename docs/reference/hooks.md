# Hooks Reference

Forge v6 installs canonical hook logic under `.forge/hooks/`. Claude Code and Codex adapters route
their native events into the same policy.

## Hooks (Run Automatically)

| Hook | Trigger | What happens |
| --- | --- | --- |
| `SessionStart` | New/resumed host session, clear, or compaction | Runs the stable host-context compatibility no-op, then injects branch, state, and drift context; remote fetch remains source-gated |
| `UserPromptSubmit` | Before each user prompt | Runs the same stable host-context compatibility no-op; it creates no worktree or session authority |
| `Stop` | Main host finishes a turn | Builds candidate evidence and reminds the host to keep an unfinished workflow's `.forge/local/state.md` current |
| `PreToolUse` | Before a shell command | Audits commands, blocks dangerous patterns, enforces workflow evidence, and checks protected external-mutation authority |
| `PostToolUse` | After supported file writes | Runs the configured formatter |
| `PreCompact` | Before context compression | Ensures the volatile memory directory exists and logs a diagnostic; it does not claim to inject a save instruction into model context |
| `SubagentStop` | Reviewer/producer finishes | Validates structured, candidate-bound review output |
| `ConfigChange` | Claude Code configuration changes | Audits changes and may block managed deny-rule removal in strict mode |

## Host Routing

Claude Code hooks are registered in `.claude/settings.json`; Codex hooks are registered in
`.codex/hooks.json`. The worktree lifecycle helper copies missing Claude settings, Codex config, and
a Codex hook validation mirror without overwriting an existing destination. Codex hook execution
still routes through the primary checkout. Canonical scripts stay in `.forge/hooks/` and read only
the event worktree's `.forge/local/state.md` for current v6 state.

The retained `host-context` hook command is deliberately a compatibility no-op so existing native
hook trust remains stable. `host-context launch` accepts only the canonical agent or council
dispatcher and declares `FORGE_NATIVE_HOST=claude|codex` for reviewer routing. It creates no receipt,
does not authenticate a session, and grants no authority. Candidate, review, verification, state,
goal, authorization, and promotion evidence remain bound to the exact worktree and artifact.

Codex may register a stable router from the primary checkout. For every linked-worktree event,
`codex-worktree-dispatch.{sh,ps1}` validates an absolute event `cwd`, resolves the event repository,
requires the same Git common directory as the registered checkout, and rejects missing or symlinked
canonical hook targets. It then executes the named hook from that event worktree. This selects
the correct worktree only when the host supplies that worktree in the event `cwd`.

Codex hook `cwd` can remain the session directory while `exec_command` runs in a different
`workdir`; its Bash hook payload omits that per-call directory. Forge cannot recover an omitted
directory safely. Before commit, push, or PR creation, use a host session whose workspace is the
task worktree when this limitation applies. Selecting only a tool working directory does not
change the hook context. A Forge refresh repairs its parsers but does not repair this upstream
payload loss. See [Codex issue #33986](https://github.com/openai/codex/issues/33986).

## Goal Evidence Output

`build-evidence.{sh,ps1}` prints Goal markers and JSON only when the canonical Goal nonce is
active. A missing or empty nonce, or the exact template placeholder, keeps ordinary Stop output
quiet. Evidence computation and worktree-local fingerprint updates still run, including when
`check-state-updated` invokes the builder inline. Active Goal output and accounting are unchanged.
For explicit inspection outside Goal, run `build-evidence.sh --diagnostic` or
`build-evidence.ps1 -Diagnostic`; these options emit diagnostics without activating Goal.

## Workflow Gates

`check-state-updated.{sh,ps1}` excludes workflows with `Phase: complete` from stale-receipt
advisories and unchanged-checkpoint continuations. Their recorded command and historical receipts
remain intact. An unfinished workflow still receives the checkpoint reminder, and the
`stop_hook_active` guard prevents recursive continuation. Completion does not bypass canonical
state validation, native Goal accounting, changelog enforcement, or shipping receipt checks.
This behavior is shared by Claude Code and Codex. A completed primary-checkout quick-fix no longer
interrupts a linked feature session with that historical workflow reminder; hook context still
comes from the event `cwd`, under the routing limitations above.

Codex Windows registrations end their PowerShell `-Command` wrapper with `exit $LASTEXITCODE`
so the host receives the router's exact status, including exit 2 for continuation or blocking.
Without explicit propagation, PowerShell maps a nonzero nested result to exit 1. See
[Microsoft's exit-code documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1).

`check-workflow-gates.{sh,ps1}` validates structured receipts bound to the frozen candidate before
commit, push, or PR creation. A successful process exit is not a clean gate. PR authorization is
bound to the active goal nonce and candidate. The exact example nonce `<uuid-v4-lowercase>` is
inactive. Only checked authorization lines inside `## PR authorization` count; duplicates inside
that section use the last line and emit a warning. Checklist and narrative summaries cannot
authorize publication or invalidate the canonical approval.
Artifact-bound review prompts, outputs, and receipts live under `.forge/local/reviews/`.

For an exact `/quick-fix <valid-slug>`, the same hook keeps configuration and Goal authorization
checks, then validates one recorded ancestral base and a maximum of three implementation paths.
Exact `README.md` and `docs/CHANGELOG.md` release metadata is excluded from that path budget. Only
that bounded case skips final review and verifier receipts; malformed commands or invalid scope fall
through to the full fail-closed boundary.

`check-external-mutation-auth.{sh,ps1}` silently defers main-session operations to human authorization
and native host controls; it never emits an automatic allow decision or demands human terminal
execution. Claude templates retain native ask rules for recognized merge, PR, issue-close, publish,
recursive-delete, Kubernetes and curl mutation commands. Codex keeps its native permission controls.
The hook cannot authenticate a chat reply or an agent-written receipt.

Full investigators retain normal project capabilities and carry `FORGE_INVESTIGATION_CHILD=1`.
For recognized consequential commands, the hook blocks the child and directs it to return the
proposed action to the main session for human approval and agent execution. This is defense in
depth for common command forms, not a complete shell parser, MCP policy engine, or security boundary.
Ordinary review sandbox/tool restrictions are unchanged; review launch itself needs no extra consent.
