import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { MANAGEMENT_HASH, NOW, enrollment, jsonRequest, revokeBody, ringBody } from "./test-helpers";

let DB: TestD1;
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  vi.stubGlobal("fetch", vi.fn(() => { throw new Error("No live provider permitted"); }));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const register = (body: unknown) => worker.fetch(jsonRequest("/wake/v2/register", body), { DB });

it("rejects an enrollment that expires during actual proof verification without claiming its ID or nonce", async () => {
  const body = await enrollment();
  const verify = crypto.subtle.verify.bind(crypto.subtle);
  const delayed = vi.spyOn(crypto.subtle, "verify").mockImplementation(async (...args) => {
    const valid = await verify(...args);
    expect(valid).toBe(true);
    vi.mocked(Date.now).mockReturnValue(NOW + 121_000);
    return valid;
  });
  const mutations = vi.spyOn(DB, "batch");
  const response = await register(body);
  delayed.mockRestore();
  // Public control rules out a clock invisible to the actual route: an ordinary
  // request that starts now with that old timestamp is already rejected.
  expect((await register(await enrollment({ wakeId: "13".repeat(16) }))).status).toBe(401);
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_timestamp_stale" });
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(mutations).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
  // Fresh independent proof can claim that exact resource and nonce: expired work
  // did not create an enrollment/revocation or burn this nonce.
  expect((await register(await enrollment({ timestamp: "2026-10-04T12:02:01Z" }))).status).toBe(200);
});

it("rejects a revocation that expires during actual proof verification without burning its nonce or removing the registration", async () => {
  const body = await enrollment();
  expect((await register(body)).status).toBe(200);
  const removal = await revokeBody(body.wakeId, "bc".repeat(16));
  const verify = crypto.subtle.verify.bind(crypto.subtle);
  const delayed = vi.spyOn(crypto.subtle, "verify").mockImplementation(async (...args) => {
    const valid = await verify(...args);
    expect(valid).toBe(true);
    vi.mocked(Date.now).mockReturnValue(NOW + 121_000);
    return valid;
  });
  const mutations = vi.spyOn(DB, "batch");
  const response = await worker.fetch(jsonRequest("/wake/v2/register", removal, "DELETE"), { DB });
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_timestamp_stale" });
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(mutations).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
  delayed.mockRestore();
  const fresh = await revokeBody(body.wakeId, removal.nonce, undefined, undefined, "2026-10-04T12:02:01Z");
  expect(await (await worker.fetch(jsonRequest("/wake/v2/register", fresh, "DELETE"), { DB })).json()).toEqual({ ok: true });
});

function verificationFinishesAt(milliseconds: number) {
  const verify = crypto.subtle.verify.bind(crypto.subtle);
  return vi.spyOn(crypto.subtle, "verify").mockImplementation(async (...args) => {
    const valid = await verify(...args);
    expect(valid).toBe(true);
    vi.mocked(Date.now).mockReturnValue(milliseconds);
    return valid;
  });
}

it("expired rotation preserves the old wake capability and leaves the nonce for independently fresh management work", async () => {
  const body = await enrollment();
  expect((await register(body)).status).toBe(200);
  const rotation = await enrollment({ operation: "rotate", nonce: "bd".repeat(16), wakeKeyVerificationHash: "08".repeat(32) }, MANAGEMENT_HASH);
  const delayed = verificationFinishesAt(NOW + 121_000);
  const response = await register(rotation);
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_timestamp_stale" });
  delayed.mockRestore();
  const ring = await ringBody(body.wakeId, "be".repeat(16), undefined, "2026-10-04T12:02:01Z");
  expect(await (await worker.fetch(jsonRequest("/wake/v2/request", ring), { DB })).json()).toEqual({ error: "fcm_not_configured" });
  const fresh = await enrollment({ ...rotation, timestamp: "2026-10-04T12:02:01Z" }, MANAGEMENT_HASH);
  expect((await register(fresh)).status).toBe(200);
  expect(fetch).not.toHaveBeenCalled();
});

const operations: Array<"enroll" | "rotate" | "revoke"> = ["enroll", "rotate", "revoke"];
it.each(operations)("%s still accepts the inclusive original timestamp boundary after verification", async (operation) => {
  const body = await enrollment();
  if (operation !== "enroll") expect((await register(body)).status).toBe(200);
  const request = operation === "revoke" ? await revokeBody(body.wakeId, "bf".repeat(16))
    : await enrollment({ operation, nonce: "bf".repeat(16) }, MANAGEMENT_HASH);
  verificationFinishesAt(NOW + 120_000);
  const response = await worker.fetch(jsonRequest("/wake/v2/register", request, operation === "revoke" ? "DELETE" : "POST"), { DB });
  expect(response.status).toBe(200);
  expect(fetch).not.toHaveBeenCalled();
});

it.each(["enroll", "revoke"])("clock retreat makes an original %s proof too far in the future without consuming work", async (operation) => {
  const body = await enrollment();
  if (operation === "revoke") expect((await register(body)).status).toBe(200);
  const request = operation === "revoke" ? await revokeBody(body.wakeId, "c0".repeat(16)) : body;
  const delayed = verificationFinishesAt(NOW - 121_000);
  const response = await worker.fetch(jsonRequest("/wake/v2/register", request, operation === "revoke" ? "DELETE" : "POST"), { DB });
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_timestamp_stale" });
  delayed.mockRestore();
  vi.mocked(Date.now).mockReturnValue(NOW);
  expect((await worker.fetch(jsonRequest("/wake/v2/register", request, operation === "revoke" ? "DELETE" : "POST"), { DB })).status).toBe(200);
  expect(fetch).not.toHaveBeenCalled();
});

it.each(["enroll", "rotate"])("accepted delayed %s records live admission time rather than arrival time", async (operation) => {
  const body = await enrollment();
  if (operation === "rotate") expect((await register(body)).status).toBe(200);
  const request = await enrollment({ operation: operation === "rotate" ? "rotate" : "enroll", nonce: "c1".repeat(16) }, MANAGEMENT_HASH);
  const delayed = verificationFinishesAt(NOW + 61_000);
  expect((await register(request)).status).toBe(200);
  delayed.mockRestore();
  // Secondary storage-preservation observation, not the primary HTTP seam.
  const row = DB.sqlite.prepare("SELECT rotated_at FROM wake_registrations WHERE wake_id = ?").get(body.wakeId);
  expect(row).toEqual({ rotated_at: NOW / 1000 + 61 });
  expect(DB.sqlite.prepare("SELECT seen_at FROM wake_v2_nonces WHERE wake_id = ? AND nonce = ?").get(body.wakeId, request.nonce))
    .toEqual({ seen_at: NOW / 1000 + 61 });
  const replay = operation === "rotate" ? request : await enrollment({ operation: "rotate", nonce: request.nonce }, MANAGEMENT_HASH);
  const response = await register(replay);
  expect(response.status).toBe(401);
  expect(await response.json()).toEqual({ error: "wake_nonce_replayed" });
  expect(fetch).not.toHaveBeenCalled();
});
