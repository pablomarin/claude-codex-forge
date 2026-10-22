# Connected local development

For a trusted local project, Claude should be able to call its configured Codex reviewer and run
application, Docker and database commands through its normal tools. Forge leaves the main
session's sandbox policy to the native host, developer and organization. Ordinary independent
reviewers still use their isolated, immutable candidate configuration.

Ask your agent:

```text
Enable connected development for this trusted local project. Preserve my existing permissions,
MCP settings and workflow state. Use Forge's connected-development setup option and verify
reviewer, Docker and development-database access separately.
```

This authorizes the scoped local configuration change. The agent uses the normal installer from
the target project root; the developer does not need to edit settings or run a manual terminal.
For an existing v6 installation the manual equivalents are:

```bash
/absolute/path/to/claude-codex-forge/setup.sh --upgrade --connected-development
```

```powershell
& C:\path\to\claude-codex-forge\setup.ps1 -Upgrade -ConnectedDevelopment
```

Fresh setup accepts the same option without `--upgrade` / `-Upgrade`. Repository worktrees are
included by the installer's existing discovery; it preserves their branches and workflow state.
The option changes only local `sandbox.enabled` to `false` in Claude's `settings.local.json`.
Existing local entries and command permissions are preserved; the local file must remain ignored.
Forge records this explicit choice in the ignored `.forge/local/connected-development.json`.
New worktrees created through Forge inherit only that choice when the primary checkout still
selects `sandbox.enabled=false`. Their existing local sandbox choice takes precedence. Forge
does not copy the primary checkout's local settings, environment variables or secrets. Selecting
a stricter sandbox in the primary checkout stops connected inheritance for future worktrees.
Do not combine this option with full-refresh/preview or global-retirement modes. Complete the
ordinary approved full refresh first, then select connected development in a routine update.

This gives the main shell normal host access. Native command permissions, organization policy,
and Forge's authorization for consequential actions remain in effect. An organization-enforced
sandbox may still restrict the session; report that boundary instead of bypassing it. Routine
upgrades preserve existing sandbox choices, including old strict settings whose ownership cannot
be established. Removing a default from a template alone does not change an installed choice.

## Verify each capability

Start a fresh local Claude session or restart the existing one after configuration so it loads the
selected shell policy. Keep other running sessions and their current work intact.

Run checks through the agent's ordinary command tool in the selected local Claude UI session:

1. Create or adopt a worktree and inspect its effective project configuration.
2. Launch an actual ordinary Codex review through Forge and retain the result and receipt.
3. Check the Docker daemon with a read-only command, then exercise a disposable development
   container if the task needs it.
4. Run a read-only query against the intended development database, including the connection
   path used by the application or integration tests.

A manually typed terminal command does not prove the agent's command tool has the same access.
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
