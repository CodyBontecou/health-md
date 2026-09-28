import { audit, limitIngest, requireIngestToken } from "./auth";
import { decryptExport, encryptExport, parseExportKeyring, sha256Hex } from "./crypto";
import { EnvelopeValidationError, parseAndValidateEnvelope } from "./envelope";
import { assertJsonContentType, HttpError, json, parsePositiveInteger, readBoundedBody } from "./http";
import type { Env, EnvelopeInfo } from "./types";

const MAX_ACCOUNT_BYTES = 1_073_741_824; // pilot quota; not a strict concurrent reservation

interface ExportRow {
  id: string;
  objectKey: string;
  encryptionKeyId: string;
  plaintextSha256: string;
  byteCount: number;
  envelopeSchemaVersion: number;
  dailyRecordSchemaVersion: number;
  source: string;
  exportedAt: string;
  receivedAt: string;
  dateStart: string;
  dateEnd: string;
  recordCount: number;
  failureCount: number;
  externalRecordCount: number;
}

function insertExport(env: Env, userId: string, tokenId: string, exportId: string, objectKey: string, keyId: string,
  digest: string, bytes: number, info: EnvelopeInfo, receivedAt: string): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO exports (
       id, user_id, object_key, encryption_key_id, plaintext_sha256, byte_count,
       envelope_schema_version, daily_record_schema_version, source, exported_at,
       received_at, date_start, date_end, record_count, failure_count, external_record_count
     ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM ingest_tokens t JOIN users u ON u.id = t.user_id
         WHERE u.id = ? AND t.id = ? AND u.status = 'active' AND t.revoked_at IS NULL)`,
  ).bind(exportId, userId, objectKey, keyId, digest, bytes, info.envelopeSchemaVersion,
    info.dailyRecordSchemaVersion, info.source, info.exportedAt, receivedAt, info.dateStart,
    info.dateEnd, info.recordCount, info.failureCount, info.externalRecordCount, userId, tokenId);
}

export async function ingest(request: Request, env: Env): Promise<Response> {
  const principal = await requireIngestToken(request, env);
  await limitIngest(env, principal.tokenId);
  assertJsonContentType(request);
  const maximumBytes = parsePositiveInteger(env.MAX_EXPORT_BYTES, "MAX_EXPORT_BYTES", 1024, 25 * 1024 * 1024);
  const body = await readBoundedBody(request, maximumBytes);
  let info: EnvelopeInfo;
  try {
    info = parseAndValidateEnvelope(body);
  } catch (error) {
    if (error instanceof EnvelopeValidationError) {
      throw new HttpError(422, "invalid_envelope", error.message);
    }
    throw error;
  }
  const keyring = parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON);
  const keyId = env.CURRENT_EXPORT_KEY_ID;
  const rootKey = keyring.get(keyId);
  if (!rootKey) throw new Error("Current export encryption key is not configured");
  const digest = await sha256Hex(body);
  const existing = await env.DB.prepare(
    `SELECT e.id FROM exports e JOIN users u ON u.id = e.user_id
     WHERE e.user_id = ? AND e.plaintext_sha256 = ? AND u.status = 'active' LIMIT 1`,
  ).bind(principal.userId, digest).first<{ id: string }>();
  if (existing) return json({ accepted: true, duplicate: true, id: existing.id });
  const usage = await env.DB.prepare(
    "SELECT COALESCE(SUM(byte_count), 0) AS bytes FROM exports WHERE user_id = ?",
  ).bind(principal.userId).first<{ bytes: number }>();
  if ((usage?.bytes ?? 0) + body.byteLength > MAX_ACCOUNT_BYTES) {
    throw new HttpError(413, "account_quota", "Account export storage quota reached.");
  }
  const exportId = crypto.randomUUID();
  const objectKey = `v1/${crypto.randomUUID()}`;
  const ciphertext = await encryptExport(body, rootKey, principal.userId, exportId);
  const receivedAt = new Date().toISOString();
  await env.EXPORTS.put(objectKey, ciphertext, {
    httpMetadata: { contentType: "application/octet-stream", cacheControl: "no-store" },
  });
  const statements: D1PreparedStatement[] = [
    insertExport(env, principal.userId, principal.tokenId, exportId, objectKey, keyId, digest, body.byteLength, info, receivedAt),
    ...info.dailyRecords.map((record) => env.DB.prepare(
      `INSERT INTO daily_records (
         user_id, owner_date, export_id, record_index, schema_version, capture_status, exported_at, received_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, owner_date) DO UPDATE SET
         export_id = excluded.export_id,
         record_index = excluded.record_index,
         schema_version = excluded.schema_version,
         capture_status = excluded.capture_status,
         exported_at = excluded.exported_at,
         received_at = excluded.received_at
       WHERE excluded.exported_at > daily_records.exported_at OR
         (excluded.exported_at = daily_records.exported_at AND excluded.received_at > daily_records.received_at)`,
    ).bind(principal.userId, record.date, exportId, record.index, record.schemaVersion,
      record.captureStatus, info.exportedAt, receivedAt)),
    env.DB.prepare(
      "UPDATE ingest_tokens SET last_used_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
    ).bind(receivedAt, principal.tokenId, principal.userId),
    env.DB.prepare(
      `INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
       SELECT ?, ?, ?, ?, ? FROM exports WHERE id = ?`,
    ).bind(crypto.randomUUID(), principal.userId, "export.accepted", exportId, receivedAt, exportId),
  ];
  try {
    // D1 batch is transactional; a failed metadata commit does not acknowledge the payload.
    const results = await env.DB.batch(statements);
    if (results[0]?.meta.changes !== 1) {
      throw new HttpError(401, "unauthorized", "Export token is no longer active.");
    }
  } catch (error) {
    try {
      await env.EXPORTS.delete(objectKey);
    } catch {
      // Reconcile orphaned encrypted objects before production deployment.
    }
    const concurrentDuplicate = await env.DB.prepare(
      `SELECT e.id FROM exports e JOIN users u ON u.id = e.user_id
       WHERE e.user_id = ? AND e.plaintext_sha256 = ? AND u.status = 'active' LIMIT 1`,
    ).bind(principal.userId, digest).first<{ id: string }>();
    if (concurrentDuplicate) {
      return json({ accepted: true, duplicate: true, id: concurrentDuplicate.id });
    }
    throw error;
  }
  return json({ accepted: true, duplicate: false, id: exportId, records: info.recordCount }, { status: 201 });
}

export async function listExports(env: Env, userId: string): Promise<Response> {
  const [exports, days, storage] = await Promise.all([
    env.DB.prepare(
      `SELECT id, byte_count AS byteCount, envelope_schema_version AS envelopeSchemaVersion,
              daily_record_schema_version AS dailyRecordSchemaVersion, source,
              exported_at AS exportedAt, received_at AS receivedAt, date_start AS dateStart,
              date_end AS dateEnd, record_count AS recordCount, failure_count AS failureCount,
              external_record_count AS externalRecordCount
       FROM exports WHERE user_id = ? ORDER BY received_at DESC, id DESC LIMIT 50`,
    ).bind(userId).all(),
    env.DB.prepare(
      `SELECT owner_date AS date, schema_version AS schemaVersion, capture_status AS captureStatus,
              exported_at AS exportedAt, received_at AS receivedAt
       FROM daily_records WHERE user_id = ? ORDER BY owner_date DESC LIMIT 50`,
    ).bind(userId).all(),
    env.DB.prepare(
      "SELECT COUNT(*) AS count, COALESCE(SUM(byte_count), 0) AS bytes FROM exports WHERE user_id = ?",
    ).bind(userId).first<{ count: number; bytes: number }>(),
  ]);
  return json({ exports: exports.results, days: days.results, storage: storage ?? { count: 0, bytes: 0 },
    nextExportOffset: exports.results.length === 50 ? 50 : null,
    nextDayOffset: days.results.length === 50 ? 50 : null });
}

// Bounded owner-only navigation of retained metadata. The inventory is not a
// snapshot across concurrent uploads/deletions; the MCP cursor handles agent
// discovery separately. No raw health readings appear in these responses.
export async function listExportPage(env: Env, userId: string, offset: number): Promise<Response> {
  if (!Number.isInteger(offset) || offset < 0 || offset > 1_000_000) {
    throw new HttpError(400, "invalid_page", "Invalid export page.");
  }
  const result = await env.DB.prepare(
    `SELECT id, byte_count AS byteCount, envelope_schema_version AS envelopeSchemaVersion,
            daily_record_schema_version AS dailyRecordSchemaVersion, source,
            exported_at AS exportedAt, received_at AS receivedAt, date_start AS dateStart,
            date_end AS dateEnd, record_count AS recordCount, failure_count AS failureCount,
            external_record_count AS externalRecordCount
     FROM exports WHERE user_id = ? ORDER BY received_at DESC, id DESC LIMIT 51 OFFSET ?`,
  ).bind(userId, offset).all();
  return json({ exports: result.results.slice(0, 50),
    nextOffset: result.results.length > 50 ? offset + 50 : null });
}

export async function listDayPage(env: Env, userId: string, offset: number): Promise<Response> {
  if (!Number.isInteger(offset) || offset < 0 || offset > 1_000_000) {
    throw new HttpError(400, "invalid_page", "Invalid day page.");
  }
  const result = await env.DB.prepare(
    `SELECT owner_date AS date, schema_version AS schemaVersion, capture_status AS captureStatus,
            exported_at AS exportedAt, received_at AS receivedAt
     FROM daily_records WHERE user_id = ? ORDER BY owner_date DESC LIMIT 51 OFFSET ?`,
  ).bind(userId, offset).all();
  return json({ days: result.results.slice(0, 50),
    nextOffset: result.results.length > 50 ? offset + 50 : null });
}

export async function downloadExport(env: Env, userId: string, exportId: string): Promise<Response> {
  if (!/^[a-f0-9-]{36}$/u.test(exportId)) throw new HttpError(404, "not_found", "Export not found.");
  const row = await env.DB.prepare(
    `SELECT id, object_key AS objectKey, encryption_key_id AS encryptionKeyId,
            plaintext_sha256 AS plaintextSha256, byte_count AS byteCount
     FROM exports WHERE id = ? AND user_id = ?`,
  ).bind(exportId, userId).first<Pick<ExportRow,
    "id" | "objectKey" | "encryptionKeyId" | "plaintextSha256" | "byteCount">>();
  if (!row) throw new HttpError(404, "not_found", "Export not found.");
  const object = await env.EXPORTS.get(row.objectKey);
  if (!object) throw new Error("Encrypted export object is unavailable");
  const key = parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON).get(row.encryptionKeyId);
  if (!key) throw new Error("Encrypted export key is unavailable");
  const plaintext = await decryptExport(new Uint8Array(await object.arrayBuffer()), key, userId, row.id);
  if (plaintext.byteLength !== row.byteCount || await sha256Hex(plaintext) !== row.plaintextSha256) {
    throw new Error("Stored export integrity check failed");
  }
  await audit(env, userId, "export.downloaded", exportId);
  return new Response(Uint8Array.from(plaintext).buffer, {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="healthmd-export-${exportId}.json"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "Content-Security-Policy": "default-src 'none'; sandbox",
    },
  });
}
