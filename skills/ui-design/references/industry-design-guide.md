# Industry & Product Context Guide

> Match design direction to product context. Use this BEFORE choosing styles, colors, or animations.
>
> Last reviewed: 2026-10-23

## How to Use

1. Find your product's **context row** below
2. Note the **motion budget**, **palette direction**, and **font direction**
3. Use the **must-do** and **avoid** examples only where they fit the actual task;
   they do not override the UI skill's quality bar or require unrelated features
4. Reference specific palette IDs and font pairing IDs from `typography-and-color.md`

**Important:** These are starting points, not rigid rules or effect quotas. A healthcare _marketing site_ has different needs than a healthcare _patient portal_. All surfaces require premium visual quality. Choose themes from the brand and user preference, not blanket industry bans on dark mode. Add only features in the task's scope; a property admin table does not need virtual tours because its industry row mentions them.

---

## Context Matrix

### Trust-First Products (low motion, high contrast, conservative)

These products handle money, health, legal, or personal safety. Make them refined,
current and comfortable while preserving confidence. Use calm, purposeful motion,
excellent composition, layered surfaces and typography; a conservative context
does not waive visual appeal. Show only verified credentials/security claims.

| Product Context                 | Style Direction             | Motion Budget                                       | Palette Direction                                                                 | Font Direction                                                            | Must-Do                                                                       | Avoid                                                                                  |
| ------------------------------- | --------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Healthcare / Patient Portal** | Accessible + Soft surfaces  | Low — smooth transitions only (200-300ms)           | Calm blue/teal + health green. Palette `P-05`. High contrast (AAA where possible) | Large (16px+ body), high-readability sans-serif. Pairing `F-02` or `F-06` | WCAG AAA on critical paths, large touch targets (48px+), clear error states   | Bright neon, motion-heavy effects, dark mode as default, neumorphism (contrast issues) |
| **Fintech / Banking**           | Minimal + Data-dense        | Low — number animations, status transitions only    | Navy/dark blue + trust gold. Palette `P-02`. Dark mode for dashboards             | Professional, clear hierarchy. Pairing `F-05` or `F-02`                   | Security indicators, real-time data updates, high-contrast alerts (red/green) | Playful design, AI purple/pink gradients, hidden fees, slow rendering                  |
| **Insurance / Legal**           | Trust & Authority + Minimal | Very low — section reveals, accordion only          | Navy + gold/blue accent. Palette `P-07`. Conservative, high contrast              | Authoritative serif or professional sans. Pairing `F-01` or `F-05`        | Credential display, case results, clear CTAs, accessibility AAA               | Ornate design, playful colors, complex animations, low contrast                        |
| **Government / Public Service** | Accessible + Ethical        | Minimal — focus rings, skip links, clear navigation | Professional blue + high contrast. Palette `P-07`. Black/white                    | Large, clear typography (18px+ body). Pairing `F-05` or system fonts      | WCAG AAA, keyboard navigation, skip links, multilingual support               | Motion effects, decorative elements, low contrast, complex layouts                     |
| **Senior Care / Elderly**       | Accessible + Soft           | Very low — clear transitions only                   | Calm blue + warm neutrals. Palette `P-08`. Extra-large text                       | 18px+ body minimum, high-weight headings. Pairing `F-02`                  | Large touch targets (56px+), simple navigation, family portal                 | Small text, complex navigation, hidden information, rapid animations                   |

### Balanced Products (moderate motion, professional aesthetics)

Mainstream products need trust, engagement and premium craft. Use purposeful
movement and considered delight without delaying tasks or distracting from data.

| Product Context                    | Style Direction             | Motion Budget                                               | Palette Direction                                                       | Font Direction                                                 | Must-Do                                                                  | Avoid                                                         |
| ---------------------------------- | --------------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------- |
| **SaaS / B2B Platform**            | Glassmorphism + Flat        | Medium — hover states, section transitions, feature reveals | Trust blue + accent contrast (orange CTA). Palette `P-01`               | Professional + hierarchy. Pairing `F-02` or `F-03`             | Clear feature hierarchy, demo/trial CTA, social proof                    | Dark mode by default, excessive animation, hidden pricing     |
| **E-commerce**                     | Vibrant + Card-based        | Medium — card hover lift, cart animations, product zoom     | Brand primary + success green + urgency orange. Palette `P-03`          | Engaging, clear hierarchy. Pairing `F-02`                      | High-quality product images, fast loading, trust badges, clear checkout  | Flat design without depth, text-heavy pages, slow performance |
| **Productivity / Developer Tools** | Flat + Micro-interactions   | Low-Medium — quick actions (150ms), task animations         | Palette `P-09`. Clear hierarchy + functional colors. Dark mode for IDEs | Clean, efficient. Monospace for code. Pairing `F-09` or `F-10` | Keyboard shortcuts, fast performance, code examples, search              | Complex onboarding, slow rendering, excessive chrome          |
| **Education / E-learning**         | Friendly + Progress-focused | Medium — progress animations, achievement unlocks           | Palette `P-06`. Playful but structured. Indigo + progress green         | Friendly, engaging. Pairing `F-06` or `F-02`                   | Progress tracking, gamification, video player UX, mobile-first           | Dark modes, complex jargon, boring static design              |
| **Real Estate / Property**         | Glassmorphism + Minimal     | Medium — gallery transitions, map interactions              | Trust teal + professional blue. Palette `P-11`                          | Professional, confident. Pairing `F-01` or `F-05`              | Virtual tours, map integration, high-quality photos, mobile booking      | Poor imagery, complex booking flows, hidden fees              |
| **Restaurant / Food Service**      | Vibrant + Appetizing        | Medium — menu hover, food image reveals                     | Warm colors (red, orange, brown) + gold. Palette `P-10`                 | Warm, inviting. Pairing `F-07` or `F-06`                       | High-quality food photography, online ordering, hours/location prominent | Low-quality images, outdated menus, hidden contact info       |
| **Non-profit / Charity**           | Storytelling + Ethical      | Medium — impact counters, story reveals                     | Palette `P-05`. Cause-related colors + trust blue + warm tones          | Heartfelt, readable. Pairing `F-06` or `F-01`                  | Impact stories, donation transparency, mobile-first                      | Hidden financials, no impact data, corporate coldness         |

