import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { request as httpRequest } from "node:http";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { sha256Hex } from "../src/crypto";
import type { Env } from "../src/types";
import worker from "../src/index";

const root = resolve(import.meta.dirname, "..");
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
const origin = "https://account.example.test";
const password = "synthetic-owner-password-for-tests";

function setup() {
  const directory = mkdtempSync(join(tmpdir(), "healthmd-explore-synthetic-"));
  folders.push(directory);
  const identityKey = Buffer.from(randomBytes(32)).toString("base64");
  const exportKey = Buffer.from(randomBytes(32)).toString("base64");
  const pepper = Buffer.from(randomBytes(32)).toString("base64");
  const { env, db } = createVmEnvironment({ dataDirectory: directory, sourceDirectory: root,
    publicOrigin: origin, identityKey, exportKeys: JSON.stringify({ v1: exportKey }),
    currentKeyId: "v1", passwordPepper: pepper, personalMvp: true, revisionRetention: "unlimited" });
  return { env, db };
}
async function proxy(port: number, path: string, cookie?: string, body?: unknown,
  authorization?: string, from = origin) {
  return new Promise<{ status: number; body: string; headers: Record<string, string | string[] | undefined> }>((done, fail) => {
    const request = httpRequest({ host: "127.0.0.1", port, path,
      method: body === undefined ? "GET" : "POST", headers: {
        Host: "account.example.test", "X-Forwarded-Host": "account.example.test", "X-Forwarded-Proto": "https",
        ...(body === undefined ? {} : { Origin: from, "X-HealthMd-Intent": "dashboard",
          "Content-Type": "application/json" }),
        ...(cookie ? { Cookie: cookie } : {}), ...(authorization ? { Authorization: authorization } : {}),
      } }, (response) => {
      const parts: Uint8Array[] = [];
      response.on("data", (chunk: Uint8Array) => parts.push(chunk));
      response.on("end", () => done({ status: response.statusCode ?? 0,
        body: Buffer.concat(parts).toString("utf8"), headers: response.headers }));
    });
    request.on("error", fail);
    if (body !== undefined) request.write(JSON.stringify(body));
    request.end();
  });
}

