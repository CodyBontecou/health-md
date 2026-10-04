import { AuthError, isOpaqueAccountId, type NativeSessionResponse, type Registration } from "./model";
import { isReference, isToken } from "./crypto";
import { canonicalScope, client } from "./parsing";

/** In-memory native attempt fence test seam; does not implement OS callbacks or secure storage. */
export class NativeAttempt {
  private pending = true;
  private callbackAccepted = false;
  private readonly expected: {
    registration: Registration; clientId: string; state: string; scope: string; installationId: string;
    generation: number;
  };
  constructor(expected: {
    registration: Registration; clientId: string; state: string; scope: string; installationId: string;
    generation: number;
  }) { this.expected = structuredClone(expected); }
  cancel(): void { this.pending = false; this.callbackAccepted = false; }
  acceptCallback(raw: string, currentGeneration: number): { code: string } | { denied: true } {
    const e = this.expected;
    if (!this.pending || currentGeneration !== e.generation || e.registration.environment !== "synthetic" ||
        !isReference(e.state) || new TextEncoder().encode(raw).length > 4096 ||
        /[%#\u0000-\u0020\u007f]/u.test(raw)) throw new AuthError("invalid_request");
    const parts = raw.split("?");
    if (parts.length !== 2 || parts[0] !== client(e.registration, e.clientId).callback) {
      throw new AuthError("invalid_request");
    }
    const values: Record<string, string> = Object.create(null);
    for (const pair of parts[1]!.split("&")) {
      const p = pair.split("=");
      if (p.length !== 2 || !["code", "error", "state", "iss"].includes(p[0]!) ||
          Object.hasOwn(values, p[0]!)) throw new AuthError("invalid_request");
      values[p[0]!] = p[1]!;
    }
    if (Object.keys(values).length !== 3 || values.state !== e.state || values.iss !== e.registration.issuer ||
        !((isToken(values.code, "code") && !values.error) ||
          (values.error === "access_denied" && !values.code))) throw new AuthError("invalid_request");
    this.pending = false;
    this.callbackAccepted = !!values.code;
    return values.code ? { code: values.code } : { denied: true };
  }
  /** Must be checked AGAIN at the native secure-store commit, not just upon receiving HTTP. */
  acceptSession(response: NativeSessionResponse, currentGeneration: number): void {
    const e = this.expected;
    if (!this.callbackAccepted || currentGeneration !== e.generation ||
        response.issuer !== e.registration.issuer || response.environment !== e.registration.environment ||
        response.audience !== e.registration.audience || response.client_id !== e.clientId ||
        response.installation_id !== e.installationId || response.scope !== canonicalScope(e.scope) ||
        response.token_type !== "Bearer" || !isToken(response.access_token, "access") ||
        !isToken(response.refresh_token, "refresh") || !isReference(response.session_id) ||
        !isOpaqueAccountId(response.account_id) ||
        !Number.isSafeInteger(response.session_generation) || response.session_generation < 0 ||
        !Number.isSafeInteger(response.expires_in) || response.expires_in <= 0 || response.expires_in > 300) {
      throw new AuthError("invalid_grant");
    }
    this.callbackAccepted = false;
  }
}
