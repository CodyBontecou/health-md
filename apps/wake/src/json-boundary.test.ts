import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { enrollment, NOW, jsonRequest, ringBody, revokeBody, syntheticPem, USER_ID, APNS_TOKEN, WAKE_HASH } from "./test-helpers";

let DB: TestD1;
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  // Every outbound call is intercepted, including unexpected ones on a red run.
  vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockRejectedValue(new Error("synthetic-outbound-denied")));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

function rawRequest(path: string, body: string, method = "POST"): Request {
  return new Request(`https://wake.invalid${path}`, {
    method, headers: { "content-type": "application/json" }, body,
  });
}

it("rejects a duplicate enrollment field before a later token can hide an unapproved value", async () => {
  const body = await enrollment();
  // The proof is valid for the ordinary final fields; it does not legitimize
  // the earlier unapproved object discarded by last-key-wins JSON decoding.
  const raw = '{"deliveryToken":{"unapproved":"synthetic-private-marker"},' + JSON.stringify(body).slice(1);
  const prepare = vi.spyOn(DB, "prepare");
  const logs = [vi.spyOn(console, "log").mockImplementation(() => {}), vi.spyOn(console, "error").mockImplementation(() => {})];
  const response = await worker.fetch(rawRequest("/wake/v2/register", raw), { DB });
  expect(response.status).toBe(400);
  expect(await response.json()).toEqual({ error: "Invalid JSON body" });
  expect(response.headers.get("cache-control")).toBe("no-store");
  expect(prepare).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
  for (const log of logs) expect(log).not.toHaveBeenCalled();
});

it("rejects ambiguous OAuth JSON without dispatching an FCM notification", async () => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), { DB })).status).toBe(200);
  const env = await fcmEnv();
  const outbound = vi.mocked(fetch);
  outbound.mockResolvedValueOnce(new Response(
    '{"access_token":{"unapproved":"synthetic-private-marker"},"access_token":"synthetic-access","token_type":"Bearer","expires_in":3600}',
  )).mockResolvedValueOnce(Response.json({ name: "projects/synthetic-project/messages/synthetic-message" }));
  const response = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env);
  expect(await response.json()).toEqual({ status: "undeliverable" });
  expect(outbound).toHaveBeenCalledTimes(1);
  expect(outbound.mock.calls[0][0]).toBe("https://oauth2.googleapis.com/token");
});

async function fcmEnv() {
  return { DB, FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
    type: "service_account", project_id: "synthetic-project",
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com",
    private_key: (await syntheticPem("fcm")).pem,
  }) };
}

it.each([
  ["v1 enroll", "/wake/register", "POST", "user\\u0049d"],
  ["v1 rotate", "/wake/register", "POST", "wake\\u0049d"],
  ["v1 revoke", "/wake/register", "DELETE", "userId"],
  ["v1 ring", "/wake/request", "POST", "no\\u006ece"],
  ["v2 enroll", "/wake/v2/register", "POST", "delivery\\u0054oken"],
  ["v2 rotate", "/wake/v2/register", "POST", "operation"],
  ["v2 revoke", "/wake/v2/register", "DELETE", "pro\\u006ff"],
  ["v2 ring", "/wake/v2/request", "POST", "hmac"],
])("rejects decoded duplicate keys at %s before state/provider access", async (label, path, method, keyLiteral) => {
  const legacy = { userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH };
  const registered = await worker.fetch(jsonRequest("/wake/register", legacy), { DB });
  const result: unknown = await registered.json();
  if (typeof result !== "object" || result === null || !("wakeId" in result) || typeof result.wakeId !== "string") {
    throw new Error("Synthetic legacy enrollment failed");
  }
  const enrolled = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", enrolled), { DB })).status).toBe(200);
  const bodies: Record<string, unknown> = {
    "v1 enroll": legacy,
    "v1 rotate": { ...legacy, wakeId: result.wakeId },
    "v1 revoke": { userId: USER_ID, wakeId: result.wakeId },
    "v1 ring": await ringBody(result.wakeId, "cd".repeat(16), undefined, undefined, 1),
    "v2 enroll": await enrollment({ wakeId: "13".repeat(16) }),
    "v2 rotate": await enrollment({ operation: "rotate", nonce: "ce".repeat(16) }),
    "v2 revoke": await revokeBody(enrolled.wakeId, "cf".repeat(16)),
    "v2 ring": await ringBody(enrolled.wakeId, "d0".repeat(16)),
  };
  const raw = `{"${keyLiteral}":{"unapproved":"synthetic-private-marker"},` + JSON.stringify(bodies[label]).slice(1);
  const prepare = vi.spyOn(DB, "prepare");
  const batch = vi.spyOn(DB, "batch");
  const logs = [vi.spyOn(console, "log").mockImplementation(() => {}), vi.spyOn(console, "error").mockImplementation(() => {})];
  const response = await worker.fetch(rawRequest(path, raw, method), { DB });
  expect(response.status).toBe(400);
  expect(await response.json()).toEqual({ error: "Invalid JSON body" });
  expect(prepare).not.toHaveBeenCalled();
  expect(batch).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
  for (const log of logs) expect(log).not.toHaveBeenCalled();
});

