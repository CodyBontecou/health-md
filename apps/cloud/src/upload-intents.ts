import { HttpError } from "./http";
import type { Env, IngestPrincipal } from "./types";

const INTENT_LEASE_MS = 15 * 60_000;
const COMPLETED_INTENT_RETENTION_MS = 24 * 60 * 60_000;
const MAX_ACTIVE_UPLOADS_PER_ACCOUNT = 2;

export interface UploadIntent {
  id: string;
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
  state: "reserved" | "object_written" | "committed";
}

interface StorageRow {
  committedBytes: number;
  reservedBytes: number;
  quotaBytes: number;
}

async function deleteExpiredRows(env: Env, rows: Array<{ id: string; objectKey: string }>): Promise<number> {
  let removed = 0;
  for (const row of rows) {
    // Do not release the durable reservation until the possibly-written object
    // is gone. A provider deletion failure remains retryable and fail-closed.
    await env.EXPORTS.delete(row.objectKey);
    const result = await env.DB.prepare(
      "DELETE FROM upload_intents WHERE id = ? AND state IN ('reserved', 'object_written')",
    ).bind(row.id).run();
    removed += result.meta.changes ?? 0;
  }
  return removed;
}

export async function reconcileAccountUploadIntents(
  env: Env,
  userId: string,
  now = new Date().toISOString(),
): Promise<number> {
  const expired = await env.DB.prepare(
    `SELECT id, object_key AS objectKey FROM upload_intents
     WHERE user_id = ? AND state IN ('reserved', 'object_written') AND expires_at <= ?
     ORDER BY expires_at LIMIT 4`,
  ).bind(userId, now).all<{ id: string; objectKey: string }>();
  return deleteExpiredRows(env, expired.results);
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
  const active = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM upload_intents
     WHERE user_id = ? AND state IN ('reserved', 'object_written') AND expires_at > ?`,
  ).bind(principal.userId, now).first<{ count: number }>();
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
  digest: string,
  scopeDigest: string | null,
  byteCount: number,
): Promise<UploadIntent> {
  const createdAt = new Date().toISOString();
  await reconcileAccountUploadIntents(env, principal.userId, createdAt);
  const intent: UploadIntent = {
    id: crypto.randomUUID(),
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
    // A plain INSERT either succeeds or throws (including trigger RAISE/unique
    // failures). D1's `meta.changes` is not portable across local/remote
    // adapters when triggers also update the storage ledger, so it must not be
    // used to decide whether this reservation exists.
    await env.DB.prepare(
      `INSERT INTO upload_intents
       (id, user_id, token_id, export_id, object_key, plaintext_sha256, scope_digest,
        byte_count, state, created_at, updated_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'reserved', ?, ?, ?)`,
    ).bind(intent.id, intent.userId, intent.tokenId, intent.exportId, intent.objectKey,
      intent.digest, intent.scopeDigest, intent.byteCount, intent.createdAt, intent.createdAt,
      intent.expiresAt).run();
  } catch {
    return await classifyReservationFailure(env, principal, digest, scopeDigest, byteCount, createdAt);
  }
  return intent;
}

export async function markUploadObjectWritten(env: Env, intent: UploadIntent): Promise<void> {
  const result = await env.DB.prepare(
    `UPDATE upload_intents SET state = 'object_written', updated_at = ?
     WHERE id = ? AND user_id = ? AND export_id = ? AND state = 'reserved'`,
  ).bind(new Date().toISOString(), intent.id, intent.userId, intent.exportId).run();
  if ((result.meta.changes ?? 0) !== 1) throw new Error("Upload reservation is no longer active");
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
  await env.EXPORTS.delete(intent.objectKey);
  await env.DB.prepare(
    `DELETE FROM upload_intents
     WHERE id = ? AND user_id = ? AND state IN ('reserved', 'object_written')`,
  ).bind(intent.id, intent.userId).run();
}

export async function reconcileUploadIntents(
  env: Env,
  limit = 25,
  now = new Date(),
): Promise<{ expired: number; completed: number }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Invalid upload-intent limit");
  const instant = now.toISOString();
  const expiredRows = await env.DB.prepare(
    `SELECT id, object_key AS objectKey FROM upload_intents
     WHERE state IN ('reserved', 'object_written') AND expires_at <= ?
     ORDER BY expires_at LIMIT ?`,
  ).bind(instant, limit).all<{ id: string; objectKey: string }>();
  const expired = await deleteExpiredRows(env, expiredRows.results);
  const cutoff = new Date(now.getTime() - COMPLETED_INTENT_RETENTION_MS).toISOString();
  const completedRows = await env.DB.prepare(
    `SELECT id FROM upload_intents WHERE state = 'committed' AND updated_at < ?
     ORDER BY updated_at LIMIT ?`,
  ).bind(cutoff, limit).all<{ id: string }>();
  let completed = 0;
  for (const row of completedRows.results) {
    const result = await env.DB.prepare(
      "DELETE FROM upload_intents WHERE id = ? AND state = 'committed'",
    ).bind(row.id).run();
    completed += result.meta.changes ?? 0;
  }
  return { expired, completed };
}

export const uploadIntentPolicy = {
  leaseMs: INTENT_LEASE_MS,
  completedRetentionMs: COMPLETED_INTENT_RETENTION_MS,
  maxActivePerAccount: MAX_ACTIVE_UPLOADS_PER_ACCOUNT,
} as const;
