import { decryptIdentity, encryptIdentity, keyedLookup, randomToken, sha256Hex } from "./crypto";
import { assertSameOrigin, HttpError, json, parsePositiveInteger, readJson } from "./http";
import { recordAccountSecurityMetric } from "./telemetry";
import type { Env, IngestPrincipal, SessionUser, UserRow } from "./types";

const EMAIL_PATTERN = /^[^\s@]{1,64}@[^\s@]{1,190}$/u;
const TOKEN_PATTERN = /^hmd_(?:ing|ses|login)_[A-Za-z0-9_-]{40,50}$/u;
const COOKIE_NAME = "__Host-healthmd_cloud_session";
const DEV_COOKIE_NAME = "healthmd_cloud_session_dev";

export function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") throw new HttpError(400, "invalid_email", "Enter a valid email address.");
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email) || /[\r\n]/u.test(email)) {
    throw new HttpError(400, "invalid_email", "Enter a valid email address.");
  }
  return email;
}

function sessionCookie(token: string, ttlDays: number, secure: boolean): string {
  return `${secure ? COOKIE_NAME : DEV_COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${ttlDays * 86400}${secure ? "; Secure" : ""}`;
}

export function clearSessionCookie(secure: boolean): string {
  return `${secure ? COOKIE_NAME : DEV_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0${secure ? "; Secure" : ""}`;
}

function cookieToken(request: Request, env: Env): string | null {
  const rawCookie = request.headers.get("Cookie") ?? "";
  const entries = rawCookie.split(";");
  for (const entry of entries) {
    const [name, token] = entry.trim().split("=", 2);
    if (name === (env.ENVIRONMENT === "production" ? COOKIE_NAME : DEV_COOKIE_NAME) &&
        token && TOKEN_PATTERN.test(token) && token.startsWith("hmd_ses_")) {
      return token;
    }
  }
  return null;
}

export async function getSession(request: Request, env: Env): Promise<SessionUser | null> {
  const token = cookieToken(request, env);
  if (!token) return null;
  const tokenHash = await sha256Hex(token);
  const session = await env.DB.prepare(
    `SELECT u.id, u.email_ciphertext AS emailCiphertext, u.email_iv AS emailIv,
            s.id AS sessionId, s.created_at AS sessionCreatedAt
     FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at > ? AND u.status = 'active'`,
  ).bind(tokenHash, new Date().toISOString()).first<SessionUser>();
  return session;
}

export async function requireSession(request: Request, env: Env): Promise<SessionUser> {
  const session = await getSession(request, env);
  if (!session) throw new HttpError(401, "unauthorized", "Sign in to continue.");
  return session;
}

export async function requireIngestToken(request: Request, env: Env): Promise<IngestPrincipal> {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer (hmd_ing_[A-Za-z0-9_-]{40,50})$/u.exec(header);
  if (!match?.[1]) throw new HttpError(401, "unauthorized", "A valid export token is required.");
  const tokenHash = await sha256Hex(match[1]);
  const principal = await env.DB.prepare(
    `SELECT t.id AS tokenId, t.user_id AS userId FROM ingest_tokens t
     JOIN users u ON u.id = t.user_id
     WHERE t.token_hash = ? AND t.revoked_at IS NULL AND u.status = 'active'`,
  ).bind(tokenHash).first<IngestPrincipal>();
  if (!principal) throw new HttpError(401, "unauthorized", "A valid export token is required.");
  return principal;
}

export async function rateLimit(env: Env, bucket: string, limit: number): Promise<boolean> {
  const start = new Date(Math.floor(Date.now() / 3600000) * 3600000).toISOString();
  const expiry = new Date(Date.now() + 2 * 3600000).toISOString();
  const result = await env.DB.prepare(
    `INSERT INTO auth_rate_limits (bucket_key, window_start, request_count, expires_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT (bucket_key, window_start) DO UPDATE SET request_count = request_count + 1
     WHERE request_count < ?`,
  ).bind(bucket, start, expiry, limit).run();
  return (result.meta.changes ?? 0) > 0;
}

