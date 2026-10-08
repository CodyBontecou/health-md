import * as Result from "effect/Result";

const ownedNumberBrand: unique symbol = Symbol("ownedJsonNumber");
export interface OwnedJsonNumber { readonly [ownedNumberBrand]: true }
export interface ExactJsonNumberFailure {
  readonly _tag: "ExactJsonNumberFailure";
  readonly code: "invalid_json_number";
}
export type SourceNumber =
  | { readonly class: "i64" | "u64"; readonly decimal: string }
  | { readonly class: "f64"; readonly bits: string };
export interface ExactJsonNumberParser {
  readonly parse: (representation: unknown, payload: unknown) => Result.Result<OwnedJsonNumber, ExactJsonNumberFailure>;
  readonly read: (handle: unknown) => Result.Result<SourceNumber, ExactJsonNumberFailure>;
}
const failure: ExactJsonNumberFailure = Object.freeze({ _tag: "ExactJsonNumberFailure", code: "invalid_json_number" });
const u64Max = 18446744073709551615n;
const i64Magnitude = 9223372036854775808n;
const i32Max = 2147483647;
const digit = (text: string, at: number): boolean => {
  const code = text.charCodeAt(at);
  return code >= 48 && code <= 57;
};

function fromBits(bits: bigint): number {
  const view = new DataView(new ArrayBuffer(8));
  view.setBigUint64(0, bits, false);
  return view.getFloat64(0, false);
}
function floatDescriptor(value: number): SourceNumber {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value, false);
  return { class: "f64", bits: view.getBigUint64(0, false).toString(16).padStart(16, "0") };
}
// Explicit nearest/ties-even u64 conversion, before the separately rounded operation.
// No whole-token decimal-to-Number conversion participates in source admission.
function roundedU64(value: bigint): number {
  if (value === 0n) return 0;
  let exponent = -1;
  for (let rest = value; rest !== 0n; rest >>= 1n) exponent += 1;
  let significand: bigint;
  if (exponent <= 52) {
    significand = value << BigInt(52 - exponent);
  } else {
    const shift = BigInt(exponent - 52);
    significand = value >> shift;
    const remainder = value - (significand << shift);
    const half = 1n << (shift - 1n);
    if (remainder > half || (remainder === half && (significand & 1n) !== 0n)) significand += 1n;
    if (significand === (1n << 53n)) { significand >>= 1n; exponent += 1; }
  }
  return fromBits((BigInt(exponent + 1023) << 52n) | (significand - (1n << 52n)));
}

function parsed(text: string): SourceNumber | undefined {
  const negative = text[0] === "-";
  const start = negative ? 1 : 0;
  let cursor = start;
  if (text[cursor] === "0") {
    cursor += 1;
    if (digit(text, cursor)) return undefined;
  } else {
    const first = text.charCodeAt(cursor);
    if (first < 49 || first > 57 || !digit(text, cursor)) return undefined;
    do { cursor += 1; } while (digit(text, cursor));
  }
  const integerEnd = cursor;
  let fractionStart = cursor;
  let fractionEnd = cursor;
  const decimal = text[cursor] === ".";
  if (decimal) {
    cursor += 1; fractionStart = cursor;
    if (!digit(text, cursor)) return undefined;
    do { cursor += 1; } while (digit(text, cursor));
    fractionEnd = cursor;
  }
  const hasExponent = text[cursor] === "e" || text[cursor] === "E";
  let exponentNegative = false;
  let exponentStart = cursor;
  if (hasExponent) {
    cursor += 1;
    exponentNegative = text[cursor] === "-";
    if (text[cursor] === "-" || text[cursor] === "+") cursor += 1;
    exponentStart = cursor;
    if (!digit(text, cursor)) return undefined;
    do { cursor += 1; } while (digit(text, cursor));
  }
  if (cursor !== text.length) return undefined;

  let significand = 0n;
  let exponent = 0;
  let integerOverflow = false;
  for (let at = start; at < integerEnd; at += 1) {
    const next = significand * 10n + BigInt(text.charCodeAt(at) - 48);
    if (next > u64Max) {
      integerOverflow = true;
      // Source leaves the overflowing digit for parse_long_integer to consume.
      exponent = integerEnd - at;
      break;
    }
    significand = next;
  }
  if (!integerOverflow && !decimal && !hasExponent) {
    if (!negative) return { class: "u64", decimal: significand.toString() };
    if (significand > 0n && significand <= i64Magnitude) return { class: "i64", decimal: `-${significand}` };
    return floatDescriptor(-roundedU64(significand));
  }
  for (let at = fractionStart; at < fractionEnd; at += 1) {
    const next = significand * 10n + BigInt(text.charCodeAt(at) - 48);
    // Decimal overflow discards this digit and all following fractional digits;
    // those discarded digits do not decrement the source exponent.
    if (next > u64Max) break;
    significand = next;
    exponent -= 1;
  }
  if (hasExponent) {
    let magnitude = 0;
    for (let at = exponentStart; at < text.length; at += 1) {
      const next = magnitude * 10 + text.charCodeAt(at) - 48;
      if (next > i32Max) {
        if (significand !== 0n && !exponentNegative) return undefined;
        return floatDescriptor(negative ? -0 : 0);
      }
      magnitude = next;
    }
    exponent = exponentNegative ? Math.max(-2147483648, exponent - magnitude) : Math.min(i32Max, exponent + magnitude);
  }
  let value = roundedU64(significand);
  // Default serde source applies a rounded POW10 then one binary64 operation.
  // For enormous negative exponents, this terminates once the value is zero.
  while (Math.abs(exponent) > 308) {
    if (value === 0) return floatDescriptor(negative ? -0 : 0);
    if (exponent >= 0) return undefined;
    value /= pow10[308]!;
    exponent += 308;
  }
  const power = pow10[Math.abs(exponent)]!;
  value = exponent >= 0 ? value * power : value / power;
  if (!Number.isFinite(value)) return undefined;
  return floatDescriptor(negative ? -value : value);
}

