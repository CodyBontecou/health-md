import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import { buildFullDashboardModel, FullDashboardComponent, renderFullDashboard, type FullDashboardState } from "../src/dashboard.js";
import { loadHealthData, loadHealthDataText } from "../src/loader.js";

const fixture = resolve(import.meta.dirname, "../../../apps/apple/docs/reference/generated/automation/agent-query-response.json");
const theme = {
  fg: (_color: string, text: string) => text,
  bg: (_color: string, text: string) => text,
  bold: (text: string) => text,
} as any;

test("full dashboard builds semantic metric cards and width-safe visualizations from typed query evidence", async () => {
  const store = await loadHealthData([fixture]);
  const model = buildFullDashboardModel(store);
  assert.equal(model.itemCount, 1);
  assert.equal(model.metrics.length, 1);
  assert.equal(model.availableCount, 1);
  assert.equal(model.metrics[0]?.id, "steps");
  assert.equal(model.metrics[0]?.name, "Steps");
  assert.equal(model.metrics[0]?.points[0]?.value, 12_345);
  const state: FullDashboardState = { screen: "overview", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 };
  for (const width of [60, 100, 160]) {
    const lines = renderFullDashboard(model, state, width, theme);
    assert.ok(lines.length >= 28);
    assert.ok(lines.every(line => visibleWidth(line) <= width), `line overflow at ${width}`);
    const rendered = lines.join("\n");
    assert.match(rendered, /interactive health evidence dashboard/);
    assert.match(rendered, /Steps/);
    assert.match(rendered, /12,345/);
    assert.match(rendered, /Summary/);
    assert.match(rendered, /1 observation/);
    if (width >= 100) assert.match(rendered, /Trend setup · 1 dated day loaded/);
  }
  for (const [width, height] of [[1, 4], [8, 8], [19, 10], [60, 12], [100, 20]] as const) {
    const lines = renderFullDashboard(model, state, width, theme, height);
    assert.ok(lines.length <= height);
    assert.ok(lines.every(line => visibleWidth(line) <= width), `responsive overflow at ${width}x${height}`);
  }
});

test("full dashboard renders connected unit-aware trends instead of isolated dots", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-full-dashboard-trend-"));
  const file = join(directory, "trend.json");
  await writeFile(file, JSON.stringify({ metrics: [3600, 5400, 4500].map((value, index) => ({ owner_date: `2026-01-0${index + 1}`, semantic_id: "sleep_total", display_name: "Total Sleep", unit: "s", number: value })) }));
  const model = buildFullDashboardModel(await loadHealthData([file]));
  const state: FullDashboardState = { screen: "metric", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 };
  const rendered = renderFullDashboard(model, state, 120, theme).join("\n");
  assert.match(rendered, /Latest 1h 15m 0s/);
  assert.match(rendered, /Observed average 1h 15m 0s/);
  assert.match(rendered, /[\u2801-\u28ff]/);
  assert.match(rendered, /2026-01-01.*2026-01-03/);
  assert.match(rendered, /AUTO→LINE/);
  assert.match(rendered, /Selected 2026-01-03/);
  assert.doesNotMatch(rendered, /snapshot, not a trend/);
  state.chartMode = "bar";
  const bars = renderFullDashboard(model, state, 120, theme).join("\n");
  assert.match(bars, /Relative bars for 3 visible observations/);
  assert.match(bars, /2026-01-01.*█.*1h 0m 0s/);
});