function signupAllowed(email: string, env: Env): boolean {
  if (env.AUTH_SIGNUP_MODE === "closed") return false;
  if (env.AUTH_SIGNUP_MODE === "invite") {
    return (env.AUTH_INVITE_EMAILS ?? "")
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .includes(email);
  }
  // Public signup is deliberately disabled until abuse, identity, and operational gates exist.
  return false;
}

async function sendMagicLink(env: Env, email: string, token: string): Promise<boolean> {
  if (env.ENVIRONMENT === "development" && env.DEV_SHOW_MAGIC_LINK === "1") return true;
  if (!env.RESEND_API_KEY) return false;
  const link = `${env.PUBLIC_ORIGIN}/login#token=${encodeURIComponent(token)}`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.AUTH_EMAIL_FROM,
      to: [email],
      subject: "Sign in to Health.md Cloud",
      text: `You requested a Health.md Cloud sign-in link. It expires in 15 minutes.\n\n${link}\n\nIf you didn't request it, ignore this message.`,
    }),
  });
  return response.ok;
}

export async function requestMagicLink(request: Request, env: Env): Promise<Response> {
  assertSameOrigin(request, env);
  const { email: input } = await readJson<{ email?: unknown }>(request);
  const email = normalizeEmail(input);
  const emailLookup = await keyedLookup(email, env.IDENTITY_KEY_B64, "email-lookup-v1");
  const ip = request.headers.get("CF-Connecting-IP") ?? "missing";
  const ipLookup = await keyedLookup(ip, env.IDENTITY_KEY_B64, "auth-ip-rate-v1");
  const allowedByRate = await rateLimit(env, `auth-ip:${ipLookup}`, 20);
  const allowedByEmailRate = await rateLimit(env, `auth-email:${emailLookup}`, 5);
  // Identical responses prevent account enumeration. Repeated requests still count toward limits.
  const generic = () => json({ message: "If this address is eligible, a sign-in link is on its way." });
  if (!allowedByRate || !allowedByEmailRate) return generic();

  let user = await env.DB.prepare(
    "SELECT * FROM users WHERE email_lookup = ?",
  ).bind(emailLookup).first<UserRow>();
  if (user && user.status !== "active") return generic();
  if (!user && !signupAllowed(email, env)) return generic();
  const sendBudget = env.EMAIL_SEND_HOURLY_LIMIT ?
    parsePositiveInteger(env.EMAIL_SEND_HOURLY_LIMIT, "EMAIL_SEND_HOURLY_LIMIT", 1, 100_000) : 100;
  if (!await rateLimit(env, "auth-send:global", sendBudget)) {
    recordAccountSecurityMetric(env, "email_budget_exhausted");
    return generic();
  }
  let newUser: UserRow | null = null;
  if (!user) {
    const id = crypto.randomUUID();
    const encrypted = await encryptIdentity(email, env.IDENTITY_KEY_B64, id);
    newUser = {
      id,
      email_lookup: emailLookup,
      email_ciphertext: encrypted.ciphertext,
      email_iv: encrypted.iv,
      status: "active",
      created_at: new Date().toISOString(),
    };
    user = newUser;
  }
  const token = `hmd_login_${randomToken()}`;
  const tokenHash = await sha256Hex(token);
  const linkId = crypto.randomUUID();
  const ttlMinutes = parsePositiveInteger(env.MAGIC_LINK_TTL_MINUTES, "MAGIC_LINK_TTL_MINUTES", 5, 30);
  const now = new Date().toISOString();
  const expires = new Date(Date.now() + ttlMinutes * 60000).toISOString();
  const createLink = env.DB.prepare(
    `INSERT INTO magic_links (id, user_id, token_hash, expires_at, created_at)
     SELECT ?, id, ?, ?, ? FROM users WHERE email_lookup = ? AND status = 'active'`,
  ).bind(linkId, tokenHash, expires, now, emailLookup);
  try {
    if (newUser) {
      // Concurrent first requests may both observe no account. D1 serializes
      // these transactions: one user wins, the other deliberately reuses it.
      await env.DB.batch([
        env.DB.prepare(
          `INSERT OR IGNORE INTO users
           (id, email_lookup, email_ciphertext, email_iv, status, created_at)
           VALUES (?, ?, ?, ?, 'active', ?)`,
        ).bind(user.id, emailLookup, user.email_ciphertext, user.email_iv, now),
        createLink,
      ]);
    } else {
      await createLink.run();
    }
  } catch {
    // A D1 response can be lost after commit. Reconcile below before deciding
    // whether the one-time link is safe to send or reveal in local development.
  }
  let durableLink: { valid: number } | null;
  try {
    durableLink = await env.DB.prepare(`SELECT 1 AS valid FROM magic_links m
      JOIN users u ON u.id = m.user_id
      WHERE m.id = ? AND m.token_hash = ? AND u.email_lookup = ? AND u.status = 'active'`)
      .bind(linkId, tokenHash, emailLookup).first<{ valid: number }>();
  } catch {
    recordAccountSecurityMetric(env, "magic_link_persistence_failed");
    return generic();
  }
  if (durableLink?.valid !== 1) {
    recordAccountSecurityMetric(env, "magic_link_persistence_failed");
    return generic();
  }
  let sent = false;
  try {
    sent = await sendMagicLink(env, email, token);
  } catch {
    // Never log provider responses; they can contain account identifiers.
  }
  if (!sent) {
    await env.DB.prepare("DELETE FROM magic_links WHERE id = ?").bind(linkId).run();
    return generic();
  }
  if (env.ENVIRONMENT === "development" && env.DEV_SHOW_MAGIC_LINK === "1") {
    // Local Wrangler only. Refused in production; never include the token in CI artifacts.
    return json({ message: "Development sign-in link generated.", devLink: `${env.PUBLIC_ORIGIN}/login#token=${token}` });
  }
  return generic();
}

