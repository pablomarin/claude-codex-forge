# Native worktree context acceptance

The probe checks context without creating authority or changing workflow evidence.
Run its two generated commands separately through the actual host. An intentional
native MATCH denial is distinct from a process-only success.

| Case | Setup and action | Expected result |
| --- | --- | --- |
| Primary session, linked task | Native event points to primary; probe encodes linked root, even if tool process uses linked | Native MISMATCH denial names both roots; task work stops before activation/shipping |
| Aligned linked session | Native event and probe name the linked root; then run the separate process check there | Native MATCH denial followed by process MATCH at exit 0; normal workflow evidence is still required |
| Missing or stale hook | Execute the probe helper without an observing native gate | UNVERIFIED and nonzero exit; process execution cannot certify native alignment |
| Host/session change | Attach or reopen the existing task worktree, repeat both checks and read canonical state | Resume the recorded next step with unchanged valid evidence; no new worktree or copied receipts |
| Nested/symlink spelling | Prepare from a directory inside the intended checkout; event points inside that checkout | Compare the physical root rather than lexical subdirectory spelling |
| Windows mixed shell | Claude Bash command reaches a PowerShell gate; compare Git Bash and PowerShell spellings of a drive or UNC root | Both fixed command grammars identify the same canonical physical checkout |
| Malformed probe | Missing/invalid cwd, invalid hex, extra tokens, CR/LF/NUL, or a compound probe plus shipping command | No native MATCH; no early allow path around shipping checks |
| Session startup | Hook process and event use different repositories or branches | Report event-root branch/common directory and drift; startup alone remains UNVERIFIED |
| Compatibility | Existing host-context hook/launch and unrelated shell commands | Existing behavior retained; no new hook registrations, state files, receipts, index or ref changes |

Deterministic coverage lives in `test-worktree-context.sh`, its PowerShell twin and
`test-session-start.sh`. The fast gate includes the context suite and runs the PowerShell
twin when `pwsh` is available. Windows CI discovers the PowerShell test independently.

Synthetic host payloads, manual hook invocation and PowerShell 7 on macOS do not qualify
native Codex, Claude Desktop, or Windows PowerShell 5.1. Native acceptance needs the actual
tool call, event cwd and canonical gate result for each claimed host. Disabled/untrusted
hooks remain BLOCKED or UNVERIFIED; do not edit trust stores or fabricate a native pass.

The workflow requires this probe before task work and shipping. It does not parse arbitrary
commands to choose another checkout. Skipping it retains the existing event-cwd limitation,
including an inactive primary workflow permitting a command aimed at a linked checkout.
