import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import test from "node:test";
import vm from "node:vm";
import { publishedLocales } from "../i18n/locales.mjs";
import { withWhoopSamples } from "../scripts/whoop-visualization-samples.mjs";

const read = (file) => readFile(new URL(file, import.meta.url), "utf8");
const json = async (file) => JSON.parse(await read(file));
const ids = ["whoop-recovery-strain", "whoop-sleep-need", "whoop-sleep-trends", "whoop-workout-strain"];
const colors = ["theme", "default", "ocean", "forest", "sunset", "aurora", "monochrome"];
const [days, catalog, template] = await Promise.all([
  json("../assets/visualizations-data/health-sample.json"),
  json("../assets/visualizations-catalog.json"),
  json("../../../packages/contracts/proposals/provider-sections-v1/fixtures/whoop-complete.providers.json"),
]);

function withoutWhoop(day) {
  const result = structuredClone(day);
  if (result.providers) {
    delete result.providers.whoop;
    if (!Object.keys(result.providers).length) delete result.providers;
  }
  return result;
}

test("WHOOP gallery samples are reproducible, synthetic, and never alter canonical Apple fields", () => {
  const base = days.map(withoutWhoop);
  const before = JSON.stringify({ base, template });
  const generated = withWhoopSamples(base, template.whoop);
  assert.deepEqual(generated, days);
  assert.deepEqual(generated.map(withoutWhoop), base);
  assert.equal(JSON.stringify({ base, template }), before, "generation must not mutate inputs");
  assert.throws(() => withWhoopSamples(base, { ...template.whoop, schema_version: 3 }), /WHOOP daily v1\/v2/);
  const moved = withWhoopSamples([{ ...base[0], date: "2027-01-05" }], template.whoop)[0];
  assert.match(moved.providers.whoop.cycles[0].id, /synthetic-20270105$/);
  assert.equal(moved.providers.whoop.fetched_at.slice(0, 10), moved.date);
});

test("WHOOP v2 samples preserve physiological-cycle steps without altering daily Apple steps", async () => {
  const current = await json("../../../packages/contracts/provider-sections/v2/fixtures/whoop-complete.providers.json");
  const base = days.slice(0, 2).map((day) => ({ ...withoutWhoop(day), schema_version: 10 }));
  const generated = withWhoopSamples(base, current.whoop);
  assert.deepEqual(generated.map(withoutWhoop), base);
  assert.ok(generated.every((day) => day.providers.whoop.schema_version === 2));
  assert.ok(generated.every((day) => day.providers.whoop.cycles[0].step_count === 8234));
  assert.throws(() => withWhoopSamples(days, current.whoop), /daily v10/);
});

