# Typography & Color Reference

## Fluid Typography Scale

```css
:root {
  --text-xs: clamp(0.75rem, 0.7rem + 0.25vw, 0.875rem);
  --text-sm: clamp(0.875rem, 0.8rem + 0.35vw, 1rem);
  --text-base: clamp(1rem, 0.9rem + 0.5vw, 1.125rem);
  --text-lg: clamp(1.125rem, 1rem + 0.65vw, 1.25rem);
  --text-xl: clamp(1.25rem, 1.1rem + 0.8vw, 1.5rem);
  --text-2xl: clamp(1.5rem, 1.2rem + 1.5vw, 2rem);
  --text-3xl: clamp(2rem, 1.5rem + 2.5vw, 3rem);
}
```

Modular scale ratios: 1.25 (major third) or 1.333 (perfect fourth). Line-height: 1.4-1.6 body, 1.1-1.2 headings. Always `font-display: swap` on `@font-face`.

## Font Strategy

| Role        | Usage            | Example                                          |
| ----------- | ---------------- | ------------------------------------------------ |
| **Display** | Hero headlines   | Playfair Display, Cabinet Grotesk, Clash Display |
| **Heading** | Section titles   | Satoshi, General Sans, Sora                      |
| **Body**    | Paragraphs, UI   | Instrument Sans, Plus Jakarta Sans, DM Sans      |
| **Caption** | Labels, metadata | Body font at smaller size                        |

Usually keep to one or two families. Pair a distinctive display face with a
readable body where useful. System fonts, Inter, Roboto, Arial and Space Grotesk
are valid when suited to the product; create identity through hierarchy,
composition and craft rather than arbitrary font bans.

## OKLCH Color System

```css
:root {
  --color-primary: oklch(55% 0.25 250);
  --color-primary-light: oklch(70% 0.2 250);
  --color-primary-dark: oklch(40% 0.25 250);
  --color-accent: oklch(65% 0.3 30);
  --color-success: oklch(60% 0.2 145);
  --color-warning: oklch(70% 0.2 80);
  --color-error: oklch(55% 0.25 25);
  --color-neutral-50: oklch(98% 0 0);
  --color-neutral-500: oklch(55% 0.01 250);
  --color-neutral-900: oklch(15% 0 0);
}
```

HSL fallback: `@supports not (color: oklch(0% 0 0)) { }`. Semantic tokens: primary, accent, success, warning, error, neutral. 5-7 base colors, derive shades by adjusting lightness. Bold dominant colors with sharp accents beat timid palettes.

## WCAG Contrast

