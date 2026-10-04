/** Opt-in notification-only extension. V1 transcripts and rows are not upgraded. */
import { hexDecode } from "./crypto";
import { jsonResponse, onlyFields, readJsonBody } from "./http";
import { HMAC_RE, NONCE_RE, USER_ID_RE, VERIFICATION_HASH_RE, nonceRetentionCutoff, timestampWithinWindow } from "./state";
import type { WakeEnv } from "./wake";

export const MANAGEMENT_DOMAIN = "healthmd.wake.manage.v2";
export const REQUEST_DOMAIN = "healthmd.wake.request.v2";
export const V2_WAKE_ID_RE = /^[0-9a-f]{32}$/;
/** Local opaque-token budget; not a claim about Firebase token length/grammar. */
export const FCM_TOKEN_RE = /^[\x21-\x7e]{1,4096}$/;

interface Enrollment {
  operation: "enroll" | "rotate";
  wakeId: string;
  userId: string;
  transport: "fcm";
  deliveryToken: string;
  wakeKeyVerificationHash: string;
  managementKeyVerificationHash: string;
  nonce: string;
  timestamp: string;
  proof: string;
}

/** V2 deliberately accepts only canonical UTC second timestamps, not Date.parse aliases. */
export function v2Timestamp(value: unknown): number | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value)) return null;
  const millis = Date.parse(value);
  if (!Number.isFinite(millis) || new Date(millis).toISOString() !== value.replace("Z", ".000Z")) return null;
  return millis / 1000;
}

