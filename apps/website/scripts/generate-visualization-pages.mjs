import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const templatePath = path.join(root, "visualizations", "index.html");
const customizerPath = path.join(root, "assets", "visualization-customizer.js");
const sitemapPath = path.join(root, "sitemap.xml");
const siteOrigin = "https://healthmd.app";
const lastmod = "2026-06-25";

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

const dataFilterSlugs = {
  all: "all-health-data",
  Overview: "overview-trends",
  Activity: "activity-fitness",
  Heart: "heart-health",
  Sleep: "sleep-analysis",
  Vitals: "respiratory-vitals",
  Mobility: "mobility-gait",
  Mindfulness: "mindfulness-mood",
  Workouts: "workout-analytics",
  Medications: "medication-adherence"
};

const colorSchemes = ["theme", "default", "ocean", "forest", "sunset", "aurora", "monochrome"];
const colorSchemeLabels = {
  theme: "Theme",
  default: "Default",
  ocean: "Ocean",
  forest: "Forest",
  sunset: "Sunset",
  aurora: "Aurora",
  monochrome: "Monochrome"
};
const colorSchemeSlugs = Object.fromEntries(colorSchemes.map((scheme) => [scheme, `${scheme}-colors`]));
colorSchemeSlugs.theme = "theme-colors";

function decodeJsString(value) {
  return value.replace(/\\(["\\/bfnrt])/g, (_match, char) => {
    return { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t" }[char] || char;
  });
}

function extractVisualizations(source) {
  const re = /viz\("((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*"((?:\\"|[^"])*)",\s*\[[^\]]*\],\s*\{/g;
  const items = [];
  let match;
  while ((match = re.exec(source))) {
    items.push({
      id: decodeJsString(match[1]),
      label: decodeJsString(match[2]),
      category: decodeJsString(match[3]),
      renderer: decodeJsString(match[4]),
      description: decodeJsString(match[5])
    });
  }
  if (!items.length) throw new Error("No visualizations found in visualization-customizer.js");
  return items;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;"
  })[char]);
}

function pagePath(viz, dataFilter, colorScheme = "theme") {
  return `/visualizations/${dataFilterSlugs[dataFilter]}/${viz.id}/${colorSchemeSlugs[colorScheme]}/`;
}

function pageTitle(viz) {
  return `${viz.label} — Health.md ${categoryLabels[viz.category] || viz.category} Visualization`;
}

function pageDescription(viz, dataFilter, colorScheme) {
  const themeDescription = colorScheme === "theme" ? "current theme" : `the ${colorSchemeLabels[colorScheme] || colorScheme} theme`;
  return `${viz.description} Copy the Obsidian health-viz block, inspect required Apple Health permissions, and share this exact ${categoryLabels[dataFilter] || dataFilter} preview with ${themeDescription}.`;
}

