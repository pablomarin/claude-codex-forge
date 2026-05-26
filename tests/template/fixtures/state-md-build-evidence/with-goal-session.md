# Project State (per-developer, gitignored)

## /goal session

| Field            | Value                                |
| ---------------- | ------------------------------------ |
| nonce            | 00000000-0000-0000-0000-000000000001 |
| workflow_command | /new-feature foo                     |
| issued_at        | 2026-05-14T18:00:00Z                 |

## Workflow

| Field     | Value              |
| --------- | ------------------ |
| Command   | /new-feature foo   |
| Phase     | 1 — Research       |
| Next step | Run research-first |

### Checklist

- [ ] Research complete
- [ ] Plan written
- [ ] Plan approved
- [ ] Tests written (TDD)
- [ ] Code review iteration 1 — codex clean — head=`__TBD_SHA__`
- [ ] Code review iteration 1 — pr-toolkit clean — head=`__TBD_SHA__`
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized
