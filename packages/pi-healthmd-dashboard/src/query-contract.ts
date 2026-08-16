import { JsonNumberToken } from "./json.js";
import type { JsonValue } from "./model.js";

type JsonObject = { [key: string]: JsonValue };
const object = (value: JsonValue | undefined): value is JsonObject => value !== null && typeof value === "object" && !Array.isArray(value);
const keys = (value: JsonValue | undefined, allowed: readonly string[], required: readonly string[] = allowed): JsonObject | undefined => {
  if (!object(value) || Object.keys(value).some(key => !allowed.includes(key)) || required.some(key => !(key in value))) return undefined;
  return value;
};
const string = (value: JsonValue | undefined): value is string => typeof value === "string";
const nonempty = (value: JsonValue | undefined): value is string => string(value) && value.length > 0;
const I64_MIN = -(1n << 63n), I64_MAX = (1n << 63n) - 1n, U64_MAX = (1n << 64n) - 1n;
const finite = (value: JsonValue | undefined): boolean => typeof value === "number" && Number.isFinite(value) || typeof value === "bigint" && value >= I64_MIN && value <= U64_MAX;
const integerValue = (value: JsonValue | undefined): bigint | undefined => typeof value === "bigint" ? value : typeof value === "number" && Number.isSafeInteger(value) ? BigInt(value) : undefined;
const integer = (value: JsonValue | undefined): boolean => { const integer = integerValue(value); return integer !== undefined && integer >= I64_MIN && integer <= I64_MAX; };
const unsigned = (value: JsonValue | undefined): boolean => { const integer = integerValue(value); return integer !== undefined && integer >= 0n && integer <= U64_MAX; };
const integerEquals = (value: JsonValue | undefined, expected: number): boolean => integerValue(value) === BigInt(expected);
const array = (value: JsonValue | undefined, validator: (item: JsonValue) => boolean, maximum?: number): value is JsonValue[] => Array.isArray(value) && (maximum === undefined || value.length <= maximum) && value.every(validator);
const strings = (value: JsonValue | undefined): value is string[] => array(value, nonempty);
const absentOr = (value: JsonValue | undefined, validator: (item: JsonValue) => boolean): boolean => value === undefined || validator(value);
const nullableOr = (value: JsonValue | undefined, validator: (item: JsonValue) => boolean): boolean => value === undefined || value === null || validator(value);
const nullableString = (value: JsonValue | undefined): boolean => value === undefined || value === null || string(value);

const STATUSES = new Set(["available", "complete_empty", "partial", "failed", "unsupported", "skipped", "cancelled", "not_requested", "legacy_unavailable", "redacted", "not_synchronized"]);
const status = (value: JsonValue | undefined): boolean => string(value) && STATUSES.has(value);
const dateRange = (value: JsonValue): boolean => {
  const item = keys(value, ["start_date", "end_date"]);
  return Boolean(item && nonempty(item.start_date) && nonempty(item.end_date));
};
const source = (value: JsonValue): boolean => {
  const item = keys(value, ["schema", "schema_version", "digest"]);
  return Boolean(item && nonempty(item.schema) && unsigned(item.schema_version) && string(item.digest) && /^[0-9a-fA-F]{64}$/.test(item.digest));
};
const limitation = (value: JsonValue): boolean => {
  const item = keys(value, ["code", "message"]);
  return Boolean(item && nonempty(item.code) && item.code.length <= 128 && nonempty(item.message) && item.message.length <= 512);
};
const locator = (value: JsonValue): boolean => {
  if (!object(value) || !string(value.type)) return false;
  const detail = value.type === "summary_key" ? "key" : value.type === "canonical_uuid" ? "uuid" : ["external_identity", "query_manifest", "partial_failure"].includes(value.type) ? "identifier" : value.type === "warning" ? "code" : undefined;
  if (!detail) return false;
  const item = keys(value, ["type", "owner_date", detail]);
  return Boolean(item && nonempty(item.owner_date) && nonempty(item[detail]));
};
const evidenceReference = (value: JsonValue): boolean => {
  const item = keys(value, ["evidence_id", "locator", "source", "source_id", "provider_id"], ["evidence_id", "locator", "source", "source_id"]);
  return Boolean(item && nonempty(item.evidence_id) && nonempty(item.source_id) && absentOr(item.provider_id, nonempty) && item.locator !== undefined && locator(item.locator) && item.source !== undefined && source(item.source));
};
const missingInterval = (value: JsonValue): boolean => {
  const item = keys(value, ["range", "status", "reason"], ["range", "status"]);
  return Boolean(item && item.range !== undefined && dateRange(item.range) && status(item.status) && absentOr(item.reason, string));
};
const coverage = (value: JsonValue | undefined): boolean => {
  const item = keys(value, ["requested_range", "available_range", "status", "days_considered", "days_with_values", "missing", "missing_interval_count", "missing_truncated"], ["status", "days_considered", "days_with_values", "missing"]);
  const daysConsidered = item && integerValue(item.days_considered), daysWithValues = item && integerValue(item.days_with_values);
  if (!item || !status(item.status) || !unsigned(item.days_considered) || !unsigned(item.days_with_values) || daysConsidered === undefined || daysWithValues === undefined || daysWithValues > daysConsidered) return false;
  return array(item.missing, missingInterval, 64) && nullableOr(item.requested_range, dateRange) && nullableOr(item.available_range, dateRange) && absentOr(item.missing_interval_count, unsigned) && (item.missing_truncated === undefined || typeof item.missing_truncated === "boolean");
};

