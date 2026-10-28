import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('sleep guide excerpt preserves the Apple producer rows and documented CSV widths', async () => {
  const [producer, published, sample, article] = await Promise.all([
    readFile(path.join(ROOT, '../apple/docs/reference/generated/core/summary-day.csv'), 'utf8'),
    readFile(path.join(ROOT, 'docs-src/public/reference/generated/core/summary-day.csv'), 'utf8'),
    readFile(path.join(ROOT, 'assets/samples/apple-health-sleep-excerpt.csv'), 'utf8'),
    readFile(path.join(ROOT, 'content/blog/export-apple-health-sleep-data.md'), 'utf8'),
  ]);
  assert.equal(published, producer, 'website fixture stays byte-identical to the producer');
  const original = producer.trim().split('\n');
  const rows = sample.trim().split('\n');
  assert.equal(rows[0], original[0]);
  let previous = 0;
  for (const line of rows.slice(1)) {
    const index = original.indexOf(line, previous + 1);
    assert.ok(index > previous, `exact source row in order: ${line}`);
    assert.equal(line.split(',')[1], 'Sleep');
    previous = index;
  }
  assert.ok(rows.some((line) => line.split(',').length === 5), 'summary field omission preserved');
  assert.ok(rows.some((line) => line.includes(',Sleep,Sleep Stage,') && line.split(',').length === 6), 'timestamped interval preserved');
  assert.equal(article.match(/```csv\n([\s\S]*?)\n```/)?.[1], sample.trim());
  assert.ok(article.includes('](/assets/samples/apple-health-sleep-excerpt.csv)'));
  assert.match(article, /fictional values/);
});
