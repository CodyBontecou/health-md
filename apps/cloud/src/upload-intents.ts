import { HttpError } from "./http";
import type { Env, IngestPrincipal } from "./types";

const ADMISSION_LEASE_MS = 15 * 60_000;
const INTENT_LEASE_MS = 15 * 60_000;
const COMPLETED_INTENT_RETENTION_MS = 24 * 60 * 60_000;
const MAX_ACTIVE_UPLOADS_PER_ACCOUNT = 2;

export interface UploadAdmission {
  id: string;
  userId: string;
  tokenId: string;
  createdAt: string;
  expiresAt: string;
}

export interface UploadIntent {
  id: string;
  admissionId: string;
  userId: string;
  tokenId: string;
  exportId: string;
  objectKey: string;
  digest: string;
  scopeDigest: string | null;
  byteCount: number;
  createdAt: string;
  expiresAt: string;
}

interface IntentRow {
  id: string;
  objectKey: string;
  scopeDigest: string | null;
  state: "reserved" | "object_written" | "aborting" | "committed";
}

interface DurableIntentRow extends IntentRow {
  admissionId: string;
  userId: string;
  tokenId: string;
  exportId: string;
  digest: string;
  byteCount: number;
  createdAt: string;
  updatedAt: string;
  expiresAt: string;
}

interface StorageRow {
  committedBytes: number;
  reservedBytes: number;
  quotaBytes: number;
}

async function deleteAdmissionRows(env: Env, rows: Array<{ id: string }>): Promise<number> {
  let removed = 0;
  for (const row of rows) {
    try {
      await env.DB.prepare("DELETE FROM upload_admissions WHERE id = ?")
        .bind(row.id).run();
    } catch {
      // A lost response may follow a committed delete. Verify absence below.
    }
    let durable: { id: string } | null;
    try {
      durable = await env.DB.prepare("SELECT id FROM upload_admissions WHERE id = ?")
        .bind(row.id).first<{ id: string }>();
    } catch {
      throw new Error("Upload admission cleanup verification is unavailable");
    }
    if (durable) throw new Error("Expired upload admission was not removed");
    removed += 1;
  }
  return removed;
}

async function reconcileAccountUploadAdmissions(
  env: Env,
  userId: string,
  now: string,
): Promise<number> {
  const rows = await env.DB.prepare(`SELECT id FROM upload_admissions
    WHERE user_id = ? AND expires_at <= ? ORDER BY expires_at, id LIMIT 4`)
    .bind(userId, now).all<{ id: string }>();
  return deleteAdmissionRows(env, rows.results);
}

async function classifyAdmissionFailure(
  env: Env,
  principal: IngestPrincipal,
  now: string,
): Promise<never> {
  const token = await env.DB.prepare(
    `SELECT 1 AS active FROM ingest_tokens t JOIN users u ON u.id = t.user_id
     WHERE t.id = ? AND t.user_id = ? AND t.revoked_at IS NULL AND u.status = 'active'`,
  ).bind(principal.tokenId, principal.userId).first<{ active: number }>();
  if (!token) throw new HttpError(401, "unauthorized", "Export token is no longer active.");
  const active = await env.DB.prepare(`SELECT
    (SELECT COUNT(*) FROM upload_admissions
      WHERE user_id = ? AND expires_at > ?) +
    (SELECT COUNT(*) FROM upload_intents
      WHERE user_id = ? AND state IN ('reserved', 'object_written') AND expires_at > ?) AS count`)
    .bind(principal.userId, now, principal.userId, now).first<{ count: number }>();
  if ((active?.count ?? 0) >= MAX_ACTIVE_UPLOADS_PER_ACCOUNT) {
    throw new HttpError(429, "account_busy", "This account already has two uploads in progress. Retry shortly.");
  }
  throw new HttpError(503, "ingest_busy", "Export ingestion is temporarily busy. Retry shortly.");
}

