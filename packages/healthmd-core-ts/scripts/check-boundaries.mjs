import assert from "node:assert/strict";
import { builtinModules, createRequire } from "node:module";
import { readFile, readdir, realpath, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const root = fileURLToPath(new URL("../", import.meta.url));
const sourceRoot = path.join(root, "src");
const allowedEffect = new Set(["effect/Context", "effect/Effect", "effect/Data"]);
const builtins = new Set(builtinModules.map((name) => name.replace(/^node:/, "")));

/** Conservative admission lexer: rejects even comments/string mentions of host names. */
export function auditSourceText(source) {
  const decoded = source.replace(/\\u\{([\da-fA-F]+)\}|\\u([\da-fA-F]{4})/g,
    (_, long, short) => String.fromCodePoint(Number.parseInt(long ?? short, 16)));
  if (/\b(?:globalThis|global|window|document|process|Buffer|fetch|XMLHttpRequest|WebSocket|eval|Function|require|Deno|Bun|navigator|localStorage|sessionStorage|crypto|console|setTimeout|setInterval|clearTimeout|clearInterval|constructor)\b/.test(decoded)
    || /\bdeclare\s+(?:global|module|namespace|const|var|let|function)\b/.test(decoded)
    || /\bimport\s*\.\s*meta\b/.test(decoded)) {
    throw new Error("portable_forbidden_global");
  }
  // Nonliteral dynamic imports cannot be established by an esbuild import graph.
  for (const match of decoded.matchAll(/\bimport\s*\(/g)) {
    if (!/^\s*(["'])[\w./@-]+\1\s*\)/.test(decoded.slice(match.index + match[0].length))) {
      throw new Error("portable_dynamic_import");
    }
  }
}

export function auditImport(specifier) {
  if (allowedEffect.has(specifier)) return;
  if (specifier.startsWith("node:") || builtins.has(specifier) || !specifier.startsWith(".")) {
    throw new Error("portable_forbidden_import");
  }
}

async function sourceFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error("portable_source_symlink");
    if (entry.isDirectory()) files.push(...await sourceFiles(name));
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(name);
    else throw new Error("portable_unreviewed_source_kind");
  }
  return files.sort();
}

export async function checkBoundaries(sourceOverrides = new Map(), writeEvidence = true) {
  const files = await sourceFiles(sourceRoot);
  const sources = new Map();
  for (const file of files) {
    const source = sourceOverrides.get(path.relative(sourceRoot, file)) ?? await readFile(file, "utf8");
    auditSourceText(source);
    sources.set(file, source);
  }
  const result = await build({
    absWorkingDir: root,
    entryPoints: files,
    outdir: "dist/neutral",
    bundle: true,
    write: false,
    metafile: true,
    platform: "neutral",
    format: "esm",
    target: "es2022",
    logLevel: writeEvidence ? "warning" : "silent",
    logOverride: { "unsupported-dynamic-import": "error", "unsupported-require-call": "error" },
    plugins: [{ name: "portable-imports", setup(builder) {
      builder.onLoad({ filter: /\.ts$/ }, (args) => ({ contents: sources.get(args.path), loader: "ts" }));
      builder.onResolve({ filter: /.*/ }, async (args) => {
        if (args.kind === "entry-point") return;
        auditImport(args.path);
        if (allowedEffect.has(args.path)) return { path: args.path, external: true };
        let resolved = path.resolve(args.resolveDir, args.path.replace(/\.js$/, ".ts"));
        resolved = await realpath(resolved);
        if (!resolved.startsWith(sourceRoot + path.sep)) throw new Error("portable_import_escape");
        return { path: resolved };
      });
    }}],
  });
  for (const output of Object.values(result.metafile.outputs)) {
    for (const imported of output.imports) assert.ok(allowedEffect.has(imported.path) && imported.external);
  }
  const manifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const lock = JSON.parse(await readFile(path.join(root, "package-lock.json"), "utf8"));
  const effects = Object.entries(lock.packages).filter(([name]) => /(?:^|\/)node_modules\/effect$/.test(name));
  assert.equal(effects.length, 1, "one locked Effect module");
  assert.equal(effects[0][1].version, "4.0.1");
  assert.deepEqual(manifest.dependencies, { effect: "4.0.1" });
  const require = createRequire(path.join(root, "package.json"));
  const effectRoot = await realpath(path.dirname(require.resolve("effect/package.json")));
  for (const entry of Object.values(manifest.exports)) {
    const fromExport = createRequire(path.join(root, entry.import));
    assert.equal(await realpath(path.dirname(fromExport.resolve("effect/package.json"))), effectRoot);
  }
  const installedEffect = JSON.parse(await readFile(path.join(effectRoot, "package.json"), "utf8"));
  assert.equal(installedEffect.version, "4.0.1");
  assert.deepEqual(installedEffect.dependencies ?? {}, {});
  // Reject candidates that introduce Rust-backed compiler/test/bundle dependencies.
  for (const name of Object.keys(lock.packages)) {
    assert.ok(name === "" || /^node_modules\/(?:effect|typescript|esbuild|undici-types|@types\/node|@typescript\/typescript-[\w-]+|@esbuild\/[\w-]+)$/.test(name),
      "New tool/runtime dependency requires a reviewed implementation-language inventory");
  }
  if (writeEvidence) await writeFile(path.join(root, "dist/neutral-metafile.json"), JSON.stringify(result.metafile, null, 2) + "\n");
  return { sourceModules: files.length, effectInstallations: effects.length };
}

export function checkNegativeCases() {
  const cases = [
    ["node-import", () => auditImport("node:fs")],
    ["bare-node-import", () => auditImport("crypto")],
    ["react-import", () => auditImport("react")],
    ["native-import", () => auditImport("react-native")],
    ["environment", () => auditSourceText("process.env.SECRET")],
    ["computed-global", () => auditSourceText('globalThis["process"]')],
    ["aliased-global", () => auditSourceText("const host = globalThis")],
    ["unicode-global", () => auditSourceText(String.raw`pro\u0063ess.env.X`)],
    ["dom", () => auditSourceText("document.body")],
    ["dynamic-import", () => auditSourceText("import(provider)")],
    ["template-import", () => auditSourceText("import(`node:fs`)")],
    ["ambient-escape", () => auditSourceText("declare const host: any")],
    ["constructor-escape", () => auditSourceText('({}).constructor.constructor("return this")')],
  ];
  for (const [, run] of cases) assert.throws(run);
  auditImport("./host-interfaces/capabilities.js");
  auditImport("effect/Effect");
  auditSourceText('export const value = "ready";');
  return cases.map(([id]) => id);
}

export async function checkNegativeGraphs() {
  const cases = [
    ["transitive-node-import", "host-interfaces/faults.ts", 'export { readFile } from "node:fs";'],
    ["transitive-native-import", "host-interfaces/capabilities.ts", 'export * from "react-native";'],
    ["unapproved-effect-host-module", "index.ts", 'export * from "effect/process";'],
    ["relative-root-escape", "index.ts", 'export * from "../package.json";'],
    ["transitive-global", "host-interfaces/faults.ts", 'export const value = globalThis["fetch"];'],
    ["computed-dynamic-with-comment", "index.ts", 'export const load = (module: string) => import /* gap */(module);'],
  ];
  for (const [, file, source] of cases) {
    // Mutate a loaded module in memory, keeping the same source traversal/resolver/graph check.
    await assert.rejects(checkBoundaries(new Map([[file, source]]), false));
  }
  return cases.map(([id]) => id);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const negativeCases = checkNegativeCases();
  const negativeGraphs = await checkNegativeGraphs();
  console.log(JSON.stringify({ ...await checkBoundaries(), negativeCases, negativeGraphs }));
}
