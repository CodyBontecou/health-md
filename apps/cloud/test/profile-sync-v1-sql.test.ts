import { afterEach, describe, expect, it, vi } from "vitest";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createProfileSqlCandidate } from "../src/profile-sync-v1-sql";
import { ValidatedProfileSyncV1Record, profileSyncV1Hash } from "../src/profile-sync-v1-contract";
import { encode, owners, sqlHarness, type HostProfileSql } from "./support/profile-sync-sql";
const corpus = JSON.parse(readFileSync(new URL("../../../packages/contracts/profile-sync/v1/fixtures/parser-cases.json", import.meta.url), "utf8")) as { cases: { id: string; raw?: string }[] };
const literal = corpus.cases.find(c => c.id === "valid-publish")!.raw!;
const publish = JSON.parse(literal) as Record<string, unknown>;
const roots: string[] = [], stores: HostProfileSql[] = [];
afterEach(() => { for (const store of stores.splice(0)) store.db.close(); for (const root of roots.splice(0)) rmSync(root, { recursive: true }); });
async function harness(clock?: () => number) {
  const root = mkdtempSync(join(tmpdir(), "healthmd-as06-synthetic-")); roots.push(root);
  const h = await sqlHarness(join(root, "fixture.sqlite"), true, clock); stores.push(h.store);
  const a = await h.issue(owners[0]), b = await h.issue(owners[1]);
  const ra = h.request(a), rb = h.request(b);
  return { ...h, a, b, ra, rb, path: join(root, "fixture.sqlite") };
}
const original = () => new TextEncoder().encode(literal);
function success(result: Awaited<ReturnType<ReturnType<typeof createProfileSqlCandidate>["mutate"]>>): ValidatedProfileSyncV1Record {
  expect(result).toHaveProperty("ok", true);
  if (!("ok" in result)) throw new Error("Expected actual AS06 SQL success");
  expect(ValidatedProfileSyncV1Record.isValidated(result.record)).toBe(true); return result.record;
}
function mutation(n: number, operation: string, record?: ValidatedProfileSyncV1Record, fields: Record<string, unknown> = {}) {
  return encode({ schema: "healthmd.profile_sync", schema_version: 1, operation,
    mutation_id: "psm_" + n.toString(16).padStart(32, "0"), base_revision: record?.objectRevision ?? 0,
    ...(record ? { profile_id: record.profileId } : {}), ...fields });
}
async function create(h: Awaited<ReturnType<typeof harness>>) {
  expect(await h.service.optIn(h.ra)).toEqual({ ok: true });
  expect(await h.service.select(h.ra, original())).toEqual({ ok: true });
  return success(await h.service.mutate(h.ra, original()));
}
function revision(record: ValidatedProfileSyncV1Record) {
  return encode({ schema: "healthmd.profile_sync", schema_version: 1, mode: "revision", profile_id: record.profileId,
    content_revision: record.contentRevision, content_hash: record.content!.hash });
}
function state(h: Awaited<ReturnType<typeof harness>>) {
  return h.store.db.prepare("SELECT * FROM ps_partition ORDER BY owner").all();
}
describe("inactive AS06 actual-profile SQL transactions", () => {
  it("defaults unavailable with no admitted SQL/key/authority and no Worker runtime import", async () => {
    const off = createProfileSqlCandidate();
    const request = new Request("https://synthetic.example/api/profile-sync/v1/mutate", { method: "POST" });
    for (const control of [off.optIn, off.withdraw]) expect(await control(request)).toMatchObject({ result: "unavailable" });
    expect(await off.mutate(request, original())).toMatchObject({ result: "unavailable" });
    expect(readFileSync(new URL("../src/index.ts", import.meta.url), "utf8")).not.toContain("profile-sync-v1-sql");
    const source = readFileSync(new URL("../src/profile-sync-v1-sql.ts", import.meta.url), "utf8");
    expect(source).not.toMatch(/node:|node_modules|runtimeApproved|CLOUD_RUNTIME_APPROVED/);
  });
  it("uses actual AS05 content, encrypted revision/head/event/receipt/accounting and exact immutable read", async () => {
    const h = await harness(), record = await create(h);
    expect(record.content!.contentJson).toBe(publish.content_json);
    const rows = state(h); expect(rows).toHaveLength(1);
    const partition = JSON.parse(String(rows[0]!.body));
    expect(partition.usage).toMatchObject({ profiles: 1, revisions: 1, events: 1, receipts: 1,
      plaintextBytes: new TextEncoder().encode(String(publish.content_json)).length });
    expect(partition.usage.encryptedBytes).toBeGreaterThan(partition.usage.plaintextBytes);
    for (const table of ["ps_revision", "ps_receipt", "ps_event", "ps_head", "ps_partition"]) {
      const serialized = JSON.stringify(h.store.db.prepare(`SELECT * FROM ${table}`).all());
      expect(serialized).not.toContain("content_json"); expect(serialized).not.toContain("contentJson");
      expect(serialized).not.toContain(String(publish.content_json));
      expect(serialized).not.toContain(h.a.access_token);
    }
    const read = success(await h.service.read(h.request(h.a, "/api/profile-sync/v1/read"), revision(record)));
    expect(read.content!.contentJson).toBe(record.content!.contentJson);
  });
  it("two real fixture-authenticated owners cannot read/replay/select each other's profiles", async () => {
    const h = await harness(), record = await create(h), bytes = original();
    expect(await h.service.optIn(h.rb)).toEqual({ ok: true });
    const before = state(h);
    expect(await h.service.read(h.request(h.b, "/api/profile-sync/v1/read"), revision(record))).toMatchObject({ result: "not_found" });
    expect(await h.service.select(h.rb, mutation(2, "delete", record))).toMatchObject({ result: "unavailable" });
    expect(await h.service.select(h.rb, bytes)).toEqual({ ok: true });
    const own = success(await h.service.mutate(h.rb, bytes));
    expect(own.profileId).not.toBe(record.profileId);
    expect(state(h)[0]).toEqual(before[0]);
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_partition").get()).toMatchObject({ count: 2 });
  });
  it("real OS crash after COMMIT/lost ACK and reopen preserve original IDs, bytes and idempotency", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    h.store.fault = "crash-after-commit";
    const record = success(await h.service.mutate(h.ra, original()));
    h.store.reopen();
    const reopened = await sqlHarness(h.path, false); stores.push(reopened.store);
    const session = await reopened.issue(owners[0]), request = reopened.request(session);
    expect(await reopened.service.select(request, original())).toEqual({ ok: true });
    const retried = success(await reopened.service.mutate(request, original()));
    expect(retried.profileId).toBe(record.profileId); expect(retried.content!.contentJson).toBe(record.content!.contentJson);
    expect(reopened.store.db.prepare("SELECT count(*) AS count FROM ps_head").get()).toMatchObject({ count: 1 });
    expect(reopened.store.db.prepare("SELECT count(*) AS count FROM ps_event").get()).toMatchObject({ count: 1 });
  });
  it.each(["noop", "rollback", "crash"] as const)("%s cannot manufacture success or partially publish a profile", async fault => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    const before = state(h); h.store.fault = fault;
    expect(await h.service.mutate(h.ra, original())).toMatchObject({ result: "verification_pending" });
    h.store.reopen(); expect(state(h)).toEqual(before);
    for (const table of ["ps_head", "ps_revision", "ps_event", "ps_receipt", "ps_nonce"]) {
      expect(h.store.db.prepare(`SELECT count(*) AS count FROM ${table}`).get()).toMatchObject({ count: 0 });
    }
    success(await h.service.mutate(h.ra, original()));
  });
  it("exact retry returns original result after head moves; request mismatch never mutates", async () => {
    const h = await harness(), first = await create(h);
    const reorder = mutation(3, "reorder", first, { order_key: 8 });
    await h.service.select(h.ra, reorder); const second = success(await h.service.mutate(h.ra, reorder));
    expect(second.objectRevision).toBe(2); expect(second.contentRevision).toBe(1);
    await h.service.select(h.ra, original());
    const replay = success(await h.service.mutate(h.ra, original()));
    expect(replay.objectRevision).toBe(1); expect(replay.eventSequence).toBe(1);
    const changedBytes = new TextEncoder().encode(literal + " "); await h.service.select(h.ra, changedBytes);
    const before = state(h);
    expect(await h.service.mutate(h.ra, changedBytes)).toMatchObject({ result: "idempotency_mismatch" });
    expect(state(h)).toEqual(before);
  });
  it("CAS/update/no-op/reorder/delete keep immutable content, total events and retired IDs", async () => {
    const h = await harness(), first = await create(h);
    const contentJson = String(publish.content_json) + " ", hash = await profileSyncV1Hash(new TextEncoder().encode(contentJson));
    const update = mutation(4, "update", first, { content_json: contentJson, content_hash: hash });
    await h.service.select(h.ra, update); const second = success(await h.service.mutate(h.ra, update));
    expect(second.objectRevision).toBe(2); expect(second.contentRevision).toBe(2);
    const stale = mutation(5, "reorder", first, { order_key: 7 }); await h.service.select(h.ra, stale);
    expect(await h.service.mutate(h.ra, stale)).toMatchObject({ result: "conflict" });
    const noop = mutation(6, "update", second, { content_json: contentJson, content_hash: hash });
    await h.service.select(h.ra, noop); const same = success(await h.service.mutate(h.ra, noop)); expect(same.objectRevision).toBe(2);
    const removal = mutation(7, "delete", second); await h.service.select(h.ra, removal);
    const deleted = success(await h.service.mutate(h.ra, removal)); expect(deleted.deleted).toBe(true); expect(deleted.objectRevision).toBe(3);
    const gone = mutation(8, "delete", deleted); await h.service.select(h.ra, gone);
    expect(await h.service.mutate(h.ra, gone)).toMatchObject({ result: "gone" });
    expect(success(await h.service.read(h.request(h.a, "/api/profile-sync/v1/read"), revision(first))).content!.contentJson).toBe(publish.content_json);
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_event").get()).toMatchObject({ count: 3 });
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_revision").get()).toMatchObject({ count: 2 });
  });
  it("appends a fresh SQLite create after a reordered live head, independently of event sequence", async () => {
    const h = await harness(), first = await create(h);
    expect(first.orderKey).toBe(0);
    const reorder = mutation(101, "reorder", first, { order_key: 8 });
    await h.service.select(h.ra, reorder); const moved = success(await h.service.mutate(h.ra, reorder));
    const bytes = mutation(102, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    await h.service.select(h.ra, bytes); const appended = success(await h.service.mutate(h.ra, bytes));
    expect(appended.orderKey).toBe(9); expect(appended.eventSequence).toBe(3);
    const live = h.store.db.prepare("SELECT json_extract(body,'$.meta.profile_id') AS id FROM ps_head WHERE json_extract(body,'$.meta.deleted')=0 ORDER BY json_extract(body,'$.meta.order_key'),id").all();
    expect(live).toEqual([{ id: moved.profileId }, { id: appended.profileId }]);
  });
  it("uses the greatest live key, ignores deleted heads, and starts at zero when none survive", async () => {
    const h = await harness(), first = await create(h);
    const reorder = mutation(110, "reorder", first, { order_key: 20 });
    await h.service.select(h.ra, reorder); const moved = success(await h.service.mutate(h.ra, reorder));
    const secondBytes = mutation(111, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    await h.service.select(h.ra, secondBytes); const second = success(await h.service.mutate(h.ra, secondBytes));
    expect(second.orderKey).toBe(21);
    const remove = mutation(112, "delete", second); await h.service.select(h.ra, remove);
    success(await h.service.mutate(h.ra, remove));
    const thirdBytes = mutation(113, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    await h.service.select(h.ra, thirdBytes); const third = success(await h.service.mutate(h.ra, thirdBytes));
    expect(third.orderKey).toBe(21); // tombstones reserve IDs, not live order positions
    for (const [n, record] of [[114, moved], [115, third]] as const) {
      const bytes = mutation(n, "delete", record); await h.service.select(h.ra, bytes); success(await h.service.mutate(h.ra, bytes));
    }
    h.store.reopen();
    const fourthBytes = mutation(116, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    await h.service.select(h.ra, fourthBytes); const fourth = success(await h.service.mutate(h.ra, fourthBytes));
    expect(fourth.orderKey).toBe(0); expect(fourth.profileId).not.toBe(first.profileId);
  });
  it.each([Number.MAX_SAFE_INTEGER - 1, Number.MAX_SAFE_INTEGER])("handles a live key at %s without rounding, wrap or renumber", async key => {
    const h = await harness(), first = await create(h);
    const reorder = mutation(120, "reorder", first, { order_key: key });
    await h.service.select(h.ra, reorder); success(await h.service.mutate(h.ra, reorder));
    const bytes = mutation(121, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    await h.service.select(h.ra, bytes);
    const before = state(h), heads = h.store.db.prepare("SELECT * FROM ps_head ORDER BY id").all();
    const result = await h.service.mutate(h.ra, bytes);
    if (key < Number.MAX_SAFE_INTEGER) expect(success(result).orderKey).toBe(Number.MAX_SAFE_INTEGER);
    else {
      expect(result).toMatchObject({ result: "quota_exceeded" }); expect(state(h)).toEqual(before);
      expect(h.store.db.prepare("SELECT * FROM ps_head ORDER BY id").all()).toEqual(heads);
      expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_receipt").get()).toMatchObject({ count: 2 });
      expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_event").get()).toMatchObject({ count: 2 });
    }
  });
  it.each([-1, -Number.MAX_SAFE_INTEGER, 0.5, Number.MAX_SAFE_INTEGER + 1])("rejects an invalid persisted live order key %s before any create effects", async key => {
    const h = await harness(); await create(h);
    // Preserve structural head/event/receipt links to exercise allocation against
    // corrupt stored metadata. These edits are NOT authenticated profile revisions.
    for (const table of ["ps_head", "ps_event", "ps_receipt"]) {
      for (const row of h.store.db.prepare(`SELECT rowid,body FROM ${table}`).all() as { rowid: number; body: string }[]) {
        const body = JSON.parse(row.body); body.meta.order_key = key;
        h.store.db.prepare(`UPDATE ${table} SET body=? WHERE rowid=?`).run(JSON.stringify(body), row.rowid);
      }
    }
    const bytes = mutation(130, "create", undefined, { content_json: publish.content_json, content_hash: publish.content_hash });
    expect(await h.service.select(h.ra, bytes)).toEqual({ ok: true });
    const before = state(h);
    expect(await h.service.mutate(h.ra, bytes)).toMatchObject({ result: "verification_pending" });
    expect(state(h)).toEqual(before);
    for (const table of ["ps_head", "ps_revision", "ps_receipt", "ps_event"]) {
      expect(h.store.db.prepare(`SELECT count(*) AS count FROM ${table}`).get()).toMatchObject({ count: 1 });
    }
  });
  it("concurrent actual connections yield one CAS result and never overwrite another writer", async () => {
    const h = await harness(), first = await create(h);
    const peer = await sqlHarness(h.path, false); stores.push(peer.store);
    const session = await peer.issue(owners[0]), request = peer.request(session);
    const bytes = mutation(9, "reorder", first, { order_key: 12 });
    await peer.service.select(request, bytes);
    const results = await Promise.all([h.service.mutate(request, bytes), peer.service.mutate(request, bytes)]);
    for (const result of results) if ("ok" in result) expect(result.record.objectRevision).toBe(2);
    expect(results.some(r => "ok" in r)).toBe(true);
    expect(peer.store.db.prepare("SELECT count(*) AS count FROM ps_event").get()).toMatchObject({ count: 2 });
  });
  it.each(["withdraw", "revoke", "disable", "selection"] as const)("%s during encryption fences pending work", async action => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    let fired = false;
    const candidate = createProfileSqlCandidate({ ...h.ports, afterCrypto: async () => {
      if (fired) return; fired = true;
      if (action === "withdraw") await h.service.withdraw(h.ra);
      if (action === "revoke") await h.authority.revoke({ kind: "browser", identity: { accountId: owners[0], sessionId: owners[0] }, sessionId: h.a.session_id });
      if (action === "disable") await h.store.transact(s => { s.accounts[owners[0]]!.active = false; });
      if (action === "selection") await h.service.select(h.ra, new TextEncoder().encode(literal + " "));
    } });
    expect(await candidate.mutate(h.ra, original())).not.toHaveProperty("ok");
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_head").get()).toMatchObject({ count: 0 });
  });
  it("SQL authority-version fence rejects revocation between fresh JS check and batch execution", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    h.store.beforeBatch = () => {
      const row = h.store.db.prepare("SELECT body FROM ps_authority WHERE id=1").get() as { body: string };
      const auth = JSON.parse(row.body); auth.families[h.a.session_id].revokedAt = Math.floor(Date.now() / 1000);
      h.store.db.prepare("UPDATE ps_authority SET version=version+1,body=? WHERE id=1").run(JSON.stringify(auth));
    };
    expect(await h.service.mutate(h.ra, original())).not.toHaveProperty("ok");
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_receipt").get()).toMatchObject({ count: 0 });
  });
  it.each(["ciphertext", "nonce", "tenant", "head", "event", "accounting", "nonce-index"] as const)("%s tamper produces fixed non-success", async target => {
    const h = await harness(), first = await create(h);
    if (target === "nonce-index") {
      h.store.db.prepare("DELETE FROM ps_nonce WHERE rowid=(SELECT min(rowid) FROM ps_nonce)").run();
      expect(await h.service.mutate(h.ra, original())).not.toHaveProperty("ok");
      expect(await h.service.read(h.request(h.a, "/api/profile-sync/v1/read"), revision(first))).not.toHaveProperty("ok");
      return;
    }
    const table = target === "head" ? "ps_head" : target === "event" ? "ps_event" : target === "accounting" ? "ps_partition" : "ps_revision";
    const row = h.store.db.prepare(`SELECT rowid,body FROM ${table}`).get() as { rowid: number; body: string };
    const body = JSON.parse(row.body);
    if (target === "ciphertext" || target === "nonce") body.sealed[target] = (parseInt(body.sealed[target].slice(0, 2), 16) ^ 1).toString(16).padStart(2, "0") + body.sealed[target].slice(2);
    if (target === "head" || target === "event") body.meta.order_key++;
    if (target === "accounting") body.usage.encryptedBytes--;
    if (target === "tenant") {
      await h.service.optIn(h.rb);
      const owner = JSON.stringify([h.b.issuer, h.b.environment, h.b.account_id]);
      h.store.db.prepare("UPDATE ps_revision SET owner=?").run(owner);
    } else h.store.db.prepare(`UPDATE ${table} SET body=? WHERE rowid=?`).run(JSON.stringify(body), row.rowid);
    expect(await h.service.mutate(h.ra, original())).not.toHaveProperty("ok");
    expect(await h.service.read(h.request(h.a, "/api/profile-sync/v1/read"), revision(first))).not.toHaveProperty("ok");
  });
  it.each(["mutate", "optIn", "withdraw", "select"] as const)("exact old-token expiry fences delayed SQL %s after refresh with zero effects", async operation => {
    const base = Math.floor(Date.now() / 1000); let now = base;
    const h = await harness(() => now);
    h.store.db.function("unixepoch", () => now);
    now = base + 290;
    const refreshed = await h.authority.token(encode({ grant_type: "refresh_token", client_id: h.a.client_id,
      installation_id: h.a.installation_id, refresh_token: h.a.refresh_token }));
    expect(refreshed.session_generation).toBe(1);
    now = base + 299;
    // Old-generation access is deliberately still accepted after refresh.
    expect(await h.service.optIn(h.ra)).toEqual({ ok: true });
    expect(await h.service.select(h.ra, original())).toEqual({ ok: true });
    const tables = ["ps_authority", "ps_partition", "ps_head", "ps_revision", "ps_event", "ps_receipt", "ps_nonce", "ps_guard"];
    const snapshot = () => tables.map(table => h.store.db.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all());
    const before = snapshot();
    h.store.beforeBatch = () => { now = base + 301; }; // genuine token deadline crossed at SQL, not at JS validation
    const result = operation === "select" ? await h.service.select(h.ra, original()) : operation === "mutate" ?
      await h.service.mutate(h.ra, original()) : await h.service[operation](h.ra);
    expect(result).not.toHaveProperty("ok");
    expect(snapshot()).toEqual(before); // includes consent/selection, accounting and ALL profile artifacts
    const current = await h.authority.authorizeConfig(refreshed.access_token, "POST", "/api/profile-sync/v1/mutate");
    const auth = await h.store.read(state => state);
    expect(h.authority.configAccessDeadlineAtCommit(auth, current, "POST", "/api/profile-sync/v1/mutate")).toBe(base + 590);
    // The expired historical token must not poison current-token writes.
    expect(await h.service.optIn(h.request(refreshed))).toEqual({ ok: true });
  });
  it("exact deadline requires the issuing authority's opaque principal and current authorization", async () => {
    const base = Math.floor(Date.now() / 1000); let now = base;
    const h = await harness(() => now), path = "/api/profile-sync/v1/mutate";
    now = base + 290;
    const refreshed = await h.authority.token(encode({ grant_type: "refresh_token", client_id: h.a.client_id,
      installation_id: h.a.installation_id, refresh_token: h.a.refresh_token }));
    now = base + 299;
    const old = await h.authority.authorizeConfig(h.a.access_token, "POST", path);
    const current = await h.authority.authorizeConfig(refreshed.access_token, "POST", path);
    const auth = await h.store.read(state => state);
    expect(old.sessionGeneration).toBe(1);
    expect(h.authority.configAccessDeadlineAtCommit(auth, old, "POST", path)).toBe(base + 300);
    expect(h.authority.configAccessDeadlineAtCommit(auth, current, "POST", path)).toBe(base + 590);
    expect(() => h.authority.configAccessDeadlineAtCommit(auth, { ...old }, "POST", path)).toThrow();
    expect(() => h.authority.configAccessDeadlineAtCommit(auth, old, "POST", "/api/v1/exports")).toThrow();
    const peer = await sqlHarness(h.path, false, () => now); stores.push(peer.store);
    expect(() => peer.authority.configAccessDeadlineAtCommit(auth, old, "POST", path)).toThrow();
    now = base + 301;
    expect(() => h.authority.configAccessDeadlineAtCommit(auth, old, "POST", path)).toThrow();
    expect(h.authority.configAccessDeadlineAtCommit(auth, current, "POST", path)).toBe(base + 590);
    await h.authority.revoke({ kind: "access", token: refreshed.access_token });
    const revoked = await h.store.read(state => state);
    expect(() => h.authority.configAccessDeadlineAtCommit(revoked, current, "POST", path)).toThrow();
  });
  it("SQL database-time fence rejects a grant expiring while waiting for execution", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    h.store.beforeBatch = () => h.store.db.function("unixepoch", () => Math.floor(Date.now() / 1000) + 301);
    expect(await h.service.mutate(h.ra, original())).not.toHaveProperty("ok");
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_receipt").get()).toMatchObject({ count: 0 });
  });
  it("caller byte mutation during awaits cannot replace the selected original AS05 request", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    const bytes = original(), pending = h.service.mutate(h.ra, bytes); bytes.fill(0);
    expect(success(await pending).content!.contentJson).toBe(publish.content_json);
  });
  it("nonce reuse rejects the whole transaction, including both encrypted artifacts", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    const spy = vi.spyOn(crypto, "getRandomValues").mockImplementation(bytes => { if (bytes instanceof Uint8Array) bytes.fill(99); return bytes; });
    try { expect(await h.service.mutate(h.ra, original())).toMatchObject({ result: "verification_pending" }); }
    finally { spy.mockRestore(); }
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_nonce").get()).toMatchObject({ count: 0 });
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_head").get()).toMatchObject({ count: 0 });
  });
  it("revocation after immutable decrypt still prevents a read success", async () => {
    const h = await harness(), first = await create(h);
    let once = false;
    const candidate = createProfileSqlCandidate({ ...h.ports, afterCrypto: async () => {
      if (once) return; once = true;
      await h.authority.revoke({ kind: "access", token: h.a.access_token });
    } });
    expect(await candidate.read(h.request(h.a, "/api/profile-sync/v1/read"), revision(first))).not.toHaveProperty("ok");
  });
  it("invalid AS05 grammar stays a closed error with no profile effects", async () => {
    const h = await harness(); await h.service.optIn(h.ra); await h.service.select(h.ra, original());
    const malformed = new TextEncoder().encode(literal.replace('"base_revision":0', '"base_revision":0.0'));
    expect(malformed).not.toEqual(original());
    expect(await h.service.mutate(h.ra, malformed)).toMatchObject({ result: "invalid" });
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_receipt").get()).toMatchObject({ count: 0 });
  });
  it("bounded configurable fixture quota rejects all effects and unreadable proof cannot invent success", async () => {
    const h = await harness();
    const candidate = createProfileSqlCandidate({ ...h.ports, policy: { ...h.ports.policy, maxEncryptedBytes: 1 } });
    await candidate.optIn(h.ra); await candidate.select(h.ra, original());
    expect(await candidate.mutate(h.ra, original())).toMatchObject({ result: "quota_exceeded" });
    expect(h.store.db.prepare("SELECT count(*) AS count FROM ps_receipt").get()).toMatchObject({ count: 0 });
    h.store.unreadable = true;
    expect(await candidate.mutate(h.ra, original())).not.toHaveProperty("ok");
  });
});
