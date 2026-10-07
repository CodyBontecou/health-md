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
const coreInputPins = {
  ".node-version": "73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f",
  "AGENTS.md": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
  "README.md": "27f9a30230a34c76df65a5268c371f5823a92e9bd110c243842cf83457dbc7c9",
  "package-lock.json": "61746468956308b8a7811cc02fb41c6ac239d5830121ceffeab43324b639c36e",
  "package.json": "669826ebeacdc3211b4d41ec0f17ddad63b78b710bb74756fa2dfd586c756ba2",
  "scripts/build.mjs": "74a89aaaca29b65bdbc13fec480aaa642b8bf72c7daeebacfae150750c7cd83b",
  "scripts/check-boundaries.mjs": "3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09",
  "scripts/check.mjs": "e61622b1190322a61021055b342636e5edfd7f4cfba7ef7e240e375a7a6c3eae",
  "src/contracts/exact-values.ts": "2c56f1942f585a5cf3d2c5387d42c87ef2853255b2fc9ddda86e1666a15a4275",
  "src/contracts/registry.ts": "0a2712e9f7ec42596b65a509d8ccf755d8e85f5bfb2f47e0b272bf180469fe09",
  "src/host-interfaces/capabilities.ts": "d782133d2e5458baad95382a5d65c36c0e97266ae22d7eb62138fd8336c78812",
  "src/host-interfaces/faults.ts": "8be680e6895512aa3f95c70ecaff076cbd021e0e3db39a785e286f7b1de7cf72",
  "src/index.ts": "3b2632b7f93517e259be66242444b449402d0a3821c38a76b6b28c6abce256d8",
  "src/operations/catalog.ts": "eee557683d518595545797ed228e6e56e6659ea0d2325270059c1a13d89a0db7",
  "src/operations/normalize.ts": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
  "src/operations/query.ts": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
  "tests/catalog-vectors.ts": "a28c9539cb62c1c5b52319c5e4cca27f93b3bebd5b5900592775800067a06f51",
  "tests/catalog.test.ts": "a3751d2bc08ab1b855db9b7ab318430cf927d5b00f7104124448f820168e1b27",
  "tests/exact-values-vectors.ts": "b64ca4d8bd50335a41f4d6f2ff045825f8feb3c0e91c3ce58e13715ae77ec954",
  "tests/exact-values.test.ts": "03c50ea1fb9f0d9d1efee6b415468876a3f917b9628ee32bb9b76587ec6578a5",
  "tests/foundation.test.ts": "f9f54951e7fb19db668373c4b8aab74d5aa5e282396380bc163152ffedb1ba0c",
  "tests/query-traversal-vectors.ts": "ee70ea97d59a83993c0b50ecdf3b8dd08b5796d379b007fcaea450a7dcc0c12a",
  "tests/query-traversal.test.ts": "d4f52ac9b25e16e76f21a4e2da2698a1a020f7cf6a3701d01d6c186760fba4ea",
  "tests/registry-vectors.ts": "f470896023dff3e000aa4171afd8988606fc4dc049c0d5b17929bfbbda67873a",
  "tests/registry.test.ts": "23c0932104a0874f4e1d8b382d38a7c01ed818f6deca12171225e8007b4a2761",
  "tsconfig.build.json": "da405f2cf08aea30602cc1ffdbaedd25a0ead61e8b966e806404627212cb0614",
  "tsconfig.json": "5c9087c0fdfed84a89a16f31266a0b76c3269d9aabcbf23e7cf8dd7f6d0405a5",
  "tsconfig.test.json": "a2f54ecf614e4a58e3fbaf664f6cebc81d41d4ec6e861ae9fb4c4d5f484f68e5"
};
const source = resolve("../../packages/healthmd-core-ts");
const installed = resolve("node_modules/@healthmd/core-ts");
const sourceManifest = await readFile(join(source, "package.json"));
const receipt = JSON.parse(await readFile("../../docs/migration/effect-refactor/receipts/REGISTRY-READER.json", "utf8"));
assert.equal(receipt.result, "passed"); assert.equal(receipt.review.status, "accepted", "qualified_core_receipt_required");
assert.equal(receipt.source_sha, coreInputAuthority.sourceSha, "qualified_core_source_authority_drift");
assert.equal(receipt.patch_digest, coreInputAuthority.patchDigest, "qualified_core_patch_authority_drift");
const qualified = receipt.inputs.artifact_and_native_interface.emitted_artifacts;
const artifacts = Object.fromEntries(Object.entries(qualified).filter(([path]) => path.startsWith("dist/core/")));
assert.ok(Object.keys(artifacts).length > 0, "qualified_core_artifacts_missing");
assert.equal(hash(sourceManifest), receipt.inputs.contract_and_fixture_digests["packages/healthmd-core-ts/package.json"]);
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
  const stale = join(temporary, "stale"); await cp(installed, stale, { recursive: true });
  await writeFile(join(stale, "dist/core/index.js"), "export {};\n");
  await assert.rejects(auditCore(stale), /core_build_bytes_drift/);
} finally { await rm(temporary, { recursive: true, force: true }); }
const coreUrl = import.meta.resolve("@healthmd/core-ts");
const hostUrl = import.meta.resolve("@healthmd/core-ts/host-interfaces");
const actualEffect = await realpath(fileURLToPath(import.meta.resolve("effect/Effect")));
for (const url of [coreUrl, hostUrl]) {
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
  physicalEffectInstallations: effects.length, reviewedToolLaunchers: Object.keys(launchers), serviceIdentity: true, negativeIdentityCases: ["sibling-symlink", "stale-build", "unbuilt-source-edit", "extra-source-file"] }));
function run(args) { const result = spawnSync(process.execPath, args, { stdio: "inherit" }); if (result.status !== 0) process.exit(result.status ?? 1); }
if (!process.argv.includes("--tests-only")) { run(["node_modules/typescript/bin/tsc", "--project", "tsconfig.json"]); run(["scripts/build-candidate.mjs"]); }
const compiled = (await tree("dist/tests")).filter((path) => path.endsWith(".test.js"));
assert.ok(compiled.length > 0, "candidate_tests_missing");
const graph = JSON.parse(await readFile("dist/test-metafile.json", "utf8"));
assert.ok(Object.keys(graph.inputs).every((path) => !path.includes("node_modules")), "dependencies_must_remain_external");
run(["--test", ...compiled]);
console.log("CLI candidate check passed: exact runtime, packed core identity, typecheck, compiled test build and lifecycle");
