import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { buildCommand } from '../apple-health-cli/command.mjs';
const defaults = { metric: 'steps', range: '7', format: 'json', detail: 'summary' };
test('builds documented commands across every supported combination', () => {
  for (const [metric, id] of Object.entries({ steps: 'steps', sleep: 'sleep_total', heart: 'resting_heart_rate', workouts: 'workouts' }))
    for (const range of ['7', '30', '90', 'yesterday', 'custom'])
      for (const format of ['json', 'jsonl'])
        for (const detail of ['summary', 'lossless']) {
          const result = buildCommand({ metric, range, format, detail, from: '2026-01-01', to: '2026-01-07' });
          const dates = range === 'custom' ? '--from 2026-01-01 --to 2026-01-07' : range === 'yesterday' ? '--yesterday' : `--last ${range}`;
          assert.equal(result.command, `healthmd extract --metric ${id} ${dates} --detail ${detail} --format ${format} --output ${id.replaceAll('_', '-')}.${format}`);
          assert.equal(result.receipt, format === 'jsonl' ? `${result.filename}.receipt.json` : null);
        }
});
test('rejects invalid dates and untrusted command input', () => {
  for (const dates of [{}, { from: '2026-02-30', to: '2026-03-01' }, { from: '2026-01-02', to: '2026-01-01' }, { from: '2026-01-01; whoami', to: '2026-01-02' }])
    assert.throws(() => buildCommand({ ...defaults, range: 'custom', ...dates }));
  for (const field of ['metric', 'range', 'format', 'detail'])
    assert.throws(() => buildCommand({ ...defaults, [field]: '$(whoami)' }));
  assert.doesNotThrow(() => buildCommand({ ...defaults, range: 'custom', from: '2024-02-29', to: '2024-02-29' }));
});
test('SEO graph matches visible FAQs and identifies the free tool', async () => {
  const html = await readFile(new URL('../apple-health-cli/index.html', import.meta.url), 'utf8');
  assert.equal((html.match(/<h1\b/g) ?? []).length, 1);
  assert.match(html, /rel="canonical" href="https:\/\/healthmd.app\/apple-health-cli\/"/);
  const graph = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1])['@graph'];
  const visible = html.replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/, '');
  for (const question of graph.find(node => node['@type'] === 'FAQPage').mainEntity) {
    assert.ok(visible.includes(question.name));
    assert.ok(visible.includes(question.acceptedAnswer.text));
  }
  assert.equal(graph.find(node => node['@type'] === 'WebApplication').offers.price, '0');
  assert.equal((visible.match(/class="cta"/g) ?? []).length, 1);
});
