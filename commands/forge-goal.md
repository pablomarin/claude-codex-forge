# Forge Goal Composition Contract

This canonical workflow is installed only as `.forge/workflows/goal.md`. Forge must never install
`.claude/commands/goal.md` or `.agents/skills/goal/SKILL.md`; each host retains its native `/goal`.

## Activation

1. Read `.forge/local/state.md` and the active workflow. Refuse activation without a human-created,
   immutable goal authorization record from the trusted global Forge writer.
2. Create one objective nonce and objective hash. Persist the workflow command, immutable base
   ref/SHA, durable turn ceiling, consumed turn count, checklist, exact next step, candidate, evidence
   paths, last active host, and status. Native counters are telemetry only.
3. Start the active host's native `/goal` over this contract only when authenticated qualification
   proves every Must behavior. Otherwise report `BLOCKED`; never claim reduced parity.

## Loop

On every turn:

1. Validate the authorization binding, objective nonce, durable count/ceiling, state, and evidence.
2. Resume the exact next unchecked durable step. A same-host resume may restore native context; a
   cross-host resume starts a fresh native session and never claims session transfer.
3. Increment the persistent Forge count through hook-owned records. Native session, token, or turn
   counters may reset; the Forge ceiling and consumed count never reset after interruption or host
   switching.
4. Record measurable checklist progress and the next step. `FORGE_GOAL_STUCK_WARNING` is advisory:
   inspect progress, use council for a genuine decision, or surface a blocker; it does not reset the
   budget or authorize another broad loop.
5. If `FORGE_GOAL_BUDGET_EXHAUSTED` appears, preserve the exact checkpoint and stop native autonomy.
   Resume requires new human authority and continues with the existing count; it never starts at zero.
6. Invalidate only receipts whose candidate boundary changed and rerun the affected final gates.

Ordinary reviewer/engine launch failure uses the workflow's visible automatic fallback to a fresh
same-engine reviewer. Findings do not trigger fallback. A council may resolve bounded engineering
judgment, but never user input, destructive action, secrets, PR creation, merge, publish, deploy, or
another external mutation.

## Pause and Terminal Status

End native autonomy and persist the exact next step when:

- user input or explicit authorization is required;
- a destructive/security-sensitive action or new external mutation is proposed;
- a workflow invariant or authenticated native-goal Must behavior is blocked;
- the persistent budget is exhausted; or
- the developer interrupts or cancels the run.

Record only `complete`, `blocked`, or `cancelled`. `complete` requires the workflow's current
candidate-bound evidence and all authorized mutations to have succeeded; native goal exit is never
proof. PR creation is always a fresh human pause with authorization bound to the active nonce and
candidate.
