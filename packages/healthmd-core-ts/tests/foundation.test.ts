import assert from "node:assert/strict";
import { test } from "node:test";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import { TestClock } from "effect/testing";
import { CandidateSession, inspectCandidate, CapabilityFailed, CapabilityUnavailable } from "@healthmd/core-ts";
import { CandidateSession as HostSession } from "@healthmd/core-ts/host-interfaces";
import type { CandidateResource, CapabilityFault } from "@healthmd/core-ts";

function fake(inspect: Effect.Effect<"ready", CapabilityFault>) {
  const counts = { acquired: 0, released: 0 };
  const resource: CandidateResource = {
    inspect,
    release: Effect.sync(() => { counts.released += 1; }),
  };
  const layer = Layer.succeed(CandidateSession)({
    acquire: Effect.sync(() => { counts.acquired += 1; return resource; }),
  });
  return { counts, layer };
}

test("candidate and host-interface exports share the same service identity", () => {
  assert.equal(CandidateSession, HostSession);
});

test("successful scoped inspection releases its owned resource exactly once", async () => {
  const host = fake(Effect.succeed("ready"));
  assert.equal(await Effect.runPromise(inspectCandidate.pipe(Effect.provide(host.layer))), "ready");
  assert.deepEqual(host.counts, { acquired: 1, released: 1 });
});

test("typed inspection failure releases once and exposes only a stable safe failure", async () => {
  const host = fake(Effect.fail(new CapabilityFailed()));
  const result = await Effect.runPromise(inspectCandidate.pipe(
    Effect.provide(host.layer),
    Effect.catchTag("CapabilityFailed", (failure) => Effect.succeed({ code: failure.code, message: failure.message })),
  ));
  assert.deepEqual(result, { code: "capability_failed", message: "Candidate capability failed" });
  assert.deepEqual(host.counts, { acquired: 1, released: 1 });
});

test("acquisition failure never inspects or releases an unacquired resource", async () => {
  const layer = Layer.succeed(CandidateSession)({ acquire: Effect.fail(new CapabilityUnavailable()) });
  const code = await Effect.runPromise(inspectCandidate.pipe(
    Effect.provide(layer),
    Effect.catchTag("CapabilityUnavailable", (failure) => Effect.succeed(failure.code)),
  ));
  assert.equal(code, "capability_unavailable");
});

test("interruption waits for finalization and releases exactly once", async () => {
  const counts = await Effect.runPromise(Effect.gen(function* () {
    const started = yield* Deferred.make<void>();
    const host = fake(Effect.gen(function* () {
      yield* Deferred.succeed(started, undefined);
      return yield* Effect.never;
    }));
    const fiber = yield* Effect.forkChild(inspectCandidate.pipe(Effect.provide(host.layer)));
    yield* Deferred.await(started);
    yield* Fiber.interrupt(fiber);
    yield* Fiber.interrupt(fiber);
    const exit = yield* Effect.exit(Fiber.join(fiber));
    assert.ok(Exit.hasInterrupts(exit));
    return host.counts;
  }));
  assert.deepEqual(counts, { acquired: 1, released: 1 });
});

test("virtual clock drives inspection without wall-clock delays", async () => {
  const host = fake(Effect.sleep("1 hour").pipe(Effect.as("ready" as const)));
  const value = await Effect.runPromise(Effect.gen(function* () {
    const fiber = yield* Effect.forkChild(inspectCandidate.pipe(Effect.provide(host.layer)));
    yield* TestClock.adjust("1 hour");
    return yield* Fiber.join(fiber);
  }).pipe(Effect.provide(TestClock.layer())));
  assert.equal(value, "ready");
  assert.deepEqual(host.counts, { acquired: 1, released: 1 });
});

test("interruption cannot finish before an asynchronous finalizer acknowledges cleanup", async () => {
  const released = await Effect.runPromise(Effect.gen(function* () {
    const inspected = yield* Deferred.make<void>();
    const releasing = yield* Deferred.make<void>();
    const acknowledged = yield* Deferred.make<void>();
    let completed = false;
    const layer = Layer.succeed(CandidateSession)({
      acquire: Effect.succeed({
        inspect: Effect.gen(function* () {
          yield* Deferred.succeed(inspected, undefined);
          return yield* Effect.never;
        }),
        release: Effect.gen(function* () {
          yield* Deferred.succeed(releasing, undefined);
          yield* Deferred.await(acknowledged);
          completed = true;
        }),
      }),
    });
    const operation = yield* Effect.forkChild(inspectCandidate.pipe(Effect.provide(layer)));
    yield* Deferred.await(inspected);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(operation));
    yield* Deferred.await(releasing);
    assert.equal(completed, false);
    yield* Deferred.succeed(acknowledged, undefined);
    yield* Fiber.join(cancellation);
    return completed;
  }));
  assert.equal(released, true);
});

test("concurrent operations keep fake host resource ownership separate", async () => {
  const first = fake(Effect.succeed("ready"));
  const second = fake(Effect.fail(new CapabilityFailed()));
  const results = await Promise.all([
    Effect.runPromiseExit(inspectCandidate.pipe(Effect.provide(first.layer))),
    Effect.runPromiseExit(inspectCandidate.pipe(Effect.provide(second.layer))),
  ]);
  assert.ok(Exit.isSuccess(results[0]!));
  assert.ok(Exit.isFailure(results[1]!));
  assert.deepEqual(first.counts, { acquired: 1, released: 1 });
  assert.deepEqual(second.counts, { acquired: 1, released: 1 });
});
