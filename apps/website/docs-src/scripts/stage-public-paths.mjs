#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');
const DOCS = path.join(DIST, 'docs');

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

console.log('Staged documentation public assets under /docs/.');
