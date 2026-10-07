import assert from "node:assert/strict";
import test from "node:test";
import * as Effect from "effect/Effect";
import * as Result from "effect/Result";
import * as Exit from "effect/Exit";
import { createDiscovery, discoveryFactory, type DiscoveryIssuer, type TrustedParser, type OwnedDecision } from "../../src/surfaces/discovery-normalizer.js";
import { discoveryCatalog, discoveryContract, discoveryVectors, type DecisionFields as FrozenDecisionFields } from "./discovery-normalizer-vectors.js";

// Compile-time consumption of the independently frozen full interface; no alternate test API.
const acceptedFactory = discoveryFactory;
interface Vector {
  readonly id: string; readonly argv_json?: string; readonly tty: boolean;
  readonly input_stimulus?: { readonly kind: string; readonly unit?: string; readonly count?: number; readonly token?: string; readonly wire?: string };
  readonly parser_stimulus: { readonly behavior: string; readonly wire?: string };
  readonly expected_decision_utf8: string; readonly expected_effects: Readonly<Record<string, number>>;
}
const vectors: readonly Vector[] = discoveryVectors;
const forbiddenKeys = ["network", "credentials", "mutations", "source_calls", "acquires", "releases", "stdout_writes"] as const;
for (const vector of vectors) test(`discovery frozen local literal ${vector.id}`, async () => {
  let parserCalls = 0, traps = 0, coercions = 0;
  const forbidden = Object.fromEntries(forbiddenKeys.map((key) => [key, 0]));
  // The fake has explicit forbidden-I/O spies, but never grants those capabilities to the gate.
  const forbid = (key: typeof forbiddenKeys[number]): never => { forbidden[key] = (forbidden[key] ?? 0) + 1; throw Error("SYNTHETIC_PRIVATE_IO"); };
  const hooks: ProxyHandler<object> = {
    get() { traps++; throw Error("SYNTHETIC_PRIVATE_PROXY"); },
    ownKeys() { traps++; throw Error("SYNTHETIC_PRIVATE_PROXY"); },
    getPrototypeOf() { traps++; throw Error("SYNTHETIC_PRIVATE_PROXY"); },
    getOwnPropertyDescriptor() { traps++; throw Error("SYNTHETIC_PRIVATE_PROXY"); },
    has() { traps++; throw Error("SYNTHETIC_PRIVATE_PROXY"); },
  };
  let argv: unknown = vector.argv_json ?? '["query"]', tty: unknown = vector.tty;
  const stimulus = vector.input_stimulus;
  if (stimulus) switch (stimulus.kind) {
    case "proxy": argv = new Proxy({}, hooks); break;
    case "array": argv = ["query"]; break;
    case "object_with_coercion": argv = { [Symbol.toPrimitive]() { coercions++; throw Error("SYNTHETIC_PRIVATE_COERCION"); }, toString() { coercions++; throw Error("SYNTHETIC_PRIVATE_COERCION"); }, valueOf() { coercions++; throw Error("SYNTHETIC_PRIVATE_COERCION"); } }; break;
    case "tty_proxy": tty = new Proxy({}, hooks); break;
    case "repeat_wire": assert.ok(stimulus.unit && stimulus.count); argv = stimulus.unit.repeat(stimulus.count); break;
    case "argv_repeat": assert.ok(stimulus.token && stimulus.count); argv = JSON.stringify(Array.from({ length: stimulus.count }, () => stimulus.token)); break;
    case "token_repeat": assert.ok(stimulus.unit && stimulus.count); argv = JSON.stringify([stimulus.unit.repeat(stimulus.count)]); break;
    case "literal": assert.equal(typeof stimulus.wire, "string"); argv = stimulus.wire; break;
    default: assert.fail("Unrecognized frozen harness directive");
  }
  let foreign: unknown;
  if (vector.parser_stimulus.behavior === "foreign_issuer") {
    const other = createDiscovery({ parse(_argv, issuer) { foreign = issuer.issue('["invocation","query","manual-ip",17647,false,false,null,false,false,false,false,false,false]'); return foreign; } }, discoveryCatalog);
    await Effect.runPromise(other.normalize('["query"]', false));
  }
  const parser: TrustedParser = {
    parse(snapshot, issuer) {
      parserCalls++;
      assert.ok(Object.isFrozen(snapshot)); assert.ok(Object.isFrozen(issuer));
      assert.equal(snapshot.length <= discoveryContract.budgets.argv_count, true);
      assert.equal(snapshot.every((token) => typeof token === "string"), true);
      assert.deepEqual(Object.keys(issuer), ["issue"]);
      switch (vector.parser_stimulus.behavior) {
        case "issue": return issuer.issue(vector.parser_stimulus.wire);
        case "foreign_issuer": return foreign;
        case "proxy": return new Proxy({}, hooks);
        case "record": return { type: "invocation", path: "query" };
        case "throw_private_provider_error": throw Error("SYNTHETIC_PROVIDER_SECRET");
        case "must_not_call": return forbid("source_calls");
        default: return forbid("network");
      }
    },
  };
  const gate = acceptedFactory.create(parser, discoveryCatalog);
  const decision = await Effect.runPromise(gate.normalize(argv, tty));
  const frozenShape: FrozenDecisionFields = decision;
  assert.ok(Object.isFrozen(frozenShape));
  const encoded = gate.encode(decision); assert.ok(Result.isSuccess(encoded));
  assert.equal(encoded.success, vector.expected_decision_utf8);
  assert.equal(encoded.success.includes("SYNTHETIC_SECRET"), false);
  assert.equal(encoded.success.includes("SYNTHETIC_PROVIDER"), false);
  assert.equal(decision.request_sent, false); assert.equal(decision.authority_granted, false);
  const observed: Readonly<Record<string, number>> = { parser_calls: parserCalls, proxy_traps: traps, coercion_calls: coercions, ...forbidden };
  for (const [key, expected] of Object.entries(vector.expected_effects)) assert.equal(observed[key], expected, `${vector.id}: ${key}`);
  // Every case also verifies the encoder's same-factory boundary before any caller properties.
  const callbacksBefore = parserCalls;
  const foreignEncoder = createDiscovery(parser, discoveryCatalog);
  assert.ok(Result.isFailure(foreignEncoder.encode(decision)));
  for (const value of [JSON.parse(encoded.success) as unknown, new Proxy({}, hooks), null, encoded.success]) {
    const failed = gate.encode(value); assert.ok(Result.isFailure(failed)); assert.deepEqual(failed.failure, { code: "private_discovery_owned" });
  }
  assert.equal(traps, 0); assert.equal(coercions, 0); assert.equal(parserCalls, callbacksBefore);
});

