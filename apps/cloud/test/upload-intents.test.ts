import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { abandonUploadIntent, acquireUploadAdmission, markUploadObjectWritten,
  reconcileUploadAdmissions, reconcileUploadIntents,
  releaseUploadAdmission, reserveUploadIntent as reserveWithAdmission,
  uploadIntentPolicy } from "../src/upload-intents";
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

async function reserveUploadIntent(env: ReturnType<typeof setup>["env"], principal: IngestPrincipal,
  digest: string, scopeDigest: string | null, byteCount: number) {
  const admission = await acquireUploadAdmission(env, principal);
  try {
    return await reserveWithAdmission(env, principal, admission, digest, scopeDigest, byteCount);
  } catch (error) {
    await releaseUploadAdmission(env, admission);
    throw error;
  }
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

function reservationDatabase(original: D1Database, options: {
  insert?: "normal" | "lost_response" | "false_success";
  failVerification?: boolean;
  admissionInsert?: "normal" | "lost_response" | "false_success";
  failAdmissionVerification?: boolean;
  admissionDelete?: "normal" | "lost_response";
}): D1Database {
  return new Proxy(original, { get(target, property) {
    if (property !== "prepare") {
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    }
    return (query: string) => {
      const statement = target.prepare(query);
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty === "run" && query.includes("INSERT INTO upload_intents")) {
              if (options.insert === "false_success") {
                return async () => target.prepare("SELECT 1").run();
              }
              if (options.insert === "lost_response") return async () => {
                await boundStatement.run();
                throw new Error("synthetic lost upload-reservation response");
              };
            }
            if (boundProperty === "run" && query.includes("INSERT INTO upload_admissions")) {
              if (options.admissionInsert === "false_success") {
                return async () => target.prepare("SELECT 1").run();
              }
              if (options.admissionInsert === "lost_response") return async () => {
                await boundStatement.run();
                throw new Error("synthetic lost upload-admission response");
              };
            }
            if (boundProperty === "run" && query.includes("DELETE FROM upload_admissions") &&
                options.admissionDelete === "lost_response") return async () => {
              await boundStatement.run();
              throw new Error("synthetic lost upload-admission delete response");
            };
            if (boundProperty === "first" && options.failAdmissionVerification &&
                query.includes("FROM upload_admissions WHERE id = ? LIMIT 1")) {
              return async () => { throw new Error("synthetic admission verification outage"); };
            }
            if (boundProperty === "first" && options.failVerification &&
                query.includes("FROM upload_intents WHERE id = ? LIMIT 1")) {
              return async () => { throw new Error("synthetic reservation verification outage"); };
            }
            const value = Reflect.get(boundStatement, boundProperty);
            return typeof value === "function" ? value.bind(boundStatement) : value;
          } });
        };
      } });
    };
  } }) as D1Database;
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("bounds pre-body admissions per account and releases them exactly", async () => {
  const { env, db } = setup();
  try {
    const firstAccount = account(db);
    const secondAccount = account(db);
    const [first, second, otherFirst, otherSecond] = await Promise.all([
      acquireUploadAdmission(env, firstAccount), acquireUploadAdmission(env, firstAccount),
      acquireUploadAdmission(env, secondAccount), acquireUploadAdmission(env, secondAccount),
    ]);
    await expect(acquireUploadAdmission(env, firstAccount))
      .rejects.toMatchObject({ status: 429, code: "account_busy" });
    await releaseUploadAdmission(env, first);
    const replacement = await acquireUploadAdmission(env, firstAccount);
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM upload_admissions
      WHERE user_id = ?`).get(firstAccount.userId)).toEqual({ count: 2 });
    await Promise.all([releaseUploadAdmission(env, second), releaseUploadAdmission(env, replacement),
      releaseUploadAdmission(env, otherFirst), releaseUploadAdmission(env, otherSecond)]);
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_admissions").get())
      .toEqual({ count: 0 });
  } finally { db.close(); }
});

it("recovers lost admission insert and release responses", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const original = env.DB;
    env.DB = reservationDatabase(original, { admissionInsert: "lost_response" });
    const admission = await acquireUploadAdmission(env, principal);
    env.DB = reservationDatabase(original, { admissionDelete: "lost_response" });
    await expect(releaseUploadAdmission(env, admission)).resolves.toBeUndefined();
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_admissions").get())
      .toEqual({ count: 0 });
  } finally { db.close(); }
});

it("does not return an admission after a false-success insert response", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    env.DB = reservationDatabase(env.DB, { admissionInsert: "false_success" });
    await expect(acquireUploadAdmission(env, principal))
      .rejects.toMatchObject({ status: 503, code: "ingest_busy" });
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_admissions").get())
      .toEqual({ count: 0 });
  } finally { db.close(); }
});

it("withholds an admission while its durable verification is unreadable", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    env.DB = reservationDatabase(env.DB, { failAdmissionVerification: true });
    await expect(acquireUploadAdmission(env, principal))
      .rejects.toMatchObject({ status: 503, code: "admission_verification_pending" });
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM upload_admissions
      WHERE user_id = ?`).get(principal.userId)).toEqual({ count: 1 });
  } finally { db.close(); }
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
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_admissions").get())
      .toEqual({ count: 0 });
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

