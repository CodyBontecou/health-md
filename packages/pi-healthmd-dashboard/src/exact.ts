import { boundedJson, truncateUtf8 } from "./json.js";
import type { JsonValue } from "./model.js";

export interface DecodedExactNumber {
  representation: "binary64" | "signed_integer" | "unsigned_integer";
  exactText: string;
  chartValue?: number;
  safeForChart: boolean;
}

export function decodeBinary64(bits: string): DecodedExactNumber {
  if (!/^[0-9a-f]{16}$/.test(bits)) throw new Error(`Invalid binary64 bits: ${bits}`);
  const value = Buffer.from(bits, "hex").readDoubleBE(0);
  if (!Number.isFinite(value)) throw new Error(`Non-finite binary64 is forbidden: ${bits}`);
  const exactText = Object.is(value, -0) ? "-0" : value.toString();
  return { representation: "binary64", exactText, chartValue: value, safeForChart: true };
}

export function decodeExactNumber(value: JsonValue): DecodedExactNumber | undefined {
  if (!value || Array.isArray(value) || typeof value !== "object") return undefined;
  const representation = value.representation;
  if (representation === "binary64") {
    if (typeof value.bits !== "string") throw new Error("binary64 exact number requires bits");
    return decodeBinary64(value.bits);
  }
  if (representation === "signed_integer" || representation === "unsigned_integer") {
    if (typeof value.decimal !== "string") throw new Error(`${representation} exact number requires decimal`);
    if (value.decimal.length > 40) throw new Error("Exact integer exceeds 40 characters");
    const pattern = representation === "signed_integer" ? /^(?:0|-?[1-9][0-9]*)$/ : /^(?:0|[1-9][0-9]*)$/;
    if (!pattern.test(value.decimal)) throw new Error(`Invalid ${representation}: ${value.decimal}`);
    const integer = BigInt(value.decimal);
    const safe = integer >= BigInt(Number.MIN_SAFE_INTEGER) && integer <= BigInt(Number.MAX_SAFE_INTEGER);
    return { representation, exactText: value.decimal, ...(safe ? { chartValue: Number(integer) } : {}), safeForChart: safe };
  }
  return undefined;
}

export function displayValue(value: JsonValue, maxBytes = 2_000): string {
  try {
    const exact = decodeExactNumber(value);
    if (exact) return exact.exactText;
  } catch { /* Invalid exact values remain safely displayable and are reported by validation. */ }
  if (typeof value === "string") return truncateUtf8(value, maxBytes, "…[value truncated]");
  if (typeof value === "number") return Object.is(value, -0) ? "-0" : String(value);
  if (typeof value === "bigint" || typeof value === "boolean" || value === null) return String(value);
  return boundedJson(value, maxBytes);
}

export function numericValue(value: JsonValue): number | undefined {
  try {
    const exact = decodeExactNumber(value);
    if (exact) return exact.chartValue;
  } catch { return undefined; }
  if (typeof value === "bigint") return value >= BigInt(Number.MIN_SAFE_INTEGER) && value <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(value) : undefined;
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
