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
const bundleOutfile = path.join(websiteRoot, "assets", "healthmd-plugin-visualizations.js");
const catalogOutfile = path.join(websiteRoot, "assets", "visualizations-catalog.json");
const pluginCssOutfile = path.join(websiteRoot, "assets", "healthmd-plugin-visualizations.css");
const sourceRepository = "https://github.com/CodyBontecou/health-md-visualizations";

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

function obsidianStubPlugin() {
  return {
    name: "healthmd-visualization-catalog-obsidian-stub",
    setup(build) {
      build.onResolve({ filter: /^obsidian$/ }, () => ({ path: "obsidian", namespace: "healthmd-stub" }));
      build.onLoad({ filter: /.*/, namespace: "healthmd-stub" }, () => ({
        loader: "js",
        contents: `
export class App {}
export class Editor {}
export class Modal {}
export class Notice {}
export class Setting {}
export class SuggestModal extends Modal {}
`,
      }));
    },
  };
}

function extractObjectKeys(source, exportName) {
  const declaration = source.indexOf(`export const ${exportName}`);
  if (declaration < 0) throw new Error(`Could not find plugin export ${exportName}`);
  const open = source.indexOf("{", declaration);
  const close = source.indexOf("\n};", open);
  if (open < 0 || close < 0) throw new Error(`Could not parse plugin export ${exportName}`);
  return Array.from(source.slice(open + 1, close).matchAll(/^[\t ]*"([^"]+)"\s*:/gm), (match) => match[1]);
}

function extractSetValues(source, exportName) {
  const declaration = source.indexOf(`export const ${exportName}`);
  if (declaration < 0) throw new Error(`Could not find plugin export ${exportName}`);
  const end = source.indexOf(";", declaration);
  const body = source.slice(declaration, end);
  return Array.from(body.matchAll(/"([^"]+)"/g), (match) => match[1]);
}

async function normalizeSourceMap(mapfile) {
  const sourceMap = JSON.parse(await fs.readFile(mapfile, "utf8"));
  sourceMap.sources = sourceMap.sources.map((source) => {
    const normalized = source.replaceAll("\\", "/");
    const leafletMarker = "/node_modules/leaflet/";
    if (normalized.includes(leafletMarker)) {
      return `https://github.com/Leaflet/Leaflet/blob/v1.9.4/${normalized.split(leafletMarker)[1]}`;
    }
    if (normalized.endsWith("/healthmd-viz-entry.ts")) return "healthmd-generated-entry.ts";
    const srcMarker = "/src/";
    if (normalized.includes(srcMarker)) {
      return `${sourceRepository}/blob/main/src/${normalized.split(srcMarker).slice(1).join("/src/")}`;
    }
    return normalized;
  });
  const localPluginPath = pluginRepo.replaceAll("\\", "/");
  sourceMap.sourcesContent = sourceMap.sourcesContent?.map((content, index) => {
    if (typeof content !== "string" || sourceMap.sources[index] !== "healthmd-generated-entry.ts") return content;
    return content.replaceAll(pluginRepo, sourceRepository).replaceAll(localPluginPath, sourceRepository);
  });
  await fs.writeFile(mapfile, `${JSON.stringify(sourceMap, null, 2)}\n`, "utf8");
}

async function generatedPluginCss() {
  const source = await fs.readFile(path.join(pluginRepo, "styles.css"), "utf8");
  const startMarker = "/* Schema v7 roll-up and medication insight views */";
  const endMarker = "/* Source data viewer (JSON/CSV opened from chart data points) */";
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0) throw new Error("Could not find plugin visualization insight CSS markers");
  return `/* Generated from health-md-visualizations/styles.css. Do not edit directly. */
.html-preview {
  --background-modifier-border: var(--color-gray-alpha-300);
  --interactive-accent: var(--color-tertiary);
  --text-muted: var(--color-secondary);
  --radius-m: var(--radius-md);
}
${source.slice(start, end).trim()}\n`;
}

async function loadPluginMetadata(esbuild, tmpDir) {
  const entry = path.join(tmpDir, "healthmd-viz-metadata-entry.ts");
  const outfile = path.join(tmpDir, "healthmd-viz-metadata.mjs");
  await fs.writeFile(entry, `
import { VISUALIZATION_CATALOG, VISUALIZATION_CATEGORIES } from ${importPath(path.join(pluginSrc, "insert-wizard.ts"))};

export const pluginMetadata = {
  categories: VISUALIZATION_CATEGORIES,
  catalog: VISUALIZATION_CATALOG,
};
`, "utf8");

  await esbuild.build({
    entryPoints: [entry],
    bundle: true,
    outfile,
    format: "esm",
    platform: "node",
    target: "node20",
    legalComments: "none",
    logLevel: "silent",
    treeShaking: true,
    plugins: [obsidianStubPlugin()],
  });
  const imported = await import(`${pathToFileURL(outfile).href}?v=${Date.now()}`);
  const registrySource = await fs.readFile(path.join(pluginSrc, "visualizations", "index.ts"), "utf8");
  const canvasRendererIds = extractObjectKeys(registrySource, "VISUALIZATIONS");
  const htmlRendererIds = extractObjectKeys(registrySource, "HTML_VISUALIZATIONS");
  const rollupOnlyIds = extractSetValues(registrySource, "ROLLUP_ONLY_VISUALIZATIONS");
  const canvasIds = new Set(canvasRendererIds);
  const htmlIds = new Set(htmlRendererIds);
  return {
    ...imported.pluginMetadata,
    catalog: imported.pluginMetadata.catalog.map((item) => ({
      ...item,
      renderer: htmlIds.has(item.type) ? "html" : canvasIds.has(item.type) ? "canvas" : undefined,
    })),
    canvasRendererIds,
    htmlRendererIds,
    rollupOnlyIds,
  };
}

