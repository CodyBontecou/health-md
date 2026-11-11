import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('published Health Connect CSV excerpt stays tied to the Android renderer fixture', async () => {
  const [fixture, sample, html] = await Promise.all([
    readFile(path.join(ROOT, '../../packages/contracts/render-input/v1/fixtures/native-android-render-requests-v1.json'), 'utf8'),
    readFile(path.join(ROOT, 'assets/samples/health-connect-summary-excerpt.csv'), 'utf8'),
    readFile(path.join(ROOT, 'health-connect-export/index.html'), 'utf8'),
  ]);
  const source = JSON.parse(fixture).cases.find((entry) => entry.id === 'frozen-default');
  const output = source.expected_outputs.find((entry) => entry.format === 'csv');
  const original = Buffer.from(output.bytes_base64, 'base64').toString('utf8').trim().split('\n');
  const excerpt = sample.trim().split('\n');
  assert.equal(excerpt[0], original[0]);
  assert.ok(excerpt.length > 1 && excerpt.length < original.length, 'a small excerpt, not a complete export');
  for (const line of excerpt.slice(1)) {
    assert.ok(original.includes(line), `published row must come from the Android output: ${line}`);
    assert.equal(line.split(',').length, 6, 'preserve the empty Timestamp cell');
  }
  const inline = html.match(/<code class="language-csv">([\s\S]*?)<\/code>/)?.[1];
  assert.equal(inline, sample.trim(), 'the inline preview matches the downloaded excerpt');
  assert.ok(html.includes('href="/assets/samples/health-connect-summary-excerpt.csv" download'));
  assert.match(html, /fictional activity values/);
});
