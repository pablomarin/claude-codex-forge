# Media Assets

Real images make or break a website. Placeholder boxes and gray rectangles signal "unfinished". Use stock photos and AI-generated imagery during development — not after.

## Stock Photography (Pexels / Unsplash MCP)

When an MCP server for stock photos is available, use it proactively:

- **Search contextually** — don't use generic keywords. Instead of "office", use "modern tech startup office Austin Texas" or "diverse team whiteboard brainstorming"
- **Match the aesthetic** — dark mode site? Search for moody, low-key photography. Bright SaaS? Search for well-lit, clean compositions
- **People add credibility** — team photos, founder portraits, and candid work shots signal authenticity. Prefer authentic-looking over staged corporate
- **Download and place immediately** — save to `public/images/` and use the actual path in your components. Never use external URLs for production images
- **Attribution** — Unsplash and Pexels may require attribution. Include photographer credit in a credits section or page footer (NOT in alt text — alt text is for accessibility descriptions only)

## AI Image Generation (Gemini API)

Activate the Forge generate-image skill when it is available to create custom images through an approved provider. It verifies the provider contract for the run and saves the resulting asset in the project.

When generating images:

### Prompting Best Practices

1. **Be specific in one sentence** — include style, mood, colors, composition:
   - Good: `"minimal SaaS dashboard UI mockup, dark theme, purple accent, clean data visualization"`
   - Bad: `"dashboard"`

2. **Name the style explicitly**:
   - `"editorial photography"` — magazine-quality, dramatic lighting
   - `"flat illustration"` — clean vector-like, modern SaaS
   - `"3D render"` — depth, materials, shadows
   - `"cinematic"` — film color grading, wide aspect ratio
   - `"Linear-style aesthetic"` — reference specific products for style

3. **Add "no text"** when you don't want rendered text in the image (text rendering is good but may not match your fonts)

4. **Specify aspect ratio in the prompt** — say "wide banner" or "vertical mobile" alongside any aspect ratio flags

5. **Use reference images for brand consistency** — pass existing brand assets as references to maintain visual coherence across generated images

### Common Image Sizes

| Use Case                 | Dimensions | Aspect Ratio | Notes                    |
| ------------------------ | ---------- | ------------ | ------------------------ |
| Hero banner (desktop)    | 1920x1080  | 16:9         | Full-width hero section  |
| Blog featured / OG image | 1200x630   | ~1.9:1       | Social media preview     |
| Square social            | 1080x1080  | 1:1          | Instagram, LinkedIn      |
| YouTube thumbnail        | 1280x720   | 16:9         | Video preview            |
| Twitter/X header         | 1500x500   | 3:1          | Wide banner              |
| Vertical story / mobile  | 1080x1920  | 9:16         | Instagram/TikTok stories |
| Team member photo        | 400x400    | 1:1          | Avatar / headshot        |
| Product screenshot       | 1200x900   | 4:3          | Feature showcase         |

### Transparent Assets

For icons, logos, or mascots that need transparency:

- Prompt with: `"[subject]. Place on a solid bright green background (#00FF00). The background must be a single flat green color with no gradients or shadows."`
- Process with FFmpeg or image tool to remove green background
- Save as PNG with alpha channel

### Output Directly to Project

Save generated images directly into the project's public directory:

- Next.js: `public/images/` → reference as `/images/filename.png`
- Astro/Vite: `public/images/` or `src/assets/`
- Name descriptively: `hero-landing.png`, `team-brainstorm.jpg`, not `image1.png`

## Image Optimization

Every image on the page should be optimized:

- **Format**: WebP for photos (80% quality), AVIF where supported, PNG only for transparency
- **Responsive `srcset`**: Provide 1x, 2x sizes minimum. Use `<picture>` for format fallbacks:
  ```html
  <picture>
    <source srcset="hero.avif" type="image/avif" />
    <source srcset="hero.webp" type="image/webp" />
    <img
      src="hero.jpg"
      alt="Description"
      width="1920"
      height="1080"
      loading="lazy"
    />
  </picture>
  ```
- **Explicit dimensions**: Always set `width` and `height` to prevent layout shift (CLS)
- **Lazy loading**: `loading="lazy"` on all below-fold images. Hero image should be `loading="eager"` or use `priority` in Next.js
- **Compression**: Target 80-85% quality for JPEG/WebP. Use Sharp, Squoosh, or image optimizer MCP if available

## Video

For hero background videos or product demos:

- **Stock video**: Pexels MCP supports video search — use for ambient backgrounds (tech, nature, abstract)
- **Format**: MP4 (H.264) for compatibility, WebM for smaller size. Provide both:
  ```html
  <video autoplay muted loop playsinline>
    <source src="hero-bg.webm" type="video/webm" />
    <source src="hero-bg.mp4" type="video/mp4" />
  </video>
  ```
