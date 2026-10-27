import { decodeBase64, encodeBase64, keyedLookup } from "./crypto";
import { object, project, readVerifiedEnvelope, validDate, type EnvelopeRow } from "./dashboard";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { parseRepairSpec, type RepairDraftSpec } from "./repair-drafts";
import type { Env } from "./types";

const MAX_READ_BYTES = 48 * 1024 * 1024;
const PAGE_SIZE = 10;
const text = new TextEncoder();
interface StoredSpec { specCiphertext: string; specIv: string; scopeDigest: string }
interface ProvenanceRow extends EnvelopeRow, StoredSpec {
  exportId: string; dateStart: string; dateEnd: string; exportedAt: string; receivedAt: string;
  failureCount: number; recordIndex: number | null; captureStatus: string | null;
}
interface PrimaryRow extends EnvelopeRow {
  exportId: string; recordIndex: number; captureStatus: string | null;
}
const exportFields = `e.id AS exportId, e.source AS source,
  e.daily_record_schema_version AS dailyVersion, e.object_key AS objectKey,
  e.encryption_key_id AS keyId, e.plaintext_sha256 AS digest,
  e.byte_count AS byteCount, e.envelope_schema_version AS envelopeVersion,
  e.record_count AS recordCount`;

async function specKey(env: Env): Promise<CryptoKey> {
  const root = await crypto.subtle.importKey("raw", Uint8Array.from(decodeBase64(env.IDENTITY_KEY_B64)).buffer,
    "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256",
    salt: text.encode("healthmd.cloud.supplement-salt.v1"),
    info: text.encode("healthmd.cloud.supplement-key.v1") }, root,
  { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
function aad(userId: string, exportId: string): Uint8Array {
  return text.encode(`healthmd.cloud.supplement.v1\0${userId}\0${exportId}`);
}
export async function supplementScopeDigest(spec: RepairDraftSpec, env: Env): Promise<string> {
  // Normalized, purpose-keyed digest for idempotency. No date/metric list in
  // plaintext metadata, URLs, logs or device-readable receipts.
  return keyedLookup(JSON.stringify(parseRepairSpec(spec)), env.IDENTITY_KEY_B64, "supplement-scope-v1");
}
export async function encryptSupplementSpec(spec: RepairDraftSpec, env: Env, userId: string,
  exportId: string): Promise<StoredSpec> {
  const normalized = parseRepairSpec(spec);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv,
    additionalData: Uint8Array.from(aad(userId, exportId)) }, await specKey(env),
  Uint8Array.from(text.encode(JSON.stringify(normalized)))));
  return { specCiphertext: encodeBase64(ciphertext), specIv: encodeBase64(iv),
    scopeDigest: await supplementScopeDigest(normalized, env) };
}
async function decryptSpec(row: StoredSpec & { exportId: string }, env: Env, userId: string): Promise<RepairDraftSpec> {
  try {
    const bytes = await crypto.subtle.decrypt({ name: "AES-GCM",
      iv: Uint8Array.from(decodeBase64(row.specIv)),
      additionalData: Uint8Array.from(aad(userId, row.exportId)) },
    await specKey(env), Uint8Array.from(decodeBase64(row.specCiphertext)).buffer);
    const spec = parseRepairSpec(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
    if (await supplementScopeDigest(spec, env) !== row.scopeDigest) throw new Error("scope");
    return spec;
  } catch { throw new HttpError(503, "unavailable_data", "Supplement provenance is unavailable."); }
}
function evidence(values: Record<string, number | null>) {
  return Object.fromEntries(Object.entries(values).map(([metricId, value]) => [metricId,
    typeof value === "number" ? { status: "observed", value } :
      { status: "value_unavailable_in_uploaded_summary", value: null }]));
}
async function dayEvidence(row: EnvelopeRow & { exportId: string; recordIndex: number },
  date: string, metricIds: readonly string[], env: Env, userId: string) {
  if (!Number.isSafeInteger(row.recordIndex) || row.recordIndex < 0 || row.recordIndex >= row.recordCount) {
    throw new HttpError(503, "unavailable_data", "Supplement record is unavailable.");
  }
  const envelope = await readVerifiedEnvelope(row, env, userId);
  const record = object((envelope.records as unknown[])[row.recordIndex]);
  if (record?.schema !== "healthmd.health_data" || record.schema_version !== row.dailyVersion ||
      record.date !== date) throw new HttpError(503, "unavailable_data", "Supplement record is unavailable.");
  const zone = object(record.time_context)?.calendar_timezone;
  const calendarTimezone = typeof zone === "string" && /^[A-Za-z0-9_+\/-]{1,64}$/u.test(zone) ?
    zone : null;
  if (row.source !== "ios" || row.dailyVersion !== 8 || metricIds.length === 0) {
    return { status: row.source === "ios" && row.dailyVersion === 8 ? "retained" : "unsupported_profile",
      calendarTimezone, metrics: {} };
  }
  return { status: "reviewed_apple_v8", calendarTimezone,
    metrics: evidence(project(record, metricIds as Parameters<typeof project>[1])) };
}

// Owner-only original-provenance view. Never merges a narrow supplement into
// the primary chart or projects Android/provider statistics as Apple metrics.
// Even a failure-only envelope is discoverable for dates in its declared range;
// its failed-date timestamps are NOT assumed to be logical owner dates.
export async function readSupplementEvidence(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<{ date?: unknown; offset?: unknown }>(request, 512);
  if (!validDate(input?.date) || !Number.isSafeInteger(input.offset) ||
      (input.offset as number) < 0 || (input.offset as number) > 1_000_000) {
    throw new HttpError(400, "invalid_evidence_request", "Choose a valid owner day and page offset.");
  }
  const date = input.date;
  const offset = input.offset as number;
  const [primary, found] = await Promise.all([
    env.DB.prepare(`SELECT ${exportFields}, d.record_index AS recordIndex,
      d.capture_status AS captureStatus FROM daily_records d
      JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
      WHERE d.user_id = ? AND d.owner_date = ?`).bind(userId, date).first<PrimaryRow>(),
    env.DB.prepare(`SELECT ${exportFields}, e.date_start AS dateStart, e.date_end AS dateEnd,
      e.exported_at AS exportedAt, e.received_at AS receivedAt,
      e.failure_count AS failureCount, r.record_index AS recordIndex,
      r.capture_status AS captureStatus,
      s.spec_ciphertext AS specCiphertext, s.spec_iv AS specIv, s.scope_digest AS scopeDigest
      FROM supplemental_exports s JOIN exports e ON e.id = s.export_id AND e.user_id = s.user_id
      LEFT JOIN supplemental_records r ON r.export_id = s.export_id AND r.user_id = s.user_id
        AND r.owner_date = ?
      WHERE s.user_id = ? AND e.date_start <= ? AND e.date_end >= ?
      ORDER BY s.created_at DESC, e.id DESC LIMIT ? OFFSET ?`)
      .bind(date, userId, date, date, PAGE_SIZE + 1, offset).all<ProvenanceRow>(),
  ]);
  const page = found.results.slice(0, PAGE_SIZE);
  let bytes = 0;
  const selections = await Promise.all(page.map(async (row) => {
    const spec = await decryptSpec(row, env, userId);
    if (spec.source !== row.source || !spec.dates.includes(date)) {
      throw new HttpError(503, "unavailable_data", "Supplement provenance is unavailable.");
    }
    return { row, spec };
  }));
  const selected = [...new Set(selections.flatMap(({ spec }) => spec.metricIds))].sort();
  let current: Record<string, unknown> | null = null;
  if (primary) {
    const primaryMetadata = { exportId: primary.exportId, pointer: `/records/${primary.recordIndex}`,
      source: primary.source, dailyVersion: primary.dailyVersion, captureStatus: primary.captureStatus };
    if (bytes + primary.byteCount > MAX_READ_BYTES) {
      current = { ...primaryMetadata, status: "read_limit", metrics: {} };
    } else {
      const detail = await dayEvidence(primary, date, selected, env, userId);
      bytes += primary.byteCount;
      current = { ...primaryMetadata, ...detail };
    }
  }
  const supplements = [];
  for (const { row, spec } of selections) {
    const base = { exportId: row.exportId, pointer: row.recordIndex === null ? null : `/records/${row.recordIndex}`,
      source: row.source, dailyVersion: row.dailyVersion, scope: spec.scope,
      metricIds: spec.metricIds, detail: spec.detail, captureStatus: row.captureStatus,
      exportedAt: row.exportedAt, receivedAt: row.receivedAt,
      failureCount: row.failureCount, recordIndex: row.recordIndex };
    if (bytes + row.byteCount > MAX_READ_BYTES) {
      supplements.push({ ...base, status: "read_limit", metrics: {} });
    } else if (row.recordIndex === null) {
      const envelope = await readVerifiedEnvelope(row, env, userId);
      if (!Array.isArray(envelope.failed_date_details) ||
          envelope.failed_date_details.length !== row.failureCount ||
          (envelope.records as unknown[]).some((item) => object(item)?.date === date)) {
        throw new HttpError(503, "unavailable_data", "Supplement record is unavailable.");
      }
      bytes += row.byteCount;
      supplements.push({ ...base, status: "no_retained_record_for_day", metrics: {} });
    } else {
      const detail = await dayEvidence(row as ProvenanceRow & { recordIndex: number }, date,
        spec.metricIds, env, userId);
      bytes += row.byteCount;
      supplements.push({ ...base, ...detail });
    }
  }
  return json({ version: 1, date, primary: current, supplements,
    nextOffset: found.results.length > PAGE_SIZE ? offset + PAGE_SIZE : null,
    note: "Primary and supplements remain separate. Null is unavailable, not zero; no retained record or a failed date does not prove the phone had no reading. Failure counts describe the whole envelope, not this owner day. Inspect exact original JSON by export ID." });
}
