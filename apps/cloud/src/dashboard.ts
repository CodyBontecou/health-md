import { decryptExport, parseExportKeyring, sha256Hex } from "./crypto";
import { HttpError, json } from "./http";
import type { Env } from "./types";
import registry from "../../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json" with { type: "json" };

// Internal, owner-session-only view: three verified Apple-v8 daily summary
// projections. Do not map Android v4 or provider statistics onto these IDs.
const projections = [
  { id: "steps", section: "activity", field: "steps", key: "steps", divisor: 1 },
  { id: "sleep_total", section: "sleep", field: "totalDuration", key: "sleep_total_hours", divisor: 3600 },
  { id: "resting_heart_rate", section: "heart", field: "restingHeartRate", key: "resting_heart_rate", divisor: 1 },
] as const;
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

type Values = Record<(typeof projections)[number]["id"], number | null>;
type DayStatus = "not_uploaded" | "available" | "unsupported_profile" | "read_limit";
interface Row {
  date: string; recordIndex: number; source: string; dailyVersion: number;
  exportId: string; objectKey: string; keyId: string; digest: string;
  byteCount: number; envelopeVersion: number; recordCount: number;
}
function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
function emptyValues(): Values { return { steps: null, sleep_total: null, resting_heart_rate: null }; }
function project(record: Record<string, unknown>): Values {
  const values = emptyValues();
  const units = object(record.units);
  const timezone = object(record.time_context)?.calendar_timezone;
  // Refuse to present a daily value whose owner-day context or unit is not
  // proven. Zero remains a genuine measured zero; absence remains null.
  if (typeof timezone !== "string" || !/^[A-Za-z0-9_+\/-]{1,64}$/u.test(timezone)) return values;
  for (const [index, metric] of projections.entries()) {
    const raw = object(record[metric.section])?.[metric.field];
    if (typeof raw === "number" && Number.isFinite(raw) && units?.[metric.key] === catalog[index]!.unit) {
      values[metric.id] = raw / metric.divisor;
    }
  }
  return values;
}

// A bad/missing encrypted object is an error, never an invented empty day.
async function readEnvelope(row: Row, env: Env, userId: string): Promise<Record<string, unknown>> {
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

export async function dashboardTrends(env: Env, userId: string): Promise<Response> {
  const last = await env.DB.prepare(
    "SELECT MAX(owner_date) AS date FROM daily_records WHERE user_id = ?",
  ).bind(userId).first<{ date: string | null }>();
  const end = last?.date ?? null;
  if (!end) return json({ version: 1, window: { start: null, end: null }, metrics: catalog, days: [] });
  if (!DATE.test(end) || !Number.isFinite(Date.parse(`${end}T00:00:00Z`))) {
    throw new HttpError(503, "unavailable_data", "Current daily dates are unavailable.");
  }
  const endTime = Date.parse(`${end}T00:00:00Z`);
  const start = new Date(endTime - 29 * DAY).toISOString().slice(0, 10);
  const { results } = await env.DB.prepare(`
    SELECT d.owner_date AS date, d.record_index AS recordIndex,
      e.source AS source, e.daily_record_schema_version AS dailyVersion,
      e.id AS exportId, e.object_key AS objectKey, e.encryption_key_id AS keyId,
      e.plaintext_sha256 AS digest, e.byte_count AS byteCount,
      e.envelope_schema_version AS envelopeVersion, e.record_count AS recordCount
    FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
    WHERE d.user_id = ? AND d.owner_date BETWEEN ? AND ?
    ORDER BY d.owner_date ASC LIMIT 30
  `).bind(userId, start, end).all<Row>();
  const byDate = new Map(results.map((row) => [row.date, row]));
  const cache = new Map<string, Record<string, unknown>>();
  let bytes = 0;
  const days: Array<{ date: string; status: DayStatus; values: Values }> = [];
  for (let i = 0; i < 30; i++) {
    const date = new Date(endTime - (29 - i) * DAY).toISOString().slice(0, 10);
    const row = byDate.get(date);
    if (!row) { days.push({ date, status: "not_uploaded", values: emptyValues() }); continue; }
    if (row.source !== "ios" || row.dailyVersion !== 8) {
      days.push({ date, status: "unsupported_profile", values: emptyValues() }); continue;
    }
    if (!Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0 || row.recordIndex >= row.recordCount) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    let envelope = cache.get(row.exportId);
    if (!envelope) {
      if (!Number.isSafeInteger(row.byteCount) || row.byteCount < 1 ||
          bytes + row.byteCount > MAX_DECRYPTED_BYTES) {
        days.push({ date, status: "read_limit", values: emptyValues() }); continue;
      }
      envelope = await readEnvelope(row, env, userId);
      bytes += row.byteCount;
      cache.set(row.exportId, envelope);
    }
    const record = object((envelope.records as unknown[])[row.recordIndex]);
    if (record?.schema !== "healthmd.health_data" || record.schema_version !== 8 || record.date !== date) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    days.push({ date, status: "available", values: project(record) });
  }
  return json({ version: 1, window: { start, end }, metrics: catalog, days });
}
