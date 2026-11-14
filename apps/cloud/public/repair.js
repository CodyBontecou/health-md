(() => {
"use strict";
// Shared session-only planner for overview, explorer and standalone view. No
// request scope or health dates in URLs, browser storage, link targets or logs.
// This page cannot launch a mobile export.
const $ = (id) => document.getElementById(id);
const dayMs = 86400000;
const dates = new Set();
let previewed = null;
let ready = false;
let disabled = false;
let pendingSelection = null;
let pendingEvidenceDate = null;
let provenanceSequence = 0;
let inspectedDate = null;
let provenanceOffset = null;
const message = (text) => { if ($("repair-message")) $("repair-message").textContent = text; };
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
function clearProvenance() {
  provenanceSequence++; inspectedDate = null; provenanceOffset = null;
  if ($("repair-provenance-results")) $("repair-provenance-results").replaceChildren();
  if ($("repair-provenance-status")) $("repair-provenance-status").textContent = "";
  if ($("repair-provenance-more")) $("repair-provenance-more").hidden = true;
}
function invalidate() { previewed = null; $("repair-save").disabled = true; $("repair-results").replaceChildren();
  $("repair-status").textContent = "Scope changed. Review coverage before saving."; clearProvenance(); }
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
function describeMetric(id, result) {
  if (result?.status === "observed" && typeof result.value === "number" && Number.isFinite(result.value)) {
    return `${id}: ${result.value} (observed in this export)`;
  }
  return `${id}: value unavailable in this uploaded summary (not zero)`;
}
function renderEvidenceBlock(label, item) {
  const block = element("article", ""); block.className = "record-card";
  block.append(element("h4", label));
  if (!item) { block.append(element("p", "No current primary snapshot was uploaded for this day.")); return block; }
  block.append(element("p", `${item.source === "ios" ? "Apple" : "Android"} v${item.dailyVersion} · ${item.status.replaceAll("_", " ")} · original export ${item.exportId}${item.pointer ? ` ${item.pointer}` : " (no retained day record)"}`));
  block.append(element("p", `Declared calendar timezone: ${item.calendarTimezone || "not reported / not validated"}; compare owner-day boundaries on the phone before exporting.`));
  if (item.captureStatus) block.append(element("p", `Archive capture: ${item.captureStatus}`));
  if (item.scope) block.append(element("p", `Declared scope: ${item.scope === "metric_ids" ? item.metricIds.join(", ") : "entire days"} · ${item.detail.replaceAll("_", " ")} · envelope failures: ${item.failureCount} (not attributed to this day)`));
  if (item.status === "read_limit") block.append(element("p", "Outside this bounded read. Inspect the original export separately."));
  const metrics = Object.entries(item.metrics || {});
  if (metrics.length) {
    const list = element("ul", "");
    for (const [id, value] of metrics) list.append(element("li", describeMetric(id, value)));
    block.append(list);
  }
  return block;
}
async function loadProvenance(date, offset = 0) {
  if (!ready || disabled || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
  const sequence = ++provenanceSequence;
  if (offset === 0) {
    inspectedDate = date; provenanceOffset = null;
    $("repair-provenance-results").replaceChildren();
  }
  $("repair-provenance-more").hidden = true;
  $("repair-provenance-status").textContent = `Checking separately retained evidence for ${date}…`;
  try {
    const result = await api("/api/repair/supplements", { date, offset });
    if (sequence !== provenanceSequence || disabled) return;
    const target = $("repair-provenance-results");
    if (offset === 0) target.append(renderEvidenceBlock("Current primary snapshot", result.primary));
    if (!result.supplements.length && offset === 0) target.append(element("p", "No supplemental export retained for this day. This does not establish whether the phone has readings."));
    for (const entry of result.supplements) target.append(renderEvidenceBlock("Separate supplement · never merged", entry));
    provenanceOffset = result.nextOffset;
    $("repair-provenance-more").hidden = provenanceOffset === null;
    $("repair-provenance-status").textContent = `${date}: original current and supplemental evidence only. Missing values are not zeros; failed-date counts belong to the whole envelope.`;
  } catch (error) {
    if (sequence === provenanceSequence && !disabled) $("repair-provenance-status").textContent = error.message;
  }
}
async function loadDrafts() {
  try {
    const { requests } = await api("/api/repair/drafts");
    if (disabled) return;
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
  } catch (error) { if (!disabled) message(error.message); }
}
async function init() {
  try {
    await api("/api/account");
    if (disabled) return;
    const panel = await fetch("/repair-panel", { credentials: "same-origin", cache: "no-store" });
    if (disabled) return;
    if (!panel.ok) throw new Error("Planner unavailable. Please try again.");
    const fragment = new DOMParser().parseFromString(await panel.text(), "text/html")
      .getElementById("repair-planner");
    if (disabled) return;
    if (!fragment) throw new Error("Planner unavailable. Please try again.");
    $("repair-mount").replaceChildren(document.importNode(fragment, true));
    const { metrics } = await api("/api/explore/catalog");
    if (disabled) return;
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
        if (disabled) return;
        // Do not enable save for a response to an earlier, changed selection.
        if (JSON.stringify(chosen) !== JSON.stringify(spec())) return;
        previewed = chosen; renderPreview(result); $("repair-save").disabled = false; message("");
      } catch (error) { invalidate(); message(error.message); }
    });
    $("repair-read-provenance").addEventListener("click", () => {
      const chosen = $("repair-one").value;
      if (!chosen) { $("repair-provenance-status").textContent = "Choose one owner day above first."; return; }
      void loadProvenance(chosen);
    });
    $("repair-provenance-more").addEventListener("click", () => {
      if (inspectedDate && provenanceOffset !== null) void loadProvenance(inspectedDate, provenanceOffset);
    });
    $("repair-save").addEventListener("click", async () => {
      try { if (!previewed || JSON.stringify(previewed) !== JSON.stringify(spec())) throw new Error("Review the current scope first.");
        const result = await api("/api/repair/drafts", previewed);
        if (disabled) return;
        $("repair-save").disabled = true; previewed = null;
        await loadDrafts(); message(`Private draft saved until ${new Date(result.expiresAt).toLocaleString()}. No export or link was started.`);
      } catch (error) { message(error.message); }
    });
    syncSource(); ready = true;
    if (pendingSelection) { applySelection(pendingSelection); pendingSelection = null; }
    await loadDrafts();
    if (pendingEvidenceDate) { const day = pendingEvidenceDate; pendingEvidenceDate = null; void loadProvenance(day); }
  } catch (error) {
    if (disabled) return;
    if (error.message === "Sign in to continue.") location.replace("/login");
    else if ($("repair-message")) message(error.message);
    else $("repair-mount").textContent = "Planner temporarily unavailable. Other dashboard functions still work.";
  }
}
function applySelection(selection) {
  if (!ready) { pendingSelection = selection; return; }
  const source = selection?.source;
  const metricId = selection?.metricId;
  const chosen = selection?.date ? [selection.date] : selection?.dates || [];
  if (source && source !== "ios" && source !== "android") return;
  if (!Array.isArray(chosen) || chosen.length > 31 || chosen.some((date) => {
    if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return true;
    const stamp = Date.parse(`${date}T00:00:00Z`);
    return !Number.isFinite(stamp) || new Date(stamp).toISOString().slice(0, 10) !== date ||
      date > new Date(Date.now() + dayMs).toISOString().slice(0, 10);
  })) return;
  if (metricId && (source !== "ios" || ![...$("repair-metrics").querySelectorAll("input")]
    .some((input) => input.value === metricId))) return;
  const sourceChanged = Boolean(source && source !== $("repair-source").value);
  const clearedPrevious = sourceChanged && dates.size > 0;
  const proposed = new Set(sourceChanged ? [] : dates);
  for (const date of chosen) proposed.add(date);
  if (proposed.size > 31) {
    message("Maximum 31 selected days. Remove some before adding another range."); return;
  }
  if (sourceChanged) {
    for (const input of $("repair-metrics").querySelectorAll("input")) input.checked = false;
    $("repair-source").value = source;
    $("repair-scope").value = source === "android" ? "entire_days" : "metric_ids";
  }
  if (metricId) {
    $("repair-scope").value = "metric_ids";
    [...$("repair-metrics").querySelectorAll("input")]
      .find((input) => input.value === metricId).checked = true;
  } else if (selection?.entireDay) $("repair-scope").value = "entire_days";
  dates.clear(); for (const date of proposed) dates.add(date);
  if (chosen.length === 1) $("repair-one").value = chosen[0];
  syncSource(); renderDates();
  $("repair-planner").scrollIntoView({ behavior: "smooth", block: "start" });
  $(chosen.length ? "repair-preview" : "repair-one").focus({ preventScroll: true });
  message(chosen.length ? `${chosen.length} day(s) added to this private plan.${clearedPrevious ? " Previous source selections were cleared." : ""} Review coverage before saving.` :
    "Choose a date to plan an export. This cannot contact your phone yet.");
}
if ($("repair-mount")) {
  document.addEventListener("healthmd:repair-select", (event) => applySelection(event.detail));
  document.addEventListener("healthmd:repair-provenance", (event) => {
    if (!ready) { pendingEvidenceDate = event.detail?.date; return; }
    $("repair-planner").scrollIntoView({ behavior: "smooth", block: "start" });
    void loadProvenance(event.detail?.date);
  });
  document.addEventListener("healthmd:repair-clear", () => {
    dates.clear(); previewed = null; pendingSelection = null; pendingEvidenceDate = null; ready = false; disabled = true;
    clearProvenance();
  });
  document.addEventListener("click", (event) => {
    if (event.target instanceof Element && event.target.closest('a[href="#repair-planner"]') && !ready) {
      event.preventDefault(); applySelection({ focus: "date" });
    }
  });
  window.addEventListener("pagehide", () => {
    dates.clear(); previewed = null; pendingSelection = null; pendingEvidenceDate = null; ready = false;
    clearProvenance(); $("repair-mount").replaceChildren();
  });
  window.addEventListener("pageshow", (event) => { if (event.persisted) location.reload(); });
  void init();
}
})();
