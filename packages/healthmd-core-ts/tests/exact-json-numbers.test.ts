import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import * as Result from "effect/Result";
import { serializeExactJsonNumber } from "../src/serialization/exact-json-numbers.js";
import { binary64Vectors, integerVectors, rejectedVectors } from "./exact-json-numbers-vectors.js";

const vectorSha = "3da51631a58425a061c4f386a88ab22457af855e914775fb77233358c0c4b1e8";
function rendered(representation: unknown, payload: unknown): string {
  const result = serializeExactJsonNumber(representation, payload);
  assert.ok(Result.isSuccess(result));
  return new TextDecoder().decode(result.success);
}
for (const [id, bits, text] of binary64Vectors) {
  test(`approved finite binary64 literal: ${id}`, () => {
    const result = serializeExactJsonNumber("binary64", bits);
    assert.ok(Result.isSuccess(result));
    assert.deepEqual(result.success, new TextEncoder().encode(text));
    assert.equal(result.success.length, text.length);
    exactProperties(bits, text);
  });
}
for (const [representation, decimal] of integerVectors) {
  test(`approved ${representation} literal: ${decimal}`, () => assert.equal(rendered(representation, decimal), decimal));
}
for (const [index, record] of rejectedVectors.entries()) {
  test(`approved rejection: ${index}`, () => {
    // Records are fixture harness data; the API only receives the two primitives.
    const object = record as { representation?: unknown; bits?: unknown; decimal?: unknown } | null;
    const representation = object?.representation;
    const payload = representation === "binary64" || representation === "binary32" ? object?.bits : object?.decimal;
    const result = serializeExactJsonNumber(representation, payload);
    assert.ok(Result.isFailure(result));
    assert.deepEqual(result.failure, { _tag: "ExactJsonNumberFailure", code: "invalid_json_number" });
    assert.ok(Object.isFrozen(result.failure));
  });
}
test("primitive admission never reflects, coerces or calls hostile objects", () => {
  let calls = 0;
  const hostile = new Proxy({}, {
    get() { calls++; throw new Error("synthetic-private-marker"); },
    ownKeys() { calls++; throw new Error("synthetic-private-marker"); },
    getOwnPropertyDescriptor() { calls++; throw new Error("synthetic-private-marker"); },
    getPrototypeOf() { calls++; throw new Error("synthetic-private-marker"); },
  });
  for (const value of [hostile, () => { calls++; }, Symbol("synthetic-private-marker"), 1n, 1, undefined]) {
    assert.ok(Result.isFailure(serializeExactJsonNumber(value, "0")));
    assert.ok(Result.isFailure(serializeExactJsonNumber("binary64", value)));
  }
  assert.equal(calls, 0);
});
test("giant primitive lexemes fail length admission; success bytes have independent ownership", () => {
  const giant = "9".repeat(1000000);
  assert.ok(Result.isFailure(serializeExactJsonNumber(giant, "0")));
  for (const kind of ["binary64", "signed_integer", "unsigned_integer"]) {
    assert.ok(Result.isFailure(serializeExactJsonNumber(kind, giant)));
  }
  const first = serializeExactJsonNumber("binary64", "3ff0000000000000");
  const second = serializeExactJsonNumber("binary64", "3ff0000000000000");
  assert.ok(Result.isSuccess(first)); assert.ok(Result.isSuccess(second));
  first.success.fill(0);
  assert.equal(new TextDecoder().decode(second.success), "1.0");
  assert.equal(rendered("binary64", "3ff0000000000000"), "1.0");
});
test("preapproved vectors and immutable CODEC100 fixture remain byte-identical", async () => {
  assert.equal(createHash("sha256").update(await readFile("tests/exact-json-numbers-vectors.ts")).digest("hex"), vectorSha);
  assert.equal(createHash("sha256").update(await readFile("tests/exact-values-vectors.ts")).digest("hex"),
    "b64ca4d8bd50335a41f4d6f2ff045825f8feb3c0e91c3ce58e13715ae77ec954");
});

