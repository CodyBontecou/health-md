import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { NOW, enrollment, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

let credentials: Record<string, string>;
let DB: TestD1;
const MARKER = "synthetic-private-upstream-marker";
const oauth = () => Response.json({ access_token: "synthetic-access-token", token_type: "Bearer", expires_in: 3600 });
const accepted = () => Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });

beforeAll(async () => {
  const { pem } = await syntheticPem("fcm");
  credentials = { type: "service_account", project_id: "synthetic-project", private_key: pem,
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com", token_uri: "https://oauth2.googleapis.com/token" };
});
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  vi.spyOn(Date, "now").mockReturnValue(NOW);
  for (const name of ["log", "error", "warn", "info", "debug"] as const) vi.spyOn(console, name).mockImplementation(() => {});
});
afterEach(() => {
  for (const name of ["log", "error", "warn", "info", "debug"] as const) expect(console[name]).not.toHaveBeenCalled();
  DB.sqlite.close(); vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals();
});

async function attempt(config: string | undefined = JSON.stringify(credentials), nonce = "cd".repeat(16)) {
  const body = await enrollment();
  await worker.fetch(jsonRequest("/wake/v2/register", body), { DB });
  const response = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, nonce)), { DB, FCM_SERVICE_ACCOUNT_JSON: config });
  expect(response.headers.get("cache-control")).toBe("no-store");
  return response;
}

function mockProvider() {
  const mocked = vi.fn<typeof fetch>().mockImplementation(async (url, options) => {
    expect(options?.redirect).toBe("manual");
    return url === "https://oauth2.googleapis.com/token" ? oauth() : accepted();
  });
  vi.stubGlobal("fetch", mocked);
  return mocked;
}

describe("absent or malformed private configuration", () => {
  it.each(["", "{}", "not-json", "[]", "x".repeat(16385)])("contacts no provider for malformed config %#", async (config) => {
    const mocked = mockProvider();
    const response = await attempt(config);
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: config === "" ? "fcm_not_configured" : "fcm_config_invalid" });
    expect(mocked).not.toHaveBeenCalled();
  });

  it.each([
    { project_id: "../attacker" }, { project_id: "project.invalid/" },
    { client_email: "attacker@example.invalid" }, { private_key: MARKER },
    { token_uri: "https://attacker.invalid/token" }, { type: "authorized_user" },
    { private_key_id: "bad\r\nkey" },
  ])("does not derive HTTP authority from malformed credential fields %#", async (override) => {
    const mocked = mockProvider();
    const response = await attempt(JSON.stringify({ ...credentials, ...override }));
    expect(await response.json()).toEqual({ error: "fcm_config_invalid" });
    expect(mocked).not.toHaveBeenCalled();
  });

  it("degrades when the secret is absent and does not consume delivery budget", async () => {
    const mocked = mockProvider();
    const body = await enrollment();
    await worker.fetch(jsonRequest("/wake/v2/register", body), { DB });
    const response = await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16))), { DB });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "fcm_not_configured" });
    expect(mocked).not.toHaveBeenCalled();
    expect(DB.sqlite.prepare("SELECT delivered_this_hour, in_flight_until FROM wake_counters WHERE wake_id = ?").get(body.wakeId))
      .toEqual({ delivered_this_hour: 0, in_flight_until: 0 });
    expect(await (await worker.fetch(jsonRequest("/wake/v2/request", await ringBody(body.wakeId, "ce".repeat(16))), { DB, FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(credentials) })).json())
      .toEqual({ status: "delivered" });
  });
});

