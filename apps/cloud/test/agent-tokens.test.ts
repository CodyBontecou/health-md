import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { createSingleUserAccount } from "../vm/bootstrap";
import { createVmEnvironment } from "../vm/runtime";

const root = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const password = "synthetic-owner-password-for-tests";
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-agent-token-test-"));
  folders.push(directory);
  const { env, db } = createVmEnvironment({
    dataDirectory: directory, sourceDirectory: root, publicOrigin: origin,
    identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }), currentKeyId: "v1",
    passwordPepper: secret(), personalMvp: true, revisionRetention: "unlimited",
  });
  env.EXPORT_ENDPOINT_ORIGIN = "https://api.example.test";
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const req = (path: string, method = "GET", cookie?: string, body?: unknown) => worker.fetch(
    new Request(`${origin}${path}`, {
      method,
      headers: {
        ...(cookie ? { Cookie: cookie } : {}),
        ...(method === "GET" ? {} : { Origin: origin, "X-HealthMd-Intent": "dashboard" }),
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env);
  const login = await req("/api/auth/password-login", "POST", undefined,
    { username: "pilot", password });
  expect(login.status).toBe(200);
  return { env, db, req, cookie: login.headers.get("set-cookie")!.split(";")[0] };
}

function ambiguousDatabase(original: D1Database, options: {
  loseBatchResponse?: boolean; failCreateVerification?: boolean; failRevokeVerification?: boolean;
}): D1Database {
  let responseLost = false;
  let verificationFailed = false;
  return new Proxy(original, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      const result = await target.batch(statements);
      if (options.loseBatchResponse && !responseLost) {
        responseLost = true;
        throw new Error("synthetic lost agent-token batch response");
      }
      return result;
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      if (verificationFailed ||
          (!options.failCreateVerification && !options.failRevokeVerification) ||
          !query.includes("FROM mcp_read_tokens t WHERE t.id = ? AND t.user_id = ?") ||
          (options.failCreateVerification && !query.includes("t.token_hash AS tokenHash")) ||
          (options.failRevokeVerification && !query.includes("t.revoked_at AS revokedAt"))) return statement;
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
              throw new Error("synthetic agent-token verification outage");
            };
          } });
        };
      } });
    };
    const value = Reflect.get(target, property);
    return typeof value === "function" ? value.bind(target) : value;
  } }) as D1Database;
}

const tokenInput = { label: "Synthetic model", days: 30, password,
  consent: true, scope: "full_export" };

it("recovers lost create and revoke responses from exact durable read-token state", async () => {
  const { env, db, req, cookie } = await setup();
  const original = env.DB;
  try {
    env.DB = ambiguousDatabase(original, { loseBatchResponse: true });
    const created = await req("/api/agent-tokens", "POST", cookie, tokenInput);
    expect(created.status).toBe(201);
    const issued = await created.json() as { id: string; token: string };
    expect(issued.token).toMatch(/^hmd_read_[A-Za-z0-9_-]{43}$/u);
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM audit_events
      WHERE target_id = ? AND event_type = 'agent_token.created'`).get(issued.id))
      .toMatchObject({ count: 1 });

    env.DB = ambiguousDatabase(original, { loseBatchResponse: true });
    expect((await req(`/api/agent-tokens/${issued.id}`, "DELETE", cookie)).status).toBe(200);
    env.DB = original;
    expect((await req(`/api/agent-tokens/${issued.id}`, "DELETE", cookie)).status).toBe(200);
    expect(db.connection.prepare("SELECT revoked_at AS revokedAt FROM mcp_read_tokens WHERE id = ?")
      .get(issued.id)).toMatchObject({ revokedAt: expect.any(String) });
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM audit_events
      WHERE target_id = ? AND event_type = 'agent_token.revoked'`).get(issued.id))
      .toMatchObject({ count: 1 });
  } finally { env.DB = original; db.close(); }
});

it("withholds read-token success while creation or revocation verification is unreadable", async () => {
  const { env, db, req, cookie } = await setup();
  const original = env.DB;
  try {
    env.DB = ambiguousDatabase(original, { failCreateVerification: true });
    const uncertainCreate = await req("/api/agent-tokens", "POST", cookie, tokenInput);
    expect(uncertainCreate.status).toBe(503);
    expect((await uncertainCreate.json() as { error: string }).error)
      .toBe("agent_token_verification_pending");
    const id = (db.connection.prepare("SELECT id FROM mcp_read_tokens ORDER BY created_at DESC LIMIT 1")
      .get() as { id: string }).id;

    env.DB = ambiguousDatabase(original, { failRevokeVerification: true });
    const uncertainRevoke = await req(`/api/agent-tokens/${id}`, "DELETE", cookie);
    expect(uncertainRevoke.status).toBe(503);
    expect((await uncertainRevoke.json() as { error: string }).error)
      .toBe("agent_token_revocation_pending");
    env.DB = original;
    expect((await req(`/api/agent-tokens/${id}`, "DELETE", cookie)).status).toBe(200);
  } finally { env.DB = original; db.close(); }
});

it("serializes the ten-active full-export read-token cap", async () => {
  const { env, db, req, cookie } = await setup();
  try {
    const user = db.connection.prepare("SELECT id FROM users LIMIT 1").get() as { id: string };
    const now = new Date().toISOString();
    const expires = new Date(Date.now() + 86_400_000).toISOString();
    const insert = db.connection.prepare(`INSERT INTO mcp_read_tokens
      (id, user_id, label, token_hash, last_four, created_at, expires_at, read_scope)
      VALUES (?, ?, 'Synthetic existing', ?, 'test', ?, ?, 'full_export')`);
    for (let index = 0; index < 9; index++) {
      insert.run(randomUUID(), user.id, randomUUID(), now, expires);
    }
    const responses = await Promise.all([
      req("/api/agent-tokens", "POST", cookie, { ...tokenInput, label: "Synthetic concurrent A" }),
      req("/api/agent-tokens", "POST", cookie, { ...tokenInput, label: "Synthetic concurrent B" }),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([201, 409]);
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM mcp_read_tokens
      WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?`).get(user.id, now))
      .toMatchObject({ count: 10 });
  } finally { db.close(); }
}, 30_000);
