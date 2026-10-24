---
name: ui-design
description: >
  Design, build, improve and review every user-facing UI: websites, apps,
  dashboards, forms, settings and components. Use for any visual, layout,
  styling, interaction or UI-copy change. Requires premium visual direction,
  21st.dev-first component discovery and independent browser UI QA.
---

# UI Design

Build current, distinctive interfaces that feel comfortable to use. A working
screen is unfinished when it looks generic, dated, cluttered or verbose.
Premium visual quality is an acceptance criterion for **every mode**, including
internal apps and high-stakes workflows. Simplicity means effortless use, not
unstyled rectangles. More effects do not automatically mean better design.

## 1. Establish the visual direction before UI code

Read the existing brand, design system and relevant screens. For an existing app,
improve the affected surface coherently; do not silently redesign unrelated routes.
For each UI task, document a short design brief in the existing plan or task report:

- User, primary task, routes/components and states in scope.
- Specific aesthetic and intended first impression; avoid only "modern and clean."
- Visual references: inspect the user's references and relevant live component
  previews. Record URLs and what to borrow: hierarchy, density, surface treatment,
  interaction. Do not copy a whole product or claim to have browsed unavailable refs.
- Semantic color tokens, typography hierarchy, spacing, radii, elevation,
  background/layer treatment and motion behavior. Use the project's tokens when
  extending an established app.
- One memorable design decision that supports the task: for example a beautifully
  composed workspace, a strong navigation rail, a fluid inspector, or a useful
  interactive visualization. A decorative hero is rarely appropriate inside an app.
- Concise copy and what stays visible versus available on demand.
- Acceptance at desktop and phone sizes, keyboard/reduced-motion behavior and
  the visual quality the independent reviewer must check.

Translate requested qualities such as distinctive composition, color, depth,
transparency, movement, component craft and concise copy into observable
acceptance criteria. Carry the direction through affected main screens, details,
forms, phone layouts and themes; document where restraint serves the task.
Do not reduce an explicit premium brief to only "clean and functional."

This is the agent's documented direction using established requirements, not a
new mandatory human approval pause. Small component fixes need a proportionate
brief, not a new design document. For a major new surface, build a representative
screen with realistic data and inspect it before propagating the pattern.

## 2. Choose the interaction mode, keep the same quality bar

| Surface | Mode | Design emphasis |
| --- | --- | --- |
| Landing pages, portfolios, brand sites | Marketing / Expressive | Memorable composition, imagery, conversion, expressive motion |
| Apps, dashboards, admin, CRUD, settings | Product UI | Premium workspace, fast interactions, scanability, comfortable density |
| Money, health, legal, sensitive or irreversible decisions | Trust-First | Refined surfaces, calm motion, clear consequences, confidence |

Risk tunes the treatment; it never excuses blandness. Mix modes by route or
section: an admin app's destructive dialog uses Trust-First interaction rules
without losing the app's visual system. A conservative mode still needs excellent
color, typography, composition and component craft.

Read the matching [product patterns](references/product-ui-patterns.md),
[trust patterns](references/trust-first-patterns.md), or
[landing patterns](references/landing-patterns.md). For a new visual system,
use [industry guidance](references/industry-design-guide.md) and
[typography and color](references/typography-and-color.md) as starting points,
not mandatory templates.

## 3. Search 21st.dev first

