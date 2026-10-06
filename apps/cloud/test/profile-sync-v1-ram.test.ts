import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { createProfileSyncV1Ram, type ProfileSyncV1Ram } from "../src/profile-sync-v1-ram";
import { randomReference, s256 } from "../src/account-auth-v1/crypto";
import type { NativeSessionResponse } from "../src/account-auth-v1/model";
import { parseProfileSyncV1Error, ValidatedProfileSyncV1Content, ValidatedProfileSyncV1Record,
  profileSyncV1Hash, profileSyncV1MutationHash } from "../src/profile-sync-v1-contract";

// Literal existing vector in place. NEVER reconstruct this mutation or use apple-1.json.
const corpus: { cases: { id: string; raw?: string; request_hash?: string }[] } = JSON.parse(readFileSync(
  new URL("../../../packages/contracts/profile-sync/v1/fixtures/parser-cases.json", import.meta.url), "utf8"));
const vector = corpus.cases.find(c => c.id === "valid-publish");
if (!vector?.raw) throw new Error("Pinned valid-publish fixture absent");
const raw = vector.raw;
const expectedContent: string = JSON.parse(raw).content_json;
const encode = (s: string) => new TextEncoder().encode(s);
const wire = (v: unknown) => encode(JSON.stringify(v));
const REQUEST_HASH = "68d69191ef91180973ed1fbecdd0971770544940d39069178204d0855563a225";
const CONTENT_HASH = "dd69558fb78acc68119f3e67f8b4195aab065c59346bec1b0f846f73a621a19e";
const flags = ["local_review_required", "platform_review", "template_review", "unbound_destination"];
const origin = "https://account-auth.synthetic.example";
const mutatePath = "/api/profile-sync/v1/mutate", readPath = "/api/profile-sync/v1/read";
const browserHeaders = { Cookie: "synthetic-as06-browser=present", Origin: origin, "X-HealthMd-CSRF": "synthetic-as06-csrf" };
const request = (path: string, method = "POST", body?: unknown, headers?: Record<string, string>) => new Request(origin + path, {
  method, headers: { ...(body !== undefined ? { "Content-Type": "application/json" } : {}), ...headers },
  ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
});
const native = (s: NativeSessionResponse, path = mutatePath) => request(path, "POST", undefined, { Authorization: `Bearer ${s.access_token}` });
const unavailable = { schema: "healthmd.profile_sync", schema_version: 1, result: "unavailable" };
const empty = {
  heads: {}, revisions: {}, cipherSlots: {}, events: [], receipts: {}, evidence: {}, idempotencyIndex: {},
  revisionIndex: {}, issuedIds: [], nonceIndex: {}, sequence: 0,
  usage: { plaintextBytes: 0, encryptedBytes: 0, profiles: 0, revisions: 0, events: 0, receipts: 0 },
  reservations: {}, retainedStaging: {},
};
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>(done => { resolve = done; });
  return { promise, resolve };
}
function pause(phase: "prepare" | "readback" = "prepare", initiallyArmed = true) {
  const entered = deferred(), release = deferred(); let armed = initiallyArmed;
  return { entered: entered.promise, release: release.resolve, arm: () => { armed = true; },
    wait: async (at: "prepare" | "readback", realCompletion: Promise<void>) => {
      await realCompletion; // forwards actual crypto completion, never invents ciphertext/success
      if (at === phase && armed) { armed = false; entered.resolve(); await release.promise; }
    } };
}
async function issue(ram: ProfileSyncV1Ram): Promise<NativeSessionResponse> {
  const verifier = randomReference(), state = randomReference(), installation = randomReference();
  const query = new URLSearchParams({ client_id: "synthetic-apple-ios",
    redirect_uri: "https://callbacks.account-sync.example/apple-ios/return", response_type: "code",
    scope: "account:sessions:read account:sessions:revoke:self config:profiles:read config:profiles:write",
    state, code_challenge: await s256(verifier), code_challenge_method: "S256",
    audience: "urn:healthmd:account-config:synthetic:v1" });
  const begin = await ram.auth(new Request(`${origin}/account/authorize?${query}`, { headers: browserHeaders }));
  expect(begin.status).toBe(200);
  const review = await begin.json() as { authorization_id: string };
  const decision = await ram.auth(request("/api/account-auth/v1/decision", "POST",
    { authorization_id: review.authorization_id, decision: "approve" }, browserHeaders));
  expect(decision.status).toBe(303);
  const callback = new URL(decision.headers.get("location")!);
  expect([...callback.searchParams.keys()].sort()).toEqual(["code", "iss", "state"]);
  expect(callback.searchParams.get("state")).toBe(state);
  expect(callback.searchParams.get("iss")).toBe(origin);
  const token = await ram.auth(request("/api/account-auth/v1/token", "POST", {
    grant_type: "authorization_code", client_id: "synthetic-apple-ios", redirect_uri: "https://callbacks.account-sync.example/apple-ios/return",
    code: callback.searchParams.get("code"), code_verifier: verifier, installation_id: installation,
  }));
  expect(token.status).toBe(200);
  expect(token.headers.get("cache-control")).toBe("no-store");
  const result = await token.json() as NativeSessionResponse;
  expect(result.account_id).toBe("synthetic-account-as06");
  expect(result.session_generation).toBe(0);
  return result;
}
async function inventory(ram: ProfileSyncV1Ram) {
  const response = await ram.auth(request("/api/account-auth/v1/sessions", "GET", undefined, browserHeaders));
  expect(response.status).toBe(200);
  return (await response.json() as { sessions: { session_id: string; revoked: boolean }[] }).sessions;
}
async function revoke(ram: ProfileSyncV1Ram, s: NativeSessionResponse) {
  const response = await ram.auth(request("/api/account-auth/v1/revoke", "POST", { session_id: s.session_id }, browserHeaders));
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ revoked: true });
  expect((await inventory(ram)).find(row => row.session_id === s.session_id)?.revoked).toBe(true);
}
async function refresh(ram: ProfileSyncV1Ram, s: NativeSessionResponse): Promise<NativeSessionResponse> {
  const response = await ram.auth(request("/api/account-auth/v1/token", "POST", { grant_type: "refresh_token",
    client_id: s.client_id, installation_id: s.installation_id, refresh_token: s.refresh_token }));
  expect(response.status).toBe(200);
  const result = await response.json() as NativeSessionResponse;
  expect(result.session_id).toBe(s.session_id);
  expect(result.session_generation).toBe(1);
  return result;
}
async function select(ram: ProfileSyncV1Ram, s: NativeSessionResponse) {
  expect(await ram.optIn(native(s))).toEqual({ ok: true });
  expect(await ram.selectCreate(native(s), encode(raw))).toEqual({ ok: true });
}
function revisionRequest(record: ValidatedProfileSyncV1Record) {
  return wire({ schema: "healthmd.profile_sync", schema_version: 1, mode: "revision",
    profile_id: record.profileId, content_revision: record.contentRevision, content_hash: record.content?.hash });
}
function requireSuccess(result: Awaited<ReturnType<ProfileSyncV1Ram["mutate"]>>) {
  expect("ok" in result && result.ok).toBe(true);
  if (!("ok" in result)) throw new Error("Selected positive control did not publish/decrypt");
  return result.record;
}

