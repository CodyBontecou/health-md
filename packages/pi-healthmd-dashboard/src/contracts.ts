import { decodeExactNumber } from "./exact.js";
import type { ContractKind, JsonValue } from "./model.js";
import { validateQueryContract } from "./query-contract.js";
import { validateProviderSectionsSchema, validateUnifiedV9Schema } from "./schemas.js";

export interface ContractClassification {
  kind: ContractKind;
  schema?: string;
  schemaVersion?: string | number | bigint;
  profile?: string;
  ownerDate?: string;
  platform?: string;
  captureStatus?: string;
  valid: boolean;
  errors: string[];
  experimentalV9: boolean;
}

type Obj = { [key: string]: JsonValue };
const isObject = (value: JsonValue | undefined): value is Obj => value !== null && typeof value === "object" && !Array.isArray(value);
const version = (value: JsonValue | undefined) => typeof value === "string" || typeof value === "number" || typeof value === "bigint" ? value : undefined;
const string = (value: JsonValue | undefined) => typeof value === "string" ? value : undefined;
const ownDate = (value: Obj) => string(value.owner_date) ?? string(value.date) ?? (isObject(value.ownership) ? string(value.ownership.owner_date) : undefined);
const STATISTICS = ["sum", "average", "minimum", "maximum", "latest", "count", "duration_sum", "first_time", "last_time"] as const;
const V9_FIXTURE_METRIC_RULES = new Map<string, ReadonlyArray<readonly [string, string]>>([
  ["steps", [["sum", "count"]]],
  ["heart_rate_variability_sdnn", [["average", "millisecond"]]],
  ["heart_rate_variability_rmssd", [["latest", "millisecond"]]],
]);
const V9_FIXTURE_SOURCE_RULES = new Map<string, readonly [string, string]>([
  ["apple:steps", ["steps", "sum"]],
  ["apple:heart_rate_variability_sdnn", ["hrv", "average"]],
  ["android:steps", ["steps", "sum"]],
  ["android:heart_rate_variability_rmssd", ["android.hrv_rmssd", "latest"]],
]);

function timestampDate(value: string): Date | undefined {
  const milliseconds = value.replace(/\.(\d{3})\d*Z$/, ".$1Z");
  const parsed = new Date(milliseconds);
  return Number.isFinite(parsed.getTime()) ? parsed : undefined;
}

function localParts(value: Date, timeZone: string): { date: string; time: string } | undefined {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone, year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
    }).formatToParts(value);
    const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(item => item.type === type)?.value;
    const year = part("year"), month = part("month"), day = part("day");
    const hour = part("hour"), minute = part("minute"), second = part("second");
    return year && month && day && hour && minute && second ? { date: `${year}-${month}-${day}`, time: `${hour}:${minute}:${second}` } : undefined;
  } catch { return undefined; }
}

function nextDate(value: string): string | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return undefined;
  const date = new Date(0);
  date.setUTCFullYear(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + 1);
  date.setUTCHours(0, 0, 0, 0);
  return Number.isFinite(date.getTime()) ? date.toISOString().slice(0, 10) : undefined;
}

