#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const websiteRoot = path.resolve(__dirname, "..");
const defaultPluginRepo = "/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md";
const pluginRepo = path.resolve(process.env.HEALTHMD_OBSIDIAN_PLUGIN_REPO || defaultPluginRepo);
const pluginSrc = path.join(pluginRepo, "src");
const outfile = path.join(websiteRoot, "assets", "healthmd-plugin-visualizations.js");


async function assertFile(file) {
  try {
    await fs.access(file);
  } catch (_error) {
    throw new Error(`Required plugin source file missing: ${file}`);
  }
}

function importPath(file) {
  return JSON.stringify(file);
}

async function loadEsbuild() {
  const require = createRequire(import.meta.url);
  const searchPaths = [websiteRoot, path.join(websiteRoot, "docs-src"), pluginRepo];
  for (const base of searchPaths) {
    try {
      const resolved = require.resolve("esbuild", { paths: [base] });
      return import(pathToFileURL(resolved).href);
    } catch (_error) {
      // Try the next install location.
    }
  }
  throw new Error("Could not find esbuild. Install it in website, website/docs-src, or the Obsidian plugin repo.");
}

await assertFile(path.join(pluginSrc, "canvas-utils.ts"));
await assertFile(path.join(pluginSrc, "visualizations", "index.ts"));

const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "healthmd-viz-bundle-"));
const entry = path.join(tmpDir, "healthmd-viz-entry.ts");
const sourceLabel = `${path.basename(pluginRepo)} src/visualizations`;
const importLines = [
  `import { COLOR_SCHEMES, resolveTheme } from ${importPath(path.join(pluginSrc, "canvas-utils.ts"))};`,
  `import { VISUALIZATIONS, HTML_VISUALIZATIONS } from ${importPath(path.join(pluginSrc, "visualizations", "index.ts"))};`,
];

await fs.writeFile(entry, `${importLines.join("\n")}

declare global {
  interface Window { HealthMdPluginVisualizations: unknown; }
}

window.HealthMdPluginVisualizations = {
  source: ${JSON.stringify(sourceLabel)},
  sourceRepo: ${JSON.stringify(pluginRepo)},
  generatedBy: "website/scripts/build-plugin-visualizations.mjs",
  colorSchemes: COLOR_SCHEMES,
  resolveTheme,
  renderers: VISUALIZATIONS,
  htmlRenderers: HTML_VISUALIZATIONS
};
`, "utf8");

const esbuild = await loadEsbuild();
await esbuild.build({
  entryPoints: [entry],
  bundle: true,
  outfile,
  format: "iife",
  platform: "browser",
  target: "es2018",
  legalComments: "none",
  sourcemap: false,
  logLevel: "silent",
  banner: {
    js: `// Generated from ${sourceLabel}. Do not edit directly.\n// Run: npm run visualizations:bundle`,
  },
});

await fs.rm(tmpDir, { recursive: true, force: true });
console.log(`Bundled plugin visualizations from ${pluginRepo}`);
console.log(`Wrote ${path.relative(websiteRoot, outfile)}`);
