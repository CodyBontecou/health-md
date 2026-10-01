import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { sha256Hex } from "../src/crypto";
import { authenticateReadToken } from "../mcp/auth";
import worker from "../src/index";

const sourceDirectory = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const password = "synthetic-owner-password-for-dispatch";
const vectors = JSON.parse(readFileSync(resolve(sourceDirectory,
  "../../packages/contracts/cloud-repair/v1/fixtures/review-only-dispatch-v1.json"), "utf8")) as {
    invalid_owner_queue_bodies: unknown[];
    device_claim_example: { request: Record<string, unknown> };
    device_empty: { version: number; request: null };
  };
const scope = { source: "ios", dates: ["2026-04-01", "2026-04-02"], scope: "metric_ids",
  metricIds: ["steps", "sleep_total"], detail: "summary" };
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
function setup(dispatch = true, enrollment = true, syntheticOnly = false) {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-dispatch-synthetic-")); folders.push(directory);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const { env, db } = createVmEnvironment({ dataDirectory: directory, sourceDirectory,
    publicOrigin: origin, identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1", passwordPepper: secret(), personalMvp: !syntheticOnly,
    syntheticOnly, deviceEnrollment: enrollment, repairDispatch: dispatch, revisionRetention: "unlimited" });
  function req(path: string, method = "GET", body?: unknown, cookie?: string, bearer?: string,
    from = origin) {
    return worker.fetch(new Request(`${origin}${path}`, { method, headers: {
      ...(cookie ? { Cookie: cookie } : {}), ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
      ...(body === undefined ? (from === origin ? {} : { Origin: from }) :
        { Origin: from, "Content-Type": "application/json", "X-HealthMd-Intent": "dashboard" }),
      ...(method === "DELETE" ? { Origin: from } : {}),
      "CF-Connecting-IP": "192.0.2.24",
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }), env);
  }
  return { env, db, directory, req };
}
type TestEnv = ReturnType<typeof setup>;
async function owner(test: TestEnv) {
  await createSingleUserAccount(test.env, "pilot", "pilot@example.test", password);
  const login = await test.req("/api/auth/password-login", "POST", { username: "pilot", password });
  expect(login.status).toBe(200);
  return login.headers.get("set-cookie")!.split(";")[0]!;
}
async function approve(test: TestEnv, cookie: string, source: "ios" | "android") {
  const created = await test.req("/api/repair/device/enroll", "POST", { source });
  expect(created.status).toBe(201);
  const { code, token } = await created.json() as { code: string; token: string };
  const approved = await test.req("/api/repair/devices/approve", "POST", { code, password }, cookie);
  expect(approved.status).toBe(200);
  const { deviceId } = await approved.json() as { deviceId: string };
  return { deviceId, token };
}
async function draft(test: TestEnv, cookie: string, spec: unknown = scope) {
  const response = await test.req("/api/repair/drafts", "POST", spec, cookie);
  expect(response.status).toBe(201);
  return (await response.json() as { id: string }).id;
}
const queue = (test: TestEnv, cookie: string, draftId: string, deviceId: string) =>
  test.req("/api/repair/dispatch", "POST", { draftId, deviceId }, cookie);
const claim = (test: TestEnv, token: string) =>
  test.req("/api/repair/device/claim", "POST", undefined, undefined, token);
const resume = (test: TestEnv, token: string) =>
  test.req("/api/repair/device/resume", "POST", undefined, undefined, token);

function ambiguousDeviceDatabase(original: D1Database, options: {
  loseEnrollmentResponse?: boolean; loseBatchResponse?: boolean;
  failEnrollmentVerification?: boolean; failApprovalVerification?: boolean;
  failRevocationVerification?: boolean;
}): D1Database {
  let responseLost = false;
  let verificationFailed = false;
  return new Proxy(original, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      const result = await target.batch(statements);
      if (options.loseBatchResponse && !responseLost) {
        responseLost = true;
        throw new Error("synthetic lost repair-device batch response");
      }
      return result;
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty === "run" && options.loseEnrollmentResponse && !responseLost &&
                query.includes("INSERT INTO repair_devices")) return async () => {
              await boundStatement.run();
              responseLost = true;
              throw new Error("synthetic lost repair-device enrollment response");
            };
            const failRead = boundProperty === "first" && !verificationFailed && (
              (options.failEnrollmentVerification && query.includes("token_hash AS tokenHash")) ||
              (options.failApprovalVerification && query.includes("d.user_id AS userId") &&
                query.includes("d.grant_expires_at AS grantExpiresAt")) ||
              (options.failRevocationVerification && query.includes("AS activeDispatch")));
            if (failRead) return async () => {
              verificationFailed = true;
              throw new Error("synthetic repair-device verification outage");
            };
            const value = Reflect.get(boundStatement, boundProperty);
            return typeof value === "function" ? value.bind(boundStatement) : value;
          } });
        };
      } });
    }
    const value = Reflect.get(target, property);
    return typeof value === "function" ? value.bind(target) : value;
  } }) as D1Database;
}

