import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
assert.equal(process.versions.node, "24.21.0", "exact_candidate_node_required");
assert.ok(process.env.npm_execpath, "candidate_check_requires_npm");
const npm = spawnSync(process.execPath, [process.env.npm_execpath, "--version"], { encoding: "utf8" });
assert.equal(npm.status, 0); assert.equal(npm.stdout.trim(), "11.19.0", "exact_candidate_npm_required");
const manifest = JSON.parse(await readFile("package.json", "utf8"));
const lock = JSON.parse(await readFile("package-lock.json", "utf8"));
assert.equal(lock.lockfileVersion, 3);
assert.deepEqual(lock.packages[""].dependencies, manifest.dependencies);
assert.deepEqual(lock.packages[""].devDependencies, manifest.devDependencies);
const versions = { effect: "4.0.1", typescript: "7.0.2", esbuild: "0.28.2", "@types/node": "24.19.1", "undici-types": "7.24.6" };
for (const [name, version] of Object.entries(versions)) {
  assert.equal(lock.packages[`node_modules/${name}`]?.version, version);
  assert.equal(JSON.parse(await readFile(`node_modules/${name}/package.json`, "utf8")).version, version);
}
assert.equal(lock.packages["node_modules/@healthmd/core-ts"]?.link, undefined, "install_packed_core_with_install_links");
assert.equal(lock.packages["node_modules/@healthmd/core-ts"]?.version, "0.0.0-candidate.1");
assert.equal(lock.packages["node_modules/@healthmd/core-ts"]?.resolved, "file:../../packages/healthmd-core-ts");
for (const [path, record] of Object.entries(lock.packages)) {
  if (!path) continue;
  const name = path.split("node_modules/").at(-1);
  assert.ok(["@healthmd/core-ts", ...Object.keys(versions)].includes(name) || name.startsWith("@typescript/typescript-") || name.startsWith("@esbuild/"), `unreviewed_candidate_dependency:${name}`);
  assert.notEqual(record.link, true, "dependency_symlink_unreviewed");
  if (name.startsWith("@typescript/typescript-")) assert.equal(record.version, "7.0.2", "compiler_platform_pin_drift");
  if (name.startsWith("@esbuild/")) assert.equal(record.version, "0.28.2", "bundler_platform_pin_drift");
  if (name !== "@healthmd/core-ts") {
    assert.ok(record.resolved.startsWith("https://registry.npmjs.org/"), "unreviewed_registry_source");
    assert.match(record.integrity, /^sha512-/, "dependency_integrity_missing");
  }
}
// Frozen independently from the accepted historical tree plus exactly its reviewed patch.
// Runtime verification requires no Git executable or repository history.
const coreInputAuthority = {
  sourceSha: "3b551faef158e1f0c0d675a72a72f8fe3e919bc3",
  patchDigest: "110aa7e30055cb45fee8be13bd29a19f8f6872c01909fdc4a057e8f01ce34ce4",
};
// Two metadata pins reviewed by CORE-CANDIDATE-API; old receipt remains historical code authority.
const coreMetadataAuthority = { taskId: "CORE-CANDIDATE-API", sourceSha: "c306053b9cb7bcb65ebdcc0789ddad9bc56652d6",
  historicalManifestSha256: "669826ebeacdc3211b4d41ec0f17ddad63b78b710bb74756fa2dfd586c756ba2",
  emittedArtifactMapSha256: "7845384cd4a0c8fb493651100d97159ecb7d269875fb62b0f7ecef2e92c8bbc4" };
