# Agent Mode Selection Implementation Plan

> **For agentic workers:** Execute this plan task-by-task using the Forge
> subagent-driven-development workflow. For every task, write the named failing test
> first, observe the expected failure, implement only enough to pass, run the focused
> suite, and commit the task before continuing.

**Goal:** Install one authoritative Forge harness that can be driven interchangeably by
Claude Code or Codex, select the active main agent from the current host, and dispatch
independent review, investigation, council, and goal work with visible fresh same-engine
fallback.

**Architecture:** Keep the authored policy in the existing repository source directories,
materialize it once under `.forge/` in downstream projects, and generate ordinary-file
Claude and Codex adapters that point at that canonical content. A Bash/Windows PowerShell
dispatcher owns engine selection, capability profiles, fresh-process invocation, fallback,
and receipts; a manifest-driven full refresh owns safe migration and removal of known
legacy Forge artifacts.

**Tech Stack:** Bash 3.2-compatible shell, Windows PowerShell 5.1-compatible scripts,
Markdown/Agent Skills, JSON/TOML adapter templates, Git, existing shell contract tests,
Claude Code CLI, and Codex CLI. No Node, package, build, symlink, or new runtime dependency.

**Spec:** `docs/prds/agent-mode-selection.md`

## Approach Comparison

### Default: Canonical `.forge/` harness with regular-file host adapters

Author every workflow, rule, skill, agent, hook, state contract, and evidence contract once.
Setup copies those canonical files to `.forge/`, then writes small native wrappers into
`.claude/`, `.agents/`, and `.codex/`. Root `CLAUDE.md` and `AGENTS.md` receive bounded
Forge-owned marker blocks while all project-owned text outside those blocks is preserved.

| Criterion | Assessment | Reason |
| --- | --- | --- |
| Complexity | High | Requires adapter generation, migration, and two runtime schemas |
| Blast radius | High | Changes setup, workflow paths, hooks, state, review, council, and docs |
| Reversibility | Medium | The manifest and marker boundaries permit rollback, but migrated state must not be duplicated |
| Validation | High | Canonical fingerprints, installed-fixture tests, and CLI smoke tests expose drift |
| Long-term risk | Low | Policy is authored once and host differences stay isolated in thin adapters |

### Alternative: Generate complete native mirrors for both hosts

Keep one repository source but copy the full policy into both `.claude/` and Codex discovery
trees. Hash parity tests would reject mismatched generated trees.

| Criterion | Assessment | Reason |
| --- | --- | --- |
| Complexity | Medium | Installation is simpler because each host sees a complete native tree |
| Blast radius | Medium | Fewer indirections, but every downstream install contains duplicate policy |
| Reversibility | High | Existing Claude layout changes less |
| Validation | Medium | Hashes catch setup drift but not two simultaneously discoverable policy copies |
| Long-term risk | Medium | Downstream edits and partial upgrades can recreate stale competing behavior |

### Rejected: Imports or filesystem symlinks as the sharing mechanism

Claude-to-Codex import is a one-time migration whose semantics can differ, not continuous
synchronization. Git can materialize symlinks as ordinary text when `core.symlinks=false`,
and Windows link creation may require Developer Mode or privileges. Neither is a safe
cross-platform installation contract.

### Spike result

A temporary clean-repository spike installed one canonical workflow, rule, state file, and
hook revision with thin Claude and Codex wrappers. Fresh Claude and fresh Codex both loaded
the exact canonical workflow/rule/state. After changing only the canonical workflow and hook
from v1 to v2, both loaded v2 without adapter regeneration or double discovery. Claude
observed the hook revision; Codex did not, proving that Codex hook registration/trust remains
a host-adapter responsibility under either architecture rather than an argument for mirrors.

## Contrarian Verdict

The first fresh Contrarian review **OBJECTED** that full native mirrors might be safer because
a narrow pointer test could not establish hook, permission, goal, or migration parity. The
time-boxed spike directly tested the architectural indirection and isolated the Codex hook
miss to the native adapter. The same fresh Contrarian then returned:

> **VALIDATE —** The spike resolves the architectural objection, while the Codex hook miss
> is a shared native-adapter requirement and gives full mirrors no unique correctness
> advantage.

A full Engineering Council was not triggered because the Contrarian validated after one
spike and no unresolved high-impact architectural ambiguity remains.

## Global Constraints

- Preserve `setup.sh` / `setup.ps1` and every hook `.sh` / `.ps1` behaviorally.
- Maintain Bash 3.2 and Windows PowerShell 5.1 compatibility.
- Do not add Node, a package manager, a build step, a daemon, a database, or symlinks. Clean
  installation remains shell-only; Unix authoritative full refresh explicitly requires Python 3
  for safe JSON migration and fails before any write when it is absent.
- Default setup installs both host surfaces and never asks for or stores a permanent main.
- `.forge/local/state.md`, `.forge/local/memory/`, receipts, and other volatile evidence are
  per-developer, gitignored, and never overwritten after creation.
- `.forge/memory/` is project-owned durable memory, excluded from the managed-file rewrite/delete
  inventory and preserved by every setup mode.
- Root project instructions, settings, MCP configuration, secrets, unknown files, and custom
  host extensions are protected. Setup may only replace Forge-owned marker blocks or merge
  documented managed entries.
- Full refresh deletes only content proven Forge-owned by an exact generated marker or a
  version-specific checked-in fingerprint; stamp and path alone are insufficient. Deletion happens
  only at the final transaction point after replacement and translated-state validation.
- Every review participant and every council seat starts in a fresh process or fresh native
  subagent with a unique receipt and structured semantic result. A council advisor's anonymous
  peer critique is a second turn in that same fresh seat session, not five additional participant
  processes. `actual_engine != main_engine` and exit zero are never independence or cleanliness
  tests.
- Investigation may use native web tools, explicitly read-only query/MCP credentials, project
  execution, and isolated worktree writes. In v1 an external mutation is rendered as an exact
  deterministic action for the developer to execute manually; an agent-writable authorization
  receipt is audit-only, and no model receives general mutation credentials or a mutating MCP tool.
- A host switch does not require a lease or handoff and does not invalidate otherwise-fresh
  evidence. Documentation must warn against simultaneous editing.
- Keep the current worktree and branch isolated through the entire implementation.

## Target Installed Layout

```text
.forge/
  instructions.md                 # canonical project-level Forge contract
  state.template.md               # canonical state schema
  workflows/                      # canonical PRD/feature/bug/review/goal workflows
  rules/                          # canonical rules
  skills/                         # canonical reusable skill bodies and references
  agents/                         # canonical agent role bodies
  hooks/                          # canonical Bash and PowerShell hook implementations
    lib/agent-dispatch.sh|ps1     # fresh review/investigation dispatcher
    lib/council-dispatch.sh|ps1   # six-seat topology/fallback dispatcher
    lib/authorized-action.sh|ps1  # render/verify human-executed exact action manifests
  managed-files.tsv               # installed Forge ownership + canonical fingerprints
  version                         # installed harness version
  memory/                         # project-owned durable, reviewable shared memories
  local/                          # gitignored state, memory, reviews, council, goal evidence
.claude/
  commands/                       # generated wrappers for Claude slash-command discovery
  skills/                         # generated wrappers for Claude skill discovery
  agents/                         # generated Claude-native role wrappers
  settings.json                   # merged Claude hook/permission registrations
.agents/skills/                   # generated Codex workflow and reusable-skill wrappers
.codex/
  config.toml                     # merged Codex sandbox/agent registrations
  hooks.json                      # primary-checkout registry; routes events to current worktree
  agents/*.toml                   # generated Codex-native role definitions
CLAUDE.md                         # project text + bounded Forge marker/import block
AGENTS.md                         # project text + bounded Forge marker/pointer block
```

Repository source remains author-friendly: `commands/`, `rules/`, `skills/`, `agents/`, and
`hooks/` stay the source of truth; `templates/adapters/` and `manifests/` define installed
wrappers and ownership. Setup is the materializer, so the source repository itself does not
need committed generated `.forge/` copies.

## Task 1: Specify Canonical Layout, Adapter Contracts, and Ownership Manifests

**Files:**

- Create: `manifests/managed-v6.tsv`
- Create: `manifests/legacy-v5.tsv`
- Create: `manifests/legacy-v5-fingerprints.tsv`
- Create: `manifests/legacy-v5-regions.tsv`
- Create: `manifests/host-capabilities.tsv`
- Create: `manifests/workflow-capabilities.tsv`
- Create: `templates/adapters/claude-command.template.md`
- Create: `templates/adapters/claude-skill.template.md`
- Create: `templates/adapters/codex-skill.template.md`
- Create: `templates/adapters/claude-agent.template.md`
- Create: `templates/adapters/codex-agent.template.toml`
- Create: `templates/adapters/CLAUDE.block.template.md`
- Create: `templates/adapters/AGENTS.block.template.md`
- Create: `FORGE.template.md`
- Create: `GLOBAL-FORGE.template.md`
- Create: `GLOBAL-AGENTS.template.md`
- Create: `tests/template/test-dual-layout.sh`
- Create: `tests/template/test-platform-parity.sh`
- Modify: `tests/template/run-all.sh`
- Modify: `tests/template/test-contracts.sh`

**Step 1: Write the failing manifest and adapter contract tests.**

Add assertions that each source workflow, rule, skill/reference, agent, and hook has exactly
one canonical installed destination under `.forge/`; every generated wrapper has
`forge-generated`, `canonical-path`, and `canonical-revision` fields; no adapter embeds a
second full policy body; no manifest destination escapes the project; no installed path or
existing ancestor is a symlink/junction/reparse point; and Claude/Codex names cover the same
parity matrix. Centralize static Bash/PowerShell inventory and field parity in
`test-platform-parity.sh`; feature suites keep only behavioral assertions.

**Step 2: Run the focused tests and observe RED.**

Run `bash tests/template/test-dual-layout.sh` and the relevant contract section. Expected:
missing manifests/templates and missing run-all registration.

**Step 3: Add the v6 manifest schemas and adapter templates.**

Use tab-separated, comment-capable records that shell and PowerShell can parse without a new
runtime. Define record kinds `canonical`, `adapter`, `merge`, `marker`, `protected`, `tombstone`,
and `legacy`; source, destination, platform/host, and ownership fields are explicit. List every
known v5 managed path/setting in `legacy-v5.tsv`, including exact legacy root/global template
regions, while excluding local state/memory, secrets, and unknown wildcards. Generate and review
`legacy-v5-fingerprints.tsv` from released v5 sources so pre-stamp standard installs can be
positively identified and customized content cannot.

Released v5 `CLAUDE.md` is a mixed user/policy file: setup deliberately preserved it and its own
template asked developers to edit project goal, description, stack, structure, design, deployment,
and E2E sections. `legacy-v5-regions.tsv` therefore defines, per released version, exact ordered
managed-region anchors/bodies and explicit user-owned regions. The recognizer permits the one
generated first-line project-name field and arbitrary bytes only inside those user regions. Full
refresh preserves user-region bytes in the v6 root file, removes only exact matching managed
regions, and blocks when a boundary, ordering, or managed byte changed. It never requires the whole
mixed file to equal the template. Generate equivalent Bash/PowerShell fixtures for default and
edited user sections, custom/spaced/punctuation names, changed managed bytes, missing/duplicated
anchors, and boundary-looking text inside a user region.

`host-capabilities.tsv` is the single current behavior map for instruction/rule discovery,
commands/skills, every hook event/handler, subagents, permissions, fresh runs, investigation,
trust, and native goals. It specifies the Codex command-hook equivalent for Claude's prompt-based
`SubagentStop` evaluator and a lifecycle config-fingerprint check replacing unsupported Codex
`ConfigChange`. `workflow-capabilities.tsv` maps every current external-plugin behavior to its
v6 owned skill or canonical workflow replacement.

Keep v1 model selection deliberately fixed, not user-configurable: one checked certifying/advisory
profile per engine in `host-capabilities.tsv`, including exact provider/model/effort argv/config,
observable identity fields for each qualified CLI version, and minimum output/sandbox capabilities.
Preserve the current high-rigor code/plan baseline (`gpt-5.6-sol`/`xhigh` for Codex and qualified
`opus`/`max` for Claude); advisory council/general defaults are fixed rows only when current Forge
already requires a distinct cost profile. Unsupported flags fail before launch and observable
actual-field mismatches fail qualification. Non-observable fields are `UNOBSERVABLE` and bound only
to the captured invocation/config hash—Forge does not claim silent-substitution detection. Model
overrides and arbitrary tuple qualification are deferred beyond v1.

Wrappers must use instruction prose to read the canonical file completely. Do not depend on
Markdown import support except in the bounded Claude root marker where `@.forge/instructions.md`
is a documented native feature.

Stage the shared project/global instruction bodies and thin root marker templates, but do not yet
modify the live `CLAUDE.template.md` or `GLOBAL-CLAUDE.template.md` consumed by the current installer.
Task 2 cuts those live templates over in the same commit that materializes their `.forge` targets.
At this checkpoint contract tests validate the staged adapter bodies/revisions; the existing setup
suite must still prove the v5 installer produces complete instructions.

**Step 4: Make contracts GREEN.**

Run `bash tests/template/test-dual-layout.sh`, `bash tests/template/test-platform-parity.sh`, and
`bash tests/template/test-contracts.sh`. Verify a deliberate stale revision and a `../` manifest
destination are both rejected, and that every manifest/template/hook source resolves exactly once.
Run `bash tests/template/test-setup.sh` to prove the uncut live installer remains green.

**Step 5: Commit.**

```bash
git add manifests templates/adapters FORGE.template.md GLOBAL-FORGE.template.md \
  GLOBAL-AGENTS.template.md \
  tests/template/test-dual-layout.sh tests/template/test-platform-parity.sh \
  tests/template/test-contracts.sh tests/template/run-all.sh
git commit -m "feat: define canonical dual-engine harness layout"
```

## Task 2: Materialize the Canonical Harness and Both Host Surfaces

**Files:**