it("recovers lost repair-device enrollment, approval and revocation responses", async () => {
  const test = setup(); const { env, db, req } = test;
  const original = env.DB;
  try {
    const cookie = await owner(test);
    env.DB = ambiguousDeviceDatabase(original, { loseEnrollmentResponse: true });
    const enrollment = await req("/api/repair/device/enroll", "POST", { source: "ios" });
    expect(enrollment.status).toBe(201);
    const issued = await enrollment.json() as { code: string; token: string };

    env.DB = ambiguousDeviceDatabase(original, { loseBatchResponse: true });
    const approval = await req("/api/repair/devices/approve", "POST",
      { code: issued.code, password }, cookie);
    expect(approval.status).toBe(200);
    const deviceId = (await approval.json() as { deviceId: string }).deviceId;
    env.DB = original;
    const draftId = await draft(test, cookie);
    expect((await queue(test, cookie, draftId, deviceId)).status).toBe(201);

    env.DB = ambiguousDeviceDatabase(original, { loseBatchResponse: true });
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie)).status).toBe(200);
    env.DB = original;
    db.connection.prepare(`DELETE FROM audit_events
      WHERE target_id = ? AND event_type = 'repair_device.revoked'`).run(deviceId);
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie)).status).toBe(200);
    expect(db.connection.prepare(`SELECT state FROM repair_dispatches WHERE device_id = ?`)
      .get(deviceId)).toMatchObject({ state: "cancelled" });
    expect(db.connection.prepare(`SELECT COUNT(*) AS count FROM audit_events
      WHERE target_id = ? AND event_type = 'repair_device.revoked'`).get(deviceId))
      .toMatchObject({ count: 1 });
  } finally { env.DB = original; db.close(); }
});

it("withholds repair-device success while exact durable verification is unreadable", async () => {
  const test = setup(); const { env, db, req } = test;
  const original = env.DB;
  try {
    const cookie = await owner(test);
    env.DB = ambiguousDeviceDatabase(original, { failEnrollmentVerification: true });
    const uncertainEnrollment = await req("/api/repair/device/enroll", "POST", { source: "ios" });
    expect(uncertainEnrollment.status).toBe(503);
    expect((await uncertainEnrollment.json() as { error: string }).error)
      .toBe("device_enrollment_verification_pending");

    env.DB = original;
    const enrollment = await req("/api/repair/device/enroll", "POST", { source: "ios" });
    const issued = await enrollment.json() as { code: string };
    env.DB = ambiguousDeviceDatabase(original, { failApprovalVerification: true });
    const uncertainApproval = await req("/api/repair/devices/approve", "POST",
      { code: issued.code, password }, cookie);
    expect(uncertainApproval.status).toBe(503);
    expect((await uncertainApproval.json() as { error: string }).error)
      .toBe("device_approval_verification_pending");
    const deviceId = (db.connection.prepare(`SELECT id FROM repair_devices
      WHERE approved_at IS NOT NULL ORDER BY approved_at DESC LIMIT 1`).get() as { id: string }).id;

    env.DB = ambiguousDeviceDatabase(original, { failRevocationVerification: true });
    const uncertainRevoke = await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie);
    expect(uncertainRevoke.status).toBe(503);
    expect((await uncertainRevoke.json() as { error: string }).error)
      .toBe("device_revocation_verification_pending");
    env.DB = original;
    expect((await req(`/api/repair/devices/${deviceId}`, "DELETE", undefined, cookie)).status).toBe(200);
  } finally { env.DB = original; db.close(); }
});

