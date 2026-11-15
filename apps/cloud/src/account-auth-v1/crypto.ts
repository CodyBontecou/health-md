import { AuthError } from "./model";

export type TokenKind = "code" | "access" | "refresh";
const prefixes = { code: "hmd_acode_", access: "hmd_nac_", refresh: "hmd_nrf_" } as const;
export type Entropy = (bytes: number) => Uint8Array;
export const webEntropy: Entropy = (size) => crypto.getRandomValues(new Uint8Array(size));

export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/=/gu, "").replace(/\+/gu, "-").replace(/\//gu, "_");
}
export function randomReference(entropy: Entropy = webEntropy): string {
  const bytes = entropy(32);
  if (!(bytes instanceof Uint8Array) || bytes.length !== 32) throw new AuthError("unavailable");
  return base64url(bytes);
}
export function isReference(value: unknown): value is string {
  // Canonical unpadded encoding of 32 bytes (zero trailing padding bits).
  return typeof value === "string" && /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/u.test(value);
}
export function isToken(value: unknown, kind: TokenKind): value is string {
  return typeof value === "string" && value.startsWith(prefixes[kind]) &&
    isReference(value.slice(prefixes[kind].length));
}
export function newToken(kind: TokenKind, entropy: Entropy): string {
  return prefixes[kind] + randomReference(entropy);
}
export async function s256(verifier: string): Promise<string> {
  if (!/^[A-Za-z0-9._~-]{43,128}$/u.test(verifier)) throw new AuthError("invalid_request");
  return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
}
export async function tokenDigest(token: string, kind: TokenKind): Promise<string> {
  if (!isToken(token, kind)) throw new AuthError("invalid_grant");
  return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256",
    new TextEncoder().encode(`healthmd.account-auth.v1\0${kind}\0${token}`))));
}
export async function purposeRateKey(key: CryptoKey, purpose: string, label: string): Promise<string> {
  return base64url(new Uint8Array(await crypto.subtle.sign("HMAC", key,
    new TextEncoder().encode(`healthmd.account-auth.v1.rate\0${purpose}\0${label}`))));
}
