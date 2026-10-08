import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Result from "effect/Result";
import * as Scope from "effect/Scope";
import { captureExactJsonValueReader, createExactJsonCodec } from "../src/serialization/exact-json-value.js";
import type { CapturedExactJsonValueReader, ExactJsonValueNode, OwnedJsonValue, SourceNumericValue } from "../src/serialization/exact-json-value.js";
import { createExactJsonNumberParser } from "../src/serialization/exact-json-number-parser.js";
import { exactJsonValueContract, exactJsonValueVectors } from "./exact-json-value-vectors.js";

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
  test(`independent value literal: ${row.case_id}`, () => {
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

test("values fixture and accepted numeric/scalar bytes remain independent and immutable", async () => {
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
