import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { CSV_HEADER, CSV_LIMITS, combineHealthmdCsv, parseHealthmdCsv } from '../assets/csv-combiner-core.js';
import { mountCsvCombiner } from '../assets/csv-combiner.js';
import { funnelLink } from '../assets/seo-funnel.js';
const header = CSV_HEADER.join(',');
const row = '2026-03-15,Activity,Steps,12500,count';
const file = (text, name = 'day.csv') => new File([text], name, { type: 'text/csv' });

for (const name of ['summary-day', 'lossless-day', 'provider-day']) {
  test(`combiner preserves every parsed field and row shape in the Apple ${name} fixture`, async () => {
    const text = await readFile(new URL(`../docs-src/public/reference/generated/core/${name}.csv`, import.meta.url), 'utf8');
    const result = await combineHealthmdCsv([file(text), file(text)]);
    const rows = parseHealthmdCsv(text);
    assert.deepEqual(parseHealthmdCsv(result.csv), [CSV_HEADER, ...rows.slice(1), ...rows.slice(1)]);
    assert.equal(result.rowCount, (rows.length - 1) * 2);
    assert.equal(result.fileCount, 2, 'duplicate inputs are retained');
  });
}

test('Android excerpt and Apple summary share the supported header without normalizing their values', async () => {
  const texts = await Promise.all([
    readFile(new URL('../assets/samples/health-connect-summary-excerpt.csv', import.meta.url), 'utf8'),
    readFile(new URL('../docs-src/public/reference/generated/core/summary-day.csv', import.meta.url), 'utf8'),
  ]);
  const result = await combineHealthmdCsv(texts.map(text => file(text)));
  assert.deepEqual(parseHealthmdCsv(result.csv), [CSV_HEADER, ...texts.flatMap(text => parseHealthmdCsv(text).slice(1))]);
});

test('BOM, quoted commas, quotes, multiline fields, empty timestamps and negative numbers round-trip', async () => {
  const text = '\uFEFF' + header + '\r\n2026-03-15,Metadata,note,"line one,\nline ""two""",text,\r\n2026-03-15,Body,Change,-1.25,kg\r\n';
  const output = await combineHealthmdCsv([file(text)]);
  assert.deepEqual(parseHealthmdCsv(output.csv), parseHealthmdCsv(text));
  assert.equal(output.rowCount, 2);
  assert.ok(output.csv.startsWith('\uFEFF' + header + '\r\n'));
});

test('repeated headers and blank lines are removed without deduplicating records', async () => {
  const output = await combineHealthmdCsv([file(`${header}\n\n${row}\n${header}\n${row}\n`)]);
  assert.equal(output.repeatedHeaders, 1);
  assert.deepEqual(parseHealthmdCsv(output.csv), [CSV_HEADER, row.split(','), row.split(',')]);
});

test('header-only exports do not invent zero measurements', async () => {
  const output = await combineHealthmdCsv([file(header + '\n')]);
  assert.equal(output.rowCount, 0);
  assert.deepEqual(parseHealthmdCsv(output.csv), [CSV_HEADER]);
});

for (const [name, body] of Object.entries({
  'XML archives': '<export><record/></export>',
  'other columns': 'Date,Steps\n2026-03-15,1',
  'truncated quotes': `${header}\n2026-03-15,A,B,"incomplete`,
  'unquoted quotes': `${header}\n2026-03-15,A,B,bad"quote,count`,
  'text after quotes': `${header}\n2026-03-15,A,B,"ok"bad,count`,
  'extra columns': `${header}\n${row},,extra`,
  'missing columns': `${header}\n2026-03-15,A`,
})) test(`rejects ${name}`, async () => {
  await assert.rejects(combineHealthmdCsv([file(body)]));
});

for (const value of ['=1+1', '+SUM(1)', '-SUM(1)', '@SUM(1)', ' \t=1', '＝1', '＋SUM(1)', '－SUM(1)', '＠SUM(1)', '\tplain', '\u0000']) {
  test(`rejects formula/control prefix ${JSON.stringify(value)} without modifying data`, async () => {
    const body = `${header}\n2026-03-15,Metadata,note,${JSON.stringify(value).replace(/\\t/g, '\t').replace(/\\u0000/g, '\u0000')},text,`;
    await assert.rejects(combineHealthmdCsv([file(body)]), /formula-like|control/);
  });
}