export async function acquireUploadAdmission(
  env: Env,
  principal: IngestPrincipal,
): Promise<UploadAdmission> {
  const createdAt = new Date().toISOString();
  await reconcileAccountUploadAdmissions(env, principal.userId, createdAt);
  const admission: UploadAdmission = {
    id: crypto.randomUUID(),
    userId: principal.userId,
    tokenId: principal.tokenId,
    createdAt,
    expiresAt: new Date(Date.parse(createdAt) + ADMISSION_LEASE_MS).toISOString(),
  };
  try {
    await env.DB.prepare(`INSERT INTO upload_admissions
      (id, user_id, token_id, created_at, expires_at) VALUES (?, ?, ?, ?, ?)`)
      .bind(admission.id, admission.userId, admission.tokenId,
        admission.createdAt, admission.expiresAt).run();
  } catch {
    // Distinguish a lost successful response from a real trigger rejection by
    // reading the random candidate ID rather than parsing provider errors.
  }
  let durable: UploadAdmission | null;
  try {
    durable = await env.DB.prepare(`SELECT id, user_id AS userId, token_id AS tokenId,
      created_at AS createdAt, expires_at AS expiresAt
      FROM upload_admissions WHERE id = ? LIMIT 1`)
      .bind(admission.id).first<UploadAdmission>();
  } catch {
    throw new HttpError(503, "admission_verification_pending",
      "Upload admission status could not be verified. Retry shortly.");
  }
  if (durable && durable.userId === admission.userId && durable.tokenId === admission.tokenId &&
      durable.createdAt === admission.createdAt && durable.expiresAt === admission.expiresAt) {
    return admission;
  }
  if (durable) throw new Error("Upload admission durable state is inconsistent");
  return classifyAdmissionFailure(env, principal, createdAt);
}

export async function releaseUploadAdmission(env: Env, admission: UploadAdmission): Promise<void> {
  try {
    await env.DB.prepare(`DELETE FROM upload_admissions
      WHERE id = ? AND user_id = ? AND token_id = ?`)
      .bind(admission.id, admission.userId, admission.tokenId).run();
  } catch {
    // Verify a possibly committed delete rather than leaking an account slot.
  }
  let durable: { id: string } | null;
  try {
    durable = await env.DB.prepare("SELECT id FROM upload_admissions WHERE id = ?")
      .bind(admission.id).first<{ id: string }>();
  } catch {
    throw new HttpError(503, "admission_release_pending",
      "Upload admission release could not be verified. Retry shortly.");
  }
  if (durable) {
    throw new HttpError(503, "admission_release_pending",
      "Upload admission release could not be verified. Retry shortly.");
  }
}

interface CleanupIntentRow {
  id: string;
  userId: string;
  objectKey: string;
  state: IntentRow["state"];
}

async function claimIntentForCleanup(
  env: Env,
  id: string,
  userId: string,
  expiredBefore?: string,
): Promise<CleanupIntentRow | null> {
  const updatedAt = new Date().toISOString();
  try {
    await env.DB.prepare(`UPDATE upload_intents SET state = 'aborting', updated_at = ?
      WHERE id = ? AND user_id = ? AND state IN ('reserved', 'object_written')
        ${expiredBefore === undefined ? "" : "AND expires_at <= ?"}`)
      .bind(...(expiredBefore === undefined ? [updatedAt, id, userId] :
        [updatedAt, id, userId, expiredBefore])).run();
  } catch {
    // A response may be lost after the claim commits. Read durable state below.
  }
  let durable: CleanupIntentRow | null;
  try {
    durable = await env.DB.prepare(`SELECT id, user_id AS userId, object_key AS objectKey, state
      FROM upload_intents WHERE id = ? LIMIT 1`).bind(id).first<CleanupIntentRow>();
  } catch {
    throw new Error("Upload-intent cleanup claim verification is unavailable");
  }
  if (!durable) return null;
  if (durable.userId !== userId) throw new Error("Upload-intent cleanup owner is inconsistent");
  if (durable.state === "committed") return durable;
  if (durable.state !== "aborting") {
    throw new Error("Upload-intent cleanup claim was not recorded");
  }
  return durable;
}

