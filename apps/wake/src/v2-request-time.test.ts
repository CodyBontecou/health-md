import { afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { NOW, enrollment, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

let DB: TestD1;
let clock: number;
let config: string;
beforeAll(async () => {
  config = JSON.stringify({ type: "service_account", project_id: "synthetic-project", private_key: (await syntheticPem("fcm")).pem,
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com" });
});
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  clock = NOW;
  vi.spyOn(Date, "now").mockImplementation(() => clock);
  vi.stubGlobal("fetch", vi.fn(() => { throw new Error("No live provider permitted"); }));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const ring = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/request", body), { DB });

it("rejects a wake proof that expires during verification before consuming its nonce or reserving delivery", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), { DB })).status).toBe(200);
  const request = await ringBody(body.wakeId, "d0".repeat(16));
  const verify = crypto.subtle.verify.bind(crypto.subtle);
  const delayed = vi.spyOn(crypto.subtle, "verify").mockImplementation(async (...args) => {
    const valid = await verify(...args);
    expect(valid).toBe(true);
    clock = NOW + 121_000;
    return valid;
  });
  const mutations = vi.spyOn(DB, "batch");
  const response = await ring(request);
  const outcome = await response.json();
  const mutationsBeforeRetry = mutations.mock.calls.length;
  delayed.mockRestore();
  // A separately started, already-stale proof confirms that the actual route
  // sees this clock and has timestamp rejection, not just configuration errors.
  const control = await ring(await ringBody(body.wakeId, "d1".repeat(16)));
  expect(control.status).toBe(401);
  expect(await control.json()).toEqual({ error: "wake_timestamp_stale" });
  // Missing credentials are deliberate. Fresh signed work with that same nonce
  // reaches configuration admission, rather than finding a burned replay nonce.
  const fresh = await ringBody(body.wakeId, request.nonce, undefined, "2026-10-04T12:02:01Z");
  const accepted = await ring(fresh);
  expect(await accepted.json()).toEqual({ error: "fcm_not_configured" });
  expect(accepted.status).toBe(503);
  expect(response.status).toBe(401);
  expect(outcome).toEqual({ error: "wake_timestamp_stale" });
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(mutationsBeforeRetry).toBe(0);
  expect(fetch).not.toHaveBeenCalled();
});

function verificationFinishesAt(milliseconds: number) {
  const verify = crypto.subtle.verify.bind(crypto.subtle);
  return vi.spyOn(crypto.subtle, "verify").mockImplementation(async (...args) => {
    const valid = await verify(...args);
    expect(valid).toBe(true);
    clock = milliseconds;
    return valid;
  });
}
async function registered() {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), { DB })).status).toBe(200);
  return body.wakeId;
}
const timestamp = () => new Date(clock).toISOString().replace(".000Z", "Z");
function configuredProvider() {
  vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-access-token", token_type: "Bearer", expires_in: 3600 });
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });
    throw new Error("Unexpected provider URL");
  }));
}
const configuredRing = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/request", body), { DB, FCM_SERVICE_ACCOUNT_JSON: config });

it("clock retreat rejects a now-future wake proof without burning it", async () => {
  const id = await registered();
  const request = await ringBody(id, "d2".repeat(16));
  const delayed = verificationFinishesAt(NOW - 121_000);
  const response = await ring(request);
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_timestamp_stale" });
  delayed.mockRestore();
  clock = NOW;
  expect(await (await ring(request)).json()).toEqual({ error: "fcm_not_configured" });
  expect(fetch).not.toHaveBeenCalled();
});

it.each([-120_000, 120_000])("retains the inclusive timestamp boundary after verification at %i milliseconds", async (offset) => {
  const id = await registered();
  const request = await ringBody(id, "d3".repeat(16));
  verificationFinishesAt(NOW + offset);
  const response = await ring(request);
  expect(response.status).toBe(503);
  expect(await response.json()).toEqual({ error: "fcm_not_configured" });
  expect(fetch).not.toHaveBeenCalled();
});

it("valid delayed verification starts the immutable original lease at admission, not arrival", async () => {
  const id = await registered();
  const request = await ringBody(id, "d4".repeat(16));
  configuredProvider();
  const delayed = verificationFinishesAt(NOW + 61_000);
  expect(await (await configuredRing(request)).json()).toEqual({ status: "delivered" });
  expect(fetch).toHaveBeenCalledTimes(2);
  delayed.mockRestore();
  expect(await (await configuredRing(request)).json()).toEqual({ error: "wake_nonce_replayed" });
  expect(fetch).toHaveBeenCalledTimes(2);
});

it("verification crossing the dedupe boundary uses current admission time and counts both accepted requests", async () => {
  const id = await registered();
  configuredProvider();
  expect(await (await configuredRing(await ringBody(id, "d5".repeat(16)))).json()).toEqual({ status: "delivered" });
  clock = NOW + 29_000;
  const request = await ringBody(id, "d6".repeat(16), undefined, timestamp());
  verificationFinishesAt(NOW + 30_000);
  expect(await (await configuredRing(request)).json()).toEqual({ status: "delivered" });
  expect(fetch).toHaveBeenCalledTimes(4);
});

it("verification crossing the hourly boundary uses the new bucket without weakening the six-acceptance limit", async () => {
  const id = await registered();
  configuredProvider();
  for (let index = 0; index < 6; index++) {
    clock = NOW + index * 30_000;
    expect(await (await configuredRing(await ringBody(id, index.toString(16).padStart(32, "0"), undefined, timestamp()))).json()).toEqual({ status: "delivered" });
  }
  clock = NOW + 180_000;
  const limited = await configuredRing(await ringBody(id, "d7".repeat(16), undefined, timestamp()));
  expect(limited.status).toBe(429);
  expect(await limited.json()).toEqual({ error: "wake_rate_limited", retryAfterSeconds: 3420 });
  clock = NOW + 3_599_000;
  const request = await ringBody(id, "d8".repeat(16), undefined, timestamp());
  verificationFinishesAt(NOW + 3_600_000);
  expect(await (await configuredRing(request)).json()).toEqual({ status: "delivered" });
  expect(fetch).toHaveBeenCalledTimes(14);
});
