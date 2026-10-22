# Connected development by default

Base: `main`, immutable SHA `8482366756787374b21e80584aa42f6885a2342b`.

## Reproduction and root cause

6.4.12 requires a new opt-in setup argument and an ignored selection marker. Ordinary
upgrades leave Claude local sandbox restrictions in effect, and worktree seeding does
nothing without the marker. Codex's managed workspace-write block also disables networking.
This fails the user's requirement that a normal upgrade deliver connected development.

## Authorized correction

Remove the optional public flags from both installers and materializers. Fresh Claude
templates use `sandbox.enabled=false`; installation and ordinary upgrades also configure
that single key in ignored local settings, preserving unrelated settings, permissions and
file permissions. This uses Claude's native shell because Docker sockets and raw database
connections do not work reliably through its HTTP sandbox proxy. Codex's managed
workspace-write block enables outbound networking without disabling filesystem isolation.
No bypass-permissions mode or global settings changes are introduced.

Worktree create/adopt configures connected access without consulting a source marker or
copying source local secrets. Remove marker generation and inheritance machinery; old
ignored markers remain inert. Reject malformed, tracked or symlinked local settings.

Full-refresh validates real local settings read-only, preserves them in staging, and
includes the connected result in the existing atomic transaction. A nested staging
directory is not its own Git checkout: only treat the configured physical project root
as a repository when it matches Git's top-level. This keeps preview and execution
equivalent and prevents staging from editing live private excludes. Always copy the
existing `.gitignore` into staging, even when it already ignores `.forge/local/`.
Otherwise the stage helper could create a two-line replacement and discard project
ignore rules. Preserve all existing bytes and append only missing local-ignore entries;
when both entries exist, keep the whole file byte-identical. Assert `.env`, `node_modules`
and custom ignore rules survive preview, execution and rollback. Normalize physical
Git top-level paths before comparison in both twins. Preview must not write live
settings; rollback restores original bytes and modes.

## Owned paths

`setup.sh`, `setup.ps1`, both materializers, both development-access and worktree-lifecycle
helpers, `scripts/merge-settings.py`, Claude/Codex templates, focused installer/migration/
worktree tests, current guides, `FORGE.template.md`, README and changelog. Preserve the
separate harness-choice worktree and reviewer isolation. Release this correction as 6.4.13.

## Verification and acceptance

Add a direct normal-install regression and observe failure before production edits.
Then exercise fresh setup, ordinary upgrade with strict existing local settings, existing
checkout fanout, marker-free create/adopt, preserved target values and Git cleanliness,
malformed/tracked/symlink refusal, and Codex network migration with outside TOML preserved.
Run Bash and available PS7 owning checks and the ordinary fast gate. Full-refresh preview,
execution and rollback must include the local settings change transactionally.

For native acceptance, use the existing trusted disposable Claude Desktop test project,
upgrade without a connectivity flag and start a new session. From normal Claude tools
exercise real Codex review transport, disposable Docker and TCP database probes. Exercise
the reciprocal Claude reviewer from the current Codex host. Record actual capabilities
and failures; no synthetic fixture qualifies a native-host claim. A repo cannot enable
internet on a cloud environment whose external host/organization policy disables it;
document that boundary accurately without reintroducing an opt-in Forge switch.

One fresh broad plan review, bounded repair/closure if needed, then independent final
specification and quality reviews over the exact candidate. Native Windows remains CI-owned.
