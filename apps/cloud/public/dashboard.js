"use strict";
// Shared account chrome lives in this already-allowed asset, so a static-only
// rollout also works with the deliberately older disposable VM backend.
const HealthMdAccount = (() => {
  const get = (id) => document.getElementById(id);
  const pages = {
    dashboard: { defaultView: "overview", views: {
      overview: ["Health overview", "Your retained days, trends, and exports in one place.", "overview"],
      trends: ["Health trends", "Review bounded daily summaries. Gaps are not zero, and no live device is queried.", "trends"],
      history: ["Export history", "Browse your current snapshots and retained original envelopes.", "history"],
      plan: ["Plan missing exports", "Review retained coverage and prepare a draft. Nothing contacts or launches a phone.", "plan"],
      connections: ["Connections", "Separate phone-upload tokens from explicitly authorized agent reads.", "connections"],
      security: ["Account & security", "Manage account access and deletion. This pilot has no off-host backup.", "security"],
    } },
    explore: { defaultView: "compare", views: {
      compare: ["Explore your data", "Compare retained summaries with separate scales and honest gaps.", "explore"],
      library: ["Export library", "Filter evidence actually present in retained export envelopes.", "explore"],
      fields: ["Original fields", "Inspect original JSON on demand. Selecting this view does not read any fields.", "explore"],
      plan: ["Plan missing exports", "Prepare a coverage-review draft using the dates you selected. Nothing launches a phone.", "plan"],
    } },
    repair: { defaultView: "plan", views: { plan: ["Plan missing exports", "Cloud can review uploaded evidence, not whether your phone holds the missing data.", "plan"] } },
    login: { defaultView: "login", public: true, views: { login: ["Sign in", "Access your private retained-export workspace.", "login"] } },
    "deletion-status": { defaultView: "deletion-status", public: true, views: { "deletion-status": ["Check account deletion", "Use your one-time receipt. It never becomes a URL or a browser sign-in credential.", "deletion-status"] } },
  };
  const navigation = [
    ["overview", "Overview", "/dashboard", "grid", "Workspace"],
    ["trends", "Health trends", "/dashboard#trends", "chart"],
    ["explore", "Explore data", "/explore", "database"],
    ["history", "Export history", "/dashboard#history", "archive"],
    ["plan", "Plan missing exports", "/repair", "calendar"],
    ["connections", "Connections", "/dashboard#connections", "link", "Manage"],
    ["security", "Account & security", "/dashboard#security", "user"],
  ];
  const icons = {
    grid: [["rect", { x: 3, y: 3, width: 7, height: 7, rx: 1 }], ["rect", { x: 14, y: 3, width: 7, height: 7, rx: 1 }], ["rect", { x: 3, y: 14, width: 7, height: 7, rx: 1 }], ["rect", { x: 14, y: 14, width: 7, height: 7, rx: 1 }]],
    chart: [["path", { d: "M3 3v18h18M7 14l4-4 4 3 6-8" }]],
    database: [["ellipse", { cx: 12, cy: 5, rx: 8, ry: 3 }], ["path", { d: "M4 5v14c0 4 16 4 16 0V5M4 12c0 4 16 4 16 0" }]],
    archive: [["path", { d: "M4 4h16v4H4zM5 8v12h14V8M9 12h6" }]],
    calendar: [["rect", { x: 3, y: 5, width: 18, height: 16, rx: 2 }], ["path", { d: "M16 3v4M8 3v4M3 11h18M12 14v4M10 16h4" }]],
    link: [["path", { d: "m10 13 4-4M8 16l-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M16 8l2-2a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0", transform: "translate(1 0) scale(.9)" }]],
    user: [["circle", { cx: 12, cy: 8, r: 4 }], ["path", { d: "M4 21v-2a8 8 0 0 1 16 0v2" }]],
    lock: [["rect", { x: 5, y: 10, width: 14, height: 11, rx: 2 }], ["path", { d: "M8 10V7a4 4 0 0 1 8 0v3" }]],
  };
  const featureRoutes = {
    sessions: ["/api/sessions", "GET"], securityActivity: ["/api/security-events", "GET"],
    accountExport: ["/api/account/export/page/1", "GET"], supplements: ["/api/repair/supplements", "POST"],
    deletionStatus: ["/api/account/deletion-status", "GET"],
  };
  let page, view, mobile, initialized = false, locked = false;
  function icon(name) {
    const node = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    node.setAttribute("viewBox", "0 0 24 24"); node.setAttribute("aria-hidden", "true");
    for (const [tag, attributes] of icons[name]) {
      const shape = document.createElementNS("http://www.w3.org/2000/svg", tag);
      for (const [key, value] of Object.entries(attributes)) shape.setAttribute(key, String(value));
      node.append(shape);
    }
    return node;
  }
  function sidebar(open, focus = false) {
    get("dashboard-sidebar").hidden = !open;
    if (mobile.matches && open) {
      get("dashboard-sidebar").setAttribute("role", "dialog"); get("dashboard-sidebar").setAttribute("aria-modal", "true");
    } else {
      get("dashboard-sidebar").setAttribute("role", "complementary"); get("dashboard-sidebar").removeAttribute("aria-modal");
    }
    document.body.dataset.sidebar = open ? "open" : "closed";
    get("sidebar-toggle").setAttribute("aria-expanded", String(open));
    get("sidebar-backdrop").hidden = !(mobile.matches && open);
    get("sidebar-close").hidden = !(mobile.matches && open);
    get("dashboard-inset").inert = mobile.matches && open;
    document.querySelector(".skip-link").hidden = mobile.matches && open;
    if (focus) (open && mobile.matches ? get("account-nav").querySelector('a[aria-current]') || get("sidebar-close") : get("sidebar-toggle")).focus();
  }
  function activate(next, options = {}) {
    if (!initialized || locked || !Object.hasOwn(pages[page].views, next)) return false;
    const changed = view !== next;
    view = next;
    const [title, description, selected] = pages[page].views[view];
    for (const panel of document.querySelectorAll("[data-workspace-views]")) {
      panel.hidden = !panel.dataset.workspaceViews.split(" ").includes(view);
    }
    for (const link of get("account-nav").querySelectorAll("a")) {
      if (link.dataset.nav === selected) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
    for (const tab of document.querySelectorAll("[data-workspace-tab]")) {
      const active = tab.dataset.workspaceTab === view;
      tab.setAttribute("aria-selected", String(active)); tab.tabIndex = active ? 0 : -1;
    }
    get("workspace-title").textContent = title;
    get("workspace-description").textContent = description;
    get("workspace-breadcrumb").textContent = pages[page].public ? title : selected === "explore" ? "Explore data" : navigation.find(([key]) => key === selected)[1];
    document.title = `${title} · Health.md Cloud`;
    // Only fixed, non-sensitive view names enter navigation history. Dates,
    // metrics, filters, credentials and inspector paths remain page-local.
    if (options.history && changed) history.pushState(null, "", `${location.pathname}#${view}`);
    if (mobile.matches) sidebar(false);
    if (options.focus) { window.scrollTo?.({ top: 0, behavior: "instant" }); get("workspace-title").focus({ preventScroll: true }); }
    document.dispatchEvent(new CustomEvent("healthmd:workspace-view", { detail: { view } }));
    return true;
  }
  function readView() {
    const aliases = { "trends-title": "trends", "data-title": "history", "repair-planner": "plan", "connect-title": "connections", "deletion-section": "security", "library-title": "library", "inspector-title": "fields", explore: "compare" };
    const fragment = location.hash.slice(1);
    const requested = aliases[fragment] || fragment;
    const valid = Object.hasOwn(pages[page].views, requested);
    if (fragment && !valid) history.replaceState(null, "", location.pathname);
    activate(valid ? requested : pages[page].defaultView);
  }
  async function probe(name) {
    if (!Object.hasOwn(featureRoutes, name)) return null;
    const route = featureRoutes[name];
    const [path, method] = route;
    try {
      const response = await fetch(path, { method, credentials: "omit", cache: "no-store",
        ...(method === "POST" ? { headers: { "Content-Type": "application/json", "X-HealthMd-Intent": "dashboard" }, body: "{}" } : {}) });
      const code = response.status;
      if (response.body) await response.body.cancel();
      return code;
    } catch { return null; }
  }
  function clear() {
    document.dispatchEvent(new Event("healthmd:account-clear"));
    document.dispatchEvent(new Event("healthmd:repair-clear"));
    for (const input of document.querySelectorAll("input")) { input.value = ""; input.checked = false; }
    if (initialized && !pages[page].public) lock();
  }
  function lock() {
    locked = true;
    if (initialized) for (const link of get("account-nav").querySelectorAll("a")) link.setAttribute("aria-disabled", "true");
  }
  async function logout() {
    get("logout").disabled = true;
    clear();
    try {
      const response = await fetch("/api/auth/logout", { method: "POST", credentials: "same-origin", cache: "no-store", headers: { "X-HealthMd-Intent": "dashboard" } });
      if (!response.ok) throw new Error("Sign-out unavailable");
      location.replace("/login");
    } catch {
      get("workspace-status").textContent = "Sign-out could not be confirmed. Your displayed data has been cleared; retry signing out.";
      get("logout").disabled = false;
    }
  }
  function init(requestedPage = document.body.dataset.page) {
    if (initialized || !pages[requestedPage] || !get("account-nav")) return;
    initialized = true; page = requestedPage;
    const nav = get("account-nav"); nav.replaceChildren();
    const entries = pages[page].public ? [["login", "Sign in", "/login", "lock", "Access"],
      ...(page === "deletion-status" ? [["deletion-status", "Deletion status", "/deletion-status", "archive"]] : [])] : navigation;
    for (const [key, label, href, symbol, group] of entries) {
      if (group) { const heading = document.createElement("p"); heading.className = "sidebar-label"; heading.textContent = group; nav.append(heading); }
      const link = document.createElement("a"); link.href = href; link.dataset.nav = key;
      if (key === "history") link.dataset.tableView = "exports";
      link.append(icon(symbol), document.createTextNode(label)); nav.append(link);
      link.addEventListener("click", (event) => {
        if (locked) { event.preventDefault(); return; }
        if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        const local = key === "explore" && page === "explore" ? "compare" : key;
        if (Object.hasOwn(pages[page].views, local)) { event.preventDefault(); activate(local, { history: true, focus: true }); }
        else if (mobile.matches) sidebar(false);
      });
    }
    if (pages[page].public) {
      get("workspace-kind").textContent = "Private workspace";
      get("workspace-access").textContent = page === "deletion-status" ? "Receipt required" : "Sign-in required";
    }
    get("logout").hidden = !!pages[page].public;
    get("logout").addEventListener("click", logout);
    mobile = matchMedia("(max-width: 900px)");
    sidebar(!mobile.matches);
    let narrow = mobile.matches;
    const responsiveSidebar = () => {
      if (narrow === mobile.matches) return;
      narrow = mobile.matches; sidebar(!narrow);
    };
    mobile.addEventListener("change", responsiveSidebar);
    window.addEventListener("resize", responsiveSidebar);
    get("sidebar-toggle").addEventListener("click", () => sidebar(get("dashboard-sidebar").hidden, true));
    for (const id of ["sidebar-close", "sidebar-backdrop"]) get(id).addEventListener("click", () => sidebar(false, true));
    const tabs = [...document.querySelectorAll("[data-workspace-tab]")];
    for (const [index, tab] of tabs.entries()) {
      tab.addEventListener("click", () => activate(tab.dataset.workspaceTab, { history: true }));
      tab.addEventListener("keydown", (event) => {
        const next = event.key === "ArrowRight" ? (index + 1) % tabs.length : event.key === "ArrowLeft" ?
          (index + tabs.length - 1) % tabs.length : event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : null;
        if (next !== null) { event.preventDefault(); activate(tabs[next].dataset.workspaceTab, { history: true }); tabs[next].focus(); }
      });
    }
    document.addEventListener("keydown", (event) => {
      if (!mobile.matches || get("dashboard-sidebar").hidden) return;
      if (event.key === "Escape") { event.preventDefault(); sidebar(false, true); }
      if (event.key === "Tab") {
        const focusable = [...get("dashboard-sidebar").querySelectorAll("a[href],button:not(:disabled)")].filter((node) => !node.hidden);
        const next = event.shiftKey ? focusable.at(-1) : focusable[0];
        if (document.activeElement === (event.shiftKey ? focusable[0] : focusable.at(-1))) { event.preventDefault(); next.focus(); }
      }
    });
    for (const type of ["healthmd:repair-select", "healthmd:repair-provenance"]) {
      document.addEventListener(type, () => activate("plan", { history: true, focus: true }));
    }
    window.addEventListener("pagehide", clear);
    window.addEventListener("pageshow", (event) => { if (event.persisted) location.reload(); });
    if (pages[page].public) activate(pages[page].defaultView);
    else { readView(); window.addEventListener("hashchange", readView); window.addEventListener("popstate", readView); }
  }
  return { init, activate, probe, lock, clear, get view() { return view; } };
})();
const $ = (id) => document.getElementById(id);
const status = (text) => { $("message").textContent = text; };
const planFromRow = (selection) => document.dispatchEvent(
  new CustomEvent("healthmd:repair-select", { detail: selection }));

async function api(path, method = "GET", body) {
  const response = await fetch(path, {
    method,
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(method !== "GET" ? { "X-HealthMd-Intent": "dashboard" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const result = await response.json();
  if (!response.ok) {
    const error = new Error(result.message || "Request failed. Please retry.");
    error.httpStatus = response.status;
    throw error;
  }
  return result;
}

function newDeletionStatusToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `hmd_del_${btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "")}`;
}

function clearDashboardAccount() {
  clearDashboardViews();
  $("connect-section").hidden = true;
  $("agents-section").hidden = true;
  $("deletion-section").hidden = true;
  $("session-list").replaceChildren();
  $("token-list").replaceChildren();
  $("new-token").value = "";
  $("new-token-panel").hidden = true;
  $("export-list").replaceChildren();
  $("day-list").replaceChildren();
  $("security-activity-list").replaceChildren();
  $("account-export-panel").hidden = true;
  $("agent-list").replaceChildren();
  $("trend-cards").replaceChildren();
  $("stat-days").textContent = "—";
  $("stat-exports").textContent = "—";
  $("stat-latest").textContent = "—";
  $("new-agent-token").value = "";
  $("new-agent-panel").hidden = true;
  document.dispatchEvent(new Event("healthmd:repair-clear"));
  $("repair-mount").replaceChildren();
  for (const id of ["agent-password", "delete-password", "delete-confirmation", "agent-name", "token-name"]) $(id).value = "";
  $("agent-consent").checked = false;
  $("account").textContent = "Account access disabled.";
}
function showDeletionPending(statusToken, message) {
  HealthMdAccount.activate("security");
  clearDashboardAccount();
  HealthMdAccount.lock();
  $("deletion-status-token").value = statusToken || "";
  $("deletion-receipt-section").hidden = !statusToken;
  status(message);
}

function addTextRow(list, label, details, action) {
  const row = document.createElement("li");
  const text = document.createElement("span");
  text.textContent = `${label} · ${details}`;
  row.append(text);
  if (action) row.append(action);
  list.append(row);
}

async function showTokens() {
  const { tokens } = await api("/api/ingest-tokens");
  if (dashboardView.disabled) return;
  const list = $("token-list");
  list.replaceChildren();
  if (!tokens.length) addTextRow(list, "No tokens yet", "Create one to connect your phone");
  for (const token of tokens) {
    const details = token.revokedAt ? "Revoked" : `•••• ${token.lastFour}`;
    let button = null;
    if (!token.revokedAt) {
      button = document.createElement("button");
      button.className = "subtle";
      button.textContent = "Revoke";
      button.addEventListener("click", async () => {
        if (!confirm(`Revoke export token ${token.name}? Your phone will stop uploading until you add a new token.`)) return;
        try {
          await api(`/api/ingest-tokens/${token.id}`, "DELETE");
          status("Export token revoked.");
          await showTokens();
        } catch (error) { status(error.message); }
      });
    }
    addTextRow(list, token.name, details, button);
  }
}

async function showAgents() {
  const { tokens } = await api("/api/agent-tokens");
  if (dashboardView.disabled) return;
  const list = $("agent-list");
  list.replaceChildren();
  if (!tokens.length) addTextRow(list, "No agent credentials", "Create one only for a provider you trust");
  for (const item of tokens) {
    const state = item.revokedAt ? "Revoked" : new Date(item.expiresAt) <= new Date() ? "Expired" : "Active";
    const detail = `${item.scope === "full_export" ? "All retained exports" : "Daily aggregates only"} · ${state} · expires ${new Date(item.expiresAt).toLocaleDateString()} · •••• ${item.lastFour}`;
    let button = null;
    if (!item.revokedAt) {
      button = document.createElement("button");
      button.className = "subtle";
      button.textContent = "Revoke";
      button.addEventListener("click", async () => {
        if (!confirm(`Revoke ${item.label}? The agent will lose access immediately.`)) return;
        try {
          await api(`/api/agent-tokens/${item.id}`, "DELETE");
          status("Agent credential revoked.");
          await showAgents();
        } catch (error) { status(error.message); }
      });
    }
    addTextRow(list, item.label, detail, button);
  }
}

async function showSessions() {
  const { sessions } = await api("/api/sessions");
  if (dashboardView.disabled) return;
  const list = $("session-list");
  list.replaceChildren();
  for (const item of sessions) {
    const button = document.createElement("button");
    button.className = "subtle";
    button.textContent = item.current ? "Sign out here" : "Revoke";
    button.addEventListener("click", async () => {
      try {
        await api(`/api/sessions/${item.id}`, "DELETE");
        if (item.current) { location.replace("/login"); return; }
        status("Browser session revoked.");
        await showSessions();
      } catch (error) { status(error.message); }
    });
    addTextRow(list, item.current ? "This browser" : "Other browser",
      `created ${new Date(item.createdAt).toLocaleString()} · expires ${new Date(item.expiresAt).toLocaleString()}`,
      button);
  }
}

const securityEventLabels = Object.freeze({
  "password_login.succeeded": "Password sign-in",
  "session.created": "Browser session created",
  "session.revoked": "Browser session revoked",
  "session.others_revoked": "Other browser sessions revoked",
  "ingest_token.created": "Phone upload token created",
  "ingest_token.revoked": "Phone upload token revoked",
  "agent_token.created": "Agent credential created",
  "agent_token.revoked": "Agent credential revoked",
  "export.downloaded": "Original export downloaded",
  "repair_device.approved": "Repair device approved",
  "repair_device.revoked": "Repair device revoked",
  "repair_dispatch.queued": "Repair review queued",
  "repair_dispatch.cancelled": "Repair review cancelled",
  "repair_dispatch.claimed": "Repair review claimed",
  "repair_dispatch.declined": "Repair review declined",
});

async function showSecurityActivity() {
  const { events } = await api("/api/security-events");
  if (dashboardView.disabled) return;
  const list = $("security-activity-list");
  list.replaceChildren();
  if (!events.length) addTextRow(list, "No recent security activity", "New events will appear here");
  for (const event of events) {
    addTextRow(list, securityEventLabels[event.type] || "Security activity",
      new Date(event.occurredAt).toLocaleString());
  }
}

// First-party dashboard-01-style views. All choices and health values stay in
// this page's memory; the existing owner-session APIs and read bounds are unchanged.
const SVG_NS = "http://www.w3.org/2000/svg";
const formatDay = (date) => new Date(`${date}T12:00:00Z`).toLocaleDateString(undefined,
  { month: "short", day: "numeric", timeZone: "UTC" });
const formatted = (value) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value);
const dayLabel = (day, id, unit) => {
  if (day.status === "not_uploaded") return "Not uploaded";
  if (day.status === "unsupported_profile") return "No reviewed Apple mapping";
  if (day.status === "read_limit") return "Outside bounded read";
  const value = day.values[id];
  return typeof value === "number" && Number.isFinite(value) ? `${formatted(value)} ${unit}` : "Value unavailable";
};
function svgElement(tag, attributes) {
  const element = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, String(value));
  return element;
}
const dashboardView = {
  result: null, range: 30, metricId: "steps", page: 0, pageSize: 10,
  sort: "date", direction: "desc", columns: new Set(), disabled: false,
  capabilities: { sessions: false, securityActivity: false, accountExport: false, supplements: false, deletionStatus: "unknown" },
};
// The disposable VM may intentionally remain on its older backend. Probe only
// unauthenticated route guards: never download health data to detect a feature,
// mint a credential, or assume a failed probe means legacy deletion is safe.
async function detectDashboardCapabilities() {
  const results = await Promise.all(Object.keys(dashboardView.capabilities).map(async (name) =>
    [name, await HealthMdAccount.probe(name)]));
  if (dashboardView.disabled) return;
  for (const [name, code] of results) {
    dashboardView.capabilities[name] = name === "deletionStatus" ?
      code === 401 ? "supported" : code === 404 ? "legacy" : "unknown" : code === 401;
  }
  $("session-management").hidden = !dashboardView.capabilities.sessions;
  $("security-activity").hidden = !dashboardView.capabilities.securityActivity;
  $("delete-account-form").hidden = dashboardView.capabilities.deletionStatus === "unknown";
  if (dashboardView.capabilities.deletionStatus === "legacy") {
    $("deletion-copy").textContent = "Deleting your account disables sign-in, uploads, and read credentials immediately. Stored exports are then erased by the background deletion job. This unbacked pilot has no self-service deletion status receipt; contact the operator to confirm completion.";
  } else if (dashboardView.capabilities.deletionStatus === "unknown") {
    $("deletion-copy").textContent = "Account deletion is temporarily unavailable because this service's deletion-status support could not be verified. Reload to retry. No deletion request has been sent.";
  }
}
const evidenceLabels = Object.freeze({
  available: "Reviewed summary", not_uploaded: "Not uploaded",
  unsupported_profile: "Unmapped profile", read_limit: "Read limit",
});
function textElement(tag, text, className) {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}
function reading(day, id) {
  const value = day.values[id];
  return day.status === "available" && typeof value === "number" && Number.isFinite(value) ? value : null;
}
function visibleTrendDays() {
  return dashboardView.result?.days.slice(-dashboardView.range) || [];
}
function trendObservations(metric, days) {
  return days.filter((day) => reading(day, metric.id) !== null);
}
function trendChange(metric, observations) {
  const latest = observations.at(-1);
  const previous = observations.at(-2);
  if (!latest || !previous) return "No comparison";
  const delta = reading(latest, metric.id) - reading(previous, metric.id);
  return `${delta > 0 ? "+" : ""}${formatted(delta)} ${metric.unit}`;
}
function renderTrend(metric, days) {
  const observations = trendObservations(metric, days);
  const latest = observations.at(-1);
  const previous = observations.at(-2);
  const card = textElement("article", "", "stat-card");
  const heading = textElement("div", "", "stat-card-head");
  const name = textElement("button", metric.label, "subtle stat-metric-button");
  name.type = "button";
  name.setAttribute("aria-label", `Show ${metric.label} trend`);
  name.addEventListener("click", () => selectTrendMetric(metric.id));
  heading.append(name, textElement("span", trendChange(metric, observations), "stat-badge"));
  const value = textElement("strong", latest ? formatted(reading(latest, metric.id)) : "—", "stat-value");
  value.append(textElement("span", latest ? ` ${metric.unit}` : "", "stat-value-unit"));
  card.append(heading, value,
    textElement("span", latest ? `Latest value · ${formatDay(latest.date)}` : "No value in this window", "stat-description"),
    textElement("span", previous ? `Change vs ${formatDay(previous.date)} · ${observations.length}/${days.length} days observed` :
      `${observations.length} of ${days.length} calendar days observed`, "stat-foot"));
  return card;
}
// Each continuous segment is filled independently. Never interpolate or join
// an absent, unsupported, read-limited, or null-valued day, including at zero.
function trendSegments(metric, days, x, y) {
  const segments = [];
  let segment = [];
  days.forEach((day, index) => {
    const value = reading(day, metric.id);
    if (value === null) {
      if (segment.length) segments.push(segment);
      segment = [];
    } else segment.push({ x: x(index), y: y(value), day, value });
  });
  if (segment.length) segments.push(segment);
  return segments;
}
function trendScale(numbers) {
  const min = Math.min(0, ...numbers);
  const max = Math.max(0, ...numbers);
  const rawStep = Math.max(1, max - min) / 3;
  const magnitude = 10 ** Math.floor(Math.log10(rawStep));
  const step = [1, 2, 5, 10].find((size) => size * magnitude >= rawStep) * magnitude;
  const low = Math.floor(min / step) * step;
  const high = Math.max(low + step, Math.ceil(max / step) * step);
  const ticks = Array.from({ length: Math.round((high - low) / step) + 1 }, (_, index) => low + index * step);
  return { low, high, ticks };
}
function renderMainChart() {
  const target = $("main-chart");
  target.replaceChildren();
  target.setAttribute("aria-busy", "false");
  const days = visibleTrendDays();
  const metric = dashboardView.result?.metrics.find((item) => item.id === dashboardView.metricId);
  const observations = metric ? trendObservations(metric, days) : [];
  $("chart-unit").textContent = metric ? `Daily values · ${metric.unit}` : "";
  $("chart-coverage").textContent = `${observations.length} of ${days.length} calendar days observed`;
  if (!observations.length) {
    target.append(textElement("p", days.length ? "No verified values for this metric in the selected window. Review daily evidence below." :
      "No retained daily exports yet. Upload a Summary day to see your trends.", "chart-empty"));
    return;
  }
  const numbers = observations.map((day) => reading(day, metric.id));
  const { low, high, ticks: valueTicks } = trendScale(numbers);
  const width = Math.max(240, target.clientWidth || 1000);
  const x = (index) => 62 + index * ((width - 68) / Math.max(1, days.length - 1));
  const y = (value) => 222 - (value - low) / (high - low) * 202;
  const chart = svgElement("svg", { viewBox: `0 0 ${width} 270`, preserveAspectRatio: "none", role: "img",
    "aria-label": `${metric.label} in ${metric.unit}. ${observations.length} of ${days.length} calendar days observed. Gaps are not connected. Exact daily values are in the table below.` });
  const defs = svgElement("defs", {});
  const gradient = svgElement("linearGradient", { id: "dashboard-area", x1: 0, y1: 0, x2: 0, y2: 1 });
  gradient.append(svgElement("stop", { offset: "0%", "stop-color": "currentColor", "stop-opacity": .22 }),
    svgElement("stop", { offset: "100%", "stop-color": "currentColor", "stop-opacity": .015 }));
  defs.append(gradient); chart.append(defs);
  for (const value of valueTicks) {
    chart.append(svgElement("line", { x1: 62, x2: width - 6, y1: y(value), y2: y(value), class: "trend-grid-line" }));
    const label = svgElement("text", { x: 48, y: y(value) + 4, "text-anchor": "end", class: "trend-axis-label" });
    label.textContent = formatted(value); chart.append(label);
  }
  const readout = textElement("p", `${formatDay(observations.at(-1).date)} · ${dayLabel(observations.at(-1), metric.id, metric.unit)}`, "chart-readout");
  readout.setAttribute("aria-live", "polite");
  for (const segment of trendSegments(metric, days, x, y)) {
    const line = segment.map((point, index) => `${index ? "L" : "M"}${point.x.toFixed(2)} ${point.y.toFixed(2)}`).join(" ");
    if (segment.length > 1) {
      chart.append(svgElement("path", { d: `${line} L${segment.at(-1).x} ${y(0)} L${segment[0].x} ${y(0)} Z`, class: "trend-area" }),
        svgElement("path", { d: line, class: "chart-line" }));
    }
    for (const point of segment) {
      const label = `${point.day.date} · ${formatted(point.value)} ${metric.unit}`;
      const dot = svgElement("circle", { cx: point.x, cy: point.y, r: 4, class: "trend-dot", tabindex: 0,
        role: "img", "aria-label": label });
      const title = svgElement("title", {}); title.textContent = label; dot.append(title);
      const inspect = () => { readout.textContent = label; };
      dot.addEventListener("pointerenter", inspect); dot.addEventListener("focus", inspect);
      chart.append(dot);
    }
  }
  const ticks = [...new Set([0, Math.floor((days.length - 1) / 3), Math.floor((days.length - 1) * 2 / 3), days.length - 1])];
  for (const index of ticks) {
    const label = svgElement("text", { x: x(index), y: 258, "text-anchor": index === 0 ? "start" :
      index === days.length - 1 ? "end" : "middle", class: "trend-axis-label" });
    label.textContent = formatDay(days[index].date); chart.append(label);
  }
  target.append(chart, readout);
}
function selectTrendMetric(id) {
  if (dashboardView.disabled) return;
  dashboardView.metricId = id;
  for (const button of $("trend-metrics").querySelectorAll("button")) {
    button.setAttribute("aria-pressed", String(button.dataset.metric === id));
  }
  renderMainChart(); renderSummaryTable();
}
function refreshTrendViews() {
  if (dashboardView.disabled) return;
  const result = dashboardView.result;
  if (!result) return;
  const days = visibleTrendDays();
  $("trend-cards").replaceChildren(...(result?.metrics || []).map((metric) => renderTrend(metric, days)));
  $("trend-cards").setAttribute("aria-busy", "false");
  $("trends-window").textContent = days.length ?
    `${formatDay(days[0].date)} – ${formatDay(days.at(-1).date)} · ${days.length} calendar days ending on your latest uploaded day` : "No retained daily exports yet";
  $("summary-count").textContent = String(days.length);
  const excluded = days.filter((day) => day.status === "unsupported_profile").length;
  const limited = days.filter((day) => day.status === "read_limit").length;
  $("trends-note").textContent = "Verified Apple v8 summaries only. Android, archive, and provider data are not mapped into these charts. No clinical interpretation or live device readings." +
    (excluded ? ` ${excluded} day(s) have an unmapped profile.` : "") +
    (limited ? ` ${limited} day(s) are outside the bounded read budget.` : "");
  renderMainChart(); renderSummaryTable();
}
function renderEmptyRow(target, columns, message) {
  const row = textElement("tr", "");
  const cell = textElement("td", message, "table-empty");
  cell.colSpan = columns; row.append(cell); target.append(row);
}
function sortedSummaryDays(days, search, evidence, key, direction) {
  const filtered = days.filter((day) => day.date.includes(search.trim()) && (evidence === "all" || day.status === evidence));
  return filtered.sort((a, b) => {
    const left = key === "date" ? a.date : reading(a, key);
    const right = key === "date" ? b.date : reading(b, key);
    // Unknown values are last in either direction, never coerced to zero.
    if (left === null && right !== null) return 1;
    if (right === null && left !== null) return -1;
    if (left === null && right === null) return b.date.localeCompare(a.date);
    const order = key === "date" ? left.localeCompare(right) : left - right;
    return (direction === "asc" ? order : -order) || b.date.localeCompare(a.date);
  });
}
function supplementButton(date) {
  const button = textElement("button", "Review supplements", "subtle");
  button.type = "button";
  button.setAttribute("aria-label", `Review separately retained evidence for ${date}`);
  button.addEventListener("click", () => document.dispatchEvent(
    new CustomEvent("healthmd:repair-provenance", { detail: { date } })));
  return button;
}
function renderSummaryTable() {
  if (dashboardView.disabled || !dashboardView.result) return;
  const metrics = (dashboardView.result?.metrics || []).filter((metric) => dashboardView.columns.has(metric.id));
  const head = textElement("tr", "");
  for (const column of [{ id: "date", label: "Owner date" }, ...metrics]) {
    const th = textElement("th", ""); th.scope = "col";
    th.setAttribute("aria-sort", dashboardView.sort === column.id ?
      dashboardView.direction === "asc" ? "ascending" : "descending" : "none");
    const button = textElement("button", `${column.label} ${dashboardView.sort === column.id ?
      dashboardView.direction === "asc" ? "↑" : "↓" : "↕"}`, "subtle table-sort");
    button.type = "button";
    button.addEventListener("click", () => {
      dashboardView.direction = dashboardView.sort === column.id && dashboardView.direction === "desc" ? "asc" : "desc";
      dashboardView.sort = column.id; dashboardView.page = 0; renderSummaryTable();
      $("summary-head").querySelectorAll("button")[column.id === "date" ? 0 : metrics.findIndex((metric) => metric.id === column.id) + 1].focus();
    });
    th.append(button); head.append(th);
  }
  for (const title of ["Evidence", "Actions"]) {
    const th = textElement("th", title); th.scope = "col"; head.append(th);
  }
  $("summary-head").replaceChildren(head);
  const days = sortedSummaryDays(visibleTrendDays(), $("summary-filter").value,
    $("summary-evidence").value, dashboardView.sort, dashboardView.direction);
  const pages = Math.max(1, Math.ceil(days.length / dashboardView.pageSize));
  dashboardView.page = Math.min(dashboardView.page, pages - 1);
  const offset = dashboardView.page * dashboardView.pageSize;
  const body = $("summary-body"); body.replaceChildren();
  for (const day of days.slice(offset, offset + dashboardView.pageSize)) {
    const row = textElement("tr", "");
    row.append(textElement("td", day.date, "date-cell"));
    for (const metric of metrics) {
      const value = reading(day, metric.id);
      const cell = textElement("td", value === null ? "—" : `${formatted(value)} ${metric.unit}`, "numeric-cell");
      cell.title = dayLabel(day, metric.id, metric.unit);
      if (value === null) cell.setAttribute("aria-label", dayLabel(day, metric.id, metric.unit));
      row.append(cell);
    }
    const evidence = textElement("td", "");
    evidence.append(textElement("span", evidenceLabels[day.status] || "Unavailable", `evidence-badge evidence-${day.status}`));
    const actions = textElement("td", "", "row-actions");
    if (day.status === "available" || day.status === "not_uploaded") {
      const button = textElement("button", "Add to plan", "subtle"); button.type = "button";
      const selectedMetric = dashboardView.result.metrics.find((metric) => metric.id === dashboardView.metricId);
      button.setAttribute("aria-label", `Plan ${selectedMetric.label} for ${day.date}`);
      button.addEventListener("click", () => planFromRow({ date: day.date, source: "ios", metricId: dashboardView.metricId }));
      actions.append(button);
    }
    if (dashboardView.capabilities.supplements) actions.append(supplementButton(day.date));
    row.append(evidence, actions); body.append(row);
  }
  if (!days.length) renderEmptyRow(body, metrics.length + 3,
    dashboardView.result?.days.length ? "No days match these filters." : "No daily exports to display. Upload a Summary day to begin.");
  $("summary-row-count").textContent = days.length ? `${offset + 1}–${Math.min(offset + dashboardView.pageSize, days.length)} of ${days.length} calendar days` : "0 calendar days";
  $("summary-page-label").textContent = `Page ${dashboardView.page + 1} of ${pages}`;
  $("summary-prev").disabled = dashboardView.page === 0;
  $("summary-next").disabled = dashboardView.page >= pages - 1;
}
async function showTrends() {
  const result = await api("/api/dashboard/trends");
  if (dashboardView.disabled) return;
  dashboardView.result = result;
  dashboardView.columns = new Set(result.metrics.map((metric) => metric.id));
  if (!result.metrics.some((metric) => metric.id === dashboardView.metricId)) dashboardView.metricId = result.metrics[0]?.id;
  $("stat-latest").textContent = result.window.end ? formatDay(result.window.end) : "—";
  $("trend-metrics").replaceChildren(); $("column-options").replaceChildren();
  for (const metric of result.metrics) {
    const button = textElement("button", metric.label, "subtle"); button.type = "button";
    button.dataset.metric = metric.id; button.setAttribute("aria-pressed", String(metric.id === dashboardView.metricId));
    button.addEventListener("click", () => selectTrendMetric(metric.id)); $("trend-metrics").append(button);
    const label = textElement("label", "");
    const checkbox = document.createElement("input"); checkbox.type = "checkbox"; checkbox.checked = true;
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) dashboardView.columns.add(metric.id); else dashboardView.columns.delete(metric.id);
      if (!dashboardView.columns.has(dashboardView.sort)) { dashboardView.sort = "date"; dashboardView.direction = "desc"; }
      renderSummaryTable();
    });
    label.append(checkbox, document.createTextNode(`${metric.label} (${metric.unit})`)); $("column-options").append(label);
  }
  refreshTrendViews();
}
function setDataView(view, focus = false) {
  for (const tab of document.querySelectorAll(".data-tabs [role=tab]")) {
    const selected = tab.dataset.view === view;
    tab.setAttribute("aria-selected", String(selected)); tab.tabIndex = selected ? 0 : -1;
    $(`panel-${tab.dataset.view}`).hidden = !selected;
    if (selected && focus) tab.focus();
  }
}
function initDashboardViews() {
  if (typeof ResizeObserver !== "undefined") {
    new ResizeObserver(() => {
      if (dashboardView.result && !dashboardView.disabled) renderMainChart();
    }).observe($("main-chart"));
  }
  HealthMdAccount.init("dashboard");
  const workspaceView = (view) => {
    if (view === "history") setDataView("exports");
    if (dashboardView.result && !dashboardView.disabled && ["overview", "trends"].includes(view)) renderMainChart();
  };
  document.addEventListener("healthmd:workspace-view", (event) => workspaceView(event.detail.view));
  workspaceView(HealthMdAccount.view);
  document.addEventListener("healthmd:account-clear", clearDashboardAccount);
  const tabs = [...document.querySelectorAll(".data-tabs [role=tab]")];
  for (const [index, tab] of tabs.entries()) {
    tab.addEventListener("click", () => setDataView(tab.dataset.view));
    tab.addEventListener("keydown", (event) => {
      const next = event.key === "ArrowRight" ? (index + 1) % tabs.length : event.key === "ArrowLeft" ?
        (index + tabs.length - 1) % tabs.length : event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : null;
      if (next !== null) { event.preventDefault(); setDataView(tabs[next].dataset.view, true); }
    });
  }
  for (const button of $("trend-ranges").querySelectorAll("button")) {
    button.addEventListener("click", () => {
      dashboardView.range = Number(button.dataset.range); dashboardView.page = 0;
      for (const item of $("trend-ranges").querySelectorAll("button")) item.setAttribute("aria-pressed", String(item === button));
      refreshTrendViews();
    });
  }
  for (const id of ["summary-filter", "summary-evidence", "summary-page-size"]) {
    $(id).addEventListener(id === "summary-filter" ? "input" : "change", () => {
      dashboardView.page = 0; dashboardView.pageSize = Number($("summary-page-size").value); renderSummaryTable();
    });
  }
  for (const [id, step] of [["summary-prev", -1], ["summary-next", 1]]) {
    $(id).addEventListener("click", () => { dashboardView.page += step; renderSummaryTable(); });
  }
  document.addEventListener("click", (event) => {
    if (!$("column-menu").contains(event.target)) $("column-menu").open = false;
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if ($("column-menu").open) { $("column-menu").open = false; $("column-menu").querySelector("summary").focus(); }
  });
}

