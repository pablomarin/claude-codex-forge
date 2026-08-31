---
name: ui-design
description: >
  Design and build production-grade frontend interfaces across three modes:
  Marketing/Expressive (landing pages, portfolios), Product UI (dashboards,
  admin panels, CRUD apps), and Trust-First (healthcare, finance, legal).
  Auto-triggers on any user-facing interface work.
---

# UI Design

> Build interfaces that are intentionally designed, fit for purpose, and impossible to mistake for AI-generated defaults.

## Step 0: Choose Mode

**Before anything else, determine the mode.** Every step after this branches based on the mode you select.

| If the surface involves...                                                    | Mode                       | Optimize for                                      |
| ----------------------------------------------------------------------------- | -------------------------- | ------------------------------------------------- |
| Sensitive decisions, money, health, legal, compliance, irreversible actions   | **Trust-First**            | Clarity, confidence, safety, accuracy             |
| Authenticated workflows, dashboards, tables, CRUD, admin, settings, reporting | **Product UI**             | Efficiency, scanability, task completion, density |
| Landing pages, marketing sites, portfolios, event pages, brand showcases      | **Marketing / Expressive** | Wow factor, conversion, memorability, emotion     |

**Nuance:** Domain risk overrides surface type. A fintech landing page is **Trust-First**, not Marketing. A healthcare marketing site may blend Trust-First aesthetics with Marketing conversion patterns.

### Mixed-Mode Surfaces

Some pages cross mode boundaries. When this happens, **choose the primary mode for the page, then apply section-level overrides**:

- **SaaS app with a marketing landing page** → Landing page = Marketing, app dashboard = Product UI. Different modes for different routes.
- **Fintech homepage** → Trust-First overall, but the hero section can borrow Marketing's conversion patterns (just with conservative motion).
- **Admin panel with destructive actions** → Product UI overall, but destructive flows (delete account, cancel subscription) follow Trust-First confirmation patterns.
- **E-commerce with checkout** → Marketing for product pages, Trust-First for checkout/payment flow.

**Rule:** When in doubt, choose the more conservative mode. It's easier to add polish than to fix broken trust.

After choosing a mode, check `references/industry-design-guide.md` for industry-specific palette (`P-XX`), font pairing (`F-XX`), and anti-patterns. These map to ready-to-use tokens in `references/typography-and-color.md`.

---

## Step 1: Design Thinking (BEFORE writing code)

### Universal (all modes)

1. **Purpose**: What problem does this interface solve? Who uses it? What's the primary user task?
2. **Success criteria**: How do you know the design worked? (Conversion? Task completion time? Error rate? Trust?)
3. **Constraints**: Framework, performance budget, accessibility requirements, brand guidelines

### Marketing / Expressive — add:

4. **Tone**: Pick a specific aesthetic — don't settle for "modern and clean":
   - Brutally minimal | Maximalist chaos | Retro-futuristic | Organic/natural
   - Luxury/refined | Playful/toy-like | Editorial/magazine | Brutalist/raw
   - Dark OLED luxury | SaaS minimal | Bento grid | Spatial UI
5. **Differentiation**: What's the ONE thing someone will remember after leaving?
6. **Conversion path**: What's the primary CTA? Consult `references/landing-patterns.md`

### Product UI — add:

4. **Information architecture**: What's the nav structure? Sidebar, topbar, breadcrumbs, tabs?
5. **Data density**: How much information per screen? Dense (admin/dashboard) or focused (wizard/settings)?
6. **Power users**: Do users need keyboard shortcuts, bulk actions, saved views, or command palettes?

### Trust-First — add:

4. **Risk level**: What happens if the user makes a mistake? Can it be undone?
5. **Trust signals**: What credentials, security cues, or verification steps does the user need to see?
6. **Explanation needs**: Does the user need to understand WHY something is recommended, shown, or restricted?

---

## Step 2: Reuse Approved Primitives Before Building

Before building a standard component from scratch, inspect the project's existing
design system and its approved component sources. Reuse a compatible primitive only
when its license, maintenance status, accessibility behavior, and styling can be
verified. Never import a component's business or regulated workflow logic blindly.

If the active environment can browse an approved source, use it to compare options;
otherwise ask the user for a component link or build the smallest project-native
primitive. See `references/21st-dev-components.md` for a source-neutral evaluation
checklist.

**Mode-specific guidance:**

- **Marketing**: Evaluate heroes, CTAs, pricing, testimonials, and visual effects.
- **Product UI**: Evaluate tables, forms, sidebars, tabs, and inputs.
- **Trust-First**: Evaluate forms, alerts, and dialogs, but reuse only presentation primitives.

---

## Step 3: Anti-Slop Rules (MANDATORY)

### Universal (all modes)

- No unstyled component library defaults (raw Bootstrap, default shadcn without customization)
- No placeholder images or gray rectangles — use real assets
- No missing states (hover, focus, disabled, loading, error, empty)
- Always `prefers-reduced-motion` respected
- Always WCAG AA contrast (4.5:1 text, 3:1 large text/UI)

