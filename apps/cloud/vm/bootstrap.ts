import { randomBytes, randomUUID } from "node:crypto";
import { audit, normalizeEmail } from "../src/auth";
import { encodeBase64, encryptIdentity, keyedLookup } from "../src/crypto";
import { derivePasswordVerifier, normalizeUsername, passwordIterations } from "../src/password";
import type { Env } from "../src/types";

export async function createSingleUserAccount(env: Env, usernameInput: string, emailInput: string,
  password: string): Promise<void> {
  const username = normalizeUsername(usernameInput);
  const email = normalizeEmail(emailInput);
  const existing = await env.DB.prepare("SELECT COUNT(*) AS count FROM users").first<{ count: number }>();
  if ((existing?.count ?? 0) !== 0) throw new Error("Single-user account already exists; no HTTP signup is available");
  const salt = randomBytes(32);
  const verifier = await derivePasswordVerifier(password, env.PASSWORD_PEPPER_B64 ?? "", salt);
  const accountId = randomUUID();
  const encryptedEmail = await encryptIdentity(email, env.IDENTITY_KEY_B64, accountId);
  const emailLookup = await keyedLookup(email, env.IDENTITY_KEY_B64, "email-lookup-v1");
  const usernameLookup = await keyedLookup(username, env.IDENTITY_KEY_B64, "username-lookup-v1");
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, ?, ?, 'active', ?)`).bind(accountId, emailLookup,
      encryptedEmail.ciphertext, encryptedEmail.iv, now),
    env.DB.prepare(`INSERT INTO password_credentials
      (user_id, username_lookup, salt, verifier, iterations, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`).bind(accountId, usernameLookup,
      encodeBase64(salt), verifier, passwordIterations, now, now),
  ]);
  await audit(env, accountId, "password_account.created", null);
}