### Expressive Products (high motion, bold aesthetics)

Products where visual expression supports the experience. Bold motion can fit,
but choose it deliberately; no surface has a mandatory animation quota.

| Product Context                 | Style Direction                               | Motion Budget                                                | Palette Direction                                       | Font Direction                                                   | Must-Do                                                  | Avoid                                                 |
| ------------------------------- | --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------- | ----------------------------------------------------- |
| **Creative Agency / Portfolio** | Brutalism + Motion-driven                     | High — parallax, scroll-triggered reveals, glitch effects    | Bold primaries, artistic freedom. Dark or light         | Bold, expressive, variable fonts. Pairing `F-08` or `F-12`       | Case studies, portfolio showcase, storytelling           | Corporate minimalism, generic layouts, hidden work    |
| **Gaming / Entertainment**      | 3D + Retro-futurism                           | High — WebGL, particle effects, immersive transitions        | Vibrant + neon + dark backgrounds. Palette `P-12`       | Bold, impactful. Pairing `F-11` or `F-08`                        | Immersive experience, real-time stats, community         | Minimalist design, static assets, boring layouts      |
| **Music / Podcast Platform**    | Dark OLED + Vibrant accents                   | High — waveform visualization, playlist animations           | Palette `P-12`. Dark bg + vibrant accent from album art | Modern, bold. Pairing `F-10` or `F-11`                           | Audio player UX, episode discovery, waveform viz         | Cluttered layout, poor audio player, light mode only  |
| **Fashion / Luxury Brand**      | Liquid Glass + Storytelling                   | High — slow parallax (400-600ms), premium reveals            | Black + gold/silver + minimal. Palette `P-04`           | Elegant, refined serif + clean sans. Pairing `F-01`              | High-quality imagery, storytelling, immersive experience | Cheap visuals, fast animations, generic templates     |
| **Event / Conference**          | Vibrant + Countdown-driven                    | High — countdown timer, speaker reveals, schedule animations | Palette `P-06`. Event theme colors + excitement accents | Bold, engaging. Pairing `F-08` or `F-10`                         | Registration flow, agenda, speakers, countdown           | Confusing registration, no countdown, hidden speakers |
| **Landing Page (Marketing)**    | Context-dependent — see `landing-patterns.md` | High — hero motion, scroll reveals, CTA animations           | Brand primary + high-contrast CTA accent                | Display font for headlines, clean body. Pairing `F-08` or `F-10` | Clear value prop, social proof, conversion-optimized CTA | Wall of text, no social proof, weak CTA hierarchy     |

---

## Palette IDs

Reference these in `typography-and-color.md` → "Industry Color Palettes" section:

| ID     | Name               | Best For                             |
| ------ | ------------------ | ------------------------------------ |
| `P-01` | SaaS Blue          | SaaS, B2B, productivity              |
| `P-02` | Fintech Dark       | Finance, crypto, trading             |
| `P-03` | Commerce Green     | E-commerce, marketplace              |
| `P-04` | Luxury Monochrome  | Fashion, luxury, premium             |
| `P-05` | Healthcare Calm    | Medical, health, wellness            |
| `P-06` | Education Vibrant  | Learning, courses, schools           |
| `P-07` | Government Neutral | Public service, legal, insurance     |
| `P-08` | Wellness Soft      | Spa, mental health, senior care      |
| `P-09` | Tech Indigo        | AI, developer tools, startups        |
| `P-10` | Hospitality Warm   | Restaurant, hotel, food service      |
| `P-11` | Professional Teal  | Real estate, consulting, B2B service |
| `P-12` | Entertainment Neon | Gaming, music, nightlife             |

## Font Pairing IDs

Reference these in `typography-and-color.md` → "Curated Font Pairings" section:

| ID     | Name                | Heading / Body                    |
| ------ | ------------------- | --------------------------------- |
| `F-01` | Classic Elegant     | Playfair Display / Source Sans 3  |
| `F-02` | Modern Professional | Poppins / Open Sans               |
| `F-03` | Tech Startup        | Sora / DM Sans                    |
| `F-04` | Editorial Clean     | Lora / Source Sans 3              |
| `F-05` | Corporate Authority | IBM Plex Sans / IBM Plex Serif    |
| `F-06` | Friendly Rounded    | Nunito / Lato                     |
| `F-07` | Warm Artisan        | Merriweather / Source Sans 3      |
| `F-08` | Bold Display        | Clash Display / General Sans      |
| `F-09` | Developer Mono      | JetBrains Mono / DM Sans          |
| `F-10` | Geometric Modern    | Outfit / DM Sans                  |
| `F-11` | Impact Heavy        | Big Shoulders Display / Work Sans |
| `F-12` | Creative Variable   | Bricolage Grotesque / Crimson Pro |
