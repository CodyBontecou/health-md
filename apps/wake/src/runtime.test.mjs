/** Local workerd/D1 qualification using existing Wrangler transitive tooling.
 * No account access, credentials on disk, remote bindings, or live provider I/O.
 */
import { readFileSync } from "node:fs";
import { build } from "esbuild";
import { Miniflare, Response as LocalResponse, convertV4MiniflareOptions } from "miniflare";
import { expect, it } from "vitest";
import { enrollment, revokeBody, ringBody, syntheticPem, USER_ID, APNS_TOKEN, WAKE_HASH } from "./test-helpers.ts";

it("executes v2 enrollment, OAuth/FCM, replay, rotation and revoke on local workerd/D1 without network authority", async () => {
  const bundle = await build({ entryPoints: ["src/index.ts"], bundle: true, format: "esm", platform: "browser", write: false });
  let oauthCalls = 0;
  let deliveryCalls = 0;
  let ambiguousOAuth = false;
  const localJson = (body) => new LocalResponse(JSON.stringify(body), { headers: { "content-type": "application/json" } });
  // The locked Miniflare 5 alpha exposes a v4 options adapter and outbound service.
  const outboundService = async (request) => {
    if (request.url === "https://oauth2.googleapis.com/token") {
      oauthCalls++;
      if (ambiguousOAuth) return new LocalResponse(
        '{"access_token":"synthetic-first","access\\u005ftoken":"synthetic-runtime-access","token_type":"Bearer","expires_in":3600}',
        { headers: { "content-type": "application/json" } },
      );
      return localJson({ access_token: "synthetic-runtime-access", token_type: "Bearer", expires_in: 3600 });
    }
    if (request.url === "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send") {
      deliveryCalls++;
      const body = await request.json();
      expect(body.message.notification.body).toBe("A paired computer is requesting data. Tap to continue.");
      expect(body.message.data).toBeUndefined();
      return localJson({ name: "projects/synthetic-project/messages/synthetic-message" });
    }
    throw new Error("Outbound URL not authorized by local test");
  };
  const mf = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: bundle.outputFiles[0].text, compatibilityDate: "2025-01-01",
    cf: false, outboundService, d1Databases: { DB: "synthetic-local-wake" }, d1Persist: false,
    bindings: { FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
      type: "service_account", project_id: "synthetic-project", private_key: (await syntheticPem("fcm")).pem,
      client_email: "synthetic-worker@synthetic-project.iam.gserviceaccount.com",
    }) },
  }));
  try {
    const DB = await mf.getD1Database("DB");
    for (const migration of ["0001_init.sql", "0002_fcm_v2.sql"]) {
      const sql = readFileSync(new URL(`../migrations/${migration}`, import.meta.url), "utf8");
      for (const statement of sql.replace(/--[^\n]*/g, "").split(";").filter((s) => s.trim())) {
        await DB.prepare(statement).run();
      }
    }
    const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const request = (path, body, method = "POST") => mf.dispatchFetch(`https://wake.invalid${path}`, {
      method, headers: { "content-type": "application/json" }, body: JSON.stringify(body),
    });
    const rawRequest = (path, body) => mf.dispatchFetch(`https://wake.invalid${path}`, {
      method: "POST", headers: { "content-type": "application/json" }, body,
    });
    const body = await enrollment({ timestamp });
    const ambiguousEnrollment = '{"delivery\\u0054oken":{"unapproved":"synthetic-marker"},' + JSON.stringify(body).slice(1);
    const rejectedEnrollment = await rawRequest("/wake/v2/register", ambiguousEnrollment);
    expect(rejectedEnrollment.status).toBe(400);
    expect(await rejectedEnrollment.json()).toEqual({ error: "Invalid JSON body" });
    expect((await DB.prepare("SELECT wake_id FROM wake_registrations").all()).results).toEqual([]);
    expect(await (await request("/wake/v2/register", body)).json()).toEqual({ wakeId: body.wakeId });
    const firstRing = await ringBody(body.wakeId, "cd".repeat(16), WAKE_HASH, timestamp);
    const rejectedRing = await rawRequest("/wake/v2/request", '{"hmac":null,' + JSON.stringify(firstRing).slice(1));
    expect(rejectedRing.status).toBe(400);
    expect(await rejectedRing.json()).toEqual({ error: "Invalid JSON body" });
    expect(oauthCalls).toBe(0);
    expect(deliveryCalls).toBe(0);
    // The rejected duplicate did not burn this nonce or reserve a delivery.
    const delivery = await (await request("/wake/v2/request", firstRing)).json();
    expect(oauthCalls).toBe(1);
    expect(deliveryCalls).toBe(1);
    expect(delivery).toEqual({ status: "delivered" });
    expect(await (await request("/wake/v2/request", await ringBody(body.wakeId, "cd".repeat(16), WAKE_HASH, timestamp))).json())
      .toEqual({ error: "wake_nonce_replayed" });
    const rotation = await enrollment({ operation: "rotate", nonce: "ce".repeat(16), timestamp, deliveryToken: "synthetic-rotated-runtime-token" });
    expect(await (await request("/wake/v2/register", rotation)).json()).toEqual({ wakeId: body.wakeId });
    expect(await (await request("/wake/v2/request", await ringBody(body.wakeId, "cf".repeat(16), WAKE_HASH, timestamp))).json())
      .toEqual({ status: "deduplicated" });
    expect(await (await request("/wake/v2/register", await revokeBody(body.wakeId, "d0".repeat(16), undefined, USER_ID, timestamp), "DELETE")).json())
      .toEqual({ ok: true });
    expect((await request("/wake/v2/register", body)).status).toBe(409);
    expect((await DB.prepare("SELECT nonce FROM wake_v2_nonces WHERE wake_id = ?").bind(body.wakeId).all()).results).toEqual([]);
    // Legacy inserts after the forward migration remain APNs/v1, not FCM.
    const legacy = await (await request("/wake/register", { userId: USER_ID, deviceToken: APNS_TOKEN, wakeKeyVerificationHash: WAKE_HASH })).json();
    expect(await DB.prepare("SELECT transport, registration_version FROM wake_registrations WHERE wake_id = ?").bind(legacy.wakeId).first())
      .toEqual({ transport: "apns", registration_version: 1 });
    expect(oauthCalls).toBe(1);
    expect(deliveryCalls).toBe(1);
    const secondBody = await enrollment({ timestamp, wakeId: "14".repeat(16) });
    expect((await request("/wake/v2/register", secondBody)).status).toBe(200);
    ambiguousOAuth = true;
    const secondRing = await ringBody(secondBody.wakeId, "cd".repeat(16), WAKE_HASH, timestamp);
    expect(await (await request("/wake/v2/request", secondRing)).json()).toEqual({ status: "undeliverable" });
    expect(await (await request("/wake/v2/request", secondRing)).json()).toEqual({ error: "wake_nonce_replayed" });
    expect(oauthCalls).toBe(2);
    expect(deliveryCalls).toBe(1);
  } finally { await mf.dispose(); }
}, 20_000);
