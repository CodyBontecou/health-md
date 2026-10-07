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
import * as Cause from "effect/Cause";
import { createStaticCatalog, type CatalogTool, type SurfaceProfile } from "@healthmd/core-ts/candidate/catalog";
import { normalizeDiscovery, type QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import { QuerySource, ownQueryResource, traversalBounds, type QueryBinding, type QueryFailure, type TraversalRequest } from "@healthmd/core-ts/candidate/query";
import { cliQuery, type TrustedCliQueryHost, type CliQueryOutcome } from "../src/cli/query.js";
import { mcpQuery, type TrustedMcpQueryHost, type McpQueryOutcome } from "../src/mcp/query.js";
import { unavailableResult } from "./mcp-query-vectors.js";
import { binding, grants, profiles, flowVectors, bounds, fullIds, readOnlyIds, localOnlyIds, catalogSha, availability,
  otherAvailability, lifecycleVectors, errorExpectations } from "./shared-slice-parity-vectors.js";

type Flow = typeof flowVectors[number];
type Surface = "cli" | "mcp";
const surfaces: readonly Surface[] = ["cli", "mcp"];

function fixture(row: Flow, profile: SurfaceProfile, options: {
  grants?: readonly string[]; binding?: QueryBinding; readFailure?: Effect.Effect<never, QueryFailure>;
} = {}) {
  const currentGrants = options.grants ?? grants;
  const actualBinding: QueryBinding = options.binding ?? { ...binding, profile };
  const counts = { decoded: 0, admitted: 0, opened: 0, read: 0, released: 0 };
  const hostCounts = { resolved: 0, encoded: 0 };
  const commands: QueryInvocation[] = [];
  const requests: TraversalRequest[] = [];
  const trace: string[] = [];
  const encoded: unknown[] = [];
  const cliHost: TrustedCliQueryHost = {
    decodeArguments: (text) => Effect.sync(() => { assert.equal(text, row.argv[3]); counts.decoded++; return row.arguments; }),
    admit: (invocation, timeoutSeconds) => Effect.sync(() => {
      assert.equal(timeoutSeconds * 1000, row.deadlineMilliseconds); counts.admitted++; commands.push(invocation);
      return { binding: actualBinding, grants: currentGrants };
    }),
  };
  const mcpHost: TrustedMcpQueryHost = {
    resolveCaller: Effect.sync(() => { hostCounts.resolved++; return { id: binding.caller, profile, grants: currentGrants, allowedTools: ["healthmd_metric_chart"] }; }),
    decodeArguments: (input) => Effect.sync(() => { assert.deepEqual(input, row.arguments); counts.decoded++; return input; }),
    admit: (invocation, caller) => Effect.sync(() => {
      assert.equal(caller.id, binding.caller); assert.equal(caller.profile, profile); assert.deepEqual(caller.grants, currentGrants);
      counts.admitted++; commands.push(invocation); return { binding: actualBinding, deadlineMilliseconds: row.deadlineMilliseconds };
    }),
    encodeResult: (value) => Effect.sync(() => {
      hostCounts.encoded++; encoded.push(value); assert.deepEqual(value, row.value); return row.mcpText;
    }),
  };
  const source = Layer.succeed(QuerySource)({ open: (request) => {
    requests.push(request); trace.push("open"); counts.opened++;
    return ownQueryResource(Effect.succeed({ binding: actualBinding,
      read: (cursor) => Effect.sync(() => {
        const index = counts.read++; trace.push("read:" + (cursor ?? "null"));
        assert.equal(cursor, row.cursors[index]);
        const body = row.pages[index]; const encodedBytes = row.encodedBytes[index];
        assert.notEqual(body, undefined); assert.notEqual(encodedBytes, undefined);
        return { body: body!, encodedBytes: encodedBytes!, binding: actualBinding, requestedCursor: cursor };
      }).pipe(Effect.flatMap((page) => options.readFailure ?? Effect.succeed(page))),
      release: Effect.sync(() => { counts.released++; trace.push("release"); }),
    }));
  } });
  return { counts, hostCounts, commands, requests, trace, encoded, cliHost, mcpHost, source, actualBinding, currentGrants };
}
function invoke(surface: Surface, row: Flow, f: ReturnType<typeof fixture>): Effect.Effect<CliQueryOutcome | McpQueryOutcome, never, QuerySource> {
  return surface === "cli" ? cliQuery(row.argv, f.cliHost)
    : mcpQuery("tools/call", { name: "healthmd_metric_chart", arguments: row.arguments }, f.mcpHost);
}

for (const profile of profiles) for (const row of flowVectors) test(`shared slice actual command/source/pagination: ${profile}/${row.case_id}`, async () => {
  assert.deepEqual(traversalBounds, bounds);
  const observed = [];
  for (const surface of surfaces) {
    const f = fixture(row, profile);
    const outcome = await Effect.runPromise(invoke(surface, row, f).pipe(Effect.provide(f.source)));
    if ("exitCode" in outcome) {
      assert.equal(outcome.exitCode, 0); assert.ok(outcome.exitCode === 0);
      assert.deepEqual(outcome.value, row.value); assert.equal(outcome.stdout, row.cliText);
    } else {
      assert.deepEqual(outcome, { result: { content: [{ type: "text", text: row.mcpText }], isError: false } });
      assert.deepEqual(f.encoded, [row.value]);
    }
    assert.deepEqual(f.commands, [row.invocation]);
    assert.deepEqual(f.requests, [{ invocation: row.invocation, binding: { ...binding, profile }, grants,
      deadlineMilliseconds: row.deadlineMilliseconds }]);
    assert.deepEqual(f.counts, row.counts); assert.deepEqual(f.trace, row.commonTrace);
    assert.deepEqual(f.hostCounts, { resolved: surface === "mcp" ? 1 : 0, encoded: surface === "mcp" ? 1 : 0 });
    observed.push({ commands: f.commands, requests: f.requests, counts: f.counts, trace: f.trace });
  }
  assert.deepEqual(observed[0], observed[1]);
  assert.notEqual(row.cliText, row.mcpText); // Common values agree; adapter text formats intentionally differ.
});

for (const profile of profiles) test(`pure common discovery has no query capability work: ${profile}`, async () => {
  const bytes = await readFile(new URL("../../crates/healthmd-mcp/assets/mcp-tools-v1.json", import.meta.url));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), catalogSha);
  // This is the hash-attested static catalog only, never arbitrary query-byte decoding.
  const mirror: CatalogTool[] = JSON.parse(bytes.toString("utf8"));
  const admitted = createStaticCatalog(mirror); assert.ok(Result.isSuccess(admitted));
  const catalog = admitted.success; const f = fixture(flowVectors[0], profile);
  const discovery = await Effect.runPromise(Effect.sync(() => normalizeDiscovery(catalog, profile)).pipe(Effect.provide(f.source)));
  assert.ok(Result.isSuccess(discovery));
  const listed = catalog.list(profile); assert.ok(Result.isSuccess(listed));
  assert.deepEqual(listed.success.map((tool) => tool.name), profile === "local_direct" ? fullIds : readOnlyIds);
  for (const name of fullIds) {
    const state = catalog.availability(name); assert.ok(Result.isSuccess(state));
    assert.deepEqual(state.success, name === "healthmd_metric_chart" ? availability : otherAvailability);
  }
  if (profile !== "local_direct") for (const name of localOnlyIds) assert.ok(Result.isFailure(normalizeDiscovery(catalog, profile, name)));
  assert.deepEqual(f.counts, { decoded: 0, admitted: 0, opened: 0, read: 0, released: 0 });
  assert.deepEqual(f.hostCounts, { resolved: 0, encoded: 0 }); assert.deepEqual(f.requests, []);
  // Pure Result API accepts only the reviewed mirror/profile: no secret/network/listener capabilities.
  // Public CLI/MCP discovery routes remain unimplemented; portable import guards supply host-API evidence.
});

