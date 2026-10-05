# PR authorization parsing repair

Base: `2c5862b5ea6785aa5ce7c04d621830266ca20428` (immutable Forge source base).

The developer approved fixing the reproduced publication blockers with KISS/YAGNI. This is a bounded repair to existing parsers, not a new authorization mechanism.

## Reproduction and cause

- A downstream primary checkout's PR guard reads its own HEAD and historical authorization because Codex passes the session cwd to hooks even when exec_command runs in another worktree.
- Codex projects Bash hook input to `{"command": ...}` and omits the honored per-call workdir. Official hook documentation defines cwd as session cwd; openai/codex issues #33986 and #37251 describe the matching gap. Forge cannot safely recover an omitted directory. Preserve the router's Git-common-directory boundary and do not parse shell commands or invent workdir fields.
- In the task worktree, the PR guard treats `<uuid-v4-lowercase>` from the example Goal table as active and rejects authorization nonce `none`.
- The guard scans the whole file for PR authorization lines, counting a checklist summary as a second authorization. Build-evidence likewise reads the first matching line anywhere, so the summary can hide the canonical approval in evidence.

## Minimal changes

1. In `hooks/check-workflow-gates.{sh,ps1}`, exclude the exact example nonce from Goal activation, matching workflow-state/check-state-updated. All other nonempty values retain current fail-closed nonce and HEAD checks.
2. Scope PR authorization lines to the `## PR authorization` section. Preserve the existing last-line defense and duplicate warning within that section. Narrative/checklist rows must neither authorize nor invalidate publication.
3. Apply the same Goal-template normalization and canonical-section/last-line semantics to `hooks/build-evidence.{sh,ps1}`. Inactive template Goals report no session nonce and never claim Goal-bound authorization. In the PowerShell evidence parser, read state as explicit UTF-8 and spell the em-dash regex as ASCII `\u2014`; Windows PowerShell 5.1 otherwise decodes BOM-less source/state using the ANSI code page. This two-line correction supports both UTF-8 state encodings without changing source-file encoding or weakening approval matching.
4. Correct the Goal-active explanation in `state.template.md`, and the shipping-workspace guidance in `commands/fix-bug.md`, `commands/new-feature.md`, and `docs/reference/hooks.md`. Local workdir selection does not establish a native hook shipping context. Explain the upstream boundary without promising that a Forge refresh fixes Codex payload loss.
5. Add one shared real-runtime fixture in `tests/template/pr-authorization-fixture.py`, with focused Bash/PowerShell suite entry points, and include it in `run-fast.sh` and `run-all.sh`; Windows discovery already finds the PowerShell entry point. Exercise UTF-8 state with and without BOM as well as LF/CRLF. Update existing contracts that pin the old nonce condition or workspace guidance. Use PowerShell when available; native Windows PowerShell 5.1 verification remains CI-owned on this macOS host. Bump the patch release and README badge once, with a concise changelog entry.

## Acceptance and controls

- An unactivated template Goal skips only Goal-specific PR authorization, with ordinary workflow/receipt gates preserved.
- A real Goal with missing, stale-HEAD, or mismatched-nonce canonical approval is still blocked, including when matching narrative text exists elsewhere.
- A valid canonical approval is unaffected by checklist/narrative summaries, LF/CRLF, or duplicated lines outside the canonical section. PowerShell evidence accepts UTF-8 state both with and without BOM, including U+2014 separators, without relying on ANSI source decoding.
- Real duplicate canonical approvals retain last-line behavior and a diagnostic.
- Evidence agrees with the PR guard about template inactivity and the canonical approval selected.
- Runtime tests execute the real hooks against isolated local Git fixtures; no gh publication or downstream writes.
- Owning hook tests plus `tests/template/run-fast.sh` pass, and `git diff --check` is clean. No exhaustive local suite is authorized.

## User journey and limits

Exercise local hook publication decisions and emitted evidence with passing and failing controls. No application/browser journey applies. Do not change router registrations, trust, host permissions, local approval files, or any downstream repository. Codex session/exec_command context mismatch remains an upstream limitation; ship from a host context bound to the task worktree when the host omits execution cwd.

The review's nonblocking P3 about the existing progress fingerprint reading a narrative approval is deferred: it can cause a false stuck warning, but cannot authorize publication. Repairing that separate warning is outside this bounded change.
