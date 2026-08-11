import { lstat, readdir } from "node:fs/promises";
import { join, relative, resolve } from "node:path";

export const componentRecursiveRoots = Object.freeze([
  "src", "static", "fixtures", "qualification/v1", "scripts", "test", "e2e", "docs", "dist",
]);
export const componentRootFiles = Object.freeze([
  ".env.example", ".gitignore", "AGENTS.md", "LICENSE", "Makefile", "README.md", "package.json", "package-lock.json",
  "playwright.config.ts", "tsconfig.json", "vitest.config.ts", "wrangler.toml",
]);
export const repositoryRecursiveRoots = Object.freeze([
  "docs/product/practice",
  "apps/apple/HealthMd/Shared/Practice",
  "apps/apple/HealthMdTests/Practice",
  "apps/android/app/src/main/java/com/healthmd/domain/practice",
  "apps/android/app/src/test/java/com/healthmd/domain/practice",
]);
export const repositoryFiles = Object.freeze([
  "AGENTS.md", "docs/architecture/adr-0003-practice-clinical-boundary.md", "docs/features/clinician-report-v1.md", ".github/workflows/practice-ci.yml",
]);
export const ignoredDirectoryNames = Object.freeze(new Set([
  "node_modules", ".wrangler", "coverage", "playwright-report", "test-results", "generated",
]));
export const reviewedBinarySha256 = Object.freeze(new Map([
  ["docs/product/practice/fixtures/synthetic-ingest-test-v1.pdf", "53b5033914f2a451e094bc6432f5bebbfeb75aca51d914f2a6e2afb87ff5aebc"],
]));

async function filesUnder(directory, options = {}) {
  const output = [];
  try {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isSymbolicLink()) { output.push({ path, symbolicLink: true }); continue; }
      if (entry.isDirectory()) {
        if (ignoredDirectoryNames.has(entry.name) || options.skipGenerated && entry.name === "generated") continue;
        output.push(...await filesUnder(path, options));
      } else if (entry.isFile()) output.push({ path, symbolicLink: false });
    }
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  return output;
}

export async function syntheticBoundaryFiles(componentRoot, repositoryRoot, options = {}) {
  const entries = [];
  for (const directory of componentRecursiveRoots) {
    if (directory === "dist" && options.includeDist === false) continue;
    entries.push(...await filesUnder(resolve(componentRoot, directory), { skipGenerated: directory === "qualification/v1" }));
  }
  for (const file of componentRootFiles) {
    const path = resolve(componentRoot, file);
    try { const metadata = await lstat(path); entries.push({ path, symbolicLink: metadata.isSymbolicLink() }); }
    catch (error) { if (error.code !== "ENOENT") throw error; else throw new Error(`Synthetic boundary manifest is missing required component file ${file}`); }
  }
  for (const directory of repositoryRecursiveRoots) entries.push(...await filesUnder(resolve(repositoryRoot, directory)));
  for (const file of repositoryFiles) {
    const path = resolve(repositoryRoot, file);
    try { const metadata = await lstat(path); entries.push({ path, symbolicLink: metadata.isSymbolicLink() }); }
    catch (error) { if (error.code !== "ENOENT") throw error; else throw new Error(`Synthetic boundary manifest is missing required repository file ${file}`); }
  }
  const unique = new Map();
  for (const entry of entries) {
    const display = relative(repositoryRoot, entry.path).replaceAll("\\", "/");
    unique.set(display, { ...entry, display });
  }
  return [...unique.values()].sort((a, b) => a.display.localeCompare(b.display));
}
