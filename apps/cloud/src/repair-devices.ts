import { audit, rateLimit } from "./auth";
import { keyedLookup, randomToken, sha256Hex } from "./crypto";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { verifyAccountPassword } from "./password";
import type { Env } from "./types";

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
const TOKEN = /^hmd_dev_[A-Za-z0-9_-]{43}$/u;
const CODE = /^\d{8}$/u;
const PAIR_TTL = 10 * 60_000;
const GRANT_TTL = 90 * 86_400_000;

interface DeviceRow {
  id: string; userId: string | null; source: "ios" | "android";
  approvedAt: string | null; revokedAt: string | null;
  pairingExpiresAt: string; grantExpiresAt: string | null;
}

function code8(): string {
  // Rejection sampling prevents modulo bias when mapping 32 random bits.
  const ceiling = Math.floor(2 ** 32 / 100_000_000) * 100_000_000;
  const sample = new Uint32Array(1);
  do { crypto.getRandomValues(sample); } while (sample[0]! >= ceiling);
  return String(sample[0]! % 100_000_000).padStart(8, "0");
}
async function tokenRow(request: Request, env: Env): Promise<DeviceRow> {
  const value = request.headers.get("Authorization") ?? "";
  const token = value.startsWith("Bearer ") ? value.slice(7) : "";
  if (!TOKEN.test(token)) throw new HttpError(401, "unauthorized", "An approved device grant is required.");
  const row = await env.DB.prepare(`SELECT id, user_id AS userId, source,
    approved_at AS approvedAt, revoked_at AS revokedAt,
    pairing_expires_at AS pairingExpiresAt, grant_expires_at AS grantExpiresAt
    FROM repair_devices WHERE token_hash = ?`).bind(await sha256Hex(token)).first<DeviceRow>();
  if (!row || row.revokedAt) throw new HttpError(401, "unauthorized", "An approved device grant is required.");
  return row;
}
export async function requireRepairDevice(request: Request, env: Env): Promise<{
  deviceId: string; userId: string; source: "ios" | "android";
}> {
  const row = await tokenRow(request, env);
  if (!row.userId || !row.approvedAt || !row.grantExpiresAt || row.grantExpiresAt <= new Date().toISOString()) {
    throw new HttpError(401, "unauthorized", "An approved device grant is required.");
  }
  const active = await env.DB.prepare("SELECT 1 AS active FROM users WHERE id = ? AND status = 'active'")
    .bind(row.userId).first<{ active: number }>();
  if (!active) throw new HttpError(401, "unauthorized", "An approved device grant is required.");
  return { deviceId: row.id, userId: row.userId, source: row.source };
}