function validateV9(root: Obj): string[] {
  const errors = validateUnifiedV9Schema(root);
  const source = isObject(root.source) ? root.source : undefined;
  const platform = isObject(root.platform) ? root.platform : undefined;
  const sourcePlatform = source && string(source.platform);
  const expectedSource = sourcePlatform === "apple" ? "apple_health" : sourcePlatform === "android" ? "health_connect" : undefined;
  const expectedProfile = sourcePlatform === "apple" ? "apple_health_data_v8" : sourcePlatform === "android" ? new Set(["android_frozen_v4", "android_analytical_v5"]) : undefined;

  if (!source || !platform || !expectedProfile || !expectedSource) errors.push("source/platform shape is invalid");
  else {
    const sourceProfile = string(source.source_profile);
    if (expectedProfile instanceof Set ? !sourceProfile || !expectedProfile.has(sourceProfile) : sourceProfile !== expectedProfile) errors.push("source profile disagrees with platform");
    const keys = Object.keys(platform);
    if (keys.length !== 1 || keys[0] !== sourcePlatform) errors.push("source.platform and platform section disagree");
    const section = isObject(platform[sourcePlatform!]) ? platform[sourcePlatform!] as Obj : undefined;
    const expectedSchema = sourcePlatform === "apple" ? "healthmd.platform.apple_daily" : "healthmd.platform.android_daily";
    if (!section || section.schema !== expectedSchema || section.schema_version !== 1) errors.push("nested platform contract identity is invalid");
    else if (sourcePlatform === "apple" && section.source_schema_version !== 8) errors.push("Apple source schema version is invalid");
    else if (sourcePlatform === "android") {
      const expected = sourceProfile === "android_frozen_v4" ? [4, "android-frozen-v4"] : sourceProfile === "android_analytical_v5" ? [5, "android-analytical-v5"] : undefined;
      if (!expected || section.source_schema_version !== expected[0] || section.source_profile !== expected[1]) errors.push("Android source profile/version disagrees with platform section");
    }
  }

  const calendar = isObject(root.calendar) ? root.calendar : undefined;
  const ownerDate = string(root.owner_date);
  if (calendar && ownerDate) {
    const zone = string(calendar.time_zone), startText = string(calendar.interval_start), endText = string(calendar.interval_end);
    const start = startText && timestampDate(startText), end = endText && timestampDate(endText);
    const startLocal = start && zone ? localParts(start, zone) : undefined, endLocal = end && zone ? localParts(end, zone) : undefined;
    if (!start || !end || end <= start) errors.push("owner-day interval must be non-empty and ordered");
    if (!startLocal || startLocal.date !== ownerDate || startLocal.time !== "00:00:00") errors.push("interval start is not local midnight for owner_date");
    if (!endLocal || endLocal.date !== nextDate(ownerDate) || endLocal.time !== "00:00:00") errors.push("interval end is not the next local owner-date midnight");
  }

  const capture = isObject(root.capture) ? root.capture : undefined;
  const resources = capture && Array.isArray(capture.resources) ? capture.resources : undefined;
  const resourceKeys = new Set<string>();
  const resourceStatuses = new Map<string, string>();
  if (!capture || !resources) errors.push("capture/resources shape is invalid");
  else {
    for (const item of resources) {
      if (!isObject(item)) continue;
      const itemSource = string(item.source), resource = string(item.resource), status = string(item.status);
      if (expectedSource && itemSource !== expectedSource) errors.push(`capture resource ${resource ?? "?"} has wrong primary source`);
      if (itemSource && resource) {
        const key = `${itemSource}\0${resource}`;
        if (resourceKeys.has(key)) errors.push(`duplicate resource key ${itemSource}/${resource}`);
        resourceKeys.add(key);
        if (status) resourceStatuses.set(resource, status);
      }
    }
    const expected = resources.length === 0 ? "not_requested" : resources.every(item => isObject(item) && item.status === "complete") ? "complete" : "partial";
    if (capture.status !== expected) errors.push("capture.status is not mechanically derived from resources");
  }

  const metrics = Array.isArray(root.metrics) ? root.metrics : undefined;
  if (!metrics) errors.push("metrics must be an array");
  else {
    const metricKeys = new Set<string>();
    const semanticIds = new Set<string>();
    const order = new Map(STATISTICS.map((name, index) => [name, index]));
    let prior = "";
    for (const metric of metrics) {
      if (!isObject(metric)) continue;
      const semanticId = string(metric.semantic_id), statistic = string(metric.statistic);
      const key = `${semanticId ?? "?"}\0${statistic ?? "?"}`;
      if (metricKeys.has(key)) errors.push(`duplicate metric key ${key.replace("\0", "/")}`);
      metricKeys.add(key);
      if (semanticId) semanticIds.add(semanticId);
      const sortKey = `${semanticId ?? ""}\0${String(order.get(statistic as typeof STATISTICS[number]) ?? 999).padStart(3, "0")}`;
      if (prior && sortKey < prior) errors.push("metrics are not in canonical semantic/statistic order");
      prior = sortKey;
      if (semanticId && resourceStatuses.get(semanticId) !== "complete") errors.push(`metric ${semanticId} has no completed matching capture resource`);
      if (Array.isArray(metric.provenance) && expectedSource) for (const provenance of metric.provenance) {
        if (!isObject(provenance) || provenance.source !== expectedSource) {
          errors.push(`metric ${semanticId ?? "?"} contains provider or wrong-platform provenance`);
          continue;
        }
        const sourceRule = sourcePlatform && semanticId ? V9_FIXTURE_SOURCE_RULES.get(`${sourcePlatform}:${semanticId}`) : undefined;
        if (!sourceRule || provenance.source_semantic_id !== sourceRule[0]) errors.push(`metric ${semanticId ?? "?"} source_semantic_id is not approved by the current v9 proposal fixtures`);
        if (provenance.source_statistic !== undefined && provenance.source_statistic !== sourceRule?.[1]) errors.push(`metric ${semanticId ?? "?"} source_statistic is not approved by the current v9 proposal fixtures`);
      }
      const fact = isObject(metric.value) ? metric.value : undefined;
      if (fact?.value_type === "number" && isObject(fact.number)) {
        try { if (!decodeExactNumber(fact.number)) errors.push(`metric ${semanticId ?? "?"} has unknown exact-number representation`); }
        catch (error) { errors.push(`metric ${semanticId ?? "?"} exact number invalid: ${error instanceof Error ? error.message : String(error)}`); }
      }
      const rules = semanticId ? V9_FIXTURE_METRIC_RULES.get(semanticId) : undefined;
      if (!rules) errors.push(`metric ${semanticId ?? "?"} is not approved by the current v9 proposal fixtures`);
      else if (!fact || fact.value_type !== "number" || typeof fact.unit !== "string" || !rules.some(([allowedStatistic, allowedUnit]) => statistic === allowedStatistic && fact.unit === allowedUnit)) errors.push(`metric ${semanticId} statistic/unit is not approved by the current v9 proposal fixtures`);
    }
    if (semanticIds.has("hrv")) errors.push("ambiguous hrv semantic id is forbidden");
    if (sourcePlatform === "apple" && semanticIds.has("heart_rate_variability_rmssd")) errors.push("Apple primary data must not be relabeled as RMSSD");
    if (sourcePlatform === "android" && semanticIds.has("heart_rate_variability_sdnn")) errors.push("Android primary data must not be relabeled as SDNN");
  }

  if (root.providers !== undefined) {
    errors.push(...validateProviderSectionsSchema(root.providers).map(error => `providers${error.startsWith("$") ? error.slice(1) : `: ${error}`}`));
    if (capture?.status === "not_requested") errors.push("provider-only v9 days are forbidden");
  }
  return [...new Set(errors)].slice(0, 100);
}

