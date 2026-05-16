# Permissions & Security

Permission boundaries enforced by the template.

## Permissions (No Prompts Needed)

| Action                                     | Prompt? | Why                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read any file                              | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Edit/Write files                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Run any Bash command (tests, linters, git) | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Codex CLI (`codex` commands)               | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Skill invocation                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Web search and fetch                       | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Context7 MCP tools                         | No      | Auto-approved for docs lookup                                                                                                                                                                                                                                                                                                                                                                |
| Playwright MCP tools                       | No      | Auto-approved — used by verify-e2e for UI flows                                                                                                                                                                                                                                                                                                                                              |
| **gh pr create**                           | Yes     | Creating PR requires approval. During a `/forge-goal`-driven autonomous loop, also requires `## PR authorization` in state.md with matching nonce + HEAD SHA (set by the agent after the user answers YES to the PR-create AskUserQuestion modal). The authorization is tied to the session nonce (no cross-session replay) and the exact HEAD SHA at authorization time (no stale commits). |
| **gh pr merge**                            | Yes     | Merging requires approval                                                                                                                                                                                                                                                                                                                                                                    |
| **rm -rf**, **rm -r**                      | Yes     | Destructive deletion                                                                                                                                                                                                                                                                                                                                                                         |
| **npm publish**                            | Yes     | Publishing requires approval                                                                                                                                                                                                                                                                                                                                                                 |
| `sudo`, `su`                               | Denied  | Privilege escalation                                                                                                                                                                                                                                                                                                                                                                         |
| `chmod 777`, `dd`, `mkfs`                  | Denied  | Dangerous system commands                                                                                                                                                                                                                                                                                                                                                                    |
| `rm -rf /`, `rm -rf ~`                     | Denied  | Catastrophic deletion                                                                                                                                                                                                                                                                                                                                                                        |

## What's Denied (permissions deny list)

| Item                                                    | Protection                             |
| ------------------------------------------------------- | -------------------------------------- |
| `sudo`, `su`                                            | Denied — privilege escalation blocked  |
| `rm -rf /`, `rm -rf ~`                                  | Denied — catastrophic deletion blocked |
| `chmod 777`, `dd`, `mkfs`                               | Denied — dangerous system commands     |
| Windows: `Remove-Item -Recurse -Force C:\`              | Denied (Windows template only)         |
| Windows: `Remove-Item -Recurse -Force $env:USERPROFILE` | Denied (Windows template only)         |

## What Requires Confirmation (permissions ask list)

| Action                          | Why                                          |
| ------------------------------- | -------------------------------------------- |
| `gh pr create`                  | Creating PR requires approval                |
| `gh pr merge`                   | Merging requires approval                    |
| `rm -rf`, `rm -r`               | Destructive file deletion                    |
| `npm publish`                   | Publishing packages requires approval        |
| Windows: `Remove-Item -Recurse` | Destructive deletion (Windows template only) |

## What's Skipped by Auto-Formatter

The `PostToolUse` hook skips formatting these files for safety (but does not block reading them):

| Item                                                    | Behavior                  |
| ------------------------------------------------------- | ------------------------- |
| `.env*`, `*.key`, `*.pem`, `*credential*`, `*password*` | Skipped by auto-formatter |
| `secrets/`, `.ssh/`, `.git/`, `node_modules/`           | Skipped by auto-formatter |

> **Note:** The `security.md` rule instructs Claude to never commit secrets to version control, but there are no permissions deny rules that block reading sensitive files.
