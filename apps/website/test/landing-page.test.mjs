import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const index = await readFile(path.join(ROOT, "index.html"), "utf8");
const styles = await readFile(path.join(ROOT, "assets/landing.css"), "utf8");
const script = await readFile(path.join(ROOT, "assets/landing.js"), "utf8");
const threeScript = await readFile(path.join(ROOT, "assets/landing-three.js"), "utf8");
const buildScript = await readFile(path.join(ROOT, "scripts/build-site.mjs"), "utf8");
const packageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));
const docsConfig = await readFile(path.join(ROOT, "docs-src/astro.config.mjs"), "utf8");
const docsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/healthmd.css"), "utf8");
const agentDocsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/agent-first.css"), "utf8");
const docsIndex = await readFile(path.join(ROOT, "docs-src/src/content/docs/index.md"), "utf8");
const configurationGuide = await readFile(path.join(ROOT, "docs-src/src/content/docs/configuration.md"), "utf8");
const docsHeader = await readFile(path.join(ROOT, "docs-src/src/components/HeaderLinks.astro"), "utf8");
const lightThemeProvider = await readFile(path.join(ROOT, "docs-src/src/components/LightThemeProvider.astro"), "utf8");
const verticalTablesScript = await readFile(path.join(ROOT, "docs-src/public/vertical-tables.js"), "utf8");

test("landing page makes the private automation bridge the only message", () => {
  assert.match(index, /The Private Bridge Between Health Data and Automation/);
  assert.match(index, /Health data<br><em>in motion\.<\/em>/);
  assert.match(index, /A private bridge from Apple Health and Health Connect to your files, scripts, and agents/);
  assert.match(index, /No Health\.md cloud\. Your data stays under your control\./);
  assert.match(index, /data-strand-canvas/);
  assert.equal((index.match(/<main>/g) ?? []).length, 1);
  assert.equal((index.match(/<section/g) ?? []).length, 1);
  assert.doesNotMatch(index, /id="bridge"|id="automation"|id="interfaces"|id="download"/);
  assert.doesNotMatch(index, /<footer/);
});

