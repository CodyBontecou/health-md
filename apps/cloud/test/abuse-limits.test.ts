import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { issueSession, limitIngest } from "../src/auth";
import { createVmEnvironment } from "../vm/runtime";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "http://localhost:8787";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-abuse-limits-"));
  roots.push(directory);
  return createVmEnvironment({
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
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

async function developmentMagicLink(env: ReturnType<typeof setup>["env"], email: string, ip: string): Promise<string> {
  env.ENVIRONMENT = "development";
  env.AUTH_MODE = "email_link";
  env.AUTH_SIGNUP_MODE = "invite";
  env.AUTH_INVITE_EMAILS = email;
  env.DEV_SHOW_MAGIC_LINK = "1";
  const response = await worker.fetch(new Request(`${origin}/api/auth/request-link`, {
    method: "POST",
    headers: { Origin: origin, "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ email }),
  }), env);
  expect(response.status).toBe(200);
  return (await response.json() as { devLink: string }).devLink;
}

function ambiguousSessionBatch(database: D1Database, verificationUnavailable = false): D1Database {
  return new Proxy(database, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      await target.batch(statements);
      throw new Error("synthetic lost session batch response");
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      if (!verificationUnavailable || !query.includes("SELECT 1 AS valid FROM sessions s")) return statement;
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty === "first") return async () => {
              throw new Error("synthetic session verification outage");
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
}

it("enforces an eligible-email provider send budget without changing the generic response", async () => {
  const { env, db } = setup();
  try {
    env.ENVIRONMENT = "development";
    env.AUTH_MODE = "email_link";
    env.AUTH_SIGNUP_MODE = "invite";
    env.AUTH_INVITE_EMAILS = "first@example.test,second@example.test";
    env.DEV_SHOW_MAGIC_LINK = "1";
    env.EMAIL_SEND_HOURLY_LIMIT = "1";
    const points: unknown[] = [];
    env.METRICS = { writeDataPoint: (point: unknown) => { points.push(point); } } as AnalyticsEngineDataset;
    const ask = (email: string) => worker.fetch(new Request(`${origin}/api/auth/request-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.10" },
      body: JSON.stringify({ email }),
    }), env);
    const first = await ask("first@example.test");
    expect(first.status).toBe(200);
    expect(await first.json()).toMatchObject({ message: "Development sign-in link generated." });
    db.connection.prepare("UPDATE users SET status = 'disabled'").run();
    const disabled = await ask("first@example.test");
    expect(disabled.status).toBe(200);
    expect(await disabled.json()).toEqual({
      message: "If this address is eligible, a sign-in link is on its way.",
    });
    const second = await ask("second@example.test");
    expect(second.status).toBe(200);
    expect(await second.json()).toEqual({
      message: "If this address is eligible, a sign-in link is on its way.",
    });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM magic_links").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT request_count AS count FROM auth_rate_limits
      WHERE bucket_key = 'auth-send:global'`).get()).toMatchObject({ count: 1 });
    expect(points).toEqual([{
      indexes: ["account"], blobs: ["email_budget_exhausted", "blocked", "not_applicable", "not_applicable"],
      doubles: [1],
    }]);
    expect(JSON.stringify(points)).not.toContain("second@example.test");
  } finally { db.close(); }
});

it("creates usable links for deterministic concurrent first-account requests", async () => {
  const { env, db } = setup();
  try {
    env.ENVIRONMENT = "development";
    env.AUTH_MODE = "email_link";
    env.AUTH_SIGNUP_MODE = "invite";
    env.AUTH_INVITE_EMAILS = "concurrent@example.test";
    env.DEV_SHOW_MAGIC_LINK = "1";
    const original = env.DB;
    let initialReads = 0;
    let releaseReads: (() => void) | undefined;
    const bothRead = new Promise<void>((resolve) => { releaseReads = resolve; });
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("SELECT * FROM users WHERE email_lookup")) return statement;
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
                const result = await boundStatement.first();
                initialReads += 1;
                if (initialReads === 2) releaseReads?.();
                await bothRead;
                return result;
              };
            } });
          };
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    const ask = () => worker.fetch(new Request(`${origin}/api/auth/request-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.20" },
      body: JSON.stringify({ email: "concurrent@example.test" }),
    }), env);
    const responses = await Promise.all([ask(), ask()]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    const links = await Promise.all(responses.map(async (response) =>
      (await response.json() as { devLink: string }).devLink));
    expect(links.every((link) => link.startsWith(`${origin}/login#token=hmd_login_`))).toBe(true);
    expect(new Set(links).size).toBe(2);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM magic_links").get()).toMatchObject({ n: 2 });
    env.DB = original;
    for (const link of links) {
      const token = new URL(link).hash.slice("#token=".length);
      const consumed = await worker.fetch(new Request(`${origin}/api/auth/consume-link`, {
        method: "POST", headers: { Origin: origin, "Content-Type": "application/json" },
        body: JSON.stringify({ token }),
      }), env);
      expect(consumed.status).toBe(200);
    }
  } finally { db.close(); }
});

