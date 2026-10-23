# Product UI Patterns

> Design guidance for dashboards, admin panels, internal tools, CRUD apps, and data-heavy interfaces.
> Use when the mode is **Product UI** — where efficiency, scanability, and task completion matter more than spectacle.
>
> Last reviewed: 2026-03-12

---

## Premium Workspace Standard

Efficiency and visual appeal are both acceptance criteria. Start with the
documented direction from ui-design: a deliberate canvas/surface/accent palette,
clear typography, confident composition and contemporary component craft.
Search 21st.dev for new or substantially redesigned navigation, tables, command
menus, forms, inspectors and backgrounds; integrate them into existing tokens.

A rich workspace may use a deep navigation rail against a lighter work surface,
subtle tonal gradients, translucent floating controls with opaque fallbacks,
layered inspectors, refined borders and brief selection/disclosure transitions.
Choose treatments that suit the brand; do not apply the same glass/neon recipe
to every app. Data stays readable and controls respond immediately.

Show the primary task and most important status first. Remove duplicate heading
explanations and permanent help paragraphs. Put optional fields, provenance and
secondary explanations in an inspector or expandable section, while keeping
scope, costs, dates and irreversible consequences visible. Empty states need
brief useful guidance and a primary action, not a manual.

The independent forge-ui-qa role must assess visual quality separately from task
success. Functional tables and predictable navigation alone do not pass.

---

## App Shell Architecture

Every product UI needs a consistent, predictable shell:

### Navigation Structure

| Pattern              | When to Use                     | Implementation                                                                    |
| -------------------- | ------------------------------- | --------------------------------------------------------------------------------- |
| **Sidebar + Topbar** | Apps with 5+ top-level sections | Collapsible sidebar (icon-only on collapse), topbar for user/search/notifications |
| **Topbar only**      | Simple apps with 3-4 sections   | Horizontal nav in header, no sidebar                                              |
| **Sidebar only**     | Dense admin panels              | Full sidebar with nested sections, no topbar nav                                  |
| **Tabs**             | Parallel views within a section | Horizontal tabs for switching between related views                               |
| **Breadcrumbs**      | Deep hierarchies (3+ levels)    | Show full path, each segment clickable                                            |

### App Shell Rules

- Navigation placement must be **consistent across all screens** — never move the sidebar or change the topbar
- Current location must be **always visible** — highlighted nav item, breadcrumbs, or page title
- **Page headers** should include: title, optional description, and primary action button (top-right)
- **Back navigation** should always work predictably (browser back, breadcrumbs, or explicit back button)

---

## Data Tables

The most complex and important component in product UI.

### Features to Select for the Actual Task

Use only the capabilities the user needs; this is not a quota to add every
control to a simple list.

- [ ] **Sticky header** — visible during scroll
- [ ] **Sort** — click column header, visual indicator for sort direction
- [ ] **Filter** — persistent filter bar or dropdown filters per column
- [ ] **Search** — global text search across visible columns
- [ ] **Pagination or virtual scroll** — never render 1000+ rows in DOM
- [ ] **Empty state** — helpful message when no results match filters
- [ ] **Loading state** — skeleton rows, not a spinner replacing the whole table
- [ ] **Row selection** — checkboxes for bulk actions (select all, select page)
- [ ] **Column visibility** — user can show/hide columns
- [ ] **Responsive** — horizontal scroll on mobile, or card layout for narrow screens

### Table Anti-Patterns

- Tables wider than viewport without horizontal scroll
- Pagination that loses scroll position
- Filters that require a "Submit" button (use live filtering)
- Row click that navigates away without visual affordance (use hover highlight + cursor pointer)
- Text truncation without tooltips on hover

---

## Dashboards & KPIs

### KPI Card Pattern

```
┌─────────────────┐
│  Revenue         │  ← Label (muted, small)
│  $142,583        │  ← Value (large, bold)
│  ↑ 12.3%         │  ← Trend (green up / red down, with direction icon)
│  vs last month   │  ← Comparison period (muted, small)
└─────────────────┘
```

### Dashboard Rules

- **KPI cards**: 3-5 max above the fold. Show value, trend direction, and comparison period
- **Chart selection**: Line for trends, bar for comparison, pie/donut ONLY for parts-of-whole (max 5 slices)
- **Drilldown**: Click a KPI or chart segment to filter the detail table below
- **Time controls**: Date range picker with presets (Today, 7d, 30d, 90d, Custom)
- **Data freshness**: Show "Last updated: 2 min ago" timestamp — users need to trust the data
- **Loading**: Skeleton cards + skeleton charts, not a full-page spinner

### Chart Styling Guide

| Data Story                    | Chart Type               | Styling Notes                                                                   |
| ----------------------------- | ------------------------ | ------------------------------------------------------------------------------- |
| Trend over time               | Line chart               | Smooth curves (`tension: 0.4`), area fill at 10% opacity, branded primary color |
| Comparison between categories | Horizontal bar chart     | Sorted by value, brand palette, rounded corners on bars                         |
| Parts of whole (max 5)        | Donut chart              | 60% inner radius, legend below, muted border between segments                   |
| Distribution                  | Histogram or box plot    | Neutral colors, clear axis labels                                               |
| Correlation                   | Scatter plot             | Opacity 60% for density, branded accent for highlighted points                  |
| Progress toward goal          | Radial progress or gauge | Brand primary fill, muted track, percentage label centered                      |

**Chart rules:**