it("binds a short-lived, review-only request to exactly one owner-approved device", async () => {
  const test = setup(); const { env, db, req } = test;
  try {
    const cookie = await owner(test);
    const ios = await approve(test, cookie, "ios");
    const android = await approve(test, cookie, "android");
    const firstDraft = await draft(test, cookie);
    for (const invalid of vectors.invalid_owner_queue_bodies) {
      expect((await req("/api/repair/dispatch", "POST", invalid, cookie)).status).toBe(400);
    }
    expect((await req("/api/repair/dispatch", "POST", { draftId: firstDraft,
      deviceId: ios.deviceId, forceReplacement: true }, cookie)).status).toBe(400);
    expect((await req("/api/repair/dispatch", "POST", { draftId: firstDraft, deviceId: ios.deviceId })).status)
      .toBe(401);
    expect((await queue(test, cookie, firstDraft, android.deviceId)).status).toBe(409);
    expect((await queue(test, cookie, firstDraft, ios.deviceId)).status).toBe(201);
    const list = await req("/api/repair/dispatches", "GET", undefined, cookie);
    const before = await list.json() as { requests: Array<{ id: string; state: string; uploadEnabled: boolean }> };
    expect(list.headers.get("cache-control")).toBe("no-store");
    expect(before.requests).toMatchObject([{ state: "queued", uploadEnabled: false }]);
    const requestId = before.requests[0]!.id;
    expect(JSON.stringify(before)).not.toContain(scope.dates[0]);
    expect(JSON.stringify(before)).not.toContain("steps");
    expect((await queue(test, cookie, firstDraft, ios.deviceId)).status).toBe(409);
    const encrypted = db.connection.prepare("SELECT spec_ciphertext AS encrypted FROM repair_drafts WHERE id = ?")
      .get(firstDraft) as { encrypted: string };
    expect(encrypted.encrypted).not.toContain(scope.dates[0]);
    expect((await claim(test, android.token)).status).toBe(200);
    expect(await (await resume(test, android.token)).json()).toMatchObject(vectors.device_empty);
    const claimed = await claim(test, ios.token);
    expect(claimed.status).toBe(200);
    expect(claimed.headers.get("cache-control")).toBe("no-store");
    const result = await claimed.json() as { request: { id: string; spec: unknown; uploadEnabled: boolean;
      uploadMode: string; expiresAt: string; launchable: boolean } };
    expect(result.request).toMatchObject({ ...vectors.device_claim_example.request,
      id: requestId, expiresAt: result.request.expiresAt });
    expect(Date.parse(result.request.expiresAt) - Date.now()).toBeLessThanOrEqual(15 * 60_000);
    expect(Date.parse(result.request.expiresAt) - Date.now()).toBeGreaterThan(0);
    expect(JSON.stringify(result)).not.toContain("hmd_dev_");
    expect(JSON.stringify(result)).not.toContain("https://api.healthmd.app/api/v1/exports");
    // Lost HTTP response: only the bound phone can read the same already
    // claimed request again; repeating claim never creates a second claim.
    expect(await (await resume(test, ios.token)).json()).toMatchObject({ request: result.request });
    expect(await (await claim(test, ios.token)).json()).toMatchObject({ request: result.request });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM repair_dispatches WHERE state = 'claimed'").get())
      .toMatchObject({ n: 1 });
    const androidDraft = await draft(test, cookie, { source: "android", dates: ["2026-04-07"],
      scope: "entire_days", metricIds: [], detail: "time_series" });
    expect((await queue(test, cookie, androidDraft, android.deviceId)).status).toBe(201);
    expect(await (await claim(test, android.token)).json()).toMatchObject({ request: {
      source: "android", spec: { source: "android", dates: ["2026-04-07"],
        scope: "entire_days", metricIds: [] }, uploadEnabled: false,
    } });
    expect((await req("/api/repair/device/claim", "POST", undefined, undefined,
      "hmd_ing_not-a-device")).status).toBe(401);
    expect((await req("/api/v1/exports", "POST", {}, undefined, ios.token)).status).toBe(401);
    expect(authenticateReadToken(db.connection, `Bearer ${ios.token}`)).toBeNull();
    expect((await req("/api/explore/exports", "POST", {}, undefined, ios.token)).status).toBe(401);
    expect((await req("/api/repair/dispatch", "POST", { draftId: firstDraft, deviceId: ios.deviceId },
      cookie, undefined, "https://attacker.example.test")).status).toBe(403);
    const foreign = randomUUID(); const now = new Date().toISOString();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', ?)`).run(foreign, randomUUID(), now);
    const sessionToken = `hmd_ses_${Buffer.from(randomBytes(32)).toString("base64url")}`;
    db.connection.prepare(`INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)`).run(randomUUID(), foreign, await sha256Hex(sessionToken),
      new Date(Date.now() + 3_600_000).toISOString(), now, now);
    const foreignCookie = `__Host-healthmd_cloud_session=${sessionToken}`;
    expect((await queue(test, foreignCookie, firstDraft, ios.deviceId)).status).toBe(404);
    expect(await (await req("/api/repair/dispatches", "GET", undefined, foreignCookie)).json())
      .toMatchObject({ requests: [] });
    expect((await req("/api/repair/dispatch/cancel", "POST", { id: requestId }, foreignCookie)).status)
      .toBe(404);
    expect((await req("/api/repair/device/decline", "POST", { id: requestId },
      undefined, android.token)).status).toBe(404);
    const decline = await req("/api/repair/device/decline", "POST", { id: requestId }, undefined, ios.token);
    expect(decline.status).toBe(200);
    expect((await resume(test, ios.token).then((response) => response.json()))).toMatchObject({ request: null });
    expect((await req("/api/repair/device/decline", "POST", { id: requestId },
      undefined, ios.token)).status).toBe(404);
    expect((await req("/api/repair/dispatch/cancel", "POST", { id: requestId,
      forceReplacement: true }, cookie)).status).toBe(400);
    expect(JSON.stringify(await req("/api/repair/dispatches", "GET", undefined, cookie)
      .then((response) => response.json()))).not.toContain(scope.dates[0]);
    // The staged schema has a reserved confirmed state, but without a
    // verified ingest receipt it must never be presented as an upload success.
    db.connection.prepare("UPDATE repair_dispatches SET state = 'confirmed' WHERE id = ?")
      .run(requestId);
    expect((await (await req("/api/repair/dispatches", "GET", undefined, cookie)).json() as {
      requests: Array<{ id: string; state: string }> }).requests.find((item) => item.id === requestId))
      .toMatchObject({ state: "unverified" });
    expect(env.CLOUD_REPAIR_DISPATCH_ENABLED).toBe("1");
  } finally { db.close(); }
}, 30_000);

