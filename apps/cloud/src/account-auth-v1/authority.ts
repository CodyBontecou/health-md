import { AuthError, isOpaqueAccountId, type AccessRow, type AuthState, type AuthStore, type Binding, type BrowserIdentity,
  type ConfigPrincipal, type Family, type NativeSessionResponse, type Pending, type Receipt,
  type Registration, type SessionInventory } from "./model";
import { isReference, newToken, randomReference, s256, tokenDigest, webEntropy, type Entropy } from "./crypto";
import { canonicalScope, client, parseAuthorization, parseTokenRequest, validateSyntheticRegistration } from "./parsing";

export interface SyntheticDependencies {
  registration: Registration;
  store: AuthStore;
  clock: () => number; // seconds; re-read at transaction and verification boundaries
  entropy?: Entropy;
  rateKey: (purpose: "start" | "decision" | "token", label: string) => Promise<string>;
}
const ACCESS_TTL = 300;
const ABSOLUTE_TTL = 30 * 86400;
const IDLE_TTL = 7 * 86400;
function same(a: unknown, b: unknown): boolean { return JSON.stringify(a) === JSON.stringify(b); }

/** Synthetic-only deep lifecycle seam. No environment flags or durable/live adapter factory. */
export class SyntheticNativeAuthority {
  readonly registration: Registration;
  private readonly store: AuthStore;
  private readonly entropy: Entropy;
  private readonly deps: SyntheticDependencies;
  private readonly issuedPrincipals = new WeakMap<object, string>();
  constructor(dependencies: SyntheticDependencies) {
    this.registration = validateSyntheticRegistration(dependencies.registration);
    this.store = dependencies.store;
    this.entropy = dependencies.entropy ?? webEntropy;
    this.deps = { ...dependencies };
  }
  private now(): number {
    const n = this.deps.clock();
    if (!Number.isSafeInteger(n) || n < 0 || n > Number.MAX_SAFE_INTEGER - ABSOLUTE_TTL) {
      throw new AuthError("unavailable");
    }
    return n;
  }
  private browser(state: Readonly<AuthState>, identity: BrowserIdentity, recent = false): boolean {
    const row = state.browsers[identity.sessionId];
    const now = this.now();
    return !!row && isOpaqueAccountId(row.accountId) && row.sessionId === identity.sessionId && row.accountId === identity.accountId &&
      !!state.accounts[row.accountId]?.active && !row.revoked && row.expiresAt > now &&
      (!recent || (row.reauthenticatedAt <= now && row.reauthenticatedAt > now - 300));
  }
  private pendingValid(state: Readonly<AuthState>, p: Pending): boolean {
    return p.issuer === this.registration.issuer && p.environment === this.registration.environment &&
      p.audience === this.registration.audience && p.query.audience === p.audience &&
      p.query.redirect_uri === client(this.registration, p.query.client_id).callback &&
      canonicalScope(p.query.scope) === p.query.scope &&
      this.browser(state, { accountId: p.accountId, sessionId: p.browserId });
  }
  private familyValid(state: Readonly<AuthState>, f: Family): boolean {
    const b = f.binding;
    const now = this.now();
    return isOpaqueAccountId(b.accountId) && b.issuer === this.registration.issuer && b.environment === this.registration.environment &&
      b.audience === this.registration.audience && b.callback === client(this.registration, b.clientId).callback &&
      isReference(b.installationId) && isReference(b.sessionId) && canonicalScope(b.scope) === b.scope &&
      !!state.accounts[b.accountId]?.active && f.revokedAt === null && f.absoluteExpiresAt > now &&
      f.idleExpiresAt > now;
  }
  private accessValid(state: Readonly<AuthState>, a: AccessRow, f: Family): boolean {
    return a.sessionId === f.binding.sessionId && a.expiresAt > this.now() &&
      a.generation >= 0 && a.generation <= f.generation && this.familyValid(state, f);
  }
  private rate(state: AuthState, key: string, limit: number): boolean {
    const window = Math.floor(this.now() / 3600);
    const row = state.rates[key];
    const count = row?.window === window ? row.count : 0;
    state.rates[key] = { window, count: Math.min(limit + 1, count + 1) };
    return count < limit;
  }
  private async key(purpose: "start" | "decision" | "token", label: string): Promise<string> {
    const key = await this.deps.rateKey(purpose, label);
    if (!isReference(key)) throw new AuthError("unavailable");
    return `${purpose}:${key}`;
  }
  /** Always verifies the exact operation marker AND live postconditions on an authoritative snapshot. */
  private async commit<T>(kind: Receipt["kind"], mutate: (s: AuthState, id: string, at: number) => Omit<Receipt, "id" | "kind" | "at">,
    proof: (s: Readonly<AuthState>, r: Receipt) => T): Promise<T> {
    const id = randomReference(this.entropy);
    let expected: Receipt | undefined;
    try {
      await this.store.transact((s) => {
        if (s.receipts[id]) throw new AuthError("unavailable");
        const at = this.now();
        expected = { id, kind, at, ...mutate(s, id, at) };
        s.receipts[id] = expected;
      });
    } catch { /* A commit may have happened. Neither transport success nor failure proves it. */ }
    try {
      return await this.store.read((s) => {
        const receipt = s.receipts[id];
        if (!expected || !receipt || !same(receipt, expected)) throw new AuthError("verification_pending");
        if (receipt.outcome === "reuse_family_revoked") {
          const f = receipt.sessionId && s.families[receipt.sessionId];
          if (!f || f.revokedAt === null || f.binding.accountId !== receipt.accountId) {
            throw new AuthError("verification_pending");
          }
        }
        if (receipt.outcome !== "ok") throw new AuthError(receipt.outcome);
        return proof(s, receipt);
      });
    } catch (error) {
      if (error instanceof AuthError) throw error;
      throw new AuthError("verification_pending");
    }
  }
  async begin(rawUrl: string, identity: BrowserIdentity, trustedRateLabel: string): Promise<{
    authorization_id: string; client_id: string; scope: string; csrf_required: true;
  }> {
    const query = parseAuthorization(rawUrl, this.registration);
    const rate = await this.key("start", `${trustedRateLabel}\0${query.client_id}`);
    const pendingId = randomReference(this.entropy);
    let expected: Pending | undefined;
    return this.commit("begin", (s, _id, now) => {
      if (!this.browser(s, identity)) return { outcome: "unauthorized" };
      if (!this.rate(s, rate, 20)) return { outcome: "rate_limited" };
      if (Object.values(s.pending).filter((p) => p.accountId === identity.accountId &&
          p.query.client_id === query.client_id && !p.consumedBy && p.expiresAt > now).length >= 5) {
        return { outcome: "rate_limited" };
      }
      if (s.pending[pendingId]) return { outcome: "unavailable" };
      expected = { id: pendingId, query, accountId: identity.accountId, browserId: identity.sessionId,
        issuer: this.registration.issuer, environment: this.registration.environment,
        audience: this.registration.audience, consentPolicy: "source-v1", createdAt: now,
        expiresAt: now + 300, consumedBy: null };
      s.pending[pendingId] = expected;
      return { outcome: "ok", accountId: identity.accountId, pendingId };
    }, (s) => {
      const p = s.pending[pendingId];
      if (!p || !same(p, expected) || !this.pendingValid(s, p) || p.expiresAt <= this.now() || p.consumedBy) {
        throw new AuthError("verification_pending");
      }
      return { authorization_id: pendingId, client_id: query.client_id, scope: query.scope, csrf_required: true };
    });
  }
  async decide(authorizationId: string, decision: string, identity: BrowserIdentity): Promise<{ callback: string }> {
    if (!isReference(authorizationId) || !["approve", "deny"].includes(decision)) throw new AuthError("invalid_request");
    const pendingClient = await this.read((s) => s.pending[authorizationId]?.query.client_id);
    if (!pendingClient) throw new AuthError("invalid_grant");
    const rate = await this.key("decision", `${identity.accountId}\0${pendingClient}`);
    const code = newToken("code", this.entropy);
    const digest = await tokenDigest(code, "code");
    let pExpected: Pending | undefined;
    return this.commit("decision", (s, id, now) => {
      const p = s.pending[authorizationId];
      if (!p || p.query.client_id !== pendingClient || p.consumedBy || p.expiresAt <= now || p.accountId !== identity.accountId ||
          p.browserId !== identity.sessionId || !this.pendingValid(s, p) || !this.browser(s, identity)) {
        return { outcome: "invalid_grant" };
      }
      if (!this.rate(s, rate, 5)) return { outcome: "rate_limited" };
      if (s.codes[digest]) return { outcome: "unavailable" };
      p.consumedBy = id;
      pExpected = structuredClone(p);
      if (decision === "approve") s.codes[digest] = { digest, pendingId: p.id, expiresAt: now + 120, consumedBy: null };
      return { outcome: "ok", pendingId: p.id, accountId: p.accountId, ...(decision === "approve" ? { digest } : {}) };
    }, (s, r) => {
      const p = s.pending[authorizationId];
      const c = s.codes[digest];
      if (!p || !same(p, pExpected) || !this.pendingValid(s, p) ||
          (decision === "approve" && (!c || c.pendingId !== p.id || c.expiresAt !== r.at + 120 ||
            c.consumedBy || c.expiresAt <= this.now()))) throw new AuthError("verification_pending");
      return { callback: `${p.query.redirect_uri}?${decision === "approve" ? `code=${code}` : "error=access_denied"}` +
        `&state=${p.query.state}&iss=${p.issuer}` };
    });
  }
  private response(f: Family, access: string, refresh: string, expiresAt: number): NativeSessionResponse {
    const b = f.binding;
    const expiresIn = expiresAt - this.now();
    if (expiresIn <= 0) throw new AuthError("invalid_grant");
    return { token_type: "Bearer", access_token: access, expires_in: expiresIn, refresh_token: refresh,
      session_id: b.sessionId, scope: b.scope, issuer: b.issuer, environment: b.environment,
      audience: b.audience, client_id: b.clientId, installation_id: b.installationId,
      account_id: b.accountId, session_generation: f.generation };
  }
  async token(bytes: Uint8Array): Promise<NativeSessionResponse> {
    const req = parseTokenRequest(bytes);
    client(this.registration, req.client_id);
    const rate = await this.key("token", `${req.client_id}\0${req.installation_id}`);
    const access = newToken("access", this.entropy);
    const refresh = newToken("refresh", this.entropy);
    const ad = await tokenDigest(access, "access"), rd = await tokenDigest(refresh, "refresh");
    const digest = await tokenDigest(req.grant_type === "authorization_code" ? req.code : req.refresh_token,
      req.grant_type === "authorization_code" ? "code" : "refresh");
    const challenge = req.grant_type === "authorization_code" ? await s256(req.code_verifier) : null;
    const newSessionId = randomReference(this.entropy);
    let expectedFamily: Family | undefined;
    const kind = req.grant_type === "authorization_code" ? "exchange" : "refresh";
    return this.commit(kind, (s, id, now) => {
      if (!this.rate(s, rate, 30)) return { outcome: "rate_limited" };
      if (s.access[ad] || s.refresh[rd]) return { outcome: "unavailable" };
      let f: Family;
      if (req.grant_type === "authorization_code") {
        const c = s.codes[digest], p = c && s.pending[c.pendingId];
        if (!c || !p || !p.consumedBy || c.consumedBy || c.expiresAt <= now ||
            !this.pendingValid(s, p) || p.query.client_id !== req.client_id ||
            p.query.redirect_uri !== req.redirect_uri || p.query.code_challenge !== challenge) {
          return { outcome: "invalid_grant" };
        }
        const active = Object.values(s.families).filter((row) => row.binding.accountId === p.accountId &&
          row.revokedAt === null && row.absoluteExpiresAt > now && row.idleExpiresAt > now);
        if (active.length >= 20) return { outcome: "rate_limited" };
        if (s.families[newSessionId]) return { outcome: "unavailable" };
        const binding: Binding = { issuer: p.issuer, environment: p.environment, audience: p.audience,
          accountId: p.accountId, clientId: req.client_id, callback: req.redirect_uri,
          installationId: req.installation_id, sessionId: newSessionId, scope: p.query.scope };
        f = { binding, createdAt: now, absoluteExpiresAt: now + ABSOLUTE_TTL,
          idleExpiresAt: now + IDLE_TTL, generation: 0, revokedAt: null };
        c.consumedBy = id;
        s.families[newSessionId] = f;
      } else {
        const parent = s.refresh[digest], row = parent && s.families[parent.sessionId];
        if (!parent || !row || row.binding.clientId !== req.client_id ||
            row.binding.installationId !== req.installation_id || !this.familyValid(s, row)) {
          return { outcome: "invalid_grant" };
        }
        if (parent.spentBy !== null || parent.generation !== row.generation) {
          row.revokedAt = now;
          return { outcome: "reuse_family_revoked", sessionId: row.binding.sessionId,
            accountId: row.binding.accountId, digest };
        }
        parent.spentBy = id;
        row.generation++;
        row.idleExpiresAt = Math.min(row.absoluteExpiresAt, now + IDLE_TTL);
        f = row;
      }
      const sessionId = f.binding.sessionId;
      expectedFamily = structuredClone(f);
      s.access[ad] = { digest: ad, sessionId, generation: f.generation,
        expiresAt: Math.min(now + ACCESS_TTL, f.absoluteExpiresAt, f.idleExpiresAt) };
      s.refresh[rd] = { digest: rd, sessionId, generation: f.generation, spentBy: null };
      return { outcome: "ok", accountId: f.binding.accountId, sessionId, digest, accessDigest: ad, refreshDigest: rd };
    }, (s, r) => {
      const f = r.sessionId && s.families[r.sessionId], a = s.access[ad], child = s.refresh[rd];
      const consumed = req.grant_type === "authorization_code" ? s.codes[digest]?.consumedBy : s.refresh[digest]?.spentBy;
      if (!f || !same(f, expectedFamily) || !a || !this.accessValid(s, a, f) || !child ||
          child.sessionId !== r.sessionId || child.generation !== f.generation || child.spentBy || consumed !== r.id ||
          a.digest !== ad || child.digest !== rd || a.generation !== f.generation ||
          a.expiresAt !== Math.min(r.at + ACCESS_TTL, f.absoluteExpiresAt, f.idleExpiresAt)) {
        throw new AuthError("verification_pending");
      }
      return this.response(f, access, refresh, a.expiresAt);
    });
  }
  private async read<T>(inspect: (s: Readonly<AuthState>) => T): Promise<T> {
    try { return await this.store.read(inspect); }
    catch (error) { if (error instanceof AuthError) throw error; throw new AuthError("verification_pending"); }
  }
  async authenticate(accessToken: string, requiredScopes: readonly string[]): Promise<ConfigPrincipal> {
    const digest = await tokenDigest(accessToken, "access");
    return this.read((s) => {
      const a = s.access[digest], f = a && s.families[a.sessionId];
      if (!a || !f || !this.accessValid(s, a, f)) throw new AuthError("unauthorized");
      if (!requiredScopes.every((scope) => f.binding.scope.split(" ").includes(scope))) throw new AuthError("forbidden");
      const p: ConfigPrincipal = Object.freeze({ issuer: f.binding.issuer, environment: f.binding.environment,
        audience: f.binding.audience, accountId: f.binding.accountId, sessionId: f.binding.sessionId,
        clientId: f.binding.clientId, installationId: f.binding.installationId, scope: f.binding.scope,
        sessionGeneration: f.generation });
      this.issuedPrincipals.set(p, digest);
      return p;
    });
  }
  /** Authentication only; deliberately grants NO transfer or opt-in. No profile parser/storage is installed. */
  private configScopes(method: string, exactPath: string): readonly string[] {
    if (method !== "POST" || !["/api/profile-sync/v1/read", "/api/profile-sync/v1/mutate"].includes(exactPath)) {
      throw new AuthError("forbidden");
    }
    return exactPath.endsWith("/mutate") ? ["config:profiles:read", "config:profiles:write"] : ["config:profiles:read"];
  }
  async authorizeConfig(accessToken: string, method: string, exactPath: string): Promise<ConfigPrincipal> {
    return this.authenticate(accessToken, this.configScopes(method, exactPath));
  }
  /** Future transfer handlers MUST recheck this inside their own authoritative mutation transaction. */
  assertConfigAtCommit(s: Readonly<AuthState>, principal: ConfigPrincipal, method: string, exactPath: string): void {
    const digest = this.issuedPrincipals.get(principal);
    const a = digest && s.access[digest];
    const f = s.families[principal.sessionId];
    if (!a || !f || !this.accessValid(s, a, f) ||
        principal.accountId !== f.binding.accountId || principal.issuer !== f.binding.issuer ||
        principal.environment !== f.binding.environment || principal.audience !== f.binding.audience ||
        principal.clientId !== f.binding.clientId || principal.installationId !== f.binding.installationId ||
        principal.scope !== f.binding.scope || principal.sessionGeneration !== f.generation ||
        !this.configScopes(method, exactPath).every((scope) => principal.scope.split(" ").includes(scope))) {
      throw new AuthError("unauthorized");
    }
  }
  private inventory(f: Family, current: boolean): SessionInventory {
    return { session_id: f.binding.sessionId, client_id: f.binding.clientId,
      platform: client(this.registration, f.binding.clientId).platform, created_at: f.createdAt,
      expires_at: Math.min(f.absoluteExpiresAt, f.idleExpiresAt), revoked: f.revokedAt !== null, current };
  }
  async nativeSessions(accessToken: string): Promise<SessionInventory[]> {
    const digest = await tokenDigest(accessToken, "access");
    return this.read((s) => {
      const a = s.access[digest], f = a && s.families[a.sessionId];
      if (!a || !f || !this.accessValid(s, a, f) || !f.binding.scope.split(" ").includes("account:sessions:read")) {
        throw new AuthError("unauthorized");
      }
      return [this.inventory(f, true)];
    });
  }
  async browserSessions(identity: BrowserIdentity): Promise<SessionInventory[]> {
    return this.read((s) => {
      if (!this.browser(s, identity, true)) throw new AuthError("unauthorized");
      return Object.values(s.families).filter((f) => f.binding.accountId === identity.accountId)
        .sort((a, b) => b.createdAt - a.createdAt || a.binding.sessionId.localeCompare(b.binding.sessionId))
        .slice(0, 20).map((f) => this.inventory(f, false));
    });
  }
  async revoke(proof: { kind: "access"; token: string } |
    { kind: "refresh"; token: string; clientId: string; installationId: string } |
    { kind: "browser"; identity: BrowserIdentity; sessionId: string }): Promise<{ revoked: true }> {
    const digest = proof.kind === "browser" ? undefined : await tokenDigest(proof.token, proof.kind);
    if (proof.kind === "browser" && !isReference(proof.sessionId)) throw new AuthError("not_found");
    return this.commit("revoke", (s, _id, now) => {
      let f: Family | undefined;
      if (proof.kind === "browser") {
        if (!this.browser(s, proof.identity, true)) return { outcome: "unauthorized" };
        f = s.families[proof.sessionId];
        if (!f || f.binding.accountId !== proof.identity.accountId) return { outcome: "not_found" };
      } else {
        const row = proof.kind === "access" ? s.access[digest!] : s.refresh[digest!];
        f = row && s.families[row.sessionId];
        if (!f || !s.accounts[f.binding.accountId]?.active ||
            f.binding.issuer !== this.registration.issuer || f.binding.environment !== this.registration.environment ||
            f.binding.audience !== this.registration.audience) return { outcome: "unauthorized" };
        if (proof.kind === "access") {
          const a = s.access[digest!]!;
          // Allow idempotent self-revoke of a revoked family, not expired access.
          if (a.expiresAt <= now || !f.binding.scope.split(" ").includes("account:sessions:revoke:self")) {
            return { outcome: "unauthorized" };
          }
        } else if (f.binding.clientId !== proof.clientId || f.binding.installationId !== proof.installationId ||
            f.absoluteExpiresAt <= now) return { outcome: "unauthorized" };
      }
      f.revokedAt ??= now;
      return { outcome: "ok", accountId: f.binding.accountId, sessionId: f.binding.sessionId };
    }, (s, r) => {
      const f = r.sessionId && s.families[r.sessionId];
      if (!f || f.binding.accountId !== r.accountId || f.revokedAt === null) throw new AuthError("verification_pending");
      return { revoked: true };
    });
  }
}
