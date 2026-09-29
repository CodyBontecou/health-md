import { decryptExport, parseExportKeyring, sha256Hex } from "./crypto";
import { HttpError, json, readJson, assertSameOrigin } from "./http";
import type { Env } from "./types";
import registry from "../../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json" with { type: "json" };

// These are the eleven reviewed Apple-v8 daily-summary bindings used by the
// separate MCP reader. Android and provider-native statistics are NOT aliases.
const projections = [
  { id: "steps", section: "activity", field: "steps", key: "steps", divisor: 1 },
  { id: "active_energy", section: "activity", field: "activeCalories", key: "active_calories", divisor: 1 },
  { id: "heart_rate_avg", section: "heart", field: "averageHeartRate", key: "average_heart_rate", divisor: 1 },
  { id: "heart_rate_min", section: "heart", field: "heartRateMin", key: "heart_rate_min", divisor: 1 },
  { id: "heart_rate_max", section: "heart", field: "heartRateMax", key: "heart_rate_max", divisor: 1 },
  { id: "resting_heart_rate", section: "heart", field: "restingHeartRate", key: "resting_heart_rate", divisor: 1 },
  { id: "hrv", section: "heart", field: "hrv", key: "hrv_ms", divisor: 1 },
  { id: "sleep_total", section: "sleep", field: "totalDuration", key: "sleep_total_hours", divisor: 3600 },
  { id: "sleep_deep", section: "sleep", field: "deepSleep", key: "sleep_deep_hours", divisor: 3600 },
  { id: "sleep_rem", section: "sleep", field: "remSleep", key: "sleep_rem_hours", divisor: 3600 },
  { id: "weight", section: "body", field: "weight", key: "weight_kg", divisor: 1 },
] as const;
type MetricId = (typeof projections)[number]["id"];
const catalog = projections.map((projection) => {
  const metric = registry.metrics.find((item) => item.semantic_id === projection.id);
  const output = metric?.apple?.outputs?.[0];
  if (!metric?.apple || output?.key !== projection.key || !output.unit) {
    throw new Error("Dashboard metric binding no longer matches the shared registry");
  }
  return { id: projection.id, label: metric.apple.reference_name ?? projection.id, unit: output.unit };
});
const DAY = 86_400_000;
const MAX_DECRYPTED_BYTES = 48 * 1024 * 1024;
const MAX_OBJECT_BYTES = 25 * 1024 * 1024 + 256;
const DATE = /^\d{4}-\d{2}-\d{2}$/u;
const OBJECT_KEY = /^v1\/[a-f0-9-]{36}$/u;
const EXPORT_ID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
export interface EnvelopeRow {
  source: string; dailyVersion: number; exportId: string; objectKey: string;
  keyId: string; digest: string; byteCount: number; envelopeVersion: number; recordCount: number;
}
interface DayRow extends EnvelopeRow { date: string; recordIndex: number }
type Profile = "all" | "apple_v8" | "android_compat";
type DayStatus = "not_uploaded" | "available" | "unsupported_profile" | "filtered_profile" | "read_limit";

