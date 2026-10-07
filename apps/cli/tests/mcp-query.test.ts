import assert from "node:assert/strict";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import * as Exit from "effect/Exit";
import * as Cause from "effect/Cause";
import { QuerySource, ownQueryResource, traversalBounds as actualBounds, type QueryBinding, type QueryFailure } from "@healthmd/core-ts/candidate/query";
import type { QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import { mcpQuery, type TrustedMcpQueryHost, type ResolvedMcpCaller } from "../src/mcp/query.js";
import { cliQuery } from "../src/cli/query.js";
import { baseArgv } from "./cli-query-vectors.js";
import { toolCall, caller, binding, invocation, body, bodyText, success, allPagesArguments, receipt, receiptText, receiptResult,
  applicationErrors, methodNegatives, toolNegatives, normalizationNegatives, unavailableResult, protocolResult, expectedCounts, traversalBounds } from "./mcp-query-vectors.js";
function fake(options: { caller?: ResolvedMcpCaller; failure?: Effect.Effect<never, QueryFailure>; binding?: QueryBinding; encode?: Effect.Effect<string, unknown> } = {}) {
  const counts = { caller: 0, decoded: 0, admitted: 0, opened: 0, read: 0, released: 0, encoded: 0 };
  const seen: QueryInvocation[] = []; const encoded: unknown[] = []; const principal = options.caller ?? caller;
  const actualBinding: QueryBinding = options.binding ?? { ...binding, caller: principal.id, profile: principal.profile };
  const host: TrustedMcpQueryHost = {
    resolveCaller: Effect.sync(() => { counts.caller++; return principal; }),
    decodeArguments: (input) => Effect.sync(() => { counts.decoded++; return input; }),
    admit: (normalized, resolved) => Effect.sync(() => {
      counts.admitted++; seen.push(normalized); assert.deepEqual(resolved, principal);
      return { binding: actualBinding, deadlineMilliseconds: 1200000 };
    }),
    encodeResult: (value) => Effect.sync(() => { counts.encoded++; encoded.push(value); }).pipe(Effect.andThen(options.encode ?? Effect.sync(() => {
      // Literal trusted-codec fixtures, never candidate-derived expected bytes.
      if (seen[seen.length - 1]?.all_pages) { assert.deepEqual(value, receipt); return receiptText; }
      assert.deepEqual(value, body); return bodyText;
    }))),
  };
  const source = Layer.succeed(QuerySource)({ open: (request) => {
    counts.opened++; assert.deepEqual(request.binding, actualBinding); assert.deepEqual(request.grants, principal.grants);
    return ownQueryResource(Effect.succeed({ binding: actualBinding,
      read: (cursor) => Effect.sync(() => { counts.read++; }).pipe(Effect.andThen(options.failure ?? Effect.succeed({ body, encodedBytes: 64, binding: actualBinding, requestedCursor: cursor }))),
      release: Effect.sync(() => { counts.released++; }),
    }));
  } });
  return { counts, seen, encoded, host, source };
}
test("private MCP calls the same packed normalizer/owned traversal and exact fixed text envelope", async () => {
  const f = fake(); assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source))), success);
  assert.deepEqual(f.seen, [invocation]); assert.deepEqual(f.encoded, [body]); assert.deepEqual(f.counts, expectedCounts);
  assert.deepEqual(actualBounds, traversalBounds);
});
for (const method of methodNegatives) test(`private unsupported method precedes all host work: ${method}`, async () => {
  const f = fake(); assert.deepEqual(await Effect.runPromise(mcpQuery(method, toolCall, f.host).pipe(Effect.provide(f.source))), applicationErrors.method);
  assert.equal(Object.values(f.counts).every((count) => count === 0), true);
});
for (const name of toolNegatives) test(`guessed/unimplemented private tool precedes current principal and read scope: ${name}`, async () => {
  const f = fake({ caller: { ...caller, grants: [] } });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", { ...toolCall, name }, f.host).pipe(Effect.provide(f.source))), applicationErrors.unknown);
  assert.equal(Object.values(f.counts).every((count) => count === 0), true);
});
test("current profile allowlist denial precedes scope and argument decoding", async () => {
  const f = fake({ caller: { ...caller, allowedTools: [], grants: [] } });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source))), applicationErrors.unknown);
  assert.equal(f.counts.caller, 1); assert.equal(f.counts.decoded, 0); assert.equal(f.counts.opened, 0);
});
test("missing current read scope fails before decoding/admission/source", async () => {
  const f = fake({ caller: { ...caller, grants: [] } });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source))), applicationErrors.forbidden);
  assert.equal(f.counts.caller, 1); assert.equal(f.counts.decoded, 0); assert.equal(f.counts.admitted, 0); assert.equal(f.counts.opened, 0);
});
for (const [index, args] of normalizationNegatives.entries()) test(`invalid arguments fail before source: ${index}`, async () => {
  const f = fake(); assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", { ...toolCall, arguments: args }, f.host).pipe(Effect.provide(f.source))), applicationErrors.arguments);
  assert.equal(f.counts.decoded, 1); assert.equal(f.counts.admitted, 0); assert.equal(f.counts.opened, 0);
});
test("malformed parsed call/name and missing arguments follow scoped fixed source projections", async () => {
  for (const call of [null, [], {}, { name: 1 }, { name: null }]) {
    const f = fake(); assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", call, f.host).pipe(Effect.provide(f.source))), applicationErrors.unknown);
    assert.equal(f.counts.caller, 0);
  }
  const f = fake(); assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", { name: toolCall.name }, f.host).pipe(Effect.provide(f.source))), applicationErrors.arguments);
  assert.equal(f.counts.admitted, 0);
});
test("decoded envelope authority claims cannot replace current host caller/profile/grants/binding", async () => {
  for (const profile of ["local_direct", "local_read_only", "remote_read_only"] as const) {
    const f = fake({ caller: { ...caller, profile } });
    const call = { ...toolCall, caller: "synthetic_other", profile: "local_direct", grants: ["healthmd:export"], source: "synthetic_other", dataset: "synthetic_other" };
    assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", call, f.host).pipe(Effect.provide(f.source))), success);
    assert.deepEqual(f.counts, expectedCounts);
  }
});
test("admission binding mismatch cannot acquire under another caller or profile", async () => {
  for (const mismatch of [{ ...binding, caller: "synthetic_other" }, { ...binding, profile: "local_direct" as const }]) {
    const f = fake({ binding: mismatch }); const result = await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source)));
    assert.ok("result" in result); assert.equal(result.result.isError, true); assert.equal(f.counts.opened, 0);
    assert.equal(result.result.content[0]?.text.includes("healthmd_query_binding_mismatch"), true);
  }
});
test("lossless/all-pages flags preserve partial coverage and exact shared receipt projection", async () => {
  const f = fake(); const result = await Effect.runPromise(mcpQuery("tools/call", { ...toolCall, arguments: allPagesArguments }, f.host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, receiptResult); assert.deepEqual(f.encoded, [receipt]); assert.equal(f.seen[0]?.detail_level, "lossless");
  assert.equal(f.seen[0]?.all_pages, true); assert.deepEqual(f.counts, expectedCounts);
});
test("CLI and MCP normalize identical arguments and return the same common one-page/receipt values", async () => {
  for (const args of [toolCall.arguments, allPagesArguments]) {
    const f = fake(); const mcp = await Effect.runPromise(mcpQuery("tools/call", { ...toolCall, arguments: args }, f.host).pipe(Effect.provide(f.source)));
    assert.ok("result" in mcp);
    const cliSeen: QueryInvocation[] = [];
    const cli = await Effect.runPromise(cliQuery(baseArgv, {
      decodeArguments: () => Effect.succeed(args),
      admit: (normalized) => Effect.sync(() => { cliSeen.push(normalized); return { binding, grants: caller.grants }; }),
    }).pipe(Effect.provide(f.source)));
    assert.equal(cli.exitCode, 0); assert.deepEqual(cliSeen, f.seen.slice(0, 1));
    if (cli.exitCode === 0) assert.deepEqual(cli.value, f.encoded[0]);
  }
});
test("decoder failure/defect produces no provider cause or source acquisition", async () => {
  for (const failure of [Effect.fail("synthetic_decode_secret"), Effect.die("synthetic_decode_secret")]) {
    const f = fake(); const host: TrustedMcpQueryHost = { ...f.host, decodeArguments: () => failure };
    const result = await Effect.runPromise(mcpQuery("tools/call", toolCall, host).pipe(Effect.provide(f.source)));
    assert.deepEqual(result, applicationErrors.arguments); assert.equal(JSON.stringify(result).includes("synthetic_decode_secret"), false); assert.equal(f.counts.opened, 0);
  }
});
test("known unavailable error preserves code but uses private fixed content-free text", async () => {
  const f = fake({ failure: Effect.fail({ code: "healthmd_query_unavailable" }) });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source))), unavailableResult);
  assert.equal(f.counts.released, 1); assert.equal(f.counts.encoded, 0);
});
test("provider/host/encoder defect and oversized encoded result never escape raw causes", async () => {
  for (const encoding of [Effect.fail("synthetic_codec_secret"), Effect.die("synthetic_codec_secret"), Effect.succeed("x".repeat(traversalBounds.aggregateBytes + 1))]) {
    const f = fake({ encode: encoding });
    const result = await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source)));
    assert.deepEqual(result, protocolResult); assert.equal(f.counts.released, 1); assert.equal(JSON.stringify(result).includes("synthetic_codec_secret"), false);
  }
  const f = fake({ failure: Effect.die("synthetic_provider_secret") });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(f.source))), protocolResult);
  assert.equal(f.counts.released, 1);
  const admission = fake();
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, { ...admission.host, admit: () => Effect.die("synthetic_admission_secret") }).pipe(Effect.provide(admission.source))), protocolResult);
  assert.equal(admission.counts.opened, 0);
});
test("reused application diagnostics cannot be contaminated by a result recipient", async () => {
  const f = fake(); const result = await Effect.runPromise(mcpQuery("synthetic/guess", toolCall, f.host).pipe(Effect.provide(f.source)));
  assert.ok("error" in result); assert.throws(() => Object.assign(result.error, { message: "synthetic_mutation_secret" }), TypeError);
  assert.deepEqual(await Effect.runPromise(mcpQuery("synthetic/guess", toolCall, f.host).pipe(Effect.provide(f.source))), applicationErrors.method);
});
for (const defect of [false, true]) test(`MCP Fiber interruption awaits acknowledgment and strips mixed cleanup reasons: ${defect}`, async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const ack = yield* Deferred.make<void>();
    let released = 0; let complete = false; const f = fake();
    const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
      read: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)),
      release: Effect.gen(function* () { yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(ack); released++;
        if (defect) return yield* Effect.die("synthetic_cleanup_secret"); }),
    })) });
    const fiber = yield* Effect.forkChild(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(source)));
    yield* Deferred.await(entered); const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { complete = true; }))));
    yield* Deferred.await(releasing); assert.equal(released, 0); assert.equal(complete, false);
    yield* Deferred.succeed(ack, undefined); yield* Fiber.join(cancellation);
    const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.isFailure(exit)); assert.ok(Cause.hasInterruptsOnly(exit.cause));
    assert.equal(released, 1); assert.equal(complete, true); assert.equal(JSON.stringify(exit).includes("synthetic_cleanup_secret"), false);
  }));
});
test("pending interrupt at final masked allocation acquires1 reads0 releases1 after acknowledgment", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const allocated = yield* Deferred.make<void>(); const handoff = yield* Deferred.make<void>(); const releasing = yield* Deferred.make<void>(); const ack = yield* Deferred.make<void>();
    let acquired = 0; let reads = 0; let released = 0; let complete = false; const f = fake();
    const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.gen(function* () {
      acquired++; yield* Deferred.succeed(allocated, undefined); yield* Deferred.await(handoff);
      return { binding, read: (cursor: string | null) => Effect.sync(() => { reads++; return { body, encodedBytes: 64, binding, requestedCursor: cursor }; }),
        release: Deferred.succeed(releasing, undefined).pipe(Effect.andThen(Deferred.await(ack)), Effect.andThen(Effect.sync(() => { released++; }))), };
    })) });
    const fiber = yield* Effect.forkChild(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(source)));
    yield* Deferred.await(allocated); const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { complete = true; }))));
    yield* Effect.yieldNow; yield* Deferred.succeed(handoff, undefined); yield* Deferred.await(releasing);
    assert.equal(complete, false); assert.equal(released, 0);
    yield* Deferred.succeed(ack, undefined); yield* Fiber.join(cancellation);
    assert.equal(acquired, 1); assert.equal(reads, 0); assert.equal(released, 1); assert.equal(complete, true);
  }));
});
test("interrupted host admission cannot open a source", async () => {
  await Effect.runPromise(Effect.gen(function* () {
    const entered = yield* Deferred.make<void>(); const f = fake();
    const host: TrustedMcpQueryHost = { ...f.host, admit: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)) };
    const fiber = yield* Effect.forkChild(mcpQuery("tools/call", toolCall, host).pipe(Effect.provide(f.source)));
    yield* Deferred.await(entered); yield* Fiber.interrupt(fiber); assert.equal(f.counts.opened, 0);
  }));
});

