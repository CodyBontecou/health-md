import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { classifyContract } from "../src/contracts.js";
import { decodeExactNumber, displayValue } from "../src/exact.js";
import { jsonStringify, parseJsonLossless } from "../src/json.js";
import { loadHealthData } from "../src/loader.js";

const repo = resolve(import.meta.dirname, "../../..");
const evidence: Array<[string, string]> = [
  ["apps/apple/docs/reference/generated/core/provider-day.json", "apple_health_data"],
  ["apps/apple/docs/reference/generated/core/canonical-archive.json", "healthkit_archive"],
  ["apps/apple/docs/reference/generated/automation/api-export-v2-provider-sidecar.json", "api_envelope"],
  ["apps/apple/docs/reference/generated/automation/raw-result-complete.json", "raw_envelope"],
  ["apps/apple/docs/reference/generated/automation/agent-query-response.json", "query_response"],
  ["apps/apple/docs/reference/generated/cli/strict-raw-complete-response.json", "raw_envelope"],
  ["apps/apple/docs/reference/generated/rollups/weekly.json", "rollup"],
  ["apps/android/docs/export-contract/samples/android-full-day-granular.json", "android_unversioned"],
  ["apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json", "android_raw_snapshot"],
  ["apps/android/app/src/test/resources/raw-export/v1/medical-exact-fhir-record.json", "generic_json"],
  ["packages/contracts/proposals/provider-sections-v1/fixtures/whoop-complete.providers.json", "whoop_typed_daily"],
];
for (const [path, kind] of evidence) test(`classifies actual ${kind} evidence`, async () => {
  const store = await loadHealthData([join(repo, path)]);
  assert.equal(store.documents[0]?.contractKind, kind);
  assert.ok(store.entries.length > 0);
  if (path.includes("medical-exact-fhir")) assert.ok(store.entries.some(entry => entry.path.includes("fhir")));
});

test("pure adapter recognizes remaining explicit identities without inferring equivalence", () => {
  for (const schemaVersion of [5, 6, 7, 8]) assert.equal(classifyContract({ schema: "healthmd.health_data", schema_version: schemaVersion }).kind, "apple_health_data");
  assert.equal(classifyContract({ schema: "healthmd.health_data", schema_version: 4 }).kind, "android_frozen_v4");
  assert.equal(classifyContract({ type: "health-data", schemaProfile: "android-analytical-v5", schemaVersion: 5 }).kind, "android_analytical_v5");
  assert.equal(classifyContract({ profileVersion: 5, schemaVersion: 5, payload: {} }).kind, "generic_json");
  assert.equal(classifyContract({ schema: "healthmd.external_provider_daily", schema_version: 1 }).kind, "external_provider_daily");
  assert.equal(classifyContract({ schema: "healthmd.android_merge_provenance", schema_version: 1 }).kind, "android_merge_reference");
  assert.equal(classifyContract({ schema: "healthmd.raw_record", schema_version: 1 }).kind, "android_raw_reference");
  assert.equal(classifyContract({ header: { schema: "healthmd.raw-changes", version: 1 }, events: [], issues: [], manifest: {} }).kind, "android_raw_reference");
  assert.equal(classifyContract({ schema: "healthmd.raw-snapshot.manifest", version: 1 }).kind, "android_raw_manifest");
  assert.equal(classifyContract({ schema: "healthmd.unknown", schema_version: 1 }).kind, "generic_healthmd");
});

test("Android v5 signature metadata remains generically readable without masquerading as a daily export", async () => {
  const store = await loadHealthData([join(repo, "apps/android/app/src/test/resources/export-contract/signatures/exporter_signature_android_analytical_v5.json")]);
  assert.equal(store.documents[0]?.contractKind, "generic_json");
  assert.ok(store.entries.some(entry => entry.path.endsWith("metricDiscriminators.schemaProfile") && entry.value === "android-analytical-v5"));
});

test("actual nested Android raw identity is retained", async () => {
  const store = await loadHealthData([join(repo, "apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json")]);
  assert.equal(store.documents[0]?.schema, "healthmd.raw-snapshot");
  assert.equal(store.documents[0]?.schemaVersion, 1);
});

test("packaged schema snapshots remain byte-identical to canonical contracts", async () => {
  for (const [packaged, canonical] of [
    ["schemas/unified-health-data-v9.schema.json", "packages/contracts/proposals/unified-health-data-v9/unified-health-data-v9.schema.json"],
    ["schemas/provider-sections-v1.schema.json", "packages/contracts/proposals/provider-sections-v1/provider-sections-v1.schema.json"],
  ] as const) assert.deepEqual(await readFile(join(repo, "packages/pi-healthmd-dashboard", packaged)), await readFile(join(repo, canonical)));
});

test("lossless parser preserves actual source-fidelity integer tokens", async () => {
  const store = await loadHealthData([join(repo, "apps/apple/docs/reference/generated/core/canonical-archive.json")]);
  const large = store.entries.find(entry => entry.path.endsWith("metadata.unsigned_integer.value"));
  assert.equal(large?.value, 18446744073709551615n);
  assert.match(jsonStringify(large), /18446744073709551615/);
  const parsed = parseJsonLossless('{"n":18446744073709551615,"negativeZero":-0}') as { n: bigint; negativeZero: number };
  assert.equal(parsed.n, 18446744073709551615n);
  assert.equal(Object.is(parsed.negativeZero, -0), true);
  assert.throws(() => parseJsonLossless(`{"n":${"1".repeat(1025)}}`), /number token exceeds/);
  assert.throws(() => parseJsonLossless('{"n":1e9999}'), /finite binary64/);
});

