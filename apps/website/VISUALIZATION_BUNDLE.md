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
