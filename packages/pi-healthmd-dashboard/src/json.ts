import { parse } from "lossless-json";
import type { JsonValue } from "./model.js";

const MAX_NUMBER_TOKEN_CHARS = 1024;

export class JsonNumberToken {
  constructor(readonly token: string) {}
}

export function parseJsonNumberTokens(text: string): unknown {
  return parse(text, null, token => {
    if (token.length > MAX_NUMBER_TOKEN_CHARS) throw new Error(`JSON number token exceeds ${MAX_NUMBER_TOKEN_CHARS} characters`);
    return new JsonNumberToken(token);
  });
}

export function parseJsonLossless(text: string): JsonValue {
  return parse(text, null, token => {
    if (token.length > MAX_NUMBER_TOKEN_CHARS) throw new Error(`JSON number token exceeds ${MAX_NUMBER_TOKEN_CHARS} characters`);
    if (/[.eE]/.test(token)) {
      const number = Number(token);
      if (!Number.isFinite(number)) throw new Error("JSON number is outside the finite binary64 range");
      return number;
    }
    if (token === "-0") return -0;
    const integer = BigInt(token);
    return integer >= BigInt(Number.MIN_SAFE_INTEGER) && integer <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(integer) : integer;
  }) as JsonValue;
}

export function jsonStringify(value: unknown, space?: number): string {
  return JSON.stringify(value, (_key, item) => typeof item === "bigint" ? item.toString() : item, space) ?? "null";
}

export function utf8ByteLength(text: string): number { return Buffer.byteLength(text, "utf8"); }

export function truncateUtf8(text: string, maxBytes: number, suffix = "…[truncated]"): string {
  if (maxBytes <= 0) return "";
  if (utf8ByteLength(text) <= maxBytes) return text;
  const suffixBytes = utf8ByteLength(suffix);
  if (suffixBytes >= maxBytes) return Buffer.from(suffix).subarray(0, maxBytes).toString("utf8").replace(/\uFFFD$/u, "");
  const buffer = Buffer.from(text);
  let end = maxBytes - suffixBytes;
  while (end > 0 && (buffer[end]! & 0xc0) === 0x80) end--;
  return `${buffer.subarray(0, end).toString("utf8")}${suffix}`;
}

interface PreviewState { nodes: number; maxNodes: number; maxDepth: number; maxStringChars: number }
function preview(value: unknown, state: PreviewState, depth: number): unknown {
  if (state.nodes++ >= state.maxNodes) return "…[node limit]";
  if (typeof value === "string") return value.length <= state.maxStringChars ? value : `${value.slice(0, state.maxStringChars)}…[string truncated]`;
  if (typeof value === "bigint") return value.toString();
  if (value === null || typeof value === "number" || typeof value === "boolean" || value === undefined) return value;
  if (depth >= state.maxDepth) return Array.isArray(value) ? `[array ${value.length} items]` : "{object depth limit}";
  if (Array.isArray(value)) {
    const output: unknown[] = [];
    for (let index = 0; index < value.length && state.nodes < state.maxNodes; index++) output.push(preview(value[index], state, depth + 1));
    if (output.length < value.length) output.push(`…[${value.length - output.length} items omitted]`);
    return output;
  }
  if (typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const key in value as Record<string, unknown>) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
      if (state.nodes >= state.maxNodes) { output["…"] = "[properties omitted]"; break; }
      output[key.length <= state.maxStringChars ? key : `${key.slice(0, state.maxStringChars)}…`] = preview((value as Record<string, unknown>)[key], state, depth + 1);
    }
    return output;
  }
  return String(value);
}

export function boundedJson(value: unknown, maxBytes: number): string {
  const state: PreviewState = {
    nodes: 0,
    maxNodes: Math.max(8, Math.min(1_024, Math.floor(maxBytes / 16))),
    maxDepth: 12,
    maxStringChars: Math.max(16, Math.min(256, Math.floor(maxBytes / 32))),
  };
  return truncateUtf8(jsonStringify(preview(value, state, 0)), maxBytes);
}
