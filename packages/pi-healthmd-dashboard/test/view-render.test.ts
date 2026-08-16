import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { loadHealthData } from "../src/loader.js";
import { initialView } from "../src/model.js";
import { renderDashboard } from "../src/render.js";
import { updateView } from "../src/view.js";

const fixture = resolve(import.meta.dirname, "../../../packages/contracts/proposals/unified-health-data-v9/fixtures/android-minimal.json");

test("view selection, date window, zoom, pan, show/hide and reset are deterministic", () => {
  let view = initialView();
  view = updateView(view, { action: "select", target: "steps", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  view = updateView(view, { action: "date_window", startDate: "2026-07-01", endDate: "2026-07-31" });
  const before = view.windowSize;
  view = updateView(view, { action: "zoom_in" });
  assert.ok(view.windowSize < before);
  view = updateView(view, { action: "pan_right" });
  assert.ok(view.offset > 0);
  view = updateView(view, { action: "pan_left" });
  assert.equal(view.offset, 0);
  view = updateView(view, { action: "hide" });
  assert.equal(view.visible, false);
  view = updateView(view, { action: "reset" });
  assert.equal(view.visible, false);
  assert.equal(view.mode, "table");
  view = updateView(view, { action: "show" });
  assert.equal(view.visible, true);
  view = updateView(view, { action: "reset" });
  assert.equal(view.visible, true);
});

test("overview shows canonical typed-query metric values without requiring manual selection", async () => {
  const queryFixture = resolve(import.meta.dirname, "../../../apps/apple/docs/reference/generated/automation/agent-query-response.json");
  const store = await loadHealthData([queryFixture]);
  const rendered = renderDashboard(store, initialView(), 100).join("\n");
  assert.match(rendered, /metric:overview • table • 1 shown/);
  assert.match(rendered, /12345/);
  assert.doesNotMatch(rendered, /No matching loaded evidence/);
});

test("responsive chart and table rendering is width-safe and exposes source/date/coverage/context", async () => {
  const store = await loadHealthData([fixture]);
  let view = updateView(initialView(), { action: "select", target: "steps", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  for (const width of [20, 40, 80, 120]) {
    const lines = renderDashboard(store, view, width);
    assert.ok(lines.length > 3);
    assert.ok(lines.every(line => line.length <= Math.max(20, width)), `line overflow at ${width}`);
    const text = lines.join("\n");
    assert.match(text, width >= 40 ? /EXPERIMENTAL proposed v9 reader/ : /EXPERIMENTAL/);
    assert.match(text, width >= 40 ? /Source:/ : /Coverage:/);
    assert.match(text, /Coverage:/);
  }
  const chart = renderDashboard(store, view, 100).join("\n");
  assert.match(chart, /█/);
});

test("chart scaling remains finite for binary64 extremes and displays negative zero", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-extreme-chart-"));
  const file = join(directory, "extremes.json");
  await writeFile(file, '{"points":[{"owner_date":"2026-01-01","semantic_id":"x","statistic":"latest","unit":"count","value":-1.7976931348623157e308},{"owner_date":"2026-01-02","semantic_id":"x","statistic":"latest","unit":"count","value":-0},{"owner_date":"2026-01-03","semantic_id":"x","statistic":"latest","unit":"count","value":1.7976931348623157e308}]}');
  const store = await loadHealthData([file]);
  let view = updateView(initialView(), { action: "select", target: "x", targetKind: "metric" });
  view = updateView(view, { action: "mode", mode: "chart" });
  const rendered = renderDashboard(store, view, 120).join("\n");
  assert.match(rendered, /█/);
  assert.match(rendered, /-0/);
});

test("structured and unsafe exact values use table fallback", async () => {
  const store = await loadHealthData([fixture]);
  let view = updateView(initialView(), { action: "select", target: "$.capture", targetKind: "path" });
  view = updateView(view, { action: "mode", mode: "chart" });
  const rendered = renderDashboard(store, view, 80).join("\n");
  assert.match(rendered, /table fallback/i);
  assert.match(rendered, /PATH/);
});