async function deleteAbortingIntent(env: Env, row: CleanupIntentRow): Promise<void> {
  // Claiming `aborting` first prevents object-written/final-commit transitions.
  // Keep the row and reservation until the possibly-written object is gone.
  await env.EXPORTS.delete(row.objectKey);
  try {
    await env.DB.prepare("DELETE FROM upload_intents WHERE id = ? AND state = 'aborting'")
      .bind(row.id).run();
  } catch {
    // A response may be lost after trigger-backed quota release commits.
  }
  let durable: { state: string } | null;
  try {
    durable = await env.DB.prepare("SELECT state FROM upload_intents WHERE id = ?")
      .bind(row.id).first<{ state: string }>();
  } catch {
    throw new Error("Upload-intent cleanup verification is unavailable");
  }
  if (durable) throw new Error("Aborting upload intent was not removed");
}

async function deleteExpiredRows(env: Env, rows: CleanupIntentRow[], expiredBefore: string): Promise<number> {
  let removed = 0;
  for (const row of rows) {
    const claimed = await claimIntentForCleanup(env, row.id, row.userId, expiredBefore);
    if (!claimed || claimed.state === "committed") continue;
    if (claimed.objectKey !== row.objectKey) throw new Error("Upload-intent cleanup object is inconsistent");
    await deleteAbortingIntent(env, claimed);
    removed += 1;
  }
  return removed;
}

export async function reconcileAccountUploadIntents(
  env: Env,
  userId: string,
  now = new Date().toISOString(),
): Promise<number> {
  const expired = await env.DB.prepare(
    `SELECT id, user_id AS userId, object_key AS objectKey, state FROM upload_intents
     WHERE user_id = ? AND state IN ('reserved', 'object_written', 'aborting') AND expires_at <= ?
     ORDER BY expires_at LIMIT 4`,
  ).bind(userId, now).all<CleanupIntentRow>();
  return deleteExpiredRows(env, expired.results, now);
}

async function classifyReservationFailure(
  env: Env,
  principal: IngestPrincipal,
  digest: string,
  scopeDigest: string | null,
  bytes: number,
  now: string,
): Promise<never> {
  const existing = await env.DB.prepare(
    `SELECT id, object_key AS objectKey, scope_digest AS scopeDigest, state
     FROM upload_intents WHERE user_id = ? AND plaintext_sha256 = ? LIMIT 1`,
  ).bind(principal.userId, digest).first<IntentRow>();
  if (existing) {
    if (existing.scopeDigest !== scopeDigest) {
      throw new HttpError(409, "scope_conflict", "These bytes are being retained under a different export scope.");
    }
    throw new HttpError(429, "upload_in_progress", "An identical export is already being processed. Retry shortly.");
  }
  const token = await env.DB.prepare(
    `SELECT 1 AS active FROM ingest_tokens t JOIN users u ON u.id = t.user_id
     WHERE t.id = ? AND t.user_id = ? AND t.revoked_at IS NULL AND u.status = 'active'`,
  ).bind(principal.tokenId, principal.userId).first<{ active: number }>();
  if (!token) throw new HttpError(401, "unauthorized", "Export token is no longer active.");
  const storage = await env.DB.prepare(
    `SELECT committed_bytes AS committedBytes, reserved_bytes AS reservedBytes, quota_bytes AS quotaBytes
     FROM account_storage WHERE user_id = ?`,
  ).bind(principal.userId).first<StorageRow>();
  if (!storage) throw new Error("Account storage ledger is unavailable");
  if (storage.committedBytes + storage.reservedBytes + bytes > storage.quotaBytes) {
    throw new HttpError(413, "account_quota", "Account export storage quota reached.");
  }
  const active = await env.DB.prepare(`SELECT
    (SELECT COUNT(*) FROM upload_admissions
      WHERE user_id = ? AND expires_at > ?) +
    (SELECT COUNT(*) FROM upload_intents
      WHERE user_id = ? AND state IN ('reserved', 'object_written') AND expires_at > ?) AS count`)
    .bind(principal.userId, now, principal.userId, now).first<{ count: number }>();
  if ((active?.count ?? 0) >= MAX_ACTIVE_UPLOADS_PER_ACCOUNT) {
    throw new HttpError(429, "account_busy", "This account already has two uploads in progress. Retry shortly.");
  }
  // A concurrent transaction may have changed between the diagnostic reads.
  // Fail with bounded backpressure rather than exposing database details.
  throw new HttpError(503, "ingest_busy", "Export ingestion is temporarily busy. Retry shortly.");
}