function queryValue(value: JsonValue, depth = 0): boolean {
  if (depth > 64 || !object(value) || !nonempty(value.type)) return false;
  let valid = false;
  if (value.type === "quantity") valid = finite(value.value) && nonempty(value.unit);
  else if (value.type === "duration") valid = finite(value.seconds);
  else if (value.type === "count") valid = integer(value.value);
  else if (["string", "timestamp", "date"].includes(value.type)) valid = string(value.value);
  else if (value.type === "boolean") valid = typeof value.value === "boolean";
  else if (value.type === "category") valid = nonempty(value.identifier) && absentOr(value.display, string) && absentOr(value.raw_value, integer);
  else if (value.type === "array") valid = array(value.value, item => queryValue(item, depth + 1));
  else valid = true;
  if (!valid) return false;
  const allowed = value.type === "quantity" ? ["type", "value", "unit"] : value.type === "duration" ? ["type", "seconds"] : value.type === "category" ? ["type", "identifier", "display", "raw_value"] : ["type", "value"];
  return Object.keys(value).every(key => allowed.includes(key));
}

const metricItem = (value: JsonValue): boolean => {
  const allowed = ["metric_id", "display_name", "owner_date", "value", "status", "evidence", "limitations"];
  const item = keys(value, allowed, ["metric_id", "display_name", "owner_date", "status", "evidence", "limitations"]);
  return Boolean(item && nonempty(item.metric_id) && nonempty(item.display_name) && nonempty(item.owner_date) && status(item.status) && nullableOr(item.value, queryValue) && array(item.evidence, evidenceReference) && array(item.limitations, limitation, 64));
};
const aggregation = (value: JsonValue): boolean => {
  const item = keys(value, ["metric_id", "kind", "expected_unit"], ["metric_id", "kind"]);
  return Boolean(item && nonempty(item.metric_id) && string(item.kind) && ["sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"].includes(item.kind) && absentOr(item.expected_unit, string));
};
const comparisonItem = (value: JsonValue): boolean => {
  const item = keys(value, ["metric_id", "aggregation", "first_range", "second_range", "first_value", "second_value", "absolute_change", "percent_change", "direction", "coverage", "evidence", "limitations"], ["metric_id", "aggregation", "first_range", "second_range", "direction", "coverage", "evidence", "limitations"]);
  return Boolean(item && nonempty(item.metric_id) && item.aggregation !== undefined && aggregation(item.aggregation) && item.first_range !== undefined && dateRange(item.first_range) && item.second_range !== undefined && dateRange(item.second_range) && string(item.direction) && ["increased", "decreased", "unchanged", "not_comparable"].includes(item.direction) && coverage(item.coverage) && nullableOr(item.first_value, queryValue) && nullableOr(item.second_value, queryValue) && nullableOr(item.absolute_change, queryValue) && nullableOr(item.percent_change, finite) && array(item.evidence, evidenceReference) && array(item.limitations, limitation, 64));
};
const workout = (value: JsonValue): boolean => {
  const allowed = ["workout_id", "activity", "start", "end", "details", "evidence_ids"];
  const item = keys(value, allowed);
  return Boolean(item && nonempty(item.workout_id) && nonempty(item.activity) && nonempty(item.start) && nonempty(item.end) && object(item.details) && Object.values(item.details).every(detail => queryValue(detail)) && strings(item.evidence_ids));
};
const sleepPhysiology = (value: JsonValue): boolean => {
  const item = keys(value, ["metric_id", "status", "sample_count", "first_sample_at", "last_sample_at", "observed_owner_dates", "evidence"], ["metric_id", "status", "sample_count", "observed_owner_dates", "evidence"]);
  return Boolean(item && nonempty(item.metric_id) && status(item.status) && unsigned(item.sample_count) && nullableString(item.first_sample_at) && nullableString(item.last_sample_at) && strings(item.observed_owner_dates) && array(item.evidence, evidenceReference));
};
const sleepWindow = (value: JsonValue): boolean => {
  const item = keys(value, ["start_offset_seconds", "duration_seconds"], ["duration_seconds"]);
  return Boolean(item && absentOr(item.start_offset_seconds, finite) && finite(item.duration_seconds));
};
const sleepSession = (value: JsonValue): boolean => {
  const allowed = ["session_id", "owner_date", "calendar_dates", "classification", "completeness", "start", "end", "local_start", "local_end", "calendar_timezone", "analysis_start", "analysis_end", "requested_window", "elapsed_duration_seconds", "observed_duration_seconds", "untracked_duration_seconds", "asleep_duration_seconds", "awake_duration_seconds", "stage_durations_seconds", "physiology", "evidence", "limitations"];
  const item = keys(value, allowed, allowed.filter(key => key !== "requested_window"));
  if (!item || !["session_id", "owner_date", "start", "end", "local_start", "local_end", "calendar_timezone", "analysis_start", "analysis_end"].every(key => nonempty(item[key]))) return false;
  if (!string(item.classification) || !["overnight", "nap", "sleep"].includes(item.classification) || !string(item.completeness) || !["complete", "partial", "truncated_at_start", "truncated_at_end", "truncated_at_both", "aggregated", "outside_session"].includes(item.completeness)) return false;
  if (!strings(item.calendar_dates) || !["elapsed_duration_seconds", "observed_duration_seconds", "untracked_duration_seconds", "asleep_duration_seconds", "awake_duration_seconds"].every(key => finite(item[key]))) return false;
  return object(item.stage_durations_seconds) && Object.values(item.stage_durations_seconds).every(finite) && nullableOr(item.requested_window, sleepWindow) && array(item.physiology, sleepPhysiology) && array(item.evidence, evidenceReference) && array(item.limitations, limitation, 64);
};
const alignmentItem = (value: JsonValue): boolean => {
  const item = keys(value, ["alignment_id", "workout", "preceding_sleep", "following_sleep", "seconds_from_preceding_sleep", "seconds_until_following_sleep", "physiology_sample_count", "status", "evidence", "limitations"], ["alignment_id", "workout", "physiology_sample_count", "status", "evidence", "limitations"]);
  return Boolean(item && nonempty(item.alignment_id) && item.workout !== undefined && workout(item.workout) && unsigned(item.physiology_sample_count) && string(item.status) && ["complete", "partial", "unavailable"].includes(item.status) && nullableOr(item.preceding_sleep, sleepSession) && nullableOr(item.following_sleep, sleepSession) && nullableOr(item.seconds_from_preceding_sleep, finite) && nullableOr(item.seconds_until_following_sleep, finite) && array(item.evidence, evidenceReference) && array(item.limitations, limitation, 64));
};
const contextEvidence = (value: JsonValue): boolean => {
  const item = keys(value, ["reference", "value", "note", "metric_ids"], ["reference", "metric_ids"]);
  return Boolean(item && item.reference !== undefined && evidenceReference(item.reference) && strings(item.metric_ids) && nullableOr(item.value, queryValue) && absentOr(item.note, string));
};
const queryItem = (value: JsonValue): boolean => {
  if (!object(value) || !string(value.type)) return false;
  const validator = value.type === "metric" ? metricItem : value.type === "comparison" ? comparisonItem : value.type === "workout" ? workout : value.type === "sleep_session" ? sleepSession : value.type === "workout_sleep_alignment" ? alignmentItem : value.type === "evidence" ? contextEvidence : undefined;
  return Boolean(validator && Object.keys(value).length === 2 && value[value.type] !== undefined && validator(value[value.type]!));
};
const packetMetadata = (value: JsonValue): boolean => {
  const item = keys(value, ["generated_at", "producer"]);
  return Boolean(item && nonempty(item.generated_at) && nonempty(item.producer));
};
const packetFact = (value: JsonValue): boolean => {
  const item = keys(value, ["fact_id", "label", "owner_date", "value", "evidence"], ["fact_id", "label", "value", "evidence"]);
  return Boolean(item && nonempty(item.fact_id) && nonempty(item.label) && absentOr(item.owner_date, string) && item.value !== undefined && queryValue(item.value) && array(item.evidence, evidenceReference));
};
function packetFactCount(value: JsonValue, itemsEmpty: boolean): number | undefined {
  const item = keys(value, ["schema", "schema_version", "packet_id", "kind", "range", "facts", "coverage", "sources", "limitations", "metadata"]);
  if (!itemsEmpty || !item || item.schema !== "healthmd.evidence_packet" || item.schema_version !== 1 || !nonempty(item.packet_id) || !string(item.kind) || !["daily_wellness", "training", "doctor_visit"].includes(item.kind)) return undefined;
  if (!nullableOr(item.range, dateRange) || !coverage(item.coverage) || !array(item.sources, source, 64) || !array(item.limitations, limitation, 64) || item.metadata === undefined || !packetMetadata(item.metadata) || !array(item.facts, packetFact)) return undefined;
  return item.facts.length;
}

