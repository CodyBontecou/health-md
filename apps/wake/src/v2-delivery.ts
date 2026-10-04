/** Authenticated v2 dispatch with atomic per-wake-ID replay/policy reservation. */
import { sendFcmWake } from "./fcm";
import { jsonResponse, onlyFields, readJsonBody } from "./http";
import { decideDelivery, DEDUPE_WINDOW_SEC, HMAC_RE, HOURLY_DELIVERY_LIMIT, NONCE_RE, nonceRetentionCutoff, timestampWithinWindow, type CounterRow } from "./state";
import { REQUEST_DOMAIN, V2_WAKE_ID_RE, v2Timestamp, verifyV2Proof } from "./v2";
import type { WakeEnv } from "./wake";

/** Longer than two bounded provider calls; expired leases are recoverable after a crash. */
export const DELIVERY_LEASE_SEC = 30;
interface Registration {
  verification_hash: string;
  device_token: string;
  transport: string;
  registration_version: number;
}
interface Counter extends CounterRow { in_flight_until: number }

export async function handleV2Request(request: Request, env: WakeEnv, fcmConfig: string | undefined): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) return jsonResponse({ error: "Invalid JSON body" }, 400);
  const { wakeId, nonce, timestamp, hmac } = body;
  if (
    !onlyFields(body, ["wakeId", "nonce", "timestamp", "hmac"])
    || typeof wakeId !== "string" || !V2_WAKE_ID_RE.test(wakeId)
    || typeof nonce !== "string" || !NONCE_RE.test(nonce) || nonce.length % 2 !== 0
    || typeof timestamp !== "string" || v2Timestamp(timestamp) === null
    || typeof hmac !== "string" || !HMAC_RE.test(hmac)
  ) return jsonResponse({ error: "wake_request_invalid" }, 400);
  const now = env.nowSec?.() ?? Math.floor(Date.now() / 1000);
  const registration = await env.DB.prepare("SELECT verification_hash, device_token, transport, registration_version FROM wake_registrations WHERE wake_id = ?")
    .bind(wakeId).first<Registration>();
  if (!registration || registration.registration_version !== 2 || registration.transport !== "fcm") {
    return jsonResponse({ error: "wake_unknown" }, 404);
  }
  if (!await verifyV2Proof(registration.verification_hash, JSON.stringify([REQUEST_DOMAIN, wakeId, nonce, timestamp]), hmac)) {
    return jsonResponse({ error: "wake_hmac_invalid" }, 401);
  }
  if (!timestampWithinWindow(v2Timestamp(timestamp)!, now)) return jsonResponse({ error: "wake_timestamp_stale" }, 401);
  const bucket = Math.floor(now / 3600);
  // D1 batch is a transaction. changes() couples nonce consumption and lease
  // acquisition; no read-then-write window can deliver the same nonce twice.
  const results = await env.DB.batch([
    env.DB.prepare("DELETE FROM wake_v2_nonces WHERE wake_id = ? AND seen_at < ?").bind(wakeId, nonceRetentionCutoff(now)),
    env.DB.prepare(`INSERT INTO wake_v2_nonces (wake_id, nonce, seen_at)
      SELECT wake_id, ?, ? FROM wake_registrations
      WHERE wake_id = ? AND verification_hash = ? AND device_token = ? AND transport = 'fcm' AND registration_version = 2
      ON CONFLICT(wake_id, nonce) DO NOTHING`).bind(nonce, now, wakeId, registration.verification_hash, registration.device_token),
    env.DB.prepare(`INSERT INTO wake_counters
      (wake_id, hour_bucket, delivered_this_hour, last_delivered_at, in_flight_nonce, in_flight_until)
      SELECT ?, ?, 0, 0, ?, ? WHERE changes() = 1
      ON CONFLICT(wake_id) DO UPDATE SET in_flight_nonce = excluded.in_flight_nonce, in_flight_until = excluded.in_flight_until
      WHERE wake_counters.in_flight_until <= ? AND wake_counters.last_delivered_at <= ?
        AND (wake_counters.hour_bucket != ? OR wake_counters.delivered_this_hour < ?)`)
      .bind(wakeId, bucket, nonce, now + DELIVERY_LEASE_SEC, now, now - DEDUPE_WINDOW_SEC, bucket, HOURLY_DELIVERY_LIMIT),
  ]);
  if (results[1].meta.changes !== 1) {
    const replayed = await env.DB.prepare("SELECT nonce FROM wake_v2_nonces WHERE wake_id = ? AND nonce = ?").bind(wakeId, nonce).first();
    return replayed ? jsonResponse({ error: "wake_nonce_replayed" }, 401) : jsonResponse({ error: "wake_auth_changed" }, 409);
  }
  if (results[2].meta.changes !== 1) {
    const counter = await env.DB.prepare("SELECT hour_bucket, delivered_this_hour, last_delivered_at, in_flight_until FROM wake_counters WHERE wake_id = ?")
      .bind(wakeId).first<Counter>();
    const decision = decideDelivery(counter, now);
    if (decision.kind === "deduplicated") return jsonResponse({ status: "deduplicated" });
    if (decision.kind === "rate_limited") return jsonResponse({ error: "wake_rate_limited", retryAfterSeconds: decision.retryAfterSeconds }, 429);
    return jsonResponse({ error: "wake_in_flight", retryAfterSeconds: Math.max(1, (counter?.in_flight_until ?? now + DELIVERY_LEASE_SEC) - now) }, 429);
  }

  const result = await sendFcmWake(fcmConfig, registration.device_token, now);
  if (result.kind !== "delivered") {
    await env.DB.prepare("UPDATE wake_counters SET in_flight_nonce = NULL, in_flight_until = 0 WHERE wake_id = ? AND in_flight_nonce = ?")
      .bind(wakeId, nonce).run();
    return result.kind === "unavailable" ? jsonResponse({ error: result.code }, 503) : jsonResponse({ status: "undeliverable" });
  }
  const acceptedAt = env.nowSec?.() ?? Math.floor(Date.now() / 1000);
  const acceptedBucket = Math.floor(acceptedAt / 3600);
  await env.DB.prepare(`UPDATE wake_counters SET hour_bucket = ?, delivered_this_hour = CASE
      WHEN hour_bucket = ? THEN delivered_this_hour + 1 ELSE 1 END,
      last_delivered_at = ?, in_flight_nonce = NULL, in_flight_until = 0
      WHERE wake_id = ? AND in_flight_nonce = ?`)
    .bind(acceptedBucket, acceptedBucket, acceptedAt, wakeId, nonce).run();
  return jsonResponse({ status: "delivered" });
}
