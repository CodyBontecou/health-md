import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import worker, { BUNDLE_ID } from "../src/index.js";
import { apnsHost, sendSilentPush } from "../src/apns.js";
import { computeNextFire } from "../src/scheduling.js";

test("APNs wire request uses the selected environment, background type and priority 5", async () => {
  const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const bytes = await webcrypto.subtle.exportKey("pkcs8", pair.privateKey);
  const authKey = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(bytes).toString("base64")}\n-----END PRIVATE KEY-----`;
  const original = globalThis.fetch;
  try {
    for (const environment of ["development", "production", null]) {
      globalThis.fetch = async (url, options) => {
        assert.equal(new URL(url).hostname, environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com");
        assert.equal(options.headers["apns-topic"], BUNDLE_ID);
        assert.equal(options.headers["apns-push-type"], "background");
        assert.equal(options.headers["apns-priority"], "5");
        assert.equal(options.headers["apns-expiration"], "123456");
        assert.deepEqual(JSON.parse(options.body), { aps: { "content-available": 1 }, type: "scheduled-export", fireAt: "synthetic" });
        return new Response(JSON.stringify({ reason: "Unregistered", timestamp: 123000 }), { status: 410, headers: { "apns-id": "synthetic-id" } });
      };
      assert.deepEqual(await sendSilentPush({ authKey, keyId: "synthetic-key", teamId: "synthetic-team" }, {
        apnsToken: "synthetic-device", bundleId: BUNDLE_ID, host: apnsHost(environment),
        customPayload: { type: "scheduled-export", fireAt: "synthetic" }, expirationSec: 123456
      }), { status: 410, reason: "Unregistered", timestamp: 123000, apnsId: "synthetic-id" });
    }
  } finally { globalThis.fetch = original; }
});

test("restored receipt verifier retains production-to-sandbox fallback and legacy cutoff", async () => {
  const original = globalThis.fetch;
  const calls = [];
  try {
    globalThis.fetch = async (url, options) => {
      calls.push(url);
      assert.equal(JSON.parse(options.body)["receipt-data"], "synthetic-receipt");
      return new Response(JSON.stringify(calls.length === 1 ? { status: 21007 } : {
        status: 0, receipt: { bundle_id: BUNDLE_ID, original_application_version: "1",
          original_purchase_date_ms: String(Date.parse("2026-04-25T12:00:00Z")) }
      }));
    };
    const result = await worker.fetch(new Request("https://worker.test/verify-legacy", {
      method: "POST", body: JSON.stringify({ receipt: "synthetic-receipt" })
    }), {});
    assert.equal(result.status, 200);
    assert.equal(result.headers.get("Cache-Control"), "no-store");
    assert.deepEqual(await result.json(), { isLegacy: true, originalVersion: "1" });
    assert.deepEqual(calls, ["https://buy.itunes.apple.com/verifyReceipt", "https://sandbox.itunes.apple.com/verifyReceipt"]);
  } finally { globalThis.fetch = original; }
});

test("receipt JWS rejects wrong bundle/implausible dates and preserves cutoff/debug behavior", async () => {
  async function verify(bundleId, date, env = {}) {
    const jws = `header.${Buffer.from(JSON.stringify({ bundleId, originalApplicationVersion: "1", originalPurchaseDate: date })).toString("base64url")}.signature`;
    return worker.fetch(new Request("https://worker.test/verify-legacy-jws", { method: "POST", body: JSON.stringify({ jws }) }), env);
  }
  assert.equal((await verify("other.app", Date.parse("2026-04-25T12:00:00Z"))).status, 400);
  assert.equal((await verify(BUNDLE_ID, 0)).status, 400);
  assert.deepEqual(await (await verify(BUNDLE_ID, Date.parse("2026-04-26T00:00:00Z"))).json(), { isLegacy: false, originalVersion: "1" });
  assert.deepEqual(await (await verify(BUNDLE_ID, Date.parse("2026-04-26T00:00:00Z"), { DEBUG_FORCE_LEGACY: "true" })).json(), { isLegacy: true, originalVersion: "1" });
});

test("daily/weekly scheduler retains Lisbon local time over the DST change", () => {
  const daily = { frequency: "daily", hour: 7, minute: 20 };
  assert.equal(computeNextFire(daily, "Europe/Lisbon", Date.parse("2026-10-07T06:20:00Z") / 1000), Date.parse("2026-10-08T06:20:00Z") / 1000);
  assert.equal(computeNextFire(daily, "Europe/Lisbon", Date.parse("2026-10-24T06:20:00Z") / 1000), Date.parse("2026-10-25T07:20:00Z") / 1000);
  assert.equal(computeNextFire({ ...daily, frequency: "weekly", weekday: 7 }, "Europe/Lisbon", Date.parse("2026-10-24T06:20:00Z") / 1000), Date.parse("2026-10-25T07:20:00Z") / 1000);
});