### Marketing / Expressive — also avoid:

- Inter, Roboto, Arial, Space Grotesk, system-ui defaults (choose distinctive fonts instead)
- Purple gradients on white backgrounds
- Evenly-padded card grids with identical rounded corners
- Generic hero sections with centered text and a gradient button
- **Anti-convergence**: No two designs should look the same. Vary themes, fonts, aesthetics

### Product UI — also avoid:

- Decorative animations that slow task completion
- Custom fonts that hurt scanability at small sizes (system fonts and Inter are FINE here)
- Marketing-style hero sections in app UIs
- Ambiguous icons without labels
- Inconsistent spacing, alignment, or component patterns across screens

### Trust-First — also avoid:

- Playful or casual tone on serious workflows
- Motion-heavy effects that feel unserious (particles, glitch, neon)
- Hidden information or progressive disclosure of critical details
- Color-only status indicators (always pair with icons + text)
- AI purple/pink gradients on professional/regulated surfaces

---

## Step 4: Visual Rules (MODE-SPECIFIC)

### Marketing / Expressive

Static pages are drafts. Every marketing page needs **visible, intentional motion** — but the TYPE depends on the visual system you choose:

#### Visual Systems (pick one, don't mix)

| System              | Hero Treatment                                   | Motion Level                               | Best For                                   | Font Pairing   |
| ------------------- | ------------------------------------------------ | ------------------------------------------ | ------------------------------------------ | -------------- |
| **Spectacle Tech**  | Canvas particles, WebGL shader gradient          | High — parallax, stagger, scroll-triggered | SaaS, AI, dev tools, startups              | `F-03`, `F-10` |
| **Editorial Clean** | Full-bleed photography, slow ken burns           | Medium — subtle reveals, type animation    | Magazines, blogs, content, agencies        | `F-04`, `F-01` |
| **Luxury Minimal**  | Slow parallax (400-600ms), video background      | Low-Medium — elegant reveals, no gimmicks  | Fashion, luxury, premium services          | `F-01`, `F-12` |
| **Playful Vibrant** | Animated illustrations, Lottie, bright gradients | High — bouncy spring, playful interactions | Education, community, consumer, events     | `F-06`, `F-10` |
| **Organic Natural** | Flowing SVG shapes, soft gradients, nature photo | Medium — morphing blobs, gentle scroll     | Wellness, non-profit, sustainability, food | `F-07`, `F-06` |

#### Universal Marketing Requirements (all systems)

1. **Hero MUST have intentional motion** — type depends on the visual system above.
2. **At least one interactive element** responding to mouse position or scroll.
3. **Feature cards MUST have entrance animations** + hover transforms.
4. **Staggered page load** — elements reveal in sequence, not all at once.
5. **Section transitions** — visual separation (waves for Spectacle, whitespace for Editorial, subtle gradient for Luxury).

**Spatial composition**: Asymmetry, overlap, diagonal flow, grid-breaking, bold negative space.
**Backgrounds**: Match visual system — gradient meshes for Spectacle, clean white for Editorial, dark + gold for Luxury, bright gradients for Playful, soft organic textures for Natural.

See `references/animation-techniques.md` for implementation details.

### Product UI

Efficiency beats spectacle. Every pixel should help the user complete their task:

1. **Consistent app shell** — predictable sidebar/topbar/breadcrumb structure across all screens.
2. **Dense but scannable** — group related info, use whitespace to separate groups, align labels consistently.
3. **Functional motion only** — smooth transitions (150-200ms), skeleton loaders, optimistic updates. No decorative animation.
4. **Complete state coverage** — every component needs: default, hover, focus, active, disabled, loading, error, empty states.
5. **Keyboard-first** — all actions reachable via keyboard. Tab order follows visual order.

| Element             | Key Pattern                                                                 |
| ------------------- | --------------------------------------------------------------------------- |
| Tables              | Sticky headers, sort, filter, bulk actions, column visibility, pagination   |
| Forms               | Inline validation on blur, clear error placement, autosave or explicit save |
| Dashboards          | KPI cards with comparison periods, chart selection by data type, drilldown  |
| Navigation          | Breadcrumbs for depth, tabs for parallel views, sidebar for global nav      |
| Empty states        | Helpful guidance + primary action, not blank screens                        |
| Destructive actions | Confirmation dialog with explicit consequences, undo when possible          |

See `references/product-ui-patterns.md` for comprehensive patterns.

### Trust-First

Users need to feel safe, informed, and in control:

1. **Calm, professional aesthetic** — smooth transitions only (200-300ms). No particles, WebGL, animated waves, or spring animations.
2. **Maximum clarity** — plain language, visible status, explicit next steps. If a user has to guess what's happening, it's broken.
3. **Confirmation on irreversible actions** — review steps, explicit consequences, friction before destructive actions.
4. **Trust signals visible** — credentials, security badges, encryption indicators, privacy policies, contact information.
5. **Accessibility AAA on critical paths** — 7:1 contrast on text that affects decisions. Large touch targets (48px+).