it("enforces one active dispatch per phone, cancellation, expiry and revocation", async () => {
  const test = setup(); const { db, req, env } = test;
  try {
    const cookie = await owner(test);
    const device = await approve(test, cookie, "ios");
    const one = await draft(test, cookie);
    const two = await draft(test, cookie, { ...scope, dates: ["2026-04-03"] });
    const [a, b] = await Promise.all([queue(test, cookie, one, device.deviceId),
      queue(test, cookie, two, device.deviceId)]);
    expect([a.status, b.status].sort()).toEqual([201, 409]);
    expect(db.connection.prepare(`SELECT COUNT(*) AS n FROM repair_dispatches
      WHERE state = 'queued'`).get()).toMatchObject({ n: 1 });
    const boundDraft = (db.connection.prepare("SELECT draft_id AS id FROM repair_dispatches")
      .get() as { id: string }).id;
    const usedRequest = (db.connection.prepare("SELECT id FROM repair_dispatches").get() as { id: string }).id;
    expect((await req("/api/repair/dispatch/cancel", "POST", { id: usedRequest }, cookie,
      undefined, "https://attacker.example.test")).status).toBe(403);
    expect((await req("/api/repair/dispatch/cancel", "POST", { id: usedRequest }, cookie)).status).toBe(200);
    expect(await (await claim(test, device.token)).json()).toMatchObject({ request: null });
    expect((await queue(test, cookie, boundDraft, device.deviceId)).status).toBe(409);
    const otherDraft = boundDraft === one ? two : one;
    expect((await queue(test, cookie, otherDraft, device.deviceId)).status).toBe(201);
    const secondRequest = (db.connection.prepare("SELECT id FROM repair_dispatches WHERE state = 'queued'")
      .get() as { id: string }).id;
    expect((await claim(test, device.token)).status).toBe(200);
    // Cancelling the draft erases its ciphertext and disables an existing claim.
    expect((await req(`/api/repair/drafts/${otherDraft}`, "DELETE", undefined, cookie)).status).toBe(200);
    expect(db.connection.prepare("SELECT spec_ciphertext AS value FROM repair_drafts WHERE id = ?")
      .get(otherDraft)).toMatchObject({ value: "" });
    expect(db.connection.prepare("SELECT state FROM repair_dispatches WHERE id = ?")
      .get(secondRequest)).toMatchObject({ state: "cancelled" });
    expect(await (await resume(test, device.token)).json()).toMatchObject({ request: null });
    const third = await draft(test, cookie, { ...scope, dates: ["2026-04-05"] });
    expect((await queue(test, cookie, third, device.deviceId)).status).toBe(201);
    db.connection.prepare("UPDATE repair_dispatches SET expires_at = '2000-01-01T00:00:00Z' WHERE state = 'queued'")
      .run();
    expect(await (await claim(test, device.token)).json()).toMatchObject({ request: null });
    expect((await (await req("/api/repair/dispatches", "GET", undefined, cookie)).json() as {
      requests: Array<{ state: string }> }).requests[0]).toMatchObject({ state: "expired" });
    expect((await queue(test, cookie, third, device.deviceId)).status).toBe(409);
    const fourth = await draft(test, cookie, { ...scope, dates: ["2026-04-06"] });
    expect((await queue(test, cookie, fourth, device.deviceId)).status).toBe(201);
    expect((await req(`/api/repair/devices/${device.deviceId}`, "DELETE", undefined, cookie)).status).toBe(200);
    expect((await claim(test, device.token)).status).toBe(401);
    expect(db.connection.prepare("SELECT state FROM repair_dispatches WHERE draft_id = ?")
      .get(fourth)).toMatchObject({ state: "cancelled" });
    await worker.scheduled({} as ScheduledEvent, env);
  } finally { db.close(); }
}, 30_000);