describe("inactive AS06 compound RAM public authority", () => {
  it("constructs ZERO admitted ports by default and denies browser/foreign/mixed configuration even with real native issuance", async () => {
    const off = await createProfileSyncV1Ram();
    expect(off.observe()).toEqual({ admittedPorts: 0, controls: [], partitions: [] });
    expect((await off.auth(request("/api/account-auth/v1/token", "POST", {}))).status).toBe(503);
    for (const action of [off.optIn, off.withdraw]) expect(await action(request(mutatePath))).toEqual(unavailable);
    for (const action of [off.selectCreate, off.mutate, off.read]) expect(await action(request(mutatePath), encode(raw))).toEqual(unavailable);
    expect(off.observe()).toEqual({ admittedPorts: 0, controls: [], partitions: [] });
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only" });
    const session = await issue(ram), before = ram.observe();
    for (const headers of [browserHeaders, { Authorization: `Bearer ${session.refresh_token}` },
      { ...browserHeaders, Authorization: `Bearer ${session.access_token}` }]) {
      expect(await ram.optIn(request(mutatePath, "POST", undefined, headers))).toEqual(unavailable);
      expect(await ram.selectCreate(request(mutatePath, "POST", undefined, headers), encode(raw))).toEqual(unavailable);
      expect(await ram.mutate(request(mutatePath, "POST", undefined, headers), encode(raw))).toEqual(unavailable);
      expect(await ram.read(request(readPath, "POST", undefined, headers), wire({}))).toEqual(unavailable);
    }
    expect((await ram.auth(request(mutatePath, "POST", {}, browserHeaders))).status).toBe(404); // no route install
    for (const path of [mutatePath + "?x=1", mutatePath + "/", "/api/v1/exports", "/mcp"]) {
      expect(await ram.optIn(native(session, path))).toEqual(unavailable);
    }
    expect(await ram.optIn(request(mutatePath, "GET", undefined, { Authorization: `Bearer ${session.access_token}` }))).toEqual(unavailable);
    expect(ram.observe()).toEqual(before);
  });

  it("owns caller bytes and COMPLETE detached frozen observer/record values; exact request whitespace cannot replace selected intent", async () => {
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only" });
    const session = await issue(ram); await select(ram, session);
    const selected = ram.observe();
    expect(await ram.mutate(native(session), encode(raw + " "))).toEqual(unavailable);
    expect(ram.observe()).toEqual(selected); // same parsed content, DIFFERENT exact request fingerprint
    const bytes = encode(raw), pending = ram.mutate(native(session), bytes);
    bytes.fill(32); // immediately after facade entry, BEFORE auth/codec/crypto awaits
    const record = requireSuccess(await pending);
    expect(record.content?.contentJson).toBe(expectedContent);
    const snapshot = ram.observe();
    const immutableData = (value: unknown): void => {
      if (value === null || typeof value !== "object") return;
      expect(Object.isFrozen(value)).toBe(true);
      expect([Object.prototype, Array.prototype]).toContain(Object.getPrototypeOf(value));
      for (const child of Object.values(value)) immutableData(child);
    };
    immutableData(snapshot); // EVERY nested map/array/receipt/cipher byte, not shallow Readonly
    const slot = snapshot.partitions[0]!.values.heads[record.profileId]!.revisionSlot;
    expect(Reflect.set(snapshot.partitions[0]!.values.cipherSlots[slot]!.ciphertext, "0", 0)).toBe(false);
    expect(Reflect.set(snapshot.controls[0]!.key, "epoch", 0)).toBe(false);
    expect(() => Array.prototype.push.call(snapshot.controls[0]!.intent!.requiresAction, "unsafe")).toThrow(TypeError);
    expect(Reflect.set(record, "objectRevision", 99)).toBe(false);
    expect(Reflect.set(record.content!, "hash", "0".repeat(64))).toBe(false);
    expect(() => Array.prototype.push.call(record.content!.requiresAction, "unsafe")).toThrow(TypeError);
    const ownedRead = revisionRequest(record), reading = ram.read(native(session, readPath), ownedRead);
    ownedRead.fill(32);
    expect(requireSuccess(await reading)).toEqual(record);
    const detachedAgain = ram.observe();
    expect(detachedAgain).toEqual(snapshot);
    expect(detachedAgain.partitions).not.toBe(snapshot.partitions);
    expect(detachedAgain.partitions[0]!.values.cipherSlots[slot]!.ciphertext).not.toBe(snapshot.partitions[0]!.values.cipherSlots[slot]!.ciphertext);
    expect(selected.partitions[0]!.values).toEqual(empty); // old detached snapshot never changes on publication
  });

  it("rejects caller-clock reentrancy/thenables in synchronous frames without publishing a tentative or holding the async operation lock", async () => {
    const latch = pause(); let ram: ProfileSyncV1Ram | undefined;
    let reenter = false, thenable = false, nestedDenied = false;
    const clock = (): number => {
      if (reenter) { reenter = false; try { ram!.observe(); } catch { nestedDenied = true; } }
      // Deliberately hostile boundary value; void/number TypeScript typing is not a sync/ownership guarantee.
      if (thenable) return Promise.resolve(100_000) as unknown as number;
      return 100_000;
    };
    ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", clock, waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const before = ram.observe(), pending = ram.mutate(native(session), encode(raw));
    await latch.entered;
    reenter = true; latch.release();
    expect(await pending).toEqual(unavailable);
    expect(nestedDenied).toBe(true); // caller catches nested exception, but active frame remains tainted/aborts
    expect(ram.observe()).toEqual(before);
    thenable = true;
    expect(await ram.mutate(native(session), encode(raw))).toEqual(unavailable);
    thenable = false;
    expect(ram.observe()).toEqual(before);
    expect(requireSuccess(await ram.mutate(native(session), encode(raw))).content?.contentJson).toBe(expectedContent);
    let asyncClockInvoked = false;
    await expect(createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only",
      clock: (async () => { asyncClockInvoked = true; return 100_000; }) as unknown as () => number })).rejects.toMatchObject({ code: "unavailable" });
    expect(asyncClockInvoked).toBe(false);
  });

  it.each(["prepare", "readback"] as const)("keeps the ORIGINAL issued principal after a genuine AS02 refresh during %s, without fresh-principal laundering or rollback", async phase => {
    const latch = pause(phase);
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const pending = ram.mutate(native(session), encode(raw));
    await latch.entered;
    const during = ram.observe();
    if (phase === "prepare") expect(during.partitions[0]!.values).toEqual(empty);
    else expect(during.partitions[0]!.values.events[0]?.sessionGeneration).toBe(0); // already published, original correlation
    const rotated = await refresh(ram, session); // actual generation transition commits BEFORE resume
    latch.release();
    expect(await pending).toEqual(unavailable); // old bearer still authenticates in AS02; original principal MUST be fenced
    expect(ram.observe().partitions).toEqual(during.partitions);
    if (phase === "prepare") {
      expect(await ram.selectCreate(native(rotated), encode(raw))).toEqual({ ok: true });
      expect(requireSuccess(await ram.mutate(native(rotated), encode(raw))).content?.contentJson).toBe(expectedContent);
    } else {
      const head = Object.values(during.partitions[0]!.values.heads)[0]!;
      const read = requireSuccess(await ram.read(native(rotated, readPath), wire({ schema: "healthmd.profile_sync", schema_version: 1,
        mode: "revision", profile_id: head.profileId, content_revision: 1, content_hash: CONTENT_HASH })));
      expect(read.content?.contentJson).toBe(expectedContent);
      expect(ram.observe().partitions).toEqual(during.partitions); // NO postpublication restore/rebase/recreate
    }
  });

  it("denies a decrypted mutation response when browser peer revocation wins readback, preserving BOTH the publication and peer change", async () => {
    const latch = pause("readback");
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const pending = ram.mutate(native(session), encode(raw));
    await latch.entered;
    const published = ram.observe().partitions;
    expect(published[0]!.values.events[0]?.requestHash).toBe(REQUEST_HASH);
    await revoke(ram, session);
    latch.release();
    expect(await pending).toEqual(unavailable); // no plaintext/reference returned after revoke
    expect(ram.observe().partitions).toEqual(published); // publication is NOT undone
    expect((await inventory(ram)).find(row => row.session_id === session.session_id)?.revoked).toBe(true);
  });

  it("rechecks CURRENT authority on public immutable READ after real decrypt, never substituting a different hash or retaining pre-await authority", async () => {
    const latch = pause("readback", false);
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const record = requireSuccess(await ram.mutate(native(session), encode(raw))), before = ram.observe().partitions;
    expect(await ram.read(native(session, readPath), wire({ schema: "healthmd.profile_sync", schema_version: 1,
      mode: "revision", profile_id: record.profileId, content_revision: 1, content_hash: "0".repeat(64) }))).toEqual(
      { schema: "healthmd.profile_sync", schema_version: 1, result: "verification_pending" });
    expect(ram.observe().partitions).toEqual(before);
    latch.arm();
    const reading = ram.read(native(session, readPath), revisionRequest(record));
    await latch.entered; await revoke(ram, session); latch.release();
    expect(await reading).toEqual(unavailable);
    expect(ram.observe().partitions).toEqual(before);
    expect((await inventory(ram)).find(row => row.session_id === session.session_id)?.revoked).toBe(true);
  });

  it("withholds success for tampered REAL GCM ciphertext and leaves an already published ambiguous result intact, not reconstructed or rolled back", async () => {
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only" });
    const session = await issue(ram); await select(ram, session);
    const realEncrypt = crypto.subtle.encrypt.bind(crypto.subtle);
    // Fault ONLY at the genuine WebCrypto boundary: encrypt for real, then flip one authenticated tag bit.
    // No private commit/store/key/tamper/reset port and no fabricated crypto success.
    const spy = vi.spyOn(crypto.subtle, "encrypt").mockImplementation(async (algorithm, key, data) => {
      const result = new Uint8Array(await realEncrypt(algorithm, key, data));
      result[result.length - 1] = result[result.length - 1]! ^ 1;
      return result.buffer;
    });
    let result: Awaited<ReturnType<ProfileSyncV1Ram["mutate"]>>;
    try { result = await ram.mutate(native(session), encode(raw)); } finally { spy.mockRestore(); }
    expect(result).toEqual({ schema: "healthmd.profile_sync", schema_version: 1, result: "verification_pending" });
    const published = ram.observe();
    const head = Object.values(published.partitions[0]!.values.heads)[0]!;
    expect(head.contentHash).toBe(CONTENT_HASH);
    expect(published.partitions[0]!.values.receipts["psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]?.requestHash).toBe(REQUEST_HASH);
    expect(await ram.read(native(session, readPath), wire({ schema: "healthmd.profile_sync", schema_version: 1, mode: "revision",
      profile_id: head.profileId, content_revision: 1, content_hash: CONTENT_HASH }))).toEqual(
      { schema: "healthmd.profile_sync", schema_version: 1, result: "verification_pending" });
    expect(ram.observe()).toEqual(published); // failed verification NEVER repairs/replaces ciphertext or rolls back
  });

  it("commits consent withdrawal on a fresh aggregate DURING genuine preparation, with COMPLETE zero profile effects", async () => {
    const latch = pause();
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const before = ram.observe();
    const pending = ram.mutate(native(session), encode(raw));
    await latch.entered;
    expect(ram.observe().partitions).toEqual(before.partitions);
    expect(await ram.withdraw(native(session))).toEqual({ ok: true });
    const withdrawn = ram.observe();
    expect(withdrawn.controls[0]?.consent).toEqual({ optedIn: false, epoch: 2 });
    expect(withdrawn.controls[0]?.selectionEpoch).toBe(3);
    expect(withdrawn.controls[0]?.intent).toBeNull();
    expect(withdrawn.partitions).toEqual(before.partitions); // withdrawal committed BEFORE resume
    latch.release();
    expect(await pending).toEqual(unavailable);
    expect(ram.observe()).toEqual(withdrawn); // not only counts; consent is not restored
  });

  it("does not revive old preparation after withdrawal, re-opt-in and reselection of the SAME bytes", async () => {
    const latch = pause();
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const session = await issue(ram); await select(ram, session);
    const pending = ram.mutate(native(session), encode(raw));
    await latch.entered;
    expect(await ram.withdraw(native(session))).toEqual({ ok: true });
    await select(ram, session); // new consent/selection epochs, not a Boolean revival
    const replacement = ram.observe();
    expect(replacement.controls[0]?.consent).toEqual({ optedIn: true, epoch: 3 });
    expect(replacement.controls[0]?.selectionEpoch).toBe(5);
    expect(replacement.partitions[0]?.values).toEqual(empty);
    latch.release();
    expect(await pending).toEqual(unavailable);
    expect(ram.observe()).toEqual(replacement); // stale tentative cannot consume NEW intent
    expect(requireSuccess(await ram.mutate(native(session), encode(raw))).content?.contentJson).toBe(expectedContent);
  });

  it("requires selection of the requested original immutable profile, not a pending create of the SAME literal fixture", async () => {
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only" });
    const session = await issue(ram); await select(ram, session);
    const record = requireSuccess(await ram.mutate(native(session), encode(raw)));
    expect(record.content?.contentJson).toBe(expectedContent);
    expect(record.content?.hash).toBe(CONTENT_HASH);
    const published = ram.observe();
    expect(published.controls[0]?.intent?.publishedProfileId).toBe(record.profileId);
    const originalRead = revisionRequest(record);
    expect(requireSuccess(await ram.read(native(session, readPath), originalRead))).toEqual(record);
    expect(ram.observe()).toEqual(published); // positive real immutable decrypt, no read effects

    expect(await ram.optIn(native(session))).toEqual({ ok: true });
    expect(ram.observe().controls[0]?.intent).toBeNull();
    expect(ram.observe().partitions).toEqual(published.partitions);
    expect(await ram.selectCreate(native(session), encode(raw))).toEqual({ ok: true }); // verbatim AGAIN
    const pending = ram.observe();
    expect(pending.controls[0]?.consent).toEqual({ optedIn: true, epoch: 2 });
    expect(pending.controls[0]?.selectionEpoch).toBe(4);
    expect(pending.controls[0]?.intent).toEqual({ epoch: 4, consentEpoch: 2, keyEpoch: 1, keyVersion: 1,
      mutationId: "psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", requestHash: REQUEST_HASH, contentHash: CONTENT_HASH,
      requestBytes: 2941, contentBytes: 2402, sessionId: session.session_id, sessionGeneration: 0, requiresAction: flags,
      publishedProfileId: null }); // pending CREATE is not selection of the old immutable profile
    expect(pending.partitions).toEqual(published.partitions); // COMPLETE values, not counts/hash-only
    expect((await inventory(ram)).find(row => row.session_id === session.session_id)?.revoked).toBe(false);
    const oldRead = await ram.read(native(session, readPath), originalRead); // SAME original selector and real bearer
    if ("ok" in oldRead) expect(oldRead.record).toEqual(record); // RED distinguishes actual decrypted success
    expect(ram.observe()).toEqual(pending); // even the reproduced unauthorized read did not write profile state
    expect("ok" in oldRead).toBe(false); // genuine selection-correlated denial boundary
    expect(oldRead).toEqual(unavailable);
  });

  it("preserves a browser peer revoke during real preparation, then publishes/decrypts the SAME selected bytes from a NEW family", async () => {
    expect(encode(raw)).toHaveLength(2941);
    expect(encode(expectedContent)).toHaveLength(2402);
    expect(expectedContent.endsWith("\n")).toBe(true);
    expect(vector?.request_hash).toBe(REQUEST_HASH);
    expect(await profileSyncV1MutationHash(encode(raw))).toBe(REQUEST_HASH);
    expect(await profileSyncV1Hash(encode(expectedContent))).toBe(CONTENT_HASH);
    const latch = pause();
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    expect(ram.observe().partitions[0]?.values).toEqual(empty);
    const first = await issue(ram);
    expect(ram.observe().controls[0]?.consent).toEqual({ optedIn: false, epoch: 0 });
    expect(ram.observe().controls[0]?.intent).toBeNull();
    expect(ram.observe().partitions[0]?.values).toEqual(empty); // sign-in selects/transfers NOTHING
    await select(ram, first);
    const before = ram.observe().partitions;
    const pending = ram.mutate(native(first), encode(raw));
    await latch.entered;
    expect(ram.observe().partitions).toEqual(before); // complete prepublication proof, not counts
    await revoke(ram, first); // actual same-aggregate recently-reauthenticated browser AUTH peer commits
    latch.release();
    expect(await pending).toEqual(unavailable);
    expect(ram.observe().partitions).toEqual(before);
    expect(await ram.selectCreate(native(first), encode(raw))).toEqual(unavailable);
    expect((await inventory(ram)).find(row => row.session_id === first.session_id)?.revoked).toBe(true);

    const second = await issue(ram); // no reset/regrant/restore of first family
    expect(second.session_id).not.toBe(first.session_id);
    expect(second.account_id).toBe(first.account_id);
    await select(ram, second); // NEW explicit consent/intent, SAME exact mutation
    const record = requireSuccess(await ram.mutate(native(second), encode(raw)));
    expect(ValidatedProfileSyncV1Record.isValidated(record)).toBe(true);
    expect(ValidatedProfileSyncV1Content.isValidated(record.content)).toBe(true);
    expect(record).toMatchObject({ objectRevision: 1, contentRevision: 1, eventSequence: 1, orderKey: 0, deleted: false });
    expect(record.content?.contentJson).toBe(expectedContent);
    expect(encode(record.content!.contentJson)).toEqual(encode(expectedContent)); // ALL fields/escapes/Unicode/LF
    expect(record.content?.hash).toBe(CONTENT_HASH);
    expect(record.content?.requiresAction).toEqual(flags); // never clear action flags
    const observed = ram.observe(), values = observed.partitions[0]!.values;
    expect(record.profileId).toMatch(/^psp_[0-9a-f]{32}$/u);
    expect(observed.controls[0]!.consent).toEqual({ optedIn: true, epoch: 2 });
    expect(observed.controls[0]!.selectionEpoch).toBe(4);
    expect(observed.controls[0]!.intent).toEqual({ epoch: 4, consentEpoch: 2, keyEpoch: 1, keyVersion: 1,
      mutationId: "psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", requestHash: REQUEST_HASH, contentHash: CONTENT_HASH,
      requestBytes: 2941, contentBytes: 2402, sessionId: second.session_id, sessionGeneration: 0, requiresAction: flags,
      publishedProfileId: record.profileId });
    expect(Object.keys(values.heads)).toEqual([record.profileId]);
    const head = values.heads[record.profileId]!;
    expect(head).toEqual({ profileId: record.profileId, objectRevision: 1, contentRevision: 1, eventSequence: 1,
      orderKey: 0, contentHash: CONTENT_HASH, revisionSlot: `${record.profileId}:1` });
    const receipt = values.receipts["psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]!;
    expect(receipt).toEqual({ namespace: { issuer: origin, environment: "synthetic", accountId: second.account_id }, head,
      mutationId: "psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", requestHash: REQUEST_HASH, requestBytes: 2941, contentBytes: 2402,
      intentEpoch: 4, consentEpoch: 2,
      key: { id: "synthetic-config-key-1", version: 1, epoch: 1 }, sessionId: second.session_id, sessionGeneration: 0, requiresAction: flags });
    expect(values.events).toEqual([receipt]);
    expect(values.evidence).toEqual({ [head.revisionSlot]: receipt });
    expect(values.revisions).toEqual({ [head.revisionSlot]: { correlation: receipt, cipherSlot: head.revisionSlot } });
    expect(Object.keys(values.cipherSlots)).toEqual([head.revisionSlot]);
    const envelope = values.cipherSlots[head.revisionSlot]!;
    expect(envelope.format).toBe("healthmd.profile-sync.ram.config");
    expect(envelope.version).toBe(1);
    expect(envelope.header).toEqual([72, 80, 67, 82, 1]);
    expect(envelope.nonce).toHaveLength(12);
    expect(envelope.ciphertext).toHaveLength(2418); // real GCM tag, no plaintext substitution
    expect(values.idempotencyIndex).toEqual({ [receipt.mutationId]: head.revisionSlot });
    expect(values.revisionIndex).toEqual({ [record.profileId]: [head.revisionSlot] });
    expect(values.issuedIds).toEqual([record.profileId]);
    expect(Object.values(values.nonceIndex)).toEqual([head.revisionSlot]);
    expect(values.sequence).toBe(1);
    expect(values.usage).toEqual({ plaintextBytes: 2402, encryptedBytes: 2435, profiles: 1, revisions: 1, events: 1, receipts: 1 });
    expect(values.reservations).toEqual({}); expect(values.retainedStaging).toEqual({});
    expect(JSON.stringify(observed)).not.toContain(expectedContent);
    expect(JSON.stringify(observed)).not.toContain(second.access_token);
    const read = requireSuccess(await ram.read(native(second, readPath), revisionRequest(record)));
    expect(read).toEqual(record);
    expect(read.content?.contentJson).toBe(expectedContent);
    expect(ram.observe().partitions).toEqual(observed.partitions);
    expect((await inventory(ram)).find(row => row.session_id === first.session_id)?.revoked).toBe(true);
    expect(parseProfileSyncV1Error(wire(unavailable))).toEqual({ result: "unavailable" });
  });
});

describe("AS06 wave2 selected CREATE retry", () => {
  it("recovers original committed CREATE after real decrypt boundary fault", async () => {
    expect(process.versions.node).toBe("24.19.0");
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only" });
    const s = await issue(ram); await select(ram, s);
    const real = crypto.subtle.decrypt.bind(crypto.subtle);
    const fault = vi.spyOn(crypto.subtle, "decrypt").mockImplementationOnce(async (...args) => {
      await real(...args); throw new Error("synthetic lost readback");
    });
    try { expect(await ram.mutate(native(s), encode(raw))).toEqual({ ...unavailable, result: "verification_pending" }); }
    finally { fault.mockRestore(); }
    const saved = ram.observe(), id = saved.controls[0]!.intent!.publishedProfileId;
    expect(id).toMatch(/^psp_[0-9a-f]{32}$/u);
    expect(saved.partitions[0]!.values.receipts["psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]?.head.profileId).toBe(id);
    const record = requireSuccess(await ram.mutate(native(s), encode(raw)));
    expect(record.profileId).toBe(id);
    expect(ValidatedProfileSyncV1Record.isValidated(record)).toBe(true);
    expect(record).toMatchObject({ objectRevision: 1, contentRevision: 1, eventSequence: 1, orderKey: 0 });
    expect(encode(record.content!.contentJson)).toEqual(encode(expectedContent));
    expect(record.content?.hash).toBe(CONTENT_HASH); expect(record.content?.requiresAction).toEqual(flags);
    expect(ram.observe()).toEqual(saved); // ALL cipher/nonce/event/receipt/index/usage/control values, not counts
  });

  it("explicitly reviews the original receipt across refresh and a NEW family without rewriting original evidence", async () => {
    const latch = pause("readback", false);
    const ram = await createProfileSyncV1Ram({ sentinel: "healthmd.profile-sync.v1.ram.synthetic-only", waitForCrypto: latch.wait });
    const s = await issue(ram); await select(ram, s);
    const record = requireSuccess(await ram.mutate(native(s), encode(raw))), original = ram.observe().partitions;
    latch.arm(); const old = ram.mutate(native(s), encode(raw)); await latch.entered;
    const fresh = await refresh(ram, s); latch.release();
    expect(await old).toEqual(unavailable); expect(ram.observe().partitions).toEqual(original);
    expect(await ram.mutate(native(fresh), encode(raw))).toEqual(unavailable); // no generation inheritance
    expect(await ram.optIn(native(fresh))).toEqual({ ok: true });
    const bytes = encode(raw), reviewing = ram.selectRetry(native(fresh), bytes); bytes.fill(32);
    expect(await reviewing).toEqual({ ok: true });
    const selected = ram.observe(); expect(selected.controls[0]?.intent?.sessionGeneration).toBe(1);
    expect(requireSuccess(await ram.mutate(native(fresh), encode(raw)))).toEqual(record); expect(ram.observe()).toEqual(selected);
    await revoke(ram, s); const next = await issue(ram);
    expect(await ram.mutate(native(next), encode(raw))).toEqual(unavailable); // no family inheritance
    await ram.optIn(native(next)); expect(await ram.selectRetry(native(next), encode(raw))).toEqual({ ok: true });
    const reviewed = ram.observe(), retry = encode(raw), recovering = ram.mutate(native(next), retry); retry.fill(32);
    expect(requireSuccess(await recovering)).toEqual(record); expect(ram.observe()).toEqual(reviewed);
    expect(reviewed.partitions).toEqual(original); // ALL original session/gen0/cipher/event/receipt values
    expect((await inventory(ram)).find(r => r.session_id === s.session_id)?.revoked).toBe(true);
  });

  it("denies missing/foreign/mismatch",async()=>{
    const off=await createProfileSyncV1Ram();expect(await off.selectRetry(request(mutatePath),encode(raw))).toEqual(unavailable);
    expect(off.observe().admittedPorts).toBe(0);
    const r=await createProfileSyncV1Ram({sentinel:"healthmd.profile-sync.v1.ram.synthetic-only"}),s=await issue(r),q=native(s),z=encode(raw);
    await select(r,s);const b=r.observe();
    for(const h of [browserHeaders,{Cookie:"x",Authorization:`Bearer ${s.access_token}`},{Authorization:`Bearer ${s.refresh_token}`}])expect(await r.selectRetry(request(mutatePath,"POST",undefined,h),z)).toEqual(unavailable);
    for(const x of [q,native(s,readPath)])expect(await r.selectRetry(x,z)).toEqual(unavailable);
    expect(r.observe()).toEqual(b);requireSuccess(await r.mutate(q,z));const v=r.observe();
    for(const f of [r.mutate,r.selectRetry])expect(await f(q,encode(raw+" "))).toEqual({...unavailable,result:"idempotency_mismatch"});
    expect(r.observe()).toEqual(v);
  });

  it.each(["withdraw","reopt","pending","revoke"])("fences captured replay through %s",async action=>{
    const l=pause("readback",false),r=await createProfileSyncV1Ram({sentinel:"healthmd.profile-sync.v1.ram.synthetic-only",waitForCrypto:l.wait}),s=await issue(r),q=native(s),z=encode(raw);
    await select(r,s);const rec=requireSuccess(await r.mutate(q,z)),b=r.observe().partitions;
    l.arm();const p=r.mutate(q,z);await l.entered;
    if(action==="revoke")await revoke(r,s);
    else if(action==="pending")await r.selectCreate(q,z);
    else{await r.withdraw(q);if(action==="reopt"){await r.optIn(q);expect(await r.selectRetry(q,z)).toEqual({ok:true});}}
    const v=r.observe();l.release();expect(await p).toEqual(unavailable);expect(r.observe()).toEqual(v);expect(v.partitions).toEqual(b);
    if(action==="reopt")expect(requireSuccess(await r.mutate(q,z))).toEqual(rec);
    if(action==="revoke") expect((await inventory(r)).find(x=>x.session_id===s.session_id)?.revoked).toBe(true);
  });

  it("keeps corrupt replay",async()=>{
    const r=await createProfileSyncV1Ram({sentinel:"healthmd.profile-sync.v1.ram.synthetic-only"}),s=await issue(r),q=native(s),z=encode(raw);await select(r,s);
    const real=crypto.subtle.encrypt.bind(crypto.subtle),spy=vi.spyOn(crypto.subtle,"encrypt").mockImplementationOnce(async(...a)=>{const b=new Uint8Array(await real(...a));b[b.length-1]=b[b.length-1]!^1;return b.buffer;});
    const u={...unavailable,result:"verification_pending"};
    try{expect(await r.mutate(q,z)).toEqual(u);}finally{spy.mockRestore();}
    const v=r.observe();expect(await r.mutate(q,z)).toEqual(u);expect(r.observe()).toEqual(v);
  });
});