function validatePage(value: JsonValue, label: string, maximumItems: number): string[] {
  const allowed = ["schema", "schema_version", "items", "packet", "coverage", "sources", "evidence", "next_cursor", "limitations", "metadata"];
  const item = keys(value, allowed, ["schema", "schema_version", "items", "coverage", "sources", "evidence", "limitations"]);
  if (!item || item.schema !== "healthmd.query_response" || item.schema_version !== 1) return [`${label} must be a structurally canonical healthmd.query_response/1`];
  if (!array(item.items, queryItem) || !coverage(item.coverage) || !array(item.sources, source, 64) || !array(item.evidence, evidenceReference) || !array(item.limitations, limitation, 64) || !nullableString(item.next_cursor) || !nullableOr(item.metadata, object)) return [`${label} has invalid canonical fields`];
  const facts = item.packet === undefined || item.packet === null ? 0 : packetFactCount(item.packet, item.items.length === 0);
  if (facts === undefined || item.items.length + facts > maximumItems) return [`${label} exceeds canonical item bounds or contains an invalid evidence packet`];
  return [];
}

const UNSIGNED_INTEGER_FIELDS = new Set(["schema_version", "days_considered", "days_with_values", "missing_interval_count", "sample_count", "physiology_sample_count", "page_count", "item_count", "packet_fact_count"]);
function validateIntegerTokens(value: unknown): string[] {
  const errors: string[] = [];
  const stack: Array<{ value: unknown; parent?: Record<string, unknown>; key?: string }> = [{ value }];
  while (stack.length) {
    const item = stack.pop()!;
    if (item.value instanceof JsonNumberToken) {
      const integerField = item.key && (UNSIGNED_INTEGER_FIELDS.has(item.key) || item.key === "raw_value" || item.key === "value" && item.parent?.type === "count");
      if (!integerField) continue;
      if (!/^-?(?:0|[1-9]\d*)$/.test(item.value.token)) { errors.push(`Canonical integer field ${item.key} used a non-integer JSON token`); continue; }
      const integer = BigInt(item.value.token);
      const unsignedField = item.key !== "raw_value" && !(item.key === "value" && item.parent?.type === "count");
      if (unsignedField ? integer < 0n || integer > U64_MAX : integer < I64_MIN || integer > I64_MAX) errors.push(`Canonical integer field ${item.key} is out of range`);
      continue;
    }
    if (Array.isArray(item.value)) {
      for (const child of item.value) stack.push({ value: child });
    } else if (item.value !== null && typeof item.value === "object") {
      const parent = item.value as Record<string, unknown>;
      for (const [key, child] of Object.entries(parent)) stack.push({ value: child, parent, key });
    }
  }
  return [...new Set(errors)].slice(0, 100);
}

