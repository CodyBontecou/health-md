import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { ingestSupplement } from "../src/exports";
import { errorResponse } from "../src/http";
import { purgeArchivedRevisions, processAccountDeletions } from "../src/lifecycle";
import { VmHealthDataReader, type ReadPrincipal } from "../mcp/reader";
import { sha256Hex } from "../src/crypto";
import type { RepairDraftSpec } from "../src/repair-drafts";
import worker from "../src/index";

const root = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const date = "2026-04-01";
const password = "synthetic-owner-password-for-repairs";
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-supplement-synthetic-")); folders.push(directory);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const { env, db, objects } = createVmEnvironment({ dataDirectory: directory, sourceDirectory: root,
    publicOrigin: origin, identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1", passwordPepper: secret(), personalMvp: true, revisionRetention: "unlimited" });
  function request(path: string, method = "GET", body?: unknown, cookie?: string, bearer?: string, from = origin) {
    return worker.fetch(new Request(`${origin}${path}`, { method, headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json", Origin: from,
        "X-HealthMd-Intent": "dashboard" }), ...(cookie ? { Cookie: cookie } : {}),
      ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }), env);
  }
  return { directory, env, db, objects, request };
}
type TestEnv = ReturnType<typeof setup>;
async function owner(test: TestEnv) {
  await createSingleUserAccount(test.env, "pilot", "pilot@example.test", password);
  const login = await test.request("/api/auth/password-login", "POST", { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")!.split(";")[0]!;
  const token = await test.request("/api/ingest-tokens", "POST", { name: "Synthetic phone" }, cookie);
  const bearer = (await token.json() as { token: string }).token;
  const userId = (test.db.connection.prepare("SELECT id FROM users WHERE status = 'active'").get() as { id: string }).id;
  return { cookie, bearer, userId };
}
function envelope(day = date, steps = 500) {
  const summary = JSON.parse(readFileSync(resolve(root, "../apple/docs/reference/generated/core/summary-day.json"), "utf8"));
  summary.date = day; summary.activity.steps = steps;
  return { schema: "healthmd.api_export", schema_version: 1,
    daily_record_schema: "healthmd.health_data", daily_record_schema_version: 8,
    source: "ios", exported_at: "2026-04-03T12:00:00Z", date_range: { start: day, end: day },
    record_count: 1, records: [summary], failed_date_details: [] };
}
const spec: RepairDraftSpec = { source: "ios", dates: [date], scope: "metric_ids",
  metricIds: ["sleep_total", "steps"], detail: "summary" };
function narrow(day = date, steps = 0) {
  return { ...envelope(day), exported_at: "2026-04-08T12:00:00Z", records: [{
    schema: "healthmd.health_data", schema_version: 8, date: day,
    time_context: { calendar_timezone: "UTC" }, units: { steps: "steps" },
    activity: { steps }, raw_capture_status: "not_requested",
  }] };
}
async function supplement(test: TestEnv, bearer: string, data: unknown, scope = spec): Promise<Response> {
  try {
    return await ingestSupplement(new Request(`${origin}/api/v1/exports`, { method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(data) }), test.env, scope);
  } catch (error) { return errorResponse(error); }
}
const read = async (test: TestEnv, cookie?: string, requested = date, offset = 0) =>
  test.request("/api/repair/supplements", "POST", { date: requested, offset }, cookie);

it("keeps a narrow existing-day repair separate from the primary and shows original per-field provenance", async () => {
  const test = setup();
  const { env, db, objects, request, directory } = test;
  try {
    const { cookie, bearer, userId } = await owner(test);
    const primary = await request("/api/v1/exports", "POST", envelope(), undefined, bearer);
    expect(primary.status).toBe(201);
    const primaryId = (await primary.json() as { id: string }).id;
    const page = { start: date, end: date, metrics: ["steps", "sleep_total"], profile: "all" };
    const before = await request("/api/explore/chart", "POST", page, cookie);
    expect((await before.json() as { days: unknown[] }).days).toMatchObject([
      { exportId: primaryId, status: "available", values: { steps: 500, sleep_total: 7.75 } },
    ]);
    expect((await read(test)).status).toBe(401);
    expect((await read(test, bearer)).status).toBe(401);
    expect((await test.request("/api/repair/supplements", "POST", { date, offset: 0 }, cookie,
      undefined, "https://attacker.example.test")).status).toBe(403);
    expect((await request("/api/repair/supplements", "POST", { date, offset: -1 }, cookie)).status).toBe(400);
    expect((await request("/api/repair/supplements", "POST", { date: "2026-02-30", offset: 0 }, cookie)).status)
      .toBe(400);
    const deniedHeader = await worker.fetch(new Request(`${origin}/api/v1/exports`, { method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json",
        "X-HealthMd-Repair-Request": randomUUID() }, body: JSON.stringify(narrow()) }), env);
    expect(deniedHeader.status).toBe(409);
    expect((db.connection.prepare("SELECT export_id FROM daily_records WHERE owner_date = ?")
      .get(date) as { export_id: string }).export_id).toBe(primaryId);
    const selected = narrow();
    selected.records[0]!.time_context.calendar_timezone = "America/Los_Angeles";
    const response = await supplement(test, bearer, selected);
    expect(response.status).toBe(201);
    expect(response.headers.get("cache-control")).toBe("no-store");
    const result = await response.json() as { id: string; mode: string; records: number; failureCount: number };
    expect(result).toMatchObject({ mode: "supplemental", records: 1, failureCount: 0 });
    expect((db.connection.prepare("SELECT export_id FROM daily_records WHERE owner_date = ?")
      .get(date) as { export_id: string }).export_id).toBe(primaryId);
    const after = await request("/api/explore/chart", "POST", page, cookie);
    expect((await after.json() as { days: unknown[] }).days).toMatchObject([
      { exportId: primaryId, status: "available", values: { steps: 500, sleep_total: 7.75 } },
    ]);
    const evidence = await read(test, cookie);
    expect(evidence.status).toBe(200);
    expect(evidence.headers.get("cache-control")).toBe("no-store");
    expect(await evidence.json()).toMatchObject({ version: 1, date, nextOffset: null,
      primary: { exportId: primaryId, status: "reviewed_apple_v8", pointer: "/records/0",
        calendarTimezone: "UTC", metrics: { steps: { status: "observed", value: 500 },
          sleep_total: { status: "observed", value: 7.75 } } },
      supplements: [{ exportId: result.id, status: "reviewed_apple_v8", pointer: "/records/0",
        calendarTimezone: "America/Los_Angeles", metricIds: ["sleep_total", "steps"], captureStatus: "not_requested",
        metrics: { steps: { status: "observed", value: 0 },
          sleep_total: { status: "value_unavailable_in_uploaded_summary", value: null } } }],
    });
    const inventory = await request("/api/explore/exports", "POST",
      { source: "all", version: "all", scope: "all", start: null, end: null, offset: 0 }, cookie);
    expect((await inventory.json() as { exports: unknown[] }).exports).toMatchObject([
      { id: result.id, retentionRole: "supplemental" }, { id: primaryId, retentionRole: "current" },
    ]);
    const retained = db.connection.prepare("SELECT object_key AS objectKey FROM exports WHERE id = ?")
      .get(result.id) as { objectKey: string };
    expect(readFileSync(join(directory, "objects", retained.objectKey)).toString()).not.toContain("steps");
    const original = await request(`/api/exports/${result.id}/download`, "GET", undefined, cookie);
    expect(await original.json()).toEqual(selected);
    expect(await objects.reconcile(db)).toBe(0);
    const reader = new VmHealthDataReader(directory, env.EXPORT_ENCRYPTION_KEYS_JSON);
    const principal: ReadPrincipal = { userId, tokenId: "synthetic", scope: "full_export" };
    const aggregates: ReadPrincipal = { ...principal, scope: "aggregates" };
    try {
      expect((await reader.findExportForDate(principal, date)).exportId).toBe(primaryId);
      expect((await reader.listExports(principal, "", 10)).exports).toMatchObject([
        { exportId: result.id, retentionRole: "supplemental" },
        { exportId: primaryId, retentionRole: "current" },
      ]);
      await expect(reader.listExports(aggregates, "", 10)).rejects.toMatchObject({ code: "forbidden" });
      expect((await reader.getDailySummary(aggregates, date)).metrics).toEqual(
        expect.arrayContaining([expect.objectContaining({ metric: "steps", value: 500 })]));
    } finally { reader.close(); }
    const newer = { ...envelope(date, 700), exported_at: "2026-04-10T12:00:00Z" };
    expect((await request("/api/v1/exports", "POST", newer, undefined, bearer)).status).toBe(201);
    const rechecked = await read(test, cookie);
    expect(await rechecked.json()).toMatchObject({
      primary: { metrics: { steps: { status: "observed", value: 700 } } },
      supplements: [{ exportId: result.id, metrics: { steps: { status: "observed", value: 0 } } }],
    });
  } finally { db.close(); }
}, 30_000);

it("deduplicates concurrent scoped uploads without cross-mode reuse or an orphan", async () => {
  const test = setup(); const { db, objects, request } = test;
  try {
    const { bearer, cookie } = await owner(test);
    const body = narrow();
    const [first, second] = await Promise.all([
      supplement(test, bearer, body), supplement(test, bearer, body),
    ]);
    expect([first.status, second.status].sort()).toEqual([200, 201]);
    const receipts = await Promise.all([first.json(), second.json()]) as Array<{ id: string; duplicate: boolean }>;
    expect(receipts[0]?.id).toBe(receipts[1]?.id);
    expect(receipts.some((item) => item.duplicate)).toBe(true);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_records").get()).toMatchObject({ n: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM daily_records").get()).toMatchObject({ n: 0 });
    expect(await objects.reconcile(db)).toBe(0);
    expect((await supplement(test, bearer, body, { ...spec, metricIds: ["steps"] })).status).toBe(409);
    expect((await request("/api/v1/exports", "POST", body, undefined, bearer)).status).toBe(409);
    // Existing identical ordinary bytes cannot be laundered into a supplement.
    const ordinary = envelope(date, 3);
    expect((await request("/api/v1/exports", "POST", ordinary, undefined, bearer)).status).toBe(201);
    expect((await supplement(test, bearer, ordinary, { ...spec, scope: "entire_days", metricIds: [] })).status)
      .toBe(409);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_exports").get()).toMatchObject({ n: 1 });
    expect((await read(test, cookie)).status).toBe(200);
    expect(await objects.reconcile(db)).toBe(0);
  } finally { db.close(); }
}, 30_000);