it("keeps exploration session-only, bounded, source-aware and able to navigate original synthetic JSON", async () => {
  const { env, db } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const service = await startVmServer(env, 0, "account");
  const post = (path: string, body: unknown, cookie?: string, from?: string) =>
    proxy(service.port, path, cookie, body, undefined, from);
  const filters = { source: "all", version: "all", scope: "all", start: null, end: null, offset: 0 };
  const chart = { start: "2026-03-15", end: "2026-03-17",
    metrics: ["steps", "sleep_total", "hrv", "weight"], profile: "all" };
  try {
    expect((await proxy(service.port, "/explore")).status).toBe(303);
    expect((await proxy(service.port, "/api/explore/catalog")).status).toBe(401);
    expect((await post("/api/explore/chart", chart)).status).toBe(401);
    expect((await post("/api/explore/exports", filters, undefined, origin)).status).toBe(401);
    expect((await post("/api/explore/node", { exportId: randomUUID(), pointer: "", offset: 0 })).status).toBe(401);
    const login = await post("/api/auth/password-login", { username: "pilot", password });
    const cookie = (login.headers["set-cookie"] as string[] | undefined)?.[0]?.split(";")[0];
    expect(login.status).toBe(200);
    expect(cookie).toBeDefined();
    expect((await proxy(service.port, "/explore", cookie)).status).toBe(200);
    expect(JSON.parse((await proxy(service.port, "/api/explore/catalog", cookie)).body).metrics).toHaveLength(11);
    expect((await post("/api/explore/chart", chart, cookie, "https://other.example.test")).status).toBe(403);
    const token = await post("/api/ingest-tokens", { name: "Synthetic phone" }, cookie);
    const bearer = JSON.parse(token.body).token as string;
    expect((await proxy(service.port, "/api/explore/chart", undefined, chart,
      `Bearer ${bearer}`)).status).toBe(401);
    expect((await post("/api/explore/chart", { ...chart, start: "2026-01-01" }, cookie)).status).toBe(400);
    expect((await post("/api/explore/chart", { ...chart, metrics: ["hrv_rmssd_ms"] }, cookie)).status).toBe(400);
    expect((await post("/api/explore/chart", { ...chart, metrics: ["steps", "steps"] }, cookie)).status).toBe(400);
    expect((await post("/api/explore/exports", { ...filters, source: "' OR true --" }, cookie)).status).toBe(400);
    const summary = JSON.parse(readFileSync(resolve(root,
      "../apple/docs/reference/generated/core/summary-day.json"), "utf8"));
    summary.date = "2026-03-15";
    summary.raw_capture_status = "complete";
    summary.healthkit_record_archive = { schema: "healthmd.healthkit_records", schema_version: 1,
      records: Array.from({ length: 25 }, (_, i) => ({ original_uuid: `fictional-${i}` })) };
    summary["sensitive/x~y"] = "<img src=x onerror=alert(1)>";
    summary.long_text = "A".repeat(900);
    summary.large_integer = 18446744073709551615;
    summary.sample_decimal = 0.125;
    const fixture = { schema: "healthmd.api_export", schema_version: 2,
      daily_record_schema: "healthmd.health_data", daily_record_schema_version: 8,
      external_record_schema: "healthmd.external_provider_daily", external_record_schema_version: 1,
      external_record_count: 1, external_records: [{ schema: "healthmd.external_provider_daily",
        schema_version: 1, date: "2026-03-15", provider: "synthetic", payload: { note: "private fictional" } }],
      source: "ios", exported_at: "2026-03-19T12:00:00Z", date_range: { start: "2026-03-15", end: "2026-03-15" },
      record_count: 1, records: [summary], failed_date_details: [] };
    const ingest = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(fixture),
    }), env);
    expect(ingest.status).toBe(201);
    const exportId = (await ingest.json() as { id: string }).id;
    const plotted = await post("/api/explore/chart", chart, cookie);
    expect(plotted.status).toBe(200);
    expect(plotted.headers["cache-control"]).toBe("no-store");
    const plottedBody = JSON.parse(plotted.body);
    expect(plottedBody.catalog).toHaveLength(11);
    expect(plottedBody.days).toHaveLength(3);
    expect(plottedBody.days[0]).toMatchObject({ status: "available", exportId,
      values: { steps: summary.activity.steps, sleep_total: 7.75 } });
    expect(plottedBody.days[1]).toMatchObject({ status: "not_uploaded", values: { steps: null } });
    expect(JSON.stringify(plottedBody)).not.toContain("sensitive/x~y");
    const androidFilter = JSON.parse((await post("/api/explore/chart", { ...chart,
      profile: "android_compat" }, cookie)).body);
    expect(androidFilter.days[0]).toMatchObject({ status: "filtered_profile", values: { steps: null } });
    const all = await post("/api/explore/exports", filters, cookie);
    expect(JSON.parse(all.body).exports).toMatchObject([{ id: exportId, source: "ios", dailyVersion: 8,
      externalRecordCount: 1 }]);
    expect(JSON.parse((await post("/api/explore/exports", { ...filters, source: "android" }, cookie)).body)
      .exports).toEqual([]);
    expect(JSON.parse((await post("/api/explore/exports", { ...filters,
      start: "2026-03-16" }, cookie)).body).exports).toEqual([]);
    const rootNode = JSON.parse((await post("/api/explore/node", { exportId, pointer: "", offset: 0 }, cookie)).body);
    expect(rootNode.type).toBe("object");
    expect(rootNode.items.some((item: { key: string }) => item.key === "external_records")).toBe(true);
    let dayNode = JSON.parse((await post("/api/explore/node", {
      exportId, pointer: "/records/0", offset: 0 }, cookie)).body);
    let escapedKeyFound = false;
    for (let page = 0; page < 10; page++) {
      escapedKeyFound ||= dayNode.items.some((item: { key: string; pointer: string }) =>
        item.key === "sensitive/x~y" && item.pointer === "/records/0/sensitive~1x~0y");
      if (escapedKeyFound || dayNode.nextOffset === null) break;
      dayNode = JSON.parse((await post("/api/explore/node", {
        exportId, pointer: "/records/0", offset: dayNode.nextOffset }, cookie)).body);
    }
    expect(escapedKeyFound).toBe(true);
    expect(JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/sensitive~1x~0y", offset: 0 }, cookie)).body).preview)
      .toBe("<img src=x onerror=alert(1)>");
    const long = JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/long_text", offset: 0 }, cookie)).body);
    expect(long.truncated).toBe(true);
    expect(long.preview.length).toBeLessThan(530);
    const archive = JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/healthkit_record_archive/records", offset: 0 }, cookie)).body);
    expect(archive.items).toHaveLength(20);
    expect(archive.nextOffset).toBe(20);
    expect(JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/external_records/0/payload/note", offset: 0 }, cookie)).body).preview)
      .toBe("private fictional");
    expect(JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/large_integer", offset: 0 }, cookie)).body)
      .exactValueUnavailable).toBe(true);
    expect(JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/sample_decimal", offset: 0 }, cookie)).body).approximate).toBe(true);
    expect(JSON.parse((await post("/api/explore/node", { exportId,
      pointer: "/records/0/healthkit_record_archive/records", offset: 20 }, cookie)).body).items).toHaveLength(5);
    expect((await post("/api/explore/node", { exportId, pointer: "/records/-1", offset: 0 }, cookie)).status).toBe(404);
    expect((await post("/api/explore/node", { exportId, pointer: "/records/~2", offset: 0 }, cookie)).status).toBe(400);
    expect((await post("/api/explore/node", { exportId: randomUUID(), pointer: "", offset: 0 }, cookie)).status).toBe(404);
    const android = { ...fixture, source: "android", daily_record_schema_version: 4,
      exported_at: "2026-03-20T12:00:00Z", date_range: { start: "2026-03-16", end: "2026-03-16" },
      external_records: [{ ...fixture.external_records[0], date: "2026-03-16" }],
      records: [{ schema: "healthmd.health_data", schema_version: 4,
        date: "2026-03-16", activity: { steps: 654321 } }] };
    const androidReceipt = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(android),
    }), env);
    expect(androidReceipt.status).toBe(201);
    const androidId = (await androidReceipt.json() as { id: string }).id;
    const currentChart = JSON.parse((await post("/api/explore/chart", chart, cookie)).body);
    expect(currentChart.days[1]).toMatchObject({ date: "2026-03-16", status: "unsupported_profile",
      exportId: androidId, values: { steps: null } });
    const onlyAndroid = JSON.parse((await post("/api/explore/chart", {
      ...chart, profile: "android_compat" }, cookie)).body);
    expect(onlyAndroid.days[1]).toMatchObject({ status: "unsupported_profile", values: { steps: null } });
    const androidInventory = JSON.parse((await post("/api/explore/exports", {
      ...filters, source: "android", version: 4 }, cookie)).body);
    expect(androidInventory.exports).toMatchObject([{ id: androidId, dailyVersion: 4 }]);
    const older = { ...fixture, exported_at: "2026-03-14T12:00:00Z" };
    const oldResponse = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(older),
    }), env);
    expect(oldResponse.status).toBe(201);
    const oldId = (await oldResponse.json() as { id: string }).id;
    expect(JSON.parse((await post("/api/explore/exports", filters, cookie)).body).exports).toHaveLength(3);
    expect(JSON.parse((await post("/api/explore/exports", { ...filters, scope: "current" }, cookie)).body)
      .exports).toHaveLength(2);
    expect((await post("/api/explore/node", { exportId: oldId, pointer: "", offset: 0 }, cookie)).status).toBe(200);
    // A distinct synthetic account session cannot navigate this owner's export.
    const otherId = randomUUID();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(otherId, randomUUID(), new Date().toISOString());
    const otherToken = `hmd_ses_${Buffer.from(randomBytes(32)).toString("base64url")}`;
    const now = new Date().toISOString();
    db.connection.prepare(`INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)`).run(randomUUID(), otherId, await sha256Hex(otherToken),
      new Date(Date.now() + 3600000).toISOString(), now, now);
    const otherCookie = `__Host-healthmd_cloud_session=${otherToken}`;
    expect(JSON.parse((await post("/api/explore/exports", filters, otherCookie)).body).exports).toEqual([]);
    expect((await post("/api/explore/node", { exportId, pointer: "", offset: 0 }, otherCookie)).status).toBe(404);
    expect(JSON.parse((await post("/api/explore/chart", chart, otherCookie)).body).days
      .every((day: { status: string }) => day.status === "not_uploaded")).toBe(true);
    expect((await proxy(service.port, `/api/exports/${exportId}/download`, cookie)).status).toBe(200);
  } finally { await service.close(); db.close(); }
}, 30_000);