Before inventing a standard component or a new visual treatment, inspect
**[21st.dev](https://21st.dev)** for relevant components and live previews.
This applies to apps as well as marketing: navigation, command menus, tables,
forms, tabs, dialogs, inspectors, cards, charts, backgrounds and motion.

Also inspect existing project primitives. Reuse an established primitive for a
small fix; do not replace it just to satisfy a component quota. For new or
substantially redesigned components, compare a small relevant selection from
21st.dev, then reuse or adapt the best compatible option. Record source URLs,
what was selected and why. For a selected compatible component,
retrieve and read its actual source before implementation
using the available free allowance; do not settle for recreating its preview.
If authentication limits discovery or source access, ask the user to sign in
in an agent-accessible session. Follow the linked acquisition workflow, then adapt
colors, type and behavior into one coherent design system. Report whether source
was retrieved/adapted, inspected but rejected, or used only as a visual reference.

Read [21st.dev discovery and adoption](references/21st-dev-components.md) for the
workflow, compatibility checks and honest fallback. A source being inaccessible
or a free allowance being exhausted does not authorize a purchase or a stack
migration. Document the limitation and use project primitives or a considered
native implementation; do not stop all useful UI work or invent search results.

## 4. Compose a premium interface in every mode

- **Color:** choose a deliberate palette with semantic accents and rich neutrals.
  Define canvas, surface, elevated surface, border, text, muted text, brand and
  status tokens. Avoid one accent pasted over default gray library components.
- **Backgrounds and depth:** create hierarchy with layered surfaces, tonal
  backgrounds, subtle gradients, borders, light and shadow. Use transparency or
  backdrop blur where it improves separation; give it an opaque fallback and
  verify contrast over the actual content behind it. Reserve busy textures and
  high-energy effects for regions where they do not compete with work.
- **Typography:** make hierarchy, alignment and number formatting intentional.
  Readable system fonts and Inter are valid for dense apps; distinctive display
  type can carry brand where it stays legible. No arbitrary font bans.
- **Composition:** a clear focal point, useful grouping and deliberate rhythm.
  Avoid an endless grid of identical cards, oversized empty padding, or every
  fact shouting with the same badge/weight. Essential task content comes first.
- **Components:** customize primitives into the app's system. Rich controls earn
  their place through the task: searchable selectors, contextual toolbars,
  accessible dialogs, drawers, useful tables, keyboard commands and data views.
  Do not add features solely to look sophisticated.
- **Movement:** include intentional, polished feedback: selection, hover/press,
  focus, disclosure, navigation and loading. Subtle delight is welcome in apps
  when it does not delay action or destabilize data. Prefer brief transitions;
  Trust-First uses calm emphasis. Marketing may be more expressive. Avoid
  gratuitous looping motion, mandatory particles, and a new animation library
  when CSS or the existing stack suffices.

See [animation techniques](references/animation-techniques.md) for techniques,
not a requirement to use every effect. Respect reduced motion with an equivalent
static state, keyboard access, responsive touch behavior and measured performance.

## 5. Edit the interface copy

Use short labels and direct actions. Remove redundant introductions, repeated
page-title explanations, permanent tutorial paragraphs, duplicate status text
and implementation jargon. Do not put engineering evidence or internal policy
in the product UI unless it helps the user make a decision.

Show the task, primary action and essential status immediately. Put secondary
explanations in contextual help, expandable details or an inspector. Never hide
permissions, costs, risk, critical status or irreversible consequences behind a
tooltip. Empty states usually need one useful sentence and an action; error
states need what happened and how to recover. Prefer a compact summary plus
details over a wall of text. Accessible labels stay visible or programmatically
available; reducing copy does not mean replacing clear actions with mystery icons.

## 6. Build real states and inspect the result

Use real permitted assets or clearly synthetic, realistic fixtures; never invent
production facts or expose private data for a demo. Read
[media assets](references/media-assets.md) when imagery is needed. Implement
applicable default, hover, focus, active, disabled, loading, empty, success and
error states. Preserve task context when forms validate, panels open or data
refreshes. A control that looks interactive must work.

Inspect rendered screenshots at **1440×900** and **390×844**, plus the project's
required responsive widths (baseline 320, 375, 768, 1024, 1440). Check long content,
realistic density, keyboard focus, supported themes, reduced motion and overflow.
Use [the polish checklist](references/polish-checklist.md) and
[UX anti-patterns](references/ux-antipatterns.md). Code inspection, a build or a
DOM visibility assertion does not prove visual quality.

## 7. Independent UI acceptance

For UI-changing work, the main agent dispatches a fresh **forge-ui-qa** role from
`.forge/agents/forge-ui-qa.md` (source repository: `agents/forge-ui-qa.md`). Supply
the documented direction, references, acceptance criteria, actual URL, affected
routes/states, candidate identity, persona, authenticated browser when needed
and permitted synthetic interactions. Writes default to no. Do not supply code
as an explanation for an unclear screen.

The reviewer checks the browser independently, rates **visual quality and
usability separately**, and returns screenshots and concrete findings. Both axes
must meet the role's premium bar; a plain but functional screen cannot pass.
Fix observed acceptance failures, then use one bounded closure pass on findings
and direct regressions during repair. After a UI repair changes a frozen candidate,
the new final audit must observe the complete required route/state matrix on the
new candidate; a findings-only closure report cannot substitute for that coverage.
Keep the final audit within the declared design scope rather than expanding into
unrelated design debt. Taste is advisory unless it contradicts the documented
direction. Missing browser access or missing required evidence is BLOCKED, never
an invented visual PASS.

The main agent supplies the unchanged audit to `verify-e2e`, which includes it in
the existing candidate-bound E2E report. Required UI QA FAIL makes E2E FAIL;
missing, stale or BLOCKED audit makes E2E PARTIAL. A final audit must cover the
final candidate. This is workflow acceptance through existing E2E evidence;
the receipt validates evidence linkage, not aesthetic judgment by a hook.
