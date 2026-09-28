import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { verifyAccountPassword } from "./password";
import type { Env } from "./types";

interface ExportObjectRow { id: string; objectKey: string }
interface DeletionRow { id: string; userId: string }

export async function requestAccountDeletion(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  if (env.AUTH_MODE !== "password" || env.SYNTHETIC_PREVIEW_ONLY) {
    throw new HttpError(403, "deletion_unavailable", "Account deletion is unavailable in this profile.");
  }
  const input = await readJson<{ password?: unknown; confirmation?: unknown }>(request);
  if (input.confirmation !== "DELETE" || !await verifyAccountPassword(env, userId, input.password)) {
    throw new HttpError(401, "invalid_credentials", "Password confirmation failed.");
  }
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const results = await env.DB.batch([
    env.DB.prepare("UPDATE users SET status = 'disabled' WHERE id = ? AND status = 'active'").bind(userId),
    env.DB.prepare("INSERT INTO account_deletions (id, user_id, requested_at) VALUES (?, ?, ?)")
      .bind(id, userId, now),
  ]);
  if (results[0]?.meta.changes !== 1) throw new HttpError(409, "account_inactive", "Account is not active.");
  return json({ deletionId: id, status: "pending" }, { status: 202 });
}

// Safe to repeat after a crash: the user remains disabled, an object delete is
// idempotent, and the corresponding metadata row is removed only afterwards.
export async function processAccountDeletions(env: Env, perJob = 25): Promise<void> {
  const jobs = await env.DB.prepare(
    "SELECT id, user_id AS userId FROM account_deletions WHERE completed_at IS NULL ORDER BY requested_at LIMIT 10",
  ).all<DeletionRow>();
  for (const job of jobs.results) {
    const exports = await env.DB.prepare(
      "SELECT id, object_key AS objectKey FROM exports WHERE user_id = ? ORDER BY received_at LIMIT ?",
    ).bind(job.userId, perJob).all<ExportObjectRow>();
    for (const entry of exports.results) {
      await env.EXPORTS.delete(entry.objectKey);
      await env.DB.prepare("DELETE FROM exports WHERE id = ? AND user_id = ?")
        .bind(entry.id, job.userId).run();
    }
    if (exports.results.length === 0) {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM users WHERE id = ? AND status = 'disabled'").bind(job.userId),
        env.DB.prepare("UPDATE account_deletions SET completed_at = ? WHERE id = ? AND completed_at IS NULL")
          .bind(new Date().toISOString(), job.id),
      ]);
    }
  }
}

// Old superseded envelopes only: never remove an export referenced by the
// current daily-record index, even if it is older than the revision window.
export async function purgeArchivedRevisions(env: Env, retentionDays: number, limit = 25): Promise<number> {
  if (!Number.isInteger(retentionDays) || retentionDays < 1 || retentionDays > 3650) {
    throw new Error("Invalid revision-retention days");
  }
  const cutoff = new Date(Date.now() - retentionDays * 86400000).toISOString();
  const rows = await env.DB.prepare(
    `SELECT e.id, e.object_key AS objectKey FROM exports e
     WHERE e.received_at < ? AND NOT EXISTS
       (SELECT 1 FROM daily_records d WHERE d.export_id = e.id)
     ORDER BY e.received_at LIMIT ?`,
  ).bind(cutoff, limit).all<ExportObjectRow>();
  for (const row of rows.results) {
    await env.EXPORTS.delete(row.objectKey);
    await env.DB.prepare("DELETE FROM exports WHERE id = ? AND NOT EXISTS (SELECT 1 FROM daily_records WHERE export_id = ?)")
      .bind(row.id, row.id).run();
  }
  return rows.results.length;
}
