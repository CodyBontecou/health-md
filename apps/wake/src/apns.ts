/** APNs HTTP/2 push for the wake doorbell. Token-based (ES256 JWT) auth.
 *
 * Adapted from the proven isome scheduled-notifications APNs client; wake sends
 * a visible alert push (never silent — the tap is the deliberate consent
 * gesture and suspended apps do not reliably budget silent pushes).
 */

export interface ApnsCredentials {
  authKey: string;
  keyId: string;
  teamId: string;
}

export interface SendVisiblePushOptions {
  apnsToken: string;
  bundleId: string;
  payload: Record<string, unknown>;
  expirationSec: number;
  host?: "api.push.apple.com" | "api.sandbox.push.apple.com";
}

export interface SendPushResult {
  status: number;
  reason?: string;
  apnsId?: string;
}

const JWT_LIFETIME_SEC = 50 * 60;
let cachedJwt: { token: string; expiresAt: number; keyId: string } | null = null;

function base64urlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (let i = 0; i < arr.byteLength; i += 1) binary += String.fromCharCode(arr[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlEncodeJson(obj: unknown): string {
  return base64urlEncode(new TextEncoder().encode(JSON.stringify(obj)));
}

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const stripped = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(stripped);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out;
}

async function importEs256PrivateKey(pem: string): Promise<CryptoKey> {
  const pkcs8 = pemToPkcs8Bytes(pem);
  const keyData = pkcs8.buffer.slice(
    pkcs8.byteOffset,
    pkcs8.byteOffset + pkcs8.byteLength,
  ) as ArrayBuffer;
  return crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

export async function signApnsJwt(
  creds: ApnsCredentials,
  nowSec: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  if (cachedJwt && cachedJwt.keyId === creds.keyId && cachedJwt.expiresAt > nowSec + 60) {
    return cachedJwt.token;
  }

  const header = { alg: "ES256", kid: creds.keyId, typ: "JWT" };
  const payload = { iss: creds.teamId, iat: nowSec };
  const signingInput = `${base64urlEncodeJson(header)}.${base64urlEncodeJson(payload)}`;

  const key = await importEs256PrivateKey(creds.authKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: { name: "SHA-256" } },
    key,
    new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${base64urlEncode(signature)}`;
  cachedJwt = { token, expiresAt: nowSec + JWT_LIFETIME_SEC, keyId: creds.keyId };
  return token;
}

export async function sendVisiblePush(
  creds: ApnsCredentials,
  opts: SendVisiblePushOptions,
): Promise<SendPushResult> {
  const jwt = await signApnsJwt(creds);
  const host = opts.host ?? "api.push.apple.com";
  const url = `https://${host}/3/device/${opts.apnsToken}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-topic": opts.bundleId,
      "apns-expiration": String(opts.expirationSec),
      "content-type": "application/json",
    },
    body: JSON.stringify(opts.payload),
  });

  const apnsId = response.headers.get("apns-id") ?? undefined;
  if (response.status === 200) return { status: 200, apnsId };

  let reason: string | undefined;
  try {
    const text = await response.text();
    if (text) reason = (JSON.parse(text) as { reason?: string }).reason;
  } catch {
    // Non-JSON APNs response body; leave reason unset.
  }
  return { status: response.status, reason, apnsId };
}