test("WHOOP demo records preserve IDs, millisecond precision, relationships, missingness, and capture counts", () => {
  const allIds = new Set();
  let naps = 0, partial = 0, negativeAdjustment = 0, missingNeed = 0, pending = 0;
  for (const day of days) {
    const whoop = day.providers.whoop;
    assert.equal(whoop.schema, "healthmd.provider.whoop_daily");
    assert.equal(whoop.schema_version, 1);
    assert.ok(!("body" in whoop), "current body profiles are not historical daily records");
    const resources = { cycles: whoop.cycles, recovery: whoop.recoveries, sleep: whoop.sleep, workouts: whoop.workouts };
    for (const resource of whoop.resources) {
      assert.equal(resource.record_count, resources[resource.resource].length);
      if (resource.status === "failure") {
        assert.equal(whoop.capture_status, "partial");
        assert.equal(typeof resource.error.retryable, "boolean");
        assert.equal(resource.record_count, 0);
      }
    }
    partial += whoop.capture_status === "partial" ? 1 : 0;
    for (const record of [...whoop.cycles, ...whoop.sleep, ...whoop.workouts]) {
      assert.equal(typeof record.id, "string");
      assert.match(record.id, /synthetic/);
      assert.ok(!allIds.has(record.id));
      allIds.add(record.id);
      assert.ok(Date.parse(record.start_time) < Date.parse(record.end_time));
      assert.ok(Date.parse(record.end_time) <= Date.parse(whoop.fetched_at));
      for (const [key, value] of Object.entries(record)) {
        if (key.endsWith("_milliseconds")) assert.ok(Number.isInteger(value), key);
        if (key.endsWith("_percent")) assert.ok(value >= 0 && value <= 100, key);
        if (key === "strain_score") assert.ok(value >= 0 && value <= 21);
      }
    }
    for (const recovery of whoop.recoveries) {
      assert.ok(whoop.cycles.some(({ id }) => id === recovery.cycle_id));
      assert.ok(whoop.sleep.some(({ id }) => id === recovery.sleep_id));
      if (recovery.score_state === "PENDING_SCORE") {
        pending += 1;
        assert.ok(!("recovery_score_percent" in recovery));
      } else assert.ok(recovery.recovery_score_percent >= 0 && recovery.recovery_score_percent <= 100);
    }
    for (const sleep of whoop.sleep) {
      assert.equal(sleep.cycle_id, whoop.cycles[0].id);
      assert.equal(sleep.total_sleep_milliseconds, sleep.light_sleep_milliseconds + sleep.slow_wave_sleep_milliseconds + sleep.rem_sleep_milliseconds);
      assert.equal(sleep.total_in_bed_milliseconds, sleep.total_sleep_milliseconds + sleep.awake_milliseconds + sleep.no_data_milliseconds);
      naps += sleep.is_nap ? 1 : 0;
      negativeAdjustment += sleep.recent_nap_adjustment_milliseconds < 0 ? 1 : 0;
      missingNeed += sleep.sleep_debt_need_milliseconds === undefined ? 1 : 0;
    }
    for (const workout of whoop.workouts) {
      const durations = Object.values(workout.zone_durations);
      assert.equal(durations.length, 6);
      assert.ok(durations.every((value) => Number.isInteger(value) && value >= 0));
      assert.ok(durations.reduce((a, b) => a + b, 0) < Date.parse(workout.end_time) - Date.parse(workout.start_time));
    }
  }
  assert.ok(naps > 0 && partial > 0 && negativeAdjustment > 0 && missingNeed > 0 && pending > 0);
  assert.ok(days.some((day) => day.providers.whoop.workouts.length > 1));
  assert.ok(days.some((day) => day.providers.whoop.sleep.some((sleep) => sleep.start_time.slice(0, 10) < day.date)));
});

class Stats {
  constructor(text = "") { this.text = text; this.children = []; this.style = {}; this.classList = { add() {}, remove() {} }; }
  empty() { this.text = ""; this.children = []; }
  createDiv(options = {}) { const child = new Stats(options.text || ""); this.children.push(child); return child; }
  allText() { return [this.text, ...this.children.map((child) => child.allText())].join(" "); }
}

test("the actual shipped browser bundle parses and renders all four WHOOP previews at mobile and desktop sizes", async () => {
  // Leaflet's feature detection runs when the shared bundle loads, even though
  // WHOOP renderers use only canvas. No map or external tiles are requested.
  const document = { documentElement: { style: {} }, createElement: () => ({ style: {}, getContext() {} }), addEventListener() {} };
  const navigator = { userAgent: "", platform: "Linux" };
  const window = { document, navigator, devicePixelRatio: 1, addEventListener() {}, removeEventListener() {} };
  const sandbox = { window, document, navigator, console };
  vm.runInNewContext(await read("../assets/healthmd-plugin-visualizations.js"), sandbox);
  const api = sandbox.window.HealthMdPluginVisualizations;
  const current = await json("../../../packages/contracts/provider-sections/v2/fixtures/whoop-complete.providers.json");
  current.whoop.cycles[0].step_count = 0;
  const v10 = { ...withoutWhoop(days[0]), schema_version: 10, providers: current };
  const migrated = api.parseHealthDay(v10);
  assert.equal(migrated.whoop.cycles[0].step_count, 0);
  assert.equal(migrated.steps, api.parseHealthDay(withoutWhoop(v10)).steps);
  const parsed = days.map(api.parseHealthDay);
  assert.ok(parsed.every((day) => day.whoop?.source === "typed"));
  for (const [index, day] of parsed.entries()) {
    assert.equal(JSON.stringify(day.providers.whoop), JSON.stringify(days[index].providers.whoop));
    assert.equal(day.steps, api.parseHealthDay(withoutWhoop(days[index])).steps);
  }
  for (const id of ids) {
    const item = catalog.visualizations.find(({ type }) => type === id);
    assert.equal(item.category, "whoop");
    assert.equal(item.renderer, "canvas");
    assert.equal(typeof api.renderers[id], "function");
    assert.deepEqual(item.exportSources, id === "whoop-sleep-need" ? ["daily-json", "daily-csv"] : ["daily-json", "daily-csv", "daily-markdown"]);
    for (const width of [340, 900]) {
      for (const isDark of [true, false]) {
        const regions = [], operations = [];
        const canvas = { width, height: 180, style: {} };
        const ctx = new Proxy({ canvas }, {
          get(target, key) {
            if (key in target) return target[key];
            return (...args) => {
              for (const arg of args) if (typeof arg === "number") assert.ok(Number.isFinite(arg), `${id}: finite ${String(key)}`);
              operations.push({ key, args });
            };
          },
        });
        const stats = new Stats("stale");
        const theme = { bg: isDark ? "#101010" : "#ffffff", fg: isDark ? "#eeeeee" : "#171717", muted: "#888888", isDark, colors: { accent: "#5b8ff9", secondary: "#61d9a5" } };
        api.renderers[id](ctx, parsed, width, 180, { type: id, sleep: "all", limit: 180 }, theme, stats, { add(region) { regions.push(region); } });
        assert.ok(regions.length > 0, `${id} has interactive data, not an empty chart`);
        assert.ok(operations.some(({ key }) => key === "fillRect"));
        assert.match(stats.allText(), /partial capture\(s\)/);
        assert.ok(!stats.allText().includes("stale"));
      }
    }
  }
});