test('file, byte, row and field limits fail before producing a download', async () => {
  await assert.rejects(combineHealthmdCsv([]), /Choose at least/);
  await assert.rejects(combineHealthmdCsv(Array(32).fill(file(header))), /31 files/);
  await assert.rejects(combineHealthmdCsv([file(header, 'private.xml')]), /ending in .csv/);
  let read = false;
  const oversized = { name: 'private.csv', size: CSV_LIMITS.fileBytes + 1, arrayBuffer: () => { read = true; } };
  await assert.rejects(combineHealthmdCsv([oversized]), /1 MiB/);
  assert.equal(read, false);
  await assert.rejects(combineHealthmdCsv(Array(6).fill({ ...oversized, size: CSV_LIMITS.fileBytes })), /5 MiB/);
  const denseRow = 'a,b,c,d,e\n';
  await assert.rejects(combineHealthmdCsv([file(header + '\n' + denseRow.repeat(25001)), file(header + '\n' + denseRow.repeat(25000))]), /50,000/);
  await assert.rejects(combineHealthmdCsv([file(header + '\na,b,c,' + 'x'.repeat(CSV_LIMITS.fieldChars + 1) + ',e')]), /field is too large/);
});

test('bad UTF-8 and read failures produce fixed errors without filenames or data', async () => {
  await assert.rejects(combineHealthmdCsv([file(new Uint8Array([0xff, 0xfe]))]), /not valid UTF-8/);
  await assert.rejects(combineHealthmdCsv([{ name: 'sensitive.csv', size: 1, arrayBuffer: () => Promise.reject(new Error('sensitive file detail')) }]), error => /could not be read/.test(error.message) && !/sensitive/.test(error.message));
});

function ui() {
  const controls = Object.fromEntries(['files', 'combine', 'demo', 'clear', 'status', 'error', 'download'].map(name => [name, {
    files: [], hidden: true, disabled: false, textContent: '', listeners: {},
    addEventListener(event, callback) { this.listeners[event] = callback; },
    removeAttribute(name) { delete this[name]; },
  }]));
  Object.defineProperty(controls.files, 'value', { set() { this.files = []; } });
  const root = { querySelector: selector => controls[selector.match(/data-csv-(\w+)/)[1]], setAttribute() {}, removeAttribute() {} };
  const blobs = [], revoked = [];
  mountCsvCombiner(root, { urlApi: { createObjectURL(blob) { blobs.push(blob); return `blob:demo-${blobs.length}`; }, revokeObjectURL(url) { revoked.push(url); } } });
  return { controls, blobs, revoked };
}

test('demo creates a downloadable fictional result; clearing releases the URL and selection', async () => {
  const { controls: c, blobs, revoked } = ui();
  await c.demo.listeners.click();
  assert.equal(c.download.hidden, false);
  assert.equal(c.download.download, 'healthmd-combined-example.csv');
  assert.equal(parseHealthmdCsv(await blobs[0].text()).length, 5);
  assert.match(c.status.textContent, /Fictional example: 2 files combined; 4 rows/);
  assert.equal(funnelLink(c.download.href, 'https://healthmd.app'), null, 'private tool downloads are not action events');
  c.clear.listeners.click();
  assert.deepEqual(revoked, ['blob:demo-1']);
  assert.equal(c.download.hidden, true);
  assert.equal(c.download.href, undefined);
  assert.equal(c.files.files.length, 0);
});

test('clearing while a file read is pending cannot resurrect a result or an error', async () => {
  const { controls: c, blobs } = ui();
  let finish;
  const bytes = new TextEncoder().encode(header + '\n' + row);
  c.files.files = [{ name: 'day.csv', size: bytes.byteLength, arrayBuffer: () => new Promise(resolve => { finish = resolve; }) }];
  c.files.listeners.change();
  const pending = c.combine.listeners.click();
  c.clear.listeners.click();
  finish(bytes.buffer);
  await pending;
  assert.equal(blobs.length, 0);
  assert.equal(c.download.hidden, true);
  assert.equal(c.error.hidden, true);
  assert.match(c.status.textContent, /Choose daily CSV/);
});

test('errors hide stale downloads and the modules contain no network or storage sink', async () => {
  const { controls: c, revoked } = ui();
  await c.demo.listeners.click();
  c.files.files = [file('not a CSV')];
  c.files.listeners.change();
  await c.combine.listeners.click();
  assert.equal(c.download.hidden, true);
  assert.equal(c.error.hidden, false);
  assert.equal(revoked.length, 1);
  for (const name of ['csv-combiner.js', 'csv-combiner-core.js']) {
    const source = await readFile(new URL('../assets/' + name, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /\bfetch\s*\(|XMLHttpRequest|sendBeacon|localStorage|sessionStorage|indexedDB/);
  }
});
