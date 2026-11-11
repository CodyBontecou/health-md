/** Pure wake-request validation, HMAC verification, and delivery policy.
 *
 * Everything here is side-effect free so the policy (RFC-0005 worker spec:
 * ±120 s timestamp window, 30 s dedupe, 6 delivered/hour, per-wakeId scoping)
 * is unit-testable without D1 or APNs.
 */

import { constantTimeEqual, hexDecode, hmacSha256 } from "./crypto";

export const WAKE_HMAC_DOMAIN = "healthmd.wake.v1";
export const TIMESTAMP_WINDOW_SEC = 120;
export const DEDUPE_WINDOW_SEC = 30;
export const HOURLY_DELIVERY_LIMIT = 6;
/** Nonce retention; comfortably larger than the timestamp verification window. */
export const NONCE_RETENTION_SEC = 300;

/** Nonces older than this cutoff are prunable. */
export function nonceRetentionCutoff(nowSec: number, retentionSec: number = NONCE_RETENTION_SEC): number {
  return nowSec - retentionSec;
}

export const USER_ID_RE = /^[A-Za-z0-9_-]{16,64}$/;
export const WAKE_ID_RE = /^[A-Za-z0-9_-]{8,128}$/;
export const APNS_TOKEN_RE = /^[A-Fa-f0-9]{32,200}$/;
/** FCM registration token: opaque, URL-safe with ':' separators. */
export const FCM_TOKEN_RE = /^[A-Za-z0-9_:.-]{32,4096}$/;
/** SHA-256 verification hash: exactly 64 lowercase hex chars. */
export const VERIFICATION_HASH_RE = /^[0-9a-f]{64}$/;
/** Request HMAC: exactly 64 lowercase hex chars. */
export const HMAC_RE = /^[0-9a-f]{64}$/;
/** Nonce: ≥128 bits, lowercase hex. */
export const NONCE_RE = /^[0-9a-f]{32,128}$/;

export const FALLBACK_NOTIFICATION_BODY = "Your CLI is waiting. Open Health.md to continue.";
export const NOTIFICATION_TITLE = "Health.md";
export const NOTIFICATION_CATEGORY = "HEALTHMD_DIRECT_WAKE";
export const PEER_LABEL_MAX_BYTES = 128;

export interface CounterRow {
  hour_bucket: number;
  delivered_this_hour: number;
  last_delivered_at: number;
}

export type DeliveryDecision =
  | { kind: "deduplicated" }
  | { kind: "rate_limited"; retryAfterSeconds: number }
  | { kind: "deliver"; deliveredThisHour: number; hourBucket: number };

export function hourBucketOf(nowSec: number): number {
  return Math.floor(nowSec / 3600);
}

export function decideDelivery(counter: CounterRow | null, nowSec: number): DeliveryDecision {
  if (counter && nowSec - counter.last_delivered_at < DEDUPE_WINDOW_SEC) {
    return { kind: "deduplicated" };
  }
  const bucket = hourBucketOf(nowSec);
  const deliveredThisHour =
    counter && counter.hour_bucket === bucket ? counter.delivered_this_hour : 0;
  if (deliveredThisHour >= HOURLY_DELIVERY_LIMIT) {
    const nextHourStart = (bucket + 1) * 3600;
    return { kind: "rate_limited", retryAfterSeconds: Math.max(1, nextHourStart - nowSec) };
  }
  return { kind: "deliver", deliveredThisHour, hourBucket: bucket };
}

/** Parse an RFC 3339 timestamp to unix seconds, or `null` when unparseable. */
export function parseTimestampSeconds(value: unknown): number | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 40) return null;
  const millis = Date.parse(value);
  if (Number.isNaN(millis)) return null;
  return Math.floor(millis / 1000);
}

export function timestampWithinWindow(timestampSec: number, nowSec: number): boolean {
  return Math.abs(nowSec - timestampSec) <= TIMESTAMP_WINDOW_SEC;
}

/**
 * Verify the CLI's domain-separated wake HMAC.
 *
 * The key is the SHA-256 of the raw 32-byte wake key — exactly the verification
 * hash the phone registered — so the worker never holds the raw key. Message
 * bytes are the domain label, the nonce hex string, and the timestamp string,
 * concatenated as ASCII (pinned cross-language in the Rust and worker tests).
 */
