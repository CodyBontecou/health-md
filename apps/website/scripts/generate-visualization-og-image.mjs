import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn } from "node:child_process";
import os from "node:os";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const customizerPath = path.join(root, "assets", "visualization-customizer.js");
const sampleDataPath = path.join(root, "assets", "visualizations-data", "health-sample.json");
const pluginPath = path.join(root, "assets", "healthmd-plugin-visualizations.js");
const iconPath = path.join(root, "assets", "app-icon", "icon_1024x1024.png");

const categoryLabels = {
  all: "All data",
  Overview: "Overview & trends",
  Activity: "Activity & fitness",
  Heart: "Heart",
  Sleep: "Sleep",
  Vitals: "Respiratory & vitals",
  Mobility: "Mobility",
  Mindfulness: "Mindfulness & mood",
  Workouts: "Workouts",
  Medications: "Medications"
};

const colorSchemeSlugs = {
  theme: "theme-colors",
  default: "default-colors",
  ocean: "ocean-colors",
  forest: "forest-colors",
  sunset: "sunset-colors",
  aurora: "aurora-colors",
  monochrome: "monochrome-colors"
};

function parseArgs(argv) {
  const args = {
    viz: "activity-rings",
    colors: "ocean",
    theme: "dark",
    out: ""
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const [rawKey, rawValue] = arg.slice(2).split("=", 2);
    const key = rawKey === "color" || rawKey === "colorScheme" ? "colors" : rawKey;
    args[key] = rawValue ?? argv[++i] ?? "";
  }
  if (args.theme !== "dark" && args.theme !== "light") throw new Error("--theme must be dark or light");
  if (!colorSchemeSlugs[args.colors]) throw new Error(`Unknown --colors value: ${args.colors}`);
  return args;
}