/** Validate the canonical typed query receipts returned by both Health.md CLI and MCP adapters. */
export function validateQueryContract(value: JsonValue, maximumItems = 1_000, exactTokens?: unknown, initialCursor?: string): string[] {
  if (!Number.isSafeInteger(maximumItems) || maximumItems < 1 || maximumItems > 1_000) return ["Health.md query item bound is invalid"];
  const tokenErrors = exactTokens === undefined ? [] : validateIntegerTokens(exactTokens);
  if (!object(value)) return [...tokenErrors, "Health.md typed query returned a non-object JSON result"];
  if (value.schema === "healthmd.query_response") return [...new Set([...tokenErrors, ...validatePage(value, "Health.md query response", maximumItems)])].slice(0, 100);
  const top = keys(value, ["schema", "schema_version", "pages", "receipt"]);
  if (!top || top.schema !== "healthmd.mcp_query_pages" || top.schema_version !== 1 || !Array.isArray(top.pages) || top.pages.length === 0 || top.pages.length > 4_096 || !object(top.receipt)) return [...tokenErrors, "Health.md typed query did not return a canonical healthmd.query_response/1 or healthmd.mcp_query_pages/1"];
  const errors = [...tokenErrors, ...top.pages.flatMap((page, index) => validatePage(page, `Health.md query page ${index + 1}`, maximumItems))];
  const receipt = keys(top.receipt, ["page_count", "item_count", "packet_fact_count", "traversal_complete", "next_cursor", "limit_reason"]);
  const itemCount = top.pages.reduce<number>((count, page) => count + (object(page) && Array.isArray(page.items) ? page.items.length : 0), 0);
  const factCount = top.pages.reduce<number>((count, page) => {
    if (!object(page) || !Array.isArray(page.items) || page.packet === undefined || page.packet === null) return count;
    return count + (packetFactCount(page.packet, page.items.length === 0) ?? 0);
  }, 0);
  if (!receipt || !integerEquals(receipt.page_count, top.pages.length) || !integerEquals(receipt.item_count, itemCount) || !integerEquals(receipt.packet_fact_count, factCount) || typeof receipt.traversal_complete !== "boolean" || !nullableString(receipt.next_cursor) || !nullableString(receipt.limit_reason)) errors.push("Health.md multipage receipt is inconsistent");
  else {
    const cursors = top.pages.map(page => object(page) ? page.next_cursor : undefined);
    const intermediate = cursors.slice(0, -1), returnedCursors = cursors.filter(nonempty);
    if (intermediate.some(cursor => !nonempty(cursor)) || new Set(returnedCursors).size !== returnedCursors.length || initialCursor !== undefined && returnedCursors.includes(initialCursor)) errors.push("Health.md multipage cursor chain is invalid");
    const lastCursor = cursors.at(-1);
    if (receipt.traversal_complete) {
      if (receipt.next_cursor !== null || receipt.limit_reason !== null || !(lastCursor === null || lastCursor === undefined)) errors.push("Health.md completed traversal receipt is inconsistent");
    } else if (!nonempty(receipt.next_cursor) || !string(receipt.limit_reason) || !["maximum_pages", "maximum_aggregate_bytes"].includes(receipt.limit_reason) || receipt.limit_reason === "maximum_pages" && top.pages.length !== 4_096 || lastCursor !== receipt.next_cursor) errors.push("Health.md limited traversal receipt is inconsistent");
  }
  return [...new Set(errors)].slice(0, 100);
}
