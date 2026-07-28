import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const catalogPath = path.join(root, "assets", "visualizations-catalog.json");
const singleGeneratorPath = path.join(root, "scripts", "generate-visualization-og-image.mjs");

const allColors = ["theme", "default", "ocean", "forest", "sunset", "aurora", "monochrome"];
const allThemes = ["dark"];
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
    viz: "all",
    colors: "all",
    themes: "dark",
    force: false,
    limit: 0
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--force") {
      args.force = true;
      continue;
    }
    if (!arg.startsWith("--")) continue;
    const [key, inlineValue] = arg.slice(2).split("=", 2);
    args[key] = inlineValue ?? argv[++i] ?? "";
  }
  return args;
}

function extractVisualizations(document) {
  if (document?.schema !== "healthmd.visualization_catalog" || !Array.isArray(document.visualizations)) {
    throw new Error("Generated visualization catalog is invalid");
  }
  return document.visualizations.map((item) => ({
    id: item.type,
    label: item.label,
    category: item.category,
  }));
}

function listArg(value, fallback) {
  if (!value || value === "all") return fallback;
  return String(value).split(",").map((item) => item.trim()).filter(Boolean);
}

function outputPath(vizId, color, theme) {
  return path.join(root, "assets", "visualization-og", vizId, `${colorSchemeSlugs[color]}-${theme}-theme.png`);
}

async function exists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

const args = parseArgs(process.argv.slice(2));
const catalogDocument = JSON.parse(await fs.readFile(catalogPath, "utf8"));
let visualizations = extractVisualizations(catalogDocument);
const requestedViz = listArg(args.viz, visualizations.map((viz) => viz.id));
visualizations = visualizations.filter((viz) => requestedViz.includes(viz.id));
const colors = listArg(args.colors, allColors);
const themes = listArg(args.themes, allThemes);
const limit = Number(args.limit) || 0;

for (const color of colors) {
  if (!colorSchemeSlugs[color]) throw new Error(`Unknown color scheme: ${color}`);
}
for (const theme of themes) {
  if (theme !== "dark" && theme !== "light") throw new Error(`Unknown theme: ${theme}`);
}
if (!visualizations.length) throw new Error(`No matching visualizations for --viz ${args.viz}`);

const jobs = [];
for (const viz of visualizations) {
  for (const color of colors) {
    for (const theme of themes) {
      jobs.push({ viz, color, theme, outPath: outputPath(viz.id, color, theme) });
    }
  }
}
const selectedJobs = limit > 0 ? jobs.slice(0, limit) : jobs;

let generated = 0;
let skipped = 0;
const failures = [];
const startedAt = Date.now();

for (let index = 0; index < selectedJobs.length; index += 1) {
  const job = selectedJobs[index];
  const label = `${job.viz.id} ${job.color}/${job.theme}`;
  if (!args.force && await exists(job.outPath)) {
    skipped += 1;
    console.log(`[${index + 1}/${selectedJobs.length}] skip ${label}`);
    continue;
  }

  console.log(`[${index + 1}/${selectedJobs.length}] generate ${label}`);
  const result = spawnSync(process.execPath, [
    singleGeneratorPath,
    "--viz", job.viz.id,
    "--colors", job.color,
    "--theme", job.theme,
    "--out", job.outPath
  ], { cwd: root, encoding: "utf8", stdio: "pipe", timeout: 45000 });

  if (result.status === 0) {
    generated += 1;
    continue;
  }
  failures.push({ job, status: result.status, output: `${result.stdout || ""}${result.stderr || ""}`.trim() });
  console.error(`  failed ${label}`);
  if (result.error) console.error(`  ${result.error.message}`);
}

const elapsedSeconds = ((Date.now() - startedAt) / 1000).toFixed(1);
console.log(`OG image batch complete: ${generated} generated, ${skipped} skipped, ${failures.length} failed in ${elapsedSeconds}s.`);

if (failures.length) {
  console.error("Failures:");
  failures.forEach(({ job, status, output }) => {
    console.error(`- ${job.viz.id} ${job.color}/${job.theme} (status ${status})`);
    if (output) console.error(output.split("\n").slice(-8).join("\n"));
  });
  process.exitCode = 1;
}
