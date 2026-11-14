import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { createProfileSyncV1ReadView, type ReadViewContext, type ProfileSyncV1ReadView,
  type CompletedReadView } from "../src/profile-sync-v1-read-view";
import { profileSyncV1Hash } from "../src/profile-sync-v1-contract";

const sentinel = "healthmd.profile-sync.v1.read-view.synthetic-only";
const owner: ReadViewContext = { issuer: "https://issuer-a.account-sync.example", environment: "synthetic-a", account: "sentinel-A", generation: 0 };
const content = readFileSync(new URL("../../../packages/contracts/profile-sync/v1/fixtures/apple-1.json", import.meta.url), "utf8");
const contentHash = "e6f5c1492d0d86bd5b9fa73dde9beccd22b0e7cc64cb4ee6ab4c10c0e4aa860a";
const envelope = { schema: "healthmd.profile_sync", schema_version: 1 };
const wire = (value: unknown) => new TextEncoder().encode(JSON.stringify(value));
const id = (n: number) => "psp_" + n.toString(16).padStart(32, "0");
const cursor = (n: number) => "psc_" + n.toString(16).padStart(64, "0");
const snapshotId = "pss_" + "1".repeat(32);
const read = (mode: "snapshot" | "changes" = "snapshot", after: string | null = null, limit = 8) =>
  wire({ ...envelope, mode, cursor: after, limit });
const live = (n: number, sequence = n, order = n) => ({ ...envelope, profile_id: id(n), object_revision: 1,
  event_sequence: sequence, order_key: order, deleted: false, content_revision: 1, content_hash: contentHash, content_json: content });
const page = (items: unknown[], next: string | null = null, mode = "snapshot", watermark = 4, viewId = snapshotId) =>
  wire({ ...envelope, mode, snapshot_id: viewId, high_watermark: watermark, items, next_cursor: next, complete: next === null });
const collector = () => createProfileSyncV1ReadView({ sentinel, context: owner });
const bytes = (input: Uint8Array) => Array.from(input);
const fields = (n: number, sequence = n, order = n) => ({ profileId: id(n), objectRevision: 1, eventSequence: sequence,
  orderKey: order, contentRevision: 1, content: { hash: contentHash, requiresAction: ["local_review_required", "platform_review", "registry_review", "template_review", "unbound_destination"] } });

function observed(c: ProfileSyncV1ReadView) {
  const v = c.view();
  const view = (value: CompletedReadView | null) => value && ({ ...value, items: value.items.map(r => ({
    profileId: r.profileId, objectRevision: r.objectRevision, eventSequence: r.eventSequence, orderKey: r.orderKey,
    contentRevision: r.contentRevision, deleted: r.deleted, content: r.content && {
      contentJson: r.content.contentJson, hash: r.content.hash, requiresAction: r.content.requiresAction,
    },
  })) });
  return { ...v, committed: view(v.committed), tentative: view(v.tentative) };
}
async function ready(c = collector(), context = owner) {
  const request = read(), reply = page([live(1)], null, "snapshot", 1);
  expect(c.select(context, request)).toEqual({ result: "pending" });
  expect(await c.receive(context, request, reply)).toEqual({ result: "complete" });
  return c;
}
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>(done => { resolve = done; });
  return { promise, resolve };
}
function pause() {
  const entered = deferred(), release = deferred(); let armed = false;
  return { arm: () => { armed = true; }, entered: entered.promise, release: release.resolve,
    wait: async (completion: Promise<void>) => {
      await completion;
      if (armed) { armed = false; entered.resolve(); await release.promise; }
    } };
}
const foreign: ReadViewContext = { issuer: "https://issuer-b.account-sync.example", environment: "synthetic-b", account: "sentinel-B", generation: 1 };
function frozenTree(v: unknown): void {
  if (v === null || typeof v !== "object") return;
  expect(Object.isFrozen(v)).toBe(true);
  for (const value of Object.values(v)) frozenTree(value);
}
function retainedCommit(c: ProfileSyncV1ReadView, before: ReturnType<typeof observed>): void {
  expect(observed(c).committed).toEqual(before.committed);
}

// Compare every byte without asking a generic matcher to enumerate millions of
// array keys. Keep all non-byte diagnostic fields in the normal deep comparison.
function expectSameObservation(actual: ReturnType<typeof observed>, expected: ReturnType<typeof observed>): void {
  function pair(a: { requestBytes: readonly number[]; replyBytes?: readonly number[] } | null,
    b: { requestBytes: readonly number[]; replyBytes?: readonly number[] } | null) {
    expect(a === null).toBe(b === null);
    if (!a || !b) return;
    for (const key of ["requestBytes", "replyBytes"] as const) {
      const left = a[key], right = b[key];
      expect(left?.length).toBe(right?.length);
      if (left && right) for (let i = 0; i < left.length; i++) {
        if (left[i] !== right[i]) throw new Error(`${key} differs at byte ${i}`);
      }
    }
  }
  for (const key of ["committed", "tentative"] as const) {
    const left = actual[key], right = expected[key];
    expect(left?.pages.length).toBe(right?.pages.length);
    if (left && right) left.pages.forEach((p, i) => pair(p, right.pages[i]!));
  }
  pair(actual.selected, expected.selected); pair(actual.parsing, expected.parsing);
  const omitBytes = (value: ReturnType<typeof observed>) => {
    const without = <T extends { requestBytes: readonly number[]; replyBytes?: readonly number[] }>(p: T) =>
      ({ ...p, requestBytes: undefined, replyBytes: undefined });
    return { ...value,
      committed: value.committed && { ...value.committed, pages: value.committed.pages.map(without) },
      tentative: value.tentative && { ...value.tentative, pages: value.tentative.pages.map(without) },
      selected: value.selected && without(value.selected), parsing: value.parsing && without(value.parsing) };
  };
  expect(omitBytes(actual)).toEqual(omitBytes(expected));
}

