"use strict";
// Session-only planner. No request scope or health dates in URLs, browser
// storage, link targets or logs. This page cannot launch a mobile export.
const $ = (id) => document.getElementById(id);
const dayMs = 86400000;
const dates = new Set();
let previewed = null;
const message = (text) => { $("repair-message").textContent = text; };
const element = (name, text) => { const node = document.createElement(name); node.textContent = text; return node; };
async function api(path, body, method) {
  const response = await fetch(path, { method: method || (body === undefined ? "GET" : "POST"),
    credentials: "same-origin", cache: "no-store", headers: body === undefined ? {} : {
      "Content-Type": "application/json", "X-HealthMd-Intent": "dashboard" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message || "Request failed.");
  return result;
}
function invalidate() { previewed = null; $("repair-save").disabled = true; $("repair-results").replaceChildren();
  $("repair-status").textContent = "Scope changed. Review coverage before saving."; }
function renderDates() {
  const list = $("repair-dates"); list.replaceChildren();
  for (const date of [...dates].sort()) {
    const row = element("li", date);
    const button = element("button", `Remove ${date}`); button.type = "button"; button.className = "subtle";
    button.addEventListener("click", () => { dates.delete(date); invalidate(); renderDates(); });
    row.append(button); list.append(row);
  }
}
function syncSource() {
  const android = $("repair-source").value === "android";
  if (android) { $("repair-scope").value = "entire_days";
    if ($("repair-detail").value === "lossless") $("repair-detail").value = "summary"; }
  $("repair-scope").querySelector('[value="metric_ids"]').disabled = android;
  $("repair-detail").querySelector('[value="lossless"]').disabled = android;
  $("repair-metric-fieldset").hidden = $("repair-scope").value !== "metric_ids";
  invalidate();
}
function spec() {
  const metricIds = $("repair-scope").value === "metric_ids" ?
    [...$("repair-metrics").querySelectorAll("input:checked")].map((node) => node.value).sort() : [];
  const chosen = [...dates].sort();
  if (!chosen.length || chosen.length > 31 || ($("repair-scope").value === "metric_ids" && !metricIds.length)) {
    throw new Error("Choose 1–31 dates and at least one metric for a selected-metrics request.");
  }
  return { source: $("repair-source").value, dates: chosen, scope: $("repair-scope").value,
    metricIds, detail: $("repair-detail").value };
}
function coverageText(day, id) {
  const evidence = day.metrics[id];
  return evidence === "observed" ? "Observed in retained summary" :
    evidence === "no_uploaded_day" ? "No uploaded day" :
    evidence === "value_unavailable_in_uploaded_summary" ? "Value unavailable in uploaded summary" :
    day.coverage === "read_limit" ? "Outside bounded read" : day.coverage === "different_source" ?
      "Another source has the current day" : day.coverage === "unsupported_profile" ?
        "No reviewed mapping for this schema" : day.coverage === "not_uploaded" ?
          "No uploaded day" : "Current day uploaded; original fields may differ";
}
function renderPreview(result) {
  const table = element("table", "");
  table.append(element("caption", "Retained evidence only; no phone was queried"));
  const header = element("tr", "");
  for (const label of ["Owner day", "Current snapshot", "Replacement safety", ...(result.spec.metricIds.length ?
    ["Selected metrics"] : [])]) {
    const th = element("th", label); th.scope = "col"; header.append(th);
  }
  const head = element("thead", ""); head.append(header); table.append(head);
  const body = element("tbody", "");
  for (const day of result.days) {
    const row = element("tr", ""); row.append(element("td", day.date));
    row.append(element("td", day.coverage === "not_uploaded" ? "Not uploaded" :
      `${day.source === "ios" ? "Apple" : "Android"} v${day.dailyVersion} · ${day.coverage.replaceAll("_", " ")}`));
    row.append(element("td", day.safety === "new_day_only" ? "No current snapshot to replace" :
      day.safety === "source_conflict" ? "Different source; do not overwrite" :
        "Existing snapshot; safe supplement required"));
    if (result.spec.metricIds.length) {
      const cell = element("td", "");
      for (const id of result.spec.metricIds) cell.append(element("div", `${id}: ${coverageText(day, id)}`));
      row.append(cell);
    }
    body.append(row);
  }
  table.append(body); $("repair-results").replaceChildren(table);
  $("repair-status").textContent = `${result.days.length} day(s) reviewed. No device was contacted. No request can launch from this dashboard yet.`;
}
async function loadDrafts() {
  try {
    const { requests } = await api("/api/repair/drafts");
    const list = $("repair-drafts"); list.replaceChildren();
    if (!requests.length) { list.append(element("li", "No active drafts.")); return; }
    for (const draft of requests) {
      const row = element("li", "");
      row.append(element("span", `${draft.spec.dates.length} ${draft.spec.source === "ios" ? "Apple" : "Android"} day(s) · ${draft.spec.scope === "metric_ids" ? `${draft.spec.metricIds.length} selected metric(s)` : "entire days"} · ${draft.spec.detail.replaceAll("_", " ")} · expires ${new Date(draft.expiresAt).toLocaleString()} · not sent`));
      const remove = element("button", "Cancel draft"); remove.type = "button"; remove.className = "subtle";
      remove.addEventListener("click", async () => {
        try { await api(`/api/repair/drafts/${draft.id}`, {}, "DELETE"); await loadDrafts(); message("Draft cancelled."); }
        catch (error) { message(error.message); }
      }); row.append(remove); list.append(row);
    }
  } catch (error) { message(error.message); }
}
async function init() {
  try {
    await api("/api/account");
    const { metrics } = await api("/api/explore/catalog");
    for (const metric of metrics) {
      const label = element("label", ""); label.className = "metric-choice";
      const input = element("input", ""); input.type = "checkbox"; input.value = metric.id;
      input.addEventListener("change", invalidate);
      label.append(input, document.createTextNode(`${metric.label} · ${metric.unit}`));
      $("repair-metrics").append(label);
    }
    for (const id of ["repair-source", "repair-scope", "repair-detail"]) {
      $(id).addEventListener("change", syncSource);
    }
    $("repair-add-one").addEventListener("click", () => {
      const date = $("repair-one").value;
      if (!date) { message("Choose a day first."); return; }
      if (!dates.has(date) && dates.size >= 31) { message("Maximum 31 distinct days."); return; }
      dates.add(date); invalidate(); renderDates(); message("");
    });
    $("repair-add-range").addEventListener("click", () => {
      const from = $("repair-from").value; const through = $("repair-through").value;
      const start = Date.parse(`${from}T00:00:00Z`); const end = Date.parse(`${through}T00:00:00Z`);
      const count = (end - start) / dayMs + 1;
      if (!Number.isInteger(count) || count < 1 || count > 31) { message("Choose 1–31 valid calendar days."); return; }
      const proposed = new Set(dates);
      for (let i = 0; i < count; i++) proposed.add(new Date(start + i * dayMs).toISOString().slice(0, 10));
      if (proposed.size > 31) { message("Combined selection exceeds 31 distinct days."); return; }
      dates.clear(); for (const date of proposed) dates.add(date);
      invalidate(); renderDates(); message("");
    });
    $("repair-form").addEventListener("submit", async (event) => {
      event.preventDefault(); try { const chosen = spec(); const result = await api("/api/repair/preview", chosen);
        // Do not enable save for a response to an earlier, changed selection.
        if (JSON.stringify(chosen) !== JSON.stringify(spec())) return;
        previewed = chosen; renderPreview(result); $("repair-save").disabled = false; message("");
      } catch (error) { invalidate(); message(error.message); }
    });
    $("repair-save").addEventListener("click", async () => {
      try { if (!previewed || JSON.stringify(previewed) !== JSON.stringify(spec())) throw new Error("Review the current scope first.");
        const result = await api("/api/repair/drafts", previewed);
        $("repair-save").disabled = true; previewed = null;
        await loadDrafts(); message(`Private draft saved until ${new Date(result.expiresAt).toLocaleString()}. No export or link was started.`);
      } catch (error) { message(error.message); }
    });
    syncSource(); await loadDrafts();
  } catch (error) { if (error.message === "Sign in to continue.") location.replace("/login"); else message(error.message); }
}
if (document.body.dataset.page === "repair") {
  window.addEventListener("pagehide", () => { dates.clear(); previewed = null;
    $("repair-results").replaceChildren(); $("repair-drafts").replaceChildren(); });
  window.addEventListener("pageshow", (event) => { if (event.persisted) location.reload(); });
  void init();
}
