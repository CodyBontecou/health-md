import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { APNS_TOKEN, USER_ID, WAKE_HASH, MANAGEMENT_HASH, NOW, enrollment, jsonRequest, revokeBody } from "./test-helpers";

let DB: TestD1;
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  vi.stubGlobal("fetch", vi.fn(() => { throw new Error("No provider calls authorized"); }));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const post = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/register", body), { DB });

describe("v2 owner management", () => {
  it("pins an independently computed enrollment proof", async () => {
    const body = await enrollment();
    expect(body.proof).toBe("55b5da42049b31347200bcb2e0dd6b2b1c7513bc411d7b44d9b0651e4504c3fc");
    expect((await post(body)).status).toBe(200);
  });

  it("requires the old phone-only management proof for rotation and revocation", async () => {
    const body = await enrollment();
    expect((await post(body)).status).toBe(200);
    const nextHash = "08".repeat(32);
    const rotated = await enrollment({ operation: "rotate", nonce: "bc".repeat(16),
      deliveryToken: "synthetic-rotated-token", wakeKeyVerificationHash: "09".repeat(32), managementKeyVerificationHash: nextHash }, MANAGEMENT_HASH);
    expect((await post(rotated)).status).toBe(200);
    const oldProof = await enrollment({ operation: "rotate", nonce: "bd".repeat(16) }, MANAGEMENT_HASH);
    expect((await post(oldProof)).status).toBe(401);
    const callerOnlyHasWakeKey = await revokeBody(body.wakeId, "cd".repeat(16), WAKE_HASH);
    expect((await worker.fetch(jsonRequest("/wake/v2/register", callerOnlyHasWakeKey, "DELETE"), { DB })).status).toBe(401);
    const revoked = await revokeBody(body.wakeId, "ce".repeat(16), nextHash);
    expect(await (await worker.fetch(jsonRequest("/wake/v2/register", revoked, "DELETE"), { DB })).json()).toEqual({ ok: true });
    expect((await post(await enrollment({ operation: "rotate", nonce: "cf".repeat(16) }, nextHash))).status).toBe(404);
  });

  it("rejects rotating a delegated wake hash into the owner-management role", async () => {
    await post(await enrollment());
    for (const change of [
      { managementKeyVerificationHash: WAKE_HASH, wakeKeyVerificationHash: "01".repeat(32) },
      { wakeKeyVerificationHash: MANAGEMENT_HASH, managementKeyVerificationHash: "02".repeat(32) },
    ]) {
      expect((await post(await enrollment({ operation: "rotate", nonce: "bd".repeat(16), ...change }, MANAGEMENT_HASH))).status).toBe(400);
    }
  });

  it("cannot be rotated, revoked, or policy-reset through legacy endpoints", async () => {
    const body = await enrollment();
    await post(body);
    DB.sqlite.exec(`INSERT INTO wake_counters (wake_id, hour_bucket, delivered_this_hour, last_delivered_at) VALUES ('${body.wakeId}', 1, 6, 1)`);
    const rotated = await worker.fetch(jsonRequest("/wake/register", {
      wakeId: body.wakeId, userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH,
    }), { DB });
    expect(rotated.status).toBe(404);
    expect(await (await worker.fetch(jsonRequest("/wake/register", { userId: USER_ID, wakeId: body.wakeId }, "DELETE"), { DB })).json())
      .toEqual({ ok: true });
    expect(DB.sqlite.prepare("SELECT delivered_this_hour FROM wake_counters WHERE wake_id = ?").get(body.wakeId)?.delivered_this_hour).toBe(6);
    expect(DB.sqlite.prepare("SELECT transport FROM wake_registrations WHERE wake_id = ?").get(body.wakeId)?.transport).toBe("fcm");
  });
});
