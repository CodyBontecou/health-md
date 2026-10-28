import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { MANAGEMENT_HASH, NOW, TIMESTAMP, WAKE_HASH, enrollment, jsonRequest, proof, revokeBody, ringBody } from "./test-helpers";

let DB: TestD1;
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  vi.stubGlobal("fetch", vi.fn(() => { throw new Error("No live providers permitted"); }));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const register = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/register", body), { DB });
const ring = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/request", body), { DB });
const remove = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/register", body, "DELETE"), { DB });

describe("strict notification-only v2 inputs", () => {
  it.each(["peerLabel", "deviceToken", "rawWakeKey", "metric", "startDate", "exportOperation", "healthPayload", "url", "data", "topic", "condition", "apns", "__proto__"])
    ("rejects unapproved %s on registration, request, and revocation without retention", async (field) => {
      const body = await enrollment();
      const marker = "synthetic-forbidden-content";
      expect((await register({ ...body, [field]: marker })).status).toBe(400);
      expect(DB.sqlite.prepare("SELECT wake_id FROM wake_registrations").all()).toEqual([]);
      await register(body);
      expect((await ring({ ...await ringBody(body.wakeId, "bd".repeat(16)), [field]: marker })).status).toBe(400);
      expect((await remove({ ...await revokeBody(body.wakeId, "be".repeat(16)), [field]: marker })).status).toBe(400);
      expect(DB.sqlite.prepare("SELECT nonce FROM wake_v2_nonces WHERE wake_id = ?").all(body.wakeId)).toEqual([{ nonce: body.nonce }]);
      expect(DB.sqlite.prepare("SELECT device_token, peer_label FROM wake_registrations WHERE wake_id = ?").get(body.wakeId))
        .toEqual({ device_token: body.deliveryToken, peer_label: null });
      expect(fetch).not.toHaveBeenCalled();
    });

  it.each([
    { transport: "apns" }, { transport: "FCM" }, { transport: "https://attacker.invalid" },
    { deliveryToken: "a\nb" }, { deliveryToken: "" }, { deliveryToken: "x".repeat(4097) },
    { wakeId: "short-id" }, { wakeKeyVerificationHash: MANAGEMENT_HASH },
    { nonce: "a".repeat(33) }, { timestamp: "2026-02-30T00:00:00Z" },
    { timestamp: "October 4, 2026" }, { timestamp: "2026-10-04T12:00:00+00:00" },
  ])("rejects malformed delivery metadata %#", async (overrides) => {
    expect((await register(await enrollment(overrides))).status).toBe(400);
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("domain, freshness, rotation, and revocation", () => {
  it("does not accept a wake proof as a phone management proof or any tampered registration field", async () => {
    const body = await enrollment();
    expect((await register({ ...body, proof: await proof(WAKE_HASH, "unrelated-domain") })).status).toBe(401);
    for (const change of [
      { operation: "rotate" }, { wakeId: "13".repeat(16) }, { userId: "synthetic_install_002" },
      { deliveryToken: "synthetic-new-token" }, { wakeKeyVerificationHash: "01".repeat(32) },
      { managementKeyVerificationHash: "02".repeat(32) }, { nonce: "bb".repeat(16) }, { timestamp: "2026-10-04T12:00:01Z" },
    ]) {
      const response = await register({ ...body, ...change });
      expect([401, 404]).toContain(response.status);
    }
    expect((await register(body)).status).toBe(200);
  });

  it("binds request proofs to v2, wake ID, nonce and timestamp; legacy requests cannot ring FCM", async () => {
    const body = await enrollment();
    await register(body);
    const request = await ringBody(body.wakeId, "cd".repeat(16));
    expect((await ring({ ...request, nonce: "ce".repeat(16) })).status).toBe(401);
    expect((await ring({ ...request, timestamp: "2026-10-04T12:00:01Z" })).status).toBe(401);
    expect((await ring(await ringBody(body.wakeId, "cf".repeat(16), WAKE_HASH, TIMESTAMP, 1))).status).toBe(401);
    expect((await worker.fetch(jsonRequest("/wake/request", await ringBody(body.wakeId, "d0".repeat(16), WAKE_HASH, TIMESTAMP, 1)), { DB })).status).toBe(404);
    const other = await enrollment({ wakeId: "13".repeat(16) });
    await register(other);
    expect((await ring({ ...request, wakeId: other.wakeId })).status).toBe(401);
    expect((await ring(await ringBody("14".repeat(16), "d1".repeat(16)))).status).toBe(404);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("accepts the exact timestamp boundary, rejects stale management/wake proofs, and burns nonces per ID", async () => {
    const stale = await enrollment({ timestamp: "2026-10-04T11:57:59Z" });
    expect((await register(stale)).status).toBe(401);
    const body = await enrollment({ timestamp: "2026-10-04T11:58:00Z" });
    expect((await register(body)).status).toBe(200);
    expect((await ring(await ringBody(body.wakeId, "cd".repeat(16), WAKE_HASH, "2026-10-04T12:02:01Z"))).status).toBe(401);
    expect((await ring(await ringBody(body.wakeId, body.nonce))).status).toBe(401);
    const fresh = await ringBody(body.wakeId, "ce".repeat(16), WAKE_HASH, "2026-10-04T12:02:00Z");
    expect(await (await ring(fresh)).json()).toEqual({ error: "fcm_not_configured" });
    expect(await (await ring(fresh)).json()).toEqual({ error: "wake_nonce_replayed" });
    const other = await enrollment({ wakeId: "13".repeat(16) });
    await register(other);
    expect((await ring(await ringBody(other.wakeId, "ce".repeat(16)))).status).toBe(503);
  });

  it("rotation rejects the old wake hash, preserves policy, and replay cannot resurrect a revoked ID", async () => {
    const body = await enrollment();
    await register(body);
    DB.sqlite.exec(`INSERT INTO wake_counters (wake_id, hour_bucket, delivered_this_hour, last_delivered_at) VALUES ('${body.wakeId}', ${NOW / 1000 / 3600}, 6, ${NOW / 1000 - 30})`);
    const nextHash = "08".repeat(32);
    const rotation = await enrollment({ operation: "rotate", nonce: "bc".repeat(16), wakeKeyVerificationHash: nextHash }, MANAGEMENT_HASH);
    expect((await register(rotation)).status).toBe(200);
    expect((await ring(await ringBody(body.wakeId, "cd".repeat(16)))).status).toBe(401);
    expect(await (await ring(await ringBody(body.wakeId, "ce".repeat(16), nextHash))).json())
      .toEqual({ error: "wake_rate_limited", retryAfterSeconds: 3600 });
    expect((await register(rotation)).status).toBe(401);
    expect(await (await remove(await revokeBody(body.wakeId, "cf".repeat(16)))).json()).toEqual({ ok: true });
    expect(DB.sqlite.prepare("SELECT * FROM wake_counters WHERE wake_id = ?").get(body.wakeId)).toBeUndefined();
    expect(DB.sqlite.prepare("SELECT * FROM wake_v2_nonces WHERE wake_id = ?").get(body.wakeId)).toBeUndefined();
    expect((await register(body)).status).toBe(409);
    expect((await ring(await ringBody(body.wakeId, "d0".repeat(16), nextHash))).status).toBe(404);
  });
});