function genericIdentity(root: Obj): Pick<ContractClassification, "schema" | "schemaVersion" | "profile" | "ownerDate" | "platform" | "captureStatus"> {
  const source = isObject(root.source) ? root.source : undefined;
  const capture = isObject(root.capture) ? root.capture : undefined;
  const header = isObject(root.header) ? root.header : undefined;
  const nestedSchema = header && string(header.schema);
  const nestedVersion = header && version(header.version);
  const schema = string(root.schema) ?? nestedSchema;
  const schemaVersion = version(root.schema_version) ?? version(root.version) ?? nestedVersion;
  const captureStatus = (capture ? string(capture.status) : undefined) ?? string(root.capture_status);
  return {
    ...(schema ? { schema } : {}),
    ...(schemaVersion !== undefined ? { schemaVersion } : {}),
    ...(string(root.profile) ?? string(root.schemaProfile) ? { profile: (string(root.profile) ?? string(root.schemaProfile))! } : {}),
    ...(ownDate(root) ? { ownerDate: ownDate(root)! } : {}),
    ...(source && string(source.platform) ? { platform: string(source.platform)! } : {}),
    ...(captureStatus ? { captureStatus } : {}),
  };
}

export function classifyContract(value: JsonValue, exactQueryTokens?: unknown): ContractClassification {
  if (!isObject(value)) return { kind: "generic_json", valid: true, errors: [], experimentalV9: false };
  const identity = genericIdentity(value);
  let kind: ContractKind = "generic_json";
  const schema = identity.schema;
  const schemaVersion = identity.schemaVersion;
  const profile = identity.profile;
  if (schema === "healthmd.health_data" && schemaVersion === 9) kind = "unified_v9";
  else if (schema === "healthmd.health_data" && [5, 6, 7, 8].includes(Number(schemaVersion))) kind = "apple_health_data";
  else if (value.type === "health-data" && (profile === "android-analytical-v5" || value.profileVersion === 5 || value.schemaVersion === 5)) kind = "android_analytical_v5";
  else if ((schema === "healthmd.health_data" && Number(schemaVersion) === 4) || value.type === "health-data" && value.schemaVersion === 4) kind = "android_frozen_v4";
  else if (value.type === "health-data" && schemaVersion === undefined && value.schemaVersion === undefined) kind = "android_unversioned";
  else if (schema === "healthmd.healthkit_records") kind = "healthkit_archive";
  else if (schema === "healthmd.raw-snapshot" || schema === "healthmd.raw_snapshot") kind = "android_raw_snapshot";
  else if (schema === "healthmd.raw-snapshot.manifest" || schema === "healthmd.raw_snapshot.manifest") kind = "android_raw_manifest";
  else if (schema === "healthmd.android_merge_provenance") kind = "android_merge_reference";
  else if (["healthmd.raw_record", "healthmd.raw_changes", "healthmd.raw-changes"].includes(schema ?? "")) kind = "android_raw_reference";
  else if (schema === "healthmd.provider.whoop_daily" || isObject(value.whoop) && value.whoop.schema === "healthmd.provider.whoop_daily") kind = "whoop_typed_daily";
  else if (schema === "healthmd.external_provider_daily") kind = "external_provider_daily";
  else if (schema?.includes("rollup")) kind = "rollup";
  else if (schema === "healthmd.api_export" || Array.isArray(value.external_records) && value.external_record_schema === "healthmd.external_provider_daily" || value.daily_record_schema === "healthmd.health_data" && Array.isArray(value.records)) kind = "api_envelope";
  else if (schema === "healthmd.raw_result" || isObject(value.raw_result) && value.raw_result.schema === "healthmd.raw_result") kind = "raw_envelope";
  else if (schema === "healthmd.query_response") kind = "query_response";
  else if (schema === "healthmd.mcp_query_pages") kind = "mcp_query_pages";
  else if (isObject(value.schema) && "source_version" in value.schema || "categories" in value && Array.isArray(value.periods)) kind = "rollup";
  else if ("header" in value && "manifest" in value && "records" in value) kind = "android_raw_snapshot";
  else if (schema?.startsWith("healthmd.")) kind = "generic_healthmd";
  const errors = kind === "unified_v9" ? validateV9(value) : kind === "query_response" || kind === "mcp_query_pages" ? validateQueryContract(value, 1_000, exactQueryTokens) : [];
  return { kind, ...identity, valid: errors.length === 0, errors, experimentalV9: kind === "unified_v9" && errors.length === 0 };
}