- **Performance**: Keep under 5MB, 720p max for backgrounds, shorter is better (5-15 seconds loop)
- **Always `muted`** for autoplay (browsers block unmuted autoplay)
- **Poster image**: Set `poster="hero-poster.jpg"` for the first frame while loading
- **Fallback**: Show a static image for users with `prefers-reduced-motion`

## When Real Photos Aren't Available

If no stock photo MCP or image generator is available, at minimum:

- Use SVG illustrations (hand-drawn style, not clipart)
- Use CSS gradients and patterns as image placeholders
- Use Lottie animations for hero sections instead of static images
- Add clear `TODO` comments marking where real images should be placed
- **Never ship gray placeholder rectangles to production**

---

## Platform Size Reference

Exact dimensions for social media, banners, and sharing assets. Sizes change — verify against official platform docs if in doubt.

> Last reviewed: 2026-03-12

### Social Media Posts

| Platform  | Type            | Size (px)                  | Aspect Ratio |
| --------- | --------------- | -------------------------- | ------------ |
| Instagram | Post (square)   | 1080 x 1080                | 1:1          |
| Instagram | Post (portrait) | 1080 x 1350                | 4:5          |
| Instagram | Story / Reel    | 1080 x 1920                | 9:16         |
| Instagram | Carousel        | 1080 x 1080 or 1080 x 1350 | 1:1 or 4:5   |
| Facebook  | Post            | 1200 x 630                 | ~1.9:1       |
| Facebook  | Story           | 1080 x 1920                | 9:16         |
| Twitter/X | Post            | 1200 x 675                 | 16:9         |
| LinkedIn  | Post            | 1200 x 627                 | ~1.9:1       |
| Pinterest | Pin             | 1000 x 1500                | 2:3          |
| TikTok    | Video           | 1080 x 1920                | 9:16         |
| YouTube   | Thumbnail       | 1280 x 720                 | 16:9         |
| Threads   | Post            | 1080 x 1080                | 1:1          |

### Profile & Cover Images

| Platform  | Type            | Size (px)                                  |
| --------- | --------------- | ------------------------------------------ |
| Facebook  | Cover           | 851 x 315                                  |
| Facebook  | Profile         | 320 x 320                                  |
| Twitter/X | Header          | 1500 x 500                                 |
| Twitter/X | Profile         | 400 x 400                                  |
| LinkedIn  | Personal banner | 1584 x 396                                 |
| LinkedIn  | Company banner  | 1128 x 191                                 |
| YouTube   | Channel art     | 2560 x 1440 (safe area: 1546 x 423 center) |

### OG / Sharing Assets (REQUIRED — see `polish-checklist.md` Section 9)

| Asset           | Size (px)  | Format | Location                      |
| --------------- | ---------- | ------ | ----------------------------- |
| OpenGraph image | 1200 x 630 | PNG    | `src/app/opengraph-image.png` |
| Favicon         | 48 x 48    | ICO    | `src/app/favicon.ico`         |
| SVG icon        | scalable   | SVG    | `src/app/icon.svg`            |
| Apple icon      | 180 x 180  | PNG    | `src/app/apple-icon.png`      |

### Ad Banners

| Platform          | Type             | Size (px)   |
| ----------------- | ---------------- | ----------- |
| Google Ads        | Medium Rectangle | 300 x 250   |
| Google Ads        | Leaderboard      | 728 x 90    |
| Google Ads        | Large Rectangle  | 336 x 280   |
| Google Ads        | Wide Skyscraper  | 160 x 600   |
| Facebook/Meta Ads | Feed             | 1200 x 628  |
| Facebook/Meta Ads | Story            | 1080 x 1920 |

### Website

| Use                | Size (px)       | Notes                   |
| ------------------ | --------------- | ----------------------- |
| Hero (desktop)     | 1920 x 600–1080 | Full-width, responsive  |
| Hero (mobile)      | 750 x 1334      | iPhone viewport         |
| Feature screenshot | 1200 x 900      | 4:3, product showcase   |
| Team photo         | 400 x 400       | Square, avatar/headshot |
| Blog featured      | 1200 x 630      | Doubles as OG image     |

### Print (if needed)

- **Business card**: 1050 x 600 px (3.5 x 2 inches at 300 DPI)
- **A4 flyer**: 2480 x 3508 px (210 x 297 mm at 300 DPI)
- **Poster A3**: 3508 x 4961 px (297 x 420 mm at 300 DPI)
- Always use **CMYK** color space and **3-5mm bleed** for print
