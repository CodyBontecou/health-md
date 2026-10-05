import { afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { enrollment, jsonRequest, MANAGEMENT_HASH, NOW, revokeBody, ringBody, syntheticPem, WAKE_HASH } from "./test-helpers";

let DB: TestD1;
let config: string;
let clock: number;
const oauth = () => Response.json({ access_token: "synthetic-access", token_type: "Bearer", expires_in: 3600 });
const accepted = () => Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });
beforeAll(async () => {
  config = JSON.stringify({ type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com", private_key: (await syntheticPem("fcm")).pem });
});
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  clock = NOW;
  vi.spyOn(Date, "now").mockImplementation(() => clock);
  vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(new Error("synthetic-outbound-denied")));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const env = () => ({ DB, FCM_SERVICE_ACCOUNT_JSON: config });

it("does not start an FCM push after successful public revocation during OAuth", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  let revoked = false;
  let deliveryCalls = 0;
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      const response = await worker.fetch(jsonRequest("/wake/v2/register", await revokeBody(body.wakeId, "ce".repeat(16)), "DELETE"), env());
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ok: true });
      revoked = true;
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      deliveryCalls++;
      return accepted();
    }
    throw new Error("synthetic-outbound-denied");
  });
  const response = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env());
  expect(revoked).toBe(true);
  // Public lookup remains revoked; the stale pending ring must not outrun it.
  expect((await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cf".repeat(16))), env())).status).toBe(404);
  expect(deliveryCalls).toBe(0);
  expect(response.status).toBe(409);
  expect(await response.json()).toEqual({ error: "wake_auth_changed" });
  expect(outbound).toHaveBeenCalledTimes(1);
});

it("does not start an FCM push after its original lease expires during OAuth", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  let expireDuringOAuth = true;
  let deliveryCalls = 0;
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      if (expireDuringOAuth) { clock += 30_000; expireDuringOAuth = false; }
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      deliveryCalls++;
      return accepted();
    }
    throw new Error("synthetic-outbound-denied");
  });
  const request = await ringBody(body.wakeId, "cd".repeat(16));
  const response = await worker.fetch(jsonRequest("/wake/v2/request", request), env());
  expect(response.status).toBe(409);
  expect(await response.json()).toEqual({ error: "wake_auth_changed" });
  expect(deliveryCalls).toBe(0);
  expect(outbound).toHaveBeenCalledTimes(1);
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env())).json()).toEqual({ error: "wake_nonce_replayed" });
  // A fresh, independently authenticated request may acquire a new lease;
  // the rejected invocation cannot renew its own consumed nonce/lease.
  const timestamp = new Date(clock).toISOString().replace(".000Z", "Z");
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "ce".repeat(16), undefined, timestamp)), env())).json())
    .toEqual({ status: "delivered" });
  expect(deliveryCalls).toBe(1);
  expect(outbound).toHaveBeenCalledTimes(3);
});

it("does not let replaced lease metadata extend the invocation's original expiry", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      clock += 30_000;
      // External-store fault injection only. Observe rejection through HTTP
      // and provider calls; a later private value is not fresh admission.
      await DB.prepare("UPDATE wake_counters SET in_flight_until = in_flight_until + 60 WHERE wake_id = ?")
        .bind(body.wakeId).run();
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return accepted();
    throw new Error("synthetic-outbound-denied");
  });
  const request = await ringBody(body.wakeId, "cd".repeat(16));
  const response = await worker.fetch(jsonRequest("/wake/v2/request", request), env());
  expect(response.status).toBe(409);
  expect(await response.json()).toEqual({ error: "wake_auth_changed" });
  expect(outbound).toHaveBeenCalledTimes(1);
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env())).json()).toEqual({ error: "wake_nonce_replayed" });
});

it.each(["delivery token", "wake key"])("does not send against a %s replaced by public rotation during OAuth", async (field) => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const nextHash = "08".repeat(32);
  const token = field === "delivery token" ? "synthetic-replacement-token" : body.deliveryToken;
  const hash = field === "wake key" ? nextHash : WAKE_HASH;
  let rotated = false;
  const deliveries: string[] = [];
  const outbound = vi.mocked(fetch).mockImplementation(async (url, options) => {
    if (url === "https://oauth2.googleapis.com/token") {
      if (!rotated) {
        const rotation = await enrollment({ operation: "rotate", nonce: "ce".repeat(16), deliveryToken: token, wakeKeyVerificationHash: hash });
        expect((await worker.fetch(jsonRequest("/wake/v2/register", rotation), env())).status).toBe(200);
        rotated = true;
      }
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      deliveries.push(JSON.parse(String(options?.body)).message.token);
      return accepted();
    }
    throw new Error("synthetic-outbound-denied");
  });
  const response = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env());
  expect(rotated).toBe(true);
  expect(response.status).toBe(409);
  expect(await response.json()).toEqual({ error: "wake_auth_changed" });
  expect(deliveries).toEqual([]);
  expect(outbound).toHaveBeenCalledTimes(1);
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16), hash)), env())).json())
    .toEqual({ error: "wake_nonce_replayed" });
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cf".repeat(16), hash)), env())).json())
    .toEqual({ status: "delivered" });
  expect(deliveries).toEqual([token]);
  expect(outbound).toHaveBeenCalledTimes(3);
});

