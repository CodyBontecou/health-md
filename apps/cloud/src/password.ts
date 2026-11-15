import { audit, issueSession, rateLimit } from "./auth";
import { decodeBase64, encodeBase64, keyedLookup } from "./crypto";
import { assertSameOrigin, HttpError, json, readJson } from "./http";
import type { Env } from "./types";

// Versioned, peppered PBKDF2 verifier for the single-user password profile.
// A stronger memory-hard KDF is required if this profile is opened beyond one
// account; do not use this module as a public-registration password service.
const ITERATIONS = 600_000;
const USERNAME_PATTERN = /^[a-z0-9][a-z0-9._-]{2,63}$/u;
const text = new TextEncoder();

interface CredentialRow {
  userId: string;
  salt: string;
  verifier: string;
  iterations: number;
}

export function normalizeUsername(value: unknown): string {
  if (typeof value !== "string") throw new HttpError(400, "invalid_credentials", "Invalid username or password.");
  const normalized = value.trim().toLowerCase();
  if (!USERNAME_PATTERN.test(normalized)) {
    throw new HttpError(400, "invalid_credentials", "Invalid username or password.");
  }
  return normalized;
}

function validPassword(value: unknown): value is string {
  return typeof value === "string" && value.length >= 16 && value.length <= 1024 &&
    !/[\u0000-\u001f\u007f]/u.test(value);
}

function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  return Uint8Array.from(bytes).buffer;
}

export async function derivePasswordVerifier(password: string, pepperBase64: string, salt: Uint8Array,
  iterations = ITERATIONS): Promise<string> {
  if (!validPassword(password) || salt.byteLength !== 32 || iterations < ITERATIONS ||
      iterations > 1_200_000) throw new Error("Invalid password-verifier parameters");
  const pepper = decodeBase64(pepperBase64);
  if (pepper.byteLength !== 32) throw new Error("Password pepper must be 32 bytes");
  const pepperKey = await crypto.subtle.importKey("raw", exactBuffer(pepper),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const input = await crypto.subtle.sign("HMAC", pepperKey, text.encode(`healthmd.cloud.password.v1\0${password}`));
  const key = await crypto.subtle.importKey("raw", input, "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256",
    salt: exactBuffer(salt), iterations }, key, 256);
  return encodeBase64(new Uint8Array(bits));
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  let mismatch = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) mismatch |= (left[index] ?? 0) ^ (right[index] ?? 0);
  return mismatch === 0;
}

export async function verifyPassword(password: string, pepperBase64: string, salt: string,
  verifier: string, iterations: number): Promise<boolean> {
  if (!validPassword(password)) return false;
  let expected: Uint8Array;
  let derived: Uint8Array;
  try {
    expected = decodeBase64(verifier);
    derived = decodeBase64(await derivePasswordVerifier(password, pepperBase64, decodeBase64(salt), iterations));
  } catch {
    return false;
  }
  return expected.length === 32 && constantTimeEqual(derived, expected);
}

export async function verifyAccountPassword(env: Env, userId: string, password: unknown): Promise<boolean> {
  if (typeof password !== "string") return false;
  const allowed = await rateLimit(env, `account-reauth:${userId}`, 10);
  if (!allowed) return false;
  const row = await env.DB.prepare(
    "SELECT salt, verifier, iterations FROM password_credentials WHERE user_id = ?",
  ).bind(userId).first<Pick<CredentialRow, "salt" | "verifier" | "iterations">>();
  return !!row && verifyPassword(password, env.PASSWORD_PEPPER_B64 ?? "",
    row.salt, row.verifier, row.iterations);
}

export async function passwordLogin(request: Request, env: Env): Promise<Response> {
  assertSameOrigin(request, env);
  const input = await readJson<{ username?: unknown; password?: unknown }>(request);
  const username = normalizeUsername(input.username);
  const ip = request.headers.get("CF-Connecting-IP") ?? "missing";
  const ipLookup = await keyedLookup(ip, env.IDENTITY_KEY_B64, "password-ip-rate-v1");
  const usernameLookup = await keyedLookup(username, env.IDENTITY_KEY_B64, "username-lookup-v1");
  const allowedByIp = await rateLimit(env, `password-ip:${ipLookup}`, 30);
  const allowedByUsername = await rateLimit(env, `password-user:${usernameLookup}`, 5);
  if (!allowedByIp || !allowedByUsername) {
    throw new HttpError(429, "rate_limited", "Too many sign-in attempts. Try again later.");
  }
  const row = await env.DB.prepare(
    `SELECT p.user_id AS userId, p.salt, p.verifier, p.iterations FROM password_credentials p
     JOIN users u ON u.id = p.user_id WHERE p.username_lookup = ? AND u.status = 'active'`,
  ).bind(usernameLookup).first<CredentialRow>();
  // Spend comparable KDF time for unknown usernames. Do not reveal account presence.
  const dummySalt = encodeBase64(new Uint8Array(32));
  const dummyVerifier = encodeBase64(new Uint8Array(32));
  const candidate = typeof input.password === "string" ? input.password : "";
  const verified = await verifyPassword(candidate, env.PASSWORD_PEPPER_B64 ?? "",
    row?.salt ?? dummySalt, row?.verifier ?? dummyVerifier, row?.iterations ?? ITERATIONS);
  if (!row || !verified) {
    throw new HttpError(401, "invalid_credentials", "Invalid username or password.");
  }
  await audit(env, row.userId, "password_login.succeeded", null);
  return issueSession(env, row.userId);
}

export const passwordIterations = ITERATIONS;