- Modify: `CLAUDE.template.md`
- Modify: `GLOBAL-CLAUDE.template.md`
- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `scripts/merge-settings.py`
- Create: `scripts/render-codex-config.py`
- Create: `scripts/materialize-adapters.sh`
- Create: `scripts/materialize-adapters.ps1`
- Create: `scripts/verify-runtime.sh`
- Create: `scripts/verify-runtime.ps1`
- Create: `scripts/qualify-dispatch-isolation.sh`
- Create: `scripts/qualify-dispatch-isolation.ps1`
- Create: `scripts/qualify-goal-feasibility.sh`
- Create: `scripts/qualify-goal-feasibility.ps1`
- Create: `scripts/forge-goal-authorize.sh`
- Create: `scripts/forge-goal-authorize.ps1`
- Create: `hooks/lib/codex-worktree-dispatch.sh`
- Create: `hooks/lib/codex-worktree-dispatch.ps1`
- Modify: `manifests/managed-v6.tsv`
- Modify: `settings/settings.template.json`
- Modify: `settings/settings-windows.template.json`
- Modify: `settings/global-settings.template.json`
- Create: `settings/codex-config.template.toml`
- Create: `settings/codex-hooks.template.json`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-merge-settings.sh`
- Modify: `tests/template/test-dual-layout.sh`
- Create: `tests/template/test-runtime-identity.sh`
- Create: `tests/template/test-runtime-identity.ps1`
- Create: `tests/template/test-goal-feasibility.sh`
- Create: `tests/template/test-goal-feasibility.ps1`
- Create: `tests/template/fixtures/host-events/claude-2.1.237.json`
- Create: `tests/template/fixtures/host-events/codex-0.144.1.jsonl`
- Create: `tests/template/run-all.ps1`
- Create: `.github/workflows/windows-parity.yml`

**Step 1: Write failing clean-install and idempotency tests.**

In scratch projects cover Unix setup with both CLIs present, Claude only, Codex only, and
neither binary. Assert all cases install the same canonical and dual-host file inventory;
availability only changes the report. Assert a second setup run is idempotent. Run global setup
against a temporary home and require bounded, content-preserving Forge blocks/config for both
`~/.claude` and `~/.codex`; never touch the real test user's home. Add static PowerShell parity
assertions for parameter names, manifest parsing, destination inventory, and templates. Add root
and nested-directory discovery fixtures proving both host instruction surfaces enumerate every
canonical rule exactly once.

Preflight every project and global setup mode before its first write. If ordinary setup, force,
upgrade, or global setup sees v5 material at this Task 2 checkpoint, exit nonzero with a truthful
`BLOCKED: full refresh is not available in this checkpoint` message and keep the usable v5 harness;
do not advertise an unknown option. Task 3 replaces this interim message with the exact executable
project/global full-refresh command and tests the printed remediation end-to-end. Ambiguous legacy
is preserved and blocked in both checkpoints. No mode may materialize v6 beside still-discoverable
v5 policy. Cover default, force, upgrade, project/global, exact legacy, ambiguous legacy, and clean-
install fixtures on both platforms.

Create `run-all.ps1` as the owning Windows PowerShell 5.1 suite runner. It deterministically
discovers and invokes every `tests/template/test-*.ps1` behavioral suite with no silent ignore
list, and fails on duplicate/undiscoverable suites. Every such suite must be hermetic and use fake
engines/checked fixtures—no authentication, network, model call, or manual TUI. Live scripts use
the separate `scripts/qualify-*` naming/runner and produce release attestation that deterministic
CI schema tests validate. `test-platform-parity.sh` checks that every owning `.ps1` suite is
reachable through `run-all.ps1`. The Windows workflow invokes this checked runner under Windows
PowerShell 5.1, so later deterministic PowerShell behavior is load-bearing when introduced.

Engine detection records binary path and reported version but does not equate presence with
usability. Setup performs non-authenticating help/capability probes for the native flags Forge
needs and reports missing capabilities without refusing to materialize either host surface.
Installation status distinguishes `MATERIALIZED` from per-host `RUNTIME_READY`; missing binaries,
untrusted Codex project config/hooks, or a failed discovery sentinel remain explicit readiness
gaps rather than installation failures or false success.

Codex linked worktrees are a documented host exception: Codex discovers hook registration from the
primary checkout's `.codex`, even while other project config is worktree-local. When setup runs in
the primary checkout, merge a bounded registration there pointing to a stable primary
`codex-worktree-dispatch` adapter. The adapter resolves the trusted event cwd, proves its Git common
directory matches the registered repository, and delegates only to that current worktree's
`.forge/hooks`; policy/state never come from the primary worktree. A linked-worktree setup never
silently mutates its sibling primary checkout: it materializes the selected worktree, reports the
exact primary setup/full-refresh command, and keeps Codex hook readiness blocked until the primary
registration is installed. Protect/backup/journal the primary registration under the selected
primary transaction. Test one primary plus two linked worktrees with different state/candidate
ids, stale/absent primary registration, wrong-common-dir events, rollback, and correct per-worktree
gate/counter routing.

Probe structured identity metadata now, before the dispatcher depends on it. Check in redacted
captured event fixtures for every qualified CLI version and record exactly which fields are
observable. For the current matrix, Codex `0.144.1` JSONL exposes no provider/model/effort, while
Claude `2.1.237` exposes canonical provider/model in `modelUsage` but not actual effort. Verify
observable fields against the receipt; for non-observable fields verify the exact explicit
invocation/config hash and that unsupported values are rejected at launch. The fixture/test must
fail if a later parser invents an `actual_*` value from requested configuration.

Before Task 5 makes review dispatch load-bearing, run an authenticated isolation qualification for
each installed engine. Claude's subscription/OAuth-compatible default is `--safe-mode` plus
explicit system prompt, tools, strict MCP config, setting sources, and sandbox/permission flags;
do not use `--bare` on this path. Qualify a separate optional `--bare` recipe only when an API key,
provider credential, or `apiKeyHelper` is deliberately configured. Include OAuth/keychain-only and
API-key fixtures. Codex has no arbitrary isolated config-file or project-discovery-off flag, so its
exact recipe uses a clean scratch primary Git repository and a separate sibling candidate Git
repository exposed as an additional data directory,
`--ignore-user-config --ignore-rules --ephemeral`, read-only sandbox/never approval, explicit
prompt/schema/output paths, and explicit disables for hooks, plugins, plugin sharing, apps, and
other ambient tool surfaces supported by the qualified CLI. Canary project/user instructions,
skills, hooks, plugins, MCP servers, and rules must remain unobserved. If a flag/feature is absent
or a canary leaks, that engine is not dispatch-capable and implementation cannot claim its
`RUNTIME_READY` state; record `BLOCKED` before proceeding to dispatcher implementation.

The same qualification owns a council-only two-turn capability while ordinary reviewers stay
ephemeral. Claude turn 1 uses `claude -p --session-id <uuid>` without
`--no-session-persistence`; turn 2 uses `claude -p --resume <uuid>` in the same isolated session
store. Codex turn 1 omits `--ephemeral`, captures the structured `thread.started` id, and turn 2
uses `codex exec resume <id>`. Both turns repeat the qualified sandbox/config restrictions, bind
the seat/engine/config/canary hashes, prevent cross-seat resume, and clean up the exact owned
session store/artifacts when the host supports it. If isolated exact-id resume, credential-safe
storage, or cleanup cannot be qualified for an engine/auth mode, mark that engine
`council_resume=BLOCKED`; do not emulate a resumed seat with a fresh invocation.

The sibling candidate is a real repository: materialize the exact base commit and apply the frozen
candidate's index/mode/rename/deletion state, preserving Git history and repository-relative
commands. Codex remains launched with `-C` at the empty scratch primary root and `--add-dir` for the
candidate, so the sibling's host-control files are data and are not startup discovery roots; the
prompt names the sibling as the logical project root and Git-aware qualification verifies
`rev-parse`, diffs, deletions, renames, executable modes, and repository-relative scripts. Canary
tests must prove the additional directory does not become an instruction/hook/skill/config source.

For investigation, seed a disposable sibling candidate repository from the same frozen candidate
and allow writes only there. Validate its resulting diff and replay only declared reproduction/artifact paths
into the real worktree if the original candidate identity is unchanged; reject symlinks, path
escapes, binary/oversized output outside policy, and Forge state/evidence/auth mutations. This
gives the investigative agent ordinary file/query/execute capability without loading the trusted
primary repository's ambient Codex configuration. The live qualification must prove the replay
path before Task 5 starts.

Also run a minimal authenticated native-goal feasibility slice on each installed host. This is a
disposable proving fixture with its own minimal adapter/oracle, not the production implementation
claimed in Tasks 4 and 9. It proves one autonomous phase/checkpoint transition after native
`/goal`, process interruption followed by exact-checkpoint resume, and budget/stuck behavior.
Because native token-budget controls differ, the portable contract uses a Forge overlay rather
than Codex's under-development `token_budget` feature.

The immutable per-goal nonce, objective hash, and ceiling live in a user-owned authorization record
outside every project/workspace-write root. Global setup installs the writer only as
`~/.forge/bin/forge-goal-authorize` and records the trusted absolute home/authorization path; the
writer accepts no alternate root derived from `HOME` or argv. Claude's owned permissions/sandbox
hard-deny Write/Edit and every Bash/PowerShell execution path to the writer/authorization tree;
Codex workspace sandbox excludes it. A developer runs the writer from a separate terminal, or a
qualified host approval UI runs that exact hash after an explicit approval. An agent attempt,
copied source helper, shell indirection, or valid-shaped direct write therefore fails before the
record changes; if either host cannot prove that boundary, goal activation remains `BLOCKED`.
Escalating the exact denied action is itself a visible human authorization, never automatic.
Project-only setup never writes this global boundary; it reports the exact global setup command and
keeps goal activation blocked until that separate operation and qualification succeed.

Completed turns are represented by hook-owned, no-clobber records under
`.forge/local/goal-counters/<nonce>/turns/<turn-id>`; state shows a derived count but cannot
reset/increase the ceiling or erase charged turns. The external authorization binds project/worktree
identity, objective hash, nonce, ceiling, monotonic issue id, and exact writer revision; replay or
replacement without a new human action is rejected. This avoids a workflow lock while making
duplicate/concurrent Stop events idempotent and monotonic across host switches. Tests run the real
host profile against helper invocation, copied-helper invocation, valid-shaped forgery, replay,
ceiling replacement, direct edit, host switch, and concurrent Stop, plus a separate operator-channel
success fixture.

At the bound, the proving adapters checkpoint the exact next step, emit
`FORGE_GOAL_BUDGET_EXHAUSTED`, and invoke native pause/termination. The deterministic fixture sets
`FORGE_GOAL_TEST_TURN_BUDGET=1`; its oracle is the immutable authorization, hook-owned turn record,
phase/checklist checkpoint, marker, and paused autonomy. Stuck behavior uses an unchanged progress
fingerprint for the checked threshold and requires `FORGE_GOAL_STUCK_WARNING`.

Claude qualification may automate `claude -p "/goal ..."` and resume. Ordinary `codex exec`
prompt text is structurally incapable of certifying native Codex `/goal`; Forge uses a documented
manual authenticated Codex TUI protocol that records the developer-command activation, status,
pause/interruption, resume, and transcript/result hashes, unless a separately named cross-platform
TUI/app-server driver is qualified. Fake CLIs and `codex exec` receipts cannot satisfy this row.
If either native host cannot prove the goal slice, mark goal-overlay activation, Task 9 goal
composition, runtime readiness, and final release `BLOCKED`, but allow independent migration,
dispatcher, investigation, council, documentation, and deterministic E2E work to proceed. Task 11
repeats the complete matrix against the final candidate.

**Step 2: Run the focused tests and observe RED.**

Run `bash tests/template/test-setup.sh`, `bash tests/template/test-merge-settings.sh`, and
`bash tests/template/test-dual-layout.sh`. Expected: current setup only creates `.claude`.

**Step 3: Add manifest-driven materialization.**

Implement Bash functions `load_managed_manifest`, `install_canonical_file`,
`render_adapter`, `replace_marker_block`, `detect_engines`, and `write_install_manifest`.
Implement PowerShell twins `Read-ManagedManifest`, `Install-CanonicalFile`,
`Render-Adapter`, `Set-ForgeMarkerBlock`, `Get-EngineAvailability`, and
`Write-InstallManifest`. These functions live in the new materialization helpers; `setup.sh`
and `setup.ps1` delegate to them instead of carrying a second implementation.

The adapters substitute only stable tokens such as `{{CANONICAL_PATH}}`, `{{NAME}}`, and
`{{REVISION}}`. Compute revision from the canonical source content during setup and write the
same revision into wrapper and installed manifest. Materialize both hosts by default. Keep
root text outside `<!-- forge:begin v6 -->` / `<!-- forge:end v6 -->` byte-preserved; create
the file with only the block when absent.

In this same materializer commit, move the shared project/global bodies from the live
`CLAUDE.template.md`/`GLOBAL-CLAUDE.template.md` into the staged Forge sources and cut the live
templates to thin marker/import surfaces. Only after setup materializes the canonical targets do
contract tests reject a second embedded body. Run the existing setup suite at this checkpoint so no
commit can install a wrapper whose canonical target is absent.
Add same-checkpoint project/global manifest records for the worktree router, global goal writer,
and every other shipped helper before any installed caller references them; an installed-fixture
test must prove the files and matching revisions exist.

**Step 4: Merge, do not replace, host configuration.**

Extend the existing merge helper to support JSON managed-entry merges while preserving unknown
keys and values semantically; formatting may normalize, so take a backup before rewriting. Opaque
protected files, secrets, and text outside marker regions retain byte identity. For TOML, preserve
arbitrary existing bytes outside a bounded Forge marker and refuse malformed or duplicate Forge
markers. Do not implement or claim a home-grown partial TOML parser. Generate self-contained,
Forge-namespaced entries (using standard Codex namespaces where the host requires them), stage the
complete candidate config in an installed-project fixture, and validate it through the
version-qualified Codex config loader discovered in Task 2, such as a capability-probed
`codex --strict-config -C <fixture> doctor --json`. If Codex or that exact validator capability is
unavailable, preserve/materialize the config but report Codex config readiness `BLOCKED`/`PENDING`;
do not invent a collision or claim `RUNTIME_READY`. If the host validator rejects a collision or
malformed complete file, leave the original unchanged and report the exact blocking diagnostic.
Fixtures include valid disjoint `[mcp_servers.context7]` and `[mcp_servers.playwright]` tables,
quoted/dotted keys, inline and multiline values, whitespace/comments, an actual duplicate generated
namespace, and a malformed Forge marker. Claude settings point at `.forge/hooks/*`; Codex
hooks use Codex-native payload/event registrations and point at the same canonical
implementations.

Keep exactly one canonical Codex config/hooks template pair under `settings/`; manifests and
later guard registration reference those files. `verify-runtime` performs opt-in live sentinels
for root/nested instruction and rule discovery, project trust, hook trust, and hook execution.
Setup reports materialization and prints the verification command without claiming trust or
`RUNTIME_READY` from inventory alone.

Treat the project `.mcp.json` as the user-owned MCP source. Translate supported JSON server fields
with the Python standard library when Python is available, render them into the Forge-owned Codex
TOML marker without parsing the existing TOML, then validate the complete staged config through the
qualified Codex loader,
fingerprint the source, and refresh only that marker when it changes. The static Forge-managed MCP
servers also exist in the Codex template so a clean install does not acquire a mandatory Python
dependency. On PowerShell use the platform JSON parser. Preserve unknown MCP fields and literal
secret-bearing entries in place; never copy literal credentials into generated config, argv,
logs, or receipts. Report any custom entry that cannot be safely translated as `BLOCKED` for
Codex MCP parity instead of silently claiming it works. Test command/args/env-reference
transports, no-Python setup, and a literal-secret case.

Preserve `--global` as a supported operation: merge the Forge-owned global Claude instruction,
settings, and hook entries and the Forge-owned global Codex instruction/config entries using the
same bounded-marker/managed-entry rules. Global setup installs no permanent main preference and
never replaces user text or unknown config outside its owned sections.

**Step 5: Make clean-install tests GREEN and pass the early native gates.**

Run the focused suites and inspect one installed fixture. Confirm `.forge/local/` is gitignored,
no regular policy file exists twice, and paths with spaces work. Run the checked Windows runner
contract, captured identity-event tests, and deterministic goal trigger/oracle fixtures on Bash
and PowerShell, then run `qualify-dispatch-isolation` against authenticated installed hosts. A
dispatch-isolation failure blocks Task 5 for that engine. Run `qualify-goal-feasibility`; failure
blocks only the goal surfaces/readiness/release named above, not unrelated implementation tasks.

**Step 6: Commit.**

```bash
git add CLAUDE.template.md GLOBAL-CLAUDE.template.md setup.sh setup.ps1 scripts settings \
  hooks/lib/codex-worktree-dispatch.* manifests/managed-v6.tsv tests/template
git add .github/workflows/windows-parity.yml
git commit -m "feat: install canonical harness with dual-host adapters"
```

## Task 3: Implement Authoritative `-F` / `--full-refresh` Migration

**Files:**

- Modify: `setup.sh`
- Modify: `setup.ps1`
- Create: `scripts/full-refresh.sh`
- Create: `scripts/full-refresh.ps1`
- Create: `scripts/migrate-state-v5-v6.sh`
- Create: `scripts/migrate-state-v5-v6.ps1`
- Create: `scripts/recover-full-refresh.sh`
- Create: `scripts/recover-full-refresh.ps1`
- Modify: `scripts/migrate-continuity.sh`
- Modify: `scripts/migrate-continuity.ps1`
- Modify: `scripts/merge-settings.py`
- Modify: `manifests/managed-v6.tsv`
- Modify: `state.template.md`
- Create: `hooks/lib/state-path.sh`
- Create: `hooks/lib/state-path.ps1`
- Modify: `hooks/session-start.sh`
- Modify: `hooks/session-start.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `hooks/build-evidence.sh`
- Modify: `hooks/build-evidence.ps1`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-migrate.sh`
- Create: `tests/template/test-full-refresh.sh`
- Create: `tests/template/test-full-refresh.ps1`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-session-start.sh`
- Modify: `tests/template/test-build-evidence.sh`
- Modify: `tests/template/test-state-roundtrip.sh`
- Modify: `tests/template/run-all.sh`

**Step 1: Make state consumers dual-read before exposing full refresh.**

First write failing fixtures where v5 state exists only at `.claude/local/state.md`, translated v6
state exists only at `.forge/local/state.md`, and both exist with versioned precedence. Implement
one Bash/PowerShell `state-path` helper and update SessionStart, Stop/state, evidence, and ship-gate
consumers to prefer validated v6 state while falling back to v5 only for an unmigrated install.
All v6 writes use the canonical path, and legacy reviewer/goal/authorization lines never become
v6-clean evidence. At this checkpoint, a full-refresh fixture must exercise Claude and Codex resume
plus allow/block hook decisions against the translated state. Do not enable or stamp full refresh
until these consumers pass. Task 4 extends the same helper to the remaining hooks/memory surfaces;
it does not introduce the first v6-capable state reader.
Register both `state-path` helpers in `managed-v6.tsv` in this checkpoint and prove installed hooks
never call an unmaterialized helper.

**Step 2: Write the legacy-fixture matrix.**

Build fixtures for stamped v5, exact fingerprinted pre-stamp v5, unstamped lookalike, modified
known managed file, exact legacy root/global templates, customized legacy root/global policy,
custom `.claude` extension, exact and modified Forge-owned plugin settings, settings/MCP secrets,
malformed JSON, Python absent, active v5 state plus `.state-seed-snapshot.md`, both old/new state
conflict, symlinked destination/ancestor, failed copy, failure after the first and penultimate live
rename, interrupted refresh, project/global flag combinations, stale global harness detection,
and ordinary pre-stamp installs with default/custom/spaced/punctuation project names, arbitrary
edits inside every documented v5 user region, plus one-byte changes to managed bytes and region
boundaries.
For every supported stamped v5 release, include a normal customized settings file with unknown
siblings plus exact managed-looking plugin, permission, and hook entries. Include one fixture where
the identical entry predated Forge, one release with an actually persisted entry-ownership marker
if such a release exists, an exact released whole-file fingerprint, and a near-match where one
managed entry was user-modified. Without positive per-entry/whole-file provenance, preserve the
exact entry as custom compatibility configuration and do not add a semantic duplicate. For an exact
legacy hook registration, keep the registration while replacing only a separately proven legacy
hook file with a thin stage-aware delegate. Block only when the preserved entry creates an actual
unresolvable behavioral collision or its referenced legacy file is customized/ambiguous. Known
enabled plugins are not presumed inert merely because v6 workflows stop naming them: inventory
their hook, auto-trigger, and skill surfaces. Any overlap with v6 keeps that host's `RUNTIME_READY`
blocked unless live qualification for the exact plugin version/config proves it inert or the
developer explicitly resolves the pending entry. Add enabled-plugin auto-trigger/hook canaries and
one genuinely inert preserved-plugin fixture.
Add Windows
junction/reparse fixtures to the PowerShell suite. Require modified/unverifiable legacy files to
remain byte-identical and report `BLOCKED`; require semantic equality for unknown valid JSON keys
and byte identity for opaque/malformed/protected files. Require report categories `CREATED`,
`REWRITTEN`, `DELETED`, `PRESERVED`, `PRESERVED_COMPAT`,
`PRESERVED_COMPAT_BLOCKED`, and `BLOCKED`.

**Step 3: Run `bash tests/template/test-full-refresh.sh` and observe RED.**

Expected: `-F` is unknown and no ownership-aware migration exists.

**Step 4: Add the explicit mode and pre-stage transaction.**

Add `-F|--full-refresh` to Bash and `-FullRefresh` with distinct `-R` alias to PowerShell;
PowerShell aliases are case-insensitive, so `-F` remains the existing Force alias. Keep lowercase
`-f|--force` as the existing Bash overwrite behavior and reject combining force/full-refresh.
`--upgrade` detects a fingerprinted or stamped legacy install and directs the developer to full
refresh; it must not create a mixed v5/v6 layout. Only in this commit replace Task 2's truthful
interim `BLOCKED` message with the exact now-executable scoped command, and test by executing the
printed remediation against project and temporary-home fixtures.

Scope is explicit. Project `-F`/`--full-refresh` and `-FullRefresh`/`-R` mutate only the selected
repository and never the user's home. Global migration is a separate transaction invoked as
`--global -F` on Bash or `-Global -FullRefresh`/`-Global -R` on PowerShell, and it mutates only the
allowlisted Forge-owned regions within the selected temporary/real home (`.forge`, `.claude`, and
`.codex`). Reject ambiguous or incompatible flag combinations.
A project refresh may fingerprint the global harness read-only and report the exact follow-up
global command when it is stale, but it never upgrades it implicitly.

Resolve `transaction_root` before preflight: the canonical repository root for project refresh,
or the validated selected temporary/real home directory for global refresh. Global staging,
journals, and backups live under that home's Forge-owned `.forge/local/` child, while an exact
allowlist permits only the intended `~/.forge`, `~/.claude`, and `~/.codex` destinations. Every
containment/same-filesystem check derives from the selected home—not the narrower Forge child and
not the invoking repository. A global transaction never writes into or derives paths from the
invoking repository; tests run it from a read-only repository and an unrelated directory and
reject journal destinations or host-global writes outside the selected home/allowlist.

Full refresh must:

1. preflight Python 3 on Unix before any mutation; missing Python is a fail-closed requirement of
   authoritative JSON migration, while clean setup remains shell-only;
2. acquire one exclusive, recoverable setup transaction guard for the resolved project/home scope
   before inventory and hold it through commit/rollback. This serializes installer/migration
   transactions only; it is not a development-workflow lock and does not prevent Claude and Codex
   from using the same worktree. A stale guard is recoverable only after its journal and owner are
   proven inactive;
3. inventory/classify without following links and reject every symlink, junction, or reparse-point
   destination ancestor or resolved path outside the project/home root;
4. prove legacy ownership by exact generated marker, a version-specific path/content fingerprint,
   or the versioned mixed-file region recognizer defined in Task 1; preserve all explicit user
   regions byte-for-byte and require every managed boundary/body to match; a stamp is supporting
   evidence, never sufficient by itself;
5. remove exact unmodified legacy root/global templates or exact managed regions; carry preserved
   user regions into the v6 root surface and block changed/ambiguous managed policy so v5 and v6
   never silently compete;
6. stage the entire canonical harness, adapters, settings merge, state translation, seed snapshot,
   reports, and raw backups under the resolved transaction root on the destination filesystem;
   before the first live rename, write and durably flush an operation journal under that root's
   Forge-local `migration-journals/` directory containing
   the ordered replacement/deletion set, original fingerprints, rollback backups, and transaction
   phase;
7. translate active v5 state to the versioned v6 schema, preserving workflow checkpoint/narrative
   while explicitly invalidating old Codex/pr-toolkit review, goal, and authorization evidence;
   translate `.state-seed-snapshot.md` and validate both hosts' resume interpretation;
8. preserve raw originals under `.forge/local/migration-backups/`; an old/new state conflict is
   `BLOCKED`, never guessed or overwritten;
9. apply settings tombstones only when ownership is proven by an exact released whole-file
   fingerprint or an entry-level Forge ownership marker/inventory that the installed v5 release
   actually persisted. A stamp, exact value, and matching surrounding inventory can aid diagnosis
   but cannot retroactively prove who created an entry. Preserve unproven exact historical entries
   as custom compatibility registrations, suppress a semantically duplicate v6 registration, and
   keep exact legacy hook paths working through separately fingerprinted thin delegates. Preserved
   permissions/inert registrations may report `PRESERVED_COMPAT`. A known enabled plugin with
   overlapping ambient hooks/auto-triggered skills reports `PRESERVED_COMPAT_BLOCKED` until exact
   live qualification or explicit developer resolution. Also block an unresolved behavior
   collision, a modified/ambiguous referenced hook, or malformed JSON;
10. validate all staged revisions, marker uniqueness, complete TOML config through the qualified
    Codex loader,
   translated state, and required files before mutating any live destination;
11. immediately before each replacement or deletion, move the live destination without following
    links into a same-filesystem quarantine path using a no-clobber primitive, then hash those moved
    bytes and compare them with the inventory fingerprint recorded in the journal. A mismatch is a
    concurrent-edit conflict: restore the quarantined original if the destination is still absent,
    otherwise preserve both versions and stop `BLOCKED` for manual reconciliation. Install the
    staged replacement with a platform-qualified no-replace primitive, so a destination created
    after inventory cannot be overwritten; update and durably flush the journal after each move.
    Delete only exact proven obsolete paths at the final commit point, prune only empty known
    directories, and never recursively delete a host root or overwrite a prior backup;
12. on any commit-phase failure, use the journal and rollback set to restore every replaced or
    deleted destination before returning; retain legacy paths and usable v5 state, never write the
    v6 stamp, and preserve an uncertain journal for explicit recovery rather than guessing. The
    next setup run detects an incomplete journal and requires verified rollback/recovery before a
    new transaction. Write `.forge/version` and `.forge/managed-files.tsv` only after all required
    operations succeed; and
13. print the categorized report, engine availability, materialization state, and runtime-readiness
    gaps.

Use an EXIT/finally cleanup for the staging directory but never discard a journal needed for
recovery. A partial required failure exits nonzero and does not stamp readiness. The recovery
helpers verify every current/original fingerprint before restoring and cannot delete arbitrary
paths from a hand-edited journal.

**Step 5: Preserve historical continuity migration.**

Retarget `--migrate` helpers to `.forge/local/state.md` while keeping existing `CONTINUITY.md`
and root-instruction protections. A legacy continuity migration may run before full refresh or
be invoked by its preflight, but content is never silently discarded.

**Step 6: Make migration tests GREEN.**

Run `bash tests/template/test-full-refresh.sh`, `bash tests/template/test-migrate.sh`, and
`bash tests/template/test-setup.sh`. Run `test-full-refresh.ps1` through the checked Windows
PowerShell 5.1 runner; when PowerShell is unavailable locally, require static contract parity and
the already-owning Windows CI rather than deferring behavior to Task 11. Include adversarial
fixtures that mutate the first and penultimate destination after inventory, create a destination
between quarantine and install, run two refreshes for the same scope, and recover an inactive stale
guard/journal; no case may clobber either version or stamp a partial install.

**Step 7: Commit.**

```bash
git add setup.sh setup.ps1 scripts state.template.md hooks manifests/managed-v6.tsv tests/template
git commit -m "feat: add ownership-aware full refresh migration"
```

## Task 4: Move State, Memory, Hooks, and Evidence to Host-Neutral Paths

**Files:**

- Modify: `state.template.md`
- Modify: `manifests/managed-v6.tsv`
- Modify: `rules/memory.md`
- Modify: `hooks/session-start.sh`
- Modify: `hooks/session-start.ps1`
- Modify: `hooks/pre-compact-memory.sh`
- Modify: `hooks/pre-compact-memory.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `hooks/build-evidence.sh`
- Modify: `hooks/build-evidence.ps1`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`
- Modify: `hooks/post-tool-format.sh`
- Modify: `hooks/post-tool-format.ps1`
- Modify: `hooks/check-bash-safety.sh`
- Modify: `hooks/check-bash-safety.ps1`
- Modify: `hooks/check-config-change.sh`
- Modify: `hooks/check-config-change.ps1`
- Create: `hooks/check-subagent-review.sh`
- Create: `hooks/check-subagent-review.ps1`
- Modify: `settings/settings.template.json`
- Modify: `settings/settings-windows.template.json`
- Modify: `settings/codex-hooks.template.json`
- Modify: `hooks/auto-approve-local-writes.sh`
- Modify: `hooks/auto-approve-local-writes.ps1`
- Modify: `hooks/lib/review-breaker.sh`
- Modify: `hooks/lib/review-breaker.ps1`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-session-start.sh`
- Modify: `tests/template/test-state-roundtrip.sh`
- Modify: `tests/template/test-build-evidence.sh`
- Modify: `tests/template/test-review-breaker.sh`
- Modify: `tests/template/test-bash-safety.sh`

**Step 1: Change fixtures to the v6 state contract and observe RED.**

Move fixture paths to `.forge/local/state.md`. Add a schema version, canonical worktree identity,
`Last active host`, immutable workflow base ref/resolved SHA, per-action host fields,
review receipt paths, council receipt path, and the existing goal nonce/objective/evidence
fields. Add Claude and Codex hook payload fixtures, including Codex `apply_patch`, concurrent
Stop execution, missing/old evidence side channels, command-based subagent review enforcement,
and config mutation detected at SessionStart/ship boundaries.

**Step 2: Implement canonical path resolution once per platform.**

Add a small sourced helper if necessary, but do not copy path logic into every hook. It must
derive project root from trusted hook input/current repository, reject paths outside it, and
resolve `.forge/local/state.md`, `.forge/local/memory/`, and receipt directories. Hooks may
read a legacy path only during a documented transition; v6 writes only canonical paths. The
dual-read parser maps v5 structural checkpoints/narrative but never treats legacy reviewer/goal/
authorization lines as v6-clean evidence. Retain this compatibility through v6.0 rather than
forcing an atomic parser/callsite cutover.

Make Stop verification self-sufficient and idempotent so concurrent Codex Stop hooks cannot
race `build-evidence`. Ensure successful Codex hooks emit valid empty JSON or the required
host-specific envelope. Extend post-format parsing to Claude `Write`/`Edit` and Codex
`apply_patch` payloads without executing patch text.

Implement the production hook-owned counter/marker half of the host-neutral Forge turn-budget
overlay qualified in Task 2. Validate the immutable user-owned authorization record and derive the
count from atomic no-clobber per-turn records; project state may mirror but cannot authorize,
increase, reset, or erase the bound. Persist the exact checkpoint before emitting
`FORGE_GOAL_BUDGET_EXHAUSTED`. Duplicate/concurrent Stop events cannot double-charge a turn, agent
tampering blocks rather than resetting, and a host switch continues the same nonce. Only tests may
use `FORGE_GOAL_TEST_TURN_BUDGET`. This task produces the marker; Task 9 installs the root-adapter
instructions that consume it and pause/terminate native autonomy. A conformance fixture proves the
Task 2 feasibility oracle and final Task 9 adapters use the same record/marker contract.

Add the same command receipt hook on both hosts for v6-capable subagent producers: it validates the
fresh per-task spec/quality review receipt and blocks completion when absent or non-clean. Do not
replace the Claude legacy prompt evaluator yet. Because Codex lacks `ConfigChange`,
persist the managed config fingerprint and verify it at Codex SessionStart and every ship gate;
Claude retains its immediate event and also runs the boundary check. Tests compare observable
allow/block outcomes, not nominal event names.

Register that command hook in both Claude settings templates and the Codex hook template in this
task alongside the existing Claude prompt hook. `workflow-capabilities.tsv` supplies a positive
producer/schema marker so exactly one evaluator is authoritative: unconverted v5 producers use the
legacy live prompt evaluator and the receipt command no-ops; v6-capable producers use the command
receipt and the legacy evaluator is stage-gated off. Task 9 removes the prompt hook and flips to
strict receipt-only only after every producer is converted. Installed-fixture tests invoke the
registered policy from both rendered host configs after Tasks 4, 5, 8, and each Task 9 checkpoint;
test legacy semantic rejection, v6 missing/non-clean receipt rejection, no double evaluation, and
allow paths. A direct script invocation alone is insufficient.

**Step 3: Make memory shared.**

Use two explicit layers: `.forge/local/memory/` for volatile per-developer drafts and
`.forge/memory/` for project-owned, reviewable durable learnings shared through Git. Pre-compact
reminders write only local memory; workflow compounding may promote a vetted learning into the
durable directory as an ordinary reviewed project change. Setup never manages or overwrites the
durable directory. Do not copy native Claude or Codex private memories automatically. Document
them as optional host context; only the two Forge layers have cross-host ownership rules.

**Step 4: Run focused hook and round-trip suites.**

Run all named hook/state suites. Add a concurrency test that starts both Stop hooks against a
fresh fingerprint and accepts either order while requiring the same final evidence. Add a
host-switch test where Claude records the plan checkpoint and Codex resumes at implementation
without repeating completed gates. Add two-worktree fixtures proving local state/memory never
cross-satisfy gates while a committed `.forge/memory/` learning is visible to both hosts after
ordinary Git propagation. Add authorization tamper/reset/increase/replay cases and prove only a new
human-created nonce can restart a goal budget.

**Step 5: Commit.**

```bash
git add state.template.md manifests/managed-v6.tsv rules/memory.md hooks settings tests/template
git commit -m "feat: make Forge continuity host neutral"
```

## Task 5: Add Fresh Reviewer and Investigation Dispatch

**Files:**

- Create: `hooks/lib/agent-dispatch.sh`
- Create: `hooks/lib/agent-dispatch.ps1`
- Create: `hooks/lib/host-context.sh`
- Create: `hooks/lib/host-context.ps1`
- Create: `hooks/lib/authorized-action.sh`
- Create: `hooks/lib/authorized-action.ps1`
- Create: `hooks/lib/candidate-fingerprint.sh`
- Create: `hooks/lib/candidate-fingerprint.ps1`
- Create: `scripts/render-dispatch-config.sh`
- Create: `scripts/render-dispatch-config.ps1`
- Create: `templates/review-result.template.txt`
- Create: `templates/runtime/claude-review-settings.template.json`
- Create: `templates/runtime/codex-review-overrides.template.tsv`
- Create: `hooks/check-external-mutation-auth.sh`
- Create: `hooks/check-external-mutation-auth.ps1`
- Modify: `manifests/managed-v6.tsv`
- Modify: `manifests/legacy-v5.tsv`
- Modify: `settings/settings.template.json`
- Modify: `settings/settings-windows.template.json`
- Modify: `settings/codex-hooks.template.json`
- Create: `commands/review.md`
- Modify: `commands/codex.md`
- Modify: `agents/research-first.md`
- Create: `agents/independent-reviewer.md`
- Create: `templates/adapters/codex-reviewer.template.toml`
- Create: `tests/template/test-agent-dispatch.sh`
- Create: `tests/template/test-agent-dispatch.ps1`
- Create: `tests/template/test-authorized-action.sh`
- Create: `tests/template/test-authorized-action.ps1`
- Create: `tests/template/fixtures/fake-engines/claude`
- Create: `tests/template/fixtures/fake-engines/codex`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/run-all.sh`

**Step 1: Write the four-mode and failure matrix tests first.**

Test Claude main with Codex reviewer, Codex main with Claude reviewer, Claude main with explicit
fresh Claude reviewer, and Codex main with explicit fresh Codex reviewer. Then test missing
binary, launch/auth failure, malformed/empty result, explicit unavailable choice, other-engine
failure, unsupported required CLI capability, timeout, fallback failure, artifact mutation, paths
with spaces, capability profiles, exit-zero-with-P1 findings, contradictory result envelopes,
reviewer-hook no-op behavior, and untrusted/disabled project hooks. Assert review/investigation
subprocesses never mutate Forge state, evidence counters, or authorization records.
Cover every requested-engine/availability combination and distinguish engine/capability launch
failure from semantic/artifact/authorization/invariant blocking. Add a hostile ambient-project
fixture with stateful hooks, plugins, and a write-capable MCP server; assert the generated child
configuration excludes all three while retaining one explicitly selected read-only query server.
Preserve the existing hermetic General second-opinion/analysis/brainstorming/question behavior as
the read-only `general` role, with Claude-main, Codex-main, and same-engine fallback cases.
For every code mode require distinct `code-spec` and `code-quality` invocation ids on the same
candidate; missing, duplicated, stale, or mixed-candidate pairs cannot certify.
Test that native Claude/Codex SessionStart/action contexts select their own host, while a stale
adapter, direct caller override, copied context, wrong session/thread id, or context revision
mismatch blocks rather than mislabeling same-engine review as cross-engine. For council calls, test
`fallback_policy=none` in every main/other seat failure so per-seat dispatch never changes topology.
Add a branch fixture with substantial feature changes already committed before a small final staged
delta. Both lenses must review the immutable workflow base SHA through the complete candidate, even
when the default branch moves or the workflow resumes in an already-existing worktree.
Tests use PATH-injected fake executables and never call a live model.

**Step 2: Define the dispatcher CLI and receipt schema.**

The stable interface is:

```text
<fixed claude|codex host launcher> agent-dispatch run \
  --engine auto|claude|codex \
  --fallback-policy automatic|none \
  --role general|plan|code-spec|code-quality|investigation|investigation-repro|prd|comments|council-advisor|council-chair \
  --profile review|investigate \
  --artifact file:PATH|git:head|git:working-tree \
  --workflow-base-sha SHA [--workflow-base-ref REF] \
  --prompt-file PATH --output PATH \
  [--conversation ephemeral|new|resume --session-id ID --session-id-output PATH] \
  [--timeout-seconds N]
```

The host-native settings/adapter registration supplies a fixed launcher that binds `active_host`
to the native SessionStart/action session or thread id and managed-config revision. The dispatcher
reads that hook-owned context; there is no model-controlled `--main`. Direct execution without a
matching current host context, stale launchers, and receipt/context mismatches are non-certifying
`invariant` failures. The review workflow maps its user-facing reviewer selection to `--engine`;
council dispatch uses the same primitive for each seat with `--fallback-policy none`, leaving all
whole-topology decisions to `council-dispatch`. The PowerShell interface has equivalent named
parameters. On
stdout, print concise selection
and fallback status; never hide degradation. Write a line-oriented receipt under
`.forge/local/reviews/` containing schema version, invocation id, timestamp, main host,
requested engine, first attempted engine, actual engine, fallback boolean/reason, role,
profile, fresh-process flag, artifact kind/identity/hash, worktree identity, Git HEAD, prompt
hash, immutable workflow base ref/resolved SHA, output path/hash, process exit status, semantic
verdict, maximum severity, findings digest, result-schema version, requested/bound
provider/model/reasoning effort, observable `actual_*` fields or explicit `UNOBSERVABLE`, exact
invocation/config hash, model qualification revision, and
`blocked_class=engine|capability|artifact|authorization|invariant|none`.
For
`git:working-tree`, fingerprint the base/head plus staged, unstaged, and untracked review scope;
for `git:head`, bind the exact commit; for `file:PATH`, bind the canonicalized file. Escape values
and reject newlines in scalar fields rather than sourcing receipt content. The final reviewer
envelope is line-oriented and machine-checked: only `verdict=CLEAN` with
`max_severity=NONE|P3` and no P0/P1/P2 finding records can certify. `FINDINGS` is a successful
review result that opens another revision round, not an engine-launch fallback; `BLOCKED`,
malformed, contradictory, or prose-only output cannot certify.

Preserve the current two-independent-review obligation without the external plugin: a shippable
code iteration requires two distinct fresh invocations against the same candidate,
`code-spec` (specification/reliability/test intent) and `code-quality`
(quality/security/maintainability). Reviewer engine selection/fallback applies independently to
both, invocation ids cannot match, and neither result can substitute for the other. Plan/PRD/
comment/General roles remain single-invocation unless their workflow already requires another gate.

Implement `candidate-fingerprint` here as the single snapshot primitive consumed by the dispatcher.
For every Git artifact it requires the workflow base ref and resolved SHA persisted when the
workflow/worktree began; it never silently recomputes the base from a moving default branch. Include
that base SHA, current HEAD, index tree, unstaged binary diff, and an ordered path/content manifest
for every in-scope untracked file, bound to canonical worktree identity. Capture uses `lstat`/
no-follow traversal with path containment, per-file/total size limits, and regular-file/mode
validation. Tracked symlinks are represented as inert Git mode plus target bytes and never
materialized as followable links; untracked symlinks, FIFOs, devices, sockets, Windows
junctions/reparse points, and ancestor escapes are rejected. Add Unix symlink/FIFO and Windows
junction/reparse fixtures. Materialize the isolated sibling candidate Git repository with the full
history/diff from workflow base through current HEAD plus the exact working/index manifest; the
review prompt explicitly scopes `base_sha..candidate`, so earlier task commits cannot disappear.
Recheck identity immediately after capture; a racing mutation discards the snapshot. Reject a base
that is missing, not an ancestor under the workflow's declared semantics, or inconsistent with
state. Task 8 extends the same primitive to verification/E2E and candidate-to-commit promotion
rather than defining a second fingerprint.

**Step 3: Implement deterministic engine selection and fresh invocation.**

With `fallback_policy=automatic`, use this complete selection table: `auto` requests the other engine; explicit `claude|codex`
requests exactly that engine, including an explicit main-engine review. If the requested candidate
is unusable because of an `engine` or `capability` failure, visibly retry once with the only other
usable engine in a new fresh invocation. Thus an explicit main-engine launch failure may fall back
to the other engine, while an explicit healthy same-engine review is not labeled fallback. If the
remaining engine is unavailable or fails, exit nonzero and do not emit clean evidence. A semantic
`FINDINGS` result returns normally to the revision loop. `BLOCKED` with class `artifact`,
`authorization`, or `invariant` never triggers engine fallback; `BLOCKED` with class `engine` or
`capability` does. Record the requested candidate, every attempted candidate, blocked class, and
fallback path in the receipt.

With `fallback_policy=none`, attempt the selected engine exactly once and return the structured
failure to the owning orchestrator without trying another engine. Council uses only this mode for
all advisor/critique/chair turns, so a main-seat failure cannot create a 2-main/3-other topology and
an other-seat failure cannot be hidden as a per-seat fallback.

The disposition table is exhaustive even when no child envelope can be trusted. Missing binary,
authentication/launch failure, nonzero exit, timeout, missing/empty output, malformed schema,
contradictory fields, and prose-only output are dispatcher-observed `engine|capability` failures
and visibly try the remaining engine. A valid semantic `FINDINGS` returns to the revision loop;
valid `BLOCKED artifact|authorization|invariant` stops without fallback. The dispatcher, not child
text, assigns launch/schema classes. Tests cover every row for auto, explicit-other, and
explicit-main selection.

Probe the exact host flags/subcommands required for the selected role before launch. Treat a
present binary that lacks fresh-run, sandbox, output-capture, or goal composition capability as
unusable for that operation and record the missing capability as the fallback reason. Do not
key correctness only to a version string; documentation still records the tested minimum and
current versions so developers can upgrade intentionally.
Resolve the role's fixed v1 provider/model/effort profile from `host-capabilities.tsv` and pass it explicitly. Validate
only the `actual_*` fields the Task 2 captured event matrix proves observable; fail on an observable
mismatch. For non-observable provider/model/effort, record `UNOBSERVABLE`, bind the exact argv/config
and qualification hash, and require unsupported values to fail before/at launch. Do not infer
actual identity from requested configuration or claim silent-substitution detection the host does
not expose. Tests replay captured live events, low-effort/local overrides, unsupported values,
missing observable metadata, and requested-versus-actual mismatches; none may emit certifying
evidence outside its qualified row. No v1 model override or arbitrary tuple qualification exists.

Ordinary review/investigation runs Claude headlessly with `claude -p --no-session-persistence` using the Task 2 qualified
OAuth-compatible safe-mode recipe, or the separately qualified bare recipe only for explicit
API-key/provider/helper authentication, plus a private settings/MCP file. Codex runs with
`codex exec --ephemeral` in the Task 2 qualified clean scratch primary repository, using the existing PTY helper only when the
installed CLI requires it. `render-dispatch-config` renders Claude's private configuration and
Codex's checked CLI-override/feature-disable argv from separate host templates; it never claims
Codex accepts an arbitrary config file. The exact frozen candidate is a sibling real Git repository
provided as an additional data directory; Codex's primary cwd remains the empty scratch repository,
so candidate-owned `AGENTS.md`, `.codex`, `.agents`, and plugin files are reviewable bytes but not
startup discovery surfaces. Prompts identify the sibling as the logical project root and require
Git/project commands to execute there. Both receive the canonical role
prompt/schema explicitly, and the child receives only an explicitly selected read-only MCP/query
channel. Set `FORGE_DISPATCH_MODE=review|investigate` so every Forge hook is also a tested no-op.
Pre-launch and in-process canaries must prove ambient project/user hooks, plugins, skills, MCP,
rules, and instructions are absent; otherwise that engine is unusable for the role and follows
normal fallback. The review profile exposes read tools only.

Only `council-advisor` may request the qualified Task 2 two-turn transport. Its `new` call records
the exact Claude session UUID or Codex structured thread id; its `resume` call requires the same
engine, seat, host context, candidate/question/config/canary hashes, and private session store. No
other role may resume, and `--fallback-policy none` means a missing/failed resume returns to the
council orchestrator without per-seat engine substitution. Cleanup is bounded to the exact owned
session artifacts. If the selected engine lacks qualified exact-id resume, that seat is a
capability failure and the council applies its whole-attempt policy.

The investigation profile allows sandboxed writes and project execution inside its disposable
candidate copy but disables arbitrary process network. After the child exits, the dispatcher
validates and replays only declared reproduction/artifact paths into the real worktree while the
source candidate identity is still exact; any concurrent mutation rejects replay. Internet
research uses host-native WebSearch/WebFetch, and live
queries use only declared read-only MCP tools/runners and read-only credentials copied by
reference into the sanitized per-invocation configuration. If a project has no enforceable
read-only channel, or selected host flags cannot exclude an ambient write-capable channel, the
live query is `BLOCKED` rather than granting general write credentials. This is the authorization
boundary; prompt text and mutation-pattern hooks are not.

Treat the investigator's result as a hypothesis until a separate `investigation-repro` invocation
receives only the claimed hypothesis, exact primary check, and an independent control—not the
investigator's reasoning/context. It reruns both through the same read-only external/worktree
boundaries and writes a reproduction receipt with a distinct invocation id, candidate/query/command
hashes, control hash, outputs, and status `REPRODUCED|FAILED|PARTIAL|UNVERIFIED`. A live finding is
actionable/verified only when the primary result agrees and the control behaves as predicted;
otherwise surface the status and do not silently promote it. Tests include a wrong date filter,
false-positive query without a control, and a correct reproduction.

Default each invocation to the current documented 20-minute bound and make the timeout
configurable. A timeout is a launch failure for fallback purposes, must terminate the spawned
process tree as far as each supported platform permits, and records `fallback_reason=timeout`;
never reuse a partial output as a valid result.

**Step 4: Keep external mutation human-executed in v1.**

The investigator may propose an exact action but cannot perform it in its read-only external
profile, and a conversational approval line or agent-writable receipt is never treated as proof of
human authority. `authorized-action` only canonicalizes a predeclared executable/argv adapter,
renders the exact system/operation/target/action hash and expected effect into a local pending-action
manifest, and verifies a result the user reports afterward. The audit receipt records nonce,
worktree identity, exact action, timestamps, and outcome, but is audit-only and cannot unlock a
model tool.

For v1, pause and ask the developer to execute the rendered deterministic command themselves in
their terminal, or use a host permission UI only if live qualification proves it launches the
exact runner with a non-agent-forgeable approval token. The main agent and every fresh child are
never given the mutating credential, MCP tool, or automated runner path. MCP-only mutation,
including remote OAuth/Streamable HTTP, is visibly `BLOCKED` with manual instructions until Forge
adopts and qualifies a real MCP client/transport runtime in separate scope. Direct adapters use a
fixed executable plus argv array—no shell evaluation, arbitrary network, or reusable credential
serialization. A retry or uncertain result requires another human execution decision.

Register the external-mutation hook for both hosts as defense in depth: it blocks recognizable
agent mutation attempts and points to the pending human action, but it is not claimed as the
security boundary. Tests prove an agent-written approval/receipt never unlocks execution, the
model has no mutating MCP tool, only allowlisted action adapters render, nested shell text is inert,
and a user-reported result remains `UNVERIFIED` until the independent reproduction step succeeds.
Credentials remain in protected user/host surfaces and are never serialized into prompts, argv
logs, receipts, or tracked evidence.

**Step 5: Replace the engine-specific `/codex` workflow.**

Create host-neutral `review.md` for General second opinions/analysis/brainstorming/questions plus
plan, code, PRD, review-comment, and investigation roles. General remains hermetic and read-only.
Keep `codex.md` through Tasks 5-8 as a clearly deprecated transitional shim that delegates to
`review.md`/the dispatcher while current feature/bug/rule callers still name it. It preserves the
old invocation contract but emits new receipts where the dual-mode consumer can read them. Add a
per-checkpoint dangling-command test: every live workflow reference must resolve to an installed
command/skill. Task 9 removes and tombstones the shim only after converting every caller.

**Step 6: Make Bash and PowerShell behavioral tests GREEN and run one optional real-CLI smoke per installed engine.**

The deterministic fake-engine suite is required on both platforms. The PowerShell suite owns
engine selection/schema fallback, timeout descendant cleanup, candidate/path handling, and
human-action blocking in this task; Task 11 does not become the first behavioral execution of
these `.ps1` files. Run it on Windows PowerShell 5.1 when available and in the owning Windows CI
job. A real smoke may be skipped with an explicit reason when authentication/network is
unavailable; it is not the primary test oracle.

**Step 7: Commit.**

```bash
git add hooks/lib hooks/check-external-mutation-auth.* commands agents manifests settings \
  scripts/render-dispatch-config.* templates/adapters templates/runtime \
  templates/review-result.template.txt tests/template
git commit -m "feat: dispatch fresh cross-engine and same-engine reviews"
```

## Task 6: Make Engineering Council Dynamic and Failure-Tolerant

**Files:**

- Modify: `skills/council/SKILL.template.md`
- Modify: `skills/council/references/advisors.md`
- Modify: `skills/council/references/output-schema.md`
- Modify: `skills/council/references/peer-review-protocol.md`
- Create: `hooks/lib/council-dispatch.sh`
- Create: `hooks/lib/council-dispatch.ps1`
- Modify: `agents/council-advisor.md`
- Modify: `manifests/managed-v6.tsv`
- Create: `tests/template/test-council-dispatch.sh`
- Create: `tests/template/test-council-dispatch.ps1`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/run-all.sh`

**Step 1: Write topology and fallback tests first.**

For each main host, assert the healthy topology has advisors 1-3 on the main engine,
advisors 4-5 on the other engine, and the chairman on the other engine. Assert all six
seat sessions are fresh and retain distinct advisor personas. Each advisor performs initial advice
and then anonymous peer critique as two isolated turns in its own session; it receives only the
other anonymous drafts for the critique turn. Also test an explicit per-seat
engine override that retains all required roles. Before Round 1, preflight every configured engine
for its binary, qualified council profile, and exact-id resume capability. If a configured
non-main engine is already known unavailable, announce the reason and start one all-main attempt
directly—do not launch and discard a partial mixed council. Otherwise inject a runtime failure in
each non-main-engine seat during initial advice, anonymous peer review, and chairman synthesis;
also inject every main-engine seat/turn failure, including a custom `chair=main`. All seat
dispatches use `fallback_policy=none`, so a main-engine failure blocks and a non-main-engine
failure reaches the topology orchestrator unmasked. When a mixed attempt has begun and a
non-main-engine turn fails, discard that entire partial mixed council and rerun all five fresh
advisor sessions (both turns) plus a fresh chairman on the main engine. Any main-engine failure,
including during the all-main fallback, is a blocker rather than a fabricated verdict. Assert the
known-absent case launches exactly the six fresh all-main sessions and eleven turns, with no hidden
discarded attempt.

**Step 2: Implement topology orchestration over `agent-dispatch`.**

The council dispatcher accepts optional repeated `--seat-engine <seat>=claude|codex|main|other`
overrides and validates that all five named advisor roles and one chairman remain present.
Round 1 starts five fresh advisor seat sessions. The orchestrator strips engine/author metadata,
assigns stable anonymous labels, and builds a content-hashed bundle. Round 2 resumes each same
advisor seat for one second turn with only the other anonymous drafts and peer-review schema—no
other seat identity or hidden context. A sixth fresh chairman session then receives the original
question, anonymous advice, and anonymous peer reviews. This preserves five independent critiques
without paying for five additional process/session startups.

Each two-turn seat uses Task 5's qualified council-only exact-id transport. Bind the session id,
both turn ids, engine, persona/seat, question/bundle hashes, isolation canaries, and configuration
revision. A missing, cross-seat, wrong-engine, or unresumable id is a capability failure; never
silently substitute a fresh peer invocation. The chairman is one fresh ephemeral session.

Write receipts for six fresh sessions and eleven turn results plus one topology receipt with
intended and actual engine per role/round, topology mode `mixed|custom|same-engine-fallback`,
trigger reason, question hash, anonymized bundle hash, advisor/peer turn ids and output hashes,
chairman output hash, minority reports, and final verdict. Any failed non-main-engine advisor,
critique, or chairman turn discards every artifact from that started attempt and triggers a
complete all-main rerun of all six fresh sessions and all eleven turns. A custom main-engine
chairman failure blocks under the same main-engine rule. Use parallel processes only where
Bash/PowerShell error collection remains
deterministic; otherwise prefer correct bounded sequential dispatch over platform divergence.

**Step 3: Keep the existing five personas and anonymous peer review.**

Engine assignment becomes runtime data, not persona text. Round-2 reviewers and the chairman see
only anonymized artifacts. Minority reports remain mandatory. A fallback rerun receives the
original question and personas, not failed agents' hidden context or discarded partial outputs.

**Step 4: Run the council and cross-file contract suites.**

Require parity for Bash and PowerShell topology/receipt fields and no hardcoded assumption that
Claude or Codex is always chairman. The owning PowerShell 5.1 behavioral suite exercises
successful parallel/sequential collection, same-session second-turn isolation, other-engine failure in each round/chair, descendant
cleanup, and complete all-main rerun now; Task 11 only repeats these as integration coverage.

**Step 5: Commit.**

```bash
git add skills/council agents/council-advisor.md hooks/lib/council-dispatch.* manifests/managed-v6.tsv \
  tests/template
git commit -m "feat: add dynamic dual-engine council dispatch"
```

## Task 7: Create and Pressure-Test Forge-Owned Portable Skills

**Files:**

- Modify: `skills/release/SKILL.template.md`
- Modify: `skills/ui-design/SKILL.template.md`
- Modify: `skills/generate-image/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/brainstorming/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/writing-plans/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/systematic-debugging/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/subagent-driven-development/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/executing-plans/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/requesting-review/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/receiving-review/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/simplifying-work/SKILL.template.md`
- Create if the unique-callsite test passes: `skills/verifying-work/SKILL.template.md`
- Modify: `manifests/managed-v6.tsv`
- Modify/Create: supporting references named by each new skill after contract inspection
- Modify: `tests/template/test-contracts.sh`
- Create: `tests/template/test-skill-pressure-schema.sh`
- Create: `tests/template/fixtures/skill-pressure/*`
- Create: `scripts/qualify-skill-pressure.sh`
- Create: `scripts/qualify-skill-pressure.ps1`
- Modify: `tests/template/run-all.sh`

**Step 1: Inventory external skill dependencies and write failing skill contracts.**

Complete `manifests/workflow-capabilities.tsv` before authoring: map every current Superpowers,
PR review toolkit, `/simplify`, code-simplifier, headless-execution, and review-comment behavior to
one existing agent/hook/receipt, explicit canonical workflow step, or candidate owned skill. The
nine listed new skill paths are candidates, not a quota. Require a unique live callsite and a
behavioral gap not already enforced by the reviewer dispatcher, verify agents, state/evidence
hooks, or canonical workflow before creating a skill. In particular, do not create
`requesting-review` or `verifying-work` merely to duplicate Task 5 or Task 8. Assert every surviving
portable skill exposes its unique contract through both host adapter formats while rejecting
host-specific tool syntax, unresolved plugin references, duplicate policy ownership, and missing
mappings.

**Step 2: Fork and test each required Forge-owned skill one at a time.**

For each new skill, use the separate authenticated `scripts/qualify-skill-pressure.*` runner to
follow the writing-skills RED/GREEN/REFACTOR loop before moving to the next:

1. record the exact current contract Forge relies on;
2. run a fresh-agent pressure scenario without the skill and capture the failure/rationalization;
3. write the minimum host-neutral skill and references needed to prevent it;
4. rerun the same scenario with the skill and require compliance;
5. add loophole-specific tests; and
6. only then add the skill to the managed manifest.

Do not bulk-copy plugin text. Preserve attribution/licensing where required and remove
host-specific tool syntax. Subagent-driven development maps to fresh native subagents when the
active host supports them and to the same future evidence/review gate contract on both hosts.

**Step 3: Record live qualification separately and keep deterministic CI hermetic.**

Preserve a redacted local qualification log for each surviving new skill and a manifest rationale for every
candidate rejected as duplicate. This bounded fresh-agent test is deliberate: the active
writing-skills process requires a before/after pressure case for every skill actually authored
because deterministic file-shape tests cannot expose prompt rationalization. It needs no human or
external-system coordination. At this checkpoint, the new skills may be
installed but are not yet load-bearing; the existing workflow and evidence suites must remain
green. `test-skill-pressure-schema.sh` and its checked fixtures validate attestation shape and
RED/GREEN linkage only; `run-all` never authenticates or invokes a model. Later tasks switch gate
parsing first and workflow callsites only after dual-read support.

**Step 4: Commit.**

```bash
git add skills manifests/managed-v6.tsv tests/template scripts/qualify-skill-pressure.*
git commit -m "feat: add Forge-owned portable workflow skills"
```

## Task 8: Add Dual-Read Receipt-v2 Evidence Gates

**Files:**

- Modify: `hooks/build-evidence.sh`
- Modify: `hooks/build-evidence.ps1`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `hooks/lib/review-breaker.sh`
- Modify: `hooks/lib/review-breaker.ps1`
- Modify: `hooks/lib/candidate-fingerprint.sh`
- Modify: `hooks/lib/candidate-fingerprint.ps1`
- Create: `hooks/lib/verification-receipt.sh`
- Create: `hooks/lib/verification-receipt.ps1`
- Modify: `manifests/managed-v6.tsv`
- Modify: `agents/verify-app.md`
- Modify: `agents/verify-e2e.md`
- Modify: `state.template.md`
- Modify: `tests/template/fixtures/state-md-build-evidence/*`
- Modify: `tests/template/fixtures/state-md-workflow-gate-evidence/*`
- Modify: `tests/template/test-build-evidence.sh`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-review-breaker.sh`
- Modify: `tests/template/test-state-roundtrip.sh`

**Step 1: Write failing schema-v2 evidence tests while retaining v5 fixtures.**

Cover clean other-engine review, clean explicit same-engine review, clean fallback review,
missing receipt, non-fresh receipt, wrong artifact hash, wrong HEAD, post-review mutation, wrong
role/profile, semantic `FINDINGS|BLOCKED|CLEAN`, exit-zero-with-P1 findings, stale goal nonce,
host switch with valid evidence, copied same-HEAD receipt from another worktree, council fallback
receipt, and investigation authorization mismatch. Keep the existing v5 fixtures green in
compatibility mode, but require migrated v5 reviewer/goal/authorization evidence to be invalid.
Add candidate-bound verification cases: E2E then mutation then clean review, verify-app then
untracked-file addition, staged/unstaged mutation, omitted untracked file, pre-commit candidate
promotion to a matching commit, wrong parent, tree mismatch, and a real modify/create/rename/mode
change → `git add -A` → freeze → review/verify/E2E → commit sequence. Include an intermediate
dirty review whose later staging necessarily creates a new ship candidate and requires new final
receipts. No pre-mutation verification may make a later candidate shippable.

**Step 2: Replace engine identity gates with receipt validity.**

`compute_reviewer_gate` / `Compute-ReviewerGate` validate schema, fresh invocation, requested and
actual selection, fallback reason when applicable, role, artifact fingerprint, HEAD, output
fingerprint, immutable workflow base SHA, structured verdict/max severity/findings digest, current
state linkage, and canonical worktree identity. A receipt copied between worktrees is invalid even
at the same commit, and a receipt whose base differs from the persisted workflow base cannot omit
earlier feature commits.
Same-engine evidence is valid when the receipt proves a fresh bounded process. Only semantic
`CLEAN` with no P0/P1/P2 certifies; process success never substitutes. Maintain invalidation after
mutation. For the code ship gate, apply these validations to both required lenses and additionally
require matching iteration/candidate/worktree plus distinct invocation ids; one clean receipt or
two copies of one invocation never certify.

The fingerprint primitive supports dirty candidates for intermediate review, but only a
`staged-clean` candidate is shippable. After implementation, simplification, changelog/solution
documentation, E2E use-case graduation, and generated tracked specs are complete, force-stage only
exact workflow-approved ignored artifacts from the intended list, then run `git add -A`.
Freeze fails if any unstaged change or in-scope untracked path remains. The ship candidate identity
is immutable workflow base SHA, pre-commit HEAD, exact index tree, and canonical worktree identity; staging is
therefore preparation before freeze, never a post-review mutation. Every final verifier writes a
structured receipt with candidate id, command/profile, start/end, exit status, local report hash,
and tool-specific result. Final review, verify-app, and E2E are read-only with respect to tracked/
in-scope source; reports and receipts go only under ignored `.forge/local/` evidence paths.
`build-evidence` requires all final gates to refer to the same current staged-clean candidate id,
replacing the current branch-point/mtime freshness test. Any index, tracked, unstaged, or in-scope
untracked mutation invalidates every candidate-bound receipt and restarts freeze plus all final
gates.
Register both `verification-receipt` helpers in `managed-v6.tsv` before verify-app/E2E callers
activate and cover their installed revisions in the same fixture.

Commit promotion never advances the real branch before validation. The helper first revalidates
staged-clean identity, then creates a disposable worktree/ref at the expected pre-commit HEAD,
materializes the exact frozen index tree, and captures the repository's configured standard hook
paths/hashes. It directly runs the normal pre-commit, prepare-commit-msg, and commit-msg executables
with Git's documented cwd/argv/environment, but deliberately does not run `git commit` and cannot
fire post-commit yet. After these pre-commit hooks are stable, create the exact parent/tree/message
commit object with `git commit-tree` (including configured signing when qualified) on a temporary
ref. Before launch, expose only an explicit, hash-checked allowlist of
ignored hook runtime dependencies from the original worktree into the disposable runner as
read-only temporary copies/projections; those bytes are never added to the candidate. Missing,
changed, writable, escaping, or undeclared dependencies block promotion with exact remediation.

If a successful hook changes the temporary tree, capture a bounded no-follow change artifact
covering regular tracked/untracked paths, modes, renames, and deletions. Reject escapes, Forge
local/evidence/auth paths, oversized/binary output outside policy, and any mutation not permitted by
the workflow scope. If the original candidate identity is still exact, replay the validated hook
artifact into the original worktree, stage it, dispose the temporary attempt, and require a new
freeze plus both reviews/verify/E2E. Allow only the checked small replay limit; a hook that mutates
again after replay is `BLOCKED` rather than looping forever. A failed hook or invalid artifact is
never replayed. The real branch remains untouched throughout this repair cycle.

If the temporary commit's parent and tree exactly equal the expected HEAD and frozen tree, atomically
update the real branch ref with compare-and-swap (`git update-ref <branch> <candidate-commit>
<expected-head>`), then verify the original worktree/index are clean at that commit. A concurrent
HEAD change rejects without overwrite and never runs post-commit. Only after successful CAS invoke
the previously captured exact post-commit executable once from the original promoted worktree,
with the real branch checked out, HEAD at the promoted commit, and Git's normal branch/cwd/
environment contract. A post-commit failure is reported as `POST_COMMIT_HOOK_FAILED`; a mutation is
reported as `POST_COMMIT_DIRTY`. Like normal Git post-commit behavior, neither rewrites or rolls
back the valid commit, but either blocks push/workflow completion until explicitly handled. Recheck
HEAD, tree, index, and worktree immediately after the hook. The promotion receipt records old candidate id, hook
run hashes/status, temporary commit, new branch commit/tree, and worktree identity; a later amend or
mutation invalidates it. Tests include an auto-fixing successful pre-commit hook whose artifact is
replayed and whose second promotion succeeds after all gates rerun, a repeatedly mutating hook that
hits the bound, ignored dependency present/missing/changed cases, pre-hook failure, post-hook success/
failure/mutation, successful CAS, and concurrent CAS failure. Assert post-commit sees the real branch
name and original worktree cwd, runs exactly once only after successful CAS, and the real branch
never advances to a mismatched tree.
Bash and PowerShell must compute identical candidate identities for the same fixture. Intermediate
dirty receipts can never be promoted.

Retire the engine-specific Codex plus plugin-specific PR-toolkit implementations, not the two-seat
obligation. The portable certification artifact is the pair of clean `code-spec` and
`code-quality` receipts from distinct fresh invocations on the same iteration/candidate/worktree.
Their canonical prompts are non-overlapping but together cover specification, reliability,
testing, quality, security, and maintainability. Rebase the existing convergence breaker on the
first iteration where both receipts are clean, preserving its post-certification round limit and
human-only adjudication rather than weakening or deleting the loop.

**Step 3: Keep v5/v6 dual-read compatibility through v6.0.**

State/evidence parsers accept v5 structure only for an unmigrated legacy harness and v6 receipts
for the new harness. The migration translator marks old clean-review/goal/authorization evidence
stale, so dual-read never upgrades trust implicitly. Keep this reader for the v6.0 compatibility
window; removing it is a later versioned migration, not part of the callsite switch.

**Step 4: Run all evidence and state suites, then commit.**

Compare Bash and PowerShell decisions. Deliberately mutate the reviewed artifact after passing
review, verify-app, and E2E receipts and require the ship gate to block. Run current v5 workflow
tests unchanged plus the new v6 receipt matrix so this is a working compatibility checkpoint.

```bash
git add hooks agents/verify-app.md agents/verify-e2e.md state.template.md \
  manifests/managed-v6.tsv tests/template
git commit -m "feat: add dual-read engine-neutral evidence gates"
```

## Task 9: Switch Workflows to the Host-Neutral Contract in Bounded Groups

**Files:**

- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `scripts/verify-runtime.sh`
- Modify: `scripts/verify-runtime.ps1`
- Modify: `commands/new-feature.md`
- Modify: `commands/fix-bug.md`
- Modify: `commands/quick-fix.md`
- Modify: `commands/finish-branch.md`
- Modify: `commands/review-pr-comments.md`
- Modify: `commands/prd/discuss.md`
- Modify: `commands/prd/create.md`
- Create: `commands/forge-goal.md`
- Remove: `commands/codex.md`
- Modify: `FORGE.template.md`
- Modify: `templates/adapters/CLAUDE.block.template.md`
- Modify: `templates/adapters/AGENTS.block.template.md`
- Modify: `skills/release/SKILL.template.md`
- Modify: `agents/verify-app.md`
- Modify: `agents/verify-e2e.md`
- Modify: `agents/research-first.md`
- Modify: `rules/workflow.md`
- Modify: `rules/critical-rules.md`
- Modify: `settings/settings.template.json`
- Modify: `settings/settings-windows.template.json`
- Modify: `settings/codex-hooks.template.json`
- Modify: `manifests/managed-v6.tsv`
- Modify: `manifests/workflow-capabilities.tsv`
- Modify: `docs/prds/forge-goal.md`
- Create: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/run-all.sh`

**Step 1: Write the complete workflow-parity test before changing callsites.**

Assert both installed host surfaces cover PRD discussion/create, new feature, bug, quick fix,
review, investigation, council, native-goal composition, review comments, finish branch, release,
state/memory, verify-app, and verify-e2e. Reject unresolved `superpowers:`, PR-toolkit,
`/simplify`, code-simplifier, and hardcoded `/codex` runtime dependencies. The checked
`workflow-capabilities.tsv` mapping must cover every removed behavior and installed adapter.
Make parity stage-aware: its checked allowlist is derived from the workflow capability manifest
and names the bounded conversion group in progress, so it rejects regressions without requiring
later groups to be converted early. Add preserved custom native-goal collision fixtures for
`.claude/commands/goal.md` and `.agents/skills/goal/`.

First revise `docs/prds/forge-goal.md` so its non-goals, resume semantics, budget rules, and
acceptance rows distinguish resettable native-host counters from the authoritative persistent Forge
authorization/turn records. The Forge counter and ceiling survive interruption and host switching;
resume may never reset them. Then derive a checked host-neutral goal behavior matrix from that
updated PRD, not only the happy path. It includes objective/nonce creation, budget exhaustion checkpointing, periodic
stuck warnings, user-input/authorization termination, interrupted-session persistence, same-host
resume, cross-host resume at the exact next unchecked step, evidence invalidation, and terminal
status. Preserve the existing shared-hook cases and require both root adapters to compose every
Must behavior over their native `/goal`; an unsupported Must behavior is `BLOCKED`, not silently
reduced parity.

**Step 2: Switch PRD, review, investigation, and agent/rule callsites; run and commit.**

Use adapter-supplied current host, canonical `.forge` paths, owned skills, and structured
dispatcher receipts. Keep the legacy plugin entries and legacy review-hook behavior available for
the still-unconverted feature/bug/quick workflows; the new receipt hook runs in compatibility mode
and cannot require receipt-v2 from a workflow that the stage allowlist still marks v5. Run focused
parity/hook tests plus the full current suite before the first bounded commit.

**Step 3: Switch new-feature, fix-bug, and quick-fix; run and commit.**

Record `Last active host`, resume the next unchecked durable step, replace Claude-only
Task/AskUserQuestion syntax with portable capability instructions, preserve worktree/TDD/review/
simplify/verify/E2E gates, and use automatic reviewer fallback. Add the simultaneous-editing
warning without locks or leases. Make these workflows' subagent calls produce the structured
receipt while legacy plugins remain installed, so both old and new evidence readers stay green at
this checkpoint. At new workflow/worktree creation, persist the intended base ref and resolved base
SHA before the first change. An adopted existing worktree reuses an already persisted base or
requires an explicit base when ancestry is ambiguous; it never recomputes from a later-moving
default branch. Pass that SHA through every candidate, dispatcher, receipt, isolated repository,
and prompt. Run all workflow/evidence/state suites before this commit.

Rewrite the finalization order explicitly: implementation and TDD; create/update solution and
changelog material; design E2E cases and run a preliminary feature E2E pass while fixes are still
allowed; after that pass, graduate the committed use cases and generate/run any tracked specs; run
simplification and apply any changes; force-stage exact approved ignored artifacts from the
workflow's intended list, then `git add -A`; freeze the staged-clean candidate; run final
review, verify-app, and the complete feature/regression E2E matrix read-only against that same
candidate; then commit through candidate promotion. E2E's
human-readable report and all receipts are local evidence under `.forge/local/`, not committed
post-verification source. Any finding or mutation restarts from staging/freeze and repeats all three
final gates. Preserve intermediate reviews where useful, but they never satisfy the ship gate.

**Step 4: Switch review-comments, finish-branch, release, and goal composition; run and commit.**

`commands/forge-goal.md` is canonical source material installed only as
`.forge/workflows/goal.md`. The manifest must explicitly forbid a Claude command or Codex skill
adapter named `goal`, preventing either native `/goal` from being shadowed. Root host instructions
compose their native `/goal` over this objective/nonce/evidence/authorization contract; they do
not claim native sessions transfer. PR creation and a new external mutation are explicit human
pauses; ordinary engine fallback is automatic. Finish-branch preserves translated seed-snapshot
semantics and durable/local memory ownership. Update `FORGE.template.md` and both generated root
adapter blocks in this same group so native-goal composition is an installed instruction, not an
unowned prose promise. The root adapters consume Task 4's exhaustion/stuck markers, require the
human-created goal authorization record, and pause/terminate native autonomy; conformance tests
compare them to the Task 2 proving oracle. If the authenticated native goal row remains blocked,
install the documented material but keep goal activation and host readiness blocked rather than
claiming support. Setup preserves any custom native-goal command/skill collision, marks that
host not `RUNTIME_READY`, and prints exact rename guidance instead of shadowing it.

Only after every workflow group is converted, remove clean-install legacy plugin entries and the
Claude legacy prompt evaluator, enable the strict receipt-only hook, activate full no-legacy
parity, and retain provenance-aware
full-refresh tombstones for old installs. At that same final checkpoint, remove the transitional
`commands/codex.md` shim and add its positively owned installed path to the tombstone manifest;
the dangling-reference test must prove no live caller remains. This ordering keeps each
intermediate commit executable and green rather than installing a strict consumer before its
producers.

**Step 5: Run complete parity after each bounded commit.**

Every commit in this task must keep `run-all.sh` green because Task 8 already understands both
state schemas. Retain the v5 reader until a future release; do not create a final cleanup mega-diff.

```bash
git add commands agents rules settings manifests/managed-v6.tsv \
  manifests/workflow-capabilities.tsv tests/template
git commit -m "feat: switch core workflows to engine-neutral adapters"
git add commands/new-feature.md commands/fix-bug.md commands/quick-fix.md \
  manifests/workflow-capabilities.tsv tests/template
git commit -m "feat: make development workflows host neutral"
git add setup.sh setup.ps1 scripts/verify-runtime.* commands/finish-branch.md \
  commands/review-pr-comments.md commands/forge-goal.md \
  commands/codex.md \
  docs/prds/forge-goal.md \
  FORGE.template.md templates/adapters/CLAUDE.block.template.md \
  templates/adapters/AGENTS.block.template.md skills/release/SKILL.template.md \
  settings/settings.template.json settings/settings-windows.template.json \
  settings/codex-hooks.template.json manifests/managed-v6.tsv \
  manifests/workflow-capabilities.tsv tests/template
git commit -m "feat: complete dual-host workflow parity"
```

## Task 9A: Make Resource Discipline Load-Bearing in Review Loops

**Files:**

- Modify: `FORGE.template.md`
- Modify: `rules/principles.md`
- Modify: `rules/workflow.md`
- Modify: `rules/critical-rules.md`
- Modify: `commands/new-feature.md`
- Modify: `commands/fix-bug.md`
- Modify: `commands/quick-fix.md`
- Modify: `commands/review.md`
- Modify: `commands/review-pr-comments.md`
- Modify: `agents/independent-reviewer.md`
- Modify: `templates/review-result.template.txt`
- Create: `tests/template/test-resource-discipline.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/run-all.sh`

**Step 1: Write the resource-discipline contract before changing prompts.**

Add failing static and installed-workflow fixtures that require the same concise policy at the
root instruction, canonical rule, plan-review, code-review, independent-reviewer, and closure
review surfaces. The contract is:

1. optimize for the smallest correct solution and treat developer time, session length, tokens,
   and money as finite engineering resources;
2. do not pursue perfection, cosmetic polish, speculative hardening, or edge cases without a
   concrete supported trigger, stated acceptance criterion, material likelihood, security impact,
   or data-integrity impact;
3. one broad review is allowed for an artifact revision; after fixes, closure review verifies the
   named findings and direct regressions only rather than opening another unrelated broad scan;
4. the default loop budget is one broad review, one repair pass, and one closure review. A still-
   open reachable P0/P1 may receive one surgical repair, after which Forge surfaces the blocker to
   the developer instead of iterating indefinitely;
5. P3, naming, cosmetic, purely theoretical, and unchanged-candidate concerns never keep a loop
   open. P2 is reserved for a concrete material maintainability, reliability, performance, or test
   risk, not a merely imaginable rare case; and
6. resource discipline never excuses a reachable security boundary failure, data loss, incorrect
   supported behavior, or violation of an explicit acceptance criterion.

Require focused owning checks during repair and one complete aggregate after final bytes freeze.
A mutation invalidates only the evidence whose boundary it can affect; do not restart unrelated
verification mechanically. Environment-only Windows/authenticated/manual gates remain honest final
gates and do not trigger implementation loops or fake evidence.

**Step 2: Put the rule where agents repeatedly see it.**

Add a short `Resource Discipline` section near the top of `FORGE.template.md` and
`rules/principles.md`. Repeat a compact pre-iteration checkpoint inside both plan-review and
code-review loops in `new-feature` and `fix-bug`, and in the host-neutral `review` workflow. The
independent reviewer must state whether it is running a broad or closure review; closure scope is
limited to named findings plus direct regressions. `review-pr-comments` and `quick-fix` inherit the
same stop rule without adding a new heavy review phase.

Keep the repetition short and identical in meaning. Do not create another large policy document,
new service, or model-dependent enforcement hook. Contract tests prove the installed Claude and
Codex instruction chains expose the rule at root and at every review invocation.

**Step 3: Remove or qualify conflicting absolutes.**

Audit every live Forge-owned rule, workflow, agent, and reviewer template. Replace unconditional
language such as `continue until every possible issue`, `missing edge case` without reachability,
or `work doggedly until no progress is possible` with resource-bounded language. Preserve strict
P0/P1 handling for reachable correctness, security, data integrity, and accepted requirements.
Keep `No Bugs Left Behind` scoped to known reproducible defects in the active supported surface;
an unsupported hypothesis is not a known defect.

The severity rubric must say that speculative or vanishingly unlikely cases without material
impact are P3/out of scope, while rare but catastrophic security/data-loss triggers remain P0/P1.
Existing convergence and evidence hooks continue to enforce clean candidate receipts; this task
changes classification and loop scope rather than weakening ship gates.

**Step 4: Run the focused resource and workflow contracts.**

Run `test-resource-discipline.sh`, `test-contracts.sh`, and `test-workflow-parity.sh`. Fixtures cover
plan findings, code findings, P3-only closure, speculative edge cases, a real rare data-loss case,
an unchanged candidate, a direct regression, an external final gate, and a reviewer that attempts
to start a second broad scan. Require the practical stop decision while preserving genuine P0/P1
blocks. Do not add a full aggregate here; Task 11 owns the final release aggregate.

**Step 5: Commit.**

```bash
git add FORGE.template.md rules commands agents/independent-reviewer.md \
  templates/review-result.template.txt tests/template
git commit -m "feat: bound review loops by engineering value"
```

## Task 10: Document the Dual-Engine Contract and Upgrade Path

**Files:**

- Modify: `README.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/guides/setup-scenarios.md`
- Modify: `docs/guides/upgrading.md`
- Modify: `docs/guides/parallel-sessions.md`
- Modify: `docs/explanation/workflow.md`
- Modify: `docs/explanation/autonomous-goal.md`
- Modify: `docs/explanation/codex-investigate.md`
- Modify: `docs/explanation/engineering-council.md`
- Modify: `docs/explanation/memory-architecture.md`
- Modify: `docs/reference/commands.md`
- Modify: `docs/reference/file-structure.md`
- Modify: `docs/reference/hooks.md`
- Modify: `docs/reference/permissions.md`
- Modify: `docs/reference/cheatsheet.md`
- Modify: `docs/troubleshooting.md`
- Create: `docs/adr/0010-dual-engine-canonical-harness.md`
- Modify: `docs/adr/README.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `tests/template/test-contracts.sh`

**Step 1: Write documentation contracts first.**

Require install/upgrade examples, both invocation surfaces, reviewer selection/fallback, council
topology/fallback, investigation authorization, goal resume, canonical paths, hook trust, engine
availability troubleshooting, Codex primary-checkout hook routing for linked worktrees, and the
simultaneous-edit warning. Reject stale claims that Forge
is Claude-only, Codex is always reviewer, or `.claude` owns shared state.

Require a compatibility table with tested Claude/Codex versions, required capabilities, setup
diagnostics, and the behavior when a binary is present but too old or unsupported for one role.
Require the workflow and cheatsheet documentation to explain the resource-discipline stop rule:
one broad review followed by bounded repair/closure, P3/speculative findings do not keep a loop
open, and real reachable P0/P1 security/correctness/data risks still block.

**Step 2: Write task-oriented docs and one architecture ADR.**

Lead with the developer outcome: run `./setup.sh -F` or `./setup.ps1 -FullRefresh` (`-R`), open either
host, and continue. Explain that there is no permanent main; current host is main for that action.
Show visible fallback messages and receipt locations. Explain that Grok is a future adapter and
not a v1 compatibility claim.

Document safe upgrade behavior, report categories, protected content, Codex hook trust ceremony,
Claude/Codex native-goal differences, investigation capability boundaries, and recovery from a
blocked full refresh.

Use one ADR with subsections for canonical harness/adapters, fresh-run review independence, and
manifest-driven full refresh; those are facets of one decision and do not justify three separate
coordination artifacts.

**Step 3: Version as a breaking harness release.**

Add a top changelog entry for `6.0` describing the authoritative migration and compatibility
boundary. Do not overwrite or renumber historical entries.

**Step 4: Run documentation and full contract tests.**

Run `bash tests/template/test-contracts.sh` and search for stale `.claude/local/state.md`,
hardcoded Codex reviewer requirements, and old force-upgrade instructions outside historical
documentation explicitly allowlisted by tests.

**Step 5: Commit.**

```bash
git add README.md docs tests/template/test-contracts.sh
git commit -m "docs: publish the dual-engine Forge contract"
```

## Task 11: End-to-End Installation, Native Qualification, and Windows CI

**Files:**

- Create: `tests/template/test-dual-engine-e2e.sh`
- Create: `tests/template/test-dual-engine-e2e.ps1`
- Create: `tests/template/test-runtime-qualification-schema.sh`
- Create: `tests/template/test-runtime-qualification-schema.ps1`
- Create: `scripts/qualify-runtime-final.sh`
- Create: `scripts/qualify-runtime-final.ps1`
- Modify: `.github/workflows/windows-parity.yml`
- Create: `docs/qualification/agent-mode-selection.md`
- Create: `tests/template/fixtures/legacy-v5-install/` only if a generated fixture cannot remain minimal
- Modify: `tests/template/run-all.sh`
- Modify: `docs/prds/agent-mode-selection.md`
- Modify: `.forge/local/state.md` during execution after migration; do not commit it

**Step 1: Encode the acceptance scenarios before declaring implementation complete.**

Use temporary Git repositories and fake engine CLIs for deterministic required E2E. Each case
must assert installed filesystem, state transitions, receipts, output, and exit status. Mirror
the acceptance matrix in PowerShell. Fake CLIs prove dispatch logic but cannot prove native
discovery, trust, sandboxing, hook execution, or `/goal`; required authenticated qualification
below covers those boundaries. The deterministic `test-runtime-qualification-schema.*` suites
validate captured/redacted attestation structure and reject fake evidence, but never authenticate or
open a TUI; only separately invoked `scripts/qualify-runtime-final.*` may do live/manual work.

### E2E Use Cases

1. **Authoritative legacy refresh:** Stamped and exact-fingerprinted pre-stamp v5 projects with
   custom files, secrets, MCP configuration, edited documented user regions in root instructions,
   active state, and seed snapshot
   run full refresh. They receive one
   canonical `.forge` harness, both adapter surfaces, migrated state, no known obsolete managed
   duplicates, invalidated legacy review/goal/auth evidence, unchanged protected fingerprints,
   byte-identical migrated user regions, and a complete action report. A changed managed root
   region or actual settings behavior collision blocks instead of competing/deleting; exact
   historical entries without provenance remain `PRESERVED_COMPAT` and suppress semantic
   duplicates while proven legacy hook files become thin delegates. A preserved enabled plugin
   with an overlapping auto-trigger/hook remains `PRESERVED_COMPAT_BLOCKED` until exact
   qualification or developer resolution. Inject
   failures after the first and penultimate commit-phase rename; every prior replacement rolls
   back, the legacy harness remains usable, no v6 stamp appears, and an incomplete/uncertain
   journal is surfaced for explicit recovery.
2. **Global dual-host setup:** Against a temporary home, global setup creates or refreshes the
   Forge-owned Claude and Codex blocks/config while preserving arbitrary preexisting instruction
   text byte-for-byte outside markers and unknown JSON settings semantically unchanged. Project
   full refresh never mutates this home; it only reports a stale-global follow-up, while the
   separate global full-refresh invocation upgrades it transactionally. Invalid mixed scopes fail
   before mutation. Ordinary/force/upgrade project and global setup against exact or ambiguous v5
   all stop before the first v6 write and print the scoped full-refresh/manual command, proving no
   mixed discoverable harness can be created.
3. **Clean install with one engine:** Claude-only and Codex-only machines both receive both
   adapters. A workflow uses the installed engine as main and falls back to a fresh same-engine
   reviewer without stopping; the receipt exposes the unavailable preferred engine and reason.
4. **Four review modes:** Each main/reviewer pairing completes plan and code review against the
   correct artifact; every code iteration has distinct spec and quality review invocation ids on
   the same candidate. Same-engine modes prove fresh ids, structured semantic results,
   zero reviewer-side Forge state mutation, and no inherited primary context. From each main host,
   the read-only General role also completes a second-opinion/analysis prompt and follows the same
   visible engine fallback contract.
5. **Cross-host resume:** Claude creates and records an approved plan. Codex opens the same
   worktree, reads the next incomplete checkpoint, implements without repeating planning, and
   preserves still-fresh review evidence. Run the reverse direction too.
6. **Artifact invalidation:** After a clean plan/code receipt, mutate the artifact. Both hosts
   see the gate invalid and must review again before commit/push/PR.
7. **Council healthy topology:** From each host, three advisors use main, two use other, and the
   other engine chairs. Six fresh seat session ids are distinct; each advisor has distinct advice
   and peer-critique turn ids, and the chairman has its own turn. The final receipt includes the
   anonymized bundle and minority reports.
8. **Council degraded topology:** Make the other engine unavailable and separately fail one
   other-engine invocation in either round or the chair. Known preflight absence starts exactly one
   all-main council without a discarded mixed attempt; a failure after mixed dispatch begins visibly
   reruns all advice, peer-review, and chairman calls on fresh main-engine processes and does not
   certify the discarded partial mixed council. A custom main-engine chairman failure blocks, as
   does any failure during the all-main attempt.
9. **Council seat override:** Override at least one advisor and the chairman engine while retaining
   all six roles, anonymous peer review, and minority reports. Reject malformed or incomplete
   override maps and apply the complete fallback rule if a configured non-main engine fails.
10. **Investigation authorization:** An investigative reviewer can research the web, use a
   declared read-only query channel, execute inside the worktree, and write a reproduction without
   general external-write credentials. A hostile ambient write MCP/plugin/hook is absent from the
   child while the selected read-only query remains usable. Its finding stays a hypothesis until a
   distinct reproduction invocation reruns the primary check and a control. An external mutation
   remains unavailable to every model; Forge renders an allowlisted deterministic action for the
   developer to execute manually, treats an agent-written approval receipt as audit-only, and
   reports MCP-only mutation `BLOCKED` in v1.
11. **Goal parity and resume:** Start the same Forge objective through Claude native `/goal` and
   Codex native `/goal` composition in separate fixtures. Both use the same nonce/evidence contract,
   pause at explicit PR authorization, and stop at the evidence-defined boundary. Switch hosts
   mid-objective and reject stale evidence after mutation. For each host separately, force token
   budget exhaustion, a stuck-warning threshold, user interruption, and process interruption;
   require durable objective persistence, same-host resume, and continuation from the exact next
   unchecked checkpoint without repeating completed work. Prove the human-owned authorization
   ceiling and nonce cannot be changed/reset through workflow state, concurrent Stop events charge
   once, and a new budget requires a new human action. Codex evidence must include the manual TUI
   developer-command/status transcript; `codex exec` or fake CLI output is rejected.
12. **Failed migration honesty:** Force a required adapter copy failure. Full refresh exits
    nonzero, preserves protected content and old state, does not write the v6 readiness stamp,
    and reports `BLOCKED` with recovery guidance.
13. **Cross-worktree evidence isolation:** Copy a clean receipt to another worktree at the same
    HEAD. Worktree identity rejects it while committed durable memory remains normally visible.
14. **Materialized versus ready:** An untrusted Codex fixture installs successfully as
    `MATERIALIZED` but not `RUNTIME_READY`; discovery/trust verification promotes readiness only
    after instructions, every rule, and a hook sentinel are observed.
15. **Native-goal collision honesty:** Preserve custom Claude `goal.md` and Codex `goal` skill
    content byte-for-byte, install no shadow adapter, mark only the affected host not
    `RUNTIME_READY`, and print exact rename/remediation guidance.
16. **Mutation-free finalization:** A feature creates/updates implementation, solution/changelog,
    graduated E2E use cases, and generated specs; simplification finishes, exact approved ignored
    artifacts are force-staged from an intended list, and then `git add -A` captures ordinary paths;
    staged-clean freeze succeeds, and final review/verify-app/E2E write only local evidence. The
    promoted commit tree exactly matches the frozen index. Both final reviewers cover the persisted
    workflow base through earlier task commits and the final staged delta. Injecting any tracked,
    unstaged, index, or in-scope untracked mutation after a gate invalidates all final receipts and
    forces a rerun. An auto-fixing hook replays one validated artifact, refreezes/reruns all gates,
    and then succeeds; a repeated mutation hits the bound without advancing the branch.
17. **Linked-worktree Codex hooks:** Primary setup installs one protected Codex hook registry and
    stable router. Two linked worktrees with different candidates/states both receive hook events
    in their own `.forge` trees; stale/missing primary registration keeps readiness blocked, a
    wrong-common-dir event is rejected, linked setup prints the exact primary command without
    mutating its sibling, and an injected primary-registration failure rolls back cleanly.

**Step 2: Run focused E2E and observe any remaining RED.**

Run `bash tests/template/test-dual-engine-e2e.sh`; repair one failing acceptance behavior at a
time with focused regression tests.

**Step 3: Require authenticated native-host qualification.**

Against disposable repositories on the documented supported Claude and Codex versions, verify
root/nested instruction and rule discovery, custom workflow/skill invocation, hook/config trust,
fresh same-engine isolation, read-only review, read-only external investigation, worktree writes,
structured output, and every Must row in the goal behavior matrix, including budget exhaustion,
stuck warning, user/process interruption, same-host resume, and exact checkpoint continuation.
Record versions, commands, non-secret result hashes, and readiness in
`docs/qualification/agent-mode-selection.md`. Run the dispatch-isolation qualification before
Task 5 and repeat it here against the final candidate. If either
installed host cannot be authenticated/exercised, native-goal and runtime-readiness acceptance
remain `BLOCKED`; fake output cannot substitute. Claude may use its qualified print/resume path.
Codex native `/goal` requires the manual authenticated TUI protocol (developer-command activation,
status, interruption, resume, transcript hash) unless the plan's named driver was separately
qualified; ordinary `codex exec` is never accepted as native-goal proof.

Run this through `scripts/qualify-runtime-final.sh` or `.ps1` as a release-attestation action, not
through `run-all`. The Windows PR job exercises the deterministic schema/fake-engine suite under
PowerShell 5.1; a release still requires a separately recorded live Windows/native-host
qualification when the acceptance matrix says so.

**Step 4: Extend mandatory Windows behavioral CI and run the complete local matrix.**

The Windows job runs on every PR and exercises Windows PowerShell 5.1 setup, `-FullRefresh`/`-R`,
symlink/junction defenses, state translation, dispatcher/fallback/timeout/process cleanup,
council both rounds, hook decisions, receipts, and goal composition fixtures. PowerShell 7 may be
a supplemental matrix entry; 5.1 is mandatory. A failing or absent Windows job blocks acceptance
and release. Static parity remains supplemental.

```bash
bash tests/template/run-all.sh
git diff --check
```

Local macOS/Linux verification may record Windows CI as pending until the branch is pushed, but
must never label platform parity complete. The PR cannot be approved for merge/release until the
required Windows job is green.

**Step 5: Finalize and stage every tracked acceptance artifact.**

Check machine-verifiable acceptance criteria only when the corresponding tests and review
evidence exist. Only Pablo or another explicitly named human Technical Lead may check the PRD's
Technical Lead approval field; implementation/tests never grant it. Finish qualification records,
ADRs/docs, test fixtures, changelog/solution text, and all other tracked outputs before freeze.
Because this template repository intentionally ignores workflow-generated `docs/prds/`,
`docs/plans/`, `docs/research/`, `docs/solutions/`, and `tests/e2e/`, build an explicit intended-
artifact list and `git add -f` only the approved exact files from those roots; never force-add a
directory or unknown ignored file. Then `git add -A`, require no remaining unstaged or in-scope
untracked paths, and freeze the staged-clean candidate.

**Step 6: Run mutation-free final gates and promote the exact commit.**

Run both fresh final review lenses (`code-spec` and `code-quality`), verify-app, and the complete
E2E regression against that one candidate. They may write only ignored local receipts/reports. Any
finding or tracked/index/in-scope-untracked mutation returns to Step 5 and invalidates every final
receipt. Commit only with the Task 8 temporary-ref compare-and-swap promotion helper and verify the
branch commit tree equals the frozen index; do not run a post-review `git add` or ordinary
branch-advancing `git commit`. The required Windows CI may remain pending until push/PR, but it must
be green before merge/release approval.

## Developer Briefing

- [planned] `./setup.sh -F` and `./setup.ps1 -FullRefresh` (`-R`) will be the authoritative v5-to-v6
  migration path; lowercase `-f` will retain its existing narrower overwrite meaning.
- [planned] Legacy deletion will require an exact generated marker or released-content
  fingerprint; customized or unverifiable legacy policy will be preserved and block readiness.
- [planned] A downstream project will contain one managed policy tree under `.forge/` and thin
  regular-file adapters for both Claude Code and Codex.
- [planned] Global setup will use the same one-canonical-source pattern under the user's Forge
  directory and preserve host-global custom instructions/config outside bounded sections.
- [planned] The host currently executing a workflow will be recorded as the last active host,
  never as a permanent project main.
- [planned] Automatic review will prefer the other engine and will visibly fall back to a fresh
  same-engine process when the other engine is missing or cannot launch.
- [planned] Explicit same-engine review will be a normal supported mode; independence will be
  evidenced by invocation/artifact/worktree receipts, and cleanliness by a structured semantic
  result rather than process exit status.
- [planned] Investigation will allow isolated worktree writes, project execution, native web
  research, and declared read-only query channels, followed by a separate primary/control
  reproduction. In v1, external mutation remains human-executed from an exact rendered action;
  no model receives the mutating MCP tool or credential.
- [planned] Healthy councils will retain the existing five-advisor-plus-chair preset with a
  3-main/2-other advisor split and other-engine chairman; known other-engine absence starts
  all-main directly, while an other-engine failure after mixed dispatch begins restarts all six
  seats fresh on the main engine.
- [planned] Advanced council calls will be able to override individual seat engines without
  removing personas, peer review, chairman synthesis, minority reports, or fallback honesty.
- [planned] Native Claude and Codex goals will share Forge state, nonce, and evidence but will not
  pretend to transfer the native chat/session itself.
- [planned] Developers may change hosts between phases in one worktree without a lock or handoff;
  documentation will warn them not to run simultaneous edits.
- [planned] Volatile per-worktree memory and durable project-owned memory will have separate
  `.forge/local/memory/` and `.forge/memory/` ownership rules, both readable from either host.
- [planned] Setup will report `MATERIALIZED` and per-host `RUNTIME_READY` separately, with live
  discovery/trust qualification required for the latter.
- [planned] Windows PowerShell 5.1 behavioral CI and authenticated Claude/Codex native-goal
  qualification will be mandatory acceptance evidence, not optional smoke tests.
- [inferred] Because Grok Build exposes only partial Claude compatibility and no established Forge
  hook/goal contract, this layout leaves room for a future `.grok` adapter but does not advertise
  Grok support in v1.

## Verification and PR Gate

After all tasks:

1. Run self-review against this plan, the approved PRD, and the final diff.
2. Run a fresh independent plan/code review and resolve every P0/P1/P2 finding.
3. Run `bash tests/template/run-all.sh`, `git diff --check`, fixture inventory/parity checks,
   required authenticated Claude/Codex qualification, and the mandatory Windows PowerShell 5.1
   CI job; any unavailable required boundary remains `BLOCKED`, not partially verified.
4. Rebuild final evidence against the exact HEAD and diff fingerprint after the last mutation.
5. Request explicit user authorization bound to the exact HEAD before `git push`/PR creation.
6. Create the PR only after authorization; stop after the open PR and do not merge.
