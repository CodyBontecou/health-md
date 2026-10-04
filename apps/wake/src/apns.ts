/** APNs HTTP/2 push for the wake doorbell. Token-based (ES256 JWT) auth.
 *
 * Adapted from the proven isome scheduled-notifications APNs client; wake sends
 * a visible alert push (never silent — the tap is the deliberate consent
 * gesture and suspended apps do not reliably budget silent pushes).
 */

import { providerJson } from "./http";

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
  const header = { alg: "ES256", kid: creds.keyId, typ: "JWT" };
  const payload = { iss: creds.teamId, iat: nowSec };
  const signingInput = `${base64urlEncodeJson(header)}.${base64urlEncodeJson(payload)}`;

  const key = await importEs256PrivateKey(creds.authKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: { name: "SHA-256" } },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64urlEncode(signature)}`;
}

export async function sendVisiblePush(
  creds: ApnsCredentials,
  opts: SendVisiblePushOptions,
): Promise<SendPushResult> {
  const host = opts.host ?? "api.push.apple.com";
  if (
    !["api.push.apple.com", "api.sandbox.push.apple.com"].includes(host)
    || !/^[A-Fa-f0-9]{32,200}$/.test(opts.apnsToken)
    || !/^[A-Za-z0-9.-]{1,255}$/.test(opts.bundleId)
    || !/^[A-Za-z0-9]{10}$/.test(creds.keyId) || !/^[A-Za-z0-9]{10}$/.test(creds.teamId)
    || creds.authKey.length > 8192 || !creds.authKey.startsWith("-----BEGIN PRIVATE KEY-----")
  ) return { status: 0, reason: "ApnsConfigInvalid" };
  try {
    // Request-local signing avoids stale credentials across reused isolates.
    const jwt = await signApnsJwt(creds);
    const response = await providerJson(`https://${host}/3/device/${opts.apnsToken}`, {
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
    }, "discard");
    const apnsId = response.headers.get("apns-id") ?? undefined;
    return response.status === 200 ? { status: 200, apnsId }
      : { status: response.status, reason: "ApnsRejected", apnsId };
  } catch {
    return { status: 0, reason: "ApnsTransportFailed" };
  }
}
