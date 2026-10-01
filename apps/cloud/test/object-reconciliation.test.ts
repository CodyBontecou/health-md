import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { reconcileOrphanExportObjects } from "../src/object-reconciliation";
import { purgeArchivedRevisions } from "../src/lifecycle";
import { reserveUploadIntent } from "../src/upload-intents";
import type { IngestPrincipal } from "../src/types";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-object-reconciliation-"));
  roots.push(directory);
  return createVmEnvironment({
    dataDirectory: directory,
    sourceDirectory,
    publicOrigin: "https://maintenance.example.test",
    identityKey: secret(),
    exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1",
    passwordPepper: secret(),
    personalMvp: true,
    revisionRetention: "unlimited",
  });
}

function account(db: ReturnType<typeof setup>["db"]): IngestPrincipal {
  const userId = randomUUID();
  const tokenId = randomUUID();
  const now = new Date().toISOString();
  db.connection.prepare(`INSERT INTO users
    (id, email_lookup, email_ciphertext, email_iv, status, created_at)
    VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(userId, randomUUID(), now);
  db.connection.prepare(`INSERT INTO ingest_tokens
    (id, user_id, name, token_hash, last_four, created_at)
    VALUES (?, ?, 'Synthetic device', ?, 'test', ?)`).run(tokenId, userId, randomUUID(), now);
  return { userId, tokenId };
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

async function archivedExport(env: ReturnType<typeof setup>["env"],
  db: ReturnType<typeof setup>["db"]): Promise<{ id: string; key: string }> {
  const principal = account(db);
  const id = randomUUID();
  const key = `v1/${randomUUID()}`;
  await env.EXPORTS.put(key, new Uint8Array([1, 2, 3]));
  db.connection.prepare(`INSERT INTO exports
    (id, user_id, object_key, encryption_key_id, plaintext_sha256, byte_count,
     envelope_schema_version, daily_record_schema_version, source, exported_at, received_at,
     date_start, date_end, record_count, failure_count, external_record_count)
    VALUES (?, ?, ?, 'v1', ?, 3, 1, 1, 'ios', ?, '2020-01-01T00:00:00.000Z',
      '2020-01-01', '2020-01-01', 1, 0, 0)`)
    .run(id, principal.userId, key, "a".repeat(64), "2020-01-01T00:00:00.000Z");
  return { id, key };
}

it("deletes only unreferenced ciphertext across bounded cursor pages", async () => {
  const { env, db } = setup();
  try {
    const intent = await reserveUploadIntent(env, account(db), "a".repeat(64), null, 10);
    const orphanA = `v1/${randomUUID()}`;
    const orphanB = `v1/${randomUUID()}`;
    const keys = [orphanA, intent.objectKey, orphanB];
    const deleted: string[] = [];
    env.EXPORTS = {
      list: async (options: { cursor?: string; limit?: number }) => {
        const offset = Number(options.cursor ?? 0);
        const end = Math.min(offset + (options.limit ?? 25), keys.length);
        return {
          objects: keys.slice(offset, end).map((key) => ({ key })),
          truncated: end < keys.length,
          ...(end < keys.length ? { cursor: String(end) } : {}),
        };
      },
      delete: async (key: string) => { deleted.push(key); },
    } as unknown as R2Bucket;

    expect(await reconcileOrphanExportObjects(env, 2)).toEqual({
      scanned: 2, removed: 1, completedCycle: false,
    });
    expect(deleted).toEqual([orphanA]);
    expect(db.connection.prepare("SELECT cursor_value AS cursor FROM maintenance_cursors").get())
      .toMatchObject({ cursor: "2" });

    expect(await reconcileOrphanExportObjects(env, 2)).toEqual({
      scanned: 1, removed: 1, completedCycle: true,
    });
    expect(deleted).toEqual([orphanA, orphanB]);
    expect(db.connection.prepare("SELECT cursor_value AS cursor FROM maintenance_cursors").get())
      .toMatchObject({ cursor: "" });
  } finally { db.close(); }
});

it("removes archived ciphertext after a lost metadata-delete response", async () => {
  const { env, db } = setup();
  try {
    const archived = await archivedExport(env, db);
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("DELETE FROM exports WHERE id = ? AND NOT EXISTS")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty === "run") return async () => {
                await boundStatement.run();
                throw new Error("synthetic lost archived-delete response");
              };
              const value = Reflect.get(boundStatement, boundProperty);
              return typeof value === "function" ? value.bind(boundStatement) : value;
            } });
          };
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    expect(await purgeArchivedRevisions(env, 30)).toBe(1);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports WHERE id = ?").get(archived.id))
      .toMatchObject({ n: 0 });
    expect(await env.EXPORTS.get(archived.key)).toBeNull();
  } finally { db.close(); }
});

it("preserves ciphertext when archived-delete verification is unavailable", async () => {
  const { env, db } = setup();
  try {
    const archived = await archivedExport(env, db);
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (query.includes("DELETE FROM exports WHERE id = ? AND NOT EXISTS")) {
          return new Proxy(statement, { get(prepared, statementProperty) {
            if (statementProperty !== "bind") {
              const value = Reflect.get(prepared, statementProperty);
              return typeof value === "function" ? value.bind(prepared) : value;
            }
            return (...values: unknown[]) => {
              const bound = prepared.bind(...values);
              return new Proxy(bound, { get(boundStatement, boundProperty) {
                if (boundProperty === "run") return async () => {
                  await boundStatement.run();
                  throw new Error("synthetic lost archived-delete response");
                };
                const value = Reflect.get(boundStatement, boundProperty);
                return typeof value === "function" ? value.bind(boundStatement) : value;
              } });
            };
          } });
        }
        if (!query.includes("SELECT 1 AS present FROM exports WHERE id = ?")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty === "first") return async () => {
                throw new Error("synthetic archived-delete verification outage");
              };
              const value = Reflect.get(boundStatement, boundProperty);
              return typeof value === "function" ? value.bind(boundStatement) : value;
            } });
          };
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    await expect(purgeArchivedRevisions(env, 30)).rejects.toThrow(
      "Archived export deletion verification is unavailable",
    );
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports WHERE id = ?").get(archived.id))
      .toMatchObject({ n: 0 });
    const objects = env.EXPORTS;
    expect(await objects.get(archived.key)).not.toBeNull();
    env.DB = original;
    env.EXPORTS = {
      list: async () => ({ objects: [{ key: archived.key }], truncated: false }),
      delete: async (key: string) => objects.delete(key),
    } as unknown as R2Bucket;
    expect(await reconcileOrphanExportObjects(env)).toMatchObject({ removed: 1 });
    expect(await objects.get(archived.key)).toBeNull();
  } finally { db.close(); }
});

it("does not advance the cursor after delete failure or touch unexpected keys", async () => {
  const { env, db } = setup();
  try {
    env.EXPORTS = {
      list: async () => ({ objects: [{ key: `v1/${randomUUID()}` }], truncated: false }),
      delete: async () => { throw new Error("synthetic R2 delete failure"); },
    } as unknown as R2Bucket;
    await expect(reconcileOrphanExportObjects(env)).rejects.toThrow("synthetic R2 delete failure");
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM maintenance_cursors").get())
      .toMatchObject({ n: 0 });

    let deleted = false;
    env.EXPORTS = {
      list: async () => ({ objects: [{ key: "v1/unexpected" }], truncated: false }),
      delete: async () => { deleted = true; },
    } as unknown as R2Bucket;
    await expect(reconcileOrphanExportObjects(env)).rejects.toThrow("Unexpected encrypted object key");
    expect(deleted).toBe(false);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM maintenance_cursors").get())
      .toMatchObject({ n: 0 });
  } finally { db.close(); }
});
