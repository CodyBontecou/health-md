// Inactive synthetic SOURCE only. Imported by tests, never by a router/app factory.
// ONE RAM aggregate; no durable/privacy/retention/region/key-custody approval.
// Only selected create + exact immutable read are in scope. No CRUD/CAS/replay,
// feeds/tombstones/reset/deletion/rotation/browser configuration or native apply.
import { SyntheticNativeAuthority } from "./account-auth-v1/authority";
import { purposeRateKey } from "./account-auth-v1/crypto";
import { createNativeAuthHttp } from "./account-auth-v1/http";
import { AuthError, emptyAuthState, type AuthState, type AuthStore, type ConfigPrincipal,
  type Registration } from "./account-auth-v1/model";
import { parseProfileSyncV1Mutation, parseProfileSyncV1Read, ProfileSyncV1Error,
  type ProfileSyncV1Mutation, type ProfileSyncV1ErrorResult,
  ValidatedProfileSyncV1Content, ValidatedProfileSyncV1Record } from "./profile-sync-v1-contract";

export interface SyntheticRamInjection {
  readonly sentinel: "healthmd.profile-sync.v1.ram.synthetic-only";
  readonly clock?: () => number;
  /** Timing only: receives completion, NOT key/plaintext/ciphertext or authority.
   * The module separately awaits its OWN real crypto result even if this returns early. */
  readonly waitForCrypto?: (phase: "prepare" | "readback", completion: Promise<void>) => Promise<void>;
}
type Fixed = Readonly<{ schema: "healthmd.profile_sync"; schema_version: 1; result: ProfileSyncV1ErrorResult }>;
type Success = Readonly<{ ok: true; record: ValidatedProfileSyncV1Record }>;
type Control = Readonly<{ ok: true }>;
type Namespace = { issuer: string; environment: string; accountId: string };
type KeyReference = { id: string; version: number; epoch: number };
type Intent = {
  epoch: number; consentEpoch: number; keyEpoch: number; keyVersion: number;
  mutationId: string; requestHash: string; contentHash: string; requestBytes: number; contentBytes: number;
  sessionId: string; sessionGeneration: number; requiresAction: string[]; publishedProfileId: string | null;
};
type Head = {
  profileId: string; objectRevision: number; eventSequence: number; orderKey: number;
  contentRevision: number; contentHash: string; revisionSlot: string;
};
type Correlation = {
  namespace: Namespace; head: Head; mutationId: string; requestHash: string; requestBytes: number;
  contentBytes: number; intentEpoch: number; consentEpoch: number; key: KeyReference;
  sessionId: string; sessionGeneration: number; requiresAction: string[];
};
// Binary extent is HPCR + version byte + 96-bit nonce + GCM ciphertext/tag.
// Format/version labels are diagnostic metadata, not serialized plaintext content.
type Envelope = { format: "healthmd.profile-sync.ram.config"; version: 1; header: number[]; nonce: number[]; ciphertext: number[] };
type Revision = { correlation: Correlation; cipherSlot: string };
type Partition = {
  heads: Record<string, Head>; revisions: Record<string, Revision>; cipherSlots: Record<string, Envelope>;
  events: Correlation[]; receipts: Record<string, Correlation>; evidence: Record<string, Correlation>;
  idempotencyIndex: Record<string, string>; revisionIndex: Record<string, string[]>;
  issuedIds: string[]; nonceIndex: Record<string, string>; sequence: number;
  usage: { plaintextBytes: number; encryptedBytes: number; profiles: number; revisions: number; events: number; receipts: number };
  reservations: Record<string, never>; retainedStaging: Record<string, never>;
};
type Controls = { consent: { optedIn: boolean; epoch: number }; selectionEpoch: number; intent: Intent | null };
type Aggregate = { auth: AuthState; controls: Controls; key: KeyReference & { handle: CryptoKey }; profile: Partition };
export type SyntheticRamObservation = Readonly<{
  admittedPorts: number;
  controls: readonly { namespace: Namespace; consent: Controls["consent"]; selectionEpoch: number;
    intent: Intent | null; key: KeyReference }[];
  partitions: readonly { namespace: Namespace; values: Partition }[];
}>;
export interface ProfileSyncV1Ram {
  auth(request: Request): Promise<Response>;
  optIn(request: Request): Promise<Control | Fixed>;
  withdraw(request: Request): Promise<Control | Fixed>;
  selectCreate(request: Request, originalBytes: Uint8Array): Promise<Control | Fixed>;
  mutate(request: Request, originalBytes: Uint8Array): Promise<Success | Fixed>;
  read(request: Request, originalBytes: Uint8Array): Promise<Success | Fixed>;
  /** Complete, detached synthetic diagnostic. Not a credential or permission input. */
  observe(): SyntheticRamObservation;
}
const SENTINEL = "healthmd.profile-sync.v1.ram.synthetic-only";
const MUTATE = "/api/profile-sync/v1/mutate", READ = "/api/profile-sync/v1/read";
const ORIGIN = "https://account-auth.synthetic.example";
const OWNER = "synthetic-account-as06", BROWSER = "synthetic-browser-as06";
const namespace: Namespace = Object.freeze({ issuer: ORIGIN, environment: "synthetic", accountId: OWNER });
const registration: Registration = Object.freeze({ issuer: ORIGIN, environment: "synthetic",
  audience: "urn:healthmd:account-config:synthetic:v1", clients: Object.freeze([
    Object.freeze({ client_id: "synthetic-apple-ios", platform: "apple", callback: "https://callbacks.account-sync.example/apple-ios/return" }),
  ]) });
