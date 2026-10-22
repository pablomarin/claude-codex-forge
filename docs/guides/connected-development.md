# Connected development

For a trusted local project, Claude should be able to call its configured Codex reviewer and run
application, Docker and database commands through its normal tools. Forge configures connected
development automatically on fresh setup, ordinary upgrades, full refresh and worktree
creation/adoption. Ordinary independent reviewers retain isolated immutable candidate configuration.

Ask your agent:

```text
Upgrade Forge normally and verify reviewer, Docker and development-database access through
your normal command tools. Preserve unrelated settings, permissions and workflow state.
```

The agent uses the normal installer from the target project root; the developer does not need
to choose a connectivity option, edit settings or run a manual terminal.
For an existing v6 installation the manual equivalents are:

```bash
/absolute/path/to/claude-codex-forge/setup.sh --upgrade
```

```powershell
& C:\path\to\claude-codex-forge\setup.ps1 -Upgrade
```

Repository worktrees are included automatically; setup preserves their branches and workflow
state. Claude templates set `sandbox.enabled=false`, and setup manages that one key in ignored
`settings.local.json`, replacing old strict values. Unrelated local entries, native command
permissions and file permissions are preserved. New worktrees receive the default directly
without copying the primary checkout's local settings, environment variables or secrets.
Old ignored selection markers are no longer read or generated. Full refresh includes the local
setting transactionally: preview leaves live files unchanged and rollback restores prior bytes.

Codex's managed `[sandbox_workspace_write]` block sets `network_access=true`, retaining its
workspace filesystem boundary and preserving configuration outside Forge's marker. See the
[Codex configuration reference](https://developers.openai.com/codex/config-reference/).
Worktree creation/adoption also refreshes that exact managed network entry when an older base
still contains `false`; any resulting tracked configuration change is visible in the worktree diff.

This gives the main shell normal host access. Native command permissions, organization policy,
and Forge's authorization for consequential actions remain in effect. An organization-enforced
sandbox may still restrict the session; report that boundary accurately. Forge does not enable
bypass-permissions mode or change user-global policy. A cloud host must also permit internet
access and provide tools, credentials and services: repository settings cannot enable an
externally disabled network or expose a developer machine's Docker daemon. Codex documents its
separate [cloud internet setting](https://developers.openai.com/codex/cloud/internet-access/).

## Verify each capability

Start a fresh local Claude session or restart the existing one after configuration so it loads the
default shell policy. Keep other running sessions and their current work intact.

Run checks through the agent's ordinary command tool in the selected local Claude UI session:

1. Create or adopt a worktree and inspect its effective project configuration.
2. Launch an actual ordinary Codex review through Forge and retain the result and receipt.
3. Check the Docker daemon with a read-only command, then exercise a disposable development
   container if the task needs it.
4. Run a read-only query against the intended development database, including the connection
   path used by the application or integration tests.

Repeat reciprocal reviewer access from a Codex-main session. A manually typed terminal command
does not prove the agent's command tool has the same access.
Installer output and synthetic reviewer fixtures do not qualify authenticated Desktop behavior.
Report unavailable tools, authentication and services separately; do not print connection secrets.

## Why a network allowlist is insufficient

Claude's shell sandbox routes supported traffic through an HTTP proxy. Docker and many native
database drivers do not fit that model. Excluding `docker` or a database CLI also misses scripts
such as `npm test` that invoke them internally. Users choosing to keep sandboxing can configure
specific domains and command exclusions under their own policy, but Forge cannot maintain a
universal exception list. See [Anthropic's sandbox documentation](https://code.claude.com/docs/en/sandboxing).

Claude Desktop can read project configuration from the primary checkout while tools work in a
linked checkout. Its local environment can also omit variables exported in a terminal. Check
Desktop's saved environment, executable discovery and authentication independently, and configure
necessary ignored environment files explicitly without copying secrets into Forge evidence.
See [Desktop local environments](https://code.claude.com/docs/en/desktop#local-sessions).
