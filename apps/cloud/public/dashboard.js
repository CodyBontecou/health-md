"use strict";
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

function showDeletionPending(statusToken, message) {
  $("connect-section").hidden = true;
  $("deletion-section").hidden = true;
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
  $("deletion-status-token").value = statusToken;
  $("deletion-receipt-section").hidden = false;
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
  const list = $("security-activity-list");
  list.replaceChildren();
  if (!events.length) addTextRow(list, "No recent security activity", "New events will appear here");
  for (const event of events) {
    addTextRow(list, securityEventLabels[event.type] || "Security activity",
      new Date(event.occurredAt).toLocaleString());
  }
}

// Charts intentionally use no remote dependency or external asset: the
// browser receives only bounded, owner-session daily summary projections.
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
function renderTrend(metric, days) {
  const card = document.createElement("article");
  card.className = "chart-card";
  const heading = document.createElement("header");
  const name = document.createElement("span");
  name.className = "chart-name";
  name.textContent = metric.label;
  const unit = document.createElement("span");
  unit.className = "chart-unit";
  unit.textContent = metric.unit;
  heading.append(name, unit);
  const observations = days.map((day, index) => ({ index, day, value: day.values[metric.id] }))
    .filter(({ day, value }) => day.status === "available" && typeof value === "number" && Number.isFinite(value));
  const latest = observations.at(-1);
  const value = document.createElement("p");
  value.className = "chart-value";
  value.textContent = latest ? formatted(latest.value) : "—";
  const subtitle = document.createElement("p");
  subtitle.className = "chart-subtitle";
  subtitle.textContent = latest ? `Latest retained value · ${formatDay(latest.day.date)}` : "No value in this retained window";
  const plot = document.createElement("div");
  plot.className = "chart-plot";
  const chart = svgElement("svg", { viewBox: "0 0 300 112", preserveAspectRatio: "none",
    role: "img", "aria-label": `${metric.label}: ${observations.length} observed of ${days.length} calendar days. Missing days are not connected.` });
  chart.append(svgElement("line", { x1: 0, y1: 105, x2: 300, y2: 105, class: "chart-base" }));
  if (observations.length) {
    const numbers = observations.map((item) => item.value);
    const min = Math.min(...numbers);
    const max = Math.max(...numbers);
    const span = Math.max(1, max - min);
    let segment = [];
    const drawSegment = () => {
      if (segment.length > 1) chart.append(svgElement("path", { d: segment.join(" "), class: "chart-line" }));
      segment = [];
    };
    for (let index = 0; index < days.length; index++) {
      const day = days[index];
      const reading = day.status === "available" ? day.values[metric.id] : null;
      if (typeof reading !== "number" || !Number.isFinite(reading)) { drawSegment(); continue; }
      const x = 8 + index * (284 / Math.max(1, days.length - 1));
      const y = 94 - ((reading - min) / span) * 72;
      segment.push(`${segment.length ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)}`);
      if (index === latest?.index || observations.length === 1) {
        chart.append(svgElement("circle", { cx: x.toFixed(2), cy: y.toFixed(2), r: 3.5, class: "chart-point" }));
      }
    }
    drawSegment();
  }
  plot.append(chart);
  const axis = document.createElement("div");
  axis.className = "chart-axis";
  for (const date of [days[0].date, days.at(-1).date]) {
    const label = document.createElement("span");
    label.textContent = formatDay(date);
    axis.append(label);
  }
  const coverage = document.createElement("div");
  coverage.className = "chart-coverage";
  coverage.textContent = `${observations.length} of ${days.length} calendar days have this value`;
  const details = document.createElement("details");
  details.className = "chart-table";
  const summary = document.createElement("summary");
  summary.textContent = "View daily values & gaps";
  const table = document.createElement("table");
  const caption = document.createElement("caption");
  caption.textContent = `${metric.label} from retained daily exports`;
  const head = document.createElement("thead");
  const headerRow = document.createElement("tr");
  for (const text of ["Date", "Value or reason", "Evidence & plan"]) {
    const cell = document.createElement("th");
    cell.scope = "col";
    cell.textContent = text;
    headerRow.append(cell);
  }
  head.append(headerRow);
  const body = document.createElement("tbody");
  for (const day of days) {
    const row = document.createElement("tr");
    for (const text of [day.date, dayLabel(day, metric.id, metric.unit)]) {
      const cell = document.createElement("td");
      cell.textContent = text;
      row.append(cell);
    }
    const action = document.createElement("td");
    if (day.status === "not_uploaded" || day.status === "available") {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "subtle";
      button.textContent = "Add to plan";
      button.setAttribute("aria-label", `Plan ${metric.label} for ${day.date}`);
      button.addEventListener("click", () => planFromRow({ date: day.date, source: "ios", metricId: metric.id }));
      action.append(button);
    }
    const provenance = document.createElement("button");
    provenance.type = "button";
    provenance.className = "subtle";
    provenance.textContent = "Review supplements";
    provenance.setAttribute("aria-label", `Review separately retained evidence for ${day.date}`);
    provenance.addEventListener("click", () => document.dispatchEvent(
      new CustomEvent("healthmd:repair-provenance", { detail: { date: day.date } })));
    action.append(provenance);
    row.append(action);
    body.append(row);
  }
  table.append(caption, head, body);
  details.append(summary, table);
  card.append(heading, value, subtitle, plot, axis, coverage, details);
  return card;
}
async function showTrends() {
  const result = await api("/api/dashboard/trends");
  const cards = $("trend-cards");
  cards.replaceChildren();
  if (!result.window.end) {
    $("trends-window").textContent = "No retained daily exports yet";
    $("trends-note").textContent = "Export a Summary day to see trends. No sample or device data is filled in for you.";
    return;
  }
  $("trends-window").textContent = `${result.window.start} – ${result.window.end} · Last 30 calendar days ending with your latest retained snapshot`;
  $("stat-latest").textContent = formatDay(result.window.end);
  for (const metric of result.metrics) cards.append(renderTrend(metric, result.days));
  const excluded = result.days.filter((day) => day.status === "unsupported_profile").length;
  const limited = result.days.filter((day) => day.status === "read_limit").length;
  $("trends-note").textContent = `Summary values are not a clinical interpretation or a real-time device reading. Archive and provider data are not charted.${excluded ? ` ${excluded} day(s) use a profile without a reviewed Apple mapping.` : ""}${limited ? ` ${limited} day(s) exceeded this view's bounded read budget.` : ""}`;
}

