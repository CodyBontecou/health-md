// Inactive AS06 candidate. No router/runtime import, live registration or privacy approval.
// D1 batch/CAS protocol; the authoritative auth row MUST be advanced in the SAME
// database transaction as every AS02 account/session/consent change. The host driver
// implements AS02's exclusive callback contract. No D1 AuthStore is implied here.
import { SyntheticNativeAuthority } from "./account-auth-v1/authority";
import type { AuthState, ConfigPrincipal } from "./account-auth-v1/model";
import { parseProfileSyncV1Mutation, parseProfileSyncV1Read, ProfileSyncV1Error,
  ValidatedProfileSyncV1Record, parseProfileSyncV1Page, type ProfileSyncV1ErrorResult } from "./profile-sync-v1-contract";

export type SqlValue = string | number | null;
export interface ProfileSqlStatement { sql: string; values: readonly SqlValue[] }
/** Fresh primary reads; batch is atomic, ordered and rolls back on ANY error.
 * Never retry callbacks or silently retry a rejected CAS with a newer version. */
export interface ProfileSqlPort { batch(statements: readonly ProfileSqlStatement[]): Promise<Record<string, unknown>[][]> }
/** Unused by runtime factories. D1's batch has transaction/rollback semantics;
 * first-primary prevents a replica from supplying stale authorization/readback. */
export function d1ProfileSqlPort(database: D1Database): ProfileSqlPort {
  return { async batch(statements) {
    const primary = database.withSession("first-primary");
    const results = await primary.batch<Record<string, unknown>>(statements.map(s => primary.prepare(s.sql).bind(...s.values)));
    if (results.some(r => !r.success)) throw new Error("Profile transaction unavailable");
    return results.map(r => r.results);
  } };
}
// Separate inactive schema, NOT an applied pilot migration or a resource initializer.
export const PROFILE_SQL_CANDIDATE_SCHEMA = [
  "CREATE TABLE ps_authority (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL CHECK(version>=0), body TEXT NOT NULL CHECK(json_valid(body))) STRICT",
  "CREATE TABLE ps_partition (owner TEXT PRIMARY KEY, version INTEGER NOT NULL CHECK(version>=0), body TEXT NOT NULL CHECK(json_valid(body))) STRICT",
  "CREATE TABLE ps_head (owner TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL CHECK(json_valid(body)), PRIMARY KEY(owner,id)) STRICT",
  "CREATE TABLE ps_revision (owner TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, body TEXT NOT NULL CHECK(json_valid(body)), PRIMARY KEY(owner,id,revision)) STRICT",
  "CREATE TABLE ps_event (owner TEXT NOT NULL, sequence INTEGER NOT NULL, body TEXT NOT NULL CHECK(json_valid(body)), PRIMARY KEY(owner,sequence)) STRICT",
  "CREATE TABLE ps_receipt (owner TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL CHECK(json_valid(body)), PRIMARY KEY(owner,id)) STRICT",
  "CREATE TABLE ps_nonce (owner TEXT NOT NULL, key TEXT NOT NULL, nonce TEXT NOT NULL, PRIMARY KEY(owner,key,nonce)) STRICT",
  "CREATE TABLE ps_view (owner TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(owner,id)) STRICT",
  "CREATE TABLE ps_cursor (owner TEXT NOT NULL, token TEXT NOT NULL, view TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(owner,token)) STRICT",
  "CREATE TABLE ps_view_nonce (owner TEXT NOT NULL, key TEXT NOT NULL, nonce TEXT NOT NULL, PRIMARY KEY(owner,key,nonce)) STRICT",
  "CREATE TRIGGER ps_profile_nonce_guard BEFORE INSERT ON ps_nonce WHEN EXISTS(SELECT 1 FROM ps_view_nonce WHERE owner=NEW.owner AND key=NEW.key AND nonce=NEW.nonce) BEGIN SELECT RAISE(ABORT,'nonce collision'); END",
  "CREATE TRIGGER ps_view_nonce_guard BEFORE INSERT ON ps_view_nonce WHEN EXISTS(SELECT 1 FROM ps_nonce WHERE owner=NEW.owner AND key=NEW.key AND nonce=NEW.nonce) BEGIN SELECT RAISE(ABORT,'nonce collision'); END",
  "CREATE TABLE ps_guard (value INTEGER NOT NULL CHECK(value=1)) STRICT",
] as const;
export interface ProfileSqlKey { readonly id: string; readonly version: number }
/** Proposed configurable seam, NOT ConfigurationPrivacyPolicy approval. No lifecycle
 * defaults: this candidate retains all bounded fixture rows and performs no erasure. */
