import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { ReadPrincipal } from "./reader";

const TOKEN_PATTERN = /^Bearer (hmd_read_[A-Za-z0-9_-]{43})$/u;
const LABEL_PATTERN = /^[A-Za-z0-9][A-Za-z0-9 _.-]{0,79}$/u;
const UUID_PATTERN = /^[a-f0-9-]{36}$/u;
export type ReadScope = "aggregates" | "full_export";

export function tokenDigest(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

// This DB connection must be created with { readOnly: true } in the MCP
// process. Do not import write-side account, session or ingestion auth.
export function authenticateReadToken(db: DatabaseSync, authorization: string | null): ReadPrincipal | null {
  const token = TOKEN_PATTERN.exec(authorization ?? "")?.[1];
  if (!token) return null;
  return (db.prepare(`SELECT t.user_id AS userId, t.id AS tokenId, t.read_scope AS scope
    FROM mcp_read_tokens t JOIN users u ON u.id = t.user_id
    WHERE t.token_hash = ? AND t.revoked_at IS NULL AND t.expires_at > ?
      AND u.status = 'active'`).get(tokenDigest(token), new Date().toISOString()) as ReadPrincipal | undefined) ?? null;
}

// Offline operator CLI only. Raw credentials are shown once and never stored.
export function createReadToken(db: DatabaseSync, userId: string, label: string, days = 90,
  scope: ReadScope = "aggregates"): {
  id: string; token: string; expiresAt: string;
} {
  if (!UUID_PATTERN.test(userId) || !LABEL_PATTERN.test(label) ||
      !Number.isInteger(days) || days < 1 || days > 365 ||
      (scope !== "aggregates" && scope !== "full_export")) throw new Error("Invalid read-token parameters");
  const active = db.prepare("SELECT 1 FROM users WHERE id = ? AND status = 'active'").get(userId);
  if (!active) throw new Error("Active account not found");
  const id = randomUUID();
  const token = `hmd_read_${Buffer.from(randomBytes(32)).toString("base64url")}`;
  const expiresAt = new Date(Date.now() + days * 86400000).toISOString();
  db.prepare(`INSERT INTO mcp_read_tokens
    (id, user_id, label, token_hash, last_four, created_at, expires_at, read_scope)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(id, userId, label, tokenDigest(token),
    token.slice(-4), new Date().toISOString(), expiresAt, scope);
  return { id, token, expiresAt };
}

export function revokeReadToken(db: DatabaseSync, id: string): boolean {
  if (!UUID_PATTERN.test(id)) throw new Error("Invalid read-token identifier");
  return Number(db.prepare(`UPDATE mcp_read_tokens SET revoked_at = ?
    WHERE id = ? AND revoked_at IS NULL`).run(new Date().toISOString(), id).changes) === 1;
}

export function listReadTokens(db: DatabaseSync, userId: string): Array<{
  id: string; label: string; lastFour: string; createdAt: string; expiresAt: string; revokedAt: string | null;
  scope: ReadScope;
}> {
  if (!UUID_PATTERN.test(userId)) throw new Error("Invalid account identifier");
  return db.prepare(`SELECT id, label, last_four AS lastFour, created_at AS createdAt,
    expires_at AS expiresAt, revoked_at AS revokedAt, read_scope AS scope FROM mcp_read_tokens
    WHERE user_id = ? ORDER BY created_at DESC LIMIT 100`).all(userId) as unknown as Array<{
      id: string; label: string; lastFour: string; createdAt: string; expiresAt: string; revokedAt: string | null;
      scope: ReadScope;
    }>;
}
