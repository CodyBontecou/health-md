import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { lstat, readFile, readdir, realpath, rm } from "node:fs/promises";

const toolRoot = fileURLToPath(new URL("./", import.meta.url));
const require = createRequire(join(toolRoot, "package.json"));
const platformName = `@effect/tsgo-${process.platform}-${process.arch}`;
const platformRoot = dirname(require.resolve(`${platformName}/package.json`));
const manifest = JSON.parse(await readFile(join(platformRoot, "package.json")));
assert.equal(manifest.version, "0.51.0");
assert.equal(manifest.name, platformName);
assert.equal(await realpath(platformRoot), platformRoot, "Platform package must be installed locally");
const artifacts = join(platformRoot, "artifacts");
assert.equal(await realpath(artifacts), artifacts, "Artifact directory must not be a symlink");
const kept = join(artifacts, "typescript", "7.0.2");
assert.equal(await realpath(kept), kept, "Selected compiler must not be a symlink");
assert.ok((await lstat(join(kept, process.platform === "win32" ? "tsc.exe" : "tsc"))).isFile());
// This package also ships Rust Oxlint addons and other compiler versions. Remove only
// the unused siblings from this tool's own pinned dependency, before any diagnostics run.
for (const entry of await readdir(artifacts, { withFileTypes: true })) {
  assert.ok(entry.isDirectory() && !entry.isSymbolicLink(), "Unexpected platform artifact kind");
  if (entry.name !== "typescript") await rm(join(artifacts, entry.name), { recursive: true, force: true });
}
for (const entry of await readdir(join(artifacts, "typescript"), { withFileTypes: true })) {
  assert.ok(entry.isDirectory() && !entry.isSymbolicLink(), "Unexpected compiler artifact kind");
  if (entry.name !== "7.0.2") await rm(join(artifacts, "typescript", entry.name), { recursive: true, force: true });
}
console.log(`Kept ${platformName} TypeScript 7.0.2; removed unused compiler versions and Oxlint artifacts`);
