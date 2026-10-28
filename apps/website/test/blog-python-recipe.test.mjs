import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const post = await readFile(new URL('../content/blog/apple-health-to-python.md', import.meta.url), 'utf8');
const fences = [...post.matchAll(/```python\n([\s\S]*?)\n```/g)];
assert.equal(fences.length, 1, 'execute the exact single published recipe');
const code = fences[0][1];
const HEADER = 'Date,Category,Metric,Value,Unit,Timestamp';
const row = (day, value, timestamp = '') => `${day},Activity,Steps,${value},count${timestamp ? ',' + timestamp : ''}`;
const reportHeader = 'WeekStarting,RecordedDays,Steps,AveragePerRecordedDay\n';

async function runner(t) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'healthmd-python-recipe-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const script = path.join(dir, 'analyze_steps.py');
  await writeFile(script, code);
  return {
    run: paths => spawnSync('python3', [script, ...paths], { encoding: 'utf8', timeout: 10000 }),
    async file(text, name = 'input.csv') { const file = path.join(dir, name); await writeFile(file, text); return file; },
  };
}

test('published Python script executes against actual summary/lossless/provider producer fixtures', async t => {
  const { run } = await runner(t);
  for (const [name, steps] of [['summary-day', 12500], ['lossless-day', 12500], ['provider-day', 1]]) {
    const file = path.resolve(ROOT, `../apple/docs/reference/generated/core/${name}.csv`);
    const original = await readFile(file);
    const result = run([file]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, reportHeader + `2026-03-09,1,${steps},${steps}.00\n`);
    assert.deepEqual(await readFile(file), original, 'source file remains byte-identical');
  }
  assert.ok(post.includes('2026-03-09,1,12500,12500.00'), 'visible expected result matches execution');
});

test('multiple files group sorted Mondays and include zero days without filling missing dates', async t => {
  const r = await runner(t);
  const a = await r.file(HEADER + '\n' + row('2026-03-18', '0') + '\n' + row('2026-03-16', '11000.0'), 'a.csv');
  const b = await r.file(HEADER + '\n' + row('2026-03-15', '12500'), 'b.csv');
  const result = r.run([a, b]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, reportHeader + '2026-03-09,1,12500,12500.00\n2026-03-16,2,11000,5500.00\n');
});

test('UTF-8 BOM, CRLF, six-field summaries, metadata JSON and timed samples retain scope', async t => {
  const r = await runner(t);
  const lines = [HEADER, '2026-03-15,Metadata,example,"quoted, value\nwith newline",,',
    '2026-03-15,Sleep,Total Duration,27900,seconds', row('2026-03-15', '12500') + ',',
    row('2026-03-15', '22', '2026-03-15T08:00:00Z'), '2026-03-15,Activity,Steps,44,meters'];
  const input = await r.file('\ufeff' + lines.join('\r\n'));
  const result = r.run([input]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, reportHeader + '2026-03-09,1,12500,12500.00\n');
});

for (const [name, body] of Object.entries({
  'overlapping daily rows': row('2026-03-15', '12500') + '\n' + row('2026-03-15', '12500'),
  'invalid date': row('2026-02-30', '12'),
  'ambiguous date': row('03/15/2026', '12'),
  'fractional count': row('2026-03-15', '1.5'),
  'negative count': row('2026-03-15', '-1'),
  'blank count': row('2026-03-15', ''),
  'nonfinite count': row('2026-03-15', 'NaN'),
  'formula count': row('2026-03-15', '=1+1'),
  'repeated header': HEADER,
  'extra field': row('2026-03-15', '12') + ',,extra',
  'truncated row': '2026-03-15,Activity,Steps,12',
  'malformed quoted CSV': '2026-03-15,Activity,Steps,"unterminated,count',
  'no selected metric': '2026-03-15,Sleep,Total Duration,27900,seconds',
})) {
  test(`invalid input fails without partial output: ${name}`, async t => {
    const r = await runner(t);
    const good = await r.file(HEADER + '\n' + row('2026-03-16', '11000'), 'good.csv');
    const bad = await r.file(HEADER + '\n' + body);
    // No-selected-metric must fail alone; other cases fail after valid data too.
    const result = r.run(name === 'no selected metric' ? [bad] : [good, bad]);
    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Cannot build report:/);
  });
}

test('missing files, wrong headers, duplicate file arguments and no arguments fail explicitly', async t => {
  const r = await runner(t);
  const bad = await r.file('Date,Steps\n2026-03-15,12', 'wrong.csv');
  const good = await r.file(HEADER + '\n' + row('2026-03-15', '12500'));
  for (const paths of [[], [bad], [good, good], [good, good + '.missing']]) {
    const result = r.run(paths);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Cannot build report:/);
  }
});
