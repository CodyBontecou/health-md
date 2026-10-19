import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createContext, runInContext } from "node:vm";
import { parseHTML, type HTMLElement } from "linkedom";

const publicDir = resolve(import.meta.dirname, "../public");
const asset = (name: string) => readFileSync(resolve(publicDir, name), "utf8");
const metrics = [
  { id: "steps", label: "Steps", unit: "steps" },
  { id: "resting_heart_rate", label: "Resting Heart Rate", unit: "bpm" },
  { id: "sleep_total", label: "Total Sleep", unit: "hours" },
];
// Fictional values only. No retained owner data or credentials are used.
function syntheticTrends() {
  return {
    version: 1, window: { start: "2026-03-01", end: "2026-03-30" }, metrics,
    days: Array.from({ length: 30 }, (_, index) => ({
      date: `2026-03-${String(index + 1).padStart(2, "0")}`,
      status: index === 0 ? "not_uploaded" : index === 1 ? "unsupported_profile" : index === 2 ? "read_limit" : "available",
      values: {
        steps: index < 3 ? null : index === 29 ? 0 : 1000 + index * 100,
        resting_heart_rate: index < 3 ? null : 60 + index % 6,
        sleep_total: index < 3 || index === 28 ? null : 6 + index % 3,
      },
    })),
  };
}
function setup(result: {
  version: number; window: { start: string | null; end: string | null };
  metrics: typeof metrics; days: ReturnType<typeof syntheticTrends>["days"];
} = syntheticTrends(), mobile = false) {
  const { document, window } = parseHTML(asset("dashboard.html"));
  document.body.dataset.page = "none";
  // linkedom does not model native <select> default selection/value mutation.
  for (const [id, value] of [["summary-evidence", "all"], ["summary-page-size", "10"]]) {
    Object.defineProperty(document.getElementById(id), "value", { writable: true, value });
  }
  const fetch = vi.fn(async (_path: string, _options?: unknown): Promise<{
    ok: boolean; status?: number; json: () => Promise<unknown>;
  }> => ({ ok: true, json: async () => structuredClone(result) }));
  const location = { pathname: "/dashboard", hash: "", replace: vi.fn(), reload: vi.fn() };
  const history = { pushState: vi.fn(), replaceState: vi.fn() };
  const context = createContext({ document, window, location, history, Event: window.Event, CustomEvent: window.CustomEvent,
    matchMedia: () => ({ matches: mobile, addEventListener: vi.fn() }), fetch });
  runInContext(asset("dashboard.js"), context);
  runInContext('Object.assign(dashboardView.capabilities, { sessions: true, securityActivity: true, accountExport: true, supplements: true, deletionStatus: "supported" })', context);
  const evaluate = <T = unknown>(source: string): T => runInContext(source, context);
  const node = (id: string) => document.getElementById(id)!;
  const click = (selector: string) => document.querySelector<HTMLElement>(selector)!.click();
  const change = (id: string, value: string, event = "change") => {
    node(id).value = value;
    node(id).dispatchEvent(new window.Event(event));
  };
  return { document, window, context, evaluate, node, click, change, fetch };
}