describe("inactive AS07 read-view public collector", () => {
  it("stages a two-page snapshot, publishes only completion, and preserves exact retries and portable content", async () => {
    const c = collector(), a = read(), b = read("snapshot", cursor(1));
    const first = page([live(1), live(2)], cursor(1)), last = page([live(3), live(4)]);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(c.view().selected).toMatchObject({ context: owner, read: { mode: "snapshot", cursor: null, limit: 8 }, requestBytes: bytes(a) });
    expect(await c.receive(owner, a, first)).toEqual({ result: "pending" });
    const staged = c.view();
    expect(staged.committed).toBeNull();
    expect(staged.tentative).toMatchObject({ context: owner, mode: "snapshot", snapshotId, highWatermark: 4,
      baseHighWatermark: null, nextCursor: cursor(1), items: [fields(1), fields(2)],
      pages: [{ context: owner, read: { mode: "snapshot", cursor: null, limit: 8 }, requestBytes: bytes(a), replyBytes: bytes(first) }] });
    expect(staged.selected).toBeNull();
    expect(staged.parsing).toBeNull();
    expect(staged.requiresSnapshot).toBe(true);
    expect(await c.receive(owner, a, first)).toEqual({ result: "unchanged" });
    expect(c.view()).toEqual(staged);
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    expect(await c.receive(owner, b, last)).toEqual({ result: "complete" });
    const completed = c.view();
    expect(completed).toMatchObject({ context: owner, tentative: null, selected: null, parsing: null, requiresSnapshot: false,
      committed: { context: owner, mode: "snapshot", snapshotId, highWatermark: 4, baseHighWatermark: null,
        items: [fields(1), fields(2), fields(3), fields(4)], pages: [
          { context: owner, read: { mode: "snapshot", cursor: null, limit: 8 }, requestBytes: bytes(a), replyBytes: bytes(first) },
          { context: owner, read: { mode: "snapshot", cursor: cursor(1), limit: 8 }, requestBytes: bytes(b), replyBytes: bytes(last) },
        ] } });
    for (const item of completed.committed!.items) expect(item.content!.contentJson).toBe(content);
    expect(observed(c)).toEqual({ context: owner, tentative: null, selected: null, parsing: null, requiresSnapshot: false,
      epoch: 4, retainedPairs: 2, retainedBytes: a.length + b.length + first.length + last.length,
      committed: { context: owner, mode: "snapshot", snapshotId, highWatermark: 4, baseHighWatermark: null, epoch: 1,
        items: [1, 2, 3, 4].map(n => ({ ...fields(n), deleted: false, content: { ...fields(n).content, contentJson: content } })),
        pages: [{ context: owner, read: { mode: "snapshot", cursor: null, limit: 8 }, requestBytes: bytes(a), replyBytes: bytes(first) },
          { context: owner, read: { mode: "snapshot", cursor: cursor(1), limit: 8 }, requestBytes: bytes(b), replyBytes: bytes(last) }] } });
    for (const [request, reply] of [[a, first], [b, last]] as const) {
      expect(c.select(owner, request)).toEqual({ result: "unchanged" });
      expect(await c.receive(owner, request, reply)).toEqual({ result: "unchanged" });
      expect(c.view()).toEqual(completed);
    }
  });

  it("continues a completed snapshot with bounded changes, repeated IDs, reorder metadata and a tombstone", async () => {
    const c = await ready(), baseline = observed(c), a = read("changes"), b = read("changes", cursor(2));
    const moved = { ...live(1, 2, 9), object_revision: 2 };
    const tombstone = { ...envelope, profile_id: id(1), object_revision: 3, event_sequence: 4, deleted: true,
      order_key: null, content_revision: null, content_hash: null, content_json: null };
    const first = page([moved, live(2, 3)], cursor(2), "changes", 4), last = page([tombstone], null, "changes", 4);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, first)).toEqual({ result: "pending" });
    retainedCommit(c, baseline);
    expect(c.view().tentative).toMatchObject({ baseHighWatermark: 1, mode: "changes", nextCursor: cursor(2),
      items: [{ profileId: id(1), objectRevision: 2, contentRevision: 1, eventSequence: 2, orderKey: 9 }, fields(2, 3)] });
    const beforeRetry = observed(c);
    expect(await c.receive(owner, a, first)).toEqual({ result: "unchanged" });
    expect(observed(c)).toEqual(beforeRetry);
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    expect(await c.receive(owner, b, last)).toEqual({ result: "complete" });
    expect(observed(c).committed).toEqual({ context: owner, mode: "changes", snapshotId, highWatermark: 4,
      baseHighWatermark: 1, epoch: 3, items: [
        { ...fields(1, 2, 9), objectRevision: 2, deleted: false, content: { ...fields(1).content, contentJson: content } },
        { ...fields(2, 3), deleted: false, content: { ...fields(2).content, contentJson: content } },
        { profileId: id(1), objectRevision: 3, eventSequence: 4, deleted: true, orderKey: null, contentRevision: null, content: null },
      ], pages: [{ context: owner, read: { mode: "changes", cursor: null, limit: 8 }, requestBytes: bytes(a), replyBytes: bytes(first) },
        { context: owner, read: { mode: "changes", cursor: cursor(2), limit: 8 }, requestBytes: bytes(b), replyBytes: bytes(last) }] });
    const done = observed(c);
    expect(await c.receive(owner, a, first)).toEqual({ result: "unchanged" });
    expect(await c.receive(owner, b, last)).toEqual({ result: "unchanged" });
    expect(observed(c)).toEqual(done);
    const next = read("changes", null, 1);
    expect(c.select(owner, next)).toEqual({ result: "pending" });
    expect(await c.receive(owner, next, page([live(3, 5)], null, "changes", 5))).toEqual({ result: "complete" });
    expect(c.view().committed).toMatchObject({ baseHighWatermark: 4, highWatermark: 5, items: [fields(3, 5)] });
  });

  it("requires a snapshot initially and after an explicit reset, including a valid empty completed snapshot", async () => {
    const c = collector(), empty = observed(c);
    expect(c.select(owner, read("changes"))).toEqual({ result: "resync_required" });
    expect(observed(c)).toEqual(empty);
    await ready(c);
    const before = observed(c);
    expect(c.reset(owner)).toEqual({ result: "resync_required" });
    expect(c.view()).toMatchObject({ tentative: null, selected: null, parsing: null, requiresSnapshot: true });
    retainedCommit(c, before);
    const reset = observed(c);
    expect(c.select(owner, read("changes"))).toEqual({ result: "resync_required" });
    expect(observed(c)).toEqual(reset);
    const a = read();
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, page([], null, "snapshot", 1))).toEqual({ result: "complete" });
    expect(c.view().committed).toMatchObject({ context: owner, items: [], pages: [{ requestBytes: bytes(a) }] });
    expect(c.view().requiresSnapshot).toBe(false);
  });

  it("does not interpret an incomplete view's missing profile as a deletion", async () => {
    const c = await ready(), old = observed(c);
    expect(c.reset(owner)).toEqual({ result: "resync_required" });
    const a = read(), reply = page([live(2)], cursor(1), "snapshot", 2);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, reply)).toEqual({ result: "pending" });
    expect(c.view().tentative!.items.map(r => r.profileId)).toEqual([id(2)]);
    retainedCommit(c, old);
    expect(c.reset(owner)).toEqual({ result: "resync_required" });
    retainedCommit(c, old);
    expect(c.view().tentative).toBeNull();
  });

  it("owns exact request/reply subarray bytes and caller context before an asynchronous pause", async () => {
    const gate = pause(), supplied = { ...owner }, c = createProfileSyncV1ReadView({ sentinel, context: supplied, waitForParse: gate.wait });
    const request = read(), exactReply = page([live(1)], null, "snapshot", 1);
    const backing = new Uint8Array(exactReply.length + 6); backing.set(exactReply, 3);
    const reply = backing.subarray(3, 3 + exactReply.length);
    supplied.account = "sentinel-B";
    expect(c.select(owner, request)).toEqual({ result: "pending" });
    gate.arm();
    const pending = c.receive(owner, request, reply);
    await gate.entered;
    const captured = observed(c);
    expect(captured).toMatchObject({ context: owner, committed: null, tentative: null,
      selected: { requestBytes: bytes(request), context: owner }, parsing: { requestBytes: bytes(request), replyBytes: bytes(exactReply), context: owner } });
    request.fill(0); backing.fill(0);
    expect(observed(c)).toEqual(captured);
    gate.release();
    expect(await pending).toEqual({ result: "complete" });
    const v = c.view();
    expect(v.committed!.pages[0]!.requestBytes).toEqual(captured.selected!.requestBytes);
    expect(v.committed!.pages[0]!.replyBytes).toEqual(bytes(exactReply));
    expect(v.committed!.items[0]!.content!.contentJson).toBe(content);
    frozenTree(v);
    const other = c.view();
    expect(v).not.toBe(other);
    expect(v.committed).not.toBe(other.committed);
    expect(v.committed!.pages[0]!.replyBytes).not.toBe(other.committed!.pages[0]!.replyBytes);
    expect(Reflect.set(v.context!, "generation", 99)).toBe(false);
    expect(Reflect.set(v.committed!.pages[0]!.replyBytes, "0", 0)).toBe(false);
    expect(Reflect.set(v.committed!.items, "0", null)).toBe(false);
    expect(observed(c).committed!.items[0]!.content!.contentJson).toBe(content);
  });

  it("reset fences a captured late reply without changing a new completed winner", async () => {
    const gate = pause(), c = await ready(createProfileSyncV1ReadView({ sentinel, context: owner, waitForParse: gate.wait }));
    const prior = observed(c), oldRead = read("changes"), oldReply = page([live(2, 2)], null, "changes", 2);
    expect(c.select(owner, oldRead)).toEqual({ result: "pending" });
    gate.arm(); const late = c.receive(owner, oldRead, oldReply); await gate.entered;
    expect(c.reset(owner)).toEqual({ result: "resync_required" });
    retainedCommit(c, prior);
    const fresh = read();
    expect(c.select(owner, fresh)).toEqual({ result: "pending" });
    expect(await c.receive(owner, fresh, page([live(3, 3)], null, "snapshot", 3, "pss_" + "2".repeat(32)))).toEqual({ result: "complete" });
    const winner = observed(c);
    gate.release();
    expect(await late).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(winner);
    expect(await c.receive(owner, oldRead, oldReply)).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(winner);
  });

  it.each(["reset", "switch"] as const)("%s fences valid and invalid replies before real parsing settles", async control => {
    for (const invalid of [false, true]) {
      const c = await ready(), prior = observed(c), a = read("changes");
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      const stale = c.receive(owner, a, page([{ ...live(2, 2),
        content_hash: invalid ? "0".repeat(64) : contentHash }], null, "changes", 2));
      // No await: the real codec is still suspended at content hashing.
      const next = control === "reset" ? owner : foreign;
      expect(control === "reset" ? c.reset(owner) : c.switch(next)).toEqual({ result: "resync_required" });
      retainedCommit(c, prior);
      const fresh = read();
      expect(c.select(next, fresh)).toEqual({ result: "pending" });
      expect(await c.receive(next, fresh, page([live(3, 3)], null, "snapshot", 3))).toEqual({ result: "complete" });
      const winner = observed(c);
      expect(await stale).toEqual({ result: "quarantined" });
      expectSameObservation(observed(c), winner);
    }
  });

  it("exposes owned parsing diagnostics without publishing a final page before the timing fence", async () => {
    const gate = pause(), c = await ready(createProfileSyncV1ReadView({ sentinel, context: owner, waitForParse: gate.wait }));
    c.reset(owner);
    const a = read(), b = read("snapshot", cursor(1));
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, page([live(2, 2)], cursor(1), "snapshot", 3))).toEqual({ result: "pending" });
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    const before = observed(c), reply = page([live(3, 3)], null, "snapshot", 3);
    gate.arm(); const pending = c.receive(owner, b, reply); await gate.entered;
    const during = observed(c);
    expect(during.parsing).toEqual({ ...before.selected, replyBytes: bytes(reply) });
    expect(during.retainedBytes).toBe(before.retainedBytes + reply.length);
    expect(during.retainedPairs).toBe(before.retainedPairs + 1);
    expectSameObservation({ ...during, parsing: null, retainedBytes: before.retainedBytes,
      retainedPairs: before.retainedPairs }, before);
    frozenTree(c.view());
    gate.release();
    expect(await pending).toEqual({ result: "complete" });
    expect(c.view().committed!.items.map(r => r.profileId)).toEqual([id(2), id(3)]);
    expect(c.view()).toMatchObject({ tentative: null, selected: null, parsing: null, requiresSnapshot: false });
  });

  it("switch owns a higher-generation context, retains ORIGINAL committed provenance and fences late parse", async () => {
    const gate = pause(), c = await ready(createProfileSyncV1ReadView({ sentinel, context: owner, waitForParse: gate.wait }));
    const original = observed(c), a = read("changes"), reply = page([live(2, 2)], null, "changes", 2);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    gate.arm(); const late = c.receive(owner, a, reply); await gate.entered;
    const supplied = { ...foreign };
    expect(c.switch(supplied)).toEqual({ result: "resync_required" });
    supplied.generation = 100; supplied.account = "sentinel-A";
    expect(c.view()).toMatchObject({ context: foreign, tentative: null, selected: null, parsing: null, requiresSnapshot: true });
    retainedCommit(c, original);
    const switched = observed(c);
    expect(c.select(foreign, read("changes"))).toEqual({ result: "resync_required" });
    expect(observed(c)).toEqual(switched);
    expect(c.select(foreign, read())).toEqual({ result: "pending" });
    expect(await c.receive(foreign, read(), page([], null, "snapshot", 0))).toEqual({ result: "complete" });
    const winner = observed(c);
    gate.release(); expect(await late).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(winner);
    expect(winner.committed!.context).toEqual(foreign);
  });

  it("a same-partition higher generation still cannot use the retained old view as a changes baseline", async () => {
    const c = await ready(), original = observed(c), next = { ...owner, generation: 1 };
    expect(c.switch(next)).toEqual({ result: "resync_required" });
    retainedCommit(c, original);
    const before = observed(c);
    expect(c.select(next, read("changes"))).toEqual({ result: "resync_required" });
    expect(observed(c)).toEqual(before);
  });

  it.each([
    { ...owner, issuer: foreign.issuer }, { ...owner, environment: foreign.environment },
    { ...owner, account: foreign.account }, { ...owner, generation: 1 },
  ])("rejects mismatched context without touching any retained field: %j", async other => {
    const c = await ready(), before = observed(c);
    expect(c.select(other, read())).toEqual({ result: "quarantined" });
    expect(await c.receive(other, read(), page([]))).toEqual({ result: "quarantined" });
    expect(c.reset(other)).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(before);
  });

  it.each([-1, 0.5, Number.MAX_SAFE_INTEGER + 1, NaN, Infinity])("invalid generation %s cannot switch or admit source state", async generation => {
    const c = await ready(), before = observed(c), other = { ...foreign, generation };
    expect(c.switch(other)).toEqual({ result: "invalid" });
    expect(observed(c)).toEqual(before);
    const unavailable = createProfileSyncV1ReadView({ sentinel, context: other });
    expect(unavailable.select(other, read())).toEqual({ result: "unavailable" });
    expect(unavailable.view().context).toBeNull();
  });

  it("refuses non-increasing generation, unreserved context and historical revision reads without changing state", async () => {
    const c = await ready(), before = observed(c);
    for (const context of [owner, { ...foreign, generation: 0 }, { ...foreign, issuer: "https://real.invalid" }]) {
      expect(c.switch(context)).toEqual({ result: "invalid" });
      expect(observed(c)).toEqual(before);
    }
    const revision = wire({ ...envelope, mode: "revision", profile_id: id(1), content_revision: 1, content_hash: contentHash });
    expect(c.select(owner, revision)).toEqual({ result: "invalid" });
    expect(await c.receive(owner, revision, page([live(1)]))).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(before);
  });

  it("requires the exact selected request bytes rather than semantically equivalent reconstructed JSON", async () => {
    const c = await ready(); expect(c.reset(owner)).toEqual({ result: "resync_required" });
    const selected = read(), rebuilt = new TextEncoder().encode(new TextDecoder().decode(selected) + "\n");
    expect(c.select(owner, selected)).toEqual({ result: "pending" });
    const before = observed(c);
    expect(c.select(owner, rebuilt)).toEqual({ result: "quarantined" });
    expect(await c.receive(owner, rebuilt, page([live(2)], null, "snapshot", 2))).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(before);
    expect(await c.receive(owner, selected, page([live(2)], null, "snapshot", 2))).toEqual({ result: "complete" });
  });

  it("different replies to a stored exact request are quarantined, including whitespace-only rewrites", async () => {
    const c = collector(), a = read(), first = page([live(1)], cursor(1), "snapshot", 2);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, first)).toEqual({ result: "pending" });
    const staged = observed(c), changed = new TextEncoder().encode(new TextDecoder().decode(first) + "\n");
    expect(await c.receive(owner, a, changed)).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(staged);
    const b = read("snapshot", cursor(1)), last = page([live(2)], null, "snapshot", 2);
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    expect(await c.receive(owner, b, last)).toEqual({ result: "complete" });
    const done = observed(c);
    expect(await c.receive(owner, a, changed)).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(done);
  });

  it("does not allow a second different in-flight reply to win or replace the prior committed view", async () => {
    const gate = pause(), c = await ready(createProfileSyncV1ReadView({ sentinel, context: owner, waitForParse: gate.wait }));
    const old = observed(c), request = read("changes"), first = page([live(2, 2)], null, "changes", 2);
    expect(c.select(owner, request)).toEqual({ result: "pending" });
    gate.arm(); const pending = c.receive(owner, request, first); await gate.entered;
    const flight = observed(c);
    expect(await c.receive(owner, request, first)).toEqual({ result: "pending" });
    expect(observed(c)).toEqual(flight);
    expect(await c.receive(owner, request, page([live(3, 2)], null, "changes", 2))).toEqual({ result: "quarantined" });
    retainedCommit(c, old);
    const fenced = observed(c);
    gate.release(); expect(await pending).toEqual({ result: "quarantined" });
    expect(observed(c)).toEqual(fenced);
  });

  it("an early-resolving or throwing timing hook never replaces OWN real codec validation", async () => {
    for (const waitForParse of [() => Promise.resolve(), () => { throw new Error("synthetic timing fault"); }]) {
      const c = createProfileSyncV1ReadView({ sentinel, context: owner, waitForParse });
      const a = read(); expect(c.select(owner, a)).toEqual({ result: "pending" });
      const bad = page([{ ...live(1), content_hash: "0".repeat(64) }], null, "snapshot", 1);
      expect(await c.receive(owner, a, bad)).toEqual({ result: "invalid" });
      expect(c.view()).toMatchObject({ committed: null, tentative: null, selected: null, parsing: null, requiresSnapshot: true });
    }
  });

  it.each([
    ["mode", () => page([live(3, 3)], null, "changes", 10)],
    ["snapshot ID", () => page([live(3, 3)], null, "snapshot", 10, "pss_" + "2".repeat(32))],
    ["watermark", () => page([live(3, 3)], null, "snapshot", 11)],
    ["global order", () => page([live(3, 3, 1)], null, "snapshot", 10)],
    ["duplicate ID", () => page([{ ...live(2, 3), object_revision: 2 }], null, "snapshot", 10)],
    ["duplicate event", () => page([live(3, 2)], null, "snapshot", 10)],
    ["cursor loop", () => page([live(3, 3)], cursor(1), "snapshot", 10)],
  ] as const)("a cross-page %s mismatch discards tentative state, not the original committed view", async (_label, bad) => {
    const c = await ready(), old = observed(c); expect(c.reset(owner)).toEqual({ result: "resync_required" });
    const a = read(), b = read("snapshot", cursor(1));
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, page([live(2)], cursor(1), "snapshot", 10))).toEqual({ result: "pending" });
    const staged = observed(c);
    for (const [wrong, expected] of [[read("snapshot", cursor(2)), "quarantined"], [read("changes", cursor(1)), "quarantined"], [read("snapshot"), "unchanged"]] as const) {
      expect(c.select(owner, wrong)).toEqual({ result: expected });
      expect(observed(c)).toEqual(staged);
    }
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    expect(await c.receive(owner, b, bad())).toEqual({ result: "quarantined" });
    retainedCommit(c, old);
    expect(c.view()).toMatchObject({ tentative: null, selected: null, parsing: null, requiresSnapshot: true });
  });

  it("detects a cursor loop returning to an earlier page, not just the current cursor", async () => {
    const c = collector();
    for (let n = 1; n <= 3; n++) {
      const a = read("snapshot", n === 1 ? null : cursor(n - 1));
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, page([live(n)], n === 3 ? cursor(1) : cursor(n), "snapshot", 3)))
        .toEqual({ result: n === 3 ? "quarantined" : "pending" });
    }
    expect(c.view().committed).toBeNull();
    expect(c.view().requiresSnapshot).toBe(true);
  });

  it("enforces requested page size, unique snapshot events, and nondecreasing same-owner watermarks", async () => {
    for (const [limit, reply] of [[1, page([live(1), live(2)], null, "snapshot", 2)],
      [8, page([live(1), live(2, 1)], null, "snapshot", 2)], [8, page([], null, "snapshot", 0)]] as const) {
      const c = await ready(), old = observed(c); expect(c.reset(owner)).toEqual({ result: "resync_required" });
      const a = read("snapshot", null, limit); expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, reply)).toEqual({ result: "quarantined" });
      retainedCommit(c, old);
    }
  });

  it.each([
    ["sequence replay", () => ({ ...live(2, 2), object_revision: 2 })],
    ["object revision regression", () => ({ ...live(2, 3), object_revision: 1 })],
    ["immutable content generation changed", () => ({ ...live(2, 3), object_revision: 3, content_revision: 2 })],
  ] as const)("changes rejects cross-page %s", async (_label, bad) => {
    const c = await ready(), old = observed(c), a = read("changes"), b = read("changes", cursor(1));
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, page([{ ...live(2, 2), object_revision: 2 }], cursor(1), "changes", 3))).toEqual({ result: "pending" });
    expect(c.select(owner, b)).toEqual({ result: "pending" });
    expect(await c.receive(owner, b, page([bad()], null, "changes", 3))).toEqual({ result: "quarantined" });
    retainedCommit(c, old);
    expect(c.view().requiresSnapshot).toBe(true);
  });

  it("changes rejects immutable content bytes drift at the same content revision and resurrection after a tombstone", async () => {
    const changed = content.replace('"name":"Summary"', '"name":"Changed"');
    const changedHash = await profileSyncV1Hash(new TextEncoder().encode(changed)); // wire-input helper, NOT a verdict oracle
    for (const first of [live(2, 2), { ...envelope, profile_id: id(2), object_revision: 2, event_sequence: 2,
      deleted: true, order_key: null, content_revision: null, content_hash: null, content_json: null }]) {
      const c = await ready(), old = observed(c), a = read("changes"), b = read("changes", cursor(1));
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, page([first], cursor(1), "changes", 3))).toEqual({ result: "pending" });
      expect(c.select(owner, b)).toEqual({ result: "pending" });
      expect(await c.receive(owner, b, page([{ ...live(2, 3), object_revision: 3, content_json: changed, content_hash: changedHash }], null, "changes", 3)))
        .toEqual({ result: "quarantined" });
      retainedCommit(c, old);
    }
  });

  it("changes cannot replay baseline events or regress the pinned high-watermark", async () => {
    for (const reply of [page([live(2, 1)], null, "changes", 1), page([], null, "changes", 0)]) {
      const c = await ready(), old = observed(c), a = read("changes");
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, reply)).toEqual({ result: "quarantined" });
      retainedCommit(c, old);
    }
  });

  it("actual malformed/future content and incomplete empty pages fail closed without replacing committed bytes", async () => {
    const future = content.replace('"schema_version":1', '"schema_version":2');
    const futureHash = await profileSyncV1Hash(new TextEncoder().encode(future));
    for (const reply of [page([{ ...live(2), content_json: future, content_hash: futureHash }], null, "snapshot", 2),
      page([{ ...live(2), content_hash: "0".repeat(64) }], null, "snapshot", 2), page([], cursor(1), "snapshot", 2),
      new Uint8Array([0xff]), wire({ ...envelope, mode: "snapshot", private_message: "never reflect this" })]) {
      const c = await ready(), old = observed(c); expect(c.reset(owner)).toEqual({ result: "resync_required" });
      const a = read(); expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, reply)).toEqual({ result: "invalid" });
      retainedCommit(c, old);
      expect(c.view()).toMatchObject({ tentative: null, selected: null, parsing: null, requiresSnapshot: true });
    }
  });

  it("real AS05 fixed errors never become success pages, cursor movement or reflected private state", async () => {
    for (const error of ["unavailable", "invalid", "requires_upgrade", "conflict", "gone", "not_found", "resync_required",
      "idempotency_mismatch", "intent_expired", "verification_pending", "quota_exceeded"]) {
      const c = await ready(), old = observed(c), a = read("changes");
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      const selected = observed(c), expected = error === "resync_required" ? "resync_required" : error === "requires_upgrade" ? "invalid" :
        ["unavailable", "invalid", "quota_exceeded"].includes(error) ? error : "quarantined";
      expect(await c.receive(owner, a, wire({ ...envelope, result: error }))).toEqual({ result: expected });
      retainedCommit(c, old);
      if (!["resync_required", "requires_upgrade"].includes(error)) expect(observed(c)).toEqual(selected);
      else expect(c.view()).toMatchObject({ tentative: null, selected: null, requiresSnapshot: true });
    }
    const c = await ready(), old = observed(c), a = read("changes");
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, wire({ ...envelope, result: "resync_required", message: "private" }))).toEqual({ result: "invalid" });
    retainedCommit(c, old);
  });

  it("accepts exactly 100 snapshot items and refuses item 101 while preserving the ENTIRE prior observer", async () => {
    const c = collector();
    for (let start = 1; start <= 100; start += 8) {
      const a = read("snapshot", start === 1 ? null : cursor(start)), end = Math.min(start + 7, 100);
      const reply = page(Array.from({ length: end - start + 1 }, (_, i) => live(start + i)), end === 100 ? null : cursor(start + 8), "snapshot", 100);
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      expect(await c.receive(owner, a, reply)).toEqual({ result: end === 100 ? "complete" : "pending" });
    }
    expect(c.view().committed!.items.map(r => r.profileId)).toEqual(Array.from({ length: 100 }, (_, i) => id(i + 1)));
    const complete = observed(c); expect(c.reset(owner)).toEqual({ result: "resync_required" });
    for (let start = 1; start <= 97; start += 8) {
      const a = read("snapshot", start === 1 ? null : cursor(start)), end = Math.min(start + 7, 101);
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      const before = end === 101 ? observed(c) : null;
      const reply = page(Array.from({ length: end - start + 1 }, (_, i) => live(start + i)), end === 101 ? null : cursor(start + 8), "snapshot", 101);
      expect(await c.receive(owner, a, reply)).toEqual({ result: end === 101 ? "quota_exceeded" : "pending" });
      retainedCommit(c, complete);
      if (before) expectSameObservation(observed(c), before);
    }
  });

  it("accepts 256 change events and refuses event 257 without dropping prior committed/tentative/selected data", async () => {
    const c = await ready();
    for (const [count, startSequence] of [[256, 2], [257, 258]] as const) {
      for (let offset = 0; offset < count; offset += 8) {
        const end = Math.min(offset + 8, count), original = read("changes", offset === 0 ? null : cursor(offset));
        // A deliberately NEW exact wire request, not a retry of the prior round's stored pair.
        const a = count === 257 ? new TextEncoder().encode(new TextDecoder().decode(original) + "\n") : original;
        const reply = page(Array.from({ length: end - offset }, (_, i) => live(startSequence + offset + i, startSequence + offset + i)),
          end === count ? null : cursor(end), "changes", startSequence + count - 1);
        expect(c.select(owner, a)).toEqual({ result: "pending" });
        // Only the rejected final page needs a before/after observer comparison.
        // Earlier pages still assert selection and admission, without repeatedly
        // copying every retained wire byte into an unused diagnostic snapshot.
        const before = count === 257 && end === count ? observed(c) : null;
        expect(await c.receive(owner, a, reply)).toEqual({ result: end === count ? count === 256 ? "complete" : "quota_exceeded" : "pending" });
        if (before) expectSameObservation(observed(c), before);
      }
      expect(c.view().committed!.items.length).toBe(256);
      expect(c.view().committed!.highWatermark).toBe(257);
    }
  });

  it("bounds aggregate retained page pairs at 256 INCLUDING the prior committed view; exact retries are free", async () => {
    const c = await ready();
    for (let n = 1; n <= 256; n++) {
      const a = read("changes", n === 1 ? null : cursor(n)), reply = page([live(n + 1, n + 1)], n === 256 ? null : cursor(n + 1), "changes", 257);
      expect(c.select(owner, a)).toEqual({ result: "pending" });
      const before = n === 256 ? observed(c) : null;
      expect(await c.receive(owner, a, reply)).toEqual({ result: n === 256 ? "quota_exceeded" : "pending" });
      if (before) expectSameObservation(observed(c), before);
      if (n === 255) {
        expect(c.view().retainedPairs).toBe(256);
        const staged = observed(c);
        expect(await c.receive(owner, a, reply)).toEqual({ result: "unchanged" });
        expectSameObservation(observed(c), staged);
      }
    }
    expect(c.view().committed!.mode).toBe("snapshot");
  });

  it("checks 8192-byte requests, individual reply limits and SharedArrayBuffer BEFORE retaining anything", async () => {
    const c = collector(), a = read(), padded = new Uint8Array(8192); padded.fill(32); padded.set(a);
    expect(c.select(owner, padded)).toEqual({ result: "pending" });
    const selected = observed(c);
    expect(c.select(owner, new Uint8Array(8193))).toEqual({ result: "quota_exceeded" });
    expect(await c.receive(owner, padded, new Uint8Array(4_194_305))).toEqual({ result: "quota_exceeded" });
    for (const shared of [new Uint8Array(new SharedArrayBuffer(0)), new Uint8Array(new SharedArrayBuffer(a.length))]) {
      expect(c.select(owner, shared)).toEqual({ result: "invalid" });
      expect(await c.receive(owner, shared, page([]))).toEqual({ result: "invalid" });
      expect(await c.receive(owner, padded, shared)).toEqual({ result: "invalid" });
      expect(observed(c)).toEqual(selected);
    }
    expect(await c.receive(owner, padded, page([], null, "snapshot", 0))).toEqual({ result: "complete" });
    expect(c.view().committed!.pages[0]!.requestBytes).toEqual(bytes(padded));
  });

  it("the 4MiB aggregate byte boundary includes exact replies, tentative pages and selected requests", async () => {
    const maximum = 4_194_304, a = read(), small = page([], null, "snapshot", 0), c = collector();
    const exact = new Uint8Array(maximum - a.length); exact.fill(32); exact.set(small);
    expect(c.select(owner, a)).toEqual({ result: "pending" });
    expect(await c.receive(owner, a, exact)).toEqual({ result: "complete" });
    expect(c.view().retainedBytes).toBe(maximum);
    const full = observed(c);
    expect(c.select(owner, read("changes"))).toEqual({ result: "quota_exceeded" });
    expectSameObservation(observed(c), full);
    expect(await c.receive(owner, a, exact)).toEqual({ result: "unchanged" });
    expectSameObservation(observed(c), full);
    const fresh = collector(); expect(fresh.select(owner, a)).toEqual({ result: "pending" });
    const before = observed(fresh);
    expect(await fresh.receive(owner, a, new Uint8Array(maximum - a.length + 1))).toEqual({ result: "quota_exceeded" });
    expect(observed(fresh)).toEqual(before);
    const staged = collector(), first = page([live(1)], cursor(1), "snapshot", 2), b = read("snapshot", cursor(1));
    expect(staged.select(owner, a)).toEqual({ result: "pending" });
    expect(await staged.receive(owner, a, first)).toEqual({ result: "pending" });
    expect(staged.select(owner, b)).toEqual({ result: "pending" });
    const tentative = observed(staged), tooLarge = new Uint8Array(maximum - tentative.retainedBytes + 1);
    expect(await staged.receive(owner, b, tooLarge)).toEqual({ result: "quota_exceeded" });
    expect(observed(staged)).toEqual(tentative);
  });

  it("the unavailable default and invalid synthetic admission have an empty frozen observer and no external ports", async () => {
    const crypto = vi.spyOn(globalThis.crypto.subtle, "digest"), network = vi.spyOn(globalThis, "fetch");
    try {
      const c = createProfileSyncV1ReadView(), poison = new Uint8Array(0);
      Object.defineProperty(poison, "buffer", { get() { throw new Error("default must not inspect bytes"); } });
      expect(c.select(owner, poison)).toEqual({ result: "unavailable" });
      expect(await c.receive(owner, poison, poison)).toEqual({ result: "unavailable" });
      expect(c.reset(owner)).toEqual({ result: "unavailable" });
      expect(c.switch(foreign)).toEqual({ result: "unavailable" });
      expect(observed(c)).toEqual({ context: null, committed: null, tentative: null, selected: null, parsing: null,
        requiresSnapshot: true, epoch: 0, retainedBytes: 0, retainedPairs: 0 });
      frozenTree(c.view());
      const invalid = createProfileSyncV1ReadView({ sentinel, context: { ...owner, issuer: "https://unselected.invalid" },
        waitForParse: () => { throw new Error("unavailable timing hook invoked"); } });
      expect(await invalid.receive(owner, poison, poison)).toEqual({ result: "unavailable" });
      expect(observed(invalid)).toEqual(observed(c));
      expect(crypto).not.toHaveBeenCalled(); expect(network).not.toHaveBeenCalled();
    } finally { crypto.mockRestore(); network.mockRestore(); }
  });
});
