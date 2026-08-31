---
name: generate-image
description: >
  Generate AI images using Google's Gemini API. Use when the user asks to
  create, generate, make, or design any image, illustration, icon, hero
  banner, thumbnail, or visual asset. Also use when building UI that needs
  real images instead of placeholders.
---

# Generate Image via Gemini API

> Generate production-quality images using Google's Gemini image generation models.

## Prerequisites

1. **API Key**: User must have `GEMINI_API_KEY` set as environment variable.
   Get one free at [aistudio.google.com](https://aistudio.google.com) → "Get API Key".

2. **Node.js**: Required for running the generation script. (Python also works — see alternative below.)

3. **@google/genai SDK**: Install in the project if not present:
   ```bash
   npm install @google/genai   # or: pnpm add @google/genai
   ```

## Before Generating: Check Current API Docs

**IMPORTANT**: Model IDs change frequently. Before writing the generation script,
fetch the latest official documentation to confirm the current model ID and API format:

Use an available documentation source to inspect
`https://ai.google.dev/gemini-api/docs/image-generation`, or ask the user to
provide the current provider documentation when browsing is unavailable. Record the
model ID and response format actually verified for the run.

As of the last update, the models are:

- `gemini-3.1-flash-image-preview` — fast, high-volume (recommended default)
- `gemini-3-pro-image-preview` — highest quality, professional assets
- `gemini-2.5-flash-image` — older stable model

**Always verify these are still current before generating.**

## Generation Script (Node.js)

Create a temporary script, run it, then clean up. Adapt the model ID based on the docs check above.

```javascript
// generate-image.mjs — run with: node generate-image.mjs "prompt" [options]
import { GoogleGenAI } from "@google/genai";
import { writeFileSync } from "fs";
import { resolve } from "path";

const prompt = process.argv[2];
const outputPath = process.argv[3] || "generated-image.png";
const aspectRatio = process.argv[4] || "16:9";
const imageSize = process.argv[5] || "1K";

if (!prompt) {
  console.error(
    'Usage: node generate-image.mjs "prompt" [output.png] [aspectRatio] [imageSize]',
  );
  process.exit(1);
}

if (!process.env.GEMINI_API_KEY) {
  console.error("Error: GEMINI_API_KEY environment variable not set.");
  console.error("Get a free key at: https://aistudio.google.com");
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// IMPORTANT: verify this model ID is current by checking
// https://ai.google.dev/gemini-api/docs/image-generation
const MODEL = "gemini-3.1-flash-image-preview";

try {
  const response = await ai.models.generateContent({
    model: MODEL,
    contents: prompt,
    config: {
      responseModalities: ["IMAGE"],
      imageConfig: {
        aspectRatio: aspectRatio,
        imageSize: imageSize,
      },
    },
  });

  const parts = response.candidates?.[0]?.content?.parts || [];
  const imagePart = parts.find((p) =>
    p.inlineData?.mimeType?.startsWith("image/"),
  );

  if (!imagePart) {
    console.error(
      "No image in response. The model may have returned text instead.",
    );
    const textPart = parts.find((p) => p.text);
    if (textPart) console.error("Model said:", textPart.text);
    process.exit(1);
  }

  const buffer = Buffer.from(imagePart.inlineData.data, "base64");
  const fullPath = resolve(outputPath);
  writeFileSync(fullPath, buffer);
  console.log(`Image saved: ${fullPath} (${buffer.length} bytes)`);
} catch (err) {
  console.error("Generation failed:", err.message || err);
  process.exit(1);
}
```

## Alternative: Python Script

If the project uses Python instead of Node.js:

```python
# generate_image.py — run with: python generate_image.py "prompt" [output.png] [aspect] [size]
import sys, os, base64
from google import genai
from google.genai import types

prompt = sys.argv[1] if len(sys.argv) > 1 else None
output = sys.argv[2] if len(sys.argv) > 2 else "generated-image.png"
aspect = sys.argv[3] if len(sys.argv) > 3 else "16:9"
size = sys.argv[4] if len(sys.argv) > 4 else "1K"

if not prompt:
    print("Usage: python generate_image.py 'prompt' [output.png] [aspect] [size]")
    sys.exit(1)

client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))
response = client.models.generate_content(
    model="gemini-3.1-flash-image-preview",
    contents=prompt,
    config=types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(aspect_ratio=aspect, image_size=size),
    ),
)

for part in response.candidates[0].content.parts:
    if hasattr(part, "inline_data") and part.inline_data:
        img_bytes = base64.b64decode(part.inline_data.data)
        with open(output, "wb") as f:
            f.write(img_bytes)
        print(f"Image saved: {os.path.abspath(output)} ({len(img_bytes)} bytes)")
        break
```

## Workflow

1. **Check docs** — inspect the official Gemini image generation page to confirm model ID
2. **Check prerequisites** — verify `GEMINI_API_KEY` is set and SDK is installed
3. **Write the script** — create a temporary `.mjs` or `.py` file based on the template above, using the verified model ID
4. **Run it** — execute with the user's prompt, desired output path, aspect ratio, and size
5. **Verify** — confirm the image file was created and is valid
6. **Clean up** — delete the temporary script (keep the generated image)
7. **Integrate** — move/reference the image in the project (e.g., `public/images/hero.png`)

## Common Image Sizes

| Use Case       | Aspect Ratio | Size | Example Output                                                       |
| -------------- | ------------ | ---- | -------------------------------------------------------------------- |
| Hero banner    | 16:9         | 2K   | `node generate-image.mjs "prompt" public/images/hero.png 16:9 2K`    |
| Blog/OG image  | 16:9         | 1K   | `node generate-image.mjs "prompt" public/images/og.png 16:9 1K`      |
| Square social  | 1:1          | 1K   | `node generate-image.mjs "prompt" public/images/social.png 1:1 1K`   |
| Vertical story | 9:16         | 1K   | `node generate-image.mjs "prompt" public/images/story.png 9:16 1K`   |
| Team headshot  | 1:1          | 1K   | `node generate-image.mjs "prompt" public/images/headshot.png 1:1 1K` |
| Icon/logo      | 1:1          | 512  | `node generate-image.mjs "prompt" public/images/icon.png 1:1 512`    |

## Prompting Tips

1. **Be specific in one sentence** — style, mood, colors, composition:
   - Good: `"minimal SaaS dashboard UI mockup, dark theme, purple accent, clean data visualization, no text"`
   - Bad: `"dashboard"`

2. **Name the style**: `"editorial photography"`, `"flat illustration"`, `"3D render"`, `"cinematic"`, `"watercolor"`

3. **Add "no text"** when you don't want rendered text in the image

4. **Reference real products for style**: `"Linear-style aesthetic"`, `"Stripe.com hero feel"`, `"Apple product page style"`

5. **For transparent assets**: Prompt with `"[subject] on solid bright green background (#00FF00), flat green, no gradients"` then process with an image tool to remove background

## Error Handling

| Error                              | Cause                            | Fix                                         |
| ---------------------------------- | -------------------------------- | ------------------------------------------- |
| `GEMINI_API_KEY not set`           | Missing env var                  | `export GEMINI_API_KEY="your-key"`          |
| `models/... is not found`          | Model ID deprecated              | Re-check the official docs, update model ID |
| `No image in response`             | Prompt may violate safety policy | Simplify prompt, remove sensitive content   |
| `Cannot find module @google/genai` | SDK not installed                | `npm install @google/genai`                 |
| `quota exceeded`                   | Rate limit hit                   | Wait or switch to a different model tier    |
