# /prd:create {feature-name}

Generate a structured PRD from the refined understanding captured in `/prd:discuss`.

## Prerequisites

- Discussion file exists at `docs/prds/{feature-name}-discussion.md`
- Discussion status is "Complete" (user said "ready")
- If no discussion file exists, prompt user to run `/prd:discuss` first

## Instructions

> **Research note:** The PRD captures WHAT the user needs — goals, constraints, acceptance criteria. HOW to build it (libraries, patterns, data models, auth mechanisms) belongs in the design phase, informed by the `research-first` agent in `/new-feature` Phase 2. Do NOT run web research here; the PRD is not a technology decision document.

### Step 1: Load Context

1. Read `docs/prds/{feature-name}-discussion.md`
2. Extract:
   - Refined user stories
   - Personas identified
   - Non-goals agreed
   - Key decisions made (scope decisions, not solution choices)
   - Business / compliance constraints (regulatory, legal, SLA)
   - Platform / operational constraints (browser/OS floors, accessibility targets, network conditions)
   - Dependencies (features/systems that must exist first)
   - Required integrations or capabilities (named external systems or named capabilities — e.g. "must sync with Salesforce", "must support SAML 2.0 SSO", "must export iCalendar")
   - Security outcomes (who can access what, what must never leak, what must be auditable, regulatory outcomes)
   - Success metrics

### Step 2: Generate PRD

Create `docs/prds/{feature-name}.md` using the template below.

> **Note on E2E:** The PRD defines WHAT to build. E2E use cases (HOW users will verify it) are designed in Phase 3.2b of `/new-feature` or `/fix-bug`, not in the PRD. The PRD should clearly identify user-facing behavior so the use case design phase has something concrete to work from.

### Step 3: Review Prompt

After creating PRD:

1. Summarize what was created (section count, story count)
2. Ask user to review
3. Offer to make adjustments
4. When approved, prompt to continue with `/new-feature {feature-name}` at technical design

## PRD Template

````markdown
# PRD: {Feature Name}

**Version:** 1.0
**Status:** Draft
**Author:** Current Forge host + {User}
**Created:** {date}
**Last Updated:** {date}

---

## 1. Overview

{2-3 sentence summary of what we're building and why. Should answer: What problem does this solve? Who benefits? What's the high-level approach?}

## 2. Goals & Success Metrics

### Goals

- {Primary goal}
- {Secondary goal}

### Success Metrics

| Metric   | Target   | How Measured         |
| -------- | -------- | -------------------- |
| {metric} | {target} | {measurement method} |

### Non-Goals (Explicitly Out of Scope)

- ❌ {What we're NOT building}
- ❌ {What's deferred to future phases}

## 3. User Personas

### {Persona 1 Name}

- **Role:** {role description}
- **Permissions:** {what they can do}
- **Goals:** {what they want to achieve}

### {Persona 2 Name}

- **Role:** {role description}
- **Permissions:** {what they can do}
- **Goals:** {what they want to achieve}

## 4. User Stories

### US-001: {Story Title}

**As a** {persona}
**I want** {capability}
**So that** {benefit}

**Scenario:**

```gherkin
Given {precondition}
When {action}
Then {expected result}
And {additional result}
```

**Acceptance Criteria:**

- [ ] {criterion 1 - specific and testable}
- [ ] {criterion 2 - specific and testable}
- [ ] {criterion 3 - specific and testable}

**Edge Cases:**
| Condition | Expected Behavior |
|-----------|-------------------|
| {edge case 1} | {behavior} |
| {edge case 2} | {behavior} |

**Priority:** {Must Have / Should Have / Nice to Have}

---

### US-002: {Story Title}

{Repeat structure for each story}

---

## 5. Constraints & Policies

> Outcome-level only. Hard limits the product must respect. HOW we satisfy them is design.

### Business / Compliance Constraints

- {e.g. "Must comply with HIPAA — PHI cannot leave the VPC"}
- {e.g. "Free tier limited to 100 requests/day per org"}

### Platform / Operational Constraints

- {e.g. "Must run on iOS 16+ — no newer API features"}
- {e.g. "Must degrade gracefully on 3G networks"}

### Dependencies & Required Integrations

> Name WHAT external systems or capabilities the user requires us to work with. HOW we call them (API style, SDK, message format) is design.

- **Requires:** {feature/system that must exist first}
- **Blocked by:** {any blockers}
- **Named integrations (scope, not mechanism):** {e.g. "Must sync with Salesforce Contacts", "Must support Okta SSO for enterprise tenants", "Must export to QuickBooks"}

## 6. Security Outcomes Required

> WHAT must be protected and against what. HOW (auth mechanisms, hashing algorithms, audit formats) is design.

- **Who can access what:** {e.g. "Only org admins can delete projects"}
- **What must never leak:** {e.g. "User passwords must never be retrievable in plaintext, by anyone, ever"}
- **What must be auditable:** {e.g. "All mutations to billing records must be traceable to an actor"}
- **What legal/regulatory outcomes apply:** {e.g. "GDPR right-to-erasure honored within 30 days"}

## 7. Open Questions

> Questions that need answers before or during implementation

- [ ] {Question 1}
- [ ] {Question 2}

## 8. References

- **Discussion Log:** `docs/prds/{feature-name}-discussion.md`
- **Related PRDs:** {links to related PRDs}
- **Competitor Reference:** {if synthesizing from competitors}

---

## Appendix A: Revision History

| Version | Date   | Author        | Changes     |
| ------- | ------ | ------------- | ----------- |
| 1.0     | {date} | Forge host + User | Initial PRD |

## Appendix B: Approval

- [ ] Product Owner approval
- [ ] Technical Lead approval
- [ ] Ready for technical design
````

## Validation Checklist

Before finalizing, verify PRD has:

- [ ] Clear overview (someone can understand in 30 seconds)
- [ ] At least 1 user story with Gherkin scenario
- [ ] Acceptance criteria for EVERY story (specific, testable)
- [ ] Edge cases documented
- [ ] Explicit non-goals
- [ ] Success metrics with targets
- [ ] Constraints & Policies stated at outcome level (no "use library X" / "implement with Y")
- [ ] Required integrations are NAMED as scope (e.g. "must sync with Salesforce") — not HOW we call them (no SDK choice, API call shape, message broker pick)
- [ ] Interoperability requirements ARE allowed as scope when they define the product surface (e.g. "accept SAML 2.0", "export iCalendar", "serve OpenAPI 3.1") — these are WHAT the product must interoperate with, not HOW it implements internally
- [ ] Security outcomes stated (who accesses what, what must not leak, required auth capabilities like "SSO") — NOT internal security mechanism (hashing algorithm, token signing choice, session storage)
- [ ] No internal implementation picks — no data model schemas, no internal algorithm choices, no internal SDK/library picks (those belong in design)
- [ ] No TBD or placeholder text

## Output

- Creates `docs/prds/{feature-name}.md`
- PRD is ready for technical design phase
- Prompt user to continue with `/new-feature {feature-name}` when approved

## Error Handling

**If no discussion file exists:**

```

No discussion file found for "{feature-name}".

Before creating a PRD, we should refine the user stories together.
Run: /prd:discuss {feature-name}

Then provide your user stories, and I'll help identify gaps before we write the PRD.

```

**If discussion is incomplete:**

```

The discussion for "{feature-name}" appears incomplete (status: In Progress).

Would you like to:

1. Continue the discussion (recommended)
2. Create PRD anyway with current understanding

Reply with your choice.

```
