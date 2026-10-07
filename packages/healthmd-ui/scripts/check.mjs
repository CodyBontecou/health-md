import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
assert.equal(process.versions.node, "24.21.0", "Use pinned Node24");
assert.ok(process.env.npm_execpath, "Run through npm run check");
const npm = spawnSync(process.execPath, [process.env.npm_execpath, "--version"], { encoding: "utf8" });
assert.equal(npm.status, 0); assert.equal(npm.stdout.trim(), "11.19.0");
const manifest = JSON.parse(await readFile("package.json", "utf8"));
const lock = JSON.parse(await readFile("package-lock.json", "utf8"));
assert.equal(lock.lockfileVersion, 3);
assert.deepEqual(lock.packages[""].devDependencies, manifest.devDependencies);
assert.deepEqual(lock.packages[""].peerDependencies, manifest.peerDependencies);
assert.deepEqual(lock.packages[""].peerDependenciesMeta, manifest.peerDependenciesMeta);
for (const [name, version] of Object.entries(manifest.devDependencies)) {
  assert.equal(lock.packages[`node_modules/${name}`]?.version, version);
  assert.equal(JSON.parse(await readFile(`node_modules/${name}/package.json`, "utf8")).version, version);
}
assert.equal(lock.packages["node_modules/undici-types"]?.version, "7.24.6");
const testsOnly = process.argv.includes("--tests-only");
const commands = testsOnly ? [] : [
  ["node_modules/typescript/bin/tsc", "--project", "tsconfig.json"], ["scripts/build.mjs"],
];
for (const args of commands) {
  const result = spawnSync(process.execPath, args, { stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
async function discover(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = `${directory}/${entry.name}`;
    if (entry.isSymbolicLink()) throw new Error("test_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await discover(path));
    else if (entry.isFile() && entry.name.endsWith(".test.js")) files.push(path);
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
console.log("UI candidate check passed; headless compiled-JS model/component-props only");
