import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { decodeExactNumber } from "../src/exact.js";
import { loadHealthData } from "../src/loader.js";
import { formatEvidence, queryStore } from "../src/query.js";

const repo = resolve(import.meta.dirname, "../../..");
const fixtureDir = join(repo, "packages/contracts/proposals/unified-health-data-v9/fixtures");
const fixtures = ["android-minimal.json", "android-not-requested.json", "apple-minimal.json", "apple-partial.json", "apple-whoop.json"];

for (const fixture of fixtures) {
  test(`loads and indexes canonical proposed v9 fixture ${fixture}`, async () => {
    const store = await loadHealthData([join(fixtureDir, fixture)]);
    assert.equal(store.documents.length, 1);
    assert.equal(store.documents[0]?.experimentalV9, true);
    assert.equal(store.documents[0]?.profile, "unified-cross-platform-v1");
    assert.ok(store.entries.some(entry => entry.path === "$.capture.status"));
    assert.ok(store.entries.some(entry => entry.path === "$.source.platform"));
  });
}

test("canonical fixtures preserve exact values, capture, platform, provenance, explicit zero, and provider identity", async () => {
  const store = await loadHealthData(fixtures.map(file => join(fixtureDir, file)));
  const steps = queryStore(store, { metric: "steps", path: ".number", limit: 100 });
  assert.ok(steps.matches.some(entry => JSON.stringify(entry.value).includes('"decimal":"1234"')));
  const hrv = queryStore(store, { metric: "heart_rate_variability_rmssd", path: ".number", limit: 20 });
  assert.equal(decodeExactNumber(hrv.matches[0]!.value)?.chartValue, 48);
  assert.equal(hrv.matches[0]?.unit, "millisecond");
  assert.equal(hrv.matches[0]?.statistic, "latest");
  assert.ok(hrv.matches[0]?.provenance);
  assert.ok(store.entries.some(entry => entry.path.includes("providers.whoop.recoveries[0].hrv_rmssd_ms") && entry.provider === "whoop"));
  assert.ok(store.entries.some(entry => entry.path.endsWith("capture.resources[0].record_count") && entry.value === 0));
  assert.ok(store.entries.some(entry => entry.value === "not_requested"));
  assert.ok(store.entries.some(entry => entry.value === "partial"));
  assert.deepEqual(new Set(store.documents.map(document => document.platform)), new Set(["apple", "android"]));
});

test("exact integers outside safe chart range retain exact text", () => {
  const decoded = decodeExactNumber({ representation: "unsigned_integer", decimal: "18446744073709551615" });
  assert.equal(decoded?.exactText, "18446744073709551615");
  assert.equal(decoded?.safeForChart, false);
  assert.equal(decoded?.chartValue, undefined);
});

test("indexes an actual source-fidelity HealthKit contract and sensitive generic paths", async () => {
  const archive = join(repo, "apps/apple/docs/reference/generated/core/canonical-archive.json");
  const store = await loadHealthData([archive]);
  assert.equal(store.documents[0]?.schema, "healthmd.healthkit_records");
  for (const search of ["state_of_mind", "medication", "clinical", "workout_route"]) {
    const result = queryStore(store, { search, limit: 10 });
    assert.ok(result.totalMatches > 0, `expected ${search}`);
  }
  assert.ok(queryStore(store, { path: "$.records", search: "latitude", limit: 10 }).totalMatches > 0);
});

test("resolves matching digest references and reports mismatch/unresolved honestly", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-dashboard-"));
  const companion = Buffer.from(JSON.stringify({ schema: "healthmd.healthkit_records", schema_version: 1, records: [] }));
  const digest = createHash("sha256").update(companion).digest("hex");
  await writeFile(join(directory, "companion.json"), companion);
  await writeFile(join(directory, "v9.json"), JSON.stringify({
    schema: "healthmd.health_data", schema_version: 9, profile: "unified-cross-platform-v1",
    platform: { apple: { healthkit_record_archive: { schema: "healthmd.healthkit_records", schema_version: 1, sha256: digest, byte_count: companion.byteLength } } },
  }));
  let store = await loadHealthData([directory]);
  assert.equal(store.references[0]?.status, "resolved");
  const v9 = JSON.parse(await readFile(join(directory, "v9.json"), "utf8"));
  v9.platform.apple.healthkit_record_archive.byte_count++;
  await writeFile(join(directory, "v9.json"), JSON.stringify(v9));
  store = await loadHealthData([directory]);
  assert.equal(store.references[0]?.status, "byte_count_mismatch");
  v9.platform.apple.healthkit_record_archive.sha256 = "0".repeat(64);
  await writeFile(join(directory, "v9.json"), JSON.stringify(v9));
  store = await loadHealthData([directory]);
  assert.equal(store.references[0]?.status, "digest_mismatch");
  store = await loadHealthData([join(directory, "v9.json")]);
  assert.equal(store.references[0]?.status, "unresolved");
});

