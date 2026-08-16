import type { Theme } from "@earendil-works/pi-coding-agent";
import { decodeKittyPrintable, matchesKey, truncateToWidth, visibleWidth, type KeyId } from "@earendil-works/pi-tui";
import { displayValue, numericValue } from "./exact.js";
import type { HealthStore, JsonValue } from "./model.js";

interface Obj { [key: string]: JsonValue }
const object = (value: JsonValue | undefined): value is Obj => value !== null && typeof value === "object" && !Array.isArray(value);
const text = (value: JsonValue | undefined): string | undefined => typeof value === "string" && value ? value : undefined;
const finiteValue = (value: JsonValue | undefined): number | undefined => value === undefined ? undefined : numericValue(value);
const numericCandidate = (value: JsonValue): boolean => typeof value === "number" || typeof value === "bigint" || object(value) && ["binary64", "signed_integer", "unsigned_integer"].includes(String(value.representation));

export interface DashboardPoint {
  date: string;
  value?: number;
  display: string;
  status: string;
  numericExpected: boolean;
  revision?: string;
}
export type DashboardDomain = "Activity" | "Sleep" | "Heart" | "Mobility" | "Recovery" | "Body" | "Other";
export interface DashboardMetric {
  key: string;
  id: string;
  name: string;
  domain: DashboardDomain;
  comparisonIdentity: string;
  unit?: string;
  source?: string;
  provider?: string;
  platform?: string;
  statistic?: string;
  contract?: string;
  origin?: string;
  operation?: string;
  points: DashboardPoint[];
  statuses: string[];
}
export interface DashboardTypedItem { type: string; label: string; date?: string; status?: string; detail: string }
export interface DashboardCoverage { statuses: string[]; daysConsidered: number; daysWithValues: number; missingIntervals: number; missingTruncated: boolean; requestedRange?: string; availableRange?: string }
export interface FullDashboardModel {
  metrics: DashboardMetric[];
  typedItems: DashboardTypedItem[];
  typedItemCount: number;
  coverage: DashboardCoverage;
  dates: string[];
  sources: string[];
  origins: string[];
  contracts: string[];
  documentCount: number;
  itemCount: number;
  availableCount: number;
  chartableCount: number;
  unavailableCount: number;
}
export type DashboardScreen = "overview" | "metric" | "records" | "coverage";
export type DashboardChartMode = "auto" | "line" | "bar";
export interface FullDashboardState {
  screen: DashboardScreen;
  selected: number;
  pointWindow: number;
  pointOffset: number;
  recordOffset: number;
  cursor?: number;
  availableOnly?: boolean;
  domain?: DashboardDomain | "All";
  fetchMenu?: boolean;
  fetching?: boolean;
  fetchStatus?: string;
  chartMode?: DashboardChartMode;
  help?: boolean;
  searchEditing?: boolean;
  searchQuery?: string;
}
export type DashboardFetchHandler = (days: 7 | 30 | 90, metricIds: string[], signal: AbortSignal) => Promise<void>;

const DASHBOARD_DOMAINS: DashboardDomain[] = ["Activity", "Sleep", "Heart", "Mobility", "Recovery", "Body", "Other"];
const DEFAULT_TREND_METRICS = ["steps", "distance_walking_running", "flights_climbed", "sleep_total", "sleep_deep", "sleep_core", "sleep_rem", "sleep_awake", "resting_heart_rate", "blood_oxygen", "vo2_max", "respiratory_rate", "walking_speed", "walking_step_length", "walking_asymmetry", "walking_double_support"];
function metricDomain(id: string): DashboardDomain {
  const value = id.toLowerCase();
  if (/sleep|bedtime|wake_time|awake/.test(value)) return "Sleep";
  if (/^walking_|gait|mobility|stair|speed|asymmetry|double_support/.test(value)) return "Mobility";
  if (/(?:^|_)steps?$|active_energy|exercise|stand_|flight|distance_walking|distance_cycl|move_|activity/.test(value)) return "Activity";
  if (/heart|pulse|blood_pressure|blood_oxygen|vo2|cardio/.test(value)) return "Heart";
  if (/respiratory|recovery|strain|stress|temperature|hrv/.test(value)) return "Recovery";
  if (/weight|height|body_|bmi|waist|lean_mass|fat_/.test(value)) return "Body";
  return "Other";
}

function queryValue(value: JsonValue | undefined): { numeric?: number; display: string; unit?: string; numericExpected: boolean } {
  if (!object(value)) return { display: value === undefined || value === null ? "—" : displayValue(value), numericExpected: false };
  const kind = text(value.type);
  if (kind === "quantity") {
    const numeric = finiteValue(value.value), unit = text(value.unit);
    return { ...(numeric === undefined ? {} : { numeric }), display: value.value === undefined ? "—" : displayValue(value.value), ...(unit ? { unit } : {}), numericExpected: true };
  }
  if (kind === "count") {
    const numeric = finiteValue(value.value);
    return { ...(numeric === undefined ? {} : { numeric }), display: value.value === undefined ? "—" : displayValue(value.value), unit: "count", numericExpected: true };
  }
  if (kind === "duration") {
    const numeric = finiteValue(value.seconds);
    return { ...(numeric === undefined ? {} : { numeric }), display: value.seconds === undefined ? "—" : displayValue(value.seconds), unit: "s", numericExpected: true };
  }
  if (kind === "category") return { display: text(value.display) ?? text(value.identifier) ?? "—", numericExpected: false };
  return { display: displayValue(value), numericExpected: false };
}

function metricIdentity(parts: Array<string | number | bigint | undefined>): string { return parts.map(part => part === undefined ? "" : String(part)).join("\0"); }
function addRangeDates(target: Set<string>, value: JsonValue | undefined): void {
  if (!object(value) || !text(value.start_date) || !text(value.end_date)) return;
  const start = Date.parse(`${text(value.start_date)}T00:00:00Z`), end = Date.parse(`${text(value.end_date)}T00:00:00Z`), day = 86_400_000;
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start || (end - start) / day > 36_600) return;
  for (let time = start; time <= end; time += day) target.add(new Date(time).toISOString().slice(0, 10));
}
function rangeText(value: JsonValue | undefined): string | undefined { return object(value) && text(value.start_date) && text(value.end_date) ? `${text(value.start_date)}..${text(value.end_date)}` : undefined; }
function typedItem(type: string, payload: Obj): DashboardTypedItem {
  if (type === "workout") { const start = text(payload.start); return { type, label: text(payload.activity) ?? "Workout", ...(start ? { date: start.slice(0, 10) } : {}), detail: `${start ?? "—"} → ${text(payload.end) ?? "—"}` }; }
  if (type === "sleep_session") { const date = text(payload.owner_date), status = text(payload.completeness); return { type, label: `${text(payload.classification) ?? "Sleep"} sleep`, ...(date ? { date } : {}), ...(status ? { status } : {}), detail: `${payload.asleep_duration_seconds === undefined ? "—" : displayValue(payload.asleep_duration_seconds)} s asleep` }; }
  if (type === "comparison") { const status = text(payload.direction); return { type, label: text(payload.metric_id) ?? "Period comparison", ...(status ? { status } : {}), detail: `${rangeText(payload.first_range) ?? "—"} vs ${rangeText(payload.second_range) ?? "—"}` }; }
  if (type === "workout_sleep_alignment") {
    const workout = object(payload.workout) ? payload.workout : undefined, start = workout ? text(workout.start) : undefined, status = text(payload.status);
    return { type, label: workout && text(workout.activity) ? text(workout.activity)! : "Workout/sleep alignment", ...(start ? { date: start.slice(0, 10) } : {}), ...(status ? { status } : {}), detail: `${payload.physiology_sample_count === undefined ? "—" : displayValue(payload.physiology_sample_count)} physiology samples` };
  }
  if (type === "evidence") return { type, label: Array.isArray(payload.metric_ids) ? payload.metric_ids.filter(value => typeof value === "string").join(", ") || "Evidence" : "Evidence", detail: text(payload.note) ?? "Context evidence" };
  return { type, label: type.replaceAll("_", " "), detail: "Canonical typed item" };
}

