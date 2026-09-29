import { decodeBase64, encodeBase64 } from "./crypto";
import { object, project, readVerifiedEnvelope, validDate, type EnvelopeRow } from "./dashboard";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import type { Env } from "./types";

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
const DAY = 86_400_000;
const MAX_READ_BYTES = 48 * 1024 * 1024;
const TTL_MS = DAY;
const METRICS = new Set(["steps", "active_energy", "heart_rate_avg", "heart_rate_min",
  "heart_rate_max", "resting_heart_rate", "hrv", "sleep_total", "sleep_deep", "sleep_rem", "weight"]);
type Source = "ios" | "android";
type Detail = "summary" | "time_series" | "lossless";
type Scope = "metric_ids" | "entire_days";
export interface RepairDraftSpec {
  source: Source;
  dates: string[];
  scope: Scope;
  metricIds: string[];
  detail: Detail;
}
interface DraftRow { id: string; userId: string; source: Source; dayCount: number;
  specCiphertext: string; specIv: string; state: string; createdAt: string; expiresAt: string }
interface CurrentRow extends EnvelopeRow { date: string; recordIndex: number }
const fields = `d.owner_date AS date, d.record_index AS recordIndex,
  e.id AS exportId, e.source AS source, e.daily_record_schema_version AS dailyVersion,
  e.object_key AS objectKey, e.encryption_key_id AS keyId, e.plaintext_sha256 AS digest,
  e.byte_count AS byteCount, e.envelope_schema_version AS envelopeVersion,
  e.record_count AS recordCount`;

export function parseRepairSpec(input: unknown): RepairDraftSpec {
  const data = object(input);
  if (!data || (data.source !== "ios" && data.source !== "android") ||
      (data.scope !== "entire_days" && data.scope !== "metric_ids") ||
      (data.detail !== "summary" && data.detail !== "time_series" && data.detail !== "lossless") ||
      !Array.isArray(data.dates) || data.dates.length < 1 || data.dates.length > 31 ||
      !data.dates.every(validDate) || new Set(data.dates).size !== data.dates.length ||
      data.dates.some((day: string) => day > new Date(Date.now() + DAY).toISOString().slice(0, 10)) ||
      !Array.isArray(data.metricIds) || data.metricIds.length > METRICS.size ||
      !data.metricIds.every((id: unknown) => typeof id === "string" && METRICS.has(id)) ||
      new Set(data.metricIds).size !== data.metricIds.length ||
      (data.scope === "metric_ids" && (data.source !== "ios" || data.metricIds.length === 0)) ||
      (data.scope === "entire_days" && data.metricIds.length !== 0) ||
      (data.source === "android" && data.detail === "lossless")) {
    throw new HttpError(400, "invalid_repair_scope", "Choose 1–31 distinct days and a supported source, detail and metric scope.");
  }
  // Never persist arbitrary fields, names, bearer credentials, URLs or notes.
  return { source: data.source as Source, dates: [...data.dates].sort() as string[],
    scope: data.scope as Scope, metricIds: [...data.metricIds].sort() as string[], detail: data.detail as Detail };
}

