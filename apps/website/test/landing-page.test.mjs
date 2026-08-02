import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const index = await readFile(path.join(ROOT, "index.html"), "utf8");
const privacyPolicy = await readFile(path.join(ROOT, "privacy-policy.html"), "utf8");
const terms = await readFile(path.join(ROOT, "terms-of-service.html"), "utf8");
const styles = await readFile(path.join(ROOT, "assets/landing.css"), "utf8");
const script = await readFile(path.join(ROOT, "assets/landing.js"), "utf8");
const threeSource = await readFile(path.join(ROOT, "scripts/landing-three.source.js"), "utf8");
const threeBuildScript = await readFile(path.join(ROOT, "scripts/build-three-hero.mjs"), "utf8");
const buildScript = await readFile(path.join(ROOT, "scripts/build-site.mjs"), "utf8");
const packageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));
const docsConfig = await readFile(path.join(ROOT, "docs-src/astro.config.mjs"), "utf8");
const docsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/healthmd.css"), "utf8");
const agentDocsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/agent-first.css"), "utf8");
const docsIndex = await readFile(path.join(ROOT, "docs-src/src/content/docs/index.md"), "utf8");
const configurationGuide = await readFile(path.join(ROOT, "docs-src/src/content/docs/configuration.md"), "utf8");
const iphoneExportGuide = await readFile(path.join(ROOT, "docs-src/src/content/docs/iphone-first-export.md"), "utf8");
const docsHead = await readFile(path.join(ROOT, "docs-src/src/components/Head.astro"), "utf8");
const docsHeader = await readFile(path.join(ROOT, "docs-src/src/components/HeaderLinks.astro"), "utf8");
const lightThemeProvider = await readFile(path.join(ROOT, "docs-src/src/components/LightThemeProvider.astro"), "utf8");
const verticalTablesScript = await readFile(path.join(ROOT, "docs-src/public/vertical-tables.js"), "utf8");

test("landing page makes local-first health data movement the primary message", () => {
  assert.match(index, /Move Your Health Forward/);
  assert.match(index, /Move your<br>health forward\./);
  assert.match(index, /A private bridge for your health data<br>to your files, scripts, and agents\./);
  assert.match(index, /Your data\. Your rules\./);
  assert.match(index, /Health\.md does not store your health data\.[\s\S]*You choose every export destination\./);
  assert.match(index, /class="flow-map reveal"/);
  assert.equal((index.match(/<main>/g) ?? []).length, 1);
  assert.equal((index.match(/<section/g) ?? []).length, 1);
  assert.doesNotMatch(index, /id="bridge"|id="automation"|id="interfaces"|id="download"/);
  assert.doesNotMatch(index, /<footer/);
});