function clearDashboardViews() {
  dashboardView.disabled = true;
  dashboardView.result = null;
  dashboardView.columns.clear();
  $("main-chart").replaceChildren();
  $("trend-metrics").replaceChildren();
  $("column-options").replaceChildren();
  $("summary-head").replaceChildren();
  $("summary-body").replaceChildren();
  $("summary-filter").value = "";
  $("column-menu").open = false;
  for (const id of ["trends-window", "chart-coverage", "chart-unit", "summary-count", "summary-row-count", "summary-page-label", "storage", "stat-bytes"]) $(id).textContent = "";
  for (const id of ["summary-prev", "summary-next", "summary-filter", "summary-evidence", "summary-page-size"]) $(id).disabled = true;
  for (const button of $("trend-ranges").querySelectorAll("button")) button.disabled = true;
  $("more-days").hidden = true; $("more-exports").hidden = true;
}
function appendExports(exports) {
  if (dashboardView.disabled) return;
  const list = $("export-list");
  for (const item of exports) {
    const row = textElement("tr", "");
    const dates = item.dateStart && item.dateEnd ? `${item.dateStart} – ${item.dateEnd}` : "No declared days";
    for (const text of [dates, item.source === "ios" ? "Apple" : item.source === "android" ? "Android" : item.source,
      String(item.recordCount)]) row.append(textElement("td", text));
    const role = textElement("td", "");
    role.append(textElement("span", item.retentionRole === "supplemental" ? "Separate supplement" :
      item.retentionRole === "current" ? "Current for ≥1 day" : ["revision", "unreferenced"].includes(item.retentionRole) ?
        "Revision / unreferenced" : "Not reported", "evidence-badge"));
    row.append(role, textElement("td", new Date(item.receivedAt).toLocaleString()));
    const download = textElement("td", "");
    const link = textElement("a", "Download JSON", "subtle-link");
    link.href = `/api/exports/${item.id}/download`;
    link.setAttribute("aria-label", `Download original ${item.source} export received ${new Date(item.receivedAt).toLocaleString()}`);
    download.append(link); row.append(download); list.append(row);
  }
}
function appendDays(days) {
  if (dashboardView.disabled) return;
  for (const day of days) {
    const row = textElement("tr", "");
    for (const text of [day.date, day.source === "ios" ? "Apple" : "Android", `v${day.schemaVersion}`,
      day.captureStatus || "Not reported"]) row.append(textElement("td", text));
    const action = textElement("button", "Plan entire day", "subtle"); action.type = "button";
    action.setAttribute("aria-label", `Plan entire ${day.source === "ios" ? "Apple" : "Android"} day ${day.date}`);
    action.addEventListener("click", () => planFromRow({ date: day.date, source: day.source, entireDay: true }));
    const buttons = textElement("td", "", "row-actions"); buttons.append(action);
    if (dashboardView.capabilities.supplements) buttons.append(supplementButton(day.date));
    row.append(buttons); $("day-list").append(row);
  }
}