export function buildFullDashboardModel(store: HealthStore): FullDashboardModel {
  const metrics = new Map<string, DashboardMetric>(), typedItems: DashboardTypedItem[] = [];
  const revisions = new Map(store.documents.filter(document => document.origin !== "file").map(document => [document.id, document.id]));
  const dates = new Set<string>(), sources = new Set<string>(), origins = new Set<string>(), contracts = new Set<string>(), coverageStatuses = new Set<string>(), coverageSnapshots = new Set<string>(), coverageRequestedDates = new Set<string>(), coverageAvailableDates = new Set<string>(), missingIntervals = new Set<string>();
  const coverageFragments: Array<{ start: number; end: number; daysWithValues: number }> = [];
  let itemCount = 0, typedItemCount = 0, daysConsidered = 0, daysWithValues = 0, reportedMissingIntervals = 0, missingTruncated = false, requestedRange: string | undefined, availableRange: string | undefined;
  for (const document of store.documents) {
    origins.add(document.origin);
    contracts.add([document.schema, document.schemaVersion].filter(value => value !== undefined).map(String).join("@") || document.contractKind);
    const root = object(document.value) ? document.value : undefined;
    const pages: Obj[] = root?.schema === "healthmd.query_response" ? [root] : root?.schema === "healthmd.mcp_query_pages" && Array.isArray(root.pages) ? root.pages.filter(object) : [];
    if (root?.schema === "healthmd.mcp_query_pages" && object(root.receipt) && finiteValue(root.receipt.item_count) !== undefined) itemCount += finiteValue(root.receipt.item_count)! + (finiteValue(root.receipt.packet_fact_count) ?? 0);
    else itemCount += pages.reduce((total, page) => total + (Array.isArray(page.items) ? page.items.length : 0), 0);
    for (const page of pages) {
      if (Array.isArray(page.sources)) for (const value of page.sources) if (object(value) && text(value.source_id)) sources.add(text(value.source_id)!);
      if (object(page.coverage)) {
        const coverage = page.coverage, status = text(coverage.status), considered = finiteValue(coverage.days_considered), withValues = finiteValue(coverage.days_with_values), declaredMissing = finiteValue(coverage.missing_interval_count);
        if (declaredMissing !== undefined && declaredMissing >= 0) reportedMissingIntervals = Math.max(reportedMissingIntervals, Math.trunc(declaredMissing));
        if (status) coverageStatuses.add(status);
        const requested = rangeText(coverage.requested_range), available = rangeText(coverage.available_range), snapshot = `${status ?? ""}\0${considered ?? ""}\0${withValues ?? ""}\0${requested ?? ""}\0${available ?? ""}`;
        if (!coverageSnapshots.has(snapshot)) {
          coverageSnapshots.add(snapshot); daysConsidered += considered ?? 0; daysWithValues += withValues ?? 0;
          if (object(coverage.requested_range) && text(coverage.requested_range.start_date) && text(coverage.requested_range.end_date) && withValues !== undefined) {
            const start = Date.parse(`${text(coverage.requested_range.start_date)}T00:00:00Z`), end = Date.parse(`${text(coverage.requested_range.end_date)}T00:00:00Z`);
            if (Number.isFinite(start) && Number.isFinite(end) && end >= start) coverageFragments.push({ start, end, daysWithValues: withValues });
          }
        }
        requestedRange ??= requested;
        availableRange ??= available;
        addRangeDates(coverageRequestedDates, coverage.requested_range);
        addRangeDates(coverageAvailableDates, coverage.available_range);
        missingTruncated ||= coverage.missing_truncated === true;
        if (Array.isArray(coverage.missing)) for (const missing of coverage.missing) if (object(missing)) missingIntervals.add(`${rangeText(missing.range) ?? "unknown"}\0${text(missing.status) ?? "unknown"}\0${text(missing.reason) ?? ""}`);
      }
      if (object(page.packet) && Array.isArray(page.packet.facts)) for (const fact of page.packet.facts) if (object(fact)) {
        typedItemCount++;
        const decoded = queryValue(fact.value), date = text(fact.owner_date);
        if (date) dates.add(date);
        if (typedItems.length < 5_000) typedItems.push({ type: "packet_fact", label: text(fact.label) ?? text(fact.fact_id) ?? "Evidence fact", ...(date ? { date } : {}), detail: `${decoded.display}${decoded.unit ? ` ${decoded.unit}` : ""}` });
      }
      if (!Array.isArray(page.items)) continue;
      for (const itemValue of page.items) {
        if (!object(itemValue)) continue;
        const itemType = text(itemValue.type);
        if (!itemType) continue;
        if (itemType !== "metric") {
          const payload = itemValue[itemType];
          if (object(payload)) {
            const item = typedItem(itemType, payload);
            typedItemCount++;
            if (item.date) dates.add(item.date);
            if (typedItems.length < 5_000) typedItems.push(item);
          }
          continue;
        }
        if (!object(itemValue.metric)) continue;
        const metric = itemValue.metric, id = text(metric.metric_id);
        if (!id) continue;
        const name = text(metric.display_name) ?? id, date = text(metric.owner_date) ?? "undated", status = text(metric.status) ?? "unknown";
        const decoded = queryValue(metric.value), evidence = Array.isArray(metric.evidence) ? metric.evidence.filter(object) : [];
        const sourceIds = [...new Set(evidence.map(item => text(item.source_id)).filter((value): value is string => Boolean(value)))].sort();
        const providerIds = [...new Set(evidence.map(item => text(item.provider_id)).filter((value): value is string => Boolean(value)))].sort();
        const source = sourceIds.length ? sourceIds.join("+") : undefined, provider = providerIds.length ? providerIds.join("+") : undefined;
        for (const sourceId of sourceIds) sources.add(sourceId);
        if (date !== "undated") dates.add(date);
        const comparisonIdentity = metricIdentity([decoded.unit, source, provider, document.platform, undefined, document.schema, document.schemaVersion, document.origin, document.operation]);
        const key = metricIdentity([id, comparisonIdentity]);
        let series = metrics.get(key);
        if (!series) {
          const contract = [document.schema, document.schemaVersion].filter(value => value !== undefined).map(String).join("@") || document.contractKind;
          series = { key, id, name, domain: metricDomain(id), comparisonIdentity, ...(decoded.unit ? { unit: decoded.unit } : {}), ...(source ? { source } : {}), ...(provider ? { provider } : {}), ...(document.platform ? { platform: document.platform } : {}), contract, origin: document.origin, ...(document.operation ? { operation: document.operation } : {}), points: [], statuses: [] };
          metrics.set(key, series);
        }
        if (!series.statuses.includes(status)) series.statuses.push(status);
        const pointKey = `${date}\0${decoded.display}\0${status}`, revision = document.origin === "file" ? undefined : document.id;
        const superseded = revision !== undefined && series.points.some(point => point.date === date && point.revision !== undefined && point.revision !== revision);
        if (!superseded && !series.points.some(point => `${point.date}\0${point.display}\0${point.status}` === pointKey)) series.points.push({ date, ...(decoded.numeric === undefined ? {} : { value: decoded.numeric }), display: decoded.display, status, numericExpected: decoded.numericExpected, ...(revision ? { revision } : {}) });
      }
    }
  }

  // Generic/v9 fallback: retain exact semantic, unit, statistic, provider, platform, source, and contract identity.
  const names = new Map<string, string>();
  for (const entry of store.entries) if (entry.semanticId && entry.path.endsWith(".display_name") && typeof entry.value === "string") names.set(entry.semanticId, entry.value);
  for (const entry of store.entries) {
    if (entry.contractKind === "query_response" || entry.contractKind === "mcp_query_pages") continue;
    if (!entry.semanticId || /(?:^|\.|\[)(?:evidence|provenance|sources|coverage|limitations)(?:\.|\[|$)/.test(entry.path)) continue;
    if (!(entry.path.endsWith(".number") || /\.value\.(?:value|seconds)$/.test(entry.path)) || !numericCandidate(entry.value)) continue;
    const numeric = numericValue(entry.value);
    const comparisonIdentity = metricIdentity([entry.unit, entry.source, entry.provider, entry.platform, entry.statistic, entry.schema, entry.schemaVersion, entry.origin, entry.operation]);
    const key = metricIdentity([entry.semanticId, comparisonIdentity]);
    let series = metrics.get(key);
    if (!series) {
      const contract = [entry.schema, entry.schemaVersion].filter(value => value !== undefined).map(String).join("@") || entry.contractKind;
      series = { key, id: entry.semanticId, name: names.get(entry.semanticId) ?? entry.semanticId, domain: metricDomain(entry.semanticId), comparisonIdentity, ...(entry.unit ? { unit: entry.unit } : {}), ...(entry.source ? { source: entry.source } : {}), ...(entry.provider ? { provider: entry.provider } : {}), ...(entry.platform ? { platform: entry.platform } : {}), ...(entry.statistic ? { statistic: entry.statistic } : {}), contract, origin: entry.origin, ...(entry.operation ? { operation: entry.operation } : {}), points: [], statuses: ["available"] };
      metrics.set(key, series);
    }
    const date = entry.ownerDate ?? entry.date ?? "undated";
    if (date !== "undated") dates.add(date);
    const shown = displayValue(entry.value), pointKey = `${date}\0${shown}`, revision = revisions.get(entry.documentId);
    const superseded = revision !== undefined && series.points.some(point => point.date === date && point.revision !== undefined && point.revision !== revision);
    if (!superseded && !series.points.some(point => `${point.date}\0${point.display}` === pointKey)) series.points.push({ date, ...(numeric === undefined ? {} : { value: numeric }), display: shown, status: "available", numericExpected: true, ...(revision ? { revision } : {}) });
  }

  const sorted = [...metrics.values()], priority = ["steps", "active_energy", "sleep_total", "resting_heart_rate", "heart_rate", "walking_running_distance"];
  const priorityOf = (metric: DashboardMetric) => { const index = priority.indexOf(metric.id); return index < 0 ? priority.length : index; };
  for (const metric of sorted) metric.points.sort((a, b) => a.date.localeCompare(b.date));
  sorted.sort((a, b) => Number(metricHasAvailableEvidence(b)) - Number(metricHasAvailableEvidence(a)) || Number(b.points.some(point => point.value !== undefined)) - Number(a.points.some(point => point.value !== undefined)) || priorityOf(a) - priorityOf(b) || a.domain.localeCompare(b.domain) || a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
  const availableCount = sorted.filter(metricHasAvailableEvidence).length;
  const chartableCount = sorted.filter(metricTrendReady).length;
  if (coverageRequestedDates.size) {
    const requestedDates = [...coverageRequestedDates].sort(), availableDates = [...coverageAvailableDates].sort();
    daysConsidered = coverageRequestedDates.size;
    requestedRange = `${requestedDates[0]}..${requestedDates.at(-1)}`;
    if (availableDates.length) availableRange = `${availableDates[0]}..${availableDates.at(-1)}`;
    if (coverageFragments.length) {
      const fragments = [...coverageFragments].sort((left, right) => left.start - right.start || left.end - right.end), groups: Array<{ end: number; daysWithValues: number }> = [];
      for (const fragment of fragments) { const group = groups.at(-1); if (group && fragment.start <= group.end) { group.end = Math.max(group.end, fragment.end); group.daysWithValues = Math.max(group.daysWithValues, fragment.daysWithValues); } else groups.push({ end: fragment.end, daysWithValues: fragment.daysWithValues }); }
      daysWithValues = groups.reduce((sum, group) => sum + group.daysWithValues, 0);
    }
  }
  return {
    metrics: sorted,
    typedItems,
    typedItemCount,
    coverage: { statuses: [...coverageStatuses].sort(), daysConsidered, daysWithValues, missingIntervals: Math.max(missingIntervals.size, reportedMissingIntervals), missingTruncated, ...(requestedRange ? { requestedRange } : {}), ...(availableRange ? { availableRange } : {}) },
    dates: [...dates].sort(),
    sources: [...sources].sort(),
    origins: [...origins].sort(),
    contracts: [...contracts].sort(),
    documentCount: store.documents.length,
    itemCount: itemCount || sorted.length,
    availableCount,
    chartableCount,
    unavailableCount: Math.max(0, sorted.length - availableCount),
  };
}

type DashboardTheme = Pick<Theme, "fg" | "bg" | "bold">;
function statusTone(status: string | undefined): Parameters<DashboardTheme["fg"]>[0] {
  if (status === "available" || status === "complete") return "success";
  if (["failed", "unsupported", "cancelled", "redacted", "not_synchronized", "unavailable"].includes(status ?? "")) return "warning";
  return status ? "accent" : "text";
}
function printableInput(data: string): string | undefined {
  const kitty = decodeKittyPrintable(data);
  if (kitty) return kitty;
  const bracketedStart = "\x1b[200~", bracketedEnd = "\x1b[201~";
  if (data.startsWith(bracketedStart) && data.endsWith(bracketedEnd)) {
    const pasted = data.slice(bracketedStart.length, -bracketedEnd.length).replace(/[\r\n\t]+/gu, " ").replace(/[\0-\x1f\x7f]/gu, "");
    return pasted || undefined;
  }
  return data && !/[\0-\x1f\x7f]/u.test(data) ? data : undefined;
}
function fit(value: string, width: number): string { const shown = truncateToWidth(value, Math.max(0, width), "…"); return shown + " ".repeat(Math.max(0, width - visibleWidth(shown))); }
function frameLine(content: string, width: number, theme: DashboardTheme): string { return theme.fg("border", "│") + fit(content, Math.max(0, width - 2)) + theme.fg("border", "│"); }
function border(width: number, top: boolean, theme: DashboardTheme): string { return theme.fg("border", `${top ? "╭" : "╰"}${"─".repeat(Math.max(0, width - 2))}${top ? "╮" : "╯"}`); }
function metricHasAvailableEvidence(metric: DashboardMetric): boolean { return metric.statuses.some(status => status === "available" || status === "partial") && metric.points.some(point => point.status === "available" || point.status === "partial"); }
function hasUnsafeExact(metric: DashboardMetric): boolean { return metric.points.some(point => point.numericExpected && point.value === undefined); }
function latest(metric: DashboardMetric): DashboardPoint | undefined { return metric.points.at(-1); }
function compactNumber(value: number, maximumFractionDigits = 2): string {
  if (!Number.isFinite(value)) return displayValue(value);
  return new Intl.NumberFormat("en-US", { maximumFractionDigits, useGrouping: true }).format(value);
}
function chartDomain(values: number[], includeZero = false): { low: number; high: number } {
  let low = Math.min(...values), high = Math.max(...values);
  if (includeZero) { low = Math.min(0, low); high = Math.max(0, high); }
  if (low === high) {
    const padding = Math.max(Math.abs(low) * 0.05, 1), candidateLow = low - padding, candidateHigh = high + padding;
    if (Number.isFinite(candidateLow) && Number.isFinite(candidateHigh)) return { low: candidateLow, high: candidateHigh };
    return low > 0 ? { low: low * 0.9, high } : { low, high: high * 0.9 };
  }
  const span = high - low;
  if (Number.isFinite(span)) {
    const padding = span * 0.08, candidateLow = low - padding, candidateHigh = high + padding;
    if (Number.isFinite(candidateLow) && Number.isFinite(candidateHigh)) return { low: candidateLow, high: candidateHigh };
  }
  return { low, high };
}
function stableRatio(value: number, low: number, high: number): number {
  if (low === high) return 0.5;
  const span = high - low;
  let ratio: number;
  if (Number.isFinite(span) && span !== 0) ratio = (value - low) / span;
  else {
    const scale = Math.max(Math.abs(low), Math.abs(high), Math.abs(value));
    ratio = scale === 0 ? 0.5 : (value / scale - low / scale) / (high / scale - low / scale);
  }
  return Number.isFinite(ratio) ? Math.max(0, Math.min(1, ratio)) : 0.5;
}
function stableAverage(values: number[]): number {
  const scale = Math.max(...values.map(Math.abs));
  if (scale === 0) return 0;
  const normalized = values.reduce((sum, value) => sum + value / scale, 0) / values.length;
  return Math.max(-1, Math.min(1, normalized)) * scale;
}
function stableDifference(current: number, first: number): number | undefined { const difference = current - first; return Number.isFinite(difference) ? difference : undefined; }
function durationText(seconds: number, compact = false): string {
  const sign = seconds < 0 || Object.is(seconds, -0) ? "−" : "", total = Math.round(Math.abs(seconds));
  const hours = Math.floor(total / 3600), minutes = Math.floor(total % 3600 / 60), remaining = total % 60;
  if (compact) return hours ? `${sign}${hours}h${minutes ? `${minutes}m` : ""}` : minutes ? `${sign}${minutes}m${remaining ? `${remaining}s` : ""}` : `${sign}${remaining}s`;
  return `${sign}${hours ? `${hours}h ` : ""}${minutes || hours ? `${minutes}m ` : ""}${remaining}s`.trim();
}
function friendlyNumeric(metric: DashboardMetric, value: number, compact = false): string {
  const unit = metric.unit?.toLowerCase();
  if (unit === "s" || unit === "sec" || unit === "seconds") return durationText(value, compact);
  const number = compactNumber(value, compact ? 1 : 2);
  if (unit === "percent" || unit === "%") return `${number}%`;
  return `${number}${metric.unit ? ` ${metric.unit}` : ""}`;
}
function friendlyPoint(metric: DashboardMetric, point: DashboardPoint | undefined): string {
  if (!point) return "unavailable";
  return point.value === undefined ? `${point.display}${metric.unit ? ` ${metric.unit}` : ""}` : friendlyNumeric(metric, point.value);
}
function rawPoint(metric: DashboardMetric, point: DashboardPoint | undefined): string {
  return point ? `${point.display}${metric.unit ? ` ${metric.unit}` : ""}` : "unavailable";
}
function shownValue(metric: DashboardMetric): string { return friendlyPoint(metric, latest(metric)); }
function sparkline(metric: DashboardMetric, maximum = 10): string {
  if (hasUnsafeExact(metric)) return "⚠ unsafe exact";
  const points = numericPoints(metric).slice(-maximum);
  if (!points.length) return "";
  if (points.length === 1) return "1 observation";
  if (!metricTrendReady(metric)) return `${points.length} disconnected observations`;
  const values = points.map(point => point.value), minimum = Math.min(...values), maximumValue = Math.max(...values), blocks = "▁▂▃▄▅▆▇█", day = 86_400_000;
  return values.map((value, index) => {
    const block = blocks[Math.max(0, Math.min(blocks.length - 1, Math.round(stableRatio(value, minimum, maximumValue) * (blocks.length - 1))))];
    if (!index) return block;
    const gap = Date.parse(`${points[index]!.date}T00:00:00Z`) - Date.parse(`${points[index - 1]!.date}T00:00:00Z`);
    return gap > day * 1.5 ? `·${block}` : block;
  }).join("");
}
function visibleMetricIndexes(model: FullDashboardModel, state: FullDashboardState): number[] {
  const domain = state.domain ?? "All", availableOnly = state.availableOnly !== false, query = state.searchQuery?.trim().toLowerCase();
  return model.metrics.map((_metric, index) => index).filter(index => {
    const metric = model.metrics[index]!;
    const searchable = `${metric.name}\0${metric.id}\0${metric.domain}\0${metric.unit ?? ""}\0${metric.source ?? ""}\0${metric.provider ?? ""}`.toLowerCase();
    return (!availableOnly || metricHasAvailableEvidence(metric)) && (domain === "All" || metric.domain === domain) && (!query || searchable.includes(query));
  }).sort((left, right) => DASHBOARD_DOMAINS.indexOf(model.metrics[left]!.domain) - DASHBOARD_DOMAINS.indexOf(model.metrics[right]!.domain) || left - right);
}
function pointObserved(point: DashboardPoint): point is DashboardPoint & { value: number } { return point.value !== undefined && (point.status === "available" || point.status === "partial"); }
function numericPoints(metric: DashboardMetric): Array<DashboardPoint & { value: number }> { return metric.points.filter(pointObserved); }
function pointsTrendReady(points: Array<DashboardPoint & { value: number }>): boolean {
  const timestamps = points.map(point => Date.parse(`${point.date}T00:00:00Z`)), day = 86_400_000;
  if (timestamps.some(time => !Number.isFinite(time)) || timestamps.some((time, index) => index > 0 && time <= timestamps[index - 1]!)) return false;
  return timestamps.some((time, index) => index > 0 && time - timestamps[index - 1]! <= day * 1.5);
}
function metricTrendReady(metric: DashboardMetric): boolean { return !hasUnsafeExact(metric) && pointsTrendReady(numericPoints(metric)); }
function representativeMetric(model: FullDashboardModel, ids: string[], domain?: DashboardDomain): DashboardMetric | undefined {
  return model.metrics.find(metric => ids.includes(metric.id) && metricHasAvailableEvidence(metric)) ?? (domain ? model.metrics.find(metric => metric.domain === domain && metricHasAvailableEvidence(metric) && numericPoints(metric).length > 0) : undefined);
}
function periodComparison(metric: DashboardMetric): { label: string; coverage: string } | undefined {
  const points = numericPoints(metric), last = points.at(-1), day = 86_400_000;
  if (points.length < 2 || !last || new Set(points.map(point => point.date)).size !== points.length || !/^\d{4}-\d{2}-\d{2}$/.test(last.date)) return undefined;
  const end = Date.parse(`${last.date}T00:00:00Z`);
  if (!Number.isFinite(end)) return undefined;
  const current = points.filter(point => { const time = Date.parse(`${point.date}T00:00:00Z`); return time > end - 7 * day && time <= end; });
  const previous = points.filter(point => { const time = Date.parse(`${point.date}T00:00:00Z`); return time > end - 14 * day && time <= end - 7 * day; });
  const currentDays = new Set(current.map(point => point.date)).size, previousDays = new Set(previous.map(point => point.date)).size, coverage = `now ${currentDays}/7 · prior ${previousDays}/7`;
  if (currentDays < 4 || previousDays < 4 || Math.abs(currentDays - previousDays) > 2) return { label: "Insufficient coverage", coverage };
  const average = (values: Array<DashboardPoint & { value: number }>) => stableAverage(values.map(point => point.value));
  const before = average(previous), now = average(current), relative = before === 0 ? undefined : now / Math.abs(before) - before / Math.abs(before), change = relative === undefined || !Number.isFinite(relative * 100) ? undefined : relative * 100;
  if (change === undefined || !Number.isFinite(change)) return { label: "Prior average was zero", coverage };
  return { label: `${change > 0 ? "↑" : change < 0 ? "↓" : "→"} ${compactNumber(Math.abs(change), 1)}% vs prior 7d`, coverage };
}
function selectedPoints(metric: DashboardMetric | undefined, state: FullDashboardState): DashboardPoint[] {
  if (!metric) return [];
  const end = Math.max(0, metric.points.length - state.pointOffset);
  return metric.points.slice(Math.max(0, end - state.pointWindow), end);
}
function brailleBit(x: number, y: number): number {
  const bits = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]];
  return bits[y]?.[x] ?? 0;
}
function plot(metric: DashboardMetric | undefined, state: FullDashboardState, width: number, height: number, theme: DashboardTheme): string[] {
  const points = selectedPoints(metric, state), numeric = points.filter(pointObserved);
  if (!metric) return [theme.fg("dim", "No metric selected.")];
  if (hasUnsafeExact(metric)) return [theme.fg("warning", "Chart refused: series contains an unsafe exact numeric value.")];
  if (numericPoints(metric).some(point => !Number.isFinite(Date.parse(`${point.date}T00:00:00Z`)))) return [theme.fg("warning", "Trend unavailable: series contains an undated or invalid-date observation.")];
  if (numeric.length === 0) return [theme.fg("dim", "No numeric observations for this metric.")];
  if (numeric.length === 1) {
    const point = numeric[0]!, cardWidth = Math.max(18, Math.min(width, 58)), inside = cardWidth - 2;
    const cardLine = (content: string) => `${theme.fg("borderMuted", "│")}${fit(` ${content}`, inside)}${theme.fg("borderMuted", "│")}`;
    return [
      theme.fg("borderMuted", `╭${"─".repeat(inside)}╮`),
      cardLine(theme.bold(theme.fg("text", friendlyPoint(metric, point)))),
      cardLine(`${theme.fg("muted", point.date)}  ${theme.fg(statusTone(point.status), point.status)}`),
      cardLine(theme.fg("dim", "One observation is a snapshot, not a trend.")),
      cardLine(theme.fg("dim", "Load at least two dates to draw a meaningful chart.")),
      theme.fg("borderMuted", `╰${"─".repeat(inside)}╯`),
    ];
  }
  const labelWidth = Math.min(12, Math.max(7, Math.floor(width * 0.16))), plotWidth = Math.max(8, width - labelWidth - 2), chartHeight = Math.max(3, height - 1);
  const values = numeric.map(point => point.value), minimum = Math.min(...values), maximum = Math.max(...values), { low, high } = chartDomain(values);
  const pixelWidth = plotWidth * 2, pixelHeight = chartHeight * 4, pixels = Array.from({ length: pixelHeight }, () => new Uint8Array(pixelWidth));
  const timestamps = numeric.map(point => Date.parse(`${point.date}T00:00:00Z`)), dated = timestamps.every(Number.isFinite) && timestamps.every((time, index) => index === 0 || time > timestamps[index - 1]!);
  if (!dated) return [theme.fg("warning", "Trend unavailable: observations require distinct valid owner dates."), ...numeric.slice(-4).map(point => `${fit(point.date, 12)} ${friendlyPoint(metric, point)}`)];
  const coordinates = numeric.map((point, index) => ({ x: Math.round((dated ? (timestamps[index]! - timestamps[0]!) / (timestamps.at(-1)! - timestamps[0]!) : index / (numeric.length - 1)) * (pixelWidth - 1)), y: pixelHeight - 1 - Math.round(stableRatio(point.value, low, high) * (pixelHeight - 1)) }));
  for (const coordinate of coordinates) pixels[coordinate.y]![coordinate.x] = 1;
  for (let index = 1; index < coordinates.length; index++) {
    if (dated && timestamps[index]! - timestamps[index - 1]! > 86_400_000 * 1.5) continue;
    const start = coordinates[index - 1]!, end = coordinates[index]!, dx = Math.abs(end.x - start.x), dy = Math.abs(end.y - start.y), sx = start.x < end.x ? 1 : -1, sy = start.y < end.y ? 1 : -1;
    let x = start.x, y = start.y, error = dx - dy;
    for (;;) { pixels[y]![x] = 1; if (x === end.x && y === end.y) break; const twice = error * 2; if (twice > -dy) { error -= dy; x += sx; } if (twice < dx) { error += dx; y += sy; } }
  }
  const rows = Array.from({ length: chartHeight }, (_, row) => Array.from({ length: plotWidth }, (_, column) => {
    let code = 0;
    for (let py = 0; py < 4; py++) for (let px = 0; px < 2; px++) if (pixels[row * 4 + py]?.[column * 2 + px]) code |= brailleBit(px, py);
    return code ? String.fromCodePoint(0x2800 + code) : " ";
  }));
  const cursor = Math.max(0, Math.min(state.cursor ?? numeric.length - 1, numeric.length - 1)), cursorPoint = numeric[cursor]!, cursorCoordinate = coordinates[cursor]!;
  rows[Math.floor(cursorCoordinate.y / 4)]![Math.floor(cursorCoordinate.x / 2)] = "◆";
  const rendered = rows.map((row, index) => {
    const axis = index === 0 ? friendlyNumeric(metric, high, true) : index === chartHeight - 1 ? friendlyNumeric(metric, low, true) : "";
    return `${fit(theme.fg("dim", axis), labelWidth)} ${theme.fg("borderMuted", "│")}${theme.fg("accent", row.join(""))}`;
  });
  const firstDate = numeric[0]!.date, lastDate = numeric.at(-1)!.date, dateSpace = Math.max(1, plotWidth - firstDate.length - lastDate.length);
  rendered.push(`${" ".repeat(labelWidth + 2)}${theme.fg("dim", `${firstDate}${" ".repeat(dateSpace)}${lastDate}`)}`);
  rendered.push(`${theme.fg("muted", "Selected")} ${cursorPoint.date}  ${theme.bold(theme.fg("accent", friendlyPoint(metric, cursorPoint)))}  ${theme.fg(statusTone(cursorPoint.status), cursorPoint.status)}`);
  return rendered;
}
function barPlot(metric: DashboardMetric | undefined, state: FullDashboardState, width: number, height: number, theme: DashboardTheme): string[] {
  if (!metric) return [theme.fg("dim", "No metric selected.")];
  if (hasUnsafeExact(metric)) return [theme.fg("warning", "Chart refused: series contains an unsafe exact numeric value.")];
  const numeric = selectedPoints(metric, state).filter(pointObserved);
  if (!numeric.length) return [theme.fg("dim", "No numeric observations for this metric.")];
  if (numeric.length === 1) return plot(metric, state, width, height, theme);
  const shown = numeric.slice(-Math.max(2, height - 2)), labelWidth = width >= 32 ? 10 : 5, valueWidth = Math.max(6, Math.min(18, Math.floor(width * 0.25))), barWidth = Math.max(3, width - labelWidth - valueWidth - 4);
  const { low: minimum, high: maximum } = chartDomain(shown.map(point => point.value), true), zero = Math.round(stableRatio(0, minimum, maximum) * (barWidth - 1)), mixed = minimum < 0 && maximum > 0;
  const rows = shown.map(point => {
    const cells = Array.from({ length: barWidth }, () => " "), position = Math.round(stableRatio(point.value, minimum, maximum) * (barWidth - 1));
    if (mixed) cells[zero] = "│";
    const start = Math.min(zero, position), end = Math.max(zero, position);
    for (let index = start; index <= end; index++) cells[index] = "█";
    const label = labelWidth >= 10 ? point.date.slice(0, 10) : point.date.slice(-5);
    return `${fit(theme.fg("dim", label), labelWidth)} ${theme.fg("accent", cells.join(""))} ${fit(friendlyPoint(metric, point), valueWidth)}`;
  });
  return [theme.fg("dim", `Relative bars for ${shown.length} visible observations · exact values shown`), "", ...rows];
}
type ResolvedChartMode = "snapshot" | "line" | "bar";
function resolvedChartMode(metric: DashboardMetric | undefined, state: FullDashboardState): ResolvedChartMode {
  if (!metric) return "snapshot";
  const points = selectedPoints(metric, state).filter(pointObserved);
  if (points.length <= 1) return "snapshot";
  const requested = state.chartMode ?? "auto";
  if (requested !== "auto") return requested;
  const dates = points.map(point => point.date), validDiscreteDates = dates.every(date => /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(Date.parse(`${date}T00:00:00Z`))) && new Set(dates).size === dates.length;
  return validDiscreteDates && !pointsTrendReady(points) ? "bar" : "line";
}
function metricChart(metric: DashboardMetric | undefined, state: FullDashboardState, width: number, height: number, theme: DashboardTheme): string[] {
  return resolvedChartMode(metric, state) === "bar" ? barPlot(metric, state, width, height, theme) : plot(metric, state, width, height, theme);
}
function availabilityBar(model: FullDashboardModel, _width: number, theme: DashboardTheme): string {
  return `${theme.fg("success", `● ${model.availableCount} available`)}   ${theme.fg("accent", `◆ ${model.chartableCount} trend-ready`)}   ${theme.fg("dim", `○ ${model.unavailableCount} unavailable or empty`)}`;
}
function summaryCard(metric: DashboardMetric | undefined, domain: DashboardDomain, width: number, theme: DashboardTheme): string[] {
  const inside = Math.max(12, width - 2), title = truncateToWidth(`─ ${domain}${metric ? ` · ${metric.name}` : ""} `, inside, "…"), top = `╭${title}${"─".repeat(Math.max(0, inside - visibleWidth(title)))}╮`, bottom = `╰${"─".repeat(inside)}╯`;
  if (!metric) return [theme.fg("borderMuted", top), `${theme.fg("borderMuted", "│")}${fit(theme.fg("dim", " No available evidence"), inside)}${theme.fg("borderMuted", "│")}`, `${theme.fg("borderMuted", "│")}${" ".repeat(inside)}${theme.fg("borderMuted", "│")}`, theme.fg("borderMuted", bottom)];
  const comparison = periodComparison(metric), trend = hasUnsafeExact(metric) ? "⚠ exact" : sparkline(metric, 14), observationCount = numericPoints(metric).length, latestPoint = latest(metric);
  return [
    theme.fg("borderMuted", top),
    `${theme.fg("borderMuted", "│")}${fit(` ${theme.fg("text", shownValue(metric))}  ${latestPoint ? theme.fg(statusTone(latestPoint.status), latestPoint.status) : ""}  ${theme.fg("accent", trend)}`, inside)}${theme.fg("borderMuted", "│")}`,
    `${theme.fg("borderMuted", "│")}${fit(` ${theme.fg("dim", comparison ? `${comparison.label} • ${comparison.coverage}` : `${observationCount} observation${observationCount === 1 ? "" : "s"}`)}`, inside)}${theme.fg("borderMuted", "│")}`,
    theme.fg("borderMuted", bottom),
  ];
}
function joinedCards(left: string[], right: string[], width: number): string[] {
  const leftWidth = Math.floor((width - 2) / 2), rightWidth = width - leftWidth - 2;
  return Array.from({ length: Math.max(left.length, right.length) }, (_, index) => `${fit(left[index] ?? "", leftWidth)}  ${fit(right[index] ?? "", rightWidth)}`);
}
type PieSlice = { label: string; color: Parameters<DashboardTheme["fg"]>[0]; glyph: string; value: number };
function pieRows(stages: PieSlice[], width: number, theme: DashboardTheme): string[] {
  const total = stages.reduce((sum, stage) => sum + stage.value, 0), radiusX = Math.max(3, Math.min(10, Math.floor((width - 4) / 4))), radiusY = Math.max(2, Math.min(4, Math.floor(radiusX / 2)));
  const cumulative: number[] = []; let sum = 0;
  for (const stage of stages) { sum += stage.value / total; cumulative.push(sum); }
  return Array.from({ length: radiusY * 2 + 1 }, (_, row) => {
    const y = row - radiusY;
    return Array.from({ length: radiusX * 2 + 1 }, (_, column) => {
      const x = column - radiusX, normalizedX = x / radiusX, normalizedY = y / radiusY;
      if (normalizedX * normalizedX + normalizedY * normalizedY > 1) return "  ";
      const fraction = (Math.atan2(normalizedY, normalizedX) + Math.PI) / (Math.PI * 2), index = Math.max(0, cumulative.findIndex(value => fraction <= value)), stage = stages[index] ?? stages.at(-1)!;
      return theme.fg(stage.color, stage.glyph.repeat(2));
    }).join("");
  });
}
function sleepComposition(model: FullDashboardModel, width: number, theme: DashboardTheme, pie = false): string[] {
  const definitions: Array<[string, string, Parameters<DashboardTheme["fg"]>[0], string]> = [["sleep_deep", "Deep", "accent", "█"], ["sleep_core", "Core", "text", "▓"], ["sleep_rem", "REM", "muted", "▒"], ["sleep_awake", "Awake", "dim", "░"]];
  const first = definitions.map(([id]) => representativeMetric(model, [id])).find(Boolean);
  if (!first) return [];
  const date = latest(first)?.date;
  const stages = definitions.flatMap(([id, label, color, glyph]) => { const metric = model.metrics.find(candidate => candidate.id === id && candidate.comparisonIdentity === first.comparisonIdentity); const point = metric?.points.find(candidate => candidate.date === date && pointObserved(candidate)); return metric && point?.value !== undefined ? [{ label, color, glyph, value: point.value }] : []; });
  if (stages.some(stage => stage.value < 0)) return [];
  const asleepStages = stages.filter(stage => stage.label !== "Awake"), asleepTotal = asleepStages.reduce((sum, stage) => sum + stage.value, 0);
  const totalMetric = model.metrics.find(metric => metric.id === "sleep_total" && metric.comparisonIdentity === first.comparisonIdentity), totalPoint = totalMetric?.points.find(point => point.date === date && pointObserved(point)), expectedAsleep = totalPoint?.value;
  if (!date || !totalMetric || asleepStages.length !== 3 || !Number.isFinite(asleepTotal) || asleepTotal <= 0 || expectedAsleep === undefined || expectedAsleep <= 0 || asleepTotal / expectedAsleep < 0.95 || asleepTotal / expectedAsleep > 1.05) return [];
  const total = stages.reduce((sum, stage) => sum + stage.value, 0);
  if (!Number.isFinite(total) || total <= 0) return [];
  const barWidth = Math.max(12, Math.min(48, width - 20));
  const sizes = stages.map(stage => stage.value > 0 ? Math.floor(stage.value / total * barWidth) : 0), order = stages.map((stage, index) => ({ index, remainder: stage.value > 0 ? stage.value / total * barWidth - sizes[index]! : -1 })).sort((left, right) => right.remainder - left.remainder);
  let remaining = barWidth - sizes.reduce((sum, size) => sum + size, 0);
  for (let index = 0; remaining > 0 && order.length; index++, remaining--) sizes[order[index % order.length]!.index]!++;
  const bar = stages.map((stage, index) => theme.fg(stage.color, stage.glyph.repeat(sizes[index]!))).join("");
  const legend = stages.map(stage => `${stage.glyph} ${stage.label} ${compactNumber(stage.value / total * 100, 0)}%`).join(" • "), title = theme.bold(theme.fg("accent", `Sleep composition · ${date}`)), totalText = friendlyNumeric(totalMetric, total, true);
  return pie ? [title, ...pieRows(stages.filter(stage => stage.value > 0), width, theme), `${theme.fg("muted", "Total")} ${totalText}`, theme.fg("dim", legend)] : [title, `${bar}  ${totalText}`, theme.fg("dim", legend)];
}
function activitySnapshot(model: FullDashboardModel, theme: DashboardTheme): string[] {
  const metrics = ([['steps', 'Steps'], ['distance_walking_running', 'Distance'], ['flights_climbed', 'Flights']] as Array<[string, string]>).map(([id, label]) => ({ label, metric: representativeMetric(model, [id]) })).filter((value): value is { label: string; metric: DashboardMetric } => Boolean(value.metric));
  return metrics.length ? [
    theme.bold(theme.fg("accent", "Latest activity observations · independent identities")),
    ...metrics.map(({ label, metric }) => { const point = latest(metric), identity = metric.provider ?? metric.source ?? metric.platform ?? "source retained"; return `${theme.fg("muted", label)}  ${theme.fg("text", friendlyPoint(metric, point))}  ${point ? theme.fg(statusTone(point.status), point.status) : ""}  ${theme.fg("dim", `${point?.date ?? "undated"} • ${identity}`)}`; }),
  ] : [];
}
function historyGuidance(model: FullDashboardModel): string | undefined {
  if (!model.documentCount || model.chartableCount > 0) return undefined;
  if (model.dates.length < 4) return `${model.dates.length || "No"} dated day${model.dates.length === 1 ? "" : "s"} loaded. Press F, then 2, for the recommended 30-day range.`;
  return "No continuous identity-safe trends yet; discrete observations use bars automatically.";
}
function overviewLines(model: FullDashboardModel, metric: DashboardMetric | undefined, state: FullDashboardState, width: number, height: number, theme: DashboardTheme): string[] {
  const dates = model.dates.length ? `${model.dates[0]} → ${model.dates.at(-1)}` : "No dated evidence";
  const representatives: Array<[DashboardDomain, DashboardMetric | undefined]> = [
    ["Activity", representativeMetric(model, ["steps", "active_energy", "distance_walking_running"], "Activity")],
    ["Sleep", representativeMetric(model, ["sleep_total", "sleep_duration"], "Sleep")],
    ["Heart", representativeMetric(model, ["resting_heart_rate", "heart_rate", "blood_oxygen"], "Heart")],
    ["Mobility", representativeMetric(model, ["walking_speed", "walking_step_length"], "Mobility")],
    ["Recovery", representativeMetric(model, ["respiratory_rate", "hrv_rmssd", "hrv_sdnn"], "Recovery")],
    ["Body", representativeMetric(model, ["body_mass", "weight", "bmi"], "Body")],
  ];
  const domain = state.domain ?? "All", filteredRepresentatives = domain === "All" ? representatives : representatives.filter(([candidate]) => candidate === domain);
  let available = filteredRepresentatives.filter((value): value is [DashboardDomain, DashboardMetric] => Boolean(value[1]));
  if (!available.length && state.availableOnly === false && domain !== "All" && metric?.domain === domain) available = [[domain, metric]];
  const unsafeCount = model.metrics.filter(hasUnsafeExact).length, guidance = height >= 16 ? historyGuidance(model) : undefined;
  const twoColumns = width >= 100, reservedLines = guidance ? 10 : 9, maximumCards = twoColumns ? Math.max(2, Math.floor((height - reservedLines) / 4) * 2) : Math.max(1, Math.floor((height - reservedLines) / 4));
  const shown = available.slice(0, maximumCards), cardWidth = twoColumns ? Math.floor((width - 2) / 2) : width, cards = shown.map(([domain, metric]) => summaryCard(metric, domain, cardWidth, theme));
  const cardLines = twoColumns ? Array.from({ length: Math.ceil(cards.length / 2) }, (_, row) => joinedCards(cards[row * 2]!, cards[row * 2 + 1] ?? [], width)).flat() : cards.flat();
  const pieFits = domain === "Sleep" && height >= 17 + cardLines.length + (unsafeCount ? 1 : 0) + (guidance ? 1 : 0);
  const composition = domain === "All" || domain === "Sleep" ? sleepComposition(model, width, theme, pieFits) : [], activity = domain === "All" || domain === "Activity" ? activitySnapshot(model, theme) : [];
  return [
    `${theme.bold(theme.fg("accent", "Summary"))}  ${theme.fg("muted", `${dates} • navigation ${state.availableOnly === false ? "all" : "available"} / ${domain}`)}`,
    availabilityBar(model, width, theme),
    ...(guidance ? [theme.fg("accent", `Trend setup · ${guidance}`)] : []),
    metric ? `${theme.fg("muted", `Selected · ${metric.domain}`)}  ${theme.bold(metric.name)}  ${theme.fg("text", shownValue(metric))}  ${latest(metric) ? theme.fg(statusTone(latest(metric)!.status), latest(metric)!.status) : ""}  ${theme.fg("dim", "D/Enter details")}` : theme.fg("dim", "No metric selected · F fetches dashboard data"),
    ...(unsafeCount ? [theme.fg("warning", `⚠ unsafe exact: ${unsafeCount} series retained but not charted`)] : []),
    "",
    ...(cardLines.length ? cardLines : [theme.fg("dim", "No available summary metrics. Press F to fetch trend data.")]),
    "",
    ...composition,
    ...(composition.length ? [""] : []),
    ...activity,
  ];
}
function metricLines(metric: DashboardMetric | undefined, state: FullDashboardState, width: number, height: number, theme: DashboardTheme): string[] {
  if (!metric) return [theme.fg("warning", "No metrics are available in the loaded evidence.")];
  const points = selectedPoints(metric, state), numeric = points.filter(pointObserved), values = numeric.map(point => point.value), current = numeric.at(-1), latestPoint = latest(metric), requestedChart = state.chartMode ?? "auto", activeChart = resolvedChartMode(metric, state);
  const identity = [metric.contract, metric.origin, metric.operation, metric.unit, metric.statistic, metric.source, metric.provider, metric.platform].filter(Boolean).join(" • "), chartLabel = requestedChart === "auto" ? `AUTO→${activeChart.toUpperCase()}` : activeChart === "snapshot" ? `${requestedChart.toUpperCase()}→SNAPSHOT` : activeChart.toUpperCase();
  let summary: string[];
  if (hasUnsafeExact(metric)) summary = [
    `${theme.fg("muted", "Latest")} ${theme.bold(theme.fg("warning", friendlyPoint(metric, latestPoint)))}`,
    theme.fg("warning", "Exact source value is outside the safe chart range."),
  ];
  else if (!values.length) summary = [
    `${theme.fg("muted", "Latest")} ${theme.bold(theme.fg("text", friendlyPoint(metric, latestPoint)))}  ${latestPoint ? theme.fg(statusTone(latestPoint.status), latestPoint.status) : ""}`,
    theme.fg("warning", "No available or partial numeric observations."),
  ];
  else if (values.length === 1) {
    const latestIsObserved = latestPoint === current && latestPoint !== undefined && pointObserved(latestPoint);
    summary = latestIsObserved ? [
      `${theme.fg("muted", "Snapshot")} ${theme.bold(theme.fg("text", friendlyPoint(metric, current)))}  ${theme.fg("dim", `on ${current!.date}`)}  ${theme.fg(statusTone(current!.status), current!.status)}`,
      ...(friendlyPoint(metric, current) !== rawPoint(metric, current) ? [theme.fg("dim", `Source value ${rawPoint(metric, current)}`)] : []),
    ] : [
      `${theme.fg("muted", "Latest")} ${theme.bold(theme.fg("text", friendlyPoint(metric, latestPoint)))}  ${latestPoint ? theme.fg(statusTone(latestPoint.status), latestPoint.status) : ""}`,
      `${theme.fg("muted", "Most recent observed")} ${friendlyPoint(metric, current)}  ${current!.date}`,
    ];
  } else {
    const first = numeric[0]!, change = stableDifference(current!.value, first.value), average = stableAverage(values), changeText = change === undefined ? "outside finite display range" : `${change > 0 ? "+" : ""}${friendlyNumeric(metric, change)}`;
    summary = [
      `${theme.fg("muted", "Latest")} ${theme.bold(theme.fg("text", friendlyPoint(metric, latestPoint)))}  ${latestPoint ? theme.fg(statusTone(latestPoint.status), latestPoint.status) : ""}   ${theme.fg("muted", "Observed average")} ${friendlyNumeric(metric, average)}   ${theme.fg("muted", "Observations")} ${numeric.length}`,
      `${theme.fg("muted", "Observed change")} ${theme.fg("accent", changeText)}   ${theme.fg("muted", "Observed range")} ${friendlyNumeric(metric, Math.min(...values))} – ${friendlyNumeric(metric, Math.max(...values))}`,
    ];
  }
  const lines = [
    `${theme.bold(theme.fg("accent", metric.name))} ${theme.fg("muted", metric.id)}`,
    theme.fg("dim", `${identity || "source identity retained from loaded contract"} • ${chartLabel} • window ${state.pointWindow >= 3650 ? "all" : `last ${state.pointWindow} observations`}`),
    ...summary,
    "",
    ...metricChart(metric, state, width, Math.max(3, Math.min(10, height - 12)), theme),
    "",
    theme.fg("muted", values.length === 1 ? "Observation" : "Recent observations"),
    ...points.slice(-3).map(point => `${fit(point.date, 12)} ${fit(friendlyPoint(metric, point), 22)} ${theme.fg(statusTone(point.status), point.status)}`),
  ];
  return lines;
}
function recordLines(model: FullDashboardModel, state: FullDashboardState, height: number, theme: DashboardTheme): string[] {
  const capacity = Math.max(1, height - 4), maximum = Math.max(0, model.typedItems.length - capacity), offset = Math.max(0, Math.min(state.recordOffset, maximum));
  return [
    theme.bold(theme.fg("accent", `Typed records (${model.typedItemCount})`)),
    theme.fg("dim", "Workouts, sleep sessions, comparisons, alignments, context evidence, and packet facts"),
    "",
    ...(model.typedItems.length ? model.typedItems.slice(offset, offset + capacity).map((item, index) => `${index === 0 ? theme.fg("accent", "▶") : " "} ${fit(item.date ?? "—", 12)} ${fit(item.type, 24)} ${fit(item.label, 28)} ${theme.fg(item.status ? statusTone(item.status) : "text", item.status ?? item.detail)}`) : [theme.fg("dim", "No non-metric typed records in this response.")]),
  ];
}
function coverageLines(model: FullDashboardModel, width: number, theme: DashboardTheme): string[] {
  return [
    theme.bold(theme.fg("accent", "Coverage & provenance")),
    `${theme.fg("muted", "Documents")}  ${model.documentCount}   ${theme.fg("muted", "Items")} ${model.itemCount}`,
    `${theme.fg("muted", "Dates")}      ${model.dates[0] ?? "—"} → ${model.dates.at(-1) ?? "—"}`,
    `${theme.fg("muted", "Coverage")}   ${model.coverage.statuses.join(", ") || "unspecified"} • ${model.coverage.daysWithValues}/${model.coverage.daysConsidered} days with values`,
    `${theme.fg("muted", "Ranges")}     requested ${model.coverage.requestedRange ?? "—"} • available ${model.coverage.availableRange ?? "—"}`,
    `${theme.fg("muted", "Missing")}    ${model.coverage.missingIntervals}${model.coverage.missingTruncated ? " total • details truncated" : " intervals"}`,
    `${theme.fg("muted", "Sources")}    ${model.sources.join(", ") || "unspecified"}`,
    `${theme.fg("muted", "Origins")}    ${model.origins.join(", ") || "unknown"}`,
    `${theme.fg("muted", "Contracts")}  ${model.contracts.join(", ") || "unknown"}`,
    "",
    availabilityBar(model, width, theme),
    theme.fg("muted", `${model.chartableCount} identity-safe series have connected dated observations.`),
    "",
    theme.fg("dim", "Availability is contract evidence, not a health interpretation."),
  ];
}
function welcomeLines(theme: DashboardTheme): string[] {
  return [
    theme.bold(theme.fg("accent", "Welcome to Health.md")),
    theme.fg("muted", "A private, read-only view of health evidence you explicitly load or fetch."),
    "",
    theme.bold("Start with history"),
    `${theme.fg("accent", "F")}  Choose a bounded 7, 30, or 90-day fetch`,
    `${theme.fg("accent", "Enter")}  Open the fetch choices`,
    "",
    theme.fg("muted", "30 days is recommended: it gives charts enough history without requesting an open-ended range."),
    theme.fg("dim", "Keep Health.md foregrounded with Direct CLI Access enabled while fetching."),
    "",
    theme.bold("Already have an export?"),
    theme.fg("muted", "Close this view and run /healthmd load <file-or-directory>."),
    "",
    theme.fg("dim", "Evidence stays identity-separated by metric, unit, source, provider, platform, schema, and origin."),
  ];
}
function helpLines(theme: DashboardTheme): string[] {
  return [
    theme.bold(theme.fg("accent", "Dashboard help")),
    theme.fg("muted", "The dashboard chooses snapshots, bars, or connected lines from the evidence shape."),
    "",
    `${theme.bold("1–8")}  All · Activity · Sleep · Heart · Mobility · Recovery · Body · Other`,
    `${theme.bold("/")}    Search metric name, semantic ID, unit, source, or provider`,
    `${theme.bold("↑↓")}   Select metric             ${theme.bold("Enter / D")}  Open metric detail`,
    `${theme.bold("←→")}   Inspect observations      ${theme.bold("V")}          Auto / bar / line`,
    `${theme.bold("W")}    7 / 30 / 90 / all window  ${theme.bold("[ ]")}        Pan history`,
    `${theme.bold("F")}    Fetch bounded history     ${theme.bold("A")}          Available / all`,
    `${theme.bold("O/T/C")} Overview / records / coverage`,
    "",
    theme.fg("dim", "One observation remains a snapshot. Missing dates are never connected."),
    theme.fg("dim", "Comparisons require adequate coverage and are descriptive, not medical guidance."),
    "",
    theme.fg("dim", "Press ? or Esc to return"),
  ];
}
function searchLines(model: FullDashboardModel, state: FullDashboardState, theme: DashboardTheme): string[] {
  const matches = visibleMetricIndexes(model, state).map(index => model.metrics[index]!), query = state.searchQuery ?? "";
  return [
    theme.bold(theme.fg("accent", "Search metrics")),
    `${theme.fg("muted", ">")} ${query}${theme.fg("accent", "▌")}`,
    theme.fg("dim", "Name, semantic ID, domain, unit, source, and provider are searchable."),
    "",
    theme.fg("muted", `${matches.length} matching metric${matches.length === 1 ? "" : "s"}`),
    ...matches.slice(0, 8).map((metric, index) => `${index === 0 ? theme.fg("accent", "▶") : " "} ${theme.bold(metric.name)}  ${theme.fg("dim", `${metric.id} · ${metric.domain}${metric.unit ? ` · ${metric.unit}` : ""}`)}`),
    ...(!matches.length ? [theme.fg("warning", "No metrics match. Backspace to broaden the search.")] : []),
    "",
    theme.fg("dim", "Enter applies • Backspace edits • Ctrl+U clears • Esc keeps the current filter"),
  ];
}
function sidebarLines(model: FullDashboardModel, state: FullDashboardState, height: number, width: number, theme: DashboardTheme): string[] {
  const indexes = visibleMetricIndexes(model, state), domain = state.domain ?? "All", mode = state.availableOnly === false ? "all" : "available";
  const rows: Array<{ index?: number; text: string }> = [];
  let previousDomain: DashboardDomain | undefined;
  for (const index of indexes) {
    const metric = model.metrics[index]!;
    if (domain === "All" && metric.domain !== previousDomain) { rows.push({ text: theme.bold(theme.fg("muted", metric.domain.toUpperCase())) }); previousDomain = metric.domain; }
    const selected = index === state.selected, marker = selected ? "▶" : " ", status = metricHasAvailableEvidence(metric) ? theme.fg("success", "●") : theme.fg("dim", "○"), label = `${marker} ${status} ${metric.name}`;
    rows.push({ index, text: selected ? theme.bg("selectedBg", fit(theme.fg("accent", label), width)) : fit(label, width) });
  }
  const capacity = Math.max(1, height - 2), selectedRow = Math.max(0, rows.findIndex(row => row.index === state.selected)), start = Math.max(0, Math.min(selectedRow - Math.floor(capacity / 2), Math.max(0, rows.length - capacity)));
  const query = state.searchQuery?.trim(), lines = [theme.bold(theme.fg("accent", `${domain} · ${mode} (${indexes.length})`)), theme.fg("dim", query ? `/ “${query}” · Ctrl+U clear` : "1–8 domains · / search")];
  lines.push(...rows.slice(start, start + capacity).map(row => row.text));
  if (!indexes.length) lines.push(theme.fg("dim", "No matching metrics"));
  while (lines.length < height) lines.push(" ".repeat(width));
  return lines.slice(0, height).map(line => fit(line, width));
}

function fetchLines(model: FullDashboardModel, state: FullDashboardState, theme: DashboardTheme): string[] {
  const discovered = [...new Set(model.metrics.filter(metric => metricHasAvailableEvidence(metric) && metric.points.some(point => point.numericExpected)).map(metric => metric.id))], ids = discovered.length ? discovered : DEFAULT_TREND_METRICS;
  if (state.fetching) return [theme.bold(theme.fg("accent", "Fetching Health.md trend data…")), "", theme.fg("muted", state.fetchStatus ?? "Contacting the configured read-only source."), "", theme.fg("dim", "Keep Health.md foregrounded with Direct CLI Access enabled."), theme.fg("dim", "The validated response will be added to the configured persistent cache.")];
  return [
    theme.bold(theme.fg("accent", "Fetch trend data")),
    ...(state.fetchStatus ? [theme.fg(state.fetchStatus.startsWith("Fetch failed") ? "warning" : "muted", state.fetchStatus)] : []),
    theme.fg("muted", `${ids.length || "All"} queryable metric${ids.length === 1 ? "" : "s"} • configured read-only source`),
    "",
    `${theme.bold("1")}  Last 7 days     Quick recent trend`,
    `${theme.bold("2")}  Last 30 days    Recommended dashboard range`,
    `${theme.bold("3")}  Last 90 days    Longer personal baseline`,
    "",
    theme.fg("dim", "Dates are inclusive. Existing cached evidence is retained."),
    theme.fg("dim", "Keep Health.md foregrounded with Direct CLI Access enabled."),
    "",
    theme.fg("dim", "Esc cancels"),
  ];
}

export function renderFullDashboard(model: FullDashboardModel, state: FullDashboardState, width: number, theme: DashboardTheme, height = 30): string[] {
  const w = Math.max(1, width), totalHeight = Math.max(1, height);
  if (w < 20 || totalHeight < 11) return ["Health.md dashboard", `${model.availableCount}/${model.metrics.length} available`, "Resize terminal", "Esc close"].slice(0, totalHeight).map(line => truncateToWidth(line, w, ""));
  const inner = w - 2, visibleIndexes = visibleMetricIndexes(model, state), selectedIndex = visibleIndexes.includes(state.selected) ? state.selected : visibleIndexes[0] ?? -1, metric = selectedIndex >= 0 ? model.metrics[selectedIndex] : undefined, bodyHeight = Math.max(3, totalHeight - 8);
  const tabs = (["overview", "metric", "records", "coverage"] as const).map(screen => screen === state.screen ? theme.bg("selectedBg", theme.fg("accent", ` ${screen.toUpperCase()} `)) : theme.fg("dim", ` ${screen.toUpperCase()} `)).join(" ");
  const header = [
    border(w, true, theme),
    frameLine(` ${theme.bold(theme.fg("accent", "Health.md"))}  ${theme.fg("muted", "interactive health evidence dashboard")}`, w, theme),
    frameLine(` ${tabs}`, w, theme),
    frameLine(` ${theme.fg(state.fetchStatus && !state.fetching ? (state.fetchStatus.startsWith("Fetch failed") ? "warning" : "success") : "dim", state.fetchStatus ?? `${model.documentCount} document${model.documentCount === 1 ? "" : "s"} • ${model.itemCount} items • ${model.dates[0] ?? "—"}..${model.dates.at(-1) ?? "—"}${state.searchQuery ? ` • search “${state.searchQuery}”` : ""}`)}`, w, theme),
    frameLine(theme.fg("borderMuted", ` ${"─".repeat(Math.max(0, inner - 2))}`), w, theme),
  ];
  const useSidebar = inner >= 92 && model.metrics.length > 0, sidebarWidth = useSidebar ? Math.min(34, Math.floor(inner * 0.3)) : 0, mainWidth = useSidebar ? inner - sidebarWidth - 4 : inner - 2;
  const mainRaw = state.help ? helpLines(theme) : state.searchEditing ? searchLines(model, state, theme) : state.fetchMenu || state.fetching ? fetchLines(model, state, theme) : !model.documentCount ? welcomeLines(theme) : state.screen === "overview" ? overviewLines(model, metric, state, mainWidth, bodyHeight, theme) : state.screen === "metric" ? metricLines(metric, state, mainWidth, bodyHeight, theme) : state.screen === "records" ? recordLines(model, state, bodyHeight, theme) : coverageLines(model, mainWidth, theme);
  const main = Array.from({ length: bodyHeight }, (_, index) => fit(mainRaw[index] ?? "", mainWidth));
  let body: string[];
  if (useSidebar) {
    const side = sidebarLines(model, state, bodyHeight, sidebarWidth, theme);
    body = main.map((line, index) => frameLine(` ${side[index]} ${theme.fg("borderMuted", "│")} ${line}`, w, theme));
  } else body = main.map(line => frameLine(` ${line}`, w, theme));
  const footerHint = state.help ? "? / Esc return" : state.searchEditing ? "Type to search • Enter apply • Ctrl+U clear • Esc return" : state.fetchMenu || state.fetching ? "1 7d • 2 30d recommended • 3 90d • Esc cancel" : "1–8 domains • / search • ? help • ↑↓ select • Enter detail • F fetch • Esc close";
  const footer = [
    frameLine(theme.fg("borderMuted", ` ${"─".repeat(Math.max(0, inner - 2))}`), w, theme),
    frameLine(` ${theme.fg("dim", footerHint)}`, w, theme),
    border(w, false, theme),
  ];
  return [...header, ...body, ...footer].map(line => truncateToWidth(line, w, ""));
}

export class FullDashboardComponent {
  private model: FullDashboardModel;
  private disposed = false;
  private fetchController: AbortController | undefined;
  private state: FullDashboardState = { screen: "overview", selected: 0, pointWindow: 30, pointOffset: 0, recordOffset: 0, availableOnly: true, domain: "All", chartMode: "auto" };
  constructor(private readonly tui: { requestRender(): void }, private readonly theme: DashboardTheme, private readonly getStore: () => HealthStore | undefined, private readonly onClose: () => void, private readonly getHeight: () => number = () => 30, private readonly onFetch?: DashboardFetchHandler) {
    this.model = this.readModel();
  }
  private readModel(): FullDashboardModel {
    const store = this.getStore();
    return store ? buildFullDashboardModel(store) : { metrics: [], typedItems: [], typedItemCount: 0, coverage: { statuses: [], daysConsidered: 0, daysWithValues: 0, missingIntervals: 0, missingTruncated: false }, dates: [], sources: [], origins: [], contracts: [], documentCount: 0, itemCount: 0, availableCount: 0, chartableCount: 0, unavailableCount: 0 };
  }
  private renderSoon(): void { if (!this.disposed) this.tui.requestRender(); }
  private selectVisible(position: number): void {
    const indexes = visibleMetricIndexes(this.model, this.state);
    if (indexes.length) this.state.selected = indexes[Math.max(0, Math.min(position, indexes.length - 1))]!;
    delete this.state.cursor; this.state.pointOffset = 0;
  }
  private moveMetric(delta: number): void {
    const indexes = visibleMetricIndexes(this.model, this.state), current = Math.max(0, indexes.indexOf(this.state.selected));
    this.selectVisible(current + delta);
  }
  private selectDomain(domain: DashboardDomain | "All"): void {
    this.state.domain = domain; this.state.screen = "overview"; delete this.state.searchQuery; this.normalizeSelection();
  }
  private normalizeSelection(): void {
    const indexes = visibleMetricIndexes(this.model, this.state);
    if (indexes.length && !indexes.includes(this.state.selected)) this.state.selected = indexes[0]!;
    else if (!indexes.length) this.state.selected = 0;
    delete this.state.cursor; this.state.pointOffset = 0;
  }
  private async startFetch(days: 7 | 30 | 90): Promise<void> {
    if (!this.onFetch || this.state.fetching) { this.state.fetchMenu = false; this.state.fetchStatus = "Fetch unavailable: no dashboard source configured"; this.renderSoon(); return; }
    const discovered = [...new Set(this.model.metrics.filter(metric => metricHasAvailableEvidence(metric) && metric.points.some(point => point.numericExpected)).map(metric => metric.id))], ids = (discovered.length ? discovered : DEFAULT_TREND_METRICS).slice(0, 512);
    this.fetchController = new AbortController();
    const selectedKey = this.model.metrics[this.state.selected]?.key;
    this.state.fetchMenu = false; this.state.fetching = true; this.state.fetchStatus = `Fetching the last ${days} days…`; this.renderSoon();
    try {
      await this.onFetch(days, ids, this.fetchController.signal);
      this.model = this.readModel();
      const retained = selectedKey ? this.model.metrics.findIndex(metric => metric.key === selectedKey) : -1;
      this.state.selected = retained >= 0 ? retained : 0; delete this.state.cursor; this.state.pointOffset = 0;
      this.state.fetchStatus = `Fetched ${days} days • ${this.model.documentCount} cached response${this.model.documentCount === 1 ? "" : "s"}`;
      this.normalizeSelection();
    } catch (error) {
      const message = (error instanceof Error ? error.message : String(error)).replace(/[\r\n\t\0-\x1f\x7f]/g, " ");
      const cancelled = this.fetchController.signal.aborted;
      this.state.fetchStatus = cancelled ? "Fetch cancelled" : `Fetch failed: ${message}`;
      this.state.fetchMenu = !cancelled;
    } finally { this.state.fetching = false; this.fetchController = undefined; this.renderSoon(); }
  }
  handleInput(data: string): void {
    const pressed = (...keys: KeyId[]) => keys.some(key => matchesKey(data, key));
    if (pressed("ctrl+c")) { this.fetchController?.abort(); this.onClose(); return; }
    if (this.state.help) {
      if (pressed("q", "shift+q")) { this.onClose(); return; }
      if (pressed("escape", "?")) delete this.state.help;
      this.renderSoon(); return;
    }
    if (this.state.searchEditing) {
      if (pressed("escape", "return")) { delete this.state.searchEditing; this.normalizeSelection(); }
      else if (pressed("ctrl+u")) { delete this.state.searchQuery; this.normalizeSelection(); }
      else if (pressed("backspace", "delete")) { this.state.searchQuery = (this.state.searchQuery ?? "").slice(0, -1); if (!this.state.searchQuery) delete this.state.searchQuery; this.normalizeSelection(); }
      else {
        const printable = printableInput(data);
        if (printable) { this.state.searchQuery = truncateToWidth(`${this.state.searchQuery ?? ""}${printable}`, 64, ""); this.normalizeSelection(); }
      }
      this.renderSoon(); return;
    }
    if (this.state.fetchMenu) {
      if (pressed("escape", "q", "shift+q", "f", "shift+f")) this.state.fetchMenu = false;
      else if (pressed("1")) void this.startFetch(7);
      else if (pressed("2")) void this.startFetch(30);
      else if (pressed("3")) void this.startFetch(90);
      this.renderSoon(); return;
    }
    if (this.state.fetching) { if (pressed("escape", "q", "shift+q")) { this.fetchController?.abort(); this.state.fetchStatus = "Cancelling fetch…"; this.renderSoon(); } return; }
    if (pressed("escape", "q", "shift+q")) { this.onClose(); return; }
    if (pressed("?")) this.state.help = true;
    else if (pressed("/")) { this.state.domain = "All"; this.state.searchEditing = true; this.normalizeSelection(); }
    else if (pressed("ctrl+u") && this.state.searchQuery) { delete this.state.searchQuery; this.normalizeSelection(); }
    else if (pressed("f", "shift+f") || pressed("return") && !this.model.documentCount) { this.state.fetchMenu = true; delete this.state.fetchStatus; }
    else if (pressed("1")) this.selectDomain("All");
    else if (pressed("2")) this.selectDomain("Activity");
    else if (pressed("3")) this.selectDomain("Sleep");
    else if (pressed("4")) this.selectDomain("Heart");
    else if (pressed("5")) this.selectDomain("Mobility");
    else if (pressed("6")) this.selectDomain("Recovery");
    else if (pressed("7")) this.selectDomain("Body");
    else if (pressed("8")) this.selectDomain("Other");
    else if (pressed("up", "k", "shift+k")) { if (this.state.screen === "records") this.state.recordOffset = Math.max(0, this.state.recordOffset - 1); else this.moveMetric(-1); }
    else if (pressed("down", "j", "shift+j")) { if (this.state.screen === "records") this.state.recordOffset = Math.min(Math.max(0, this.model.typedItems.length - 1), this.state.recordOffset + 1); else this.moveMetric(1); }
    else if (pressed("home")) { if (this.state.screen === "records") this.state.recordOffset = 0; else this.selectVisible(0); }
    else if (pressed("end")) { if (this.state.screen === "records") this.state.recordOffset = Math.max(0, this.model.typedItems.length - 1); else this.selectVisible(visibleMetricIndexes(this.model, this.state).length - 1); }
    else if (pressed("left")) { const metric = this.model.metrics[this.state.selected], count = metric ? selectedPoints(metric, this.state).filter(pointObserved).length : 0; this.state.cursor = Math.max(0, (this.state.cursor ?? Math.max(0, count - 1)) - 1); }
    else if (pressed("right")) { const metric = this.model.metrics[this.state.selected], count = metric ? selectedPoints(metric, this.state).filter(pointObserved).length : 0; this.state.cursor = Math.min(Math.max(0, count - 1), (this.state.cursor ?? Math.max(0, count - 1)) + 1); }
    else if (pressed("tab")) this.state.screen = this.state.screen === "overview" ? "metric" : this.state.screen === "metric" ? "records" : this.state.screen === "records" ? "coverage" : "overview";
    else if (pressed("o", "shift+o")) this.state.screen = "overview";
    else if (pressed("d", "shift+d", "return")) this.state.screen = "metric";
    else if (pressed("t", "shift+t")) this.state.screen = "records";
    else if (pressed("c", "shift+c")) this.state.screen = "coverage";
    else if (pressed("v", "shift+v")) { const current = this.state.chartMode ?? "auto"; this.state.chartMode = current === "auto" ? "bar" : current === "bar" ? "line" : "auto"; this.state.screen = "metric"; }
    else if (pressed("a", "shift+a")) { this.state.availableOnly = !(this.state.availableOnly !== false); this.normalizeSelection(); }
    else if (pressed("g", "shift+g")) {
      const domains: Array<DashboardDomain | "All"> = ["All", ...DASHBOARD_DOMAINS], start = domains.indexOf(this.state.domain ?? "All");
      for (let offset = 1; offset <= domains.length; offset++) { this.state.domain = domains[(start + offset) % domains.length]!; if (visibleMetricIndexes(this.model, this.state).length) break; }
      this.normalizeSelection();
    } else if (pressed("w", "shift+w")) { const windows = [7, 30, 90, 3650], index = windows.indexOf(this.state.pointWindow); this.state.pointWindow = windows[(index + 1) % windows.length]!; this.state.pointOffset = 0; delete this.state.cursor; }
    else if (pressed("[")) { this.state.pointOffset += Math.max(1, Math.floor(this.state.pointWindow / 2)); delete this.state.cursor; }
    else if (pressed("]")) { this.state.pointOffset = Math.max(0, this.state.pointOffset - Math.max(1, Math.floor(this.state.pointWindow / 2))); delete this.state.cursor; }
    else if (pressed("+", "=", "shift+=")) { this.state.pointWindow = Math.max(1, Math.floor(this.state.pointWindow / 2)); delete this.state.cursor; }
    else if (pressed("-", "_", "shift+-")) { this.state.pointWindow = Math.min(3650, this.state.pointWindow * 2); delete this.state.cursor; }
    else if (pressed("r", "shift+r")) { this.model = this.readModel(); this.normalizeSelection(); }
    this.renderSoon();
  }
  render(width: number): string[] { return renderFullDashboard(this.model, this.state, width, this.theme, this.getHeight()); }
  invalidate(): void {}
  dispose(): void { this.disposed = true; this.fetchController?.abort(); }
}
