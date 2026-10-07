import assert from "node:assert/strict";
import { test } from "node:test";
import { createRequire } from "node:module";
import { realpath } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import * as Effect from "effect/Effect";
import * as Deferred from "effect/Deferred";
import * as Layer from "effect/Layer";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import * as Cause from "effect/Cause";
import { CandidateSession, CapabilityFailed, CapabilityUnavailable, type CapabilityFault, type CandidateResource } from "@healthmd/core-ts";
import { CandidateSession as HostSession } from "@healthmd/core-ts/host-interfaces";
import { cliCandidate, mcpCandidate, inspectHost, smokeCandidate, type CandidateOutcome } from "../src/candidate-host.js";
type Surface = () => Effect.Effect<{ readonly surface: string; readonly result: CandidateOutcome }, never, CandidateSession>;
const surfaces: readonly Surface[] = [cliCandidate, mcpCandidate];
const surfaceCases: readonly (readonly [string, Surface])[] = [["CLI", cliCandidate], ["MCP", mcpCandidate]];
function fake(inspect: Effect.Effect<"ready", CapabilityFault>) {
  const counts = { acquired: 0, inspected: 0, released: 0 };
  const resource: CandidateResource = {
    inspect: Effect.sync(() => { counts.inspected++; }).pipe(Effect.andThen(inspect)),
    release: Effect.sync(() => { counts.released++; }),
  };
  return { counts, layer: Layer.succeed(CandidateSession)({ acquire: Effect.sync(() => { counts.acquired++; return resource; }) }) };
}
test("packed core exports and adapter resolve one physical Effect module and service identity", async () => {
  const core = import.meta.resolve("@healthmd/core-ts");
  const effect = await realpath(fileURLToPath(import.meta.resolve("effect/Effect")));
  const fromCore = await realpath(createRequire(core).resolve("effect/Effect")); assert.equal(fromCore, effect);
  const namespace: typeof Effect = await import(pathToFileURL(fromCore).href); assert.equal(namespace, Effect);
  assert.equal(CandidateSession, HostSession);
});
test("thin CLI and MCP surfaces call one portable owned operation", async () => {
  const host = fake(Effect.succeed("ready"));
  const cli = await Effect.runPromise(cliCandidate().pipe(Effect.provide(host.layer)));
  const mcp = await Effect.runPromise(mcpCandidate().pipe(Effect.provide(host.layer)));
  assert.deepEqual(cli, { surface: "cli_candidate", result: { status: "ready" } });
  assert.deepEqual(mcp, { surface: "mcp_candidate", result: { status: "ready" } });
  assert.deepEqual(host.counts, { acquired: 2, inspected: 2, released: 2 });
});
test("typed inspection failures produce only fixed content-free candidate outcomes", async () => {
  for (const surface of surfaces) {
    const host = fake(Effect.fail(new CapabilityFailed()));
    const result = await Effect.runPromise(surface().pipe(Effect.provide(host.layer)));
    assert.deepEqual(result.result, { status: "failed", code: "capability_failed" });
    assert.deepEqual(host.counts, { acquired: 1, inspected: 1, released: 1 });
  }
});
test("unavailable acquisition never fabricates readiness or releases an unowned resource", async () => {
  const host = Layer.succeed(CandidateSession)({ acquire: Effect.fail(new CapabilityUnavailable()) });
  assert.deepEqual(await Effect.runPromise(inspectHost.pipe(Effect.provide(host))), { status: "failed", code: "capability_unavailable" });
});
test("unexpected provider defects are sanitized after owned cleanup", async () => {
  const host = fake(Effect.die(new Error("synthetic_provider_secret")));
  const result = await Effect.runPromise(cliCandidate().pipe(Effect.provide(host.layer)));
  assert.deepEqual(result, { surface: "cli_candidate", result: { status: "failed", code: "capability_failed" } });
  assert.equal(JSON.stringify(result).includes("synthetic_provider_secret"), false);
  assert.deepEqual(host.counts, { acquired: 1, inspected: 1, released: 1 });
});
test("release defects cannot escape as provider payloads or successful readiness", async () => {
  let released = 0;
  const host = Layer.succeed(CandidateSession)({ acquire: Effect.succeed({ inspect: Effect.succeed("ready" as const), release: Effect.sync(() => { released++; }).pipe(Effect.andThen(Effect.die("synthetic_cleanup_secret"))) }) });
  assert.deepEqual(await Effect.runPromise(mcpCandidate().pipe(Effect.provide(host))), { surface: "mcp_candidate", result: { status: "failed", code: "capability_failed" } });
  assert.equal(released, 1);
});
for (const [label, surface] of surfaceCases) test(`${label} interruption remains interruption and waits asynchronous cleanup acknowledgment`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const inspected = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const acknowledge = yield* Deferred.make<void>();
    let released = 0; let finished = false;
    const host = Layer.succeed(CandidateSession)({ acquire: Effect.succeed({
      inspect: Deferred.succeed(inspected, undefined).pipe(Effect.andThen(Effect.never)),
      release: Deferred.succeed(releasing, undefined).pipe(Effect.andThen(Deferred.await(acknowledge)), Effect.andThen(Effect.sync(() => { released++; }))),
    }) });
    const fiber = yield* Effect.forkChild(surface().pipe(Effect.provide(host)));
    yield* Deferred.await(inspected);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { finished = true; }))));
    yield* Deferred.await(releasing); assert.equal(finished, false); assert.equal(released, 0);
    yield* Deferred.succeed(acknowledge, undefined); yield* Fiber.join(cancellation); yield* Fiber.interrupt(fiber);
    const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.hasInterrupts(exit)); assert.equal(released, 1); assert.equal(finished, true);
  }));
});
test("concurrent thin surfaces retain independent resource ownership", async () => {
  const first = fake(Effect.succeed("ready")); const second = fake(Effect.fail(new CapabilityFailed()));
  const results = await Promise.all([Effect.runPromise(cliCandidate().pipe(Effect.provide(first.layer))), Effect.runPromise(mcpCandidate().pipe(Effect.provide(second.layer)))]);
  assert.equal(results[0]?.result.status, "ready"); assert.equal(results[1]?.result.status, "failed");
  assert.deepEqual(first.counts, { acquired: 1, inspected: 1, released: 1 }); assert.deepEqual(second.counts, first.counts);
});
test("explicit development smoke supplies fake capabilities only", async () => {
  assert.deepEqual(await smokeCandidate(), { cli: { surface: "cli_candidate", result: { status: "ready" } }, mcp: { surface: "mcp_candidate", result: { status: "ready" } }, counts: { acquired: 2, released: 2 } });
});

for (const [label, surface] of surfaceCases) test(`${label} mixed interruption and cleanup defect preserves only sanitized interruption`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const inspected = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const acknowledge = yield* Deferred.make<void>();
    let released = 0;
    const host = Layer.succeed(CandidateSession)({ acquire: Effect.succeed({
      inspect: Deferred.succeed(inspected, undefined).pipe(Effect.andThen(Effect.never)),
      release: Effect.gen(function* () {
        yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(acknowledge);
        released++; return yield* Effect.die(new Error("synthetic_cleanup_secret_mixed_cause"));
      }),
    }) });
    const fiber = yield* Effect.forkChild(surface().pipe(Effect.provide(host)));
    yield* Deferred.await(inspected); const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber));
    yield* Deferred.await(releasing); assert.equal(released, 0);
    yield* Deferred.succeed(acknowledge, undefined); yield* Fiber.join(cancellation);
    const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.isFailure(exit));
    assert.ok(Cause.hasInterruptsOnly(exit.cause)); assert.equal(released, 1);
    assert.equal(JSON.stringify(exit).includes("synthetic_cleanup_secret_mixed_cause"), false);
  }));
});