it("has one atomic claim under concurrent polls and stops serving expired or revoked grants", async () => {
  const test = setup(); const { db, req } = test;
  try {
    const cookie = await owner(test);
    const device = await approve(test, cookie, "ios");
    const boundedGrant = new Date(Date.now() + 70_000).toISOString();
    db.connection.prepare("UPDATE repair_devices SET grant_expires_at = ? WHERE id = ?")
      .run(boundedGrant, device.deviceId);
    const first = await draft(test, cookie);
    const queued = await queue(test, cookie, first, device.deviceId);
    expect(queued.status).toBe(201);
    expect(Date.parse((await queued.json() as { expiresAt: string }).expiresAt))
      .toBeLessThanOrEqual(Date.parse(boundedGrant));
    const attempts = await Promise.all([claim(test, device.token), claim(test, device.token)]);
    expect(attempts.filter((response) => response.status === 200).length).toBeGreaterThanOrEqual(1);
    expect(attempts.every((response) => response.status === 200 || response.status === 409)).toBe(true);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM repair_dispatches WHERE state = 'claimed'").get())
      .toMatchObject({ n: 1 });
    expect((await resume(test, device.token)).status).toBe(200);
    const forgedOrigin = await req("/api/repair/device/claim", "POST", undefined, undefined,
      device.token, "https://attacker.example.test");
    // No browser origin is required for a native request, but a conflicting
    // supplied browser Origin is never accepted even with a device token.
    expect(forgedOrigin.status).toBe(403);
    db.connection.prepare("UPDATE repair_dispatches SET expires_at = '2000-01-01T00:00:00Z'").run();
    expect(await (await resume(test, device.token)).json()).toMatchObject({ request: null });
    db.connection.prepare("UPDATE repair_devices SET grant_expires_at = '2000-01-01T00:00:00Z'").run();
    expect((await resume(test, device.token)).status).toBe(401);
  } finally { db.close(); }
}, 30_000);

