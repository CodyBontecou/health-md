import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { abandonUploadIntent, markUploadObjectWritten, reconcileUploadIntents,
  reserveUploadIntent, uploadIntentPolicy } from "../src/upload-intents";
import type { IngestPrincipal } from "../src/types";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");

function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-intents-"));
  roots.push(directory);
  return createVmEnvironment({
    dataDirectory: directory,
    sourceDirectory,
    publicOrigin: "https://api.example.test",
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

it("bounds active uploads per account without imposing a process-global account limit", async () => {
  const { env, db } = setup();
  try {
    const firstAccount = account(db);
    const secondAccount = account(db);
    const [first, second, otherFirst, otherSecond] = await Promise.all([
      reserveUploadIntent(env, firstAccount, "a".repeat(64), null, 100),
      reserveUploadIntent(env, firstAccount, "b".repeat(64), null, 100),
      reserveUploadIntent(env, secondAccount, "c".repeat(64), null, 100),
      reserveUploadIntent(env, secondAccount, "d".repeat(64), null, 100),
    ]);
    expect(new Set([first.userId, second.userId])).toEqual(new Set([firstAccount.userId]));
    expect(new Set([otherFirst.userId, otherSecond.userId])).toEqual(new Set([secondAccount.userId]));
    await expect(reserveUploadIntent(env, firstAccount, "e".repeat(64), null, 100))
      .rejects.toMatchObject({ status: 429, code: "account_busy" });
    expect(db.connection.prepare(`SELECT reserved_bytes AS reservedBytes FROM account_storage
      WHERE user_id = ?`).get(firstAccount.userId)).toMatchObject({ reservedBytes: 200 });

    await abandonUploadIntent(env, first);
    const replacement = await reserveUploadIntent(env, firstAccount, "e".repeat(64), null, 100);
    expect(replacement.userId).toBe(firstAccount.userId);
    expect(db.connection.prepare(`SELECT reserved_bytes AS reservedBytes FROM account_storage
      WHERE user_id = ?`).get(firstAccount.userId)).toMatchObject({ reservedBytes: 200 });
  } finally { db.close(); }
});

it("accepts a successful D1 insert even when adapter change metadata is zero", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property !== "prepare") {
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("INSERT INTO upload_intents")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty !== "run") {
                const value = Reflect.get(boundStatement, boundProperty);
                return typeof value === "function" ? value.bind(boundStatement) : value;
              }
              return async () => {
                const result = await boundStatement.run();
                return { ...result, meta: { ...result.meta, changes: 0 } };
              };
            } });
          };
        } });
      };
    } }) as D1Database;
    const intent = await reserveUploadIntent(env, principal, "a".repeat(64), null, 100);
    expect(intent.userId).toBe(principal.userId);
    expect(db.connection.prepare("SELECT state FROM upload_intents WHERE id = ?").get(intent.id))
      .toMatchObject({ state: "reserved" });
  } finally { db.close(); }
});

it("accepts an exact object-written transition after its D1 response is lost", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const intent = await reserveUploadIntent(env, principal, "a".repeat(64), null, 3);
    await env.EXPORTS.put(intent.objectKey, new Uint8Array([1, 2, 3]));
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("UPDATE upload_intents SET state = 'object_written'")) return statement;
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
                throw new Error("synthetic lost object-written response");
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
    await expect(markUploadObjectWritten(env, intent)).resolves.toBeUndefined();
    expect(db.connection.prepare("SELECT state FROM upload_intents WHERE id = ?").get(intent.id))
      .toMatchObject({ state: "object_written" });
  } finally { db.close(); }
});

it("fails safely when object-written verification is unavailable", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const intent = await reserveUploadIntent(env, principal, "a".repeat(64), null, 3);
    await env.EXPORTS.put(intent.objectKey, new Uint8Array([1, 2, 3]));
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (query.includes("UPDATE upload_intents SET state = 'object_written'")) {
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
                  throw new Error("synthetic lost object-written response");
                };
                const value = Reflect.get(boundStatement, boundProperty);
                return typeof value === "function" ? value.bind(boundStatement) : value;
              } });
            };
          } });
        }
        if (!query.includes("SELECT state, updated_at AS updatedAt FROM upload_intents")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty === "first") return async () => {
                throw new Error("synthetic object-written verification outage");
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
    await expect(markUploadObjectWritten(env, intent)).rejects.toThrow(
      "Upload object-written verification is unavailable",
    );
    env.DB = original;
    await abandonUploadIntent(env, intent);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM upload_intents WHERE id = ?").get(intent.id))
      .toMatchObject({ n: 0 });
    expect(await env.EXPORTS.get(intent.objectKey)).toBeNull();
  } finally { db.close(); }
});

it("reserves quota atomically before writing an object", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    db.connection.prepare("UPDATE account_storage SET quota_bytes = 150 WHERE user_id = ?")
      .run(principal.userId);
    await reserveUploadIntent(env, principal, "a".repeat(64), null, 100);
    await expect(reserveUploadIntent(env, principal, "b".repeat(64), null, 51))
      .rejects.toMatchObject({ status: 413, code: "account_quota" });
    expect(db.connection.prepare(`SELECT committed_bytes AS committedBytes,
      reserved_bytes AS reservedBytes FROM account_storage WHERE user_id = ?`)
      .get(principal.userId)).toMatchObject({ committedBytes: 0, reservedBytes: 100 });
  } finally { db.close(); }
});

it("removes expired staged ciphertext before releasing its durable reservation", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const intent = await reserveUploadIntent(env, principal, "a".repeat(64), null, 3);
    await env.EXPORTS.put(intent.objectKey, new Uint8Array([1, 2, 3]));
    await markUploadObjectWritten(env, intent);
    db.connection.prepare("UPDATE upload_intents SET expires_at = ? WHERE id = ?")
      .run("2020-01-01T00:00:00.000Z", intent.id);

    expect(await reconcileUploadIntents(env, 25, new Date("2026-01-01T00:00:00.000Z")))
      .toEqual({ expired: 1, completed: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM upload_intents").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT reserved_bytes FROM account_storage WHERE user_id = ?")
      .get(principal.userId)).toMatchObject({ reserved_bytes: 0 });
    expect(await env.EXPORTS.get(intent.objectKey)).toBeNull();
    expect(uploadIntentPolicy.maxActivePerAccount).toBe(2);
  } finally { db.close(); }
});
