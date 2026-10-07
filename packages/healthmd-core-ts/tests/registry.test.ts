import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as Result from "effect/Result";
import { readReviewedRegistry, registryExpectedSha256 } from "../src/contracts/registry.js";
import { registryAuthority, profileVectors, semanticVectors, mutationVectors } from "./registry-vectors.js";
const prefix = "../../packages/healthmd-core-rust/crates/healthmd-core/registry/";
const hash = (value: string | Uint8Array): string => createHash("sha256").update(value).digest("hex");
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (typeof value === "object" && value !== null) return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k, v]) => [k, sorted(v)]));
  return value;
}
const canonical = (value: unknown): string => JSON.stringify(sorted(value), null, 2) + "\n";
async function frozen() {
  const bytes = await readFile(prefix + "metric-registry-v1.json");
  assert.equal(bytes.length, registryAuthority.bytes); assert.equal(hash(bytes), registryAuthority.sha256);
  assert.equal(registryExpectedSha256, registryAuthority.sha256);
  return bytes.toString("utf8");
}
for (const vector of profileVectors) test(`registry complete independent projection: ${vector.id}`, async () => {
  const result = readReviewedRegistry(await frozen()); assert.ok(Result.isSuccess(result));
  const projected = result.success.snapshot(vector.id); assert.ok(Result.isSuccess(projected)); const snapshot = projected.success;
  assert.equal(hash(JSON.stringify(sorted(snapshot))), vector.snapshot_sha256);
  assert.equal(snapshot.metrics.length, vector.metrics); assert.equal(snapshot.outputs.length, vector.outputs);
  assert.equal(snapshot.unavailable_metrics.length, vector.unavailable); assert.equal(snapshot.outputs.filter((o) => o.enabled_by_default).length, vector.enabled);
  assert.equal(snapshot.metrics[0]?.selection_id, vector.first); assert.equal(snapshot.metrics.at(-1)?.selection_id, vector.last);
  assert.equal(snapshot.public_schema_version, vector.schema_version);
});
for (const vector of mutationVectors) test(`registry strict source boundary literal: ${vector.id}`, async () => {
  // Fixed mutations and outcomes were reviewed before the reader existed.
  const asset: unknown = JSON.parse(await frozen()); let parent = asset as Record<string | number, unknown>;
  for (const segment of vector.path.slice(0, -1)) parent = parent[segment] as Record<string | number, unknown>;
  const key = vector.path.at(-1)!;
  if (vector.value === "DELETE") delete parent[key]; else parent[key] = vector.value;
  const result = readReviewedRegistry(canonical(asset)); assert.equal(Result.isSuccess(result), vector.valid);
  if (Result.isFailure(result)) assert.deepEqual(result.failure, { _tag: "RegistryFailure", code: "invalid_registry" });
  else assert.equal(result.success.authority.byte_binding, "requires_reviewed_host_binding");
});
test("registry retains all semantic rows and literal platform classifications without fabricated equivalence", async () => {
  const raw = await frozen(); const asset = JSON.parse(raw) as { metrics: readonly unknown[]; categories: readonly unknown[]; known_capability_ids: readonly string[] };
  const result = readReviewedRegistry(raw); assert.ok(Result.isSuccess(result));
  assert.deepEqual(result.success.semanticRows, asset.metrics);
  assert.equal(result.success.semanticRows.length, registryAuthority.metrics); assert.equal(asset.categories.length, registryAuthority.categories); assert.equal(asset.known_capability_ids.length, registryAuthority.capabilities);
  for (const expected of semanticVectors) {
    const actual: (typeof result.success.semanticRows)[number] | undefined = result.success.semanticRows.find((m) => m.semantic_id === expected.semantic_id); assert.ok(actual); assert.equal(actual.equivalence, expected.equivalence);
    for (const platform of ["apple", "android"] as const) { assert.equal(actual[platform].status, expected[platform].status); assert.equal(actual[platform].selection_id ?? null, expected[platform].selection_id); assert.equal(actual[platform].unit ?? null, expected[platform].unit); }
  }
});
test("registry preserves unsupported versus unavailable and backed without substituting zero", async () => {
  const result = readReviewedRegistry(await frozen()); assert.ok(Result.isSuccess(result));
  for (const [id, state] of [["sleep_total", "backed"], ["wrist_temperature", "unavailable"], ["invented_metric", "unsupported"]]) {
    const selected = result.success.selection("android_frozen_v4", id!); assert.ok(Result.isSuccess(selected)); assert.equal(selected.success.state, state);
    assert.equal("value" in selected.success, false);
  }
  const selected = result.success.selection("missing_profile", "sleep_total"); assert.ok(Result.isFailure(selected)); assert.equal(selected.failure.code, "unsupported_registry_profile");
});
test("registry matches existing immutable native baseline fields and unavailable order", async () => {
  const result = readReviewedRegistry(await frozen()); assert.ok(Result.isSuccess(result));
  for (const [profile, filename, keys] of [
    ["apple_health_data_v8", "native-baseline-apple-v7.json", ["selection_id", "reference_name", "category_id", "unit", "kind", "source_aggregation", "archive_only", "default_enabled", "availability_key", "source_selector"]],
    ["android_frozen_v4", "native-baseline-android-v4-v5.json", ["selection_id", "category_id", "unit", "source_aggregation", "default_enabled", "availability_key"]],
  ] as const) {
    const baseline = JSON.parse(await readFile(prefix + filename, "utf8")) as { metrics: readonly Record<string, unknown>[]; unavailable_metrics?: readonly { selection_id: string }[] };
    const projected = result.success.snapshot(profile); assert.ok(Result.isSuccess(projected)); assert.equal(projected.success.metrics.length, baseline.metrics.length);
    for (const [i, metric] of projected.success.metrics.entries()) for (const key of keys) assert.deepEqual(metric[key], baseline.metrics[i]![key]);
    if (baseline.unavailable_metrics) assert.deepEqual(projected.success.unavailable_metrics.map((m) => m.selection_id), baseline.unavailable_metrics.map((m) => m.selection_id));
  }
});
test("registry version precedes parsing; profile failures and parser failures stay sanitized", async () => {
  const version = readReviewedRegistry("sensitive malformed text", 2); assert.ok(Result.isFailure(version)); assert.equal(version.failure.code, "unsupported_registry_version");
  const result = readReviewedRegistry(await frozen()); assert.ok(Result.isSuccess(result));
  const unsupported = result.success.snapshot("missing"); assert.ok(Result.isFailure(unsupported)); assert.deepEqual(unsupported.failure, { _tag: "RegistryFailure", code: "unsupported_registry_profile" });
  const wrongVersion = result.success.snapshot("missing", 2); assert.ok(Result.isFailure(wrongVersion)); assert.equal(wrongVersion.failure.code, "unsupported_registry_version");
  for (const input of [undefined, {}, "sensitive malformed text", "{}\n", "x".repeat(1048577), "[".repeat(40) + "0" + "]".repeat(40), "[" + "0,".repeat(100001) + "0]"]) {
    const rejected = readReviewedRegistry(input); assert.ok(Result.isFailure(rejected)); assert.deepEqual(rejected.failure, { _tag: "RegistryFailure", code: "invalid_registry" });
  }
});
test("registry rejects noncanonical bytes and duplicate keys before shape projection", async () => {
  const raw = await frozen(); const asset: unknown = JSON.parse(raw);
  for (const text of [JSON.stringify(asset), raw.trimEnd(), raw + "\n", raw.replace('"registry_version": 1', '"registry_version": 1, "registry_version": 1')]) {
    assert.ok(Result.isFailure(readReviewedRegistry(text)));
  }
});
test("registry defensive snapshots are deeply immutable and authority binding remains an explicit precondition", async () => {
  const result = readReviewedRegistry(await frozen()); assert.ok(Result.isSuccess(result)); const reader = result.success;
  const snapshot = reader.snapshot("android_frozen_v4"); assert.ok(Result.isSuccess(snapshot));
  assert.ok(Object.isFrozen(reader)); assert.ok(Object.isFrozen(reader.semanticRows[0]?.android)); assert.ok(Object.isFrozen(snapshot.success.metrics[0]?.related_semantic_ids)); assert.ok(Object.isFrozen(snapshot.success.outputs));
  assert.throws(() => { (snapshot.success.metrics as unknown[]).pop(); });
  assert.throws(() => { (snapshot.success as { registry_version: number }).registry_version = 9; });
  assert.deepEqual(reader.authority, { expected_sha256: registryAuthority.sha256, byte_binding: "requires_reviewed_host_binding" });
  // A structurally valid altered unit is not authenticated by this reader; host binding must reject it.
  const changed = JSON.parse(await frozen()) as { metrics: { android: { unit: string } }[] }; changed.metrics[0]!.android.unit = "other";
  const text = canonical(changed); assert.notEqual(hash(text), registryAuthority.sha256);
  const validatedOnly = readReviewedRegistry(text); assert.ok(Result.isSuccess(validatedOnly)); assert.equal(validatedOnly.success.authority.byte_binding, "requires_reviewed_host_binding");
});

