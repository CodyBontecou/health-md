import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { issueSession } from "../src/auth";
import { processAccountDeletionById, purgeExpiredDeletionReceipts } from "../src/lifecycle";
import maintenanceWorker from "../src/maintenance-worker";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import type { Env, LifecycleMessage } from "../src/types";

const roots: string[] = [];
const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";

function secret(): string { return Buffer.from(randomBytes(32)).toString("base64"); }
function deletionStatusToken(): string {
  return `hmd_del_${Buffer.from(randomBytes(32)).toString("base64url")}`;
}
function deletionInput(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return { confirmation: "DELETE", statusToken: deletionStatusToken(), ...extra };
}

async function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-account-lifecycle-"));
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
  created.env.AUTH_MODE = "email_link";
  created.env.AUTH_SIGNUP_MODE = "invite";
  created.env.AUTH_EMAIL_FROM = "Health.md Cloud <cloud@healthmd.app>";
  created.env.RESEND_API_KEY = "synthetic-provider-secret";
  await createSingleUserAccount(created.env, "synthetic-owner", "owner@example.test",
    "synthetic-password-not-for-production");
  const user = created.db.connection.prepare("SELECT id FROM users").get() as { id: string };
  return { ...created, userId: user.id };
}

async function session(env: Env, userId: string): Promise<string> {
  const response = await issueSession(env, userId);
  const cookie = response.headers.get("set-cookie")?.split(";", 1)[0];
  if (!cookie) throw new Error("Synthetic session cookie was not issued");
  return cookie;
}

async function request(env: Env, path: string, method = "GET", body?: unknown, cookie?: string): Promise<Response> {
  return worker.fetch(new Request(`${origin}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json", Origin: origin }),
      ...(method === "GET" ? {} : { Origin: origin }),
      ...(cookie ? { Cookie: cookie } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env);
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

it("uses a fresh email-link session as deletion step-up and durably queues erasure", async () => {
  const { env, db, userId } = await setup();
  const queued: LifecycleMessage[] = [];
  env.LIFECYCLE_QUEUE = { send: async (message: LifecycleMessage) => { queued.push(message); } } as
    unknown as Queue<LifecycleMessage>;
  try {
    const cookie = await session(env, userId);
    const token = await request(env, "/api/ingest-tokens", "POST", { name: "Synthetic phone" }, cookie);
    const bearer = (await token.json() as { token: string }).token;
    const fixture = readFileSync(resolve(sourceDirectory,
      "../apple/docs/reference/generated/automation/api-export-v1.json"), "utf8");
    const upload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: fixture,
    }), env);
    expect(upload.status).toBe(201);

    const requestedStatusToken = deletionStatusToken();
    const deletion = await request(env, "/api/account/delete", "POST",
      deletionInput({ statusToken: requestedStatusToken }), cookie);
    expect(deletion.status).toBe(202);
    const receipt = await deletion.json() as {
      status: string; statusToken: string; statusExpiresAt: string
    };
    expect(receipt).toEqual({ status: "pending", statusToken: requestedStatusToken,
      statusExpiresAt: expect.any(String) });
    expect(Date.parse(receipt.statusExpiresAt)).toBeGreaterThan(Date.now());
    expect(queued).toHaveLength(1);
    expect(queued[0]).toMatchObject({ version: 1, type: "account.delete",
      deletionId: expect.stringMatching(/^[a-f0-9-]{36}$/u) });
    const deletionId = queued[0]!.deletionId;
    const pending = await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${receipt.statusToken}` },
    }), env);
    expect(await pending.json()).toEqual({ status: "pending" });
    expect((await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer hmd_del_${"A".repeat(43)}` },
    }), env)).status).toBe(401);
    expect(db.connection.prepare("SELECT status_token_hash AS hash FROM account_deletions WHERE id = ?")
      .get(deletionId)).not.toMatchObject({ hash: receipt.statusToken });
    expect((await request(env, "/api/account", "GET", undefined, cookie)).status).toBe(401);
    expect(db.connection.prepare("SELECT status FROM users WHERE id = ?").get(userId))
      .toMatchObject({ status: "disabled" });

    let acknowledged = false;
    let retried = false;
    env.SERVICE_PROFILE = "maintenance";
    await maintenanceWorker.queue({ messages: [{ body: queued[0],
      ack: () => { acknowledged = true; }, retry: () => { retried = true; } }] } as
      unknown as MessageBatch<LifecycleMessage>, env);
    expect({ acknowledged, retried }).toEqual({ acknowledged: true, retried: false });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT completed_at FROM account_deletions WHERE id = ?")
      .get(deletionId)).toMatchObject({ completed_at: expect.any(String) });
    env.SERVICE_PROFILE = undefined;
    const completed = await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${receipt.statusToken}` },
    }), env);
    expect(await completed.json()).toEqual({ status: "completed" });
    db.connection.prepare("UPDATE account_deletions SET status_expires_at = '2020-01-01T00:00:00.000Z'").run();
    await purgeExpiredDeletionReceipts(env);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM account_deletions").get()).toMatchObject({ n: 0 });
  } finally { db.close(); }
});

