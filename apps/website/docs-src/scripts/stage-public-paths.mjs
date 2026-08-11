#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  docsRouteForSource,
  markdownPathForDocsPath,
  walkMarkdownSources,
} from '../lib/docs-metadata.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');
const DOCS = path.join(DIST, 'docs');
const CONTENT = path.join(ROOT, 'src/content/docs');

const entries = [
  ['favicon.png', 'favicon.png'],
  ['vertical-tables.js', 'vertical-tables.js'],
  ['assets', 'assets'],
  ['reference', 'reference'],
  ['social', 'social'],
];

for (const [sourceRelative, destinationRelative] of entries) {
  const source = path.join(DIST, sourceRelative);
  const destination = path.join(DOCS, destinationRelative);
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await fs.cp(source, destination, { recursive: true, force: true });
}

let markdownCount = 0;
for (const source of await walkMarkdownSources(CONTENT)) {
  const relative = path.relative(CONTENT, source).split(path.sep).join('/');
  const markdownRoute = markdownPathForDocsPath(docsRouteForSource(relative));
  const destination = path.join(DIST, ...markdownRoute.replace(/^\/+/, '').split('/'));
  const existing = await fs.access(destination).then(() => true).catch(() => false);
  if (existing) {
    throw new Error(`Markdown alternate route collides with a staged public asset: ${markdownRoute}`);
  }
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await fs.copyFile(source, destination);
  markdownCount += 1;
}

console.log(`Staged documentation public assets and ${markdownCount} source Markdown alternatives under /docs/.`);