async function showExports() {
  const { exports, days, storage, nextExportOffset, nextDayOffset } = await api("/api/exports");
  if (dashboardView.disabled) return;
  $("storage").textContent = `${storage.count} envelopes · ${(storage.bytes / 1048576).toFixed(2)} MiB stored`;
  $("stat-days").textContent = new Intl.NumberFormat().format(storage.dayCount);
  $("stat-exports").textContent = new Intl.NumberFormat().format(storage.count);
  $("stat-bytes").textContent = `${(storage.bytes / 1048576).toFixed(2)} MiB retained`;
  const accountExportPages = Math.max(1, Math.ceil(storage.count / 5));
  $("account-export-page").max = String(accountExportPages);
  $("account-export-pages").textContent = `(1–${accountExportPages})`;
  $("account-export-panel").hidden = !dashboardView.capabilities.accountExport;
  $("export-list").replaceChildren();
  $("day-list").replaceChildren();
  if (!exports.length) renderEmptyRow($("export-list"), 6, "No exports yet. Send a single day from your phone to begin.");
  if (!days.length) renderEmptyRow($("day-list"), 5, "No daily snapshots yet. Send an export to begin.");
  appendExports(exports);
  appendDays(days);
  $("more-exports").dataset.offset = nextExportOffset ?? "";
  $("more-exports").hidden = nextExportOffset === null;
  $("more-days").dataset.offset = nextDayOffset ?? "";
  $("more-days").hidden = nextDayOffset === null;
}

