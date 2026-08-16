import { displayValue } from "./exact.js";
import { boundedJson, jsonStringify, truncateUtf8, utf8ByteLength } from "./json.js";
import type { HealthStore, IndexEntry, JsonValue, QueryOptions, QueryResult } from "./model.js";

const MAX_RESULTS = 100;
export const MAX_EVIDENCE_BYTES = 24_000;
/** @deprecated Use MAX_EVIDENCE_BYTES; retained for API compatibility. */
export const MAX_EVIDENCE_CHARS = MAX_EVIDENCE_BYTES;
const MAX_VALUE_BYTES = 2_000;
const MAX_PROVENANCE_BYTES = 2_000;

function searchable(entry: IndexEntry): string {
  const scalarValue = entry.kind === "scalar" ? displayValue(entry.value, 512) : "";
  return [entry.path, entry.documentId, entry.file, entry.date, entry.ownerDate, entry.recordTimestamp, entry.unit, entry.statistic, entry.semanticId, entry.platform, entry.provider, entry.source, entry.origin, entry.operation, entry.contractKind, entry.schema, entry.schemaVersion, scalarValue].filter(value => value !== undefined && value !== null && value !== "").join(" ").toLowerCase();
}

export function matchingEntries(store: HealthStore, options: QueryOptions): IndexEntry[] {
  const needle = options.search?.toLowerCase();
  return store.entries.filter(entry => {
    if (options.path && !entry.path.toLowerCase().includes(options.path.toLowerCase())) return false;
    if (needle && !searchable(entry).includes(needle)) return false;
    if (options.metric && entry.semanticId !== options.metric) return false;
    return true;
  });
}

export function queryStore(store: HealthStore, options: QueryOptions): QueryResult {
  const requestedLimit = Math.max(1, Math.min(options.limit ?? 25, MAX_RESULTS));
  const offset = Math.max(0, options.offset ?? 0);
  const candidates = matchingEntries(store, options);
  const matches = candidates.slice(offset, offset + requestedLimit);
  return { matches, totalMatches: candidates.length, truncated: offset + matches.length < candidates.length, evidenceChars: 0, evidenceBytes: 0 };
}

function boundedText(text: string, maximum: number): string {
  return truncateUtf8(text.replace(/[\r\n\t]/g, " "), maximum, "…[value omitted]");
}
function boundedValue(entry: IndexEntry): string { return boundedText(displayValue(entry.value, MAX_VALUE_BYTES), MAX_VALUE_BYTES); }
function boundedProvenance(value: JsonValue): string { return boundedJson(value, MAX_PROVENANCE_BYTES); }

function evidenceRow(entry: IndexEntry): object {
  return {
    document: entry.documentId, file: entry.file, path: entry.path, value: boundedValue(entry), kind: entry.kind,
    contractKind: entry.contractKind, ...(entry.schema ? { schema: entry.schema } : {}), ...(entry.schemaVersion !== undefined ? { schemaVersion: String(entry.schemaVersion) } : {}), contractValid: entry.contractValid,
    ...(entry.contractErrors.length ? { contractErrors: entry.contractErrors.slice(0, 5) } : {}),
    ...(entry.date ? { date: entry.date } : {}), ...(entry.ownerDate ? { ownerDate: entry.ownerDate } : {}),
    ...(entry.recordTimestamp ? { recordTimestamp: entry.recordTimestamp } : {}), ...(entry.unit ? { unit: entry.unit } : {}),
    ...(entry.statistic ? { statistic: entry.statistic } : {}), ...(entry.semanticId ? { semanticId: entry.semanticId } : {}),
    ...(entry.platform ? { platform: entry.platform } : {}), ...(entry.provider ? { provider: entry.provider } : {}),
    ...(entry.source ? { source: entry.source } : {}), origin: entry.origin, ...(entry.operation ? { operation: entry.operation } : {}),
    ...(entry.captureStatus ? { captureStatus: entry.captureStatus } : {}), ...(entry.provenance ? { provenance: boundedProvenance(entry.provenance) } : {}),
  };
}

export function formatEvidence(result: QueryResult): object {
  const evidence: object[] = [];
  let omittedForSize = 0;
  for (const entry of result.matches) {
    let row = evidenceRow(entry);
    let candidate = { totalMatches: result.totalMatches, returned: evidence.length + 1, truncated: true, omittedForSize, evidence: [...evidence, row] };
    if (utf8ByteLength(jsonStringify(candidate)) > MAX_EVIDENCE_BYTES) {
      if (evidence.length === 0) {
        row = { document: entry.documentId, path: boundedText(entry.path, 512), value: "[value omitted: evidence row exceeded output bound]", contractKind: entry.contractKind, contractValid: entry.contractValid };
        candidate = { ...candidate, evidence: [row] };
        if (utf8ByteLength(jsonStringify(candidate)) <= MAX_EVIDENCE_BYTES) evidence.push(row);
      }
      omittedForSize = result.matches.length - evidence.length;
      break;
    }
    evidence.push(row);
  }
  const output = { totalMatches: result.totalMatches, returned: evidence.length, truncated: result.truncated || omittedForSize > 0, omittedForSize, evidence };
  result.evidenceChars = jsonStringify(output).length;
  result.evidenceBytes = utf8ByteLength(jsonStringify(output));
  return output;
}
