import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';
import test from 'node:test';
import { parseDocument, DomUtils } from 'htmlparser2';
import { SAMPLE_DIR, ARCHIVE_PATH, WORKBOOK_NAME, RAW_ROWS, SAMPLE_DAYS, SAMPLE_SUMMARY, sampleFiles, buildSpreadsheetSamples } from '../scripts/build-spreadsheet-samples.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Read the ZIP central directory so both native XLSX deflate and stored pack entries work.
function unzip(bytes) {
  const end = bytes.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  assert.ok(end >= 0);
  const files = new Map();
  let offset = bytes.readUInt32LE(end + 16);
  for (let i = 0; i < bytes.readUInt16LE(end + 10); i++) {
    assert.equal(bytes.readUInt32LE(offset), 0x02014b50);
    const method = bytes.readUInt16LE(offset + 10);
    const size = bytes.readUInt32LE(offset + 20);
    const nameLength = bytes.readUInt16LE(offset + 28);
    const local = bytes.readUInt32LE(offset + 42);
    const name = bytes.subarray(offset + 46, offset + 46 + nameLength).toString();
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    const compressed = bytes.subarray(start, start + size);
    assert.ok(method === 0 || method === 8);
    files.set(name, method === 8 ? inflateRawSync(compressed) : compressed);
    offset += 46 + nameLength + bytes.readUInt16LE(offset + 30) + bytes.readUInt16LE(offset + 32);
  }
  return files;
}
const name = node => node.name?.split(':').at(-1);
const nodes = (xml, tag) => DomUtils.findAll(node => name(node) === tag, parseDocument(xml, { xmlMode: true }).children);
const content = node => node ? DomUtils.textContent(node) : '';
const parts = unzip(await fs.readFile(path.join(SAMPLE_DIR, WORKBOOK_NAME)));
const xml = file => parts.get(file).toString();
const strings = nodes(xml('xl/sharedStrings.xml'), 'si').map(content);
function cells(file) {
  return new Map(nodes(xml(file), 'c').map(node => {
    const text = content(node.children.find(child => name(child) === 'v'));
    const formula = content(node.children.find(child => name(child) === 'f'));
    const type = node.attribs.t;
    const value = type === 's' ? strings[Number(text)] : type === 'n' || (!type && text !== '') ? Number(text) : text;
    return [node.attribs.r, { value, formula, type }];
  }));
}
const overview = cells('xl/worksheets/sheet1.xml');
const daily = cells('xl/worksheets/sheet2.xml');
const raw = cells('xl/worksheets/sheet3.xml');

test('28 fictional CSV days preserve exact metrics, units and an omitted sleep reading', async () => {
  assert.equal(SAMPLE_DAYS.length, 28);
  assert.equal(new Set(SAMPLE_DAYS.map(day => day.date)).size, 28);
  assert.equal(RAW_ROWS.length, 55);
  assert.deepEqual(SAMPLE_SUMMARY.missing_sleep_dates, ['2026-10-08']);
  const files = sampleFiles();
  for (let i = 0; i < SAMPLE_DAYS.length; i++) {
    const day = SAMPLE_DAYS[i];
    if (i) assert.equal(Date.parse(day.date) - Date.parse(SAMPLE_DAYS[i - 1].date), 86_400_000);
    const csv = files.get(`daily/${day.date}.csv`).toString();
    assert.equal(csv.split('\n')[0], 'Date,Category,Metric,Value,Unit,Timestamp');
    assert.ok(csv.includes(`${day.date},Activity,Steps,${day.steps},count,`));
    assert.equal(csv.includes(',Sleep,Total Duration,'), day.sleep_seconds !== null);
  }
  const combined = files.get('combined.csv').toString();
  assert.equal(combined.match(/^Date,Category,Metric,Value,Unit,Timestamp$/gm).length, 1);
  assert.equal(combined.trim().split('\n').length, 56);
  const stepRows = RAW_ROWS.filter(row => row[1] === 'Activity');
  assert.equal(stepRows.reduce((sum, row) => sum + row[3], 0), 249630);
  assert.ok(Math.abs(RAW_ROWS.filter(row => row[1] === 'Sleep').reduce((sum, row) => sum + row[3], 0) / 3600 - 202.1) < 1e-9);
});