test("provider error getters cannot execute inside the completed cause sanitizer", async () => {
  let accessed = false; const error = Object.defineProperty({}, "code", { get() { accessed = true; throw new Error("synthetic_getter_secret"); } });
  const f = fake(); const host: TrustedMcpQueryHost = { ...f.host, resolveCaller: Effect.fail(error) };
  const result = await Effect.runPromise(mcpQuery("tools/call", toolCall, host).pipe(Effect.provide(f.source)));
  assert.deepEqual(result, protocolResult); assert.equal(accessed, false);
});
test("invalid current host deadline fails common validation before source acquisition", async () => {
  const f = fake(); const host: TrustedMcpQueryHost = { ...f.host, admit: () => Effect.succeed({ binding, deadlineMilliseconds: 0 }) };
  const result = await Effect.runPromise(mcpQuery("tools/call", toolCall, host).pipe(Effect.provide(f.source)));
  assert.ok("result" in result); assert.equal(result.result.isError, true);
  assert.equal(result.result.content[0]?.text.includes("healthmd_invalid_arguments"), true); assert.equal(f.counts.opened, 0);
});
test("pure native-like release defect remains a fixed MCP protocol failure", async () => {
  const f = fake(); let released = 0;
  const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.succeed({ binding,
    read: (cursor) => Effect.succeed({ body, encodedBytes: 64, binding, requestedCursor: cursor }),
    release: Effect.sync(() => { released++; }).pipe(Effect.andThen(Effect.die("synthetic_release_secret"))),
  })) });
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", toolCall, f.host).pipe(Effect.provide(source))), protocolResult);
  assert.equal(released, 1); assert.equal(f.counts.encoded, 0);
});
