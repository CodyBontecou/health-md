import { AuthError, SCOPES, type AuthorizationQuery, type CodeRequest, type RefreshRequest,
  type Registration } from "./model";
import { isReference, isToken } from "./crypto";

export const AUTH_BODY_BYTES = 8192;
const QUERY_KEYS = ["client_id", "redirect_uri", "response_type", "scope", "state", "code_challenge",
  "code_challenge_method", "audience"];
const BAD_TEXT = /[\u0000-\u001f\u007f-\u009f]/u;
function bad(): never { throw new AuthError("invalid_request"); }

/** Tiny bounded JSON grammar: auth objects have string values ONLY. No lossy JSON.parse object pass. */
export function parseAuthObject(bytes: Uint8Array): Record<string, string> {
  if (bytes.byteLength === 0 || bytes.byteLength > AUTH_BODY_BYTES) bad();
  let text: string;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { return bad(); }
  let pos = 0;
  const space = () => { while (/[ \t\r\n]/u.test(text[pos] ?? "x")) pos++; };
  const string = (): string => {
    if (text[pos++] !== '"') bad();
    const start = pos - 1;
    let escaped = false;
    while (pos < text.length) {
      const ch = text[pos++];
      if (escaped) { escaped = false; continue; }
      if (ch === "\\") { escaped = true; continue; }
      if (ch === '"') {
        let value: unknown;
        try { value = JSON.parse(text.slice(start, pos)); } catch { return bad(); }
        if (typeof value !== "string" || value.length > 4096 || BAD_TEXT.test(value) ||
            /[\ud800-\udfff]/u.test(value)) bad();
        return value;
      }
    }
    return bad();
  };
  space();
  if (text[pos++] !== "{") bad();
  space();
  const result: Record<string, string> = Object.create(null);
  if (text[pos] !== "}") {
    while (true) {
      if (Object.keys(result).length >= 12) bad();
      const key = string();
      if (Object.hasOwn(result, key)) bad();
      space();
      if (text[pos++] !== ":") bad();
      space();
      result[key] = string();
      space();
      if (text[pos] === "}") break;
      if (text[pos++] !== ",") bad();
      space();
    }
  }
  if (text[pos++] !== "}") bad();
  space();
  if (pos !== text.length) bad();
  return result;
}
export function exactFields(value: Record<string, string>, keys: readonly string[]): void {
  if (Object.keys(value).length !== keys.length || !keys.every((key) => Object.hasOwn(value, key))) bad();
}
export function canonicalScope(scope: string): string {
  const parts = scope.split(" ");
  if (!parts.length || !parts.every((s) => (SCOPES as readonly string[]).includes(s)) ||
      [...new Set(parts)].sort().join(" ") !== scope ||
      (parts.includes("config:profiles:write") && !parts.includes("config:profiles:read"))) bad();
  return scope;
}
export function client(registration: Registration, id: string) {
  const found = registration.clients.find((c) => c.client_id === id);
  if (!found) throw new AuthError("invalid_request");
  return found;
}
/** Source factory deliberately supports reserved-domain synthetic registrations only. */
export function validateSyntheticRegistration(input: Registration): Registration {
  if (input.environment !== "synthetic" || input.issuer !== "https://account-auth.synthetic.example" ||
      input.audience !== "urn:healthmd:account-config:synthetic:v1" ||
      input.clients.length < 1 || input.clients.length > 5) throw new AuthError("unavailable");
  const names = ["apple-ios", "apple-ipados", "apple-macos", "android-play", "android-fdroid"];
  const seen = new Set<string>();
  const clients = input.clients.map((c) => {
    const name = c.client_id.replace(/^synthetic-/u, "");
    if (!names.includes(name) || seen.has(c.client_id) || c.client_id !== `synthetic-${name}` ||
        c.callback !== `https://callbacks.account-sync.example/${name}/return` ||
        c.platform !== (name.startsWith("apple-") ? "apple" : "android")) throw new AuthError("unavailable");
    seen.add(c.client_id);
    return Object.freeze({ ...c });
  });
  return Object.freeze({ ...input, clients: Object.freeze(clients) });
}
export function parseAuthorization(rawUrl: string, registration: Registration): AuthorizationQuery {
  if (new TextEncoder().encode(rawUrl).length > 4096 || BAD_TEXT.test(rawUrl) || rawUrl.includes("#")) bad();
  const parts = rawUrl.split("?");
  if (parts.length !== 2 || parts[0] !== `${registration.issuer}/account/authorize`) bad();
  const query: Record<string, string> = Object.create(null);
  for (const pair of parts[1]!.split("&")) {
    const fields = pair.split("=");
    if (fields.length !== 2 || !QUERY_KEYS.includes(fields[0]!) || Object.hasOwn(query, fields[0]!)) bad();
    let value: string;
    try { value = decodeURIComponent(fields[1]!.replace(/\+/gu, " ")); } catch { return bad(); }
    if (BAD_TEXT.test(value)) bad();
    query[fields[0]!] = value;
  }
  exactFields(query, QUERY_KEYS);
  if (query.redirect_uri !== client(registration, query.client_id!).callback ||
      query.audience !== registration.audience || query.response_type !== "code" ||
      query.code_challenge_method !== "S256" || !isReference(query.state) || !isReference(query.code_challenge)) bad();
  canonicalScope(query.scope!);
  return { client_id: query.client_id!, redirect_uri: query.redirect_uri!, response_type: "code",
    scope: query.scope!, state: query.state, code_challenge: query.code_challenge,
    code_challenge_method: "S256", audience: query.audience! };
}
export function parseTokenRequest(bytes: Uint8Array): CodeRequest | RefreshRequest {
  const v = parseAuthObject(bytes);
  if (v.grant_type === "authorization_code") {
    exactFields(v, ["grant_type", "client_id", "redirect_uri", "code", "code_verifier", "installation_id"]);
    if (!isToken(v.code, "code") || !/^[A-Za-z0-9._~-]{43,128}$/u.test(v.code_verifier!) ||
        !isReference(v.installation_id)) bad();
    return { grant_type: "authorization_code", client_id: v.client_id!, redirect_uri: v.redirect_uri!,
      code: v.code, code_verifier: v.code_verifier!, installation_id: v.installation_id };
  }
  if (v.grant_type === "refresh_token") {
    exactFields(v, ["grant_type", "client_id", "installation_id", "refresh_token"]);
    if (!isToken(v.refresh_token, "refresh") || !isReference(v.installation_id)) bad();
    return { grant_type: "refresh_token", client_id: v.client_id!, installation_id: v.installation_id,
      refresh_token: v.refresh_token };
  }
  return bad();
}
