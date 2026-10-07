import assert from "node:assert/strict";
import test from "node:test";
import * as Result from "effect/Result";
import { createPersonalRecordCodec, type PersonalAuthorizationDescriptor, type PersonalCodecFailure, type TrustedPersonalCodecContext } from "../src/contracts/personal-slice.js";
import { acceptedContractCaseMap, personalRecordVectors, personalMutationVectors, personalMalformedJsonVectors,
  personalRawIntegerTokenNegatives, personalAdditionalPositiveMutations } from "./personal-codecs-vectors.js";

function authority() {
  let calls = 0, permitted = true, title = false;
  const descriptors: PersonalAuthorizationDescriptor[] = [];
  const context: TrustedPersonalCodecContext = {
    authorize(descriptor) {
      calls++; descriptors.push(descriptor);
      // Synthetic trusted catalog, independent of caller app_class; no authentication claim.
      const catalog = descriptor.payload_kind === "usage_aggregate" ? "browser"
        : descriptor.payload_kind === "foreground_app_session" ? "non_browser" : null;
      const binding = descriptor.lineage;
      return { permitted: permitted && binding.dataset_id === "synthetic-dataset-a"
        && (binding.source_id === "synthetic-source-a" || binding.source_id === "synthetic-source-b")
        && binding.source_revision === "synthetic-source-contract1" && binding.purpose === "synthetic_local_collection",
        authority_binding: "synthetic-only-current-grant", frontier_binding: "synthetic-only-current-frontier", app_class: catalog, title_permitted: title };
    },
  };
  return { codec: createPersonalRecordCodec(context), calls: () => calls, descriptors, deny: () => { permitted = false; }, title: () => { title = true; } };
}
function replace(object: unknown, pointer: string, value: unknown): void {
  const keys = pointer.slice(1).split("/");
  let target = object as Record<string, unknown>;
  for (const key of keys.slice(0, -1)) target = target[key] as Record<string, unknown>;
  target[keys.at(-1)!] = value;
}
function expectFailure<A>(result: Result.Result<A, PersonalCodecFailure>, code: string) {
  assert.ok(Result.isFailure(result));
  assert.deepEqual(result.failure, { _tag: "PersonalCodecFailure", code });
  assert.ok(Object.isFrozen(result.failure));
}
function frozen(value: unknown): void {
  if (value === null || typeof value !== "object") return;
  assert.ok(Object.isFrozen(value));
  for (const child of Object.values(value)) frozen(child);
}
for (const vector of personalRecordVectors) {
  test(`personal literal ${vector.case_id}`, () => {
    const host = authority(); const decoded = host.codec.decode(vector.input_json); assert.ok(Result.isSuccess(decoded));
    frozen(decoded.success); frozen(host.descriptors[0]);
    const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
    assert.equal(encoded.success, vector.expected_encoded);
    assert.deepEqual(JSON.parse(encoded.success), vector.expected_record); assert.equal(host.calls(), 2);
  });
}
for (const vector of personalMutationVectors) {
  test(`personal rejection ${vector.case_id}`, () => {
    const host = authority(); const record: unknown = JSON.parse(personalRecordVectors[vector.base_record_index]!.input_json);
    replace(record, vector.replace_or_add, vector.literal_value);
    if ("additional_replacements" in vector) for (const more of vector.additional_replacements) replace(record, more.path, more.value);
    expectFailure(host.codec.decode(JSON.stringify(record)), vector.expected_failure);
    assert.equal(host.calls(), vector.expected_failure === "scope_not_authorized" ? 1 : 0);
  });
}
for (const vector of [...personalMalformedJsonVectors, ...personalRawIntegerTokenNegatives]) {
  test(`personal lexical rejection ${vector.case_id}`, () => {
    const host = authority(); expectFailure(host.codec.decode(vector.input_json), vector.expected_failure); assert.equal(host.calls(), 0);
  });
}
for (const vector of personalAdditionalPositiveMutations) {
  test(`personal accepted ${vector.case_id}`, () => {
    const host = authority(); const record: unknown = JSON.parse(personalRecordVectors[vector.base_record_index]!.input_json);
    replace(record, vector.replace_or_add, vector.literal_value);
    const decoded = host.codec.decode(JSON.stringify(record)); assert.ok(Result.isSuccess(decoded));
    const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
    assert.equal((JSON.parse(encoded.success) as { payload: { duration: { bits: string } } }).payload.duration.bits, vector.expected_preserved_bits);
  });
}
test("personal unknown arguments and foreign encode objects invoke no traps/coercion/host", () => {
  const host = authority(); let traps = 0;
  const proxy = new Proxy({}, { get() { traps++; throw Error("private"); }, ownKeys() { traps++; throw Error("private"); }, getPrototypeOf() { traps++; throw Error("private"); } });
  const revoked = Proxy.revocable({}, {}); revoked.revoke();
  for (const input of [proxy, revoked.proxy, {}, [], 1, null, true, 1n, Symbol("private"), () => undefined]) {
    expectFailure(host.codec.decode(input), "unsupported_shape"); expectFailure(host.codec.encode(input), "unsupported_shape");
  }
  const throwing = { toString() { traps++; throw Error("private"); }, toJSON() { traps++; throw Error("private"); } };
  expectFailure(host.codec.decode(throwing), "unsupported_shape"); expectFailure(host.codec.encode(throwing), "unsupported_shape");
  const decoded = host.codec.decode(personalRecordVectors[0].input_json); assert.ok(Result.isSuccess(decoded));
  const other = authority(); expectFailure(other.codec.encode(decoded.success), "unsupported_shape");
  expectFailure(host.codec.encode(new Proxy(decoded.success, {})), "unsupported_shape");
  expectFailure(host.codec.encode(JSON.parse(personalRecordVectors[0].input_json)), "unsupported_shape");
  assert.equal(traps, 0); assert.equal(host.calls(), 1); assert.equal(other.calls(), 0);
});
test("personal bounds precede host and exact raw UTF8 byte limit is inclusive", () => {
  const host = authority(), raw = personalRecordVectors[0].input_json;
  const exact = raw + " ".repeat(65536 - Buffer.byteLength(raw));
  assert.ok(Result.isSuccess(host.codec.decode(exact))); assert.equal(host.calls(), 1);
  expectFailure(host.codec.decode(exact + " "), "candidate_limit_exceeded");
  expectFailure(host.codec.decode('"' + "é".repeat(32768) + '"'), "candidate_limit_exceeded");
  expectFailure(host.codec.decode("[".repeat(34) + "0" + "]".repeat(34)), "candidate_limit_exceeded");
  expectFailure(host.codec.decode("[" + Array(4096).fill("0").join(",") + "]"), "candidate_limit_exceeded");
  assert.equal(host.calls(), 1);
});
test("personal malformed Unicode and string escapes stay fixed before authority", () => {
  const host = authority();
  for (const raw of ['"\ud800"', '"\udc00"', '"\\ud800x"', '"\\udc00"', '"\\u0000"', '"\\q"', '"\\uZZZZ"', '"unterminated', "{} trailing", "[0,]", "{\"x\":0,}"])
    expectFailure(host.codec.decode(raw), "unsupported_shape");
  assert.equal(host.calls(), 0);
});
test("personal current host grant/catalog/frontier denial and callback faults do not leak", () => {
  const host = authority(); const decoded = host.codec.decode(personalRecordVectors[0].input_json); assert.ok(Result.isSuccess(decoded));
  host.deny(); expectFailure(host.codec.encode(decoded.success), "scope_not_authorized");
  expectFailure(host.codec.decode(personalRecordVectors[0].input_json), "scope_not_authorized");
  const fault = createPersonalRecordCodec({ authorize() { throw { coordinates: "private", reason: "provider-private" }; } });
  expectFailure(fault.decode(personalRecordVectors[0].input_json), "scope_not_authorized");
  const record: unknown = JSON.parse(personalRecordVectors[0].input_json); replace(record, "/lineage/source_id", "caller-forged");
  expectFailure(authority().codec.decode(JSON.stringify(record)), "scope_not_authorized");
});
test("personal title token is decoded only after independent host authorization", () => {
  const record: unknown = JSON.parse(personalRecordVectors[3].input_json);
  replace(record, "/payload/title", { state: "known", value: "synthetic-sensitive-title" });
  const raw = JSON.stringify(record), host = authority(), original = JSON.parse;
  let decodedTitles = 0;
  JSON.parse = ((input: string, ...args: unknown[]) => {
    if (input.includes("synthetic-sensitive-title")) { decodedTitles++; assert.ok(host.calls() > 0); }
    return Reflect.apply(original, JSON, [input, ...args]);
  }) as typeof JSON.parse;
  try {
    expectFailure(host.codec.decode(raw), "scope_not_authorized"); assert.equal(decodedTitles, 0);
    host.title(); const result = host.codec.decode(raw); assert.ok(Result.isSuccess(result)); assert.equal(decodedTitles, 1);
    assert.ok(!JSON.stringify(host.descriptors).includes("synthetic-sensitive-title"));
    host.deny(); expectFailure(host.codec.encode(result.success), "scope_not_authorized");
  } finally { JSON.parse = original; }
});
test("personal exact time comparison preserves tiny binary64 differences and observed zero", () => {
  const host = authority(), record: unknown = JSON.parse(personalRecordVectors[3].input_json);
  // Same finite binary64 endpoint: exact zero duration, original epoch/bit representation remains owned.
  const instant = { representation: "binary64_epoch_seconds", epoch: "apple_reference_2001", bits: "3ff0000000000001", source_resolution: "binary64_storage", uncertainty: { state: "unknown", reason: "not_reported" } };
  replace(record, "/payload/start/instant", { ...instant }); replace(record, "/payload/end/instant", { ...instant });
  replace(record, "/payload/duration/bits", "8000000000000000");
  const decoded = host.codec.decode(JSON.stringify(record)); assert.ok(Result.isSuccess(decoded));
  const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
  assert.ok(encoded.success.includes('"bits":"8000000000000000"')); assert.ok(encoded.success.includes('"bits":"3ff0000000000001"'));
  replace(record, "/payload/end/instant/bits", "3ff0000000000002");
  expectFailure(host.codec.decode(JSON.stringify(record)), "clock_inconsistent");
});
test("personal source case inventory remains81 with separate later proofs explicit", () => {
  assert.equal(acceptedContractCaseMap.length, 81);
  assert.equal(new Set(acceptedContractCaseMap.map((c) => c.case_id)).size, 81);
  assert.equal(acceptedContractCaseMap.filter((c) => c.classification === "codec").length, 11);
  assert.equal(acceptedContractCaseMap.filter((c) => c.classification === "codec_subcase_and_later_gate").length, 19);
});
test("personal accepted health-negativezero-preserve and resolution-negative-floor-nanos codec cases", () => {
  const host = authority(), record: unknown = JSON.parse(personalRecordVectors[0].input_json);
  replace(record, "/payload/value", { representation: "binary64", bits: "8000000000000000", unit: "count" });
  replace(record, "/time/instant/epoch_seconds", "-1"); replace(record, "/time/instant/nanoseconds", 999999999);
  const raw = JSON.stringify(record), decoded = host.codec.decode(raw); assert.ok(Result.isSuccess(decoded));
  const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
  assert.deepEqual(JSON.parse(encoded.success), JSON.parse(raw));
});
test("personal resolution coordinate endpoints and negativezero-speed canonical subcases preserve bits", () => {
  const host = authority(), record: unknown = JSON.parse(personalRecordVectors[1].input_json);
  replace(record, "/payload/latitude/bits", "4056800000000000"); replace(record, "/payload/longitude/bits", "4066800000000000");
  replace(record, "/payload/speed", { state: "known", value: { representation: "binary64", bits: "8000000000000000", unit: "meter_per_second" } });
  const raw = JSON.stringify(record), decoded = host.codec.decode(raw); assert.ok(Result.isSuccess(decoded));
  const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
  assert.deepEqual(JSON.parse(encoded.success), JSON.parse(raw));
});
test("personal accuracy has no admitted absent arm and unavailable sensor projection carries no original bits", () => {
  const host = authority(), record: unknown = JSON.parse(personalRecordVectors[1].input_json);
  replace(record, "/payload/horizontal_accuracy", { state: "absent" });
  expectFailure(host.codec.decode(JSON.stringify(record)), "unsupported_shape"); assert.equal(host.calls(), 0);
  replace(record, "/payload/horizontal_accuracy", { state: "unavailable", reason: "native_invalid_accuracy" });
  replace(record, "/payload/speed", { state: "unavailable", reason: "native_invalid_speed" });
  const raw = JSON.stringify(record), decoded = host.codec.decode(raw); assert.ok(Result.isSuccess(decoded));
  const encoded = host.codec.encode(decoded.success); assert.ok(Result.isSuccess(encoded));
  assert.deepEqual(JSON.parse(encoded.success), JSON.parse(raw));
});
