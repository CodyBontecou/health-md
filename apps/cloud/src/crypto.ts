const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();
const EXPORT_MAGIC = textEncoder.encode("HMDC1");
const EXPORT_SALT_BYTES = 16;
const AES_GCM_IV_BYTES = 12;

function toBuffer(bytes: Uint8Array): ArrayBuffer {
  return Uint8Array.from(bytes).buffer;
}

export function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}

export function decodeBase64(value: string): Uint8Array {
  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new Error("Invalid base64 secret");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function encodeBase64Url(bytes: Uint8Array): string {
  return encodeBase64(bytes).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

export function randomToken(byteCount = 32): string {
  return encodeBase64Url(crypto.getRandomValues(new Uint8Array(byteCount)));
}

export async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const input = typeof value === "string" ? textEncoder.encode(value) : value;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", toBuffer(input)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function importAesKey(base64: string): Promise<CryptoKey> {
  const bytes = decodeBase64(base64);
  if (bytes.byteLength !== 32) throw new Error("Encryption keys must contain exactly 32 bytes");
  return crypto.subtle.importKey("raw", toBuffer(bytes), { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

async function importHmacKey(base64: string): Promise<CryptoKey> {
  const bytes = decodeBase64(base64);
  if (bytes.byteLength !== 32) throw new Error("Identity key must contain exactly 32 bytes");
  return crypto.subtle.importKey("raw", toBuffer(bytes), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
}

export async function keyedLookup(value: string, identityKeyBase64: string, purpose: string): Promise<string> {
  const key = await importHmacKey(identityKeyBase64);
  const digest = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, textEncoder.encode(`${purpose}\0${value}`)),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function encryptIdentity(
  plaintext: string,
  identityKeyBase64: string,
  accountId: string,
): Promise<{ ciphertext: string; iv: string }> {
  const key = await importAesKey(identityKeyBase64);
  const iv = crypto.getRandomValues(new Uint8Array(AES_GCM_IV_BYTES));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: textEncoder.encode(`healthmd.cloud.identity.v1\0${accountId}`) },
      key,
      textEncoder.encode(plaintext),
    ),
  );
  return { ciphertext: encodeBase64(ciphertext), iv: encodeBase64(iv) };
}

export async function decryptIdentity(
  ciphertextBase64: string,
  ivBase64: string,
  identityKeyBase64: string,
  accountId: string,
): Promise<string> {
  const key = await importAesKey(identityKeyBase64);
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: toBuffer(decodeBase64(ivBase64)),
      additionalData: textEncoder.encode(`healthmd.cloud.identity.v1\0${accountId}`),
    },
    key,
    toBuffer(decodeBase64(ciphertextBase64)),
  );
  return textDecoder.decode(plaintext);
}

export function parseExportKeyring(value: string): ReadonlyMap<string, string> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new Error("EXPORT_ENCRYPTION_KEYS_JSON is not valid JSON");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("EXPORT_ENCRYPTION_KEYS_JSON must be an object");
  }
  const entries = Object.entries(parsed);
  if (entries.length === 0) throw new Error("At least one export encryption key is required");
  const keyring = new Map<string, string>();
  for (const [id, encoded] of entries) {
    if (!/^[A-Za-z0-9._-]{1,32}$/u.test(id) || typeof encoded !== "string") {
      throw new Error("Invalid export encryption key entry");
    }
    if (decodeBase64(encoded).byteLength !== 32) {
      throw new Error(`Export encryption key ${id} must contain exactly 32 bytes`);
    }
    keyring.set(id, encoded);
  }
  return keyring;
}

async function deriveExportKey(rootKeyBase64: string, salt: Uint8Array): Promise<CryptoKey> {
  const rootBytes = decodeBase64(rootKeyBase64);
  if (rootBytes.byteLength !== 32) throw new Error("Export encryption keys must contain exactly 32 bytes");
  const root = await crypto.subtle.importKey("raw", toBuffer(rootBytes), "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: toBuffer(salt),
      info: textEncoder.encode("healthmd.cloud.export.v1"),
    },
    root,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

function exportAad(userId: string, exportId: string): Uint8Array {
  return textEncoder.encode(`healthmd.cloud.export.v1\0${userId}\0${exportId}`);
}

export async function encryptExport(
  plaintext: Uint8Array,
  rootKeyBase64: string,
  userId: string,
  exportId: string,
): Promise<Uint8Array> {
  const salt = crypto.getRandomValues(new Uint8Array(EXPORT_SALT_BYTES));
  const iv = crypto.getRandomValues(new Uint8Array(AES_GCM_IV_BYTES));
  const key = await deriveExportKey(rootKeyBase64, salt);
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: toBuffer(exportAad(userId, exportId)) },
      key,
      toBuffer(plaintext),
    ),
  );
  const result = new Uint8Array(EXPORT_MAGIC.length + salt.length + iv.length + ciphertext.length);
  result.set(EXPORT_MAGIC, 0);
  result.set(salt, EXPORT_MAGIC.length);
  result.set(iv, EXPORT_MAGIC.length + salt.length);
  result.set(ciphertext, EXPORT_MAGIC.length + salt.length + iv.length);
  return result;
}

export async function decryptExport(
  encrypted: Uint8Array,
  rootKeyBase64: string,
  userId: string,
  exportId: string,
): Promise<Uint8Array> {
  const minimumLength = EXPORT_MAGIC.length + EXPORT_SALT_BYTES + AES_GCM_IV_BYTES + 16;
  if (encrypted.byteLength < minimumLength) throw new Error("Encrypted export is truncated");
  for (let index = 0; index < EXPORT_MAGIC.length; index += 1) {
    if (encrypted[index] !== EXPORT_MAGIC[index]) throw new Error("Encrypted export has an unknown format");
  }
  const saltStart = EXPORT_MAGIC.length;
  const ivStart = saltStart + EXPORT_SALT_BYTES;
  const ciphertextStart = ivStart + AES_GCM_IV_BYTES;
  const salt = encrypted.slice(saltStart, ivStart);
  const iv = encrypted.slice(ivStart, ciphertextStart);
  const key = await deriveExportKey(rootKeyBase64, salt);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: toBuffer(iv), additionalData: toBuffer(exportAad(userId, exportId)) },
    key,
    toBuffer(encrypted.slice(ciphertextStart)),
  );
  return new Uint8Array(plaintext);
}

export function timingSafeEqual(left: string, right: string): boolean {
  const leftBytes = textEncoder.encode(left);
  const rightBytes = textEncoder.encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let mismatch = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < length; index += 1) {
    mismatch |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return mismatch === 0;
}