test("summary provides period comparisons and identity-safe sleep/activity views", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-full-dashboard-summary-"));
  const file = join(directory, "summary.json");
  const steps = Array.from({ length: 14 }, (_, index) => ({ owner_date: `2026-01-${String(index + 1).padStart(2, "0")}`, semantic_id: "steps", display_name: "Steps", unit: "steps", number: index < 7 ? 100 : 110 }));
  const stages = [["sleep_total", "Total Sleep", 14400], ["sleep_deep", "Deep Sleep", 3600], ["sleep_core", "Core Sleep", 7200], ["sleep_rem", "REM Sleep", 3600], ["sleep_awake", "Awake", 1800]].map(([semantic_id, display_name, number]) => ({ owner_date: "2026-01-14", semantic_id, display_name, unit: "s", number }));
  await writeFile(file, JSON.stringify({ metrics: [...steps, ...stages] }));
  const model = buildFullDashboardModel(await loadHealthData([file]));
  const state: FullDashboardState = { screen: "overview", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 };
  const rendered = renderFullDashboard(model, state, 160, theme, 38).join("\n");
  assert.match(rendered, /↑ 10% vs prior 7d/);
  assert.match(rendered, /Sleep composition · 2026-01-14/);
  assert.match(rendered, /Deep 22%.*Core 44%.*REM 22%.*Awake 11%/);
  assert.match(rendered, /Latest activity observations · independent identities/);
  assert.match(rendered, /Steps.*2026-01-14.*source retained/);
  const rem = model.metrics.find(metric => metric.id === "sleep_rem")!;
  rem.comparisonIdentity = `${rem.comparisonIdentity}-incompatible`;
  assert.doesNotMatch(renderFullDashboard(model, state, 160, theme, 38).join("\n"), /Sleep composition/);

  const hoursFile = join(directory, "hours.json");
  const hourStages = [["sleep_total", 8], ["sleep_deep", 2], ["sleep_core", 4], ["sleep_rem", 2], ["sleep_awake", 1]].map(([semantic_id, number]) => ({ owner_date: "2026-01-14", semantic_id, unit: "h", number }));
  await writeFile(hoursFile, JSON.stringify({ metrics: hourStages }));
  const hoursModel = buildFullDashboardModel(await loadHealthData([hoursFile]));
  const hoursRendered = renderFullDashboard(hoursModel, state, 160, theme, 38).join("\n");
  assert.match(hoursRendered, /Sleep composition.*[\s\S]*9 h/);
  const pieRendered = renderFullDashboard(hoursModel, { ...state, domain: "Sleep" }, 160, theme, 38).join("\n");
  assert.match(pieRendered, /Sleep composition/);
  assert.match(pieRendered, /████|▓▓|▒▒|░░/);
  assert.match(pieRendered, /█ Deep 22%.*▓ Core 44%.*▒ REM 22%.*░ Awake 11%/);
  assert.doesNotMatch(hoursRendered, /9s/);
  const constrained = renderFullDashboard(hoursModel, { ...state, domain: "Sleep" }, 160, theme, 20).join("\n");
  assert.match(constrained, /█ Deep 22%.*▓ Core 44%.*▒ REM 22%.*░ Awake 11%/);
  assert.doesNotMatch(constrained, /Total 9 h/);
  const totalSeries = hoursModel.metrics.find(metric => metric.id === "sleep_total")!;
  hoursModel.metrics.push({ ...totalSeries, key: "unsafe-summary", id: "unsafe", name: "Unsafe", domain: "Other", points: [{ date: "2026-01-14", display: "18446744073709551615", status: "available", numericExpected: true }] });
  const unsafeBoundary = renderFullDashboard(hoursModel, { ...state, domain: "Sleep" }, 160, theme, 29).join("\n");
  assert.match(unsafeBoundary, /█ Deep 22%.*▓ Core 44%.*▒ REM 22%.*░ Awake 11%/);
  assert.doesNotMatch(unsafeBoundary, /Total 9 h/);
  hoursModel.metrics.pop();
  const deep = hoursModel.metrics.find(metric => metric.id === "sleep_deep")!, core = hoursModel.metrics.find(metric => metric.id === "sleep_core")!;
  deep.points[0]!.value = 0; core.points[0]!.value = 6;
  const zeroPie = renderFullDashboard(hoursModel, { ...state, domain: "Sleep" }, 160, theme, 38).join("\n");
  assert.match(zeroPie, /█ Deep 0%/);
  assert.doesNotMatch(zeroPie, /██/);
  deep.points[0]!.value = -1;
  assert.doesNotMatch(renderFullDashboard(hoursModel, state, 160, theme, 38).join("\n"), /Sleep composition/);
  deep.points[0]!.value = 2; deep.points[0]!.status = "failed"; core.points[0]!.value = 4;
  assert.doesNotMatch(renderFullDashboard(hoursModel, state, 160, theme, 38).join("\n"), /Sleep composition/);
});

