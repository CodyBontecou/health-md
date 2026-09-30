import { audit } from "./auth";
import { HttpError, assertSameOrigin, json, readJson } from "./http";
import { activeRepairDraft } from "./repair-drafts";
import { requireRepairDevice } from "./repair-devices";
import type { Env } from "./types";

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/u;
const DISPATCH_TTL_MS = 15 * 60_000;
interface DispatchRow {
  id: string; userId: string; draftId: string; deviceId: string;
  source: "ios" | "android"; state: string; createdAt: string;
  expiresAt: string; claimedAt: string | null;
}
interface DevicePrincipal { deviceId: string; userId: string; source: "ios" | "android" }

function ensureDispatchAvailable(env: Env): void {
  // Explicitly off on existing live services and on the upload-disabled preview.
  // This is review-only delivery, NOT permission to upload or launch a phone job.
  if (env.CLOUD_REPAIR_DISPATCH_ENABLED !== "1" ||
      env.CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED !== "1" || env.SYNTHETIC_PREVIEW_ONLY === "1" ||
      (env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" &&
       env.CLOUD_RUNTIME_APPROVED !== "healthmd-cloud-v1-reviewed")) {
    throw new HttpError(403, "dispatch_disabled", "Device-bound requests are not available on this profile.");
  }
}
function checkDeviceOrigin(request: Request, env: Env): void {
  const origin = request.headers.get("Origin");
  if (origin && origin !== env.PUBLIC_ORIGIN) {
    throw new HttpError(403, "invalid_origin", "Invalid device request origin.");
  }
}
function exactInput(value: unknown, fields: string[]): void {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).length !== fields.length ||
      Object.keys(value).some((key) => !fields.includes(key))) {
    throw new HttpError(400, "invalid_request", "Unexpected request fields.");
  }
}
function idInput(value: unknown, name: string): string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new HttpError(400, "invalid_request", `Invalid ${name}.`);
  }
  return value;
}

// The owner session authorizes delivery of an existing encrypted draft to one
// already approved device. Recheck all constraints in the INSERT transaction;
// a stale preflight read is never authorization by itself.
export async function queueRepairDispatch(request: Request, env: Env, userId: string): Promise<Response> {
  ensureDispatchAvailable(env);
  assertSameOrigin(request, env);
  const input = await readJson<{ draftId?: unknown; deviceId?: unknown }>(request, 512);
  exactInput(input, ["draftId", "deviceId"]);
  const draftId = idInput(input.draftId, "draft");
  const deviceId = idInput(input?.deviceId, "device");
  const draft = await activeRepairDraft(env, userId, draftId);
  if (!draft) throw new HttpError(404, "not_found", "Draft not available.");
  const device = await env.DB.prepare(`SELECT source, grant_expires_at AS grantExpiresAt
    FROM repair_devices WHERE id = ? AND user_id = ? AND approved_at IS NOT NULL
    AND revoked_at IS NULL AND grant_expires_at > ?`).bind(deviceId, userId, new Date().toISOString())
    .first<{ source: string; grantExpiresAt: string }>();
  if (!device || device.source !== draft.spec.source) {
    throw new HttpError(409, "device_mismatch", "Choose an approved phone with the draft's source.");
  }
  const now = new Date().toISOString();
  const expiresAt = new Date(Math.min(Date.now() + DISPATCH_TTL_MS,
    Date.parse(draft.expiresAt), Date.parse(device.grantExpiresAt))).toISOString();
  if (expiresAt <= new Date(Date.now() + 30_000).toISOString()) {
    throw new HttpError(409, "request_expiring", "Refresh the draft or device approval before queueing.");
  }
  const id = crypto.randomUUID();
  let changed: number;
  try {
    const inserted = await env.DB.prepare(`INSERT INTO repair_dispatches
      (id, user_id, draft_id, device_id, state, created_at, expires_at)
      SELECT ?, d.user_id, d.id, v.id, 'queued', ?, ? FROM repair_drafts d
      JOIN users u ON u.id = d.user_id AND u.status = 'active'
      JOIN repair_devices v ON v.id = ? AND v.user_id = d.user_id AND v.source = d.source
      WHERE d.id = ? AND d.user_id = ? AND d.state = 'draft'
        AND d.expires_at >= ? AND v.approved_at IS NOT NULL
        AND v.revoked_at IS NULL AND v.grant_expires_at >= ?
        AND NOT EXISTS (SELECT 1 FROM repair_dispatches x WHERE x.draft_id = d.id)
        AND NOT EXISTS (SELECT 1 FROM repair_dispatches x WHERE x.device_id = v.id
          AND x.user_id = d.user_id AND x.state IN ('queued', 'claimed') AND x.expires_at > ?)`)
      .bind(id, now, expiresAt, deviceId, draftId, userId, expiresAt, expiresAt, now).run();
    changed = inserted.meta.changes;
  } catch {
    // Unique draft binding also rejects simultaneous owner submissions.
    throw new HttpError(409, "dispatch_conflict", "Draft or device already has a request.");
  }
  if (changed !== 1) throw new HttpError(409, "dispatch_conflict", "Draft or device is no longer available.");
  await audit(env, userId, "repair_dispatch.queued", id);
  return json({ version: 1, id, deviceId, state: "queued", expiresAt,
    uploadMode: "supplemental_only", launchable: false }, { status: 201 });
}

