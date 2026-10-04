/** Wake registration and request handlers (RFC-0005 P2 worker spec).
 *
 * The worker is a doorbell: it learns only the opaque wakeId, request
 * timestamps, a coarse "a paired computer wants data" signal, and the paired
 * computer's display name. No health data, dates, metric identity, or request
 * contents ever appear here — in storage, logs, or notifications.
 */

import { sendVisiblePush } from "./apns";
import { jsonResponse, onlyFields, readJsonBody } from "./http";
import {
  APNS_TOKEN_RE,
  decideDelivery,
  generateWakeId,
  notificationPayload,
  NONCE_RETENTION_SEC,
  nonceRetentionCutoff,
  parseTimestampSeconds,
  sanitizePeerLabel,
  timestampWithinWindow,
  USER_ID_RE,
  VERIFICATION_HASH_RE,
  verifyWakeHmac,
  WAKE_ID_RE,
  type CounterRow,
} from "./state";

export interface WakeEnv {
  DB: D1Database;
  nowSec?: () => number;
}

export interface ApnsConfig {
  authKey: string;
  keyId: string;
  teamId: string;
  host: string;
  bundleId: string;
}

interface RegistrationRow {
  wake_id: string;
  user_id: string;
  verification_hash: string;
  device_token: string;
  peer_label: string | null;
  created_at: number;
  rotated_at: number;
  registration_version?: number;
}

function rowToCounter(row: unknown): CounterRow | null {
  if (!row || typeof row !== "object") return null;
  const r = row as {
    hour_bucket?: unknown;
    delivered_this_hour?: unknown;
    last_delivered_at?: unknown;
  };
  if (
    typeof r.hour_bucket !== "number"
    || typeof r.delivered_this_hour !== "number"
    || typeof r.last_delivered_at !== "number"
  ) {
    return null;
  }
  return {
    hour_bucket: r.hour_bucket,
    delivered_this_hour: r.delivered_this_hour,
    last_delivered_at: r.last_delivered_at,
  };
}