it("contains a final admission-read failure without starting a push or logging bound data", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const logs = [vi.spyOn(console, "log").mockImplementation(() => {}), vi.spyOn(console, "error").mockImplementation(() => {})];
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      // External D1 dependency fails on the next read after OAuth, without
      // mocking a Worker module or matching its SQL implementation.
      vi.spyOn(DB, "prepare").mockImplementationOnce(() => { throw new Error("synthetic-private-storage-marker"); });
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return accepted();
    throw new Error("synthetic-outbound-denied");
  });
  const request = await ringBody(body.wakeId, "cd".repeat(16));
  const response = await worker.fetch(jsonRequest("/wake/v2/request", request), env());
  expect(response.status).toBe(503);
  expect(await response.json()).toEqual({ error: "wake_storage_unavailable" });
  expect(outbound).toHaveBeenCalledTimes(1);
  for (const log of logs) expect(log).not.toHaveBeenCalled();
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env())).json()).toEqual({ error: "wake_nonce_replayed" });
});

it("does not clear a different request's active lease when the expired original returns from OAuth", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  let oauthCalls = 0;
  let second: Promise<Response> | undefined;
  let secondResponse: Response | undefined;
  let release: (() => void) | undefined;
  const held = new Promise<Response>((resolve) => { release = () => resolve(oauth()); });
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      oauthCalls++;
      if (oauthCalls === 1) {
        clock += 30_000;
        const timestamp = new Date(clock).toISOString().replace(".000Z", "Z");
        second = worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "ce".repeat(16), undefined, timestamp)), env());
        await vi.waitFor(() => expect(oauthCalls).toBe(2));
        return oauth();
      }
      return held;
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return accepted();
    throw new Error("synthetic-outbound-denied");
  });
  try {
    const first = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env());
    expect(first.status).toBe(409);
    expect(await first.json()).toEqual({ error: "wake_auth_changed" });
    const timestamp = new Date(clock).toISOString().replace(".000Z", "Z");
    const third = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cf".repeat(16), undefined, timestamp)), env());
    expect(third.status).toBe(429);
    expect(await third.json()).toEqual({ error: "wake_in_flight", retryAfterSeconds: 30 });
    expect(outbound).toHaveBeenCalledTimes(2);
  } finally {
    release?.();
    // Drain all started work before afterEach restores the fetch boundary,
    // including a red/assertion failure in the first request's checks.
    if (second) secondResponse = await second;
  }
  expect(secondResponse).toBeDefined();
  if (secondResponse) expect(await secondResponse.json()).toEqual({ status: "delivered" });
  expect(outbound).toHaveBeenCalledTimes(3);
});

it("rejects a timestamp that becomes outside the window before send without renewing its nonce", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") { clock -= 121_000; return oauth(); }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return accepted();
    throw new Error("synthetic-outbound-denied");
  });
  const request = await ringBody(body.wakeId, "cd".repeat(16));
  const response = await worker.fetch(jsonRequest("/wake/v2/request", request), env());
  expect(response.status).toBe(409);
  expect(await response.json()).toEqual({ error: "wake_auth_changed" });
  expect(outbound).toHaveBeenCalledTimes(1);
  clock = NOW;
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env())).json()).toEqual({ error: "wake_nonce_replayed" });
  expect(outbound).toHaveBeenCalledTimes(1);
});

it("preserves an unchanged wake capability when only the separate management key rotates", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") {
      const rotation = await enrollment({ operation: "rotate", nonce: "ce".repeat(16), managementKeyVerificationHash: "09".repeat(32) }, MANAGEMENT_HASH);
      expect((await worker.fetch(jsonRequest("/wake/v2/register", rotation), env())).status).toBe(200);
      return oauth();
    }
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") return accepted();
    throw new Error("synthetic-outbound-denied");
  });
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env())).json())
    .toEqual({ status: "delivered" });
  expect(outbound).toHaveBeenCalledTimes(2);
});

it("does not claim an already-started accepted provider push can be recalled by revocation", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  const outbound = vi.mocked(fetch).mockImplementation(async (url) => {
    if (url === "https://oauth2.googleapis.com/token") return oauth();
    if (url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      expect((await worker.fetch(jsonRequest("/wake/v2/register", await revokeBody(body.wakeId, "ce".repeat(16)), "DELETE"), env())).status).toBe(200);
      return accepted();
    }
    throw new Error("synthetic-outbound-denied");
  });
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env())).json())
    .toEqual({ status: "delivered" });
  expect((await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cf".repeat(16))), env())).status).toBe(404);
  expect(outbound).toHaveBeenCalledTimes(2);
});
