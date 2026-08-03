#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildBlog } from './build-blog.mjs';
import { buildLocalizedLanding } from './build-localized-pages.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUTPUT = path.join(ROOT, 'dist');
const DOCS_OUTPUT = path.join(ROOT, 'docs-src', 'dist');
const STATIC_DIRECTORIES = ['assets', 'visualizations'];
const STATIC_FILES = [
  'favicon.ico',
  'privacy-policy.html',
  'robots.txt',
  'sitemap.xml',
  'terms-of-service.html',
];

await fs.rm(OUTPUT, { recursive: true, force: true });
await fs.mkdir(OUTPUT, { recursive: true });

// Astro now emits stable /docs/ and /es/docs/ routes directly. Copy the complete
// output first, then merge the website's shared static assets over its public assets.
await fs.cp(DOCS_OUTPUT, OUTPUT, { recursive: true, force: true });

for (const directory of STATIC_DIRECTORIES) {
  await fs.cp(path.join(ROOT, directory), path.join(OUTPUT, directory), { recursive: true, force: true });
}

for (const filename of STATIC_FILES) {
  await fs.copyFile(path.join(ROOT, filename), path.join(OUTPUT, filename));
}

try {
  await fs.cp(path.join(ROOT, 'es'), path.join(OUTPUT, 'es'), { recursive: true, force: true });
} catch (error) {
  if (error?.code !== 'ENOENT') throw error;
}

await Promise.all([
  buildLocalizedLanding({ outputRoot: OUTPUT, locale: 'en' }),
  buildLocalizedLanding({ outputRoot: OUTPUT, locale: 'es' }),
]);

const posts = await buildBlog({ outputRoot: OUTPUT });
console.log(`Built Health.md static site with Spanish localization and ${posts.length} blog post${posts.length === 1 ? '' : 's'} in ${OUTPUT}`);
