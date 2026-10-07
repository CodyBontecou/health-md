import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as Result from "effect/Result";
import {
  decodeExactNumber, encodeExactNumber, decodeExactTimestamp, encodeExactTimestamp,
  decodeCanonicalInteger, encodeCanonicalInteger, decodeCivilDate, encodeCivilDate,
  decodeBinary64, encodeBinary64, type ExactValueResult,
} from "../src/contracts/exact-values.js";
import { exactVectors } from "./exact-values-vectors.js";

for (const vector of exactVectors) {
  test(`exact literal: ${vector.id}`, () => {
    const decoded: ExactValueResult<unknown> = vector.codec === "number" ? decodeExactNumber(vector.input)
      : vector.codec === "timestamp" ? decodeExactTimestamp(vector.input)
      : vector.codec === "date" ? decodeCivilDate(vector.input)
      : decodeCanonicalInteger(vector.input, vector.codec);
    assert.equal(Result.isSuccess(decoded), vector.valid);
    if (Result.isFailure(decoded)) {
      assert.deepEqual(decoded.failure, { _tag: "ExactValueFailure", code: "invalid_semantic_batch" });
      return;
    }
    assert.ok(vector.encoded !== undefined);
    const encoded = vector.codec === "number" ? encodeExactNumber(vector.input)
      : vector.codec === "timestamp" ? encodeExactTimestamp(vector.input)
      : vector.codec === "date" ? encodeCivilDate(vector.input)
      : encodeCanonicalInteger(BigInt(vector.input as string), vector.codec);
    assert.ok(Result.isSuccess(encoded));
    assert.equal(encoded.success, vector.encoded);
  });
}

test("binary64 conversion preserves literal IEEE bits and signed zero", () => {
  for (const [bits, value] of [
    ["0000000000000000", 0], ["8000000000000000", -0], ["3ff0000000000000", 1],
    ["0000000000000001", 5e-324], ["7fefffffffffffff", 1.7976931348623157e308],
    ["ffefffffffffffff", -1.7976931348623157e308],
  ] as const) {
    const decoded = decodeBinary64(bits); assert.ok(Result.isSuccess(decoded));
    assert.ok(Object.is(decoded.success, value));
    const encoded = encodeBinary64(value); assert.ok(Result.isSuccess(encoded));
    assert.equal(encoded.success, bits);
  }
  for (const value of [NaN, Infinity, -Infinity]) assert.ok(Result.isFailure(encodeBinary64(value)));
});

test("bounded integer admission rejects giant lexemes before conversion", () => {
  const giant = "9".repeat(1000000);
  for (const kind of ["signed", "unsigned", "ordinal", "epoch"] as const) {
    assert.ok(Result.isFailure(decodeCanonicalInteger(giant, kind)));
    assert.ok(Result.isFailure(encodeCanonicalInteger(1n << 100000n, kind)));
  }
  assert.ok(Result.isFailure(decodeExactNumber({ representation: "unsigned_integer", decimal: giant })));
});

test("safe failures retain no untrusted shape issue or thrown accessor cause", () => {
  const marker = "synthetic-private-marker";
  const invalid = decodeExactNumber({ representation: marker, decimal: marker });
  assert.ok(Result.isFailure(invalid));
  assert.equal(JSON.stringify(invalid.failure).includes(marker), false);
  const accessor = Object.defineProperty({}, "epoch_seconds", { get() { throw new Error(marker); } });
  const thrown = decodeExactTimestamp(accessor); assert.ok(Result.isFailure(thrown));
  assert.deepEqual(thrown.failure, invalid.failure);
  assert.ok(Object.isFrozen(thrown.failure));
});

test("encoders validate rather than serializing invalid values", () => {
  assert.ok(Result.isFailure(encodeExactNumber({ representation: "binary64", bits: "7ff8000000000000" })));
  assert.ok(Result.isFailure(encodeExactTimestamp({ epoch_seconds: "0", nanoseconds: 0, calendar_utc_offset_seconds: 64801 })));
  assert.ok(Result.isFailure(encodeCivilDate("2100-02-29")));
  for (const [value, kind] of [[170141183460469231731687303715884105728n, "signed"], [-1n, "unsigned"], [18446744073709551616n, "ordinal"], [9223372036854775808n, "epoch"]] as const) {
    assert.ok(Result.isFailure(encodeCanonicalInteger(value, kind)));
  }
});

test("nonfinite/fractional timestamp fields fail independently of JSON defaults", () => {
  for (const key of ["nanoseconds", "source_utc_offset_seconds", "calendar_utc_offset_seconds"]) {
    for (const value of [NaN, Infinity, -Infinity]) {
      assert.ok(Result.isFailure(decodeExactTimestamp({ epoch_seconds: "0", nanoseconds: 0, source_utc_offset_seconds: null, calendar_utc_offset_seconds: 0, [key]: value })));
    }
  }
});

test("frozen semantic differential bytes and contained scalar facts stay authoritative", async () => {
  const bytes = await readFile("../contracts/semantic-input/v1/fixtures/differential-v1.json");
  assert.equal(createHash("sha256").update(bytes).digest("hex"), "fcdf1190d5360e1641b23fbde30ab02016624d2f3b01c70c23b5d6110ca8a439");
  const counts = { numbers: 0, timestamps: 0, dates: 0, ordinals: 0 };
  function walk(value: unknown): void {
    if (Array.isArray(value)) { for (const item of value) walk(item); return; }
    if (value === null || typeof value !== "object") return;
    const object = value as Record<string, unknown>;
    if (["binary64", "signed_integer", "unsigned_integer"].includes(String(object.representation))) {
      assert.ok(Result.isSuccess(decodeExactNumber(object))); counts.numbers++;
    }
    if ("epoch_seconds" in object) { assert.ok(Result.isSuccess(decodeExactTimestamp(object))); counts.timestamps++; }
    if ("owner_date" in object) { assert.ok(Result.isSuccess(decodeCivilDate(object.owner_date))); counts.dates++; }
    if ("source_ordinal" in object) { assert.ok(Result.isSuccess(decodeCanonicalInteger(object.source_ordinal, "ordinal"))); counts.ordinals++; }
    for (const item of Object.values(object)) walk(item);
  }
  walk(JSON.parse(bytes.toString("utf8")));
  assert.ok(Object.values(counts).every((count) => count > 0));
});