export interface SyntheticSqlPolicy {
  readonly fixtureOnly: true; readonly version: string;
  readonly maxProfiles: number; readonly maxEvents: number; readonly maxReceipts: number; readonly maxEncryptedBytes: number;
}
export interface SyntheticProfileSqlPorts {
  readonly sentinel: "healthmd.profile-sync.sql.synthetic-only";
  readonly sql: ProfileSqlPort; readonly authority: SyntheticNativeAuthority;
  readonly policy: SyntheticSqlPolicy;
  readonly keyReference: (owner: string) => ProfileSqlKey;
  readonly resolveKey: (owner: string, reference: ProfileSqlKey) => Promise<CryptoKey>;
  /** Timing only, never replaces actual crypto or SQL evidence. */
  readonly clock?: () => number; // synthetic source lease clock; SQL independently fences database time
  readonly afterCrypto?: () => Promise<void>;
}
type Fixed = Readonly<{ schema: "healthmd.profile_sync"; schema_version: 1; result: ProfileSyncV1ErrorResult }>;
type Result = Readonly<{ ok: true; record: ValidatedProfileSyncV1Record }> | Fixed;
type Control = Readonly<{ ok: true }> | Fixed;
export interface ProfileSqlCandidate {
  optIn(request: Request): Promise<Control>;
  withdraw(request: Request): Promise<Control>;
  select(request: Request, originalBytes: Uint8Array): Promise<Control>;
  mutate(request: Request, originalBytes: Uint8Array): Promise<Result>;
  read(request: Request, originalBytes: Uint8Array): Promise<Result>;
  readPage(request: Request, originalBytes: Uint8Array): Promise<Uint8Array>;
}
type Meta = { profile_id: string; object_revision: number; event_sequence: number; order_key: number | null;
  deleted: boolean; content_revision: number | null; content_hash: string | null };
type Sealed = { key: ProfileSqlKey; nonce: string; ciphertext: string };
type Revision = { meta: Meta; sealed: Sealed; plaintextBytes: number };
type Receipt = { id: string; requestHash: string; meta: Meta; sealed: Sealed };
type Head = { meta: Meta; receipt: string };
type Event = { meta: Meta; receipt: string };
type Partition = { consent: boolean; consentEpoch: number; selectionEpoch: number;
  intent: { hash: string; session: string; generation: number } | null; selected: string[];
  key: ProfileSqlKey; policy: string; sequence: number;
  usage: { profiles: number; revisions: number; events: number; receipts: number; plaintextBytes: number; encryptedBytes: number } };
type Snapshot = { auth: AuthState; authVersion: number; version: number; partition: Partition;
  heads: Head[]; revisions: Revision[]; events: Event[]; receipts: Receipt[] };
const MUTATE = "/api/profile-sync/v1/mutate", READ = "/api/profile-sync/v1/read";
const encode = (s: string) => new TextEncoder().encode(s);
// Metadata object property order is irrelevant; content remains an EXACT string.
function comparable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(comparable);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => [k, comparable(v)]));
  return value;
}
const equal = (a: unknown, b: unknown) => JSON.stringify(comparable(a)) === JSON.stringify(comparable(b));
const fixed = (result: ProfileSyncV1ErrorResult = "unavailable"): Fixed => Object.freeze({ schema: "healthmd.profile_sync", schema_version: 1, result });
const ok = Object.freeze({ ok: true as const });
const statement = (sql: string, ...values: SqlValue[]): ProfileSqlStatement => ({ sql, values });
function requireValue(value: unknown, category: ProfileSyncV1ErrorResult = "verification_pending"): asserts value {
  if (!value) throw new ProfileSyncV1Error(category);
}
function next(value: number): number { requireValue(Number.isSafeInteger(value) && value >= 0 && value < Number.MAX_SAFE_INTEGER); return value + 1; }
function own(bytes: Uint8Array, max = 4_194_304): Uint8Array<ArrayBuffer> {
  requireValue(bytes instanceof Uint8Array && bytes.length > 0 && bytes.length <= max && !(typeof SharedArrayBuffer !== "undefined" && bytes.buffer instanceof SharedArrayBuffer), "invalid");
  return new Uint8Array(bytes);
}
function hex(bytes: Uint8Array): string { return Array.from(bytes, n => n.toString(16).padStart(2, "0")).join(""); }
function unhex(value: string): Uint8Array<ArrayBuffer> {
  requireValue(typeof value === "string" && /^(?:[0-9a-f]{2})+$/u.test(value));
  return Uint8Array.from(value.match(/../gu)!, b => parseInt(b, 16));
}
function metadata(record: ValidatedProfileSyncV1Record): Meta {
  return { profile_id: record.profileId, object_revision: record.objectRevision, event_sequence: record.eventSequence,
    order_key: record.orderKey, deleted: record.deleted, content_revision: record.contentRevision, content_hash: record.content?.hash ?? null };
}
/** Append after every LIVE head, independent of event count or retired IDs.
 * Invalid persisted keys are not silently normalized; an exhausted order space
 * denies the create atomically rather than wrapping, tying or renumbering. */
