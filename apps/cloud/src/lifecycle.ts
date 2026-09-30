import { sha256Hex } from "./crypto";
import { assertSameOrigin, HttpError, json, parsePositiveInteger, readJson } from "./http";
import { verifyAccountPassword } from "./password";
import type { Env, LifecycleMessage, SessionUser } from "./types";

interface ExportObjectRow { id: string; objectKey: string }
interface DeletionRow { id: string; userId: string }
interface DeletionStatusRow { requestedAt: string; completedAt: string | null; expiresAt: string }

const EMAIL_DELETION_REAUTH_MS = 15 * 60_000;
const DELETION_STATUS_TOKEN = /^hmd_del_[A-Za-z0-9_-]{43}$/u;

function deletionStatusTtlDays(env: Env): number {
  return env.DELETION_STATUS_TTL_DAYS ?
    parsePositiveInteger(env.DELETION_STATUS_TTL_DAYS, "DELETION_STATUS_TTL_DAYS", 1, 90) : 30;
}

export async function requestAccountDeletion(request: Request, env: Env, user: SessionUser): Promise<Response> {
  assertSameOrigin(request, env);
  if (env.SYNTHETIC_PREVIEW_ONLY) {
    throw new HttpError(403, "deletion_unavailable", "Account deletion is unavailable in this profile.");
  }
  const input = await readJson<{
    password?: unknown; confirmation?: unknown; statusToken?: unknown;
  }>(request);
  if (input.confirmation !== "DELETE") {
    throw new HttpError(401, "invalid_credentials", "Recent sign-in and confirmation are required.");
  }
  // The browser generates this high-entropy bearer before submitting the
  // destructive request. If the response is lost after D1 commits, the user
  // still has the only credential needed to observe completion.
  if (typeof input.statusToken !== "string" || !DELETION_STATUS_TOKEN.test(input.statusToken)) {
    throw new HttpError(400, "invalid_deletion_receipt", "A valid deletion status receipt is required.");
  }
  if (env.AUTH_MODE === "password") {
    if (!await verifyAccountPassword(env, user.id, input.password)) {
      throw new HttpError(401, "invalid_credentials", "Password confirmation failed.");
    }
  } else {
    const sessionAge = Date.now() - Date.parse(user.sessionCreatedAt);
    if (!Number.isFinite(sessionAge) || sessionAge < -60_000 || sessionAge > EMAIL_DELETION_REAUTH_MS) {
      throw new HttpError(401, "reauthentication_required", "Sign in again before deleting this account.");
    }
  }
  const id = crypto.randomUUID();
  const statusToken = input.statusToken;
  const statusTokenHash = await sha256Hex(statusToken);
  const now = new Date().toISOString();
  const statusExpiresAt = new Date(Date.now() + deletionStatusTtlDays(env) * 86400000).toISOString();
  let batchCompleted = false;
  let batchFailure: unknown;
  try {
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET status = 'disabled' WHERE id = ? AND status = 'active'").bind(user.id),
      env.DB.prepare(`INSERT INTO account_deletions
        (id, user_id, requested_at, status_token_hash, status_expires_at) VALUES (?, ?, ?, ?, ?)`)
        .bind(id, user.id, now, statusTokenHash, statusExpiresAt),
    ]);
    batchCompleted = true;
  } catch (error) {
    batchFailure = error;
  }
  let committed: { valid: number; completedAt: string | null } | null;
  try {
    // The deletion row and account disablement are one D1 transaction. The
    // user row can legitimately disappear if scheduled maintenance completes
    // between that commit and this read, so it must not be part of the durable
    // receipt postcondition.
    committed = await env.DB.prepare(`SELECT 1 AS valid, completed_at AS completedAt
      FROM account_deletions
      WHERE id = ? AND user_id = ? AND status_token_hash = ?`)
      .bind(id, user.id, statusTokenHash).first<{ valid: number; completedAt: string | null }>();
  } catch {
    // The caller already owns the receipt and can safely poll it. Do not try to
    // undo an account disablement whose commit outcome cannot be read.
    throw new HttpError(503, "deletion_verification_pending",
      "Account deletion verification is temporarily unavailable. Check the status receipt shortly.");
  }
  if (committed?.valid !== 1) {
    if (!batchCompleted) throw batchFailure;
    throw new HttpError(409, "account_inactive", "Account is not active.");
  }
  if (!committed.completedAt) {
    const message: LifecycleMessage = { version: 1, type: "account.delete", deletionId: id };
    try { await env.LIFECYCLE_QUEUE?.send(message); }
    catch { /* The durable D1 job remains available to scheduled maintenance. */ }
  }
  return json({ deletionId: id, status: committed.completedAt ? "completed" : "pending",
    statusToken, statusExpiresAt }, { status: 202 });
}

export async function getAccountDeletionStatus(request: Request, env: Env): Promise<Response> {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = /^Bearer (hmd_del_[A-Za-z0-9_-]{40,60})$/u.exec(authorization);
  if (!match?.[1]) {
    throw new HttpError(401, "invalid_deletion_receipt", "Deletion status receipt is invalid or expired.");
  }
  const row = await env.DB.prepare(
    `SELECT requested_at AS requestedAt, completed_at AS completedAt, status_expires_at AS expiresAt
     FROM account_deletions WHERE status_token_hash = ? AND status_expires_at > ? LIMIT 1`,
  ).bind(await sha256Hex(match[1]), new Date().toISOString()).first<DeletionStatusRow>();
  if (!row) {
    throw new HttpError(401, "invalid_deletion_receipt", "Deletion status receipt is invalid or expired.");
  }
  return json({
    status: row.completedAt ? "completed" : "pending",
    requestedAt: row.requestedAt,
    completedAt: row.completedAt,
    statusExpiresAt: row.expiresAt,
  });
}

