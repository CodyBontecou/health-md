import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PRODUCER = path.resolve(ROOT, '../apple/docs/reference/generated/core');
const readPost = (slug) => readFile(path.join(ROOT, 'content/blog', `${slug}.md`), 'utf8');
const claude = await readPost('analyze-apple-health-with-claude');
const sheets = await readPost('apple-health-to-google-sheets');
const summaryCSV = await readFile(path.join(PRODUCER, 'summary-day.csv'), 'utf8');
const losslessCSV = await readFile(path.join(PRODUCER, 'lossless-day.csv'), 'utf8');
const dailyJSON = JSON.parse(await readFile(path.join(PRODUCER, 'summary-day.json'), 'utf8'));
const csvHeader = summaryCSV.split('\n')[0];
const ledger = await readFile(path.join(ROOT, 'content/blog/_review/apple-health-to-google-sheets.md'), 'utf8');
const registry = await readFile(path.join(ROOT, 'content/blog/_review/verified-snippets.md'), 'utf8');

function step(post, number) {
  const section = post.match(new RegExp(`^## Step ${number}:.*\\n([\\s\\S]*?)(?=^## |$(?![\\s\\S]))`, 'm'));
  assert.ok(section, `Step ${number} exists`);
  return section[1];
}

test('Claude file-upload instructions distinguish CSV columns from nested daily JSON', () => {
  const exportStep = step(claude, 1);
  const paragraphs = exportStep.split(/\n\s*\n/);
  const jsonDescription = paragraphs.find((paragraph) => /JSON.*nested/i.test(paragraph));
  assert.ok(jsonDescription, 'JSON is described separately as a nested object');
  assert.ok(
    paragraphs.some((paragraph) => /CSV/.test(paragraph) && paragraph.includes(`\`${csvHeader}\``)),
    'the producer header is described specifically as CSV',
  );
  for (const key of ['date', 'schema', 'schema_version', 'activity', 'heart', 'sleep']) {
    assert.ok(Object.hasOwn(dailyJSON, key), `producer JSON includes ${key}`);
    assert.ok(jsonDescription.includes(`\`${key}\``), `JSON guidance names the actual ${key} field`);
  }
  for (const section of ['activity', 'heart', 'sleep']) {
    assert.equal(typeof dailyJSON[section], 'object', `${section} is nested, not a CSV column`);
  }
});

test('Sheets explains mixed-type Value cells and coerces only a selected numeric metric', () => {
  // These simple fixture rows need no CSV parsing; lossless JSON cells remain quoted intact.
  assert.match(summaryCSV, /,Metadata,schema,healthmd\.health_data,,/);
  assert.match(summaryCSV, /,Metadata,time_context\.calendar_timezone,UTC,,/);
  assert.match(summaryCSV, /,Raw HealthKit,Raw Capture Status,not_requested,status,/);
  assert.match(summaryCSV, /,Sleep,Bedtime,\d\d:\d\d,time/);
  assert.match(summaryCSV, /,VO2 Max Carried Forward,true,boolean,/);
  assert.match(summaryCSV, /,VO2 Max Source UUID,[0-9a-f-]+,uuid,/);
  assert.match(losslessCSV, /,Raw HealthKit,Raw HealthKit Record,"\{/);

  assert.match(step(sheets, 1), /`Value`[^\n]*mixed[ -]type/i);
  assert.doesNotMatch(sheets, /`Value` column is numeric|without a cleanup pass|values chart as numbers/i);
  const analysis = step(sheets, 3);
  for (const token of ['`Category`', '`Activity`', '`Metric`', '`Steps`', '`Unit`', '`count`']) {
    assert.ok(analysis.includes(token), `numeric analysis filters the actual CSV ${token}`);
  }
  assert.match(summaryCSV, /,Activity,Steps,\d+,count(?:\n|$)/);
  assert.match(analysis, /VALUE\(D2\)/, 'text numbers get explicit numeric coercion after filtering');
  assert.match(analysis, /(?:don't|do not|never)[^\n]*(?:fail|missing)[^\n]*zero/i, 'failed coercion is not silently treated as zero');
  assert.ok(analysis.includes('`=A2-WEEKDAY(A2,2)+1`'), 'weekly grouping uses an explicit Monday-start date');
  assert.match(analysis, /`Sleep`[\s\S]*`Total Duration`[\s\S]*`seconds`/);
  assert.match(summaryCSV, /,Sleep,Total Duration,[\d.]+,seconds(?:\n|$)/);
});

test('Sheets combines every daily CSV into one raw table before the weekly pivot', () => {
  const importing = step(sheets, 2);
  assert.match(importing, /(?:append|copy)[\s\S]*(?:remaining|each|every|all)[\s\S]*daily/i);
  assert.match(importing, /(?:one|single)[\s\S]*(?:raw[ -]data|Raw data)[\s\S]*(?:table|tab)/i);
  assert.match(importing, /(?:one|single)[\s\S]*header/i);
  assert.match(importing, /(?:skip|remove|excluding|without)[\s\S]*header/i);
  assert.match(importing, /(?:all|every|each)[\s\S]*date/i, 'check that every exported date reached the source table');
  assert.doesNotMatch(sheets, /Import each into its own tab/i, 'separate tabs are not an alternative pivot source');
  assert.match(step(sheets, 3), /(?:range|table)[\s\S]*AVERAGE/i);
});

test('CSV verification evidence uses producer fixtures and does not repeat the numeric-column claim', () => {
  const csvSnippet = registry.split('## CSV export header contract\n')[1]?.split(/^## /m)[0];
  assert.ok(csvSnippet, 'the reusable CSV contract entry exists');
  for (const evidence of [ledger, csvSnippet]) {
    assert.doesNotMatch(evidence, /`Value`(?: column is| is)? numeric/i);
    assert.match(evidence, /mixed[ -]type/i);
    assert.ok(evidence.includes('summary-day.csv'), 'evidence traces to the actual producer CSV fixture');
    assert.ok(evidence.includes('CSVExporter.swift'), 'evidence traces to the production row writer');
  }
});
