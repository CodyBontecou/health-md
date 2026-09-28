import { audit, rateLimit } from "./auth";
import { randomToken, sha256Hex } from "./crypto";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { verifyAccountPassword } from "./password";
import type { Env } from "./types";

// The only new dashboard grant is the existing, explicit full_export MCP
// authority. Legacy aggregate credentials remain unchanged; never silently
// upgrade them or accept ingest/session credentials in the reader.
const LABEL = /^[A-Za-z0-9][A-Za-z0-9 _.-]{0,79}$/u;
const ID = /^[a-f0-9-]{36}$/u;

function requireOwnerPilot(env: Env): void {
  if (env.VM_PERSONAL_MVP_NO_BACKUP_ACK !== "I_ACCEPT_PERMANENT_DATA_LOSS" ||
      env.AUTH_MODE !== "password" || env.SYNTHETIC_PREVIEW_ONLY === "1") {
    throw new HttpError(403, "unavailable", "Agent credentials are unavailable in this profile.");
  }
}

export async function listAgentTokens(env: Env, userId: string): Promise<Response> {
  requireOwnerPilot(env);
  const rows = await env.DB.prepare(`SELECT id, label, last_four AS lastFour, created_at AS createdAt,
    expires_at AS expiresAt, revoked_at AS revokedAt, read_scope AS scope
    FROM mcp_read_tokens WHERE user_id = ? ORDER BY created_at DESC LIMIT 100`).bind(userId).all();
  return json({ tokens: rows.results });
}

export async function createAgentToken(request: Request, env: Env, userId: string): Promise<Response> {
  requireOwnerPilot(env);
  assertSameOrigin(request, env);
  const body = await readJson<{ label?: unknown; days?: unknown; password?: unknown;
    consent?: unknown; scope?: unknown }>(request);
  const label = typeof body.label === "string" ? body.label.trim() : "";
  if (!LABEL.test(label) || !Number.isInteger(body.days) || Number(body.days) < 1 ||
      Number(body.days) > 90 || body.scope !== "full_export" || body.consent !== true) {
    throw new HttpError(400, "invalid_request", "Name an agent, choose 1–90 days, and confirm full-export access.");
  }
  if (!await rateLimit(env, `agent-token-create:${userId}`, 10)) {
    throw new HttpError(429, "rate_limited", "Too many credential requests. Try later.");
  }
  if (!await verifyAccountPassword(env, userId, body.password)) {
    throw new HttpError(401, "invalid_credentials", "Password confirmation failed.");
  }
  const count = await env.DB.prepare(`SELECT COUNT(*) AS count FROM mcp_read_tokens
    WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?`)
    .bind(userId, new Date().toISOString()).first<{ count: number }>();
  if ((count?.count ?? 0) >= 10) {
    throw new HttpError(409, "token_limit", "Revoke an agent credential before creating another.");
  }
  const id = crypto.randomUUID();
  const token = `hmd_read_${randomToken()}`;
  const now = new Date().toISOString();
  const expiresAt = new Date(Date.now() + Number(body.days) * 86400000).toISOString();
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO mcp_read_tokens
      (id, user_id, label, token_hash, last_four, created_at, expires_at, read_scope)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'full_export')`)
      .bind(id, userId, label, await sha256Hex(token), token.slice(-4), now, expiresAt),
    env.DB.prepare(`INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
      VALUES (?, ?, 'agent_token.created', ?, ?)`)
      .bind(crypto.randomUUID(), userId, id, now),
  ]);
  return json({ id, token, expiresAt, scope: "full_export" }, { status: 201 });
}

export async function revokeAgentToken(request: Request, env: Env, userId: string, id: string): Promise<Response> {
  requireOwnerPilot(env);
  assertSameOrigin(request, env);
  if (!ID.test(id)) throw new HttpError(404, "not_found", "Agent credential not found.");
  const updated = await env.DB.prepare(`UPDATE mcp_read_tokens SET revoked_at = ?
    WHERE id = ? AND user_id = ? AND revoked_at IS NULL`)
    .bind(new Date().toISOString(), id, userId).run();
  if (!updated.meta.changes) throw new HttpError(404, "not_found", "Agent credential not found.");
  await audit(env, userId, "agent_token.revoked", id);
  return json({ revoked: true });
}