// Independent rational property checker: decode into per-value numerator and
// denominator, not the implementation's common subnormal units. This is a
// mathematical admission/shortestness predicate; it supplies no expected text.
type Fraction = readonly [bigint, bigint];
function binary(bits: bigint): Fraction {
  const exp = Number((bits >> 52n) & 2047n);
  const mantissa = (bits & ((1n << 52n) - 1n)) + (exp === 0 ? 0n : 1n << 52n);
  const shift = exp === 0 ? -1074 : exp - 1075;
  return shift < 0 ? [mantissa, 1n << BigInt(-shift)] : [mantissa << BigInt(shift), 1n];
}
function midpoint(a: Fraction, b: Fraction): Fraction { return [a[0] * b[1] + b[0] * a[1], 2n * a[1] * b[1]]; }
function compare(a: Fraction, b: Fraction): bigint { return a[0] * b[1] - b[0] * a[1]; }
function decimal(m: bigint, e: number): Fraction { return e < 0 ? [m, 10n ** BigInt(-e)] : [m * 10n ** BigInt(e), 1n]; }
function onGrid(f: Fraction, e: number): Fraction {
  return e < 0 ? [f[0] * 10n ** BigInt(-e), f[1]] : [f[0], f[1] * 10n ** BigInt(e)];
}
function parsed(text: string): readonly [bigint, number, number] {
  const match = /^([0-9]+)(?:\.([0-9]+))?(?:e([+-]?[0-9]+))?$/.exec(text)!;
  assert.ok(match);
  const fraction = match[2] ?? "";
  let digits = (match[1]! + fraction).replace(/^0+/, "");
  let e = Number(match[3] ?? "0") - fraction.length;
  while (digits.endsWith("0")) { digits = digits.slice(0, -1); e++; }
  return [BigInt(digits), e, digits.length];
}
function exactProperties(raw: string, text: string): void {
  const bits = BigInt("0x" + raw) & ((1n << 63n) - 1n);
  assert.equal(text.startsWith("-"), (BigInt("0x" + raw) >> 63n) === 1n);
  if (bits === 0n) return;
  const [m, e, precision] = parsed(text.replace(/^-/, ""));
  const value = binary(bits);
  const lower = midpoint(binary(bits - 1n), value);
  const upper = midpoint(value, bits === 0x7fefffffffffffffn ? [1n << 1024n, 1n] : binary(bits + 1n));
  const inclusive = (bits & 1n) === 0n;
  const emitted = decimal(m, e);
  const low = compare(emitted, lower); const high = compare(emitted, upper);
  assert.ok(inclusive ? low >= 0n && high <= 0n : low > 0n && high < 0n);
  assert.ok(precision <= 17);
  const order = precision + e - 1;
  // Examine adjacent decades too, avoiding the magnitude/carry blind spot.
  for (let digits = 1; digits < precision; digits++) {
    for (const grid of [order - digits, order - digits + 1, order - digits + 2]) {
      const l = onGrid(lower, grid); const u = onGrid(upper, grid);
      const lo = l[0] / l[1] + (l[0] % l[1] !== 0n || !inclusive ? 1n : 0n);
      const hi = u[0] / u[1] - (u[0] % u[1] === 0n && !inclusive ? 1n : 0n);
      const minimum = 10n ** BigInt(digits - 1); const maximum = 10n ** BigInt(digits) - 1n;
      assert.ok((lo > maximum || hi < minimum || lo > hi), `shorter admitted decimal for ${raw}`);
    }
  }
  // Closest decimal on the selected precision grid; exact half ties use even.
  const v = onGrid(value, e);
  const floor = v[0] / v[1];
  const selectedDistance = m * v[1] >= v[0] ? m * v[1] - v[0] : v[0] - m * v[1];
  for (const candidate of [floor, floor + 1n]) {
    const f = decimal(candidate, e);
    const l = compare(f, lower); const u = compare(f, upper);
    if (!(inclusive ? l >= 0n && u <= 0n : l > 0n && u < 0n)) continue;
    const distance = candidate * v[1] >= v[0] ? candidate * v[1] - v[0] : v[0] - candidate * v[1];
    assert.ok(selectedDistance <= distance);
    if (selectedDistance === distance && candidate !== m) assert.equal(m & 1n, 0n);
  }
  // Runtime parser used only as a round-trip predicate, never a text oracle.
  const view = new DataView(new ArrayBuffer(8)); view.setFloat64(0, Number(text), false);
  assert.equal(view.getBigUint64(0, false).toString(16).padStart(16, "0"), raw);
  assert.ok(text.length <= 25);
}
test("exact interval, shortestness and nearest-even across every finite exponent and seeded bit patterns", () => {
  let cases = 0;
  for (let exponent = 0; exponent < 2047; exponent++) {
    const bits = (BigInt(exponent) << 52n) | (exponent % 2 === 0 ? 1n : 0n);
    const raw = bits.toString(16).padStart(16, "0");
    exactProperties(raw, rendered("binary64", raw)); cases++;
  }
  let seed = 0x92f283c71d933a11n;
  for (let i = 0; i < 256; i++) {
    seed = BigInt.asUintN(64, seed * 6364136223846793005n + 1442695040888963407n);
    if (((seed >> 52n) & 2047n) === 2047n) continue;
    const raw = seed.toString(16).padStart(16, "0");
    exactProperties(raw, rendered("binary64", raw)); cases++;
  }
  assert.equal(cases, 2303);
});