export async function verifyV2Proof(hash: string, message: string, proof: string): Promise<boolean> {
  if (!VERIFICATION_HASH_RE.test(hash) || !HMAC_RE.test(proof)) return false;
  const keyBytes = hexDecode(hash);
  const signature = hexDecode(proof);
  if (!keyBytes || !signature) return false;
  const key = await crypto.subtle.importKey("raw", keyBytes as BufferSource, { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  return crypto.subtle.verify("HMAC", key, signature as BufferSource, new TextEncoder().encode(message));
}

function parseEnrollment(body: Record<string, unknown>): Enrollment | null {
  const { operation, wakeId, userId, transport, deliveryToken, wakeKeyVerificationHash, managementKeyVerificationHash, nonce, timestamp, proof } = body;
  if (
    !onlyFields(body, ["operation", "wakeId", "userId", "transport", "deliveryToken", "wakeKeyVerificationHash", "managementKeyVerificationHash", "nonce", "timestamp", "proof"])
    || (operation !== "enroll" && operation !== "rotate")
    || typeof wakeId !== "string" || !V2_WAKE_ID_RE.test(wakeId)
    || typeof userId !== "string" || !USER_ID_RE.test(userId)
    || transport !== "fcm"
    || typeof deliveryToken !== "string" || !FCM_TOKEN_RE.test(deliveryToken)
    || typeof wakeKeyVerificationHash !== "string" || !VERIFICATION_HASH_RE.test(wakeKeyVerificationHash)
    || typeof managementKeyVerificationHash !== "string" || !VERIFICATION_HASH_RE.test(managementKeyVerificationHash)
    || wakeKeyVerificationHash === managementKeyVerificationHash
    || typeof nonce !== "string" || !NONCE_RE.test(nonce) || nonce.length % 2 !== 0
    || typeof timestamp !== "string" || v2Timestamp(timestamp) === null
    || typeof proof !== "string" || !HMAC_RE.test(proof)
  ) return null;
  return { operation, wakeId, userId, transport, deliveryToken, wakeKeyVerificationHash, managementKeyVerificationHash, nonce, timestamp, proof };
}

export function managementMessage(body: Omit<Enrollment, "proof">): string {
  return JSON.stringify([
    MANAGEMENT_DOMAIN, body.operation, body.wakeId, body.userId, body.transport,
    body.deliveryToken, body.wakeKeyVerificationHash, body.managementKeyVerificationHash,
    body.nonce, body.timestamp,
  ]);
}

interface ManagementRow {
  user_id: string;
  verification_hash: string;
  management_hash: string | null;
  registration_version: number;
  transport: string;
}

async function managementRow(env: WakeEnv, wakeId: string, userId: string): Promise<ManagementRow | null> {
  const row = await env.DB.prepare("SELECT user_id, verification_hash, management_hash, registration_version, transport FROM wake_registrations WHERE wake_id = ?")
    .bind(wakeId).first<ManagementRow>();
  return row && row.user_id === userId && row.registration_version === 2 && row.transport === "fcm" && row.management_hash ? row : null;
}

function burnManagementNonce(env: WakeEnv, wakeId: string, userId: string, hash: string, nonce: string, now: number): D1PreparedStatement[] {
  return [
    env.DB.prepare("DELETE FROM wake_v2_nonces WHERE wake_id = ? AND seen_at < ?").bind(wakeId, nonceRetentionCutoff(now)),
    env.DB.prepare(`INSERT INTO wake_v2_nonces (wake_id, nonce, seen_at)
      SELECT wake_id, ?, ? FROM wake_registrations
      WHERE wake_id = ? AND user_id = ? AND management_hash = ? AND registration_version = 2
      ON CONFLICT(wake_id, nonce) DO NOTHING`).bind(nonce, now, wakeId, userId, hash),
  ];
}

/** Initial creation is self-authenticated, not account/install ownership authentication. */
export async function handleV2Register(request: Request, env: WakeEnv): Promise<Response> {
  const json = await readJsonBody(request);
  if (!json) return jsonResponse({ error: "Invalid JSON body" }, 400);
  const body = parseEnrollment(json);
  if (!body) return jsonResponse({ error: "wake_registration_invalid" }, 400);
  const now = env.nowSec?.() ?? Math.floor(Date.now() / 1000);
  if (!timestampWithinWindow(v2Timestamp(body.timestamp)!, now)) return jsonResponse({ error: "wake_timestamp_stale" }, 401);
  const existing = body.operation === "rotate" ? await managementRow(env, body.wakeId, body.userId) : null;
  if (body.operation === "rotate" && !existing) return jsonResponse({ error: "wake_unknown" }, 404);
  const signingHash = existing?.management_hash ?? body.managementKeyVerificationHash;
  if (!await verifyV2Proof(signingHash, managementMessage(body), body.proof)) {
    return jsonResponse({ error: "wake_proof_invalid" }, 401);
  }
  if (existing && (body.managementKeyVerificationHash === existing.verification_hash
    || body.wakeKeyVerificationHash === existing.management_hash)) {
    return jsonResponse({ error: "wake_registration_invalid" }, 400);
  }
  if (existing) {
    const results = await env.DB.batch([
      ...burnManagementNonce(env, body.wakeId, body.userId, signingHash, body.nonce, now),
      env.DB.prepare(`UPDATE wake_registrations SET verification_hash = ?, device_token = ?, management_hash = ?, rotated_at = ?
        WHERE wake_id = ? AND user_id = ? AND management_hash = ? AND registration_version = 2 AND changes() = 1`)
        .bind(body.wakeKeyVerificationHash, body.deliveryToken, body.managementKeyVerificationHash, now, body.wakeId, body.userId, signingHash),
    ]);
    if (results[1].meta.changes !== 1) return jsonResponse({ error: "wake_nonce_replayed" }, 401);
    if (results[2].meta.changes !== 1) return jsonResponse({ error: "wake_auth_changed" }, 409);
    return jsonResponse({ wakeId: body.wakeId });
  }
  const results = await env.DB.batch([
    env.DB.prepare(`INSERT INTO wake_registrations
      (wake_id, user_id, verification_hash, device_token, peer_label, created_at, rotated_at, transport, registration_version, management_hash)
      SELECT ?, ?, ?, ?, NULL, ?, ?, 'fcm', 2, ?
      WHERE NOT EXISTS (SELECT 1 FROM wake_v2_revocations WHERE wake_id = ?) ON CONFLICT(wake_id) DO NOTHING`)
      .bind(body.wakeId, body.userId, body.wakeKeyVerificationHash, body.deliveryToken, now, now, body.managementKeyVerificationHash, body.wakeId),
    env.DB.prepare(`INSERT INTO wake_v2_nonces (wake_id, nonce, seen_at)
      SELECT ?, ?, ? WHERE changes() = 1`).bind(body.wakeId, body.nonce, now),
  ]);
  if (results[0].meta.changes !== 1) return jsonResponse({ error: "wake_exists" }, 409);
  return jsonResponse({ wakeId: body.wakeId });
}

/** V2 revoke requires management possession; userId alone is never sufficient. */
export async function handleV2Unregister(request: Request, env: WakeEnv): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) return jsonResponse({ error: "Invalid JSON body" }, 400);
  const { wakeId, userId, nonce, timestamp, proof } = body;
  if (
    !onlyFields(body, ["wakeId", "userId", "nonce", "timestamp", "proof"])
    || typeof wakeId !== "string" || !V2_WAKE_ID_RE.test(wakeId)
    || typeof userId !== "string" || !USER_ID_RE.test(userId)
    || typeof nonce !== "string" || !NONCE_RE.test(nonce) || nonce.length % 2 !== 0
    || typeof timestamp !== "string" || v2Timestamp(timestamp) === null
    || typeof proof !== "string" || !HMAC_RE.test(proof)
  ) return jsonResponse({ error: "wake_registration_invalid" }, 400);
  const now = env.nowSec?.() ?? Math.floor(Date.now() / 1000);
  if (!timestampWithinWindow(v2Timestamp(timestamp)!, now)) return jsonResponse({ error: "wake_timestamp_stale" }, 401);
  const existing = await managementRow(env, wakeId, userId);
  if (!existing?.management_hash) return jsonResponse({ error: "wake_unknown" }, 404);
  if (!await verifyV2Proof(existing.management_hash, JSON.stringify([MANAGEMENT_DOMAIN, "revoke", wakeId, userId, nonce, timestamp]), proof)) {
    return jsonResponse({ error: "wake_proof_invalid" }, 401);
  }
  const results = await env.DB.batch([
    ...burnManagementNonce(env, wakeId, userId, existing.management_hash, nonce, now),
    env.DB.prepare("INSERT INTO wake_v2_revocations (wake_id, revoked_at) SELECT ?, ? WHERE changes() = 1").bind(wakeId, now),
    env.DB.prepare("DELETE FROM wake_registrations WHERE wake_id = ? AND user_id = ? AND management_hash = ? AND changes() = 1")
      .bind(wakeId, userId, existing.management_hash),
    env.DB.prepare("DELETE FROM wake_counters WHERE wake_id = ? AND changes() = 1").bind(wakeId),
  ]);
  if (results[1].meta.changes !== 1) return jsonResponse({ error: "wake_nonce_replayed" }, 401);
  // D1's metadata includes the cascaded nonce deletes, not just the parent row.
  if (results[3].meta.changes < 1) return jsonResponse({ error: "wake_auth_changed" }, 409);
  return jsonResponse({ ok: true });
}
