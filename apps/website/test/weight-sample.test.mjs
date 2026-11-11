import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('weight guide examples preserve the published Apple exporter sample values and units', async () => {
  const [article, csv, json] = await Promise.all([
    readFile(path.join(ROOT, 'content/blog/export-apple-health-weight-data.md'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/public/reference/generated/core/summary-day.csv'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/public/reference/generated/core/summary-day.json'), 'utf8'),
  ]);
  const rows = article.match(/```csv\n([\s\S]*?)\n```/)[1].split('\n');
  const original = csv.trim().split(/\r?\n/);
  assert.equal(rows[0], original[0]);
  assert.equal(rows.length, 2);
  assert.ok(original.includes(rows[1]));
  assert.equal(rows[1].split(',').length, 5, 'the daily row omits the final Timestamp field');
  const excerpt = JSON.parse(article.match(/```json\n([\s\S]*?)\n```/)[1]);
  const sample = JSON.parse(json);
  assert.equal(excerpt.body.weight, sample.body.weight);
  assert.equal(excerpt.units.weight_kg, sample.units.weight_kg);
});
