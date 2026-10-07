import { build } from "esbuild";
import { createRequire } from "node:module";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { resolve, relative } from "node:path";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import Metro from "metro";
const root = resolve(import.meta.dirname, "..");
const require = createRequire(resolve(root, "package.json"));
assert.equal(process.version, "v24.21.0");
const core = resolve(root, "../../../packages/healthmd-core-ts/dist/core/host-interfaces/capabilities.js");
const ui = resolve(root, "../../../packages/healthmd-ui/dist/model/index.js");
for (const [path, expected] of [[core, "ae1516fb397db074c95fc14214b3a48f99192daa16f1d7ac00f047d9b1ed94ef"], [ui, "68d7d53b4f4dfc7b7c74fa6ae5cdf1b952b0da6b10482b15be09f2666e73af47"]]) {
  assert.equal(createHash("sha256").update(await readFile(path)).digest("hex"), expected, "accepted_emitted_input_drift");
}
await mkdir(resolve(root, "dist"), {recursive: true});
const output = await build({entryPoints: [resolve(root, "src/probe.ts")], outfile: resolve(root, "dist/probe.js"), bundle: true, format: "cjs", platform: "neutral", target: "es2022", metafile: true,
  plugins: [{name: "single-candidate-identity", setup(builder) {
    builder.onResolve({filter: /^healthmd-candidate-/}, ({path}) => ({path: path === "healthmd-candidate-capabilities" ? core : ui}));
    builder.onResolve({filter: /^effect(?:\/|$)/}, ({path}) => ({path: require.resolve(path)}));
  }}]});
for (const input of Object.keys(output.metafile.inputs)) {
  if (input.includes("node_modules/effect/")) assert.ok(resolve(input).startsWith(resolve(root, "node_modules/effect") + "/"), "duplicate_effect_physical_source");
}
const hashes = {};
for (const path of [core, ui, require.resolve("effect/package.json"), require.resolve("react/package.json")]) {
  hashes[path.startsWith(root) ? path.slice(root.length + 1) : path.slice(resolve(root, "../../..").length + 1)] = createHash("sha256").update(await readFile(path)).digest("hex");
}
await writeFile(resolve(root, "dist/inputs.json"), JSON.stringify({hashes, metafile: output.metafile}, null, 2) + "\n");
if (!process.argv.includes("--portable-only")) {
  const config = await Metro.loadConfig({cwd: root, config: resolve(root, "metro.config.cjs")});
  const base = require("metro/private/DeltaBundler/Serializers/baseJSBundle").default;
  const stringify = require("metro/private/lib/bundleToString").default;
  config.serializer.customSerializer = async (entry, prepend, graph, options) => {
    const inputs = [];
    for (const path of [...graph.dependencies.keys()].sort()) {
      assert.ok(path.startsWith(root + "/"), "external_metro_physical_source");
      if (path.includes("node_modules/react/")) assert.ok(path.startsWith(resolve(root, "node_modules/react") + "/"), "duplicate_react_physical_source");
      inputs.push({path: relative(root, path), sha256: createHash("sha256").update(await readFile(path)).digest("hex")});
    }
    await writeFile(resolve(root, "dist/metro-inputs.json"), JSON.stringify(inputs, null, 2) + "\n");
    return stringify(base(entry, prepend, graph, options)).code;
  };
  await mkdir(resolve(root, "dist/assets"), {recursive: true});
  await writeFile(resolve(root, "dist/assets/host-probe-v1.json"), await readFile(resolve(root, "fixtures/host-probe-v1.json")));
  await Metro.runBuild(config, {entry: "src/HostProbe.tsx", out: resolve(root, "dist/assets/index.android.bundle"), dev: false, minify: true, platform: "android"});
  await rename(resolve(root, "dist/assets/index.android.bundle.js"), resolve(root, "dist/assets/index.android.bundle"));
}