test('saved workbook raw rows, formulas and native recalculated daily results agree', () => {
  assert.deepEqual(nodes(xml('xl/workbook.xml'), 'sheet').map(node => node.attribs.name), ['Overview', 'Daily metrics', 'Raw data']);
  for (let i = 0; i < RAW_ROWS.length; i++) {
    for (let column = 0; column < 6; column++) assert.equal(raw.get(`${'ABCDEF'[column]}${i + 7}`)?.value ?? '', RAW_ROWS[i][column]);
    assert.match(raw.get(`G${i + 7}`).formula, /ISNUMBER/);
  }
  for (let i = 0; i < SAMPLE_DAYS.length; i++) {
    const r = i + 7, day = SAMPLE_DAYS[i];
    assert.equal(daily.get(`D${r}`).value, day.steps);
    assert.match(daily.get(`D${r}`).formula, /SUMIFS/);
    assert.match(daily.get(`C${r}`).formula, /COUNTIFS/);
    assert.ok(daily.get(`D${r}`).formula.includes('Raw data'));
    assert.ok(daily.get(`G${r}`).formula.includes('/3600'));
    if (day.sleep_seconds === null) {
      assert.equal(daily.get(`E${r}`).value, 0);
      assert.equal(daily.get(`G${r}`).value, '');
      assert.equal(daily.get(`H${r}`).value, '#N/A');
    } else {
      assert.equal(daily.get(`F${r}`).value, day.sleep_seconds);
      assert.ok(Math.abs(daily.get(`G${r}`).value - day.sleep_seconds / 3600) < 1e-9);
    }
  }
  assert.equal(overview.get('C6').value, 28);
  assert.equal(overview.get('E6').value, 249630);
  assert.equal(overview.get('C7').value, 27);
  assert.ok(Math.abs(overview.get('D7').value - 202.1 / 27) < 1e-9);
  for (const [sheet, map] of [['Overview', overview], ['Daily metrics', daily], ['Raw data', raw]]) {
    for (const [cell, data] of map) {
      if (data.type === 'e') assert.equal(`${sheet}!${cell}:${data.value}`, 'Daily metrics!H17:#N/A');
      assert.doesNotMatch(data.formula, /#REF!|\[\d+\]/);
    }
  }
  assert.ok(![...parts.keys()].some(file => /vbaProject|externalLinks|connections\.xml/.test(file)));
});

test('both native charts have live source bindings, cached points, units and retained line colors', () => {
  const charts = [...parts.keys()].filter(file => /\/charts\/chart\d+\.xml$/.test(file));
  assert.equal(charts.length, 2);
  for (const [index, column, color, unit] of [[0, 'D', '2563EB', 'count'], [1, 'H', '7C3AED', 'hours']]) {
    const chart = xml(charts[index]);
    const formulas = nodes(chart, 'f').map(content);
    assert.ok(formulas.includes("'Daily metrics'!$B$7:$B$34"));
    assert.ok(formulas.includes(`'Daily metrics'!$${column}$7:$${column}$34`));
    assert.match(chart, new RegExp(color));
    assert.match(chart, new RegExp(unit));
    assert.equal(nodes(chart, 'dispBlanksAs')[0].attribs.val, 'gap');
    const category = nodes(chart, 'cat')[0];
    assert.equal(nodes(DomUtils.getOuterHTML(category), 'pt').length, 28);
    const values = nodes(DomUtils.getOuterHTML(nodes(chart, 'val')[0]), 'pt');
    assert.ok(values.length >= 27, 'saved chart is populated before Excel recalculation');
    const missing = values.find(node => node.attribs.idx === '10');
    if (index === 1) assert.ok(!missing || content(missing) === '#N/A' || content(missing) === '', 'missing sleep must never be cached as zero');
  }
});

test('download pack is reproducible and carries the exact workbook, CSVs and fiction notice', async () => {
  await buildSpreadsheetSamples({ check: true });
  const pack = unzip(await fs.readFile(ARCHIVE_PATH));
  const prefix = 'Health.md Spreadsheet Sample/';
  assert.equal([...pack.keys()].filter(file => file.startsWith(prefix + 'daily/')).length, 28);
  assert.deepEqual(pack.get(prefix + WORKBOOK_NAME), await fs.readFile(path.join(SAMPLE_DIR, WORKBOOK_NAME)));
  assert.match(pack.get(prefix + 'README.txt').toString(), /All values are fictional/);
  assert.match(pack.get(prefix + 'README.txt').toString(), /not a complete Health.md export/);
  for (const [file, bytes] of sampleFiles()) assert.deepEqual(pack.get(prefix + file), bytes);
  for (const slug of ['apple-health-to-excel', 'apple-health-to-google-sheets']) {
    const source = await fs.readFile(path.join(ROOT, 'content/blog', `${slug}.md`), 'utf8');
    for (const target of ['/assets/downloads/healthmd-spreadsheet-sample.zip', '/assets/downloads/spreadsheet-sample/healthmd-health-data-sample.xlsx', '/assets/downloads/spreadsheet-sample/combined.csv', '/assets/downloads/spreadsheet-sample/workbook-preview.png']) assert.ok(source.includes(target));
  }
});