test("sparse windows are not promoted to seven-day comparisons or trends", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-full-dashboard-sparse-"));
  const file = join(directory, "sparse.json");
  await writeFile(file, JSON.stringify({ metrics: [
    { owner_date: "2026-01-01", semantic_id: "steps", display_name: "Steps", unit: "steps", number: 100 },
    { owner_date: "2026-01-08", semantic_id: "steps", display_name: "Steps", unit: "steps", number: 110 },
  ] }));
  const model = buildFullDashboardModel(await loadHealthData([file]));
  const state: FullDashboardState = { screen: "overview", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 };
  const rendered = renderFullDashboard(model, state, 160, theme).join("\n");
  assert.equal(model.chartableCount, 0);
  assert.match(rendered, /2 disconnected observations/);
  assert.match(rendered, /Insufficient coverage • now 1\/7 · prior 1\/7/);
  assert.doesNotMatch(rendered, /% vs prior 7d/);
  const sparseDetail = renderFullDashboard(model, { ...state, screen: "metric" }, 120, theme).join("\n");
  assert.match(sparseDetail, /AUTO→BAR/);
  assert.match(sparseDetail, /Relative bars for 2 visible observations/);

  const invalidFile = join(directory, "invalid-date.json");
  await writeFile(invalidFile, JSON.stringify({ metrics: [
    { owner_date: "2026-01-01", semantic_id: "steps", unit: "steps", number: 100 },
    { owner_date: "2026-01-02", semantic_id: "steps", unit: "steps", number: 110 },
    { semantic_id: "steps", unit: "steps", number: 120 },
  ] }));
  const invalidModel = buildFullDashboardModel(await loadHealthData([invalidFile]));
  assert.equal(invalidModel.chartableCount, 0);
  const invalidDetail = renderFullDashboard(invalidModel, { ...state, screen: "metric" }, 120, theme).join("\n");
  assert.match(invalidDetail, /Trend unavailable: series contains an undated or invalid-date observation/);

  const mixedFile = join(directory, "mixed-window.json");
  await writeFile(mixedFile, JSON.stringify({ metrics: ["01", "02", "10", "20"].map((day, index) => ({ owner_date: `2026-01-${day}`, semantic_id: "steps", unit: "steps", number: 100 + index })) }));
  const mixedModel = buildFullDashboardModel(await loadHealthData([mixedFile]));
  assert.equal(mixedModel.chartableCount, 1);
  const disconnectedWindow = renderFullDashboard(mixedModel, { ...state, screen: "metric", pointWindow: 2 }, 120, theme).join("\n");
  assert.match(disconnectedWindow, /AUTO→BAR/);
  assert.match(disconnectedWindow, /Relative bars for 2 visible observations/);
  const onePointWindow = renderFullDashboard(mixedModel, { ...state, screen: "metric", pointWindow: 1 }, 120, theme).join("\n");
  assert.match(onePointWindow, /AUTO→SNAPSHOT/);
});

test("full dashboard handles mixed finite extremes and preserves non-observed statuses", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-full-dashboard-extremes-"));
  const extremesFile = join(directory, "extremes.json");
  await writeFile(extremesFile, JSON.stringify({ metrics: [
    { owner_date: "2026-01-01", semantic_id: "x", unit: "count", number: -Number.MAX_VALUE },
    { owner_date: "2026-01-02", semantic_id: "x", unit: "count", number: Number.MAX_VALUE },
  ] }));
  const extremes = buildFullDashboardModel(await loadHealthData([extremesFile]));
  for (const chartMode of ["line", "bar"] as const) {
    const lines = renderFullDashboard(extremes, { screen: "metric", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0, chartMode }, 120, theme);
    assert.ok(lines.every(line => visibleWidth(line) <= 120));
    const rendered = lines.join("\n");
    assert.match(rendered, chartMode === "line" ? /Selected 2026-01-02/ : /Relative bars/);
    assert.doesNotMatch(rendered, /NaN|Infinity/);
  }

  const statusResponse = { schema: "healthmd.query_response", schema_version: 1, items: [
    { type: "metric", metric: { metric_id: "x", display_name: "X", owner_date: "2026-01-01", value: { type: "count", value: 100 }, status: "available", evidence: [], limitations: [] } },
    { type: "metric", metric: { metric_id: "x", display_name: "X", owner_date: "2026-01-02", value: { type: "count", value: 999 }, status: "failed", evidence: [], limitations: [] } },
  ], coverage: { status: "partial", days_considered: 2, days_with_values: 1, requested_range: { start_date: "2026-01-01", end_date: "2026-01-02" }, available_range: { start_date: "2026-01-01", end_date: "2026-01-01" }, missing: [{ range: { start_date: "2026-01-02", end_date: "2026-01-02" }, status: "failed", reason: "source_failed" }], missing_interval_count: 1, missing_truncated: false }, sources: [], evidence: [], limitations: [], next_cursor: null };
  const statusModel = buildFullDashboardModel(loadHealthDataText([{ path: "healthmd-mcp://status", text: JSON.stringify(statusResponse), origin: "healthmd-mcp", operation: "healthmd_metric_chart" }]));
  const statusRendered = renderFullDashboard(statusModel, { screen: "metric", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 }, 120, theme).join("\n");
  assert.match(statusRendered, /Latest 999 count.*failed/);
  assert.match(statusRendered, /healthmd\.query_response@1.*healthmd-mcp.*healthmd_metric_chart/);
  assert.match(statusRendered, /Most recent observed 100 count.*2026-01-01/);
  assert.doesNotMatch(statusRendered, /Average.*549/);
  const statusOverview = renderFullDashboard(statusModel, { screen: "overview", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 }, 120, theme).join("\n");
  assert.match(statusOverview, /Selected · Other.*999 count.*failed/);
});

