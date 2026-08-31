# Principles

## Top-Level Principles

**Work purposefully.** Be autonomous while each iteration makes material progress toward the user's
goal. Stop review churn at the bounded closure rule and surface a real remaining blocker.

**Work smart.** When debugging, think deeply. Add logging to check assumptions.

**Check your work.** Run code to verify it works. Check logs after starting processes.

**Research first.** AI knowledge has a cutoff. Use the `research-first` agent (or Context7/WebFetch/WebSearch manually) to check current docs before design. See Phase 2 in `/new-feature` and Phase 2.5 in `/fix-bug`.

**Learn from competitors.** Before implementing features, research how established products solved it.

## Resource Discipline

Build the smallest correct solution. Treat developer time, session length, tokens, and money as
finite engineering resources. Do not pursue perfection, cosmetic polish, speculative hardening, or
edge cases without a concrete supported trigger, explicit acceptance criterion, material
likelihood, security impact, or data-integrity impact.

Default to one broad review, one repair pass, and one closure review limited to named findings and
direct regressions. One still-open reachable P0/P1 may receive one surgical repair and verification;
then surface the blocker to the developer. Resource discipline never excuses a reachable security
boundary failure, data loss, incorrect supported behavior, or violation of an explicit acceptance
criterion.

## Core Design Philosophy

- **Brutal simplicity** over clever solutions (KISS)
- **Composition** over inheritance
- **Immutability** by default
- **DRY** - if it appears twice, extract it
- **Reuse** - check if a utility exists before creating new code
