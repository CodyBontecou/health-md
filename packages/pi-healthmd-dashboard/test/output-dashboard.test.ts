import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { createController } from "../src/extension.js";
import { jsonStringify, utf8ByteLength } from "../src/json.js";
import { loadHealthData } from "../src/loader.js";
import { initialView } from "../src/model.js";
import { formatEvidence, queryStore } from "../src/query.js";
import { renderDashboard, selectedEntries, visibleWidth } from "../src/render.js";
import { updateView } from "../src/view.js";

const repo = resolve(import.meta.dirname, "../../..");

test("actual formatted query result including provenance is strictly within 24k", async () => {
  const store = await loadHealthData([join(repo, "packages/contracts/proposals/unified-health-data-v9/fixtures/apple-whoop.json")]);
  const formatted = formatEvidence(queryStore(store, { limit: 100 }));
  assert.ok(utf8ByteLength(jsonStringify(formatted)) <= 24_000);
  assert.ok("omittedForSize" in formatted);
});

test("load result shape used by controller can be bounded below Pi limit", async () => {
  const controller = createController();
  await controller.approveAndLoad([join(repo, "packages/contracts/proposals/unified-health-data-v9/fixtures")]);
  const query = controller.query({ limit: 100 });
  assert.ok(utf8ByteLength(jsonStringify(query)) <= 24_000);
});

test("structured Unicode evidence is previewed without defeating byte bounds", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-unicode-bound-"));
  const file = join(dir, "unicode.json");
  await writeFile(file, JSON.stringify({ records: Array.from({ length: 500 }, (_, index) => ({ index, note: "健康🫀".repeat(500) })) }));
  const store = await loadHealthData([file]);
  const result = queryStore(store, { path: "$", limit: 100 });
  const formatted = formatEvidence(result);
  assert.ok(result.evidenceBytes <= 24_000);
  assert.ok(utf8ByteLength(jsonStringify(formatted)) <= 24_000);
  assert.ok(queryStore(store, { search: "健康🫀", limit: 5 }).totalMatches > 0);
});

