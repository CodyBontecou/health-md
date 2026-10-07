import { spawnSync } from "node:child_process";
import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { build } from "esbuild";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
process.chdir(fileURLToPath(root));
async function discover(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = `${directory}/${entry.name}`;
    if (entry.isSymbolicLink()) throw new Error("test_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await discover(name));
    else if (entry.isFile() && entry.name.endsWith(".test.ts")) files.push(name);
  }
  return files.sort();
}
const entryPoints = await discover("tests");
if (entryPoints.length === 0) throw new Error("no_candidate_tests");
await rm("dist", { recursive: true, force: true });
await mkdir("dist/tests", { recursive: true });
for (const config of ["tsconfig.build.json", "tsconfig.test.json"]) {
  const result = spawnSync(process.execPath, ["node_modules/typescript/bin/tsc", "--project", config], { stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
const tests = await build({
  entryPoints,
  outdir: "dist/tests",
  outbase: "tests",
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node24",
  external: ["effect", "effect/*", "@healthmd/core-ts", "@healthmd/core-ts/*"],
  metafile: true,
});
await writeFile("dist/test-metafile.json", JSON.stringify(tests.metafile, null, 2) + "\n");
console.log(JSON.stringify({ compiledTestEntries: entryPoints }));