export async function startRepairDeviceEnrollment(request: Request, env: Env): Promise<Response> {
  if (env.CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED !== "1" ||
      env.SYNTHETIC_PREVIEW_ONLY === "1" ||
      (env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" &&
       env.CLOUD_RUNTIME_APPROVED !== "healthmd-cloud-v1-reviewed")) {
    throw new HttpError(403, "unavailable", "Device enrollment is unavailable on this profile.");
  }
  const origin = request.headers.get("Origin");
  if (origin && origin !== env.PUBLIC_ORIGIN) throw new HttpError(403, "invalid_origin", "Invalid enrollment origin.");
  const input = await readJson<{ source?: unknown }>(request, 512);
  if (input?.source !== "ios" && input?.source !== "android") {
    throw new HttpError(400, "invalid_source", "Choose an iOS or Android device.");
  }
  const address = request.headers.get("CF-Connecting-IP");
  if (!address) throw new HttpError(429, "rate_limited", "Enrollment is temporarily unavailable.");
  const ipHash = await keyedLookup(address, env.IDENTITY_KEY_B64, "repair-enroll-ip-v1");
  if (!await rateLimit(env, `repair-enroll:${ipHash}`, 5) ||
      !await rateLimit(env, "repair-enroll-global", 100)) {
    throw new HttpError(429, "rate_limited", "Enrollment is temporarily unavailable.");
  }
  const pending = await env.DB.prepare(`SELECT COUNT(*) AS count FROM repair_devices WHERE user_id IS NULL
    AND revoked_at IS NULL AND pairing_expires_at > ?`).bind(new Date().toISOString())
    .first<{ count: number }>();
  if ((pending?.count ?? 0) >= 20) throw new HttpError(429, "rate_limited", "Enrollment is temporarily unavailable.");
  const now = new Date().toISOString();
  const expiresAt = new Date(Date.now() + PAIR_TTL).toISOString();
  const id = crypto.randomUUID();
  const token = `hmd_dev_${randomToken(32)}`;
  // Eight decimal digits never cross into a URL, cookie or audit record.
  for (let attempt = 0; attempt < 4; attempt++) {
    const code = code8();
    const codeHash = await keyedLookup(code, env.IDENTITY_KEY_B64, "repair-pair-code-v1");
    try {
      await env.DB.prepare(`INSERT INTO repair_devices
        (id, token_hash, code_hash, source, created_at, pairing_expires_at)
        VALUES (?, ?, ?, ?, ?, ?)`).bind(id, await sha256Hex(token), codeHash,
          input.source, now, expiresAt).run();
      return json({ version: 1, token, code, source: input.source, expiresAt }, { status: 201 });
    } catch {
      // A hash collision is vanishingly rare; bounded retry avoids revealing
      // database internals. No other exception may create an approved grant.
    }
  }
  throw new HttpError(503, "unavailable", "Enrollment is temporarily unavailable.");
}
export async function repairDeviceStatus(request: Request, env: Env): Promise<Response> {
  const row = await tokenRow(request, env);
  const now = new Date().toISOString();
  if (!row.approvedAt) {
    if (row.pairingExpiresAt <= now) throw new HttpError(401, "expired", "Enrollment expired.");
    return json({ version: 1, status: "pending", source: row.source });
  }
  if (!row.userId || !row.grantExpiresAt || row.grantExpiresAt <= now) {
    throw new HttpError(401, "expired", "Device grant expired.");
  }
  await requireRepairDevice(request, env);
  return json({ version: 1, status: "approved", source: row.source, expiresAt: row.grantExpiresAt });
}
export async function approveRepairDevice(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<{ code?: unknown; password?: unknown }>(request, 2048);
  if (typeof input?.code !== "string" || !CODE.test(input.code) ||
      !await verifyAccountPassword(env, userId, input.password)) {
    throw new HttpError(401, "invalid_approval", "Invalid enrollment code or account password.");
  }
  const existing = await env.DB.prepare(`SELECT COUNT(*) AS count FROM repair_devices
    WHERE user_id = ? AND revoked_at IS NULL AND grant_expires_at > ?`)
    .bind(userId, new Date().toISOString()).first<{ count: number }>();
  if ((existing?.count ?? 0) >= 4) throw new HttpError(409, "device_limit", "Revoke an old device first.");
  const codeHash = await keyedLookup(input.code, env.IDENTITY_KEY_B64, "repair-pair-code-v1");
  const now = new Date().toISOString();
  const expiresAt = new Date(Date.now() + GRANT_TTL).toISOString();
  const device = await env.DB.prepare(`SELECT id, source FROM repair_devices WHERE code_hash = ?
    AND user_id IS NULL AND approved_at IS NULL AND revoked_at IS NULL AND pairing_expires_at > ?`)
    .bind(codeHash, now).first<Pick<DeviceRow, "id" | "source">>();
  if (!device) throw new HttpError(401, "invalid_approval", "Invalid enrollment code or account password.");
  const changed = await env.DB.prepare(`UPDATE repair_devices SET user_id = ?, approved_at = ?,
    grant_expires_at = ?, code_hash = NULL WHERE id = ? AND code_hash = ? AND user_id IS NULL
    AND pairing_expires_at > ? AND revoked_at IS NULL`)
    .bind(userId, now, expiresAt, device.id, codeHash, now).run();
  if (!changed.meta.changes) throw new HttpError(409, "already_claimed", "Enrollment was already used.");
  await audit(env, userId, "repair_device.approved", device.id);
  return json({ deviceId: device.id, source: device.source, expiresAt, approved: true });
}
export async function listRepairDevices(env: Env, userId: string): Promise<Response> {
  const { results } = await env.DB.prepare(`SELECT id, source, created_at AS createdAt,
    approved_at AS approvedAt, grant_expires_at AS expiresAt, last_used_at AS lastUsedAt
    FROM repair_devices WHERE user_id = ? AND revoked_at IS NULL AND grant_expires_at > ?
    ORDER BY approved_at DESC LIMIT 4`).bind(userId, new Date().toISOString()).all();
  return json({ devices: results });
}
export async function revokeRepairDevice(request: Request, env: Env, userId: string, id: string): Promise<Response> {
  assertSameOrigin(request, env);
  if (!UUID.test(id)) throw new HttpError(404, "not_found", "Device not found.");
  const now = new Date().toISOString();
  const result = await env.DB.prepare(`UPDATE repair_devices SET revoked_at = ?
    WHERE id = ? AND user_id = ? AND revoked_at IS NULL`).bind(now, id, userId).run();
  if (!result.meta.changes) throw new HttpError(404, "not_found", "Device not found.");
  await env.DB.prepare(`UPDATE repair_dispatches SET state = 'cancelled'
    WHERE device_id = ? AND user_id = ? AND state IN ('queued', 'claimed')`).bind(id, userId).run();
  await audit(env, userId, "repair_device.revoked", id);
  return json({ revoked: true });
}
export async function purgeExpiredRepairDevices(env: Env): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(`DELETE FROM repair_devices WHERE
    (user_id IS NULL AND pairing_expires_at <= ?) OR
    (user_id IS NOT NULL AND grant_expires_at <= ?)`).bind(now, now).run();
}