test("newest fetched revision wins for the same identity and owner date", () => {
  const response = (value: number) => ({ schema: "healthmd.query_response", schema_version: 1, items: [{ type: "metric", metric: { metric_id: "steps", display_name: "Steps", owner_date: "2026-01-01", value: { type: "count", value }, status: "available", evidence: [], limitations: [] } }], coverage: { status: "available", days_considered: 1, days_with_values: 1, requested_range: { start_date: "2026-01-01", end_date: "2026-01-01" }, available_range: { start_date: "2026-01-01", end_date: "2026-01-01" }, missing: [], missing_interval_count: 0, missing_truncated: false }, sources: [], evidence: [], limitations: [], next_cursor: null });
  const model = buildFullDashboardModel(loadHealthDataText([
    { path: "healthmd-cache://new", text: JSON.stringify(response(200)), origin: "healthmd-mcp", operation: "healthmd_metric_chart" },
    { path: "healthmd-cache://old", text: JSON.stringify(response(100)), origin: "healthmd-mcp", operation: "healthmd_metric_chart" },
  ]));
  assert.equal(model.metrics[0]?.points.length, 1);
  assert.equal(model.metrics[0]?.points[0]?.value, 200);
});

test("available and domain filters drive grouped metric navigation", async () => {
  const store = await loadHealthData([fixture]);
  const model = buildFullDashboardModel(store), base = model.metrics[0]!;
  model.metrics.push({ ...base, key: "sleep-unavailable", id: "sleep_total", name: "Total Sleep", domain: "Sleep", statuses: ["unsupported"], points: [{ date: "2026-03-15", display: "—", status: "unsupported", numericExpected: false }] });
  const state: FullDashboardState = { screen: "metric", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0, availableOnly: true, domain: "All" };
  assert.doesNotMatch(renderFullDashboard(model, state, 120, theme).join("\n"), /Total Sleep/);
  state.availableOnly = false;
  assert.match(renderFullDashboard(model, state, 120, theme).join("\n"), /Total Sleep/);
  state.domain = "Sleep";
  state.selected = 1;
  assert.match(renderFullDashboard(model, state, 120, theme).join("\n"), /Sleep · all \(1\)/);
  state.screen = "overview";
  const narrow = renderFullDashboard(model, state, 80, theme).join("\n");
  assert.match(narrow, /navigation all \/ Sleep/);
  assert.match(narrow, /Selected · Sleep.*Total Sleep/);
  assert.doesNotMatch(narrow, /Latest activity observations/);
});

test("dashboard fetch menu launches bounded trend presets", async () => {
  const store = await loadHealthData([fixture]);
  let request: { days: number; ids: string[] } | undefined;
  const component = new FullDashboardComponent({ requestRender() {} }, theme, () => store, () => {}, () => 30, async (days, ids) => { request = { days, ids }; });
  component.handleInput("f");
  assert.match(component.render(120).join("\n"), /Fetch trend data/);
  component.handleInput("2");
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(request, { days: 30, ids: ["steps"] });
  assert.match(component.render(120).join("\n"), /Fetched 30 days/);

  let firstRunIds: string[] = [];
  const empty = new FullDashboardComponent({ requestRender() {} }, theme, () => undefined, () => {}, () => 30, async (_days, ids) => { firstRunIds = ids; });
  assert.match(empty.render(120).join("\n"), /Welcome to Health\.md/);
  empty.handleInput("\r");
  assert.match(empty.render(120).join("\n"), /Fetch trend data/);
  empty.handleInput("\x1b");
  empty.handleInput("f"); empty.handleInput("1");
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(firstRunIds.includes("steps") && firstRunIds.includes("sleep_total") && firstRunIds.length <= 32);

  const cancellable = new FullDashboardComponent({ requestRender() {} }, theme, () => store, () => {}, () => 30, async (_days, _ids, signal) => new Promise((_resolve, reject) => signal.addEventListener("abort", () => reject(new Error("cancelled")), { once: true })));
  cancellable.handleInput("f"); cancellable.handleInput("1"); cancellable.handleInput("\x1b");
  await new Promise(resolve => setImmediate(resolve));
  assert.match(cancellable.render(120).join("\n"), /Fetch cancelled/);
});

