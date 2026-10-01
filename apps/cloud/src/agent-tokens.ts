import { rateLimit } from "./auth";
import { randomToken, sha256Hex } from "./crypto";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import { verifyAccountPassword } from "./password";
import type { Env } from "./types";

// The only new dashboard grant is the existing, explicit full_export MCP
// authority. Legacy aggregate credentials remain unchanged; never silently
// upgrade them or accept ingest/session credentials in the reader.
const LABEL = /^[A-Za-z0-9][A-Za-z0-9 _.-]{0,79}$/u;
const ID = /^[a-f0-9-]{36}$/u;
interface AgentTokenCommitRow { id: string; userId: string; label: string; tokenHash: string;
  lastFour: string; createdAt: string; expiresAt: string; scope: string; audited: number }

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
  const id = crypto.randomUUID();
  const auditId = crypto.randomUUID();
  const token = `hmd_read_${randomToken()}`;
  const tokenHash = await sha256Hex(token);
  const lastFour = token.slice(-4);
  const now = new Date().toISOString();
  const expiresAt = new Date(Date.now() + Number(body.days) * 86400000).toISOString();
  try {
    await env.DB.batch([
      // The cap check is part of the serialized write transaction; a preflight
      // count would let concurrent owner requests exceed ten active grants.
      env.DB.prepare(`INSERT INTO mcp_read_tokens
        (id, user_id, label, token_hash, last_four, created_at, expires_at, read_scope)
        SELECT ?, ?, ?, ?, ?, ?, ?, 'full_export' WHERE
          EXISTS (SELECT 1 FROM users WHERE id = ? AND status = 'active') AND
          (SELECT COUNT(*) FROM mcp_read_tokens
            WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?) < 10`)
        .bind(id, userId, label, tokenHash, lastFour, now, expiresAt, userId, userId, now),
      env.DB.prepare(`INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
        SELECT ?, ?, 'agent_token.created', ?, ? FROM mcp_read_tokens
        WHERE id = ? AND user_id = ? AND token_hash = ? AND label = ?
          AND last_four = ? AND created_at = ? AND expires_at = ?
          AND read_scope = 'full_export' AND revoked_at IS NULL`)
        .bind(auditId, userId, id, now, id, userId, tokenHash, label, lastFour, now, expiresAt),
    ]);
  } catch {
    // The transaction can commit before its response is lost. Verify below
    // before releasing the one-time plaintext read credential.
  }
  let committed: AgentTokenCommitRow | null;
  try {
    committed = await env.DB.prepare(`SELECT t.id, t.user_id AS userId, t.label,
      t.token_hash AS tokenHash, t.last_four AS lastFour, t.created_at AS createdAt,
      t.expires_at AS expiresAt, t.read_scope AS scope,
      EXISTS(SELECT 1 FROM audit_events a WHERE a.id = ? AND a.user_id = t.user_id
        AND a.event_type = 'agent_token.created' AND a.target_id = t.id
        AND a.occurred_at = t.created_at) AS audited
      FROM mcp_read_tokens t WHERE t.id = ? AND t.user_id = ?`)
      .bind(auditId, id, userId).first<AgentTokenCommitRow>();
  } catch {
    throw new HttpError(503, "agent_token_verification_pending",
      "Agent credential creation verification is temporarily unavailable. Review credentials before retrying.");
  }
  if (committed && (committed.id !== id || committed.userId !== userId || committed.label !== label ||
      committed.tokenHash !== tokenHash || committed.lastFour !== lastFour || committed.createdAt !== now ||
      committed.expiresAt !== expiresAt || committed.scope !== "full_export" || committed.audited !== 1)) {
    throw new HttpError(503, "agent_token_verification_pending",
      "Agent credential creation verification is temporarily unavailable. Review credentials before retrying.");
  }
  if (!committed) {
    let state: { active: number; count: number } | null;
    try {
      state = await env.DB.prepare(`SELECT
        EXISTS(SELECT 1 FROM users WHERE id = ? AND status = 'active') AS active,
        (SELECT COUNT(*) FROM mcp_read_tokens
          WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?) AS count`)
        .bind(userId, userId, now).first<{ active: number; count: number }>();
    } catch {
      throw new HttpError(503, "agent_token_verification_pending",
        "Agent credential creation verification is temporarily unavailable. Review credentials before retrying.");
    }
    if (!state?.active) throw new HttpError(401, "unauthorized", "Sign in to continue.");
    if (Number(state.count) >= 10) {
      throw new HttpError(409, "token_limit", "Revoke an agent credential before creating another.");
    }
    throw new HttpError(503, "agent_token_creation_failed",
      "Agent credential creation is temporarily unavailable.");
  }
  return json({ id, token, expiresAt, scope: "full_export" }, { status: 201 });
}

export async function revokeAgentToken(request: Request, env: Env, userId: string, id: string): Promise<Response> {
  requireOwnerPilot(env);
  assertSameOrigin(request, env);
  if (!ID.test(id)) throw new HttpError(404, "not_found", "Agent credential not found.");
  const now = new Date().toISOString();
  const auditId = crypto.randomUUID();
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE mcp_read_tokens SET revoked_at = ?
        WHERE id = ? AND user_id = ? AND revoked_at IS NULL`).bind(now, id, userId),
      env.DB.prepare(`INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
        SELECT ?, ?, 'agent_token.revoked', ?, ? FROM mcp_read_tokens
        WHERE id = ? AND user_id = ? AND revoked_at = ?`)
        .bind(auditId, userId, id, now, id, userId, now),
    ]);
  } catch {
    // A lost response may hide a committed revocation. Verify below.
  }
  let durable: { revokedAt: string | null; audited: number } | null;
  try {
    durable = await env.DB.prepare(`SELECT t.revoked_at AS revokedAt,
      EXISTS(SELECT 1 FROM audit_events a WHERE a.id = ? AND a.user_id = t.user_id
        AND a.event_type = 'agent_token.revoked' AND a.target_id = t.id
        AND a.occurred_at = t.revoked_at) AS audited
      FROM mcp_read_tokens t WHERE t.id = ? AND t.user_id = ?`)
      .bind(auditId, id, userId).first<{ revokedAt: string | null; audited: number }>();
  } catch {
    throw new HttpError(503, "agent_token_revocation_pending",
      "Agent credential revocation verification is temporarily unavailable. Review credentials before retrying.");
  }
  if (!durable) throw new HttpError(404, "not_found", "Agent credential not found.");
  // An earlier exact retry may already have revoked this owner-bound token. A
  // newly committed revocation also requires its transaction-coupled audit row.
  if (durable.revokedAt && (durable.revokedAt !== now || durable.audited === 1)) {
    return json({ revoked: true });
  }
  throw new HttpError(503, "agent_token_revocation_pending",
    "Agent credential revocation verification is temporarily unavailable. Review credentials before retrying.");
}