| Element        | Key Pattern                                                                                |
| -------------- | ------------------------------------------------------------------------------------------ |
| Forms          | Multi-step with review, required field indicators, inline validation, clear error messages |
| Status         | Plain-language alerts, color + icon + text (never color alone), timestamps, data freshness |
| Sensitive data | Masking by default, reveal controls, audit trail, session timeout warnings                 |
| Confirmations  | Explicit consequences stated, separate confirm button, undo when possible                  |
| Explanations   | Why a recommendation exists, what happens next, who to contact for help                    |

See `references/trust-first-patterns.md` for domain-specific patterns.

---

## Step 5: Real Assets (NOT Placeholders)

### Universal

Never ship placeholder images, fake data, or gray rectangles. Use real assets during development.

### Marketing / Expressive

- **Stock photography** → an approved stock-photo source for contextual photos matching your aesthetic
- **AI-generated imagery** → activate the Forge generate-image skill when it is available, for custom hero images and illustrations
- **Optimize everything** → WebP/AVIF, explicit dimensions, lazy-load below fold

### Product UI

- **Realistic seeded data** → Use plausible names, emails, dates, amounts — not "John Doe" / "test@test.com"
- **Realistic empty states** → Helpful message + primary action (not "No data found")
- **Screenshots for docs/onboarding** → Actual product screenshots, not wireframes

### Trust-First

- **Redacted examples** → Show data structure without exposing real PII
- **Realistic but safe** → Use clearly fake but plausible data (e.g. "Jane Smith, Account \*\*\*\*4829")
- **Professional imagery** → Avoid stock photos of smiling people in medical/legal contexts. Use credentials, buildings, abstract trust imagery

See `references/media-assets.md` for sizes, formats, platform references, and optimization.

---

## Step 6: Implementation References

Consult these references for detailed implementation:

- **Component evaluation** → `references/21st-dev-components.md` — source-neutral reuse checklist
- **Industry context** → `references/industry-design-guide.md` — product-type → palette, font, motion, anti-patterns
- **Landing pages** → `references/landing-patterns.md` — conversion patterns and CTA hierarchy _(Marketing mode)_
- **Product UI** → `references/product-ui-patterns.md` — app shells, tables, dashboards, workflows _(Product mode)_
- **Trust-First** → `references/trust-first-patterns.md` — trust signals, high-stakes forms, domain flows _(Trust mode)_
- **UX anti-patterns** → `references/ux-antipatterns.md` — Do/Don't checklist across all modes
- **Animations & effects** → `references/animation-techniques.md` — SVG waves, WebGL, Framer Motion, GSAP _(primarily Marketing mode)_
- **Typography & color** → `references/typography-and-color.md` — font pairings (F-01–F-12), palettes (P-01–P-12), OKLCH, dark mode
- **Media assets & sizes** → `references/media-assets.md` — platform sizes, image generation, optimization
- **Post-build polish** → `references/polish-checklist.md` — quality audit before delivery

---

## Step 7: Final Check (MODE-AWARE)

### Universal checks (all modes)

1. Does it look **intentionally designed**, not generated? If it looks like AI output, redo it.
2. Is there a clear **visual hierarchy** — can you instantly see what's most important?
3. Are **all interactive states** covered? (hover, focus, active, disabled, loading, error, empty)
4. Are assets **real** — not placeholder boxes or gray rectangles?
5. Does it **respect `prefers-reduced-motion`** and meet WCAG AA contrast?
6. Are **social metadata assets** present? (`favicon.ico`, `apple-icon.png`, `icon.svg`, `opengraph-image.png`, OpenGraph + Twitter card) — see `references/polish-checklist.md` Section 9
7. Run through `references/polish-checklist.md`

### Marketing / Expressive — also check:

8. Does the **hero create a "wow" moment** using the chosen visual system? (Spectacle: particles/WebGL, Editorial: photography/type, Luxury: slow parallax, Playful: illustrations, Organic: flowing shapes)
9. Are **section dividers animated** (not flat lines)?
10. Is there at least one **interactive element** (mouse/scroll responsive)?
11. Are fonts **distinctive** (not generic defaults)?
12. Would a **non-technical person say "wow"** on page load?
13. Is the **conversion path clear** — primary CTA visible, repeated, high-contrast?

### Product UI — also check:

8. Can the user **complete their primary task** without confusion?
9. Is the **navigation predictable** — can you always tell where you are?
10. Are **tables scannable** — sticky headers, clear sort/filter, good density?
11. Are **forms usable** — visible labels, inline validation, clear error placement?
12. Does the interface support **power users** — keyboard nav, bulk actions, shortcuts?
13. Are **loading and empty states** handled gracefully?

### Trust-First — also check:

8. Does the user feel **safe and informed** — trust signals visible, status clear?
9. Are **irreversible actions** protected with confirmation + explicit consequences?
10. Is **sensitive data** masked by default with reveal controls?
11. Are **critical paths AAA accessible** — large text, high contrast, large touch targets?
12. Does the interface **explain itself** — why something is shown, what happens next?
13. Is **all status communicated with color + icon + text** (never color alone)?