async function requestKey(env: Env): Promise<CryptoKey> {
  const root = await crypto.subtle.importKey("raw", Uint8Array.from(decodeBase64(env.IDENTITY_KEY_B64)).buffer,
    "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256",
    salt: new TextEncoder().encode("healthmd.cloud.repair-draft.salt.v1"),
    info: new TextEncoder().encode("healthmd.cloud.repair-draft.key.v1") }, root,
  { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
function aad(userId: string, id: string): Uint8Array {
  return new TextEncoder().encode(`healthmd.cloud.repair-draft.v1\0${userId}\0${id}`);
}
async function encryptSpec(spec: RepairDraftSpec, env: Env, userId: string, id: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv,
    additionalData: Uint8Array.from(aad(userId, id)) }, await requestKey(env),
  Uint8Array.from(new TextEncoder().encode(JSON.stringify(spec)))));
  return { ciphertext: encodeBase64(ciphertext), iv: encodeBase64(iv) };
}
async function decryptSpec(row: DraftRow, env: Env, userId: string): Promise<RepairDraftSpec> {
  try {
    const bytes = await crypto.subtle.decrypt({ name: "AES-GCM",
      iv: Uint8Array.from(decodeBase64(row.specIv)), additionalData: Uint8Array.from(aad(userId, row.id)) },
    await requestKey(env), Uint8Array.from(decodeBase64(row.specCiphertext)).buffer);
    const spec = parseRepairSpec(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
    if (spec.source !== row.source || spec.dates.length !== row.dayCount) throw new Error("mismatch");
    return spec;
  } catch { throw new HttpError(503, "unavailable_data", "A saved request is unavailable."); }
}

export async function previewRepair(spec: RepairDraftSpec, env: Env, userId: string): Promise<Response> {
  const placeholders = spec.dates.map(() => "?").join(", ");
  const { results } = await env.DB.prepare(`SELECT ${fields} FROM daily_records d
    JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
    WHERE d.user_id = ? AND d.owner_date IN (${placeholders}) ORDER BY d.owner_date ASC LIMIT 31`)
    .bind(userId, ...spec.dates).all<CurrentRow>();
  const byDate = new Map(results.map((row) => [row.date, row]));
  let bytes = 0;
  const cache = new Map<string, Record<string, unknown>>();
  const days = [];
  for (const date of spec.dates) {
    const row = byDate.get(date);
    if (!row) { days.push({ date, coverage: "not_uploaded", safety: "new_day_only",
      metrics: Object.fromEntries(spec.metricIds.map((id) => [id, "no_uploaded_day"])) }); continue; }
    const base = { date, source: row.source, dailyVersion: row.dailyVersion,
      safety: row.source !== spec.source ? "source_conflict" : "existing_day_requires_review" };
    if (row.source !== spec.source) { days.push({ ...base, coverage: "different_source", metrics: {} }); continue; }
    if (spec.scope === "entire_days") { days.push({ ...base, coverage: "uploaded_day", metrics: {} }); continue; }
    if (row.source !== "ios" || row.dailyVersion !== 8) {
      days.push({ ...base, coverage: "unsupported_profile", metrics: {} }); continue;
    }
    if (!Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0 || row.recordIndex >= row.recordCount) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    if (!cache.has(row.exportId)) {
      if (!Number.isSafeInteger(row.byteCount) || bytes + row.byteCount > MAX_READ_BYTES) {
        days.push({ ...base, coverage: "read_limit", metrics: {} }); continue;
      }
      cache.set(row.exportId, await readVerifiedEnvelope(row, env, userId));
      bytes += row.byteCount;
    }
    const record = object((cache.get(row.exportId)!.records as unknown[])[row.recordIndex]);
    if (record?.schema !== "healthmd.health_data" || record.schema_version !== 8 || record.date !== date) {
      throw new HttpError(503, "unavailable_data", "A retained daily record is unavailable.");
    }
    const values = project(record, spec.metricIds as Parameters<typeof project>[1]);
    days.push({ ...base, coverage: "uploaded_day",
      metrics: Object.fromEntries(spec.metricIds.map((id) => [id, typeof values[id] === "number" ?
        "observed" : "value_unavailable_in_uploaded_summary"])) });
  }
  return json({ version: 1, spec, days, launchable: false,
    note: "Saved scopes cannot start a phone export. Existing days require a reviewed non-replacing supplemental path. No phone was queried." });
}

export async function previewRepairRequest(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  return previewRepair(parseRepairSpec(await readJson<unknown>(request, 4096)), env, userId);
}
export async function createRepairDraft(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  if (env.SYNTHETIC_PREVIEW_ONLY === "1") {
    throw new HttpError(403, "preview_no_drafts", "This synthetic preview cannot save requests.");
  }
  const spec = parseRepairSpec(await readJson<unknown>(request, 4096));
  const id = crypto.randomUUID();
  const createdAt = new Date().toISOString();
  const expiresAt = new Date(Date.now() + TTL_MS).toISOString();
  const encrypted = await encryptSpec(spec, env, userId, id);
  const result = await env.DB.prepare(`INSERT INTO repair_drafts
    (id, user_id, spec_ciphertext, spec_iv, source, day_count, state, created_at, expires_at)
    SELECT ?, ?, ?, ?, ?, ?, 'draft', ?, ? WHERE (
      SELECT COUNT(*) FROM repair_drafts WHERE user_id = ? AND state = 'draft' AND expires_at > ?
    ) < 10`).bind(id, userId, encrypted.ciphertext, encrypted.iv, spec.source, spec.dates.length,
      createdAt, expiresAt, userId, createdAt).run();
  if (!result.meta.changes) throw new HttpError(409, "draft_limit", "Cancel or wait for a saved draft to expire.");
  return json({ id, state: "draft", spec, createdAt, expiresAt, launchable: false }, { status: 201 });
}
export async function listRepairDrafts(env: Env, userId: string): Promise<Response> {
  const { results } = await env.DB.prepare(`SELECT id, user_id AS userId, spec_ciphertext AS specCiphertext,
    spec_iv AS specIv, source, day_count AS dayCount, state, created_at AS createdAt,
    expires_at AS expiresAt FROM repair_drafts WHERE user_id = ? AND state = 'draft' AND expires_at > ?
    ORDER BY created_at DESC, id DESC LIMIT 10`).bind(userId, new Date().toISOString()).all<DraftRow>();
  return json({ requests: await Promise.all(results.map(async (row) => ({ id: row.id,
    spec: await decryptSpec(row, env, userId), state: row.state,
    createdAt: row.createdAt, expiresAt: row.expiresAt, launchable: false }))) });
}
export async function cancelRepairDraft(request: Request, env: Env, userId: string, id: string): Promise<Response> {
  assertSameOrigin(request, env);
  if (!UUID.test(id)) throw new HttpError(404, "not_found", "Draft not found.");
  const now = new Date().toISOString();
  const result = await env.DB.prepare(`UPDATE repair_drafts SET state = 'cancelled',
    cancelled_at = ?, spec_ciphertext = '', spec_iv = ''
    WHERE id = ? AND user_id = ? AND state = 'draft' AND expires_at > ?`)
    .bind(now, id, userId, now).run();
  if (!result.meta.changes) throw new HttpError(404, "not_found", "Draft not found.");
  return json({ cancelled: true });
}
export async function purgeExpiredRepairDrafts(env: Env): Promise<void> {
  await env.DB.prepare("DELETE FROM repair_drafts WHERE expires_at <= ? OR state = 'cancelled'")
    .bind(new Date().toISOString()).run();
}