export function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
export function validDate(input: unknown): input is string {
  if (typeof input !== "string" || !DATE.test(input)) return false;
  const parsed = new Date(`${input}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === input;
}
function project(record: Record<string, unknown>, metrics: readonly MetricId[]): Record<string, number | null> {
  const values: Record<string, number | null> = Object.fromEntries(metrics.map((id) => [id, null]));
  const units = object(record.units);
  const timezone = object(record.time_context)?.calendar_timezone;
  if (typeof timezone !== "string" || !/^[A-Za-z0-9_+\/-]{1,64}$/u.test(timezone)) return values;
  for (const id of metrics) {
    const binding = projections.find((item) => item.id === id)!;
    const unit = catalog.find((item) => item.id === id)!.unit;
    const raw = object(record[binding.section])?.[binding.field];
    if (typeof raw === "number" && Number.isFinite(raw) && units?.[binding.key] === unit) {
      values[id] = raw / binding.divisor;
    }
  }
  return values;
}

// Shared by the owner-only chart and JSON navigator. The original download
// remains the only byte-exact representation (including unsafe JSON integers).
export async function readVerifiedEnvelope(row: EnvelopeRow, env: Env, userId: string): Promise<Record<string, unknown>> {
  if (!EXPORT_ID.test(row.exportId) || !OBJECT_KEY.test(row.objectKey) ||
      !Number.isSafeInteger(row.byteCount) || row.byteCount < 1 || row.byteCount > 25 * 1024 * 1024) {
    throw new HttpError(503, "unavailable_data", "A retained export is unavailable.");
  }
  const objectData = await env.EXPORTS.get(row.objectKey);
  if (!objectData) throw new HttpError(503, "unavailable_data", "A retained export is unavailable.");
  const encrypted = new Uint8Array(await objectData.arrayBuffer());
  const key = parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON).get(row.keyId);
  if (!key || encrypted.byteLength > MAX_OBJECT_BYTES) {
    throw new HttpError(503, "unavailable_data", "A retained export is unavailable.");
  }
  try {
    const plaintext = await decryptExport(encrypted, key, userId, row.exportId);
    if (plaintext.byteLength !== row.byteCount || await sha256Hex(plaintext) !== row.digest) throw new Error("integrity");
    const envelope = object(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(plaintext)));
    if (envelope?.schema !== "healthmd.api_export" || ![1, 2].includes(Number(envelope.schema_version)) ||
        envelope.schema_version !== row.envelopeVersion || envelope.source !== row.source ||
        envelope.daily_record_schema_version !== row.dailyVersion ||
        !Array.isArray(envelope.records) || envelope.records.length !== row.recordCount) throw new Error("metadata");
    return envelope;
  } catch { throw new HttpError(503, "unavailable_data", "A retained export is unavailable."); }
}

async function chartDays(env: Env, userId: string, start: string, end: string,
  metrics: readonly MetricId[], profile: Profile, includePointers: boolean) {
  const dayCount = Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / DAY) + 1;
  const { results } = await env.DB.prepare(`
    SELECT d.owner_date AS date, d.record_index AS recordIndex,
      e.source AS source, e.daily_record_schema_version AS dailyVersion,
      e.id AS exportId, e.object_key AS objectKey, e.encryption_key_id AS keyId,
      e.plaintext_sha256 AS digest, e.byte_count AS byteCount,
      e.envelope_schema_version AS envelopeVersion, e.record_count AS recordCount
    FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
    WHERE d.user_id = ? AND d.owner_date BETWEEN ? AND ?
    ORDER BY d.owner_date ASC LIMIT 31
  `).bind(userId, start, end).all<DayRow>();
  const byDate = new Map(results.map((row) => [row.date, row]));
  const cache = new Map<string, Record<string, unknown>>();
  let bytes = 0;
  const days: Array<{ date: string; status: DayStatus; values: Record<string, number | null>;
    source?: string; dailyVersion?: number; exportId?: string; recordIndex?: number }> = [];
  for (let i = 0; i < dayCount; i++) {
    const date = new Date(Date.parse(`${start}T00:00:00Z`) + i * DAY).toISOString().slice(0, 10);
    const row = byDate.get(date);
    const values = Object.fromEntries(metrics.map((id) => [id, null])) as Record<string, number | null>;
    if (!row) { days.push({ date, status: "not_uploaded", values }); continue; }
    const evidence = includePointers ? { source: row.source, dailyVersion: row.dailyVersion,
      exportId: row.exportId, recordIndex: row.recordIndex } : {};
    if ((profile === "apple_v8" && (row.source !== "ios" || row.dailyVersion !== 8)) ||
        (profile === "android_compat" && row.source !== "android")) {
      days.push({ date, status: "filtered_profile", values, ...evidence }); continue;
    }
    if (row.source !== "ios" || row.dailyVersion !== 8) {
      days.push({ date, status: "unsupported_profile", values, ...evidence }); continue;
    }
    if (!Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0 || row.recordIndex >= row.recordCount) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    let envelope = cache.get(row.exportId);
    if (!envelope) {
      if (!Number.isSafeInteger(row.byteCount) || row.byteCount < 1 ||
          bytes + row.byteCount > MAX_DECRYPTED_BYTES) {
        days.push({ date, status: "read_limit", values, ...evidence }); continue;
      }
      envelope = await readVerifiedEnvelope(row, env, userId);
      bytes += row.byteCount;
      cache.set(row.exportId, envelope);
    }
    const record = object((envelope.records as unknown[])[row.recordIndex]);
    if (record?.schema !== "healthmd.health_data" || record.schema_version !== 8 || record.date !== date) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    days.push({ date, status: "available", values: project(record, metrics), ...evidence });
  }
  return days;
}

export function exploreCatalog(): Response {
  return json({ version: 1, metrics: catalog, profileNote:
    "Reviewed Apple v8 daily summaries only. Android and provider values remain available in original retained JSON." });
}

export async function dashboardTrends(env: Env, userId: string): Promise<Response> {
  const last = await env.DB.prepare(
    "SELECT MAX(owner_date) AS date FROM daily_records WHERE user_id = ?",
  ).bind(userId).first<{ date: string | null }>();
  const end = last?.date ?? null;
  const metrics: MetricId[] = ["steps", "sleep_total", "resting_heart_rate"];
  const selected = catalog.filter((item) => metrics.some((id) => id === item.id));
  if (!end) return json({ version: 1, window: { start: null, end: null }, metrics: selected, days: [] });
  if (!validDate(end)) throw new HttpError(503, "unavailable_data", "Current daily dates are unavailable.");
  const start = new Date(Date.parse(`${end}T00:00:00Z`) - 29 * DAY).toISOString().slice(0, 10);
  return json({ version: 1, window: { start, end }, metrics: selected,
    days: await chartDays(env, userId, start, end, metrics, "all", false) });
}

export async function exploreChart(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const body = await readJson<{ start?: unknown; end?: unknown; metrics?: unknown; profile?: unknown }>(request);
  if (!validDate(body?.start) || !validDate(body?.end)) {
    throw new HttpError(400, "invalid_date", "Use valid dates in YYYY-MM-DD format.");
  }
  const count = Math.round((Date.parse(`${body.end}T00:00:00Z`) - Date.parse(`${body.start}T00:00:00Z`)) / DAY) + 1;
  if (count < 1 || count > 31) throw new HttpError(400, "invalid_range", "Choose 1–31 calendar days.");
  if (!Array.isArray(body.metrics) || body.metrics.length < 1 || body.metrics.length > projections.length ||
      new Set(body.metrics).size !== body.metrics.length ||
      !body.metrics.every((id: unknown) => projections.some((binding) => binding.id === id))) {
    throw new HttpError(400, "invalid_metrics", "Choose distinct, reviewed Apple daily metrics.");
  }
  if (body.profile !== "all" && body.profile !== "apple_v8" && body.profile !== "android_compat") {
    throw new HttpError(400, "invalid_profile", "Choose a supported source/schema filter.");
  }
  const metrics = body.metrics as MetricId[];
  return json({ version: 1, window: { start: body.start, end: body.end },
    catalog, metrics: metrics.map((id) => catalog.find((item) => item.id === id)), profile: body.profile,
    days: await chartDays(env, userId, body.start, body.end, metrics, body.profile as Profile, true) });
}
