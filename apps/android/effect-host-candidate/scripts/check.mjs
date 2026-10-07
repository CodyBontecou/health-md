import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
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
  if (entry.hasInstallScript) assert.equal(path, "node_modules/esbuild");
  try {
    const actual = JSON.parse(await readFile(resolve(root, path, "package.json")));
    assert.equal(actual.version, entry.version, "postinstall_version");
    assert.ok(!/cargo |rustc |node-gyp|napi build/.test(JSON.stringify(actual.scripts ?? {})), "postinstall_native_script");
  } catch (error) { if (error.code !== "ENOENT" || !entry.optional) throw error; }
}
for (const name of ["react", "effect"]) assert.equal(Object.keys(lock.packages).filter((path) => path.endsWith("node_modules/" + name)).length, 1);
const fixtureBytes = await readFile(resolve(root, "fixtures/host-probe-v1.json"));
assert.equal(createHash("sha256").update(fixtureBytes).digest("hex"), "c4a16f4b200a350f9c41e619af4129e81ad52245fdc79643c67ddf239c301ef6");
const fixture = JSON.parse(fixtureBytes);
for (const argv of [[resolve(root, "node_modules/typescript/bin/tsc"), "--project", "tsconfig.json"], ["scripts/build.mjs", "--portable-only"]]) {
  const run = spawnSync(process.execPath, argv, {cwd: root, stdio: "inherit"}); assert.equal(run.status, 0);
}
const {runHostProbe} = require(resolve(root, "dist/probe.js"));
let next = 0, acquired = 0, released = 0, releasing = 0, frames = 0, accepted = 0, acknowledged = 0, maxActive = 0, maxQueued = 0;
const handles = new Map(); const waiting = [];
let complete; const result = new Promise((resolve) => {complete = resolve;});
const drain = () => { while (frames < 2 && waiting.length) waiting.shift()(); };
const native = {
  async acquire(delay) { const token = ++next; handles.set(token, {delay, timer: null, resolve: null}); acquired++; return token; },
  inspect(token) { return new Promise((resolve) => { const h = handles.get(token); h.resolve = resolve; h.timer = setTimeout(() => { h.timer = null; h.resolve = null; resolve("ready"); }, h.delay); }); },
  async release(token) {
    const h = handles.get(token); clearTimeout(h.timer); h.timer = null;
    if (h.resolve) { h.resolve("cancelled"); h.resolve = null; }
    releasing++; await new Promise((resolve) => setTimeout(resolve, 50)); assert.ok(handles.delete(token)); released++; releasing--;
  },
  async stats() { return { acquired, released, releasing, active: handles.size, inspecting: [...handles.values()].filter((h) => h.timer).length,
    unresolved_inspections: [...handles.values()].filter((h) => h.resolve).length, accepted_frames: accepted, acknowledged_frames: acknowledged,
    max_active: maxActive, max_queued: maxQueued, active_frames: frames, queued_frames: waiting.length }; },
  async reset() { assert.equal(handles.size + frames + waiting.length, 0); acquired = released = accepted = acknowledged = maxActive = maxQueued = 0; },
  frame(value) {
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) { const next = value.charCodeAt(++i); if (!(next >= 0xdc00 && next <= 0xdfff)) return Promise.reject({code: "schema_invalid"}); }
      else if (c >= 0xdc00 && c <= 0xdfff) return Promise.reject({code: "schema_invalid"});
    }
    if (Buffer.byteLength(value, "utf8") > fixture.bounds.frame_bytes) return Promise.reject({code: "frame_limit"});
    let f; try { f = JSON.parse(value); } catch { return Promise.reject({code: "schema_invalid"}); }
    if (!f || Array.isArray(f) || Object.keys(f).sort().join() !== [...fixture.admission.frame_keys].sort().join() ||
      f.schema !== fixture.schema || f.version !== 1 || f.case_id !== "queue_backpressure" || f.sequence !== 0) return Promise.reject({code: "schema_invalid"});
    if (frames === 2 && waiting.length === 4) return Promise.reject({code: "backpressure"});
    accepted++;
    return new Promise((resolve) => {
      const work = () => { frames++; maxActive = Math.max(maxActive, frames); setTimeout(() => { frames--; acknowledged++; resolve("ack"); drain(); }, 100); };
      if (frames < 2) work(); else { waiting.push(work); maxQueued = Math.max(maxQueued, waiting.length); }
    });
  },
  report(value) { complete(JSON.parse(value)); },
};
await runHostProbe(native, {react: "19.2.3", hermes: true});
const report = await result; assert.equal(report.result, "passed"); assert.equal(report.observations.length, fixture.cases.length);
for (const expected of fixture.cases) {
  const actual = report.observations.find((x) => x.case_id === expected.case_id); assert.ok(actual);
  for (const [key, value] of Object.entries(expected.expected)) assert.deepEqual(actual.observed[key], value, expected.case_id + ":" + key);
}
const output = {proof_class: "portable_synthetic", cases: report.observations.length, locked_packages: Object.keys(lock.packages).length - 1, result: "passed", observations: report.observations};
await mkdir(resolve(root, "dist"), {recursive: true}); await writeFile(resolve(root, "dist/portable-result.json"), JSON.stringify(output, null, 2) + "\n");
console.log(JSON.stringify({proof_class: output.proof_class, cases: output.cases, result: output.result}));