test("exact number representations preserve -0, subnormal, extremes, and safely reject invalid values", () => {
  assert.equal(decodeExactNumber({ representation: "binary64", bits: "8000000000000000" })?.exactText, "-0");
  assert.equal(decodeExactNumber({ representation: "binary64", bits: "0000000000000001" })?.chartValue, 5e-324);
  assert.equal(decodeExactNumber({ representation: "binary64", bits: "7fefffffffffffff" })?.chartValue, Number.MAX_VALUE);
  assert.throws(() => decodeExactNumber({ representation: "binary64", bits: "7ff0000000000000" }), /Non-finite/);
  assert.throws(() => decodeExactNumber({ representation: "unsigned_integer", decimal: "-1" }), /Invalid/);
  assert.throws(() => decodeExactNumber({ representation: "signed_integer", decimal: "1".repeat(41) }), /40/);
  assert.doesNotThrow(() => displayValue({ representation: "unsigned_integer", decimal: "-1" }));
});

test("recognized invalid typed query response remains indexed and marked invalid", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-query-invalid-"));
  const file = join(dir, "invalid-query.json");
  await writeFile(file, JSON.stringify({ schema: "healthmd.query_response", schema_version: 2, items: "bad" }));
  const store = await loadHealthData([file]);
  assert.equal(store.documents[0]?.contractKind, "query_response");
  assert.equal(store.documents[0]?.contractValid, false);
  assert.ok(store.warnings.some(warning => /healthmd\.query_response\/1/.test(warning)));
});

test("file-loaded query contracts retain exact integer token validation", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-query-token-"));
  const file = join(dir, "decimal-version.json");
  const canonical = await readFile(join(repo, "apps/apple/docs/reference/generated/automation/agent-query-response.json"), "utf8");
  await writeFile(file, canonical.replace('"schema_version":1', '"schema_version":1.0'));
  const store = await loadHealthData([file]);
  assert.equal(store.documents[0]?.contractKind, "query_response");
  assert.equal(store.documents[0]?.contractValid, false);
  assert.ok(store.warnings.some(warning => /non-integer JSON token/.test(warning)));
});

test("recognized invalid v9 remains indexed and boundedly warned", async () => {
  const dir = await mkdtemp(join(tmpdir(), "healthmd-v9-invalid-"));
  const file = join(dir, "invalid.json");
  await writeFile(file, JSON.stringify({ schema: "healthmd.health_data", schema_version: 9, profile: "wrong", unknown: true }));
  const store = await loadHealthData([file]);
  assert.equal(store.documents[0]?.contractKind, "unified_v9");
  assert.equal(store.documents[0]?.experimentalV9, false);
  assert.equal(store.documents[0]?.contractValid, false);
  assert.ok(store.entries.length > 0);
  assert.ok(store.warnings.length > 0 && store.warnings.length <= 100);
});

test("v9 validation rejects malformed resource, platform, and metric semantic invariants", () => {
  const base = {
    schema: "healthmd.health_data", schema_version: 9, profile: "unified-cross-platform-v1", owner_date: "2026-01-01",
    calendar: { identifier: "gregorian", time_zone: "UTC", interval_start: "2026-01-01T00:00:00Z", interval_end: "2026-01-02T00:00:00Z", assignment_rule: "record_start_in_half_open_day_interval" },
    source: { platform: "apple", source_profile: "apple_health_data_v8" },
    capture: { status: "complete", resources: [{ source: "apple_health", resource: "steps", status: "complete", record_count: 1 }] },
    metrics: [{ semantic_id: "steps", statistic: "sum", value: { value_type: "number", number: { representation: "unsigned_integer", decimal: "1" }, unit: "count" }, provenance: [{ source: "apple_health", source_semantic_id: "steps" }] }],
    platform: { apple: { schema: "healthmd.platform.apple_daily", schema_version: 1, source_schema_version: 8 } },
  };
  const metric = base.metrics[0]!;
  assert.equal(classifyContract(base).valid, true);
  assert.equal(classifyContract({ ...base, platform: { apple: { schema: "wrong", schema_version: 1 } } }).valid, false);
  assert.equal(classifyContract({ ...base, capture: { status: "complete", resources: [{ status: "complete" }] } }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ statistic: "sum", value: { value_type: "number", number: { representation: "unsigned_integer", decimal: "-1" } }, provenance: [] }] }).valid, false);
  assert.equal(classifyContract({ ...base, owner_date: "not-a-date" }).valid, false);
  assert.equal(classifyContract({ ...base, source: { ...base.source, unexpected: true } }).valid, false);
  assert.equal(classifyContract({ ...base, providers: { whoop: { schema: "healthmd.provider.whoop_daily", schema_version: 1 } } }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, value: { value_type: "unknown" } }] }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, provenance: [{ source: "health_connect", source_semantic_id: "steps" }] }] }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, provenance: [{ source: "apple_health", source_semantic_id: "not_steps", source_statistic: "sum" }] }] }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, provenance: [{ source: "apple_health", source_semantic_id: "steps", source_statistic: "latest" }] }] }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, semantic_id: "arbitrary_metric" }], capture: { status: "complete", resources: [{ source: "apple_health", resource: "arbitrary_metric", status: "complete", record_count: 1 }] } }).valid, false);
  assert.equal(classifyContract({ ...base, metrics: [{ ...metric, semantic_id: "heart_rate_variability_rmssd", statistic: "latest", value: { ...metric.value, unit: "millisecond" } }], capture: { status: "complete", resources: [{ source: "apple_health", resource: "heart_rate_variability_rmssd", status: "complete", record_count: 1 }] } }).valid, false);
});
