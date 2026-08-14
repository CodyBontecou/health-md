import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { safeProvenanceMetadataPath } from "./provenance-metadata.mjs";
import { repositoryFiles, repositoryRecursiveRoots, syntheticBoundaryFiles } from "./synthetic-boundary-manifest.mjs";

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
const sourceFiles = [];
const normalizedPaths = (await syntheticBoundaryFiles(root, repositoryRoot, { includeDist: false })).map(({ path, display }) => ({ path, display }));
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
const statusScopes = ["apps/practice", ...repositoryRecursiveRoots, ...repositoryFiles];
const statusLines = run("git", ["status", "--porcelain=v1", "--untracked-files=all", "--", ...statusScopes], repositoryRoot).split("\n").filter(Boolean);
for (const line of statusLines) if (line.length < 4 || !safeProvenanceMetadataPath(line.slice(3))) throw new Error(`Provenance refuses a changed path that is not safe build metadata: ${digest(line)}`);
const dirty = statusLines.length > 0;
const statusDigest = digest(statusLines.join("\n"));
const repositoryHead = run("git", ["rev-parse", "HEAD"], repositoryRoot);
const sourceHeadCommit = process.env.PRACTICE_SOURCE_HEAD_SHA?.trim() || repositoryHead;
if (!/^[a-f0-9]{40}$/.test(sourceHeadCommit)) throw new Error("PRACTICE_SOURCE_HEAD_SHA must be a full lowercase commit SHA");
const provenance = {
  schema: "practice.synthetic.provenance/3",
  generatedAt: new Date().toISOString(),
  classification: "build-metadata-only-no-clinical-content",
  scope: "Practice component, governed product protocol/docs, focused mobile fail-closed policies, and Practice CI workflow",
  git: { repositoryHead, qualifiedTreeCommit: repositoryHead, sourceHeadCommit, dirty, scopedChangeCount: statusLines.length, statusDigest, candidateCommit: dirty ? null : sourceHeadCommit, candidateDescription: dirty ? "current governed working tree; no immutable candidate because scoped source is modified or untracked" : sourceHeadCommit === repositoryHead ? "clean source head and qualified tree are identical" : "clean source head qualified through the event merge tree recorded separately" },
  tools: { node: process.version, npm: run("npm", ["--version"]), playwright: packageJson.devDependencies["@playwright/test"], wrangler: packageJson.devDependencies.wrangler, typescript: packageJson.devDependencies.typescript },
  lockSha256: digest(await readFile(resolve(root, "package-lock.json"))),
  currentTreeSha256: treeHasher.digest("hex"),
  sourceFiles,
  buildAssets,
  productionEnabled: false,
};
const output = resolve(root, "qualification/generated/provenance.json"); await mkdir(dirname(output), { recursive: true }); await writeFile(output, `${JSON.stringify(provenance, null, 2)}\n`);
console.log(`Wrote current-tree provenance for ${sourceFiles.length} source/config/test/qualification files and ${buildAssets.length} nonempty built assets; dirty=${dirty}, productionEnabled=false.`);