it("keeps a client-known receipt when a deletion commit response and verification are unavailable", async () => {
  const { env, db, userId } = await setup();
  try {
    const cookie = await session(env, userId);
    const statusToken = deletionStatusToken();
    const original = env.DB;
    let batchResponseLost = false;
    let verificationUnavailable = false;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "batch") return async (statements: D1PreparedStatement[]) => {
        const result = await target.batch(statements);
        if (!batchResponseLost) {
          batchResponseLost = true;
          throw new Error("synthetic lost D1 deletion response");
        }
        return result;
      };
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (verificationUnavailable ||
            !query.includes("SELECT 1 AS valid, completed_at AS completedAt")) {
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
              if (boundProperty !== "first") {
                const value = Reflect.get(boundStatement, boundProperty);
                return typeof value === "function" ? value.bind(boundStatement) : value;
              }
              return async () => {
                verificationUnavailable = true;
                throw new Error("synthetic D1 deletion verification outage");
              };
            } });
          };
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;

    const response = await request(env, "/api/account/delete", "POST",
      deletionInput({ statusToken }), cookie);
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: "deletion_verification_pending" });
    env.DB = original;
    expect(db.connection.prepare("SELECT status FROM users WHERE id = ?").get(userId))
      .toMatchObject({ status: "disabled" });
    const pending = await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${statusToken}` },
    }), env);
    expect(await pending.json()).toEqual({ status: "pending" });
    const deletion = db.connection.prepare("SELECT id FROM account_deletions").get() as { id: string };
    expect(await processAccountDeletionById(env, deletion.id)).toBe(true);
    const completed = await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${statusToken}` },
    }), env);
    expect(await completed.json()).toEqual({ status: "completed" });
  } finally { db.close(); }
});

