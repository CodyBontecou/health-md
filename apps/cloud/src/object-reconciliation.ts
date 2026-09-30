import type { Env } from "./types";

const CURSOR_NAME = "r2-orphan-scan-v1";
const OBJECT_KEY = /^v1\/[a-f0-9-]{36}$/u;

export async function reconcileOrphanExportObjects(
  env: Env,
  limit = 25,
): Promise<{ scanned: number; removed: number; completedCycle: boolean }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("Invalid object reconciliation limit");
  }
  const state = await env.DB.prepare(
    "SELECT cursor_value AS cursorValue FROM maintenance_cursors WHERE name = ?",
  ).bind(CURSOR_NAME).first<{ cursorValue: string }>();
  const cursor = state?.cursorValue || undefined;
  const page = await env.EXPORTS.list({ prefix: "v1/", limit, ...(cursor ? { cursor } : {}) });
  if (page.truncated && !page.cursor) throw new Error("R2 reconciliation cursor is unavailable");
  let removed = 0;
  for (const object of page.objects) {
    if (!OBJECT_KEY.test(object.key)) {
      throw new Error("Unexpected encrypted object key during reconciliation");
    }
    const reference = await env.DB.prepare(`SELECT CASE WHEN
      EXISTS (SELECT 1 FROM exports WHERE object_key = ?) OR
      EXISTS (SELECT 1 FROM upload_intents WHERE object_key = ?)
      THEN 1 ELSE 0 END AS referenced`).bind(object.key, object.key).first<{ referenced: number }>();
    if (reference?.referenced === 1) continue;
    // Every normal write creates its random-key intent before R2. Therefore an
    // unreferenced exact v1 key cannot become a legitimate write concurrently.
    await env.EXPORTS.delete(object.key);
    removed += 1;
  }
  const nextCursor = page.truncated ? page.cursor ?? "" : "";
  await env.DB.prepare(`INSERT INTO maintenance_cursors (name, cursor_value, updated_at)
    VALUES (?, ?, ?) ON CONFLICT(name) DO UPDATE SET cursor_value = excluded.cursor_value,
      updated_at = excluded.updated_at`).bind(CURSOR_NAME, nextCursor, new Date().toISOString()).run();
  return { scanned: page.objects.length, removed, completedCycle: !page.truncated };
}
