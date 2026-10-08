import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import * as Result from "effect/Result";
import * as Effect from "effect/Effect";
import * as Scope from "effect/Scope";
import * as Exit from "effect/Exit";
import { createCanonicalJsonSerializer } from "../src/serialization/canonical-json.js";
import { createExactJsonCodec, captureExactJsonValueReader } from "../src/serialization/exact-json-value.js";
import type { ExactJsonValueFactory, OwnedJsonValue } from "../src/serialization/exact-json-value.js";
import { canonicalJsonVectors, retainedSerializerPacketProposals } from "./canonical-json-vectors.js";

type Row = { readonly case_id: string; readonly input: Readonly<Record<string, unknown>>; readonly expected: Readonly<Record<string, unknown>> };
const rows: readonly Row[] = canonicalJsonVectors;
const compact = "serde_value_compact";
function success<T, E>(result: Result.Result<T, E>): T { assert.ok(Result.isSuccess(result)); return result.success; }
function rejected<T, E>(result: Result.Result<T, E>): void {
  assert.ok(Result.isFailure(result));
  assert.deepEqual(result.failure, { _tag: "ExactJsonValueFailure", code: "invalid_json_value" });
}
function own(a: ExactJsonValueFactory, text: string): OwnedJsonValue { return success(a.codec.parse("text", text)); }
function serializer(a: ExactJsonValueFactory) { return success(createCanonicalJsonSerializer(a.codec, a.readerToken)); }
function text(value: unknown): string { assert.equal(typeof value, "string"); return value as string; }
function count(value: unknown): number { assert.equal(typeof value, "number"); return value as number; }
function inputRecipe(input: Readonly<Record<string, unknown>>): string {
  switch (input.harness) {
    case "bounded_array_numeric_output": return "[" + (text(input.repeat_token) + ",").repeat(count(input.repeat_count)) + text(input.tail_json) + "]";
    case "bounded_array_escaped_output": return "[" + (text(input.repeat_token) + ",").repeat(count(input.repeat_count)) + text(input.escaped_string_json) + "," + text(input.tail_json) + "]";
    case "array_nulls": return "[" + "null,".repeat(count(input.count) - 1) + "null]";
    case "nested_arrays": return "[".repeat(count(input.count)) + text(input.inner_json) + "]".repeat(count(input.count));
    case "quoted_ascii": case "quoted_unicode": return '"' + text(input.char).repeat(count(input.count)) + '"';
    case "quoted_escaped_short_control": return '"' + text(input.escape).repeat(count(input.count)) + '"';
    default: throw new Error("unrealized independent input recipe");
  }
}
function expectedRecipe(value: unknown): string {
  assert.ok(typeof value === "object" && value !== null);
  const r = value as Readonly<Record<string, unknown>>;
  if ("opening_brackets" in r) return "[".repeat(count(r.opening_brackets)) + text(r.inner) + "]".repeat(count(r.closing_brackets));
  if (r.quote === true) return '"' + text(r.char ?? r.repeated).repeat(count(r.repeat_count)) + '"';
  return text(r.prefix) + text(r.repeated).repeat(count(r.repeat_count)) + text(r.tail);
}
function output(bytes: Uint8Array, expected: string): void { assert.deepEqual(bytes, new Uint8Array(Buffer.from(expected, "utf8"))); }

