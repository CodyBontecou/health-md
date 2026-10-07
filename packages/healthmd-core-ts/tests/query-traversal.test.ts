import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Result from "effect/Result";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import { TestClock } from "effect/testing";
import { QuerySource, ownQueryResource, traverseQuery, traversalBounds, type QueryBinding, type QueryBody, type AttributedPage, type TraversalRequest, type QueryFailure } from "../src/operations/query.js";
import { normalizeMetricChart } from "../src/operations/normalize.js";
import { traversalVectors, authorityVectors } from "./query-traversal-vectors.js";

const binding: QueryBinding = { caller: "synthetic-caller", source: "synthetic-source", profile: "local_read_only", coverage: "synthetic-coverage", logicalQuery: "synthetic-query", dataset: "synthetic-dataset" };
function request(allPages = true, cursor: string | null = null): TraversalRequest {
  const normalized = normalizeMetricChart({ dates: { type: "all_available" }, metrics: { type: "all_available" }, all_pages: allPages, page: { max_items: 1000, max_bytes: 1048576, cursor } });
  assert.ok(Result.isSuccess(normalized));
  return { invocation: normalized.success, binding, grants: ["healthmd:read"], deadlineMilliseconds: 60000 };
}
function fake(pages: readonly { readonly body: unknown; readonly encodedBytes: number }[], pageBinding = binding) {
  const state = { acquired: 0, released: 0, cursors: [] as (string | null)[] };
  const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.sync(() => {
    state.acquired++;
    return { binding, read: (cursor: string | null) => Effect.sync(() => {
      const index = state.cursors.length; state.cursors.push(cursor);
      assert.ok(pages[index], "fixed synthetic page exists");
      return { ...pages[index]!, body: pages[index]!.body as QueryBody, binding: pageBinding, requestedCursor: cursor };
    }), release: Effect.sync(() => { state.released++; }) };
  })) });
  return { layer, state };
}
const evaluate = (input: TraversalRequest, layer: ReturnType<typeof fake>["layer"]) => Effect.runPromise(traverseQuery(input).pipe(Effect.result, Effect.provide(layer)));
for (const vector of traversalVectors) {
  test(`traversal fixed receipt: ${vector.id}`, async () => {
    const host = fake(vector.pages); const result = await evaluate(request(vector.allPages, vector.initialCursor), host.layer);
    if (vector.expectedFailure) { assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, vector.expectedFailure); }
    else { assert.ok(Result.isSuccess(result)); assert.deepEqual(result.success, vector.expected); }
    assert.equal(host.state.acquired, 1); assert.equal(host.state.released, 1);
  });
}
for (const vector of authorityVectors) {
  test(`traversal authority: ${vector.id}`, async () => {
    const input = request(); const altered = vector.mutation === "grant" ? binding : { ...binding, [vector.mutation]: "wrong-synthetic" } as QueryBinding;
    const host = fake([{ body: { items: [], next_cursor: null }, encodedBytes: 30 }], altered);
    const result = await evaluate(vector.mutation === "grant" ? { ...input, grants: [] } : input, host.layer);
    assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, vector.expectedFailure);
    assert.equal(host.state.acquired, vector.mutation === "grant" ? 0 : 1);
    assert.equal(host.state.released, vector.mutation === "grant" ? 0 : 1);
  });
}

test("page limit4096 preserves next opaque cursor and exactly4096 source calls", async () => {
  assert.deepEqual(traversalBounds, { aggregateBytes: 2097152, receiptReserveBytes: 16384, pages: 4096, pageBytes: 1048576, pageItems: 1000 });
  let calls = 0; let releases = 0;
  const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
    read: (cursor: string | null) => Effect.sync(() => ({ body: { items: [], next_cursor: `opaque-${++calls}` }, encodedBytes: 40, binding, requestedCursor: cursor })),
    release: Effect.sync(() => { releases++; }),
  })) });
  const result = await evaluate(request(), layer); assert.ok(Result.isSuccess(result));
  assert.equal(calls, 4096); assert.equal(releases, 1);
  const receipt = result.success as { receipt: unknown };
  assert.deepEqual(receipt.receipt, { page_count: 4096, item_count: 0, packet_fact_count: 0, traversal_complete: false, next_cursor: "opaque-4096", limit_reason: "maximum_pages" });
});

test("aggregate boundary admits exact2080768 and replays first excluded page", async () => {
  const first = { body: { items: [], next_cursor: "opaque-b" }, encodedBytes: 1048576 };
  const terminal = { body: { items: [], next_cursor: null }, encodedBytes: 1032192 };
  const exact = await evaluate(request(), fake([first, terminal]).layer); assert.ok(Result.isSuccess(exact));
  assert.equal((exact.success as { receipt: { traversal_complete: boolean } }).receipt.traversal_complete, true);
  const exceeded = await evaluate(request(), fake([first, { ...terminal, encodedBytes: 1032193 }]).layer); assert.ok(Result.isSuccess(exceeded));
  assert.deepEqual((exceeded.success as { receipt: unknown }).receipt, { page_count: 1, item_count: 0, packet_fact_count: 0, traversal_complete: false, next_cursor: "opaque-b", limit_reason: "maximum_aggregate_bytes" });
  const continued = await evaluate(request(true, "opaque-b"), fake([terminal]).layer); assert.ok(Result.isSuccess(continued));
  assert.equal((continued.success as { receipt: { traversal_complete: boolean } }).receipt.traversal_complete, true);
});

