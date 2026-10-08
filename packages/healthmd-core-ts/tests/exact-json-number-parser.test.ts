import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Result from "effect/Result";
import * as Scope from "effect/Scope";
import { createExactJsonNumberParser } from "../src/serialization/exact-json-number-parser.js";
import type { OwnedJsonNumber } from "../src/serialization/exact-json-number-parser.js";
import { numberParserVectors } from "./exact-json-number-parser-vectors.js";

const failure = { _tag: "ExactJsonNumberFailure", code: "invalid_json_number" } as const;
function rejected(value: Result.Result<unknown, unknown>): void {
  assert.ok(Result.isFailure(value));
  assert.deepEqual(value.failure, failure);
  assert.ok(Object.isFrozen(value.failure));
}
function own(parser: ReturnType<typeof createExactJsonNumberParser>, text = "1"): OwnedJsonNumber {
  const result = parser.parse("serde_value_default", text);
  assert.ok(Result.isSuccess(result));
  assert.ok(Object.isFrozen(result.success));
  assert.equal(Object.getPrototypeOf(result.success), null);
  assert.deepEqual(Reflect.ownKeys(result.success), []);
  return result.success;
}

// Each scenario builds the literal stimulus; no candidate output supplies expected values.
for (const vector of numberParserVectors) {
  test(`independent number parser literal: ${vector.case_id}`, () => {
    const parser = createExactJsonNumberParser();
    if (typeof vector.input === "string") {
      const result = parser.parse("serde_value_default", vector.input);
      if ("error" in vector.expected) {
        rejected(result);
      } else {
        assert.ok(Result.isSuccess(result));
        const descriptor = parser.read(result.success);
        assert.ok(Result.isSuccess(descriptor));
        assert.deepEqual(descriptor.success, vector.expected);
        assert.ok(Object.isFrozen(descriptor.success));
      }
      return;
    }
    const scenario = vector.input.harness;
    let traps = 0;
    const trap = (): never => { traps += 1; throw new Error("caller secret must never be observed"); };
    const proxy = new Proxy({}, {
      get: trap, set: trap, has: trap, ownKeys: trap, getPrototypeOf: trap,
      getOwnPropertyDescriptor: trap, defineProperty: trap, isExtensible: trap,
    });
    switch (scenario) {
      case "throwing proxy/accessor/coercion object":
      case "throwing Proxy object": rejected(parser.parse("serde_value_default", proxy)); break;
      case "object with accessor/toString/Symbol.toPrimitive traps": {
        const accessor = { get decimal(): never { return trap(); }, toString: trap, [Symbol.toPrimitive]: trap };
        rejected(parser.parse("serde_value_default", accessor)); break;
      }
      case "array": rejected(parser.parse("serde_value_default", [])); break;
      case "null": rejected(parser.parse("serde_value_default", null)); break;
      case "numeric1": rejected(parser.parse("serde_value_default", 1)); break;
      case "true": rejected(parser.parse("serde_value_default", true)); break;
      case "bigint1": rejected(parser.parse("serde_value_default", 1n)); break;
      case "throwing Proxy representation": rejected(parser.parse(proxy, "1")); break;
      case "signed_integer": rejected(parser.parse("signed_integer", "1")); break;
      case "string1millioncodeunits": rejected(parser.parse("serde_value_default", "1".repeat(1_000_000))); break;
      case "read authentic other factory handle": rejected(parser.read(own(createExactJsonNumberParser()))); break;
      case "read throwing proxy handle": rejected(parser.read(proxy)); break;
      case "read caller object with matching visible fields/brand":
        rejected(parser.read({ class: "u64", decimal: "1", [Symbol("ownedNumberBrand")]: true })); break;
      case "save original bound reader, later substitute unrelated reader config": {
        const handle = own(parser);
        const captured = parser.read;
        const unrelated = createExactJsonNumberParser();
        // A consumer's later reader substitution cannot change captured factory membership.
        const substitute = unrelated.read;
        const original = captured(handle);
        assert.ok(Result.isSuccess(original));
        assert.deepEqual(original.success, { class: "u64", decimal: "1" });
        rejected(substitute(handle));
        assert.ok("original_factory_membership" in vector.expected);
        assert.equal(vector.expected.original_factory_membership, true);
        assert.ok("substitute_accepted" in vector.expected);
        assert.equal(vector.expected.substitute_accepted, false);
        break;
      }
      case "mutate returned descriptor then read same handle": {
        const handle = own(parser);
        const first = parser.read(handle);
        assert.ok(Result.isSuccess(first));
        assert.equal(Reflect.set(first.success, "decimal", "2"), false);
        const second = parser.read(handle);
        assert.ok(Result.isSuccess(second));
        assert.notEqual(first.success, second.success);
        assert.deepEqual(second.success, { class: "u64", decimal: "1" });
        assert.deepEqual(Reflect.ownKeys(second.success).sort(), ["class", "decimal"]);
        assert.ok("immutable_original" in vector.expected);
        assert.equal(vector.expected.immutable_original, true);
        assert.ok("fresh_view" in vector.expected);
        assert.equal(vector.expected.fresh_view, true);
        break;
      }
      case "operation scope closes while pure numeric handle still exists": {
        // A real operation lifetime ends; the independent pure codec does not reopen it.
        const scope = Effect.runSync(Scope.make());
        let operationLive = true;
        Effect.runSync(Scope.addFinalizer(scope, Effect.sync(() => { operationLive = false; })));
        const handle = own(parser);
        Effect.runSync(Scope.close(scope, Exit.succeed(undefined)));
        assert.ok("operation_after_close" in vector.expected);
        assert.equal(operationLive, vector.expected.operation_after_close);
        assert.deepEqual(Reflect.ownKeys(parser).sort(), ["parse", "read"]);
        assert.ok("codec_implies_authority" in vector.expected);
        assert.equal("authority" in parser, vector.expected.codec_implies_authority);
        assert.ok(Result.isSuccess(parser.read(handle)));
        break;
      }
      case "pass owned descriptor/object directly as primitive payload": {
        const descriptor = parser.read(own(parser));
        assert.ok(Result.isSuccess(descriptor));
        rejected(parser.parse("serde_value_default", descriptor.success)); break;
      }
      default: throw new Error(`unhandled frozen scenario: ${scenario satisfies never}`);
    }
    assert.equal(traps, 0);
  });
}

test("independent fixture bytes and retained scalar implementation stay frozen", async () => {
  for (const [path, sha] of [
    ["tests/exact-json-number-parser-vectors.ts", "22880c130c4871b7b32371f04753a064988805cdbabe1ec73c0ce5ade71779a3"],
    ["src/serialization/exact-json-numbers.ts", "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"],
  ] as const) assert.equal(createHash("sha256").update(await readFile(path)).digest("hex"), sha);
  assert.equal(numberParserVectors.length, 98);
});
