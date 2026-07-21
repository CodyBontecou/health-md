import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const expectedV7Visualizations = [
  "metric-trend",
  "cardio-fitness-freshness",
  "rollup-explorer",
  "capture-coverage-calendar",
  "blood-pressure-bands",
  "glucose-range",
  "body-composition",
  "running-form",
  "cycling-performance",
  "hearing-exposure",
  "nutrition-grid",
  "symptom-heatmap",
  "cycle-timeline",
  "medication-schedule-timeline",
  "medication-skip-reasons",
];

async function readJson(path) {
  return JSON.parse(await readFile(new URL(path, import.meta.url), "utf8"));
}

test("generated website catalog includes every plugin visualization exactly once", async () => {
  const catalog = await readJson("../assets/visualizations-catalog.json");
  assert.equal(catalog.schema, "healthmd.visualization_catalog");
  assert.equal(catalog.schemaVersion, 1);
  assert.ok(Array.isArray(catalog.visualizations));
  const ids = catalog.visualizations.map((item) => item.type);
  assert.equal(new Set(ids).size, ids.length);
  assert.ok(ids.length >= 58);
  for (const id of expectedV7Visualizations) assert.ok(ids.includes(id), id);
  for (const item of catalog.visualizations) {
    assert.ok(item.label, item.type);
    assert.ok(item.description, item.type);
    assert.ok(item.category, item.type);
    assert.ok(item.renderer === "canvas" || item.renderer === "html", item.type);
  }
});

test("Visualization Studio derives availability from the generated plugin catalog", async () => {
  const [customizer, pageGenerator, bundleGenerator] = await Promise.all([
    readFile(new URL("../assets/visualization-customizer.js", import.meta.url), "utf8"),
    readFile(new URL("../scripts/generate-visualization-pages.mjs", import.meta.url), "utf8"),
    readFile(new URL("../scripts/build-plugin-visualizations.mjs", import.meta.url), "utf8"),
  ]);
  assert.match(customizer, /buildVisualizationsFromPluginCatalog/);
  assert.match(customizer, /Array\.isArray\(api\.catalog\)/);
  assert.match(customizer, /Object\.assign\(\{\}, curated\?\.config \|\| \{\}, generatedConfig\)/);
  assert.match(pageGenerator, /visualizations-catalog\.json/);
  assert.doesNotMatch(pageGenerator, /extractVisualizations\(source\)/);
  assert.match(bundleGenerator, /VISUALIZATION_CATALOG/);
  assert.match(bundleGenerator, /visualizations-catalog\.json/);
});

test("plugin-generated preview fixtures cover v7 views without Health Records payloads", async () => {
  const [days, rollups] = await Promise.all([
    readJson("../assets/visualizations-data/health-sample.json"),
    readJson("../assets/visualizations-data/health-rollups.json"),
  ]);
  assert.equal(days.length, 30);
  assert.ok(days.some((day) => day.body && day.nutrition && day.symptoms && day.reproductiveHealth));
  assert.deepEqual(new Set(days.map((day) => day.raw_capture_status)), new Set(["complete", "partial", "not_requested"]));
  assert.equal(rollups[0]?.schema, "healthmd.rollup_summary");
  assert.ok(rollups[0].start_date >= days[0].date);
  assert.ok(rollups[0].end_date <= days.at(-1).date);

  const serialized = JSON.stringify({ days, rollups }).toLowerCase();
  for (const forbidden of ["fhir_resource", "clinical_record", "verifiable_clinical", "cda_document", "original_uuid"]) {
    assert.ok(!serialized.includes(forbidden), forbidden);
  }
});

test("generated plugin source map is reproducible and contains no local checkout paths", async () => {
  const sourceMap = await readJson("../assets/healthmd-plugin-visualizations.js.map");
  const serialized = JSON.stringify({ sources: sourceMap.sources, sourcesContent: sourceMap.sourcesContent });
  assert.ok(!serialized.includes("/Users/"));
  assert.ok(!serialized.includes("/private/var/"));
  assert.ok(!serialized.includes("github.workspace"));
});
