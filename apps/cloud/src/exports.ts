import { audit, limitIngest, requireIngestToken } from "./auth";
import { decryptExport, encryptExport, sha256Hex } from "./crypto";
import { currentExportKey, resolveExportKey } from "./account-export-keys";
import { EnvelopeValidationError, parseAndValidateEnvelope } from "./envelope";
import { assertJsonContentType, HttpError, json, parsePositiveInteger, readBoundedBody } from "./http";
import { parseRepairSpec, type RepairDraftSpec } from "./repair-drafts";
import { encryptSupplementSpec, supplementScopeDigest } from "./repair-supplements";
import { abandonUploadIntent, commitUploadIntentStatement, markUploadObjectWritten,
  reserveUploadIntent } from "./upload-intents";
import type { Env, EnvelopeInfo } from "./types";

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
  // Until a separately authenticated, device-bound dispatch and receipt path
  // exists, never mistake a claimed repair header for an ordinary replacement.
  request.headers.forEach((_value, name) => {
    if (name.toLowerCase().startsWith("x-healthmd-repair-")) {
      throw new HttpError(409, "repair_not_enabled", "Repair uploads need a verified request.");
    }
  });
  return ingestMode(request, env, null);
}

// Trusted server-internal path only: no public route passes a client-supplied
// spec here. Step 2 must bind an approved device request before exposing it.
export async function ingestSupplement(request: Request, env: Env, trustedScope: RepairDraftSpec): Promise<Response> {
  return ingestMode(request, env, parseRepairSpec(trustedScope));
}

async function ingestMode(request: Request, env: Env, spec: RepairDraftSpec | null): Promise<Response> {
  const principal = await requireIngestToken(request, env);
  await limitIngest(env, principal.tokenId, principal.userId);
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
  if (spec) {
    const start = Date.parse(`${info.dateStart}T00:00:00Z`);
    const end = Date.parse(`${info.dateEnd}T00:00:00Z`);
    const days = (end - start) / 86_400_000 + 1;
    const allowed = new Set(spec.dates);
    // Failure timestamps are instants, not trustworthy logical owner dates.
    // Allow a one-day UTC margin for a mobile calendar zone, but never label a
    // particular failure as a requested day on this evidence alone.
    const low = new Date(start - 86_400_000).toISOString().slice(0, 10);
    const high = new Date(end + 86_400_000).toISOString().slice(0, 10);
    if (info.source !== spec.source || !Number.isInteger(days) || days < 1 || days > 7 ||
        info.failureTimestamps.some((instant) => instant.slice(0, 10) < low || instant.slice(0, 10) > high) ||
        (info.source === "ios" && info.dailyRecordSchemaVersion !== 8) ||
        (info.source === "android" && ![4, 5].includes(info.dailyRecordSchemaVersion)) ||
        Array.from({ length: days }, (_, i) => new Date(start + i * 86_400_000).toISOString().slice(0, 10))
          .some((date) => !allowed.has(date))) {
      throw new HttpError(422, "scope_mismatch", "Export source, profile or owner-day range does not match the request.");
    }
  }
  const { keyId, key: exportKey } = await currentExportKey(env, principal.userId);
  const digest = await sha256Hex(body);
  const scopeDigest = spec ? await supplementScopeDigest(spec, env) : null;
  const duplicateReceipt = async (): Promise<Response | null> => {
    const existing = await env.DB.prepare(
      `SELECT e.id, s.scope_digest AS scopeDigest FROM exports e JOIN users u ON u.id = e.user_id
       LEFT JOIN supplemental_exports s ON s.export_id = e.id AND s.user_id = e.user_id
       WHERE e.user_id = ? AND e.plaintext_sha256 = ? AND u.status = 'active' LIMIT 1`,
    ).bind(principal.userId, digest).first<{ id: string; scopeDigest: string | null }>();
    if (!existing) return null;
    if (existing.scopeDigest !== scopeDigest) {
      throw new HttpError(409, "scope_conflict", "These bytes were retained under a different export scope.");
    }
    return json({ accepted: true, duplicate: true, id: existing.id,
      ...(spec ? { mode: "supplemental", records: info.recordCount, failureCount: info.failureCount } : {}) });
  };
  const existing = await duplicateReceipt();
  if (existing) return existing;
  let intent: Awaited<ReturnType<typeof reserveUploadIntent>>;
  try {
    intent = await reserveUploadIntent(env, principal, digest, scopeDigest, body.byteLength);
  } catch (error) {
    if (error instanceof HttpError && error.code === "upload_in_progress") {
      // Preserve the existing exact-retry contract without admitting another
      // write. Wait only briefly for the durable winner, then return bounded
      // backpressure so the client can retry the same bytes later.
      for (let attempt = 0; attempt < 20; attempt += 1) {
        await new Promise((done) => setTimeout(done, 100));
        const concurrent = await duplicateReceipt();
        if (concurrent) return concurrent;
      }
    }
    throw error;
  }
  const ciphertext = await encryptExport(body, exportKey, principal.userId, intent.exportId);
  const receivedAt = new Date().toISOString();
  const encryptedSpec = spec ? await encryptSupplementSpec(spec, env, principal.userId, intent.exportId) : null;
  try {
    await env.EXPORTS.put(intent.objectKey, ciphertext, {
      httpMetadata: { contentType: "application/octet-stream", cacheControl: "no-store" },
    });
    await markUploadObjectWritten(env, intent);
  } catch (error) {
    try { await abandonUploadIntent(env, intent); } catch { /* Durable reconciliation retains the reservation. */ }
    throw error;
  }
  const statements: D1PreparedStatement[] = [
    insertExport(env, principal.userId, principal.tokenId, intent.exportId, intent.objectKey,
      keyId, digest, body.byteLength, info, receivedAt),
    ...(encryptedSpec ? [env.DB.prepare(`INSERT INTO supplemental_exports
      (export_id, user_id, spec_ciphertext, spec_iv, scope_digest, created_at)
      SELECT ?, ?, ?, ?, ?, ? FROM exports WHERE id = ? AND user_id = ?`)
      .bind(intent.exportId, principal.userId, encryptedSpec.specCiphertext, encryptedSpec.specIv,
        encryptedSpec.scopeDigest, receivedAt, intent.exportId, principal.userId)] : []),
    ...info.dailyRecords.map((record) => env.DB.prepare(spec ?
      `INSERT INTO supplemental_records
       (user_id, owner_date, export_id, record_index, schema_version, capture_status)
       SELECT ?, ?, ?, ?, ?, ? FROM supplemental_exports
       WHERE export_id = ? AND user_id = ?` :
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
    ).bind(...(spec ? [principal.userId, record.date, intent.exportId, record.index,
      record.schemaVersion, record.captureStatus, intent.exportId, principal.userId] :
      [principal.userId, record.date, intent.exportId, record.index, record.schemaVersion,
        record.captureStatus, info.exportedAt, receivedAt]))),
    env.DB.prepare(
      "UPDATE ingest_tokens SET last_used_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
    ).bind(receivedAt, principal.tokenId, principal.userId),
    env.DB.prepare(
      `INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
       SELECT ?, ?, ?, ?, ? FROM exports WHERE id = ?`,
    ).bind(crypto.randomUUID(), principal.userId,
      spec ? "supplement.accepted" : "export.accepted", intent.exportId, receivedAt, intent.exportId),
    commitUploadIntentStatement(env, intent, receivedAt),
  ];
  try {
    // D1 batch is transactional; a failed metadata commit does not acknowledge the payload.
    const results = await env.DB.batch(statements);
    if (results[0]?.meta.changes !== 1 || results.at(-1)?.meta.changes !== 1) {
      throw new HttpError(401, "unauthorized", "Export token is no longer active.");
    }
  } catch (error) {
    try { await abandonUploadIntent(env, intent); } catch { /* Durable reconciliation retries cleanup. */ }
    const concurrentDuplicate = await duplicateReceipt();
    if (concurrentDuplicate) return concurrentDuplicate;
    throw error;
  }
  return json({ accepted: true, duplicate: false, id: intent.exportId, records: info.recordCount,
    ...(spec ? { mode: "supplemental", failureCount: info.failureCount } : {}) }, { status: 201 });
}

