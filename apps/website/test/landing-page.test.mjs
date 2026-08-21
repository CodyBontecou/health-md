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
const legalStyles = await readFile(path.join(ROOT, "assets/legal.css"), "utf8");
const script = await readFile(path.join(ROOT, "assets/landing.js"), "utf8");
const threeSource = await readFile(path.join(ROOT, "scripts/landing-three.source.js"), "utf8");
const threeBuildScript = await readFile(path.join(ROOT, "scripts/build-three-hero.mjs"), "utf8");
const buildScript = await readFile(path.join(ROOT, "scripts/build-site.mjs"), "utf8");
const packageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));
const docsConfig = await readFile(path.join(ROOT, "docs-src/astro.config.mjs"), "utf8");
const docsUi = await readFile(path.join(ROOT, "i18n/docs-ui.mjs"), "utf8");
const docsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/healthmd.css"), "utf8");
const agentDocsStyles = await readFile(path.join(ROOT, "docs-src/src/styles/agent-first.css"), "utf8");
const docsIndex = await readFile(path.join(ROOT, "docs-src/src/content/docs/index.md"), "utf8");
const configurationGuide = await readFile(path.join(ROOT, "docs-src/src/content/docs/configuration.md"), "utf8");
const iphoneExportGuide = await readFile(path.join(ROOT, "docs-src/src/content/docs/iphone-first-export.md"), "utf8");
const docsHead = await readFile(path.join(ROOT, "docs-src/src/components/Head.astro"), "utf8");
const docsHeader = await readFile(path.join(ROOT, "docs-src/src/components/HeaderLinks.astro"), "utf8");
const docsFooter = await readFile(path.join(ROOT, "docs-src/src/components/Footer.astro"), "utf8");
const emptyLanguageSelect = await readFile(path.join(ROOT, "docs-src/src/components/EmptyLanguageSelect.astro"), "utf8");
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
  assert.equal((index.match(/<section/g) ?? []).length, 5);
  assert.match(index, /<section class="export-showcase" id="exports"/);
  assert.match(index, /<section class="download-cta" id="download"/);
  assert.doesNotMatch(index, /id="bridge"|id="automation"|id="interfaces"/);
  assert.match(index, /<footer class="site-footer">/);
});

