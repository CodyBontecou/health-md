// Host-only SQLite/fixture driver. Never import this file from src/ or a Worker.
import { DatabaseSync } from "node:sqlite";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { PROFILE_SQL_CANDIDATE_SCHEMA, createProfileSqlCandidate,
  type ProfileSqlPort, type ProfileSqlStatement, type SyntheticProfileSqlPorts } from "../../src/profile-sync-v1-sql";
import { SyntheticNativeAuthority } from "../../src/account-auth-v1/authority";
import { emptyAuthState, type AuthState, type AuthStore, type Registration, type NativeSessionResponse } from "../../src/account-auth-v1/model";
import { purposeRateKey, randomReference, s256 } from "../../src/account-auth-v1/crypto";

export const owners = ["synthetic-account-a", "synthetic-account-b"] as const;
const policySource = JSON.parse(readFileSync(new URL("../../../../packages/contracts/account-auth/v1/source-policy.json", import.meta.url), "utf8")) as {
  environments: { synthetic: Omit<Registration, "environment"> }; scopes: string[] };
export const registration: Registration = { ...policySource.environments.synthetic, environment: "synthetic" };
export const encode = (value: unknown) => new TextEncoder().encode(JSON.stringify(value));
export class HostProfileSql implements ProfileSqlPort, AuthStore {
  db: DatabaseSync;
  fault: "lost" | "noop" | "rollback" | "crash" | "crash-after-commit" | undefined;
  unreadable = false;
  beforeBatch: (() => void) | undefined;
  constructor(readonly path: string) { this.db = this.connect(); }
  private connect(): DatabaseSync {
    const db = new DatabaseSync(this.path);
    db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000");
    return db;
  }
  reopen(): void { this.db.close(); this.db = this.connect(); }
  initialize(): void {
    for (const sql of PROFILE_SQL_CANDIDATE_SCHEMA) this.db.exec(sql);
    const state = emptyAuthState();
    for (const accountId of owners) {
      state.accounts[accountId] = { active: true };
      state.browsers[accountId] = { accountId, sessionId: accountId, revoked: false,
        expiresAt: Math.floor(Date.now() / 1000) + 86400, reauthenticatedAt: Math.floor(Date.now() / 1000) };
    }
    this.db.prepare("INSERT INTO ps_authority VALUES(1,0,?)").run(JSON.stringify(state));
  }
  async transact(change: (state: AuthState) => void): Promise<void> {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const row = this.db.prepare("SELECT version,body FROM ps_authority WHERE id=1").get() as { version: number; body: string };
      const state = JSON.parse(row.body) as AuthState;
      const value: unknown = change(state);
      if (value !== undefined) throw new Error("Non-synchronous fixture callback");
      // AuthStore's callback executes once under the actual exclusive SQL transaction.
      this.db.prepare("UPDATE ps_authority SET version=version+1,body=? WHERE id=1").run(JSON.stringify(state));
      this.db.exec("COMMIT");
    } catch (error) { this.db.exec("ROLLBACK"); throw error; }
  }
  async read<T>(inspect: (state: Readonly<AuthState>) => T): Promise<T> {
    const row = this.db.prepare("SELECT body FROM ps_authority WHERE id=1").get() as { body: string };
    return inspect(JSON.parse(row.body) as AuthState);
  }
  async batch(statements: readonly ProfileSqlStatement[]): Promise<Record<string, unknown>[][]> {
    const write = statements[0]?.sql.startsWith("INSERT INTO ps_guard");
    if (this.unreadable && !write) throw new Error("Fixture evidence unavailable");
    const hook = this.beforeBatch;
    if (write && hook) { this.beforeBatch = undefined; hook(); }
    const fault = write ? this.fault : undefined;
    if (write) this.fault = undefined;
    if (fault === "noop") return statements.map(() => []);
    if (fault === "crash" || fault === "crash-after-commit") {
      // A separate OS process executes the ACTUAL adapter's emitted domain SQL.
      // Abrupt exit before/after COMMIT; no fake MemoryJournal restoration.
      const script = `import {DatabaseSync} from 'node:sqlite';
        const db=new DatabaseSync(process.argv[1]); db.exec('PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
        const input=JSON.parse(process.argv[2]);
        for(let i=0;i<input.statements.length;i++) {
          const s=input.statements[i]; db.prepare(s.sql).all(...s.values);
          if(input.fault==='crash' && i===Math.floor(input.statements.length/2)) process.exit(42);
        }
        db.exec('COMMIT'); process.exit(42);`;
      const child = spawnSync(process.execPath, ["--input-type=module", "-e", script, this.path, JSON.stringify({ statements, fault })], { encoding: "utf8" });
      if (child.status !== 42) throw new Error("Crash fixture did not reach its requested cut");
      throw new Error("Fixture process lost acknowledgement");
    }
    this.db.exec("BEGIN IMMEDIATE");
    let committed = false;
    try {
      const results = statements.map(s => this.db.prepare(s.sql).all(...s.values) as Record<string, unknown>[]);
      if (fault === "rollback") throw new Error("Fixture rollback before COMMIT");
      this.db.exec("COMMIT"); committed = true;
      if (fault === "lost") throw new Error("Fixture lost acknowledgement");
      return results;
    } catch (error) { if (!committed) this.db.exec("ROLLBACK"); throw error; }
  }
}
export async function sqlHarness(path: string, fresh = true, clock: () => number = () => Math.floor(Date.now() / 1000)) {
  const store = new HostProfileSql(path); if (fresh) store.initialize();
  const rateKey = await crypto.subtle.importKey("raw", new Uint8Array(32).fill(91), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const authority = new SyntheticNativeAuthority({ registration, store, clock,
    rateKey: (purpose, label) => purposeRateKey(rateKey, purpose, label) });
  // Public AS02 browser decision + S256 exchange, TWO distinct fixture browser owners.
  async function issue(accountId: typeof owners[number]): Promise<NativeSessionResponse> {
    const verifier = randomReference();
    const query = new URLSearchParams({ client_id: "synthetic-apple-ios", redirect_uri: registration.clients[0]!.callback,
      response_type: "code", scope: policySource.scopes.join(" "), state: randomReference(), code_challenge: await s256(verifier),
      code_challenge_method: "S256", audience: registration.audience });
    const identity = { accountId, sessionId: accountId };
    const pending = await authority.begin(`${registration.issuer}/account/authorize?${query}`, identity, "synthetic-fixture-address");
    const decision = await authority.decide(pending.authorization_id, "approve", identity);
    return authority.token(encode({ grant_type: "authorization_code", client_id: "synthetic-apple-ios",
      redirect_uri: registration.clients[0]!.callback, code: new URL(decision.callback).searchParams.get("code"),
      code_verifier: verifier, installation_id: randomReference() }));
  }
  const keys = await Promise.all(owners.map(async (_, index) => crypto.subtle.importKey("raw", new Uint8Array(32).fill(17 + index), "AES-GCM", false, ["encrypt", "decrypt"])));
  const ports: SyntheticProfileSqlPorts = { sentinel: "healthmd.profile-sync.sql.synthetic-only", sql: store, authority,
    policy: { fixtureOnly: true, version: "synthetic-local-not-approved-v1", maxProfiles: 100, maxEvents: 256, maxReceipts: 512, maxEncryptedBytes: 1_048_576 },
    keyReference: () => ({ id: "fixture-config-only", version: 1 }),
    resolveKey: async owner => {
      const index = owners.indexOf(JSON.parse(owner)[2] as typeof owners[number]);
      if (index < 0) throw new Error("Unknown fixture owner"); return keys[index]!;
    } };
  const service = createProfileSqlCandidate(ports);
  const request = (session: NativeSessionResponse, path = "/api/profile-sync/v1/mutate") => new Request(registration.issuer + path,
    { method: "POST", headers: { Authorization: `Bearer ${session.access_token}` } });
  return { store, authority, issue, ports, service, request };
}
