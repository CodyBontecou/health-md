import { afterEach, expect, it } from "vitest";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/index";
import { limitIngest } from "../src/auth";
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