- Use the project's palette tokens for chart colors — never random colors
- Always include axis labels, tooltips on hover, and a legend
- Responsive: charts should resize gracefully, not overflow
- Empty chart state: "No data for this period" with suggestion to adjust filters
- Animate on first load only (count-up for numbers, draw for lines) — no looping animations

### Branded App Shell

Product UI doesn't mean boring. Make app shells distinctive:

- **Sidebar**: Brand primary as accent color for active item, subtle hover states, collapsible with icon-only mode
- **Page headers**: Consistent layout — title left, actions right, optional breadcrumbs above
- **Cards and panels**: Subtle shadows (`shadow-sm`), consistent border-radius, brand accent on focus/selection
- **Empty states**: Branded illustrations (search 21st.dev for "empty state" components), not just text
- **Loading skeletons**: Match the exact layout of the loaded content — same heights, widths, positions
- **Dark mode**: Fully supported with `prefers-color-scheme` — not an afterthought

---

## Forms & Workflows

### Form Patterns

| Pattern               | When to Use                                                           |
| --------------------- | --------------------------------------------------------------------- |
| **Single-page form**  | < 7 fields, simple data entry                                         |
| **Multi-step wizard** | 7+ fields, logical groupings, or dependent steps                      |
| **Inline edit**       | Editing a single field in a detail view (click to edit, blur to save) |
| **Drawer/panel**      | Quick create/edit without leaving the current page                    |
| **Full-page form**    | Complex creation flow with preview (e.g. campaign builder)            |

### Form Rules

- **Labels always visible** above inputs (not just placeholder)
- **Required fields** marked with `*` or "(required)"
- **Validation on blur** for most fields, not on submit only
- **Error messages** below the field that caused them, in red with icon
- **Submit button state**: disabled while submitting, show spinner, re-enable on error
- **Autosave** for long forms (draft state), or explicit "Save" with unsaved-changes warning on navigation
- **Destructive actions** (delete, cancel): separate from primary actions, require confirmation

### Multi-Step Wizard

```
┌─ Step 1 ─── Step 2 ─── Step 3 ─── Review ─┐
│  ●──────────○──────────○──────────○          │  ← Progress indicator
│                                               │
│  [Form fields for current step]               │
│                                               │
│  [Back]                    [Continue]          │  ← Always show Back
└───────────────────────────────────────────────┘
```

---

## Drawers, Modals, and Panels

| Pattern               | When to Use                                            | Width                |
| --------------------- | ------------------------------------------------------ | -------------------- |
| **Modal/Dialog**      | Confirmation, simple form (< 5 fields), critical alert | 400-600px centered   |
| **Drawer (right)**    | Detail view, quick edit, create form                   | 400-600px from right |
| **Side panel**        | Always-visible detail alongside a list                 | 30-40% of viewport   |
| **Full-page overlay** | Complex creation flow, wizard                          | Full viewport        |

**Rules:**

- Modals for decisions, drawers for data entry, panels for context
- Always closeable with Escape key and click-outside
- Never nest modals inside modals
- Drawer should not obscure the list/table it was opened from (keep context visible)

---

## Status & Feedback

### Status Indicators

| Severity | Color        | Icon        | Example                           |
| -------- | ------------ | ----------- | --------------------------------- |
| Success  | Green        | Checkmark   | "Payment processed"               |
| Warning  | Amber/Yellow | Triangle    | "Subscription expiring in 3 days" |
| Error    | Red          | X circle    | "Failed to save — network error"  |
| Info     | Blue         | Info circle | "New version available"           |
| Neutral  | Gray         | Clock/dot   | "Pending review"                  |

**Rules:**

- NEVER use color alone — always pair with icon and text
- Timestamps on all status changes ("Updated 2 min ago", not just "Updated")
- Toast notifications for async success/error (auto-dismiss success after 5s, persist errors)
- Inline errors near the trigger, not just toasts

---

## Empty States

Every view that can be empty needs a designed empty state:

```
┌───────────────────────────┐
│        [Illustration]      │
│                            │
│   No projects yet          │  ← Clear title
│   Create your first        │  ← Helpful description
│   project to get started   │
│                            │
│   [+ Create Project]       │  ← Primary action
└───────────────────────────┘
```

**Types:**

- **First-use empty** — "No X yet. Create your first X to get started." + CTA
- **Filter-empty** — "No results match your filters." + "Clear filters" link
- **Error-empty** — "Failed to load. [Retry]"
- **Permission-empty** — "You don't have access. [Request access]"

---

## Performance for Product UI

- **Virtualize long lists** — react-window or react-virtuoso for 100+ rows
- **Skeleton loaders** per-component, not full-page spinners
- **Optimistic updates** — update UI immediately, rollback on error
- **Debounce search/filter** — 300ms debounce on text input, not per keystroke
- **Progressive loading** — load above-fold content first, lazy-load tabs/sections
- **Stale-while-revalidate** — show cached data immediately, refresh in background

---

## Motion Budget: Product UI

| Allowed                                 | Not Allowed                      |
| --------------------------------------- | -------------------------------- |
| Page transitions (150-200ms fade/slide) | Canvas particles, WebGL effects  |
| Skeleton shimmer during loading         | Animated SVG wave dividers       |
| Hover state transitions (100-150ms)     | Spring entrance animations       |
| Toast slide-in/out                      | Scroll-triggered reveals         |
| Accordion open/close                    | Parallax effects                 |
| Progress bar animation                  | Custom cursor effects            |
| Number count-up for KPIs                | Continuous background animations |
