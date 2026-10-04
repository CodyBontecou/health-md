import { afterEach, describe, expect, it } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SyntheticNativeAuthority } from "../src/account-auth-v1/authority";
import { getSession, requireIngestToken } from "../src/auth";
import { authenticateReadToken } from "../mcp/auth";
import type { Env } from "../src/types";
import { NativeAttempt } from "../src/account-auth-v1/callback";
import { newToken, purposeRateKey, randomReference, s256, tokenDigest, webEntropy } from "../src/account-auth-v1/crypto";
import { createNativeAuthHttp } from "../src/account-auth-v1/http";
import { AuthError, emptyAuthState, type AuthState, type AuthStore, type BrowserIdentity,
  type NativeSessionResponse, type Registration } from "../src/account-auth-v1/model";
import { parseAuthObject, parseAuthorization, parseTokenRequest } from "../src/account-auth-v1/parsing";

const policy: { environments: { synthetic: Omit<Registration, "environment"> }; scopes: string[];
  native_denied_operations: { method: string; path: string }[]; credential_kinds: string[] } =
  JSON.parse(readFileSync(new URL("../../../packages/contracts/account-auth/v1/source-policy.json", import.meta.url), "utf8"));
const registration: Registration = { ...policy.environments.synthetic, environment: "synthetic" };
const vectors: {
  callback_vectors: { id: string; uri: string; expected: string; context?: {
    environment?: string; client_id?: string; pending?: boolean; generation_matches?: boolean } }[];
  authorization_vectors: { id: string; patch?: Record<string, string>; remove?: string[]; expected: string }[];
  exchange_vectors: { id: string; patch?: Record<string, boolean | number>; expected: string }[];
  authority_vectors: { id: string; route: string; expected: string;
    principal?: Record<string, unknown>; request?: Record<string, unknown> }[];
  lifecycle_vectors: { id: string; steps: { op: string; expected: string; token?: string;
    verified?: boolean; installation_matches?: boolean; scope_expansion?: boolean }[] }[];
} = JSON.parse(readFileSync(new URL("../../../packages/contracts/account-auth/v1/fixtures/security-vectors.json", import.meta.url), "utf8"));
const identity: BrowserIdentity = { accountId: "synthetic-account-a", sessionId: "synthetic-browser-a" };
const foreign: BrowserIdentity = { accountId: "synthetic-account-b", sessionId: "synthetic-browser-b" };
const encoder = new TextEncoder();
const bytes = (v: unknown) => encoder.encode(JSON.stringify(v));
const roots: string[] = [];
const connections: DatabaseSync[] = [];
afterEach(() => { for (const db of connections.splice(0)) db.close(); for (const root of roots.splice(0)) rmSync(root, { recursive: true }); });

type Fault = "lost" | "noop" | "before" | "rollback" | "receipt-only" | "no-receipt";
/** Real private ephemeral SQLite, two connections, SQL transactions and fault injection; NOT a live adapter. */
class TransactionalSqlite implements AuthStore {
  fault: Fault | undefined;
  unreadable = false;
  afterCommit: (() => void) | undefined;
  constructor(readonly db: DatabaseSync) {}
  private load(): AuthState {
    const row = this.db.prepare("SELECT body FROM synthetic_state WHERE id=1").get() as { body: string };
    return JSON.parse(row.body) as AuthState;
  }
  async transact(change: (state: AuthState) => void): Promise<void> {
    const fault = this.fault; this.fault = undefined;
    if (fault === "before") throw new Error("synthetic before commit");
    this.db.exec("BEGIN IMMEDIATE");
    let committed = false;
    try {
      const prior = this.load();
      const state = structuredClone(prior);
      change(state);
      if (fault === "rollback") throw new Error("synthetic rollback");
      if (fault === "receipt-only") {
        prior.receipts = state.receipts;
        this.db.prepare("UPDATE synthetic_state SET body=? WHERE id=1").run(JSON.stringify(prior));
      } else if (fault !== "noop") {
        if (fault === "no-receipt") state.receipts = prior.receipts;
        this.db.prepare("UPDATE synthetic_state SET body=? WHERE id=1").run(JSON.stringify(state));
      }
      this.db.exec("COMMIT"); committed = true;
    } catch (error) {
      if (!committed) this.db.exec("ROLLBACK");
      throw error;
    }
    const hook = this.afterCommit; this.afterCommit = undefined; hook?.();
    if (fault === "lost") throw new Error("synthetic lost commit reply");
  }
  async read<T>(inspect: (state: Readonly<AuthState>) => T): Promise<T> {
    if (this.unreadable) throw new Error("synthetic unreadable proof");
    return inspect(this.load());
  }
}
async function harness() {
  const root = mkdtempSync(join(tmpdir(), "healthmd-as02-synthetic-")); roots.push(root);
  const path = join(root, "synthetic.sqlite");
  const connect = () => {
    const db = new DatabaseSync(path); connections.push(db);
    db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000;");
    return db;
  };
  const db = connect();
  db.exec("CREATE TABLE synthetic_state (id INTEGER PRIMARY KEY CHECK(id=1), body TEXT NOT NULL CHECK(json_valid(body))) STRICT;");
  let now = 100_000;
  const state = emptyAuthState();
  state.accounts[identity.accountId] = { active: true }; state.accounts[foreign.accountId] = { active: true };
  for (const b of [identity, foreign]) state.browsers[b.sessionId] = { ...b, expiresAt: now + 1_000_000,
    revoked: false, reauthenticatedAt: now };
  db.prepare("INSERT INTO synthetic_state VALUES(1,?)").run(JSON.stringify(state));
  const store = new TransactionalSqlite(db), peer = new TransactionalSqlite(connect());
  const key = await crypto.subtle.generateKey({ name: "HMAC", hash: "SHA-256", length: 256 }, false, ["sign"]);
  const makeAuthority = (storage: AuthStore) => new SyntheticNativeAuthority({ registration, store: storage,
    clock: () => now, rateKey: (purpose, label) => purposeRateKey(key, purpose, label) });
  const authority = makeAuthority(store), other = makeAuthority(peer);
  const http = createNativeAuthHttp({ authority, rateLabel: () => "synthetic-address",
    browser: { verify: async (request, requirements) => {
      if (requirements.csrf && request.headers.get("X-HealthMd-CSRF") !== "synthetic-csrf") return null;
      return request.headers.get("Cookie") === "synthetic-browser=a" ? identity :
        request.headers.get("Cookie") === "synthetic-browser=b" ? foreign : null;
    } } });
  const installation = randomReference();
  const verifier = randomReference();
  const challenge = await s256(verifier);
  const stateRef = randomReference();
  const query = { client_id: "synthetic-apple-ios", redirect_uri: registration.clients[0]!.callback,
    response_type: "code", scope: policy.scopes.join(" "), state: stateRef, code_challenge: challenge,
    code_challenge_method: "S256", audience: registration.audience };
  const queryUrl = (q: Record<string, string> = query) => `${registration.issuer}/account/authorize?${new URLSearchParams(q)}`;
  const codeRequest = (code: string) => ({ grant_type: "authorization_code", client_id: query.client_id,
    redirect_uri: query.redirect_uri, code, code_verifier: verifier, installation_id: installation });
  const refreshRequest = (session: NativeSessionResponse) => ({ grant_type: "refresh_token",
    client_id: session.client_id, installation_id: session.installation_id, refresh_token: session.refresh_token });
  const consent = async (owner = identity, q = query) => {
    const begin = await authority.begin(queryUrl(q), owner, "synthetic-address");
    const result = await authority.decide(begin.authorization_id, "approve", owner);
    const code = new URL(result.callback).searchParams.get("code")!;
    return { code, begin, callback: result.callback };
  };
  const issue = async (owner = identity) => authority.token(bytes(codeRequest((await consent(owner)).code)));
  const request = (path: string, method = "GET", body?: unknown, headers?: Record<string, string>) =>
    new Request(`${registration.issuer}${path}`, { method, headers: {
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}), ...headers },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
  const browserHeaders = { Cookie: "synthetic-browser=a", Origin: registration.issuer, "X-HealthMd-CSRF": "synthetic-csrf" };
  return { authority, other, store, peer, http, query, queryUrl, codeRequest, refreshRequest, consent, issue,
    installation, verifier, challenge, stateRef, request, browserHeaders, advance: (seconds: number) => { now += seconds; },
    now: () => now };
}
async function failure(promise: Promise<unknown>, code?: string): Promise<void> {
  try { await promise; throw new Error("Expected denial"); }
  catch (error) { expect(error instanceof AuthError).toBe(true); if (code) expect((error as AuthError).code).toBe(code); }
}