test("product and legal copy reject Health.md server storage without hiding user destinations", () => {
  const publicCopy = `${index}\n${privacyPolicy}\n${terms}`;
  assert.match(privacyPolicy, /Health\.md does not collect or store (?:Apple Health, Health Connect, or other )?health data on Health\.md servers/i);
  assert.match(privacyPolicy, /user-configured API endpoint/i);
  assert.match(privacyPolicy, /file provider/i);
  assert.match(terms, /We do not collect or store your health data on Health\.md servers/);
  assert.doesNotMatch(publicCopy, /Hosted Account|hosted-data|serve-hosted|\/data\/v1\//i);
});

test("landing experience follows the reference's single-screen desktop composition", () => {
  assert.match(index, /<nav class="header-nav" aria-label="Documentation">/);
  assert.match(index, /<a class="header-docs-link" href="docs\/">Docs<\/a>/);
  assert.doesNotMatch(index, /↗/);
  assert.match(styles, /\.header-shell\s*{[\s\S]*?padding:\s*42px 13\.7% 0/);
  assert.match(styles, /\.brand-name\s*{[\s\S]*?color:\s*var\(--muted\);[\s\S]*?font-size:\s*19px;[\s\S]*?font-weight:\s*590/);
  assert.match(styles, /\.header-docs-link\s*{[\s\S]*?color:\s*var\(--muted\);[\s\S]*?font-size:\s*15px;[\s\S]*?font-weight:\s*430/);
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
  assert.deepEqual(
    [...sources.matchAll(/class="lucide (lucide-[^"]+)"/g)].map((match) => match[1]),
    ["lucide-heart-pulse", "lucide-moon-star", "lucide-footprints", "lucide-activity", "lucide-droplet", "lucide-cross"],
  );
  assert.doesNotMatch(sources, /source-more/);
  assert.match(index, /data-thread-field/);
  const routes = index.match(/<g class="route-lines">([\s\S]*?)<\/g>/)?.[1] ?? "";
  const destinationYs = [...routes.matchAll(/900 (\d+)"><\/path>/g)].map((match) => Number(match[1]));
  assert.deepEqual(destinationYs, [34, 155, 275, 396]);
  const destinationGaps = destinationYs.slice(1).map((value, index) => value - destinationYs[index]);
  assert.ok(Math.max(...destinationGaps) - Math.min(...destinationGaps) <= 1);
  assert.match(styles, /\.outcome-files\s*{\s*top:\s*calc\(8% - 28px\)/);
  assert.match(styles, /\.outcome-doctor\s*{\s*top:\s*calc\(36% - 28px\)/);
  assert.match(styles, /\.outcome-scripts\s*{\s*top:\s*calc\(64% - 28px\)/);
  assert.match(styles, /\.outcome-ai\s*{\s*top:\s*calc\(92% - 28px\)/);
  assert.equal((index.match(/class="outcome outcome-/g) ?? []).length, 4);
  const outcomeLabels = [...index.matchAll(/<span class="outcome-label">([^<]+)<\/span>/g)].map((match) => match[1]);
  assert.deepEqual(outcomeLabels, ["Files", "Doctor", "Scripts", "AI"]);
  assert.match(index, /outcome-files/);
  assert.match(index, /outcome-scripts/);
  assert.match(index, /<div class="outcome outcome-ai">[\s\S]*?<span class="outcome-label">AI<\/span>/);
  assert.match(index, /<div class="outcome outcome-doctor">[\s\S]*?<span class="outcome-label">Doctor<\/span>/);
  assert.doesNotMatch(index, /outcome-agents|<span class="outcome-label">Agents<\/span>|outcome-more|And more/);
  assert.match(script, /threadCount = 78/);
  assert.match(script, /particleCount = 46/);
  assert.match(script, /seededValue/);
  assert.match(script, /createElementNS/);
  assert.match(styles, /@keyframes thread-breathe/);
  assert.match(styles, /@keyframes route-travel/);
});

test("hero uses Logo.dev brand marks and licensed Lucide icons", async () => {
  const logoSources = [...index.matchAll(/<img src="(https:\/\/img\.logo\.dev\/[^"]+)"/g)]
    .map((match) => match[1].replaceAll("&amp;", "&"));
  const logoPaths = logoSources.map((source) => new URL(source).pathname);

  assert.equal(logoSources.length, 12);
  assert.deepEqual(logoPaths, [
    "/dropbox.com",
    "/google.com",
    "/icloud.com",
    "/name/apple-health",
    "/mychart.org",
    "/commonhealth.org",
    "/nodejs.org",
    "/js.org",
    "/openai.com",
    "/anthropic.com",
    "/huggingface.co",
    "/deepseek.com",
  ]);
  for (const source of logoSources) {
    const url = new URL(source);
    assert.equal(url.searchParams.get("token"), "pk_O_ZGdx4QSLCUENuM4MHPlg");
    assert.equal(url.searchParams.get("format"), "png");
    assert.equal(url.searchParams.get("retina"), "true");
  }
  assert.equal((index.match(/referrerpolicy="origin"/g) ?? []).length, logoSources.length);
  assert.equal((index.match(/class="outcome-logo-card/g) ?? []).length, 13);
  assert.match(index, /lucide-square-terminal/);
  assert.doesNotMatch(index, /sk_[A-Za-z0-9_-]+/);
  assert.match(styles, /\.outcome-stack\s*{[\s\S]*?width:\s*151px;[\s\S]*?display:\s*flex;[\s\S]*?flex:\s*0 0 151px/);
  assert.match(styles, /\.outcome-stack-four \.outcome-logo-card\s*{[\s\S]*?width:\s*40px;[\s\S]*?height:\s*40px/);
  assert.match(styles, /\.outcome-logo-card:nth-child\(1\)[\s\S]*?--card-tilt:\s*-3deg/);
  assert.match(styles, /\.outcome-logo-card \+ \.outcome-logo-card\s*{[\s\S]*?margin-left:\s*-5px/);
  assert.match(styles, /\.outcome-logo-card\s*{[\s\S]*?width:\s*46px;[\s\S]*?height:\s*46px/);
  assert.match(styles, /\n\.outcome-logo-card img\s*{[\s\S]*?width:\s*30px;[\s\S]*?height:\s*30px/);
  assert.match(styles, /\.outcome-logo-card img/);
  await access(path.join(ROOT, "assets/icons/lucide.LICENSE.txt"));
});

test("mobile landing leads with the pitch before a compact flow map", () => {
  const mobileStyles = styles.match(/@media \(max-width: 620px\) {([\s\S]*?)\n}\n\n@media \(max-width: 390px\)/)?.[1] ?? "";
  assert.match(mobileStyles, /\.site-header\s*{[\s\S]*?inset:\s*env\(safe-area-inset-top\) 0 auto/);
  assert.match(mobileStyles, /\.header-shell\s*{[\s\S]*?padding:\s*0[\s\S]*?calc\(20px \+ env\(safe-area-inset-right\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-left\)\)/);
  assert.match(mobileStyles, /\.hero\s*{[\s\S]*?display:\s*flex;[\s\S]*?flex-direction:\s*column/);
  assert.match(mobileStyles, /\.hero\s*{[\s\S]*?calc\(91px \+ env\(safe-area-inset-top\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-right\)\)[\s\S]*?calc\(40px \+ env\(safe-area-inset-bottom\)\)[\s\S]*?calc\(20px \+ env\(safe-area-inset-left\)\)/);
  assert.match(mobileStyles, /\.hero-intro\s*{[\s\S]*?order:\s*1/);
  assert.match(mobileStyles, /\.hero-intro h1\s*{[\s\S]*?font-size:\s*clamp\(56px, 14\.5vw, 68px\);[\s\S]*?line-height:\s*0\.92/);
  assert.match(mobileStyles, /\.hero-pitch\s*{[\s\S]*?order:\s*2;[\s\S]*?margin-top:\s*24px/);
  assert.match(mobileStyles, /\.hero-description\s*{[\s\S]*?font-size:\s*22px/);
  assert.match(mobileStyles, /\.hero-actions\s*{[\s\S]*?margin-top:\s*20px/);
  assert.match(mobileStyles, /\.flow-map\s*{[\s\S]*?order:\s*3;[\s\S]*?margin-top:\s*24px/);
  assert.match(mobileStyles, /\.source-pulse,\s*\.source-drop\s*{[\s\S]*?display:\s*none/);
  assert.match(mobileStyles, /\.source-heart\s*{\s*top:\s*8%/);
  assert.match(mobileStyles, /\.source-moon\s*{\s*top:\s*32%/);
  assert.match(mobileStyles, /\.source-activity\s*{\s*top:\s*56%/);
  assert.match(mobileStyles, /\.source-medical\s*{\s*top:\s*80%/);
  assert.match(mobileStyles, /\.flow-art\s*{\s*transform:\s*translateX\(-18%\)/);
  assert.match(mobileStyles, /\.route-lines\s*{[\s\S]*?transform:\s*scaleY\(0\.67\)/);
  assert.match(mobileStyles, /\.outcome\s*{[\s\S]*?left:\s*67%/);
  assert.match(mobileStyles, /\.outcome-stack\s*{[\s\S]*?width:\s*108px;[\s\S]*?flex-basis:\s*108px/);
  assert.match(mobileStyles, /\.outcome-files\s*{\s*top:\s*calc\(22% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-doctor\s*{\s*top:\s*calc\(41% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-scripts\s*{\s*top:\s*calc\(59% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-ai\s*{\s*top:\s*calc\(78% - 22px\)/);
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

test("documentation Three.js is bundled once and deferred behind a static first frame", () => {
  assert.doesNotMatch(index, /data-three-strand|assets\/landing-three\.js/);
  assert.match(threeSource, /import \* as THREE from "three"/);
  assert.match(threeSource, /THREE\.WebGLRenderer/);
  assert.match(threeSource, /THREE\.TubeGeometry/);
  assert.match(threeSource, /powerPreference: "low-power"/);
  assert.match(threeSource, /devicePixelRatio \|\| 1, 1\.35/);
  assert.ok(Buffer.byteLength(threeSource) < 15_000);
  assert.equal(packageJson.dependencies.three, "^0.185.1");
  assert.equal(packageJson.devDependencies.esbuild, "0.28.1");
  assert.match(threeBuildScript, /bundle: true/);
  assert.match(threeBuildScript, /minify: true/);
  assert.doesNotMatch(buildScript, /three\.module\.min\.js|three\.core\.min\.js/);
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

test("docs navigation starts with user goals and labels preview surfaces", () => {
  const getStarted = docsConfig.indexOf("label: 'Get Started'");
  const agents = docsConfig.indexOf("label: 'Use an Agent'");
  const exports = docsConfig.indexOf("label: 'Export & Automate'");
  const integrations = docsConfig.indexOf("label: 'Build an Integration'");
  assert.ok(getStarted >= 0 && getStarted < agents);
  assert.ok(agents < exports && exports < integrations);
  assert.match(docsConfig, /First iPhone export', slug: 'iphone-first-export'/);
  assert.match(docsConfig, /Direct iPhone CLI · Preview/);
  assert.ok((docsConfig.match(/collapsed: true/g) ?? []).length >= 5);
  assert.match(docsIndex, /Start with Health\.md/);
  assert.match(docsIndex, /Contents\/Helpers\/healthmd" doctor/);
  assert.match(docsIndex, /Five-minute local agent quickstart/);
  assert.doesNotMatch(docsIndex, /healthmd setup codex/);
  assert.match(configurationGuide, /Available now · signed Mac helper/);
  assert.match(configurationGuide, /Preview · not yet publicly packaged/);
  assert.match(docsHeader, />MCP<|>MCP<\/a>/);
  assert.match(docsHeader, /href="\/docs\/reference\/"/);
});

test("docs overview paints a static strand before deferred WebGL", async () => {
  assert.match(docsConfig, /document\.querySelector\('\[data-three-strand\]'\)/);
  assert.match(docsConfig, /import\('\/assets\/landing-three\.bundle\.js'\)/);
  assert.match(docsConfig, /setTimeout[\s\S]*?, 3000\)/);
  assert.match(docsConfig, /prefers-reduced-motion: reduce/);
  assert.match(docsConfig, /navigator\.connection\?\.saveData/);
  assert.doesNotMatch(docsConfig, /src: '\/assets\/landing-three\.js'/);
  assert.match(docsIndex, /<canvas class="docs-dna" data-three-strand aria-hidden="true"><\/canvas>/);
  assert.match(agentDocsStyles, /docs-strand\.svg/);
  assert.match(agentDocsStyles, /\.docs-dna\[data-renderer='three'\]/);
  await access(path.join(ROOT, "docs-src/public/assets/docs-strand.svg"));
});

test("docs tables compare conventionally on desktop and filter reference rows", () => {
  assert.match(verticalTablesScript, /function wrapTableCellContents\(tableDetails\)/);
  assert.match(verticalTablesScript, /content\.className = 'hmd-table-cell-content'/);
  assert.match(verticalTablesScript, /function addTableFilters\(tableDetails, keyGroups\)/);
  assert.match(verticalTablesScript, /json path/);
  assert.match(verticalTablesScript, /hmd-row-filter/);
  assert.match(verticalTablesScript, /function markParentSidebarLink/);
  assert.match(docsStyles, /\.hmd-table-cell-content\s*{[\s\S]*?min-width:\s*0;[\s\S]*?overflow-wrap:\s*anywhere/);
  assert.match(agentDocsStyles, /@media \(min-width: 48\.001rem\)[\s\S]*?display: table;/);
  assert.match(agentDocsStyles, /display: table-header-group/);
  assert.match(agentDocsStyles, /td::before\s*{\s*display: none/);
});

test("first iPhone export guide uses current, optimized simulator screenshots", async () => {
  assert.match(iphoneExportGuide, /First iPhone export/);
  assert.match(iphoneExportGuide, /Available now · Health\.md for iPhone/);
  assert.match(iphoneExportGuide, /Preview before writing/);
  const screenshots = [
    "onboarding-start.webp",
    "export-setup-required.webp",
    "metric-selection.webp",
    "export-preview.webp",
  ];
  for (const screenshot of screenshots) {
    assert.match(iphoneExportGuide, new RegExp(screenshot.replace(".", "\\.")));
    await access(path.join(ROOT, "docs-src/public/assets/docs/iphone-first-export", screenshot));
  }
  assert.equal((iphoneExportGuide.match(/<img /g) ?? []).length, screenshots.length);
  assert.equal((iphoneExportGuide.match(/ alt="[^"]+"/g) ?? []).length, screenshots.length);
});

test("docs emit sharing images and structured article metadata", async () => {
  assert.match(docsConfig, /Head: '\.\/src\/components\/Head\.astro'/);
  assert.match(docsConfig, /og:image/);
  assert.match(docsConfig, /twitter:image/);
  assert.match(docsConfig, /@astrojs\/sitemap/);
  assert.match(docsHead, /<DefaultHead \/>/);
  assert.match(docsHead, /TechArticle/);
  assert.match(docsHead, /BreadcrumbList/);
  await access(path.join(ROOT, "docs-src/public/social/docs-og.png"));
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
