import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createIngestToken, revokeIngestToken } from "../src/auth";
import { sha256Hex } from "../src/crypto";
import { errorResponse } from "../src/http";
import { createVmEnvironment } from "../vm/runtime";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";

function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-token-issuance-"));
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
  runtime.db.connection.prepare(`INSERT INTO users
    (id, email_lookup, email_ciphertext, email_iv, status, created_at)
    VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(userId, randomUUID(), new Date().toISOString());
  return { ...runtime, userId };
}

function request(index: number): Request {
  return new Request(`${origin}/api/ingest-tokens`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: origin },
    body: JSON.stringify({ name: `Synthetic phone ${index}` }),
  });
}

async function issue(index: number, env: ReturnType<typeof createVmEnvironment>["env"],
  userId: string): Promise<Response> {
  try { return await createIngestToken(request(index), env, userId); }
  catch (error) { return errorResponse(error); }
}

function loseFirstBatchResponse(original: D1Database): D1Database {
  let lost = false;
  return new Proxy(original, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      const result = await target.batch(statements);
      if (!lost) {
        lost = true;
        throw new Error("synthetic lost token batch response");
      }
      return result;
    };
    const value = Reflect.get(target, property);
    return typeof value === "function" ? value.bind(target) : value;
  } }) as D1Database;
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("enforces the active write-token cap inside concurrent D1 writes", async () => {
  const { env, db, userId } = setup();
  try {
    const responses = await Promise.all(Array.from({ length: 12 }, (_, index) =>
      issue(index, env, userId)));
    expect(responses.filter((response) => response.status === 201)).toHaveLength(10);
    expect(responses.filter((response) => response.status === 409)).toHaveLength(2);
    expect(db.connection.prepare(
      "SELECT COUNT(*) AS n FROM ingest_tokens WHERE user_id = ? AND revoked_at IS NULL",
    ).get(userId)).toMatchObject({ n: 10 });
    expect(db.connection.prepare(
      "SELECT COUNT(*) AS n FROM audit_events WHERE user_id = ? AND event_type = 'ingest_token.created'",
    ).get(userId)).toMatchObject({ n: 10 });
  } finally { db.close(); }
});

it("returns the exact one-time token after a lost committed batch response", async () => {
  const { env, db, userId } = setup();
  try {
    env.DB = loseFirstBatchResponse(env.DB);
    const response = await createIngestToken(request(1), env, userId);
    expect(response.status).toBe(201);
    const body = await response.json() as { id: string; token: string };
    const stored = db.connection.prepare(
      "SELECT token_hash AS tokenHash FROM ingest_tokens WHERE id = ? AND user_id = ?",
    ).get(body.id, userId) as { tokenHash: string };
    expect(stored.tokenHash).toBe(await sha256Hex(body.token));
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND target_id = ? AND event_type = 'ingest_token.created'`)
      .get(userId, body.id)).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("confirms revocation and its audit event after a lost batch response", async () => {
  const { env, db, userId } = setup();
  try {
    const created = await createIngestToken(request(1), env, userId);
    const issued = await created.json() as { id: string };
    env.DB = loseFirstBatchResponse(env.DB);
    const response = await revokeIngestToken(new Request(`${origin}/api/ingest-tokens/${issued.id}`, {
      method: "DELETE", headers: { Origin: origin },
    }), env, userId, issued.id);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ revoked: true });
    expect(db.connection.prepare(
      "SELECT revoked_at AS revokedAt FROM ingest_tokens WHERE id = ? AND user_id = ?",
    ).get(issued.id, userId)).toMatchObject({ revokedAt: expect.any(String) });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND target_id = ? AND event_type = 'ingest_token.revoked'`)
      .get(userId, issued.id)).toMatchObject({ n: 1 });
  } finally { db.close(); }
});