function replaceHead(template, viz, dataFilter, colorScheme, ogImageUrl) {
  const url = `${siteOrigin}${pagePath(viz, dataFilter, colorScheme)}`;
  const title = pageTitle(viz);
  const description = pageDescription(viz, dataFilter, colorScheme);
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: `Health.md ${viz.label} visualization`,
    applicationCategory: "HealthApplication",
    operatingSystem: "iOS, macOS, Obsidian",
    url,
    description,
    isPartOf: {
      "@type": "WebSite",
      name: "Health.md",
      url: siteOrigin
    },
    keywords: ["Apple Health", "Obsidian", "Health.md", "health visualization", viz.category, viz.id, colorScheme].join(", ")
  };

  let html = template
    .replace(/<title>.*?<\/title>/s, `<title>${escapeHtml(title)}</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${escapeHtml(description)}">`)
    .replace(/<link rel="canonical" href="[^"]*">/, `<link rel="canonical" href="${escapeHtml(url)}">`)
    .replace(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${escapeHtml(title)}">`)
    .replace(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${escapeHtml(description)}">`)
    .replace(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${escapeHtml(url)}">`)
    .replace(/<meta property="og:image" content="[^"]*">/, `<meta property="og:image" content="${escapeHtml(ogImageUrl)}">`)
    .replace(/<meta name="twitter:title" content="[^"]*">/, `<meta name="twitter:title" content="${escapeHtml(title)}">`)
    .replace(/<meta name="twitter:description" content="[^"]*">/, `<meta name="twitter:description" content="${escapeHtml(description)}">`)
    .replace(/<meta name="twitter:image" content="[^"]*">/, `<meta name="twitter:image" content="${escapeHtml(ogImageUrl)}">`);

  html = html.replace(/\n  <script type="application\/ld\+json" data-viz-schema>[\s\S]*?<\/script>/, "");
  html = html.replace("\n</head>", `\n  <script type="application/ld+json" data-viz-schema>${JSON.stringify(jsonLd)}</script>\n</head>`);
  return html;
}

async function removeGeneratedPages() {
  const visualizationsRoot = path.join(root, "visualizations");
  const generatedRoots = new Set(Object.values(dataFilterSlugs));
  const categoryDirs = await fs.readdir(visualizationsRoot, { withFileTypes: true });
  await Promise.all(categoryDirs.filter((entry) => entry.isDirectory() && generatedRoots.has(entry.name)).map(async (entry) => {
    await fs.rm(path.join(visualizationsRoot, entry.name), { recursive: true, force: true });
  }));
}

async function visualizationOgImageUrl(viz, colorScheme, theme = "dark") {
  const relativePath = `/assets/visualization-og/${viz.id}/${colorSchemeSlugs[colorScheme]}-${theme}-theme.png`;
  try {
    await fs.access(path.join(root, relativePath));
    return `${siteOrigin}${relativePath}`;
  } catch {
    return `${siteOrigin}/assets/app-icon/icon_1024x1024.png`;
  }
}

async function updateSitemap(visualizations) {
  const sitemap = await fs.readFile(sitemapPath, "utf8");
  const start = "  <!-- BEGIN GENERATED VISUALIZATION URLS -->";
  const end = "  <!-- END GENERATED VISUALIZATION URLS -->";
  const urls = visualizations.map((viz) => {
    const loc = `${siteOrigin}${pagePath(viz, viz.category, "theme")}`;
    return [
      "  <url>",
      `    <loc>${escapeHtml(loc)}</loc>`,
      `    <lastmod>${lastmod}</lastmod>`,
      "    <changefreq>weekly</changefreq>",
      "    <priority>0.7</priority>",
      "  </url>"
    ].join("\n");
  }).join("\n");
  const block = `${start}\n${urls}\n${end}`;
  let next;
  const markerRe = new RegExp(`\\n  <!-- BEGIN GENERATED VISUALIZATION URLS -->[\\s\\S]*?  <!-- END GENERATED VISUALIZATION URLS -->`);
  if (markerRe.test(sitemap)) {
    next = sitemap.replace(markerRe, `\n${block}`);
  } else {
    next = sitemap.replace("\n</urlset>", `\n${block}\n</urlset>`);
  }
  await fs.writeFile(sitemapPath, next);
}

const [template, customizer] = await Promise.all([
  fs.readFile(templatePath, "utf8"),
  fs.readFile(customizerPath, "utf8")
]);
const visualizations = extractVisualizations(customizer);
await removeGeneratedPages();

let written = 0;
for (const viz of visualizations) {
  for (const dataFilter of ["all", viz.category]) {
    for (const colorScheme of colorSchemes) {
      const route = pagePath(viz, dataFilter, colorScheme);
      const dir = path.join(root, route);
      await fs.mkdir(dir, { recursive: true });
      const ogImageUrl = await visualizationOgImageUrl(viz, colorScheme);
      await fs.writeFile(path.join(dir, "index.html"), replaceHead(template, viz, dataFilter, colorScheme, ogImageUrl));
      written += 1;
    }
  }
}

await updateSitemap(visualizations);
console.log(`Generated ${written} visualization SEO pages for ${visualizations.length} visualizations.`);
