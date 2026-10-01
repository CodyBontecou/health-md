import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { sha256Hex } from "../src/crypto";
import { createVmEnvironment } from "../vm/runtime";
import { reconcileUploadIntents } from "../src/upload-intents";
import { stageExportObjectExactly } from "../src/export-object-deletion";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://api.example.test";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-commit-ambiguity-"));
  roots.push(directory);
  const runtime = createVmEnvironment({
    dataDirectory: directory,
    sourceDirectory,
    publicOrigin: origin,
    identityKey: secret(),
    exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1",
    passwordPepper: secret(),
    revisionRetention: 30,
    approved: true,
  });
  const userId = randomUUID();
  const tokenId = randomUUID();
  const token = `hmd_ing_${Buffer.from(randomBytes(32)).toString("base64url")}`;
  const now = new Date().toISOString();
  runtime.db.connection.prepare(`INSERT INTO users
    (id, email_lookup, email_ciphertext, email_iv, status, created_at)
    VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(userId, randomUUID(), now);
  runtime.db.connection.prepare(`INSERT INTO ingest_tokens
    (id, user_id, name, token_hash, last_four, created_at)
    VALUES (?, ?, 'Synthetic device', ?, 'test', ?)`).run(tokenId, userId, await sha256Hex(token), now);
  return { ...runtime, userId, token };
}

const envelope = {
  schema: "healthmd.api_export",
  schema_version: 1,
  daily_record_schema: "healthmd.health_data",
  daily_record_schema_version: 8,
  exported_at: "2026-01-02T00:00:00.000Z",
  source: "ios",
  date_range: { start: "2026-01-01", end: "2026-01-01" },
  record_count: 1,
  records: [{ schema: "healthmd.health_data", schema_version: 8, date: "2026-01-01",
    raw_capture_status: "not_requested", synthetic_fixture: true }],
  failed_date_details: [],
};

function request(token: string): Request {
  return new Request(`${origin}/api/v1/exports`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(envelope),
  });
}

function ambiguousDatabase(original: D1Database, options: {
  loseBatchResponse?: boolean; failCommitVerification?: boolean;
}): D1Database {
  let lost = false;
  let verificationFailed = false;
  return new Proxy(original, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      const result = await target.batch(statements);
      if (options.loseBatchResponse && !lost) {
        lost = true;
        throw new Error("synthetic lost D1 batch response");
      }
      return result;
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      if (!options.failCommitVerification || verificationFailed ||
          !query.includes("SELECT 1 AS valid FROM exports")) return statement;
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty !== "first") {
              const value = Reflect.get(boundStatement, boundProperty);
              return typeof value === "function" ? value.bind(boundStatement) : value;
            }
            return async () => {
              verificationFailed = true;
              throw new Error("synthetic D1 verification outage");
            };
          } });
        };
      } });
    };
    const value = Reflect.get(target, property);
    return typeof value === "function" ? value.bind(target) : value;
  } }) as D1Database;
}

async function retainedState(env: ReturnType<typeof createVmEnvironment>["env"],
  db: ReturnType<typeof createVmEnvironment>["db"]) {
  const row = db.connection.prepare(`SELECT e.object_key AS objectKey, i.state
    FROM exports e JOIN upload_intents i ON i.export_id = e.id`).get() as {
      objectKey: string; state: string;
    };
  return { row, object: await env.EXPORTS.get(row.objectKey) };
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("releases its pre-body admission when envelope validation fails", async () => {
  const { env, db, token, userId } = await setup();
  try {
    const response = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: "{}",
    }), env);
    expect(response.status).toBe(422);
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM upload_admissions
      WHERE user_id = ?`).get(userId)).toEqual({ count: 0 });
  } finally { db.close(); }
});

