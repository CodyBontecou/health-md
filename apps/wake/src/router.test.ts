import { afterEach, beforeEach, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { APNS_TOKEN, NOW, USER_ID, WAKE_HASH, enrollment, jsonRequest } from "./test-helpers";

let DB: TestD1;
beforeEach(() => { DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]); vi.spyOn(Date, "now").mockReturnValue(NOW); });
afterEach(() => { DB.sqlite.close(); vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("preserves liveness, unknown route, method and unconfigured D1 behavior", async () => {
  expect(await (await worker.fetch(new Request("https://wake.invalid/health"), {})).json())
    .toEqual({ ok: true, service: "healthmd-wake" });
  expect((await worker.fetch(new Request("https://wake.invalid/no-such-route"), {})).status).toBe(404);
  for (const path of ["/wake/register", "/wake/request", "/wake/v2/register", "/wake/v2/request"]) {
    expect((await worker.fetch(new Request(`https://wake.invalid${path}`), {})).status).toBe(405);
    expect(await (await worker.fetch(jsonRequest(path, {}), {})).json()).toEqual({ error: "D1 binding not configured" });
  }
});

it("contains D1 exceptions on every write path without logging bound values or errors", async () => {
  const log = vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(DB, "prepare").mockImplementation(() => { throw new Error("synthetic-private-D1-marker"); });
  const legacy = { userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH };
  for (const [path, body] of [["/wake/register", legacy], ["/wake/v2/register", await enrollment()]] as const) {
    const response = await worker.fetch(jsonRequest(path, body), { DB });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "wake_storage_unavailable" });
  }
  expect(log).not.toHaveBeenCalled();
});

it("rejects array/invalid JSON and oversized Content-Length without retaining content", async () => {
  for (const path of ["/wake/register", "/wake/v2/register", "/wake/v2/request"]) {
    for (const body of ["[]", "null", "synthetic-invalid-json", "{\"userId\":\"synthetic-user\"}"]) {
      const response = await worker.fetch(new Request(`https://wake.invalid${path}`, {
        method: "POST", body, headers: { "content-length": "100000" },
      }), { DB });
      expect(await response.json()).toEqual({ error: "Invalid JSON body" });
    }
    expect((await worker.fetch(jsonRequest(path, []), { DB })).status).toBe(400);
  }
});

it("cancels a request body that never finishes instead of hanging a Worker", async () => {
  vi.useFakeTimers(); vi.setSystemTime(NOW);
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({ cancel: () => { cancelled = true; } });
  // Node's Request requires duplex for streams; production has no Node dependency.
  const options = { method: "POST", body, duplex: "half" };
  const pending = worker.fetch(new Request("https://wake.invalid/wake/v2/register", options), { DB });
  await vi.advanceTimersByTimeAsync(5000);
  expect(await (await pending).json()).toEqual({ error: "Invalid JSON body" });
  expect(cancelled).toBe(true);
});