export async function issueSession(env: Env, userId: string): Promise<Response> {
  const sessionToken = `hmd_ses_${randomToken()}`;
  const ttlDays = parsePositiveInteger(env.SESSION_TTL_DAYS, "SESSION_TTL_DAYS", 1, 30);
  const now = new Date().toISOString();
  const expires = new Date(Date.now() + ttlDays * 86400000).toISOString();
  await env.DB.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(crypto.randomUUID(), userId, await sha256Hex(sessionToken), expires, now, now).run();
  await audit(env, userId, "session.created", null);
  return json({ signedIn: true }, {
    headers: { "Set-Cookie": sessionCookie(sessionToken, ttlDays, env.ENVIRONMENT === "production") },
  });
}

export async function consumeMagicLink(request: Request, env: Env): Promise<Response> {
  assertSameOrigin(request, env);
  const { token } = await readJson<{ token?: unknown }>(request);
  if (typeof token !== "string" || !TOKEN_PATTERN.test(token) || !token.startsWith("hmd_login_")) {
    throw new HttpError(400, "invalid_link", "The sign-in link is invalid or expired.");
  }
  const hash = await sha256Hex(token);
  const now = new Date().toISOString();
  // D1 RETURNING makes the single-use claim atomic across concurrent requests.
  const row = await env.DB.prepare(
    `UPDATE magic_links SET consumed_at = ?
     WHERE token_hash = ? AND consumed_at IS NULL AND expires_at > ?
     AND user_id IN (SELECT id FROM users WHERE status = 'active')
     RETURNING user_id AS userId`,
  ).bind(now, hash, now).first<{ userId: string }>();
  if (!row) throw new HttpError(400, "invalid_link", "The sign-in link is invalid or expired.");
  return issueSession(env, row.userId);
}

export async function logout(request: Request, env: Env, user: SessionUser): Promise<Response> {
  assertSameOrigin(request, env);
  const token = cookieToken(request, env);
  if (token) {
    await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ? AND user_id = ?")
      .bind(await sha256Hex(token), user.id).run();
  }
  await audit(env, user.id, "session.revoked", null);
  return json({ signedIn: false }, {
    headers: { "Set-Cookie": clearSessionCookie(env.ENVIRONMENT === "production") },
  });
}

export async function listSessions(env: Env, user: SessionUser): Promise<Response> {
  const sessions = await env.DB.prepare(
    `SELECT id, created_at AS createdAt, last_seen_at AS lastSeenAt, expires_at AS expiresAt
     FROM sessions WHERE user_id = ? AND expires_at > ? ORDER BY created_at DESC LIMIT 20`,
  ).bind(user.id, new Date().toISOString()).all<{
    id: string; createdAt: string; lastSeenAt: string; expiresAt: string;
  }>();
  return json({ sessions: sessions.results.map((session) => ({
    ...session, current: session.id === user.sessionId,
  })) });
}

