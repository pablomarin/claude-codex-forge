# Permissions & Security

Permission boundaries enforced by the canonical `.forge/` policy and each host adapter. Exact
sandbox prompts can differ between Claude Code and Codex; Forge's human-authority boundaries do not.

## Routine permission behavior

| Action                                     | Prompt? | Why                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Read any file                              | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Edit/Write files                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Run an ordinary shell command              | Host-dependent | Claude Code recognizes some read-only commands directly. In Auto mode it drops blanket Bash allow rules and evaluates other actions; commands it cannot parse completely can still prompt. Forge therefore requires small, literal, single-purpose calls but does not promise that every shell command is prompt-free                                                                         |
| Forge reviewer dispatch                    | No extra Forge question | Ordinary reviews and task-selected full investigations through configured Claude Code/Codex services have standing human launch approval, including fallback and resumed sessions. Approval permits running reviews, not accepting findings or shipping; host security controls still apply |
| Skill invocation                           | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Web search and fetch                       | No      | Allowed                                                                                                                                                                                                                                                                                                                                                                                      |
| Context7 MCP tools                         | No      | Auto-approved for docs lookup                                                                                                                                                                                                                                                                                                                                                                |
| Playwright MCP tools                       | No      | Auto-approved — used by verify-e2e for UI flows                                                                                                                                                                                                                                                                                                                                              |
| **Full investigation**                     | No extra Forge question | Main agent selects this mode from task needs under standing launch approval. Fresh agent uses normal project/user config, state, memory, tools, MCP, network, databases, APIs, and real-worktree write access; existing host controls still apply |
| **gh pr create**                           | Yes     | Creating a PR requires explicit human approval plus the matching nonce/candidate authorization in `.forge/local/state.md`; native sessions cannot replay it across a different objective or candidate                                                                                                                          |
| **gh pr merge**                            | Yes     | Merging requires approval                                                                                                                                                                                                                                                                                                                                                                    |
| **Protected external mutation**            | Yes     | The main agent obtains any missing human approval, records it, and executes through host controls. Investigators return consequential actions to the main session; Forge grants no extra authority                                                                                                                                                          |
| **rm -rf**, **rm -r**                      | Yes     | Destructive deletion                                                                                                                                                                                                                                                                                                                                                                         |
| **npm publish**                            | Yes     | Publishing requires approval                                                                                                                                                                                                                                                                                                                                                                 |
| `sudo`, `su`                               | Denied  | Privilege escalation                                                                                                                                                                                                                                                                                                                                                                         |
| `chmod 777`, `dd`, `mkfs`                  | Denied  | Dangerous system commands                                                                                                                                                                                                                                                                                                                                                                    |
| `rm -rf /`, `rm -rf ~`                     | Denied  | Catastrophic deletion                                                                                                                                                                                                                                                                                                                                                                        |

Claude Code evaluates every subcommand in a compound Bash or PowerShell call, and a matching ask
rule still wins over an allow rule. Auto mode also drops blanket `Bash`/`PowerShell` allows before
classification. Forge therefore does not add a broad exception for the screenshots' packaging and
cleanup commands. Its canonical workflow rule instead separates build, parity, staging, boundary,
and freeze operations; uses literal arguments; avoids ad hoc shell programs when a structured file
tool or reviewed script fits; and prefers fresh unique outputs over pre-delete/rebuild cycles.
Recursive deletion remains a distinct destructive action that can legitimately require approval.
See Anthropic's current [permission rules](https://code.claude.com/docs/en/permissions#bash) and
[Auto-mode decision order](https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions).

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

Ordinary reviews and full-agent investigations have standing human approval under the canonical
Human-Approved Reviews policy. The main agent may select investigation when the task needs live
project capabilities, explain the selection, and launch without another Forge consent or permission
question. This includes the first review, follow-up, fallback, and resumed sessions. This approves
executing reviews, not their findings or shipping. Ordinary reviewer transport
remains narrowly scoped: the complete bounded candidate, prompt, and evidence go only to the
configured Claude Code/Codex services. The candidate can include private or sensitive tracked and
in-scope non-ignored content; remove or gitignore anything that must not leave before review.
This transfer is not an external mutation and does not grant arbitrary network access, additional
secrets, credentials, or gitignored state beyond the candidate; outside-worktree paths; other
projects; arbitrary destinations; deployment; publication; or destructive
work. Host security controls still apply, and an agent must never invent human approval. Ordinary
review remains hermetic. Full investigation uses the normal host/project capabilities in the real
worktree under standing launch approval. A permission denial or timeout alone never upgrades
ordinary review or its fallback to investigation. Existing host security and human authority for
destructive or external mutations remain unchanged; Forge adds no launch token or permission gate.

The installed contract and materialization tests do not prove Codex Desktop Auto-review behavior.
That host boundary remains `PENDING` until the physical-operator journeys in
`docs/qualification/agent-mode-selection.md` pass on the release candidate.

Human approval authorizes the agent to execute the agreed action; it does not assign terminal or
file-editing work to the human. The agent writes the existing PR or breaker audit record after the
actual decision and verifies the result. Claude ask rules cover common shell forms of issue closure,
Kubernetes apply/delete/patch, and curl POST/PUT/PATCH/DELETE, alongside PR/merge/publish/deletion.
These are host controls, not proof of a chat reply; alternative command forms and MCP tools still
follow the canonical Human Authorization policy and their native controls.

## What's Skipped by Auto-Formatter

The `PostToolUse` hook skips formatting these files for safety (but does not block reading them):

| Item                                                    | Behavior                  |
| ------------------------------------------------------- | ------------------------- |
| `.env*`, `*.key`, `*.pem`, `*credential*`, `*password*` | Skipped by auto-formatter |
| `secrets/`, `.ssh/`, `.git/`, `node_modules/`           | Skipped by auto-formatter |

> **Note:** `.forge/rules/security.md` instructs either host never to commit secrets, but adapter
> permissions do not universally block reading every sensitive path.
