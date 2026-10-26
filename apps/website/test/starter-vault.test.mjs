import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import matter from 'gray-matter';
import { build } from 'esbuild';
import { ARCHIVE_PATH, DAYS, METRICS, buildStarterVault, chartSvg, summarize, vaultFiles, zipVault } from '../scripts/build-starter-vault.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const files = await vaultFiles();
const text = name => files.get(name).toString('utf8');

test('28 unique consecutive sample days preserve numeric values and missingness', () => {
  const notes = [...files].filter(([name]) => name.startsWith('Health/'));
  assert.equal(notes.length, 28);
  for (const [name, bytes] of notes) {
    const { data } = matter(bytes.toString('utf8'));
    const date = data.date.toISOString().slice(0, 10);
    const source = DAYS.find(day => day.date === date);
    assert.ok(source, name);
    assert.equal(name, `Health/${date}.md`);
    assert.equal(data.sample_data, true);
    assert.equal(data.type, 'health-data');
    assert.equal(data.schema, undefined, 'illustrative notes must not claim an export schema');
    for (const { key } of METRICS) {
      assert.equal(data[key], source[key], `${date} ${key}`);
      if (data[key] !== undefined) assert.equal(typeof data[key], 'number');
    }
  }
  assert.equal(new Set(DAYS.map(day => day.date)).size, 28);
  for (let i = 1; i < DAYS.length; i++) assert.equal(Date.parse(DAYS[i].date) - Date.parse(DAYS[i - 1].date), 86400000);
  assert.equal(summarize(DAYS, 'sleep_total_hours').count, 27);
  assert.equal(summarize(DAYS, 'resting_heart_rate').count, 27);
  assert.deepEqual(summarize([{ steps: 0 }, {}, { steps: 10 }], 'steps'), { count: 2, sum: 10, average: 5 });
});

test('all wiki links and local attachments resolve, including links inside Markdown tables', () => {
  for (const [name, bytes] of files) {
    if (!name.endsWith('.md')) continue;
    for (const line of bytes.toString().split('\n').filter(line => line.startsWith('|'))) {
      assert.doesNotMatch(line, /\[\[[^\]]*(?<!\\)\|/, `${name}: wiki-link aliases in tables must escape their pipe`);
    }
    for (const [, link] of bytes.toString().matchAll(/\[\[([^\]]+)\]\]/g)) {
      const target = link.split('|')[0].replace(/\\$/, '').split('#')[0];
      assert.ok(files.has(target) || files.has(`${target}.md`), `${name} -> ${target}`);
    }
  }
});

test('weekly summaries match independently reduced frontmatter and exclude absent values', () => {
  const actual = Array.from({ length: 14 }, (_, i) => matter(text(`Health/2026-10-${String(i + 12).padStart(2, '0')}.md`)).data);
  const review = text('Reviews/2026-10-19 Weekly review.md');
  for (const { key, label, unit } of METRICS) {
    const halves = [actual.slice(7), actual.slice(0, 7)];
    const values = halves.map(days => days.map(day => day[key]).filter(Number.isFinite));
    const formatted = values.map(v => key === 'steps'
      ? v.reduce((a, b) => a + b, 0).toLocaleString('en-US')
      : (v.reduce((a, b) => a + b, 0) / v.length).toFixed(2));
    assert.ok(review.includes(`| ${key === 'steps' ? 'Total steps' : `Average ${label.toLowerCase()}`} (${unit}) | ${formatted.join(' | ')} | ${values[0].length}/7 · ${values[1].length}/7 |`));
  }
  assert.match(review, /week_start: 2026-10-19/);
  assert.match(review, /week_end: 2026-10-25/);
});

