# state.md fixture: Plan review loop PASS via the "codex unavailable,

# user-confirmed" escape.

# Expected: REJECTED (exit 2) when `codex` IS available at gate time;

# ACCEPTED (exit 0) when codex is genuinely not installed.

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (2 iterations) — PASS
- [x] Plan review iteration 2 — codex unavailable, user-confirmed — ts=`2026-05-26T17:00:00Z`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
