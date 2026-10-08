import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, readFile, readdir, realpath, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import getExePath from "@effect/tsgo/lib/getExePath";
import { effectPlugin, selectAffected } from "./policy.mjs";

const toolRoot = fileURLToPath(new URL("./", import.meta.url));
const repo = path.resolve(toolRoot, "../..");
const prefixes = { core: "packages/healthmd-core-ts", cli: "apps/cli" };
const [mode, name, ...args] = process.argv.slice(2);
if (!["check", "affected", "selected"].includes(mode) || !Object.hasOwn(prefixes, name)) {
  console.error("Usage: node scripts/typescript-dev/dev.mjs check|affected|selected core|cli [--base REF | tests/example.test.ts ...]");
  process.exit(2);
}
assert.equal(process.versions.node, "24.21.0", "Use the repository's pinned Node 24.21.0");
const prefix = prefixes[name];
const component = path.join(repo, prefix);
process.chdir(toolRoot);
const compiler = getExePath(); // Selects the matching packaged Go compiler; does not patch TypeScript.
const artifactRoot = path.resolve(path.dirname(compiler), "../..");
assert.deepEqual((await readdir(artifactRoot)).sort(), ["typescript"], "Run npm --prefix scripts/typescript-dev run setup to trim unused compiler artifacts");
assert.equal(JSON.parse(await readFile(path.join(toolRoot, "node_modules/@effect/tsgo/package.json"))).version, "0.51.0");
assert.equal(JSON.parse(await readFile(path.join(toolRoot, "node_modules/typescript/package.json"))).version, "7.0.2");
const cache = path.join(component, "node_modules/.cache/healthmd-dev");
await mkdir(cache, { recursive: true });
assert.equal(await realpath(cache), cache, "Development cache must not be a symlink");
const started = performance.now();
function run(executable, argv, cwd = component) {
  const result = spawnSync(executable, argv, { cwd, stdio: "inherit", timeout: 120000 });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
const schema = JSON.parse(await readFile(path.join(toolRoot, "node_modules/@effect/tsgo/schema.json")));
const plugin = effectPlugin(schema);
// The diagnostic compiler and these configs are development-only. Frozen producer and
// consumer configurations and qualification receipts are untouched.
for (const configName of ["tsconfig.json", "tsconfig.test.json"]) {
  const config = path.join(cache, configName);
  await writeFile(config, JSON.stringify({
    extends: path.join(component, configName),
    compilerOptions: {
      noEmit: true, incremental: true, tsBuildInfoFile: `${config}.tsbuildinfo`,
      noImplicitReturns: true, noFallthroughCasesInSwitch: true,
      noUncheckedSideEffectImports: true, plugins: [plugin],
    },
  }, null, 2) + "\n");
  run(compiler, ["--project", config, "--pretty", "false"]);
}
const staticMs = Math.round(performance.now() - started);
if (mode === "check") {
  if (args.length) throw new Error("check takes no extra arguments");
  console.log(JSON.stringify({ lane: "development-static", component: name, staticMs, qualification: false }));
  process.exit(0);
}
async function discover(directory) {
  const files = [];
  for (const entry of await readdir(path.join(component, directory), { withFileTypes: true })) {
    const file = `${directory}/${entry.name}`;
    if (entry.isSymbolicLink()) throw new Error(`Unreviewed test symlink: ${file}`);
    if (entry.isDirectory()) files.push(...await discover(file));
    else if (entry.isFile() && file.endsWith(".test.ts")) files.push(file);
  }
  return files.sort();
}
const entries = await discover("tests");
assert.ok(entries.length, "No test entries found");
const require = createRequire(path.join(component, "package.json"));
const { build } = await import(require.resolve("esbuild"));
// Existing tests resolve fixture bytes and package exports relative to dist/tests.
// Preserve that layout; refresh only selected entries, never delete the full build.
const outdir = path.join(component, "dist/tests");
const options = {
  absWorkingDir: component, outdir, outbase: "tests", bundle: true,
  platform: "node", format: "esm", target: "node24", metafile: true,
  external: ["effect", "effect/*", "@healthmd/core-ts", "@healthmd/core-ts/*"],
};
let selected;
if (mode === "selected") {
  if (!args.length) throw new Error("Supply at least one exact tests/*.test.ts path");
  selected = [...new Set(args)];
  for (const entry of selected) if (!entries.includes(entry)) throw new Error(`Unknown test: ${entry}`);
} else {
  if (args.length && (args.length !== 2 || args[0] !== "--base")) throw new Error("affected accepts only --base REF");
  const base = args[1] ?? "HEAD";
  const git = argv => {
    const result = spawnSync("git", argv, { cwd: repo, encoding: "utf8", timeout: 10000 });
    if (result.error || result.status !== 0) throw new Error(`Git change detection failed: ${result.stderr ?? result.error}`);
    return result.stdout.split("\0").filter(Boolean);
  };
  // --end-of-options prevents a user-supplied ref from becoming a Git option.
  const sha = git(["rev-parse", "--verify", "--end-of-options", `${base}^{commit}`])[0]?.trim();
  if (!/^[a-f0-9]{40}$/.test(sha ?? "")) throw new Error("Unresolved base commit");
  const changed = [...new Set([...git(["diff", "--name-only", "-z", sha, "--"]), ...git(["ls-files", "--others", "--exclude-standard", "-z"])])];
  // Rebuild the graph from current source so import changes cannot reuse a stale closure.
  const graph = await build({ ...options, entryPoints: entries, write: false });
  selected = selectAffected(entries, graph.metafile, changed, prefix);
  console.log(JSON.stringify({ base: sha, changed, selectedTestEntries: selected }));
}
if (selected.length) {
  await mkdir(outdir, { recursive: true });
  assert.equal(await realpath(outdir), outdir, "Test output directory must not be a symlink");
  const compiled = await build({ ...options, entryPoints: selected });
  const outputs = Object.keys(compiled.metafile.outputs).filter(file => file.endsWith(".js")).map(file => path.resolve(component, file));
  for (const file of outputs) assert.ok((await realpath(file)).startsWith(outdir + path.sep));
  run(process.execPath, ["--test", ...outputs]);
}
console.log(JSON.stringify({ lane: "development-tests", component: name, staticMs, totalMs: Math.round(performance.now() - started), selectedTestEntries: selected, qualification: false }));