describe("first-party dashboard layout and privacy", () => {
  it("keeps all assets same-origin, unique control IDs, and working labels", () => {
    const { document } = parseHTML(asset("dashboard.html"));
    const ids = [...document.querySelectorAll("[id]")].map((node) => node.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const label of document.querySelectorAll("label[for]")) {
      expect(ids).toContain(label.getAttribute("for"));
    }
    for (const tag of document.querySelectorAll("script[src],link[rel=stylesheet]")) {
      expect(tag.getAttribute("src") || tag.getAttribute("href")).toMatch(/^\/[a-z.]+$/u);
    }
    expect(document.querySelectorAll(".data-tabs [role=tab]")).toHaveLength(3);
    expect(document.querySelector("#summary-table caption")?.textContent).toContain("Missing values are not zero");
    expect(asset("dashboard.js")).not.toMatch(/localStorage|sessionStorage|document\.cookie|console\.|innerHTML|insertAdjacentHTML/u);
    expect(asset("dashboard.html")).not.toMatch(/<iframe|on(?:click|load)=|healthmd:\/\//iu);
  });

  it("fetches only the existing bounded owner-session summaries, without dates in URLs", async () => {
    const app = setup();
    await app.evaluate("showTrends()");
    expect(app.fetch).toHaveBeenCalledWith("/api/dashboard/trends", expect.objectContaining({
      method: "GET", credentials: "same-origin", cache: "no-store", headers: {},
    }));
    expect(app.document.querySelectorAll("#trend-cards .stat-card")).toHaveLength(3);
    expect(app.node("trend-cards").getAttribute("aria-busy")).toBe("false");
    expect(app.node("summary-body").querySelectorAll("tr")).toHaveLength(10);
    expect(app.node("summary-body").textContent).toContain("0 steps");
    expect(app.node("trend-cards").textContent).toContain("Latest value");
    expect(app.node("trend-cards").textContent).toContain("Change vs Mar 29");
    expect(app.node("trend-cards").textContent).not.toMatch(/NaN|Infinity|undefined/u);
  });

  it("reloads an in-flight old template instead of initializing new controls against missing markup", async () => {
    const app = setup();
    const reload = vi.fn();
    app.context.location = { reload };
    app.node("sidebar-toggle").remove();
    await app.evaluate("initDashboard()");
    expect(reload).toHaveBeenCalledOnce();
    expect(app.fetch).not.toHaveBeenCalled();
  });

  it("detects optional capabilities without cookies, credentials, or reading health response bodies", async () => {
    const app = setup();
    const readBody = vi.fn();
    app.fetch.mockImplementation(async () => ({ ok: false, status: 401, json: readBody }));
    await app.evaluate("detectDashboardCapabilities()");
    expect(app.fetch).toHaveBeenCalledTimes(5);
    for (const [, options] of app.fetch.mock.calls) {
      expect(options).toMatchObject({ credentials: "omit", cache: "no-store" });
    }
    expect(readBody).not.toHaveBeenCalled();
    expect(app.evaluate("dashboardView.capabilities.deletionStatus")).toBe("supported");
    expect(app.node("session-management").hidden).toBe(false);
    expect(app.node("delete-account-form").hidden).toBe(false);
  });

  it("keeps the seven-migration pilot usable without unsupported controls or invented retention roles", async () => {
    const app = setup();
    app.fetch.mockImplementationOnce(async () => ({ ok: false, status: 404, json: async () => ({}) }));
    app.fetch.mockImplementation(async () => ({ ok: false, status: 404, json: async () => ({}) }));
    await app.evaluate("detectDashboardCapabilities()");
    expect(app.node("session-management").hidden).toBe(true);
    expect(app.node("security-activity").hidden).toBe(true);
    expect(app.evaluate("dashboardView.capabilities.deletionStatus")).toBe("legacy");
    expect(app.node("delete-account-form").hidden).toBe(false);
    app.fetch.mockImplementation(async () => ({ ok: true, json: async () => syntheticTrends() }));
    await app.evaluate("showTrends()");
    expect(app.node("summary-body").querySelectorAll("tr")).toHaveLength(10);
    expect(app.node("summary-body").textContent).not.toContain("Review supplements");
    app.context.legacyExport = [{ id: "00000000-0000-4000-8000-000000000000", source: "ios",
      dateStart: "2026-03-01", dateEnd: "2026-03-01", recordCount: 1, receivedAt: "2026-03-02T12:00:00Z" }];
    app.evaluate("document.getElementById('export-list').replaceChildren(); appendExports(legacyExport)");
    expect(app.node("export-list").textContent).toContain("Not reported");
    expect(app.node("export-list").textContent).not.toContain("Revision / unreferenced");
    app.evaluate('showDeletionPending(null, "Background deletion pending; confirm with operator")');
    expect(app.node("deletion-receipt-section").hidden).toBe(true);
    expect(app.node("deletion-status-token").value).toBe("");
  });

  it("does not infer legacy deletion from failed, unexpected-success, or unavailable probes", async () => {
    for (const code of [200, 403, 503]) {
      const app = setup();
      app.fetch.mockImplementation(async () => ({ ok: code === 200, status: code, json: async () => ({}) }));
      await app.evaluate("detectDashboardCapabilities()");
      expect(app.evaluate("dashboardView.capabilities.deletionStatus")).toBe("unknown");
      expect(app.node("delete-account-form").hidden).toBe(true);
      expect(app.node("deletion-copy").textContent).toContain("No deletion request has been sent");
    }
  });

  it("clears data, credentials, and in-memory state on deletion and ignores late trend responses", async () => {
    const app = setup();
    await app.evaluate("showTrends()");
    app.node("new-token").value = "synthetic-token-not-a-real-secret";
    app.node("new-agent-token").value = "synthetic-agent-not-a-real-secret";
    app.node("summary-filter").value = "2026-03-30";
    app.evaluate('showDeletionPending("synthetic-receipt-not-a-real-secret", "Deletion pending")');
    expect(app.evaluate("dashboardView.result")).toBeNull();
    expect(app.evaluate("dashboardView.disabled")).toBe(true);
    for (const id of ["main-chart", "summary-body", "trend-cards", "column-options", "session-list"]) {
      expect(app.node(id).textContent).toBe("");
    }
    for (const id of ["new-token", "new-agent-token", "summary-filter"]) expect(app.node(id).value).toBe("");
    expect(app.node("agents-section").hidden).toBe(true);
    expect(app.node("deletion-status-token").value).toBe("synthetic-receipt-not-a-real-secret");
    await app.evaluate("showTrends()");
    app.evaluate("refreshTrendViews(); renderSummaryTable()");
    expect(app.node("summary-body").textContent).toBe("");
    expect(app.node("main-chart").textContent).toBe("");
    expect(app.evaluate("dashboardView.result")).toBeNull();
  });
});

describe("metric evidence and gap-safe charts", () => {
  it("never connects null, unmapped, read-limited, or missing days, and keeps measured zero", () => {
    const app = setup();
    app.context.syntheticDays = [
      { date: "2026-03-01", status: "available", values: { steps: 0 } },
      { date: "2026-03-02", status: "available", values: { steps: 10 } },
      { date: "2026-03-03", status: "available", values: { steps: null } },
      { date: "2026-03-04", status: "available", values: { steps: 20 } },
      { date: "2026-03-05", status: "unsupported_profile", values: { steps: 999 } },
      { date: "2026-03-06", status: "available", values: { steps: 30 } },
      { date: "2026-03-07", status: "read_limit", values: { steps: 999 } },
      { date: "2026-03-08", status: "not_uploaded", values: { steps: 999 } },
      { date: "2026-03-09", status: "available", values: { steps: 40 } },
    ];
    expect(app.evaluate("trendSegments({id:'steps'}, syntheticDays, i => i, v => v).map(segment => segment.map(point => point.value))"))
      .toEqual([[0, 10], [20], [30], [40]]);
    expect(app.evaluate("dayLabel(syntheticDays[0], 'steps', 'steps')")).toBe("0 steps");
    expect(app.evaluate("dayLabel(syntheticDays[2], 'steps', 'steps')")).toBe("Value unavailable");
    expect(app.evaluate("dayLabel(syntheticDays[4], 'steps', 'steps')")).toBe("No reviewed Apple mapping");
  });

  it("uses unit-bearing absolute change rather than misleading percentages from zero", () => {
    const app = setup();
    expect(app.evaluate("trendChange({id:'steps',unit:'steps'}, [{status:'available',values:{steps:0}}, {status:'available',values:{steps:10}}])"))
      .toBe("+10 steps");
    expect(app.evaluate("trendChange({id:'steps',unit:'steps'}, [])")).toBe("No comparison");
  });

  it("changes chart metric and 7/14/30-day views without requesting or inventing more data", async () => {
    const app = setup();
    app.evaluate("initDashboardViews()");
    await app.evaluate("showTrends()");
    app.click('#trend-ranges [data-range="7"]');
    expect(app.node("summary-count").textContent).toBe("7");
    expect(app.node("summary-body").querySelectorAll("tr")).toHaveLength(7);
    expect(app.node("main-chart").querySelector("svg")?.getAttribute("aria-label")).toContain("7 of 7");
    app.click('#trend-metrics [data-metric="sleep_total"]');
    expect(app.node("chart-unit").textContent).toContain("hours");
    expect(app.node("chart-coverage").textContent).toBe("6 of 7 calendar days observed");
    expect(app.node("main-chart").querySelectorAll(".trend-area")).toHaveLength(1);
    expect(app.node("main-chart").querySelectorAll(".trend-dot")).toHaveLength(6);
    app.click('#trend-ranges [data-range="14"]');
    expect(app.node("summary-count").textContent).toBe("14");
    app.click('#trend-ranges [data-range="30"]');
    expect(app.node("summary-count").textContent).toBe("30");
    expect(app.fetch).toHaveBeenCalledTimes(1);
  });

  it("uses readable, width-matched chart coordinates and finite scales at zero", async () => {
    const app = setup();
    Object.defineProperty(app.node("main-chart"), "clientWidth", { value: 306 });
    await app.evaluate("showTrends()");
    expect(app.node("main-chart").querySelector("svg")?.getAttribute("viewBox")).toBe("0 0 306 270");
    expect(app.evaluate("trendScale([0]).ticks")).toEqual([0, 0.5]);
    expect(app.evaluate("trendScale([10451]).ticks")).toEqual([0, 5000, 10000, 15000]);
  });

  it("shows genuine empty states with no seeded or zero-filled readings", async () => {
    const result = { ...syntheticTrends(), days: [], window: { start: null, end: null } };
    const app = setup(result);
    await app.evaluate("showTrends()");
    expect(app.node("main-chart").textContent).toContain("No retained daily exports yet");
    expect(app.node("main-chart").querySelector("svg")).toBeNull();
    expect(app.node("trend-cards").textContent).toContain("No value in this window");
    expect(app.node("summary-body").textContent).toContain("No daily exports to display");
    expect(app.node("summary-next").disabled).toBe(true);
  });
});

describe("data table controls and retained actions", () => {
  it("filters dates/evidence, sorts numbers with missing values last, hides columns, and pages", async () => {
    const app = setup();
    app.evaluate("initDashboardViews()");
    await app.evaluate("showTrends()");
    app.click("#summary-next");
    expect(app.node("summary-page-label").textContent).toBe("Page 2 of 3");
    app.change("summary-page-size", "20");
    expect(app.node("summary-page-label").textContent).toBe("Page 1 of 2");
    expect(app.node("summary-body").querySelectorAll("tr")).toHaveLength(20);
    app.change("summary-filter", "03-30", "input");
    expect(app.node("summary-body").querySelectorAll("tr")).toHaveLength(1);
    expect(app.node("summary-row-count").textContent).toBe("1–1 of 1 calendar days");
    app.change("summary-filter", "", "input");
    app.change("summary-evidence", "not_uploaded");
    expect(app.node("summary-body").textContent).toContain("Not uploaded");
    expect(app.node("summary-body").textContent).not.toContain("0 steps");
    app.change("summary-evidence", "all");
    app.click("#summary-head th:nth-child(2) button");
    app.click("#summary-head th:nth-child(2) button");
    expect(app.node("summary-head").querySelector("th:nth-child(2)")?.getAttribute("aria-sort")).toBe("ascending");
    expect(app.node("summary-body").querySelector("tr")?.textContent).toContain("0 steps");
    app.context.inputDays = syntheticTrends().days;
    const ordered = app.evaluate<Array<{ status: string }>>("sortedSummaryDays(inputDays, '', 'all', 'steps', 'asc')");
    expect(ordered.slice(-3).map((day) => day.status)).toEqual(["read_limit", "unsupported_profile", "not_uploaded"]);
    app.evaluate("document.querySelector('#column-options input').checked = false");
    app.document.querySelector("#column-options input")!.dispatchEvent(new app.window.Event("change"));
    expect(app.node("summary-head").textContent).not.toContain("Steps");
    expect(app.node("summary-head").querySelectorAll("th")).toHaveLength(5);
    app.change("summary-filter", "no-matches", "input");
    expect(app.node("summary-body").textContent).toContain("No days match");
    expect(app.evaluate("document.getElementById('summary-body').querySelector('td').colSpan")).toBe(5);
  });

  it("switches tab panels with keyboard navigation and keeps the sidebar responsive", () => {
    const app = setup(undefined, true);
    app.evaluate("initDashboardViews()");
    expect(app.node("dashboard-sidebar").hidden).toBe(true);
    app.click("#sidebar-toggle");
    expect(app.node("sidebar-toggle").getAttribute("aria-expanded")).toBe("true");
    app.click('[data-table-view="exports"]');
    expect(app.node("dashboard-sidebar").hidden).toBe(true);
    expect(app.node("panel-exports").hidden).toBe(false);
    expect(app.node("panel-summaries").hidden).toBe(true);
    const event = new app.window.Event("keydown");
    Object.defineProperty(event, "key", { value: "Home" });
    app.node("tab-exports").dispatchEvent(event);
    expect(app.node("tab-summaries").getAttribute("aria-selected")).toBe("true");
    expect(app.node("tab-exports").tabIndex).toBe(-1);
  });

  it("sends only in-memory metric/day selections and retains exact original download routes", async () => {
    const app = setup();
    const selections: unknown[] = [];
    const supplements: unknown[] = [];
    app.document.addEventListener("healthmd:repair-select", (event: CustomEvent) => selections.push(event.detail));
    app.document.addEventListener("healthmd:repair-provenance", (event: CustomEvent) => supplements.push(event.detail));
    await app.evaluate("showTrends()");
    app.click("#summary-body tr .row-actions button");
    expect(selections).toEqual([{ date: "2026-03-30", source: "ios", metricId: "steps" }]);
    app.click("#summary-body tr .row-actions button:nth-child(2)");
    expect(supplements).toEqual([{ date: "2026-03-30" }]);
    app.context.syntheticSnapshots = [{ date: "2026-03-12", source: "android", schemaVersion: 4, captureStatus: "not_requested" }];
    app.evaluate("document.getElementById('day-list').replaceChildren(); appendDays(syntheticSnapshots)");
    app.click("#day-list button");
    expect(selections.at(-1)).toEqual({ date: "2026-03-12", source: "android", entireDay: true });
    app.context.syntheticExports = [{ id: "00000000-0000-4000-8000-000000000000", dateStart: null, dateEnd: null,
      recordCount: 0, source: "<img src=x onerror=alert(1)>", retentionRole: "supplemental", receivedAt: "2026-03-01T12:00:00Z" }];
    app.evaluate("document.getElementById('export-list').replaceChildren(); appendExports(syntheticExports)");
    expect(app.node("export-list").textContent).toContain("Separate supplement");
    expect(app.node("export-list").textContent).toContain("No declared days");
    expect(app.node("export-list").querySelector("img")).toBeNull();
    expect(app.node("export-list").querySelector("a")?.getAttribute("href"))
      .toBe("/api/exports/00000000-0000-4000-8000-000000000000/download");
  });
});