describe("fixed upstream failure surfaces", () => {
  it.each([400, 401, 403, 404, 429, 500, 302])("discards OAuth error body/redirect at status %s", async (status) => {
    const mocked = mockProvider().mockResolvedValue(new Response(MARKER, { status, headers: { location: "https://attacker.invalid" } }));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
    expect(mocked).toHaveBeenCalledTimes(1);
  });

  it.each([
    null, {}, { access_token: MARKER, token_type: "Bearer", expires_in: 0 },
    { access_token: MARKER, token_type: "Bearer", expires_in: 3601 },
    { access_token: MARKER, token_type: "Bearer", expires_in: 1.5 },
    { access_token: MARKER, token_type: "Bearer", expires_in: "3600" },
    { access_token: MARKER, token_type: "Other", expires_in: 3600 },
    { access_token: "secret\r\nheader", token_type: "Bearer", expires_in: 3600 },
    { access_token: "x".repeat(4097), token_type: "Bearer", expires_in: 3600 },
  ])("never sends an invalid OAuth response to FCM %#", async (body) => {
    const mocked = mockProvider().mockResolvedValue(Response.json(body));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
    expect(mocked).toHaveBeenCalledTimes(1);
  });

  it.each([400, 401, 403, 404, 429, 500, 302])("discards FCM error bodies at status %s", async (status) => {
    const mocked = mockProvider().mockResolvedValueOnce(oauth()).mockResolvedValueOnce(new Response(MARKER, { status }));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
    expect(mocked).toHaveBeenCalledTimes(2);
    expect(DB.sqlite.prepare("SELECT delivered_this_hour FROM wake_counters").get()?.delivered_this_hour).toBe(0);
  });

  it.each([{}, { name: MARKER }, { name: "projects/other-project/messages/synthetic-message" }])("does not reflect invalid provider acceptance %#", async (body) => {
    mockProvider().mockResolvedValueOnce(oauth()).mockResolvedValueOnce(Response.json(body));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
  });

  it.each(["oauth", "fcm"])("contains %s network exceptions without retaining raw text", async (stage) => {
    const mocked = mockProvider();
    if (stage === "fcm") mocked.mockResolvedValueOnce(oauth());
    mocked.mockRejectedValue(new Error(MARKER));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
    expect(JSON.stringify(DB.sqlite.prepare("SELECT * FROM wake_counters").all())).not.toContain(MARKER);
  });

  it.each(["oauth", "fcm"])("bounds streamed %s success bodies without a Content-Length", async (stage) => {
    const mocked = mockProvider();
    if (stage === "fcm") mocked.mockResolvedValueOnce(oauth());
    mocked.mockResolvedValueOnce(new Response(MARKER.repeat(1024)));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
  });

  it("rejects oversized declared provider bodies and invalid UTF-8/JSON", async () => {
    const mocked = mockProvider().mockResolvedValueOnce(new Response("{}", { headers: { "content-length": "100000" } }));
    expect(await (await attempt()).json()).toEqual({ status: "undeliverable" });
    mocked.mockResolvedValueOnce(new Response(new Uint8Array([0xff, 0xfe])));
    expect(await (await attempt(undefined, "ce".repeat(16))).json()).toEqual({ status: "undeliverable" });
  });
});

describe("deadlines cover fetch and streamed bodies", () => {
  it.each(["headers", "oauth-body", "fcm-body"])("aborts a stalled %s without a retry or budget consumption", async (stage) => {
    vi.useFakeTimers(); vi.setSystemTime(NOW);
    let cancelled = false;
    const stalled = () => new Response(new ReadableStream<Uint8Array>({ cancel: () => { cancelled = true; } }));
    const mocked = mockProvider();
    if (stage === "headers") mocked.mockImplementation(() => new Promise(() => {}));
    if (stage === "oauth-body") mocked.mockResolvedValueOnce(stalled());
    if (stage === "fcm-body") mocked.mockResolvedValueOnce(oauth()).mockResolvedValueOnce(stalled());
    const pending = attempt();
    await vi.waitFor(() => expect(mocked).toHaveBeenCalledTimes(stage === "fcm-body" ? 2 : 1));
    await vi.advanceTimersByTimeAsync(5000);
    expect(await (await pending).json()).toEqual({ status: "undeliverable" });
    expect(mocked.mock.calls.at(-1)?.[1]?.signal?.aborted).toBe(true);
    if (stage !== "headers") expect(cancelled).toBe(true);
    expect(DB.sqlite.prepare("SELECT delivered_this_hour, in_flight_until FROM wake_counters").get())
      .toEqual({ delivered_this_hour: 0, in_flight_until: 0 });
  });
});