it("preserves the receipt when maintenance completes before commit read-back", async () => {
  const { env, db, userId } = await setup();
  const queued: LifecycleMessage[] = [];
  env.LIFECYCLE_QUEUE = { send: async (message: LifecycleMessage) => { queued.push(message); } } as
    unknown as Queue<LifecycleMessage>;
  try {
    const cookie = await session(env, userId);
    const statusToken = deletionStatusToken();
    const original = env.DB;
    let completedBeforeRead = false;
    env.DB = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (query: string) => {
        const statement = target.prepare(query);
        if (completedBeforeRead ||
            !query.includes("SELECT 1 AS valid, completed_at AS completedAt")) return statement;
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
                completedBeforeRead = true;
                await target.batch([
                  target.prepare("DELETE FROM users WHERE id = ? AND status = 'disabled'").bind(userId),
                  target.prepare(`UPDATE account_deletions SET completed_at = ?
                    WHERE id = ? AND completed_at IS NULL`)
                    .bind(new Date().toISOString(), values[0]),
                ]);
                return bound.first();
              };
            } });
          };
        } });
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } }) as D1Database;

    const response = await request(env, "/api/account/delete", "POST",
      deletionInput({ statusToken }), cookie);
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ status: "completed", statusToken,
      statusExpiresAt: expect.any(String) });
    expect(completedBeforeRead).toBe(true);
    expect(queued).toEqual([]);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM users").get()).toMatchObject({ n: 0 });
    env.DB = original;
    const statusResponse = await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${statusToken}` },
    }), env);
    expect(await statusResponse.json()).toEqual({ status: "completed" });
  } finally { db.close(); }
});

it("expires a status credential without discarding an unfinished deletion job", async () => {
  const { env, db, userId } = await setup();
  try {
    const cookie = await session(env, userId);
    const deletion = await request(env, "/api/account/delete", "POST", deletionInput(), cookie);
    const receipt = await deletion.json() as { statusToken: string };
    const deletionRow = db.connection.prepare("SELECT id FROM account_deletions").get() as { id: string };
    db.connection.prepare("UPDATE account_deletions SET status_expires_at = '2020-01-01T00:00:00.000Z'")
      .run();
    await purgeExpiredDeletionReceipts(env);
    expect(db.connection.prepare(`SELECT completed_at, status_token_hash AS statusTokenHash
      FROM account_deletions WHERE id = ?`).get(deletionRow.id))
      .toMatchObject({ completed_at: null, statusTokenHash: null });
    expect((await worker.fetch(new Request(`${origin}/api/account/deletion-status`, {
      headers: { Authorization: `Bearer ${receipt.statusToken}` },
    }), env)).status).toBe(401);
  } finally { db.close(); }
});

it("requires a client-known high-entropy status receipt before deletion", async () => {
  const { env, db, userId } = await setup();
  try {
    const cookie = await session(env, userId);
    const missing = await request(env, "/api/account/delete", "POST", { confirmation: "DELETE" }, cookie);
    expect(missing.status).toBe(400);
    expect(await missing.json()).toMatchObject({ error: "invalid_deletion_receipt" });
    const malformed = await request(env, "/api/account/delete", "POST",
      { confirmation: "DELETE", statusToken: `hmd_del_${"a".repeat(42)}` }, cookie);
    expect(malformed.status).toBe(400);
    expect(db.connection.prepare("SELECT status FROM users WHERE id = ?").get(userId))
      .toMatchObject({ status: "active" });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM account_deletions").get())
      .toMatchObject({ n: 0 });
  } finally { db.close(); }
});

it("requires reauthentication when an email-link session is older than fifteen minutes", async () => {
  const { env, db, userId } = await setup();
  try {
    const cookie = await session(env, userId);
    db.connection.prepare("UPDATE sessions SET created_at = '2020-01-01T00:00:00.000Z'").run();
    const response = await request(env, "/api/account/delete", "POST", deletionInput(), cookie);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: "reauthentication_required" });
    expect(db.connection.prepare("SELECT status FROM users WHERE id = ?").get(userId))
      .toMatchObject({ status: "active" });
  } finally { db.close(); }
});

it("keeps session, token administration, and deletion isolated between active accounts", async () => {
  const { env, db, userId: firstUser } = await setup();
  try {
    const secondUser = randomUUID();
    db.connection.prepare(`INSERT INTO users
      (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(secondUser, randomUUID(), new Date().toISOString());
    const firstCookie = await session(env, firstUser);
    const secondCookie = await session(env, secondUser);
    const created = await request(env, "/api/ingest-tokens", "POST", { name: "Second phone" }, secondCookie);
    const secondToken = await created.json() as { id: string };
    const secondSessions = await request(env, "/api/sessions", "GET", undefined, secondCookie);
    const secondSession = (await secondSessions.json() as { sessions: Array<{ id: string }> }).sessions[0]!;

    expect((await request(env, `/api/ingest-tokens/${secondToken.id}`, "DELETE", undefined, firstCookie)).status)
      .toBe(404);
    expect((await request(env, `/api/sessions/${secondSession.id}`, "DELETE", undefined, firstCookie)).status)
      .toBe(404);
    expect(await (await request(env, "/api/ingest-tokens", "GET", undefined, firstCookie)).json())
      .toMatchObject({ tokens: [] });
    expect(await (await request(env, "/api/sessions/revoke-others", "POST", {}, firstCookie)).json())
      .toMatchObject({ revoked: 0 });
    expect((await request(env, "/api/sessions", "GET", undefined, secondCookie)).status).toBe(200);
    const hiddenTarget = randomUUID();
    db.connection.prepare(`INSERT INTO audit_events
      (id, user_id, event_type, target_id, occurred_at) VALUES (?, ?, 'internal.unreviewed', ?, ?)`)
      .run(randomUUID(), secondUser, hiddenTarget, new Date().toISOString());
    const firstActivity = await (await request(env, "/api/security-events", "GET", undefined,
      firstCookie)).json() as { events: Array<{ type: string }> };
    const secondActivityResponse = await request(env, "/api/security-events", "GET", undefined,
      secondCookie);
    const secondActivityText = await secondActivityResponse.text();
    const secondActivity = JSON.parse(secondActivityText) as { events: Array<{ type: string }> };
    expect(firstActivity.events.some((event) => event.type === "ingest_token.created")).toBe(false);
    expect(secondActivity.events.map((event) => event.type)).toEqual(expect.arrayContaining([
      "session.created", "ingest_token.created",
    ]));
    expect(secondActivity.events.some((event) => event.type === "internal.unreviewed")).toBe(false);
    expect(secondActivityText).not.toContain(secondToken.id);
    expect(secondActivityText).not.toContain(hiddenTarget);

    const deletion = await request(env, "/api/account/delete", "POST", deletionInput(), firstCookie);
    expect(deletion.status).toBe(202);
    const deletionRow = db.connection.prepare("SELECT id FROM account_deletions WHERE user_id = ?")
      .get(firstUser) as { id: string };
    expect(await processAccountDeletionById(env, deletionRow.id)).toBe(true);
    expect((await request(env, "/api/sessions", "GET", undefined, secondCookie)).status).toBe(200);
    expect(db.connection.prepare("SELECT status FROM users WHERE id = ?").get(secondUser))
      .toMatchObject({ status: "active" });
    expect(db.connection.prepare("SELECT revoked_at FROM ingest_tokens WHERE id = ?")
      .get(secondToken.id)).toMatchObject({ revoked_at: null });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?")
      .get(secondUser)).toMatchObject({ n: 1 });
  } finally { db.close(); }
});

