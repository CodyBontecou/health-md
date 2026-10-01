import type { Env } from "./types";

const CURSOR_NAME = "r2-orphan-scan-v1";
const OBJECT_KEY = /^v1\/[a-f0-9-]{36}$/u;

interface CursorRow {
  cursorValue: string;
  updatedAt: string;
}

async function verifyAndDeleteOrphan(env: Env, key: string): Promise<void> {
  let deletionFailure: unknown;
  try {
    await env.EXPORTS.delete(key);
  } catch (error) {
    // R2 may have committed a delete before its response was lost. Verify the
    // exact key without materializing ciphertext.
    deletionFailure = error;
  }
  let durable: R2Object | null;
  try {
    durable = await env.EXPORTS.head(key);
  } catch {
    throw new Error("R2 orphan deletion verification is unavailable");
  }
  if (durable) {
    if (deletionFailure) throw deletionFailure;
    throw new Error("Orphan export object was not removed");
  }
}

async function advanceCursor(
  env: Env,
  prior: CursorRow | null,
  nextCursor: string,
): Promise<void> {
  let updatedAt = new Date().toISOString();
  if (updatedAt === prior?.updatedAt) {
    updatedAt = new Date(Date.parse(updatedAt) + 1).toISOString();
  }
  try {
    if (prior) {
      await env.DB.prepare(`UPDATE maintenance_cursors SET cursor_value = ?, updated_at = ?
        WHERE name = ? AND cursor_value = ? AND updated_at = ?`)
        .bind(nextCursor, updatedAt, CURSOR_NAME, prior.cursorValue, prior.updatedAt).run();
    } else {
      await env.DB.prepare(`INSERT INTO maintenance_cursors (name, cursor_value, updated_at)
        VALUES (?, ?, ?) ON CONFLICT(name) DO NOTHING`)
        .bind(CURSOR_NAME, nextCursor, updatedAt).run();
    }
  } catch {
    // A response may be lost after the conditional cursor write commits.
  }
  let durable: CursorRow | null;
  try {
    durable = await env.DB.prepare(`SELECT cursor_value AS cursorValue, updated_at AS updatedAt
      FROM maintenance_cursors WHERE name = ?`).bind(CURSOR_NAME).first<CursorRow>();
  } catch {
    throw new Error("R2 reconciliation cursor verification is unavailable");
  }
  if (durable?.cursorValue === nextCursor && durable.updatedAt === updatedAt) return;
  if (prior) {
    // Another invocation may advance from our exact starting marker while this
    // page is in flight. Its different marker wins; never overwrite/regress it.
    if (durable && (durable.cursorValue !== prior.cursorValue || durable.updatedAt !== prior.updatedAt)) return;
  } else if (durable) {
    // A concurrent first writer established the cursor. Preserve its page.
    return;
  }
  throw new Error("R2 reconciliation cursor was not advanced");
}

export async function reconcileOrphanExportObjects(
  env: Env,
  limit = 25,
): Promise<{ scanned: number; removed: number; completedCycle: boolean }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("Invalid object reconciliation limit");
  }
  const state = await env.DB.prepare(
    `SELECT cursor_value AS cursorValue, updated_at AS updatedAt
     FROM maintenance_cursors WHERE name = ?`,
  ).bind(CURSOR_NAME).first<CursorRow>();
  const cursor = state?.cursorValue || undefined;
  const page = await env.EXPORTS.list({ prefix: "v1/", limit, ...(cursor ? { cursor } : {}) });
  if (page.truncated && !page.cursor) throw new Error("R2 reconciliation cursor is unavailable");
  if (page.truncated && page.cursor === cursor) throw new Error("R2 reconciliation cursor did not progress");
  let removed = 0;
  for (const object of page.objects) {
    if (!OBJECT_KEY.test(object.key)) {
      throw new Error("Unexpected encrypted object key during reconciliation");
    }
    const reference = await env.DB.prepare(`SELECT CASE WHEN
      EXISTS (SELECT 1 FROM exports WHERE object_key = ?) OR
      EXISTS (SELECT 1 FROM upload_intents WHERE object_key = ?)
      THEN 1 ELSE 0 END AS referenced`).bind(object.key, object.key).first<{ referenced: number }>();
    if (!reference || ![0, 1].includes(reference.referenced)) {
      throw new Error("R2 orphan reference verification is unavailable");
    }
    if (reference.referenced === 1) continue;
    // Every normal write creates its random-key intent before R2. Therefore an
    // unreferenced exact v1 key cannot become a legitimate write concurrently.
    await verifyAndDeleteOrphan(env, object.key);
    removed += 1;
  }
  const nextCursor = page.truncated ? page.cursor ?? "" : "";
  await advanceCursor(env, state, nextCursor);
  return { scanned: page.objects.length, removed, completedCycle: !page.truncated };
}
