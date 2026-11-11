#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { DAYS, summarize, zipVault } from './build-starter-vault.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SAMPLE_DIR = path.join(ROOT, 'assets/downloads/spreadsheet-sample');
export const WORKBOOK_NAME = 'healthmd-health-data-sample.xlsx';
export const ARCHIVE_PATH = path.join(ROOT, 'assets/downloads/healthmd-spreadsheet-sample.zip');
export const HEADER = ['Date', 'Category', 'Metric', 'Value', 'Unit', 'Timestamp'];

// An illustrative two-metric subset, not a producer-generated export fixture.
// The authored fiction is shared with the Obsidian starter, not a real person.
export const SAMPLE_DAYS = DAYS.map(day => ({
  date: day.date,
  steps: day.steps,
  sleep_seconds: day.sleep_total_hours === undefined ? null : Math.round(day.sleep_total_hours * 3600),
}));
export function rowsForDay(day) {
  const rows = [[day.date, 'Activity', 'Steps', day.steps, 'count', '']];
  if (day.sleep_seconds !== null) rows.push([day.date, 'Sleep', 'Total Duration', day.sleep_seconds, 'seconds', '']);
  return rows;
}
export const RAW_ROWS = SAMPLE_DAYS.flatMap(rowsForDay);
const csv = rows => `${[HEADER, ...rows].map(row => row.join(',')).join('\n')}\n`;

export const SAMPLE_SUMMARY = {
  fictional: true,
  start: SAMPLE_DAYS[0].date,
  end: SAMPLE_DAYS.at(-1).date,
  days: SAMPLE_DAYS.length,
  rows: RAW_ROWS.length,
  steps: summarize(DAYS, 'steps'),
  sleep_hours: summarize(DAYS, 'sleep_total_hours'),
  missing_sleep_dates: SAMPLE_DAYS.filter(day => day.sleep_seconds === null).map(day => day.date),
};

export function sampleFiles() {
  const files = new Map(SAMPLE_DAYS.map(day => [`daily/${day.date}.csv`, Buffer.from(csv(rowsForDay(day)))]));
  files.set('combined.csv', Buffer.from(csv(RAW_ROWS)));
  files.set('sample-summary.json', Buffer.from(`${JSON.stringify(SAMPLE_SUMMARY, null, 2)}\n`));
  files.set('README.txt', Buffer.from(`Health.md spreadsheet sample\n\nAll values are fictional. September 28 to October 25, 2026.\nThis is an illustrative two-metric CSV subset, not a complete Health.md export or a schema fixture. No device or personal records were used.\n\nFiles\n- ${WORKBOOK_NAME}: editable Excel workbook with native steps and sleep charts.\n- combined.csv: all 28 dates, one header, ${RAW_ROWS.length} measurement rows.\n- daily/: 28 daily CSV files for practicing import or combination.\n- sample-summary.json: independently calculated totals and coverage.\n\nUnits and dates\nSteps use count. Sleep durations use seconds in the CSVs and hours in the workbook (seconds / 3600). Dates are journal dates, not measurement timestamps; Timestamp is empty for daily summaries. Sleep journal dates use local noon to the following noon. A Tuesday 01:00 bedtime can belong to Monday's summary.\n\nMissing data\nSleep on 2026-10-08 is deliberately absent. There are 28 step days and 27 sleep days. No missing value is filled with zero. The sleep chart uses an intentional #N/A helper for that gap; this is not an export failure. Averages use recorded days only.\n\nUse the workbook\nOpen ${WORKBOOK_NAME} in Excel. Overview has two editable charts and formula-linked totals. Daily metrics calculates daily values from Raw data. Raw data preserves the six CSV columns; its separate Checked value column validates numeric inputs. Edit an existing numeric Value to try recalculation. This sample has fixed 28-day dates and bounded input ranges; adding more rows does not extend it automatically. Keep your own data separate and follow the guides to build your own workbook. The workbook has no macros or external data connections. It is a downloadable sample, not an XLSX export feature in the app.\n\nGoogle Sheets\nImport combined.csv into a new spreadsheet, choose Comma, and follow the existing Sheets guide to filter Category, Metric and Unit before charting. This uploads the sample to Google. This pack does not create a shared Google Sheet, and native Excel chart conversion in Sheets has not been verified.\n\nGuides\nhttps://healthmd.app/blog/apple-health-to-excel/\nhttps://healthmd.app/blog/apple-health-to-google-sheets/\nhttps://healthmd.app/apple-health-to-csv/#combine-csv-files\n\nSource of the authored fiction\nhttps://healthmd.app/blog/export-apple-health-data-to-obsidian/#starter-vault\n\nNo medical conclusions, targets or recommendations are implied.\n`));
  return files;
}

export async function buildSpreadsheetSamples({ check = false } = {}) {
  const files = sampleFiles();
  const workbook = await fs.readFile(path.join(SAMPLE_DIR, WORKBOOK_NAME));
  if (workbook.readUInt32LE(0) !== 0x04034b50) throw new Error('Expected an XLSX ZIP workbook');
  const archived = new Map(files);
  archived.set(WORKBOOK_NAME, workbook);
  const outputs = new Map([...files].map(([name, bytes]) => [path.join(SAMPLE_DIR, name), bytes]));
  outputs.set(ARCHIVE_PATH, zipVault(archived, { rootName: 'Health.md Spreadsheet Sample' }));
  for (const [filename, bytes] of outputs) {
    if (check) {
      const existing = await fs.readFile(filename).catch(() => Buffer.alloc(0));
      if (!existing.equals(bytes)) throw new Error(`Stale spreadsheet sample: ${path.relative(ROOT, filename)}. Run npm run spreadsheet-sample:build.`);
    } else {
      await fs.mkdir(path.dirname(filename), { recursive: true });
      await fs.writeFile(filename, bytes);
    }
  }
  console.log(`${check ? 'Verified' : 'Built'} spreadsheet sample: ${SAMPLE_DAYS.length} fictional days, ${RAW_ROWS.length} metric rows, workbook and CSV pack.`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await buildSpreadsheetSamples({ check: process.argv.includes('--check') });
}