for (const row of rows) {
  test(`independent canonical literal: ${row.case_id}`, async () => {
    const a = createExactJsonCodec(); const encoded = serializer(a);
    if (row.input.harness === undefined || row.case_id.startsWith("serialize-bound-")) {
      const source = row.input.harness === undefined ? text(row.input.owned_input) : inputRecipe(row.input);
      const parsed = a.codec.parse(row.input.representation ?? "text", source);
      if ("parse_error" in row.expected) {
        rejected(parsed);
        // This producer obtains no handle and therefore never invokes the encoder.
        let encodeCalls = 0;
        if (Result.isSuccess(parsed)) { encodeCalls += 1; encoded.encode(parsed.success, row.input.policy); }
        assert.equal(encodeCalls, row.expected.encode_calls);
        return;
      }
      const handle = success(parsed);
      if ("source_number" in row.expected) {
        const reader = success(captureExactJsonValueReader(a.codec, a.readerToken));
        const node = success(reader.read(handle)); assert.equal(node.kind, "number");
        if (node.kind === "number") assert.deepEqual(node.value, row.expected.source_number);
      }
      const result = encoded.encode(handle, row.input.policy);
      if ("error" in row.expected) { rejected(result); return; }
      const bytes = success(result);
      const expected = "utf8" in row.expected ? text(row.expected.utf8) : expectedRecipe(row.expected.output_recipe);
      output(bytes, expected);
      if ("utf8_hex" in row.expected) assert.equal(Buffer.from(bytes).toString("hex"), row.expected.utf8_hex);
      if ("encoded_bytes" in row.expected) assert.equal(bytes.length, row.expected.encoded_bytes);
      if ("complete_encoded_bytes" in row.expected) assert.equal(bytes.length, row.expected.complete_encoded_bytes);
      // Input constructions, rather than inaccessible private counters, witness the size formulas.
      if (row.input.harness === "bounded_array_escaped_output") {
        assert.equal(Buffer.byteLength('\0\n"\\é', "utf8"), row.expected.decoded_last_string_bytes);
        assert.equal(Buffer.byteLength(text(row.input.escaped_string_json), "utf8"), row.expected.escaped_string_encoded_bytes);
      }
      return;
    }
    const b = createExactJsonCodec(); const handle = own(a, "[1]");
    let traps = 0;
    const trap = (): never => { traps += 1; throw new Error("private caller cause must never escape"); };
    const handlers: ProxyHandler<object> = { get: trap, set: trap, has: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap, defineProperty: trap, isExtensible: trap };
    const proxy = new Proxy({}, handlers);
    const revocable = Proxy.revocable({}, handlers); revocable.revoke();
    const accessor = { get read(): never { return trap(); }, get parse(): never { return trap(); }, get value(): never { return trap(); }, get capture(): never { return trap(); }, toJSON: trap, toString: trap, valueOf: trap, [Symbol.toPrimitive]: trap };
    switch (row.case_id) {
      case "serialize-foreign-handle": rejected(encoded.encode(own(b, "[1]"), compact)); break;
      case "serialize-foreign-child": {
        const original = success(captureExactJsonValueReader(b.codec, b.readerToken)); const node = success(original.read(own(b, "[1]"))); assert.equal(node.kind, "array");
        if (node.kind === "array") rejected(encoded.encode(node.items[0], compact)); break;
      }
      case "serialize-handle-proxy": rejected(encoded.encode(proxy, compact)); break;
      case "serialize-handle-revoked-proxy": rejected(encoded.encode(revocable.proxy, compact)); break;
      case "serialize-forged-ast": rejected(encoded.encode(accessor, compact)); break;
      case "serialize-handle-null": rejected(encoded.encode(null, compact)); break;
      case "serialize-handle-number": rejected(encoded.encode(1, compact)); break;
      case "serialize-handle-symbol": rejected(encoded.encode(Symbol("caller"), compact)); break;
      case "serialize-handle-bigint": rejected(encoded.encode(1n, compact)); break;
      case "serialize-handle-function": rejected(encoded.encode(trap, compact)); break;
      case "serialize-codec-proxy": rejected(createCanonicalJsonSerializer(proxy, a.readerToken)); break;
      case "serialize-codec-revoked-proxy": rejected(createCanonicalJsonSerializer(revocable.proxy, a.readerToken)); break;
      case "serialize-token-proxy": rejected(createCanonicalJsonSerializer(a.codec, proxy)); break;
      case "serialize-token-revoked-proxy": rejected(createCanonicalJsonSerializer(a.codec, revocable.proxy)); break;
      case "serialize-token-cross-factory": rejected(createCanonicalJsonSerializer(a.codec, b.readerToken)); break;
      case "serialize-token-forged": rejected(createCanonicalJsonSerializer(a.codec, {})); break;
      case "serialize-codec-getter-forged": rejected(createCanonicalJsonSerializer(accessor, a.readerToken)); break;
      case "serialize-codec-null": rejected(createCanonicalJsonSerializer(null, a.readerToken)); break;
      case "serialize-reader-function-injection": rejected(createCanonicalJsonSerializer(trap, trap)); break;
      case "serialize-reader-object-injection": rejected(createCanonicalJsonSerializer(success(captureExactJsonValueReader(a.codec, a.readerToken)), a.readerToken)); break;
      case "serialize-invalid-profile": rejected(encoded.encode(own(a, "{}"), "foundation_ordered_json")); break;
      case "serialize-pretty-profile": rejected(encoded.encode(own(a, "{}"), "pretty_json")); break;
      case "serialize-empty-profile": rejected(encoded.encode(own(a, "{}"), "")); break;
      case "serialize-undefined-profile": rejected(encoded.encode(own(a, "{}"), undefined)); break;
      case "serialize-policy-proxy": rejected(encoded.encode(own(a, "{}"), proxy)); break;
      case "serialize-policy-revoked-proxy": rejected(encoded.encode(own(a, "{}"), revocable.proxy)); break;
      case "serialize-policy-coercion": rejected(encoded.encode(own(a, "{}"), accessor)); break;
      case "serialize-policy-number": rejected(encoded.encode(own(a, "{}"), 1)); break;
      case "serialize-policy-overlong": rejected(encoded.encode(own(a, "{}"), compact + "a".repeat(1048577))); break;
      case "serialize-typed-array-handle": rejected(encoded.encode(new Uint8Array([1]), compact)); break;
      case "serialize-output-owned": {
        const first = success(encoded.encode(handle, compact)); const second = success(encoded.encode(handle, compact)); output(first, text(row.expected.first_before_utf8));
        first.fill(0); const third = success(encoded.encode(handle, compact));
        output(second, text(row.expected.second_utf8)); output(third, text(row.expected.third_utf8));
        assert.notEqual(first, second); assert.notEqual(second, third); assert.notEqual(first, third);
        assert.notEqual(first.buffer, second.buffer); assert.notEqual(second.buffer, third.buffer); assert.notEqual(first.buffer, third.buffer);
        break;
      }
      case "serialize-original-reader-capture": {
        const root = own(a, text(row.input.owned_input)); const original = success(captureExactJsonValueReader(a.codec, a.readerToken));
        assert.equal(Reflect.set(a.codec, "parse", trap), false); assert.equal(Reflect.set(original, "read", trap), false);
        let callerRead: unknown = original.read; callerRead = trap; assert.equal(callerRead, trap);
        output(success(encoded.encode(root, compact)), text(row.expected.utf8)); break;
      }
      case "serialize-same-factory-child": {
        const original = success(captureExactJsonValueReader(a.codec, a.readerToken)); const node = success(original.read(own(a, text(row.input.owned_input)))); assert.equal(node.kind, "array");
        if (node.kind === "array") output(success(encoded.encode(node.items[0], compact)), text(row.expected.utf8)); break;
      }
      case "serialize-pure-scope-no-authority": {
        // This operation adapter is a synthetic lifetime witness, never authenticated source permission.
        const root = own(a, text(row.input.owned_input)); const scope = Effect.runSync(Scope.make()); let operationLive = true;
        await Effect.runPromise(Scope.addFinalizer(scope, Effect.sync(() => { operationLive = false; })));
        await Effect.runPromise(Scope.close(scope, Exit.succeed(undefined)));
        output(success(encoded.encode(root, compact)), text(row.expected.utf8));
        const fakeSourceAuthorized = false; const fakeDeliveryAllowed = operationLive && fakeSourceAuthorized;
        assert.equal(fakeSourceAuthorized, row.expected.source_authorized); assert.equal(fakeDeliveryAllowed, row.expected.delivery_allowed); break;
      }
      case "serialize-reused-handle-policy-independent": {
        const root = own(a, text(row.input.owned_input)); const results = [success(encoded.encode(root, compact)), success(encoded.encode(root, "serde_value_compact_lf")), success(encoded.encode(root, compact))];
        assert.deepEqual(results.map(bytes => Buffer.from(bytes).toString("utf8")), row.expected.utf8_sequence);
        assert.equal(new Set(results.map(bytes => bytes.buffer)).size, 3); break;
      }
      default: throw new Error("unrealized independent ownership stimulus");
    }
    assert.equal(traps, 0);
  });
}

