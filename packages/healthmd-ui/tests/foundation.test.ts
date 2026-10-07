import assert from "node:assert/strict";
import { test } from "node:test";
import { createReadinessModel, projectReadiness } from "../src/index.js";
import type { OperationScope, SourceReadiness } from "../src/index.js";
const health: SourceReadiness = { id: "synthetic.health", domain: "health", capture: "unknown", display: "available", query: "unavailable", export: "planned" };
const usage: SourceReadiness = { id: "synthetic.usage", domain: "usage", capture: "planned", display: "unknown", query: "planned", export: "planned" };
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
test("initial unknown state and selected-domain props never admit source grants", async () => {
  let reads = 0; let released = 0;
  const model = createReadinessModel({ read: async (scope) => { reads++; scope.addFinalizer(() => { released++; }); return [health, usage]; } });
  assert.deepEqual(model.getSnapshot(), { phase: "idle", selectedDomain: "all", sources: [], errorCode: null });
  model.selectDomain("usage"); assert.equal(reads, 0);
  await model.refresh(); assert.equal(reads, 1); assert.equal(released, 1);
  const props = projectReadiness(model.getSnapshot());
  assert.equal(props.phase, "ready"); assert.deepEqual(props.sources, [usage]);
  assert.equal(model.getSnapshot().sources[0]?.capture, "unknown");
  assert.equal(model.getSnapshot().sources[0]?.query, "unavailable");
  assert.ok(Object.isFrozen(props.sources)); assert.ok(Object.isFrozen(props.sources[0]));
  await model.dispose();
});
test("subscription observes actions and cleanup detaches component lifecycle", async () => {
  const model = createReadinessModel({ read: async () => [health] });
  const phases: string[] = [];
  const unsubscribe = model.subscribe(() => { phases.push(model.getSnapshot().phase); });
  model.selectDomain("health"); await model.refresh(); unsubscribe(); model.selectDomain("all");
  assert.deepEqual(phases, ["idle", "loading", "ready"]);
  await model.dispose(); assert.equal(model.getSnapshot().phase, "disposed");
  assert.throws(() => model.subscribe(() => {}), /model_disposed/);
  await assert.rejects(model.refresh(), /model_disposed/);
});
test("dispose awaits owned async cleanup and ignores late source results", async () => {
  const read = deferred<readonly SourceReadiness[]>(); const released = deferred<void>();
  let scope: OperationScope | undefined; let cleanups = 0;
  const model = createReadinessModel({ read: (ctx) => { scope = ctx; ctx.addFinalizer(async () => { cleanups++; await released.promise; }); return read.promise; } });
  const pending = model.refresh(); const disposing = model.dispose();
  assert.equal(scope?.isCancelled(), true); assert.equal(cleanups, 1);
  let disposed = false; let disposedAgain = false;
  const again = model.dispose().then(() => { disposedAgain = true; });
  void disposing.then(() => { disposed = true; }); await Promise.resolve();
  assert.equal(disposed, false); assert.equal(disposedAgain, false);
  released.resolve(); await Promise.all([disposing, again]); read.resolve([health]); await pending;
  assert.equal(cleanups, 1); assert.deepEqual(model.getSnapshot().sources, []);
  await model.dispose(); assert.equal(cleanups, 1);
});
test("superseding refresh cancels old work without stale publication", async () => {
  const old = deferred<readonly SourceReadiness[]>(); let calls = 0; let cleanup = 0;
  const model = createReadinessModel({ read: (scope) => { calls++; scope.addFinalizer(() => { cleanup++; }); return calls === 1 ? old.promise : Promise.resolve([usage]); } });
  const first = model.refresh(); await model.refresh(); old.resolve([health]); await first;
  assert.deepEqual(model.getSnapshot().sources, [usage]); assert.equal(cleanup, 2); await model.dispose();
});
test("cancel retains loaded state and can refresh again without double cleanup", async () => {
  const blocked = deferred<readonly SourceReadiness[]>(); let calls = 0; let cleanup = 0;
  const model = createReadinessModel({ read: (scope) => { scope.addFinalizer(() => { cleanup++; }); return ++calls === 2 ? blocked.promise : Promise.resolve([health]); } });
  await model.refresh(); const pending = model.refresh(); await model.cancel();
  assert.equal(model.getSnapshot().phase, "idle"); assert.deepEqual(model.getSnapshot().sources, [health]);
  blocked.resolve([usage]); await pending; await model.refresh(); assert.equal(cleanup, 3); await model.dispose();
});
test("raw operation and cleanup errors become content-free state", async () => {
  const model = createReadinessModel({ read: async (scope) => { scope.addFinalizer(() => { throw new Error("private_cleanup"); }); throw new Error("private_provider_payload"); } });
  await model.refresh(); assert.equal(model.getSnapshot().errorCode, "cleanup_failed");
  assert.doesNotMatch(JSON.stringify(model.getSnapshot()), /private/); await model.dispose();
  const other = createReadinessModel({ read: async () => { throw new Error("private_token"); } });
  await other.refresh(); assert.equal(other.getSnapshot().errorCode, "operation_failed"); await other.dispose();
});
test("bounded source descriptor validation rejects duplicate or oversized results", async () => {
  for (const result of [[health, health], Array.from({ length: 65 }, (_, i) => ({ ...health, id: `synthetic.${i}` }))]) {
    const model = createReadinessModel({ read: async () => result }); await model.refresh();
    assert.equal(model.getSnapshot().errorCode, "invalid_source_state"); assert.deepEqual(model.getSnapshot().sources, []); await model.dispose();
  }
});
test("independent models and hostile view listeners do not affect operation cleanup", async () => {
  let cleaned = 0;
  const one = createReadinessModel({ read: async (scope) => { scope.addFinalizer(() => { cleaned++; }); return [health]; } });
  const two = createReadinessModel({ read: async () => [usage] });
  one.subscribe(() => { throw new Error("view_failure"); }); await Promise.all([one.refresh(), two.refresh()]);
  assert.equal(cleaned, 1); one.selectDomain("health"); assert.equal(two.getSnapshot().selectedDomain, "all");
  await Promise.all([one.dispose(), two.dispose()]);
});

