import * as Schema from "effect/Schema";
import * as Result from "effect/Result";

/** Safe boundary failure; input values and schema issues never escape. */
export interface ExactValueFailure {
  readonly _tag: "ExactValueFailure";
  readonly code: "invalid_semantic_batch";
}
const failure: ExactValueFailure = Object.freeze({ _tag: "ExactValueFailure", code: "invalid_semantic_batch" });
export type ExactValueResult<A> = Result.Result<A, ExactValueFailure>;
const invalid = (): ExactValueResult<never> => Result.fail(failure);
function safe<A>(body: () => ExactValueResult<A>): ExactValueResult<A> {
  try { return body(); } catch { return invalid(); }
}

const NumberShape = Schema.Union([
  Schema.Struct({ representation: Schema.Literal("binary64"), bits: Schema.String }),
  Schema.Struct({ representation: Schema.Literal("signed_integer"), decimal: Schema.String }),
  Schema.Struct({ representation: Schema.Literal("unsigned_integer"), decimal: Schema.String }),
]);
const TimestampShape = Schema.Struct({
  epoch_seconds: Schema.String,
  nanoseconds: Schema.Number,
  source_utc_offset_seconds: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  calendar_utc_offset_seconds: Schema.Number,
});
export type ExactNumber = Schema.Schema.Type<typeof NumberShape>;
export interface ExactTimestamp {
  readonly epoch_seconds: string;
  readonly nanoseconds: number;
  readonly source_utc_offset_seconds: number | null;
  readonly calendar_utc_offset_seconds: number;
}
const numberShape = Schema.decodeUnknownResult(NumberShape, { onExcessProperty: "error" });
const timestampShape = Schema.decodeUnknownResult(TimestampShape, { onExcessProperty: "error" });

export type IntegerKind = "signed" | "unsigned" | "ordinal" | "epoch";
const limits = {
  signed: { min: -170141183460469231731687303715884105728n, max: 170141183460469231731687303715884105727n, length: 40 },
  unsigned: { min: 0n, max: 340282366920938463463374607431768211455n, length: 39 },
  ordinal: { min: 0n, max: 18446744073709551615n, length: 20 },
  epoch: { min: -9223372036854775808n, max: 9223372036854775807n, length: 20 },
} satisfies Record<IntegerKind, { min: bigint; max: bigint; length: number }>;

/** Length admission precedes scanning or bigint conversion; no precision-losing coercion. */
export function decodeCanonicalInteger(input: unknown, kind: IntegerKind): ExactValueResult<bigint> {
  return safe(() => {
    const bound = limits[kind];
    if (typeof input !== "string" || input.length === 0 || input.length > bound.length) return invalid();
    const signed = kind === "signed" || kind === "epoch";
    if (!(signed ? /^(?:0|-?[1-9][0-9]*)$/ : /^(?:0|[1-9][0-9]*)$/).test(input)) return invalid();
    const value = BigInt(input);
    return value < bound.min || value > bound.max ? invalid() : Result.succeed(value);
  });
}
export function encodeCanonicalInteger(input: bigint, kind: IntegerKind): ExactValueResult<string> {
  return safe(() => {
    if (typeof input !== "bigint") return invalid();
    const bound = limits[kind];
    // Bound before conversion, including caller-supplied huge bigints.
    if (input < bound.min || input > bound.max) return invalid();
    return Result.succeed(input.toString());
  });
}

function validBits(bits: string): boolean {
  return bits.length === 16 && /^[0-9a-f]{16}$/.test(bits)
    && ((BigInt("0x" + bits) >> 52n) & 0x7ffn) !== 0x7ffn;
}
export function decodeExactNumber(input: unknown): ExactValueResult<ExactNumber> {
  return safe<ExactNumber>(() => {
    const shape = numberShape(input);
    if (Result.isFailure(shape)) return invalid();
    const value = shape.success;
    if (value.representation === "binary64") {
      return validBits(value.bits) ? Result.succeed(value) : invalid();
    }
    const integer = decodeCanonicalInteger(value.decimal, value.representation === "signed_integer" ? "signed" : "unsigned");
    return Result.isFailure(integer) ? invalid() : Result.succeed(value);
  });
}
/** Fixed serde field order; validated decimal/bit strings are emitted without numeric conversion. */
export function encodeExactNumber(input: unknown): ExactValueResult<string> {
  return Result.map(decodeExactNumber(input), (value) => value.representation === "binary64"
    ? JSON.stringify({ representation: value.representation, bits: value.bits })
    : JSON.stringify({ representation: value.representation, decimal: value.decimal }));
}
/** Explicit finite binary64 conversion, retaining raw bits and negative zero. */
export function decodeBinary64(bits: unknown): ExactValueResult<number> {
  return safe(() => {
    if (typeof bits !== "string" || !validBits(bits)) return invalid();
    const view = new DataView(new ArrayBuffer(8));
    view.setBigUint64(0, BigInt("0x" + bits), false);
    return Result.succeed(view.getFloat64(0, false));
  });
}
export function encodeBinary64(input: number): ExactValueResult<string> {
  return safe(() => {
    if (typeof input !== "number" || !Number.isFinite(input)) return invalid();
    const view = new DataView(new ArrayBuffer(8));
    view.setFloat64(0, input, false);
    return Result.succeed(view.getBigUint64(0, false).toString(16).padStart(16, "0"));
  });
}

function validOffset(value: number): boolean {
  return Number.isInteger(value) && value >= -64800 && value <= 64800;
}
export function decodeExactTimestamp(input: unknown): ExactValueResult<ExactTimestamp> {
  return safe(() => {
    const shape = timestampShape(input);
    if (Result.isFailure(shape)) return invalid();
    const value = shape.success;
    if (Result.isFailure(decodeCanonicalInteger(value.epoch_seconds, "epoch"))
      || !Number.isInteger(value.nanoseconds) || value.nanoseconds < 0 || value.nanoseconds > 999999999
      || !validOffset(value.calendar_utc_offset_seconds)
      || (value.source_utc_offset_seconds != null && !validOffset(value.source_utc_offset_seconds))) return invalid();
    return Result.succeed({
      epoch_seconds: value.epoch_seconds,
      nanoseconds: value.nanoseconds,
      source_utc_offset_seconds: value.source_utc_offset_seconds ?? null,
      calendar_utc_offset_seconds: value.calendar_utc_offset_seconds,
    });
  });
}
export function encodeExactTimestamp(input: unknown): ExactValueResult<string> {
  return Result.map(decodeExactTimestamp(input), (value) => JSON.stringify(value));
}

/** Explicit civil ownership; Gregorian arithmetic requires no instant or timezone inference. */
export function decodeCivilDate(input: unknown): ExactValueResult<string> {
  if (typeof input !== "string" || input.length !== 10 || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(input)) return invalid();
  const year = Number(input.slice(0, 4));
  const month = Number(input.slice(5, 7));
  const day = Number(input.slice(8, 10));
  if (year < 1 || year > 9998 || month < 1 || month > 12 || day < 1) return invalid();
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day > days[month - 1]! ? invalid() : Result.succeed(input);
}
export const encodeCivilDate = decodeCivilDate;
