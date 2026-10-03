# Dual-Engine Runtime Qualification

**Candidate base:** `2ace7fac279a57de2b80aa1cfa96541bfd80df64`

**Observed:** 2026-08-28 on macOS

**Release status:** `BLOCKED`

The deterministic harness is qualified separately from native-host readiness. Fake engines prove
dispatch and orchestration behavior only; they do not prove authentication, native discovery,
sandbox enforcement, hooks, network access, or native `/goal` behavior.

## Deterministic evidence

| Boundary | Status | Evidence |
| --- | --- | --- |
| Installed dual-engine seam | `PASS` | `bash tests/template/test-dual-engine-e2e.sh` — 14 passed, 0 failed |
| Runtime-attestation schema | `PASS` | `bash tests/template/test-runtime-qualification-schema.sh` — 22 passed, 0 failed |
| Seventeen acceptance use cases | `PASS` mapping | `bash tests/template/test-dual-engine-e2e.sh --list-coverage`; each row names its existing owning suite |
| Windows PowerShell 5.1 behavior | `PENDING` | No local PowerShell runtime; `.github/workflows/windows-parity.yml` owns the required PR result |

The final aggregate is candidate-bound execution evidence and is recorded in the Task 11 execution
report after the bytes freeze; this tracked document does not self-certify a later test run.

## Native-host observations

| Host boundary | Status | Observed evidence |
| --- | --- | --- |
| Codex CLI identity | `PASS` | `codex-cli 0.144.1`; physical binary SHA-256 `29915529b97697def1a957b0505e770aa6a45744435d62fc263e98d7619e167a` |
| Codex authentication | `PASS` | `codex login status` returned `Logged in using ChatGPT` |
| Codex guarded dispatch | `PASS` | Authenticated opinion, full-agent investigation, exact-id resume, and both mixed-council topologies passed in a disposable project |
| Codex Desktop Auto-review transport | `PENDING` | Deterministic tests prove the installed standing-human-approval policy, not whether the Desktop approval reviewer recognizes that actual human instruction |
| Codex native `/goal` | `BLOCKED` | Requires an authenticated native interactive Goal run; `codex exec` and agent-authored substitutes do not certify it |
| Claude Code identity | `PASS` | `2.1.237 (Claude Code)`; physical binary SHA-256 `338901351d4ff17495738c67fc3e12a32c1b506738ac5e012eb782d3d8b5be43` |
| Claude authentication | `PASS` | Physical operator login completed; `claude auth status` returned `loggedIn: true`, `authMethod: claude.ai` |
| Claude guarded dispatch | `PASS` | Authenticated opinion, full-agent investigation, exact-id resume, and both mixed-council topologies passed in a disposable project |
| Claude Desktop command shaping | `PENDING` | Deterministic tests prove installed instructions, not whether the current Auto-mode classifier accepts the resulting literal, single-purpose shell calls |
| Claude native `/goal` | `PENDING` | The project-local deterministic ledger is qualified; the current candidate still needs an authenticated native `/goal` run |
| Live Windows/native qualification | `PENDING` | Requires Windows PowerShell 5.1 plus authenticated host execution on the release candidate |

Authenticated Claude and Codex models were called only through disposable qualification projects.
The dual-engine runtime matrix below passed. Missing native-goal evidence and the pending Windows job
still keep final release qualification blocked.

## Authenticated E2E matrix

| Surface | Status | Observed evidence |
| --- | --- | --- |
| Opinion/review | `PASS` | Claude main → Codex reviewer; Codex main → Claude reviewer; Claude → Claude; Codex → Codex. Each receipt bound the requested and actual engines with `fallback=false`. |
| Full-agent investigation | `PASS` | All four main/investigator combinations ran in the real disposable worktree and read shared state, durable memory, and local memory. Each created the declared local artifact. Claude used native `auto` permission mode; Codex used native on-request approval, search, and `danger-full-access`. |
| Engineering council | `PASS` | Claude-main and Codex-main mixed topologies each produced five advice turns, five exact-session peer turns, one chairman turn, `turn_results=11`, and `topology_mode=mixed`. |

Ordinary opinion and council reasoning remain isolated from the real worktree. Full investigation is
the intentionally different mode: a fresh selected-engine process with normal user/project config,
skills, MCP, state, memory, network, and worktree access. Forge does not add a declared-channel or
disposable-candidate restriction there. `investigation-repro` remains the separate isolated path for
certifying a reproduction.

