#!/usr/bin/env node
// Authoring uses the bundled spreadsheet runtime, not website dependencies.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { RAW_ROWS, SAMPLE_DAYS, SAMPLE_DIR, SAMPLE_SUMMARY, WORKBOOK_NAME } from './build-spreadsheet-samples.mjs';

const runtime = process.env.HEALTHMD_ARTIFACT_RUNTIME;
if (!runtime) throw new Error('Set HEALTHMD_ARTIFACT_RUNTIME to a directory with the bundled @oai/artifact-tool node_modules link. See spreadsheet-samples/README.md.');
if (!process.env.HEALTHMD_SOFFICE) throw new Error('Set HEALTHMD_SOFFICE to the bundled LibreOffice executable for native recalculation and populated chart caches.');
if (!process.env.HEALTHMD_PYTHON) throw new Error('Set HEALTHMD_PYTHON to the bundled Python executable for the unsupported chart-gap serialization repair.');
const require = createRequire(path.join(runtime, 'authoring.cjs'));
const { Workbook, SpreadsheetFile } = await import(require.resolve('@oai/artifact-tool'));
const arg = process.argv.indexOf('--output');
if (arg < 0 || !process.argv[arg + 1]) throw new Error('Provide --output DIRECTORY for workbook and verification previews.');
const outputDir = path.resolve(process.argv[arg + 1]);
await fs.mkdir(outputDir, { recursive: true });
const wb = Workbook.create();
const overview = wb.worksheets.add('Overview');
const daily = wb.worksheets.add('Daily metrics');
const raw = wb.worksheets.add('Raw data');
const rawEnd = RAW_ROWS.length + 6;
const input = column => `'Raw data'!$${column}$7:$${column}$${rawEnd}`;
const prepared = column => `'Daily metrics'!${column}7:${column}34`;
const colors = { ink: '#183149', muted: '#516477', header: '#213A56', blue: '#2563EB', purple: '#7C3AED' };

function base(sheet, range) {
  sheet.showGridLines = false;
  sheet.getRange(range).format.font = { name: 'Arial', size: 11, color: colors.ink };
  sheet.getRange(range).format.rowHeight = 23;
  sheet.getRange(range).format.verticalAlignment = 'center';
}
function title(sheet, cell, value) {
  sheet.getRange(cell).values = [[value]];
  sheet.getRange(cell).format.font = { name: 'Arial', size: 16, bold: true, color: colors.ink };
  sheet.getRange(cell).format.rowHeight = 29;
}
function header(sheet, range, values) {
  sheet.getRange(range).values = [values];
  sheet.getRange(range).format = { fill: colors.header, font: { name: 'Arial', size: 11, bold: true, color: '#FFFFFF' }, horizontalAlignment: 'center', verticalAlignment: 'center', rowHeight: 28 };
}
base(raw, `A1:G${rawEnd}`);
title(raw, 'A2', 'Fictional source rows');
raw.getRange('A3').values = [['Illustrative two-metric CSV subset. No personal health records.']];
raw.getRange('A4').values = [['Source: Health.md fictional starter dataset, https://healthmd.app/blog/export-apple-health-data-to-obsidian/#starter-vault']];
raw.getRange('A3:G4').format.font = { name: 'Arial', size: 10, color: colors.muted };
header(raw, 'A6:G6', ['Date', 'Category', 'Metric', 'Value', 'Unit', 'Timestamp', 'Checked value']);
raw.getRange(`A7:F${rawEnd}`).values = RAW_ROWS;
raw.getRange(`D7:D${rawEnd}`).setNumberFormat('0');
raw.getRange(`D7:D${rawEnd}`).format.font = { name: 'Arial', size: 11, color: colors.blue };
raw.getRange(`G7:G${rawEnd}`).formulas = RAW_ROWS.map((_, i) => [`=IF(D${i + 7}="","",IF(ISNUMBER(D${i + 7}),D${i + 7},NA()))`]);
raw.getRange(`G7:G${rawEnd}`).setNumberFormat('0');
for (const [column, width] of Object.entries({ A: 14, B: 14, C: 20, D: 14, E: 14, F: 14, G: 16 })) raw.getRange(`${column}1:${column}${rawEnd}`).format.columnWidth = width;
raw.getRange(`E7:E${rawEnd}`).format.horizontalAlignment = 'center';
raw.freezePanes.freezeRows(6);