export async function listExports(env: Env, userId: string): Promise<Response> {
  const [exports, days, storage] = await Promise.all([
    env.DB.prepare(
      `SELECT id, byte_count AS byteCount, envelope_schema_version AS envelopeSchemaVersion,
              daily_record_schema_version AS dailyRecordSchemaVersion, source,
              exported_at AS exportedAt, received_at AS receivedAt, date_start AS dateStart,
              date_end AS dateEnd, record_count AS recordCount, failure_count AS failureCount,
              external_record_count AS externalRecordCount,
              CASE WHEN EXISTS (SELECT 1 FROM supplemental_exports s WHERE s.export_id = exports.id)
                THEN 'supplemental'
                WHEN EXISTS (SELECT 1 FROM daily_records d WHERE d.export_id = exports.id)
                THEN 'current' ELSE 'unreferenced' END AS retentionRole
       FROM exports WHERE user_id = ? ORDER BY received_at DESC, id DESC LIMIT 50`,
    ).bind(userId).all(),
    env.DB.prepare(
      `SELECT d.owner_date AS date, d.schema_version AS schemaVersion,
              d.capture_status AS captureStatus, d.exported_at AS exportedAt,
              d.received_at AS receivedAt, e.source AS source
       FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
       WHERE d.user_id = ? ORDER BY d.owner_date DESC LIMIT 50`,
    ).bind(userId).all(),
    env.DB.prepare(
      `SELECT COUNT(*) AS count, COALESCE(SUM(byte_count), 0) AS bytes,
        (SELECT COUNT(*) FROM daily_records WHERE user_id = ?) AS dayCount
       FROM exports WHERE user_id = ?`,
    ).bind(userId, userId).first<{ count: number; bytes: number; dayCount: number }>(),
  ]);
  return json({ exports: exports.results, days: days.results, storage: storage ?? { count: 0, bytes: 0, dayCount: 0 },
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
            external_record_count AS externalRecordCount,
            CASE WHEN EXISTS (SELECT 1 FROM supplemental_exports s WHERE s.export_id = exports.id)
              THEN 'supplemental'
              WHEN EXISTS (SELECT 1 FROM daily_records d WHERE d.export_id = exports.id)
              THEN 'current' ELSE 'unreferenced' END AS retentionRole
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
    `SELECT d.owner_date AS date, d.schema_version AS schemaVersion,
            d.capture_status AS captureStatus, d.exported_at AS exportedAt,
            d.received_at AS receivedAt, e.source AS source
     FROM daily_records d JOIN exports e ON e.id = d.export_id AND e.user_id = d.user_id
     WHERE d.user_id = ? ORDER BY d.owner_date DESC LIMIT 51 OFFSET ?`,
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
  const key = await resolveExportKey(env, userId, row.encryptionKeyId);
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
