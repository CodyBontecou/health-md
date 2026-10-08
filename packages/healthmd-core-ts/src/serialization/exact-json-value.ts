import * as Result from "effect/Result";
import { createExactJsonNumberParser } from "./exact-json-number-parser.js";
import type { SourceNumber } from "./exact-json-number-parser.js";

const valueBrand: unique symbol = Symbol("ownedJsonValue");
const codecBrand: unique symbol = Symbol("ownedJsonValueCodec");
const readerBrand: unique symbol = Symbol("ownedJsonValueReader");
export interface OwnedJsonValue { readonly [valueBrand]: true }
export interface OwnedJsonValueReaderToken { readonly [readerBrand]: true }
export interface ExactJsonValueFailure { readonly _tag: "ExactJsonValueFailure"; readonly code: "invalid_json_value" }
export type SourceNumericValue = SourceNumber;
export type ExactJsonValueNode =
  | { readonly kind: "null" }
  | { readonly kind: "boolean"; readonly value: boolean }
  | { readonly kind: "string"; readonly value: string }
  | { readonly kind: "number"; readonly value: SourceNumericValue }
  | { readonly kind: "array"; readonly items: readonly OwnedJsonValue[] }
  | { readonly kind: "object"; readonly entries: readonly (readonly [string, OwnedJsonValue])[] };
export interface OwnedJsonValueCodec {
  readonly [codecBrand]: true;
  readonly parse: (representation: unknown, payload: unknown) => Result.Result<OwnedJsonValue, ExactJsonValueFailure>;
}
export interface CapturedExactJsonValueReader {
  readonly read: (handle: unknown) => Result.Result<ExactJsonValueNode, ExactJsonValueFailure>;
}
export interface ExactJsonValueFactory { readonly codec: OwnedJsonValueCodec; readonly readerToken: OwnedJsonValueReaderToken }

type Node =
  | { readonly kind: "null" }
  | { readonly kind: "boolean"; readonly value: boolean }
  | { readonly kind: "string"; readonly value: string }
  | { readonly kind: "number"; readonly value: SourceNumber }
  | { readonly kind: "array"; readonly items: readonly Node[] }
  | { readonly kind: "object"; readonly entries: readonly (readonly [string, Node])[] };
interface ReaderBinding { readonly token: OwnedJsonValueReaderToken; readonly reader: CapturedExactJsonValueReader }
const codecs = new WeakMap<object, ReaderBinding>();
const tokens = new WeakMap<object, ReaderBinding>();
const failure: ExactJsonValueFailure = Object.freeze({ _tag: "ExactJsonValueFailure", code: "invalid_json_value" });
const invalid = Symbol("invalidJsonValue");
const maxBytes = 1048576;
const maxStrings = 262144;
const rawKey = "$serde_json::private::RawValue";
const objectLike = (value: unknown): value is object => (typeof value === "object" && value !== null) || typeof value === "function";

/** Strict scalar validation and byte admission, before encoding/allocation. */
function utf8Length(text: string, limit: number): number {
  let bytes = 0;
  for (let at = 0; at < text.length; at += 1) {
    const c = text.charCodeAt(at);
    if (c <= 0x7f) bytes += 1;
    else if (c <= 0x7ff) bytes += 2;
    else if (c >= 0xd800 && c <= 0xdbff) {
      const low = text.charCodeAt(++at);
      if (!(low >= 0xdc00 && low <= 0xdfff)) throw invalid;
      bytes += 4;
    } else {
      if (c >= 0xdc00 && c <= 0xdfff) throw invalid;
      bytes += 3;
    }
    if (bytes > limit) throw invalid;
  }
  return bytes;
}
function hexDigit(c: number): number {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 97 && c <= 102) return c - 87;
  return -1;
}
function decodeHex(text: string): string {
  if (text.length > 2 * maxBytes || text.length % 2 !== 0) throw invalid;
  // Validate the entire primitive before allocating its byte carrier.
  for (let at = 0; at < text.length; at += 1) if (hexDigit(text.charCodeAt(at)) < 0) throw invalid;
  const bytes = new Uint8Array(text.length / 2);
  for (let at = 0; at < bytes.length; at += 1) bytes[at] = hexDigit(text.charCodeAt(2 * at)) * 16 + hexDigit(text.charCodeAt(2 * at + 1));
  const pieces: string[] = [];
  for (let at = 0; at < bytes.length;) {
    const first = bytes[at++]!;
    let value: number; let remaining: number; let minimum: number;
    if (first < 0x80) { value = first; remaining = 0; minimum = 0; }
    else if (first >= 0xc2 && first <= 0xdf) { value = first & 31; remaining = 1; minimum = 0x80; }
    else if (first >= 0xe0 && first <= 0xef) { value = first & 15; remaining = 2; minimum = 0x800; }
    else if (first >= 0xf0 && first <= 0xf4) { value = first & 7; remaining = 3; minimum = 0x10000; }
    else throw invalid;
    for (let n = 0; n < remaining; n += 1) {
      const next = bytes[at++];
      if (next === undefined || next < 0x80 || next > 0xbf) throw invalid;
      value = value * 64 + (next & 63);
    }
    if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) throw invalid;
    pieces.push(String.fromCodePoint(value));
  }
  return pieces.join("");
}
// Rust String ordering on valid scalars equals UTF8 lexicographic ordering.
// Lexical scanning is linear; key ordering is a separately bounded sort.
function keyOrder(a: string, b: string): number {
  let x = 0; let y = 0;
  while (x < a.length && y < b.length) {
    const ca = a.codePointAt(x)!; const cb = b.codePointAt(y)!;
    if (ca !== cb) return ca < cb ? -1 : 1;
    x += ca > 0xffff ? 2 : 1; y += cb > 0xffff ? 2 : 1;
  }
  return x === a.length ? (y === b.length ? 0 : -1) : 1;
}