test("canonical fixture and accepted parser/scalar bytes remain independent and immutable", () => {
  assert.equal(rows.length, 265); assert.equal(new Set(rows.map(row => row.case_id)).size, 265); assert.equal(retainedSerializerPacketProposals.length, 9);
  const pins = [
    ["tests/canonical-json-vectors.ts", "0412eb2a2cba7e4c11fd2123c60eed6c945f32e413af4e3b3470eb4e2298162b"],
    ["src/serialization/exact-json-value.ts", "6e8ac7aff564ac3c488799800f457f3a0e5cb74e1b2c78fb938937355a1acffc"],
    ["tests/exact-json-value.test.ts", "06a53b3977fc89326b5beaff23fef24d8bc6610111a7e3b37031f2b288ffb81f"],
    ["tests/exact-json-value-vectors.ts", "47eeb023f116a547d5916edc782794b58583caf8921668c575660f735ae3c1b0"],
    ["src/serialization/exact-json-number-parser.ts", "099505e1b4f9890848d8a159daf75f482bd24e647ba0f01a16c711bfeeebadbc"],
    ["tests/exact-json-number-parser.test.ts", "1b75c4c5824049385e2036b720cb72c0ac40d404cafb296dba210470db9e5e7f"],
    ["tests/exact-json-number-parser-vectors.ts", "22880c130c4871b7b32371f04753a064988805cdbabe1ec73c0ce5ade71779a3"],
    ["src/serialization/exact-json-numbers.ts", "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"],
    ["tests/exact-json-numbers.test.ts", "9415b3d8ab923ef905fe8e35d01fc4df47fd23516c3d54072713fefd50e10810"],
    ["tests/exact-json-numbers-vectors.ts", "3da51631a58425a061c4f386a88ab22457af855e914775fb77233358c0c4b1e8"],
  ] as const;
  for (const [path, hash] of pins) assert.equal(createHash("sha256").update(readFileSync(path)).digest("hex"), hash);
});