describe("AS01 vectors at the actual TypeScript boundary", () => {
  it.each(vectors.callback_vectors)("callback $id", async (v) => {
    const h = await harness();
    const code = newToken("code", webEntropy), refresh = newToken("refresh", webEntropy);
    const context = v.context ?? {};
    const r = { ...registration, environment: context.environment ?? "synthetic" } as Registration;
    const attempt = new NativeAttempt({ registration: r, clientId: context.client_id ?? h.query.client_id,
      state: h.stateRef, scope: h.query.scope, installationId: h.installation, generation: 7 });
    if (context.pending === false) attempt.cancel();
    const uri = v.uri.replaceAll("{callback}", h.query.redirect_uri).replaceAll("{code}", code)
      .replaceAll("{refresh}", refresh).replaceAll("{state}", h.stateRef).replaceAll("{issuer}", registration.issuer);
    if (v.expected === "deny") expect(() => attempt.acceptCallback(uri, context.generation_matches === false ? 8 : 7)).toThrow(AuthError);
    else {
      const result = attempt.acceptCallback(uri, 7);
      expect("code" in result ? "accept_code" : "accept_denial").toBe(v.expected);
      expect(() => attempt.acceptCallback(uri, 7)).toThrow(AuthError);
    }
  });
  it.each(vectors.authorization_vectors)("authorization $id", async (v) => {
    const h = await harness(); const q: Record<string, string> = { ...h.query, ...(v.patch ?? {}) };
    for (const key of v.remove ?? []) delete q[key];
    if (v.expected === "allow") expect(parseAuthorization(h.queryUrl(q), registration).response_type).toBe("code");
    else expect(() => parseAuthorization(h.queryUrl(q), registration)).toThrow(AuthError);
  });
  it.each(vectors.exchange_vectors)("exchange $id", async (v) => {
    const h = await harness(); const c = await h.consent(); const req = h.codeRequest(c.code); const p = v.patch ?? {};
    if (p.verifier_matches === false) req.code_verifier = randomReference();
    if (p.client_matches === false) req.client_id = "synthetic-android-play";
    if (p.callback_matches === false) req.redirect_uri = "https://evil.example/return";
    if (p.installation_present === false) req.installation_id = "";
    if (p.code_unused === false) await h.authority.token(bytes(req));
    if (p.expires_at === 100) h.advance(120);
    await h.store.transact((s) => {
      const pending = s.pending[c.begin.authorization_id]!;
      if (p.environment_matches === false) pending.environment = "staging";
      if (p.audience_matches === false) pending.audience = "urn:healthmd:wrong";
      if (p.account_active === false) s.accounts[identity.accountId]!.active = false;
      if (p.consent_account_matches === false) s.browsers[identity.sessionId]!.accountId = foreign.accountId;
    });
    if (v.expected === "allow") expect((await h.authority.token(bytes(req))).expires_in).toBe(300);
    else await failure(h.authority.token(bytes(req)));
  });
});