function appendOrderKey(heads: readonly Head[]): number {
  let maximum = -1;
  for (const head of heads) {
    requireValue(typeof head.meta.deleted === "boolean");
    if (head.meta.deleted) continue;
    const key = head.meta.order_key;
    requireValue(key !== null && Number.isSafeInteger(key) && key >= 0 && !Object.is(key, -0));
    if (key > maximum) maximum = key;
  }
  requireValue(maximum < Number.MAX_SAFE_INTEGER, "quota_exceeded");
  return maximum + 1;
}
function bytesIn(seal: Sealed): number { return (seal.nonce.length + seal.ciphertext.length) / 2; }
function empty(key: ProfileSqlKey, policy: string): Partition {
  return { consent: false, consentEpoch: 0, selectionEpoch: 0, intent: null, selected: [], key, policy, sequence: 0,
    usage: { profiles: 0, revisions: 0, events: 0, receipts: 0, plaintextBytes: 0, encryptedBytes: 0 } };
}
/** Default stays unavailable even if a caller passes partial/claimed production policy.
 * Only explicit synthetic ports are accepted; there is no production approval boolean. */
export function createProfileSqlCandidate(ports?: SyntheticProfileSqlPorts): ProfileSqlCandidate {
  if (!ports) {
    const unavailable = async () => fixed();
    return Object.freeze({ optIn: unavailable, withdraw: unavailable, select: unavailable, mutate: unavailable, read: unavailable, readPage: async () => encode(JSON.stringify(fixed())) });
  }
  requireValue(ports.sentinel === "healthmd.profile-sync.sql.synthetic-only" && ports.policy.fixtureOnly === true, "unavailable");
  const p = ports, policy = structuredClone(p.policy);
  requireValue(policy.version.length > 0 && [policy.maxProfiles, policy.maxEvents, policy.maxReceipts, policy.maxEncryptedBytes]
    .every(n => Number.isSafeInteger(n) && n > 0) && policy.maxProfiles <= 100 && policy.maxEvents <= 256 &&
    policy.maxReceipts <= 512 && policy.maxEncryptedBytes <= 1_048_576, "unavailable");
  const ownerOf = (principal: ConfigPrincipal) => JSON.stringify([principal.issuer, principal.environment, principal.accountId]);
  async function authenticate(request: Request, path: string): Promise<ConfigPrincipal> {
    requireValue(request.method === "POST" && request.url === p.authority.registration.issuer + path && !request.headers.has("Cookie"), "unavailable");
    const token = /^Bearer (hmd_nac_[A-Za-z0-9_-]{43})$/u.exec(request.headers.get("Authorization") ?? "")?.[1];
    requireValue(token, "unavailable");
    return p.authority.authorizeConfig(token, "POST", path);
  }
  async function snapshot(owner: string): Promise<Snapshot> {
    const rows = await p.sql.batch([
      statement("SELECT version,body FROM ps_authority WHERE id=1"),
      statement("SELECT version,body FROM ps_partition WHERE owner=?", owner),
      statement("SELECT body FROM ps_head WHERE owner=? ORDER BY id LIMIT 101", owner),
      statement("SELECT body FROM ps_revision WHERE owner=? ORDER BY id,revision LIMIT 257", owner),
      statement("SELECT body FROM ps_event WHERE owner=? ORDER BY sequence LIMIT 257", owner),
      statement("SELECT body FROM ps_receipt WHERE owner=? ORDER BY id LIMIT 513", owner),
      statement("SELECT key,nonce FROM ps_nonce WHERE owner=? ORDER BY key,nonce LIMIT 769", owner),
    ]);
    // Bound the decoded aggregate before parsing stored JSON. This is a finite
    // fixture candidate, not an unbounded account-history loader.
    requireValue(rows.flat().reduce((total, row) => total + (typeof row.body === "string" ? encode(row.body).length : 0), 0) <= 4_194_304);
    const auth = rows[0]?.[0], partition = rows[1]?.[0];
    requireValue(auth && Number.isSafeInteger(auth.version) && typeof auth.body === "string");
    const bodies = <T>(at: number): T[] => (rows[at] ?? []).map(row => {
      requireValue(typeof row.body === "string"); return JSON.parse(row.body) as T;
    });
    const result: Snapshot = { auth: JSON.parse(auth.body) as AuthState, authVersion: Number(auth.version),
      version: partition ? Number(partition.version) : -1,
      partition: partition ? JSON.parse(String(partition.body)) as Partition : empty(p.keyReference(owner), policy.version),
      heads: bodies<Head>(2), revisions: bodies<Revision>(3), events: bodies<Event>(4), receipts: bodies<Receipt>(5) };
    const s = result.partition, u = s.usage;
    requireValue(result.heads.length <= policy.maxProfiles && result.revisions.length <= 256 && result.events.length <= policy.maxEvents &&
      result.receipts.length <= policy.maxReceipts && s.policy === policy.version && equal(s.key, p.keyReference(owner)) &&
      u.profiles === result.heads.filter(h => !h.meta.deleted).length && u.revisions === result.revisions.length &&
      u.events === result.events.length && u.receipts === result.receipts.length && s.sequence === result.events.length &&
      u.plaintextBytes === result.revisions.reduce((sum, r) => sum + r.plaintextBytes, 0) &&
      result.heads.every(h => result.receipts.some(r => r.id === h.receipt && equal(r.meta, h.meta)) &&
        equal(result.events.filter(e => e.meta.profile_id === h.meta.profile_id).at(-1), h)) &&
      result.events.every((e, index) => e.meta.event_sequence === index + 1 && result.receipts.some(r => r.id === e.receipt && equal(r.meta, e.meta))) &&
      u.encryptedBytes === [...result.revisions, ...result.receipts].reduce((sum, r) => sum + bytesIn(r.sealed), 0) &&
      Number.isSafeInteger(u.encryptedBytes) && u.encryptedBytes <= policy.maxEncryptedBytes &&
      rows[6]?.length === result.revisions.length + result.receipts.length &&
      [...result.revisions, ...result.receipts].every(r => rows[6]!.some(n => n.key === JSON.stringify(r.sealed.key) && n.nonce === r.sealed.nonce)));
    requireValue(result.version >= -1 && Number.isSafeInteger(result.version) &&
      Number.isSafeInteger(s.consentEpoch) && s.consentEpoch >= 0 && Number.isSafeInteger(s.selectionEpoch) && s.selectionEpoch >= 0 &&
      s.selected.length <= policy.maxProfiles && new Set(s.selected).size === s.selected.length &&
      s.selected.every(id => result.heads.some(h => h.meta.profile_id === id)));
    return result;
  }
  function authorized(s: Snapshot, principal: ConfigPrincipal, path: string, consent = true): void {
    p.authority.assertConfigAtCommit(s.auth, principal, "POST", path); // original module-issued object, never serialized/rebound
    requireValue(principal.environment === "synthetic" && (!consent || s.partition.consent), "unavailable");
  }
  function gate(s: Snapshot, captured: Snapshot, principal: ConfigPrincipal, path: string): void {
    authorized(s, principal, path);
    requireValue(s.partition.consentEpoch === captured.partition.consentEpoch &&
      s.partition.selectionEpoch === captured.partition.selectionEpoch && equal(s.partition.key, captured.partition.key), "intent_expired");
  }
  async function commit(owner: string, s: Snapshot, partition: Partition, changes: ProfileSqlStatement[], principal: ConfigPrincipal, path = MUTATE, lease = Number.MAX_SAFE_INTEGER): Promise<void> {
    authorized(s, principal, path, false);
    // Only AS02 can resolve the actual authorizing access row. A refreshed
    // family's current generation does not identify an older valid access token.
    const validUntil = Math.min(lease, p.authority.configAccessDeadlineAtCommit(s.auth, principal, "POST", path));
    requireValue(Number.isSafeInteger(validUntil), "unavailable");
    // The CHECK failure aborts the ENTIRE D1 batch. A zero-row UPDATE is never success.
    // The auth body was checked above. Its version cannot change between that check
    // and linearization; disable/revoke/refresh advance it in the same DB transaction.
    await p.sql.batch([
      statement("INSERT INTO ps_guard(value) SELECT CASE WHEN (SELECT version FROM ps_authority WHERE id=1)=? AND unixepoch()<? AND COALESCE((SELECT version FROM ps_partition WHERE owner=?),-1)=? THEN 1 ELSE 0 END", s.authVersion, validUntil, owner, s.version),
      ...changes,
      statement("INSERT INTO ps_partition(owner,version,body) VALUES(?,?,?) ON CONFLICT(owner) DO UPDATE SET version=excluded.version,body=excluded.body", owner, next(s.version + 1) - 1, JSON.stringify(partition)),
      statement("DELETE FROM ps_guard"),
    ]);
  }
  async function key(owner: string, reference: ProfileSqlKey): Promise<CryptoKey> {
    const handle = await p.resolveKey(owner, Object.freeze({ ...reference }));
    requireValue(handle.type === "secret" && !handle.extractable && handle.algorithm.name === "AES-GCM" &&
      (handle.algorithm as AesKeyAlgorithm).length === 256 && handle.usages.includes("encrypt") && handle.usages.includes("decrypt"));
    return handle;
  }
  function aad(owner: string, purpose: string, context: unknown, reference: ProfileSqlKey): Uint8Array<ArrayBuffer> {
    return encode(JSON.stringify(["healthmd.profile-sync.sql/v1", "healthmd.profile_sync.portable", 1, owner, purpose, context, reference]));
  }
  async function seal(owner: string, purpose: string, context: unknown, reference: ProfileSqlKey, bytes: Uint8Array<ArrayBuffer>): Promise<Sealed> {
    const handle = await key(owner, reference), nonce = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad(owner, purpose, context, reference) }, handle, bytes);
    await p.afterCrypto?.();
    return { key: { ...reference }, nonce: hex(nonce), ciphertext: hex(new Uint8Array(ciphertext)) };
  }
  async function open(owner: string, purpose: string, context: unknown, sealed: Sealed): Promise<ValidatedProfileSyncV1Record> {
    requireValue(sealed.nonce.length === 24 && sealed.ciphertext.length >= 32);
    const handle = await key(owner, sealed.key);
    const plain = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: unhex(sealed.nonce),
      additionalData: aad(owner, purpose, context, sealed.key) }, handle, unhex(sealed.ciphertext)));
    const record = await ValidatedProfileSyncV1Record.parse(plain);
    await p.afterCrypto?.(); return record;
  }
  const receiptContext = (r: Receipt) => [r.id, r.requestHash, r.meta];
  const revisionContext = (r: Revision) => [r.meta.profile_id, r.meta.content_revision, r.meta.content_hash];
  async function verify(owner: string, s: Snapshot, receipt: Receipt): Promise<ValidatedProfileSyncV1Record> {
    const stored = s.receipts.find(r => r.id === receipt.id);
    requireValue(stored && equal(stored, receipt));
    const record = await open(owner, "receipt", receiptContext(stored), stored.sealed);
    requireValue(equal(metadata(record), stored.meta));
    // Every effective event/head points to the exact original authenticated receipt.
    const event = s.events.find(e => e.meta.event_sequence === record.eventSequence);
    requireValue(event && equal(event.meta, stored.meta));
    if (record.content) {
      const revision = s.revisions.find(r => r.meta.profile_id === record.profileId && r.meta.content_revision === record.contentRevision);
      requireValue(revision && revision.meta.content_hash === record.content.hash);
      const original = await open(owner, "revision", revisionContext(revision), revision.sealed);
      requireValue(equal(metadata(original), revision.meta) && original.content?.contentJson === record.content.contentJson &&
        revision.plaintextBytes === encode(record.content.contentJson).length);
    }
    return record;
  }
  async function control(request: Request, consent: boolean): Promise<Control> {
    try {
      const principal = await authenticate(request, MUTATE), owner = ownerOf(principal), s = await snapshot(owner);
      authorized(s, principal, MUTATE, false);
      const partition = structuredClone(s.partition); partition.consent = consent;
      partition.consentEpoch = next(partition.consentEpoch); partition.selectionEpoch = next(partition.selectionEpoch); partition.intent = null;
      try { await commit(owner, s, partition, [], principal); } catch { /* readback decides */ }
      const fresh = await snapshot(owner); authorized(fresh, principal, MUTATE, false);
      requireValue(equal(fresh.partition, partition)); return ok;
    } catch { return fixed(); }
  }
  type View = { id: string; binding: string; mode: "snapshot"; high: number;
    expires: number; consent: number; selection: number; limit: number; refs: string[]; tokens: string[] };
  const now = () => { const value = p.clock?.() ?? Math.floor(Date.now() / 1000);
    requireValue(Number.isSafeInteger(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER - 900); return value; };
  async function document(owner: string, purpose: string, context: unknown, sealed: Sealed): Promise<unknown> {
    requireValue(sealed.nonce.length === 24 && sealed.ciphertext.length <= 262144);
    const handle = await key(owner, sealed.key);
    const bytes = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: unhex(sealed.nonce),
      additionalData: aad(owner, purpose, context, sealed.key) }, handle, unhex(sealed.ciphertext)));
    await p.afterCrypto?.(); return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  }
  async function readPage(request: Request, originalBytes: Uint8Array): Promise<Uint8Array> {
    try {
      const bytes = own(originalBytes, 8192), principal = await authenticate(request, READ), owner = ownerOf(principal);
      const selector = parseProfileSyncV1Read(bytes); requireValue(selector.mode !== "revision", "invalid");
      requireValue(selector.mode === "snapshot", "resync_required"); // changes baseline/ACK protocol remains unresolved; never advance on send
      const s = await snapshot(owner); authorized(s, principal, READ);
      const binding = JSON.stringify([principal.clientId, principal.installationId]);
      let view: View, position = 0, changes: ProfileSqlStatement[] = [];
      if (selector.cursor !== null) {
        const found = await p.sql.batch([statement("SELECT view,position FROM ps_cursor WHERE owner=? AND token=?", owner, selector.cursor)]);
        const cursor = found[0]?.[0]; requireValue(cursor && typeof cursor.view === "string" && Number.isSafeInteger(cursor.position), "resync_required");
        const rows = await p.sql.batch([statement("SELECT body FROM ps_view WHERE owner=? AND id=?", owner, cursor.view)]);
        requireValue(typeof rows[0]?.[0]?.body === "string", "resync_required");
        view = await document(owner, "view", cursor.view, JSON.parse(rows[0]![0]!.body as string) as Sealed) as View;
        position = Number(cursor.position);
        requireValue(view.id === cursor.view && position > 0 && view.tokens[position] === selector.cursor, "resync_required");
      } else {
        const counts = await p.sql.batch([statement("SELECT count(*) AS count FROM ps_view WHERE owner=?", owner)]);
        requireValue(Number(counts[0]?.[0]?.count) < 8, "quota_exceeded"); // finite synthetic view cap, no eviction/retention policy
        const refs = s.heads.filter(h => !h.meta.deleted).sort((a, b) =>
          a.meta.order_key! - b.meta.order_key! || (a.meta.profile_id < b.meta.profile_id ? -1 : 1)).map(h => h.receipt);
        requireValue(refs.length <= 100, "resync_required");
        const id = "pss_" + hex(crypto.getRandomValues(new Uint8Array(16))), high = s.partition.sequence;
        view = { id, binding, mode: selector.mode, high, expires: now() + 900, consent: s.partition.consentEpoch,
          selection: s.partition.selectionEpoch, limit: selector.limit, refs, tokens: refs.map(() => "psc_" + hex(crypto.getRandomValues(new Uint8Array(32)))) };
        const sealed = await seal(owner, "view", id, s.partition.key, encode(JSON.stringify(view)));
        for (const value of [sealed]) changes.push(statement("INSERT INTO ps_view_nonce VALUES(?,?,?)", owner, JSON.stringify(value.key), value.nonce));
        changes.push(statement("INSERT INTO ps_view VALUES(?,?,?)", owner, id, JSON.stringify(sealed)));
        changes.push(statement("INSERT INTO ps_cursor SELECT ?,value,?,CAST(key AS INTEGER) FROM json_each(?) WHERE CAST(key AS INTEGER)>0", owner, id, JSON.stringify(view.tokens)));
      }
      requireValue(view.binding === binding && view.mode === selector.mode && view.limit === selector.limit && view.expires > now() &&
        view.consent === s.partition.consentEpoch && view.high <= s.partition.sequence, "resync_required");
      const items: unknown[] = []; let end = position;
      const wire = (nextCursor: string | null) => encode(JSON.stringify({ schema: "healthmd.profile_sync", schema_version: 1,
        mode: view.mode, snapshot_id: view.id, high_watermark: view.high, items, next_cursor: nextCursor, complete: nextCursor === null }));
      while (end < view.refs.length && items.length < selector.limit) {
        const receipt = s.receipts.find(r => r.id === view.refs[end]); requireValue(receipt, "resync_required");
        requireValue(s.partition.selected.includes(receipt.meta.profile_id), "resync_required");
        const record = await verify(owner, s, receipt);
        requireValue(record.eventSequence <= view.high, "resync_required");
        items.push({ schema: "healthmd.profile_sync", schema_version: 1, ...metadata(record), content_json: record.content?.contentJson ?? null });
        if (wire(end + 1 < view.refs.length ? view.tokens[end + 1]! : null).length > 4_194_304) { items.pop(); break; }
        end++;
      }
      requireValue(end === view.refs.length || items.length > 0, "quota_exceeded");
      const complete = end === view.refs.length;
      const reply = wire(complete ? null : view.tokens[end]!); await parseProfileSyncV1Page(reply);
      const fresh = await snapshot(owner); gate(fresh, s, principal, READ);
      requireValue(fresh.version === s.version && fresh.authVersion === s.authVersion && now() < view.expires, "resync_required");
      if (changes.length) {
        try { await commit(owner, s, s.partition, changes, principal, READ, view.expires); } catch { /* exact readback below, including lost ACK */ }
        const rows = await p.sql.batch([statement("SELECT body FROM ps_view WHERE owner=? AND id=?", owner, view.id)]);
        requireValue(typeof rows[0]?.[0]?.body === "string", "verification_pending");
        const actual = await document(owner, "view", view.id, JSON.parse(rows[0]![0]!.body as string) as Sealed);
        requireValue(equal(actual, view), "verification_pending");

      }
      const final = await snapshot(owner); gate(final, s, principal, READ); requireValue(now() < view.expires, "resync_required");
      return reply;
    } catch (error) {
      const category = error instanceof ProfileSyncV1Error && ["resync_required", "quota_exceeded", "invalid"].includes(error.category) ? error.category as ProfileSyncV1ErrorResult : "unavailable";
      return encode(JSON.stringify(fixed(category)));
    }
  }
  return Object.freeze({
    readPage,
    optIn: (request: Request) => control(request, true), withdraw: (request: Request) => control(request, false),
    async select(request: Request, originalBytes: Uint8Array): Promise<Control> {
      try {
        const bytes = own(originalBytes), principal = await authenticate(request, MUTATE), owner = ownerOf(principal);
        const s = await snapshot(owner); authorized(s, principal, MUTATE);
        const mutation = await parseProfileSyncV1Mutation(bytes);
        requireValue(mutation.profileId === null || s.partition.selected.includes(mutation.profileId), "not_found");
        const partition = structuredClone(s.partition); partition.selectionEpoch = next(partition.selectionEpoch);
        partition.intent = { hash: mutation.requestHash, session: principal.sessionId, generation: principal.sessionGeneration };
        try { await commit(owner, s, partition, [], principal); } catch { /* readback decides */ }
        const fresh = await snapshot(owner); authorized(fresh, principal, MUTATE);
        requireValue(equal(fresh.partition, partition)); return ok;
      } catch { return fixed(); }
    },
    async mutate(request: Request, originalBytes: Uint8Array): Promise<Result> {
      let attempted = false;
      try {
        const bytes = own(originalBytes), principal = await authenticate(request, MUTATE), owner = ownerOf(principal);
        const s = await snapshot(owner); authorized(s, principal, MUTATE);
        const mutation = await parseProfileSyncV1Mutation(bytes), intent = s.partition.intent;
        requireValue(intent?.hash === mutation.requestHash && intent.session === principal.sessionId &&
          intent.generation === principal.sessionGeneration, "intent_expired");
        let receipt = s.receipts.find(r => r.id === mutation.mutationId);
        if (receipt) {
          requireValue(receipt.requestHash === mutation.requestHash, "idempotency_mismatch");
        } else {
          const partition = structuredClone(s.partition), changes: ProfileSqlStatement[] = [];
          let prior: ValidatedProfileSyncV1Record | null = null;
          if (mutation.profileId !== null) {
            requireValue(partition.selected.includes(mutation.profileId), "not_found");
            const head = s.heads.find(h => h.meta.profile_id === mutation.profileId); requireValue(head, "not_found");
            const original = s.receipts.find(r => r.id === head.receipt); requireValue(original && equal(original.meta, head.meta));
            prior = await verify(owner, s, original); requireValue(!prior.deleted, "gone");
            requireValue(prior.objectRevision === mutation.baseRevision, "conflict");
          }
          const content = mutation.operation === "delete" ? null : mutation.content ?? prior?.content ?? null;
          const effective = !prior || mutation.operation === "delete" || (mutation.operation === "reorder" ? mutation.orderKey !== prior.orderKey : content?.contentJson !== prior.content?.contentJson);
          const createOrder = prior ? null : appendOrderKey(s.heads);
          const id = prior?.profileId ?? "psp_" + hex(crypto.getRandomValues(new Uint8Array(16)));
          const meta: Meta = effective ? { profile_id: id, object_revision: prior ? next(prior.objectRevision) : 1,
            event_sequence: next(partition.sequence), deleted: mutation.operation === "delete",
            order_key: mutation.operation === "delete" ? null : mutation.operation === "reorder" ? mutation.orderKey : prior ? prior.orderKey : createOrder,
            content_revision: !content ? null : prior?.content?.contentJson === content.contentJson ? prior.contentRevision : prior?.contentRevision ? next(prior.contentRevision) : 1,
            content_hash: content?.hash ?? null } : metadata(prior!);
          const recordBytes = encode(JSON.stringify({ schema: "healthmd.profile_sync", schema_version: 1, ...meta, content_json: content?.contentJson ?? null }));
          const validated = await ValidatedProfileSyncV1Record.parse(recordBytes); requireValue(equal(metadata(validated), meta));
          const addNonce = (sealed: Sealed) => changes.push(statement("INSERT INTO ps_nonce VALUES(?,?,?)", owner, JSON.stringify(sealed.key), sealed.nonce));
          if (content && (!prior || prior.content?.contentJson !== content.contentJson)) {
            const revision: Revision = { meta, plaintextBytes: encode(content.contentJson).length,
              sealed: await seal(owner, "revision", [id, meta.content_revision, meta.content_hash], partition.key, recordBytes) };
            addNonce(revision.sealed); changes.push(statement("INSERT INTO ps_revision VALUES(?,?,?,?)", owner, id, meta.content_revision, JSON.stringify(revision)));
            partition.usage.revisions = next(partition.usage.revisions); partition.usage.plaintextBytes += revision.plaintextBytes;
            partition.usage.encryptedBytes += bytesIn(revision.sealed);
          }
          const shell = { id: mutation.mutationId, requestHash: mutation.requestHash, meta };
          receipt = { ...shell, sealed: await seal(owner, "receipt", [shell.id, shell.requestHash, meta], partition.key, recordBytes) };
          addNonce(receipt.sealed); changes.push(statement("INSERT INTO ps_receipt VALUES(?,?,?)", owner, receipt.id, JSON.stringify(receipt)));
          partition.usage.receipts = next(partition.usage.receipts); partition.usage.encryptedBytes += bytesIn(receipt.sealed);
          if (effective) {
            const event: Event = { meta, receipt: receipt.id };
            changes.push(statement("INSERT INTO ps_event VALUES(?,?,?)", owner, meta.event_sequence, JSON.stringify(event)),
              statement("INSERT INTO ps_head VALUES(?,?,?) ON CONFLICT(owner,id) DO UPDATE SET body=excluded.body", owner, id, JSON.stringify(event)));
            partition.sequence = meta.event_sequence; partition.usage.events = next(partition.usage.events);
            if (!prior) { partition.selected.push(id); partition.usage.profiles = next(partition.usage.profiles); }
            if (meta.deleted) partition.usage.profiles--;
          }
          requireValue(s.heads.length + (prior ? 0 : 1) <= policy.maxProfiles && partition.usage.revisions <= 256 &&
            partition.usage.events <= policy.maxEvents && partition.usage.receipts <= policy.maxReceipts &&
            partition.usage.encryptedBytes <= policy.maxEncryptedBytes, "quota_exceeded");
          // Recheck live time/session after crypto; SQL then fences the exact fresh
          // authority and partition versions checked here. No JS transaction callback.
          const before = await snapshot(owner); gate(before, s, principal, MUTATE);
          requireValue(before.version === s.version && before.authVersion === s.authVersion, "conflict");
          attempted = true;
          try { await commit(owner, s, partition, changes, principal); } catch { /* a lost ACK is ambiguous; only exact readback proves success */ }
        }
        const fresh = await snapshot(owner); gate(fresh, s, principal, MUTATE);
        const record = await verify(owner, fresh, receipt);
        const final = await snapshot(owner); gate(final, s, principal, MUTATE);
        requireValue(final.version === fresh.version && final.authVersion === fresh.authVersion &&
          equal(final.receipts.find(r => r.id === receipt.id), receipt));
        return Object.freeze({ ok: true, record });
      } catch (error) {
        const allowed: readonly string[] = ["unavailable", "invalid", "requires_upgrade", "conflict", "gone", "not_found", "idempotency_mismatch", "intent_expired", "verification_pending", "quota_exceeded"];
        return fixed(error instanceof ProfileSyncV1Error ? allowed.includes(error.category) ? error.category as ProfileSyncV1ErrorResult : "invalid" : attempted ? "verification_pending" : "unavailable");
      }
    },
    async read(request: Request, originalBytes: Uint8Array): Promise<Result> {
      try {
        const bytes = own(originalBytes, 8192), principal = await authenticate(request, READ), owner = ownerOf(principal);
        const selector = parseProfileSyncV1Read(bytes); requireValue(selector.mode === "revision", "unavailable");
        const s = await snapshot(owner); authorized(s, principal, READ);
        requireValue(s.partition.selected.includes(selector.profileId), "not_found");
        const revision = s.revisions.find(r => r.meta.profile_id === selector.profileId && r.meta.content_revision === selector.contentRevision && r.meta.content_hash === selector.contentHash);
        requireValue(revision, "not_found");
        const record = await open(owner, "revision", revisionContext(revision), revision.sealed);
        requireValue(equal(metadata(record), revision.meta) && record.content?.hash === selector.contentHash);
        const fresh = await snapshot(owner); gate(fresh, s, principal, READ);
        requireValue(fresh.version === s.version && fresh.authVersion === s.authVersion);
        return Object.freeze({ ok: true, record });
      } catch (error) { return fixed(error instanceof ProfileSyncV1Error && error.category === "not_found" ? "not_found" : "verification_pending"); }
    },
  });
}
