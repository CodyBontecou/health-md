import { afterEach, expect, it } from "vitest";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { issueSession } from "../src/auth";
import { createSingleUserAccount } from "../vm/bootstrap";
import { createVmEnvironment } from "../vm/runtime";
import type { Env } from "../src/types";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-session-revocation-"));
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
  await createSingleUserAccount(created.env, "synthetic-owner", "owner@example.test",
    "synthetic-password-that-is-long-enough");
  const user = created.db.connection.prepare("SELECT id FROM users LIMIT 1").get() as { id: string };
  return { ...created, userId: user.id };
}

async function sessionCookie(env: Env, userId: string): Promise<string> {
  const response = await issueSession(env, userId);
  const cookie = response.headers.get("Set-Cookie");
  if (!cookie) throw new Error("Synthetic session cookie missing");
  return cookie.split(";", 1)[0]!;
}

function ambiguousBatch(database: D1Database, verificationUnavailable = false): D1Database {
  return new Proxy(database, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      await target.batch(statements);
      throw new Error("synthetic lost session-revocation batch response");
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      if (!verificationUnavailable || !query.includes("SELECT 1 AS valid FROM audit_events")) {
        return statement;
      }
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty === "first") return async () => {
              throw new Error("synthetic session-revocation verification outage");
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

async function accountRequest(env: Env, path: string, method: string, cookie: string): Promise<Response> {
  return worker.fetch(new Request(`${origin}${path}`, {
    method,
    headers: { Cookie: cookie, Origin: origin, "Content-Type": "application/json" },
    body: method === "GET" ? undefined : "{}",
  }), env);
}

it("reconciles a one-session revocation after its D1 response is lost", async () => {
  const { env, db, userId } = await setup();
  try {
    const currentCookie = await sessionCookie(env, userId);
    await sessionCookie(env, userId);
    const inventory = await accountRequest(env, "/api/sessions", "GET", currentCookie);
    const sessions = (await inventory.json() as { sessions: Array<{ id: string; current: boolean }> }).sessions;
    const other = sessions.find((session) => !session.current);
    if (!other) throw new Error("Synthetic other session missing");
    env.DB = ambiguousBatch(env.DB);
    const response = await accountRequest(env, `/api/sessions/${other.id}`, "DELETE", currentCookie);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ revoked: true, current: false });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?").get(userId))
      .toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND event_type = 'session.revoked' AND target_id = ?`).get(userId, other.id))
      .toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("returns the durable revoke-others count after its D1 response is lost", async () => {
  const { env, db, userId } = await setup();
  try {
    const currentCookie = await sessionCookie(env, userId);
    await sessionCookie(env, userId);
    await sessionCookie(env, userId);
    env.DB = ambiguousBatch(env.DB);
    const response = await accountRequest(env, "/api/sessions/revoke-others", "POST", currentCookie);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ revoked: 2 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?").get(userId))
      .toMatchObject({ n: 1 });
    expect(db.connection.prepare(`SELECT target_id AS targetId FROM audit_events
      WHERE user_id = ? AND event_type = 'session.others_revoked' ORDER BY occurred_at DESC LIMIT 1`)
      .get(userId)).toMatchObject({ targetId: "count:2" });
  } finally { db.close(); }
});

it("reconciles logout before clearing the current cookie", async () => {
  const { env, db, userId } = await setup();
  try {
    const cookie = await sessionCookie(env, userId);
    env.DB = ambiguousBatch(env.DB);
    const response = await accountRequest(env, "/api/auth/logout", "POST", cookie);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ signedIn: false });
    expect(response.headers.get("Set-Cookie")).toContain("Max-Age=0");
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?").get(userId))
      .toMatchObject({ n: 0 });
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM audit_events
      WHERE user_id = ? AND event_type = 'session.revoked' AND target_id IS NULL`).get(userId))
      .toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("does not claim or clear a session revocation while verification is unavailable", async () => {
  const { env, db, userId } = await setup();
  try {
    const currentCookie = await sessionCookie(env, userId);
    await sessionCookie(env, userId);
    const inventory = await accountRequest(env, "/api/sessions", "GET", currentCookie);
    const sessions = (await inventory.json() as { sessions: Array<{ id: string; current: boolean }> }).sessions;
    const other = sessions.find((session) => !session.current);
    if (!other) throw new Error("Synthetic other session missing");
    env.DB = ambiguousBatch(env.DB, true);
    const response = await accountRequest(env, `/api/sessions/${other.id}`, "DELETE", currentCookie);
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: "session_revocation_verification_pending" });
    expect(response.headers.get("Set-Cookie")).toBeNull();
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE id = ?").get(other.id))
      .toMatchObject({ n: 0 });
  } finally { db.close(); }
});
