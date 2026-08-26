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