/** Internal composition: no caller reader property/function is inspected. */
export function captureExactJsonValueReader(codec: unknown, readerToken: unknown): Result.Result<CapturedExactJsonValueReader, ExactJsonValueFailure> {
  if (!objectLike(codec)) return Result.fail(failure);
  const binding = codecs.get(codec);
  if (binding === undefined || !objectLike(readerToken) || tokens.get(readerToken) !== binding) return Result.fail(failure);
  return Result.succeed(binding.reader);
}

/** Pure internal factory. Consumer facades expose parse, never the reader token. */
export function createExactJsonCodec(): ExactJsonValueFactory {
  const numeric = createExactJsonNumberParser();
  const parseNumber = numeric.parse;
  const readNumber = numeric.read;
  const nodes = new WeakMap<object, Node>();
  const handles = new WeakMap<object, OwnedJsonValue>();
  function handle(node: Node): OwnedJsonValue {
    const prior = handles.get(node);
    if (prior !== undefined) return prior;
    const value = Object.freeze(Object.create(null)) as OwnedJsonValue;
    handles.set(node, value); nodes.set(value, node);
    return value;
  }
  const read: CapturedExactJsonValueReader["read"] = value => {
    if (!objectLike(value)) return Result.fail(failure);
    const node = nodes.get(value);
    if (node === undefined) return Result.fail(failure);
    let view: ExactJsonValueNode;
    switch (node.kind) {
      case "array": view = { kind: "array", items: Object.freeze(node.items.map(handle)) }; break;
      case "object": view = { kind: "object", entries: Object.freeze(node.entries.map(([key, child]) => Object.freeze([key, handle(child)] as const))) }; break;
      case "number": view = { kind: "number", value: Object.freeze({ ...node.value }) }; break;
      default: view = { ...node };
    }
    return Result.succeed(Object.freeze(view));
  };
  const parse: OwnedJsonValueCodec["parse"] = (representation, payload) => {
    if ((representation !== "text" && representation !== "utf8_hex") || typeof payload !== "string") return Result.fail(failure);
    if (payload.length > (representation === "text" ? maxBytes : 2 * maxBytes)) return Result.fail(failure);
    try {
      const text = representation === "text" ? payload : decodeHex(payload);
      utf8Length(text, maxBytes);
      // All recursive carrier passes share these counters. No private source reset.
      const budget = { nodes: 0, strings: 0, work: 0 };
      function parseInput(input: string, activeDepth: number): Node {
        budget.work += utf8Length(input, maxBytes - budget.work);
        let at = 0;
        function whitespace(): void {
          while (input[at] === " " || input[at] === "\t" || input[at] === "\r" || input[at] === "\n") at += 1;
        }
        function chargeString(bytes: number): void {
          budget.strings += bytes;
          if (budget.strings > maxStrings) throw invalid;
        }
        function unicodeUnit(): number {
          let unit = 0;
          for (let n = 0; n < 4; n += 1) {
            const c = input.charCodeAt(at++);
            const d = c >= 65 && c <= 70 ? c - 55 : hexDigit(c);
            if (d < 0) throw invalid;
            unit = unit * 16 + d;
          }
          return unit;
        }
        function string(): string {
          if (input[at++] !== '"') throw invalid;
          const pieces: string[] = [];
          let start = at;
          while (at < input.length) {
            const c = input.charCodeAt(at);
            if (c === 34) { pieces.push(input.slice(start, at)); at += 1; return pieces.join(""); }
            if (c === 92) {
              pieces.push(input.slice(start, at)); at += 1;
              const escape = input[at++];
              const simple = escape === '"' ? '"' : escape === "\\" ? "\\" : escape === "/" ? "/" : escape === "b" ? "\b" : escape === "f" ? "\f" : escape === "n" ? "\n" : escape === "r" ? "\r" : escape === "t" ? "\t" : undefined;
              if (simple !== undefined) { chargeString(1); pieces.push(simple); }
              else if (escape === "u") {
                let scalar = unicodeUnit();
                if (scalar >= 0xd800 && scalar <= 0xdbff) {
                  if (input[at++] !== "\\" || input[at++] !== "u") throw invalid;
                  const low = unicodeUnit();
                  if (low < 0xdc00 || low > 0xdfff) throw invalid;
                  scalar = 0x10000 + (scalar - 0xd800) * 1024 + low - 0xdc00;
                } else if (scalar >= 0xdc00 && scalar <= 0xdfff) throw invalid;
                chargeString(scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4);
                pieces.push(String.fromCodePoint(scalar));
              } else throw invalid;
              start = at;
            } else {
              if (c < 32) throw invalid;
              chargeString(c < 0x80 ? 1 : c < 0x800 ? 2 : c >= 0xd800 && c <= 0xdbff ? 4 : 3);
              at += c >= 0xd800 && c <= 0xdbff ? 2 : 1;
            }
          }
          throw invalid;
        }
        function value(depth: number): Node {
          whitespace(); budget.nodes += 1;
          if (budget.nodes > 65536) throw invalid;
          const first = input[at];
          if (first === '"') return Object.freeze({ kind: "string", value: string() });
          if (first === "n" && input.slice(at, at + 4) === "null") { at += 4; return Object.freeze({ kind: "null" }); }
          if (first === "t" && input.slice(at, at + 4) === "true") { at += 4; return Object.freeze({ kind: "boolean", value: true }); }
          if (first === "f" && input.slice(at, at + 5) === "false") { at += 5; return Object.freeze({ kind: "boolean", value: false }); }
          if (first === "[" || first === "{") {
            const inside = depth + 1;
            if (inside > 127) throw invalid;
            at += 1; whitespace();
            if (first === "[") {
              const items: Node[] = [];
              if (input[at] === "]") { at += 1; return Object.freeze({ kind: "array", items: Object.freeze(items) }); }
              while (true) {
                items.push(value(inside)); whitespace();
                if (input[at] === "]") { at += 1; break; }
                if (input[at++] !== ",") throw invalid;
              }
              return Object.freeze({ kind: "array", items: Object.freeze(items) });
            }
            const entries = new Map<string, Node>();
            if (input[at] === "}") { at += 1; return Object.freeze({ kind: "object", entries: Object.freeze([]) }); }
            let firstKey = true;
            while (true) {
              whitespace(); const key = string(); whitespace();
              if (input[at++] !== ":") throw invalid;
              const child = value(inside);
              // Actual std/raw_value Value visitor interprets ONLY its first decoded key.
              if (firstKey && key === rawKey) {
                if (child.kind !== "string") throw invalid;
                const inner = parseInput(child.value, inside);
                whitespace(); if (input[at++] !== "}") throw invalid;
                return inner;
              }
              firstKey = false; entries.set(key, child); whitespace();
              if (input[at] === "}") { at += 1; break; }
              if (input[at++] !== ",") throw invalid;
            }
            const ordered = [...entries].sort(([a], [b]) => keyOrder(a, b)).map(([key, node]) => Object.freeze([key, node] as const));
            return Object.freeze({ kind: "object", entries: Object.freeze(ordered) });
          }
          if (first === "-" || (first !== undefined && first >= "0" && first <= "9")) {
            const start = at;
            while (at < input.length) {
              const c = input[at]!;
              if (!((c >= "0" && c <= "9") || c === "-" || c === "+" || c === "." || c === "e" || c === "E")) break;
              if (at - start >= 1024) throw invalid;
              at += 1;
            }
            const number = parseNumber("serde_value_default", input.slice(start, at));
            if (Result.isFailure(number)) throw invalid;
            const descriptor = readNumber(number.success);
            if (Result.isFailure(descriptor)) throw invalid;
            return Object.freeze({ kind: "number", value: Object.freeze({ ...descriptor.success }) });
          }
          throw invalid;
        }
        const root = value(activeDepth); whitespace();
        if (at !== input.length) throw invalid;
        return root;
      }
      // No caller-visible handle exists until the entire JSON text and all budgets pass.
      return Result.succeed(handle(parseInput(text, 0)));
    } catch { return Result.fail(failure); }
  };
  const codec = Object.freeze({ parse }) as OwnedJsonValueCodec;
  const token = Object.freeze(Object.create(null)) as OwnedJsonValueReaderToken;
  const binding = Object.freeze({ token, reader: Object.freeze({ read }) });
  codecs.set(codec, binding); tokens.set(token, binding);
  return Object.freeze({ codec, readerToken: token });
}