test("first-page and single-page aggregate overflow fail without partial result", async () => {
  for (const allPages of [false, true]) {
    const host = fake([{ body: { items: [], next_cursor: null }, encodedBytes: 101 }]);
    const result = await evaluate({ ...request(allPages), limits: { maximumBytes: 16484, maximumPages: 4096 } }, host.layer);
    assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, "healthmd_response_too_large"); assert.equal(host.state.released, 1);
  }
});

test("page controls and actual page bytes/items enforce1MiB/1000 admission", async () => {
  for (const page of [{ max_items: 1001, max_bytes: 1048576 }, { max_items: 1000, max_bytes: 1048577 }, { max_items: 0, max_bytes: 1 }]) {
    const input = request(); const host = fake([]);
    const result = await evaluate({ ...input, invocation: { ...input.invocation, query: { ...input.invocation.query, page } } }, host.layer);
    assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, "healthmd_invalid_arguments"); assert.equal(host.state.acquired, 0);
  }
  for (const page of [{ body: { items: [], next_cursor: null }, encodedBytes: 1048577 }, { body: { items: Array(1001).fill(null), next_cursor: null }, encodedBytes: 100 }]) {
    const host = fake([page]); const result = await evaluate(request(), host.layer); assert.ok(Result.isFailure(result)); assert.equal(host.state.released, 1);
  }
});

test("source admission rejection and wrong owned binding remain separate", async () => {
  for (const reject of [true, false]) {
    let releases = 0; let reads = 0;
    const layer = Layer.succeed(QuerySource)({ open: () => reject ? Effect.fail({ code: "healthmd_query_unavailable" } as QueryFailure)
      : ownQueryResource(Effect.succeed({ binding: { ...binding, source: "other" }, read: () => Effect.sync(() => { reads++; throw new Error("must-not-read"); }), release: Effect.sync(() => { releases++; }) })) });
    const result = await evaluate(request(), layer); assert.ok(Result.isFailure(result));
    assert.equal(result.failure.code, reject ? "healthmd_query_unavailable" : "healthmd_query_binding_mismatch");
    assert.equal(reads, 0); assert.equal(releases, reject ? 0 : 1);
  }
});

test("validated-body attribution is a trusted adapter precondition, not sidecar authentication", async () => {
  let releases = 0;
  const captured = { items: [], next_cursor: null, coverage: { source: "wrong-synthetic-source" } };
  const layer = Layer.succeed(QuerySource)({ open: (input) => ownQueryResource(Effect.succeed({ binding,
    read: (cursor) => captured.coverage.source !== input.binding.source
      ? Effect.fail({ code: "healthmd_query_binding_mismatch" } as QueryFailure)
      : Effect.succeed({ body: captured, encodedBytes: 90, binding, requestedCursor: cursor }),
    release: Effect.sync(() => { releases++; }),
  })) });
  // This is an independently defined synthetic adapter rule, not a native coverage decoder.
  const result = await evaluate(request(), layer); assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, "healthmd_query_binding_mismatch"); assert.equal(releases, 1);
});

test("logical deadline is not reset by progressing pages and releases owned resource", async () => {
  let calls = 0; let releases = 0;
  const result = await Effect.runPromise(Effect.gen(function* () {
    const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
      read: (cursor: string | null) => Effect.sleep("6 seconds").pipe(Effect.map(() => ({ body: { items: [], next_cursor: `opaque-${++calls}` }, encodedBytes: 30, binding, requestedCursor: cursor }))),
      release: Effect.sync(() => { releases++; }),
    })) });
    const fiber = yield* Effect.forkChild(traverseQuery({ ...request(), deadlineMilliseconds: 10000 }).pipe(Effect.result, Effect.provide(layer)));
    yield* TestClock.adjust("6 seconds"); yield* TestClock.adjust("4 seconds");
    return yield* Fiber.join(fiber);
  }).pipe(Effect.provide(TestClock.layer())));
  assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, "healthmd_query_deadline"); assert.equal(calls, 1); assert.equal(releases, 1);
});

test("interruption waits for release acknowledgment and releases exactly once", async () => {
  let completed = false; let releases = 0;
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const acknowledged = yield* Deferred.make<void>();
    const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
      read: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)),
      release: Effect.gen(function* () { releases++; yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(acknowledged); completed = true; }),
    })) });
    const work = yield* Effect.forkChild(traverseQuery(request()).pipe(Effect.provide(layer))); yield* Deferred.await(entered);
    const interrupted = yield* Effect.forkChild(Fiber.interrupt(work)); yield* Deferred.await(releasing);
    assert.equal(completed, false); yield* Deferred.succeed(acknowledged, undefined); yield* Fiber.join(interrupted);
    const exit = yield* Effect.exit(Fiber.join(work)); assert.ok(Exit.hasInterrupts(exit)); yield* Fiber.interrupt(work);
  }));
  assert.equal(completed, true); assert.equal(releases, 1);
});

