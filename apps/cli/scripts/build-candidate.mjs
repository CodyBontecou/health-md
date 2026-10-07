import { spawnSync } from "node:child_process";
import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
async function discover(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = `${directory}/${entry.name}`;
    if (entry.isSymbolicLink()) throw new Error("candidate_test_symlink_unreviewed");
    if (entry.isDirectory()) files.push(...await discover(path));
    else if (entry.isFile() && entry.name.endsWith(".test.ts")) files.push(path);
  }
  return files.sort();
}
const entries = await discover("tests");
if (!entries.length) throw new Error("candidate_tests_missing");
await rm("dist", { recursive: true, force: true });
await mkdir("dist/tests", { recursive: true });
for (const config of ["tsconfig.build.json", "tsconfig.test.json"]) {
  const result = spawnSync(process.execPath, ["node_modules/typescript/bin/tsc", "--project", config], { stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
const compiled = await build({ entryPoints: entries, outdir: "dist/tests", outbase: "tests", bundle: true,
  platform: "node", format: "esm", target: "node24", external: ["effect", "effect/*", "@healthmd/core-ts", "@healthmd/core-ts/*"], metafile: true });
await writeFile("dist/test-metafile.json", JSON.stringify(compiled.metafile, null, 2) + "\n");
console.log(JSON.stringify({ compiledTestEntries: entries }));