await Promise.all([
  assertFile(path.join(pluginRepo, "styles.css")),
  assertFile(path.join(pluginSrc, "canvas-utils.ts")),
  assertFile(path.join(pluginSrc, "insert-wizard.ts")),
  assertFile(path.join(pluginSrc, "parsers", "json-parser.ts")),
  assertFile(path.join(pluginSrc, "parsers", "rollup-parser.ts")),
  assertFile(path.join(pluginSrc, "visualizations", "index.ts")),
]);

const esbuild = await loadEsbuild();
const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "healthmd-viz-bundle-"));

try {
  const metadata = await loadPluginMetadata(esbuild, tmpDir);
  const missingRenderers = metadata.catalog.filter((item) => !item.renderer).map((item) => item.type);
  if (missingRenderers.length) {
    throw new Error(`Plugin catalog entries are missing renderers: ${missingRenderers.join(", ")}`);
  }
  const duplicateIds = metadata.catalog
    .map((item) => item.type)
    .filter((id, index, all) => all.indexOf(id) !== index);
  if (duplicateIds.length) {
    throw new Error(`Plugin catalog contains duplicate visualization ids: ${Array.from(new Set(duplicateIds)).join(", ")}`);
  }

  const generatedCatalog = {
    schema: "healthmd.visualization_catalog",
    schemaVersion: 1,
    sourceRepository,
    categories: metadata.categories,
    visualizations: metadata.catalog,
    rollupOnlyIds: metadata.rollupOnlyIds,
  };
  await Promise.all([
    fs.writeFile(catalogOutfile, `${JSON.stringify(generatedCatalog, null, 2)}\n`, "utf8"),
    fs.writeFile(pluginCssOutfile, await generatedPluginCss(), "utf8"),
  ]);

  const entry = path.join(tmpDir, "healthmd-viz-entry.ts");
  const sourceLabel = "health-md-visualizations src/visualizations";
  await fs.writeFile(entry, `
import { COLOR_SCHEMES, resolveTheme } from ${importPath(path.join(pluginSrc, "canvas-utils.ts"))};
import { parseJSON } from ${importPath(path.join(pluginSrc, "parsers", "json-parser.ts"))};
import { parseRollupJSON } from ${importPath(path.join(pluginSrc, "parsers", "rollup-parser.ts"))};
import { VISUALIZATIONS, HTML_VISUALIZATIONS } from ${importPath(path.join(pluginSrc, "visualizations", "index.ts"))};

declare global {
  interface Window { HealthMdPluginVisualizations: unknown; }
}

window.HealthMdPluginVisualizations = {
  source: ${JSON.stringify(sourceLabel)},
  sourceRepo: ${JSON.stringify(sourceRepository)},
  generatedBy: "website/scripts/build-plugin-visualizations.mjs",
  colorSchemes: COLOR_SCHEMES,
  resolveTheme,
  renderers: VISUALIZATIONS,
  htmlRenderers: HTML_VISUALIZATIONS,
  parseHealthDay: (value: unknown) => parseJSON(typeof value === "string" ? value : JSON.stringify(value)),
  parseRollup: (value: unknown) => parseRollupJSON(typeof value === "string" ? value : JSON.stringify(value)),
  categories: ${JSON.stringify(metadata.categories)},
  catalog: ${JSON.stringify(metadata.catalog)},
  rollupOnlyIds: ${JSON.stringify(metadata.rollupOnlyIds)}
};
`, "utf8");

  await esbuild.build({
    entryPoints: [entry],
    bundle: true,
    outfile: bundleOutfile,
    format: "iife",
    platform: "browser",
    target: "es2018",
    legalComments: "none",
    minify: true,
    sourcemap: true,
    logLevel: "silent",
    banner: {
      js: `// Generated from ${sourceLabel}. Do not edit directly.\n// Run: npm run visualizations:bundle`,
    },
  });
  await normalizeSourceMap(`${bundleOutfile}.map`);

  console.log(`Bundled ${metadata.catalog.length} plugin visualizations from ${pluginRepo}`);
  console.log(`Wrote ${path.relative(websiteRoot, bundleOutfile)}`);
  console.log(`Wrote ${path.relative(websiteRoot, catalogOutfile)}`);
  console.log(`Wrote ${path.relative(websiteRoot, pluginCssOutfile)}`);
} finally {
  await fs.rm(tmpDir, { recursive: true, force: true });
}