function appendExports(exports) {
  const list = $("export-list");
  for (const item of exports) {
    const link = document.createElement("a");
    link.href = `/api/exports/${item.id}/download`;
    link.textContent = "Download JSON";
    addTextRow(list, `${item.dateStart} – ${item.dateEnd}`,
      `${item.recordCount} retained day record(s) · ${item.source} · ${item.retentionRole === "supplemental" ? "separate supplement, not current" : item.retentionRole === "current" ? "current for at least one day" : "unreferenced/revision"} · ${new Date(item.receivedAt).toLocaleString()}`, link);
  }
}

function appendDays(days) {
  for (const day of days) {
    const action = document.createElement("button");
    action.type = "button";
    action.className = "subtle";
    action.textContent = "Plan entire day";
    action.setAttribute("aria-label", `Plan entire ${day.source === "ios" ? "Apple" : "Android"} day ${day.date}`);
    action.addEventListener("click", () => planFromRow({ date: day.date, source: day.source, entireDay: true }));
    const buttons = document.createElement("span"); buttons.append(action);
    const provenance = document.createElement("button"); provenance.type = "button";
    provenance.className = "subtle"; provenance.textContent = "Review supplements";
    provenance.setAttribute("aria-label", `Review separately retained evidence for ${day.date}`);
    provenance.addEventListener("click", () => document.dispatchEvent(
      new CustomEvent("healthmd:repair-provenance", { detail: { date: day.date } })));
    buttons.append(provenance);
    addTextRow($("day-list"), day.date,
      `${day.source === "ios" ? "Apple" : "Android"} v${day.schemaVersion} · ${day.captureStatus || "status not reported"}`, buttons);
  }
}

