import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
process.chdir(fileURLToPath(new URL("../", import.meta.url)));
// This leaf model intentionally has no imports. Reject comments/strings containing
// host names too: this conservative guard is not a general-purpose TS parser.
function leafBoundary(source) {
  const text = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  return !/\b(import|require|eval)\b|\bexport\s+(?:\*|\{)[\s\S]*?\bfrom\b|\b(process|Buffer|window|document|navigator|fetch|WebSocket|XMLHttpRequest|localStorage|setTimeout|setInterval|AbortController|Deno|Bun|globalThis)\b/.test(text);
}
const negativeCases = ["import x from 'react'", "import type { X } from 'effect'", "import './adapter.js'",
  "export * from '../host.js'", "import('react-native')", "require('fs')", "eval('code')",
  "process.env.X", "Buffer.from('x')", "window.location", "document.body", "navigator.userAgent",
  "fetch('/x')", "new WebSocket('x')", "new XMLHttpRequest()", "localStorage.x",
  "setTimeout(() => {}, 0)", "setInterval(() => {}, 1)", "new AbortController()", "Deno.readFile('x')",
  "Bun.file('x')", "globalThis.location"];
for (const candidate of negativeCases) assert.equal(leafBoundary(candidate), false, candidate);
assert.equal(leafBoundary("export const source = { domain: 'health', capture: 'unknown' };"), true);
const source = await readFile("src/index.ts", "utf8");
assert.equal(leafBoundary(source), true, "model must remain ES-only import-free leaf");
const metafile = JSON.parse(await readFile("dist/model-metafile.json", "utf8"));
assert.deepEqual(Object.keys(metafile.inputs), ["src/index.ts"]);
assert.ok(Object.values(metafile.outputs).every((output) => output.imports.length === 0));
assert.equal(leafBoundary(await readFile("dist/model.bundle.js", "utf8")), true);
const manifest = JSON.parse(await readFile("package.json", "utf8"));
assert.equal(manifest.dependencies, undefined);
assert.deepEqual(manifest.peerDependencies, { effect: "4.0.1", react: "19.2.3 || 19.2.0", "react-dom": "19.2.3",
  "react-native": "0.87.1 || 0.83.10", "react-native-web": "0.21.3", "react-native-macos": "0.83.0" });
assert.ok(Object.values(manifest.peerDependenciesMeta).every((peer) => peer.optional === true));
const lock = JSON.parse(await readFile("package-lock.json", "utf8"));
for (const [name, entry] of Object.entries(lock.packages)) {
  if (name === "") continue;
  assert.match(name, /^node_modules\/(?:typescript|esbuild|@types\/node|undici-types|@typescript\/typescript-[a-z0-9-]+|@esbuild\/[a-z0-9-]+)$/);
  assert.equal(entry.link, undefined, "no linked package/core identity duplication");
}
async function scanNative(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory()) await scanNative(path);
    else assert.ok(!entry.name.endsWith(".node") && entry.name !== "binding.gyp", `unreviewed native addon: ${path}`);
  }
}
await scanNative("node_modules");
console.log(JSON.stringify({ negativeBoundaryCases: negativeCases.length, modelBundleInputs: Object.keys(metafile.inputs),
  hostPeersInstalled: false, nativeRuntimeIdentity: "unqualified; host graph not installed" }));