it.each([
  ["escaped OAuth key", '{"access\\u005ftoken":"synthetic-first","access_token":"synthetic-access","token_type":"Bearer","expires_in":3600}', false],
  ["nested OAuth key", '{"access_token":"synthetic-access","token_type":"Bearer","expires_in":3600,"metadata":[{"key":1,"k\\u0065y":2}]}', false],
  ["equal FCM keys", '{"name":"projects/synthetic-project/messages/synthetic-message","name":"projects/synthetic-project/messages/synthetic-message"}', true],
])("rejects %s in bounded provider JSON", async (_label, raw, delivery) => {
  const body = await enrollment();
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), { DB })).status).toBe(200);
  const env = await fcmEnv();
  const outbound = vi.mocked(fetch);
  if (delivery) {
    outbound.mockResolvedValueOnce(Response.json({ access_token: "synthetic-access", token_type: "Bearer", expires_in: 3600 }));
  }
  outbound.mockResolvedValueOnce(new Response(raw));
  const request = await ringBody(body.wakeId, "cd".repeat(16));
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env)).json()).toEqual({ status: "undeliverable" });
  expect(outbound).toHaveBeenCalledTimes(delivery ? 2 : 1);
  // Authenticated input consumed its nonce before the provider rejection;
  // this differs from an ambiguous request rejected without storage access.
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", request), env)).json()).toEqual({ error: "wake_nonce_replayed" });
  expect(outbound).toHaveBeenCalledTimes(delivery ? 2 : 1);
});

it("preserves valid escaped keys, string punctuation and repeated sibling metadata keys", async () => {
  const body = await enrollment();
  const raw = JSON.stringify(body).replace('"deliveryToken":', '"delivery\\u0054oken":');
  expect((await worker.fetch(rawRequest("/wake/v2/register", raw), { DB })).status).toBe(200);
  const env = await fcmEnv();
  const metadata: Record<string, unknown>[] = [
    { shared: 'quote" comma, colon: brackets[] braces{} backslash\\', constructor: "synthetic", literal: "null true false 1.2e+3" },
    { shared: "synthetic-🚀", flags: [null, true, false, -1.25e3] },
  ];
  const oauth = JSON.stringify({ access_token: "synthetic-access", token_type: "Bearer", expires_in: 3600, metadata })
    .replace('"access_token":', '"access\\u005ftoken":');
  const outbound = vi.mocked(fetch);
  outbound.mockResolvedValueOnce(new Response(oauth)).mockResolvedValueOnce(Response.json({
    name: "projects/synthetic-project/messages/synthetic-message", metadata,
  }));
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), env)).json())
    .toEqual({ status: "delivered" });
  expect(outbound).toHaveBeenCalledTimes(2);
});
