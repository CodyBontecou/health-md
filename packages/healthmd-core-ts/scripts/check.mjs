import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
process.chdir(fileURLToPath(root));
assert.equal(process.versions.node, "24.21.0", "Use the exact qualified Node runtime");
assert.ok(process.env.npm_execpath, "Run through npm run check");
const npm = spawnSync(process.execPath, [process.env.npm_execpath, "--version"], { encoding: "utf8" });
assert.equal(npm.status, 0);
assert.equal(npm.stdout.trim(), "11.19.0");
const manifest = JSON.parse(await readFile("package.json", "utf8"));
const lock = JSON.parse(await readFile("package-lock.json", "utf8"));
assert.equal(lock.lockfileVersion, 3);
assert.deepEqual(lock.packages[""].dependencies, manifest.dependencies);
assert.deepEqual(lock.packages[""].devDependencies, manifest.devDependencies);
for (const [name, version] of Object.entries({ ...manifest.dependencies, ...manifest.devDependencies })) {
  assert.equal(lock.packages[`node_modules/${name}`]?.version, version, "locked direct package version");
  const installed = JSON.parse(await readFile(`node_modules/${name}/package.json`, "utf8"));
  assert.equal(installed.version, version, "installed direct package version");
}
assert.equal(lock.packages["node_modules/undici-types"]?.version, manifest.overrides["undici-types"]);
const testsOnly = process.argv.includes("--tests-only");
for (const args of testsOnly ? [] : [
  ["node_modules/typescript/bin/tsc", "--project", "tsconfig.json"],
  ["scripts/build.mjs"],
]) {
  const result = spawnSync(process.execPath, args, { stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
async function discover(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = `${directory}/${entry.name}`;
    if (entry.isSymbolicLink()) throw new Error("test_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await discover(name));
    else if (entry.isFile() && entry.name.endsWith(".test.js")) files.push(name);
  }
  return files.sort();
}
const compiledTests = await discover("dist/tests");
assert.ok(compiledTests.length > 0, "candidate tests must exist");
console.log(JSON.stringify({ executedTestEntries: compiledTests }));
for (const args of [["--test", ...compiledTests], ...(testsOnly ? [] : [["scripts/check-boundaries.mjs"]])]) {
  const result = spawnSync(process.execPath, args, { stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log(testsOnly ? "Candidate tests passed" : "Candidate check passed: exact runtime, typecheck, build, test, boundary and module identity");