test("provider path/search targets chart and mixed provider/unit series refuse misleading scale", async () => {
  const store = await loadHealthData([join(repo, "apps/apple/docs/reference/generated/core/provider-day.json")]);
  let view = updateView(initialView(), { action: "select", target: "hrv_rmssd_ms", targetKind: "path" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /█/);
  let broad = updateView(initialView(), { action: "select", target: "whoop", targetKind: "search" });
  broad = updateView(broad, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, broad, 100).join("\n"), /mixed contract\/schema\/path\/unit\/statistic\/provider\/platform/);
  const dir = await mkdtemp(join(tmpdir(), "healthmd-mixed-"));
  const file = join(dir, "mixed.json");
  await writeFile(file, JSON.stringify({ providers: { whoop: [{ date: "2026-01-01", unit: "ms", value: 1 }], other: [{ date: "2026-01-02", unit: "seconds", value: 2 }] } }));
  const mixed = await loadHealthData([file]);
  view = updateView(initialView(), { action: "select", target: ".value", targetKind: "path" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(mixed, view, 100).join("\n"), /mixed contract\/schema\/path\/unit\/statistic\/provider\/platform/);
});

test("charts refuse mixed safe/unsafe exact values and cross-contract series", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-chart-safety-"));
  const exact = join(dir, "exact.json");
  await writeFile(exact, JSON.stringify({ metrics: [
    { owner_date: "2026-01-01", semantic_id: "x", statistic: "latest", unit: "count", number: { representation: "unsigned_integer", decimal: "1" } },
    { owner_date: "2026-01-02", semantic_id: "x", statistic: "latest", unit: "count", number: { representation: "unsigned_integer", decimal: "18446744073709551615" } },
  ] }));
  let store = await loadHealthData([exact]);
  let view = updateView(initialView(), { action: "select", target: "x", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /unsafe exact values.*table fallback/i);

  const apple = join(dir, "apple.json"), android = join(dir, "android.json");
  const record = { owner_date: "2026-01-01", semantic_id: "x", statistic: "latest", unit: "count", value: 1 };
  await writeFile(apple, JSON.stringify({ schema: "healthmd.health_data", schema_version: 8, records: [record] }));
  await writeFile(android, JSON.stringify({ type: "health-data", records: [{ ...record, owner_date: "2026-01-02" }] }));
  store = await loadHealthData([apple, android]);
  view = updateView(initialView(), { action: "select", target: "x", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /mixed contract\/schema\/path\/unit\/statistic\/provider\/platform/);
});

test("charts retain exact schema identity within the same generic contract kind", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-schema-series-"));
  const first = join(dir, "v1.json"), second = join(dir, "v2.json");
  await writeFile(first, JSON.stringify({ schema: "healthmd.example", schema_version: 1, records: [{ owner_date: "2026-01-01", semantic_id: "x", unit: "count", value: 1 }] }));
  await writeFile(second, JSON.stringify({ schema: "healthmd.example", schema_version: 2, records: [{ owner_date: "2026-01-02", semantic_id: "x", unit: "count", value: 2 }] }));
  const store = await loadHealthData([first, second]);
  const evidence = JSON.stringify(formatEvidence(queryStore(store, { metric: "x", limit: 100 })));
  assert.match(evidence, /"schemaVersion":"1"/);
  assert.match(evidence, /"schemaVersion":"2"/);
  let view = updateView(initialView(), { action: "select", target: "x", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /mixed contract\/schema\/path/);
});

test("semantic-ID searches reach exact numeric descendants", async () => {
  const store = await loadHealthData([join(repo, "packages/contracts/proposals/unified-health-data-v9/fixtures/apple-minimal.json")]);
  assert.ok(queryStore(store, { search: "steps", limit: 100 }).matches.some(entry => entry.path.endsWith(".number")));
  let view = updateView(initialView(), { action: "select", target: "steps", targetKind: "search" });
  view = updateView(view, { action: "mode", mode: "chart" });
  assert.match(renderDashboard(store, view, 100).join("\n"), /█/);
});

test(">100 records are filtered/sorted before pagination with owner date and timestamp separate", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-many-"));
  const file = join(dir, "many.json");
  const records = Array.from({ length: 150 }, (_, i) => ({ owner_date: `2026-${String(Math.floor(i / 28) + 1).padStart(2, "0")}-${String(i % 28 + 1).padStart(2, "0")}`, start_time: `2026-01-01T00:${String(i % 60).padStart(2, "0")}:00Z`, semantic_id: "x", statistic: "latest", unit: "count", number: i }));
  await writeFile(file, JSON.stringify({ records: records.reverse() }));
  const store = await loadHealthData([file]);
  let view = updateView(initialView(), { action: "select", target: "x", targetKind: "metric" });
  view = updateView(view, { action: "date_window", startDate: "2026-01-01", endDate: "2026-06-30" });
  view = { ...view, windowSize: 120, offset: 0 };
  const selected = selectedEntries(store, view);
  assert.ok(selected.length > 100);
  assert.ok(selected.every(entry => entry.ownerDate && entry.recordTimestamp));
  assert.ok(selected.every((entry, i) => i === 0 || (selected[i - 1]!.date ?? "") <= (entry.date ?? "")));
});

test("render respects exact widths including 8 columns and CJK/emoji visible widths and stays compact", async () => {
  const store = await loadHealthData([join(repo, "packages/contracts/proposals/unified-health-data-v9/fixtures/apple-minimal.json")]);
  for (const width of [8, 20, 40]) {
    const lines = renderDashboard(store, initialView(), width);
    assert.ok(lines.length <= 10);
    assert.ok(lines.every(line => visibleWidth(line) <= width));
  }
  assert.equal(visibleWidth("健康"), 4);
  assert.equal(visibleWidth("🫀"), 2);
  assert.equal(visibleWidth("👨‍👩‍👧‍👦"), 2);
});