test("landing experience is locked to one viewport with a docs-only header", () => {
  assert.match(index, /<nav class="header-nav" aria-label="Documentation">/);
  assert.match(index, /<a class="header-docs-link" href="docs\/">\s*Docs/);
  assert.doesNotMatch(index, /data-menu-toggle|primary-navigation|hero-meta|hero-route|brand-mode/);
  assert.match(styles, /html,\s*\nbody\s*{[\s\S]*?overflow:\s*hidden/);
  assert.match(styles, /main,\s*\n\.hero\s*{[\s\S]*?height:\s*100svh/);
  assert.match(styles, /\.hero-copy\s*{[\s\S]*?backdrop-filter:\s*none/);
});

test("hero uses official store badges with direct marketplace links", () => {
  const actions = index.match(/<div class="hero-actions"[\s\S]*?<\/div>/)?.[0] ?? "";
  assert.equal((actions.match(/<a /g) ?? []).length, 2);
  assert.match(actions, /href="https:\/\/apps\.apple\.com\/us\/app\/health-md\/id6757763969"/);
  assert.match(actions, /href="https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.healthmd\.android"/);
  assert.match(actions, /assets\/store-badges\/download-on-app-store\.svg/);
  assert.match(actions, /assets\/store-badges\/get-it-on-google-play\.png/);
  assert.match(styles, /\.hero-store-badge-apple\s*{[\s\S]*?width:\s*135px;[\s\S]*?height:\s*45px/);
  assert.match(styles, /\.hero-store-badge-google\s*{[\s\S]*?width:\s*151px;[\s\S]*?height:\s*45px/);
});

test("hero DNA has projected depth and B-DNA-inspired Canvas fallback geometry", () => {
  assert.match(script, /fullGeometry/);
  assert.match(script, /grooveOffset:\s*Math\.PI \* 0\.86/);
  assert.match(script, /geometry\.pitch \/ 10\.5/);
  assert.match(script, /items\.sort/);
  assert.match(script, /kind:\s*"rung"/);
  assert.match(script, /kind:\s*"backbone"/);
  assert.match(script, /colorA:\s*"#dcdcd8"/);
});

test("hero upgrades to a locally served Three.js molecular scene", () => {
  assert.match(index, /<script type="module" src="assets\/landing-three\.js"><\/script>/);
  assert.match(index, /data-three-strand/);
  assert.match(threeScript, /THREE\.WebGLRenderer/);
  assert.match(threeScript, /THREE\.PerspectiveCamera/);
  assert.match(threeScript, /THREE\.TubeGeometry/);
  assert.match(threeScript, /THREE\.CylinderGeometry/);
  assert.match(threeScript, /pitch \/ 10\.5/);
  assert.match(threeScript, /group\.rotation\.x/);
  assert.match(threeScript, /rotation = time \* 0\.00017/);
  assert.match(threeScript, /THREE\.Fog\(0xf6f6f2/);
  assert.match(threeScript, /THREE\.MeshPhysicalMaterial/);
  assert.match(threeScript, /pairSequence/);
  assert.match(threeScript, /hydrogenMaterial/);
  assert.match(threeScript, /baseRadius = narrow \? 0\.016 : 0\.019/);
  assert.equal(packageJson.dependencies.three, "^0.185.1");
  assert.match(buildScript, /three\.module\.min\.js/);
  assert.match(buildScript, /three\.core\.min\.js/);
  assert.match(buildScript, /three\.LICENSE\.txt/);
});

test("landing page keeps a restrained light design with the real app icon", () => {
  assert.match(styles, /color-scheme:\s*light/);
  assert.match(styles, /--paper:\s*#f6f6f2/);
  assert.match(index, /<img class="brand-icon" src="assets\/app-icon\/icon_80x80\.png"/);
  assert.match(styles, /\.brand-icon\s*{[\s\S]*?width:\s*28px;[\s\S]*?height:\s*28px/);
  assert.match(styles, /\.hero-field::after/);
  assert.match(styles, /backdrop-filter:\s*none/);
  assert.doesNotMatch(index, /brand-mark|hero-axis|hero-route|data-theme-option|assets\/landing-minimal\.css/);
  assert.doesNotMatch(styles, /--accent|--green/);
});

test("landing fonts are self-hosted with their license", async () => {
  assert.match(styles, /url\("fonts\/Geist-Variable\.woff2"\)/);
  assert.match(styles, /url\("fonts\/GeistMono-Variable\.woff2"\)/);
  assert.doesNotMatch(styles, /cdn\.jsdelivr\.net/);
  await Promise.all([
    "assets/fonts/Geist-Variable.woff2",
    "assets/fonts/GeistMono-Variable.woff2",
    "assets/fonts/Geist.LICENSE.txt",
  ].map((reference) => access(path.join(ROOT, reference))));
});

test("docs use the landing page's self-hosted light visual system", () => {
  assert.match(docsConfig, /ThemeProvider: '\.\/src\/components\/LightThemeProvider\.astro'/);
  assert.match(docsConfig, /ThemeSelect: '\.\/src\/components\/EmptyThemeSelect\.astro'/);
  assert.match(docsConfig, /src\/styles\/agent-first\.css/);
  assert.match(lightThemeProvider, /document\.documentElement\.dataset\.theme = 'light'/);
  assert.match(agentDocsStyles, /--hmd-background-100:\s*#f6f6f2/);
  assert.match(agentDocsStyles, /--hmd-primary:\s*#121212/);
  assert.match(docsStyles, /url\("\/assets\/fonts\/Geist-Variable\.woff2"\)/);
  assert.match(docsStyles, /url\("\/assets\/fonts\/GeistMono-Variable\.woff2"\)/);
  assert.doesNotMatch(docsStyles, /cdn\.jsdelivr\.net/);
});

test("docs navigation and overview are agent-first without hiding data contracts", () => {
  const quickstart = docsConfig.indexOf("label: 'Agent Quickstart'");
  const operations = docsConfig.indexOf("label: 'Operate & Automate'");
  const contracts = docsConfig.indexOf("label: 'Data Contracts'");
  const appWorkflows = docsConfig.indexOf("label: 'App & Export'");
  assert.ok(quickstart >= 0 && quickstart < operations);
  assert.ok(operations < contracts && contracts < appWorkflows);
  assert.match(docsConfig, /slug: 'configuration'/);
  assert.match(docsConfig, /slug: 'mcp'/);
  assert.match(docsConfig, /slug: 'cli'/);
  assert.match(docsConfig, /slug: 'reference\/generated'/);
  assert.match(docsIndex, /Health data for your agent/);
  assert.match(docsIndex, /healthmd setup codex/);
  assert.match(docsIndex, /Data contracts and structures/);
  assert.match(configurationGuide, /## Codex/);
  assert.match(configurationGuide, /## Claude Desktop or Claude Code/);
  assert.match(docsHeader, />MCP<|>MCP<\/a>/);
  assert.match(docsHeader, /href="\/docs\/reference\/"/);
});

test("docs overview carries the restrained Three.js DNA treatment", () => {
  assert.match(docsConfig, /document\.querySelector\("\[data-three-strand\]"\)/);
  assert.match(docsConfig, /import\("\/assets\/landing-three\.js"\)/);
  assert.doesNotMatch(docsConfig, /src: '\/assets\/landing-three\.js'/);
  assert.match(docsIndex, /<canvas class="docs-dna" data-three-strand aria-hidden="true"><\/canvas>/);
  assert.match(agentDocsStyles, /\.docs-dna\s*{/);
  assert.match(agentDocsStyles, /@media \(prefers-reduced-motion: reduce\)/);
});

test("vertical docs tables keep mixed text and inline code in one value column", () => {
  assert.match(verticalTablesScript, /function wrapTableCellContents\(tableDetails\)/);
  assert.match(verticalTablesScript, /content\.className = 'hmd-table-cell-content'/);
  assert.match(verticalTablesScript, /while \(cell\.firstChild\) content\.append\(cell\.firstChild\)/);
  assert.match(verticalTablesScript, /wrapTableCellContents\(tableDetails\)/);
  assert.match(docsStyles, /\.hmd-table-cell-content\s*{[\s\S]*?min-width:\s*0;[\s\S]*?overflow-wrap:\s*anywhere/);
});

test("landing motion preserves safeguards and a static fallback", () => {
  assert.match(script, /prefers-reduced-motion: reduce/);
  assert.match(script, /requestAnimationFrame/);
  assert.match(script, /IntersectionObserver/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(script, /healthmd-three-failed/);
});

test("landing page JSON-LD remains valid and matches visible scope", () => {
  const blocks = [...index.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  assert.equal(blocks.length, 1);
  for (const [, source] of blocks) assert.doesNotThrow(() => JSON.parse(source));
  assert.doesNotMatch(index, /FAQPage/);
});

test("landing page asset references resolve in the website source", async () => {
  const references = new Set(
    [...index.matchAll(/(?:href|src)="(assets\/[^"]+)"/g)].map((match) => match[1]),
  );
  assert.ok(references.size > 0);
  await Promise.all([...references].map((reference) => access(path.join(ROOT, reference))));
});

test("same-page landing links point to existing ids", () => {
  const ids = new Set([...index.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]));
  const targets = [...index.matchAll(/href="#([^"]+)"/g)].map((match) => match[1]);
  for (const target of targets) assert.ok(ids.has(target), `missing #${target}`);
});
