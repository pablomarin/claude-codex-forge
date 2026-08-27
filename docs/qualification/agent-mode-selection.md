# Dual-Engine Runtime Qualification

**Candidate base:** `296b45978913242396aed4bfc1062289a4b053b9`

**Observed:** 2026-08-27 on macOS

**Release status:** `BLOCKED`

The deterministic harness is qualified separately from native-host readiness. Fake engines prove
dispatch and orchestration behavior only; they do not prove authentication, native discovery,
sandbox enforcement, hooks, network access, or native `/goal` behavior.

## Deterministic evidence

| Boundary | Status | Evidence |
| --- | --- | --- |
| Installed dual-engine seam | `PASS` | `bash tests/template/test-dual-engine-e2e.sh` — 14 passed, 0 failed |
| Runtime-attestation schema | `PASS` | `bash tests/template/test-runtime-qualification-schema.sh` — 12 passed, 0 failed |
| Seventeen acceptance use cases | `PASS` mapping | `bash tests/template/test-dual-engine-e2e.sh --list-coverage`; each row names its existing owning suite |
| Windows PowerShell 5.1 behavior | `PENDING` | No local PowerShell runtime; `.github/workflows/windows-parity.yml` owns the required PR result |

The final aggregate is candidate-bound execution evidence and is recorded in the Task 11 execution
report after the bytes freeze; this tracked document does not self-certify a later test run.

## Native-host observations

| Host boundary | Status | Observed evidence |
| --- | --- | --- |
| Codex CLI identity | `PASS` | `codex-cli 0.144.1`; physical binary SHA-256 `29915529b97697def1a957b0505e770aa6a45744435d62fc263e98d7619e167a` |
| Codex authentication | `PASS` | `codex login status` returned `Logged in using ChatGPT` |
| Codex guarded dispatch | `PENDING` | Authenticated model qualification was not invoked before the final candidate freeze |
| Codex native `/goal` | `BLOCKED` | No sealed physical operator TUI capture; `codex exec` and fake output are not substitutes |
| Claude Code identity | `PASS` | `2.1.237 (Claude Code)`; physical binary SHA-256 `338901351d4ff17495738c67fc3e12a32c1b506738ac5e012eb782d3d8b5be43` |
| Claude authentication | `BLOCKED` | `claude auth status` returned `loggedIn: false`, `authMethod: none` |
| Claude guarded dispatch and native `/goal` | `BLOCKED` | An unauthenticated host cannot produce native runtime evidence |
| Live Windows/native qualification | `PENDING` | Requires Windows PowerShell 5.1 plus authenticated host execution on the release candidate |

No live model was called to produce this record. The missing Claude authentication, missing Codex
TUI capture, and pending Windows job keep runtime readiness and release qualification blocked.

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