export async function verifyWakeHmac(
  verificationHashHex: string,
  nonceHex: string,
  timestamp: string,
  providedHmacHex: string,
): Promise<boolean> {
  if (!VERIFICATION_HASH_RE.test(verificationHashHex)) return false;
  if (!HMAC_RE.test(providedHmacHex)) return false;
  const key = hexDecode(verificationHashHex);
  const provided = hexDecode(providedHmacHex);
  if (!key || !provided) return false;
  const message = new TextEncoder().encode(WAKE_HMAC_DOMAIN + nonceHex + timestamp);
  const expected = await hmacSha256(key, message);
  return constantTimeEqual(expected, provided);
}

/** Strip control characters, trim, and enforce the ≤128-byte label budget. */
export function sanitizePeerLabel(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return null;
  // eslint-disable-next-line no-control-regex
  const cleaned = value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").trim();
  if (cleaned.length === 0) return null;
  if (new TextEncoder().encode(cleaned).byteLength > PEER_LABEL_MAX_BYTES) return null;
  return cleaned;
}

export function notificationBody(peerLabel: string | null): string {
  return peerLabel ? `Your CLI is waiting. Open Health.md to continue on ${peerLabel}.` : FALLBACK_NOTIFICATION_BODY;
}

export function notificationPayload(peerLabel: string | null): Record<string, unknown> {
  return {
    aps: {
      alert: { title: NOTIFICATION_TITLE, body: notificationBody(peerLabel) },
      sound: "default",
      category: NOTIFICATION_CATEGORY,
    },
    healthmd: { kind: "direct-cli-wake" },
  };
}

/**
 * Push transport and doorbell purpose of one registration.
 *
 * `delegated-sync` doorbells are held by a third party the phone delivered the
 * key to (for example a sponsoring clinic's server). The worker deliberately
 * learns nothing about that holder: no name, endpoint, or membership. Copy is
 * a fixed localized string resolved on the phone, so the holder can never put
 * text in front of the patient.
 */
export type WakePlatform = "apns" | "fcm";
export type WakePurpose = "direct-cli" | "delegated-sync";

export const SYNC_REQUEST_CATEGORY = "HEALTHMD_SYNC_REQUEST";
export const SYNC_REQUEST_TITLE_LOC_KEY = "HEALTHMD_SYNC_REQUEST_TITLE";
export const SYNC_REQUEST_BODY_LOC_KEY = "HEALTHMD_SYNC_REQUEST_BODY";
export const SYNC_REQUEST_KIND = "delegated-sync-request";

export type RegistrationTarget =
  | { ok: true; platform: WakePlatform; purpose: WakePurpose }
  | { ok: false; error: string };

/** Validate the transport/purpose pair and the device token's shape for it. */
export function parseRegistrationTarget(
  platform: unknown,
  purpose: unknown,
  deviceToken: unknown,
): RegistrationTarget {
  const resolvedPlatform = platform === undefined ? "apns" : platform;
  const resolvedPurpose = purpose === undefined ? "direct-cli" : purpose;
  if (resolvedPlatform !== "apns" && resolvedPlatform !== "fcm") {
    return { ok: false, error: "Invalid platform" };
  }
  if (resolvedPurpose !== "direct-cli" && resolvedPurpose !== "delegated-sync") {
    return { ok: false, error: "Invalid purpose" };
  }
  // Android Direct CLI wake is RFC-0005 P3 and remains planned.
  if (resolvedPlatform === "fcm" && resolvedPurpose === "direct-cli") {
    return { ok: false, error: "Unsupported purpose for platform" };
  }
  const tokenRe = resolvedPlatform === "apns" ? APNS_TOKEN_RE : FCM_TOKEN_RE;
  if (typeof deviceToken !== "string" || !tokenRe.test(deviceToken)) {
    return { ok: false, error: "Invalid deviceToken" };
  }
  return { ok: true, platform: resolvedPlatform, purpose: resolvedPurpose };
}

/** Visible APNs alert for a delegated sync request; copy is localized on device. */
export function syncRequestApnsPayload(wakeId: string): Record<string, unknown> {
  return {
    aps: {
      alert: {
        "title-loc-key": SYNC_REQUEST_TITLE_LOC_KEY,
        "loc-key": SYNC_REQUEST_BODY_LOC_KEY,
      },
      sound: "default",
      category: SYNC_REQUEST_CATEGORY,
    },
    healthmd: { kind: SYNC_REQUEST_KIND, wakeId },
  };
}

/**
 * FCM data message for a delegated sync request. The app always posts the
 * visible notification itself (localized copy, tap intent), so high priority
 * is never spent on an invisible wake.
 */
export function syncRequestFcmData(wakeId: string): Record<string, string> {
  return { kind: SYNC_REQUEST_KIND, wakeId };
}

/** Generate an opaque, unguessable wake id (128 bits, hex). */
export function generateWakeId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
