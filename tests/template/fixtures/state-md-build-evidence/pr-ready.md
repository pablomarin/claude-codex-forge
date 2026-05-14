# Project State (per-developer, gitignored)

## /goal session

| Field            | Value                                |
| ---------------- | ------------------------------------ |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo                     |
| issued_at        | 2026-05-14T18:00:00Z                 |

## Workflow

| Field     | Value              |
| --------- | ------------------ |
| Command   | /new-feature foo   |
| Phase     | 1 — Research       |
| Next step | Run research-first |

### Checklist

- [x] Research complete
- [x] Plan written
- [x] Plan approved
- [x] Tests written (TDD)
- [x] Code review iteration 1 — codex clean — head=`__HEAD_SHA__`
- [x] Code review iteration 1 — pr-toolkit clean — head=`__HEAD_SHA__`
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [x] PR authorized