export async function reserveUploadIntent(
  env: Env,
  principal: IngestPrincipal,
  admission: UploadAdmission,
  digest: string,
  scopeDigest: string | null,
  byteCount: number,
): Promise<UploadIntent> {
  const createdAt = new Date().toISOString();
  await reconcileAccountUploadIntents(env, principal.userId, createdAt);
  if (admission.userId !== principal.userId || admission.tokenId !== principal.tokenId) {
    throw new Error("Upload admission principal does not match");
  }
  const intent: UploadIntent = {
    id: crypto.randomUUID(),
    admissionId: admission.id,
    userId: principal.userId,
    tokenId: principal.tokenId,
    exportId: crypto.randomUUID(),
    objectKey: `v1/${crypto.randomUUID()}`,
    digest,
    scopeDigest,
    byteCount,
    createdAt,
    expiresAt: new Date(Date.parse(createdAt) + INTENT_LEASE_MS).toISOString(),
  };
  try {
    // A response may be lost after the trigger-bearing insert commits. Adapter
    // change metadata is not portable, so verify the exact candidate below.
    await env.DB.prepare(
      `INSERT INTO upload_intents
       (id, admission_id, user_id, token_id, export_id, object_key, plaintext_sha256, scope_digest,
        byte_count, state, created_at, updated_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'reserved', ?, ?, ?)`,
    ).bind(intent.id, intent.admissionId, intent.userId, intent.tokenId, intent.exportId,
      intent.objectKey, intent.digest, intent.scopeDigest, intent.byteCount, intent.createdAt,
      intent.createdAt, intent.expiresAt).run();
  } catch {
    // The exact candidate read distinguishes a lost successful response from a
    // true trigger/uniqueness rejection without relying on error text.
  }
  let durable: DurableIntentRow | null;
  try {
    durable = await env.DB.prepare(
      `SELECT id, admission_id AS admissionId, user_id AS userId, token_id AS tokenId,
              export_id AS exportId, object_key AS objectKey,
              plaintext_sha256 AS digest, scope_digest AS scopeDigest,
              byte_count AS byteCount, state, created_at AS createdAt,
              updated_at AS updatedAt, expires_at AS expiresAt
       FROM upload_intents WHERE id = ? LIMIT 1`,
    ).bind(intent.id).first<DurableIntentRow>();
  } catch {
    throw new HttpError(503, "reservation_verification_pending",
      "Upload reservation status could not be verified. Retry shortly.");
  }
  if (durable && durable.admissionId === intent.admissionId &&
      durable.userId === intent.userId && durable.tokenId === intent.tokenId &&
      durable.exportId === intent.exportId && durable.objectKey === intent.objectKey &&
      durable.digest === intent.digest && durable.scopeDigest === intent.scopeDigest &&
      durable.byteCount === intent.byteCount && durable.state === "reserved" &&
      durable.createdAt === intent.createdAt && durable.updatedAt === intent.createdAt &&
      durable.expiresAt === intent.expiresAt) {
    return intent;
  }
  if (durable) throw new Error("Upload reservation durable state is inconsistent");
  return await classifyReservationFailure(env, principal, digest, scopeDigest, byteCount, createdAt);
}

export async function markUploadObjectWritten(env: Env, intent: UploadIntent): Promise<void> {
  const updatedAt = new Date().toISOString();
  try {
    await env.DB.prepare(
      `UPDATE upload_intents SET state = 'object_written', updated_at = ?
       WHERE id = ? AND user_id = ? AND export_id = ? AND state = 'reserved'`,
    ).bind(updatedAt, intent.id, intent.userId, intent.exportId).run();
  } catch {
    // A response may be lost after the staged-object transition commits.
    // Verify its exact durable marker rather than adapter change metadata.
  }
  let durable: { state: string; updatedAt: string } | null;
  try {
    durable = await env.DB.prepare(`SELECT state, updated_at AS updatedAt FROM upload_intents
      WHERE id = ? AND user_id = ? AND export_id = ?`)
      .bind(intent.id, intent.userId, intent.exportId)
      .first<{ state: string; updatedAt: string }>();
  } catch {
    throw new Error("Upload object-written verification is unavailable");
  }
  if (durable?.state !== "object_written" || durable.updatedAt !== updatedAt) {
    throw new Error("Upload reservation is no longer active");
  }
}