it("retains partial, failed-only and Android envelopes without inventing primary coverage", async () => {
  const test = setup(); const { db, request } = test;
  try {
    const { bearer, cookie } = await owner(test);
    const next = "2026-04-02";
    const mixed = { ...narrow(), date_range: { start: date, end: next },
      failed_date_details: [{ date: `${next}T00:00:00Z`, reason: "no_health_data" }] };
    const both = { ...spec, dates: [date, next] };
    const partial = await supplement(test, bearer, mixed, both);
    expect(partial.status).toBe(201);
    expect(await partial.json()).toMatchObject({ records: 1, failureCount: 1 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM daily_records").get()).toMatchObject({ n: 0 });
    const inspected = await read(test, cookie, next);
    expect(await inspected.json()).toMatchObject({ primary: null, supplements: [
      { status: "no_retained_record_for_day", pointer: null, failureCount: 1, metrics: {} },
    ] });
    const failedOnly = { ...mixed, record_count: 0, records: [], date_range: { start: next, end: next } };
    const empty = await supplement(test, bearer, failedOnly, { ...both, dates: [next] });
    expect(empty.status).toBe(201);
    expect(await empty.json()).toMatchObject({ records: 0, failureCount: 1 });
    const again = await read(test, cookie, next);
    expect((await again.json() as { supplements: unknown[] }).supplements).toMatchObject([
      { status: "no_retained_record_for_day", pointer: null, failureCount: 1 },
      { status: "no_retained_record_for_day", pointer: null, failureCount: 1 },
    ]);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_records").get()).toMatchObject({ n: 1 });
    const android = { ...mixed, source: "android", daily_record_schema_version: 4,
      failed_date_details: [], date_range: { start: date, end: date },
      records: [{ schema: "healthmd.health_data", schema_version: 4, date, activity: { steps: 44 } }] };
    const androidSpec: RepairDraftSpec = { source: "android", dates: [date], scope: "entire_days",
      metricIds: [], detail: "time_series" };
    expect((await supplement(test, bearer, android, androidSpec)).status).toBe(201);
    const separate = await read(test, cookie);
    expect((await separate.json() as { supplements: unknown[] }).supplements[0]).toMatchObject(
      { source: "android", status: "unsupported_profile", metricIds: [], metrics: {} });
    expect((await supplement(test, bearer, android, spec)).status).toBe(422);
    const outside = { ...mixed, date_range: { start: "2026-03-30", end: next } };
    expect((await supplement(test, bearer, outside, both)).status).toBe(422);
    const unrelatedFailure = { ...failedOnly,
      failed_date_details: [{ date: "2026-06-01T00:00:00Z", reason: "no_health_data" }] };
    expect((await supplement(test, bearer, unrelatedFailure, { ...both, dates: [next] })).status).toBe(422);
    expect((await request("/api/repair/supplements", "POST", { date: next, offset: 0 }, cookie)).status).toBe(200);
  } finally { db.close(); }
}, 30_000);

it("enforces retained-byte quota at transactional commit across simultaneous different supplements", async () => {
  const test = setup(); const { env, db, objects } = test;
  try {
    const { bearer, userId } = await owner(test);
    const firstPayload = narrow(date, 3);
    const secondPayload = narrow(date, 4);
    const firstSize = Buffer.byteLength(JSON.stringify(firstPayload));
    const secondSize = Buffer.byteLength(JSON.stringify(secondPayload));
    const baseBytes = 1_073_741_824 - firstSize - secondSize + 1;
    const fakeId = randomUUID();
    db.connection.prepare(`INSERT INTO exports
      (id, user_id, object_key, encryption_key_id, plaintext_sha256, byte_count,
       envelope_schema_version, daily_record_schema_version, source, exported_at,
       received_at, date_start, date_end, record_count, failure_count, external_record_count)
      VALUES (?, ?, ?, 'v1', ?, ?, 1, 8, 'ios', ?, ?, ?, ?, 0, 1, 0)`)
      .run(fakeId, userId, `v1/${randomUUID()}`, Buffer.from(randomBytes(32)).toString("hex"), baseBytes,
        "2026-04-03T12:00:00.000Z", "2026-04-03T12:00:00.000Z", date, date);
    // Durable reservation rejects the over-quota writer before it creates an
    // encrypted object. No actual 1 GiB object is ever created.
    const originalStore = env.EXPORTS;
    const originalPut = originalStore.put.bind(originalStore);
    let puts = 0;
    env.EXPORTS = new Proxy(originalStore, { get(target, property) {
      if (property === "put") return async (...args: Parameters<typeof originalPut>) => {
        puts += 1;
        return originalPut(...args);
      };
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const [first, second] = await Promise.all([
      supplement(test, bearer, firstPayload), supplement(test, bearer, secondPayload),
    ]);
    expect([first.status, second.status].sort()).toEqual([201, 413]);
    expect(puts).toBe(1);
    expect((db.connection.prepare("SELECT COALESCE(SUM(byte_count), 0) AS bytes FROM exports")
      .get() as { bytes: number }).bytes).toBeLessThanOrEqual(1_073_741_824);
    db.connection.prepare("DELETE FROM exports WHERE id = ?").run(fakeId);
    expect(await objects.reconcile(db)).toBe(0);
  } finally { db.close(); }
}, 30_000);

it("bounds paged provenance reads and fails closed on tampered metadata or ciphertext", async () => {
  const test = setup(); const { db, request, directory } = test;
  try {
    const { bearer, cookie } = await owner(test);
    for (let i = 0; i < 11; i++) {
      expect((await supplement(test, bearer, narrow(date, i))).status).toBe(201);
    }
    const first = await read(test, cookie);
    expect(first.status).toBe(200);
    const firstPage = await first.json() as { primary: null; nextOffset: number; supplements: unknown[] };
    expect(firstPage.primary).toBeNull();
    expect(firstPage.nextOffset).toBe(10);
    expect(firstPage.supplements).toHaveLength(10);
    expect(firstPage.supplements[0]).toMatchObject({ metrics: { steps: { status: "observed", value: 10 } } });
    const second = await read(test, cookie, date, 10);
    expect((await second.json() as { supplements: unknown[]; nextOffset: number | null })).toMatchObject({
      nextOffset: null, supplements: [{ metrics: { steps: { status: "observed", value: 0 } } }],
    });
    const latest = db.connection.prepare(`SELECT e.object_key AS objectKey, e.id FROM exports e
      JOIN supplemental_exports s ON s.export_id = e.id ORDER BY s.created_at DESC, e.id DESC LIMIT 1`)
      .get() as { objectKey: string; id: string };
    const objectPath = join(directory, "objects", latest.objectKey);
    const original = readFileSync(objectPath);
    const corrupted = Buffer.from(original); corrupted[corrupted.length - 1] ^= 1;
    writeFileSync(objectPath, corrupted);
    expect((await read(test, cookie)).status).toBe(503);
    writeFileSync(objectPath, original);
    db.connection.prepare("UPDATE supplemental_exports SET spec_ciphertext = 'invalid' WHERE export_id = ?")
      .run(latest.id);
    expect((await read(test, cookie)).status).toBe(503);
    expect((await request("/api/repair/supplements", "POST", { date, offset: 0 }, bearer)).status).toBe(401);
  } finally { db.close(); }
}, 30_000);

it("rolls back failed commits, protects supplements from revision cleanup and erases on account deletion", async () => {
  const test = setup(); const { env, db, objects, request, directory } = test;
  try {
    const { bearer, cookie } = await owner(test);
    db.connection.exec(`CREATE TRIGGER synthetic_reject BEFORE INSERT ON supplemental_exports
      BEGIN SELECT RAISE(FAIL, 'synthetic rejection'); END`);
    expect((await supplement(test, bearer, narrow())).status).toBe(500);
    db.connection.exec("DROP TRIGGER synthetic_reject");
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 0 });
    expect(await objects.reconcile(db)).toBe(0);
    const retained = await supplement(test, bearer, narrow());
    expect(retained.status).toBe(201);
    const exportId = (await retained.json() as { id: string }).id;
    const row = db.connection.prepare("SELECT object_key AS objectKey FROM exports WHERE id = ?")
      .get(exportId) as { objectKey: string };
    const payload = join(directory, "objects", row.objectKey);
    expect(statSync(payload).isFile()).toBe(true);
    const metadata = db.connection.prepare("SELECT * FROM supplemental_exports WHERE export_id = ?")
      .get(exportId) as Record<string, unknown>;
    expect(JSON.stringify(metadata)).not.toContain(date);
    expect(JSON.stringify(metadata)).not.toContain("sleep_total");
    db.connection.prepare("UPDATE exports SET received_at = '2020-01-01T00:00:00.000Z' WHERE id = ?")
      .run(exportId);
    expect(await purgeArchivedRevisions(env, 30)).toBe(0);
    expect(statSync(payload).isFile()).toBe(true);
    const deletion = await request("/api/account/delete", "POST", { password, confirmation: "DELETE",
      statusToken: `hmd_del_${Buffer.from(randomBytes(32)).toString("base64url")}` }, cookie);
    expect(deletion.status).toBe(202);
    await processAccountDeletions(env);
    await processAccountDeletions(env);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_exports").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM supplemental_records").get()).toMatchObject({ n: 0 });
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM exports").get()).toMatchObject({ n: 0 });
    expect(statSync(payload, { throwIfNoEntry: false })).toBeUndefined();
    expect(await objects.reconcile(db)).toBe(0);
  } finally { db.close(); }
}, 30_000);

it("keeps read authority owner-scoped and rejects supplement requests on the write-only listener", async () => {
  const test = setup(); const { env, db, request } = test;
  const account = await startVmServer(env, 0, "account");
  const ingest = await startVmServer(env, 0, "ingest");
  try {
    const { bearer, cookie } = await owner(test);
    expect((await supplement(test, bearer, narrow())).status).toBe(201);
    const otherId = randomUUID(); const now = new Date().toISOString();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', ?)`).run(otherId, randomUUID(), now);
    const otherToken = `hmd_ses_${Buffer.from(randomBytes(32)).toString("base64url")}`;
    db.connection.prepare(`INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)`).run(randomUUID(), otherId, await sha256Hex(otherToken),
      new Date(Date.now() + 3600_000).toISOString(), now, now);
    const otherCookie = `__Host-healthmd_cloud_session=${otherToken}`;
    expect(await (await read(test, otherCookie)).json()).toMatchObject({ primary: null, supplements: [] });
    expect((await read(test, cookie)).status).toBe(200);
    const hit = async (port: number, path: string, method: string) => new Promise<number>((done, fail) => {
      import("node:http").then(({ request: nodeRequest }) => {
        const call = nodeRequest({ host: "127.0.0.1", port, path, method,
          headers: { Host: "account.example.test", "X-Forwarded-Host": "account.example.test",
            "X-Forwarded-Proto": "https" } }, (res) => {
          res.resume(); res.on("end", () => done(res.statusCode ?? 0));
        }); call.on("error", fail); call.end();
      }).catch(fail);
    });
    expect(await hit(ingest.port, "/api/repair/supplements", "POST")).toBe(404);
    expect(await hit(account.port, "/api/repair/supplements", "POST")).toBe(401);
    expect(await hit(account.port, "/api/v1/exports", "POST")).toBe(404);
  } finally { await account.close(); await ingest.close(); db.close(); }
}, 30_000);