export function extractContext(object: Obj): Partial<{ ownerDate: string; recordTimestamp: string; unit: string; statistic: string; semanticId: string; provenance: JsonValue; platform: string; provider: string; source: string; captureStatus: string }> {
  const owner = string(object.owner_date) ?? string(object.date) ?? (isObject(object.ownership) ? string(object.ownership.owner_date) : undefined);
  const timestamp = ["start_time", "start_date", "startTime", "startDate", "observed_at", "observedAt", "fetched_at", "fetchedAt", "timestamp", "end_time", "end_date", "endTime", "endDate"].map(key => string(object[key])).find(Boolean);
  const typedUnit = object.type === "count" && object.value !== undefined ? "count" : object.type === "duration" && object.seconds !== undefined ? "s" : undefined;
  const evidenceSources = Array.isArray(object.evidence) ? [...new Set(object.evidence.flatMap(item => isObject(item) && string(item.source_id) ? [string(item.source_id)!] : []))] : [];
  const source = string(object.source_id) ?? (evidenceSources.length > 0 ? evidenceSources.sort().join(",") : undefined);
  return {
    ...(owner ? { ownerDate: owner } : {}), ...(timestamp ? { recordTimestamp: timestamp } : {}),
    ...(string(object.unit) ?? typedUnit ? { unit: (string(object.unit) ?? typedUnit)! } : {}), ...(string(object.statistic) ? { statistic: string(object.statistic)! } : {}),
    ...(string(object.semantic_id) ?? string(object.metric_id) ? { semanticId: (string(object.semantic_id) ?? string(object.metric_id))! } : {}),
    ...(object.provenance !== undefined ? { provenance: object.provenance } : object.evidence !== undefined ? { provenance: object.evidence } : {}),
    ...(string(object.platform) ? { platform: string(object.platform)! } : {}), ...(string(object.provider) ? { provider: string(object.provider)! } : {}),
    ...(source ? { source } : {}), ...(string(object.capture_status) ? { captureStatus: string(object.capture_status)! } : {}),
  };
}
