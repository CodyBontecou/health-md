import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { sha256Hex } from "../src/crypto";
import worker from "../src/index";

const root = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const password = "synthetic-account-password-for-device-tests";
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
function setup(syntheticOnly = false) {
  const dir = mkdtempSync(join(tmpdir(), "healthmd-device-grants-")); folders.push(dir);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const { env, db } = createVmEnvironment({ dataDirectory: dir, sourceDirectory: root,
    publicOrigin: origin, identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1", passwordPepper: secret(), personalMvp: !syntheticOnly,
    syntheticOnly, deviceEnrollment: true, revisionRetention: "unlimited" });
  function req(path: string, method = "GET", body?: unknown, cookie?: string, bearer?: string,
    from = origin, ip = "192.0.2.30") {
    return worker.fetch(new Request(`${origin}${path}`, { method, headers: {
      ...(body === undefined ? {} : { Origin: from, "Content-Type": "application/json",
        "X-HealthMd-Intent": "dashboard" }), ...(cookie ? { Cookie: cookie } : {}),
      ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
      ...(method === "DELETE" ? { Origin: from } : {}), "CF-Connecting-IP": ip,
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }), env);
  }
  return { env, db, req };
}

it("binds a request-only secret to an owner-approved platform, then revokes it", async () => {
  const { env, db, req } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const login = await req("/api/auth/password-login", "POST", { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")!.split(";")[0]!;
  const account = await startVmServer(env, 0, "account");
  const ingest = await startVmServer(env, 0, "ingest");
  try {
    const unenrolled = await req("/api/repair/device/status");
    expect(unenrolled.status).toBe(401);
    const created = await req("/api/repair/device/enroll", "POST", { source: "ios" });
    expect(created.status).toBe(201);
    expect(created.headers.get("cache-control")).toBe("no-store");
    const grant = await created.json() as { code: string; token: string; source: string; expiresAt: string };
    expect(grant.code).toMatch(/^\d{8}$/);
    expect(grant.token).toMatch(/^hmd_dev_[A-Za-z0-9_-]{43}$/);
    const stored = db.connection.prepare("SELECT * FROM repair_devices LIMIT 1").get() as Record<string, unknown>;
    expect(JSON.stringify(stored)).not.toContain(grant.token);
    expect(JSON.stringify(stored)).not.toContain(grant.code);
    expect((await req("/api/repair/device/status", "GET", undefined, undefined, grant.token)).status).toBe(200);
    expect((await req("/api/repair/devices", "GET", undefined, undefined, grant.token)).status).toBe(401);
    expect((await req("/api/repair/drafts", "GET", undefined, undefined, grant.token)).status).toBe(401);
    expect((await req("/api/repair/devices/approve", "POST", { code: grant.code, password })).status).toBe(401);
    expect((await req("/api/repair/devices/approve", "POST", { code: grant.code, password: "wrong" }, cookie))
      .status).toBe(401);
    expect((await req("/api/repair/devices/approve", "POST", { code: grant.code, password }, cookie,
      undefined, "https://elsewhere.example.test")).status).toBe(403);
    const approved = await req("/api/repair/devices/approve", "POST", { code: grant.code, password }, cookie);
    expect(approved.status).toBe(200);
    const { deviceId, source } = await approved.json() as { deviceId: string; source: string };
    expect(source).toBe("ios");
    expect((await req("/api/repair/devices/approve", "POST", { code: grant.code, password }, cookie)).status)
      .toBe(401);
    const status = await req("/api/repair/device/status", "GET", undefined, undefined, grant.token);
    expect(await status.json()).toMatchObject({ version: 1, status: "approved", source: "ios" });
    expect((await (await req("/api/repair/devices", "GET", undefined, cookie)).json() as {
      devices: Array<{ id: string; source: string }> }).devices).toMatchObject([{ id: deviceId, source: "ios" }]);
    expect((await req("/api/repair/device/status", "GET", undefined, undefined,
      `hmd_ing_${grant.token.slice(8)}`)).status).toBe(401);
    const ingestDenied = await req("/api/v1/exports", "POST", {}, undefined, grant.token);
    expect(ingestDenied.status).toBe(401);
    const otherId = randomUUID(); const now = new Date().toISOString();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', ?)`).run(otherId, randomUUID(), now);
    const otherToken = `hmd_ses_${Buffer.from(randomBytes(32)).toString("base64url")}`;
    db.connection.prepare(`INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)`).run(randomUUID(), otherId, await sha256Hex(otherToken),
      new Date(Date.now() + 3600_000).toISOString(), now, now);
    const otherCookie = `__Host-healthmd_cloud_session=${otherToken}`;
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, otherCookie)).status).toBe(404);
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie,
      undefined, "https://elsewhere.example.test")).status).toBe(403);
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie)).status).toBe(200);
    expect((await req("/api/repair/device/status", "GET", undefined, undefined, grant.token)).status).toBe(401);
    expect((await req("/api/repair/devices/approve", "POST", { code: grant.code, password }, cookie)).status)
      .toBe(401);
    // Test actual listener profiles, not just the Worker router.
    const hit = async (port: number, path: string, method: string) => new Promise<number>((done, fail) => {
      import("node:http").then(({ request }) => {
        const call = request({ host: "127.0.0.1", port, path, method,
          headers: { Host: "account.example.test", "X-Forwarded-Host": "account.example.test",
            "X-Forwarded-Proto": "https" } }, (res) => {
          res.resume(); res.on("end", () => done(res.statusCode ?? 0));
        }); call.on("error", fail); call.end();
      }).catch(fail);
    });
    expect(await hit(account.port, "/api/repair/device/status", "GET")).toBe(401);
    expect(await hit(ingest.port, "/api/repair/device/status", "GET")).toBe(404);
    expect(await hit(ingest.port, "/api/repair/devices", "GET")).toBe(404);
    expect(await hit(ingest.port, "/api/repair/device/enroll", "POST")).toBe(404);
  } finally { await account.close(); await ingest.close(); db.close(); }
}, 30_000);