it("recovers an exact upload reservation after its D1 response is lost", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    env.DB = reservationDatabase(env.DB, { insert: "lost_response" });
    const intent = await reserveUploadIntent(env, principal, "b".repeat(64), null, 100);
    expect(db.connection.prepare(`SELECT user_id AS userId, token_id AS tokenId, state
      FROM upload_intents WHERE id = ?`).get(intent.id)).toEqual({
      userId: principal.userId, tokenId: principal.tokenId, state: "reserved",
    });
  } finally { db.close(); }
});

it("does not return a reservation after a false-success insert response", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    env.DB = reservationDatabase(env.DB, { insert: "false_success" });
    await expect(reserveUploadIntent(env, principal, "b".repeat(64), null, 100))
      .rejects.toMatchObject({ status: 503, code: "ingest_busy" });
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_intents").get())
      .toEqual({ count: 0 });
  } finally { db.close(); }
});

it("withholds a committed reservation while its verification is unreadable", async () => {
  const { env, db } = setup();
  try {
    const principal = account(db);
    const original = env.DB;
    env.DB = reservationDatabase(original, { failVerification: true });
    await expect(reserveUploadIntent(env, principal, "b".repeat(64), null, 100))
      .rejects.toMatchObject({ status: 503, code: "reservation_verification_pending" });
    env.DB = original;
    expect(db.connection.prepare(`SELECT state, byte_count AS byteCount FROM upload_intents
      WHERE user_id = ?`).get(principal.userId)).toEqual({ state: "reserved", byteCount: 100 });
    await expect(reserveUploadIntent(env, principal, "b".repeat(64), null, 100))
      .rejects.toMatchObject({ status: 429, code: "upload_in_progress" });
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
    const expiredAdmission = await acquireUploadAdmission(env, principal);
    db.connection.prepare(`UPDATE upload_admissions SET created_at = ?, expires_at = ? WHERE id = ?`)
      .run("2019-12-31T00:00:00.000Z", "2020-01-01T00:00:00.000Z", expiredAdmission.id);

    expect(await reconcileUploadAdmissions(env, 25, new Date("2026-01-01T00:00:00.000Z")))
      .toBe(1);
    expect(await reconcileUploadIntents(env, 25, new Date("2026-01-01T00:00:00.000Z")))
      .toEqual({ expired: 1, completed: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM upload_intents").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT reserved_bytes FROM account_storage WHERE user_id = ?")
      .get(principal.userId)).toMatchObject({ reserved_bytes: 0 });
    expect(await env.EXPORTS.get(intent.objectKey)).toBeNull();
    expect(uploadIntentPolicy.maxActivePerAccount).toBe(2);
    expect(uploadIntentPolicy.admissionLeaseMs).toBe(15 * 60_000);
  } finally { db.close(); }
});
