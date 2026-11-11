#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { sampleFiles } from './build-spreadsheet-samples.mjs';
import { zipVault } from './build-starter-vault.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const EXAMPLE_DIR = path.join(ROOT, 'examples/weekly-review');
export const SAMPLE_DIR = path.join(ROOT, 'assets/downloads/weekly-review');
export const ARCHIVE_PATH = path.join(ROOT, 'assets/downloads/healthmd-weekly-review-example.zip');
export const ROOT_NAME = 'Health.md Weekly Review Example';
const SOURCE_FILES = ['weekly_review.py', 'README.txt', 'expected-weekly-review.md'];

export async function weeklyReviewFiles() {
  const files = new Map();
  for (const name of SOURCE_FILES) files.set(name, await fs.readFile(path.join(EXAMPLE_DIR, name)));
  for (const [name, bytes] of sampleFiles()) if (name.startsWith('daily/')) files.set(name, bytes);
  files.set('LICENSE', await fs.readFile(path.join(ROOT, 'LICENSE')));
  const manifest = {
    fictional: true,
    source: 'https://healthmd.app/apple-health-to-csv/#spreadsheet-sample',
    files: Object.fromEntries([...files].map(([name, bytes]) => [name, createHash('sha256').update(bytes).digest('hex')])),
  };
  files.set('manifest.json', Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`));
  return files;
}

export async function buildWeeklyReviewSample({ check = false } = {}) {
  const files = await weeklyReviewFiles();
  const outputs = new Map(SOURCE_FILES.map(name => [path.join(SAMPLE_DIR, name), files.get(name)]));
  outputs.set(ARCHIVE_PATH, zipVault(files, { rootName: ROOT_NAME }));
  for (const [filename, bytes] of outputs) {
    if (check) {
      const existing = await fs.readFile(filename).catch(() => Buffer.alloc(0));
      if (!existing.equals(bytes)) throw new Error(`Stale weekly review example: ${path.relative(ROOT, filename)}. Run npm run weekly-review:build.`);
    } else {
      await fs.mkdir(path.dirname(filename), { recursive: true });
      await fs.writeFile(filename, bytes);
    }
  }
  console.log(`${check ? 'Verified' : 'Built'} weekly review example: ${files.size} files with 28 fictional daily inputs.`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await buildWeeklyReviewSample({ check: process.argv.includes('--check') });
}
