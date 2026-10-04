import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { APNS_TOKEN, USER_ID, WAKE_HASH, NOW, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

let DB: TestD1;
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("never treats an added legacy transport/token field as FCM enrollment", async () => {
  const response = await worker.fetch(jsonRequest("/wake/register", {
    userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH, transport: "fcm",
  }), { DB });
  expect(response.status).toBe(400);
  expect(DB.sqlite.prepare("SELECT wake_id FROM wake_registrations").all()).toEqual([]);
});

it("bounds legacy request bodies without reflecting forbidden content", async () => {
  const secretMarker = "synthetic-private-marker";
  for (const path of ["/wake/register", "/wake/request"]) {
    const response = await worker.fetch(jsonRequest(path, { healthPayload: secretMarker.repeat(1024) }), { DB });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "Invalid JSON body" });
  }
});

it("sanitizes APNs errors, credential failures, and provider exceptions without logs or leaks", async () => {
  const marker = "synthetic-private-provider-marker";
  const logs = [vi.spyOn(console, "log").mockImplementation(() => {}), vi.spyOn(console, "error").mockImplementation(() => {})];
  const registered = await worker.fetch(jsonRequest("/wake/register", {
    userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH,
  }), { DB });
  const { wakeId } = await registered.json() as { wakeId: string };
  const { pem } = await syntheticPem("apns");
  const env = { DB, APNS_AUTH_KEY: pem, APNS_KEY_ID: "SYNTHKEY01", APNS_TEAM_ID: "SYNTHTEAM1" };
  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ reason: marker }, { status: 400 }));
  vi.stubGlobal("fetch", fetchMock);
  expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "ad".repeat(16), WAKE_HASH, undefined, 1)), env)).json())
    .toEqual({ status: "undeliverable" });
  fetchMock.mockRejectedValue(new Error(marker));
  expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "ae".repeat(16), WAKE_HASH, undefined, 1)), env)).json())
    .toEqual({ status: "undeliverable" });
  fetchMock.mockClear();
  expect(await (await worker.fetch(jsonRequest("/wake/request", await ringBody(wakeId, "af".repeat(16), WAKE_HASH, undefined, 1)), { ...env, APNS_AUTH_KEY: marker })).json())
    .toEqual({ status: "undeliverable" });
  expect(fetchMock).not.toHaveBeenCalled();
  for (const log of logs) expect(log).not.toHaveBeenCalled();
});