const encoder = new TextEncoder();
const fixed = (result: ProfileSyncV1ErrorResult = "unavailable"): Fixed => Object.freeze({ schema: "healthmd.profile_sync", schema_version: 1, result });
const ok: Control = Object.freeze({ ok: true });
function deny(): never { throw new AuthError("unavailable"); }
function freeze<T>(value: T): T {
  if (value && typeof value === "object") { for (const child of Object.values(value)) freeze(child); Object.freeze(value); }
  return value;
}
function emptyPartition(): Partition {
  return { heads: {}, revisions: {}, cipherSlots: {}, events: [], receipts: {}, evidence: {}, idempotencyIndex: {},
    revisionIndex: {}, issuedIds: [], nonceIndex: {}, sequence: 0,
    usage: { plaintextBytes: 0, encryptedBytes: 0, profiles: 0, revisions: 0, events: 0, receipts: 0 },
    reservations: {}, retainedStaging: {} };
}
function clone(a: Aggregate): Aggregate {
  // CryptoKey is an immutable, private, nonextractable handle, NOT a returned data alias.
  return { auth: structuredClone(a.auth), controls: structuredClone(a.controls), key: { ...a.key }, profile: structuredClone(a.profile) };
}
function synchronous(value: unknown): void {
  if (value && (typeof value === "object" || typeof value === "function") && "then" in value) deny();
}
function callbackIsSync(callback: Function): void {
  if (["[object AsyncFunction]", "[object GeneratorFunction]", "[object AsyncGeneratorFunction]"].includes(Object.prototype.toString.call(callback))) deny();
}
function createMutation(m: ProfileSyncV1Mutation): asserts m is ProfileSyncV1Mutation & { content: ValidatedProfileSyncV1Content } {
  if (m.operation !== "create" || m.baseRevision !== 0 || m.profileId !== null || m.orderKey !== null ||
    !ValidatedProfileSyncV1Content.isValidated(m.content)) deny();
}
function same(a: unknown, b: unknown): boolean { return JSON.stringify(a) === JSON.stringify(b); }
function next(n: number): number { if (!Number.isSafeInteger(n) || n < 0 || n === Number.MAX_SAFE_INTEGER) deny(); return n + 1; }
class Unverified extends Error { constructor() { super("Synthetic immutable proof unavailable."); } }
function proofCheck(value: unknown): asserts value { if (!value) throw new Unverified(); }
const HEADER = Object.freeze([72, 80, 67, 82, 1]); // HPCR v1, configuration-only synthetic envelope
const QUOTA = 1_048_576; // bounded synthetic ciphertext budget; NOT a product storage/retention policy
function extent(e: Envelope): number { return e.header.length + e.nonce.length + e.ciphertext.length; }
function validEnvelope(e: Envelope, contentBytes: number): void {
  proofCheck(e.format === "healthmd.profile-sync.ram.config" && e.version === 1 && same(e.header, HEADER) &&
    e.nonce.length === 12 && e.ciphertext.length === contentBytes + 16 &&
    [...e.nonce, ...e.ciphertext].every(n => Number.isInteger(n) && n >= 0 && n <= 255));
}
function nonceId(e: Envelope, k: KeyReference): string { return `${k.id}:${k.epoch}:${e.nonce.join(",")}`; }
function keyRef(a: Aggregate): KeyReference { return { id: a.key.id, version: a.key.version, epoch: a.key.epoch }; }
/** Configuration ONLY; uint32-length-prefixed UTF-8 fields prevent delimiter ambiguity. */
function aad(c: Correlation): Uint8Array<ArrayBuffer> {
  const fields = ["healthmd.profile-sync.ram.config/aad/v1", c.namespace.issuer, c.namespace.environment, c.namespace.accountId,
    c.head.profileId, String(c.head.contentRevision), "healthmd.profile_sync", "1", "healthmd.profile_sync.portable", "1",
    c.head.contentHash, c.key.id, String(c.key.version), String(c.key.epoch)];
  const parts = fields.map(s => encoder.encode(s));
  const bytes = new Uint8Array(parts.reduce((n, p) => n + 4 + p.length, 0));
  const view = new DataView(bytes.buffer); let pos = 0;
  for (const p of parts) { view.setUint32(pos, p.length, false); pos += 4; bytes.set(p, pos); pos += p.length; }
  return bytes;
}
type Capture = { principal: ConfigPrincipal; controls: Controls; key: Aggregate["key"] };
type Proof = { correlation: Correlation; envelope: Envelope };

