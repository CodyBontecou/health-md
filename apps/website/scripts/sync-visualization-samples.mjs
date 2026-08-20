#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const websiteRoot = path.resolve(__dirname, "..");
const repositoryRoot = path.resolve(websiteRoot, "..", "..");
const configuredPluginRepo = process.env.HEALTHMD_OBSIDIAN_PLUGIN_REPO;
if (!configuredPluginRepo) {
  throw new Error("Set HEALTHMD_OBSIDIAN_PLUGIN_REPO to a checkout of CodyBontecou/health-md-visualizations.");
}
const pluginRepo = path.resolve(configuredPluginRepo);
const outputDirectory = path.join(websiteRoot, "assets", "visualizations-data");
const dailyOutput = path.join(outputDirectory, "health-sample.json");
const rollupOutput = path.join(outputDirectory, "health-rollups.json");
const startDate = process.env.HEALTHMD_VISUALIZATION_SAMPLE_START_DATE || "2026-04-18";
const endDate = process.env.HEALTHMD_VISUALIZATION_SAMPLE_END_DATE || "2026-05-17";

function addDays(dateIso, amount) {
  const date = new Date(`${dateIso}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}

function isoWeekId(dateIso) {
  const date = new Date(`${dateIso}T00:00:00Z`);
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const year = date.getUTCFullYear();
  const yearStart = new Date(Date.UTC(year, 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

function alignRollupToSample(rawRollup) {
  const daysExpected = rawRollup.rollup_period === "weekly"
    ? 7
    : Math.max(1, Number(rawRollup.days_expected) || 1);
  const start = addDays(endDate, 1 - daysExpected);
  const count = Math.max(1, Math.min(daysExpected, Number(rawRollup.days_counted) || 1));
  const sourceDates = Array.from({ length: count }, (_unused, index) =>
    addDays(start, count === 1 ? 0 : Math.round(index * (daysExpected - 1) / (count - 1)))
  );
  return {
    ...rawRollup,
    period_id: rawRollup.rollup_period === "weekly"
      ? isoWeekId(endDate)
      : `${start}_to_${endDate}`,
    start_date: start,
    end_date: endDate,
    source_dates: sourceDates,
    days_expected: daysExpected,
    days_counted: count,
    coverage_percent: count / daysExpected * 100,
    generated_at: `${endDate}T23:59:59Z`,
  };
}

function runNode(script, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script], {
      cwd: pluginRepo,
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        if (stdout.trim()) console.log(stdout.trim());
        resolve();
      } else {
        reject(new Error(`Mock-data generator failed (${code}): ${stderr.trim() || stdout.trim()}`));
      }
    });
  });
}

const generator = path.join(pluginRepo, "scripts", "generate-mock-health-data.mjs");
const historicalWeeklyFixture = path.join(
  repositoryRoot,
  "apps",
  "apple",
  "docs",
  "reference",
  "generated",
  "rollups",
  "weekly.json"
);
const rangeFixture = path.join(pluginRepo, "tests", "fixtures", "rollup-summary-v9", "range-v9.json");
await Promise.all([
  fs.access(generator),
  fs.access(historicalWeeklyFixture),
  fs.access(rangeFixture),
]);

const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "healthmd-site-viz-data-"));
try {
  await runNode(generator, {
    HEALTHMD_MOCK_OUTPUT_DIR: tmpDir,
    HEALTHMD_MOCK_START_DATE: startDate,
    HEALTHMD_MOCK_END_DATE: endDate,
  });
  const filenames = (await fs.readdir(tmpDir))
    .filter((filename) => /^\d{4}-\d{2}-\d{2}\.json$/.test(filename))
    .sort();
  if (!filenames.length) throw new Error("Plugin mock-data generator produced no daily JSON files");
  const days = await Promise.all(filenames.map(async (filename) =>
    JSON.parse(await fs.readFile(path.join(tmpDir, filename), "utf8"))
  ));
  if (days.some((day) => day.schema !== "healthmd.health_data" || day.schema_version !== 8)) {
    throw new Error("Plugin mock-data generator must produce only healthmd.health_data v8 daily samples");
  }
  const rawRollups = await Promise.all([historicalWeeklyFixture, rangeFixture].map(async (fixture) =>
    JSON.parse(await fs.readFile(fixture, "utf8"))
  ));
  const rangeRollup = rawRollups[1];
  if (
    rangeRollup.schema !== "healthmd.rollup_summary"
    || rangeRollup.schema_version !== 9
    || rangeRollup.rollup_period !== "range"
    || rangeRollup.source_schema !== "healthmd.health_data"
    || rangeRollup.source_schema_version !== 8
  ) {
    throw new Error("Plugin range fixture must be a healthmd.rollup_summary v9 sourced from healthmd.health_data v8");
  }
  const rollups = rawRollups.map(alignRollupToSample);

  await fs.mkdir(outputDirectory, { recursive: true });
  await Promise.all([
    fs.writeFile(dailyOutput, `${JSON.stringify(days)}\n`, "utf8"),
    fs.writeFile(rollupOutput, `${JSON.stringify(rollups, null, 2)}\n`, "utf8"),
  ]);
  console.log(`Wrote ${path.relative(websiteRoot, dailyOutput)} with ${days.length} privacy-safe plugin-generated days`);
  console.log(`Wrote ${path.relative(websiteRoot, rollupOutput)} with historical v8 weekly and v9 range examples aligned to the sample window`);
} finally {
  await fs.rm(tmpDir, { recursive: true, force: true });
}
