import { encodeBase64, parseExportKeyring, unwrapAccountExportKey, wrapAccountExportKey } from "./crypto";
import type { Env } from "./types";

interface AccountKeyRow {
  userId?: string;
  keyId: string;
  wrappingKeyId: string;
  wrappedKey: string;
  wrapIv: string;
}

function wrappingKeys(env: Env): ReadonlyMap<string, string> {
  if (!env.ACCOUNT_KEY_WRAPPING_KEYS_JSON) throw new Error("Account export wrapping keys are unavailable");
  return parseExportKeyring(env.ACCOUNT_KEY_WRAPPING_KEYS_JSON);
}

async function unwrap(env: Env, userId: string, row: AccountKeyRow): Promise<{ keyId: string; key: string }> {
  const wrapping = wrappingKeys(env).get(row.wrappingKeyId);
  if (!wrapping) throw new Error("Historical account export wrapping key is unavailable");
  return {
    keyId: row.keyId,
    key: await unwrapAccountExportKey(row.wrappedKey, row.wrapIv, wrapping, userId,
      row.keyId, row.wrappingKeyId),
  };
}

export async function currentExportKey(env: Env, userId: string): Promise<{ keyId: string; key: string }> {
  const legacyKeys = parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON);
  if (env.ACCOUNT_KEY_MODE !== "per_account") {
    const key = legacyKeys.get(env.CURRENT_EXPORT_KEY_ID);
    if (!key) throw new Error("Current export encryption key is not configured");
    return { keyId: env.CURRENT_EXPORT_KEY_ID, key };
  }
  const wrappingKeyId = env.CURRENT_ACCOUNT_WRAPPING_KEY_ID;
  if (!wrappingKeyId || !/^[A-Za-z0-9._-]{1,32}$/u.test(wrappingKeyId)) {
    throw new Error("Current account wrapping key ID is invalid");
  }
  const wrapping = wrappingKeys(env).get(wrappingKeyId);
  if (!wrapping) throw new Error("Current account wrapping key is unavailable");
  const existing = await env.DB.prepare(
    `SELECT key_id AS keyId, wrapping_key_id AS wrappingKeyId,
            wrapped_key AS wrappedKey, wrap_iv AS wrapIv
     FROM account_export_keys WHERE user_id = ? AND retired_at IS NULL LIMIT 1`,
  ).bind(userId).first<AccountKeyRow>();
  if (existing) return unwrap(env, userId, existing);

  const keyId = crypto.randomUUID();
  const dataKey = encodeBase64(crypto.getRandomValues(new Uint8Array(32)));
  const wrapped = await wrapAccountExportKey(dataKey, wrapping, userId, keyId, wrappingKeyId);
  try {
    const result = await env.DB.prepare(
      `INSERT INTO account_export_keys
       (user_id, key_id, wrapping_key_id, wrapped_key, wrap_iv, created_at)
       SELECT ?, ?, ?, ?, ?, ? FROM users WHERE id = ? AND status = 'active'`,
    ).bind(userId, keyId, wrappingKeyId, wrapped.wrappedKey, wrapped.iv,
      new Date().toISOString(), userId).run();
    if ((result.meta.changes ?? 0) === 1) return { keyId, key: dataKey };
  } catch {
    // Another isolate may have created the one active account key first.
  }
  const winner = await env.DB.prepare(
    `SELECT key_id AS keyId, wrapping_key_id AS wrappingKeyId,
            wrapped_key AS wrappedKey, wrap_iv AS wrapIv
     FROM account_export_keys WHERE user_id = ? AND retired_at IS NULL LIMIT 1`,
  ).bind(userId).first<AccountKeyRow>();
  if (!winner) throw new Error("Active account export key could not be created");
  return unwrap(env, userId, winner);
}

export async function rewrapAccountExportKeys(env: Env, limit = 25): Promise<number> {
  if (env.ACCOUNT_KEY_MODE !== "per_account" || !env.CURRENT_ACCOUNT_WRAPPING_KEY_ID ||
      !Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("Account export key rotation is not configured");
  }
  const currentWrappingKeyId = env.CURRENT_ACCOUNT_WRAPPING_KEY_ID;
  const keys = wrappingKeys(env);
  const currentWrappingKey = keys.get(currentWrappingKeyId);
  if (!currentWrappingKey) throw new Error("Current account wrapping key is unavailable");
  const rows = await env.DB.prepare(
    `SELECT user_id AS userId, key_id AS keyId, wrapping_key_id AS wrappingKeyId,
            wrapped_key AS wrappedKey, wrap_iv AS wrapIv
     FROM account_export_keys WHERE wrapping_key_id != ? ORDER BY created_at, key_id LIMIT ?`,
  ).bind(currentWrappingKeyId, limit).all<AccountKeyRow>();
  let changed = 0;
  for (const row of rows.results) {
    if (!row.userId) throw new Error("Account export key owner is unavailable");
    const plaintext = await unwrap(env, row.userId, row);
    const wrapped = await wrapAccountExportKey(plaintext.key, currentWrappingKey, row.userId,
      row.keyId, currentWrappingKeyId);
    const result = await env.DB.prepare(
      `UPDATE account_export_keys SET wrapping_key_id = ?, wrapped_key = ?, wrap_iv = ?, rewrapped_at = ?
       WHERE user_id = ? AND key_id = ? AND wrapping_key_id = ? AND wrapped_key = ? AND wrap_iv = ?`,
    ).bind(currentWrappingKeyId, wrapped.wrappedKey, wrapped.iv, new Date().toISOString(),
      row.userId, row.keyId, row.wrappingKeyId, row.wrappedKey, row.wrapIv).run();
    changed += result.meta.changes ?? 0;
  }
  return changed;
}

export async function resolveExportKey(
  env: Env,
  userId: string,
  keyId: string,
): Promise<string> {
  // Legacy root-key exports remain readable during an explicit migration.
  const legacy = parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON).get(keyId);
  if (legacy) return legacy;
  if (env.ACCOUNT_KEY_MODE !== "per_account") throw new Error("Encrypted export key is unavailable");
  const row = await env.DB.prepare(
    `SELECT key_id AS keyId, wrapping_key_id AS wrappingKeyId,
            wrapped_key AS wrappedKey, wrap_iv AS wrapIv
     FROM account_export_keys WHERE user_id = ? AND key_id = ? LIMIT 1`,
  ).bind(userId, keyId).first<AccountKeyRow>();
  if (!row) throw new Error("Account export key is unavailable");
  return (await unwrap(env, userId, row)).key;
}