describe("AS01 resource authority vectors (authentication seam, NOT configuration transfer)", () => {
  // Browser configuration consent/privacy/selection is owned by later config handlers, not this native seam.
  const applicable = vectors.authority_vectors.filter((v) => v.id !== "browser_explicit_config");
  it.each(applicable)("authority $id", async (v) => {
    const h = await harness(); const s = await h.issue();
    const p = v.principal ?? {}, r = v.request ?? {};
    await h.store.transact((state) => {
      const family = state.families[s.session_id]!;
      if (p.audience) family.binding.audience = String(p.audience);
      if (p.environment) family.binding.environment = String(p.environment);
      if (p.issuer) family.binding.issuer = String(p.issuer);
      if (p.client_id) family.binding.clientId = String(p.client_id);
      if (p.scopes) family.binding.scope = (p.scopes as string[]).join(" ");
      if (p.revoked) family.revokedAt = h.now();
      if (p.account_active === false) state.accounts[identity.accountId]!.active = false;
      if (p.expires_at === 100) for (const access of Object.values(state.access)) access.expiresAt = 100;
      if (r.recent_reauthentication === false) state.browsers[identity.sessionId]!.reauthenticatedAt = 0;
    });
    let operation: Promise<unknown>;
    if (r.target_account) {
      operation = h.authority.authorizeConfig(s.access_token, "POST", "/api/profile-sync/v1/read").then((principal) =>
        h.store.read((state) => h.authority.assertConfigAtCommit(state, { ...principal, accountId: String(r.target_account) },
          "POST", "/api/profile-sync/v1/read")));
    } else if (p.kind === "browser_session") {
      const headers = { ...h.browserHeaders };
      if (r.origin === null) delete (headers as Partial<typeof headers>).Origin;
      else if (r.origin) headers.Origin = String(r.origin);
      if (r.csrf_verified === false) delete (headers as Partial<typeof headers>)["X-HealthMd-CSRF"];
      const c = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
      operation = h.http(h.request(v.route === "revoke" ? "/api/account-auth/v1/revoke" : "/api/account-auth/v1/decision",
        "POST", v.route === "revoke" ? { session_id: s.session_id } :
          { authorization_id: c.authorization_id, decision: "approve" }, headers)).then((response) => {
        if (response.status >= 400) throw new AuthError("forbidden");
      });
    } else if (r.config_opt_in === false || r.privacy_policy_present === false || r.sync_enabled === false ||
        r.environment === "production" || r.service_profile || r.auth_enabled === false) {
      // No privacy/config handler exists: even an authenticated request cannot transfer data by default.
      const handler = r.auth_enabled === false ? createNativeAuthHttp() : h.http;
      operation = handler(h.request(v.route === "sessions" ? "/api/account-auth/v1/sessions" : "/api/profile-sync/v1/read",
        v.route === "sessions" ? "GET" : "POST", undefined,
        { Authorization: `Bearer ${s.access_token}` })).then((response) => {
        if (response.status >= 400) throw new AuthError("unavailable");
      });
    } else if (r.mixed_credentials) {
      operation = h.http(h.request("/api/account-auth/v1/sessions", "GET", undefined,
        { ...h.browserHeaders, Authorization: `Bearer ${s.access_token}` })).then((response) => {
        if (response.status >= 400) throw new AuthError("unauthorized");
      });
    } else if (v.route === "sessions" && r.target_session) {
      operation = h.http(h.request("/api/account-auth/v1/sessions?session_id=synthetic-other", "GET", undefined,
        { Authorization: `Bearer ${s.access_token}` })).then((response) => {
        if (response.status >= 400) throw new AuthError("invalid_request");
      });
    } else if (v.route === "sessions") operation = h.authority.nativeSessions(s.access_token);
    else if (v.route === "revoke" && r.target_session) {
      operation = h.http(h.request("/api/account-auth/v1/revoke", "POST", p.kind === "native_refresh" ?
        { refresh_token: s.refresh_token, client_id: s.client_id, installation_id: s.installation_id,
          session_id: r.target_session } : { session_id: r.target_session }, p.kind === "native_refresh" ? undefined :
          { Authorization: `Bearer ${s.access_token}` })).then((response) => {
        if (response.status >= 400) throw new AuthError("invalid_request");
      });
    } else if (v.route === "revoke") operation = p.kind === "native_refresh" ?
      h.authority.revoke({ kind: "refresh", token: s.refresh_token, clientId: s.client_id, installationId: s.installation_id }) :
      h.authority.revoke({ kind: "access", token: s.access_token });
    else {
      const foreignTokens: Record<string, string> = { native_refresh: s.refresh_token,
        authorization_code: newToken("code", webEntropy), ingest_token: `hmd_ing_${randomReference()}`,
        repair_device: `hmd_dev_${randomReference()}`, mcp_read_full_export: `hmd_read_${randomReference()}` };
      const token = p.kind ? foreignTokens[String(p.kind)]! : s.access_token;
      const path = String(r.path ?? (v.route === "config_write" ? "/api/profile-sync/v1/mutate" : "/api/profile-sync/v1/read"));
      operation = h.authority.authorizeConfig(token, String(r.method ?? "POST"), path + (r.query ? `?${r.query}` : ""));
    }
    if (v.expected === "allow") expect(await operation).toBeDefined();
    else await failure(operation);
  });
  it("keeps browser config explicitly unavailable until a separate reviewed privacy/opt-in handler", async () => {
    const vector = vectors.authority_vectors.find((v) => v.id === "browser_explicit_config")!;
    expect(vector.expected).toBe("allow"); // AS01's conditional future capability; not implemented/claimed here.
    const h = await harness();
    expect((await h.http(h.request("/api/profile-sync/v1/read", "POST", {}, h.browserHeaders))).status).toBe(404);
  });
});