it("creates staged ciphertext conditionally without replacing an existing opaque key", async () => {
  const { env, db } = await setup();
  try {
    const key = `v1/${randomUUID()}`;
    const first = Uint8Array.from([1, 2, 3, 4]);
    const second = Uint8Array.from([4, 3, 2, 1]);
    let observedOptions: R2PutOptions | undefined;
    const objects = env.EXPORTS;
    env.EXPORTS = new Proxy(objects, { get(target, property) {
      if (property === "put") return async (objectKey: string,
        value: ReadableStream | ArrayBuffer | ArrayBufferView | string | Blob,
        options?: R2PutOptions) => {
        observedOptions = options;
        return target.put(objectKey, value, options);
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as R2Bucket;

    await stageExportObjectExactly(env, key, first);
    expect(observedOptions?.onlyIf).toEqual({ etagDoesNotMatch: "*" });
    await expect(stageExportObjectExactly(env, key, second))
      .rejects.toThrow("Encrypted export object staging is inconsistent");
    const retained = await objects.get(key);
    expect(retained).not.toBeNull();
    expect(Array.from(new Uint8Array(await retained!.arrayBuffer()))).toEqual(Array.from(first));
  } finally { db.close(); }
});

it("recovers a lost successful R2 put only after exact staged-byte verification", async () => {
  const { env, db, token } = await setup();
  try {
    const objects = env.EXPORTS;
    env.EXPORTS = new Proxy(objects, { get(target, property) {
      if (property === "put") return async (key: string, value: ReadableStream | ArrayBuffer | ArrayBufferView |
        string | Blob, options?: R2PutOptions) => {
        await target.put(key, value, options);
        throw new Error("synthetic lost R2 put response");
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as R2Bucket;
    const response = await worker.fetch(request(token), env);
    expect(response.status).toBe(201);
    expect((await retainedState(env, db)).row.state).toBe("committed");
  } finally { db.close(); }
});

it("rejects false-success and corrupt R2 puts before metadata commit", async () => {
  for (const mode of ["missing", "corrupt"] as const) {
    const { env, db, token, userId } = await setup();
    try {
      const objectKeys: string[] = [];
      const objects = env.EXPORTS;
      env.EXPORTS = new Proxy(objects, { get(target, property) {
        if (property === "put") return async (key: string, value: ReadableStream | ArrayBuffer | ArrayBufferView |
          string | Blob, options?: R2PutOptions) => {
          objectKeys.push(key);
          if (mode === "missing") return undefined;
          if (!(value instanceof Uint8Array)) throw new Error("expected synthetic byte body");
          const altered = Uint8Array.from(value);
          const last = altered.byteLength - 1;
          altered[last] = (altered[last] ?? 0) ^ 0xff;
          return target.put(key, altered, options);
        };
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      } }) as R2Bucket;
      const response = await worker.fetch(request(token), env);
      expect(response.status).toBe(500);
      expect(db.connection.prepare("SELECT COUNT(*) AS count FROM exports WHERE user_id = ?")
        .get(userId)).toEqual({ count: 0 });
      expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_intents WHERE user_id = ?")
        .get(userId)).toEqual({ count: 0 });
      expect(objectKeys).toHaveLength(1);
      expect(await objects.get(objectKeys[0]!)).toBeNull();
    } finally { db.close(); }
  }
});

it("retains cleanup authority when staged-object verification is unreadable", async () => {
  const { env, db, token, userId } = await setup();
  try {
    const objects = env.EXPORTS;
    env.EXPORTS = new Proxy(objects, { get(target, property) {
      if (property === "head") return async () => {
        throw new Error("synthetic R2 head outage");
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as R2Bucket;
    const response = await worker.fetch(request(token), env);
    expect(response.status).toBe(500);
    expect(db.connection.prepare("SELECT state FROM upload_intents WHERE user_id = ?").get(userId))
      .toEqual({ state: "aborting" });
    const retainedReservation = db.connection.prepare(
      "SELECT reserved_bytes AS reservedBytes FROM account_storage WHERE user_id = ?",
    ).get(userId) as { reservedBytes: number };
    expect(retainedReservation.reservedBytes).toBeGreaterThan(0);
    db.connection.prepare("UPDATE upload_intents SET expires_at = ? WHERE user_id = ?")
      .run("2020-01-01T00:00:00.000Z", userId);
    env.EXPORTS = objects;
    expect(await reconcileUploadIntents(env, 25, new Date("2026-01-01T00:00:00.000Z")))
      .toEqual({ expired: 1, completed: 0 });
    expect(db.connection.prepare("SELECT reserved_bytes AS reservedBytes FROM account_storage WHERE user_id = ?")
      .get(userId)).toEqual({ reservedBytes: 0 });
  } finally { db.close(); }
});

it("cannot commit metadata after expiry cleanup claims and removes its active intent", async () => {
  const { env, db, token, userId } = await setup();
  try {
    const objectKeys: string[] = [];
    const objects = env.EXPORTS;
    env.EXPORTS = new Proxy(objects, { get(target, property) {
      if (property === "put") return async (key: string, value: ReadableStream | ArrayBuffer | ArrayBufferView |
        string | Blob, options?: R2PutOptions) => {
        objectKeys.push(key);
        return target.put(key, value, options);
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as R2Bucket;
    const original = env.DB;
    let cleanupRan = false;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async (statements: D1PreparedStatement[]) => {
        if (!cleanupRan) {
          cleanupRan = true;
          await target.prepare(`UPDATE upload_intents SET expires_at = ?
            WHERE user_id = ? AND state = 'object_written'`)
            .bind("2020-01-01T00:00:00.000Z", userId).run();
          await reconcileUploadIntents(env, 25, new Date("2026-01-01T00:00:00.000Z"));
        }
        return target.batch(statements);
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    const response = await worker.fetch(request(token), env);
    expect(response.status).toBe(500);
    expect(cleanupRan).toBe(true);
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM exports WHERE user_id = ?")
      .get(userId)).toEqual({ count: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM upload_intents WHERE user_id = ?")
      .get(userId)).toEqual({ count: 0 });
    expect(objectKeys).toHaveLength(1);
    expect(await objects.get(objectKeys[0]!)).toBeNull();
  } finally { db.close(); }
});

it("accepts a committed upload when the D1 batch response is lost", async () => {
  const { env, db, token } = await setup();
  try {
    env.DB = ambiguousDatabase(env.DB, { loseBatchResponse: true });
    const response = await worker.fetch(request(token), env);
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({ accepted: true, duplicate: false });
    const state = await retainedState(env, db);
    expect(state.row.state).toBe("committed");
    expect(state.object).not.toBeNull();
  } finally { db.close(); }
});

it("preserves committed ciphertext when post-commit verification is temporarily unavailable", async () => {
  const { env, db, token } = await setup();
  try {
    const original = env.DB;
    env.DB = ambiguousDatabase(original, { failCommitVerification: true });
    const uncertain = await worker.fetch(request(token), env);
    expect(uncertain.status).toBe(503);
    expect(await uncertain.json()).toMatchObject({ error: "commit_verification_pending" });
    const state = await retainedState(env, db);
    expect(state.row.state).toBe("committed");
    expect(state.object).not.toBeNull();

    env.DB = original;
    const retry = await worker.fetch(request(token), env);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toMatchObject({ accepted: true, duplicate: true });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 1 });
    expect(await env.EXPORTS.get(state.row.objectKey)).not.toBeNull();
  } finally { db.close(); }
});