const coreInputPins = {
  ".node-version": "73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f",
  "AGENTS.md": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
  "README.md": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606",
  "package-lock.json": "61746468956308b8a7811cc02fb41c6ac239d5830121ceffeab43324b639c36e",
  "package.json": "822034747afb2524a9133adc8869b453bac601a981141144f71a3ce5f24462f2",
  "scripts/build.mjs": "74a89aaaca29b65bdbc13fec480aaa642b8bf72c7daeebacfae150750c7cd83b",
  "scripts/check-boundaries.mjs": "3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09",
  "scripts/check.mjs": "e61622b1190322a61021055b342636e5edfd7f4cfba7ef7e240e375a7a6c3eae",
  "src/contracts/exact-values.ts": "2c56f1942f585a5cf3d2c5387d42c87ef2853255b2fc9ddda86e1666a15a4275",
  "src/contracts/personal-slice.ts": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
  "src/contracts/registry.ts": "0a2712e9f7ec42596b65a509d8ccf755d8e85f5bfb2f47e0b272bf180469fe09",
  "src/host-interfaces/capabilities.ts": "d782133d2e5458baad95382a5d65c36c0e97266ae22d7eb62138fd8336c78812",
  "src/host-interfaces/faults.ts": "8be680e6895512aa3f95c70ecaff076cbd021e0e3db39a785e286f7b1de7cf72",
  "src/index.ts": "3b2632b7f93517e259be66242444b449402d0a3821c38a76b6b28c6abce256d8",
  "src/location/point-projection.ts": "ca9fffbc5bdb1af9c261cd084251ad905f2cd911173d4792b482bb8c499aa7d3",
  "src/operations/catalog.ts": "eee557683d518595545797ed228e6e56e6659ea0d2325270059c1a13d89a0db7",
  "src/operations/normalize.ts": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
  "src/operations/personal-slice.ts": "02be2de8342e62b5f7c6da104588e055818bfa928aa1c2bbf4d9b14b1cce3b05",
  "src/operations/query.ts": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
  "src/serialization/exact-json-numbers.ts": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52",
  "src/usage-mobile/ios-eligibility.ts": "92b8181ffbb5c3df2986449e18108a753516bdaabbf69629f4b9ac0593673017",
  "tests/catalog-vectors.ts": "a28c9539cb62c1c5b52319c5e4cca27f93b3bebd5b5900592775800067a06f51",
  "tests/catalog.test.ts": "a3751d2bc08ab1b855db9b7ab318430cf927d5b00f7104124448f820168e1b27",
  "tests/combined-slice-vectors.ts": "2a87777579998eab5901cf4b3089c11bfad01789060904680d40ef7848d52b35",
  "tests/combined-slice.test.ts": "3d767799c08456e4baa4b84f19af4680e6945f4cac849dac980525a812c29ae0",
  "tests/exact-json-numbers-vectors.ts": "3da51631a58425a061c4f386a88ab22457af855e914775fb77233358c0c4b1e8",
  "tests/exact-json-numbers.test.ts": "9415b3d8ab923ef905fe8e35d01fc4df47fd23516c3d54072713fefd50e10810",
  "tests/exact-values-vectors.ts": "b64ca4d8bd50335a41f4d6f2ff045825f8feb3c0e91c3ce58e13715ae77ec954",
  "tests/exact-values.test.ts": "03c50ea1fb9f0d9d1efee6b415468876a3f917b9628ee32bb9b76587ec6578a5",
  "tests/foundation.test.ts": "f9f54951e7fb19db668373c4b8aab74d5aa5e282396380bc163152ffedb1ba0c",
  "tests/location-point-projection-vectors.ts": "d31fdc8ca3e964384e5da4a6b0c9b2d6875d932ee0bd1d9c0eef4d70192d7595",
  "tests/location-point-projection.test.ts": "4e84fce04de24da82c3d00905ba0daf6757fc256aee461b539cc86ec6d7894da",
  "tests/personal-codecs-vectors.ts": "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a",
  "tests/personal-codecs.test.ts": "01d960569d09d21d80c8b20b950b4c3a41e87cc154943bef2305a47f3a9ce197",
  "tests/query-traversal-vectors.ts": "ee70ea97d59a83993c0b50ecdf3b8dd08b5796d379b007fcaea450a7dcc0c12a",
  "tests/query-traversal.test.ts": "d4f52ac9b25e16e76f21a4e2da2698a1a020f7cf6a3701d01d6c186760fba4ea",
  "tests/registry-vectors.ts": "f470896023dff3e000aa4171afd8988606fc4dc049c0d5b17929bfbbda67873a",
  "tests/registry.test.ts": "23c0932104a0874f4e1d8b382d38a7c01ed818f6deca12171225e8007b4a2761",
  "tests/usage-mobile-ios-eligibility-vectors.ts": "c8dcbaa0bec3ef32eb603aa85eb265bc7a715bbd70782bedfda0bb78c65f456b",
  "tests/usage-mobile-ios-eligibility.test.ts": "01c83101c70411b6e83134140704da57ea47d22f2200c0056cf79db35ff57cfc",
  "tsconfig.build.json": "da405f2cf08aea30602cc1ffdbaedd25a0ead61e8b966e806404627212cb0614",
  "tsconfig.json": "5c9087c0fdfed84a89a16f31266a0b76c3269d9aabcbf23e7cf8dd7f6d0405a5",
  "tsconfig.test.json": "a2f54ecf614e4a58e3fbaf664f6cebc81d41d4ec6e861ae9fb4c4d5f484f68e5"
};
const coreOutputPaths = [
  "dist/core/contracts/exact-values.d.ts",
  "dist/core/contracts/exact-values.js",
  "dist/core/contracts/personal-slice.d.ts",
  "dist/core/contracts/personal-slice.js",
  "dist/core/contracts/registry.d.ts",
  "dist/core/contracts/registry.js",
  "dist/core/host-interfaces/capabilities.d.ts",
  "dist/core/host-interfaces/capabilities.js",
  "dist/core/host-interfaces/faults.d.ts",
  "dist/core/host-interfaces/faults.js",
  "dist/core/index.d.ts",
  "dist/core/index.js",
  "dist/core/location/point-projection.d.ts",
  "dist/core/location/point-projection.js",
  "dist/core/operations/catalog.d.ts",
  "dist/core/operations/catalog.js",
  "dist/core/operations/normalize.d.ts",
  "dist/core/operations/normalize.js",
  "dist/core/operations/personal-slice.d.ts",
  "dist/core/operations/personal-slice.js",
  "dist/core/operations/query.d.ts",
  "dist/core/operations/query.js",
  "dist/core/serialization/exact-json-numbers.d.ts",
  "dist/core/serialization/exact-json-numbers.js",
  "dist/core/usage-mobile/ios-eligibility.d.ts",
  "dist/core/usage-mobile/ios-eligibility.js"
];
const priorSlicesInputPins = {
  ".node-version": "73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f",
  "AGENTS.md": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
  "README.md": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606",
  "package-lock.json": "61746468956308b8a7811cc02fb41c6ac239d5830121ceffeab43324b639c36e",
  "package.json": "822034747afb2524a9133adc8869b453bac601a981141144f71a3ce5f24462f2",
  "scripts/build.mjs": "74a89aaaca29b65bdbc13fec480aaa642b8bf72c7daeebacfae150750c7cd83b",
  "scripts/check-boundaries.mjs": "3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09",
  "scripts/check.mjs": "e61622b1190322a61021055b342636e5edfd7f4cfba7ef7e240e375a7a6c3eae",
  "src/contracts/exact-values.ts": "2c56f1942f585a5cf3d2c5387d42c87ef2853255b2fc9ddda86e1666a15a4275",
  "src/contracts/personal-slice.ts": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
  "src/contracts/registry.ts": "0a2712e9f7ec42596b65a509d8ccf755d8e85f5bfb2f47e0b272bf180469fe09",
  "src/host-interfaces/capabilities.ts": "d782133d2e5458baad95382a5d65c36c0e97266ae22d7eb62138fd8336c78812",
  "src/host-interfaces/faults.ts": "8be680e6895512aa3f95c70ecaff076cbd021e0e3db39a785e286f7b1de7cf72",
  "src/index.ts": "3b2632b7f93517e259be66242444b449402d0a3821c38a76b6b28c6abce256d8",
  "src/location/point-projection.ts": "ca9fffbc5bdb1af9c261cd084251ad905f2cd911173d4792b482bb8c499aa7d3",
  "src/operations/catalog.ts": "eee557683d518595545797ed228e6e56e6659ea0d2325270059c1a13d89a0db7",
  "src/operations/normalize.ts": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
  "src/operations/personal-slice.ts": "02be2de8342e62b5f7c6da104588e055818bfa928aa1c2bbf4d9b14b1cce3b05",
  "src/operations/query.ts": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
  "src/serialization/exact-json-numbers.ts": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52",
  "tests/catalog-vectors.ts": "a28c9539cb62c1c5b52319c5e4cca27f93b3bebd5b5900592775800067a06f51",
  "tests/catalog.test.ts": "a3751d2bc08ab1b855db9b7ab318430cf927d5b00f7104124448f820168e1b27",
  "tests/combined-slice-vectors.ts": "2a87777579998eab5901cf4b3089c11bfad01789060904680d40ef7848d52b35",
  "tests/combined-slice.test.ts": "3d767799c08456e4baa4b84f19af4680e6945f4cac849dac980525a812c29ae0",
  "tests/exact-json-numbers-vectors.ts": "3da51631a58425a061c4f386a88ab22457af855e914775fb77233358c0c4b1e8",
  "tests/exact-json-numbers.test.ts": "9415b3d8ab923ef905fe8e35d01fc4df47fd23516c3d54072713fefd50e10810",
  "tests/exact-values-vectors.ts": "b64ca4d8bd50335a41f4d6f2ff045825f8feb3c0e91c3ce58e13715ae77ec954",
  "tests/exact-values.test.ts": "03c50ea1fb9f0d9d1efee6b415468876a3f917b9628ee32bb9b76587ec6578a5",
  "tests/foundation.test.ts": "f9f54951e7fb19db668373c4b8aab74d5aa5e282396380bc163152ffedb1ba0c",
  "tests/location-point-projection-vectors.ts": "d31fdc8ca3e964384e5da4a6b0c9b2d6875d932ee0bd1d9c0eef4d70192d7595",
  "tests/location-point-projection.test.ts": "4e84fce04de24da82c3d00905ba0daf6757fc256aee461b539cc86ec6d7894da",
  "tests/personal-codecs-vectors.ts": "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a",
  "tests/personal-codecs.test.ts": "01d960569d09d21d80c8b20b950b4c3a41e87cc154943bef2305a47f3a9ce197",
  "tests/query-traversal-vectors.ts": "ee70ea97d59a83993c0b50ecdf3b8dd08b5796d379b007fcaea450a7dcc0c12a",
  "tests/query-traversal.test.ts": "d4f52ac9b25e16e76f21a4e2da2698a1a020f7cf6a3701d01d6c186760fba4ea",
  "tests/registry-vectors.ts": "f470896023dff3e000aa4171afd8988606fc4dc049c0d5b17929bfbbda67873a",
  "tests/registry.test.ts": "23c0932104a0874f4e1d8b382d38a7c01ed818f6deca12171225e8007b4a2761",
  "tsconfig.build.json": "da405f2cf08aea30602cc1ffdbaedd25a0ead61e8b966e806404627212cb0614",
  "tsconfig.json": "5c9087c0fdfed84a89a16f31266a0b76c3269d9aabcbf23e7cf8dd7f6d0405a5",
  "tsconfig.test.json": "a2f54ecf614e4a58e3fbaf664f6cebc81d41d4ec6e861ae9fb4c4d5f484f68e5"
};
const priorSlicesOutputPaths = [
  "dist/core/contracts/exact-values.d.ts",
  "dist/core/contracts/exact-values.js",
  "dist/core/contracts/personal-slice.d.ts",
  "dist/core/contracts/personal-slice.js",
  "dist/core/contracts/registry.d.ts",
  "dist/core/contracts/registry.js",
  "dist/core/host-interfaces/capabilities.d.ts",
  "dist/core/host-interfaces/capabilities.js",
  "dist/core/host-interfaces/faults.d.ts",
  "dist/core/host-interfaces/faults.js",
  "dist/core/index.d.ts",
  "dist/core/index.js",
  "dist/core/location/point-projection.d.ts",
  "dist/core/location/point-projection.js",
  "dist/core/operations/catalog.d.ts",
  "dist/core/operations/catalog.js",
  "dist/core/operations/normalize.d.ts",
  "dist/core/operations/normalize.js",
  "dist/core/operations/personal-slice.d.ts",
  "dist/core/operations/personal-slice.js",
  "dist/core/operations/query.d.ts",
  "dist/core/operations/query.js",
  "dist/core/serialization/exact-json-numbers.d.ts",
  "dist/core/serialization/exact-json-numbers.js"
];
const priorSlicesPath = resolve("../../docs/migration/effect-refactor/cohorts/core-ts-personal-slices-v1.json");
const priorSlicesSha256 = "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853";
async function auditPriorSlicesCohort(path) {
  const bytes = await readFile(path);
  assert.equal(hash(bytes), priorSlicesSha256, "reviewed_core_cohort_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.committed_source_sha, "37580ca24a6d352d0ee2d8df2eca58e64e316d49", "reviewed_core_committed_source_drift");
  assert.deepEqual(value.runtime, { node: "24.21.0", npm: "11.19.0" });
  assert.equal(value.input_count, 40); assert.equal(value.output_count, 24);
  assert.equal(Object.keys(priorSlicesInputPins).length, 40);
  assert.deepEqual(value.input_pins, priorSlicesInputPins, "reviewed_core_input_map_drift");
  assert.deepEqual(Object.keys(value.output_pins).sort(), priorSlicesOutputPaths, "reviewed_core_output_set_drift");
  return value;
}
const priorSlices = await auditPriorSlicesCohort(priorSlicesPath);
const cohortPath = resolve("../../docs/migration/effect-refactor/cohorts/core-ts-ios-eligibility-v1.json");
const cohortSha256 = "25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761";
async function auditCohort(path) {
  const bytes = await readFile(path);
  assert.equal(hash(bytes), cohortSha256, "reviewed_core_cohort_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.committed_source_sha, "8a31e6f038d4f74b8ed6acb0da5003e0329714f5", "reviewed_core_committed_source_drift");
  assert.deepEqual(value.runtime, { node: "24.21.0", npm: "11.19.0" });
  assert.equal(value.input_count, 43); assert.equal(value.output_count, 26);
  assert.equal(Object.keys(coreInputPins).length, 43);
  assert.deepEqual(value.input_pins, coreInputPins, "reviewed_core_input_map_drift");
  assert.deepEqual(Object.keys(value.output_pins).sort(), coreOutputPaths, "reviewed_core_output_set_drift");
  return value;
}
const cohort = await auditCohort(cohortPath);
for (const name of ["historical_registry_authority", "metadata_authority", "accepted_delta", "personal_delta", "prior_cohort_authority", "prior_personal_cohort_authority", "location_delta", "combined_delta"])
  assert.deepEqual(cohort[name], priorSlices[name], "historical_slice_authority_changed");
async function auditPriorPersonalCohort(path) {
  const bytes = await readFile(path);
  assert.equal(hash(bytes), "a81df759ee321cf530137d9a6de6d18de2c3a4e42b92907444bde4e057f6b579", "reviewed_core_cohort_bytes_drift");
  return JSON.parse(bytes);
}
const priorPersonal = await auditPriorPersonalCohort(resolve("../../", cohort.prior_personal_cohort_authority.cohort_path));
assert.equal(priorPersonal.input_count, 34); assert.equal(priorPersonal.output_count, 20);
for (const name of ["historical_registry_authority", "metadata_authority", "accepted_delta", "personal_delta", "prior_cohort_authority"])
  assert.deepEqual(cohort[name], priorPersonal[name], "historical_personal_authority_changed");
const source = resolve("../../packages/healthmd-core-ts");
const installed = resolve("node_modules/@healthmd/core-ts");
const sourceManifest = await readFile(join(source, "package.json"));
async function auditAuthority(authority, path = resolve("../../", authority.receipt_path)) {
  const bytes = await readFile(path);
  assert.equal(hash(bytes), authority.receipt_sha256, "qualified_core_receipt_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.task_id, authority.task_id);
  assert.equal(value.result, "passed"); assert.equal(value.review.status, "accepted", "qualified_core_receipt_required");
  assert.equal(value.source_sha, authority.source_sha, "qualified_core_source_authority_drift");
  assert.equal(value.patch_digest, authority.patch_digest, "qualified_core_patch_authority_drift");
  assert.deepEqual(value.review, authority.review, "qualified_core_review_authority_drift");
  return value;
}
const priorBytes = await readFile(resolve("../../", cohort.prior_cohort_authority.cohort_path));
assert.equal(hash(priorBytes), "157b3cd4335575c56e517a7920f35773c2f69a4753b681b4f9ef2d56f9b38ee7", "reviewed_prior_core_cohort_bytes_drift");
const priorCohort = JSON.parse(priorBytes);
assert.equal(priorCohort.input_count, 31); assert.equal(priorCohort.output_count, 18);
assert.equal(priorCohort.committed_source_sha, "683acf1831d65feace61d3702d3b35f2838a42f6");
for (const name of ["historical_registry_authority", "metadata_authority", "accepted_delta"])
  assert.deepEqual(cohort[name], priorCohort[name], "historical_core_authority_changed");
const priorRefresh = await auditAuthority(cohort.prior_cohort_authority);
assert.equal(cohort.prior_cohort_authority.receipt_sha256, "66ecaf5ff5dcc257424e4ee1490998a3109e6b8ad59913950b8750876bd4ebba");
assert.deepEqual(priorRefresh.inputs.cohort.fixed_input_pins, priorCohort.input_pins);
const receipt = await auditAuthority(cohort.historical_registry_authority);
assert.equal(receipt.source_sha, coreInputAuthority.sourceSha);
assert.equal(receipt.patch_digest, coreInputAuthority.patchDigest);
const qualified = receipt.inputs.artifact_and_native_interface.emitted_artifacts;
const legacyArtifacts = Object.fromEntries(Object.entries(qualified).filter(([path]) => path.startsWith("dist/core/")));
assert.equal(Object.keys(legacyArtifacts).length, 16, "qualified_core_artifact_cohort_drift");
assert.equal(hash(JSON.stringify(Object.entries(legacyArtifacts).sort(([a], [b]) => a.localeCompare(b)))), coreMetadataAuthority.emittedArtifactMapSha256, "qualified_core_artifact_authority_drift");
assert.equal(receipt.inputs.contract_and_fixture_digests["packages/healthmd-core-ts/package.json"], coreMetadataAuthority.historicalManifestSha256, "historical_core_manifest_authority_drift");
const metadata = await auditAuthority(cohort.metadata_authority);
assert.equal(metadata.source_sha, coreMetadataAuthority.sourceSha);
assert.deepEqual(metadata.inputs.artifact_and_native_interface.retained_qualified_core_emitted_artifacts, legacyArtifacts);
assert.equal(metadata.inputs.artifact_and_native_interface.patch_files["packages/healthmd-core-ts/package.json"], coreInputPins["package.json"]);
assert.equal(metadata.inputs.artifact_and_native_interface.patch_files["packages/healthmd-core-ts/README.md"], coreInputPins["README.md"]);
const delta = await auditAuthority(cohort.accepted_delta);
const relativeMap = (map) => Object.fromEntries(Object.entries(map).map(([path, digest]) => [path.replace(/^packages\/healthmd-core-ts\//, ""), digest]));
assert.deepEqual(relativeMap(delta.inputs.artifact_and_native_interface.patch_files), cohort.accepted_delta.input_pins, "qualified_core_delta_inputs_drift");
assert.equal(Object.keys(cohort.accepted_delta.input_pins).length, 3);
assert.equal(Object.keys(cohort.accepted_delta.output_pins).length, 2);
assert.equal(cohort.accepted_delta.vector_sha256, coreInputPins["tests/exact-json-numbers-vectors.ts"]);
const priorArtifacts = { ...legacyArtifacts, ...cohort.accepted_delta.output_pins };
assert.deepEqual(priorArtifacts, priorCohort.output_pins, "qualified_core_delta_output_map_drift");
assert.deepEqual(relativeMap(delta.inputs.artifact_and_native_interface.core_emitted_artifacts), priorArtifacts, "qualified_core_delta_artifact_authority_drift");
assert.equal(Object.keys(priorArtifacts).length, 18);
const personal = await auditAuthority(cohort.personal_delta);
assert.equal(cohort.personal_delta.receipt_sha256, "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859");
assert.equal(cohort.personal_delta.committed_source_sha, "ba5c644ebca4c028fe8d60feb580a5e668965341");
assert.deepEqual(relativeMap(personal.inputs.artifact_and_native_interface.patch_files), cohort.personal_delta.input_pins, "qualified_personal_delta_inputs_drift");
assert.equal(Object.keys(cohort.personal_delta.input_pins).length, 3);
assert.equal(Object.keys(cohort.personal_delta.output_pins).length, 2);
assert.equal(cohort.personal_delta.vector_sha256, "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a");
assert.equal(cohort.personal_delta.vector_sha256, coreInputPins["tests/personal-codecs-vectors.ts"]);
assert.deepEqual({ ...priorCohort.input_pins, ...cohort.personal_delta.input_pins }, priorPersonal.input_pins, "qualified_personal_complete_inputs_drift");
const personalArtifacts = { ...priorArtifacts, ...cohort.personal_delta.output_pins };
assert.deepEqual(personalArtifacts, priorPersonal.output_pins, "qualified_personal_delta_output_map_drift");
assert.deepEqual(Object.fromEntries(Object.entries(personal.inputs.artifact_and_native_interface.actual_complete_emitted_pins).map(([path, digest]) => ["dist/core/" + path, digest])), personalArtifacts, "qualified_personal_delta_artifact_authority_drift");
assert.equal(Object.keys(personalArtifacts).length, 20);
for (const [path, digest] of Object.entries(cohort.personal_delta.input_pins)) assert.equal(coreInputPins[path], digest);
for (const [path, digest] of Object.entries(cohort.accepted_delta.input_pins)) assert.equal(coreInputPins[path], digest);
// New private modules extend fixed byte authority only; no package export or semantic admission.
const priorPersonalRefresh = await auditAuthority(cohort.prior_personal_cohort_authority);
assert.equal(cohort.prior_personal_cohort_authority.receipt_sha256, "2b0eff4a2e4cd2e190353c8f88ea4eaa6b4325b856f403981aa77df0b3ed9a19");
assert.deepEqual(priorPersonalRefresh.inputs.artifact_and_native_interface.committed_input_pins, priorPersonal.input_pins);
assert.deepEqual(priorPersonalRefresh.inputs.artifact_and_native_interface.existing_built_emitted_pins, priorPersonal.output_pins);
const location = await auditAuthority(cohort.location_delta);
const combined = await auditAuthority(cohort.combined_delta);
assert.equal(cohort.location_delta.receipt_sha256, "2709b73dfa64db2ba58e28b60cd9457e372e8e20c7e4175647927f750e167aca");
assert.equal(cohort.combined_delta.receipt_sha256, "2a853237f7f7dc145d9ccf49b1948c158c4f7cbe838f5a3569f96cedeea89e5f");
assert.equal(cohort.location_delta.committed_source_sha, "62a1547eb6c856c55ca5731e20de7f27cef27fe7");
assert.equal(cohort.combined_delta.committed_source_sha, "37580ca24a6d352d0ee2d8df2eca58e64e316d49");
const locationArtifact = location.inputs.artifact_and_native_interface;
const combinedArtifact = combined.inputs.artifact_and_native_interface;
assert.deepEqual(relativeMap(locationArtifact.patch_files), cohort.location_delta.input_pins);
assert.deepEqual(relativeMap(Object.fromEntries(Object.entries(combinedArtifact.patch_files).map(([path, pin]) => [path, pin.sha256]))), cohort.combined_delta.input_pins);
for (const [authority, vectorPath] of [[cohort.location_delta, "tests/location-point-projection-vectors.ts"], [cohort.combined_delta, "tests/combined-slice-vectors.ts"]]) {
  assert.equal(Object.keys(authority.input_pins).length, 3); assert.equal(Object.keys(authority.output_pins).length, 2);
  assert.equal(authority.vector_sha256, coreInputPins[vectorPath]);
}
assert.deepEqual({ ...priorPersonal.input_pins, ...cohort.location_delta.input_pins }, locationArtifact.complete_current_input_pins);
assert.deepEqual({ ...priorPersonal.output_pins, ...cohort.location_delta.output_pins }, locationArtifact.complete_emitted_pins);
assert.deepEqual({ ...locationArtifact.complete_current_input_pins, ...cohort.combined_delta.input_pins }, priorSlicesInputPins);
const sliceArtifacts = { ...personalArtifacts, ...cohort.location_delta.output_pins, ...cohort.combined_delta.output_pins };
assert.deepEqual(sliceArtifacts, priorSlices.output_pins);
assert.deepEqual(sliceArtifacts, combinedArtifact.complete_emitted_pins);
assert.deepEqual(priorSlicesInputPins, combinedArtifact.complete_current_input_pins);
assert.equal(Object.keys(sliceArtifacts).length, 24);
// Accepted private metadata gate extends fixed authority; no own refresh receipt or public export.
const slicesRefresh = await auditAuthority(cohort.prior_personal_slices_cohort_authority);
assert.equal(cohort.prior_personal_slices_cohort_authority.receipt_sha256, "faaa45e7d1d19a2cd4b69eec7f05d29bd332a4beacc1fcff36111259a462c602");
assert.deepEqual(slicesRefresh.inputs.artifact_and_native_interface.committed_input_pins, priorSlicesInputPins);
assert.deepEqual(slicesRefresh.inputs.artifact_and_native_interface.existing_built_emitted_pins, sliceArtifacts);
const eligibility = await auditAuthority(cohort.ios_eligibility_delta);
assert.equal(cohort.ios_eligibility_delta.receipt_sha256, "9a6e7da735c732dabe7dc1d77a1ff9d6aee0ee75bdb41cdf2e23a47e9862a93e");
assert.equal(cohort.ios_eligibility_delta.source_sha, "203c82f73560ca7cc6cce5ddf69c06bf3b124735");
assert.equal(cohort.ios_eligibility_delta.patch_digest, "bf5bd96a34f1938fccd10d39667a6de3f518bdc7a6343ade79f9b429cf8bf4ea");
assert.equal(cohort.ios_eligibility_delta.committed_source_sha, "8a31e6f038d4f74b8ed6acb0da5003e0329714f5");
const eligibilityArtifact = eligibility.inputs.artifact_and_native_interface;
assert.deepEqual(relativeMap(Object.fromEntries(Object.entries(eligibilityArtifact.patch_files).map(([path, pin]) => [path, pin.sha256]))), cohort.ios_eligibility_delta.input_pins);
assert.equal(Object.keys(cohort.ios_eligibility_delta.input_pins).length, 3);
assert.equal(Object.keys(cohort.ios_eligibility_delta.output_pins).length, 2);
assert.equal(cohort.ios_eligibility_delta.vector_sha256, "c8dcbaa0bec3ef32eb603aa85eb265bc7a715bbd70782bedfda0bb78c65f456b");
assert.equal(cohort.ios_eligibility_delta.vector_sha256, coreInputPins["tests/usage-mobile-ios-eligibility-vectors.ts"]);
assert.deepEqual({ ...priorSlicesInputPins, ...cohort.ios_eligibility_delta.input_pins }, coreInputPins);
const artifacts = { ...sliceArtifacts, ...cohort.ios_eligibility_delta.output_pins };
assert.deepEqual(artifacts, cohort.output_pins);
assert.deepEqual(coreInputPins, eligibilityArtifact.complete_current_input_pins);
assert.deepEqual(artifacts, eligibilityArtifact.complete_emitted_pins);
assert.equal(Object.keys(artifacts).length, 26);
// Current codec successor is a fixed tracked authority, distinct from the retained43/26.
const codecCohortPath = resolve("../../docs/migration/effect-refactor/cohorts/core-ts-exact-codecs-v1.json");
const codecCohortSha256 = "7e20aaaac8267225e96eabddea2d6a798e3fd6df501d95a550d6a2c23ac16055";
async function auditCodecCohort(path) {
  const stat = await lstat(path); assert.ok(stat.isFile() && !stat.isSymbolicLink(), "reviewed_core_cohort_bytes_drift");
  const bytes = await readFile(path); assert.equal(hash(bytes), codecCohortSha256, "reviewed_core_cohort_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.task_id, "CORE-COHORT-EXACT-CODECS");
  assert.equal(value.committed_source_sha, "1dfcca45c341eff72c89a67ed72638f4dc2db9fe");
  assert.deepEqual(value.runtime, { node: "24.21.0", npm: "11.19.0" });
  assert.equal(value.input_count, 56); assert.equal(value.output_count, 34);
  assert.equal(Object.keys(value.input_pins).length, 56); assert.equal(Object.keys(value.output_pins).length, 34);
  assert.deepEqual(value.historical43_26_authority.complete_historical_cohort, cohort);
  assert.deepEqual(value.historical43_26_authority.input_pins, coreInputPins);
  assert.deepEqual(value.historical43_26_authority.output_pins, artifacts);
  for (const [path, digest] of Object.entries(coreInputPins)) if (!["package.json", "README.md"].includes(path)) assert.equal(value.input_pins[path], digest);
  for (const [path, digest] of Object.entries(artifacts)) assert.equal(value.output_pins[path], digest);
  assert.deepEqual(value.negative_fixture_catalog.cases.slice(0, 84), cohort.negative_fixture_catalog.cases);
  assert.equal(value.negative_fixture_catalog.cases.length, 203);
  return value;
}
const codecCohort = await auditCodecCohort(codecCohortPath);
// The current consumer has exactly one mandatory authority. Fixture profiles below
// are internal disposable-copy stimuli and cannot select the consumer's cohort.
const sourceCatalogCohortPath = resolve("../../docs/migration/effect-refactor/cohorts/core-ts-source-catalog-v1.json");
const sourceCatalogCohortSha256 = "67828453f4fefc1b4c689507af9064ef1ab48672537a9360dc617da80964343d";
async function auditSourceCatalogCohort(path) {
  const stat = await lstat(path); assert.ok(stat.isFile() && !stat.isSymbolicLink(), "reviewed_core_cohort_bytes_drift");
  const bytes = await readFile(path);
  assert.equal(bytes.length, 856230, "reviewed_core_cohort_bytes_drift");
  assert.equal(hash(bytes), sourceCatalogCohortSha256, "reviewed_core_cohort_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.task_id, "CORE-COHORT-SOURCE-CATALOG");
  assert.equal(value.committed_source_sha, "227d323346773b938dba2e2f567a8d6cf33a09db");
  assert.deepEqual(value.runtime, {node:"24.21.0",npm:"11.19.0"});
  assert.equal(value.input_count,58); assert.equal(value.output_count,36);
  assert.equal(Object.keys(value.input_pins).length,58); assert.equal(Object.keys(value.output_pins).length,36);
  assert.deepEqual(value.historical_exact_codecs_authority.complete_historical_cohort, codecCohort);
  assert.deepEqual(value.catalog_literal_data_authority,codecCohort.catalog_literal_data_authority);
  assert.deepEqual(value.closed_catalog_semantic_validation,codecCohort.closed_catalog_semantic_validation);
  for(const [path,digest] of Object.entries(codecCohort.input_pins)) assert.equal(value.input_pins[path],digest);
  for(const [path,digest] of Object.entries(codecCohort.output_pins)) assert.equal(value.output_pins[path],digest);
  assert.deepEqual(value.negative_fixture_catalog.cases.slice(0,203),codecCohort.negative_fixture_catalog.cases);
  assert.equal(value.negative_fixture_catalog.cases.length,456);
  assert.equal(value.consumer_runtime_authority.required_current_profile,"current_source_catalog_58_36");
  assert.equal(value.consumer_runtime_authority.no_profile_selection_by_consumer,true);
  assert.equal(value.consumer_runtime_authority.no_own_receipt_reverse_pin,true);
  return value;
}
const sourceCatalogCohort = await auditSourceCatalogCohort(sourceCatalogCohortPath);
// Mandatory immutable successor; predecessor profiles remain test-only authorities.
const queryUsageCohortPath = resolve("../../docs/migration/effect-refactor/cohorts/core-ts-query-usage-v1.json");
const queryUsageCohortSha256 = "a006edbe5577fc46cfb1057cf67591f6aed8b25d0c187b05ccfd950b3a711c45";
const queryUsageProfile = "current_query_usage_64_40";
async function auditQueryUsageCohort(path) {
  await auditRawDocument(path, {bytes:1651134,sha256:queryUsageCohortSha256}, "reviewed_core_cohort_bytes_drift");
  const value = JSON.parse(await readFile(path,"utf8"));
  assert.equal(value.task_id,"CORE-COHORT-QUERY-USAGE");
  assert.equal(value.committed_source_sha,"32f38da439c0489648e99933c99d88805b76ca7b");
  assert.deepEqual(value.runtime,{node:"24.21.0",npm:"11.19.0"});
  assert.equal(value.input_count,64); assert.equal(value.output_count,40); assert.equal(value.emitted_output_count,59);
  assert.equal(Object.keys(value.input_pins).length,64); assert.equal(Object.keys(value.output_pins).length,40);
  assert.equal(value.complete_emitted_output_rows.length,59);
  assert.deepEqual(Object.fromEntries(value.complete_current_input_rows.map(r=>[r.path,r.sha256])),value.input_pins);
  assert.deepEqual(Object.fromEntries(value.complete_emitted_output_rows.map(r=>[r.path,r.sha256])),value.complete_emitted_output_pins);
  assert.deepEqual(Object.fromEntries(Object.entries(value.complete_emitted_output_pins).filter(([p])=>p.startsWith("dist/core/"))),value.output_pins);
  assert.deepEqual(value.historical_source_catalog_authority.complete_historical_cohort,sourceCatalogCohort);
  assert.equal(value.historical_source_catalog_authority.cohort.sha256,sourceCatalogCohortSha256);
  assert.deepEqual(value.catalog_literal_data_authority,sourceCatalogCohort.catalog_literal_data_authority);
  assert.deepEqual(value.closed_catalog_semantic_validation,sourceCatalogCohort.closed_catalog_semantic_validation);
  for(const [p,digest] of Object.entries(sourceCatalogCohort.input_pins)) {
    if(p!=="scripts/check-boundaries.mjs") assert.equal(value.input_pins[p],digest);
  }
  assert.equal(value.input_pins["scripts/check-boundaries.mjs"],"09076b02e2230e4a1c30277b2a58268f4372e998411b4acd1bd31672fdb905d5");
  for(const [p,digest] of Object.entries(sourceCatalogCohort.output_pins)) assert.equal(value.output_pins[p],digest);
  assert.equal(value.consumer_runtime_authority.required_current_profile,queryUsageProfile);
  assert.equal(value.consumer_runtime_authority.no_profile_selection_by_consumer,true);
  assert.equal(value.consumer_runtime_authority.no_own_receipt_reverse_pin,true);
  assert.equal(value.consumer_runtime_authority.historical_profiles_test_only,true);
  assert.equal(value.consumer_runtime_authority.scratch_paths_audit_only,true);
  assert.equal(value.consumer_runtime_authority.no_new_grant_native_public_authority,true);
  assert.deepEqual(Object.keys(value.qualification).sort(),["archive_payload_admission","collector_admission","consumer_admission","donor_source_adoption","native_profile_admission","physical_capture_admission","proof_class","public_profile_admission","rust_retirement_admission","source_grant_admission","status","storage_transaction_admission","unrestricted_full_history_admission"].sort());
  for(const [name,flag] of Object.entries(value.qualification)) if(name.endsWith("_admission")||name==="donor_source_adoption")assert.equal(flag,false);
  for(const flags of Object.values(value.producer_qualification_boundaries))for(const flag of Object.values(flags))assert.equal(flag,false);
  assert.deepEqual(Object.keys(value.normal_implementation_authorities).sort(),[...Object.keys(sourceCatalogCohort.normal_implementation_authorities),"QUERY-TYPED-VALUES","USAGE-DESKTOP-SESSION-PROJECTION"].sort());
  for(const [task,authority] of Object.entries(sourceCatalogCohort.normal_implementation_authorities))assert.deepEqual(value.normal_implementation_authorities[task],authority);
  assert.equal(value.normal_implementation_authorities["QUERY-TYPED-VALUES"].receipt.sha256,"8e92cf61648fd47396031dfb1077e755828a726bb8db665fe03d3f100eae1789");
  assert.equal(value.normal_implementation_authorities["USAGE-DESKTOP-SESSION-PROJECTION"].receipt.sha256,"b9da698595221fd8ec0039ca3bcb8f0ad1786f285763fbea3b8f4c0ce9ac195e");
  assert.deepEqual(value.negative_fixture_catalog.cases.slice(0,456),sourceCatalogCohort.negative_fixture_catalog.cases);
  assert.deepEqual(value.negative_fixture_catalog.execution_profile_bindings.slice(0,456),sourceCatalogCohort.negative_fixture_catalog.execution_profile_bindings);
  assert.equal(value.negative_fixture_catalog.cases.length,617);assert.equal(value.negative_fixture_catalog.execution_profile_bindings.length,617);
  assert.equal(value.positive_fixture_catalog.case_count,12);assert.equal(value.positive_fixture_catalog.cases.length,12);
  assert.equal(value.physical_toolchain_authority.complete_accepted_runtime_rows.length,676);
  assert.equal(value.physical_toolchain_authority.complete_accepted_archive_rows.length,3);
  assert.deepEqual(value.physical_toolchain_authority.component_metadata_lock_pins,sourceCatalogCohort.physical_toolchain_authority.component_metadata_lock_pins);
  assert.deepEqual(value.producer_evidence.counts,{tests:1544,suites:0,pass:1544,fail:0,cancelled:0,skipped:0,todo:0});
  assert.equal(value.producer_evidence.source_modules,20);assert.equal(value.producer_evidence.effect_installations,1);
  assert.equal(value.producer_evidence.boundary_negatives,19);
  return value;
}
const queryUsageCohort = await auditQueryUsageCohort(queryUsageCohortPath);
const qualifiedInputPins = queryUsageCohort.input_pins;
const qualifiedArtifacts = queryUsageCohort.output_pins;
function decodeHistoricalBoundary(blob) {
  const fail=()=>assert.fail("historical_input_evidence_bytes_drift");
  if(!blob||typeof blob!=="object"||Array.isArray(blob))return fail();
  if(JSON.stringify(Object.keys(blob).sort())!==JSON.stringify(["version","encoding","historical_path","bytes","sha256","data"].sort()))return fail();
  if(blob.version!==1||blob.encoding!=="base64"||blob.historical_path!=="packages/healthmd-core-ts/scripts/check-boundaries.mjs"||blob.bytes!==8065||blob.sha256!=="3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09"||typeof blob.data!=="string")return fail();
  if(blob.data.length!==4*Math.ceil(8065/3)||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(blob.data))return fail();
  const bytes=Buffer.from(blob.data,"base64");
  if(bytes.length!==8065||hash(bytes)!==blob.sha256||bytes.toString("base64")!==blob.data)return fail();
  return bytes;
}
const historicalBoundaryBytes=decodeHistoricalBoundary(queryUsageCohort.historical_input_reconstruction.blob);
assert.equal(hash(sourceManifest), qualifiedInputPins["package.json"], "reviewed_core_manifest_metadata_drift");
const codecTaskNames = ["CORE-CANDIDATE-CODEC-API", "PARSE-EXACT-JSON-NUMBERS", "PARSE-EXACT-JSON-VALUES", "SERIALIZE-CANONICAL-JSON", "SERIALIZE-EXACT-NUMBERS"];
assert.deepEqual(Object.keys(codecCohort.normal_implementation_authorities).sort(), codecTaskNames);
async function auditCodecAuthority(authority, path = resolve("../../", authority.receipt.path)) {
  const stat = await lstat(path); assert.ok(stat.isFile() && !stat.isSymbolicLink(), "qualified_core_receipt_bytes_drift");
  const bytes = await readFile(path);
  assert.equal(bytes.length, authority.receipt.bytes, "qualified_core_receipt_bytes_drift");
  assert.equal(hash(bytes), authority.receipt.sha256, "qualified_core_receipt_bytes_drift");
  const value = JSON.parse(bytes);
  assert.equal(value.task_id, authority.task_id); assert.equal(value.result, "passed", "qualified_core_receipt_required");
  assert.equal(value.review.status, "accepted", "qualified_core_receipt_required");
  assert.equal(value.source_sha, authority.source_sha); assert.equal(value.patch_digest, authority.patch_digest);
  assert.equal(value.review.fingerprint, authority.source_sha + "+" + authority.patch_digest);
  assert.equal(value.review.fingerprint, authority.review_fingerprint); assert.equal(value.review.reviewer, authority.reviewer);
  assert.equal(value.proof_class, "portable_synthetic");
  // External review/archive references are preserved audit metadata, never filesystem inputs.
  return value;
}
for (const name of codecTaskNames) await auditCodecAuthority(codecCohort.normal_implementation_authorities[name]);
const currentTaskNames = [...codecTaskNames,"DATASTORE-SOURCE-CATALOG"].sort();
assert.deepEqual(Object.keys(sourceCatalogCohort.normal_implementation_authorities).sort(),currentTaskNames);
for(const name of currentTaskNames) {
  const authority=sourceCatalogCohort.normal_implementation_authorities[name];
  const receipt=await auditCodecAuthority(authority);
  if(name==="DATASTORE-SOURCE-CATALOG") {
    assert.equal(receipt.stage,authority.required_stage);
    assert.deepEqual(receipt.target,authority.required_target);
    assert.equal(authority.required_result,"passed"); assert.equal(authority.required_review_status,"accepted");
    assert.equal(authority.proof_class,"portable_synthetic");
  } else assert.deepEqual(authority,codecCohort.normal_implementation_authorities[name]);
}
// Current producer receipts and accepted predecessor admission are strict raw authorities.
async function auditQueryUsageAuthority(authority,path=resolve("../../",authority.receipt.path)) {
  const value=await auditCodecAuthority(authority,path);
  assert.deepEqual(value.target,authority.required_target,"qualified_core_receipt_required");
  assert.deepEqual(value.limitations,authority.limitations,"qualified_core_receipt_required");
  assert.deepEqual(value.remaining_qualification,authority.remaining_qualification,"qualified_core_receipt_required");
  assert.deepEqual(value.review,authority.raw_review_metadata,"qualified_core_receipt_required");
  return value;
}
async function auditSourceCatalogAdmission(path=resolve("../../",queryUsageCohort.historical_source_catalog_authority.receipt.path)) {
  const authority=queryUsageCohort.historical_source_catalog_authority;
  await auditRawDocument(path,authority.receipt,"qualified_core_receipt_bytes_drift");
  const value=JSON.parse(await readFile(path,"utf8"));
  for(const [key,expected] of Object.entries(authority.required_receipt_semantics))assert.deepEqual(value[key],expected,"qualified_core_receipt_required");
  assert.equal(value.result,"passed");assert.equal(value.review.status,"accepted");assert.equal(value.proof_class,"portable_synthetic");
  assert.equal(value.review.fingerprint,value.source_sha+"+"+value.patch_digest);
  return value;
}
for(const task of ["QUERY-TYPED-VALUES","USAGE-DESKTOP-SESSION-PROJECTION"])await auditQueryUsageAuthority(queryUsageCohort.normal_implementation_authorities[task]);
await auditSourceCatalogAdmission();
function closedKeys(value, keys) {
  assert.ok(typeof value === "object" && value !== null && !Array.isArray(value), "catalog_literal_authority_mismatch");
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), "catalog_literal_authority_mismatch");
}
function embeddedCatalogBytes(name, expected) {
  const blob = codecCohort.embedded_raw_evidence[name];
  closedKeys(blob, ["version", "encoding", "historical_path", "bytes", "sha256", "data"]);
  assert.equal(blob.version, 1); assert.equal(blob.encoding, "base64");
  assert.equal(blob.historical_path, expected.path); // historical provenance only; never open it
  assert.equal(blob.bytes, expected.bytes); assert.equal(blob.sha256, expected.sha256);
  assert.ok(Number.isSafeInteger(blob.bytes) && blob.bytes > 0 && blob.bytes <= 52630);
  assert.equal(typeof blob.data, "string");
  assert.equal(blob.data.length, 4 * Math.ceil(blob.bytes / 3));
  assert.match(blob.data, /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/);
  const bytes = Buffer.from(blob.data, "base64");
  assert.equal(bytes.toString("base64"), blob.data, "catalog_literal_evidence_bytes_drift");
  assert.equal(bytes.length, expected.bytes, "catalog_literal_evidence_bytes_drift");
  assert.equal(hash(bytes), expected.sha256, "catalog_literal_evidence_bytes_drift");
  return bytes;
}
function parseCatalogRaw(bytes) { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes)); }
async function auditCatalogEvidence(pin, path) {
  const stat = await lstat(path); assert.ok(stat.isFile() && !stat.isSymbolicLink(), "catalog_literal_evidence_bytes_drift");
  const bytes = await readFile(path);
  assert.equal(bytes.length, pin.bytes, "catalog_literal_evidence_bytes_drift");
  assert.equal(hash(bytes), pin.sha256, "catalog_literal_evidence_bytes_drift");
  return parseCatalogRaw(bytes);
}
const catalogAuthority = codecCohort.catalog_literal_data_authority;
const expectedCatalogKeys = ["absent_component_paths", "case_count", "chain_rule", "current_partial_receipt", "exact_scope", "fingerprint", "independent_stage1_approval", "kind", "patch_digest", "required_approval_proof_class", "required_approval_result", "required_current_receipt_proof_class", "required_receipt_result", "required_receipt_review_fingerprint", "required_receipt_review_qualification", "required_receipt_review_status", "required_receipt_stage", "reviewed_partial_receipt_archive", "source_sha", "task_id", "vector", "version"];
closedKeys(catalogAuthority, expectedCatalogKeys);
assert.equal(catalogAuthority.kind, "CatalogLiteralDataAuthority"); assert.equal(catalogAuthority.version, 1);
const catalogFingerprint = "a0d2ab32357b69d6efeb7666b8ff4501605d2fbc+32cad15fbd56d61f47778ba0fef955f12ce8479d441c65a78d226faca9d708b0";
assert.equal(catalogAuthority.task_id, "DATASTORE-SOURCE-CATALOG");
assert.equal(catalogAuthority.source_sha, "a0d2ab32357b69d6efeb7666b8ff4501605d2fbc");
assert.equal(catalogAuthority.patch_digest, "32cad15fbd56d61f47778ba0fef955f12ce8479d441c65a78d226faca9d708b0");
assert.equal(catalogAuthority.fingerprint, catalogFingerprint); assert.equal(catalogAuthority.case_count, 96);
const catalogScope = { literal_source_input_only: true, implementation: false, behavior: false, runtime: false, module: false, grant: false, public: false, consumer_admission: false };
closedKeys(catalogAuthority.exact_scope, Object.keys(catalogScope)); assert.deepEqual(catalogAuthority.exact_scope, catalogScope);
assert.equal(catalogAuthority.vector.sha256, "74f638315c3db96f37306e26ac3a026204f629e3fee3d53bfad3203b03832591");
assert.equal(catalogAuthority.current_partial_receipt.sha256, "4f1c832b29e133b5b3671565e80100f738af9125b7d350bc7903d613a3f630aa");
assert.equal(catalogAuthority.independent_stage1_approval.sha256, "2340dc1e49bb5d24de7e6b89de2aa8277f4b198e54c23fa7689c57db39dc473b");
assert.equal(catalogAuthority.reviewed_partial_receipt_archive.sha256, "eda5dec7574e7dcfafffeeac7138ca1d278d9f15ee1b2bba5c97fac96ac19f42");
closedKeys(codecCohort.embedded_raw_evidence, ["catalog_stage1_approval", "catalog_reviewed_partial_receipt"]);
const catalogApprovalBytes = embeddedCatalogBytes("catalog_stage1_approval", catalogAuthority.independent_stage1_approval);
const catalogArchivedBytes = embeddedCatalogBytes("catalog_reviewed_partial_receipt", catalogAuthority.reviewed_partial_receipt_archive);
const catalogApproval = parseCatalogRaw(catalogApprovalBytes); const catalogArchived = parseCatalogRaw(catalogArchivedBytes);
// Historical partial raw bytes are authenticated embedded evidence, never the
// current tracked passed implementation receipt or a scratch filesystem input.
const catalogCurrentBytes = decodeHistoricalBlob(sourceCatalogCohort.embedded_raw_evidence.catalog_accepted_stage1_partial,
  sourceCatalogCohort.embedded_raw_evidence_contract.original_raw_expected.catalog_accepted_stage1_partial);
const catalogCurrent = parseCatalogRaw(catalogCurrentBytes);
for (const value of [catalogApproval, catalogArchived, catalogCurrent]) {
  assert.equal(value.task_id, catalogAuthority.task_id); assert.equal(value.source_sha, catalogAuthority.source_sha);
  assert.equal(value.patch_digest, catalogAuthority.patch_digest);
}
assert.equal(catalogApproval.result, "accepted"); assert.equal(catalogApproval.proof_class, "source_only_stage1_independent_review");
assert.equal(catalogApproval.fingerprint, catalogFingerprint); assert.deepEqual(catalogApproval.vector, catalogAuthority.vector);
assert.equal(catalogApproval.receipt.sha256, catalogAuthority.reviewed_partial_receipt_archive.sha256);
assert.equal(catalogApproval.receipt.bytes, catalogArchivedBytes.length);
for (const value of [catalogCurrent, catalogArchived]) { assert.equal(value.result, "partial"); assert.equal(value.proof_class, "portable_synthetic"); }
assert.equal(catalogCurrent.stage, "Stage1_96_literals_independently_accepted_implementation_queued");
assert.equal(catalogCurrent.review.status, "accepted_Stage1_interface_and_literals_only_implementation_pending");
assert.equal(catalogCurrent.review.fingerprint, catalogFingerprint);
assert.equal(catalogCurrent.review.evidence_sha256, catalogAuthority.independent_stage1_approval.sha256);
assert.equal(catalogCurrent.review.qualification, catalogAuthority.required_receipt_review_qualification);
assert.equal(catalogCurrent.history[1].receipt.sha256, catalogAuthority.reviewed_partial_receipt_archive.sha256);
assert.deepEqual(catalogCurrent.interface, catalogArchived.interface);
const catalogVectorBytes = await readFile(resolve("../../", catalogAuthority.vector.path));
assert.equal(catalogVectorBytes.length, catalogAuthority.vector.bytes); assert.equal(hash(catalogVectorBytes), catalogAuthority.vector.sha256);
closedKeys(sourceCatalogCohort.embedded_raw_evidence,sourceCatalogCohort.embedded_raw_evidence_contract.allowed_blob_names);
let embeddedTotal=0;
for(const name of sourceCatalogCohort.embedded_raw_evidence_contract.allowed_blob_names) {
  const bytes=decodeHistoricalBlob(sourceCatalogCohort.embedded_raw_evidence[name],sourceCatalogCohort.embedded_raw_evidence_contract.original_raw_expected[name]);
  embeddedTotal+=bytes.length;
}
assert.equal(embeddedTotal,sourceCatalogCohort.embedded_raw_evidence_contract.max_total_decoded_bytes);
function decodeHistoricalBlob(blob,pin) {
  const fail=()=>assert.fail("catalog_literal_evidence_bytes_drift");
  if(!blob||typeof blob!=="object"||Array.isArray(blob))return fail();
  if(JSON.stringify(Object.keys(blob).sort())!==JSON.stringify(["version","encoding","bytes","sha256","historical_path","data"].sort()))return fail();
  if(blob.version!==1||blob.encoding!=="base64"||blob.bytes!==pin.bytes||blob.sha256!==pin.sha256||typeof blob.historical_path!=="string"||typeof blob.data!=="string")return fail();
  if(!Number.isSafeInteger(blob.bytes)||blob.bytes<=0||blob.bytes>115680||blob.data.length!==4*Math.ceil(blob.bytes/3)||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(blob.data))return fail();
  const bytes=Buffer.from(blob.data,"base64");
  if(bytes.toString("base64")!==blob.data||bytes.length!==pin.bytes||hash(bytes)!==pin.sha256)return fail();
  return bytes;
}

async function tree(directory, skipBins = false) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (skipBins && entry.name === ".bin") continue;
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error("candidate_build_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await tree(path, skipBins)); else if (entry.isFile()) files.push(path); else throw new Error("candidate_file_type_unreviewed");
  }
  return files.sort();
}
async function inputTree(directory, current = directory) {
  const files = [];
  for (const entry of await readdir(current, { withFileTypes: true })) {
    // Only these exact component-root output paths are outside the reviewed input tree.
    if (current === directory && entry.isDirectory() && ["node_modules", "dist"].includes(entry.name)) continue;
    const path = join(current, entry.name);
    if (entry.isSymbolicLink()) throw new Error("candidate_source_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await inputTree(directory, path)); else if (entry.isFile()) files.push(path); else throw new Error("candidate_file_type_unreviewed");
  }
  return files.sort();
}
// Ordinary admission and disposable profiles share these exact algorithms.
// The ordinary wrappers always bind the current authenticated maps.
async function validateSourceInputs(directory, inputPins) {
  const files = await inputTree(directory);
  assert.deepEqual(files.map((path) => path.slice(directory.length + 1)), Object.keys(inputPins).sort(), "core_input_file_set_drift");
  for (const [path, digest] of Object.entries(inputPins)) assert.equal(hash(await readFile(join(directory, path))), digest, "core_input_bytes_drift");
}
async function validateOutputPackage(directory, outputPins, inputPins) {
  const rootStat = await lstat(directory);
  assert.equal(rootStat.isSymbolicLink(), false, "install_packed_core_with_install_links");
  assert.ok(rootStat.isDirectory(), "candidate_file_type_unreviewed");
  // Check both traversal components before reading any module. Descendant
  // checks alone cannot detect a symlink used as the traversal root.
  for (const component of ["dist", "dist/core"]) {
    const stat = await lstat(join(directory, component));
    if (stat.isSymbolicLink()) throw new Error("candidate_build_symlink_unreviewed");
    assert.ok(stat.isDirectory(), "candidate_file_type_unreviewed");
  }
  assert.equal(hash(await readFile(join(directory, "package.json"))), inputPins["package.json"], "core_manifest_drift");
  const files = await tree(join(directory, "dist/core"));
  assert.deepEqual(files.map((path) => path.slice(directory.length + 1)), Object.keys(outputPins).sort(), "core_build_file_set_drift");
  for (const [path, digest] of Object.entries(outputPins)) assert.equal(hash(await readFile(join(directory, path))), digest, "core_build_bytes_drift");
}
async function auditCoreInputs(directory) { await validateSourceInputs(directory, qualifiedInputPins); }
async function auditCore(directory) { await validateOutputPackage(directory, qualifiedArtifacts, qualifiedInputPins); }
async function validateCompleteProducerOutputs(directory) {
  const files=await tree(join(directory,"dist"));
  assert.deepEqual(files.map(p=>p.slice(directory.length+1)),Object.keys(queryUsageCohort.complete_emitted_output_pins).sort(),"core_complete_output_file_set_drift");
  for(const row of queryUsageCohort.complete_emitted_output_rows) {
    const bytes=await readFile(join(directory,row.path));
    assert.equal(bytes.length,row.bytes,"core_complete_output_bytes_drift");
    assert.equal(hash(bytes),row.sha256,"core_complete_output_bytes_drift");
  }
}
await auditCoreInputs(source);
await auditCore(source); await validateCompleteProducerOutputs(source); await auditCore(installed);
// Action-only mutation driver. IDs label observations AFTER the validator runs;
// expected failures are assertions only, never validator or mutation inputs.
const negativeIdentityCases=[];
const negativeExecutionProfiles=[];
const retainedDocumentPins={
  "docs/migration/effect-refactor/cohorts/core-ts-exact-codecs-v1.json": {
    "bytes": 256121,
    "sha256": "7e20aaaac8267225e96eabddea2d6a798e3fd6df501d95a550d6a2c23ac16055"
  },
  "docs/migration/effect-refactor/cohorts/core-ts-ios-eligibility-v1.json": {
    "bytes": 47904,
    "sha256": "25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761"
  },
  "docs/migration/effect-refactor/cohorts/core-ts-personal-slices-v1.json": {
    "bytes": 34945,
    "sha256": "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853"
  },
  "docs/migration/effect-refactor/cohorts/core-ts-personal-v1.json": {
    "bytes": 11123,
    "sha256": "a81df759ee321cf530137d9a6de6d18de2c3a4e42b92907444bde4e057f6b579"
  },
  "docs/migration/effect-refactor/receipts/COMBINED-SYNTHETIC.json": {
    "bytes": 90390,
    "sha256": "2a853237f7f7dc145d9ccf49b1948c158c4f7cbe838f5a3569f96cedeea89e5f"
  },
  "docs/migration/effect-refactor/receipts/CORE-CANDIDATE-CODEC-API.json": {
    "bytes": 197544,
    "sha256": "fbf14b4f4a714bd17433a5c3fbe89ccc46b9425d8d94ac6b9921610ecf5d019f"
  },
  "docs/migration/effect-refactor/receipts/DATASTORE-SOURCE-CATALOG.json": {
    "bytes": 133600,
    "sha256": "40aae1e46eaaa42a5d9220473b13ebe90af3453a5a6f33e2b947ca6f783752c5"
  },
  "docs/migration/effect-refactor/receipts/IOS-USAGE-ELIGIBILITY.json": {
    "bytes": 336408,
    "sha256": "9a6e7da735c732dabe7dc1d77a1ff9d6aee0ee75bdb41cdf2e23a47e9862a93e"
  },
  "docs/migration/effect-refactor/receipts/LOCATION-POINT-PROJECTION.json": {
    "bytes": 34523,
    "sha256": "2709b73dfa64db2ba58e28b60cd9457e372e8e20c7e4175647927f750e167aca"
  },
  "docs/migration/effect-refactor/receipts/PARSE-EXACT-JSON-NUMBERS.json": {
    "bytes": 83618,
    "sha256": "88fb9788d17a2c777b50eb306db516ec5682623fb4c6ad43c728d0604c324abb"
  },
  "docs/migration/effect-refactor/receipts/PARSE-EXACT-JSON-VALUES.json": {
    "bytes": 143547,
    "sha256": "9227a4fd1e488fb58f3c68983827e7b4b53712e84ae1a49f349a47cbb7164c5c"
  },
  "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json": {
    "bytes": 24593,
    "sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859"
  },
  "docs/migration/effect-refactor/receipts/SERIALIZE-CANONICAL-JSON.json": {
    "bytes": 376555,
    "sha256": "df942abf9eff71fc4b53ffc42968a48e8aff7f47c887910fd05bfd9306bc7e1f"
  },
  "docs/migration/effect-refactor/receipts/SERIALIZE-EXACT-NUMBERS.json": {
    "bytes": 42459,
    "sha256": "9100d985d40af66c026624c4050713477127f195dc9f20f45bbb20047f9d1f3e"
  }
};
// Ordinary retained raw gates and mutation copies share this exact validator.
// Strict normal receipt semantics above remain an additional mandatory gate.
for(const [path,pin]of Object.entries(retainedDocumentPins))
 await auditRawDocument(resolve("../../",path),pin,path.includes("/cohorts/")?"reviewed_core_cohort_bytes_drift":"qualified_core_receipt_bytes_drift");
const historicalEvidence=new Map([
 [catalogAuthority.current_partial_receipt.path,{bytes:catalogCurrentBytes,pin:catalogAuthority.current_partial_receipt}],
 [catalogAuthority.independent_stage1_approval.path,{bytes:catalogApprovalBytes,pin:catalogAuthority.independent_stage1_approval}],
 [catalogAuthority.reviewed_partial_receipt_archive.path,{bytes:catalogArchivedBytes,pin:catalogAuthority.reviewed_partial_receipt_archive}]
]);
async function auditRawDocument(path,pin,kind,missingDisposition="filesystem") {
 assert.ok(["filesystem","embedded_literal"].includes(missingDisposition),"unreviewed_evidence_disposition");
 if(missingDisposition==="embedded_literal")assert.equal(kind,"catalog_literal_evidence_bytes_drift");
 try {
  const stat=await lstat(path);assert.ok(stat.isFile()&&!stat.isSymbolicLink(),kind);
  const bytes=await readFile(path);assert.equal(bytes.length,pin.bytes,kind);assert.equal(hash(bytes),pin.sha256,kind);
 } catch(error) {
  // Missing authenticated historical evidence is a fixed evidence failure.
  // Ordinary source/package/receipt absence retains its filesystem disposition.
  if(missingDisposition==="embedded_literal"&&error?.code==="ENOENT")assert.fail(kind);
  throw error;
 }
}
async function auditFixtureInputs(root,pins) { await validateSourceInputs(root,pins); }
async function auditFixturePackage(root,pins,inputPins) { await validateOutputPackage(root,pins,inputPins); }
const jsonMutations=new Map([
 ["set committed_source_sha to unreviewed in disposable JSON",v=>{v.committed_source_sha="unreviewed";}],
 ["change committed_source_sha without updating expected hash",v=>{v.committed_source_sha="unreviewed";}],
 ["set review.status to pending in disposable JSON",v=>{v.review.status="pending";}],
 ["set review.status pending",v=>{v.review.status="pending";}],
 ["add review.status pending in disposable JSON",v=>{v.review={status:"pending"};}],
 ["set /review/status to pending in disposable JSON",v=>{v.review.status="pending";}],
 ["set /result to pending in disposable JSON",v=>{v.result="pending";}],
 ["set /result to unreviewed in disposable JSON (original partial, always changes bytes)",v=>{v.result="unreviewed";}],
 ["add ./candidate/unreviewed export",v=>{v.exports["./candidate/unreviewed"]="./dist/core/index.js";}],
 ["add an unlisted CatalogLiteralDataAuthority field in disposable JSON; never update expected hash",v=>{v.catalog_literal_data_authority.unlisted=true;}],
 ["add unlisted top-level authority field",v=>{v.unlisted=true;}],
 ["change proof_class to native-qualified in disposable JSON",v=>{v.proof_class="native-qualified";}],
 ["set proof_class to native-qualified",v=>{v.proof_class="native-qualified";}],
 ["change patch_digest in disposable JSON",v=>{v.patch_digest="unrelated_literal";}],
 ["change history[1].receipt.sha256 in disposable JSON",v=>{v.history[1].receipt.sha256="unrelated_literal";}],
 ["change receipt.sha256 in disposable approval JSON",v=>{v.receipt.sha256="unrelated_literal";}],
 ["set review.fingerprint to Stage1 fingerprint",v=>{v.review.fingerprint=catalogFingerprint;}],
 ["set task_id to arbitrary synthetic string",v=>{v.task_id="unrelated_literal";}],
 ["remove source-catalog source/test from fixed input map",v=>{delete v.input_pins["src/repository/source-catalog.ts"];delete v.input_pins["tests/source-catalog.test.ts"];}],
 ["remove repository/source-catalog js/dts from map",v=>{delete v.output_pins["dist/core/repository/source-catalog.js"];delete v.output_pins["dist/core/repository/source-catalog.d.ts"];}],
 ["use historical CatalogLiteralDataAuthority as implementation receipt",v=>{v.normal_implementation_authorities["DATASTORE-SOURCE-CATALOG"]=v.catalog_literal_data_authority;}],
 ["make actual consumer require scratch authority path",v=>{v.consumer_runtime_authority.required_scratch_path="/private/tmp/unreviewed";}],
 ["add current refresh ownreceipt into normal_implementation_authorities or required runtime authority",v=>{v.normal_implementation_authorities["CORE-COHORT-SOURCE-CATALOG"]={receipt:{path:"docs/migration/effect-refactor/receipts/CORE-COHORT-SOURCE-CATALOG.json"}};}],
 ["add arbitrary unreviewed implementation receipt discovered from directory",v=>{v.normal_implementation_authorities.UNREVIEWED={receipt:{path:"docs/migration/effect-refactor/receipts/UNREVIEWED.json"}};}]
]);
function changeJson(value,action,target) {
 const fixed=jsonMutations.get(action);if(fixed){fixed(value);return value;}
 const pointer=action.match(/^set (\/[a-z_\/]+) to unrelated_literal in disposable JSON; never update expected hash$/);
 if(pointer){const parts=pointer[1].slice(1).split("/");let cursor=value;for(const p of parts.slice(0,-1))cursor=cursor[p];cursor[parts.at(-1)]="unrelated_literal";return value;}
 const flag=action.match(/^set catalog_literal_data_authority.exact_scope.([a-z_]+) true in disposable JSON; never update expected hash$/);
 if(flag){assert.ok(Object.hasOwn(catalogScope,flag[1]));value.catalog_literal_data_authority.exact_scope[flag[1]]=true;return value;}
 if(action==="set false flag true without changing expected raw hash") {const parts=target.split(".");let cursor=value;for(const p of parts.slice(0,-1))cursor=cursor[p];cursor[parts.at(-1)]=true;return value;}
 assert.fail("unrealized_fixture_action");
}
const removeActions=new Set(["remove","absent disposable path","remove exact file","remove exact successor cohort","remove exact tracked accepted receipt"]);
const symlinkActions=new Set(["replace with symlink to retained original","replace exact file with symlink to retained original outside disposable input tree","replace exact file with symlink to retained original outside disposable module tree","replace with symlink to retained external original","replace cohort with symlink to original"]);
async function mutateFile(path,action,target,retained) {
 if(removeActions.has(action)){await rm(path);return;}
 if(symlinkActions.has(action)){await rm(path);await symlink(retained,path);return;}
 if(["replace bytes with export {}; LF","replace exact bytes with export {}; LF","add export {}; LF"].includes(action)){await writeFile(path,"export {};\n");return;}
 if(action==="replace bytes with unreviewed metadata LF"){await writeFile(path,"unreviewed metadata\n");return;}
 if(action.startsWith("append LF to disposable raw")){await writeFile(path,Buffer.concat([await readFile(path),Buffer.from("\n")]));return;}
 if(action==="append unreviewed comment to disposable vector"){await writeFile(path,Buffer.concat([await readFile(path),Buffer.from("\n// unreviewed\n")]));return;}
 if(action==="replace one byte without changing expected hash"){const bytes=await readFile(path);bytes[0]^=1;await writeFile(path,bytes);return;}
 if(action==="replace with exact historical4f partial bytes"){await writeFile(path,catalogCurrentBytes);return;}
 const value=parseCatalogRaw(await readFile(path));await writeFile(path,JSON.stringify(changeJson(value,action,target)));
}
const negativeOutcomes=[];
const positiveIdentityCases=[];
async function expectActualRejection(validate,expected) {
  let caught;
  try{await validate();}catch(error){caught=error;}
  assert.ok(caught,"fixture_mutation_was_accepted");
  const allowed=new Set(["ENOENT","candidate_build_symlink_unreviewed","candidate_source_symlink_unreviewed","catalog_literal_evidence_bytes_drift","core_build_bytes_drift","core_build_file_set_drift","core_input_bytes_drift","core_input_file_set_drift","core_manifest_drift","historical_input_evidence_bytes_drift","install_packed_core_with_install_links","qualified_core_receipt_bytes_drift","reviewed_core_cohort_bytes_drift"]);
  const actual=caught.code==="ENOENT"?"ENOENT":[...allowed].find(code=>code!=="ENOENT"&&String(caught.message).includes(code));
  assert.ok(actual,"fixture_rejection_not_fixed");assert.equal(actual,expected);
  return actual;
}
const temporary=await mkdtemp(join(tmpdir(),"healthmd-catalog-cohort-negatives-"));
try {
 const currentProfile={inputPins:sourceCatalogCohort.input_pins,outputPins:sourceCatalogCohort.output_pins};
 const historicalProfile={inputPins:codecCohort.input_pins,outputPins:codecCohort.output_pins};
 const profiles=new Map([["current_source_catalog_58_36",currentProfile],["historical_exact_codecs_56_34",historicalProfile]]);
 const bases=new Map();
 for(const [name,profile]of profiles) {
  const base=join(temporary,name);await mkdir(base);
  for(const path of Object.keys(profile.inputPins)){const dest=join(base,path);await mkdir(dirname(dest),{recursive:true});await writeFile(dest,path==="scripts/check-boundaries.mjs"?historicalBoundaryBytes:await readFile(join(source,path)));}
  for(const path of Object.keys(profile.outputPins)){const dest=join(base,path);await mkdir(dirname(dest),{recursive:true});await writeFile(dest,await readFile(join(source,path)));}
  await auditFixtureInputs(base,profile.inputPins);await auditFixturePackage(base,profile.outputPins,profile.inputPins);bases.set(name,base);
 }
 const cases=sourceCatalogCohort.negative_fixture_catalog.cases,bindings=sourceCatalogCohort.negative_fixture_catalog.execution_profile_bindings;
 assert.equal(cases.length,456);assert.equal(bindings.length,456);
 for(let i=0;i<cases.length;i++) {
  const row=cases[i],binding=bindings[i];assert.equal(binding.fixture_index,i);assert.equal(binding.candidate_profile_selectable,false);
  const profile=profiles.get(binding.profile);assert.ok(profile,"unreviewed_fixture_profile");
  const dir=join(temporary,"scene");await rm(dir,{recursive:true,force:true});await mkdir(dir);
  let validate;
  const target=row.target.replace(/^packages\/healthmd-core-ts\//,"");
  if(target==="installed core root") {
   assert.equal(row.mutation,"symlink to sibling core","unrealized_fixture_action");
   const link=join(dir,"linked");await symlink(bases.get(binding.profile),link,"dir");validate=()=>auditFixturePackage(link,profile.outputPins,profile.inputPins);
  } else if(target.startsWith("src/")||target.startsWith("tests/")||target==="README.md"||target==="package.json") {
   const copy=join(dir,"inputs");await cp(bases.get(binding.profile),copy,{recursive:true});
   // Remove generated modules before source audit: only exact component-root dist is excluded.
   const path=join(copy,target);await mkdir(dirname(path),{recursive:true});
   await mutateFile(path,row.mutation,target,join(bases.get(binding.profile),target));
   validate=target==="package.json"?()=>auditFixturePackage(copy,profile.outputPins,profile.inputPins):()=>auditFixtureInputs(copy,profile.inputPins);
  } else if(target==="dist"||target==="dist/core") {
   assert.equal(binding.profile,"current_source_catalog_58_36","unreviewed_fixture_profile");
   const action = target==="dist/core"
    ? "replace owned copied dist/core directory with symlink to retained external exact36 modules"
    : "replace owned copied dist directory with symlink to retained external exact dist/core36";
   assert.equal(row.mutation,action,"unrealized_fixture_action");
   const copy=join(dir,"packed");await cp(bases.get(binding.profile),copy,{recursive:true});
   const retained=join(dir,"retained");await cp(bases.get(binding.profile),retained,{recursive:true});
   await auditFixtureInputs(retained,profile.inputPins);
   await auditFixturePackage(retained,profile.outputPins,profile.inputPins);
   await auditFixturePackage(copy,profile.outputPins,profile.inputPins);
   // Both endpoints are fixed descendants of this fresh scene, never caller paths.
   for(const component of ["dist","dist/core"]) {
    const stat=await lstat(join(copy,component));assert.ok(stat.isDirectory()&&!stat.isSymbolicLink(),"candidate_file_type_unreviewed");
   }
   const path=join(copy,target);await rm(path,{recursive:true});
   await symlink(join(retained,target),path,"dir");
   validate=()=>auditFixturePackage(copy,profile.outputPins,profile.inputPins);
  } else if(target.startsWith("dist/core/")) {
   const copy=join(dir,"packed");await cp(bases.get(binding.profile),copy,{recursive:true});const path=join(copy,target);await mkdir(dirname(path),{recursive:true});
   await mutateFile(path,row.mutation,target,join(bases.get(binding.profile),target));validate=()=>auditFixturePackage(copy,profile.outputPins,profile.inputPins);
  } else if(target.startsWith("embedded_raw_evidence.")) {
   const name=target.slice("embedded_raw_evidence.".length),blob=sourceCatalogCohort.embedded_raw_evidence[name];assert.ok(blob);
   const file=join(dir,"embedded.json");
   if(["remove blob","change embedded raw base64 byte","replace closed blob with caller-controlled filesystem path"].includes(row.mutation)) {
    let value=structuredClone(blob);
    if(row.mutation==="remove blob")value=null;
    else if(row.mutation==="change embedded raw base64 byte")value.data=(value.data[0]==="A"?"B":"A")+value.data.slice(1);
    else value={path:"/private/tmp/unreviewed"};
    await writeFile(file,JSON.stringify(value));validate=async()=>decodeHistoricalBlob(JSON.parse(await readFile(file,"utf8")),sourceCatalogCohort.embedded_raw_evidence_contract.original_raw_expected[name]);
   } else {
    const pin=sourceCatalogCohort.embedded_raw_evidence_contract.original_raw_expected[name];await writeFile(file,decodeHistoricalBlob(blob,pin));
    await mutateFile(file,row.mutation,target,file+"-original");validate=()=>auditRawDocument(file,pin,"catalog_literal_evidence_bytes_drift","embedded_literal");
   }
  } else {
   const file=join(dir,"authority.json");let original,pin,kind;
   const historical= binding.profile==="historical_exact_codecs_56_34"?historicalEvidence.get(target):undefined;
   if(historical){original=historical.bytes;pin=historical.pin;kind="catalog_literal_evidence_bytes_drift";}
   else if(target.startsWith("historical_exact_codecs_authority.")){original=await readFile(sourceCatalogCohortPath);pin={bytes:856230,sha256:sourceCatalogCohortSha256};kind="reviewed_core_cohort_bytes_drift";}
   else if(target===sourceCatalogCohortPath.replace(resolve("../../")+"/","")||target==="docs/migration/effect-refactor/cohorts/core-ts-source-catalog-v1.json") {original=await readFile(sourceCatalogCohortPath);pin={bytes:856230,sha256:sourceCatalogCohortSha256};kind="reviewed_core_cohort_bytes_drift";}
   else {pin=retainedDocumentPins[target];assert.ok(pin,"unreviewed_fixture_target");original=await readFile(resolve("../../",target));kind=target.includes("/cohorts/")?"reviewed_core_cohort_bytes_drift":"qualified_core_receipt_bytes_drift";}
   const retained=join(dir,"original.json");await writeFile(retained,original);await writeFile(file,original);
   await auditRawDocument(file,pin,kind);
   await mutateFile(file,row.mutation,target,retained);
   const normal=Object.values(sourceCatalogCohort.normal_implementation_authorities).find(a=>a.receipt.path===target);
   if(normal&&!historical)validate=()=>auditCodecAuthority(normal,file);
   else if(pin.sha256===sourceCatalogCohortSha256)validate=()=>auditSourceCatalogCohort(file);
   else validate=()=>auditRawDocument(file,pin,kind);
  }
  // IDs and expected_failure are used only here, after action/validator selection.
  negativeOutcomes.push({id:row.id,profile:binding.profile,rejection:await expectActualRejection(validate,row.expected_failure)});
  negativeIdentityCases.push(row.id);negativeExecutionProfiles.push(binding.profile);
 }
 assert.deepEqual(negativeIdentityCases,cases.map(row=>row.id));
 assert.equal(negativeExecutionProfiles.filter(p=>p==="historical_exact_codecs_56_34").length,203);
 assert.equal(negativeExecutionProfiles.filter(p=>p==="current_source_catalog_58_36").length,253);
  // Structured successor actions operate only on owned copies and choose the
  // same source/module/raw-authority validators used by normal admission.
  const successorProfile={inputPins:qualifiedInputPins,outputPins:qualifiedArtifacts};
  profiles.set(queryUsageProfile,successorProfile);
  const successorBase=join(temporary,queryUsageProfile);await mkdir(successorBase);
  for(const path of Object.keys(qualifiedInputPins)) {
    const dest=join(successorBase,path);await mkdir(dirname(dest),{recursive:true});await writeFile(dest,await readFile(join(source,path)));
  }
  for(const path of Object.keys(qualifiedArtifacts)) {
    const dest=join(successorBase,path);await mkdir(dirname(dest),{recursive:true});await writeFile(dest,await readFile(join(source,path)));
  }
  await auditFixtureInputs(successorBase,qualifiedInputPins);await auditFixturePackage(successorBase,qualifiedArtifacts,qualifiedInputPins);
  bases.set(queryUsageProfile,successorBase);
  const receiptValidators=new Map([
    ...["QUERY-TYPED-VALUES","USAGE-DESKTOP-SESSION-PROJECTION"].map(task=>{
      const authority=queryUsageCohort.normal_implementation_authorities[task];
      return [authority.receipt.path,file=>auditQueryUsageAuthority(authority,file)];
    }),
    [queryUsageCohort.historical_source_catalog_authority.receipt.path,file=>auditSourceCatalogAdmission(file)]
  ]);
  function ownedPath(root,path) {
    assert.equal(typeof path,"string","unrealized_fixture_action");
    assert.ok(path.length>0&&!path.startsWith("/")&&!path.split("/").some(p=>p===".."||p==="."||p===""),"unrealized_fixture_action");
    return join(root,path);
  }
  async function mutateStructuredFile(file,action,retained) {
    switch(action.op) {
      case "none":return;
      case "remove":await rm(file);return;
      case "append_bytes":await writeFile(file,Buffer.concat([await readFile(file),Buffer.from(action.utf8,"utf8")]));return;
      case "replace_malformed_bytes":assert.match(action.hex,/^(?:[0-9a-f]{2})+$/);await writeFile(file,Buffer.from(action.hex,"hex"));return;
      case "symlink_to_retained_original":await rm(file);await symlink(retained,file);return;
      case "symlink_directory_to_retained_original":await rm(file,{recursive:true});await symlink(retained,file,"dir");return;
      case "create_file":await mkdir(dirname(file),{recursive:true});await writeFile(file,action.utf8,"utf8");return;
      case "json_set":case "json_delete": {
        assert.equal(typeof action.pointer,"string");assert.ok(action.pointer.startsWith("/"));
        const parts=action.pointer.slice(1).split("/").map(p=>p.replace(/~1/g,"/").replace(/~0/g,"~"));
        assert.ok(parts.every(p=>!['__proto__','constructor','prototype'].includes(p)),"unrealized_fixture_action");
        const value=JSON.parse(await readFile(file,"utf8"));let cursor=value;
        for(const p of parts.slice(0,-1)){assert.ok(Object.hasOwn(cursor,p),"unrealized_fixture_action");cursor=cursor[p];}
        const key=parts.at(-1);
        if(action.op==="json_delete"){assert.ok(Object.hasOwn(cursor,key),"unrealized_fixture_action");delete cursor[key];}
        else cursor[key]=action.value;
        await writeFile(file,JSON.stringify(value));return;
      }
      default:assert.fail("unrealized_fixture_action");
    }
  }
  async function prepareStructuredScene(action,profileName) {
    const profile=profiles.get(profileName);assert.ok(profile,"unreviewed_fixture_profile");
    const dir=join(temporary,"successor-scene");await rm(dir,{recursive:true,force:true});await mkdir(dir);
    let validate,file,retained;
    if(action.group==="source"||action.group==="module") {
      const copy=join(dir,"copy");await cp(bases.get(profileName),copy,{recursive:true});
      validate=action.group==="source"?()=>auditFixtureInputs(copy,profile.inputPins):()=>auditFixturePackage(copy,profile.outputPins,profile.inputPins);
      // Verify pristine copy through the same validator before every stimulus.
      await validate();
      if(action.op!=="none") {
        if(action.path==="installed core root") {assert.equal(action.group,"module");file=copy;retained=bases.get(profileName);}
        else {file=ownedPath(copy,action.path);retained=ownedPath(bases.get(profileName),action.path);}
        await mutateStructuredFile(file,action,retained);
      }
      return validate;
    }
    if(action.group==="receipt"||action.group==="cohort") {
      if(action.group==="receipt") {
        const validator=receiptValidators.get(action.path);assert.ok(validator,"unreviewed_fixture_target");
        const original=resolve("../../",action.path);file=join(dir,"authority.json");retained=original;
        await writeFile(file,await readFile(original));validate=()=>validator(file);
      } else {
        assert.equal(action.path,"docs/migration/effect-refactor/cohorts/core-ts-query-usage-v1.json","unreviewed_fixture_target");
        file=join(dir,"cohort.json");retained=queryUsageCohortPath;
        await writeFile(file,await readFile(retained));validate=()=>auditQueryUsageCohort(file);
      }
      await validate();await mutateStructuredFile(file,action,retained);return validate;
    }
    if(action.group==="historical_blob") {
      assert.equal(action.path,"historical_boundary_script","unreviewed_fixture_target");
      file=join(dir,"boundary-blob.json");let blob=structuredClone(queryUsageCohort.historical_input_reconstruction.blob);
      await writeFile(file,JSON.stringify(blob));validate=async()=>decodeHistoricalBoundary(JSON.parse(await readFile(file,"utf8")));
      await validate();
      if(action.op==="remove_blob")blob=null;
      else if(action.op==="tamper_base64")blob.data=(blob.data[0]==="A"?"B":"A")+blob.data.slice(1);
      else if(action.op==="replace_blob_with_path")blob={path:"/private/tmp/unreviewed"};
      else assert.fail("unrealized_fixture_action");
      await writeFile(file,JSON.stringify(blob));return validate;
    }
    assert.fail("unrealized_fixture_action");
  }
  for(const row of queryUsageCohort.positive_fixture_catalog.cases) {
    const action={...row.action,group:row.group,path:row.action.path??row.target};
    const validate=await prepareStructuredScene(action,row.profile);
    await validate();assert.equal(row.expected,"accepted");positiveIdentityCases.push(row.id);
  }
  for(let i=456;i<queryUsageCohort.negative_fixture_catalog.cases.length;i++) {
    const row=queryUsageCohort.negative_fixture_catalog.cases[i];
    const binding=queryUsageCohort.negative_fixture_catalog.execution_profile_bindings[i];
    assert.equal(binding.fixture_index,i);assert.equal(binding.profile,queryUsageProfile);assert.equal(binding.candidate_profile_selectable,false);
    const validate=await prepareStructuredScene(row.action,binding.profile);
    const rejection=await expectActualRejection(validate,row.expected_failure);
    negativeIdentityCases.push(row.id);negativeExecutionProfiles.push(binding.profile);
    negativeOutcomes.push({id:row.id,profile:binding.profile,rejection});
  }
  assert.deepEqual(negativeIdentityCases,queryUsageCohort.negative_fixture_catalog.cases.map(r=>r.id));
  assert.deepEqual(negativeExecutionProfiles,queryUsageCohort.negative_fixture_catalog.execution_profile_bindings.map(r=>r.profile));
  assert.deepEqual(negativeOutcomes.map(r=>r.rejection),queryUsageCohort.negative_fixture_catalog.cases.map(r=>r.expected_failure));
  assert.deepEqual(positiveIdentityCases,queryUsageCohort.positive_fixture_catalog.cases.map(r=>r.id));
} finally {await rm(temporary,{recursive:true,force:true});}
await assert.rejects(lstat(temporary),{code:"ENOENT"});
const filesystemCleanupAcknowledged=true;

const coreUrl = import.meta.resolve("@healthmd/core-ts");
const hostUrl = import.meta.resolve("@healthmd/core-ts/host-interfaces");
const actualEffect = await realpath(fileURLToPath(import.meta.resolve("effect/Effect")));
const candidateUrls = ["catalog", "normalize", "query", "registry", "codecs"].map((name) => import.meta.resolve(`@healthmd/core-ts/candidate/${name}`));
for (const url of [coreUrl, hostUrl, ...candidateUrls]) {
  assert.ok((await realpath(fileURLToPath(url))).startsWith((await realpath(installed)) + "/"), "core_export_escaped_packed_package");
  assert.equal(await realpath(createRequire(url).resolve("effect/Effect")), actualEffect, "effect_physical_identity_drift");
}
const launchers = { esbuild: "node_modules/esbuild/bin/esbuild", tsc: "node_modules/typescript/bin/tsc" };
assert.deepEqual((await readdir("node_modules/.bin")).sort(), Object.keys(launchers).sort(), "unreviewed_tool_launcher");
for (const [name, target] of Object.entries(launchers)) {
  const launcher = `node_modules/.bin/${name}`;
  assert.equal((await lstat(launcher)).isSymbolicLink(), true, "expected_npm_tool_launcher");
  assert.equal(await realpath(launcher), await realpath(target), "tool_launcher_target_drift");
}
const effects = [];
for (const path of await tree("node_modules", true)) {
  assert.equal(path.endsWith(".node"), false, "native_addon_unreviewed");
  if (path.endsWith("/effect/package.json")) effects.push(path);
}
assert.equal(effects.length, 1, "duplicate_effect_installation");
const core = await import(coreUrl); const host = await import(hostUrl);
const codecs = await import(import.meta.resolve("@healthmd/core-ts/candidate/codecs"));
assert.deepEqual(Object.keys(codecs).sort(), ["createCanonicalJsonSerializer", "createExactJsonCodec", "createExactJsonNumberParser", "serializeExactJsonNumber"]);
assert.equal(core.CandidateSession, host.CandidateSession, "service_identity_drift");
await new Promise((done, fail) => process.stdout.write(JSON.stringify({ qualifiedCoreFiles: Object.keys(qualifiedArtifacts).length, qualifiedCoreInputs: Object.keys(qualifiedInputPins).length, packedLocalCore: true,
  physicalEffectInstallations: effects.length, reviewedToolLaunchers: Object.keys(launchers), serviceIdentity: true, completeProducerOutputs:59, negativeIdentityCases, negativeExecutionProfiles, negativeOutcomes, positiveIdentityCases, filesystemCleanupAcknowledged }) + "\n", error => error ? fail(error) : done()));
function run(args) { const result = spawnSync(process.execPath, args, { stdio: "inherit" }); if (result.status !== 0) process.exit(result.status ?? 1); }
if (!process.argv.includes("--tests-only")) { run(["node_modules/typescript/bin/tsc", "--project", "tsconfig.json"]); run(["scripts/build-candidate.mjs"]); }
const compiled = (await tree("dist/tests")).filter((path) => path.endsWith(".test.js"));
assert.ok(compiled.length > 0, "candidate_tests_missing");
const graph = JSON.parse(await readFile("dist/test-metafile.json", "utf8"));
assert.ok(Object.keys(graph.inputs).every((path) => !path.includes("node_modules")), "dependencies_must_remain_external");
run(["--test", ...compiled]);
console.log("CLI candidate check passed: exact runtime, packed core identity, typecheck, compiled test build and lifecycle");