it("serves approved claims only on the account-authority listener, never on public ingest", async () => {
  const test = setup(); const { env, db } = test;
  const account = await startVmServer(env, 0, "account");
  const ingest = await startVmServer(env, 0, "ingest");
  try {
    const cookie = await owner(test);
    const device = await approve(test, cookie, "ios");
    const draftId = await draft(test, cookie);
    const hit = async (port: number, path: string, authorization?: string, body?: unknown,
      session?: string) => new Promise<{ status: number; body: string; cache?: string }>((done, fail) => {
      import("node:http").then(({ request }) => {
        const call = request({ host: "127.0.0.1", port, path, method: "POST", headers: {
          Host: "account.example.test", "X-Forwarded-Host": "account.example.test",
          "X-Forwarded-Proto": "https", "X-Forwarded-For": "192.0.2.24",
          ...(authorization ? { Authorization: `Bearer ${authorization}` } : {}),
          ...(body === undefined ? {} : { Origin: origin, "Content-Type": "application/json",
            "X-HealthMd-Intent": "dashboard" }), ...(session ? { Cookie: session } : {}),
        } }, (res) => {
          const chunks: Uint8Array[] = [];
          res.on("data", (chunk: Uint8Array) => chunks.push(chunk));
          res.on("end", () => done({ status: res.statusCode ?? 0,
            body: Buffer.concat(chunks).toString("utf8"), cache: res.headers["cache-control"] }));
        }); call.on("error", fail); call.end(body === undefined ? undefined : JSON.stringify(body));
      }).catch(fail);
    });
    const ownerQueued = await hit(account.port, "/api/repair/dispatch", undefined,
      { draftId, deviceId: device.deviceId }, cookie);
    expect(ownerQueued.status).toBe(201);
    expect(ownerQueued.cache).toBe("no-store");
    expect((await hit(ingest.port, "/api/repair/device/claim", device.token)).status).toBe(404);
    const claimed = await hit(account.port, "/api/repair/device/claim", device.token);
    expect(claimed.status).toBe(200);
    expect(claimed.cache).toBe("no-store");
    expect(JSON.parse(claimed.body)).toMatchObject({ request: {
      spec: { source: "ios", metricIds: ["sleep_total", "steps"] }, uploadEnabled: false,
    } });
    expect((await hit(account.port, "/api/v1/exports", device.token)).status).toBe(404);
    expect((await hit(ingest.port, "/api/repair/dispatch", device.token, { draftId,
      deviceId: device.deviceId })).status).toBe(404);
  } finally { await account.close(); await ingest.close(); db.close(); }
}, 30_000);

it("keeps the account ingress distinct from ingest and disables dispatch by default or in preview", async () => {
  const test = setup(false);
  const { env, db, req } = test;
  const account = await startVmServer(env, 0, "account");
  const ingest = await startVmServer(env, 0, "ingest");
  try {
    const cookie = await owner(test);
    const device = await approve(test, cookie, "ios");
    const id = await draft(test, cookie);
    expect((await queue(test, cookie, id, device.deviceId)).status).toBe(403);
    expect((await claim(test, device.token)).status).toBe(403);
    expect((await resume(test, device.token)).status).toBe(403);
    expect((await req("/api/repair/dispatches", "GET", undefined, cookie)).status).toBe(200);
    const hit = async (port: number, path: string, method: string) => new Promise<number>((done, fail) => {
      import("node:http").then(({ request }) => {
        const call = request({ host: "127.0.0.1", port, path, method,
          headers: { Host: "account.example.test", "X-Forwarded-Host": "account.example.test",
            "X-Forwarded-Proto": "https" } }, (res) => {
          res.resume(); res.on("end", () => done(res.statusCode ?? 0));
        }); call.on("error", fail); call.end();
      }).catch(fail);
    });
    expect(await hit(ingest.port, "/api/repair/device/claim", "POST")).toBe(404);
    expect(await hit(ingest.port, "/api/repair/dispatches", "GET")).toBe(404);
    expect(await hit(account.port, "/api/repair/dispatches", "GET")).toBe(401);
    expect(await hit(account.port, "/api/repair/device/claim", "POST")).toBe(403);
    expect(await hit(account.port, "/api/v1/exports", "POST")).toBe(404);
  } finally { await account.close(); await ingest.close(); db.close(); }
  const preview = setup(true, true, true);
  try {
    expect((await preview.req("/api/repair/device/claim", "POST")).status).toBe(403);
  } finally { preview.db.close(); }
  const missingEnrollment = setup(true, false);
  try {
    expect((await missingEnrollment.req("/api/repair/device/claim", "POST")).status).toBe(403);
  } finally { missingEnrollment.db.close(); }
}, 30_000);