base(daily, 'A1:H36');
title(daily, 'A2', 'Daily metrics');
daily.getRange('A3').values = [['Fictional data. A blank is not a measured zero.']];
daily.getRange('A4').values = [['Sleep uses journal dates. Missing chart values use #N/A so the line has a gap.']];
header(daily, 'A6:H6', ['Journal date', 'Chart date', 'Step rows', 'Steps', 'Sleep rows', 'Sleep seconds', 'Sleep hours', 'Sleep chart']);
daily.getRange('A7:A34').values = SAMPLE_DAYS.map(day => [new Date(`${day.date}T00:00:00Z`)]);
daily.getRange('A7:A34').setNumberFormat('yyyy-mm-dd');
for (let i = 0; i < 28; i++) {
  const r = i + 7;
  const criteria = (category, metric, unit) => `${input('A')},TEXT(A${r},"yyyy-mm-dd"),${input('B')},"${category}",${input('C')},"${metric}",${input('E')},"${unit}"`;
  const steps = criteria('Activity', 'Steps', 'count');
  const sleep = criteria('Sleep', 'Total Duration', 'seconds');
  daily.getRange(`B${r}:H${r}`).formulas = [[
    `=TEXT(A${r},"mm/dd")`,
    `=COUNTIFS(${steps},${input('D')},"<>")`,
    `=IF(C${r}=0,"",IF(C${r}=1,SUMIFS(${input('G')},${steps}),NA()))`,
    `=COUNTIFS(${sleep},${input('D')},"<>")`,
    `=IF(E${r}=0,"",IF(E${r}=1,SUMIFS(${input('G')},${sleep}),NA()))`,
    `=IF(F${r}="","",F${r}/3600)`,
    `=IF(G${r}="",NA(),G${r})`,
  ]];
}
daily.getRange('B7:C34').format.horizontalAlignment = 'center';
daily.getRange('E7:E34').format.horizontalAlignment = 'center';
daily.getRange('D7:F34').setNumberFormat('#,##0');
daily.getRange('G7:H34').setNumberFormat('0.00');
for (const [column, width] of Object.entries({ A: 15, B: 12, C: 11, D: 13, E: 11, F: 16, G: 14, H: 14 })) daily.getRange(`${column}1:${column}36`).format.columnWidth = width;
daily.getRange('A36').values = [['Duplicate metric rows produce #N/A. Investigate duplicates before adding values.']];
daily.freezePanes.freezeRows(6);

