# Visualization Bundle

The website visualizer must use the same rendering code as the Health.md Obsidian plugin.

## Source of truth

Plugin source lives at:

```text
/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md
```

The website bundle is generated from that plugin source:

```text
website/assets/healthmd-plugin-visualizations.js
```

Do **not** hand-edit `assets/healthmd-plugin-visualizations.js`. It is generated from the plugin's `src/canvas-utils.ts` and selected files under `src/visualizations/`.

## Regenerate the website visualizer

From `website/`:

```bash
npm run visualizations:bundle
```

This runs:

```bash
node scripts/build-plugin-visualizations.mjs
```

By default, the script reads from:

```text
/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md
```

To use a different checkout:

```bash
HEALTHMD_OBSIDIAN_PLUGIN_REPO=/path/to/obsidian-health-md npm run visualizations:bundle
```

## Required workflow for visualization changes

1. Make renderer/theme changes in the Obsidian plugin source first.
2. Build/test the plugin:

   ```bash
   cd /Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md
   npm run build
   ```

3. Regenerate the website bundle:

   ```bash
   cd /Users/codybontecou/projects/health-md/website
   npm run visualizations:bundle
   ```

4. Sanity-check the generated browser files:

   ```bash
   node --check assets/visualization-customizer.js
   node --check assets/healthmd-plugin-visualizations.js
   ```

## Theme handling

`website/assets/visualization-customizer.js` should call the bundled plugin `resolveTheme(...)` rather than maintaining separate website-only theme logic. The customizer supplies Obsidian-like body classes and CSS variables so the plugin renderer resolves colors the same way it does inside Obsidian.

If visualizations need new theme-aware colors, add them to the plugin source (`src/types.ts`, `src/canvas-utils.ts`, and the renderer) before regenerating the website bundle.

## Shareable SEO visualization URLs

The public Visualization Studio persists the selected data category, renderer, and palette in a crawlable URL:

```text
/visualizations/{data-filter}/{visualization-id}/{color-scheme}/
```

Example:

```text
/visualizations/activity-fitness/activity-rings/ocean-colors/
```

`assets/visualization-customizer.js` reads these path segments on load, applies them over any localStorage state, and updates the URL via `history.pushState` as users change controls. The base `/visualizations/` page still works as the generic studio entry point.

## Generate SEO pages

Static pages are generated for every supported visualization/color URL so link scrapers and search crawlers can read deterministic metadata without executing the app UI first:

```bash
cd website
npm run visualizations:seo
```

This runs:

```bash
node scripts/generate-visualization-pages.mjs
```

The generator:

- mirrors `visualizations/index.html` into nested route directories,
- injects visualization-specific `<title>`, canonical, description, Open Graph, Twitter, and JSON-LD metadata,
- points `og:image` / `twitter:image` to a matching generated visualization image when it exists,
- updates `sitemap.xml` with canonical `theme-colors` visualization URLs.

## Generate visualization Open Graph images

OG images are generated from the real bundled plugin renderer in a headless Chrome screenshot. The image template follows `DESIGN.md` and `design.dark.md`: neutral Geist surfaces, restrained borders/shadows, Geist typography, and Health.md purple accent. Do not add decorative gradients or glassmorphism unless the design docs change.

Generate one sample image for review:

```bash
cd website
npm run visualizations:og:sample
```

Generate a specific image:

```bash
node scripts/generate-visualization-og-image.mjs --viz sleep-schedule --colors aurora --theme dark
```

Generate the full current dark-theme set:

```bash
npm run visualizations:og
```

Current output shape:

```text
assets/visualization-og/{visualization-id}/{color-scheme}-dark-theme.png
```

Example:

```text
assets/visualization-og/activity-rings/ocean-colors-dark-theme.png
```

After changing the OG image design or generating new images, re-run `npm run visualizations:seo` so static pages pick up the correct meta image paths.