test("registry unavailable resolution remains a requested-profile projection failure", async () => {
  const asset = JSON.parse(await frozen()) as { profiles: { unavailable_selection_ids: string[] }[] };
  asset.profiles[1]!.unavailable_selection_ids[0] = "unknown_unavailable";
  const validated = readReviewedRegistry(canonical(asset)); assert.ok(Result.isSuccess(validated));
  assert.ok(Result.isSuccess(validated.success.snapshot("apple_health_data_v8")));
  const invalid = validated.success.snapshot("android_frozen_v4"); assert.ok(Result.isFailure(invalid)); assert.equal(invalid.failure.code, "invalid_registry");
});

test("registry parser rejects unpaired Unicode surrogates and preserves valid astral pairs", async () => {
  // Independent serde_json 1.0.151 UTF8-string parser parity literals; original corpus unchanged.
  for (const unit of ["\ud800", "\udfff", "\udc00\ud800", "\ud800x\udc00"]) {
    const asset = JSON.parse(await frozen()) as { metrics: { android: { unit: string } }[] };
    asset.metrics[0]!.android.unit = unit;
    assert.ok(Result.isFailure(readReviewedRegistry(canonical(asset))));
  }
  const asset = JSON.parse(await frozen()) as { metrics: { android: { unit: string } }[] };
  asset.metrics[0]!.android.unit = "\ud83d\udca4";
  const valid = readReviewedRegistry(canonical(asset)); assert.ok(Result.isSuccess(valid));
  const snapshot = valid.success.snapshot("android_frozen_v4"); assert.ok(Result.isSuccess(snapshot)); assert.equal(snapshot.success.metrics[0]!.unit, "\ud83d\udca4");
  const keyed = JSON.parse(await frozen()) as Record<string, unknown>; keyed["\ud800"] = true;
  assert.ok(Result.isFailure(readReviewedRegistry(canonical(keyed))));
});