test("full dashboard refuses a series containing unsafe exact numeric evidence", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-full-dashboard-exact-"));
  const file = join(directory, "exact.json");
  await writeFile(file, JSON.stringify({ metrics: [
    { owner_date: "2026-01-01", semantic_id: "x", unit: "count", number: { representation: "unsigned_integer", decimal: "1" } },
    { owner_date: "2026-01-02", semantic_id: "x", unit: "count", number: { representation: "unsigned_integer", decimal: "18446744073709551615" } },
  ] }));
  const model = buildFullDashboardModel(await loadHealthData([file]));
  const state: FullDashboardState = { screen: "metric", selected: 0, pointWindow: 1, pointOffset: 1, recordOffset: 0 };
  const rendered = renderFullDashboard(model, state, 120, theme).join("\n");
  assert.match(rendered, /Latest 18446744073709551615/);
  assert.match(rendered, /Chart refused: series contains an unsafe exact numeric value/);
  assert.equal(model.chartableCount, 0);
  state.screen = "overview";
  const overview = renderFullDashboard(model, state, 120, theme).join("\n");
  assert.match(overview, /⚠ unsafe exact: 1 series retained but not charted/);

  const partialText = `{"schema":"healthmd.query_response","schema_version":1,"items":[{"type":"metric","metric":{"metric_id":"x","display_name":"X","owner_date":"2026-01-03","value":{"type":"quantity","value":9223372036854775807,"unit":"count"},"status":"partial","evidence":[],"limitations":[]}}],"coverage":{"status":"partial","days_considered":1,"days_with_values":1,"requested_range":{"start_date":"2026-01-03","end_date":"2026-01-03"},"available_range":{"start_date":"2026-01-03","end_date":"2026-01-03"},"missing":[],"missing_interval_count":0,"missing_truncated":false},"sources":[],"evidence":[],"limitations":[],"next_cursor":null}`;
  const partialModel = buildFullDashboardModel(loadHealthDataText([{ path: "healthmd-mcp://partial", text: partialText, origin: "healthmd-mcp", operation: "healthmd_metric_chart" }]));
  assert.equal(partialModel.metrics[0]?.points[0]?.status, "partial");
  assert.equal(partialModel.chartableCount, 0);
  assert.match(renderFullDashboard(partialModel, { ...state, screen: "metric", pointOffset: 0 }, 120, theme).join("\n"), /Chart refused/);
});

