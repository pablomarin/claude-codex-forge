# Connected development defaults

Surface coverage: real Bash/PowerShell installer CLI and worktree lifecycle; separate
authenticated Claude Desktop and current Codex-host acceptance. No Forge-owned web/API UI.
Portable PS7 does not certify Windows 5.1. Host/cloud policy limitations remain explicit.

## UC1 — Upgrade without a new connectivity choice

Actor: Developer using either main engine.
Scenario: A v6 installation has strict Claude local settings and Codex networking disabled.
Intent: Upgrade normally and use reviewer/service connections immediately in a fresh session.
Interface: Real installer CLI.
Setup: Disposable Git project; local permissions/environment/domain settings and outside TOML.
Steps: Install fresh; restore old restrictions; run ordinary upgrade without a connectivity flag.
Verification: Fresh and upgraded local sandbox.enabled=false, managed Codex network_access=true;
unrelated local/TOML values and file modes remain intact; no selection marker is generated.
Persistence: Reload settings after another installer run and inspect effective configuration.

## UC2 — Create or adopt a connected worktree

Actor: Developer continuing work through Forge's native lifecycle helper.
Scenario: Primary has no selection marker, or retains an inert old marker.
Intent: Get connected tools automatically without copying primary secrets.
Interface: Real lifecycle create/adopt commands in Bash and PowerShell.
Setup: Disposable repository with private/global ignore variants and target-specific local values.
Steps: Create a worktree; adopt another whose local sandbox is strict; refuse an initialized reseed.
Verification: Both targets receive local sandbox.enabled=false; target environment/deny entries
survive; primary environment does not travel; Git remains clean; rejected reseed changes no config.
Persistence: Inspect settings and Git status after seeding; rerun configuration idempotently.
Older-base variant: a tracked managed Codex network_access=false becomes true during create and
adopt. Only that owned entry changes; outside TOML, BOM and CRLF bytes survive. The necessary
tracked configuration correction is visible in the diff. Root aliases still refuse tracked local JSON.

## UC3 — Refresh transactionally

Actor: Repository operator maintaining an existing installation.
Scenario: Strict local settings, private file permissions and custom project ignore rules exist.
Intent: Preview and apply a normal full refresh while retaining local content and rollback.
Interface: Real --force/-Force installer CLI and its preview.
Setup: Disposable installed project with .env/node_modules/custom ignores and mode0600 or Windows ACL.
Steps: Preview; compare snapshots; execute; restore strict setting; inject a late commit failure;
then try malformed local JSON.
Verification: Preview writes no live bytes; execution changes only intended local key and keeps
covered ignore bytes and access rules; failure restores original local bytes/mode/ACL; malformed
settings block before writes.
Persistence: Reload settings, compare rollback bytes and repeat blocked malformed refresh.

## UC4 — Use actual native tools after ordinary upgrade

Actor: Developer in the existing trusted isolated Claude Desktop test project, then current Codex host.
Scenario: Normal upgrade has replaced old restrictions without a flag or marker.
Intent: Use actual other-engine review, Docker and TCP database access through normal agent tools.
Interface: Claude Desktop command tool; reciprocal current Codex-host command tool.
Setup: Already trusted synthetic project, authenticated reviewer CLIs, cached disposable PostgreSQL image.
Steps: Start a fresh Claude session after normal upgrade; run a real Codex review and disposable
Docker/TCP SQL probe. Run a real Claude review and service probe from current Codex tools.
Verification: Actual reviewer receipts and independently expected SQL row; no manual terminal
substitute or bypass-permissions mode. Record actual host denials separately from installer PASS.
Persistence: Reload project configuration and retain native reports/receipts; remove only owned
disposable service resources.

Executable installer specs: `tests/support/connected-default-use-cases.py`,
`tests/support/development-access-use-cases.py`, and the setup-worktrees/worktree-lifecycle twins.
