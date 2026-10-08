import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { readFile as readFileAsync } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as Result from "effect/Result";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Scope from "effect/Scope";
import * as Facade from "../src/serialization/index.js";
import { createExactJsonNumberParser, createExactJsonCodec, createCanonicalJsonSerializer, serializeExactJsonNumber } from "../src/serialization/index.js";
import type { OwnedJsonNumber, SourceNumber, ExactJsonNumberParser, ExactJsonNumberFailure, ExactJsonNumberResult, OwnedJsonValue, ExactJsonValueFailure, OwnedJsonValueCodec, ExactJsonValueFactory, CanonicalJsonSerializer } from "../src/serialization/index.js";
import * as OriginalNumber from "../src/serialization/exact-json-number-parser.js";
import * as OriginalValue from "../src/serialization/exact-json-value.js";
import * as OriginalSerializer from "../src/serialization/canonical-json.js";
import * as OriginalScalar from "../src/serialization/exact-json-numbers.js";
// Original test-only reader inspects source-class views; it is never a facade export.
import { captureExactJsonValueReader } from "../src/serialization/exact-json-value.js";
import type { CapturedExactJsonValueReader, ExactJsonValueNode, SourceNumericValue } from "../src/serialization/exact-json-value.js";
import { binary64Vectors, integerVectors, rejectedVectors } from "./exact-json-numbers-vectors.js";
import { numberParserVectors } from "./exact-json-number-parser-vectors.js";
import { exactJsonValueContract, exactJsonValueVectors } from "./exact-json-value-vectors.js";
import { canonicalJsonVectors, retainedSerializerPacketProposals } from "./canonical-json-vectors.js";
import { candidateCodecApiContract, candidateCodecApiVectors } from "./candidate-codec-api-vectors.js";
import type { CandidateCodecApi } from "./candidate-codec-api-vectors.js";
// @ts-expect-error Deliberately absent named reader function.
import type { captureExactJsonValueReader as ExcludedCapture } from "../src/serialization/index.js";
// @ts-expect-error Deliberately absent named captured reader type.
import type { CapturedExactJsonValueReader as ExcludedReader } from "../src/serialization/index.js";
// @ts-expect-error Deliberately absent named AST node type.
import type { ExactJsonValueNode as ExcludedNode } from "../src/serialization/index.js";
// @ts-expect-error Deliberately absent source alias type.
import type { SourceNumericValue as ExcludedNumeric } from "../src/serialization/index.js";
// @ts-expect-error Token is only a transitive original factory field, not a named export.
import type { OwnedJsonValueReaderToken as ExcludedToken } from "../src/serialization/index.js";
const typedApi: CandidateCodecApi = Facade;
const originals = { createExactJsonNumberParser: OriginalNumber.createExactJsonNumberParser, createExactJsonCodec: OriginalValue.createExactJsonCodec, createCanonicalJsonSerializer: OriginalSerializer.createCanonicalJsonSerializer, serializeExactJsonNumber: OriginalScalar.serializeExactJsonNumber };
type RuntimeName = keyof typeof originals;
type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends (<T>() => T extends B ? 1 : 2) ? true : false;
const runtimeNameWitness: Equal<keyof typeof Facade, RuntimeName> = true;
const typeWitnesses: readonly true[] = [
  true satisfies Equal<OwnedJsonNumber, OriginalNumber.OwnedJsonNumber>,
  true satisfies Equal<SourceNumber, OriginalNumber.SourceNumber>,
  true satisfies Equal<ExactJsonNumberParser, OriginalNumber.ExactJsonNumberParser>,
  true satisfies Equal<ExactJsonNumberFailure, OriginalScalar.ExactJsonNumberFailure>,
  true satisfies Equal<ExactJsonNumberResult, OriginalScalar.ExactJsonNumberResult>,
  true satisfies Equal<OwnedJsonValue, OriginalValue.OwnedJsonValue>,
  true satisfies Equal<ExactJsonValueFailure, OriginalValue.ExactJsonValueFailure>,
  true satisfies Equal<OwnedJsonValueCodec, OriginalValue.OwnedJsonValueCodec>,
  true satisfies Equal<ExactJsonValueFactory, OriginalValue.ExactJsonValueFactory>,
  true satisfies Equal<CanonicalJsonSerializer, OriginalSerializer.CanonicalJsonSerializer>,
];
function closedTypes(factory: ExactJsonValueFactory): void {
  // @ts-expect-error Original opaque token exposes no read function.
  const forbiddenReader = factory.readerToken.read;
  // @ts-expect-error Foreign structural object cannot acquire original number brand.
  const foreignNumber: OwnedJsonNumber = {};
  // @ts-expect-error Foreign structural object cannot acquire original value brand.
  const foreignValue: OwnedJsonValue = {};
  // @ts-expect-error Original opaque codec brand cannot be forged by a parse property.
  const foreignCodec: OwnedJsonValueCodec = { parse: factory.codec.parse };
  void forbiddenReader; void foreignNumber; void foreignValue; void foreignCodec;
}
void closedTypes; // Compiler witnesses only; never execute forbidden property reads.
type Row = { readonly case_id: string; readonly group?: string; readonly input: unknown; readonly expected: Readonly<Record<string, unknown>> };
const rows: readonly Row[] = candidateCodecApiVectors;
const retainedReplays = new Map<string, readonly (() => void | Promise<void>)[]>();
{
  const readFile = readFileAsync;
  const callbacks: (() => void | Promise<void>)[] = [];
  const register = (_title: string, run: () => void | Promise<void>): void => { callbacks.push(run); };

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
  register(`independent number parser literal: ${vector.case_id}`, () => {
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

register("independent fixture bytes and retained scalar implementation stay frozen", async () => {
  for (const [path, sha] of [
    ["tests/exact-json-number-parser-vectors.ts", "22880c130c4871b7b32371f04753a064988805cdbabe1ec73c0ce5ade71779a3"],
    ["src/serialization/exact-json-numbers.ts", "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"],
  ] as const) assert.equal(createHash("sha256").update(await readFile(path)).digest("hex"), sha);
  assert.equal(numberParserVectors.length, 98);
});

  retainedReplays.set("numbers", callbacks);
}
{
  const readFile = readFileAsync;
  const callbacks: (() => void | Promise<void>)[] = [];
  const register = (_title: string, run: () => void | Promise<void>): void => { callbacks.push(run); };

type Tree =
  | { readonly kind: "null" }
  | { readonly kind: "boolean"; readonly value: boolean }
  | { readonly kind: "string"; readonly value: string }
  | { readonly kind: "number"; readonly value: SourceNumericValue }
  | { readonly kind: "array"; readonly items: readonly Tree[] }
  | { readonly kind: "object"; readonly entries: readonly (readonly [string, Tree])[] };
type Row = { readonly case_id: string; readonly input: { readonly representation?: string; readonly payload?: string; readonly harness?: string }; readonly expected: Readonly<Record<string, unknown>> };
const rows: readonly Row[] = exactJsonValueVectors;
const failure = { _tag: "ExactJsonValueFailure", code: "invalid_json_value" } as const;
function reject(result: Result.Result<unknown, unknown>): void {
  assert.ok(Result.isFailure(result)); assert.deepEqual(result.failure, failure); assert.ok(Object.isFrozen(result.failure));
}
function reader(factory: ReturnType<typeof createExactJsonCodec>): CapturedExactJsonValueReader {
  const result = captureExactJsonValueReader(factory.codec, factory.readerToken);
  assert.ok(Result.isSuccess(result)); assert.ok(Object.isFrozen(result.success)); return result.success;
}
function own(factory: ReturnType<typeof createExactJsonCodec>, text: string): OwnedJsonValue {
  const result = factory.codec.parse("text", text); assert.ok(Result.isSuccess(result));
  assert.ok(Object.isFrozen(result.success)); assert.equal(Object.getPrototypeOf(result.success), null); assert.deepEqual(Reflect.ownKeys(result.success), []);
  return result.success;
}
function view(read: CapturedExactJsonValueReader, handle: unknown): ExactJsonValueNode {
  const result = read.read(handle); assert.ok(Result.isSuccess(result)); assert.ok(Object.isFrozen(result.success)); return result.success;
}
function tree(read: CapturedExactJsonValueReader, handle: OwnedJsonValue): Tree {
  const node = view(read, handle);
  switch (node.kind) {
    case "array": assert.ok(Object.isFrozen(node.items)); return { kind: "array", items: node.items.map(child => tree(read, child)) };
    case "object": assert.ok(Object.isFrozen(node.entries)); return { kind: "object", entries: node.entries.map(([key, child]) => [key, tree(read, child)] as const) };
    case "number": assert.ok(Object.isFrozen(node.value)); return { kind: "number", value: node.value };
    default: return node;
  }
}
interface PrimitiveInput { readonly representation: string; readonly payload: string }
const text = (payload: string): PrimitiveInput => ({ representation: "text", payload });
const hex = (payload: string): PrimitiveInput => ({ representation: "utf8_hex", payload });
const zeros = (count: number): string => "[" + "0,".repeat(count - 1) + "0]";
const nulls = (count: number): string => "[" + "null,".repeat(count - 1) + "null]";
const nested = (count: number): string => "[".repeat(count) + "null" + "]".repeat(count);
const rawKey = "$serde_json::private::RawValue";
// Test input quoting for the closed raw-carrier recipes only; no candidate expected bytes.
function carrier(inner: string): string {
  return '{"' + rawKey + '":"' + inner.replaceAll("\\", "\\\\").replaceAll('"', '\\"') + '"}';
}
const boundaryInputs = new Map<string, () => PrimitiveInput>([
  ["text: null + ASCII-space repeated1048572", () => text("null" + " ".repeat(1048572))],
  ["text: null + ASCII-space repeated1048573", () => text("null" + " ".repeat(1048573))],
  ["text: quoted\u00e9 + ASCII-space repeated1048572", () => text('"é"' + " ".repeat(1048572))],
  ["text: quoted\u00e9 + ASCII-space repeated1048573", () => text('"é"' + " ".repeat(1048573))],
  ["utf8_hex: 6e756c6c + 20 repeated1048572", () => hex("6e756c6c" + "20".repeat(1048572))],
  ["utf8_hex: 6e756c6c + 20 repeated1048573", () => hex("6e756c6c" + "20".repeat(1048573))],
  ["text: [ repeated127 + null + ] repeated127", () => text(nested(127))],
  ["text: [ repeated128 + null + ] repeated128", () => text(nested(128))],
  ["text: array of65535 comma-separated nulls", () => text(nulls(65535))],
  ["text: array of65536 comma-separated nulls", () => text(nulls(65536))],
  ["text: quoted ASCIIa repeated262144", () => text('"' + "a".repeat(262144) + '"')],
  ["text: quoted ASCIIa repeated262145", () => text('"' + "a".repeat(262145) + '"')],
  ["text: quoted\u00e9 repeated131072", () => text('"' + "é".repeat(131072) + '"')],
  ["text: quoted\u00e9 repeated131073", () => text('"' + "é".repeat(131073) + '"')],
  ["text: object with ASCIIa repeated131072 key and ASCIIb repeated131072 stringvalue", () => text('{"' + "a".repeat(131072) + '":"' + "b".repeat(131072) + '"}')],
  ["text: sameobject but valueASCIIb repeated131073", () => text('{"' + "a".repeat(131072) + '":"' + "b".repeat(131073) + '"}')],
  ["text: object with duplicate keya and131071-byteASCIIb then131071-byteASCIIc stringvalues", () => text('{"a":"' + "b".repeat(131071) + '","a":"' + "c".repeat(131071) + '"}')],
  ["text: sameduplicateobject but lastASCIIc stringvalue131072bytes", () => text('{"a":"' + "b".repeat(131071) + '","a":"' + "c".repeat(131072) + '"}')],
  ["text: object of65536 duplicate keya:null members", () => text("{" + '"a":null,'.repeat(65535) + '"a":null}')],
  ["text: 0e- + ASCII0 repeated1020 + 1 (token1024)", () => text("0e-" + "0".repeat(1020) + "1")],
  ["text: 0e- + ASCII0 repeated1021 + 1 (token1025)", () => text("0e-" + "0".repeat(1021) + "1")],
  ["text: ASCIIspace repeated1048531 then literal{\"$serde_json::private::RawValue\":\"null\"}", () => text(" ".repeat(1048531) + carrier("null"))],
  ["text: ASCIIspace repeated1048532 then literal{\"$serde_json::private::RawValue\":\"null\"}", () => text(" ".repeat(1048532) + carrier("null"))],
  ["text: firstrawcarrier stringvalue encoding127 nested arrays aroundnull; outercarrierobject depth1 makes sharedactivecontainerdepth128", () => text(carrier(nested(127)))],
  ["text: firstrawcarrier stringvalue encodingarray65534zeros; outercarrierobject+string2nodes plus innerarray+65534zeros65535nodes =65537total; innerstring131069ASCIIbytes belowstringcap", () => text(carrier(zeros(65534)))],
  ["text: firstrawcarrier stringvalue encodingquotedASCIIa131072; carrierdecodedstringbytes131074 + innerdecodedstringbytes131072 total262146", () => text(carrier('"' + "a".repeat(131072) + '"'))],
  ["text primitive ASCIIspace repeated1048577", () => text(" ".repeat(1048577))],
  ["utf8_hex primitive ASCII0 repeated2097153", () => hex("0".repeat(2097153))],
  ["text: firstrawcarrier stringvalue encodingarray65533zeros; rootcarrier2nodes + innerarray65534nodes =65536total", () => text(carrier(zeros(65533)))],
  ["text: firstrawcarrier stringvalue encoding126 nested arrays aroundnull; carrierobjectdepth1 + inner126 =127", () => text(carrier(nested(126)))],
  ["text: firstrawcarrier stringvalue encodingquotedASCIIa131056; key30 + carrierdecoded131058 + innerdecoded131056 =262144", () => text(carrier('"' + "a".repeat(131056) + '"'))],
  ["text: samecarrier innerASCIIa131057; 30+131059+131057=262146", () => text(carrier('"' + "a".repeat(131057) + '"'))],
]);

const seed = '{"a":[1,-0],"b":{"x":"é"}}';
const seedTree: Tree = { kind: "object", entries: [
  ["a", { kind: "array", items: [{ kind: "number", value: { class: "u64", decimal: "1" } }, { kind: "number", value: { class: "f64", bits: "8000000000000000" } }] }],
  ["b", { kind: "object", entries: [["x", { kind: "string", value: "é" }]] }],
] };
function stats(read: CapturedExactJsonValueReader, root: OwnedJsonValue): { nodes: number; depth: number } {
  function visit(handle: OwnedJsonValue, depth: number): { nodes: number; depth: number } {
    const node = view(read, handle);
    if (node.kind !== "array" && node.kind !== "object") return { nodes: 1, depth };
    const level = depth + 1;
    const children = node.kind === "array" ? node.items : node.entries.map(pair => pair[1]);
    let count = 1; let peak = level;
    for (const child of children) { const next = visit(child, level); count += next.nodes; peak = Math.max(peak, next.depth); }
    return { nodes: count, depth: peak };
  }
  return visit(root, 0);
}
for (const row of rows) {
  register(`independent value literal: ${row.case_id}`, () => {
    const a = createExactJsonCodec(); const readA = reader(a);
    if (row.input.harness === undefined || boundaryInputs.has(row.input.harness)) {
      const input = row.input.harness === undefined
        ? { representation: row.input.representation, payload: row.input.payload }
        : boundaryInputs.get(row.input.harness)!();
      const result = a.codec.parse(input.representation, input.payload);
      if ("error" in row.expected) { reject(result); return; }
      assert.ok(Result.isSuccess(result));
      if ("tree" in row.expected) assert.deepEqual(tree(readA, result.success), row.expected.tree);
      if ("root_kind" in row.expected) {
        const node = view(readA, result.success); assert.equal(node.kind, row.expected.root_kind);
        if (node.kind === "array" && "array_length" in row.expected) {
          assert.equal(node.items.length, row.expected.array_length);
          for (const child of node.items) {
            const expected: Tree = row.case_id === "value-bound-raw-nodes-at" ? { kind: "number", value: { class: "u64", decimal: "0" } } : { kind: "null" };
            assert.deepEqual(tree(readA, child), expected);
          }
        }
        if (node.kind === "string" && "decoded_utf8_bytes" in row.expected) {
          assert.equal(Buffer.byteLength(node.value, "utf8"), row.expected.decoded_utf8_bytes);
          const multibyte = row.case_id === "value-bound-string-multibyte-at";
          assert.equal(node.value, (multibyte ? "é" : "a").repeat(multibyte ? 131072 : node.value.length));
        }
        if (node.kind === "object" && "entry_count" in row.expected) {
          assert.equal(node.entries.length, row.expected.entry_count);
          const entry = node.entries[0]!; const child = view(readA, entry[1]); assert.equal(child.kind, "string");
          if (child.kind === "string") {
            if ("last_value_length" in row.expected) assert.equal(child.value, "c".repeat(131071));
            else { assert.equal(entry[0], "a".repeat(131072)); assert.equal(child.value, "b".repeat(131072)); }
          }
        }
        const measured = stats(readA, result.success);
        if ("container_depth" in row.expected) assert.equal(measured.depth, row.expected.container_depth);
        if ("final_graph_container_depth" in row.expected) assert.equal(measured.depth, row.expected.final_graph_container_depth);
        if ("final_graph_nodes" in row.expected) assert.equal(measured.nodes, row.expected.final_graph_nodes);
        // Source budget annotations count discarded carrier nodes/strings as well.
        // They are independent input arithmetic, not falsely observed private counters.
        if (row.case_id === "value-bound-discarded-key-strings-at") {
          // The input parses one object and two string values; LAST wins retains only two nodes.
          assert.equal(input.payload, '{"a":"' + "b".repeat(131071) + '","a":"' + "c".repeat(131071) + '"}');
          assert.equal(Buffer.byteLength(input.payload!, "utf8"), 262157);
          assert.equal(1 + 2, row.expected.parsed_nodes);
          assert.equal(measured.nodes, 2);
        } else if ("parsed_nodes" in row.expected && !row.case_id.startsWith("value-bound-raw-")) assert.equal(measured.nodes, row.expected.parsed_nodes);
      }
      if ("input_utf8_bytes" in row.expected && input.representation === "text") assert.equal(Buffer.byteLength(input.payload!, "utf8"), row.expected.input_utf8_bytes);
      return;
    }
    const b = createExactJsonCodec(); const readB = reader(b);
    const rootA = own(a, seed); const rootB = own(b, seed);
    let traps = 0;
    const trap = (): never => { traps += 1; throw new Error("private caller cause must never be returned"); };
    const proxy = new Proxy({}, { get: trap, set: trap, has: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap, defineProperty: trap, isExtensible: trap });
    switch (row.case_id) {
      case "value-own-payload-proxy": reject(a.codec.parse("text", proxy)); break;
      case "value-own-representation-proxy": reject(a.codec.parse(proxy, "null")); break;
      case "value-own-accessors": reject(a.codec.parse("text", { get value(): never { return trap(); }, toString: trap, [Symbol.toPrimitive]: trap })); break;
      case "value-own-typedbytes": reject(a.codec.parse("utf8_hex", new Uint8Array([110, 117, 108, 108]))); break;
      case "value-own-nullpayload": reject(a.codec.parse("text", null)); break;
      case "value-own-numericpayload": reject(a.codec.parse("text", 1)); break;
      case "value-own-wrongrepresentation": reject(a.codec.parse("json", "null")); break;
      case "value-own-codec-proxy": reject(captureExactJsonValueReader(proxy, a.readerToken)); break;
      case "value-own-reader-proxy": reject(captureExactJsonValueReader(a.codec, proxy)); break;
      case "value-own-reader-forged": reject(captureExactJsonValueReader(a.codec, { [Symbol("ownedJsonValueReader")]: true })); break;
      case "value-own-reader-crossfactory": reject(captureExactJsonValueReader(a.codec, b.readerToken)); break;
      case "value-own-codec-forged": reject(captureExactJsonValueReader({ get parse(): never { return trap(); } }, a.readerToken)); break;
      case "value-own-read-handle-proxy": reject(readA.read(proxy)); break;
      case "value-own-read-handle-forged": reject(readA.read({ kind: "null", [Symbol("ownedJsonValue")]: true })); break;
      case "value-own-read-root-crossfactory": reject(readA.read(rootB)); break;
      case "value-own-read-child-crossfactory": {
        const root = view(readB, rootB); assert.equal(root.kind, "object");
        if (root.kind === "object") { const array = view(readB, root.entries[0]![1]); assert.equal(array.kind, "array"); if (array.kind === "array") reject(readA.read(array.items[0])); }
        break;
      }
      case "value-own-captured-reader": {
        const captured = readA.read;
        assert.equal(Reflect.set(readA, "read", readB.read), false);
        const original = captured(rootA); assert.ok(Result.isSuccess(original));
        assert.deepEqual(tree(readA, rootA), seedTree); reject(readB.read(rootA));
        assert.equal(reader(a), readA); assert.equal(readA.read, captured);
        assert.equal(row.expected.original_membership, true); assert.equal(row.expected.substitute_accepted, false); assert.equal(row.expected.original_callbacks_preserved, true);
        break;
      }
      case "value-own-fresh-views": {
        const first = view(readA, rootA); const second = view(readA, rootA);
        assert.notEqual(first, second); assert.equal(Reflect.set(first, "kind", "null"), false);
        assert.equal(first.kind, "object"); assert.equal(second.kind, "object");
        if (first.kind === "object" && second.kind === "object") {
          assert.notEqual(first.entries, second.entries); assert.notEqual(first.entries[0], second.entries[0]);
          assert.equal(Reflect.set(first.entries, "0", []), false); assert.equal(Reflect.set(first.entries[0]!, "0", "other"), false);
          const array = view(readA, first.entries[0]![1]); assert.equal(array.kind, "array");
          if (array.kind === "array") {
            assert.equal(Reflect.set(array.items, "0", rootB), false);
            const numeric = view(readA, array.items[0]); assert.equal(numeric.kind, "number");
            if (numeric.kind === "number") assert.equal(Reflect.set(numeric.value, "decimal", "2"), false);
          }
        }
        assert.deepEqual(tree(readA, rootA), seedTree);
        assert.equal(row.expected.fresh_descriptor, true); assert.equal(row.expected.all_nested_views_frozen, true); assert.equal(row.expected.original_graph_unchanged, true);
        break;
      }
      case "value-own-input-mutation": {
        let input = "[1]"; const handle = own(a, input); input = "[2]";
        assert.equal(input, "[2]"); assert.deepEqual(tree(readA, handle), row.expected.tree); assert.equal(row.expected.graph_unchanged, true); break;
      }
      case "value-own-pure-scope": {
        const scope = Effect.runSync(Scope.make()); let operationLive = true;
        Effect.runSync(Scope.addFinalizer(scope, Effect.sync(() => { operationLive = false; })));
        Effect.runSync(Scope.close(scope, Exit.succeed(undefined)));
        assert.equal(operationLive, row.expected.operation_after_close); assert.deepEqual(tree(readA, rootA), seedTree);
        assert.deepEqual(Reflect.ownKeys(a.codec), ["parse"]); assert.equal("grant" in a.codec, row.expected.codec_implies_grant);
        assert.equal(row.expected.authentic_numeric_value, true); break;
      }
      case "value-own-numeric-service-substitution": {
        const handle = own(a, "[-0,18446744073709551615]");
        let consumerNumeric: unknown = createExactJsonNumberParser();
        consumerNumeric = { get parse(): never { return trap(); }, get read(): never { return trap(); } };
        assert.ok(consumerNumeric); // Never provided to the pure codec; no injected numeric port exists.
        assert.deepEqual(tree(readA, handle), row.expected.tree); assert.equal(row.expected.original_numeric_binding, true); break;
      }
      default: throw new Error(`unhandled frozen input scenario ${row.input.harness}`);
    }
    assert.equal(traps, 0);
    if ("caller_traps" in row.expected) assert.equal(traps, row.expected.caller_traps);
  });
}

register("values fixture and accepted numeric/scalar bytes remain independent and immutable", async () => {
  for (const [path, sha] of [
    ["tests/exact-json-value-vectors.ts", "47eeb023f116a547d5916edc782794b58583caf8921668c575660f735ae3c1b0"],
    ["src/serialization/exact-json-number-parser.ts", "099505e1b4f9890848d8a159daf75f482bd24e647ba0f01a16c711bfeeebadbc"],
    ["tests/exact-json-number-parser.test.ts", "1b75c4c5824049385e2036b720cb72c0ac40d404cafb296dba210470db9e5e7f"],
    ["tests/exact-json-number-parser-vectors.ts", "22880c130c4871b7b32371f04753a064988805cdbabe1ec73c0ce5ade71779a3"],
    ["src/serialization/exact-json-numbers.ts", "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"],
  ] as const) assert.equal(createHash("sha256").update(await readFile(path)).digest("hex"), sha);
  assert.equal(rows.length, 214); assert.equal(boundaryInputs.size, 32);
  assert.deepEqual(exactJsonValueContract.representation, ["text", "utf8_hex"]);
});

  retainedReplays.set("values", callbacks);
}
{
  const readFile = readFileAsync;
  const callbacks: (() => void | Promise<void>)[] = [];
  const register = (_title: string, run: () => void | Promise<void>): void => { callbacks.push(run); };

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
  register(`independent canonical literal: ${row.case_id}`, async () => {
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

register("canonical fixture and accepted parser/scalar bytes remain independent and immutable", () => {
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

  retainedReplays.set("serializer", callbacks);
}
const frozenPins = [
  [
    "tests/candidate-codec-api-vectors.ts",
    "6e31af128f468748bc48c0b449e92188f6d0f185ef167a2edf49f7a127614db4"
  ],
  [
    "src/serialization/exact-json-number-parser.ts",
    "099505e1b4f9890848d8a159daf75f482bd24e647ba0f01a16c711bfeeebadbc"
  ],
  [
    "src/serialization/exact-json-value.ts",
    "6e8ac7aff564ac3c488799800f457f3a0e5cb74e1b2c78fb938937355a1acffc"
  ],
  [
    "src/serialization/canonical-json.ts",
    "32030fd0eca59af701d2354a374ab91d6393d9ce4a27669433092699cb0ae681"
  ],
  [
    "src/serialization/exact-json-numbers.ts",
    "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"
  ],
  [
    "tests/exact-json-number-parser-vectors.ts",
    "22880c130c4871b7b32371f04753a064988805cdbabe1ec73c0ce5ade71779a3"
  ],
  [
    "tests/exact-json-value-vectors.ts",
    "47eeb023f116a547d5916edc782794b58583caf8921668c575660f735ae3c1b0"
  ],
  [
    "tests/canonical-json-vectors.ts",
    "0412eb2a2cba7e4c11fd2123c60eed6c945f32e413af4e3b3470eb4e2298162b"
  ],
  [
    "tests/exact-json-numbers-vectors.ts",
    "3da51631a58425a061c4f386a88ab22457af855e914775fb77233358c0c4b1e8"
  ]
] as const;

const originalPackageMetadata = {
  "name": "@healthmd/core-ts",
  "version": "0.0.0-candidate.1",
  "private": true,
  "type": "module",
  "engines": {
    "node": "24.21.0",
    "npm": "11.19.0"
  },
  "packageManager": "npm@11.19.0",
  "exports": {
    ".": {
      "types": "./dist/core/index.d.ts",
      "import": "./dist/core/index.js"
    },
    "./host-interfaces": {
      "types": "./dist/core/host-interfaces/capabilities.d.ts",
      "import": "./dist/core/host-interfaces/capabilities.js"
    },
    "./candidate/catalog": {
      "types": "./dist/core/operations/catalog.d.ts",
      "import": "./dist/core/operations/catalog.js"
    },
    "./candidate/normalize": {
      "types": "./dist/core/operations/normalize.d.ts",
      "import": "./dist/core/operations/normalize.js"
    },
    "./candidate/query": {
      "types": "./dist/core/operations/query.d.ts",
      "import": "./dist/core/operations/query.js"
    },
    "./candidate/registry": {
      "types": "./dist/core/contracts/registry.d.ts",
      "import": "./dist/core/contracts/registry.js"
    }
  },
  "files": [
    "dist/core"
  ],
  "scripts": {
    "typecheck": "tsc --project tsconfig.json",
    "build": "node scripts/build.mjs",
    "test": "node scripts/check.mjs --tests-only",
    "check:boundaries": "node scripts/check-boundaries.mjs",
    "check": "node scripts/check.mjs"
  },
  "dependencies": {
    "effect": "4.0.1"
  },
  "devDependencies": {
    "typescript": "7.0.2",
    "esbuild": "0.28.2",
    "@types/node": "24.19.1"
  },
  "overrides": {
    "undici-types": "7.24.6"
  }
};
const packageMetadata = JSON.parse(readFileSync("package.json", "utf8")) as { exports: Record<string, unknown>; dependencies: Record<string, string> };
const source = readFileSync("src/serialization/index.ts", "utf8");
const namedTypeExports = [...source.matchAll(/export type \{([^}]+)\}/g)].flatMap(match => match[1]!.split(",").map(name => name.trim())).sort();
const valueFailure = { _tag: "ExactJsonValueFailure", code: "invalid_json_value" };
function succeeded<A, E>(result: Result.Result<A, E>): A { assert.ok(Result.isSuccess(result)); return result.success; }
function fixedFailure(result: Result.Result<unknown, unknown>, expected: unknown): void { assert.ok(Result.isFailure(result)); assert.deepEqual(result.failure, expected); assert.ok(Object.isFrozen(result.failure)); }
function ownValue(factory: ExactJsonValueFactory, payload = "null"): OwnedJsonValue { return succeeded(factory.codec.parse("text", payload)); }
function encodeFactory(factory: ExactJsonValueFactory): CanonicalJsonSerializer { return succeeded(createCanonicalJsonSerializer(factory.codec, factory.readerToken)); }
for (const row of rows) {
  test(`independent candidate codec API literal: ${row.case_id}`, async () => {
    const input = typeof row.input === "object" && row.input !== null ? row.input as Record<string, unknown> : {};
    if (row.case_id === "codec-export-literal") {
      assert.deepEqual(packageMetadata.exports["./candidate/codecs"], candidateCodecApiContract.literal_entry);
      assert.equal("@healthmd/core-ts/candidate/codecs", row.input); assert.ok(!Object.keys(packageMetadata.exports).some(key => key.includes("*")));
      // Fixed runtime-only specifiers avoid looking up not-yet-emitted declarations in tsc.
      const packageSpecifier: string = "@healthmd/core-ts/candidate/codecs";
      const numberSpecifier: string = "../core/serialization/exact-json-number-parser.js";
      const valueSpecifier: string = "../core/serialization/exact-json-value.js";
      const serializerSpecifier: string = "../core/serialization/canonical-json.js";
      const scalarSpecifier: string = "../core/serialization/exact-json-numbers.js";
      const loaded = await import(packageSpecifier);
      assert.equal(import.meta.resolve(packageSpecifier), new URL("../core/serialization/index.js", import.meta.url).href);
      assert.deepEqual(Object.keys(loaded).sort(), Object.keys(candidateCodecApiContract.runtime_named_exports).sort());
      // Emitted originals share the package ESM graph; inline test-bundle copies do not.
      assert.equal(loaded.createExactJsonNumberParser, (await import(numberSpecifier)).createExactJsonNumberParser);
      assert.equal(loaded.createExactJsonCodec, (await import(valueSpecifier)).createExactJsonCodec);
      assert.equal(loaded.createCanonicalJsonSerializer, (await import(serializerSpecifier)).createCanonicalJsonSerializer);
      assert.equal(loaded.serializeExactJsonNumber, (await import(scalarSpecifier)).serializeExactJsonNumber);
      return;
    }
    if (row.case_id === "codec-root-retained") {
      assert.equal(readFileSync("src/index.ts", "utf8"), candidateCodecApiContract.original_root_index_utf8); return;
    }
    if (row.case_id === "codec-identity-single" || row.group === "identity") {
      for (const name of Object.keys(originals) as RuntimeName[]) assert.equal(Facade[name], originals[name]);
      if (row.group === "identity") { const name = String(input.facade) as RuntimeName; assert.equal(Facade[name], originals[name]); return; }
      assert.equal(packageMetadata.dependencies.effect, "4.0.1");
      assert.ok(!source.includes("function") && !source.includes("export *"));
      for (const [, bits, expected] of binary64Vectors) assert.deepEqual(succeeded(serializeExactJsonNumber("binary64", bits)), new Uint8Array(Buffer.from(expected)));
      return;
    }
    if (row.case_id === "facade-runtime-names") { assert.deepEqual(Object.keys(Facade).sort(), row.expected.names); assert.equal(runtimeNameWitness, true); return; }
    if (row.case_id === "facade-type-whitelist") { assert.deepEqual(namedTypeExports, row.expected.names); return; }
    if (row.case_id.startsWith("type-") && !["type-token-not-value", "type-factory-composition"].includes(row.case_id)) {
      assert.equal(typeWitnesses.length, 10); assert.ok(typeWitnesses.every(Boolean));
      assert.ok(namedTypeExports.includes(String(input.name))); return;
    }
    if (row.case_id.startsWith("no-export-")) { assert.equal(Object.hasOwn(Facade, String(input.name)), false); assert.equal(namedTypeExports.includes(String(input.name)), false); return; }
    if (row.case_id.startsWith("no-package-path-")) {
      const deniedSpecifier: string = String(input.package_path);
      assert.ok((candidateCodecApiContract.forbidden_package_paths as readonly string[]).includes(deniedSpecifier));
      assert.equal(Object.hasOwn(packageMetadata.exports, deniedSpecifier.replace("@healthmd/core-ts", ".")), false);
      assert.ok(!Object.keys(packageMetadata.exports).some(key => key.includes("*")));
      await assert.rejects(import(deniedSpecifier), (error: unknown) => {
        assert.ok(typeof error === "object" && error !== null && "code" in error);
        assert.equal(error.code, "ERR_PACKAGE_PATH_NOT_EXPORTED");
        return true;
      });
      return;
    }
    if (row.case_id === "original-six-entries") {
      for (const [name, entry] of Object.entries(candidateCodecApiContract.original_package_exports)) assert.deepEqual(packageMetadata.exports[name], entry);
      assert.deepEqual(Object.keys(packageMetadata.exports).sort(), [...Object.keys(candidateCodecApiContract.original_package_exports), "./candidate/codecs"].sort());
      const retainedExports = { ...packageMetadata.exports }; delete retainedExports["./candidate/codecs"];
      assert.deepEqual({ ...packageMetadata, exports: retainedExports }, originalPackageMetadata);
      return;
    }
    const a = createExactJsonCodec(); const b = createExactJsonCodec(); const encoder = encodeFactory(a);
    if (row.case_id === "type-token-not-value") { assert.deepEqual(Reflect.ownKeys(a.readerToken), []); assert.ok(Object.isFrozen(a.readerToken)); assert.equal(Object.getPrototypeOf(a.readerToken), null); return; }
    if (row.case_id === "type-factory-composition") { assert.deepEqual(succeeded(typedApi.createCanonicalJsonSerializer(a.codec, a.readerToken)).encode(ownValue(a), "serde_value_compact"), encoder.encode(ownValue(a), "serde_value_compact")); return; }
    if (row.group === "number") { const parser = createExactJsonNumberParser(); const handle = succeeded(parser.parse(input.representation, input.payload)); assert.deepEqual(succeeded(parser.read(handle)), row.expected.descriptor); return; }
    if (row.group === "value_bytes") { const handle = succeeded(a.codec.parse(input.representation, input.payload)); const bytes = succeeded(encoder.encode(handle, input.policy)); assert.equal(Buffer.from(bytes).toString("hex"), row.expected.utf8_hex); assert.equal(Buffer.from(bytes).toString("utf8"), row.expected.text); return; }
    if (row.group === "scalar") { assert.equal(Buffer.from(succeeded(serializeExactJsonNumber(input.representation, input.payload))).toString("hex"), row.expected.utf8_hex); return; }
    if (row.group === "failure") { fixedFailure(input.operation === "parse_number" ? createExactJsonNumberParser().parse(input.representation, input.payload) : a.codec.parse(input.representation, input.payload), row.expected.failure); return; }
    if (row.group === "ownership") {
      let traps = 0;
      const trap = (): never => { traps += 1; throw new Error("synthetic caller marker must stay private"); };
      const handlers: ProxyHandler<object> = { get: trap, has: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap };
      const proxy = new Proxy({}, handlers); const revoked = Proxy.revocable({}, handlers); revoked.revoke();
      let result: Result.Result<unknown, unknown>;
      switch (row.case_id) {
        case "construct-cross-token": result = createCanonicalJsonSerializer(a.codec, b.readerToken); break;
        case "construct-foreign-codec": result = createCanonicalJsonSerializer({}, a.readerToken); break;
        case "construct-foreign-token": result = createCanonicalJsonSerializer(a.codec, {}); break;
        case "construct-proxy-codec": result = createCanonicalJsonSerializer(proxy, a.readerToken); break;
        case "construct-revoked-token": result = createCanonicalJsonSerializer(a.codec, revoked.proxy); break;
        case "encode-cross-value": result = encoder.encode(ownValue(b), "serde_value_compact"); break;
        case "encode-foreign-value": result = encoder.encode({}, "serde_value_compact"); break;
        case "encode-proxy-value": result = encoder.encode(proxy, "serde_value_compact"); break;
        case "encode-revoked-value": result = encoder.encode(revoked.proxy, "serde_value_compact"); break;
        case "cross-number": { const one = createExactJsonNumberParser(); const two = createExactJsonNumberParser(); result = one.read(succeeded(two.parse("serde_value_default", "1"))); break; }
        case "invalid-policy-proxy": result = encoder.encode(ownValue(a), proxy); break;
        case "fresh-output-carriers": { const handle = ownValue(a); const first = succeeded(encoder.encode(handle, "serde_value_compact")); first[0] = 0; const second = succeeded(encoder.encode(handle, "serde_value_compact")); assert.notEqual(first, second); assert.notEqual(first.buffer, second.buffer); assert.equal(Buffer.from(second).toString("hex"), row.expected.second_utf8_hex); return; }
        default: throw new Error("unrealized owned scenario");
      }
      fixedFailure(result, row.expected.failure); assert.equal(traps, row.expected.property_traps); return;
    }
    if (row.group === "retained_corpus") {
      const key = row.case_id.slice("retained-corpus-".length);
      if (key === "scalar") {
        for (const [, bits, expected] of binary64Vectors) assert.equal(Buffer.from(succeeded(serializeExactJsonNumber("binary64", bits))).toString(), expected);
        for (const [representation, decimal] of integerVectors) assert.equal(Buffer.from(succeeded(serializeExactJsonNumber(representation, decimal))).toString(), decimal);
        for (const record of rejectedVectors) { const r = record as { representation?: unknown; bits?: unknown; decimal?: unknown } | null; const representation = r?.representation; fixedFailure(serializeExactJsonNumber(representation, representation === "binary64" || representation === "binary32" ? r?.bits : r?.decimal), { _tag: "ExactJsonNumberFailure", code: "invalid_json_number" }); }
      } else {
        const callbacks = retainedReplays.get(key); assert.ok(callbacks); assert.ok(callbacks.length >= Number(input.count));
        for (const callback of callbacks) await callback();
      }
      return;
    }
    if (row.case_id === "pure-ownership-only") {
      const scope = Effect.runSync(Scope.make()); let fakeOperationLive = true;
      Effect.runSync(Scope.addFinalizer(scope, Effect.sync(() => { fakeOperationLive = false; })));
      const handle = ownValue(a); Effect.runSync(Scope.close(scope, Exit.succeed(undefined)));
      assert.equal(fakeOperationLive, false); assert.deepEqual(succeeded(encoder.encode(handle, "serde_value_compact")), new Uint8Array(Buffer.from("null")));
      for (const name of ["grant", "source", "scope", "authority"]) assert.equal(Object.hasOwn(a, name), false);
      return;
    }
    throw new Error("unrealized facade literal");
  });
}
test("candidate facade Stage1 vector and all original codec authorities stay frozen", async () => {
  assert.equal(candidateCodecApiVectors.length, 80);
  for (const [path, expected] of frozenPins) assert.equal(createHash("sha256").update(await readFileAsync(path)).digest("hex"), expected);
});