async function showExports() {
  const { exports, days, storage, nextExportOffset, nextDayOffset } = await api("/api/exports");
  $("storage").textContent = `${storage.count} envelopes · ${(storage.bytes / 1048576).toFixed(2)} MiB stored`;
  $("stat-days").textContent = new Intl.NumberFormat().format(storage.dayCount);
  $("stat-exports").textContent = new Intl.NumberFormat().format(storage.count);
  $("stat-bytes").textContent = `${(storage.bytes / 1048576).toFixed(2)} MiB on this unbacked VM`;
  const accountExportPages = Math.max(1, Math.ceil(storage.count / 5));
  $("account-export-page").max = String(accountExportPages);
  $("account-export-pages").textContent = `(1–${accountExportPages})`;
  $("account-export-panel").hidden = false;
  $("export-list").replaceChildren();
  $("day-list").replaceChildren();
  if (!exports.length) addTextRow($("export-list"), "No exports yet", "Send a single day from your phone to begin");
  if (!days.length) addTextRow($("day-list"), "No daily snapshots", "Send an export to begin");
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
  $("plan-unlisted-day").addEventListener("click", () => planFromRow({ focus: "date" }));
  $("logout").addEventListener("click", async () => {
    try {
      await api("/api/auth/logout", "POST");
      location.replace("/login");
    } catch (error) { status(error.message); }
  });
  $("create-token-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const result = await api("/api/ingest-tokens", "POST", { name: $("token-name").value });
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
  $("more-exports").addEventListener("click", async () => {
    const offset = $("more-exports").dataset.offset;
    if (!offset) return;
    try {
      const page = await api(`/api/exports/page/${offset}`);
      appendExports(page.exports);
      $("more-exports").dataset.offset = page.nextOffset ?? "";
      $("more-exports").hidden = page.nextOffset === null;
    } catch (error) { status(error.message); }
  });
  $("more-days").addEventListener("click", async () => {
    const offset = $("more-days").dataset.offset;
    if (!offset) return;
    try {
      const page = await api(`/api/days/page/${offset}`);
      appendDays(page.days);
      $("more-days").dataset.offset = page.nextOffset ?? "";
      $("more-days").hidden = page.nextOffset === null;
    } catch (error) { status(error.message); }
  });
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
    const statusToken = newDeletionStatusToken();
    try {
      await api("/api/account/delete", "POST", {
        password: $("delete-password").value,
        confirmation: $("delete-confirmation").value,
        statusToken,
      });
      $("delete-password").value = "";
      showDeletionPending(statusToken,
        "Account disabled. Durable deletion is pending. Save the one-time status receipt below before leaving this page.");
    } catch (error) {
      $("delete-password").value = "";
      if (!Number.isInteger(error.httpStatus) || error.httpStatus >= 500) {
        showDeletionPending(statusToken,
          "The deletion request outcome is temporarily uncertain. Save this one-time receipt and check its status shortly.");
      } else {
        status(error.message);
      }
    }
  });
  try {
    const runtime = await api("/api/runtime");
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
    $("account").textContent = `Signed in as ${account.email}`;
    await Promise.all([showTokens(), showSessions(), showSecurityActivity(), showExports(), showTrends().catch(() => {
      $("trends-window").textContent = "Daily summaries could not be loaded. Other dashboard functions are still available.";
      $("trend-cards").replaceChildren();
    }), ...(runtime.unbackedPersonalMvp ? [showAgents()] : [])]);
  } catch (error) {
    if (error.message === "Sign in to continue.") location.replace("/login");
    else status(error.message);
  }
}

if (document.body.dataset.page === "login") initLogin();
if (document.body.dataset.page === "dashboard") initDashboard();