it("bounds reviewed security activity and never returns target identifiers", async () => {
  const { env, db, userId } = await setup();
  try {
    const ownerCookie = await session(env, userId);
    const targets: string[] = [];
    for (let index = 0; index < 60; index += 1) {
      const target = randomUUID(); targets.push(target);
      db.connection.prepare(`INSERT INTO audit_events
        (id, user_id, event_type, target_id, occurred_at)
        VALUES (?, ?, 'ingest_token.revoked', ?, ?)`)
        .run(randomUUID(), userId, target, new Date(Date.now() + index).toISOString());
    }
    const response = await request(env, "/api/security-events", "GET", undefined, ownerCookie);
    expect(response.status).toBe(200);
    const text = await response.text();
    const events = (JSON.parse(text) as { events: Array<{ type: string; occurredAt: string }> }).events;
    expect(events).toHaveLength(50);
    expect(events.every((event) => event.type === "ingest_token.revoked")).toBe(true);
    expect(targets.some((target) => text.includes(target))).toBe(false);
  } finally { db.close(); }
});

it("lists and revokes only account-owned browser sessions", async () => {
  const { env, db, userId } = await setup();
  try {
    const first = await session(env, userId);
    const second = await session(env, userId);
    const inventory = await request(env, "/api/sessions", "GET", undefined, first);
    const sessions = (await inventory.json() as { sessions: Array<{ id: string; current: boolean }> }).sessions;
    expect(sessions).toHaveLength(2);
    const other = sessions.find((entry) => !entry.current);
    expect(other).toBeDefined();
    expect((await request(env, `/api/sessions/${other?.id}`, "DELETE", undefined, first)).status).toBe(200);
    expect((await request(env, "/api/account", "GET", undefined, second)).status).toBe(401);

    const third = await session(env, userId);
    const revoked = await request(env, "/api/sessions/revoke-others", "POST", {}, first);
    expect(await revoked.json()).toMatchObject({ revoked: 1 });
    expect((await request(env, "/api/account", "GET", undefined, third)).status).toBe(401);
    const current = sessions.find((entry) => entry.current);
    const self = await request(env, `/api/sessions/${current?.id}`, "DELETE", undefined, first);
    expect(self.status).toBe(200);
    expect(self.headers.get("set-cookie")).toContain("Max-Age=0");
  } finally { db.close(); }
});
