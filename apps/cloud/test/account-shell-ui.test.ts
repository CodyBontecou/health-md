import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createContext, runInContext } from "node:vm";
import { parseHTML, type HTMLElement } from "linkedom";

const asset = (name: string) => readFileSync(resolve(import.meta.dirname, "../public", name), "utf8");
const pages = ["dashboard", "explore", "repair", "login", "deletion-status"];
const syntheticId = "00000000-0000-4000-8000-000000000001";
const metrics = [{ id: "steps", label: "Steps", unit: "steps" }];
// Reserved domains, fictional dates/values, and non-credential markers only.
const period = {
  window: { start: "2026-03-01", end: "2026-03-03" }, profile: "all", metrics,
  days: [
    { date: "2026-03-01", status: "available", values: { steps: 0 }, exportId: syntheticId, recordIndex: 0 },
    { date: "2026-03-02", status: "not_uploaded", values: { steps: null } },
    { date: "2026-03-03", status: "available", values: { steps: 10 }, exportId: syntheticId, recordIndex: 1 },
  ],
};
const original = { type: "object", totalChildren: 3, nextOffset: null, items: [
  { key: "synthetic_zero", type: "number", value: 0 },
  { key: "synthetic_empty", type: "null" },
  { key: "synthetic_text", type: "string", preview: "<img src=x onerror=alert(1)>", pointer: "/synthetic_text" },
] };
type Response = { ok: boolean; status: number; json: () => Promise<unknown> };
function fixtureResponse(path: string, options?: { credentials?: string }): Response {
  if (options?.credentials === "omit") return { ok: false, status: 404, json: async () => ({}) };
  const routes: Record<string, unknown> = {
    "/api/account": { email: "synthetic-owner@example.test" },
    "/api/exports": { days: [{ date: "2026-03-03" }] },
    "/api/explore/catalog": { metrics },
    "/api/explore/chart": period,
    "/api/explore/exports": { nextOffset: null, exports: [{ id: syntheticId, source: "ios", dailyVersion: 8,
      dateStart: "2026-03-01", dateEnd: "2026-03-03", recordCount: 2, failureCount: 0,
      externalRecordCount: 0, receivedAt: "2026-03-04T12:00:00Z" }] },
    "/api/explore/node": original,
    "/api/runtime": { authMode: "password", unbackedPersonalMvp: true },
    "/api/auth/logout": {},
  };
  return { ok: true, status: 200, json: async () => structuredClone(routes[path] || {}) };
}
function setup(page: string, mobile = false, hash = "") {
  const { document, window } = parseHTML(asset(`${page}.html`));
  document.body.dataset.page = "none";
  // Match native checked-state selectors, which linkedom does not implement.
  Object.defineProperty(window.HTMLInputElement.prototype, "checked", {
    configurable: true,
    get() { return this.hasAttribute("checked"); },
    set(value: boolean) { if (value) this.setAttribute("checked", ""); else this.removeAttribute("checked"); },
  });
  for (const select of document.querySelectorAll("select")) {
    Object.defineProperty(select, "value", { writable: true, value: select.querySelector("option")?.getAttribute("value") });
  }
  const location = { pathname: `/${page}`, hash, replace: vi.fn(), reload: vi.fn() };
  const changeUrl = (_state: unknown, _title: string, url: string) => {
    location.hash = new URL(url, "https://synthetic.example.test").hash;
  };
  const history = { pushState: vi.fn(changeUrl), replaceState: vi.fn(changeUrl) };
  const fetch = vi.fn(async (path: string, options?: { credentials?: string }): Promise<Response> => fixtureResponse(path, options));
  const context = createContext({ document, window, location, history, fetch,
    Event: window.Event, CustomEvent: window.CustomEvent,
    matchMedia: () => ({ matches: mobile, addEventListener: vi.fn() }) });
  runInContext(asset("dashboard.js"), context);
  const evaluate = <T = unknown>(code: string): T => runInContext(code, context);
  evaluate(`HealthMdAccount.init(${JSON.stringify(page)})`);
  const node = (id: string) => document.getElementById(id)!;
  const click = (selector: string) => document.querySelector<HTMLElement>(selector)!.click();
  const startExplorer = async () => {
    document.body.dataset.page = "explore";
    runInContext(asset("explore.js"), context);
    await vi.waitFor(() => expect(node("library-list").textContent).toContain("Apple · v8"));
  };
  return { document, window, context, evaluate, node, click, location, history, fetch, startExplorer };
}

