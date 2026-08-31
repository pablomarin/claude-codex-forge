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
| Codex native `/goal` | `BLOCKED` | No sealed physical operator TUI capture; `codex exec` and fake output are not substitutes |
| Claude Code identity | `PASS` | `2.1.237 (Claude Code)`; physical binary SHA-256 `338901351d4ff17495738c67fc3e12a32c1b506738ac5e012eb782d3d8b5be43` |
| Claude authentication | `PASS` | Physical operator login completed; `claude auth status` returned `loggedIn: true`, `authMethod: claude.ai` |
| Claude guarded dispatch | `PASS` | Authenticated opinion, full-agent investigation, exact-id resume, and both mixed-council topologies passed in a disposable project |
| Claude native `/goal` | `BLOCKED` | Not invoked: the live oracle requires a separate operator-issued goal authorization receipt |
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

## Final qualification command

`scripts/qualify-runtime-final.sh` and `.ps1` are thin release wrappers over
`qualify-dispatch-isolation.*` and `qualify-goal-feasibility.*`. Their deterministic fixture mode
always returns `BLOCKED`. `--live` is the only mode that may invoke authenticated hosts, and a
`PASS` additionally requires the sealed Codex goal capture and the matching Windows PowerShell 5.1
attestation. Validation rejects fixture-as-PASS, malformed child status/schema, changed child or
engine hashes, a stale candidate, and a missing/stale Codex capture.

Example after the remaining operator evidence exists:

```bash
FORGE_CODEX_AUTH_FILE=/operator/path/auth.json \
  scripts/qualify-runtime-final.sh --live --project-root /path/to/project \
  --output /operator/path/runtime-final.receipt \
  --claude-goal-authorization /operator/path/claude-goal.authorization \
  --codex-goal-capture /operator/path/codex-goal/capture.receipt \
  --windows-attestation /operator/path/windows-powershell-51.receipt
```

Keep every operator path and credential outside the repository. The final receipt records hashes
and statuses, not secrets or transcript contents.
