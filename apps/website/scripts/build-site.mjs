#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { publishedLocales } from '../i18n/locales.mjs';
import { buildBlog } from './build-blog.mjs';
import { buildLocalizedLanding } from './build-localized-pages.mjs';
import { buildLocalizedLegalPages } from './build-localized-legal-pages.mjs';
import { localizeSitemapFile } from './build-localized-sitemap.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUTPUT = path.join(ROOT, 'dist');
const DOCS_OUTPUT = path.join(ROOT, 'docs-src', 'dist');
const STATIC_DIRECTORIES = ['assets', 'visualizations'];
const STATIC_FILES = [
  'favicon.ico',
  'llms.txt',
  'robots.txt',
];

await fs.rm(OUTPUT, { recursive: true, force: true });
await fs.mkdir(OUTPUT, { recursive: true });

// Astro emits stable /docs/ and localized /<locale>/docs/ routes directly. Copy
// the complete output first, then merge the website's shared static assets.
await fs.cp(DOCS_OUTPUT, OUTPUT, { recursive: true, force: true });

for (const directory of STATIC_DIRECTORIES) {
  await fs.cp(path.join(ROOT, directory), path.join(OUTPUT, directory), { recursive: true, force: true });
}

for (const filename of STATIC_FILES) {
  await fs.copyFile(path.join(ROOT, filename), path.join(OUTPUT, filename));
}

await Promise.all([
  buildLocalizedLegalPages(OUTPUT),
  ...publishedLocales('landing').map(({ code }) =>
    buildLocalizedLanding({ outputRoot: OUTPUT, locale: code }),
  ),
]);

const posts = await buildBlog({ outputRoot: OUTPUT });
await localizeSitemapFile(path.join(OUTPUT, 'sitemap.xml'));
const localizedCount = publishedLocales('landing').length - 1;
console.log(`Built Health.md static site with ${localizedCount} localized language routes and ${posts.length} blog post${posts.length === 1 ? '' : 's'} in ${OUTPUT}`);