async function initLogin() {
  const fragment = new URLSearchParams(location.hash.slice(1));
  const token = fragment.get("token");
  if (location.hash) history.replaceState(null, "", location.pathname);
  let runtime;
  try { runtime = await api("/api/runtime"); }
  catch (error) { status(error.message); return; }
  $("login-form").hidden = runtime.authMode !== "email_link";
  $("password-form").hidden = runtime.authMode !== "password";
  $("unbacked-warning").hidden = !runtime.unbackedPersonalMvp;
  if (runtime.authMode === "email_link") {
    $("login-description").textContent = "Request a single-use email link to access your private export dashboard.";
    if (token) {
      status("Verifying your sign-in link…");
      try {
        await api("/api/auth/consume-link", "POST", { token });
        location.replace("/dashboard");
      } catch (error) { status(error.message); }
    }
  }
  $("login-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const response = await api("/api/auth/request-link", "POST", { email: $("email").value });
      status(response.message);
      if (response.devLink) {
        const link = document.createElement("a");
        link.href = response.devLink;
        link.textContent = "Development sign-in link";
        $("message").append(document.createTextNode(" "), link);
      }
    } catch (error) { status(error.message); }
  });
  $("password-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await api("/api/auth/password-login", "POST", {
        username: $("username").value, password: $("password").value,
      });
      $("password").value = "";
      location.replace("/dashboard");
    } catch (error) { $("password").value = ""; status(error.message); }
  });
}