describe("closed parser / cryptography / registration", () => {
  it("uses real RFC7636 S256, random 256-bit secrets and purpose-separated digests", async () => {
    expect(await s256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")).toBe("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    const code = newToken("code", webEntropy);
    const digest = await tokenDigest(code, "code");
    const plain = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(code)));
    expect(digest.length).toBe(43); expect(digest === Buffer.from(plain).toString("base64url")).toBe(false);
    await failure(tokenDigest(code, "access"));
    const values = Array.from({ length: 50 }, () => randomReference());
    expect(new Set(values).size).toBe(50);
  });
  it.each([
    '{"a":"x","a":"y"}', '{"a":"x","\\u0061":"y"}', '{"a":true}', '{"a":null}',
    '{"a":1}', '{"a":{}}', '{"a":[]}', '{"a":"\\u0000"}', '{"a":"\\ud800"}',
    '{"a":"x",}', '{"a":"x"}{}', '{a:"x"}', '[]', '{"a":"\\x01"}',
  ])("rejects malformed/duplicate/nested/non-string auth JSON %s", (input) => {
    expect(() => parseAuthObject(encoder.encode(input))).toThrow(AuthError);
  });
  it("rejects invalid UTF8, oversized fragmented input and credential/scope overrides", async () => {
    expect(() => parseAuthObject(new Uint8Array([0xff, 0xfe]))).toThrow(AuthError);
    expect(() => parseAuthObject(encoder.encode(`{"a":"${"a".repeat(8192)}"}`))).toThrow(AuthError);
    const h = await harness(); const c = await h.consent(); const req = h.codeRequest(c.code);
    for (const patch of [{ scope: "health:upload" }, { account_id: foreign.accountId }, { audience: "other" },
      { client_secret: "synthetic" }, { installation_id: true }, { code_verifier: "short" },
      { code: newToken("access", webEntropy) }, { code: newToken("refresh", webEntropy) }]) {
      expect(() => parseTokenRequest(bytes({ ...req, ...patch }))).toThrow(AuthError);
    }
    const raw = h.queryUrl();
    for (const uri of [raw + "&state=" + h.stateRef, raw.replace("client_id=", "%63lient_id="),
      raw + "#x", raw.replace("state=", "state=%ZZ"), raw + "&x=y", raw.replace("/account/authorize", "/account/authorize/"),
      raw.replace("account-auth.synthetic.example", "ACCOUNT-AUTH.synthetic.example"), raw + "&" + "x".repeat(4096)]) {
      expect(() => parseAuthorization(uri, registration)).toThrow(AuthError);
    }
    const huge = h.request("/api/account-auth/v1/token", "POST", { x: "x".repeat(9000) });
    expect((await h.http(huge)).status).toBe(400);
    const stream = new ReadableStream({ start(controller) {
      for (let i = 0; i < 100; i++) controller.enqueue(encoder.encode("x".repeat(100)));
      controller.close();
    } });
    expect((await h.http(new Request(registration.issuer + "/api/account-auth/v1/token", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: stream, duplex: "half",
    } as RequestInit))).status).toBe(400);
  });
  it("accepts all five exact synthetic client registrations and rejects any real environment", async () => {
    const h = await harness();
    for (const c of registration.clients) {
      expect(parseAuthorization(h.queryUrl({ ...h.query, client_id: c.client_id, redirect_uri: c.callback }), registration)
        .client_id).toBe(c.client_id);
    }
    for (const environment of ["production", "staging", "development"]) {
      expect(() => new SyntheticNativeAuthority({ registration: { ...registration, environment } as Registration,
        store: h.store, clock: h.now, rateKey: async () => randomReference() })).toThrow(AuthError);
    }
    expect(() => new SyntheticNativeAuthority({ registration: { ...registration,
      clients: [{ ...registration.clients[0]!, callback: "https://evil.example/return" }] }, store: h.store,
    clock: h.now, rateKey: async () => randomReference() })).toThrow(AuthError);
  });
});

describe("AS01 lifecycle sequences backed by SQLite, not a symbolic store", () => {
  it.each(vectors.lifecycle_vectors)("lifecycle $id", async (v) => {
    const h = await harness(); const consent = await h.consent();
    let parent: NativeSessionResponse | undefined, child: NativeSessionResponse | undefined;
    const attempt = new NativeAttempt({ registration, state: h.stateRef, clientId: h.query.client_id,
      scope: h.query.scope, installationId: h.installation, generation: 1 });
    attempt.acceptCallback(consent.callback, 1);
    let generation = 1;
    for (const step of v.steps) {
      let observed: string;
      if (step.verified === false) h.store.afterCommit = () => { h.store.unreadable = true; };
      try {
        if (step.op === "exchange") {
          parent = await h.authority.token(bytes(h.codeRequest(consent.code))); observed = "issued";
        } else if (step.op === "refresh") {
          const req = h.refreshRequest(step.token === "child" ? child! : parent!);
          if (step.installation_matches === false) req.installation_id = randomReference();
          child = await h.authority.token(bytes(step.scope_expansion ? { ...req, scope: "health:upload" } : req));
          observed = "rotated";
        } else if (step.op === "access") {
          await h.authority.authenticate((child ?? parent)!.access_token, []); observed = "allow";
        } else if (step.op === "revoke") {
          await h.authority.revoke({ kind: "access", token: (child ?? parent)!.access_token }); observed = "revoked";
        } else if (step.op === "disable_account") {
          await h.peer.transact((state) => { state.accounts[identity.accountId]!.active = false; }); observed = "disabled";
        } else if (step.op === "switch_generation") {
          generation++; attempt.cancel(); observed = "local_signed_out_remote_pending";
        } else if (step.op === "apply_response") {
          attempt.acceptSession((child ?? parent)!, generation); observed = "allow";
        } else throw new Error("Unrecognized fixture lifecycle step");
      } catch (error) {
        expect(error instanceof AuthError).toBe(true);
        const code = (error as AuthError).code;
        observed = step.op === "access" || step.op === "apply_response" ? "deny" :
          code === "verification_pending" ? (step.op === "revoke" ? "revocation_pending" : "verification_pending_no_secret") : code;
      } finally { h.store.unreadable = false; }
      // Closed request grammar is stricter than AS01's symbolic grant outcome: escalation is invalid_request.
      expect(observed).toBe(step.scope_expansion ? "invalid_request" : step.expected);
    }
  });
});

