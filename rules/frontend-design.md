---
paths:
  - "**/*.{ts,tsx,js,jsx}"
  - "**/*.{css,scss}"
  - "**/*.html"
---

# Frontend Design Baseline

## Non-Negotiable Standards

- Semantic HTML first: `<nav>`, `<main>`, `<article>`, `<button>`, `<dialog>`
- WCAG AA contrast: 4.5:1 text, 3:1 large text/UI elements
- `prefers-reduced-motion` respected on ALL animations
- `prefers-color-scheme` respected for light/dark
- Mobile-first responsive: test 320px, 375px, 768px, 1024px, 1440px
- Focus styles on all interactive elements (`:focus-visible` ring/outline)
- No placeholder-only labels on form inputs
- Images: `alt` text, explicit `width`/`height`, WebP/AVIF with fallbacks
- Social metadata: `favicon.ico`, `apple-icon.png`, `icon.svg`, `opengraph-image.png` (1200x630), `metadataBase`, OpenGraph + Twitter card in root layout — **every deployed site, no exceptions**

## Design Standard

Every website, app and component must look current, premium and intentionally
designed. This bar applies equally to Marketing, Product UI and Trust-First.
Use deliberate color, layered backgrounds, considered transparency and polished
movement while preserving readability, task speed and reduced-motion fallbacks.
Default component-library styling and static rectangles are drafts.

NEVER deliver generic Bootstrap/template aesthetics. If it looks like AI slop, it's not done.

Keep UI copy concise. Remove redundant explanations and internal engineering
jargon; reveal secondary detail on demand while keeping critical information
visible. Document the visual direction before implementation and search 21st.dev
first for new or substantially redesigned standard components. Preserve existing
project primitives for small fixes and record real access/compatibility limits.

## Full Design Guidance

Read `.forge/skills/ui-design/SKILL.template.md` for every UI task, including
layout, styling, interactions and UI copy. Claude uses `/ui-design`; Codex uses
`$ui-design`. Implicit application is required regardless of manual invocation.

Use the independent `forge-ui-qa` role for browser acceptance at desktop and phone
sizes against the documented direction. Passing unit/E2E behavior alone cannot
certify visual quality. Include the unchanged audit in the candidate-bound E2E
report; missing or blocked required visual evidence cannot produce E2E PASS.
