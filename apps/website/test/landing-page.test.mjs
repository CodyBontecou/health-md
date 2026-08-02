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

test("landing page makes moving private health data the only message", () => {
  assert.match(index, /Move Your Health Forward/);
  assert.match(index, /Move your<br>health forward\./);
  assert.match(index, /A private bridge for your health data<br>to your files, scripts, and agents\./);
  assert.match(index, /Your data\. Your rules\./);
  assert.match(index, /No Health\.md cloud\.[\s\S]*Your data stays under your control\./);
  assert.match(index, /class="flow-map reveal"/);
  assert.equal((index.match(/<main>/g) ?? []).length, 1);
  assert.equal((index.match(/<section/g) ?? []).length, 1);
  assert.doesNotMatch(index, /id="bridge"|id="automation"|id="interfaces"|id="download"/);
  assert.doesNotMatch(index, /<footer/);
});

test("landing experience follows the reference's single-screen desktop composition", () => {
  assert.match(index, /<nav class="header-nav" aria-label="Documentation">/);
  assert.match(index, /<a class="header-docs-link" href="docs\/">\s*Docs/);
  assert.doesNotMatch(index, /data-menu-toggle|primary-navigation|hero-meta|hero-route|brand-mode/);
  assert.match(styles, /@media \(min-width: 981px\) and \(min-height: 650px\)[\s\S]*?overflow:\s*hidden/);
  assert.match(styles, /\.hero-intro\s*{[\s\S]*?position:\s*absolute/);
  assert.match(styles, /\.hero-intro h1\s*{[\s\S]*?margin-left:\s*clamp\(-8px, -0\.5vw, -4px\)/);
  assert.match(styles, /\.hero-pitch\s*{[\s\S]*?position:\s*absolute/);
});

test("landing establishes its reveal state before the stylesheet can paint", () => {
  const bootstrapPosition = index.indexOf('<script>document.documentElement.classList.add("has-js");</script>');
  const stylesheetPosition = index.indexOf('<link rel="stylesheet" href="assets/landing.css">');

  assert.ok(bootstrapPosition >= 0);
  assert.ok(bootstrapPosition < stylesheetPosition);
});

test("landing background is full-bleed and covers iOS unsafe areas", () => {
  const mainStyles = styles.match(/main\s*{([^}]*)}/)?.[1] ?? "";
  const heroStyles = styles.match(/\.hero\s*{([^}]*)}/)?.[1] ?? "";

  assert.match(index, /name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/);
  assert.match(styles, /html,\s*body\s*{[\s\S]*?background:\s*var\(--paper\)/);
  assert.match(styles, /body\s*{[\s\S]*?background:\s*var\(--paper\)/);
  assert.match(mainStyles, /min-height:\s*100svh/);
  assert.doesNotMatch(mainStyles, /padding|margin/);
  assert.match(heroStyles, /min-height:\s*100svh/);
  assert.doesNotMatch(heroStyles, /border-radius|margin/);
  assert.match(styles, /\.site-header\s*{[\s\S]*?env\(safe-area-inset-top\)/);
});

test("hero uses official store badges with direct marketplace links", () => {
  const actions = index.match(/<div class="hero-actions"[\s\S]*?<\/div>/)?.[0] ?? "";
  assert.equal((actions.match(/<a /g) ?? []).length, 2);
  assert.match(actions, /href="https:\/\/apps\.apple\.com\/us\/app\/health-md\/id6757763969"/);
  assert.match(actions, /href="https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.healthmd\.android"/);
  assert.match(actions, /assets\/store-badges\/download-on-app-store\.svg/);
  assert.match(actions, /assets\/store-badges\/get-it-on-google-play\.png/);
  assert.match(styles, /\.hero-store-badge-apple\s*{[\s\S]*?width:\s*166px;[\s\S]*?height:\s*55px/);
  assert.match(styles, /\.hero-store-badge-google\s*{[\s\S]*?width:\s*185px;[\s\S]*?height:\s*55px/);
});

test("hero visual routes health signals through Health.md to useful destinations", () => {
  const sources = index.match(/<div class="source-list"[\s\S]*?<\/div>/)?.[0] ?? "";
  assert.equal((sources.match(/class="source-node/g) ?? []).length, 6);
  assert.match(sources, /source-heart/);
  assert.match(sources, /source-moon/);
  assert.match(sources, /source-activity/);
  assert.match(sources, /source-pulse/);
  assert.match(sources, /source-drop/);
  assert.match(sources, /source-medical/);
  assert.doesNotMatch(sources, /source-more/);
  assert.match(index, /data-thread-field/);
  const routes = index.match(/<g class="route-lines">([\s\S]*?)<\/g>/)?.[1] ?? "";
  const destinationYs = [...routes.matchAll(/912 (\d+)"><\/path>/g)].map((match) => Number(match[1]));
  assert.deepEqual(destinationYs, [60, 215, 370]);
  assert.equal(destinationYs[1] - destinationYs[0], destinationYs[2] - destinationYs[1]);
  assert.match(styles, /\.outcome-files\s*{\s*top:\s*calc\(14% - 33px\)/);
  assert.match(styles, /\.outcome-scripts\s*{\s*top:\s*calc\(50% - 33px\)/);
  assert.match(styles, /\.outcome-agents\s*{\s*top:\s*calc\(86% - 33px\)/);
  assert.match(index, /outcome-files/);
  assert.match(index, /outcome-scripts/);
  assert.match(index, /outcome-agents/);
  assert.doesNotMatch(index, /outcome-more|And more/);
  assert.match(script, /threadCount = 78/);
  assert.match(script, /particleCount = 46/);
  assert.match(script, /seededValue/);
  assert.match(script, /createElementNS/);
  assert.match(styles, /@keyframes thread-breathe/);
  assert.match(styles, /@keyframes route-travel/);
});

test("mobile landing leads with the pitch before a compact flow map", () => {
  const mobileStyles = styles.match(/@media \(max-width: 620px\) {([\s\S]*?)\n}\n\n@media \(max-width: 390px\)/)?.[1] ?? "";
  assert.match(mobileStyles, /\.site-header\s*{[\s\S]*?inset:\s*env\(safe-area-inset-top\) 0 auto/);
  assert.match(mobileStyles, /\.header-shell\s*{[\s\S]*?padding:\s*0[\s\S]*?calc\(20px \+ env\(safe-area-inset-right\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-left\)\)/);
  assert.match(mobileStyles, /\.hero\s*{[\s\S]*?display:\s*flex;[\s\S]*?flex-direction:\s*column/);
  assert.match(mobileStyles, /\.hero\s*{[\s\S]*?calc\(91px \+ env\(safe-area-inset-top\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-right\)\)[\s\S]*?calc\(40px \+ env\(safe-area-inset-bottom\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-left\)\)/);
  assert.match(mobileStyles, /\.hero-intro\s*{[\s\S]*?order:\s*1/);
  assert.match(mobileStyles, /\.hero-pitch\s*{[\s\S]*?order:\s*2/);
  assert.match(mobileStyles, /\.flow-map\s*{[\s\S]*?order:\s*3/);
  assert.match(mobileStyles, /\.source-pulse,\s*\.source-drop\s*{[\s\S]*?display:\s*none/);
  assert.match(mobileStyles, /\.source-heart\s*{\s*top:\s*8%/);
  assert.match(mobileStyles, /\.source-moon\s*{\s*top:\s*32%/);
  assert.match(mobileStyles, /\.source-activity\s*{\s*top:\s*56%/);
  assert.match(mobileStyles, /\.source-medical\s*{\s*top:\s*80%/);
  assert.match(mobileStyles, /\.flow-art\s*{\s*transform:\s*translateX\(-18%\)/);
  assert.match(mobileStyles, /\.route-lines\s*{[\s\S]*?transform:\s*scaleY\(0\.67\)/);
  assert.match(mobileStyles, /\.outcome\s*{[\s\S]*?left:\s*72%/);
  assert.match(mobileStyles, /\.outcome-files\s*{\s*top:\s*calc\(26% - 25px\)/);
  assert.match(mobileStyles, /\.outcome-scripts\s*{\s*top:\s*calc\(50% - 25px\)/);
  assert.match(mobileStyles, /\.outcome-agents\s*{\s*top:\s*calc\(74% - 25px\)/);
  assert.match(mobileStyles, /\.outcome-label\s*{\s*display:\s*block/);
  assert.match(mobileStyles, /\.hero-trust\s*{\s*display:\s*none/);
});

test("animated hero avoids per-element SVG compositing and loops routes seamlessly", () => {
  const threadField = index.match(/<g class="thread-field"[^>]*>/)?.[0] ?? "";
  const threadPathStyles = styles.match(/\.thread-field path\s*{([^}]*)}/)?.[1] ?? "";
  const particleStyles = styles.match(/\.thread-particles circle\s*{([^}]*)}/)?.[1] ?? "";

  assert.doesNotMatch(threadField, /\sfilter=/);
  assert.doesNotMatch(index, /<filter id="thread-soften"/);
  assert.match(threadPathStyles, /opacity:\s*var\(--thread-opacity/);
  assert.match(particleStyles, /opacity:\s*var\(--particle-opacity/);
  assert.doesNotMatch(threadPathStyles, /animation|transform/);
  assert.doesNotMatch(particleStyles, /animation|transform/);
  assert.match(styles, /\.thread-field\s*{[^}]*animation:\s*thread-breathe/);
  assert.match(styles, /\.thread-particles\s*{[^}]*animation:\s*particle-drift/);
  assert.match(styles, /stroke-dasharray:\s*1\.5 5/);
  assert.match(styles, /@keyframes route-travel\s*{[\s\S]*?stroke-dashoffset:\s*-32\.5/);
});

test("Three.js remains locally served for the documentation DNA treatment", () => {
  assert.doesNotMatch(index, /data-three-strand|assets\/landing-three\.js/);
  assert.match(threeScript, /THREE\.WebGLRenderer/);
  assert.match(threeScript, /THREE\.TubeGeometry/);
  assert.equal(packageJson.dependencies.three, "^0.185.1");
  assert.match(buildScript, /three\.module\.min\.js/);
  assert.match(buildScript, /three\.core\.min\.js/);
  assert.match(buildScript, /three\.LICENSE\.txt/);
});

test("landing page keeps a restrained light design with the app icon in the flow", () => {
  assert.match(styles, /color-scheme:\s*light/);
  assert.match(styles, /--paper:\s*#fafaf8/);
  assert.doesNotMatch(index, /class="brand-icon"/);
  assert.match(styles, /\.header-shell\s*{[\s\S]*?padding:\s*42px[\s\S]*?13\.7%/);
  assert.match(index, /class="flow-core"[\s\S]*?assets\/app-icon\/icon_80x80\.png/);
  assert.match(styles, /--purple:\s*#9465ff/);
  assert.doesNotMatch(index, /brand-mark|hero-axis|hero-route|data-theme-option|assets\/landing-minimal\.css/);
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

test("landing motion preserves reduced-motion safeguards", () => {
  assert.match(script, /prefers-reduced-motion: reduce/);
  assert.match(script, /requestAnimationFrame/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(styles, /animation-duration:\s*0\.01ms !important/);
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
