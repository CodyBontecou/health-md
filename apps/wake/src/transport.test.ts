import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "./index";
import { hexEncode, sha256 } from "./crypto";
import { USER_ID, APNS_TOKEN, WAKE_HASH, NOW, jsonRequest, syntheticPem, proof } from "./test-helpers";
import { TestD1 } from "./test-support.mjs";

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("deployed APNs HTTP contract", () => {
  it("keeps registration, defaults, request transcript, visible payload, dedupe, and revocation", async () => {
    vi.spyOn(Date, "now").mockReturnValue(NOW);
    const DB = new TestD1();
    const { pem } = await syntheticPem("apns");
    const env = { DB, APNS_AUTH_KEY: pem, APNS_KEY_ID: "SYNTHKEY01", APNS_TEAM_ID: "SYNTHTEAM1" };
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    const registered = await worker.fetch(jsonRequest("/wake/register", {
      userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH,
    }), env);
    expect(registered.status).toBe(200);
    const { wakeId } = await registered.json() as { wakeId: string };
    expect(wakeId).toMatch(/^[0-9a-f]{32}$/);
    const ring = async (nonce: string) => {
      const timestamp = "2026-10-04T12:00:00Z";
      return worker.fetch(jsonRequest("/wake/request", {
        wakeId, nonce, timestamp,
        hmac: await proof(WAKE_HASH, "healthmd.wake.v1" + nonce + timestamp),
        peerLabel: "Synthetic desktop",
      }), env);
    };
    expect(await (await ring("aa".repeat(16))).json()).toEqual({ status: "delivered" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe(`https://api.push.apple.com/3/device/${APNS_TOKEN}`);
    expect(options?.headers).toMatchObject({
      "apns-topic": "com.codybontecou.obsidianhealth", "apns-push-type": "alert",
      "apns-priority": "10", "apns-expiration": String(NOW / 1000 + 300),
    });
    expect(JSON.parse(String(options?.body))).toEqual({
      aps: { alert: { title: "Health.md", body: "Synthetic desktop is requesting data. Tap to continue." },
        sound: "default", category: "HEALTHMD_DIRECT_WAKE" },
      healthmd: { kind: "direct-cli-wake" },
    });
    expect(await (await ring("bb".repeat(16))).json()).toEqual({ status: "deduplicated" });
    expect(await (await ring("aa".repeat(16))).json()).toEqual({ error: "wake_nonce_replayed" });
    expect(await (await worker.fetch(jsonRequest("/wake/register", { userId: USER_ID, wakeId }, "DELETE"), env)).json())
      .toEqual({ ok: true });
    expect((await ring("cc".repeat(16))).status).toBe(404);
    DB.sqlite.close();
  });
});

describe("opt-in FCM registration extension", () => {
  it("enrolls only an explicit FCM v2 resource with a separate management proof", async () => {
    vi.spyOn(Date, "now").mockReturnValue(NOW);
    const DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
    const body = {
      operation: "enroll", wakeId: "12".repeat(16), userId: USER_ID,
      transport: "fcm", deliveryToken: "synthetic-fcm-token",
      wakeKeyVerificationHash: WAKE_HASH,
      managementKeyVerificationHash: hexEncode(await sha256(new Uint8Array(32).fill(9))),
      nonce: "ab".repeat(16), timestamp: "2026-10-04T12:00:00Z",
    };
    const signature = await proof(body.managementKeyVerificationHash, JSON.stringify([
      "healthmd.wake.manage.v2", body.operation, body.wakeId, body.userId, body.transport,
      body.deliveryToken, body.wakeKeyVerificationHash, body.managementKeyVerificationHash,
      body.nonce, body.timestamp,
    ]));
    const response = await worker.fetch(jsonRequest("/wake/v2/register", { ...body, proof: signature }), { DB });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ wakeId: body.wakeId });
    const row = DB.sqlite.prepare("SELECT transport, registration_version, device_token, peer_label FROM wake_registrations WHERE wake_id = ?").get(body.wakeId);
    expect(row).toEqual({ transport: "fcm", registration_version: 2, device_token: body.deliveryToken, peer_label: null });
    DB.sqlite.close();
  });
});