it("sends a durably committed magic link after its D1 batch response is lost", async () => {
  const { env, db } = setup();
  try {
    env.ENVIRONMENT = "development";
    env.AUTH_MODE = "email_link";
    env.AUTH_SIGNUP_MODE = "invite";
    env.AUTH_INVITE_EMAILS = "ambiguous@example.test";
    env.DEV_SHOW_MAGIC_LINK = "1";
    const original = env.DB;
    let responseLost = false;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async (statements: D1PreparedStatement[]) => {
        const result = await target.batch(statements);
        if (!responseLost) {
          responseLost = true;
          throw new Error("synthetic lost magic-link batch response");
        }
        return result;
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    const response = await worker.fetch(new Request(`${origin}/api/auth/request-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.21" },
      body: JSON.stringify({ email: "ambiguous@example.test" }),
    }), env);
    expect(responseLost).toBe(true);
    expect(response.status).toBe(200);
    const link = (await response.json() as { devLink: string }).devLink;
    expect(link).toContain("#token=hmd_login_");
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM magic_links").get()).toMatchObject({ n: 1 });
    env.DB = original;
    const token = new URL(link).hash.slice("#token=".length);
    const consumed = await worker.fetch(new Request(`${origin}/api/auth/consume-link`, {
      method: "POST", headers: { Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    }), env);
    expect(consumed.status).toBe(200);
  } finally { db.close(); }
});

it("returns the magic-link session after its atomic D1 response is lost", async () => {
  const { env, db } = setup();
  try {
    const link = await developmentMagicLink(env, "claim-lost@example.test", "192.0.2.31");
    env.DB = ambiguousSessionBatch(env.DB);
    const token = new URL(link).hash.slice("#token=".length);
    const response = await worker.fetch(new Request(`${origin}/api/auth/consume-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    }), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("Set-Cookie")).toContain("=hmd_ses_");
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM magic_links
      WHERE consumed_at IS NOT NULL AND claim_nonce IS NOT NULL`).get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE event_type = 'session.created'`).get()).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("allows exactly one concurrent consumer to claim a magic link", async () => {
  const { env, db } = setup();
  try {
    const link = await developmentMagicLink(env, "claim-race@example.test", "192.0.2.32");
    const token = new URL(link).hash.slice("#token=".length);
    const consume = () => worker.fetch(new Request(`${origin}/api/auth/consume-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    }), env);
    const responses = await Promise.all([consume(), consume()]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 400]);
    expect(responses.filter((response) => response.headers.has("Set-Cookie"))).toHaveLength(1);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE event_type = 'session.created'`).get()).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("withholds a magic-link session cookie while commit verification is unavailable", async () => {
  const { env, db } = setup();
  try {
    const link = await developmentMagicLink(env, "claim-unreadable@example.test", "192.0.2.33");
    env.DB = ambiguousSessionBatch(env.DB, true);
    const token = new URL(link).hash.slice("#token=".length);
    const response = await worker.fetch(new Request(`${origin}/api/auth/consume-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    }), env);
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: "session_verification_pending" });
    expect(response.headers.get("Set-Cookie")).toBeNull();
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM magic_links
      WHERE consumed_at IS NOT NULL AND claim_nonce IS NOT NULL`).get()).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("returns a committed session after its atomic D1 batch response is lost", async () => {
  const { env, db } = setup();
  try {
    const userId = randomUUID();
    db.connection.prepare(`INSERT INTO users
      (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, 'synthetic-session', 'synthetic', 'synthetic', 'active', ?)`)
      .run(userId, new Date().toISOString());
    const original = env.DB;
    let responseLost = false;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async (statements: D1PreparedStatement[]) => {
        const result = await target.batch(statements);
        responseLost = true;
        throw new Error("synthetic lost session batch response");
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    const response = await issueSession(env, userId);
    expect(responseLost).toBe(true);
    expect(response.status).toBe(200);
    expect(response.headers.get("Set-Cookie")).toMatch(/^__Host-healthmd_cloud_session=hmd_ses_/u);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?")
      .get(userId)).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND event_type = 'session.created'`).get(userId)).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("withholds an ambiguously committed session when its durable state is unreadable", async () => {
  const { env, db } = setup();
  try {
    const userId = randomUUID();
    db.connection.prepare(`INSERT INTO users
      (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, 'synthetic-unreadable-session', 'synthetic', 'synthetic', 'active', ?)`)
      .run(userId, new Date().toISOString());
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async (statements: D1PreparedStatement[]) => {
        await target.batch(statements);
        throw new Error("synthetic lost session batch response");
      };
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (!query.includes("SELECT 1 AS valid FROM sessions s")) return statement;
        return new Proxy(statement, { get(prepared, statementProperty) {
          if (statementProperty !== "bind") {
            const value = Reflect.get(prepared, statementProperty);
            return typeof value === "function" ? value.bind(prepared) : value;
          }
          return (...values: unknown[]) => {
            const bound = prepared.bind(...values);
            return new Proxy(bound, { get(boundStatement, boundProperty) {
              if (boundProperty === "first") return async () => {
                throw new Error("synthetic session verification outage");
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
    await expect(issueSession(env, userId)).rejects.toMatchObject({
      status: 503,
      code: "session_verification_pending",
    });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?")
      .get(userId)).toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND event_type = 'session.created'`).get(userId)).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("keeps magic-link persistence failures generic and health-data-free", async () => {
  const { env, db } = setup();
  try {
    env.ENVIRONMENT = "development";
    env.AUTH_MODE = "email_link";
    env.AUTH_SIGNUP_MODE = "invite";
    env.AUTH_INVITE_EMAILS = "failure@example.test";
    env.DEV_SHOW_MAGIC_LINK = "1";
    const points: unknown[] = [];
    env.METRICS = { writeDataPoint: (point: unknown) => { points.push(point); } } as AnalyticsEngineDataset;
    const original = env.DB;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async () => {
        throw new Error("synthetic D1 write outage before commit");
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;
    const response = await worker.fetch(new Request(`${origin}/api/auth/request-link`, {
      method: "POST",
      headers: { Origin: origin, "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.22" },
      body: JSON.stringify({ email: "failure@example.test" }),
    }), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      message: "If this address is eligible, a sign-in link is on its way.",
    });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM magic_links").get()).toMatchObject({ n: 0 });
    expect(points).toEqual([{
      indexes: ["account"],
      blobs: ["magic_link_persistence_failed", "blocked", "not_applicable", "not_applicable"],
      doubles: [1],
    }]);
    expect(JSON.stringify(points)).not.toContain("failure@example.test");
  } finally { db.close(); }
});

it("enforces token and account ingest budgets before payload processing", async () => {
  const { env, db } = setup();
  try {
    env.INGEST_TOKEN_HOURLY_LIMIT = "1";
    env.INGEST_ACCOUNT_HOURLY_LIMIT = "10";
    await limitIngest(env, "token-1", "account-1");
    await expect(limitIngest(env, "token-1", "account-1")).rejects.toMatchObject({ status: 429 });

    env.INGEST_TOKEN_HOURLY_LIMIT = "10";
    env.INGEST_ACCOUNT_HOURLY_LIMIT = "2";
    await limitIngest(env, "token-a", "account-2");
    await limitIngest(env, "token-b", "account-2");
    await expect(limitIngest(env, "token-c", "account-2")).rejects.toMatchObject({ status: 429 });
    expect(db.connection.prepare(`SELECT request_count AS count FROM auth_rate_limits
      WHERE bucket_key = 'ingest-account:account-2'`).get()).toMatchObject({ count: 2 });
  } finally { db.close(); }
});
