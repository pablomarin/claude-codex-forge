# /prd:discuss {feature-name}

Interactive refinement of user stories before PRD creation. Acts as a skeptical PM who surfaces gaps, ambiguities, and missing requirements.

## Purpose

User stories are often incomplete. This command ensures we understand requirements deeply BEFORE writing a PRD, preventing costly rework downstream.

## Instructions

> **Research note:** This command is about refining WHAT the user needs — personas, goals, non-goals, acceptance. Solution research (libraries, protocols, data shapes, auth mechanisms) happens in the design phase via `/new-feature` Phase 2's `research-first` agent. Do not run solution research inside this command — staying at the requirements layer is what makes this phase valuable.
>
> **In-band discovery research IS allowed, when scoped to requirements.** If during the discussion you hit a question you genuinely cannot answer without competitor / industry-pattern context (e.g. "what does 'import progress' look like in products users expect?", "what accessibility floor do analogous products hit?"), you MAY pause the discussion, run targeted WebSearch / WebFetch / Context7 queries, and bring the findings back into the conversation. Keep the research focused on user expectations and product norms — NOT on implementation choices (libraries, protocols, code patterns). If the question you want to research is "which library should we use" or "which protocol is fastest," stop — that's design.

### Phase 1: Initial Analysis

1. Read user stories from:
   - User's message (inline)
   - Attached file
   - Existing file at `docs/prds/{feature-name}-stories.md`

2. Create discussion file at `docs/prds/{feature-name}-discussion.md` with header:

   ```markdown
   # PRD Discussion: {Feature Name}

   **Status:** In Progress
   **Started:** {date}
   **Participants:** User, current Forge host

   ## Original User Stories

   {paste user's original input}

   ## Discussion Log
   ```

### Phase 2: Targeted Questioning

Analyze the stories and ask **5-10 pointed questions** covering the areas below.

> **Stay on the WHAT, not the HOW.** Don't ask about INTERNAL implementation choices — which library, which internal data shape, which internal auth/hashing mechanism — those are design decisions, asked during brainstorming. DO ask what the user expects to SEE and DO, and whether a specific **external protocol, standard, or format** is part of the required product surface (interoperability is scope, not implementation).
>
> Examples:
>
> - "Does the user need real-time visible progress, or is a final outcome enough?" — requirement question ✅
> - "Must the product accept SAML 2.0 assertions from customer IdPs?" — scope question (interoperability) ✅
> - "Must we export iCalendar format for user downloads?" — scope question (product surface) ✅
> - "SSE vs polling for progress?" — internal mechanism, skip ❌
> - "Which JWT algorithm for internal sessions?" — internal mechanism, skip ❌

#### Personas & Access

- Who are ALL the users of this feature? (Don't assume just one persona)
- What permissions/roles are required?
- Are there read-only vs. edit personas?

#### Scope Boundaries

- What's explicitly IN scope for MVP?
- What's explicitly OUT of scope (non-goals)?
- If we could only ship 2 of N stories, which 2?

#### Happy Path Gaps

- What are the specific inputs/outputs?
- What does "success" look like concretely?
- Are there quantitative requirements? ("fast" = how fast?)

#### Error Cases & Edge Cases

- What happens when X fails?
- What if user has no permissions?
- What if data is malformed/missing?
- What are the boundary conditions?

#### Dependencies & Constraints

- Does this require other features to exist first?
- Are there technical constraints (API limits, database schema)?
- Are there business constraints (compliance, legal)?

#### Success Metrics

- How will we know this feature is working?
- What do we measure?
- What's the acceptance threshold?

### Phase 3: Iterative Refinement

1. Wait for user answers
2. Based on answers, ask follow-up questions
3. Update discussion file with Q&A log
4. Continue until user says "ready" or "done" or "let's write the PRD"

### Phase 4: Completion

When user indicates readiness:

1. Update discussion file status to "Complete"
2. Add summary section:

   ```markdown
   ## Refined Understanding

   ### Personas

   - {persona 1}: {description}

   ### User Stories (Refined)

   - US-001: {refined story}

   ### Non-Goals

   - {explicit exclusion}

   ### Key Decisions

   - {decision from discussion}

   ### Open Questions (Remaining)

   - [ ] {any unresolved questions}
   ```

3. Prompt user to run `/prd:create {feature-name}`

## Question Style Guide

**DO ask:**

- Specific, targeted questions based on the actual stories
- "What happens if..." scenarios
- "Who else might..." persona expansions
- "You mentioned X - does that mean Y or Z?"

**DON'T ask:**

- Generic checklist questions unrelated to the stories
- Too many questions at once (max 10)
- Questions the user clearly already answered
- Leading questions that assume an answer

## Example Interaction

```
User: /prd:discuss mcp-import

Here are my user stories:
- As an admin, I want to import MCP servers from a URL
- As an admin, I want to see import progress

Forge host: I've logged these stories to docs/prds/mcp-import-discussion.md.

Before we write a PRD, let me understand these better:

**Personas:**
1. Is "admin" the only role that can import? What about project owners
   or super-admins? Are there any read-only personas who need to see
   imports happening?

**Story 1 - Import from URL (scope & behavior):**
2. What URL sources must we support? (public links, private repos requiring
   auth, something else the user points us at) — scope question, not
   protocol question.

3. What happens if the URL is unreachable? Does the user see a
   clear error, a retry, something else?

4. What happens if the URL points to a valid file but the content is
   not a valid MCP config? What does the user see?

5. Can the same URL be imported twice — replace, dedupe, or error?

**Story 2 - Import progress (user-visible behavior):**
6. Is "progress" required to be real-time visible, or is an end-of-import
   success/failure message sufficient? (Real-time = new requirement;
   "end-of-import only" might be simpler and OK.)

7. If the user navigates away mid-import, what must they see when they
   return? Is the import expected to continue running whether or not they
   are watching? (User-visible behavior — the implementation choice of
   foreground vs background job is design.)

**Scope & security outcomes:**
8. Single URL at a time, or bulk import? (Scope decision.)

9. Does "import MCP servers" include credentials / API keys bundled
   with the server definition, or only the definition? (This is a
   security-outcome question — NOT "how do we encrypt them".)

10. After import, do servers auto-start or require an explicit enable
    action by the user?
```

> Notice: none of the questions above ask which protocol, parser, data
> model, or storage mechanism to use. Those are design questions, asked
> after the PRD lands.

## Output

- Creates/updates `docs/prds/{feature-name}-discussion.md`
- Conversation continues until user is ready
- Ends with prompt to run `/prd:create {feature-name}`