describe("HTTP credential isolation and no implicit health/config authority", () => {
  it("rejects foreign credential classes on native APIs; native tokens cannot authorize existing browser/ingest/MCP", async () => {
    const h = await harness(); const session = await h.issue();
    const foreignTokens = [session.refresh_token, newToken("code", webEntropy), `hmd_ses_${randomReference()}`,
      `hmd_ing_${randomReference()}`, `hmd_dev_${randomReference()}`, `hmd_read_${randomReference()}`,
      "synthetic-provider-oauth", "synthetic-direct-pairing", "synthetic-store-receipt", "synthetic-shared-setup",
      "synthetic-deletion-receipt"];
    for (const credential of foreignTokens) {
      expect((await h.http(h.request("/api/account-auth/v1/sessions", "GET", undefined,
        { Authorization: `Bearer ${credential}` }))).status).toBeGreaterThanOrEqual(400);
      await failure(h.authority.authorizeConfig(credential, "POST", "/api/profile-sync/v1/read"));
    }
    const env = { ENVIRONMENT: "production" } as Env;
    const native = h.request("/api/account", "GET", undefined, { Cookie: `__Host-healthmd_cloud_session=${session.access_token}`,
      Authorization: `Bearer ${session.access_token}` });
    expect(await getSession(native, env)).toBeNull();
    await expect(requireIngestToken(native, env)).rejects.toMatchObject({ code: "unauthorized" });
    expect(authenticateReadToken(h.store.db, `Bearer ${session.access_token}`)).toBeNull();
    expect(authenticateReadToken(h.store.db, `Bearer ${session.refresh_token}`)).toBeNull();
    for (const op of policy.native_denied_operations) {
      await failure(h.authority.authorizeConfig(session.access_token, op.method, op.path), "forbidden");
      expect((await h.http(h.request(op.path, op.method, undefined,
        { Authorization: `Bearer ${session.access_token}` }))).status).toBe(404);
    }
    expect(await h.store.read((state) => Object.keys(state).sort())).toEqual(Object.keys(emptyAuthState()).sort());
  });
  it("forbids cookies/Basic/mixed credentials or native account selectors at token/revoke routes", async () => {
    const h = await harness(); const c = await h.consent(); const req = h.codeRequest(c.code);
    const forbiddenHeaders: Record<string, string>[] = [{ Cookie: "synthetic-browser=a" }, { Cookie: "" },
      { Authorization: "Basic synthetic" }, { Authorization: `Bearer ${newToken("access", webEntropy)}` }];
    for (const headers of forbiddenHeaders) {
      expect((await h.http(h.request("/api/account-auth/v1/token", "POST", req, headers))).status).toBe(401);
    }
    const session = await h.authority.token(bytes(req));
    expect((await h.http(h.request("/api/account-auth/v1/revoke", "POST", { account_id: foreign.accountId },
      { Authorization: `Bearer ${session.access_token}` }))).status).toBe(400);
    const wrongInstall = { ...h.refreshRequest(session), installation_id: randomReference() };
    await failure(h.authority.token(bytes(wrongInstall)), "invalid_grant");
    expect((await h.authority.token(bytes(h.refreshRequest(session)))).session_generation).toBe(1);
  });
  it("requires exact Origin, CSRF and recent authoritative reauth for browser inventory/revocation", async () => {
    const h = await harness(); const s = await h.issue();
    for (const headers of [{ Cookie: "synthetic-browser=a" }, { ...h.browserHeaders, Origin: "https://website.example" },
      { ...h.browserHeaders, "X-HealthMd-CSRF": "wrong" }, { ...h.browserHeaders, Authorization: `Bearer ${s.access_token}` }]) {
      expect((await h.http(h.request("/api/account-auth/v1/sessions", "GET", undefined, headers))).status).toBe(401);
      expect((await h.http(h.request("/api/account-auth/v1/revoke", "POST", { session_id: s.session_id }, headers))).status).toBe(401);
    }
    expect((await h.http(h.request("/api/account-auth/v1/sessions", "GET", undefined, h.browserHeaders))).status).toBe(200);
    h.advance(300);
    expect((await h.http(h.request("/api/account-auth/v1/sessions", "GET", undefined, h.browserHeaders))).status).toBe(401);
    await h.store.transact((state) => { state.browsers[identity.sessionId]!.reauthenticatedAt = h.now(); });
    expect((await h.http(h.request("/api/account-auth/v1/revoke", "POST", { session_id: s.session_id }, h.browserHeaders))).status).toBe(200);
  });
  it("keeps every error/redirect/body no-store, no-referrer, fixed and non-reflecting", async () => {
    const h = await harness(); const marker = "synthetic-private-do-not-reflect";
    const errors = [h.request("/api/account-auth/v1/token", "POST", { password: marker }),
      h.request("/api/account-auth/v1/token?token=" + marker, "POST", {}),
      h.request("/api/account-auth/v1/sessions", "GET", undefined, { Authorization: "Bearer " + marker }),
      h.request("/api/account-auth/v1/token", "GET"), h.request("/api/account-auth/v1/token/", "POST", {})];
    for (const request of errors) {
      const response = await h.http(request);
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(response.headers.get("cache-control")).toBe("no-store");
      expect(response.headers.get("referrer-policy")).toBe("no-referrer");
      expect(response.headers.get("set-cookie")).toBeNull();
      expect(response.headers.get("access-control-allow-origin")).toBeNull();
      expect(response.headers.get("location")).toBeNull();
      expect((await response.text()).includes(marker)).toBe(false);
    }
    const alternate = new Request(h.queryUrl().replace(registration.issuer, "https://alternate.example"), { headers: h.browserHeaders });
    expect((await h.http(alternate)).status).toBe(400);
    expect((await createNativeAuthHttp()(h.request("/api/account-auth/v1/token", "POST", {}))).status).toBe(503);
  });
});