## Codex Desktop reviewer-launch qualification

This boundary remains `PENDING` until a physical operator records all five journeys against the
same release candidate and Codex Desktop version:

1. Explicitly invoke a review-capable Forge entry point in a project with the developer's standing
   human approval. Confirm Forge adds no consent question to ordinary review or an explicitly
   selected full-agent investigation.
2. Start the same workflow from ordinary prose under that standing approval. Confirm Forge adds
   no consent question to ordinary source review or to task-selected investigation requiring live
   project tools, services, network, or worktree writes; record any independent host security gate
   separately rather than treating this policy as permission to bypass it.
3. Resume the authorized project workflow in a fresh Desktop task or switch configured hosts.
   Confirm Forge does not re-ask for either review-mode launch. Confirm the ordinary bounded
   candidate remains isolated and full investigation uses the disclosed real-worktree capabilities.
4. Deny a host permission or force an ordinary-review timeout. Confirm Forge does not change its
   role/profile or grant live investigation capabilities; any automatic fresh fallback remains
   ordinary review. Record its requested sandbox/tools and unchanged real-worktree bytes.
5. Confirm standing launch approval does not authorize new arbitrary destinations, destructive
   actions, publication, or external mutations; their existing operation-specific boundaries remain.

Record the Desktop version, exact candidate SHA, task identifiers, and pass/fail outcome outside the
repository. Do not store candidate content, credentials, or private transcript text in the receipt.
Fake engines, isolated child CLI runs, generated adapter text, and agent-authored receipts cannot
satisfy this qualification.

## Claude Desktop command-shaping qualification

This boundary remains `PENDING` until a physical operator runs the same release candidate through
the representative downstream work and records these journeys:

1. **Package and parity:** create a fresh uniquely named package, validate it, and compare extracted
   content through separate literal calls. Confirm the non-destructive calls do not recreate the
   opaque multi-line permission prompts.
2. **Boundary and freeze:** run repository-boundary validation and candidate freeze as separate
   calls after packaging. Confirm neither call inherits unrelated deletion, redirection, heredoc,
   variable, or pipeline syntax.
3. **Recursive cleanup:** first prefer a fresh output or temporary directory. If an exact generated
   tree truly must be recursively deleted, confirm deletion is isolated from all verification work
   and receives its separate host approval; the qualification must not classify that real safety
   prompt as a regression.

Record the Claude Desktop and Claude Code versions, exact candidate SHA, tool-call descriptions, and
pass/fail outcome outside the repository without preserving private command payloads. Instruction
and materialization tests cannot prove a live Auto-mode classifier decision.

## Final qualification command

`scripts/qualify-runtime-final.sh` and `.ps1` are thin release wrappers over
`qualify-dispatch-isolation.*` and `qualify-goal-feasibility.*`. Goal qualification always proves
the repository-local ledger first and records its receipt under the supplied project evidence
directory. `--live` records the selected host binary and version, but a process exit code cannot
prove an interactive native Goal. Without evidence it remains `BLOCKED` with
`interactive-native-goal-evidence-required`; it never converts an ordinary zero-exit prompt into
`READY`. After running the documented native UI/CLI scenario, pass its exact candidate-bound
`forge.native-goal-operator-evidence.v1` record through `--claude-goal-evidence` or
`--codex-goal-evidence`. The record binds the host, physical project root, Git HEAD/tree, and
observed activation, progress, and stop behavior.
Aggregate `PASS` additionally requires both supported hosts and the matching Windows PowerShell 5.1 attestation. Validation rejects fixture-as-PASS,
malformed child status/schema, changed child or engine hashes, and a stale candidate.

Example after the remaining operator evidence exists:

```bash
scripts/qualify-runtime-final.sh --live --project-root /path/to/project \
  --output /operator/path/runtime-final.receipt \
  --claude-goal-evidence /operator/path/claude-native-goal.evidence \
  --codex-goal-evidence /operator/path/codex-native-goal.evidence \
  --windows-attestation /operator/path/windows-powershell-51.receipt
```

The authenticated clients keep their own credentials. Forge stores only project-local hashes and
statuses, never secrets or private transcript contents.