Use the [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
for actual measurements and large-text definitions.

- **Normal text**: 4.5:1 minimum (WCAG AA)
- **Large text** (18pt / 24 CSS px, or 14pt / approximately 18.7 CSS px bold) and **UI elements**: 3:1 minimum
- Measure actual foreground/background pairs; OKLCH lightness differences do not establish WCAG contrast
- Target AA, aim for AAA (7:1 text, 4.5:1 large)

## Dark Mode

```css
@media (prefers-color-scheme: dark) {
  :root {
    --color-bg: oklch(15% 0.01 250);
    --color-surface: oklch(20% 0.01 250);
    --color-text: oklch(90% 0 0);
    --color-primary: oklch(70% 0.2 250);
    --color-accent: oklch(75% 0.25 30);
  }
}
```

Reduce chroma rather than just inverting. Dark neutrals usually preserve depth;
pure black can suit an intentional OLED treatment. Adjust accent lightness and
verify contrast in the actual theme. Test supported modes throughout.

## Spacing Scale

4px base: `--space-1: 0.25rem` (4) through `--space-24: 6rem` (96). Steps: 4, 8, 12, 16, 24, 32, 48, 64, 96.

- CSS Grid for page layout, Flexbox for components
- Container max: 1200-1440px, `margin-inline: auto`
- Fluid spacing: `padding: clamp(1rem, 3vw, 3rem)`

## Backgrounds as Atmosphere

**Gradient mesh**: layer `radial-gradient()` at different positions with `background-blend-mode: screen`.

**Noise overlay**: pseudo-element with inline SVG turbulence filter at low opacity (0.03-0.05):

```css
.grain::after {
  content: "";
  position: fixed;
  inset: 0;
  opacity: 0.04;
  pointer-events: none;
  background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence baseFrequency='0.8'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
}
```

**Custom cursors**: `cursor: url('/cursors/custom.svg') 16 16, crosshair` for interactive areas. Use `grab`/`grabbing` for draggables.

---

## Curated Font Pairings

12 vetted pairings with Google Fonts imports and Tailwind config. Referenced by ID from `industry-design-guide.md`.

| ID     | Name                | Heading               | Body           | Mood                            | Best For                            | Google Fonts Import                                                               |
| ------ | ------------------- | --------------------- | -------------- | ------------------------------- | ----------------------------------- | --------------------------------------------------------------------------------- |
| `F-01` | Classic Elegant     | Playfair Display      | Source Sans 3  | Luxury, sophisticated, timeless | Fashion, luxury, editorial, legal   | `family=Playfair+Display:wght@400;600;700&family=Source+Sans+3:wght@400;600`      |
| `F-02` | Modern Professional | Poppins               | Open Sans      | Clean, corporate, friendly      | SaaS, B2B, startups, healthcare     | `family=Poppins:wght@400;500;600;700&family=Open+Sans:wght@400;600`               |
| `F-03` | Tech Startup        | Sora                  | DM Sans        | Innovative, modern, bold        | Tech, AI, developer tools           | `family=Sora:wght@400;500;600;700&family=DM+Sans:wght@400;500;700`                |
| `F-04` | Editorial Clean     | Lora                  | Source Sans 3  | Refined, readable, editorial    | Blogs, magazines, content sites     | `family=Lora:wght@400;500;600;700&family=Source+Sans+3:wght@400;500;600`          |
| `F-05` | Corporate Authority | IBM Plex Sans         | IBM Plex Serif | Professional, trustworthy       | Finance, government, enterprise     | `family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@400;600`        |
| `F-06` | Friendly Rounded    | Nunito                | Lato           | Approachable, warm, soft        | Education, non-profit, community    | `family=Nunito:wght@400;600;700&family=Lato:wght@400;700`                         |
| `F-07` | Warm Artisan        | Merriweather          | Source Sans 3  | Crafted, traditional, warm      | Restaurants, hospitality, artisan   | `family=Merriweather:wght@400;700&family=Source+Sans+3:wght@400;600`              |
| `F-08` | Bold Display        | Clash Display\*       | General Sans\* | Dramatic, bold, attention       | Agencies, portfolios, landing pages | \*Not on Google Fonts — use Fontshare CDN                                         |
| `F-09` | Developer Mono      | JetBrains Mono        | DM Sans        | Technical, precise, clear       | Dev tools, docs, code-heavy sites   | `family=JetBrains+Mono:wght@400;500;700&family=DM+Sans:wght@400;500;700`          |
| `F-10` | Geometric Modern    | Outfit                | DM Sans        | Geometric, clean, versatile     | Startups, apps, dashboards          | `family=Outfit:wght@400;500;600;700&family=DM+Sans:wght@400;500;700`              |
| `F-11` | Impact Heavy        | Big Shoulders Display | Work Sans      | Bold, impactful, energetic      | Gaming, sports, events              | `family=Big+Shoulders+Display:wght@400;600;800&family=Work+Sans:wght@400;500;600` |
| `F-12` | Creative Variable   | Bricolage Grotesque   | Crimson Pro    | Expressive, artistic, unique    | Creative, fashion, culture          | `family=Bricolage+Grotesque:wght@400;600;700&family=Crimson+Pro:wght@400;600`     |

**Usage in Tailwind:**

```js
// tailwind.config.js
fontFamily: {
  heading: ['Poppins', 'sans-serif'],      // F-02 heading
  body: ['Open Sans', 'sans-serif'],       // F-02 body
}
```

**Usage in CSS:**

```css
@import url("https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&family=Open+Sans:wght@400;600&display=swap");
```

---

## Industry Color Palettes

12 palette starting points. Referenced by ID from `industry-design-guide.md`.
These are not contrast certificates: measure each actual text/control pair,
including hover/disabled/selected states and transparent layers, before acceptance.

| ID     | Name               | Primary   | Secondary | Accent    | Background | Foreground | Muted     | Border    |
| ------ | ------------------ | --------- | --------- | --------- | ---------- | ---------- | --------- | --------- |
| `P-01` | SaaS Blue          | `#2563EB` | `#3B82F6` | `#EA580C` | `#F8FAFC`  | `#1E293B`  | `#E9EFF8` | `#E2E8F0` |
| `P-02` | Fintech Dark       | `#0F172A` | `#1E293B` | `#22C55E` | `#020617`  | `#F8FAFC`  | `#1A1E2F` | `#334155` |
| `P-03` | Commerce Green     | `#059669` | `#10B981` | `#EA580C` | `#ECFDF5`  | `#064E3B`  | `#E8F1F3` | `#A7F3D0` |
| `P-04` | Luxury Monochrome  | `#1C1917` | `#44403C` | `#A16207` | `#FAFAF9`  | `#0C0A09`  | `#E8ECF0` | `#D6D3D1` |
| `P-05` | Healthcare Calm    | `#0891B2` | `#22D3EE` | `#059669` | `#ECFEFF`  | `#164E63`  | `#E8F1F6` | `#A5F3FC` |
| `P-06` | Education Vibrant  | `#4F46E5` | `#818CF8` | `#EA580C` | `#EEF2FF`  | `#1E1B4B`  | `#EBEEF8` | `#C7D2FE` |
| `P-07` | Government Neutral | `#0F172A` | `#334155` | `#0369A1` | `#F8FAFC`  | `#020617`  | `#E8ECF1` | `#E2E8F0` |
| `P-08` | Wellness Soft      | `#8B5CF6` | `#C4B5FD` | `#059669` | `#FAF5FF`  | `#4C1D95`  | `#EDEFF9` | `#EDE9FE` |
| `P-09` | Tech Indigo        | `#6366F1` | `#818CF8` | `#059669` | `#F5F3FF`  | `#1E1B4B`  | `#EBEFF9` | `#E0E7FF` |
| `P-10` | Hospitality Warm   | `#DC2626` | `#F87171` | `#A16207` | `#FEF2F2`  | `#450A0A`  | `#F0EDF1` | `#FECACA` |
| `P-11` | Professional Teal  | `#0F766E` | `#14B8A6` | `#0369A1` | `#F0FDFA`  | `#134E4A`  | `#E8F0F3` | `#99F6E4` |
| `P-12` | Entertainment Neon | `#7C3AED` | `#A78BFA` | `#F43F5E` | `#0F0F23`  | `#E2E8F0`  | `#27273B` | `#4C1D95` |

**Usage in Tailwind (CSS variables):**

```css
:root {
  --color-primary: #2563eb; /* P-01 */
  --color-secondary: #3b82f6;
  --color-accent: #ea580c;
  --color-background: #f8fafc;
  --color-foreground: #1e293b;
  --color-muted: #e9eff8;
  --color-border: #e2e8f0;
}
```

**Dark mode variants:** For palettes with light backgrounds, swap background/foreground and reduce accent chroma. For dark palettes (P-02, P-12), they're already dark-mode ready.