describe("real SQLite transaction lifecycle, races and fault proofs", () => {
  it("runs synthetic HTTP browser consent, code exchange, refresh, inventory and self sign-out", async () => {
    const h = await harness();
    const begin = await h.http(new Request(h.queryUrl(), { headers: h.browserHeaders }));
    expect(begin.status).toBe(200);
    const authId = (await begin.json() as { authorization_id: string }).authorization_id;
    const decision = await h.http(h.request("/api/account-auth/v1/decision", "POST",
      { authorization_id: authId, decision: "approve" }, h.browserHeaders));
    expect(decision.status).toBe(303);
    expect(decision.headers.get("cache-control")).toBe("no-store");
    const code = new URL(decision.headers.get("location")!).searchParams.get("code")!;
    const exchange = await h.http(h.request("/api/account-auth/v1/token", "POST", h.codeRequest(code)));
    expect(exchange.status).toBe(200);
    const session = await exchange.json() as NativeSessionResponse;
    expect(session.scope).toBe(h.query.scope); expect(session.session_generation).toBe(0);
    const inventory = await h.authority.nativeSessions(session.access_token);
    expect(inventory.length).toBe(1); expect(inventory[0]?.current).toBe(true);
    expect(Object.keys(inventory[0]!).sort()).toEqual(["client_id", "created_at", "current", "expires_at", "platform", "revoked", "session_id"]);
    const refresh = await h.http(h.request("/api/account-auth/v1/token", "POST", h.refreshRequest(session)));
    expect(refresh.status).toBe(200); const rotated = await refresh.json() as NativeSessionResponse;
    expect(rotated.session_generation).toBe(1); expect(rotated.access_token === session.access_token).toBe(false);
    const revoke = await h.http(h.request("/api/account-auth/v1/revoke", "POST", {}, { Authorization: `Bearer ${rotated.access_token}` }));
    expect(revoke.status).toBe(200); expect(await revoke.json()).toEqual({ revoked: true });
    await failure(h.authority.authenticate(rotated.access_token, []), "unauthorized");
    const state = await h.store.read((s) => JSON.stringify(s));
    expect(state.includes(session.access_token) || state.includes(rotated.refresh_token) || state.includes(code)).toBe(false);
    expect(state.includes(h.verifier)).toBe(false);
  });
  it("returns stable authoritative account+issuer+environment across families/installations/rotation, never family/email identity", async () => {
    const h = await harness(); const first = await h.issue(); const c = await h.consent();
    const second = await h.authority.token(bytes({ ...h.codeRequest(c.code), installation_id: randomReference() }));
    const rotated = await h.authority.token(bytes(h.refreshRequest(first)));
    const other = await h.issue(foreign);
    for (const session of [first, second, rotated]) {
      expect(session.account_id === identity.accountId).toBe(true);
      expect(session.issuer === registration.issuer && session.environment === registration.environment).toBe(true);
      expect(session.account_id === session.session_id || session.account_id.includes("@")).toBe(false);
      expect(Object.keys(session).sort()).toEqual(["access_token", "account_id", "audience", "client_id", "environment",
        "expires_in", "installation_id", "issuer", "refresh_token", "scope", "session_generation", "session_id", "token_type"]);
    }
    expect(first.session_id === second.session_id).toBe(false);
    expect(first.installation_id === second.installation_id).toBe(false);
    expect(other.account_id === first.account_id).toBe(false);
    const f1 = await h.store.read((state) => JSON.stringify(state.families[first.session_id]!.binding));
    await h.authority.token(bytes(h.refreshRequest(rotated)));
    expect(await h.store.read((state) => JSON.stringify(state.families[first.session_id]!.binding) === f1)).toBe(true);
    expect((await h.authority.browserSessions(identity)).length).toBe(2);
    expect((await h.authority.nativeSessions(second.access_token)).length).toBe(1);
    // Verified response metadata is a proposed AS02 source-interface addition; no retained-account endpoint is needed.
    const a = new NativeAttempt({ registration, clientId: h.query.client_id, state: h.stateRef,
      scope: h.query.scope, installationId: second.installation_id, generation: 1 });
    a.acceptCallback(c.callback, 1); a.acceptSession(second, 1);
    const bad = new NativeAttempt({ registration, clientId: h.query.client_id, state: h.stateRef,
      scope: h.query.scope, installationId: second.installation_id, generation: 1 });
    bad.acceptCallback(c.callback, 1);
    expect(() => bad.acceptSession({ ...second, account_id: "synthetic-person@example.test" }, 1)).toThrow(AuthError);
  });
  it("consumes denial once and never grants a family; invalid browser cannot decide", async () => {
    const h = await harness(); const b = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
    await failure(h.authority.decide(b.authorization_id, "approve", foreign), "invalid_grant");
    const denied = await h.authority.decide(b.authorization_id, "deny", identity);
    expect(new URL(denied.callback).searchParams.get("error")).toBe("access_denied");
    await failure(h.authority.decide(b.authorization_id, "approve", identity), "invalid_grant");
    expect(await h.store.read((s) => Object.keys(s.codes).length + Object.keys(s.families).length)).toBe(0);
  });
  it("has a single code-exchange winner across two SQLite connections", async () => {
    const h = await harness(); const c = await h.consent(); const req = bytes(h.codeRequest(c.code));
    const results = await Promise.allSettled([h.authority.token(req), h.other.token(req)]);
    expect(results.filter((r) => r.status === "fulfilled").length).toBe(1);
    expect(await h.store.read((s) => Object.keys(s.families).length)).toBe(1);
    await failure(h.authority.token(req), "invalid_grant");
  });
  it("refresh CAS admits one child and strict concurrent reuse kills winner/access", async () => {
    const h = await harness(); const s = await h.issue(); const req = bytes(h.refreshRequest(s));
    const results = await Promise.allSettled([h.authority.token(req), h.other.token(req)]);
    expect(results.filter((r) => r.status === "fulfilled").length).toBeLessThanOrEqual(1);
    expect(results.filter((r) => r.status === "rejected").length).toBeGreaterThanOrEqual(1);
    const state = await h.store.read((state) => state);
    expect(Object.keys(state.refresh).length).toBe(2);
    expect(state.families[s.session_id]?.revokedAt !== null).toBe(true);
    await failure(h.authority.authenticate(s.access_token, []), "unauthorized");
    for (const r of results) if (r.status === "fulfilled") {
      await failure(h.authority.authenticate(r.value.access_token, []), "unauthorized");
      await failure(h.authority.token(bytes(h.refreshRequest(r.value))), "invalid_grant");
    }
  });
  it("rechecks account disable, browser switch and revocation at mutation/verification boundaries", async () => {
    const h = await harness(); const c = await h.consent();
    const pendingExchange = h.authority.token(bytes(h.codeRequest(c.code)));
    await h.peer.transact((s) => { s.accounts[identity.accountId]!.active = false; });
    await failure(pendingExchange, "invalid_grant");
    expect(await h.store.read((s) => Object.keys(s.families).length)).toBe(0);
    await h.peer.transact((s) => { s.accounts[identity.accountId]!.active = true; });
    const s = await h.issue();
    const pendingRefresh = h.authority.token(bytes(h.refreshRequest(s)));
    await h.other.revoke({ kind: "access", token: s.access_token });
    await failure(pendingRefresh);
    await failure(h.authority.authenticate(s.access_token, []), "unauthorized");
    const next = await h.consent();
    await h.peer.transact((state) => { state.browsers[identity.sessionId]!.revoked = true; });
    await failure(h.authority.token(bytes(h.codeRequest(next.code))), "invalid_grant");
  });
  it.each(["before", "noop", "rollback", "receipt-only", "no-receipt"] as const)("never reports issuance success on %s", async (fault) => {
    const h = await harness(); const c = await h.consent(); h.store.fault = fault;
    await failure(h.authority.token(bytes(h.codeRequest(c.code))), "verification_pending");
    if (fault !== "no-receipt") expect(await h.store.read((s) => Object.keys(s.families).length)).toBe(0);
    else await failure(h.authority.token(bytes(h.codeRequest(c.code))), "invalid_grant");
  });
  it.each(["before", "noop", "rollback", "receipt-only", "no-receipt"] as const)("requires exact rotation postconditions on %s", async (fault) => {
    const h = await harness(); const s = await h.issue(); h.store.fault = fault;
    await failure(h.authority.token(bytes(h.refreshRequest(s))), "verification_pending");
    if (fault === "no-receipt") await failure(h.authority.token(bytes(h.refreshRequest(s))), "reuse_family_revoked");
    else expect((await h.authority.token(bytes(h.refreshRequest(s)))).session_generation).toBe(1);
  });
  it.each(["noop", "receipt-only", "no-receipt", "rollback"] as const)("never emits consent/code without exact decision proof on %s", async (fault) => {
    const h = await harness(); const b = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
    h.store.fault = fault;
    await failure(h.authority.decide(b.authorization_id, "approve", identity), "verification_pending");
    expect(await h.store.read((state) => Object.keys(state.families).length)).toBe(0);
    if (fault === "no-receipt") await failure(h.authority.decide(b.authorization_id, "approve", identity), "invalid_grant");
    else expect((await h.authority.decide(b.authorization_id, "approve", identity)).callback.includes("?code=")).toBe(true);
  });
  it("lost begin/consent verification never fabricates a code; consumed consent cannot be replayed", async () => {
    const h = await harness(); h.store.fault = "noop";
    await failure(h.authority.begin(h.queryUrl(), identity, "synthetic-address"), "verification_pending");
    const b = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
    h.store.afterCommit = () => { h.store.unreadable = true; };
    await failure(h.authority.decide(b.authorization_id, "approve", identity), "verification_pending");
    h.store.unreadable = false;
    await failure(h.authority.decide(b.authorization_id, "approve", identity), "invalid_grant");
  });
  it("a committed session loses authority if account disable wins before readback", async () => {
    const h = await harness(); const c = await h.consent();
    h.store.afterCommit = () => {
      const row = h.peer.db.prepare("SELECT body FROM synthetic_state WHERE id=1").get() as { body: string };
      const state: AuthState = JSON.parse(row.body); state.accounts[identity.accountId]!.active = false;
      h.peer.db.exec("BEGIN IMMEDIATE");
      h.peer.db.prepare("UPDATE synthetic_state SET body=? WHERE id=1").run(JSON.stringify(state));
      h.peer.db.exec("COMMIT");
    };
    await failure(h.authority.token(bytes(h.codeRequest(c.code))), "verification_pending");
    expect(await h.store.read((state) => Object.keys(state.families).length)).toBe(1);
    await failure(h.authority.token(bytes(h.codeRequest(c.code))), "invalid_grant");
  });
  it("wrong browser review account and missing/deleted account deny inventory, revoke and refresh", async () => {
    const h = await harness(); const b = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
    await h.peer.transact((state) => { state.browsers[identity.sessionId]!.accountId = foreign.accountId; });
    await failure(h.authority.decide(b.authorization_id, "approve", identity), "invalid_grant");
    await h.peer.transact((state) => { state.browsers[identity.sessionId]!.accountId = identity.accountId; });
    const s = await h.issue();
    await h.peer.transact((state) => { delete state.accounts[identity.accountId]; });
    await failure(h.authority.nativeSessions(s.access_token), "unauthorized");
    await failure(h.authority.browserSessions(identity), "unauthorized");
    await failure(h.authority.revoke({ kind: "access", token: s.access_token }), "unauthorized");
    await failure(h.authority.token(bytes(h.refreshRequest(s))), "invalid_grant");
  });
  it("read-only scopes cannot mutate at authentication OR authoritative commit", async () => {
    const h = await harness(); const c = await h.consent(identity, { ...h.query, scope: "config:profiles:read" });
    const s = await h.authority.token(bytes(h.codeRequest(c.code)));
    const p = await h.authority.authorizeConfig(s.access_token, "POST", "/api/profile-sync/v1/read");
    await failure(h.authority.authorizeConfig(s.access_token, "POST", "/api/profile-sync/v1/mutate"), "forbidden");
    await expect(h.store.read((state) => h.authority.assertConfigAtCommit(state, p, "POST", "/api/profile-sync/v1/mutate")))
      .rejects.toThrow(AuthError);
  });
  it("verifies an exact commit after lost adapter reply but withholds unreadable issuance", async () => {
    const h = await harness(); const c = await h.consent(); h.store.fault = "lost";
    const s = await h.authority.token(bytes(h.codeRequest(c.code)));
    expect(s.session_generation).toBe(0);
    const next = await h.consent(); h.store.afterCommit = () => { h.store.unreadable = true; };
    await failure(h.authority.token(bytes(h.codeRequest(next.code))), "verification_pending");
    h.store.unreadable = false;
    await failure(h.authority.token(bytes(h.codeRequest(next.code))), "invalid_grant");
  });
  it("lost refresh response cannot recover secrets; retry revokes committed child", async () => {
    const h = await harness(); const s = await h.issue();
    h.store.afterCommit = () => { h.store.unreadable = true; };
    await failure(h.authority.token(bytes(h.refreshRequest(s))), "verification_pending");
    h.store.unreadable = false;
    await failure(h.authority.token(bytes(h.refreshRequest(s))), "reuse_family_revoked");
    expect(await h.store.read((st) => st.families[s.session_id]!.revokedAt !== null)).toBe(true);
  });
  it.each(["noop", "receipt-only", "no-receipt", "rollback"] as const)("requires actual revoke plus audit proof on %s", async (fault) => {
    const h = await harness(); const s = await h.issue(); h.store.fault = fault;
    await failure(h.authority.revoke({ kind: "access", token: s.access_token }), "verification_pending");
    if (fault !== "no-receipt") expect(await h.authority.authenticate(s.access_token, [])).toBeDefined();
    expect(await h.authority.revoke({ kind: "access", token: s.access_token })).toEqual({ revoked: true });
  });
  it("unreadable revocation is pending, but authority stays dead and retry is idempotent", async () => {
    const h = await harness(); const s = await h.issue(); h.store.afterCommit = () => { h.store.unreadable = true; };
    await failure(h.authority.revoke({ kind: "access", token: s.access_token }), "verification_pending");
    h.store.unreadable = false; await failure(h.authority.authenticate(s.access_token, []), "unauthorized");
    h.store.fault = "lost";
    expect(await h.authority.revoke({ kind: "access", token: s.access_token })).toEqual({ revoked: true });
  });
  it("wrong ownership never revokes another account; spent refresh works ONLY for self revoke", async () => {
    const h = await harness(); const s = await h.issue(); const other = await h.issue(foreign);
    await failure(h.authority.revoke({ kind: "browser", identity, sessionId: other.session_id }), "not_found");
    await failure(h.authority.revoke({ kind: "browser", identity, sessionId: randomReference() }), "not_found");
    expect(await h.authority.authenticate(other.access_token, [])).toBeDefined();
    await failure(h.authority.revoke({ kind: "refresh", token: s.refresh_token,
      clientId: s.client_id, installationId: randomReference() }), "unauthorized");
    const child = await h.authority.token(bytes(h.refreshRequest(s)));
    expect(await h.authority.revoke({ kind: "refresh", token: s.refresh_token,
      clientId: s.client_id, installationId: s.installation_id })).toEqual({ revoked: true });
    await failure(h.authority.authenticate(child.access_token, []), "unauthorized");
  });
  it("expires pending, code, access and family at equality, never resets absolute lifetime", async () => {
    const h = await harness(); const p = await h.authority.begin(h.queryUrl(), identity, "synthetic-address");
    h.advance(300); await failure(h.authority.decide(p.authorization_id, "approve", identity), "invalid_grant");
    const c = await h.consent(); h.advance(120); await failure(h.authority.token(bytes(h.codeRequest(c.code))), "invalid_grant");
    const s = await h.issue(); h.advance(300); await failure(h.authority.authenticate(s.access_token, []), "unauthorized");
    const initialAbsolute = await h.store.read((st) => st.families[s.session_id]!.absoluteExpiresAt);
    const child = await h.authority.token(bytes(h.refreshRequest(s)));
    expect(await h.store.read((st) => st.families[s.session_id]!.absoluteExpiresAt)).toBe(initialAbsolute);
    h.advance(7 * 86400); await failure(h.authority.token(bytes(h.refreshRequest(child))), "invalid_grant");
  });
  it("late responses, cancelled callbacks, account switch and stale principals cannot resurrect", async () => {
    const h = await harness(); const c = await h.consent();
    const attempt = new NativeAttempt({ registration, clientId: h.query.client_id, scope: h.query.scope,
      state: h.stateRef, installationId: h.installation, generation: 10 });
    attempt.acceptCallback(c.callback, 10);
    const s = await h.authority.token(bytes(h.codeRequest(c.code)));
    expect(() => attempt.acceptSession(s, 11)).toThrow(AuthError);
    attempt.cancel(); expect(() => attempt.acceptSession(s, 10)).toThrow(AuthError);
    const p = await h.authority.authorizeConfig(s.access_token, "POST", "/api/profile-sync/v1/mutate");
    await h.store.read((state) => h.authority.assertConfigAtCommit(state, p, "POST", "/api/profile-sync/v1/mutate"));
    await h.authority.token(bytes(h.refreshRequest(s)));
    await expect(h.store.read((state) => h.authority.assertConfigAtCommit(state, p, "POST", "/api/profile-sync/v1/mutate"))).rejects.toThrow(AuthError);
    const valid = await h.authority.authorizeConfig(s.access_token, "POST", "/api/profile-sync/v1/read");
    await expect(h.store.read((state) => h.authority.assertConfigAtCommit(state, { ...valid }, "POST", "/api/profile-sync/v1/read"))).rejects.toThrow(AuthError);
    h.advance(300);
    await expect(h.store.read((state) => h.authority.assertConfigAtCommit(state, valid, "POST", "/api/profile-sync/v1/read"))).rejects.toThrow(AuthError);
  });
  it("charges atomic admission/caps and keeps rate labels purpose-digested", async () => {
    const h = await harness();
    const begins = await Promise.allSettled(Array.from({ length: 6 }, () => h.authority.begin(h.queryUrl(), identity, "synthetic-address")));
    expect(begins.filter((r) => r.status === "fulfilled").length).toBe(5);
    expect(await h.store.read((state) => JSON.stringify(state.rates).includes("synthetic-address"))).toBe(false);
    h.advance(3600);
    for (let i = 0; i < 20; i++) {
      await h.store.transact((state) => { state.browsers[identity.sessionId]!.reauthenticatedAt = h.now(); });
      const session = await h.issue();
      expect(session.session_generation).toBe(0);
      h.advance(3600);
    }
    const c = await h.consent(); await failure(h.authority.token(bytes(h.codeRequest(c.code))), "rate_limited");
    await h.store.transact((state) => { const f = Object.values(state.families)[0]!; f.revokedAt = h.now(); });
    expect((await h.authority.token(bytes(h.codeRequest(c.code)))).session_generation).toBe(0);
  });
});
