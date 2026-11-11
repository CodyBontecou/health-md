import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('Cronometer guide nutrition example preserves the published Apple exporter row and unit', async () => {
  const [article, csv] = await Promise.all([
    readFile(path.join(ROOT, 'content/blog/export-cronometer-data.md'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/public/reference/generated/core/summary-day.csv'), 'utf8'),
  ]);
  const rows = article.match(/```csv\n([\s\S]*?)\n```/)[1].split('\n');
  const original = csv.trim().split(/\r?\n/);
  assert.equal(rows[0], original[0]);
  assert.equal(rows.length, 2);
  assert.ok(original.includes(rows[1]));
  assert.equal(rows[1].split(',').length, 5, 'the daily row omits the final Timestamp field');
  assert.deepEqual(rows[1].split(',').slice(1), ['Nutrition', 'Protein', '120.0', 'g']);
});