test('charts have units, accessible descriptions, exact point coverage and gaps at missing dates', () => {
  for (const metric of METRICS) {
    const svg = chartSvg(metric);
    assert.match(svg, /role="img" aria-labelledby="title desc"/);
    assert.ok(svg.includes(metric.unit));
    assert.doesNotMatch(svg, /NaN|Infinity|<script|https?:\/\/[^w]/);
    const observed = DAYS.filter(day => day[metric.key] !== undefined).length;
    assert.equal((svg.match(/<title>2026-/g) || []).length, observed);
    if (metric.key !== 'steps') {
      assert.equal((svg.match(/<path d="M[\d.]+ [\d.]+L/g) || []).length, 25, '27 points with one internal gap have 25 connecting segments');
      assert.match(svg, /Missing: 2026-/);
    }
  }
});

test('core configuration enables templates and Bases without installing community code', () => {
  const core = JSON.parse(text('.obsidian/core-plugins.json'));
  assert.ok(core.includes('bases') && core.includes('templates'));
  assert.equal(JSON.parse(text('.obsidian/templates.json')).folder, 'Templates');
  assert.equal(JSON.parse(text('.obsidian/workspace.json')).main.children[0].state.state.file, 'Start here.md');
  assert.ok(![...files.keys()].some(name => name.startsWith('.obsidian/plugins/') || name === '.obsidian/community-plugins.json'));
  const base = matter(`---\n${text('Views/Health log.base')}\n---`).data;
  assert.equal(base.views.length, 2);
  assert.equal(base.views[1].name, 'Review week');
  assert.ok(base.views[1].filters.and.includes('date(note.date) <= date(this.week_end)'));
  assert.match(base.summaries['Observed mean'], /values\.filter\(value\.isType\("number"\)\)/, 'empty cells must not enter means');
  assert.ok(base.views.every(view => view.summaries['note.sleep_total_hours'] === 'Observed mean'));
  assert.match(text('Templates/Weekly review.md'), /week_start:\nweek_end:/);
});

test('committed archive is reproducible and the existing blog exposes its download', async () => {
  await buildStarterVault({ check: true });
  assert.deepEqual(await fs.readFile(ARCHIVE_PATH), zipVault(files));
  const blog = await fs.readFile(path.join(ROOT, 'content/blog/export-apple-health-data-to-obsidian.md'), 'utf8');
  assert.match(blog, /\]\(\/assets\/downloads\/healthmd-obsidian-starter\.zip\)/);
  assert.match(blog, /fixed sample snapshots/);
});

test('public starter previews match the generated daily notes and weekly review', async () => {
  const post = await fs.readFile(path.join(ROOT, 'content/blog/export-apple-health-data-to-obsidian.md'), 'utf8');
  const cards = [...post.matchAll(/<section class="starter-preview-card">([\s\S]*?)<\/section>/g)].map(match => match[1]);
  const daily = cards.find(card => card.includes('One daily note'));
  assert.ok(daily, 'daily preview exists');
  const date = daily.match(/From Health\/(\d{4}-\d{2}-\d{2})\.md/)?.[1];
  assert.ok(date, 'daily preview identifies its source file');
  const day = matter(text(`Health/${date}.md`)).data;
  assert.ok(daily.includes(`<dt>Steps</dt><dd>${day.steps.toLocaleString('en-US')}</dd>`));
  assert.ok(daily.includes(`<dt>Sleep</dt><dd>${day.sleep_total_hours} hours</dd>`));
  assert.ok(daily.includes(`<dt>Resting heart rate</dt><dd>${day.resting_heart_rate} bpm</dd>`));

  const displayed = [...post.matchAll(/^\| (\d{4}-\d{2}-\d{2}) \| (\d+) \| ([\d.]+) \| (\d+) \|$/gm)];
  assert.equal(displayed.length, 3, 'all visible log rows are checked');
  for (const [, sourceDate, steps, sleep, heart] of displayed) {
    const source = matter(text(`Health/${sourceDate}.md`)).data;
    assert.equal(Number(steps), source.steps, `${sourceDate}: steps`);
    assert.equal(Number(sleep), source.sleep_total_hours, `${sourceDate}: sleep hours`);
    assert.equal(Number(heart), source.resting_heart_rate, `${sourceDate}: heart rate`);
  }

  const weekly = cards.find(card => card.includes('A completed weekly review'));
  assert.ok(weekly, 'weekly preview exists');
  const { data: range } = matter(text('Reviews/2026-10-19 Weekly review.md'));
  const start = range.week_start.toISOString().slice(0, 10);
  const end = range.week_end.toISOString().slice(0, 10);
  const days = DAYS.filter(day => day.date >= start && day.date <= end);
  const steps = summarize(days, 'steps'), sleep = summarize(days, 'sleep_total_hours');
  assert.ok(weekly.includes(`<strong>${steps.sum.toLocaleString('en-US')} steps</strong>`));
  assert.ok(weekly.includes(`<strong>${sleep.average.toFixed(2)} hours</strong>`));
  assert.equal(steps.count, sleep.count, 'shared coverage claim requires equal observation counts');
  assert.ok(weekly.includes(`${steps.count} of ${days.length} days observed`));
});

test('external plugin can parse all samples and resolve chart metrics without filling missing values', {
  skip: !process.env.HEALTHMD_OBSIDIAN_PLUGIN_REPO && 'Set HEALTHMD_OBSIDIAN_PLUGIN_REPO to verify against the external consumer',
}, async () => {
  const plugin = process.env.HEALTHMD_OBSIDIAN_PLUGIN_REPO;
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'healthmd-starter-parser-'));
  try {
    const entry = path.join(temp, 'entry.mjs');
    await fs.writeFile(entry, `export { parseMarkdown } from ${JSON.stringify(path.join(plugin, 'src/parsers/markdown-parser.ts'))};\nexport { resolveNumericMetric } from ${JSON.stringify(path.join(plugin, 'src/metric-resolver.ts'))};\n`);
    const outfile = path.join(temp, 'parser.mjs');
    await build({ entryPoints: [entry], bundle: true, platform: 'node', format: 'esm', outfile, logLevel: 'silent' });
    const { parseMarkdown, resolveNumericMetric } = await import(pathToFileURL(outfile).href);
    for (const day of DAYS) {
      const parsed = parseMarkdown(text(`Health/${day.date}.md`));
      assert.equal(parsed.date, day.date);
      for (const metric of METRICS) assert.equal(resolveNumericMetric(parsed, metric.key), day[metric.key], `${day.date} ${metric.key}`);
    }
  } finally {
    await fs.rm(temp, { recursive: true, force: true });
  }
});