it("rejects expired grants and unavailable profiles without disclosing scopes", async () => {
  const { env, db, req } = setup();
  try {
    expect((await req("/api/repair/device/enroll", "POST", { source: "desktop" })).status).toBe(400);
    expect((await req("/api/repair/device/enroll", "POST", { source: "android" }, undefined,
      undefined, "https://attacker.example.test")).status).toBe(403);
    const granted = await req("/api/repair/device/enroll", "POST", { source: "android" });
    const { token, code } = await granted.json() as { token: string; code: string };
    db.connection.prepare("UPDATE repair_devices SET pairing_expires_at = '2000-01-01T00:00:00Z'").run();
    expect((await req("/api/repair/device/status", "GET", undefined, undefined, token)).status).toBe(401);
    await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
    const login = await req("/api/auth/password-login", "POST", { username: "pilot", password });
    const cookie = login.headers.get("set-cookie")!.split(";")[0]!;
    expect((await req("/api/repair/devices/approve", "POST", { code, password }, cookie)).status).toBe(401);
    const second = await req("/api/repair/device/enroll", "POST", { source: "android" });
    const next = await second.json() as { code: string; token: string };
    expect((await req("/api/repair/devices/approve", "POST", { code: next.code, password }, cookie)).status)
      .toBe(200);
    db.connection.prepare("UPDATE repair_devices SET grant_expires_at = '2000-01-01T00:00:00Z' WHERE approved_at IS NOT NULL").run();
    expect((await req("/api/repair/device/status", "GET", undefined, undefined, next.token)).status).toBe(401);
    await worker.scheduled({} as ScheduledEvent, env);
    expect(db.connection.prepare("SELECT COUNT(*) AS count FROM repair_devices").get()).toMatchObject({ count: 0 });
  } finally { db.close(); }
  const synthetic = setup(true);
  try {
    expect((await synthetic.req("/api/repair/device/enroll", "POST", { source: "ios" })).status).toBe(403);
  } finally { synthetic.db.close(); }
  const disabled = setup();
  try {
    delete disabled.env.CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED;
    expect((await disabled.req("/api/repair/device/enroll", "POST", { source: "ios" })).status).toBe(403);
  } finally { disabled.db.close(); }
}, 30_000);