test("full dashboard exposes canonical coverage and non-metric typed records", () => {
  const response = { schema: "healthmd.query_response", schema_version: 1, items: [{ type: "workout", workout: { workout_id: "w1", activity: "Running", start: "2026-08-13T08:00:00Z", end: "2026-08-13T09:00:00Z", details: {}, evidence_ids: [] } }], coverage: { status: "partial", days_considered: 1, days_with_values: 0, requested_range: { start_date: "2026-08-13", end_date: "2026-08-13" }, available_range: null, missing: [{ range: { start_date: "2026-08-13", end_date: "2026-08-13" }, status: "unavailable", reason: "not_recorded" }], missing_interval_count: 1, missing_truncated: false }, sources: [], evidence: [], limitations: [], next_cursor: null };
  const model = buildFullDashboardModel(loadHealthDataText([{ path: "healthmd-mcp://workout", text: JSON.stringify(response), origin: "healthmd-mcp", operation: "healthmd_workouts" }]));
  assert.equal(model.typedItemCount, 1);
  assert.equal(model.typedItems[0]?.label, "Running");
  assert.deepEqual(model.coverage.statuses, ["partial"]);
  assert.equal(model.coverage.missingIntervals, 1);
  const truncated: any = structuredClone(response);
  truncated.coverage.missing_interval_count = 7; truncated.coverage.missing_truncated = true;
  const truncatedModel = buildFullDashboardModel(loadHealthDataText([{ path: "healthmd-mcp://truncated", text: JSON.stringify(truncated), origin: "healthmd-mcp", operation: "healthmd_workouts" }]));
  assert.equal(truncatedModel.coverage.missingIntervals, 7);
  const compactCoverage = renderFullDashboard(truncatedModel, { screen: "coverage", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 }, 120, theme, 20).join("\n");
  assert.match(compactCoverage, /Missing\s+7 total • details truncated/);
  assert.match(compactCoverage, /Sources.*Origins.*Contracts/s);
  const state: FullDashboardState = { screen: "records", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0 };
  assert.match(renderFullDashboard(model, state, 120, theme).join("\n"), /Running/);
  state.screen = "coverage";
  assert.match(renderFullDashboard(model, state, 120, theme).join("\n"), /partial.*0\/1 days with values/);

  const wider: any = structuredClone(response);
  wider.items = [];
  wider.coverage = { status: "partial", days_considered: 3, days_with_values: 2, requested_range: { start_date: "2026-08-12", end_date: "2026-08-14" }, available_range: { start_date: "2026-08-12", end_date: "2026-08-13" }, missing: [{ range: { start_date: "2026-08-14", end_date: "2026-08-14" }, status: "unavailable", reason: "not_recorded" }], missing_interval_count: 1, missing_truncated: false };
  const merged = buildFullDashboardModel(loadHealthDataText([
    { path: "healthmd-mcp://workout", text: JSON.stringify(response), origin: "healthmd-mcp", operation: "healthmd_workouts" },
    { path: "healthmd-mcp://wider", text: JSON.stringify(wider), origin: "healthmd-mcp", operation: "healthmd_metric_chart" },
  ]));
  assert.equal(merged.coverage.daysConsidered, 3);
  assert.equal(merged.coverage.daysWithValues, 2);
  assert.equal(merged.coverage.requestedRange, "2026-08-12..2026-08-14");
});

test("dashboard supports direct domains, metric search, and contextual help", async () => {
  const store = await loadHealthData([fixture]);
  const component = new FullDashboardComponent({ requestRender() {} }, theme, () => store, () => {});
  component.handleInput("?");
  assert.match(component.render(120).join("\n"), /Dashboard help.*1–8.*Search metric/s);
  component.handleInput("?");
  component.handleInput("/");
  for (const character of "steps") component.handleInput(character);
  assert.match(component.render(120).join("\n"), /Search metrics.*steps.*1 matching metric/s);
  component.handleInput("\r");
  assert.match(component.render(120).join("\n"), /search “steps”/);
  component.handleInput("\x15");
  assert.doesNotMatch(component.render(120).join("\n"), /search “steps”/);
  component.handleInput("/");
  component.handleInput("\x1b[200~Steps\x1b[201~");
  assert.match(component.render(120).join("\n"), /Search metrics.*Steps.*1 matching metric/s);
  component.handleInput("\r");
  component.handleInput("2");
  assert.match(component.render(120).join("\n"), /navigation available \/ Activity/);
  component.handleInput("3");
  assert.match(component.render(120).join("\n"), /navigation available \/ Sleep/);
});

test("full dashboard keyboard navigation switches screens and refreshes", async () => {
  const store = await loadHealthData([fixture]);
  let renders = 0, closed = false;
  const component = new FullDashboardComponent({ requestRender: () => { renders++; } }, theme, () => store, () => { closed = true; });
  component.handleInput("d");
  assert.match(component.render(120).join("\n"), /Snapshot/);
  component.handleInput("v");
  assert.match(component.render(120).join("\n"), /BAR/);
  component.handleInput("v");
  assert.match(component.render(120).join("\n"), /LINE/);
  component.handleInput("v");
  assert.match(component.render(120).join("\n"), /AUTO→SNAPSHOT/);
  component.handleInput("\x1b[99;2u"); // Kitty protocol Shift+C
  assert.match(component.render(120).join("\n"), /Coverage & provenance/);
  component.handleInput("r");
  assert.ok(renders >= 3);
  component.handleInput("\x1b");
  assert.equal(closed, true);
});