export async function revokeSession(
  request: Request,
  env: Env,
  user: SessionUser,
  sessionId: string,
): Promise<Response> {
  assertSameOrigin(request, env);
  if (!/^[a-f0-9-]{36}$/u.test(sessionId)) throw new HttpError(404, "not_found", "Session not found.");
  const result = await env.DB.prepare("DELETE FROM sessions WHERE id = ? AND user_id = ?")
    .bind(sessionId, user.id).run();
  if ((result.meta.changes ?? 0) !== 1) throw new HttpError(404, "not_found", "Session not found.");
  await audit(env, user.id, "session.revoked", sessionId);
  const current = sessionId === user.sessionId;
  return json({ revoked: true, current }, current ? {
    headers: { "Set-Cookie": clearSessionCookie(env.ENVIRONMENT === "production") },
  } : {});
}

export async function revokeOtherSessions(request: Request, env: Env, user: SessionUser): Promise<Response> {
  assertSameOrigin(request, env);
  const result = await env.DB.prepare("DELETE FROM sessions WHERE user_id = ? AND id != ?")
    .bind(user.id, user.sessionId).run();
  await audit(env, user.id, "session.others_revoked", user.sessionId);
  return json({ revoked: result.meta.changes ?? 0 });
}

export async function accountSummary(env: Env, user: SessionUser): Promise<Response> {
  const email = await decryptIdentity(user.emailCiphertext, user.emailIv, env.IDENTITY_KEY_B64, user.id);
  return json({ email });
}

export async function audit(env: Env, userId: string, type: string, targetId: string | null): Promise<void> {
  await env.DB.prepare(
    "INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at) VALUES (?, ?, ?, ?, ?)",
  ).bind(crypto.randomUUID(), userId, type, targetId, new Date().toISOString()).run();
}

export async function listSecurityActivity(env: Env, userId: string): Promise<Response> {
  // This explicit allowlist is the public security-history vocabulary. Target
  // IDs remain server-side because they are unnecessary correlation metadata.
  const rows = await env.DB.prepare(`SELECT event_type AS type, occurred_at AS occurredAt
    FROM audit_events WHERE user_id = ? AND event_type IN (
      'password_login.succeeded', 'session.created', 'session.revoked', 'session.others_revoked',
      'ingest_token.created', 'ingest_token.revoked', 'agent_token.created', 'agent_token.revoked',
      'export.downloaded', 'repair_device.approved', 'repair_device.revoked',
      'repair_dispatch.queued', 'repair_dispatch.cancelled', 'repair_dispatch.claimed',
      'repair_dispatch.declined'
    ) ORDER BY occurred_at DESC, id DESC LIMIT 50`).bind(userId).all<{
      type: string; occurredAt: string;
    }>();
  return json({ events: rows.results });
}

export async function listIngestTokens(env: Env, userId: string): Promise<Response> {
  const results = await env.DB.prepare(
    `SELECT id, name, last_four AS lastFour, created_at AS createdAt,
            last_used_at AS lastUsedAt, revoked_at AS revokedAt
     FROM ingest_tokens WHERE user_id = ? ORDER BY created_at DESC LIMIT 50`,
  ).bind(userId).all();
  return json({ tokens: results.results });
}

