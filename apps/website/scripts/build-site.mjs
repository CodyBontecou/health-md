#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildBlog } from './build-blog.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUTPUT = path.join(ROOT, 'dist');
const STATIC_DIRECTORIES = ['assets', 'docs', 'visualizations'];
const STATIC_FILES = [
  'favicon.ico',
  'index.html',
  'privacy-policy.html',
  'robots.txt',
  'sitemap.xml',
  'terms-of-service.html',
];

await fs.rm(OUTPUT, { recursive: true, force: true });
await fs.mkdir(OUTPUT, { recursive: true });

for (const directory of STATIC_DIRECTORIES) {
  await fs.cp(path.join(ROOT, directory), path.join(OUTPUT, directory), { recursive: true });
}

for (const filename of STATIC_FILES) {
  await fs.copyFile(path.join(ROOT, filename), path.join(OUTPUT, filename));
}

const posts = await buildBlog({ outputRoot: OUTPUT });
console.log(`Built Health.md static site with ${posts.length} blog post${posts.length === 1 ? '' : 's'} in ${OUTPUT}`);