async function initDashboard() {
  // A template request can straddle an atomic static-asset rollout. No-store
  // reload replaces an older page before the new script binds its controls.
  if (!$("sidebar-toggle")) { location.reload(); return; }
  initDashboardViews();
  $("plan-unlisted-day").addEventListener("click", () => planFromRow({ focus: "date" }));
  $("create-token-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const result = await api("/api/ingest-tokens", "POST", { name: $("token-name").value });
      if (dashboardView.disabled) return;
      $("new-token").value = result.token;
      $("new-token-panel").hidden = false;
      $("token-name").value = "";
      status("Copy your write-only token now. It will not be shown again.");
      await showTokens();
    } catch (error) { status(error.message); }
  });
  $("hide-token").addEventListener("click", () => {
    $("new-token").value = "";
    $("new-token-panel").hidden = true;
  });
  $("create-agent-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    $("new-agent-token").value = "";
    $("new-agent-panel").hidden = true;
    try {
      const result = await api("/api/agent-tokens", "POST", {
        label: $("agent-name").value, days: Number($("agent-days").value),
        password: $("agent-password").value, scope: "full_export",
        consent: $("agent-consent").checked,
      });
      if (dashboardView.disabled) return;
      $("new-agent-token").value = result.token;
      $("new-agent-panel").hidden = false;
      $("agent-name").value = "";
      $("agent-consent").checked = false;
      status("Copy this credential into the agent's secure vault now. It cannot be shown again.");
      await showAgents();
    } catch (error) { status(error.message); }
    finally { $("agent-password").value = ""; }
  });
  $("hide-agent-token").addEventListener("click", () => {
    $("new-agent-token").value = "";
    $("new-agent-panel").hidden = true;
  });
  for (const [id, path, append, field] of [["more-exports", "exports", appendExports, "exports"],
    ["more-days", "days", appendDays, "days"]]) {
    $(id).addEventListener("click", async () => {
      const offset = $(id).dataset.offset;
      if (!offset || dashboardView.disabled || $(id).disabled) return;
      $(id).disabled = true;
      try {
        const page = await api(`/api/${path}/page/${offset}`);
        if (dashboardView.disabled) return;
        append(page[field]);
        $(id).dataset.offset = page.nextOffset ?? "";
        $(id).hidden = page.nextOffset === null;
      } catch (error) { if (!dashboardView.disabled) status(error.message); }
      finally { $(id).disabled = false; }
    });
  }
  $("account-export-page").addEventListener("input", () => {
    const page = Math.min(Number($("account-export-page").max),
      Math.max(1, Number.parseInt($("account-export-page").value, 10) || 1));
    $("download-account-export").href = `/api/account/export/page/${page}`;
  });
  $("revoke-other-sessions").addEventListener("click", async () => {
    try {
      const result = await api("/api/sessions/revoke-others", "POST", {});
      status(`${result.revoked} other browser session(s) signed out.`);
      await showSessions();
    } catch (error) { status(error.message); }
  });
  $("delete-account-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const mode = dashboardView.capabilities.deletionStatus;
    if (mode === "unknown") { status("Deletion support could not be verified. Reload to retry; no request was sent."); return; }
    const statusToken = mode === "supported" ? newDeletionStatusToken() : null;
    try {
      await api("/api/account/delete", "POST", {
        password: $("delete-password").value,
        confirmation: $("delete-confirmation").value,
        ...(statusToken ? { statusToken } : {}),
      });
      $("delete-password").value = "";
      showDeletionPending(statusToken, statusToken ?
        "Account disabled. Durable deletion is pending. Save the one-time status receipt below before leaving this page." :
        "Account disabled. Background deletion is pending; contact the operator to confirm completion. This pilot does not support self-service deletion status receipts.");
    } catch (error) {
      $("delete-password").value = "";
      if (!Number.isInteger(error.httpStatus) || error.httpStatus >= 500) {
        showDeletionPending(statusToken, statusToken ?
          "The deletion request outcome is temporarily uncertain. Save this one-time receipt and check its status shortly." :
          "The deletion request outcome is temporarily uncertain. Contact the operator to confirm its status; this pilot has no self-service deletion status receipt.");
      } else {
        status(error.message);
      }
    }
  });
  try {
    const runtime = await api("/api/runtime");
    if (dashboardView.disabled) return;
    $("synthetic-warning").hidden = !runtime.syntheticPreviewOnly;
    $("unbacked-warning").hidden = !runtime.unbackedPersonalMvp;
    $("agents-section").hidden = !runtime.unbackedPersonalMvp;
    $("endpoint").value = runtime.exportEndpoint;
    $("connect-section").hidden = runtime.syntheticPreviewOnly;
    $("deletion-section").hidden = runtime.syntheticPreviewOnly;
    const passwordDeletion = runtime.authMode === "password";
    $("delete-password-field").hidden = !passwordDeletion;
    $("delete-password").required = passwordDeletion;
    if (!passwordDeletion) {
      $("deletion-copy").textContent = "Deleting your account disables sign-in, uploads, and read credentials immediately. For protection, follow a fresh email sign-in link within 15 minutes before confirming. Stored exports are then erased by a durable background deletion job.";
    }
    const account = await api("/api/account");
    if (dashboardView.disabled) return;
    $("account").textContent = `Signed in as ${account.email}`;
    await detectDashboardCapabilities();
    if (dashboardView.capabilities.deletionStatus === "legacy" && runtime.authMode !== "password") $("deletion-section").hidden = true;
    await Promise.all([showTokens(), ...(dashboardView.capabilities.sessions ? [showSessions()] : []),
      ...(dashboardView.capabilities.securityActivity ? [showSecurityActivity()] : []), showExports(), showTrends().catch(() => {
      if (dashboardView.disabled) return;
      $("trends-window").textContent = "Daily summaries could not be loaded. Other dashboard functions are still available.";
      $("trend-cards").setAttribute("aria-busy", "false");
      for (const label of $("trend-cards").querySelectorAll(".stat-foot")) label.textContent = "Temporarily unavailable";
      $("main-chart").setAttribute("aria-busy", "false");
      $("main-chart").replaceChildren(textElement("p", "Trends are temporarily unavailable. Reload to retry, or explore your original exports.", "chart-empty"));
      $("summary-body").replaceChildren();
      renderEmptyRow($("summary-body"), 1, "Daily summaries are temporarily unavailable, not empty.");
      $("summary-row-count").textContent = "Daily summaries unavailable";
    }), ...(runtime.unbackedPersonalMvp ? [showAgents()] : [])]);
  } catch (error) {
    if (error.message === "Sign in to continue.") location.replace("/login");
    else status(error.message);
  }
}

HealthMdAccount.init();
if (document.body.dataset.page === "login") initLogin();
if (document.body.dataset.page === "dashboard") initDashboard();