function decodeJsString(value) {
  return value.replace(/\\(["\\/bfnrt])/g, (_match, char) => {
    return { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" }[char] || char;
  });
}

function extractVisualization(source, id) {
  const re = /viz\("((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*\[[^\]]*\],\s*(\{[^\n]*?\})\)/g;
  let match;
  while ((match = re.exec(source))) {
    const item = {
      id: decodeJsString(match[1]),
      label: decodeJsString(match[2]),
      category: decodeJsString(match[3]),
      renderer: decodeJsString(match[4]),
      description: decodeJsString(match[5]),
      configSource: match[6]
    };
    if (item.id === id) return item;
  }
  throw new Error(`Visualization not found in visualization-customizer.js: ${id}`);
}

function defaultOutputPath(viz, colors, theme) {
  return path.join(root, "assets", "visualization-og", viz.id, `${colorSchemeSlugs[colors]}-${theme}-theme.png`);
}

function htmlForOgCard({ viz, sampleData, colors, theme }) {
  const isDark = theme === "dark";
  const categoryLabel = categoryLabels[viz.category] || viz.category;
  const titleCategoryLabel = categoryLabel.replace(/\b[a-z]/g, (char) => char.toUpperCase());
  const surface = isDark ? "#000000" : "#ffffff";
  const panel = isDark ? "#000000" : "#ffffff";
  const inset = isDark ? "#1a1a1a" : "#fafafa";
  const text = isDark ? "#ededed" : "#171717";
  const muted = isDark ? "#a0a0a0" : "#4d4d4d";
  const faint = isDark ? "#878787" : "#8f8f8f";
  const border = isDark ? "#ffffff21" : "#0000001a";
  const accent = isDark ? "#a37dbd" : "#8a66aa";
  const chartBg = isDark ? "#000000" : "#ffffff";
  const subtleShadow = isDark ? "0 1px 2px rgba(0,0,0,.16)" : "0 2px 2px rgba(0,0,0,.04)";
  const codeSnippet = `health-viz · ${viz.id} · ${colors} / ${theme}`;

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=1200, initial-scale=1">
  <title>${viz.label} OG Preview</title>
  <script src="${pathToFileURL(pluginPath).href}"></script>
  <style>
    @font-face {
      font-family: "Geist Sans";
      font-style: normal;
      font-weight: 100 900;
      font-display: swap;
      src: url("https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/geist-sans/Geist-Variable.woff2") format("woff2");
    }
    @font-face {
      font-family: "Geist Mono";
      font-style: normal;
      font-weight: 100 900;
      font-display: swap;
      src: url("https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/geist-mono/GeistMono-Variable.woff2") format("woff2");
    }
    * { box-sizing: border-box; }
    html, body { width: 1200px; height: 630px; margin: 0; overflow: hidden; }
    body {
      font-family: "Geist Sans", ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: ${text};
      background: ${surface};
      padding: 40px;
    }
    body.theme-dark { --background-primary: #000000; --background-secondary: #000000; --background-modifier-border: #ffffff21; --text-normal: #ededed; --text-muted: #a0a0a0; --text-faint: #878787; --interactive-accent: ${accent}; --color-accent: ${accent}; --text-accent: ${accent}; }
    body.theme-light { --background-primary: #ffffff; --background-secondary: #fafafa; --background-modifier-border: #0000001a; --text-normal: #171717; --text-muted: #4d4d4d; --text-faint: #8f8f8f; --interactive-accent: ${accent}; --color-accent: ${accent}; --text-accent: ${accent}; }
    .frame {
      width: 1120px;
      height: 550px;
      display: grid;
      grid-template-columns: 416px 1fr;
      gap: 32px;
      border: 1px solid ${border};
      border-radius: 16px;
      background: ${panel};
      box-shadow: ${subtleShadow};
      overflow: hidden;
    }
    .copy {
      min-width: 0;
      display: flex;
      flex-direction: column;
      justify-content: flex-start;
      gap: 88px;
      padding: 28px 32px;
      border-right: 1px solid ${border};
      background: ${panel};
    }
    .brand { display: flex; align-items: center; gap: 12px; color: ${text}; font-size: 24px; font-weight: 600; line-height: 32px; letter-spacing: -0.96px; }
    .brand img { width: 48px; height: 48px; border-radius: 12px; }
    .brand span span { display: block; margin-top: 0; color: ${muted}; font-family: "Geist Mono"; font-size: 12px; font-weight: 400; line-height: 16px; letter-spacing: 0; text-transform: none; }
    .eyebrow { display: block; margin-bottom: 16px; color: ${accent}; font-family: "Geist Mono"; font-size: 13px; font-weight: 400; line-height: 20px; letter-spacing: 0; }
    h1 { margin: 0; color: ${text}; font-size: 56px; font-weight: 600; line-height: 56px; letter-spacing: -3.36px; }
    p { width: 360px; margin: 24px 0 0; color: ${muted}; font-size: 30px; font-weight: 400; line-height: 42px; letter-spacing: -0.6px; }
    .code-card { display: none; }
    .chart-column { min-width: 0; display: flex; flex-direction: column; padding: 32px 32px 32px 0; }
    .chart-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; color: ${muted}; font-family: "Geist Mono"; font-size: 13px; line-height: 20px; }
    .palette { display: inline-flex; align-items: center; gap: 8px; }
    .swatch { width: 10px; height: 10px; border-radius: 9999px; background: ${accent}; box-shadow: 0 0 0 1px ${border}; }
    .chart-wrap { position: relative; flex: 1; display: flex; align-items: center; justify-content: center; min-width: 0; border: 1px solid ${border}; border-radius: 16px; background: ${chartBg}; overflow: hidden; }
    canvas, .html-preview { position: relative; z-index: 1; max-width: 100%; }
    .html-preview { width: 640px; transform: scale(.94); transform-origin: center; }
  </style>
</head>
<body class="theme-${theme}">
  <main class="frame">
    <section class="copy">
      <div class="brand"><img src="${pathToFileURL(iconPath).href}" alt=""><span>Health.md<span>healthmd.app</span></span></div>
      <div>
        <div class="eyebrow">${titleCategoryLabel}</div>
        <h1>${viz.label}</h1>
        <p>${viz.description}</p>
      </div>
      <div class="code-card">${codeSnippet}</div>
    </section>
    <section class="chart-column">
      <div class="chart-header"><span>Obsidian Plugin Preview</span><span class="palette"><span class="swatch"></span>${colors} / ${theme}</span></div>
      <div class="chart-wrap">
        <canvas id="chart" width="1280" height="940" style="width:640px;height:470px"></canvas>
        <div id="html-preview" class="html-preview" hidden></div>
      </div>
    </section>
  </main>
  <script>
    const sampleData = ${JSON.stringify(sampleData)};
    const viz = ${JSON.stringify({ id: viz.id, renderer: viz.renderer })};
    const config = Object.assign({}, ${viz.configSource}, { theme: "${theme}", colorScheme: "${colors}", height: Math.min(Number((${viz.configSource}).height) || 360, 470) });

    function applyCreateOptions(el, options) {
      if (!options) return;
      if (typeof options === "string") { el.className = options; return; }
      if (options.cls) el.className = Array.isArray(options.cls) ? options.cls.join(" ") : options.cls;
      if (options.text !== undefined) el.textContent = String(options.text);
      if (options.attr) Object.keys(options.attr).forEach((key) => el.setAttribute(key, String(options.attr[key])));
    }
    window.activeWindow = window;
    window.activeDocument = document;
    HTMLElement.prototype.empty = HTMLElement.prototype.empty || function () { this.textContent = ""; };
    HTMLElement.prototype.createDiv = HTMLElement.prototype.createDiv || function (options) { const el = document.createElement("div"); applyCreateOptions(el, options); this.appendChild(el); return el; };
    HTMLElement.prototype.createSpan = HTMLElement.prototype.createSpan || function (options) { const el = document.createElement("span"); applyCreateOptions(el, options); this.appendChild(el); return el; };
    HTMLElement.prototype.createEl = HTMLElement.prototype.createEl || function (tag, options) { const el = document.createElement(tag); applyCreateOptions(el, options); this.appendChild(el); return el; };
    HTMLElement.prototype.addClass = HTMLElement.prototype.addClass || function (className) { String(className || "").split(/\s+/).filter(Boolean).forEach((name) => this.classList.add(name)); };
    HTMLElement.prototype.removeClass = HTMLElement.prototype.removeClass || function (className) { String(className || "").split(/\s+/).filter(Boolean).forEach((name) => this.classList.remove(name)); };

    function parseDate(value) { return new Date(value + "T00:00:00"); }
    function addDays(date, amount) { const next = new Date(date); next.setDate(next.getDate() + amount); return next; }
    function toIsoDate(date) { return date.toISOString().slice(0, 10); }
    function filteredData(cfg) {
      let data = sampleData.slice();
      let from = cfg.from;
      const to = cfg.to;
      if (cfg.last && to) from = toIsoDate(addDays(parseDate(to), -(Number(cfg.last) - 1)));
      if (from) data = data.filter((day) => day.date >= from);
      if (to) data = data.filter((day) => day.date <= to);
      return data;
    }
    function pluginSettings() {
      return {
        theme: "${theme}", colorScheme: "${colors}", defaultWidth: 760, defaultHeight: 360, maxHeartRate: 190,
        colorAccent: "#0ea5e9", colorSecondary: "#38bdf8", colorHeart: "#e11d48",
        colorSleepDeep: "#0c2461", colorSleepRem: "#1d4ed8", colorSleepCore: "#0ea5e9", colorSleepAwake: "#7dd3fc",
        mapTilesEnabled: false, mapTileUrl: "", mapTileAttribution: "", dataPointClickAction: "pin"
      };
    }
    function fallbackTheme() {
      return { bg: "${isDark ? "#05060a" : "#ffffff"}", fg: "${text}", muted: "${muted}", isDark: ${isDark}, colors: { accent: "#0ea5e9", secondary: "#38bdf8", heart: "#e11d48", sleep: { deep: "#0c2461", rem: "#1d4ed8", core: "#0ea5e9", awake: "#7dd3fc" } }, maxHeartRate: 190, mapTilesEnabled: false };
    }
    const api = window.HealthMdPluginVisualizations;
    const themeObj = api.resolveTheme ? api.resolveTheme(pluginSettings(), config) : fallbackTheme();
    const renderer = viz.renderer === "html" ? api.htmlRenderers[viz.id] : api.renderers[viz.id];
    if (!renderer) throw new Error("Renderer not found: " + viz.id);
    if (viz.renderer === "html") {
      document.getElementById("chart").hidden = true;
      const html = document.getElementById("html-preview");
      html.hidden = false;
      renderer(filteredData(config), html, config, themeObj);
    } else {
      const canvas = document.getElementById("chart");
      const ctx = canvas.getContext("2d");
      ctx.setTransform(2, 0, 0, 2, 0, 0);
      renderer(ctx, filteredData(config), 640, 470, config, themeObj, document.createElement("div"), { add() {} });
    }
    window.__OG_READY__ = true;
  </script>
</body>
</html>`;
}

const args = parseArgs(process.argv.slice(2));
const [customizerSource, sampleDataRaw] = await Promise.all([
  fs.readFile(customizerPath, "utf8"),
  fs.readFile(sampleDataPath, "utf8")
]);
const viz = extractVisualization(customizerSource, args.viz);
const sampleData = JSON.parse(sampleDataRaw);
const outPath = path.resolve(root, args.out || defaultOutputPath(viz, args.colors, args.theme));
await fs.mkdir(path.dirname(outPath), { recursive: true });
await fs.rm(outPath, { force: true });

const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "healthmd-og-"));
const tempHtmlPath = path.join(tempDir, `${viz.id}-${args.colors}-${args.theme}.html`);
await fs.writeFile(tempHtmlPath, htmlForOgCard({ viz, sampleData, colors: args.colors, theme: args.theme }));

const chromePath = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const userDataDir = path.join(tempDir, "chrome-profile");
const chromeArgs = [
  "--headless=new",
  "--disable-gpu",
  "--hide-scrollbars",
  "--no-first-run",
  "--no-default-browser-check",
  `--user-data-dir=${userDataDir}`,
  "--window-size=1200,630",
  "--force-device-scale-factor=1",
  "--timeout=3000",
  "--run-all-compositor-stages-before-draw",
  `--screenshot=${outPath}`,
  pathToFileURL(tempHtmlPath).href
];

async function waitForScreenshot(filePath, child, timeoutMs = 15000) {
  const startedAt = Date.now();
  var stderr = "";
  var stdout = "";
  child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
  child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });

  while (Date.now() - startedAt < timeoutMs) {
    try {
      const stat = await fs.stat(filePath);
      if (stat.size > 0) {
        await new Promise((resolve) => setTimeout(resolve, 250));
        if (!child.killed) child.kill("SIGTERM");
        return;
      }
    } catch {
      // Keep waiting for Chrome to write the screenshot.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  if (!child.killed) child.kill("SIGKILL");
  throw new Error(`Chrome screenshot timed out.\n${stderr || stdout}`);
}

const chrome = spawn(chromePath, chromeArgs, { stdio: ["ignore", "pipe", "pipe"] });
chrome.on("error", (error) => { throw error; });
await waitForScreenshot(outPath, chrome);
await new Promise((resolve) => chrome.once("close", resolve));

await fs.rm(tempDir, { recursive: true, force: true });
console.log(`Generated ${path.relative(root, outPath)}`);
console.log(`Visualization: ${viz.label} (${viz.id}), ${args.colors} colors, ${args.theme} theme`);
