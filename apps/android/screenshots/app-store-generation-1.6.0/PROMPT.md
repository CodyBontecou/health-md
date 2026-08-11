# Master prompt for ChatGPT image generation

Copy everything below into ChatGPT after attaching the eight PNGs from `source/`.

---

You are an expert mobile-app creative director producing a cohesive set of eight Google Play phone-listing screenshots for **Health.md**, an Android app that exports authorized Health Connect data into user-controlled files.

I have attached eight source screenshots named `01` through `08`. Treat each attached screenshot as an **immutable source layer**. Preserve the real app UI, wording, values, iconography, spacing, and controls exactly. Do not redraw, retype, translate, simplify, “improve,” or invent any part of the interface. You may crop and scale the screenshot cleanly and place it inside a realistic, minimal Android phone frame, but the UI pixels themselves must remain unchanged. If exact UI preservation is not possible, generate only the marketing background, frame, and headline area so I can composite the original screenshot afterward.

## Deliverables

Create eight separate images—not a collage—and work through them one at a time in the numbered order below. Start with image 1. When I say **NEXT**, generate the next image while preserving the same visual system.

For every image:

- Output a portrait **1080 × 1920 PNG** at a 9:16 ratio.
- Keep the final file below 8 MB.
- Leave generous safe margins around all copy.
- Use one short headline and, where specified, one short supporting line.
- Keep every headline legible at small Google Play carousel size.
- Show the attached source screenshot prominently, not as a tiny decorative element.
- Do not add ratings, awards, download counts, prices, Google Play badges, testimonials, or unsupported claims.
- Do not use stock people, generic medical photography, ECG lines, red medical crosses, or clinical/diagnostic imagery.
- Do not imply that Health.md diagnoses, treats, monitors emergencies, or stores health records in a Health.md cloud.

## Visual direction

Build a premium, restrained system inspired by Health.md’s existing interface:

- warm off-white backgrounds
- near-black typography
- Health.md purple sampled from the attached UI
- subtle geometric facets inspired by the purple gem app icon
- faint grids, file paths, data points, or document shapes where useful
- clean, neutral, Geist-like sans-serif typography
- minimal shadows and tasteful depth
- no loud gradients, neon glow, clutter, or generic “AI app” styling

Keep the eight images clearly related, but vary the composition for rhythm: alternate centered, left-weighted, and right-weighted phone placement; use occasional close crops for detail screens; and reserve the strongest, simplest composition for image 1.

Use the exact product spelling **Health.md**.

## Screenshot sequence and exact copy

### 1. `01-core-export.png` → `01-your-health-data-your-files.png`

**Headline:** Your health data. Your files.

**Supporting line:** Export authorized Health Connect records into files you control.

Make this the hero image. Emphasize the connected export configuration and make the value understandable immediately.

### 2. `02-export-formats.png` → `02-export-your-way.png`

**Headline:** Export your way

**Supporting line:** Markdown, Obsidian Bases, JSON and CSV.

Crop and position the real screen so the export-format choices are the visual focus.

### 3. `03-health-metrics.png` → `03-choose-100-plus-metrics.png`

**Headline:** Choose from 100+ health metrics

**Supporting line:** Sleep, activity, heart, vitals, nutrition and more.

Keep the `106/106` metric count and real category controls visible. Do not fabricate additional categories.

### 4. `04-private-by-design.png` → `04-private-by-design.png`

**Headline:** Read-only. Private by design.

**Supporting line:** No account. No Health.md health-data cloud.

Use the quietest, most trust-focused composition. Reinforce user control without adding locks, shields, or security certifications that are not present in the source.

### 5. `05-scheduled-exports.png` → `05-keep-your-archive-current.png`

**Headline:** Keep your archive current

**Supporting line:** Schedule exports to your selected destination.

Highlight the enabled schedule and next-export information. Do not call it real-time syncing.

### 6. `06-file-preview.png` → `06-preview-before-export.png`

**Headline:** Preview before you export

**Supporting line:** See filenames, paths and content before anything is written.

Favor a closer crop so the real Markdown preview remains readable.

### 7. `07-home-screen-widgets.png` → `07-health-at-a-glance.png`

**Headline:** Health at a glance

**Supporting line:** Activity, sleep, heart and summary widgets.

Preserve the Android widget-picker previews exactly. You may frame the four widget choices as a coordinated feature family, but do not invent widget values or layouts.

### 8. `08-direct-cli.png` → `08-direct-to-your-computer.png`

**Headline:** Direct to your computer

**Supporting line:** Pair with the Health.md CLI for authenticated, encrypted exports with no cloud relay.

Give this image a slightly more technical feel while retaining the same visual system. Keep the real pairing screen and terminal command visible.

## Accuracy rules

These claims are allowed and should be expressed only as written above:

- Health.md reads authorized Health Connect data for export.
- Health Connect access is read-only.
- Health.md supports more than 100 metrics in the current app.
- Health.md does not require an account or operate a Health.md health-data cloud.
- Users can explicitly choose local folders, API endpoints, or a paired Direct CLI destination.
- Scheduled exports are not real-time and can be delayed by Android or device/network availability.
- The Direct CLI path uses an authenticated, encrypted connection with no cloud relay.

Do not introduce any new product claims beyond this list.

First, briefly confirm that you understand the immutable-UI requirement and the shared visual direction. Then generate **image 1 only**. Wait for me to say **NEXT** before generating image 2.

---

## Optional alternate for image 8

If I attach `alternates/08-raw-snapshot.png` instead of the Direct CLI screenshot, use:

**Headline:** Preserve every available field

**Supporting line:** Create API-complete JSON or NDJSON snapshots from supported authorized records.