test("landing closes with a localized download decision and compact footer", () => {
  const downloadSection = index.slice(
    index.indexOf('<section class="download-cta"'),
    index.indexOf("</main>"),
  );
  const footer = index.slice(index.indexOf('<footer class="site-footer">'));

  assert.match(downloadSection, /Take your health data with you\./);
  assert.match(downloadSection, /Try 10 exports free\. Full Access is a one-time purchase\. No subscription\./);
  assert.match(downloadSection, /class="download-actions" aria-label="Download Health\.md"/);
  assert.equal((downloadSection.match(/class="hero-store-badge /g) ?? []).length, 2);
  assert.match(downloadSection, /href="https:\/\/apps\.apple\.com\/us\/app\/health-md\/id6757763969"/);
  assert.match(downloadSection, /href="https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.healthmd\.android"/);

  assert.match(footer, /<nav class="footer-links" aria-label="Footer navigation">/);
  assert.match(footer, /href="docs\/">Docs<\/a>/);
  assert.match(footer, /href="privacy-policy\.html">Privacy<\/a>/);
  assert.match(footer, /href="terms-of-service\.html">Terms<\/a>/);
  assert.match(footer, /href="mailto:cody@isolated\.tech">Support<\/a>/);
  assert.match(footer, /<!-- HEALTHMD_FOOTER_LANGUAGE_SELECTOR -->/);
  assert.match(styles, /\.download-cta\s*{[\s\S]*?min-height:\s*680px/);
  assert.match(styles, /\.site-footer\s*{[\s\S]*?env\(safe-area-inset-bottom\)/);
  assert.match(styles, /\.footer-language-menu \.language-selector\s*{[\s\S]*?bottom:\s*calc\(100% \+ 8px\)/);
  assert.match(styles, /@media \(max-width: 720px\)[\s\S]*?\.download-cta\s*{[\s\S]*?min-height:\s*570px/);
});

test("export showcase turns selected health metrics into downloadable ordinary files", async () => {
  assert.match(index, /Your health data,<br>as ordinary files\./);
  assert.match(index, /Markdown, JSON, CSV, or Obsidian/);
  assert.equal((index.match(/data-export-format=/g) ?? []).length, 4);
  assert.match(index, /data-export-format="markdown" aria-pressed="true"/);
  assert.match(index, /class="export-phone-wrap reveal"/);
  assert.match(index, /class="export-phone" role="img"/);
  assert.match(index, /assets\/screenshots\/showcase\/apple-health-summary\.png/);
  assert.match(index, /class="export-phone-frame" src="assets\/screenshots\/showcase\/iphone-17-pro-silver\.png"/);
  assert.match(index, /data-sample-download/);
  assert.doesNotMatch(index, /class="phone-status"|class="metric-list"/);
  assert.match(index, /class="file-preview-stack reveal" data-preview-stack/);
  assert.match(index, /class="file-preview" data-preview-format="markdown"/);
  assert.match(script, /function setupExportFormats\(\)/);
  assert.match(script, /var selectedFormats =/);
  assert.match(script, /selectedFormats\.push\(format\)/);
  assert.match(script, /selectedFormats\.splice\(selectedIndex, 1\)/);
  assert.match(script, /function createPreviewCard\(/);
  assert.match(script, /messages\.downloadMany\.replace\("\{count\}", String\(selectedFormats\.length\)\)/);
  assert.match(styles, /@keyframes preview-card-spawn/);
  assert.match(styles, /--stack-rotation/);
  assert.match(script, /IntersectionObserver/);
  assert.match(styles, /\.export-showcase\s*{[\s\S]*?grid-template-columns:/);
  assert.match(styles, /\.export-phone-wrap\s*{[\s\S]*?display:\s*flex;/);
  assert.match(styles, /@media \(max-width: 650px\)[\s\S]*?\.export-showcase\s*{[\s\S]*?flex-direction:\s*column/);
  assert.match(styles, /@media \(max-width: 650px\)[\s\S]*?\.export-phone-wrap\s*{\s*display:\s*none;/);
  assert.equal((styles.match(/\.export-phone-wrap\s*{[^}]*display:\s*none;/g) ?? []).length, 1);
  assert.match(styles, /@media \(max-width: 650px\)[\s\S]*?\.format-picker\s*{[\s\S]*?grid-template-columns:\s*repeat\(4,/);
  assert.match(styles, /@media \(max-width: 650px\)[\s\S]*?\.export-actions\s*{[\s\S]*?grid-template-columns:\s*repeat\(2,/);
  assert.match(styles, /@media \(max-width: 650px\)[\s\S]*?\.file-preview-stack\s*{\s*width:\s*100%;\s*max-width:\s*none;\s*align-self:\s*stretch;/);

  await Promise.all([
    "assets/samples/health-data-sample.md",
    "assets/samples/health-data-sample.json",
    "assets/samples/health-data-sample.csv",
    "assets/samples/health-data-sample-obsidian.md",
    "assets/screenshots/showcase/apple-health-summary.png",
    "assets/screenshots/showcase/iphone-17-pro-silver.png",
  ].map((reference) => access(path.join(ROOT, reference))));
});

test("scheduling showcase explains recurring on-device exports", async () => {
  assert.match(index, /<section class="schedule-showcase" id="scheduling"/);
  assert.match(index, /Your health data, scheduled\./);
  assert.match(index, /Choose when Health\.md exports and where the files go\./);
  assert.equal((index.match(/data-schedule-frequency=/g) ?? []).length, 3);
  assert.match(index, /data-schedule-frequency="daily" aria-pressed="true"/);
  assert.match(index, /class="schedule-routes schedule-routes-desktop"/);
  assert.match(index, /class="schedule-routes schedule-routes-mobile"/);
  assert.match(index, /schedule-route-main" d="M170 62 V473"/);
  assert.equal((index.match(/schedule-route-branch" marker-end="url\(#schedule-arrow\)" d="M184 495/g) ?? []).length, 3);
  assert.match(index, /schedule-route-trunk" d="M175 416 V425"/);
  assert.equal((index.match(/schedule-route-branch" marker-end="url\(#schedule-arrow-mobile\)" d="M175 425/g) ?? []).length, 3);
  assert.match(index, /Runs from your device/);
  assert.match(index, /Uses the metrics you choose/);
  assert.match(index, /Saves where you want/);
  assert.match(script, /function setupSchedulePreview\(\)/);
  assert.match(styles, /@keyframes schedule-route-flow/);
  assert.match(styles, /@media \(max-width: 680px\)[\s\S]*?\.schedule-map\s*{[^}]*height:\s*590px;/);
  assert.match(styles, /@media \(max-width: 680px\)[\s\S]*?\.schedule-routes-desktop\s*{\s*display:\s*none;/);
  assert.match(styles, /@media \(max-width: 680px\)[\s\S]*?\.schedule-routes-mobile\s*{\s*display:\s*block;/);
  assert.match(styles, /@media \(max-width: 680px\)[\s\S]*?\.schedule-destinations\s*{[\s\S]*?top:\s*462px;[\s\S]*?grid-template-columns:\s*repeat\(3,/);

  await Promise.all([
    "assets/screenshots/showcase/scheduled-exports.png",
    "assets/screenshots/showcase/iphone-17-pro-silver.png",
    "assets/brand-icons/destinations/icloud.png",
    "assets/brand-icons/destinations/obsidian.png",
    "assets/brand-icons/destinations/zapier.png",
  ].map((reference) => access(path.join(ROOT, reference))));
});

test("agent showcase connects scoped questions to contextual answers", async () => {
  assert.match(index, /<section class="agent-showcase" id="agents"/);
  assert.match(index, /Your health data,<br>ready for questions\./);
  assert.match(index, /without routing data through a Health\.md cloud/);
  assert.match(index, /href="docs\/guides\/connect-agent\/"[\s\S]*?Connect an agent/);
  assert.match(index, /href="docs\/cli\/"[\s\S]*?Explore CLI &amp; MCP/);
  assert.ok(index.indexOf("Connect an agent") < index.indexOf("Explore CLI &amp; MCP"));
  assert.match(styles, /\.agent-copy\s*{[\s\S]*?height:\s*694px;/);
  assert.match(styles, /\.agent-actions\s*{[\s\S]*?position:\s*absolute;[\s\S]*?bottom:\s*0;[\s\S]*?grid-template-columns:\s*1fr;/);
  assert.match(styles, /@media \(max-width: 1120px\)[\s\S]*?\.agent-actions\s*{[\s\S]*?position:\s*static;/);
  assert.doesNotMatch(index, /class="agent-benefits"/);
  assert.equal((index.match(/data-agent-client=/g) ?? []).length, 3);
  assert.match(index, /data-agent-client="codex" aria-pressed="true"/);
  assert.equal((index.match(/data-agent-question=/g) ?? []).length, 3);
  assert.match(index, /class="agent-route"/);
  assert.equal((index.match(/<path d="M(?:234|420) /g) ?? []).length, 2);
  assert.match(index, /class="agent-result-card"/);
  assert.match(index, /aria-label="Example Health\.md answer"/);
  assert.match(index, /Resting heart rate/);
  assert.match(index, /Coverage: 14 of 14 days/);
  assert.match(index, /Evidence available/);
  const agentSection = index.slice(index.indexOf('<section class="agent-showcase"'), index.indexOf("</main>"));
  assert.doesNotMatch(agentSection, /Sample data/i);
  assert.match(script, /function setupAgentPreview\(\)/);
  assert.match(script, /title: "Health\.md CLI"/);
  assert.match(styles, /\.agent-showcase\s*{[\s\S]*?grid-template-columns:/);
  assert.match(styles, /@keyframes agent-route-flow/);
  assert.match(styles, /@media \(max-width: 760px\)[\s\S]*?\.agent-visual\s*{[\s\S]*?flex-direction:\s*column/);
  assert.match(styles, /@media \(max-width: 760px\)[\s\S]*?\.agent-hub::after\s*{\s*top:\s*150px;\s*height:\s*10px;/);
  await access(path.join(ROOT, "assets/app-icon/healthmd-mark.png"));
});

test("product and legal copy reject Health.md server storage without hiding user destinations", () => {
  const publicCopy = `${index}\n${privacyPolicy}\n${terms}`;
  assert.match(privacyPolicy, /Health\.md does not collect or store (?:Apple Health, Health Connect, or other )?health data on Health\.md servers/i);
  assert.match(privacyPolicy, /user-configured API endpoint/i);
  assert.match(privacyPolicy, /file provider/i);
  assert.match(terms, /We do not collect or store your health data on Health\.md servers/);
  assert.doesNotMatch(publicCopy, /Hosted Account|hosted-data|serve-hosted|\/data\/v1\//i);
});

test("privacy policy uses the landing design and describes the current app surfaces", () => {
  assert.match(privacyPolicy, /<body class="legal-page">/);
  assert.match(privacyPolicy, /<link rel="stylesheet" href="assets\/landing\.css">/);
  assert.match(privacyPolicy, /<link rel="stylesheet" href="assets\/legal\.css">/);
  assert.match(privacyPolicy, /<header class="site-header">/);
  assert.match(privacyPolicy, /<footer class="site-footer">/);
  assert.match(privacyPolicy, /Privacy,<br>in plain language\./);
  assert.match(privacyPolicy, /Last updated: August 20, 2026/);
  assert.match(privacyPolicy, /Direct Google Drive export:[\s\S]*?<code>drive\.file<\/code>/);
  assert.match(privacyPolicy, /Scheduled Apple exports:[\s\S]*?APNs token/);
  assert.match(privacyPolicy, /Lossless files and direct results may preserve exact timestamps/);
  assert.match(privacyPolicy, /Android medical records \(FHIR\)/);
  assert.doesNotMatch(privacyPolicy, /<style\b|theme\.js|fonts\.googleapis\.com|theme-toggle|grid-bg/);
  assert.match(legalStyles, /\.legal-hero h1\s*{[\s\S]*?font-size:\s*clamp\(64px, 7\.2vw, 108px\)/);
  assert.match(legalStyles, /\.legal-promise\s*{[\s\S]*?grid-template-columns:\s*repeat\(3,/);
  assert.match(legalStyles, /\.legal-eyebrow\s*{[\s\S]*?color:\s*#7240e8/);
  assert.match(legalStyles, /@media \(max-width: 720px\)[\s\S]*?\.legal-promise\s*{[\s\S]*?grid-template-columns:\s*1fr/);
});

test("terms of service uses the legal design and covers the current product model", () => {
  assert.match(terms, /<body class="legal-page">/);
  assert.match(terms, /<link rel="stylesheet" href="assets\/landing\.css">/);
  assert.match(terms, /<link rel="stylesheet" href="assets\/legal\.css">/);
  assert.match(terms, /<header class="site-header">/);
  assert.match(terms, /<footer class="site-footer">/);
  assert.match(terms, /Terms,<br>made readable\./);
  assert.match(terms, /Last updated: August 6, 2026/);
  assert.match(terms, /consumer apps for iPhone, iPad, Mac, and Android/);
  assert.match(terms, /command-line and MCP tools where made available/);
  assert.match(terms, /preview, source-build, beta, or compatibility path/);
  assert.match(terms, /current consumer offer is 10 free exports/);
  assert.match(terms, /It is not a subscription and does not renew/);
  assert.match(terms, /never exposing a local loopback API or its port to another machine/);
  assert.match(terms, /not a medical device, healthcare provider, diagnostic service, treatment, or emergency service/);
  assert.match(terms, /Cody Bontecou, who operates Health\.md under the isolated\.tech name/);
  assert.match(terms, /GNU Affero General Public License version 3\.0 only \(AGPL-3\.0-only\)/);
  assert.match(terms, /website source is distributed under the MIT License/);
  assert.match(terms, /Nothing in these Terms restricts rights granted by the AGPL/);
  assert.doesNotMatch(terms, /<style\b|theme\.js|fonts\.googleapis\.com|theme-toggle|grid-bg/);

  const sectionIds = [...terms.matchAll(/<section id="([^"]+)"/g)].map((match) => match[1]);
  const toc = terms.slice(terms.indexOf('<aside class="legal-toc">'), terms.indexOf('</aside>'));
  assert.equal(sectionIds.length, 21);
  for (const id of sectionIds) assert.ok(toc.includes(`href="#${id}"`), id);
});

test("privacy policy discloses automatic pseudonymous analytics and strict health-data exclusions", () => {
  const publicCopy = `${index}\n${privacyPolicy}\n${terms}`;
  assert.match(privacyPolicy, /First-Party Product Analytics/);
  assert.match(privacyPolicy, /pseudonymous rather than anonymous/);
  assert.match(privacyPolicy, /collects these limited product events automatically/);
  assert.match(privacyPolicy, /retained for no more than 13 months/);
  assert.match(privacyPolicy, /not used for advertising, fingerprinting, or cross-app tracking/);
  assert.match(privacyPolicy, /never include HealthKit or Health Connect values or identifiers, metric names, health dates/);
  assert.match(privacyPolicy, /health records and exported content cannot be represented in an analytics payload/);
  assert.match(privacyPolicy, /credentials or tokens/);
  assert.doesNotMatch(publicCopy, /\bno analytics\b/i);
  assert.doesNotMatch(privacyPolicy, /opt out|turn(?:ing)? (?:it|analytics) off|reset (?:the )?(?:random )?analytics identifier/i);
});

test("landing experience follows the reference's single-screen desktop composition", () => {
  assert.match(index, /<div class="header-nav">/);
  assert.match(index, /<nav aria-label="Documentation"><a class="header-docs-link" href="docs\/">Docs<\/a><\/nav>/);
  assert.doesNotMatch(index, /<!-- HEALTHMD_LANGUAGE_SELECTOR -->/);
  assert.doesNotMatch(index.slice(index.indexOf('<header'), index.indexOf('</header>')), /language-menu|language-selector/);
  assert.doesNotMatch(index, /↗/);
  assert.match(styles, /\.header-shell\s*{[\s\S]*?padding:\s*42px 13\.7% 0/);
  assert.match(styles, /\.brand-name\s*{[\s\S]*?color:\s*var\(--muted\);[\s\S]*?font-size:\s*19px;[\s\S]*?font-weight:\s*590/);
  assert.match(styles, /\.header-docs-link\s*{[\s\S]*?color:\s*var\(--muted\);[\s\S]*?font-size:\s*15px;[\s\S]*?font-weight:\s*430/);
  assert.match(styles, /\.language-menu\s*{[\s\S]*?position:\s*relative/);
  assert.match(styles, /\.language-selector\s*{[\s\S]*?position:\s*absolute/);
  assert.doesNotMatch(index, /data-menu-toggle|primary-navigation|hero-meta|hero-route|brand-mode/);
  assert.match(styles, /@media \(min-width: 981px\) and \(min-height: 650px\)[\s\S]*?overflow:\s*hidden/);
  assert.match(styles, /\.hero-intro\s*{[\s\S]*?position:\s*absolute/);
  assert.match(styles, /\.hero-intro h1\s*{[\s\S]*?margin-left:\s*clamp\(-8px, -0\.5vw, -4px\)/);
  assert.match(styles, /\.hero-pitch\s*{[\s\S]*?position:\s*absolute/);
});

test("landing negotiates locale and establishes its reveal state before the stylesheet can paint", () => {
  const localeRedirectPosition = index.indexOf('<script id="healthmd-locale-redirect">');
  const bootstrapPosition = index.indexOf('<script>document.documentElement.classList.add("has-js");</script>');
  const stylesheetPosition = index.indexOf('<link rel="stylesheet" href="assets/landing.css">');

  assert.ok(localeRedirectPosition >= 0);
  assert.ok(localeRedirectPosition < bootstrapPosition);
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
  assert.match(
    styles,
    /html:not\(:lang\(en\)\) \.hero-store-badge-google img\s*{[\s\S]*?left:\s*0;[\s\S]*?width:\s*100%;[\s\S]*?transform:\s*translateY\(-50%\)/,
  );
});

test("hero visual routes health signals through Health.md to useful destinations", () => {
  const sources = index.match(/<div class="source-list"[\s\S]*?<\/div>/)?.[0] ?? "";
  assert.equal((sources.match(/class="source-node/g) ?? []).length, 6);
  assert.deepEqual(
    [...sources.matchAll(/class="source-node (source-[^"]+)"/g)].map((match) => match[1]),
    [
      "source-apple-health",
      "source-health-connect",
      "source-whoop",
      "source-oura",
      "source-strava",
      "source-garmin",
    ],
  );
  assert.deepEqual(
    [...sources.matchAll(/<img src="https:\/\/img\.logo\.dev\/([^?"]+)\?/g)].map((match) => match[1]),
    ["whoop.com", "ouraring.com", "strava.com", "garmin.com"],
  );
  assert.match(sources, /src="assets\/brand-icons\/apple-health\.png"/);
  assert.match(sources, /src="assets\/brand-icons\/health-connect\.png"/);
  assert.doesNotMatch(sources, /<svg|source-more|withings/i);
  assert.match(index, /aria-label="Health data from Apple Health, Health Connect, WHOOP, Oura, Strava, and Garmin flowing privately through Health\.md/);
  assert.match(styles, /\.source-apple-health\s*{\s*top:\s*3%/);
  assert.match(styles, /\.source-garmin\s*{\s*top:\s*83%/);
  assert.match(index, /data-thread-field/);
  const routes = index.match(/<g class="route-lines">([\s\S]*?)<\/g>/)?.[1] ?? "";
  const routeStarts = [...routes.matchAll(/<path d="M(\d+) (\d+)/g)].map((match) => [Number(match[1]), Number(match[2])]);
  assert.deepEqual(routeStarts, [[692, 218], [692, 218], [692, 218], [692, 218]]);
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

test("hero uses official brand marks and licensed Lucide icons", async () => {
  const logoSources = [...index.matchAll(/<img src="(https:\/\/img\.logo\.dev\/[^"]+)"/g)]
    .map((match) => match[1].replaceAll("&amp;", "&"));
  const logoPaths = logoSources.map((source) => new URL(source).pathname);

  assert.equal(logoSources.length, 16);
  assert.deepEqual(logoPaths, [
    "/whoop.com",
    "/ouraring.com",
    "/strava.com",
    "/garmin.com",
    "/dropbox.com",
    "/google.com",
    "/icloud.com",
    "/kaiserpermanente.org",
    "/commonhealth.org",
    "/nodejs.org",
    "/js.org",
    "/python.org",
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
  assert.equal((index.match(/<img src="assets\/brand-icons\/apple-health\.png" width="32" height="32" decoding="async" alt="">/g) ?? []).length, 2);
  assert.match(index, /<img src="assets\/brand-icons\/health-connect\.png" width="32" height="32" decoding="async" alt="">/);
  await Promise.all([
    access(path.join(ROOT, "assets/brand-icons/apple-health.png")),
    access(path.join(ROOT, "assets/brand-icons/health-connect.png")),
  ]);
  assert.equal((index.match(/class="outcome-logo-card/g) ?? []).length, 14);
  assert.match(index, /lucide-square-terminal/);
  assert.match(styles, /\.outcome-icon-card\s*{[\s\S]*?background:\s*rgba\(255, 255, 255, 0\.92\);[\s\S]*?color:\s*#101012/);
  assert.doesNotMatch(index, /sk_[A-Za-z0-9_-]+/);
  assert.match(styles, /\.outcome-stack\s*{[\s\S]*?width:\s*151px;[\s\S]*?display:\s*flex;[\s\S]*?flex:\s*0 0 151px/);
  assert.match(styles, /\.outcome-stack-four \.outcome-logo-card\s*{[\s\S]*?width:\s*40px;[\s\S]*?height:\s*40px/);
  assert.match(styles, /\.outcome-logo-card:nth-child\(1\)[\s\S]*?--card-tilt:\s*-3deg/);
  assert.match(styles, /\.outcome-logo-card \+ \.outcome-logo-card\s*{[\s\S]*?margin-left:\s*-5px/);
  assert.match(styles, /\.outcome-logo-card\s*{[\s\S]*?width:\s*46px;[\s\S]*?height:\s*46px/);
  assert.match(styles, /\n\.outcome-logo-card img\s*{[\s\S]*?width:\s*30px;[\s\S]*?height:\s*30px/);
  assert.match(styles, /\.outcome-logo-card img/);
  assert.match(styles, /\.source-node\s*{[\s\S]*?border-radius:\s*13px;[\s\S]*?background:\s*rgba\(255, 255, 255, 0\.9\)/);
  assert.match(styles, /\.source-node img\s*{[\s\S]*?width:\s*32px;[\s\S]*?height:\s*32px;[\s\S]*?object-fit:\s*contain/);
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
  assert.match(mobileStyles, /\.source-node img\s*{[\s\S]*?width:\s*27px;[\s\S]*?height:\s*27px/);
  assert.doesNotMatch(mobileStyles, /\.source-(?:apple-health|health-connect|whoop|oura|strava|garmin)[^{]*\{[^}]*display:\s*none/);
  assert.match(mobileStyles, /\.flow-art\s*{\s*transform:\s*translateX\(-18%\)/);
  assert.match(mobileStyles, /\.route-lines\s*{[\s\S]*?transform:\s*scaleY\(0\.67\)/);
  assert.match(mobileStyles, /\.outcome\s*{\s*right:\s*0;\s*left:\s*auto/);
  assert.match(mobileStyles, /\.outcome-stack\s*{[\s\S]*?width:\s*108px;[\s\S]*?flex-basis:\s*108px/);
  assert.match(mobileStyles, /\.outcome-files\s*{\s*top:\s*calc\(22% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-doctor\s*{\s*top:\s*calc\(41% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-scripts\s*{\s*top:\s*calc\(59% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-ai\s*{\s*top:\s*calc\(78% - 22px\)/);
  assert.match(mobileStyles, /\.outcome-label\s*{\s*display:\s*none/);
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

test("landing page keeps a restrained light design with the transparent app mark in the flow", () => {
  assert.match(styles, /color-scheme:\s*light/);
  assert.match(styles, /--paper:\s*#fafaf8/);
  assert.doesNotMatch(index, /class="brand-icon"/);
  assert.match(styles, /\.header-shell\s*{[\s\S]*?padding:\s*42px[\s\S]*?13\.7%/);
  assert.match(index, /class="flow-core"[\s\S]*?assets\/app-icon\/healthmd-mark\.png/);
  assert.match(styles, /\.flow-core\s*{[^}]*background:\s*transparent;[^}]*box-shadow:\s*none/);
  assert.match(styles, /--purple:\s*#9465ff/);
  assert.doesNotMatch(index, /brand-mark|hero-axis|hero-route|data-theme-option|assets\/landing-minimal\.css/);
});

test("landing fonts are self-hosted with their license", async () => {
  assert.match(styles, /url\("fonts\/Geist-Variable\.woff2"\)/);
  assert.match(styles, /url\("fonts\/GeistMono-Variable\.woff2"\)/);
  assert.match(styles, /"Hiragino Sans"[\s\S]*?"Apple SD Gothic Neo"[\s\S]*?"PingFang SC"/);
  assert.match(styles, /html:lang\(zh-Hans\)[\s\S]*?line-break:\s*strict/);
  assert.match(styles, /html:lang\(ko\)[\s\S]*?word-break:\s*keep-all/);
  assert.match(styles, /html:lang\(nl\) \.hero-intro h1\s*\{\s*font-size:\s*clamp\(58px, 5vw, 76px\)/);
  assert.match(styles, /\.language-selector\s*\{[\s\S]*?max-height:\s*min\(70vh, 430px\)[\s\S]*?overflow-y:\s*auto/);
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
  assert.match(docsStyles, /"Hiragino Sans"[\s\S]*?"Apple SD Gothic Neo"[\s\S]*?"PingFang SC"/);
  assert.match(docsStyles, /html:lang\(zh-Hans\)[\s\S]*?line-break:\s*strict/);
  assert.match(docsStyles, /html:lang\(ko\)[\s\S]*?word-break:\s*keep-all/);
  assert.doesNotMatch(docsStyles, /cdn\.jsdelivr\.net/);
});

test("language selection lives in the landing and documentation footers", () => {
  assert.match(index, /<div class="footer-language">[\s\S]*?<!-- HEALTHMD_FOOTER_LANGUAGE_SELECTOR -->/);
  assert.doesNotMatch(index.slice(index.indexOf('<header'), index.indexOf('</header>')), /language-menu|language-selector/);
  assert.match(docsConfig, /LanguageSelect: '\.\/src\/components\/EmptyLanguageSelect\.astro'/);
  assert.match(emptyLanguageSelect, /Language selection is rendered in the documentation footer/);
  assert.match(docsFooter, /import LanguageSelect from '@astrojs\/starlight\/components\/LanguageSelect\.astro'/);
  assert.match(docsFooter, /class="healthmd-footer-language"[\s\S]*?<LanguageSelect \/>/);
  assert.match(docsStyles, /\.healthmd-footer-language\s*\{[\s\S]*?margin-inline-start:\s*auto/);
});

test("docs navigation starts with user goals and labels preview surfaces", () => {
  const getStarted = docsUi.indexOf("text('Get Started'");
  const agents = docsUi.indexOf("text('Use an Agent'");
  const exports = docsUi.indexOf("text('Export & Automate'");
  const integrations = docsUi.indexOf("text('Build an Integration'");
  assert.ok(getStarted >= 0 && getStarted < agents);
  assert.ok(agents < exports && exports < integrations);
  assert.match(docsUi, /text\('First iPhone export', 'Primera exportación desde iPhone', 'Erster iPhone-Export'/);
  assert.match(docsUi, /Direct iPhone CLI · Preview/);
  assert.ok((docsUi.match(/collapsed: true/g) ?? []).length >= 5);
  assert.match(docsConfig, /sidebar: starlightSidebar\(\)/);
  assert.match(docsIndex, /Start with Health\.md/);
  assert.match(docsIndex, /Contents\/Helpers\/healthmd" doctor/);
  assert.match(docsIndex, /Ten-minute local agent quickstart/);
  assert.doesNotMatch(docsIndex, /healthmd setup codex/);
  assert.match(configurationGuide, /Available now · signed Mac helper/);
  assert.match(configurationGuide, /Preview · not yet publicly packaged/);
  assert.match(docsHeader, />MCP<|>MCP<\/a>/);
  assert.match(docsHeader, /const docsRoot = routePath\('docsHome', localeCode\)/);
  assert.match(docsHeader, /href=\{`\$\{docsRoot\}\/reference\/`\}/);
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