test("resolves an exact Android raw-snapshot companion without normalizing contract identity", async () => {
  const raw = join(repo, "apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json");
  const bytes = await readFile(raw);
  const directory = await mkdtemp(join(tmpdir(), "healthmd-raw-reference-"));
  const reference = join(directory, "reference.json");
  await writeFile(reference, JSON.stringify({ companion: { schema: "healthmd.raw-snapshot", schema_version: 1, sha256: createHash("sha256").update(bytes).digest("hex") } }));
  let store = await loadHealthData([raw, reference]);
  assert.equal(store.references[0]?.status, "resolved");
  await writeFile(reference, JSON.stringify({ companion: { schema: "healthmd.raw_snapshot", schema_version: 1, sha256: createHash("sha256").update(bytes).digest("hex") } }));
  store = await loadHealthData([raw, reference]);
  assert.equal(store.references[0]?.status, "digest_mismatch");
});

test("enforces file, per-file, total-byte, and leaf bounds", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-bounds-"));
  await writeFile(join(directory, "a.json"), JSON.stringify({ a: 1, b: 2 }));
  await writeFile(join(directory, "b.json"), JSON.stringify({ c: 3 }));
  await assert.rejects(loadHealthData([directory], { maxFiles: 1 }), /file count/);
  await assert.rejects(loadHealthData([join(directory, "a.json")], { maxFileBytes: 2 }), /per-file/);
  await assert.rejects(loadHealthData([directory], { maxTotalBytes: 5 }), /total byte/);
  await assert.rejects(loadHealthData([join(directory, "a.json")], { maxLeaves: 1 }), /leaf count/);
  const longPath = join(directory, "long-path.json");
  await writeFile(longPath, JSON.stringify({ ["x".repeat(100)]: 1 }));
  await assert.rejects(loadHealthData([longPath], { maxPathBytes: 32 }), /per-path byte limit/);
  const manyPaths = join(directory, "many-paths.json");
  await writeFile(manyPaths, JSON.stringify({ values: Array.from({ length: 20 }, (_, index) => index) }));
  await assert.rejects(loadHealthData([manyPaths], { maxIndexedPathBytes: 64 }), /paths exceed total byte limit/);
  const references = join(directory, "references.json");
  await writeFile(references, JSON.stringify({ refs: [0, 1].map(index => ({ schema: "healthmd.test", schema_version: 1, sha256: String(index).repeat(64) })) }));
  await assert.rejects(loadHealthData([references], { maxReferences: 1 }), /reference count/);
});

test("generic query reaches sensitive, platform, and provider paths without filtering domains", async () => {
  const directory = await mkdtemp(join(tmpdir(), "healthmd-domains-"));
  const file = join(directory, "contracts.json");
  await writeFile(file, JSON.stringify({
    mood: { state_of_mind: "calm" }, medications: [{ name: "synthetic" }], clinical: { record: "synthetic" },
    reproductive: { cycle_day: 1 }, nutrition: { energy: 0 }, routes: [{ latitude: 0, longitude: 0 }],
    platform: { android: { merge_provenance: "synthetic" } }, providers: { whoop: { hrv_rmssd_ms: 50 } },
  }));
  const store = await loadHealthData([file]);
  for (const search of ["mood", "medications", "clinical", "reproductive", "nutrition", "routes", "platform.android", "providers.whoop"]) {
    assert.ok(queryStore(store, { path: search, limit: 5 }).totalMatches > 0, `expected generic path ${search}`);
  }
});

test("query output is bounded", async () => {
  const store = await loadHealthData([join(fixtureDir, "apple-whoop.json")]);
  const result = queryStore(store, { search: "whoop", limit: 10_000 });
  assert.ok(result.matches.length <= 100);
  formatEvidence(result);
  assert.ok(result.evidenceBytes <= 24_000);
  assert.equal(result.truncated, result.totalMatches > result.matches.length);
});