test("current grants deny both adapters before acquisition despite tool JSON authority claims", async () => {
  const row = flowVectors[0]; const cli = fixture(row, "local_read_only", { grants: [] });
  assert.deepEqual(await Effect.runPromise(invoke("cli", row, cli).pipe(Effect.provide(cli.source))), errorExpectations.cli);
  assert.deepEqual(cli.counts, { decoded: 1, admitted: 1, opened: 0, read: 0, released: 0 });
  const mcp = fixture(row, "local_read_only", { grants: [] });
  const call = { name: "healthmd_metric_chart", arguments: row.arguments, grants, caller: binding.caller, profile: "local_direct", source: binding.source };
  assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", call, mcp.mcpHost).pipe(Effect.provide(mcp.source))), errorExpectations.mcpDenied);
  assert.deepEqual(mcp.counts, { decoded: 0, admitted: 0, opened: 0, read: 0, released: 0 });
  assert.equal(mcp.hostCounts.resolved, 1);
});

test("invalid admitted profile and MCP caller mismatch cannot open a source", async () => {
  const row = flowVectors[0]; const invalid: QueryBinding = { ...binding };
  Reflect.set(invalid, "profile", "synthetic_invalid_profile"); // Malformed trusted adapter fixture, no type cast.
  for (const surface of surfaces) {
    const f = fixture(row, "local_read_only", { binding: invalid });
    const result = await Effect.runPromise(invoke(surface, row, f).pipe(Effect.provide(f.source)));
    if ("exitCode" in result) assert.deepEqual(result, errorExpectations.cli);
    else { assert.ok("result" in result); assert.equal(result.result.isError, true); }
    assert.equal(f.counts.opened, 0); assert.equal(f.counts.released, 0);
  }
  const f = fixture(row, "local_read_only", { binding: { ...binding, caller: "synthetic-other-owner" } });
  const result = await Effect.runPromise(invoke("mcp", row, f).pipe(Effect.provide(f.source)));
  assert.ok("result" in result); assert.equal(result.result.isError, true); assert.equal(f.counts.opened, 0);
});

