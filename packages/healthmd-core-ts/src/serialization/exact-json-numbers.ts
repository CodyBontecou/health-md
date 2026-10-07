import * as Result from "effect/Result";

export interface ExactJsonNumberFailure {
  readonly _tag: "ExactJsonNumberFailure";
  readonly code: "invalid_json_number";
}
const failure: ExactJsonNumberFailure = Object.freeze({ _tag: "ExactJsonNumberFailure", code: "invalid_json_number" });
export type ExactJsonNumberResult = Result.Result<Uint8Array, ExactJsonNumberFailure>;
const invalid = (): ExactJsonNumberResult => Result.fail(failure);

// Original exact-integer interval search, not a translation of zmij's tables.
// Finite f64 magnitudes are integers in units 2^-1074. Midpoint bounds use
// denominator 2^1075, so subnormal transitions and unequal power-of-two gaps
// follow directly from adjacent encodings. The virtual max-finite successor
// is 2^1024; its overflow midpoint is excluded (max-finite is odd).
const denominator = 1n << 1075n;
const fractionMask = (1n << 52n) - 1n;
const magnitudeMask = (1n << 63n) - 1n;
const maximum = 0x7fefffffffffffffn;
const powers: readonly bigint[] = (() => {
  const values = [1n];
  // floor decimal order [-324,308], 17-digit grid => exponent >= -340.
  for (let i = 1; i <= 340; i++) values.push(values[i - 1]! * 10n);
  return values;
})();
function units(bits: bigint): bigint {
  const exponent = Number(bits >> 52n);
  const fraction = bits & fractionMask;
  return exponent === 0 ? fraction : ((1n << 52n) + fraction) << BigInt(exponent - 1);
}
function decimalOrder(value: bigint): number {
  let lo = -324;
  let hi = 309; // exclusive; every finite magnitude is below 10^309.
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    const atLeast = mid < 0 ? value * powers[-mid]! >= denominator : value >= denominator * powers[mid]!;
    if (atLeast) lo = mid; else hi = mid;
  }
  return lo;
}
function scale(value: bigint, exponent: number): bigint {
  return exponent < 0 ? value * powers[-exponent]! : value;
}
function gridDenominator(exponent: number): bigint {
  return exponent < 0 ? denominator : denominator * powers[exponent]!;
}
function nearest(numerator: bigint, divisor: bigint): bigint {
  const quotient = numerator / divisor;
  const twiceRemainder = (numerator % divisor) * 2n;
  return quotient + (twiceRemainder > divisor || (twiceRemainder === divisor && (quotient & 1n) !== 0n) ? 1n : 0n);
}
function lexical(significand: bigint, exponent: number): string {
  // A carry such as 10^n is intentionally admitted before normalization.
  while (significand % 10n === 0n) { significand /= 10n; exponent++; }
  const digits = significand.toString();
  const order = digits.length + exponent - 1;
  if (order < -5 || order > 15) {
    return digits[0]! + (digits.length === 1 ? "" : "." + digits.slice(1)) + "e" + (order >= 0 ? "+" : "") + order.toString();
  }
  const point = digits.length + exponent;
  if (point <= 0) return "0." + "0".repeat(-point) + digits;
  if (point >= digits.length) return digits + "0".repeat(point - digits.length) + ".0";
  return digits.slice(0, point) + "." + digits.slice(point);
}
function floatLexeme(raw: bigint): string | undefined {
  const bits = raw & magnitudeMask;
  const sign = raw >> 63n === 0n ? "" : "-";
  if (bits === 0n) return sign + "0.0";
  const value = units(bits);
  const lower = value + units(bits - 1n);
  const upper = value + (bits === maximum ? 1n << 2098n : units(bits + 1n));
  const target = value * 2n;
  const inclusive = (bits & 1n) === 0n;
  const order = decimalOrder(target);
  // Every admitted decimal has an integer significand on one of these grids.
  // Test coarsest first; binary64 has a round-tripping decimal with <=17 digits.
  // A decimal decade crossed by the interval is covered by M=10^n (carry),
  // or M=10^(n-1), rather than restricting M to a strict n-digit range.
  for (let count = 1; count <= 17; count++) {
    const exponent = order - count + 1;
    const divisor = gridDenominator(exponent);
    const low = scale(lower, exponent);
    const high = scale(upper, exponent);
    const min = low / divisor + (low % divisor !== 0n || !inclusive ? 1n : 0n);
    const max = high / divisor - (high % divisor === 0n && !inclusive ? 1n : 0n);
    if (min > max) continue;
    const closest = nearest(scale(target, exponent), divisor);
    const selected = closest < min ? min : closest > max ? max : closest;
    return sign + lexical(selected, exponent);
  }
  return undefined; // Defensive fixed failure; not reachable for a finite f64.
}
function ascii(text: string): Uint8Array {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i);
  return bytes;
}
/** Private finite-f64/i64/u64 boundary. Primitive admission performs no caller coercion or reflection. */
export function serializeExactJsonNumber(representation: unknown, payload: unknown): ExactJsonNumberResult {
  if (typeof representation !== "string" || representation.length > 16 || typeof payload !== "string") return invalid();
  if (representation === "binary64") {
    if (payload.length !== 16 || !/^[0-9a-f]{16}$/.test(payload)) return invalid();
    const raw = BigInt("0x" + payload);
    if (((raw >> 52n) & 0x7ffn) === 0x7ffn) return invalid();
    const text = floatLexeme(raw);
    return text === undefined ? invalid() : Result.succeed(ascii(text));
  }
  if (representation !== "signed_integer" && representation !== "unsigned_integer") return invalid();
  if (payload.length === 0 || payload.length > 20) return invalid();
  const signed = representation === "signed_integer";
  if (!(signed ? /^(?:0|-?[1-9][0-9]*)$/ : /^(?:0|[1-9][0-9]*)$/).test(payload)) return invalid();
  const value = BigInt(payload);
  if (signed ? value < -9223372036854775808n || value > 9223372036854775807n : value > 18446744073709551615n) return invalid();
  return Result.succeed(ascii(payload));
}
