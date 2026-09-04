# Permissions & Security

Permission boundaries enforced by the canonical `.forge/` policy and each host adapter. Exact
sandbox prompts can differ between Claude Code and Codex; Forge's human-authority boundaries do not.

## Permissions (No Prompts Needed)

| Action                                     | Prompt? | Why                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read any file                              | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Edit/Write files                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Run any Bash command (tests, linters, git) | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Forge reviewer dispatch                    | No      | Starting a workflow authorizes transport of its complete bounded immutable candidate, prompt, and evidence to developer-configured Claude Code/Codex reviewer services; private or unchanged tracked content needs no second approval                                                                                                                                                        |
| Skill invocation                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Web search and fetch                       | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Context7 MCP tools                         | No      | Auto-approved for docs lookup                                                                                                                                                                                                                                                                                                                                                                |
| Playwright MCP tools                       | No      | Auto-approved — used by verify-e2e for UI flows                                                                                                                                                                                                                                                                                                                                              |
| **Full investigation**                     | No extra Forge restriction | Fresh agent uses the selected host's normal project/user config, state, memory, tools, MCP, network, databases, APIs, and real-worktree write access                                                                                                                                                |
| **gh pr create**                           | Yes     | Creating a PR requires explicit human approval plus the matching nonce/candidate authorization in `.forge/local/state.md`; native sessions cannot replay it across a different objective or candidate                                                                                                                          |
| **gh pr merge**                            | Yes     | Merging requires approval                                                                                                                                                                                                                                                                                                                                                                    |
| **Protected external mutation**            | Yes     | Uses the same operation-specific host prompt and current human authorization whether initiated by the main agent or an investigator; Forge grants no extra authority                                                                                                                                                          |
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
| Protected DB/cloud/API mutation | Current explicit human authority is required |
| Windows: `Remove-Item -Recurse` | Destructive deletion (Windows template only) |

Reviewer transport is narrowly scoped. It is expected review input transfer, not an external
mutation or a grant of arbitrary network access. The complete candidate can include private or
sensitive tracked and in-scope non-ignored content; remove or gitignore anything that must not leave
the developer environment before starting the workflow. Authorization does not extend to sourcing
additional secrets, credentials, or gitignored developer state from outside the candidate;
outside-worktree paths; other projects; arbitrary destinations; deploys; publication; destructive
work; or any other external mutation. Ordinary review remains hermetic; only explicit investigation
receives the selected host's normal full-agent capabilities, and the existing human mutation
boundaries still apply.

## What's Skipped by Auto-Formatter

The `PostToolUse` hook skips formatting these files for safety (but does not block reading them):

| Item                                                    | Behavior                  |
| ------------------------------------------------------- | ------------------------- |
| `.env*`, `*.key`, `*.pem`, `*credential*`, `*password*` | Skipped by auto-formatter |
| `secrets/`, `.ssh/`, `.git/`, `node_modules/`           | Skipped by auto-formatter |

> **Note:** `.forge/rules/security.md` instructs either host never to commit secrets, but adapter
> permissions do not universally block reading every sensitive path.
