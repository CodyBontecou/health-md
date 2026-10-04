import { afterEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { APNS_TOKEN, NOW, TIMESTAMP, USER_ID, WAKE_HASH, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const registration = { userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH };

it("forward-migrates existing APNs rows and preserves explicit legacy rotation/revocation", async () => {
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  const DB = new TestD1();
  try {
    const initial = await worker.fetch(jsonRequest("/wake/register", registration), { DB });
    const { wakeId } = await initial.json() as { wakeId: string };
    DB.applyMigration("0002_fcm_v2.sql");
    expect(DB.sqlite.prepare("SELECT transport, registration_version, management_hash, device_token FROM wake_registrations WHERE wake_id = ?").get(wakeId))
      .toEqual({ transport: "apns", registration_version: 1, management_hash: null, device_token: APNS_TOKEN });
    expect((await worker.fetch(jsonRequest("/wake/register", { ...registration, wakeId, userId: "synthetic_foreign_id" }), { DB })).status).toBe(404);
    const nextHash = "09".repeat(32);
    expect(await (await worker.fetch(jsonRequest("/wake/register", { ...registration, wakeId,
      wakeKeyVerificationHash: nextHash, deviceToken: "cd".repeat(32), peerLabel: "Synthetic desktop" }), { DB })).json())
      .toEqual({ wakeId });
    expect((await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "cd".repeat(16), WAKE_HASH, TIMESTAMP, 1)), { DB })).status).toBe(401);
    expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "ce".repeat(16), nextHash, TIMESTAMP, 1)), { DB })).json())
      .toEqual({ error: "apns_not_configured" });
    expect(await (await worker.fetch(jsonRequest("/wake/register", { userId: USER_ID, wakeId }, "DELETE"), { DB })).json()).toEqual({ ok: true });
    expect(await (await worker.fetch(jsonRequest("/wake/register", { userId: USER_ID, wakeId }, "DELETE"), { DB })).json()).toEqual({ ok: true });
  } finally { DB.sqlite.close(); }
});

it("preserves the sandbox override and APNs availability with malformed FCM config", async () => {
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  const DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  try {
    const { wakeId } = await (await worker.fetch(jsonRequest("/wake/register", registration), { DB })).json() as { wakeId: string };
    const env = { DB, APNS_AUTH_KEY: (await syntheticPem("apns")).pem, APNS_KEY_ID: "SYNTHKEY01", APNS_TEAM_ID: "SYNTHTEAM1",
      APNS_HOST: "api.sandbox.push.apple.com" as const, BUNDLE_ID: "com.healthmd.synthetic", FCM_SERVICE_ACCOUNT_JSON: "not-json" };
    const mocked = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 200 }));
    vi.stubGlobal("fetch", mocked);
    expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "cd".repeat(16), WAKE_HASH, TIMESTAMP, 1)), env)).json())
      .toEqual({ status: "delivered" });
    expect(mocked.mock.calls[0][0]).toBe(`https://api.sandbox.push.apple.com/3/device/${APNS_TOKEN}`);
    expect(mocked.mock.calls[0][1]?.headers).toMatchObject({ "apns-topic": "com.healthmd.synthetic" });
    expect(mocked).toHaveBeenCalledTimes(1);
  } finally { DB.sqlite.close(); }
});

it("does not reuse APNs JWTs when credentials change under the same key ID", async () => {
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  const DB = new TestD1();
  try {
    const { wakeId } = await (await worker.fetch(jsonRequest("/wake/register", registration), { DB })).json() as { wakeId: string };
    const mocked = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 200 }));
    vi.stubGlobal("fetch", mocked);
    for (let index = 0; index < 2; index++) {
      const time = NOW + index * 30_000;
      vi.spyOn(Date, "now").mockReturnValue(time);
      const env = { DB, APNS_AUTH_KEY: (await syntheticPem("apns")).pem, APNS_KEY_ID: "SYNTHKEY01", APNS_TEAM_ID: "SYNTHTEAM1" };
      const timestamp = new Date(time).toISOString().replace(".000Z", "Z");
      expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, String(index).repeat(32), WAKE_HASH, timestamp, 1)), env)).json())
        .toEqual({ status: "delivered" });
    }
    expect(new Headers(mocked.mock.calls[0][1]?.headers).get("authorization"))
      .not.toEqual(new Headers(mocked.mock.calls[1][1]?.headers).get("authorization"));
  } finally { DB.sqlite.close(); }
});

it("times out a stalled APNs provider without failing the legacy request or consuming budget", async () => {
  vi.useFakeTimers(); vi.setSystemTime(NOW);
  const DB = new TestD1();
  try {
    const { wakeId } = await (await worker.fetch(jsonRequest("/wake/register", registration), { DB })).json() as { wakeId: string };
    const env = { DB, APNS_AUTH_KEY: (await syntheticPem("apns")).pem, APNS_KEY_ID: "SYNTHKEY01", APNS_TEAM_ID: "SYNTHTEAM1" };
    const mocked = vi.fn<typeof fetch>().mockImplementation(() => new Promise(() => {}));
    vi.stubGlobal("fetch", mocked);
    const pending = worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "cd".repeat(16), WAKE_HASH, TIMESTAMP, 1)), env);
    await vi.waitFor(() => expect(mocked).toHaveBeenCalledTimes(1));
    await vi.advanceTimersByTimeAsync(5000);
    expect(await (await pending).json()).toEqual({ status: "undeliverable" });
    expect(mocked.mock.calls[0][1]?.signal?.aborted).toBe(true);
    expect(DB.sqlite.prepare("SELECT * FROM wake_counters").all()).toEqual([]);
  } finally { DB.sqlite.close(); }
});