export async function listRepairDispatches(env: Env, userId: string): Promise<Response> {
  const now = new Date().toISOString();
  const { results } = await env.DB.prepare(`SELECT x.id, x.draft_id AS draftId,
    x.device_id AS deviceId, d.source, x.state, x.created_at AS createdAt,
    x.expires_at AS expiresAt, x.claimed_at AS claimedAt,
    d.state AS draftState, d.expires_at AS draftExpiresAt, v.revoked_at AS revokedAt
    FROM repair_dispatches x JOIN repair_drafts d ON d.id = x.draft_id AND d.user_id = x.user_id
    JOIN repair_devices v ON v.id = x.device_id AND v.user_id = x.user_id
    WHERE x.user_id = ? ORDER BY x.created_at DESC, x.id DESC LIMIT 20`)
    .bind(userId).all<DispatchRow & { draftState: string; draftExpiresAt: string; revokedAt: string | null }>();
  return json({ version: 1, requests: results.map((row) => ({ id: row.id, draftId: row.draftId,
    deviceId: row.deviceId, source: row.source,
    state: row.state === "confirmed" ? "unverified" :
      row.state === "queued" || row.state === "claimed" ?
        row.revokedAt || row.draftState !== "draft" ? "cancelled" :
          row.expiresAt <= now || row.draftExpiresAt <= now ? "expired" : row.state : row.state,
    createdAt: row.createdAt, expiresAt: row.expiresAt, claimedAt: row.claimedAt,
    uploadEnabled: false })) });
}

export async function cancelRepairDispatch(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<{ id?: unknown }>(request, 256);
  exactInput(input, ["id"]);
  const id = idInput(input.id, "request");
  const result = await env.DB.prepare(`UPDATE repair_dispatches SET state = 'cancelled'
    WHERE id = ? AND user_id = ? AND state IN ('queued', 'claimed')`)
    .bind(id, userId).run();
  if (result.meta.changes !== 1) throw new HttpError(404, "not_found", "Active request not found.");
  await audit(env, userId, "repair_dispatch.cancelled", id);
  return json({ cancelled: true });
}

async function readActiveClaim(env: Env, principal: DevicePrincipal, id: string): Promise<Response> {
  const now = new Date().toISOString();
  const query = `SELECT x.id, x.user_id AS userId, x.draft_id AS draftId, x.device_id AS deviceId,
    d.source, x.state, x.created_at AS createdAt, x.expires_at AS expiresAt,
    x.claimed_at AS claimedAt FROM repair_dispatches x
    JOIN repair_drafts d ON d.id = x.draft_id AND d.user_id = x.user_id
    JOIN repair_devices v ON v.id = x.device_id AND v.user_id = x.user_id AND v.source = d.source
    JOIN users u ON u.id = x.user_id AND u.status = 'active'
    WHERE x.id = ? AND x.user_id = ? AND x.device_id = ? AND x.state = 'claimed'
      AND x.expires_at > ? AND d.state = 'draft' AND d.expires_at > ?
      AND v.approved_at IS NOT NULL AND v.revoked_at IS NULL AND v.grant_expires_at > ?`;
  const row = await env.DB.prepare(query).bind(id, principal.userId, principal.deviceId, now, now, now)
    .first<DispatchRow>();
  if (!row || row.source !== principal.source) {
    throw new HttpError(409, "request_unavailable", "No active request for this phone.");
  }
  const draft = await activeRepairDraft(env, principal.userId, row.draftId);
  if (!draft || draft.spec.source !== principal.source) {
    throw new HttpError(409, "request_unavailable", "No active request for this phone.");
  }
  // Cancellation or revocation during authenticated scope decryption must not
  // leave a stale pending response. Later cancellation cannot retract bytes
  // already delivered; the native review must recheck before acting.
  const stillActive = await env.DB.prepare(`SELECT 1 AS active FROM repair_dispatches x
    JOIN repair_devices v ON v.id = x.device_id AND v.user_id = x.user_id
    JOIN repair_drafts d ON d.id = x.draft_id AND d.user_id = x.user_id
    WHERE x.id = ? AND x.user_id = ? AND x.device_id = ? AND x.state = 'claimed'
      AND x.expires_at > ? AND v.revoked_at IS NULL AND v.grant_expires_at > ?
      AND d.state = 'draft' AND d.expires_at > ?`)
    .bind(id, principal.userId, principal.deviceId, new Date().toISOString(),
      new Date().toISOString(), new Date().toISOString()).first<{ active: number }>();
  if (!stillActive) throw new HttpError(409, "request_unavailable", "No active request for this phone.");
  return json({ version: 1, request: { id: row.id, source: row.source, spec: draft.spec,
    state: "claimed", expiresAt: row.expiresAt, uploadMode: "supplemental_only",
    uploadEnabled: false, launchable: false },
    note: "Review-only staged request. No receiver receipt, upload authority, or export command is available." });
}