base(overview, 'B1:M29');
overview.getRange('B1:M29').format.columnWidth = 12;
overview.getRange('B1:B29').format.columnWidth = 17;
title(overview, 'B2', 'Fictional health data');
overview.getRange('B3').values = [['September 28 to October 25, 2026. Edit source values to explore the formulas.']];
header(overview, 'B5:F5', ['Metric', 'Recorded days', 'Average', 'Total', 'Unit']);
overview.getRange('B6').values = [['Steps']];
overview.getRange('B7').values = [['Sleep duration']];
overview.getRange('C6:E6').formulas = [[`=COUNT(${prepared('D')})`, `=IF(C6=0,"",AVERAGE(${prepared('D')}))`, `=SUM(${prepared('D')})`]];
overview.getRange('C7:E7').formulas = [[`=COUNT(${prepared('G')})`, `=IF(C7=0,"",AVERAGE(${prepared('G')}))`, `=SUM(${prepared('G')})`]];
overview.getRange('F6:F7').values = [['count'], ['hours']];
overview.getRange('C6:E6').setNumberFormat('#,##0');
overview.getRange('C7').setNumberFormat('0');
overview.getRange('D7:E7').setNumberFormat('0.00');
overview.getRange('H5').values = [['28 fictional journal dates']];
overview.getRange('H6').values = [['October 8: no sleep reading']];
overview.getRange('H7').values = [['No targets or health conclusions']];
overview.getRange('B9').values = [['Averages include recorded days only. Missing sleep is a chart gap, not zero.']];
overview.getRange('B9:M9').format.font = { name: 'Arial', size: 10, color: colors.muted };
for (const [valueColumn, chartTitle, color, first, last, format] of [
  ['D', 'Daily steps (count)', colors.blue, 'B11', 'G27', '#,##0'],
  ['H', 'Sleep duration (hours)', colors.purple, 'H11', 'M27', '0.0'],
]) {
  // Range references stay live when Raw data changes. #N/A means a missing point.
  const chart = overview.charts.add('line', [daily.getRange('B6:B34'), daily.getRange(`${valueColumn}6:${valueColumn}34`)]);
  chart.title = chartTitle;
  chart.hasLegend = false;
  chart.titleTextStyle.typeface = 'Arial';
  chart.titleTextStyle.fontSize = 14;
  chart.xAxis = { axisType: 'textAxis', textStyle: { typeface: 'Arial', fontSize: 11 }, tickLabelInterval: 7 };
  chart.yAxis = { numberFormatCode: format, numberFormatSourceLinked: false, textStyle: { typeface: 'Arial', fontSize: 11 } };
  chart.series.items[0].line = { fill: color, style: 'solid', width: 2 };
  chart.setPosition(first, last);
}
overview.getRange('B29').values = [['Fixed 28-day example. To analyze your own export, follow the Excel or Google Sheets guide.']];
overview.tabColor = colors.header;

