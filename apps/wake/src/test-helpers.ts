/** Synthetic test inputs only. Cryptographic provider keys are generated in memory. */
import { hexEncode, hmacSha256 } from "./crypto";

export const USER_ID = "synthetic_install_001";
export const APNS_TOKEN = "ab".repeat(32);
export const FCM_TOKEN = "synthetic-fcm-token";
export const WAKE_HASH = "4bb06f8e4e3a7715d201d573d0aa423762e55dabd61a2c02278fa56cc6d294e0";
export const MANAGEMENT_HASH = "8c0cc17a04942cc4f8e0fe0b302606d3108860c126428ba2ceeb5f9ed41c2b05";
export const TIMESTAMP = "2026-10-04T12:00:00Z";
export const NOW = Date.parse(TIMESTAMP);

export function jsonRequest(path: string, body: unknown, method = "POST"): Request {
  return new Request(`https://wake.invalid${path}`, {
    method, headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}

export async function syntheticPem(algorithm: "apns" | "fcm"): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    algorithm === "apns"
      ? { name: "ECDSA", namedCurve: "P-256" }
      : { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  if (!("privateKey" in pair)) throw new Error("Expected a synthetic key pair");
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  if (!(exported instanceof ArrayBuffer)) throw new Error("Expected PKCS8 bytes");
  const encoded = btoa(String.fromCharCode(...new Uint8Array(exported)));
  return { pem: `-----BEGIN PRIVATE KEY-----\n${encoded}\n-----END PRIVATE KEY-----`, publicKey: pair.publicKey };
}

export async function proof(hash: string, message: string): Promise<string> {
  const bytes = Uint8Array.from(hash.match(/../g) ?? [], (part) => parseInt(part, 16));
  return hexEncode(await hmacSha256(bytes, new TextEncoder().encode(message)));
}

export interface TestEnrollment {
  operation: "enroll" | "rotate";
  wakeId: string;
  userId: string;
  transport: string;
  deliveryToken: string;
  wakeKeyVerificationHash: string;
  managementKeyVerificationHash: string;
  nonce: string;
  timestamp: string;
  proof: string;
}

export async function enrollment(overrides: Partial<TestEnrollment> = {}, signingHash?: string): Promise<TestEnrollment> {
  const body: TestEnrollment = {
    operation: "enroll", wakeId: "12".repeat(16), userId: USER_ID, transport: "fcm",
    deliveryToken: FCM_TOKEN, wakeKeyVerificationHash: WAKE_HASH,
    managementKeyVerificationHash: MANAGEMENT_HASH, nonce: "ab".repeat(16), timestamp: TIMESTAMP, proof: "",
    ...overrides,
  };
  body.proof = await proof(signingHash ?? body.managementKeyVerificationHash, JSON.stringify([
    "healthmd.wake.manage.v2", body.operation, body.wakeId, body.userId, body.transport,
    body.deliveryToken, body.wakeKeyVerificationHash, body.managementKeyVerificationHash,
    body.nonce, body.timestamp,
  ]));
  return body;
}

export async function ringBody(wakeId: string, nonce: string, hash = WAKE_HASH, timestamp = TIMESTAMP, version = 2) {
  return {
    wakeId, nonce, timestamp,
    hmac: await proof(hash, version === 1 ? "healthmd.wake.v1" + nonce + timestamp
      : JSON.stringify(["healthmd.wake.request.v2", wakeId, nonce, timestamp])),
  };
}

export async function revokeBody(wakeId: string, nonce: string, hash = MANAGEMENT_HASH, userId = USER_ID, timestamp = TIMESTAMP) {
  return { wakeId, userId, nonce, timestamp,
    proof: await proof(hash, JSON.stringify(["healthmd.wake.manage.v2", "revoke", wakeId, userId, nonce, timestamp])),
  };
}
