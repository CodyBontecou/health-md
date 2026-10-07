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
assert.equal(hash(sourceManifest), coreInputPins["package.json"], "reviewed_core_manifest_metadata_drift");
async function tree(directory, skipBins = false) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (skipBins && entry.name === ".bin") continue;
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error("candidate_build_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await tree(path, skipBins)); else if (entry.isFile()) files.push(path);
  }
  return files.sort();
}
async function inputTree(directory, current = directory) {
  const files = [];
  for (const entry of await readdir(current, { withFileTypes: true })) {
    // Only these exact component-root output paths are outside the reviewed input tree.
    if (current === directory && entry.isDirectory() && ["node_modules", "dist", "build"].includes(entry.name)) continue;
    const path = join(current, entry.name);
    if (entry.isSymbolicLink()) throw new Error("candidate_source_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await inputTree(directory, path)); else if (entry.isFile()) files.push(path);
  }
  return files.sort();
}
async function auditCoreInputs(directory) {
  const files = await inputTree(directory);
  assert.deepEqual(files.map((path) => path.slice(directory.length + 1)), Object.keys(coreInputPins).sort(), "core_input_file_set_drift");
  for (const [path, digest] of Object.entries(coreInputPins)) assert.equal(hash(await readFile(join(directory, path))), digest, "core_input_bytes_drift");
}
await auditCoreInputs(source);
async function auditCore(directory) {
  assert.equal((await lstat(directory)).isSymbolicLink(), false, "install_packed_core_with_install_links");
  assert.deepEqual(await readFile(join(directory, "package.json")), sourceManifest, "core_manifest_drift");
  const files = await tree(join(directory, "dist/core"));
  assert.deepEqual(files.map((path) => path.slice(directory.length + 1)), Object.keys(artifacts).sort(), "core_build_file_set_drift");
  for (const [path, digest] of Object.entries(artifacts)) assert.equal(hash(await readFile(join(directory, path))), digest, "core_build_bytes_drift");
}
await auditCore(source); await auditCore(installed);
// Exercise actual filesystem failures in disposable copies, never alter installed/source packages.
const negativeIdentityCases = [];
const temporary = await mkdtemp(join(tmpdir(), "healthmd-cli-identity-"));
try {
  const inputCopy = join(temporary, "inputs");
  for (const path of Object.keys(coreInputPins)) {
    const target = join(inputCopy, path); await mkdir(dirname(target), { recursive: true });
    await writeFile(target, await readFile(join(source, path)));
  }
  await auditCoreInputs(inputCopy);
  await writeFile(join(inputCopy, "src/index.ts"), "export {};\n");
  await assert.rejects(auditCoreInputs(inputCopy), /core_input_bytes_drift/);
  await writeFile(join(inputCopy, "src/index.ts"), await readFile(join(source, "src/index.ts")));
  await writeFile(join(inputCopy, "src/unbuilt-extra.ts"), "export {};\n");
  await assert.rejects(auditCoreInputs(inputCopy), /core_input_file_set_drift/);
  const linked = join(temporary, "linked"); await symlink(installed, linked, "dir");
  await assert.rejects(auditCore(linked), /install_packed_core_with_install_links/);
  await rm(join(inputCopy, "src/unbuilt-extra.ts"));
  await writeFile(join(inputCopy, "README.md"), "unreviewed metadata\n");
  await assert.rejects(auditCoreInputs(inputCopy), /core_input_bytes_drift/);
  await writeFile(join(inputCopy, "README.md"), await readFile(join(source, "README.md")));
  const altered = join(temporary, "altered"); await cp(installed, altered, { recursive: true });
  const alteredManifest = JSON.parse(await readFile(join(altered, "package.json"), "utf8"));
  alteredManifest.exports["./candidate/unreviewed"] = "./dist/core/index.js";
  await writeFile(join(altered, "package.json"), JSON.stringify(alteredManifest));
  await assert.rejects(auditCore(altered), /core_manifest_drift/);
  const stale = join(temporary, "stale"); await cp(installed, stale, { recursive: true });
  await writeFile(join(stale, "dist/core/index.js"), "export {};\n");
  await assert.rejects(auditCore(stale), /core_build_bytes_drift/);
  await rm(join(inputCopy, "src/serialization/exact-json-numbers.ts"));
  await assert.rejects(auditCoreInputs(inputCopy), /core_input_file_set_drift/);
  await writeFile(join(inputCopy, "src/serialization/exact-json-numbers.ts"), "export {};\n");
  await assert.rejects(auditCoreInputs(inputCopy), /core_input_bytes_drift/);
  await rm(join(inputCopy, "src/serialization/exact-json-numbers.ts"));
  await symlink(join(source, "src/serialization/exact-json-numbers.ts"), join(inputCopy, "src/serialization/exact-json-numbers.ts"));
  await assert.rejects(auditCoreInputs(inputCopy), /candidate_source_symlink_unreviewed/);
  const numericOutput = "dist/core/serialization/exact-json-numbers.js";
  const changedNumeric = join(temporary, "changed-numeric"); await cp(installed, changedNumeric, { recursive: true });
  await writeFile(join(changedNumeric, numericOutput), "export {};\n");
  await assert.rejects(auditCore(changedNumeric), /core_build_bytes_drift/);
  await rm(join(changedNumeric, numericOutput));
  await assert.rejects(auditCore(changedNumeric), /core_build_file_set_drift/);
  await writeFile(join(changedNumeric, numericOutput), await readFile(join(installed, numericOutput)));
  await writeFile(join(changedNumeric, "dist/core/unreviewed.js"), "export {};\n");
  await assert.rejects(auditCore(changedNumeric), /core_build_file_set_drift/);
  await rm(join(changedNumeric, "dist/core/unreviewed.js"));
  await rm(join(changedNumeric, numericOutput));
  await symlink(join(installed, numericOutput), join(changedNumeric, numericOutput));
  await assert.rejects(auditCore(changedNumeric), /candidate_build_symlink_unreviewed/);
  const personalSource = "src/contracts/personal-slice.ts";
  const personalInputCopy = join(temporary, "personal-inputs");
  for (const path of Object.keys(coreInputPins)) {
    const target = join(personalInputCopy, path); await mkdir(dirname(target), { recursive: true });
    await writeFile(target, await readFile(join(source, path)));
  }
  await auditCoreInputs(personalInputCopy);
  await rm(join(personalInputCopy, personalSource));
  await assert.rejects(auditCoreInputs(personalInputCopy), /core_input_file_set_drift/);
  await writeFile(join(personalInputCopy, personalSource), "export {};\n");
  await assert.rejects(auditCoreInputs(personalInputCopy), /core_input_bytes_drift/);
  await rm(join(personalInputCopy, personalSource));
  await symlink(join(source, personalSource), join(personalInputCopy, personalSource));
  await assert.rejects(auditCoreInputs(personalInputCopy), /candidate_source_symlink_unreviewed/);
  const personalOutput = "dist/core/contracts/personal-slice.js";
  const changedPersonal = join(temporary, "changed-personal"); await cp(installed, changedPersonal, { recursive: true });
  await writeFile(join(changedPersonal, personalOutput), "export {};\n");
  await assert.rejects(auditCore(changedPersonal), /core_build_bytes_drift/);
  await rm(join(changedPersonal, personalOutput));
  await assert.rejects(auditCore(changedPersonal), /core_build_file_set_drift/);
  await writeFile(join(changedPersonal, personalOutput), await readFile(join(installed, personalOutput)));
  await writeFile(join(changedPersonal, "dist/core/contracts/unreviewed-personal.js"), "export {};\n");
  await assert.rejects(auditCore(changedPersonal), /core_build_file_set_drift/);
  await rm(join(changedPersonal, "dist/core/contracts/unreviewed-personal.js"));
  await rm(join(changedPersonal, personalOutput));
  await symlink(join(installed, personalOutput), join(changedPersonal, personalOutput));
  await assert.rejects(auditCore(changedPersonal), /candidate_build_symlink_unreviewed/);
  const unreviewedPersonal = join(temporary, "unreviewed-personal.json");
  await writeFile(unreviewedPersonal, JSON.stringify({ ...personal, review: { ...personal.review, status: "pending" } }));
  await assert.rejects(auditAuthority(cohort.personal_delta, unreviewedPersonal), /qualified_core_receipt_bytes_drift/);
  const absentCohort = join(temporary, "absent-cohort.json");
  await assert.rejects(auditPriorPersonalCohort(absentCohort), { code: "ENOENT" });
  const tamperedCohort = join(temporary, "tampered-cohort.json");
  await writeFile(tamperedCohort, JSON.stringify({ ...priorPersonal, committed_source_sha: "unreviewed" }));
  await assert.rejects(auditPriorPersonalCohort(tamperedCohort), /reviewed_core_cohort_bytes_drift/);
  const unreviewedDelta = join(temporary, "unreviewed-delta.json");
  await writeFile(unreviewedDelta, JSON.stringify({ ...delta, review: { ...delta.review, status: "pending" } }));
  await assert.rejects(auditAuthority(cohort.accepted_delta, unreviewedDelta), /qualified_core_receipt_bytes_drift/);
  // Record retained cases only after their actual filesystem assertions above complete.
  negativeIdentityCases.push(...["sibling-symlink", "stale-build", "unbuilt-source-edit", "extra-source-file", "unreviewed-metadata-edit", "unreviewed-packed-export", "missing-source-file", "new-module-edit", "source-symlink", "new-module-stale-output", "missing-output", "extra-output", "output-symlink", "absent-cohort", "tampered-cohort", "unreviewed-delta", "missing-personal-source", "personal-source-edit", "personal-source-symlink", "personal-output-stale", "missing-personal-output", "extra-personal-output", "personal-output-symlink", "unreviewed-personal-receipt"]);
  const sliceSourcePaths = [
  "src/location/point-projection.ts",
  "src/operations/personal-slice.ts",
  "tests/combined-slice-vectors.ts",
  "tests/combined-slice.test.ts",
  "tests/location-point-projection-vectors.ts",
  "tests/location-point-projection.test.ts"
];
  const sliceOutputPaths = [
  "dist/core/location/point-projection.d.ts",
  "dist/core/location/point-projection.js",
  "dist/core/operations/personal-slice.d.ts",
  "dist/core/operations/personal-slice.js"
];
  for (const path of sliceSourcePaths) {
    const copy = join(temporary, "slice-inputs");
    await rm(copy, { recursive: true, force: true });
    for (const input of Object.keys(coreInputPins)) {
      const target = join(copy, input); await mkdir(dirname(target), { recursive: true });
      await writeFile(target, await readFile(join(source, input)));
    }
    await auditCoreInputs(copy);
    await rm(join(copy, path));
    await assert.rejects(auditCoreInputs(copy), /core_input_file_set_drift/);
    negativeIdentityCases.push(`slice-source:${path}:missing`);
    await writeFile(join(copy, path), "export {};\n");
    await assert.rejects(auditCoreInputs(copy), /core_input_bytes_drift/);
    negativeIdentityCases.push(`slice-source:${path}:edited`);
    await rm(join(copy, path)); await symlink(join(source, path), join(copy, path));
    await assert.rejects(auditCoreInputs(copy), /candidate_source_symlink_unreviewed/);
    negativeIdentityCases.push(`slice-source:${path}:symlink`);
  }
  for (const path of sliceOutputPaths) {
    const copy = join(temporary, "slice-outputs");
    await rm(copy, { recursive: true, force: true }); await cp(installed, copy, { recursive: true });
    await auditCore(copy);
    await rm(join(copy, path));
    await assert.rejects(auditCore(copy), /core_build_file_set_drift/);
    negativeIdentityCases.push(`slice-output:${path}:missing`);
    await writeFile(join(copy, path), "export {};\n");
    await assert.rejects(auditCore(copy), /core_build_bytes_drift/);
    negativeIdentityCases.push(`slice-output:${path}:stale`);
    await rm(join(copy, path)); await symlink(join(installed, path), join(copy, path));
    await assert.rejects(auditCore(copy), /candidate_build_symlink_unreviewed/);
    negativeIdentityCases.push(`slice-output:${path}:symlink`);
  }
  const extraCopy = join(temporary, "slice-extra-output"); await cp(installed, extraCopy, { recursive: true });
  await auditCore(extraCopy);
  await writeFile(join(extraCopy, "dist/core/operations/unreviewed-slice.js"), "export {};\n");
  await assert.rejects(auditCore(extraCopy), /core_build_file_set_drift/);
  negativeIdentityCases.push("slice-extra-output");
  await assert.rejects(auditPriorSlicesCohort(join(temporary, "absent-slice-cohort.json")), { code: "ENOENT" });
  negativeIdentityCases.push("slice-cohort:absent");
  const changedCohort = join(temporary, "changed-slice-cohort.json");
  await writeFile(changedCohort, JSON.stringify({ ...priorSlices, committed_source_sha: "unreviewed" }));
  await assert.rejects(auditPriorSlicesCohort(changedCohort), /reviewed_core_cohort_bytes_drift/);
  negativeIdentityCases.push("slice-cohort:tampered");
  for (const name of ["location_delta", "combined_delta"]) {
    const authority = cohort[name]; const bytes = await readFile(resolve("../../", authority.receipt_path));
    const copy = join(temporary, `${name}.json`);
    await assert.rejects(auditAuthority(authority, copy), { code: "ENOENT" });
    negativeIdentityCases.push(`slice-receipt:${name}:absent`);
    await writeFile(copy, Buffer.concat([bytes, Buffer.from("\n")]));
    await assert.rejects(auditAuthority(authority, copy), /qualified_core_receipt_bytes_drift/);
    negativeIdentityCases.push(`slice-receipt:${name}:tampered`);
    const value = JSON.parse(bytes);
    await writeFile(copy, JSON.stringify({ ...value, review: { ...value.review, status: "pending" } }));
    await assert.rejects(auditAuthority(authority, copy), /qualified_core_receipt_bytes_drift/);
    negativeIdentityCases.push(`slice-receipt:${name}:unreviewed`);
    await rm(copy);
  }
  // All 63 historical cases precede exactly the independently frozen 21 eligibility cases.
  for (const path of Object.keys(cohort.ios_eligibility_delta.input_pins).sort()) {
    const copy = join(temporary, "eligibility-inputs");
    await rm(copy, { recursive: true, force: true });
    for (const input of Object.keys(coreInputPins)) {
      const target = join(copy, input); await mkdir(dirname(target), { recursive: true });
      await writeFile(target, await readFile(join(source, input)));
    }
    await auditCoreInputs(copy);
    await rm(join(copy, path));
    await assert.rejects(auditCoreInputs(copy), /core_input_file_set_drift/);
    negativeIdentityCases.push(`eligibility-input:${path}:missing`);
    await writeFile(join(copy, path), "export {};\n");
    await assert.rejects(auditCoreInputs(copy), /core_input_bytes_drift/);
    negativeIdentityCases.push(`eligibility-input:${path}:edited`);
    await rm(join(copy, path)); await symlink(join(source, path), join(copy, path));
    await assert.rejects(auditCoreInputs(copy), /candidate_source_symlink_unreviewed/);
    negativeIdentityCases.push(`eligibility-input:${path}:symlink`);
  }
  for (const path of Object.keys(cohort.ios_eligibility_delta.output_pins).sort()) {
    const copy = join(temporary, "eligibility-outputs");
    await rm(copy, { recursive: true, force: true }); await cp(installed, copy, { recursive: true });
    await auditCore(copy);
    await rm(join(copy, path));
    await assert.rejects(auditCore(copy), /core_build_file_set_drift/);
    negativeIdentityCases.push(`eligibility-output:${path}:missing`);
    await writeFile(join(copy, path), "export {};\n");
    await assert.rejects(auditCore(copy), /core_build_bytes_drift/);
    negativeIdentityCases.push(`eligibility-output:${path}:stale`);
    await rm(join(copy, path)); await symlink(join(installed, path), join(copy, path));
    await assert.rejects(auditCore(copy), /candidate_build_symlink_unreviewed/);
    negativeIdentityCases.push(`eligibility-output:${path}:symlink`);
  }
  const eligibilityExtraCopy = join(temporary, "eligibility-extra-output");
  await cp(installed, eligibilityExtraCopy, { recursive: true }); await auditCore(eligibilityExtraCopy);
  await writeFile(join(eligibilityExtraCopy, "dist/core/usage-mobile/unreviewed-eligibility.js"), "export {};\n");
  await assert.rejects(auditCore(eligibilityExtraCopy), /core_build_file_set_drift/);
  negativeIdentityCases.push("eligibility-extra-output");
  await assert.rejects(auditCohort(join(temporary, "absent-eligibility-cohort.json")), { code: "ENOENT" });
  negativeIdentityCases.push("eligibility-cohort:absent");
  const eligibilityChangedCohort = join(temporary, "changed-eligibility-cohort.json");
  await writeFile(eligibilityChangedCohort, JSON.stringify({ ...cohort, committed_source_sha: "unreviewed" }));
  await assert.rejects(auditCohort(eligibilityChangedCohort), /reviewed_core_cohort_bytes_drift/);
  negativeIdentityCases.push("eligibility-cohort:tampered");
  const eligibilityBytes = await readFile(resolve("../../", cohort.ios_eligibility_delta.receipt_path));
  const eligibilityCopy = join(temporary, "eligibility-receipt.json");
  await assert.rejects(auditAuthority(cohort.ios_eligibility_delta, eligibilityCopy), { code: "ENOENT" });
  negativeIdentityCases.push("eligibility-receipt:absent");
  await writeFile(eligibilityCopy, Buffer.concat([eligibilityBytes, Buffer.from("\n")]));
  await assert.rejects(auditAuthority(cohort.ios_eligibility_delta, eligibilityCopy), /qualified_core_receipt_bytes_drift/);
  negativeIdentityCases.push("eligibility-receipt:tampered");
  const eligibilityValue = JSON.parse(eligibilityBytes);
  await writeFile(eligibilityCopy, JSON.stringify({ ...eligibilityValue, review: { ...eligibilityValue.review, status: "pending" } }));
  await assert.rejects(auditAuthority(cohort.ios_eligibility_delta, eligibilityCopy), /qualified_core_receipt_bytes_drift/);
  negativeIdentityCases.push("eligibility-receipt:unreviewed");
  assert.deepEqual(negativeIdentityCases, cohort.negative_fixture_catalog.cases.map(({ id }) => id), "frozen_negative_fixture_execution_drift");
  assert.equal(negativeIdentityCases.length, 84);
} finally { await rm(temporary, { recursive: true, force: true }); }
const coreUrl = import.meta.resolve("@healthmd/core-ts");
const hostUrl = import.meta.resolve("@healthmd/core-ts/host-interfaces");
const actualEffect = await realpath(fileURLToPath(import.meta.resolve("effect/Effect")));
const candidateUrls = ["catalog", "normalize", "query", "registry"].map((name) => import.meta.resolve(`@healthmd/core-ts/candidate/${name}`));
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
assert.equal(core.CandidateSession, host.CandidateSession, "service_identity_drift");
console.log(JSON.stringify({ qualifiedCoreFiles: Object.keys(artifacts).length, qualifiedCoreInputs: Object.keys(coreInputPins).length, packedLocalCore: true,
  physicalEffectInstallations: effects.length, reviewedToolLaunchers: Object.keys(launchers), serviceIdentity: true, negativeIdentityCases }));
function run(args) { const result = spawnSync(process.execPath, args, { stdio: "inherit" }); if (result.status !== 0) process.exit(result.status ?? 1); }
if (!process.argv.includes("--tests-only")) { run(["node_modules/typescript/bin/tsc", "--project", "tsconfig.json"]); run(["scripts/build-candidate.mjs"]); }
const compiled = (await tree("dist/tests")).filter((path) => path.endsWith(".test.js"));
assert.ok(compiled.length > 0, "candidate_tests_missing");
const graph = JSON.parse(await readFile("dist/test-metafile.json", "utf8"));
assert.ok(Object.keys(graph.inputs).every((path) => !path.includes("node_modules")), "dependencies_must_remain_external");
run(["--test", ...compiled]);
console.log("CLI candidate check passed: exact runtime, packed core identity, typecheck, compiled test build and lifecycle");