/** POST /wake/register — phone enrolls (or rotates) a pairing's wake material. */
export async function handleWakeRegister(request: Request, env: WakeEnv): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) return jsonResponse({ error: "Invalid JSON body" }, 400);

  if (!onlyFields(body, ["userId", "deviceToken", "wakeKeyVerificationHash", "peerLabel", "wakeId"])) {
    return jsonResponse({ error: "Invalid fields" }, 400);
  }

  const { userId, deviceToken, wakeKeyVerificationHash, peerLabel } = body as {
    userId?: unknown;
    deviceToken?: unknown;
    wakeKeyVerificationHash?: unknown;
    peerLabel?: unknown;
    wakeId?: unknown;
  };
  const existingWakeId = (body as { wakeId?: unknown }).wakeId;

  if (typeof userId !== "string" || !USER_ID_RE.test(userId)) {
    return jsonResponse({ error: "Invalid userId" }, 400);
  }
  if (typeof deviceToken !== "string" || !APNS_TOKEN_RE.test(deviceToken)) {
    return jsonResponse({ error: "Invalid deviceToken" }, 400);
  }
  if (
    typeof wakeKeyVerificationHash !== "string"
    || !VERIFICATION_HASH_RE.test(wakeKeyVerificationHash)
  ) {
    return jsonResponse({ error: "Invalid wakeKeyVerificationHash" }, 400);
  }
  const label = sanitizePeerLabel(peerLabel);
  if (peerLabel !== undefined && peerLabel !== null && label === null) {
    return jsonResponse({ error: "Invalid peerLabel" }, 400);
  }

  const nowSec = env.nowSec?.() ?? Math.floor(Date.now() / 1000);

  // Rotation: an explicit wakeId owned by the same install replaces its
  // verification hash and token. Unknown or foreign ids never create rows.
  if (existingWakeId !== undefined) {
    if (typeof existingWakeId !== "string" || !WAKE_ID_RE.test(existingWakeId)) {
      return jsonResponse({ error: "Invalid wakeId" }, 400);
    }
    const existing = await env.DB.prepare(
      "SELECT * FROM wake_registrations WHERE wake_id = ?",
    ).bind(existingWakeId).first<RegistrationRow>();
    if (!existing || existing.user_id !== userId || existing.registration_version === 2) {
      return jsonResponse({ error: "wake_unknown" }, 404);
    }
    await env.DB.prepare(
      `UPDATE wake_registrations
         SET verification_hash = ?, device_token = ?, peer_label = ?, rotated_at = ?
       WHERE wake_id = ?`,
    ).bind(wakeKeyVerificationHash, deviceToken, label, nowSec, existingWakeId).run();
    return jsonResponse({ wakeId: existingWakeId });
  }

  const wakeId = generateWakeId();
  await env.DB.prepare(
    `INSERT INTO wake_registrations
       (wake_id, user_id, verification_hash, device_token, peer_label, created_at, rotated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(wakeId, userId, wakeKeyVerificationHash, deviceToken, label, nowSec, nowSec).run();
  return jsonResponse({ wakeId });
}

/** DELETE /wake/register — unpairing revokes the row; idempotent by design. */
export async function handleWakeUnregister(request: Request, env: WakeEnv): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) return jsonResponse({ error: "Invalid JSON body" }, 400);

  if (!onlyFields(body, ["userId", "wakeId"])) return jsonResponse({ error: "Invalid fields" }, 400);
  const { userId, wakeId } = body as { userId?: unknown; wakeId?: unknown };
  if (typeof userId !== "string" || !USER_ID_RE.test(userId)) {
    return jsonResponse({ error: "Invalid userId" }, 400);
  }
  if (typeof wakeId !== "string" || !WAKE_ID_RE.test(wakeId)) {
    return jsonResponse({ error: "Invalid wakeId" }, 400);
  }

  const existing = await env.DB.prepare("SELECT * FROM wake_registrations WHERE wake_id = ?")
    .bind(wakeId).first<RegistrationRow>();
  // V1 stays idempotent, but cannot erase v2 rows or reset their delivery policy.
  if (existing?.registration_version === 2) return jsonResponse({ ok: true });

  await env.DB.prepare("DELETE FROM wake_registrations WHERE wake_id = ? AND user_id = ?")
    .bind(wakeId, userId).run();
  await env.DB.prepare("DELETE FROM wake_counters WHERE wake_id = ?").bind(wakeId).run();
  await env.DB.prepare("DELETE FROM wake_nonces WHERE wake_id = ?").bind(wakeId).run();
  return jsonResponse({ ok: true });
}

/** POST /wake/request — the CLI's authenticated doorbell ring. */
export async function handleWakeRequest(
  request: Request,
  env: WakeEnv,
  apns: ApnsConfig | null,
): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) return jsonResponse({ error: "Invalid JSON body" }, 400);

  if (!onlyFields(body, ["wakeId", "nonce", "timestamp", "hmac", "peerLabel"])) {
    return jsonResponse({ error: "Invalid fields" }, 400);
  }

  const { wakeId, nonce, timestamp, hmac, peerLabel } = body as {
    wakeId?: unknown;
    nonce?: unknown;
    timestamp?: unknown;
    hmac?: unknown;
    peerLabel?: unknown;
  };

  if (typeof wakeId !== "string" || !WAKE_ID_RE.test(wakeId)) {
    return jsonResponse({ error: "Invalid wakeId" }, 400);
  }
  if (typeof nonce !== "string" || !/^[0-9a-f]{32,128}$/.test(nonce)) {
    return jsonResponse({ error: "Invalid nonce" }, 400);
  }
  const timestampSec = parseTimestampSeconds(timestamp);
  if (timestampSec === null) {
    return jsonResponse({ error: "Invalid timestamp" }, 400);
  }
  if (typeof hmac !== "string" || !/^[0-9a-f]{64}$/.test(hmac)) {
    return jsonResponse({ error: "Invalid hmac" }, 400);
  }
  const label = sanitizePeerLabel(peerLabel);

  const nowSec = env.nowSec?.() ?? Math.floor(Date.now() / 1000);

  // 1. Unknown pairing → 404.
  const registration = await env.DB.prepare(
    "SELECT * FROM wake_registrations WHERE wake_id = ?",
  ).bind(wakeId).first<RegistrationRow>();
  if (!registration || registration.registration_version === 2) {
    return jsonResponse({ error: "wake_unknown" }, 404);
  }

  // 2. HMAC proves possession of the registered hash (it is itself a secret).
  const hmacValid = await verifyWakeHmac(
    registration.verification_hash,
    nonce,
    typeof timestamp === "string" ? timestamp : "",
    hmac,
  );
  if (!hmacValid) {
    return jsonResponse({ error: "wake_hmac_invalid" }, 401);
  }

  // 3. Timestamp freshness.
  if (!timestampWithinWindow(timestampSec, nowSec)) {
    return jsonResponse({ error: "wake_timestamp_stale" }, 401);
  }

  // 4. Replay: a burned nonce never rings twice, regardless of later steps.
  const replayed = await env.DB.prepare(
    "SELECT nonce FROM wake_nonces WHERE nonce = ?",
  ).bind(nonce).first();
  if (replayed) {
    return jsonResponse({ error: "wake_nonce_replayed" }, 401);
  }
  await env.DB.prepare(
    "INSERT INTO wake_nonces (nonce, wake_id, seen_at) VALUES (?, ?, ?)",
  ).bind(nonce, wakeId, nowSec).run();
  await env.DB.prepare("DELETE FROM wake_nonces WHERE seen_at < ?")
    .bind(nonceRetentionCutoff(nowSec, NONCE_RETENTION_SEC)).run();

  // 5–6. Dedupe and hourly budget, scoped per wakeId (never per IP).
  const counterRow = await env.DB.prepare(
    "SELECT hour_bucket, delivered_this_hour, last_delivered_at FROM wake_counters WHERE wake_id = ?",
  ).bind(wakeId).first();
  const decision = decideDelivery(rowToCounter(counterRow), nowSec);
  if (decision.kind === "deduplicated") {
    return jsonResponse({ status: "deduplicated" });
  }
  if (decision.kind === "rate_limited") {
    return jsonResponse(
      { error: "wake_rate_limited", retryAfterSeconds: decision.retryAfterSeconds },
      429,
    );
  }

  // 7. One visible push. Only a delivered wake consumes budget.
  if (!apns) {
    return jsonResponse({ error: "apns_not_configured" }, 503);
  }
  const result = await sendVisiblePush(
    { authKey: apns.authKey, keyId: apns.keyId, teamId: apns.teamId },
    {
      apnsToken: registration.device_token,
      bundleId: apns.bundleId,
      payload: notificationPayload(label),
      expirationSec: nowSec + 300,
      host: apns.host as "api.push.apple.com" | "api.sandbox.push.apple.com",
    },
  );
  if (result.status !== 200) {
    // Honest degradation, without logging raw upstream bodies, reasons, or IDs.
    return jsonResponse({ status: "undeliverable" });
  }

  await env.DB.prepare(
    `INSERT INTO wake_counters (wake_id, hour_bucket, delivered_this_hour, last_delivered_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT(wake_id) DO UPDATE SET
       hour_bucket = excluded.hour_bucket,
       delivered_this_hour = CASE
         WHEN wake_counters.hour_bucket = excluded.hour_bucket
         THEN wake_counters.delivered_this_hour + 1
         ELSE 1
       END,
       last_delivered_at = excluded.last_delivered_at`,
  ).bind(wakeId, decision.hourBucket, nowSec).run();

  return jsonResponse({ status: "delivered" });
}