test("all WHOOP palette routes, sitemap entries, and translated examples are generated", async () => {
  const sitemap = await read("../sitemap.xml");
  for (const id of ids) {
    for (const category of ["whoop", "all-health-data"]) {
      for (const color of colors) {
        const route = `/visualizations/${category}/${id}/${color}-colors/`;
        const page = await read(`..${route}index.html`);
        assert.ok(page.includes(`rel="canonical" href="https://healthmd.app${route}"`));
        assert.match(page, /WHOOP connection requirements/);
        assert.ok(page.includes("data-whoop-preview-note>"));
        assert.ok(sitemap.includes(`https://healthmd.app${route}`));
        assert.ok(page.includes(`https://healthmd.app/assets/visualization-og/${id}/${color}-colors-dark-theme.png`));
      }
    }
    for (const color of colors) {
      const png = await readFile(new URL(`../assets/visualization-og/${id}/${color}-colors-dark-theme.png`, import.meta.url));
      assert.equal(png.subarray(1, 4).toString(), "PNG");
      assert.equal(png.readUInt32BE(16), 1200);
      assert.equal(png.readUInt32BE(20), 630);
    }
  }
  for (const locale of publishedLocales("docs")) {
    const prefix = locale.path ? `${locale.path}/` : "";
    const guide = await read(`../docs-src/src/content/docs/${prefix}visualizations-roadmap.md`);
    assert.ok(guide.includes(`<strong>${catalog.visualizations.length}</strong>`));
    for (const id of ids) {
      assert.ok(guide.includes(`/visualizations/whoop/${id}/theme-colors/`), `${locale.code}: ${id} link`);
      assert.ok(guide.includes(`\`\`\`health-viz\ntype: ${id}\n`), `${locale.code}: ${id} example`);
    }
    assert.match(guide, /RMSSD/);
    assert.match(guide, /SDNN/);
    assert.match(guide, /Raw API Snapshots/);
  }
});

test("OG generation completes when Chrome exits immediately after writing its screenshot", { skip: process.platform === "win32" }, async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "healthmd-whoop-og-test-"));
  try {
    const chrome = path.join(temp, "mock-chrome.mjs");
    const output = path.join(temp, "preview.png");
    await writeFile(chrome, `#!${process.execPath}\nimport fs from 'node:fs/promises';\nconst output = process.argv.find((arg) => arg.startsWith('--screenshot=')).slice('--screenshot='.length);\nawait fs.writeFile(output, 'mock screenshot');\n`, { mode: 0o700 });
    const result = await promisify(execFile)(process.execPath, [
      fileURLToPath(new URL("../scripts/generate-visualization-og-image.mjs", import.meta.url)),
      "--viz", "whoop-recovery-strain", "--colors", "theme", "--out", output,
    ], { env: { ...process.env, CHROME_PATH: chrome }, timeout: 10_000 });
    assert.match(result.stdout, /Generated/);
    assert.doesNotMatch(result.stderr, /unsettled top-level await/);
    assert.equal(await readFile(output, "utf8"), "mock screenshot");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
