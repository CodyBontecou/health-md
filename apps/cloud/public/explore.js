(() => {
"use strict";
// First-party, session-only explorer. No selected fields, credentials, or
// readings are stored in URLs, localStorage, third-party scripts or logs.
const $ = (id) => document.getElementById(id);
const NS = "http://www.w3.org/2000/svg";
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const dayMs = 86400000;
const shortDate = (date) => new Date(`${date}T12:00:00Z`).toLocaleDateString(undefined,
  { month: "short", day: "numeric", timeZone: "UTC" });
const display = (value) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);
const shiftDay = (date, delta) => new Date(Date.parse(`${date}T00:00:00Z`) + delta * dayMs).toISOString().slice(0, 10);
const note = (text) => { $("explore-message").textContent = text; };
const planFromRow = (selection) => document.dispatchEvent(
  new CustomEvent("healthmd:repair-select", { detail: selection }));
let chartSequence = 0;
let librarySequence = 0;
let selectedExport = null;
let selectedPointer = "";
let selectedOffset = 0;
let nodeSequence = 0;
let disabled = false;
let supplementsAvailable = false;
function emptyTable(body, columns, text) {
  const row = element("tr"); const cell = element("td", text, "table-empty");
  cell.colSpan = columns; row.append(cell); body.replaceChildren(row);
}
function clearInspector() {
  for (const id of ["inspector-value", "inspector-children", "inspector-path"]) $(id).replaceChildren();
  for (const id of ["inspector-root", "inspector-up", "inspector-more", "inspector-previous", "inspector-download"]) $(id).hidden = true;
  $("inspector-download").removeAttribute("href");
  $("inspector-children").closest(".table-scroll").hidden = true;
}
function clearExplorer() {
  disabled = true; chartSequence++; librarySequence++; nodeSequence++;
  selectedExport = null; selectedPointer = ""; selectedOffset = 0; supplementsAvailable = false;
  clearInspector();
  for (const id of ["explore-charts", "library-list", "metric-options", "chart-summary", "inspector-meta", "library-status"]) $(id).replaceChildren();
  $("library-more").hidden = true;
  $("chart-settings").open = false;
}

async function api(path, body) {
  const response = await fetch(path, { method: body === undefined ? "GET" : "POST", credentials: "same-origin",
    cache: "no-store", headers: body === undefined ? {} : {
      "Content-Type": "application/json", "X-HealthMd-Intent": "dashboard" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message || "Request failed.");
  return result;
}
function svg(tag, attrs) {
  const element = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, String(value));
  return element;
}
function element(tag, text, className) {
  const item = document.createElement(tag);
  if (text !== undefined) item.textContent = text;
  if (className) item.className = className;
  return item;
}
function dayReading(day, id, unit) {
  if (!day) return "Outside period";
  if (day.status === "not_uploaded") return "Not uploaded";
  if (day.status === "filtered_profile") return "Excluded by source filter";
  if (day.status === "unsupported_profile") return "No reviewed Apple mapping";
  if (day.status === "read_limit") return "Outside bounded read";
  const value = day.values?.[id];
  return typeof value === "number" && Number.isFinite(value) ? `${display(value)} ${unit}` : "Value unavailable";
}
function inspectButton(exportId, pointer, label) {
  const button = element("button", label, "subtle");
  button.type = "button";
  button.addEventListener("click", () => { void openNode(exportId, pointer, 0); });
  return button;
}
function chartCard(metric, first, second, chartType, axisMode) {
  const card = element("article", undefined, "chart-card");
  const title = element("h3", `${metric.label} · ${metric.unit}`);
  const periods = [first, ...(second ? [second] : [])];
  const readings = periods.flatMap((period) => period.days.filter((day) => day.status === "available").map((day) => day.values?.[metric.id])
    .filter((value) => typeof value === "number" && Number.isFinite(value)));
  const minValue = readings.length ? Math.min(...readings) : 0;
  const maxValue = readings.length ? Math.max(...readings) : 0;
  const low = axisMode === "zero" ? Math.min(0, minValue) : minValue;
  const high = axisMode === "zero" ? Math.max(0, maxValue) : maxValue;
  const span = Math.max(1, high - low);
  const latest = [...first.days].reverse().find((day) => day.status === "available" && typeof day.values?.[metric.id] === "number" && Number.isFinite(day.values[metric.id]));
  const headline = element("p", latest ? `${display(latest.values[metric.id])} ${metric.unit}` : "—", "chart-value");
  const detail = element("p", latest ? `Latest in selected period · ${latest.date}` : "No observation in selected period", "chart-subtitle");
  const scale = element("p", `${axisMode === "zero" ? "Zero-based" : "Data-range"} axis · ${display(low)}–${display(high)} ${metric.unit}${second ? " · shared between periods" : ""}`, "chart-scale");
  const plot = element("div", undefined, "chart-plot");
  const picture = svg("svg", { viewBox: "0 0 300 112", preserveAspectRatio: "none", role: "img",
    "aria-label": `${metric.label}: ${readings.length} observations from retained exports. Gaps are disconnected. See table for exact dates and missingness.` });
  picture.append(svg("line", { x1: 0, x2: 300, y1: 104, y2: 104, class: "chart-base" }));
  const longest = Math.max(...periods.map((period) => period.days.length));
  for (let series = 0; series < periods.length; series++) {
    let segment = [];
    const draw = () => {
      if (segment.length > 1) picture.append(svg("path", { d: segment.join(" "),
        class: series === 0 ? "chart-line" : "chart-line chart-compare" }));
      segment = [];
    };
    periods[series].days.forEach((day, index) => {
      const value = day.status === "available" ? day.values?.[metric.id] : null;
      if (typeof value !== "number" || !Number.isFinite(value)) { draw(); return; }
      const x = 8 + index * (284 / Math.max(1, longest - 1));
      const y = 96 - ((value - low) / span) * 79;
      if (chartType === "bars") picture.append(svg("rect", {
        x: (x - (series === 0 ? 4 : 0)).toFixed(2), y: y.toFixed(2),
        width: second ? 3.6 : 6, height: Math.max(1, 97 - y).toFixed(2),
        class: series === 0 ? "chart-bar" : "chart-bar chart-bar-compare",
      }));
      else {
        segment.push(`${segment.length ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)}`);
        picture.append(svg("circle", { cx: x.toFixed(2), cy: y.toFixed(2), r: 2.4,
          class: series === 0 ? "chart-point" : "chart-point chart-point-compare" }));
      }
    });
    draw();
  }
  plot.append(picture);
  const legend = element("p", `${first.window.start}–${first.window.end} · ${first.days.filter((day) => day.status === "available" && Number.isFinite(day.values?.[metric.id])).length}/${first.days.length} observed${second ? `  |  comparison ${second.window.start}–${second.window.end} · ${second.days.filter((day) => day.status === "available" && Number.isFinite(day.values?.[metric.id])).length}/${second.days.length} observed` : ""}`, "chart-coverage");
  const details = element("details", undefined, "chart-table");
  details.append(element("summary", "Dates, missingness & inspect"));
  const table = element("table", undefined, "data-table");
  table.append(element("caption", `${metric.label} · source dates (not upload timestamps)`));
  const thead = element("thead");
  const heading = element("tr");
  for (const text of ["Day", "Selected period", ...(second ? ["Comparison"] : []), "Evidence & plan"]) {
    const th = element("th", text); th.scope = "col"; heading.append(th);
  }
  thead.append(heading); table.append(thead);
  const tbody = element("tbody");
  for (let index = 0; index < longest; index++) {
    const row = element("tr");
    row.append(element("td", String(index + 1)));
    const day = first.days[index];
    row.append(element("td", day ? `${day.date} · ${dayReading(day, metric.id, metric.unit)}` : "Outside period"));
    if (second) {
      const compareDay = second.days[index];
      row.append(element("td", compareDay ? `${compareDay.date} · ${dayReading(compareDay, metric.id, metric.unit)}` : "Outside period"));
    }
    const source = element("td");
    if (day?.exportId && uuid.test(day.exportId) && Number.isSafeInteger(day.recordIndex))
      source.append(inspectButton(day.exportId, `/records/${day.recordIndex}`, `Inspect ${day.date}`));
    if (second?.days[index]?.exportId && uuid.test(second.days[index].exportId) &&
        Number.isSafeInteger(second.days[index].recordIndex)) {
      source.append(inspectButton(second.days[index].exportId,
        `/records/${second.days[index].recordIndex}`, `Inspect ${second.days[index].date}`));
    }
    for (const inspected of supplementsAvailable ? new Set([day?.date, second?.days[index]?.date].filter(Boolean)) : []) {
      const button = element("button", `Review ${inspected} supplements`, "subtle");
      button.type = "button";
      button.addEventListener("click", () => document.dispatchEvent(
        new CustomEvent("healthmd:repair-provenance", { detail: { date: inspected } })));
      source.append(button);
    }
    for (const period of periods) {
      const selected = period.days[index];
      if (period.profile === "android_compat" || !selected ||
          (selected.status !== "available" && selected.status !== "not_uploaded")) continue;
      const button = element("button", `Plan ${selected.date}`, "subtle");
      button.type = "button";
      button.setAttribute("aria-label", `Plan ${metric.label} for ${selected.date}`);
      button.addEventListener("click", () => planFromRow({ date: selected.date,
        source: "ios", metricId: metric.id }));
      source.append(button);
    }
    row.append(source); tbody.append(row);
  }
  table.append(tbody); details.append(table);
  card.append(title, headline, detail, scale, plot, legend, details);
  return card;
}
async function renderCharts(event) {
  event?.preventDefault();
  if (disabled) return;
  const ids = [...$("metric-options").querySelectorAll("input:checked")].map((input) => input.value);
  if (!ids.length) { note("Choose at least one metric."); return; }
  const start = $("chart-start").value;
  const end = $("chart-end").value;
  const count = (Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / dayMs + 1;
  if (!Number.isInteger(count) || count < 1 || count > 31) { note("Choose 1–31 calendar days."); return; }
  const compare = $("compare-enabled").checked;
  if (compare) {
    const secondCount = (Date.parse(`${$("compare-end").value}T00:00:00Z`) -
      Date.parse(`${$("compare-start").value}T00:00:00Z`)) / dayMs + 1;
    if (!Number.isInteger(secondCount) || secondCount < 1 || secondCount > 31) {
      note("Choose 1–31 comparison days."); return;
    }
  }
  const seq = ++chartSequence;
  $("chart-summary").textContent = "Reading selected retained days…";
  try {
    const profile = $("chart-profile").value;
    const [first, second] = await Promise.all([
      api("/api/explore/chart", { start, end, metrics: ids, profile }),
      compare ? api("/api/explore/chart", { start: $("compare-start").value,
        end: $("compare-end").value, metrics: ids, profile }) : Promise.resolve(null),
    ]);
    if (seq !== chartSequence) return;
    const grid = $("explore-charts"); grid.replaceChildren(); grid.setAttribute("aria-busy", "false");
    for (const metric of first.metrics) grid.append(chartCard(metric, first, second,
      $("chart-type").value, $("chart-axis").value));
    $("chart-summary").textContent = `${start} – ${end}${second ? ` compared with ${second.window.start} – ${second.window.end}` : ""} · ${profile === "android_compat" ? "Android records remain inspectable below; no Apple summary mapping" : "Apple v8 metric semantics only"}`;
    note("");
  } catch (error) {
    if (seq === chartSequence && !disabled) { $("chart-summary").textContent = "Daily summaries are temporarily unavailable, not empty.";
      $("explore-charts").setAttribute("aria-busy", "false");
      $("explore-charts").replaceChildren(element("p", "Retained summaries could not be loaded. Retry your view, or browse original exports.", "chart-empty")); note(error.message); }
  }
}
function libraryFilter(offset) {
  const version = $("library-version").value;
  return { source: $("library-source").value, version: version === "all" ? "all" : Number(version),
    scope: $("library-scope").value, start: $("library-start").value || null,
    end: $("library-end").value || null, offset };
}
async function showLibrary(offset = 0) {
  if (disabled) return;
  const seq = ++librarySequence;
  $("library-status").textContent = "Reading retained export metadata…";
  try {
    const page = await api("/api/explore/exports", libraryFilter(offset));
    if (seq !== librarySequence) return;
    const list = $("library-list");
    if (offset === 0) list.replaceChildren();
    for (const item of page.exports) {
      const row = element("tr");
      const role = item.retentionRole === "supplemental" ? "Separate supplement" :
        item.retentionRole === "current" ? "Current for ≥1 day" : ["revision", "unreferenced"].includes(item.retentionRole) ? "Revision / unreferenced" : "Not reported";
      const source = item.source === "ios" ? "Apple" : item.source === "android" ? "Android" : "Not reported";
      const count = (value) => Number.isSafeInteger(value) && value >= 0 ? String(value) : "—";
      row.append(element("td", item.dateStart && item.dateEnd ? `${item.dateStart} – ${item.dateEnd}` : "No declared days", "date-cell"),
        element("td", `${source} · ${Number.isSafeInteger(item.dailyVersion) ? `v${item.dailyVersion}` : "Schema not reported"}`));
      const roleCell = element("td"); roleCell.append(element("span", role, "evidence-badge"));
      row.append(roleCell, element("td", count(item.recordCount), "numeric-cell"),
        element("td", `${count(item.failureCount)} / ${count(item.externalRecordCount)}`, "numeric-cell"),
        element("td", new Date(item.receivedAt).toLocaleString()));
      const actions = element("td", undefined, "row-actions");
      if (uuid.test(item.id)) {
        actions.append(inspectButton(item.id, "", "Explore fields"));
        const download = element("a", "Download JSON", "subtle-link");
        download.href = `/api/exports/${item.id}/download`;
        actions.append(download);
      }
      const first = Date.parse(`${item.dateStart}T00:00:00Z`);
      const last = Date.parse(`${item.dateEnd}T00:00:00Z`);
      const rangeDays = (last - first) / dayMs + 1;
      if ((item.source === "ios" || item.source === "android") &&
          Number.isInteger(rangeDays) && rangeDays >= 1 && rangeDays <= 31) {
        const button = element("button", "Plan declared range", "subtle");
        button.type = "button";
        button.setAttribute("aria-label", `Plan ${item.source === "ios" ? "Apple" : "Android"} days ${item.dateStart} through ${item.dateEnd}`);
        button.addEventListener("click", () => planFromRow({ dates: Array.from({ length: rangeDays },
          (_, i) => new Date(first + i * dayMs).toISOString().slice(0, 10)),
          source: item.source, entireDay: true }));
        actions.append(button);
      }
      row.append(actions); list.append(row);
    }
    if (offset === 0 && !page.exports.length) emptyTable(list, 7, "No matching retained envelopes. Try broadening your filters.");
    $("library-more").dataset.offset = page.nextOffset ?? "";
    $("library-more").hidden = page.nextOffset === null;
    $("library-status").textContent = page.exports.length ? `Showing ${list.querySelectorAll('tr').length} matching retained envelope(s). Results may change during uploads.` :
      offset === 0 ? "No matching retained envelopes. Try broadening your filters." : "No more matching envelopes.";
    note("");
  } catch (error) { if (seq === librarySequence && !disabled) {
    $("library-status").textContent = "Export library temporarily unavailable, not empty.";
    emptyTable($("library-list"), 7, "Retained export metadata could not be loaded.");
    $("library-more").hidden = true; note(error.message);
  } }
}
async function openNode(exportId, pointer, offset = 0) {
  if (disabled || !uuid.test(exportId)) return;
  const seq = ++nodeSequence;
  selectedExport = exportId; selectedPointer = pointer; selectedOffset = offset;
  HealthMdAccount.activate("fields", { history: true, focus: true });
  clearInspector();
  $("inspector-meta").textContent = "Reading requested field…";
  try {
    const result = await api("/api/explore/node", { exportId, pointer, offset });
    if (disabled || seq !== nodeSequence || selectedExport !== exportId || selectedPointer !== pointer || selectedOffset !== offset) return;
    $("inspector-meta").textContent = "Original retained JSON · text may contain sensitive health details. Previews may omit bytes.";
    $("inspector-path").textContent = pointer || "(envelope root)";
    $("inspector-root").hidden = pointer === "";
    $("inspector-up").hidden = pointer === "";
    const download = $("inspector-download");
    download.href = `/api/exports/${exportId}/download`;
    download.hidden = false;
    $("inspector-value").replaceChildren();
    const list = $("inspector-children");
    list.replaceChildren();
    if (result.type === "array" || result.type === "object") {
      $("inspector-value").textContent = `${result.type} · ${result.totalChildren} child(ren) · page of 20`;
      $("inspector-children").closest(".table-scroll").hidden = false;
      for (const item of result.items) {
        const row = element("tr");
        const description = item.preview !== undefined ? String(item.preview) : item.value !== undefined ?
          `${String(item.value)}${item.approximate ? " (decimal may be rounded)" : ""}` :
          item.exactValueUnavailable ? "Exact unsafe integer: download original" : item.type === "null" ? "null" :
            `${item.type} · ${item.length ?? 0} child(ren)`;
        row.append(element("td", item.key, "inspector-entry"), element("td", item.type), element("td", description, "inspector-entry"));
        const action = element("td", undefined, "row-actions");
        if (item.type === "array" || item.type === "object" || item.type === "string") action.append(inspectButton(exportId, item.pointer, "Open"));
        row.append(action); list.append(row);
      }
      if (!result.items.length) emptyTable(list, 4, "No child fields in this container.");
      $("inspector-more").dataset.offset = result.nextOffset ?? "";
      $("inspector-more").hidden = result.nextOffset === null;
      $("inspector-previous").hidden = offset === 0;
    } else {
      $("inspector-more").hidden = true;
      $("inspector-previous").hidden = true;
      $("inspector-value").textContent = result.exactValueUnavailable ?
        "Unsafe integer: download the original JSON for exact digits." :
        result.preview !== undefined ? `${result.preview}${result.truncated ? " (preview only)" : ""}` :
          result.type === "null" ? "null" : `${String(result.value)}${result.approximate ? " (decimal may be rounded; download original for exact digits)" : ""}`;
    }
    note("");
  } catch (error) { if (seq === nodeSequence && !disabled) {
    clearInspector(); $("inspector-meta").textContent = "Field temporarily unavailable. Browse the library to download the original export if it exists."; note(error.message);
  } }
}
async function init() {
  // An old HTML request can straddle a static rollout; reload before binding
  // new table markup or introducing a second global controller scope.
  if (typeof HealthMdAccount === "undefined" || !$("account-nav")) { location.reload(); return; }
  HealthMdAccount.init("explore");
  $("browse-library").addEventListener("click", () => HealthMdAccount.activate("library", { history: true, focus: true }));
  $("chart-form").addEventListener("submit", renderCharts);
  $("compare-enabled").addEventListener("change", () => {
    const enabled = $("compare-enabled").checked;
    $("compare-controls").hidden = !enabled;
    if (enabled && !$("compare-start").value) {
      const start = $("chart-start").value;
      const span = (Date.parse(`${$("chart-end").value}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / dayMs + 1;
      if (Number.isInteger(span) && span > 0 && span <= 31) {
        $("compare-end").value = shiftDay(start, -1);
        $("compare-start").value = shiftDay(start, -span);
      }
    }
  });
  $("library-form").addEventListener("submit", (event) => { event.preventDefault(); void showLibrary(); });
  $("library-more").addEventListener("click", () => {
    const offset = Number($("library-more").dataset.offset);
    if (Number.isSafeInteger(offset) && offset > 0) void showLibrary(offset);
  });
  $("inspector-root").addEventListener("click", () => { if (selectedExport) void openNode(selectedExport, ""); });
  $("inspector-up").addEventListener("click", () => {
    if (selectedExport && selectedPointer) void openNode(selectedExport,
      selectedPointer.slice(0, selectedPointer.lastIndexOf("/")));
  });
  $("inspector-more").addEventListener("click", () => {
    const offset = Number($("inspector-more").dataset.offset);
    if (selectedExport && Number.isSafeInteger(offset) && offset > 0) void openNode(selectedExport, selectedPointer, offset);
  });
  $("inspector-previous").addEventListener("click", () => {
    if (selectedExport && selectedOffset > 0) void openNode(selectedExport, selectedPointer,
      Math.max(0, selectedOffset - 20));
  });
  try {
    await api("/api/account"); // A session is required before loading any data.
    const [inventory, catalog, supplementGuard] = await Promise.all([api("/api/exports"), api("/api/explore/catalog"), HealthMdAccount.probe("supplements")]);
    if (disabled) return;
    supplementsAvailable = supplementGuard === 401;
    const end = inventory.days?.[0]?.date || new Date().toISOString().slice(0, 10);
    $("chart-end").value = end;
    $("chart-start").value = shiftDay(end, -29);
    for (const metric of catalog.metrics) {
      const label = element("label", undefined, "metric-choice");
      const input = element("input"); input.type = "checkbox"; input.value = metric.id;
      input.checked = ["steps", "sleep_total", "resting_heart_rate"].includes(metric.id);
      label.append(input, document.createTextNode(`${metric.label} · ${metric.unit}`));
      $("metric-options").append(label);
    }
    await Promise.all([renderCharts(), showLibrary()]);
  } catch (error) {
    if (disabled) return;
    if (error.message === "Sign in to continue.") location.replace("/login");
    else note(error.message);
  }
}
if (document.body.dataset.page === "explore") {
  document.addEventListener("healthmd:account-clear", clearExplorer);
  window.addEventListener("pagehide", clearExplorer);
  void init();
}
})();