test("frozen Swift reference page survives single-page traversal without evaluator claims", async () => {
  const bytes = await readFile("../contracts/direct-protocol/v3/fixtures/swift-reference.json");
  assert.equal(createHash("sha256").update(bytes).digest("hex"), "25b7a6ddeb22f67d713c577682c359f5ae4b9f97b87acc743c64b01860bdc5b2");
  const fixture = JSON.parse(bytes.toString("utf8"));
  const body = fixture.query_response.queryResponse._0.response;
  assert.equal(body.schema, "healthmd.query_response");
  const host = fake([{ body, encodedBytes: 2000 }]); const result = await evaluate(request(false), host.layer);
  assert.ok(Result.isSuccess(result)); assert.deepEqual(result.success, body);
});


test("initial cursor replay requires adapter admission of the same logical query", async () => {
  const input = request(true, "opaque-a"); let reads = 0;
  // Fake adapter's admitted cursor record stands in for separately qualified native crypto.
  const admitted = { cursor: "opaque-a", logicalQuery: binding.logicalQuery };
  const layer = Layer.succeed(QuerySource)({ open: (candidate) => candidate.binding.logicalQuery !== admitted.logicalQuery
    ? Effect.fail({ code: "healthmd_query_binding_mismatch" } as QueryFailure)
    : ownQueryResource(Effect.succeed({ binding: candidate.binding, read: (cursor) => Effect.sync(() => { reads++; return { body: { items: [], next_cursor: null }, encodedBytes: 30, binding: candidate.binding, requestedCursor: cursor }; }), release: Effect.void })) });
  const wrong = await evaluate({ ...input, binding: { ...binding, logicalQuery: "changed-query" } }, layer);
  assert.ok(Result.isFailure(wrong)); assert.equal(wrong.failure.code, "healthmd_query_binding_mismatch"); assert.equal(reads, 0);
  const valid = await evaluate(input, layer); assert.ok(Result.isSuccess(valid)); assert.equal(reads, 1);
});

test("requested cursor mismatch and backend failures are sanitized with cleanup", async () => {
  for (const wrongCursor of [true, false]) {
    let releases = 0;
    const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
      read: () => wrongCursor ? Effect.succeed({ body: { items: [], next_cursor: null }, encodedBytes: 30, binding, requestedCursor: "wrong-synthetic" })
        : Effect.fail({ code: "healthmd_query_unavailable", cause: "synthetic-private-marker" } as QueryFailure),
      release: Effect.sync(() => { releases++; }),
    })) });
    const result = await evaluate(request(), layer); assert.ok(Result.isFailure(result));
    assert.deepEqual(result.failure, { code: wrongCursor ? "healthmd_query_binding_mismatch" : "healthmd_query_unavailable" }); assert.equal(releases, 1);
  }
});


test("deadline interrupts admission and waits its partial-acquisition cleanup", async () => {
  let cleaned = 0;
  const result = await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>();
    const layer = Layer.succeed(QuerySource)({ open: () => Deferred.succeed(entered, undefined).pipe(
      Effect.andThen(Effect.never), Effect.ensuring(Effect.sync(() => { cleaned++; })),
    ) });
    const work = yield* Effect.forkChild(traverseQuery({ ...request(), deadlineMilliseconds: 1000 }).pipe(Effect.result, Effect.provide(layer)));
    yield* Deferred.await(entered); yield* TestClock.adjust("1 second");
    return yield* Fiber.join(work);
  }).pipe(Effect.provide(TestClock.layer())));
  assert.ok(Result.isFailure(result)); assert.equal(result.failure.code, "healthmd_query_deadline"); assert.equal(cleaned, 1);
});

test("pending interruption at completed allocation cannot cross an unregistered ownership handoff", async () => {
  const state = { acquired: 0, openCompleted: 0, released: 0, reads: 0 };
  await Effect.runPromise(Effect.gen(function* () {
    const allocated = yield* Deferred.make<void>(); const finish = yield* Deferred.make<void>();
    const layer = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.gen(function* () {
      // A gate exposes the otherwise-small final allocation/handoff window without unsafe hooks.
      state.acquired++; yield* Deferred.succeed(allocated, undefined); yield* Deferred.await(finish);
      state.openCompleted++;
      return { binding, read: (cursor: string | null) => Effect.sync(() => {
        state.reads++; return { body: { items: [], next_cursor: null }, encodedBytes: 30, binding, requestedCursor: cursor };
      }), release: Effect.sync(() => { state.released++; }) };
    })) });
    const work = yield* Effect.forkChild(traverseQuery(request()).pipe(Effect.provide(layer)));
    yield* Deferred.await(allocated);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(work));
    yield* Effect.yieldNow; yield* Deferred.succeed(finish, undefined); yield* Fiber.join(cancellation);
    const exit = yield* Fiber.await(work); assert.ok(Exit.hasInterrupts(exit));
    yield* Fiber.interrupt(work);
  }));
  assert.deepEqual(state, { acquired: 1, openCompleted: 1, released: 1, reads: 0 });
});
