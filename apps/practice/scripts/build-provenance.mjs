import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { safeProvenanceMetadataPath } from "./provenance-metadata.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(root, "../..");
const run = (command, args, cwd = root) => execFileSync(command, args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
const digest = value => createHash("sha256").update(value).digest("hex");
async function filesUnder(directory) {
  const output = [];
  try { for (const entry of await readdir(directory, { withFileTypes: true })) { const path = join(directory, entry.name); if (entry.isDirectory()) output.push(...await filesUnder(path)); else output.push(path); } }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  return output;
}
const sourceRoots = ["src", "static", "fixtures", "qualification/v1", "scripts", "test", "e2e", "docs"];
const rootFiles = [".env.example", ".gitignore", "AGENTS.md", "LICENSE", "Makefile", "README.md", "package.json", "package-lock.json", "playwright.config.ts", "tsconfig.json", "vitest.config.ts", "wrangler.toml"];
const paths = (await Promise.all(sourceRoots.map(path => filesUnder(resolve(root, path))))).flat();
for (const file of rootFiles) paths.push(resolve(root, file));
paths.push(resolve(repositoryRoot, ".github/workflows/practice-ci.yml"));
const sourceFiles = [];
const normalizedPaths = [...new Set(paths)].map(path => ({ path, display: (path.startsWith(root) ? relative(root, path) : relative(repositoryRoot, path)).replaceAll("\\", "/") })).sort((a, b) => a.display < b.display ? -1 : a.display > b.display ? 1 : 0);
for (const item of normalizedPaths) if (!safeProvenanceMetadataPath(item.display)) throw new Error(`Provenance refuses a source path that is not safe build metadata: ${digest(item.display)}`);
for (const item of normalizedPaths) {
  const bytes = await readFile(item.path); sourceFiles.push({ pathSha256: digest(item.display), bytes: bytes.length, sha256: digest(bytes) });
}
const treeHasher = createHash("sha256");
for (const [index, file] of sourceFiles.entries()) { const item = normalizedPaths[index]; if (!item) throw new Error("Provenance source index mismatch"); treeHasher.update(item.display); treeHasher.update("\0"); treeHasher.update(await readFile(item.path)); treeHasher.update("\0"); }
const assetPaths = (await filesUnder(resolve(root, "dist"))).sort();
const buildAssets = await Promise.all(assetPaths.map(async path => { const bytes = await readFile(path); return { path: relative(root, path).replaceAll("\\", "/"), bytes: bytes.length, sha256: digest(bytes) }; }));
if (buildAssets.length === 0 || buildAssets.some(asset => asset.bytes === 0)) throw new Error("Provenance requires nonempty built assets");
const packageJson = JSON.parse(await readFile(resolve(root, "package.json"), "utf8"));
const statusLines = run("git", ["status", "--porcelain=v1", "--untracked-files=all", "--", "apps/practice", ".github/workflows/practice-ci.yml"], repositoryRoot).split("\n").filter(Boolean);
for (const line of statusLines) if (line.length < 4 || !safeProvenanceMetadataPath(line.slice(3))) throw new Error(`Provenance refuses a changed path that is not safe build metadata: ${digest(line)}`);
const dirty = statusLines.length > 0;
const statusDigest = digest(statusLines.join("\n"));
const provenance = {
  schema: "practice.synthetic.provenance/2",
  generatedAt: new Date().toISOString(),
  classification: "build-metadata-only-no-clinical-content",
  git: { repositoryHead: run("git", ["rev-parse", "HEAD"], repositoryRoot), dirty, scopedChangeCount: statusLines.length, statusDigest, candidateCommit: dirty ? null : run("git", ["rev-parse", "HEAD"], repositoryRoot), candidateDescription: dirty ? "current working tree; HEAD is not the candidate because scoped source is modified or untracked" : "clean current HEAD" },
  tools: { node: process.version, npm: run("npm", ["--version"]), playwright: packageJson.devDependencies["@playwright/test"], wrangler: packageJson.devDependencies.wrangler, typescript: packageJson.devDependencies.typescript },
  lockSha256: digest(await readFile(resolve(root, "package-lock.json"))),
  currentTreeSha256: treeHasher.digest("hex"),
  sourceFiles,
  buildAssets,
  productionEnabled: false,
};
const output = resolve(root, "qualification/generated/provenance.json"); await mkdir(dirname(output), { recursive: true }); await writeFile(output, `${JSON.stringify(provenance, null, 2)}\n`);
console.log(`Wrote current-tree provenance for ${sourceFiles.length} source/config/test/qualification files and ${buildAssets.length} nonempty built assets; dirty=${dirty}, productionEnabled=false.`);