// Safe to repeat after a crash: the user remains disabled, object deletion is
// idempotent, and metadata is removed only after its ciphertext is gone.
export async function processAccountDeletionById(env: Env, deletionId: string, perJob = 100): Promise<boolean> {
  if (!/^[a-f0-9-]{36}$/u.test(deletionId) || !Number.isInteger(perJob) || perJob < 1 || perJob > 500) {
    throw new Error("Invalid account-deletion job");
  }
  const job = await env.DB.prepare(
    `SELECT id, user_id AS userId FROM account_deletions
     WHERE id = ? AND completed_at IS NULL`,
  ).bind(deletionId).first<DeletionRow>();
  if (!job) return true;
  const exports = await env.DB.prepare(
    "SELECT id, object_key AS objectKey FROM exports WHERE user_id = ? ORDER BY received_at LIMIT ?",
  ).bind(job.userId, perJob).all<ExportObjectRow>();
  for (const entry of exports.results) {
    await env.EXPORTS.delete(entry.objectKey);
    await env.DB.prepare("DELETE FROM exports WHERE id = ? AND user_id = ?")
      .bind(entry.id, job.userId).run();
  }
  const intents = await env.DB.prepare(
    `SELECT id, object_key AS objectKey FROM upload_intents
     WHERE user_id = ? AND state IN ('reserved', 'object_written') ORDER BY created_at LIMIT ?`,
  ).bind(job.userId, perJob).all<ExportObjectRow>();
  for (const entry of intents.results) {
    await env.EXPORTS.delete(entry.objectKey);
    await env.DB.prepare(
      "DELETE FROM upload_intents WHERE id = ? AND user_id = ? AND state IN ('reserved', 'object_written')",
    ).bind(entry.id, job.userId).run();
  }
  const remaining = await env.DB.prepare(`SELECT
    (SELECT COUNT(*) FROM exports WHERE user_id = ?) +
    (SELECT COUNT(*) FROM upload_intents WHERE user_id = ? AND state IN ('reserved', 'object_written')) AS count`)
    .bind(job.userId, job.userId).first<{ count: number }>();
  if ((remaining?.count ?? 0) > 0) return false;
  const results = await env.DB.batch([
    env.DB.prepare("DELETE FROM users WHERE id = ? AND status = 'disabled'").bind(job.userId),
    env.DB.prepare("UPDATE account_deletions SET completed_at = ? WHERE id = ? AND completed_at IS NULL")
      .bind(new Date().toISOString(), job.id),
  ]);
  if (results[1]?.meta.changes !== 1) throw new Error("Account deletion completion was not recorded");
  return true;
}

export async function processAccountDeletions(env: Env, perJob = 100): Promise<void> {
  const jobs = await env.DB.prepare(
    "SELECT id FROM account_deletions WHERE completed_at IS NULL ORDER BY requested_at LIMIT 10",
  ).all<{ id: string }>();
  for (const job of jobs.results) await processAccountDeletionById(env, job.id, perJob);
}

export async function purgeExpiredDeletionReceipts(env: Env): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.batch([
    // An overdue deletion job must survive for retry even after its status credential expires.
    env.DB.prepare(`UPDATE account_deletions SET status_token_hash = NULL
      WHERE completed_at IS NULL AND status_expires_at <= ? AND status_token_hash IS NOT NULL`).bind(now),
    env.DB.prepare("DELETE FROM account_deletions WHERE completed_at IS NOT NULL AND status_expires_at <= ?")
      .bind(now),
  ]);
}

// Old superseded envelopes only: never remove an export referenced by the
// current daily-record index or an active supplement, even if it is older
// than the revision window. Supplements have no supersession rule yet.
export async function purgeArchivedRevisions(env: Env, retentionDays: number, limit = 25): Promise<number> {
  if (!Number.isInteger(retentionDays) || retentionDays < 1 || retentionDays > 3650) {
    throw new Error("Invalid revision-retention days");
  }
  const cutoff = new Date(Date.now() - retentionDays * 86400000).toISOString();
  const rows = await env.DB.prepare(
    `SELECT e.id, e.object_key AS objectKey FROM exports e
     WHERE e.received_at < ? AND NOT EXISTS
       (SELECT 1 FROM daily_records d WHERE d.export_id = e.id)
       AND NOT EXISTS (SELECT 1 FROM supplemental_exports s WHERE s.export_id = e.id)
     ORDER BY e.received_at LIMIT ?`,
  ).bind(cutoff, limit).all<ExportObjectRow>();
  let removed = 0;
  for (const row of rows.results) {
    // Remove metadata only if still unreferenced at commit. If a concurrent
    // writer attached a supplement, its ciphertext must not disappear.
    const result = await env.DB.prepare(`DELETE FROM exports WHERE id = ? AND NOT EXISTS
      (SELECT 1 FROM daily_records WHERE export_id = ?) AND NOT EXISTS
      (SELECT 1 FROM supplemental_exports WHERE export_id = ?)`).bind(row.id, row.id, row.id).run();
    if (!result.meta.changes) continue;
    removed += 1;
    // Failure leaves an encrypted orphan for reconciliation, never a live
    // primary/supplement pointer with missing ciphertext.
    await env.EXPORTS.delete(row.objectKey);
  }
  return removed;
}
