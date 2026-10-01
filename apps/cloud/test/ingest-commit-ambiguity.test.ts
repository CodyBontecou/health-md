import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { sha256Hex } from "../src/crypto";
import { createVmEnvironment } from "../vm/runtime";

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