export function commitUploadIntentStatement(
  env: Env,
  intent: UploadIntent,
  committedAt: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `UPDATE upload_intents SET state = 'committed', updated_at = ?
     WHERE id = ? AND user_id = ? AND export_id = ? AND state IN ('reserved', 'object_written')
       AND EXISTS (SELECT 1 FROM exports WHERE id = ? AND user_id = ?)`,
  ).bind(committedAt, intent.id, intent.userId, intent.exportId, intent.exportId, intent.userId);
}

export async function abandonUploadIntent(env: Env, intent: UploadIntent): Promise<void> {
  const claimed = await claimIntentForCleanup(env, intent.id, intent.userId);
  if (claimed?.state === "committed") {
    throw new Error("Committed upload intent cannot be abandoned");
  }
  if (!claimed) {
    // Expiry cleanup may already have removed the row before a slow writer put
    // its object. With export insertion gated on an active intent, this key can
    // only be an orphan and is safe to delete.
    await env.EXPORTS.delete(intent.objectKey);
    return;
  }
  if (claimed.objectKey !== intent.objectKey) throw new Error("Upload-intent cleanup object is inconsistent");
  await deleteAbortingIntent(env, claimed);
}

async function deleteCommittedIntent(env: Env, id: string): Promise<void> {
  try {
    await env.DB.prepare("DELETE FROM upload_intents WHERE id = ? AND state = 'committed'")
      .bind(id).run();
  } catch {
    // Verify a possibly committed retention delete below.
  }
  let durable: { state: string } | null;
  try {
    durable = await env.DB.prepare("SELECT state FROM upload_intents WHERE id = ?")
      .bind(id).first<{ state: string }>();
  } catch {
    throw new Error("Completed upload-intent cleanup verification is unavailable");
  }
  if (durable) throw new Error("Completed upload intent was not removed");
}

export async function reconcileUploadAdmissions(
  env: Env,
  limit = 25,
  now = new Date(),
): Promise<number> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Invalid upload-admission limit");
  const rows = await env.DB.prepare(`SELECT id FROM upload_admissions
    WHERE expires_at <= ? ORDER BY expires_at, id LIMIT ?`)
    .bind(now.toISOString(), limit).all<{ id: string }>();
  return deleteAdmissionRows(env, rows.results);
}

export async function reconcileUploadIntents(
  env: Env,
  limit = 25,
  now = new Date(),
): Promise<{ expired: number; completed: number }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Invalid upload-intent limit");
  const instant = now.toISOString();
  const expiredRows = await env.DB.prepare(
    `SELECT id, user_id AS userId, object_key AS objectKey, state FROM upload_intents
     WHERE state IN ('reserved', 'object_written', 'aborting') AND expires_at <= ?
     ORDER BY expires_at LIMIT ?`,
  ).bind(instant, limit).all<CleanupIntentRow>();
  const expired = await deleteExpiredRows(env, expiredRows.results, instant);
  const cutoff = new Date(now.getTime() - COMPLETED_INTENT_RETENTION_MS).toISOString();
  const completedRows = await env.DB.prepare(
    `SELECT id FROM upload_intents WHERE state = 'committed' AND updated_at < ?
     ORDER BY updated_at LIMIT ?`,
  ).bind(cutoff, limit).all<{ id: string }>();
  let completed = 0;
  for (const row of completedRows.results) {
    await deleteCommittedIntent(env, row.id);
    completed += 1;
  }
  return { expired, completed };
}

export const uploadIntentPolicy = {
  admissionLeaseMs: ADMISSION_LEASE_MS,
  leaseMs: INTENT_LEASE_MS,
  completedRetentionMs: COMPLETED_INTENT_RETENTION_MS,
  maxActivePerAccount: MAX_ACTIVE_UPLOADS_PER_ACCOUNT,
} as const;