test("discovery admits private JSON escapes/whitespace and snapshots only primitive arguments", async () => {
  let captured: readonly string[] | undefined;
  const gate = createDiscovery({ parse(argv, issuer) { captured = argv; return issuer.issue('["invocation","query","manual-ip",17647,false,false,null,false,false,false,false,false,false]'); } }, discoveryCatalog);
  const result = await Effect.runPromise(gate.normalize(' \t["q\\u0075ery"]\r\n', false));
  assert.deepEqual(captured, ["query"]); assert.ok(Object.isFrozen(captured));
  assert.equal(result.kind, "local_query_catalog");
  assert.ok(Result.isSuccess(gate.encode(result)));
});

test("discovery encoder rejects revoked proxies and coercion objects without effects", () => {
  let calls = 0, coercions = 0;
  const gate = createDiscovery({ parse() { calls++; return null; } }, discoveryCatalog);
  const revoked = Proxy.revocable({}, {}); revoked.revoke();
  for (const value of [revoked.proxy, { [Symbol.toPrimitive]() { coercions++; throw Error("SYNTHETIC_PRIVATE_COERCION"); } }]) {
    const result = gate.encode(value); assert.ok(Result.isFailure(result)); assert.deepEqual(result.failure, { code: "private_discovery_owned" });
  }
  assert.equal(calls, 0); assert.equal(coercions, 0);
});

test("discovery issuer rejects nonprimitive/extra/nested/rounded tuples before issuing ownership", async () => {
  let traps = 0;
  let issuer: DiscoveryIssuer | undefined;
  const gate = createDiscovery({ parse(_argv, ownedIssuer) { issuer = ownedIssuer; return ownedIssuer.issue('["invocation","query","manual-ip",17647,false,false,null,false,false,false,false,false,false]'); } }, discoveryCatalog);
  await Effect.runPromise(gate.normalize('["query"]', false)); assert.ok(issuer);
  const proxy = new Proxy({}, { get() { traps++; throw Error("SYNTHETIC_PROXY"); }, ownKeys() { traps++; throw Error("SYNTHETIC_PROXY"); } });
  for (const value of [proxy, {}, '["invocation"]', '["failure","query","not_a_source_error",false,false]', '["text","unknown",false,false]', '["invocation","query","manual-ip",1e0,false,false,null,false,false,false,false,false,false]', '["invocation","query","manual-ip",1.0,false,false,null,false,false,false,false,false,false]', '["text","help",false,false,null]', '[[]]']) assert.equal(issuer.issue(value), null);
  assert.equal(traps, 0);
});

test("discovery owned result mutation cannot alter later encoding or catalog filtering", async () => {
  const gate = createDiscovery({ parse(_argv, issuer) { return issuer.issue('["invocation","query","manual-ip",17647,false,false,"healthmd_sleep_sessions",false,false,false,false,false,false]'); } }, discoveryCatalog);
  const decision = await Effect.runPromise(gate.normalize('["query","healthmd_sleep_sessions"]', false));
  const before = gate.encode(decision); assert.ok(Result.isSuccess(before));
  assert.throws(() => Object.defineProperty(decision, "authority_granted", { value: true }));
  const after = gate.encode(decision); assert.ok(Result.isSuccess(after)); assert.equal(after.success, before.success);
  assert.equal(decision.operation, "healthmd_sleep_sessions");
});

test("discovery observes Effect cancellation before a pure parser callback without acquisition", async () => {
  let calls = 0;
  const gate = createDiscovery({ parse() { calls++; return null; } }, discoveryCatalog);
  const exit = await Effect.runPromiseExit(Effect.interrupt.pipe(Effect.flatMap(() => gate.normalize('["query"]', false))));
  assert.ok(Exit.isFailure(exit)); assert.ok(exit.cause.reasons.some((reason) => reason._tag === "Interrupt")); assert.equal(calls, 0);
});

// The interface intentionally exposes no executor, host state, source grant, native or I/O method.
test("discovery factory and result expose only the frozen metadata boundary", async () => {
  const gate = createDiscovery({ parse(_argv, issuer) { return issuer.issue('["invocation","status","manual-ip",17647,false,false,null,false,false,false,false,false,false]'); } }, discoveryCatalog);
  assert.deepEqual(Object.keys(gate).sort(), ["encode", "normalize"]); assert.ok(Object.isFrozen(gate));
  const value: OwnedDecision = await Effect.runPromise(gate.normalize('["status"]', false));
  assert.equal(value.kind, "deferred_command"); assert.equal(value.exit, null);
  assert.deepEqual(Object.keys(value), Object.keys(JSON.parse(vectors[4]!.expected_decision_utf8)));
});
