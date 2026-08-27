# Forge Project Instructions

This file is the canonical, engine-neutral Forge contract. Claude Code and Codex adapters must
read it completely; adapters may translate discovery metadata but may not restate its policy.

## Working Contract

- The agent running in the developer's current host is the main agent for that session. There is
  no permanent main-engine preference and no workflow lease.
- Read `.forge/local/state.md` before resuming work and keep its evidence bound to the exact
  candidate revision. Do not infer a successful gate from execution alone.
- Use the canonical workflows in `.forge/workflows/`, rules in `.forge/rules/`, skills in
  `.forge/skills/`, and roles in `.forge/agents/`.
- A host switch may resume the same branch and worktree. Warn against simultaneous editing, but do
  not create workflow locks.
- Keep developer state, receipts, and local memories under `.forge/local/`; never overwrite them
  during setup. Keep project-owned durable memory under `.forge/memory/`.

## Native Goal Composition

Claude Code and Codex keep their own native `/goal`; Forge never shadows it with a command or skill.
When the developer activates native autonomy, read `.forge/workflows/goal.md` and compose the native
goal over its persistent objective, nonce, turn ceiling/count, checklist, next step, evidence, and
authorization contract. Require the human-created trusted goal authorization record and authenticated
host qualification before activation. Native counters may reset; persistent Forge counters do not.

On `FORGE_GOAL_BUDGET_EXHAUSTED`, checkpoint and stop native autonomy. Treat
`FORGE_GOAL_STUCK_WARNING` as an advisory to inspect progress, not permission to reset the budget.
Resume the exact next unchecked durable step on the same host or a fresh session on the other host;
never claim native session transfer. User input, PR creation, merge, deploy, publish, destructive
work, and any new external mutation pause for explicit human authorization. Ordinary reviewer engine
failure follows automatic visible fallback. If any authenticated native-goal Must behavior is not
proven, report `BLOCKED` and do not claim that host is runtime-ready.

## No Bugs Left Behind

Fix every known correctness, security, verification, or configuration defect in the active scope
before shipping. Do not hide a known defect behind a follow-up task. If access or evidence is
missing, report the result as unverified or blocked rather than successful.

## Ground Your Claims

State what you verified, not what you assume. Read files before making claims about them, run the
owning check before claiming behavior works, and distinguish fact from inference. Bind review and
verification receipts to the final candidate fingerprint; mutation invalidates earlier evidence.

## Protected Content

Root project instructions, user settings, MCP configuration, secrets, unknown extensions,
`.forge/local/`, and `.forge/memory/` are not Forge-owned wholesale. Setup may modify only an exact
Forge marker block or a documented managed entry and must stop when ownership cannot be proven.