/** Private pure codec factory. Handles confer numeric authenticity, never data authority. */
export function createExactJsonNumberParser(): ExactJsonNumberParser {
  const owned = new WeakMap<object, SourceNumber>();
  const read: ExactJsonNumberParser["read"] = handle => {
    // WeakMap membership does not invoke Proxy traps or inspect caller properties.
    if ((typeof handle !== "object" || handle === null) && typeof handle !== "function") return Result.fail(failure);
    const descriptor = owned.get(handle);
    if (descriptor === undefined) return Result.fail(failure);
    return Result.succeed(Object.freeze({ ...descriptor }));
  };
  const parse: ExactJsonNumberParser["parse"] = (representation, payload) => {
    if (representation !== "serde_value_default" || typeof payload !== "string" || payload.length === 0 || payload.length > 1024) return Result.fail(failure);
    // The complete grammar admits only ASCII: code-unit and UTF8 bounds coincide.
    const descriptor = parsed(payload);
    if (descriptor === undefined) return Result.fail(failure);
    const handle = Object.freeze(Object.create(null)) as OwnedJsonNumber;
    owned.set(handle, Object.freeze(descriptor));
    return Result.succeed(handle);
  };
  return Object.freeze({ parse, read });
}

// Transcribed retained de.rs POW10[0..308], independently reviewed before code.
const pow10: readonly number[] = Object.freeze([
1e000, 1e001, 1e002, 1e003, 1e004, 1e005, 1e006, 1e007, 1e008, 1e009, //
    1e010, 1e011, 1e012, 1e013, 1e014, 1e015, 1e016, 1e017, 1e018, 1e019, //
    1e020, 1e021, 1e022, 1e023, 1e024, 1e025, 1e026, 1e027, 1e028, 1e029, //
    1e030, 1e031, 1e032, 1e033, 1e034, 1e035, 1e036, 1e037, 1e038, 1e039, //
    1e040, 1e041, 1e042, 1e043, 1e044, 1e045, 1e046, 1e047, 1e048, 1e049, //
    1e050, 1e051, 1e052, 1e053, 1e054, 1e055, 1e056, 1e057, 1e058, 1e059, //
    1e060, 1e061, 1e062, 1e063, 1e064, 1e065, 1e066, 1e067, 1e068, 1e069, //
    1e070, 1e071, 1e072, 1e073, 1e074, 1e075, 1e076, 1e077, 1e078, 1e079, //
    1e080, 1e081, 1e082, 1e083, 1e084, 1e085, 1e086, 1e087, 1e088, 1e089, //
    1e090, 1e091, 1e092, 1e093, 1e094, 1e095, 1e096, 1e097, 1e098, 1e099, //
    1e100, 1e101, 1e102, 1e103, 1e104, 1e105, 1e106, 1e107, 1e108, 1e109, //
    1e110, 1e111, 1e112, 1e113, 1e114, 1e115, 1e116, 1e117, 1e118, 1e119, //
    1e120, 1e121, 1e122, 1e123, 1e124, 1e125, 1e126, 1e127, 1e128, 1e129, //
    1e130, 1e131, 1e132, 1e133, 1e134, 1e135, 1e136, 1e137, 1e138, 1e139, //
    1e140, 1e141, 1e142, 1e143, 1e144, 1e145, 1e146, 1e147, 1e148, 1e149, //
    1e150, 1e151, 1e152, 1e153, 1e154, 1e155, 1e156, 1e157, 1e158, 1e159, //
    1e160, 1e161, 1e162, 1e163, 1e164, 1e165, 1e166, 1e167, 1e168, 1e169, //
    1e170, 1e171, 1e172, 1e173, 1e174, 1e175, 1e176, 1e177, 1e178, 1e179, //
    1e180, 1e181, 1e182, 1e183, 1e184, 1e185, 1e186, 1e187, 1e188, 1e189, //
    1e190, 1e191, 1e192, 1e193, 1e194, 1e195, 1e196, 1e197, 1e198, 1e199, //
    1e200, 1e201, 1e202, 1e203, 1e204, 1e205, 1e206, 1e207, 1e208, 1e209, //
    1e210, 1e211, 1e212, 1e213, 1e214, 1e215, 1e216, 1e217, 1e218, 1e219, //
    1e220, 1e221, 1e222, 1e223, 1e224, 1e225, 1e226, 1e227, 1e228, 1e229, //
    1e230, 1e231, 1e232, 1e233, 1e234, 1e235, 1e236, 1e237, 1e238, 1e239, //
    1e240, 1e241, 1e242, 1e243, 1e244, 1e245, 1e246, 1e247, 1e248, 1e249, //
    1e250, 1e251, 1e252, 1e253, 1e254, 1e255, 1e256, 1e257, 1e258, 1e259, //
    1e260, 1e261, 1e262, 1e263, 1e264, 1e265, 1e266, 1e267, 1e268, 1e269, //
    1e270, 1e271, 1e272, 1e273, 1e274, 1e275, 1e276, 1e277, 1e278, 1e279, //
    1e280, 1e281, 1e282, 1e283, 1e284, 1e285, 1e286, 1e287, 1e288, 1e289, //
    1e290, 1e291, 1e292, 1e293, 1e294, 1e295, 1e296, 1e297, 1e298, 1e299, //
    1e300, 1e301, 1e302, 1e303, 1e304, 1e305, 1e306, 1e307, 1e308,
]);
