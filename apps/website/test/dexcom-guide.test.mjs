import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';

const BLOG_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'content', 'blog');
const read = (slug) => readFile(path.join(BLOG_DIR, `${slug}.md`), 'utf8');

// Mirrors the build script's heading ids: section-<slugified title>.
const idFor = (title) => `section-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')}`;

test('Dexcom guide in-page anchors match its H2 headings', async () => {
  const { content } = matter(await read('export-dexcom-data'));
  const ids = new Set([...content.matchAll(/^## (.+)$/gm)].map((m) => idFor(m[1])));
  const anchors = [...content.matchAll(/\]\(#([^)]+)\)/g)].map((m) => m[1]);
  assert.ok(anchors.length >= 4);
  for (const anchor of anchors) assert.ok(ids.has(anchor), `missing heading for #${anchor}`);
});

test('Dexcom guide answers G7 export early and has inbound links from other pages', async () => {
  const { data, content } = matter(await read('export-dexcom-data'));
  const first = content.trim().split(/\s+/).slice(0, 100).join(' ');
  assert.match(data.title, /Dexcom G7/);
  assert.match(first, /Dexcom G7/);
  assert.match(first, /no CSV export button/);
  assert.match(first, /Clarity/);
  const omron = matter(await read('export-omron-connect-data'));
  assert.ok(omron.data.related.includes('export-dexcom-data'));
  assert.ok(omron.data.related.length <= 3);
  assert.match(await read('apple-health-to-excel'), /\/blog\/export-dexcom-data\//);
});