// Exercise the live dependencies, then restore the original fiction before export.
wb.recalculate();
const total = overview.getRange('E6').values[0][0];
assert.equal(total, SAMPLE_SUMMARY.steps.sum);
assert.equal(overview.getRange('C7').values[0][0], 27);
assert.ok(Math.abs(overview.getRange('D7').values[0][0] - SAMPLE_SUMMARY.sleep_hours.average) < 1e-9);
const original = raw.getRange('D7').values[0][0];
raw.getRange('D7').values = [[original + 137]];
assert.equal(overview.getRange('E6').values[0][0], total + 137);
raw.getRange('D7').values = [[0]];
assert.equal(daily.getRange('D7').values[0][0], 0);
assert.equal(overview.getRange('C6').values[0][0], 28);
raw.getRange('D7').values = [[null]];
assert.equal(daily.getRange('D7').values[0][0], '');
assert.equal(overview.getRange('C6').values[0][0], 27);
raw.getRange('D7').values = [['invalid']];
assert.equal(daily.getRange('D7').values[0][0], '#N/A');
raw.getRange('D7').values = [[original]];
const secondDate = raw.getRange('A9').values[0][0];
raw.getRange('A9').values = [[SAMPLE_DAYS[0].date]];
assert.equal(daily.getRange('C7').values[0][0], 2);
assert.equal(daily.getRange('D7').values[0][0], '#N/A');
raw.getRange('A9').values = [[secondDate]];
const lastDate = raw.getRange(`A${rawEnd}`).values[0][0];
raw.getRange(`A${rawEnd}`).values = [['2026-10-08']];
assert.equal(daily.getRange('G17').values[0][0], 8);
assert.equal(daily.getRange('G34').values[0][0], '');
raw.getRange(`A${rawEnd}`).values = [[lastDate]];
wb.recalculate();
const inspection = await wb.inspect({ kind: 'region', sheetId: 'Overview', range: 'B5:F7', maxChars: 2000 });
await fs.writeFile(path.join(outputDir, 'calculation-checks.json'), JSON.stringify({ expected: SAMPLE_SUMMARY, mutationChecks: ['changed value updates total', 'zero remains recorded', 'blank excluded', 'invalid numeric input remains an error', 'duplicate date rejected', 'sleep reassignment updates date coverage'], inspection: inspection.ndjson }, null, 2));
const errors = await wb.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!', options: { useRegex: true, maxResults: 30 }, summary: 'Only intentional missing-sleep chart marker is expected at Daily metrics!H17.' });
const formulaErrors = errors.ndjson.trim().split('\n').filter(Boolean).map(line => JSON.parse(line)).filter(row => row.formula);
assert.deepEqual(formulaErrors.map(row => `${row.sheet}!${row.address}`), ['Daily metrics!H17']);
await fs.writeFile(path.join(outputDir, 'formula-scan.ndjson'), errors.ndjson);
for (const [sheetName, range, name] of [['Overview', 'B2:M29', 'workbook-preview'], ['Daily metrics', 'A2:H36', 'daily-metrics'], ['Raw data', `A2:G${rawEnd}`, 'raw-data']]) {
  const preview = await wb.render({ sheetName, range, scale: 1.5, format: 'png' });
  await fs.writeFile(path.join(outputDir, `${name}.png`), new Uint8Array(await preview.arrayBuffer()));
}
const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(path.join(outputDir, WORKBOOK_NAME));
// Populate native Excel chart caches and independently recalculate saved formulas.
// The artifact-tool export retains live series but initially has empty chart caches.
const nativeDir = await fs.mkdtemp(path.join(outputDir, '.native-recalc-'));
try {
  const result = await promisify(execFile)(process.env.HEALTHMD_SOFFICE, [
    `-env:UserInstallation=${pathToFileURL(path.join(nativeDir, 'profile')).href}`,
    '--headless', '--convert-to', 'xlsx', '--outdir', nativeDir, path.join(outputDir, WORKBOOK_NAME),
  ], { timeout: 60_000 });
  await fs.writeFile(path.join(outputDir, 'native-recalculation.log'), result.stdout);
  await fs.copyFile(path.join(nativeDir, WORKBOOK_NAME), path.join(outputDir, WORKBOOK_NAME));
} finally {
  await fs.rm(nativeDir, { recursive: true, force: true });
}
// The chart API has no documented missing-value policy, and the native serializer
// defaults it to zero. Repair only that unsupported setting using stdlib ZIP/XML.
await promisify(execFile)(process.env.HEALTHMD_PYTHON, ['-c', `
import pathlib, sys, zipfile
from xml.etree import ElementTree as E
p = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(p) as z:
    parts = [(item, z.read(item.filename)) for item in z.infolist()]
ns = {'c': 'http://schemas.openxmlformats.org/drawingml/2006/chart'}
patched = []
for item, data in parts:
    if '/charts/chart' in item.filename and item.filename.endswith('.xml'):
        root = E.fromstring(data)
        gap = root.find('.//c:dispBlanksAs', ns)
        if gap is None or gap.attrib.get('val') != 'zero':
            raise RuntimeError('Unexpected native chart policy; review serializer output')
        data = data.replace(b'<c:dispBlanksAs val="zero"/>', b'<c:dispBlanksAs val="gap"/>')
        assert E.fromstring(data).find('.//c:dispBlanksAs', ns).attrib['val'] == 'gap'
    patched.append((item, data))
with zipfile.ZipFile(p, 'w') as z:
    for item, data in patched:
        z.writestr(item, data)
`, path.join(outputDir, WORKBOOK_NAME)], { timeout: 10_000 });
await fs.mkdir(SAMPLE_DIR, { recursive: true });
await fs.copyFile(path.join(outputDir, WORKBOOK_NAME), path.join(SAMPLE_DIR, WORKBOOK_NAME));
await fs.copyFile(path.join(outputDir, 'workbook-preview.png'), path.join(SAMPLE_DIR, 'workbook-preview.png'));
console.log(`Authored ${WORKBOOK_NAME}: 28 days, ${RAW_ROWS.length} source rows, two editable charts. Recalculation and missing/zero checks passed.`);
