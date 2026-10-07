import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
const root = resolve(import.meta.dirname, "..");
const require = createRequire(resolve(root, "package.json"));
assert.equal(process.version, "v24.21.0");
assert.ok(process.env.npm_execpath, "run_through_pinned_npm");
assert.equal(spawnSync(process.execPath, [process.env.npm_execpath, "--version"], {encoding: "utf8"}).stdout.trim(), "11.19.0");
const manifest = JSON.parse(await readFile(resolve(root, "package.json")));
const lock = JSON.parse(await readFile(resolve(root, "package-lock.json")));
for (const [name, version] of Object.entries({...manifest.dependencies, ...manifest.devDependencies})) {
  assert.equal(lock.packages["node_modules/" + name].version, version);
  assert.equal(JSON.parse(await readFile(resolve(root, "node_modules", name, "package.json"))).version, version);
}
const allowed = new Set(["MIT", "ISC", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "0BSD", "CC-BY-4.0", "(MIT OR Apache-2.0)", "(MIT OR CC0-1.0)"]);
for (const [path, entry] of Object.entries(lock.packages)) if (path) {
  assert.ok(allowed.has(entry.license), "license_review_required");
  assert.ok(entry.resolved.startsWith("https://registry.npmjs.org/"));
  assert.ok(!/rust|swc|oxc|napi|node-gyp|sqlite/.test(path), "unsupported_native_tool");
  if (entry.hasInstallScript) assert.ok(["node_modules/esbuild", "node_modules/fsevents"].includes(path));
}
for (const name of ["react", "effect"]) {
  assert.equal(Object.keys(lock.packages).filter((path) => path.endsWith("node_modules/" + name)).length, 1);
}
for (const argv of [[resolve(root, "node_modules/typescript/bin/tsc"), "--project", "tsconfig.json"], ["scripts/build.mjs", "--portable-only"]]) {
  const run = spawnSync(process.execPath, argv, {cwd: root, stdio: "inherit"}); assert.equal(run.status, 0);
}
const {runHostProbe} = require(resolve(root, "dist/probe.js"));
const fixture = JSON.parse(await readFile(resolve(root, "fixtures/host-probe-v1.json")));
let releasing = 0;
let next = 0, acquired = 0, released = 0, frames = 0, queued = 0, accepted_frames = 0, acknowledged_frames = 0, max_active = 0, max_queued = 0;
const handles = new Map();
let complete;
const result = new Promise((resolve) => {complete = resolve;});
const native = {
  async acquire(delay) {const token = ++next; handles.set(token, {delay, timer: null}); acquired++; return token;},
  inspect(token) {return new Promise((resolve) => {const h = handles.get(token); h.resolve = resolve; h.timer = setTimeout(() => {h.timer = null; h.resolve = null; resolve("ready");}, h.delay);});},
  async release(token) {const h = handles.get(token); clearTimeout(h.timer); if(h.resolve) {h.resolve("cancelled"); h.resolve=null;} releasing++; await new Promise((resolve) => setTimeout(resolve, 50)); assert.ok(handles.delete(token)); released++; releasing--;},
  async stats() {return {acquired, released, releasing, active: handles.size, inspecting: [...handles.values()].filter((h) => h.timer).length, unresolved_inspections: [...handles.values()].filter((h) => h.resolve).length, accepted_frames, acknowledged_frames, max_active, max_queued, active_frames: frames, queued_frames: queued};},
  async reset() {assert.equal(handles.size, 0); acquired = released = accepted_frames = acknowledged_frames = max_active = max_queued = 0;},
  frame(value) {
    if (Buffer.byteLength(value) > 65536) return Promise.reject({code: "frame_limit"});
    const f = JSON.parse(value);
    if (Object.keys(f).length !== 4 || f.schema !== fixture.schema || f.version !== 1 || f.sequence !== 0 || f.case_id !== "queue_backpressure") return Promise.reject({code: "schema_invalid"});
    if (frames === 2 && queued === 4) return Promise.reject({code: "backpressure"});
    const wait = frames === 2; accepted_frames++; if (wait) queued++; else frames++; max_active = Math.max(max_active, frames); max_queued = Math.max(max_queued, queued);
    return new Promise((resolve) => setTimeout(() => {if (wait) queued--; else frames--; acknowledged_frames++; resolve("ack");}, wait ? 200 : 100));
  },
  report(value) {complete(JSON.parse(value));},
};
await runHostProbe(native, {react: "19.2.0", hermes: true});
const report = await result; assert.equal(report.result, "passed");
assert.equal(report.observations.length, fixture.cases.length);
for (const expected of fixture.cases) {
  const actual = report.observations.find((x) => x.case_id === expected.case_id); assert.ok(actual);
  for (const [key, value] of Object.entries(expected.expected)) assert.deepEqual(actual.observed[key], value, expected.case_id + ":" + key);
}
console.log(JSON.stringify({proof_class: "portable_synthetic", cases: report.observations.length, locked_packages: Object.keys(lock.packages).length - 1, result: "passed"}));
