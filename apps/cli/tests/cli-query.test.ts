import assert from "node:assert/strict";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import * as Cause from "effect/Cause";
import { QuerySource, ownQueryResource, type QueryBody, type QueryBinding, type QueryFailure } from "@healthmd/core-ts/candidate/query";
import type { QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import { cliQuery, type TrustedCliQueryHost } from "../src/cli/query.js";
import { argvVectors, parseNegatives, timeoutNegatives, baseArgv, decodedArguments, expectedInvocation, trustedAdmission, losslessArguments,
  singleBody, singleStdout, receiptValue, receiptStdout, expectedErrors, unsafePresentations, expectedCounts } from "./cli-query-vectors.js";
function fake(options: { args?: unknown; binding?: QueryBinding; grants?: readonly string[]; body?: QueryBody; failure?: Effect.Effect<never, QueryFailure> } = {}) {
  const counts = { admitted: 0, opened: 0, read: 0, released: 0 }; let decoded = 0;
  const seen: Array<{ invocation: QueryInvocation; timeoutSeconds: number }> = [];
  const binding: QueryBinding = options.binding ?? trustedAdmission.binding;
  const host: TrustedCliQueryHost = {
    decodeArguments: () => Effect.sync(() => { decoded++; return options.args ?? decodedArguments; }),
    admit: (invocation, timeoutSeconds) => Effect.sync(() => { counts.admitted++; seen.push({ invocation, timeoutSeconds }); return { binding, grants: options.grants ?? trustedAdmission.grants }; }),
  };
  const source = Layer.succeed(QuerySource)({ open: (request) => {
    counts.opened++;
    assert.deepEqual(request.binding, binding); assert.deepEqual(request.grants, options.grants ?? trustedAdmission.grants);
    return ownQueryResource(Effect.succeed({ binding,
      read: (cursor) => Effect.sync(() => { counts.read++; }).pipe(Effect.andThen(options.failure ?? Effect.succeed({ body: options.body ?? singleBody, encodedBytes: 64, binding, requestedCursor: cursor }))),
      release: Effect.sync(() => { counts.released++; }),
    }));
  } });
  return { counts, seen, host, source, decoded: () => decoded };
}
for (const vector of argvVectors) test(`private CLI query argv/source normalization: ${vector.case_id}`, async () => {
  const f = fake(); const result = await Effect.runPromise(cliQuery(vector.argv, f.host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, { exitCode: 0, value: singleBody, stdout: singleStdout });
  assert.deepEqual(f.seen, [{ invocation: expectedInvocation, timeoutSeconds: vector.timeoutSeconds }]);
  assert.deepEqual(f.counts, expectedCounts); assert.equal(f.decoded(), 1);
});
for (const vector of parseNegatives) test(`private CLI syntax rejects before decoding or authority: ${vector.case_id}`, async () => {
  const f = fake(); const result = await Effect.runPromise(cliQuery(vector.argv, f.host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, expectedErrors.parse); assert.equal(f.decoded(), 0);
  assert.deepEqual(f.counts, { admitted: 0, opened: 0, read: 0, released: 0 });
});
for (const timeout of timeoutNegatives) test(`semantic timeout bound ${timeout} rejects before host admission`, async () => {
  const f = fake(); assert.deepEqual(await Effect.runPromise(cliQuery([...baseArgv, "--timeout", timeout], f.host).pipe(Effect.provide(f.source))), expectedErrors.timeout);
  assert.equal(f.decoded(), 0); assert.equal(f.counts.admitted, 0);
});
test("trusted decoder failure/defect/nonobject remains fixed and never contacts query source", async () => {
  for (const decoding of [Effect.fail("synthetic_decode_secret"), Effect.die("synthetic_decode_secret"), Effect.succeed([]), Effect.succeed(null)]) {
    const f = fake(); const host: TrustedCliQueryHost = { ...f.host, decodeArguments: () => decoding };
    const result = await Effect.runPromise(cliQuery(baseArgv, host).pipe(Effect.provide(f.source)));
    assert.deepEqual(result, expectedErrors.decode); assert.equal(JSON.stringify(result).includes("synthetic_decode_secret"), false);
    assert.equal(f.counts.admitted, 0); assert.equal(f.counts.opened, 0);
  }
});
test("shared normalizer rejects attempted envelope authority before host admission", async () => {
  const f = fake({ args: { ...decodedArguments, request_id: "synthetic_private_request" } });
  assert.deepEqual(await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source))), expectedErrors.normalize);
  assert.equal(f.counts.admitted, 0); assert.equal(f.counts.opened, 0);
});
test("lossless/all-pages options remain JSON normalization and literal receipt preserves partial coverage", async () => {
  const f = fake({ args: losslessArguments });
  const result = await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, { exitCode: 0, value: receiptValue, stdout: receiptStdout });
  assert.equal(f.seen[0]?.invocation.detail_level, "lossless"); assert.equal(f.seen[0]?.invocation.all_pages, true);
  assert.deepEqual(f.counts, expectedCounts);
  // Byte accounting is trusted synthetic64; transport complete is not complete health coverage.
});
test("host-attested read-only caller/source/dataset/profile survives without argv-created grants", async () => {
  for (const profile of ["local_read_only", "remote_read_only"] as const) {
    const binding = { ...trustedAdmission.binding, profile, caller: "synthetic-another-owner", source: "synthetic-another-source", dataset: "synthetic-another-dataset" };
    const f = fake({ binding }); assert.equal((await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source)))).exitCode, 0);
    assert.deepEqual(f.counts, expectedCounts);
  }
  const denied = fake({ grants: [] });
  assert.deepEqual(await Effect.runPromise(cliQuery(baseArgv, denied.host).pipe(Effect.provide(denied.source))), expectedErrors.query);
  assert.equal(denied.counts.admitted, 1); assert.equal(denied.counts.opened, 0);
});
test("host admission/provider defects and source typed failures are content-free CLI errors", async () => {
  for (const failure of [Effect.fail({ code: "healthmd_query_unavailable" as const }), Effect.die("synthetic_provider_secret")]) {
    const f = fake({ failure });
    const result = await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source)));
    assert.deepEqual(result, expectedErrors.query); assert.deepEqual(f.counts, expectedCounts); assert.equal(JSON.stringify(result).includes("synthetic_provider_secret"), false);
  }
  const f = fake(); const host: TrustedCliQueryHost = { ...f.host, admit: () => Effect.die("synthetic_admission_secret") };
  const result = await Effect.runPromise(cliQuery(baseArgv, host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, expectedErrors.query); assert.equal(f.counts.opened, 0); assert.equal(JSON.stringify(result).includes("synthetic_admission_secret"), false);
});
for (const [index, body] of unsafePresentations.entries()) test(`unsupported presentation does not round or fabricate general raw bytes: ${index}`, async () => {
  const f = fake({ body }); assert.deepEqual(await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source))), expectedErrors.presentation);
  assert.deepEqual(f.counts, expectedCounts);
});
for (const cleanupDefect of [false, true]) test(`Fiber cancellation waits native-like cleanup acknowledgment and sanitizes mixed cause: ${cleanupDefect}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const ack = yield* Deferred.make<void>();
    let released = 0; let complete = false;
    const f = fake();
    const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding: trustedAdmission.binding,
      read: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)),
      release: Effect.gen(function* () { yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(ack); released++;
        if (cleanupDefect) return yield* Effect.die(new Error("synthetic_query_cleanup_secret"));
      }),
    })) });
    const fiber = yield* Effect.forkChild(cliQuery(baseArgv, f.host).pipe(Effect.provide(source)));
    yield* Deferred.await(entered);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { complete = true; }))));
    yield* Deferred.await(releasing); assert.equal(released, 0); assert.equal(complete, false);
    yield* Deferred.succeed(ack, undefined); yield* Fiber.join(cancellation);
    const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.isFailure(exit));
    assert.ok(Cause.hasInterruptsOnly(exit.cause)); assert.equal(released, 1); assert.equal(complete, true);
    assert.equal(JSON.stringify(exit).includes("synthetic_query_cleanup_secret"), false);
  }));
});
test("cancellation during trusted admission cannot acquire a query resource", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); const f = fake();
    const host: TrustedCliQueryHost = { ...f.host, admit: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)) };
    const fiber = yield* Effect.forkChild(cliQuery(baseArgv, host).pipe(Effect.provide(f.source)));
    yield* Deferred.await(entered); yield* Fiber.interrupt(fiber); assert.equal(f.counts.opened, 0);
  }));
});

// Supplemental candidate presentation guard: JS integer-index enumeration is not serde key ordering.
test("numeric object keys fail the restricted presenter instead of claiming canonical ordering", async () => {
  const f = fake({ body: { "10": 1, "2": 2 } });
  assert.deepEqual(await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(f.source))), expectedErrors.presentation);
  assert.deepEqual(f.counts, expectedCounts);
});
test("pure cleanup defect is a fixed query error after owned finalization", async () => {
  let released = 0; const f = fake();
  const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding: trustedAdmission.binding,
    read: (cursor) => Effect.succeed({ body: singleBody, encodedBytes: 64, binding: trustedAdmission.binding, requestedCursor: cursor }),
    release: Effect.sync(() => { released++; }).pipe(Effect.andThen(Effect.die("synthetic_release_secret"))),
  })) });
  const result = await Effect.runPromise(cliQuery(baseArgv, f.host).pipe(Effect.provide(source)));
  assert.deepEqual(result, expectedErrors.query); assert.equal(released, 1);
  assert.equal(JSON.stringify(result).includes("synthetic_release_secret"), false);
});
test("pending interruption at final allocation preserves atomic shared ownership cleanup", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const allocated = yield* Deferred.make<void>(); const handoff = yield* Deferred.make<void>();
    const releasing = yield* Deferred.make<void>(); const ack = yield* Deferred.make<void>();
    let acquired = 0; let read = 0; let released = 0; let cancelled = false; const f = fake();
    const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.gen(function* () {
      acquired++; yield* Deferred.succeed(allocated, undefined); yield* Deferred.await(handoff);
      return { binding: trustedAdmission.binding,
        read: (cursor: string | null) => Effect.sync(() => { read++; return { body: singleBody, encodedBytes: 64, binding: trustedAdmission.binding, requestedCursor: cursor }; }),
        release: Deferred.succeed(releasing, undefined).pipe(Effect.andThen(Deferred.await(ack)), Effect.andThen(Effect.sync(() => { released++; }))),
      };
    })) });
    const fiber = yield* Effect.forkChild(cliQuery(baseArgv, f.host).pipe(Effect.provide(source)));
    yield* Deferred.await(allocated);
    const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { cancelled = true; }))));
    yield* Effect.yieldNow; yield* Deferred.succeed(handoff, undefined); yield* Deferred.await(releasing);
    assert.equal(cancelled, false); assert.equal(released, 0); assert.equal(acquired, 1);
    yield* Deferred.succeed(ack, undefined); yield* Fiber.join(cancellation);
    const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.hasInterrupts(exit));
    assert.equal(read, 0); assert.equal(released, 1); assert.equal(cancelled, true);
  }));
});

test("returned failures cannot contaminate later content-free diagnostics", async () => {
  const f = fake(); const result = await Effect.runPromise(cliQuery(["query", "synthetic-operation"], f.host).pipe(Effect.provide(f.source)));
  assert.ok(result.exitCode !== 0);
  assert.throws(() => Object.assign(result.error, { message: "synthetic_mutation_secret" }), TypeError);
  assert.deepEqual(await Effect.runPromise(cliQuery(["query", "synthetic-operation"], f.host).pipe(Effect.provide(f.source))), expectedErrors.parse);
});
