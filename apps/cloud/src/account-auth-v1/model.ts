export const SCOPES = ["account:sessions:read", "account:sessions:revoke:self",
  "config:profiles:read", "config:profiles:write"] as const;
export type Scope = typeof SCOPES[number];
export type AuthFailure = "unavailable" | "invalid_request" | "invalid_grant" | "unauthorized" |
  "forbidden" | "not_found" | "rate_limited" | "verification_pending" | "reuse_family_revoked";
export class AuthError extends Error {
  constructor(readonly code: AuthFailure) { super("Account authorization could not be completed."); }
}
export interface Registration {
  readonly issuer: string;
  readonly environment: "synthetic";
  readonly audience: string;
  readonly clients: readonly { readonly client_id: string; readonly platform: "apple" | "android";
    readonly callback: string }[];
}
export interface AuthorizationQuery {
  client_id: string; redirect_uri: string; response_type: "code"; scope: string;
  state: string; code_challenge: string; code_challenge_method: "S256"; audience: string;
}
export interface CodeRequest {
  grant_type: "authorization_code"; client_id: string; redirect_uri: string;
  code: string; code_verifier: string; installation_id: string;
}
export interface RefreshRequest {
  grant_type: "refresh_token"; client_id: string; installation_id: string; refresh_token: string;
}
/** Existing server-owned opaque UUID, or an explicitly synthetic sentinel. Never an email/provider/session ID. */
export function isOpaqueAccountId(value: unknown): value is string {
  return typeof value === "string" && (/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/u.test(value) ||
    /^synthetic-account-[a-z0-9]{1,32}$/u.test(value));
}
export interface BrowserIdentity { accountId: string; sessionId: string }
export interface BrowserRow extends BrowserIdentity {
  expiresAt: number; revoked: boolean; reauthenticatedAt: number;
}
export interface Pending {
  id: string; query: AuthorizationQuery; accountId: string; browserId: string;
  issuer: string; environment: string; audience: string; consentPolicy: "source-v1";
  createdAt: number; expiresAt: number; consumedBy: string | null;
}
export interface CodeRow {
  digest: string; pendingId: string; expiresAt: number; consumedBy: string | null;
}
export interface Binding {
  issuer: string; environment: string; audience: string; accountId: string;
  clientId: string; callback: string; installationId: string; sessionId: string; scope: string;
}
export interface Family {
  binding: Binding; createdAt: number; absoluteExpiresAt: number; idleExpiresAt: number;
  generation: number; revokedAt: number | null;
}
export interface AccessRow { digest: string; sessionId: string; generation: number; expiresAt: number }
export interface RefreshRow { digest: string; sessionId: string; generation: number; spentBy: string | null }
export interface Receipt {
  id: string; kind: "begin" | "decision" | "exchange" | "refresh" | "revoke";
  outcome: "ok" | AuthFailure; at: number; accountId?: string;
  pendingId?: string; sessionId?: string; digest?: string; accessDigest?: string; refreshDigest?: string;
}
export interface AuthState {
  accounts: Record<string, { active: boolean }>;
  browsers: Record<string, BrowserRow>;
  pending: Record<string, Pending>;
  codes: Record<string, CodeRow>;
  families: Record<string, Family>;
  access: Record<string, AccessRow>;
  refresh: Record<string, RefreshRow>;
  // Fixed-event operation markers commit with mutations; no secret values.
  receipts: Record<string, Receipt>;
  rates: Record<string, { window: number; count: number }>;
}
export function emptyAuthState(): AuthState {
  return { accounts: {}, browsers: {}, pending: {}, codes: {}, families: {}, access: {}, refresh: {},
    receipts: {}, rates: {} };
}
/**
 * Authoritative, linearizable adapter contract, NOT a production implementation.
 * transact must execute the synchronous callback once under an exclusive transaction,
 * commit all state plus receipt/audit atomically, or roll back all state. Do not retry
 * callbacks, cache reads, replace another writer's snapshot, or drop spent digests.
 * read is a fresh authoritative consistent snapshot (including account/browser state).
 * Lost commit replies may throw. Successful returns/change counts are never proof.
 * Account disable/deletion must serialize through the SAME authority as these calls.
 */
export interface AuthStore {
  transact(change: (state: AuthState) => void): Promise<void>;
  read<T>(inspect: (state: Readonly<AuthState>) => T): Promise<T>;
}
export interface NativeSessionResponse {
  token_type: "Bearer"; access_token: string; expires_in: number; refresh_token: string;
  session_id: string; scope: string; issuer: string; environment: string; audience: string;
  client_id: string; installation_id: string; account_id: string; session_generation: number;
}
export interface ConfigPrincipal {
  readonly issuer: string; readonly environment: string; readonly audience: string;
  readonly accountId: string; readonly sessionId: string; readonly clientId: string;
  readonly installationId: string; readonly scope: string; readonly sessionGeneration: number;
}
export interface SessionInventory {
  session_id: string; client_id: string; platform: string; created_at: number;
  expires_at: number; revoked: boolean; current: boolean;
}