async function claimedId(env: Env, principal: DevicePrincipal): Promise<string | null> {
  const now = new Date().toISOString();
  const row = await env.DB.prepare(`SELECT x.id FROM repair_dispatches x
    JOIN repair_drafts d ON d.id = x.draft_id AND d.user_id = x.user_id
    WHERE x.user_id = ? AND x.device_id = ? AND x.state = 'claimed'
      AND x.expires_at > ? AND d.state = 'draft' AND d.expires_at > ?
    ORDER BY x.claimed_at ASC, x.id ASC LIMIT 1`)
    .bind(principal.userId, principal.deviceId, now, now).first<{ id: string }>();
  return row?.id ?? null;
}

export async function claimRepairDispatch(request: Request, env: Env): Promise<Response> {
  ensureDispatchAvailable(env);
  checkDeviceOrigin(request, env);
  const principal = await requireRepairDevice(request, env);
  const alreadyClaimed = await claimedId(env, principal);
  if (alreadyClaimed) return readActiveClaim(env, principal, alreadyClaimed);
  const now = new Date().toISOString();
  const next = await env.DB.prepare(`SELECT x.id FROM repair_dispatches x
    JOIN repair_drafts d ON d.id = x.draft_id AND d.user_id = x.user_id
    WHERE x.user_id = ? AND x.device_id = ? AND x.state = 'queued'
      AND x.expires_at > ? AND d.state = 'draft' AND d.expires_at > ?
      AND d.source = ? ORDER BY x.created_at ASC, x.id ASC LIMIT 1`)
    .bind(principal.userId, principal.deviceId, now, now, principal.source).first<{ id: string }>();
  if (!next) return json({ version: 1, request: null });
  const updated = await env.DB.prepare(`UPDATE repair_dispatches SET state = 'claimed', claimed_at = ?
    WHERE id = ? AND user_id = ? AND device_id = ? AND state = 'queued' AND expires_at > ?
      AND EXISTS (SELECT 1 FROM repair_drafts d WHERE d.id = draft_id AND d.user_id = ?
        AND d.state = 'draft' AND d.expires_at > ? AND d.source = ?)
      AND EXISTS (SELECT 1 FROM repair_devices v WHERE v.id = device_id AND v.user_id = ?
        AND v.approved_at IS NOT NULL AND v.revoked_at IS NULL AND v.grant_expires_at > ?)`)
    .bind(now, next.id, principal.userId, principal.deviceId, now,
      principal.userId, now, principal.source, principal.userId, now).run();
  if (updated.meta.changes !== 1) throw new HttpError(409, "claim_conflict", "Request was claimed, cancelled or expired.");
  await audit(env, principal.userId, "repair_dispatch.claimed", next.id);
  return readActiveClaim(env, principal, next.id);
}
export async function resumeRepairDispatch(request: Request, env: Env): Promise<Response> {
  ensureDispatchAvailable(env);
  checkDeviceOrigin(request, env);
  const principal = await requireRepairDevice(request, env);
  const id = await claimedId(env, principal);
  return id ? readActiveClaim(env, principal, id) : json({ version: 1, request: null });
}
export async function declineRepairDispatch(request: Request, env: Env): Promise<Response> {
  checkDeviceOrigin(request, env);
  const principal = await requireRepairDevice(request, env);
  const input = await readJson<{ id?: unknown }>(request, 256);
  exactInput(input, ["id"]);
  const id = idInput(input.id, "request");
  const now = new Date().toISOString();
  const result = await env.DB.prepare(`UPDATE repair_dispatches SET state = 'cancelled'
    WHERE id = ? AND user_id = ? AND device_id = ? AND state = 'claimed' AND expires_at > ?`)
    .bind(id, principal.userId, principal.deviceId, now).run();
  if (result.meta.changes !== 1) throw new HttpError(404, "not_found", "Active request not found.");
  await audit(env, principal.userId, "repair_dispatch.declined", id);
  return json({ declined: true });
}
