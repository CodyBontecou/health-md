import * as Result from "effect/Result";
import { captureExactJsonValueReader } from "./exact-json-value.js";
import { serializeExactJsonNumber } from "./exact-json-numbers.js";
import type { ExactJsonValueFailure } from "./exact-json-value.js";

export interface CanonicalJsonSerializer {
  readonly encode: (handle: unknown, policy: unknown) => Result.Result<Uint8Array, ExactJsonValueFailure>;
}
const failure: ExactJsonValueFailure = Object.freeze({ _tag: "ExactJsonValueFailure", code: "invalid_json_value" });
const invalid = Symbol("invalidCanonicalJson");
const maximumBytes = 1048576;
const hex = "0123456789abcdef";

/** Pure internal composition; the accepted parser authenticates both inputs without property access. */
export function createCanonicalJsonSerializer(codec: unknown, readerToken: unknown): Result.Result<CanonicalJsonSerializer, ExactJsonValueFailure> {
  const captured = captureExactJsonValueReader(codec, readerToken);
  if (Result.isFailure(captured)) return Result.fail(failure);
  const read = captured.success.read;
  const renderNumber = serializeExactJsonNumber;

  function encode(handle: unknown, policy: unknown): Result.Result<Uint8Array, ExactJsonValueFailure> {
    if (typeof policy !== "string" || policy.length > 22 || (policy !== "serde_value_compact" && policy !== "serde_value_compact_lf")) return Result.fail(failure);
    try {
      function walk(emit: (byte: number) => void): number {
        let bytes = 0;
        let nodes = 0;
        let stringBytes = 0;
        function byte(value: number): void {
          if (++bytes > maximumBytes) throw invalid;
          emit(value);
        }
        function ascii(text: string): void {
          for (let at = 0; at < text.length; at += 1) byte(text.charCodeAt(at));
        }
        function quoted(text: string): void {
          byte(34);
          for (let at = 0; at < text.length; at += 1) {
            let scalar = text.charCodeAt(at);
            if (scalar >= 0xd800 && scalar <= 0xdbff) {
              const low = text.charCodeAt(++at);
              if (!(low >= 0xdc00 && low <= 0xdfff)) throw invalid;
              scalar = 0x10000 + (scalar - 0xd800) * 1024 + low - 0xdc00;
            } else if (scalar >= 0xdc00 && scalar <= 0xdfff) throw invalid;
            const width = scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;
            stringBytes += width;
            if (stringBytes > 262144) throw invalid;
            if (scalar === 34 || scalar === 92) { byte(92); byte(scalar); }
            else if (scalar < 32) {
              byte(92);
              const short = scalar === 8 ? 98 : scalar === 9 ? 116 : scalar === 10 ? 110 : scalar === 12 ? 102 : scalar === 13 ? 114 : 0;
              if (short !== 0) byte(short);
              else { byte(117); byte(48); byte(48); byte(hex.charCodeAt(scalar >> 4)); byte(hex.charCodeAt(scalar & 15)); }
            } else if (width === 1) byte(scalar);
            else if (width === 2) { byte(0xc0 | (scalar >> 6)); byte(0x80 | (scalar & 63)); }
            else if (width === 3) { byte(0xe0 | (scalar >> 12)); byte(0x80 | ((scalar >> 6) & 63)); byte(0x80 | (scalar & 63)); }
            else { byte(0xf0 | (scalar >> 18)); byte(0x80 | ((scalar >> 12) & 63)); byte(0x80 | ((scalar >> 6) & 63)); byte(0x80 | (scalar & 63)); }
          }
          byte(34);
        }
        function visit(value: unknown, depth: number): void {
          if (++nodes > 65536) throw invalid;
          const result = read(value);
          if (Result.isFailure(result)) throw invalid;
          const node = result.success;
          switch (node.kind) {
            case "null": ascii("null"); break;
            case "boolean": ascii(node.value ? "true" : "false"); break;
            case "string": quoted(node.value); break;
            case "number": {
              const number = node.value;
              const rendered = number.class === "f64"
                ? renderNumber("binary64", number.bits)
                : renderNumber(number.class === "i64" ? "signed_integer" : "unsigned_integer", number.decimal);
              if (Result.isFailure(rendered) || rendered.success.length > 24) throw invalid;
              for (const part of rendered.success) byte(part);
              break;
            }
            case "array": {
              if (depth >= 127) throw invalid;
              byte(91);
              for (let at = 0; at < node.items.length; at += 1) {
                if (at !== 0) byte(44);
                visit(node.items[at], depth + 1);
              }
              byte(93); break;
            }
            case "object": {
              if (depth >= 127) throw invalid;
              byte(123);
              // The original reader retains the parser's UTF8-ordered entries; no enumeration or reordering.
              for (let at = 0; at < node.entries.length; at += 1) {
                if (at !== 0) byte(44);
                const entry = node.entries[at]!;
                quoted(entry[0]); byte(58); visit(entry[1], depth + 1);
              }
              byte(125); break;
            }
          }
        }
        visit(handle, 0);
        if (policy === "serde_value_compact_lf") byte(10);
        return bytes;
      }
      // Complete size admission includes escapes, exact numeric lexemes and the explicit LF.
      const size = walk(() => {});
      const output = new Uint8Array(size);
      let at = 0;
      const filled = walk(value => { output[at++] = value; });
      if (filled !== size || at !== size) throw invalid;
      return Result.succeed(output);
    } catch {
      return Result.fail(failure);
    }
  }
  return Result.succeed(Object.freeze({ encode }));
}