for (const profile of ["local_read_only", "remote_read_only"] as const) test(`guessed local tools cannot dispatch in private read profile: ${profile}`, async () => {
  for (const name of localOnlyIds) {
    const f = fixture(flowVectors[0], profile);
    assert.deepEqual(await Effect.runPromise(mcpQuery("tools/call", { name, arguments: {} }, f.mcpHost).pipe(Effect.provide(f.source))), errorExpectations.mcpUnknown);
    assert.equal(f.hostCounts.resolved, 0); assert.equal(f.counts.decoded, 0); assert.equal(f.counts.opened, 0);
  }
});

for (const defect of [false, true]) test(`both adapters sanitize failures after once-only source release: ${defect}`, async () => {
  for (const surface of surfaces) {
    const failure = defect ? Effect.die("synthetic-parity-provider-secret") : Effect.fail({ code: "healthmd_query_unavailable" as const });
    const f = fixture(flowVectors[0], "local_read_only", { readFailure: failure });
    const result = await Effect.runPromise(invoke(surface, flowVectors[0], f).pipe(Effect.provide(f.source)));
    assert.deepEqual(result, surface === "cli" ? errorExpectations.cli : defect ? errorExpectations.mcpProtocol : unavailableResult);
    assert.equal(f.counts.opened, 1); assert.equal(f.counts.read, 1); assert.equal(f.counts.released, 1);
    assert.equal(f.hostCounts.encoded, 0); assert.equal(JSON.stringify(result).includes("synthetic-parity-provider-secret"), false);
  }
});

for (const vector of lifecycleVectors) test(`cross-adapter actual interruption/ownership barrier: ${vector.case_id}`, async () => {
  const observations = [];
  for (const surface of surfaces) {
    const observed = await Effect.runPromise(Effect.gen(function* () {
      const entered = yield* Deferred.make<void>(); const handoff = yield* Deferred.make<void>();
      const releasing = yield* Deferred.make<void>(); const ack = yield* Deferred.make<void>();
      let acquired = 0; let reads = 0; let released = 0; let completed = false;
      const row = flowVectors[0]; const f = fixture(row, "local_read_only");
      const source = Layer.succeed(QuerySource)({ open: () => ownQueryResource(Effect.gen(function* () {
        acquired++;
        if (vector.phase === "allocation") { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(handoff); }
        return { binding,
          read: (cursor: string | null) => Effect.gen(function* () {
            reads++;
            if (vector.phase === "read") { yield* Deferred.succeed(entered, undefined); return yield* Effect.never; }
            return { body: row.pages[0], encodedBytes: row.encodedBytes[0], binding, requestedCursor: cursor };
          }),
          release: Effect.gen(function* () {
            yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(ack); released++;
            if (vector.cleanupDefect) return yield* Effect.die("synthetic-parity-cleanup-secret");
          }),
        };
      })) });
      const operation: Effect.Effect<CliQueryOutcome | McpQueryOutcome, never, QuerySource> = vector.phase === "admission"
        ? surface === "cli"
          ? cliQuery(row.argv, { ...f.cliHost, admit: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)) })
          : mcpQuery("tools/call", { name: "healthmd_metric_chart", arguments: row.arguments }, { ...f.mcpHost, admit: () => Deferred.succeed(entered, undefined).pipe(Effect.andThen(Effect.never)) })
        : invoke(surface, row, f);
      const fiber = yield* Effect.forkChild(operation.pipe(Effect.provide(source)));
      yield* Deferred.await(entered);
      const cancellation = yield* Effect.forkChild(Fiber.interrupt(fiber).pipe(Effect.tap(() => Effect.sync(() => { completed = true; }))));
      if (vector.phase !== "admission") {
        if (vector.phase === "allocation") { yield* Effect.yieldNow; yield* Deferred.succeed(handoff, undefined); }
        yield* Deferred.await(releasing); assert.equal(completed, false); assert.equal(released, 0);
        yield* Deferred.succeed(ack, undefined);
      }
      yield* Fiber.join(cancellation);
      const exit = yield* Effect.exit(Fiber.join(fiber)); assert.ok(Exit.isFailure(exit));
      assert.ok(Cause.hasInterruptsOnly(exit.cause)); assert.equal(completed, true);
      assert.equal(JSON.stringify(exit).includes("synthetic-parity-cleanup-secret"), false);
      assert.equal(acquired, vector.phase === "admission" ? 0 : 1);
      assert.equal(reads, vector.phase === "read" ? 1 : 0);
      assert.equal(released, vector.phase === "admission" ? 0 : 1);
      return { acquired, reads, released, completed: Boolean(completed), interruptOnly: Cause.hasInterruptsOnly(exit.cause) };
    }));
    observations.push(observed);
  }
  assert.deepEqual(observations[0], observations[1]);
});
