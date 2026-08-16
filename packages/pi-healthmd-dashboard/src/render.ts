import stringWidth from "string-width";
import { displayValue, numericValue } from "./exact.js";
import type { HealthStore, IndexEntry, ViewState } from "./model.js";
import { matchingEntries } from "./query.js";

export function visibleWidth(text: string): number { return stringWidth(text); }
export function truncateWidth(text: string, width: number): string {
  if (width <= 0) return "";
  if (visibleWidth(text) <= width) return text;
  if (width === 1) return "…";
  let output = "";
  for (const character of text) { if (visibleWidth(output + character) > width - 1) break; output += character; }
  return `${output}…`;
}
function padWidth(text: string, width: number): string { const truncated = truncateWidth(text, width); return `${truncated}${" ".repeat(Math.max(0, width - visibleWidth(truncated)))}`; }
function fit(lines: string[], width: number): string[] { return lines.map(line => truncateWidth(line.replace(/[\r\n\t]/g, " "), Math.max(0, width))); }

export function selectedEntries(store: HealthStore, view: ViewState): IndexEntry[] {
  const candidates = !view.target ? store.entries.filter(entry => entry.semanticId && isNumericCandidate(entry) && (entry.path.endsWith(".number") || /\.value\.(?:value|seconds)$/.test(entry.path))) : matchingEntries(store, {
    ...(view.targetKind === "metric" ? { metric: view.target } : {}), ...(view.targetKind === "path" ? { path: view.target } : {}), ...(view.targetKind === "search" ? { search: view.target } : {}),
  });
  const filtered = candidates.filter(entry => {
    const filterDate = entry.ownerDate ?? entry.date;
    return (!view.startDate || !filterDate || filterDate >= view.startDate) && (!view.endDate || !filterDate || filterDate <= view.endDate);
  });
  filtered.sort((a, b) => (a.date ?? "").localeCompare(b.date ?? "") || a.documentId.localeCompare(b.documentId) || a.path.localeCompare(b.path));
  const maxOffset = Math.max(0, filtered.length - view.windowSize);
  const start = Math.max(0, Math.min(view.offset, maxOffset));
  return filtered.slice(start, start + view.windowSize);
}

function table(entries: IndexEntry[], width: number): string[] {
  if (entries.length === 0) return ["No matching loaded evidence."];
  if (width < 16) return entries.map(entry => truncateWidth(displayValue(entry.value), width));
  const dateWidth = Math.min(20, Math.max(6, Math.floor(width * 0.22)));
  const valueWidth = Math.min(28, Math.max(5, Math.floor(width * 0.25)));
  const pathWidth = Math.max(1, width - dateWidth - valueWidth - 6);
  return [`${padWidth("DATE", dateWidth)} | ${padWidth("PATH", pathWidth)} | VALUE`, ...entries.map(entry => `${padWidth(entry.date ?? "—", dateWidth)} | ${padWidth(entry.path, pathWidth)} | ${truncateWidth(displayValue(entry.value), valueWidth)}`)];
}

function seriesIdentity(entry: IndexEntry): string {
  const pathIdentity = entry.semanticId ?? entry.path.replace(/\[\d+\]/g, "[]");
  return [pathIdentity, entry.contractKind, entry.schema ?? "", String(entry.schemaVersion ?? ""), entry.unit ?? "", entry.statistic ?? "", entry.provider ?? "", entry.platform ?? "", entry.source ?? "", entry.origin].join("\0");
}
function isNumericCandidate(entry: IndexEntry): boolean {
  if (typeof entry.value === "number" || typeof entry.value === "bigint") return true;
  return entry.value !== null && typeof entry.value === "object" && !Array.isArray(entry.value) && ["binary64", "signed_integer", "unsigned_integer"].includes(String(entry.value.representation));
}
function chart(entries: IndexEntry[], width: number, structuredTarget: boolean): { lines?: string[]; reason?: string } {
  if (structuredTarget && entries.some(entry => entry.kind !== "scalar")) return { reason: "structured values" };
  const candidates = entries.filter(entry => {
    if (!isNumericCandidate(entry) || /(?:^|\.|\[)(?:evidence|provenance|sources|coverage|limitations)(?:\.|\[|$)/.test(entry.path)) return false;
    return entry.origin === "file" || !entry.semanticId || /\.metric\.value\.(?:value|seconds)$/.test(entry.path);
  });
  if (candidates.length === 0) return { reason: "non-numeric/unsafe exact values" };
  const decoded = candidates.map(entry => ({ entry, value: numericValue(entry.value) }));
  if (decoded.some(point => point.value === undefined)) return { reason: "non-numeric/unsafe exact values" };
  const points = decoded as Array<{ entry: IndexEntry; value: number }>;
  if (new Set(points.map(point => seriesIdentity(point.entry))).size > 1) return { reason: "mixed contract/schema/path/unit/statistic/provider/platform/source/origin series" };
  const values = points.map(point => point.value);
  const minimum = Math.min(...values), maximum = Math.max(...values);
  const scale = Math.max(1, Math.abs(minimum), Math.abs(maximum));
  const scaledMinimum = minimum / scale, scaledMaximum = maximum / scale;
  const barWidth = Math.max(1, Math.min(40, width - 14));
  return { lines: points.map(point => {
    const ratio = maximum === minimum ? 1 : (point.value / scale - scaledMinimum) / (scaledMaximum - scaledMinimum);
    const bars = Math.max(1, Math.round(Math.max(0, Math.min(1, ratio)) * barWidth));
    const labelWidth = Math.max(1, Math.min(18, width - barWidth - 2));
    const shown = Object.is(point.value, -0) ? "-0" : String(point.value);
    return `${padWidth(point.entry.date ?? point.entry.documentId, labelWidth)} ${"█".repeat(bars)} ${shown}${point.entry.unit ? ` ${point.entry.unit}` : ""}`;
  }) };
}

export function renderDashboard(store: HealthStore | undefined, view: ViewState, width: number): string[] {
  if (!view.visible || width <= 0) return [];
  if (!store) return fit(["Health.md — no data", "/healthmd load <path>"], width);
  const entries = selectedEntries(store, view);
  const chartResult = view.mode === "chart" ? chart(entries, width, view.targetKind === "path") : {};
  const dates = store.entries.map(entry => entry.ownerDate ?? entry.date).filter((date): date is string => Boolean(date)).sort();
  const sources = [...new Set(store.documents.map(document => [document.origin, document.operation, document.platform, document.contractKind].filter(Boolean).join("/")))];
  const refs = store.references.reduce<Record<string, number>>((acc, ref) => ({ ...acc, [ref.status]: (acc[ref.status] ?? 0) + 1 }), {});
  const lines = [
    store.documents.some(document => document.experimentalV9) ? "EXPERIMENTAL proposed v9 reader — Health.md" : "Health.md dashboard",
    `${view.targetKind}:${view.target ?? "overview"} • ${view.mode} • ${entries.length} shown`,
    `Coverage: ${store.documents.length} files • ${dates[0] ?? "—"}..${dates.at(-1) ?? "—"}`,
    `Source: ${sources.join(",") || "unknown"} • capture ${[...new Set(store.documents.map(d => d.captureStatus).filter(Boolean))].join(",") || "unknown"}`,
    `References ${Object.entries(refs).map(([key, count]) => `${key}:${count}`).join(",") || "none"}`,
    ...(view.mode === "chart" && chartResult.reason ? [`Chart split/refused: ${chartResult.reason}; table fallback.`] : []),
    ...(chartResult.lines ?? table(entries, width)),
  ];
  return fit(lines.slice(0, 10), width);
}
