import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { currentExportKey, resolveExportKey, rewrapAccountExportKeys } from "../src/account-export-keys";
import { issueSession } from "../src/auth";
import { encryptedExportByteCount } from "../src/crypto";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://cloud.example.test";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-account-keys-"));
  roots.push(directory);
  const created = createVmEnvironment({
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
  created.env.ACCOUNT_KEY_MODE = "per_account";
  created.env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1";
  created.env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v1": secret() });
  return created;
}

function addUser(db: ReturnType<typeof setup>["db"]): string {
  const id = randomUUID();
  db.connection.prepare(`INSERT INTO users
    (id, email_lookup, email_ciphertext, email_iv, status, created_at)
    VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(id, randomUUID(), new Date().toISOString());
  return id;
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("creates distinct wrapped data keys per account and binds unwrap to the owner", async () => {
  const { env, db } = setup();
  try {
    const firstUser = addUser(db);
    const secondUser = addUser(db);
    const first = await currentExportKey(env, firstUser);
    const repeated = await currentExportKey(env, firstUser);
    const second = await currentExportKey(env, secondUser);
    expect(repeated).toEqual(first);
    expect(second.key).not.toBe(first.key);
    expect(second.keyId).not.toBe(first.keyId);
    const stored = db.connection.prepare(`SELECT wrapped_key AS wrappedKey, wrap_iv AS wrapIv
      FROM account_export_keys WHERE user_id = ?`).get(firstUser) as { wrappedKey: string; wrapIv: string };
    expect(stored.wrappedKey).not.toBe(first.key);
    expect(stored.wrapIv).not.toContain(first.key);
    expect(await resolveExportKey(env, firstUser, first.keyId)).toBe(first.key);
    await expect(resolveExportKey(env, secondUser, first.keyId)).rejects.toThrow();
    expect(await resolveExportKey(env, firstUser, "v1"))
      .toBe(JSON.parse(env.EXPORT_ENCRYPTION_KEYS_JSON).v1);
  } finally { db.close(); }
});

it("counts an exact KEK rewrap after its D1 response is lost", async () => {
  const { env, db } = setup();
  try {
    const userId = addUser(db);
    const accountKey = await currentExportKey(env, userId);
    const oldWrappingKey = JSON.parse(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON ?? "{}")["kek-v1"] as string;
    const newWrappingKey = secret();
    env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v2";
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": oldWrappingKey, "kek-v2": newWrappingKey,
    });
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("UPDATE account_export_keys SET wrapping_key_id")) return statement;
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
                throw new Error("synthetic lost key-rewrap response");
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
    expect(await rewrapAccountExportKeys(env)).toBe(1);
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v2": newWrappingKey });
    expect(await resolveExportKey(env, userId, accountKey.keyId)).toBe(accountKey.key);
  } finally { db.close(); }
});

it("retries safely when KEK rewrap verification is unavailable", async () => {
  const { env, db } = setup();
  try {
    const userId = addUser(db);
    const accountKey = await currentExportKey(env, userId);
    const oldWrappingKey = JSON.parse(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON ?? "{}")["kek-v1"] as string;
    const newWrappingKey = secret();
    env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v2";
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": oldWrappingKey, "kek-v2": newWrappingKey,
    });
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (query.includes("UPDATE account_export_keys SET wrapping_key_id")) {
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
                  throw new Error("synthetic lost key-rewrap response");
                };
                const value = Reflect.get(boundStatement, boundProperty);
                return typeof value === "function" ? value.bind(boundStatement) : value;
              } });
            };
          } });
        }
        if (!query.includes("rewrapped_at AS rewrappedAt")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty === "first") return async () => {
                throw new Error("synthetic key-rewrap verification outage");
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
    await expect(rewrapAccountExportKeys(env)).rejects.toThrow(
      "Account export key rewrap verification is unavailable",
    );
    env.DB = original;
    expect(await rewrapAccountExportKeys(env)).toBe(0);
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v2": newWrappingKey });
    expect(await resolveExportKey(env, userId, accountKey.keyId)).toBe(accountKey.key);
  } finally { db.close(); }
});

it("stores and reads new exports with an account key while preserving exact bytes", async () => {
  const { env, db } = setup();
  try {
    await createSingleUserAccount(env, "synthetic-owner", "owner@example.test",
      "synthetic-password-not-for-production");
    const user = db.connection.prepare("SELECT id FROM users").get() as { id: string };
    const session = await issueSession(env, user.id);
    const cookie = session.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
    const tokenResponse = await worker.fetch(new Request(`${origin}/api/ingest-tokens`, {
      method: "POST", headers: { Origin: origin, Cookie: cookie, "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Synthetic phone" }),
    }), env);
    const token = (await tokenResponse.json() as { token: string }).token;
    const fixture = readFileSync(resolve(sourceDirectory,
      "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
    const upload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: fixture,
    }), env);
    expect(upload.status).toBe(201);
    const receipt = await upload.json() as { id: string };
    const row = db.connection.prepare("SELECT encryption_key_id AS keyId FROM exports WHERE id = ?")
      .get(receipt.id) as { keyId: string };
    expect(row.keyId).not.toBe("v1");
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM account_export_keys WHERE user_id = ?")
      .get(user.id)).toMatchObject({ n: 1 });

    const oldWrappingKey = JSON.parse(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON ?? "{}")["kek-v1"] as string;
    const newWrappingKey = secret();
    env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v2";
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": oldWrappingKey, "kek-v2": newWrappingKey,
    });
    const rotations = await Promise.all([
      rewrapAccountExportKeys(env), rewrapAccountExportKeys(env),
    ]);
    expect(rotations.reduce((sum, value) => sum + value, 0)).toBe(1);
    expect(db.connection.prepare(`SELECT wrapping_key_id AS wrappingKeyId, rewrapped_at AS rewrappedAt
      FROM account_export_keys WHERE user_id = ?`).get(user.id)).toMatchObject({
      wrappingKeyId: "kek-v2", rewrappedAt: expect.any(String),
    });
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({ "kek-v2": newWrappingKey });
    expect(await rewrapAccountExportKeys(env)).toBe(0);

    const download = await worker.fetch(new Request(`${origin}/api/exports/${receipt.id}/download`, {
      headers: { Cookie: cookie },
    }), env);
    expect(download.status).toBe(200);
    expect(await download.text()).toBe(fixture);
    expect((await worker.fetch(new Request(`${origin}/api/dashboard/trends`, {
      headers: { Cookie: cookie },
    }), env)).status).toBe(200);

    const stored = db.connection.prepare(`SELECT object_key AS objectKey, byte_count AS byteCount
      FROM exports WHERE id = ?`).get(receipt.id) as { objectKey: string; byteCount: number };
    const bucket = env.EXPORTS;
    let materialized = false;
    env.EXPORTS = new Proxy(bucket, { get(target, property) {
      if (property === "get") return async (key: string) => {
        const object = await target.get(key);
        if (!object || key !== stored.objectKey) return object;
        return new Proxy(object, { get(body, bodyProperty) {
          if (bodyProperty === "size") return encryptedExportByteCount(stored.byteCount) + 1;
          if (bodyProperty === "arrayBuffer") return async () => {
            materialized = true;
            throw new Error("Oversized ciphertext must not be materialized");
          };
          const value = Reflect.get(body, bodyProperty);
          return typeof value === "function" ? value.bind(body) : value;
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as R2Bucket;
    const oversizedDashboard = await worker.fetch(new Request(`${origin}/api/dashboard/trends`, {
      headers: { Cookie: cookie },
    }), env);
    expect(oversizedDashboard.status).toBe(503);
    expect(await oversizedDashboard.json()).toMatchObject({ error: "unavailable_data" });
    expect(materialized).toBe(false);
    const oversizedDownload = await worker.fetch(new Request(`${origin}/api/exports/${receipt.id}/download`, {
      headers: { Cookie: cookie },
    }), env);
    expect(oversizedDownload.status).toBe(503);
    expect(await oversizedDownload.json()).toMatchObject({ error: "unavailable_data" });
    expect(materialized).toBe(false);
  } finally { db.close(); }
});

it("fails closed when wrapped key metadata is tampered", async () => {
  const { env, db } = setup();
  try {
    const userId = addUser(db);
    const key = await currentExportKey(env, userId);
    db.connection.prepare("UPDATE account_export_keys SET wrapped_key = ? WHERE user_id = ?")
      .run(Buffer.from(randomBytes(48)).toString("base64"), userId);
    await expect(resolveExportKey(env, userId, key.keyId)).rejects.toThrow();
    const oldWrappingKey = JSON.parse(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON ?? "{}")["kek-v1"] as string;
    env.CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v2";
    env.ACCOUNT_KEY_WRAPPING_KEYS_JSON = JSON.stringify({
      "kek-v1": oldWrappingKey, "kek-v2": secret(),
    });
    await expect(rewrapAccountExportKeys(env)).rejects.toThrow();
    expect(db.connection.prepare("SELECT wrapping_key_id AS id FROM account_export_keys WHERE user_id = ?")
      .get(userId)).toMatchObject({ id: "kek-v1" });
  } finally { db.close(); }
});