describe("unified account chrome", () => {
  it.each(pages)("uses the same first-party shell, labels, and system on %s", (page) => {
    const app = setup(page);
    expect(app.document.body.classList.contains("account-app")).toBe(true);
    const ids = [...app.document.querySelectorAll("[id]")].map((node) => node.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const label of app.document.querySelectorAll("label[for]")) expect(ids).toContain(label.getAttribute("for"));
    expect(app.node("workspace").tagName).toBe("MAIN");
    expect(app.document.querySelectorAll("h1")).toHaveLength(1);
    expect(app.document.querySelector(".bar,.section-nav,.hero-head")).toBeNull();
    expect(app.document.querySelectorAll('#account-nav [aria-current="page"]')).toHaveLength(1);
    expect(app.document.querySelector('script[src="/dashboard.js"]')).not.toBeNull();
    for (const element of app.document.querySelectorAll("script[src],link[rel=stylesheet]")) {
      expect(element.getAttribute("src") || element.getAttribute("href")).toMatch(/^\/[a-z.-]+$/u);
    }
    expect(app.fetch).not.toHaveBeenCalled(); // Chrome itself never reads health data.
    expect(asset("style.css")).not.toMatch(/#66488f|#c5add9|body\[data-page="dashboard"\]|@import|https?:\/\//u);
  });

  it("switches the dashboard's central views and handles fixed-name history/back navigation", () => {
    const app = setup("dashboard");
    app.evaluate("initDashboardViews()");
    app.click('[data-nav="connections"]');
    expect(app.node("workspace-title").textContent).toBe("Connections");
    expect(app.document.querySelector('[data-workspace-views="connections"]')?.hidden).toBe(false);
    expect(app.document.querySelector('[data-workspace-views="overview"]')?.hidden).toBe(true);
    app.click('[data-nav="history"]');
    expect(app.node("panel-exports").hidden).toBe(false);
    expect(app.node("panel-summaries").hidden).toBe(true);
    expect(app.location.hash).toBe("#history");
    app.location.hash = "#connections";
    app.window.dispatchEvent(new app.window.Event("popstate"));
    expect(app.node("workspace-title").textContent).toBe("Connections");
    expect(app.fetch).not.toHaveBeenCalled();
    expect(app.evaluate('HealthMdAccount.activate("__proto__")')).toBe(false);
  });

  it("sanitizes unknown private fragments and never serializes a repair selection", () => {
    const app = setup("dashboard", false, "#synthetic-field-path");
    expect(app.location.hash).toBe("");
    app.document.dispatchEvent(new app.window.CustomEvent("healthmd:repair-select", {
      detail: { date: "2026-03-02", source: "ios", metricId: "steps" },
    }));
    expect(app.node("workspace-title").textContent).toBe("Plan missing exports");
    expect(app.location.hash).toBe("#plan");
    expect(JSON.stringify(app.history.pushState.mock.calls)).not.toMatch(/2026-03-02|steps/u);
  });

  it.each(["explore", "repair", "login"])("opens/closes the mobile drawer on %s without leaving content interactive", (page) => {
    const app = setup(page, true);
    expect(app.node("dashboard-sidebar").hidden).toBe(true);
    app.click("#sidebar-toggle");
    expect(app.node("dashboard-sidebar").hidden).toBe(false);
    expect(app.node("sidebar-backdrop").hidden).toBe(false);
    expect(app.node("dashboard-inset").inert).toBe(true);
    app.click("#sidebar-close");
    expect(app.node("dashboard-sidebar").hidden).toBe(true);
    expect(app.node("dashboard-inset").inert).toBe(false);
  });

  it("keeps sign-in and deletion receipts separate from authenticated navigation", () => {
    const login = setup("login", false, "#token=synthetic-marker-not-a-credential");
    expect(login.location.hash).toContain("synthetic-marker"); // Login consumes/removes its existing link fragment.
    expect(login.document.querySelectorAll("#account-nav a")).toHaveLength(1);
    expect(login.node("logout").hidden).toBe(true);
    const receipt = setup("deletion-status");
    expect(receipt.node("workspace-access").textContent).toBe("Receipt required");
    expect(receipt.document.querySelector('[data-nav="overview"]')).toBeNull();
  });
});

describe("explorer workspace, metadata tables, and read-on-click fields", () => {
  it("renders legacy library metadata without fabricated roles or automatic original-field reads", async () => {
    const app = setup("explore");
    await app.startExplorer();
    expect(app.node("library-list").querySelectorAll("td")).toHaveLength(7);
    expect(app.node("library-list").textContent).toContain("Not reported");
    expect(app.node("library-list").textContent).toContain("0 / 0");
    expect(app.node("explore-charts").textContent).not.toContain("supplements");
    expect(app.node("explore-charts").textContent).toContain("0 steps");
    expect(app.node("explore-charts").querySelectorAll(".chart-line")).toHaveLength(0);
    app.click('[data-workspace-tab="fields"]');
    expect(app.node("explore-panel-fields").hidden).toBe(false);
    expect(app.node("explore-panel-compare").hidden).toBe(true);
    expect(app.fetch.mock.calls.filter(([path]) => path === "/api/explore/node")).toHaveLength(0);
    app.click("#browse-library");
    expect(app.node("explore-panel-library").hidden).toBe(false);
  });

  it("inspects selected fields in a bounded table, escapes text, and keeps pointers out of navigation", async () => {
    const app = setup("explore");
    await app.startExplorer();
    app.click('[data-workspace-tab="library"]');
    app.click("#library-list button");
    await vi.waitFor(() => expect(app.node("inspector-children").querySelectorAll("tr")).toHaveLength(3));
    expect(app.node("explore-panel-fields").hidden).toBe(false);
    expect(app.node("inspector-children").textContent).toContain("synthetic_zero");
    expect(app.node("inspector-children").textContent).toContain("null");
    expect(app.node("inspector-children").querySelector("img")).toBeNull();
    const calls = app.fetch.mock.calls.filter(([path]) => path === "/api/explore/node");
    expect(calls).toHaveLength(1);
    expect(calls[0]![1]).toMatchObject({ credentials: "same-origin", method: "POST", cache: "no-store" });
    expect(app.location.hash).toBe("#fields");
    expect(JSON.stringify(app.history.pushState.mock.calls)).not.toContain(syntheticId);
    expect(app.node("inspector-download").getAttribute("href")).toBe(`/api/exports/${syntheticId}/download`);
  });

  it("clears displayed evidence and credentials before logout, ignoring an in-flight node response", async () => {
    const app = setup("explore");
    await app.startExplorer();
    let complete!: (value: Response) => void;
    app.fetch.mockImplementation(async (path, options) => path === "/api/explore/node" ?
      new Promise<Response>((resolve) => { complete = resolve; }) : fixtureResponse(path, options));
    app.click("#library-list button");
    app.click("#logout");
    expect(app.node("library-list").textContent).toBe("");
    expect(app.node("explore-charts").textContent).toBe("");
    complete({ ok: true, status: 200, json: async () => original });
    await vi.waitFor(() => expect(app.location.replace).toHaveBeenCalledWith("/login"));
    expect(app.node("inspector-children").textContent).toBe("");
    expect(app.node("inspector-download").hasAttribute("href")).toBe(false);
  });

  it("reports a failed field read without retaining the previous sensitive preview", async () => {
    const app = setup("explore");
    await app.startExplorer();
    app.click("#library-list button");
    await vi.waitFor(() => expect(app.node("inspector-children").querySelectorAll("tr")).toHaveLength(3));
    app.fetch.mockImplementation(async () => ({ ok: false, status: 503, json: async () => ({ message: "Synthetic unavailable" }) }));
    app.click("#inspector-children button");
    await vi.waitFor(() => expect(app.node("inspector-meta").textContent).toContain("temporarily unavailable"));
    expect(app.node("inspector-children").textContent).toBe("");
    expect(app.node("inspector-value").textContent).toBe("");
  });
});