function supersedeFixture() {
  const firstResult = deferred<readonly SourceReadiness[]>();
  const releaseCleanup = deferred<void>();
  let reads = 0;
  let cleanupStarted = 0;
  let cleanupAcknowledged = 0;
  const model = createReadinessModel({ read: (scope) => {
    reads++;
    if (reads === 1) {
      scope.addFinalizer(async () => {
        cleanupStarted++;
        await releaseCleanup.promise;
        cleanupAcknowledged++;
      });
      return firstResult.promise;
    }
    return Promise.resolve([usage]);
  } });
  const first = model.refresh();
  const second = model.refresh();
  return { model, first, second, firstResult, releaseCleanup,
    counts: () => ({ reads, cleanupStarted, cleanupAcknowledged }) };
}
test("dispose during supersede waits for prior cleanup acknowledgement", async () => {
  const f = supersedeFixture();
  let disposed = false;
  const disposing = f.model.dispose().then(() => { disposed = true; });
  await Promise.resolve();
  assert.equal(disposed, false);
  assert.deepEqual(f.counts(), { reads: 1, cleanupStarted: 1, cleanupAcknowledged: 0 });
  f.releaseCleanup.resolve();
  await Promise.all([disposing, f.second]);
  f.firstResult.resolve([health]); await f.first;
  assert.equal(disposed, true);
  assert.deepEqual(f.counts(), { reads: 1, cleanupStarted: 1, cleanupAcknowledged: 1 });
  assert.equal(f.model.getSnapshot().phase, "disposed");
  assert.deepEqual(f.model.getSnapshot().sources, []);
});
test("cancel during supersede waits for prior cleanup and prevents successor read", async () => {
  const f = supersedeFixture();
  let cancelled = false;
  const cancelling = f.model.cancel().then(() => { cancelled = true; });
  await Promise.resolve();
  assert.equal(cancelled, false);
  assert.deepEqual(f.counts(), { reads: 1, cleanupStarted: 1, cleanupAcknowledged: 0 });
  f.releaseCleanup.resolve(); await Promise.all([cancelling, f.second]);
  f.firstResult.resolve([health]); await f.first;
  assert.equal(cancelled, true); assert.equal(f.model.getSnapshot().phase, "idle");
  assert.deepEqual(f.counts(), { reads: 1, cleanupStarted: 1, cleanupAcknowledged: 1 });
  await f.model.refresh();
  assert.deepEqual(f.model.getSnapshot().sources, [usage]);
  assert.equal(f.counts().reads, 2); await f.model.dispose();
});
test("third refresh during supersede cannot acquire before prior cleanup", async () => {
  const f = supersedeFixture();
  const third = f.model.refresh();
  await Promise.resolve();
  assert.deepEqual(f.counts(), { reads: 1, cleanupStarted: 1, cleanupAcknowledged: 0 });
  f.releaseCleanup.resolve(); await Promise.all([f.second, third]);
  f.firstResult.resolve([health]); await f.first;
  assert.deepEqual(f.counts(), { reads: 2, cleanupStarted: 1, cleanupAcknowledged: 1 });
  assert.deepEqual(f.model.getSnapshot().sources, [usage]);
  assert.equal(f.model.getSnapshot().phase, "ready"); await f.model.dispose();
});
test("loading subscriber disposal prevents stale operation acquisition", async () => {
  let reads = 0; let disposing: Promise<void> | undefined;
  const model = createReadinessModel({ read: async () => { reads++; return [health]; } });
  model.subscribe(() => {
    if (model.getSnapshot().phase === "loading") disposing = model.dispose();
  });
  await model.refresh(); await disposing;
  assert.equal(reads, 0); assert.equal(model.getSnapshot().phase, "disposed");
  assert.deepEqual(model.getSnapshot().sources, []);
});
test("loading subscriber cancellation prevents read and permits later refresh", async () => {
  let reads = 0; let cancelling: Promise<void> | undefined;
  const model = createReadinessModel({ read: async () => { reads++; return [health]; } });
  const unsubscribe = model.subscribe(() => {
    if (model.getSnapshot().phase === "loading") cancelling = model.cancel();
  });
  await model.refresh(); await cancelling;
  assert.equal(reads, 0); assert.equal(model.getSnapshot().phase, "idle");
  assert.deepEqual(model.getSnapshot().sources, []);
  unsubscribe(); await model.refresh(); assert.equal(reads, 1);
  assert.deepEqual(model.getSnapshot().sources, [health]); await model.dispose();
});
test("one-time loading subscriber refresh acquires only the latest operation", async () => {
  let reads = 0; let cleanup = 0; let reentered = false;
  let successor: Promise<void> | undefined;
  const model = createReadinessModel({ read: async (scope) => {
    reads++; scope.addFinalizer(() => { cleanup++; }); return [usage];
  } });
  model.subscribe(() => {
    if (!reentered && model.getSnapshot().phase === "loading") {
      reentered = true; successor = model.refresh();
    }
  });
  await model.refresh(); await successor;
  assert.equal(reads, 1); assert.equal(cleanup, 1);
  assert.equal(model.getSnapshot().phase, "ready");
  assert.deepEqual(model.getSnapshot().sources, [usage]); await model.dispose();
});