export async function createIngestToken(request: Request, env: Env, userId: string): Promise<Response> {
  assertSameOrigin(request, env);
  const body = await readJson<{ name?: unknown }>(request);
  const name = typeof body.name === "string" ? body.name.trim() : "";
  if (name.length < 1 || name.length > 80 || /[\x00-\x1f\x7f]/u.test(name)) {
    throw new HttpError(400, "invalid_name", "Choose a name of 1–80 characters.");
  }
  const id = crypto.randomUUID();
  const token = `hmd_ing_${randomToken()}`;
  const tokenHash = await sha256Hex(token);
  const now = new Date().toISOString();
  let batchCompleted = false;
  let batchFailure: unknown;
  try {
    await env.DB.batch([
      // The cap check belongs in the serialized write transaction. A separate
      // count read would let concurrent account requests exceed the limit.
      env.DB.prepare(
        `INSERT INTO ingest_tokens (id, user_id, name, token_hash, last_four, created_at)
         SELECT ?, ?, ?, ?, ?, ? WHERE
           EXISTS (SELECT 1 FROM users WHERE id = ? AND status = 'active') AND
           (SELECT COUNT(*) FROM ingest_tokens WHERE user_id = ? AND revoked_at IS NULL) < 10`,
      ).bind(id, userId, name, tokenHash, token.slice(-4), now, userId, userId),
      env.DB.prepare(
        `INSERT INTO audit_events (id, user_id, event_type, target_id, occurred_at)
         SELECT ?, ?, 'ingest_token.created', ?, ? FROM ingest_tokens
         WHERE id = ? AND user_id = ? AND token_hash = ?`,
      ).bind(crypto.randomUUID(), userId, id, now, id, userId, tokenHash),
    ]);
    batchCompleted = true;
  } catch (error) {
    // The D1 response can be lost after commit. Verify the exact durable token
    // and audit postcondition before deciding whether the one-time secret is safe to return.
    batchFailure = error;
  }
  let committed: { valid: number } | null;
  try {
    committed = await env.DB.prepare(`SELECT 1 AS valid FROM ingest_tokens t
      JOIN audit_events a ON a.user_id = t.user_id AND a.target_id = t.id
        AND a.event_type = 'ingest_token.created'
      WHERE t.id = ? AND t.user_id = ? AND t.token_hash = ? AND t.revoked_at IS NULL`)
      .bind(id, userId, tokenHash).first<{ valid: number }>();
  } catch {
    throw new HttpError(503, "token_verification_pending",
      "Export token creation verification is temporarily unavailable. Review account tokens before retrying.");
  }
  if (committed?.valid !== 1) {
    const state = await env.DB.prepare(`SELECT
      EXISTS (SELECT 1 FROM users WHERE id = ? AND status = 'active') AS active,
      (SELECT COUNT(*) FROM ingest_tokens WHERE user_id = ? AND revoked_at IS NULL) AS count`)
      .bind(userId, userId).first<{ active: number; count: number }>();
    if (!state?.active) throw new HttpError(401, "unauthorized", "Sign in to continue.");
    if (state.count >= 10) {
      throw new HttpError(409, "token_limit", "Revoke an export token before creating another.");
    }
    if (!batchCompleted) throw batchFailure;
    throw new HttpError(503, "token_creation_failed", "Export token creation is temporarily unavailable.");
  }
  return json({ id, token, name, message: "Copy this write-only token now. It will not be shown again." }, { status: 201 });
}

export async function revokeIngestToken(
  request: Request,
  env: Env,
  userId: string,
  tokenId: string,
): Promise<Response> {
  assertSameOrigin(request, env);
  if (!/^[a-f0-9-]{36}$/u.test(tokenId)) throw new HttpError(404, "not_found", "Token not found.");
  const now = new Date().toISOString();
  const result = await env.DB.prepare(
    "UPDATE ingest_tokens SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
  ).bind(now, tokenId, userId).run();
  if ((result.meta.changes ?? 0) === 0) throw new HttpError(404, "not_found", "Token not found.");
  await audit(env, userId, "ingest_token.revoked", tokenId);
  return json({ revoked: true });
}

export async function limitIngest(env: Env, tokenId: string, userId: string): Promise<void> {
  const tokenLimit = env.INGEST_TOKEN_HOURLY_LIMIT ?
    parsePositiveInteger(env.INGEST_TOKEN_HOURLY_LIMIT, "INGEST_TOKEN_HOURLY_LIMIT", 1, 100_000) : 120;
  const accountLimit = env.INGEST_ACCOUNT_HOURLY_LIMIT ?
    parsePositiveInteger(env.INGEST_ACCOUNT_HOURLY_LIMIT, "INGEST_ACCOUNT_HOURLY_LIMIT", 1, 100_000) : 240;
  if (!await rateLimit(env, `ingest:${tokenId}`, tokenLimit) ||
      !await rateLimit(env, `ingest-account:${userId}`, accountLimit)) {
    throw new HttpError(429, "rate_limited", "Export request limit exceeded. Retry later.");
  }
}