export async function createProfileSyncV1Ram(injection?: SyntheticRamInjection): Promise<ProfileSyncV1Ram> {
  if (!injection) {
    // No authority, aggregate, browser adapter or key is constructed/admitted by default.
    const unavailable = async () => fixed();
    return Object.freeze({ auth: createNativeAuthHttp(), optIn: unavailable, withdraw: unavailable,
      selectCreate: unavailable, mutate: unavailable, read: unavailable,
      observe: () => freeze({ admittedPorts: 0, controls: [], partitions: [] }) });
  }
  if (injection.sentinel !== SENTINEL) deny();
  const clock = injection.clock ?? (() => 100_000), wait = injection.waitForCrypto;
  let active = false, tainted = false;
  const entry = () => { if (active) { tainted = true; deny(); } };
  const frame = <T>(run: () => T): T => {
    entry(); active = true; tainted = false;
    try { callbackIsSync(run); const value = run(); synchronous(value); if (tainted) deny(); return value; }
    finally { active = false; }
  };
  const now = () => {
    const sample = () => { callbackIsSync(clock); const n = clock(); synchronous(n);
      if (!Number.isSafeInteger(n) || n < 0 || n > Number.MAX_SAFE_INTEGER - 30 * 86400) deny(); return n; };
    return active ? sample() : frame(sample);
  };
  const at = now();
  const handle = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  const rateHandle = await crypto.subtle.generateKey({ name: "HMAC", hash: "SHA-256", length: 256 }, false, ["sign"]);
  frame(() => {
    if (handle.extractable || handle.type !== "secret" || handle.algorithm.name !== "AES-GCM" ||
      (handle.algorithm as AesKeyAlgorithm).length !== 256 || !same(handle.usages, ["encrypt", "decrypt"]) ||
      rateHandle.extractable || rateHandle === handle) deny();
  });
  const auth = emptyAuthState();
  auth.accounts[OWNER] = { active: true };
  auth.browsers[BROWSER] = { accountId: OWNER, sessionId: BROWSER, expiresAt: at + 86400, reauthenticatedAt: at, revoked: false };
  let current: Aggregate = { auth, controls: { consent: { optedIn: false, epoch: 0 }, selectionEpoch: 0, intent: null },
    key: { id: "synthetic-config-key-1", version: 1, epoch: 1, handle }, profile: emptyPartition() };
  const publish = (change: (draft: Aggregate) => void): void => frame(() => {
    callbackIsSync(change); const tentative = clone(current);
    const result: unknown = change(tentative); synchronous(result); if (result !== undefined || tainted) deny();
    const owned = clone(tentative); if (tainted) deny();
    current = owned; // only publication; never restore a possibly published root
  });
  const store: AuthStore = {
    async transact(change) { entry(); publish(a => { callbackIsSync(change); const result: unknown = change(a.auth);
      synchronous(result); if (result !== undefined) deny(); }); },
    async read<T>(inspect: (state: Readonly<AuthState>) => T): Promise<T> {
      entry(); return frame(() => { callbackIsSync(inspect); return inspect(freeze(structuredClone(current.auth))); });
    },
  };
  const authority = new SyntheticNativeAuthority({ registration, store, clock: now,
    rateKey: (purpose, label) => purposeRateKey(rateHandle, purpose, label) });
  const http = createNativeAuthHttp({ authority, rateLabel: () => "synthetic-as06-address",
    browser: { verify: async (request, requirements) => {
      entry();
      if (request.headers.get("Cookie") !== "synthetic-as06-browser=present" ||
        (requirements.csrf && request.headers.get("X-HealthMd-CSRF") !== "synthetic-as06-csrf")) return null;
      return Object.freeze({ accountId: OWNER, sessionId: BROWSER });
    } } });
  const token = (request: Request, path: string): string => frame(() => {
    if (request.method !== "POST" || request.url !== `${ORIGIN}${path}` || request.headers.has("Cookie")) deny();
    const match = /^Bearer (hmd_nac_[A-Za-z0-9_-]{43})$/u.exec(request.headers.get("Authorization") ?? "");
    if (!match?.[1]) deny(); return match[1];
  });
  const assert = (a: Aggregate, p: ConfigPrincipal, path: string): void => {
    authority.assertConfigAtCommit(a.auth, p, "POST", path);
    if (p.issuer !== namespace.issuer || p.environment !== namespace.environment || p.accountId !== OWNER) deny();
  };
  const capture = (p: ConfigPrincipal, path: string, selected = true, profileId?: string): Capture => frame(() => {
    assert(current, p, path);
    if (!current.controls.consent.optedIn || (selected && !current.controls.intent)) deny();
    if (path === READ && (profileId === undefined || current.controls.intent?.publishedProfileId !== profileId)) deny();
    return { principal: p, controls: structuredClone(current.controls), key: { ...current.key } };
  });
  const gate = (a: Aggregate, c: Capture, path: string): void => {
    assert(a, c.principal, path); // ORIGINAL issued object; never refreshed/rebound
    if (!a.controls.consent.optedIn || !same(a.controls, c.controls) || a.key.handle !== c.key.handle ||
      !same(keyRef(a), { id: c.key.id, version: c.key.version, epoch: c.key.epoch })) deny();
  };
  const ownBytes = (bytes: Uint8Array, max = 4_194_304): Uint8Array<ArrayBuffer> => frame(() => {
    if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 || bytes.byteLength > max || bytes.buffer instanceof SharedArrayBuffer) deny();
    return new Uint8Array(bytes);
  });
  const realCrypto = async <T>(phase: "prepare" | "readback", result: Promise<T>): Promise<T> => {
    // Observe rejection even if a scheduling wrapper fails. Its result cannot replace real crypto.
    const completion = result.then(() => undefined); void completion.catch(() => undefined);
    if (wait) await wait(phase, completion);
    return await result;
  };
  const inspectProof = (c: Capture, correlation: Correlation, path: string): Proof => {
    gate(current, c, path);
    const p = current.profile, h = correlation.head, slot = h.revisionSlot;
    // READ admission and every fresh proof/return bind selection to THIS original profile, not some pending intent.
    if (path === READ && current.controls.intent?.publishedProfileId !== h.profileId) deny();
    const revision = p.revisions[slot], envelope = p.cipherSlots[slot];
    proofCheck(revision && envelope && same(revision.correlation, correlation) && revision.cipherSlot === slot &&
      same(p.heads[h.profileId], h) && same(p.receipts[correlation.mutationId], correlation) &&
      same(p.evidence[slot], correlation) && same(p.events[h.eventSequence - 1], correlation) &&
      p.idempotencyIndex[correlation.mutationId] === slot && same(p.revisionIndex[h.profileId], [slot]) &&
      p.issuedIds.includes(h.profileId) && p.nonceIndex[nonceId(envelope, correlation.key)] === slot &&
      p.sequence >= h.eventSequence && p.sequence === p.events.length && p.usage.profiles === p.issuedIds.length &&
      p.usage.revisions === Object.keys(p.revisions).length && p.usage.receipts === Object.keys(p.receipts).length &&
      p.usage.events === p.events.length && p.usage.encryptedBytes <= QUOTA &&
      p.usage.encryptedBytes === Object.values(p.cipherSlots).reduce((n, e) => n + extent(e), 0) &&
      p.usage.plaintextBytes === Object.values(p.revisions).reduce((n, r) => n + r.correlation.contentBytes, 0) &&
      Object.keys(p.reservations).length === 0 && Object.keys(p.retainedStaging).length === 0);
    validEnvelope(envelope, correlation.contentBytes);
    return { correlation: structuredClone(revision.correlation), envelope: structuredClone(envelope) };
  };
  const proof = (c: Capture, correlation: Correlation, path: string): Proof => frame(() => inspectProof(c, correlation, path));
  const decrypt = async (c: Capture, owned: Proof, originalContent?: string): Promise<ValidatedProfileSyncV1Record> => {
    const { correlation: r, envelope: e } = owned;
    const plaintext = new Uint8Array(await realCrypto("readback", crypto.subtle.decrypt({ name: "AES-GCM", tagLength: 128,
      iv: new Uint8Array(e.nonce), additionalData: aad(r) }, c.key.handle, new Uint8Array(e.ciphertext))));
    proofCheck(plaintext.length === r.contentBytes);
    if (originalContent !== undefined) proofCheck(same(Array.from(plaintext), Array.from(encoder.encode(originalContent))));
    const content = await ValidatedProfileSyncV1Content.parse(plaintext, r.head.contentHash);
    proofCheck(ValidatedProfileSyncV1Content.isValidated(content) && same(content.requiresAction, r.requiresAction));
    const h = r.head;
    // NEW server envelope from freshly decrypted ORIGINAL immutable bytes, not cached content/latest head.
    const record = await ValidatedProfileSyncV1Record.parse(encoder.encode(JSON.stringify({ schema: "healthmd.profile_sync", schema_version: 1,
      profile_id: h.profileId, object_revision: h.objectRevision, event_sequence: h.eventSequence, order_key: h.orderKey,
      deleted: false, content_revision: h.contentRevision, content_hash: h.contentHash, content_json: content.contentJson })));
    proofCheck(ValidatedProfileSyncV1Record.isValidated(record) && !record.deleted && record.profileId === h.profileId &&
      record.objectRevision === h.objectRevision && record.eventSequence === h.eventSequence && record.orderKey === h.orderKey &&
      record.contentRevision === h.contentRevision && record.content?.hash === h.contentHash &&
      record.content.contentJson === content.contentJson && same(record.content.requiresAction, r.requiresAction));
    return record;
  };
  const final = (c: Capture, owned: Proof, path: string, record: ValidatedProfileSyncV1Record): Success => frame(() => {
    // ONE fresh synchronous return frame: ORIGINAL principal/current auth + ALL immutable correlations after every await.
    const fresh = inspectProof(c, owned.correlation, path);
    proofCheck(same(fresh, owned));
    return Object.freeze({ ok: true, record });
  });
  const consent = async (request: Request, optedIn: boolean): Promise<Control | Fixed> => {
    try { entry(); const bearer = token(request, MUTATE);
      const p = await authority.authorizeConfig(bearer, "POST", MUTATE);
      publish(a => { assert(a, p, MUTATE); a.controls.consent = { optedIn, epoch: next(a.controls.consent.epoch) };
        a.controls.selectionEpoch = next(a.controls.selectionEpoch); a.controls.intent = null; });
      return frame(() => { assert(current, p, MUTATE); if (current.controls.consent.optedIn !== optedIn) deny(); return ok; });
    } catch { return fixed(); }
  };
  return Object.freeze({
    async auth(request: Request) { entry(); return await http(request); },
    optIn: (request: Request) => consent(request, true), withdraw: (request: Request) => consent(request, false),
    async selectCreate(request: Request, originalBytes: Uint8Array): Promise<Control | Fixed> {
      try { entry(); const bytes = ownBytes(originalBytes), bearer = token(request, MUTATE);
        const p = await authority.authorizeConfig(bearer, "POST", MUTATE), c = capture(p, MUTATE, false);
        const m = await parseProfileSyncV1Mutation(bytes); createMutation(m);
        publish(a => { gate(a, c, MUTATE); const epoch = next(a.controls.selectionEpoch); a.controls.selectionEpoch = epoch;
          a.controls.intent = { epoch, consentEpoch: a.controls.consent.epoch, keyEpoch: a.key.epoch, keyVersion: a.key.version,
            mutationId: m.mutationId, requestHash: m.requestHash, contentHash: m.content.hash, requestBytes: bytes.length,
            contentBytes: encoder.encode(m.content.contentJson).length, sessionId: p.sessionId, sessionGeneration: p.sessionGeneration,
            requiresAction: [...m.content.requiresAction], publishedProfileId: null }; });
        return frame(() => { assert(current, p, MUTATE); if (current.controls.intent?.requestHash !== m.requestHash) deny(); return ok; });
      } catch { return fixed(); }
    },
    async mutate(request: Request, originalBytes: Uint8Array): Promise<Success | Fixed> {
      let published = false;
      try { entry(); const bytes = ownBytes(originalBytes), bearer = token(request, MUTATE);
        const p = await authority.authorizeConfig(bearer, "POST", MUTATE), c = capture(p, MUTATE);
        const m = await parseProfileSyncV1Mutation(bytes); createMutation(m);
        const intent = c.controls.intent;
        if (!intent || intent.publishedProfileId || intent.requestHash !== m.requestHash || intent.mutationId !== m.mutationId ||
          intent.contentHash !== m.content.hash || intent.sessionId !== p.sessionId || intent.sessionGeneration !== p.sessionGeneration) deny();
        const random = frame(() => ({ id: crypto.getRandomValues(new Uint8Array(16)), nonce: crypto.getRandomValues(new Uint8Array(12)) }));
        const profileId = "psp_" + Array.from(random.id, b => b.toString(16).padStart(2, "0")).join("");
        const head: Head = frame(() => { gate(current, c, MUTATE); return {
          profileId, objectRevision: 1, eventSequence: next(current.profile.sequence), orderKey: current.profile.usage.profiles,
          contentRevision: 1, contentHash: m.content.hash, revisionSlot: `${profileId}:1` }; });
        const correlation: Correlation = { namespace: { ...namespace }, head, mutationId: m.mutationId, requestHash: m.requestHash,
          requestBytes: bytes.length, contentBytes: encoder.encode(m.content.contentJson).length, intentEpoch: intent.epoch,
          consentEpoch: intent.consentEpoch, key: { id: c.key.id, version: c.key.version, epoch: c.key.epoch },
          sessionId: p.sessionId, sessionGeneration: p.sessionGeneration, requiresAction: [...m.content.requiresAction] };
        const encrypted = new Uint8Array(await realCrypto("prepare", crypto.subtle.encrypt({ name: "AES-GCM", iv: random.nonce,
          additionalData: aad(correlation), tagLength: 128 }, c.key.handle, encoder.encode(m.content.contentJson))));
        const envelope: Envelope = { format: "healthmd.profile-sync.ram.config", version: 1, header: [...HEADER],
          nonce: Array.from(random.nonce), ciphertext: Array.from(encrypted) };
        validEnvelope(envelope, correlation.contentBytes);
        const committed: Capture = { ...c, controls: structuredClone(c.controls) };
        committed.controls.intent!.publishedProfileId = profileId;
        publish(a => {
          gate(a, c, MUTATE); const v = a.profile, slot = head.revisionSlot;
          // No reservation/staging/receipt/profile/quota effect exists before THIS single publication.
          if (intent.consentEpoch !== a.controls.consent.epoch || intent.keyEpoch !== a.key.epoch || intent.keyVersion !== a.key.version ||
            intent.requestBytes !== bytes.length || intent.contentBytes !== correlation.contentBytes ||
            !same(intent.requiresAction, m.content.requiresAction) || head.eventSequence !== next(v.sequence) ||
            head.orderKey !== v.usage.profiles || v.issuedIds.includes(profileId) || v.heads[profileId] || v.revisions[slot] ||
            v.cipherSlots[slot] || v.evidence[slot] || v.receipts[m.mutationId] || v.idempotencyIndex[m.mutationId] ||
            v.revisionIndex[profileId] || v.nonceIndex[nonceId(envelope, correlation.key)] || v.usage.profiles >= 100 ||
            v.events.length >= 256 || !Number.isSafeInteger(v.usage.encryptedBytes + extent(envelope)) ||
            v.usage.encryptedBytes + extent(envelope) > QUOTA) deny();
          v.heads[profileId] = structuredClone(head);
          v.revisions[slot] = { correlation: structuredClone(correlation), cipherSlot: slot };
          v.cipherSlots[slot] = structuredClone(envelope); v.events.push(structuredClone(correlation));
          v.receipts[m.mutationId] = structuredClone(correlation); v.evidence[slot] = structuredClone(correlation);
          v.idempotencyIndex[m.mutationId] = slot; v.revisionIndex[profileId] = [slot]; v.issuedIds.push(profileId);
          v.nonceIndex[nonceId(envelope, correlation.key)] = slot; v.sequence = head.eventSequence;
          v.usage = { plaintextBytes: v.usage.plaintextBytes + correlation.contentBytes,
            encryptedBytes: v.usage.encryptedBytes + extent(envelope), profiles: next(v.usage.profiles),
            revisions: next(v.usage.revisions), events: next(v.usage.events), receipts: next(v.usage.receipts) };
          a.controls.intent!.publishedProfileId = profileId;
        });
        published = true;
        const owned = proof(committed, correlation, MUTATE); // NEW detached authoritative proof, no cached preparation ciphertext
        const record = await decrypt(committed, owned, m.content.contentJson);
        return final(committed, owned, MUTATE, record);
      } catch (error) {
        if (error instanceof AuthError) return fixed();
        return fixed(published || error instanceof Unverified ? "verification_pending" : error instanceof ProfileSyncV1Error ? "invalid" : "unavailable");
      }
    },
    async read(request: Request, originalBytes: Uint8Array): Promise<Success | Fixed> {
      let verifying = false;
      try { entry(); const bytes = ownBytes(originalBytes, 8192), bearer = token(request, READ);
        const selector = parseProfileSyncV1Read(bytes); if (selector.mode !== "revision") deny();
        const p = await authority.authorizeConfig(bearer, "POST", READ), c = capture(p, READ, true, selector.profileId);
        verifying = true;
        const correlation = frame(() => {
          gate(current, c, READ);
          const r = current.profile.revisions[`${selector.profileId}:${selector.contentRevision}`];
          proofCheck(r && r.correlation.head.profileId === selector.profileId &&
            r.correlation.head.contentRevision === selector.contentRevision && r.correlation.head.contentHash === selector.contentHash);
          return structuredClone(r.correlation);
        });
        const owned = proof(c, correlation, READ), record = await decrypt(c, owned);
        return final(c, owned, READ, record);
      } catch (error) {
        if (error instanceof AuthError) return fixed();
        return fixed(verifying ? "verification_pending" : error instanceof ProfileSyncV1Error ? "invalid" : "unavailable");
      }
    },
    observe(): SyntheticRamObservation { return frame(() => freeze({ admittedPorts: 1,
      controls: [{ namespace: { ...namespace }, ...structuredClone(current.controls), key: keyRef(current) }],
      partitions: [{ namespace: { ...namespace }, values: structuredClone(current.profile) }] })); },
  });
}
