import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "./index";
import { TestD1 } from "./test-support.mjs";
import { NOW, WAKE_HASH, enrollment, jsonRequest, ringBody, syntheticPem } from "./test-helpers";

let DB: TestD1;
let config: string;
let clock: number;
const timestamp = () => new Date(clock).toISOString().replace(".000Z", "Z");
const oauth = () => Response.json({ access_token: "synthetic-access-token", token_type: "Bearer", expires_in: 3600 });
const accepted = () => Response.json({ name: "projects/synthetic-project/messages/synthetic-message" });
beforeAll(async () => {
  config = JSON.stringify({ type: "service_account", project_id: "synthetic-project", private_key: (await syntheticPem("fcm")).pem,
    client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com" });
});
beforeEach(() => {
  DB = new TestD1(["0001_init.sql", "0002_fcm_v2.sql"]);
  clock = NOW;
  vi.spyOn(Date, "now").mockImplementation(() => clock);
  vi.stubGlobal("fetch", vi.fn<typeof fetch>().mockImplementation(async (url) =>
    url === "https://oauth2.googleapis.com/token" ? oauth() : accepted()));
});
afterEach(() => { DB.sqlite.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
const env = () => ({ DB, FCM_SERVICE_ACCOUNT_JSON: config });
const ring = async (wakeId: string, nonce: string) => worker.fetch(jsonRequest("/wake/v2/request", await ringBody(wakeId, nonce, WAKE_HASH, timestamp())), env());
async function enroll(wakeId?: string) {
  const body = await enrollment(wakeId ? { wakeId } : {});
  expect((await worker.fetch(jsonRequest("/wake/v2/register", body), env())).status).toBe(200);
  return body.wakeId;
}

describe("per-ID delivery policy", () => {
  it("deduplicates at 29 seconds, delivers at 30, rejects nonce reuse before dedupe, and isolates other IDs", async () => {
    const id = await enroll();
    expect(await (await ring(id, "cd".repeat(16))).json()).toEqual({ status: "delivered" });
    expect(await (await ring(id, "cd".repeat(16))).json()).toEqual({ error: "wake_nonce_replayed" });
    clock += 29_000;
    expect(await (await ring(id, "ce".repeat(16))).json()).toEqual({ status: "deduplicated" });
    const other = await enroll("13".repeat(16));
    expect(await (await ring(other, "cd".repeat(16))).json()).toEqual({ status: "delivered" });
    clock += 1000;
    expect(await (await ring(id, "cf".repeat(16))).json()).toEqual({ status: "delivered" });
    expect(fetch).toHaveBeenCalledTimes(6);
  });

  it("permits six provider acceptances per hour, burns rate-limited nonces, and resets the next bucket", async () => {
    const id = await enroll();
    for (let index = 0; index < 6; index++) {
      clock = NOW + index * 30_000;
      const nonce = index.toString(16).padStart(32, "0");
      expect(await (await ring(id, nonce)).json()).toEqual({ status: "delivered" });
    }
    clock += 30_000;
    const limited = await ring(id, "ce".repeat(16));
    expect(limited.status).toBe(429);
    expect(await limited.json()).toEqual({ error: "wake_rate_limited", retryAfterSeconds: 3420 });
    expect(await (await ring(id, "ce".repeat(16))).json()).toEqual({ error: "wake_nonce_replayed" });
    expect(fetch).toHaveBeenCalledTimes(12);
    clock = NOW + 3_600_000;
    expect(await (await ring(id, "cf".repeat(16))).json()).toEqual({ status: "delivered" });
    expect(DB.sqlite.prepare("SELECT delivered_this_hour FROM wake_counters WHERE wake_id = ?").get(id)?.delivered_this_hour).toBe(1);
    // Pruning is scoped to the same ID and does not retain old request timestamps.
    expect(DB.sqlite.prepare("SELECT nonce FROM wake_v2_nonces WHERE wake_id = ?").all(id)).toEqual([{ nonce: "cf".repeat(16) }]);
  });

  it("recovers an expired delivery lease after a simulated request crash", async () => {
    const id = await enroll();
    DB.sqlite.exec(`INSERT INTO wake_counters (wake_id, hour_bucket, delivered_this_hour, last_delivered_at, in_flight_nonce, in_flight_until)
      VALUES ('${id}', 0, 0, 0, 'synthetic-old-lease', ${NOW / 1000 - 1})`);
    expect(await (await ring(id, "cd".repeat(16))).json()).toEqual({ status: "delivered" });
    expect(DB.sqlite.prepare("SELECT in_flight_nonce, in_flight_until FROM wake_counters WHERE wake_id = ?").get(id))
      .toEqual({ in_flight_nonce: null, in_flight_until: 0 });
  });
});

describe("database-atomic concurrency", () => {
  it("delivers the same concurrently signed nonce at most once", async () => {
    const id = await enroll();
    const responses = await Promise.all([ring(id, "cd".repeat(16)), ring(id, "cd".repeat(16))]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 401]);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reserves one delivery across distinct concurrent nonces without claiming an unfinished push was delivered", async () => {
    const id = await enroll();
    let release: (() => void) | undefined;
    const held = new Promise<Response>((resolve) => { release = () => resolve(oauth()); });
    const mocked = vi.fn<typeof fetch>().mockImplementation(async (url) => url === "https://oauth2.googleapis.com/token" ? held : accepted());
    vi.stubGlobal("fetch", mocked);
    const first = ring(id, "cd".repeat(16));
    await vi.waitFor(() => expect(mocked).toHaveBeenCalledTimes(1));
    const second = await ring(id, "ce".repeat(16));
    expect(second.status).toBe(429);
    expect(await second.json()).toEqual({ error: "wake_in_flight", retryAfterSeconds: 30 });
    expect(await (await ring(id, "ce".repeat(16))).json()).toEqual({ error: "wake_nonce_replayed" });
    release!();
    expect(await (await first).json()).toEqual({ status: "delivered" });
    expect(mocked).toHaveBeenCalledTimes(2);
  });
});
