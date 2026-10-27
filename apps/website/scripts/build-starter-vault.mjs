#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const ARCHIVE_PATH = path.join(ROOT, 'assets/downloads/healthmd-obsidian-starter.zip');
export const VAULT_NAME = 'Health.md Starter';
export const METRICS = [
  { key: 'steps', label: 'Daily steps', unit: 'steps', color: '#166d69', min: 0, max: 16000, ticks: [0, 4000, 8000, 12000, 16000] },
  { key: 'sleep_total_hours', label: 'Sleep duration', unit: 'hours', color: '#6855a5', min: 5, max: 9, ticks: [5, 6, 7, 8, 9] },
  { key: 'resting_heart_rate', label: 'Resting heart rate', unit: 'bpm', color: '#b45b3e', min: 50, max: 70, ticks: [50, 55, 60, 65, 70] },
];

// Authored fiction, deliberately independent of any device or export fixture.
// Null means absent: no property, no plotted point and no contribution to means.
const VALUES = [
  [6420, 7.25, 61], [8150, 7.5, 60], [7230, 6.75, 62], [9100, 7.1, 61],
  [5680, 6.4, 63], [12340, 8.2, 59], [7840, 7.8, 60],
  [7540, 7.4, 60], [8920, 7.6, 59], [6300, 6.9, 62], [9850, null, 60],
  [7020, 7.3, 61], [14200, 8.1, 58], [8640, 7.9, 59],
  [8120, 7.5, 60], [9340, 7.7, 59], [6890, 6.6, 62], [10120, 7.2, null],
  [7450, 7.4, 60], [13180, 8.3, 58], [8720, 7.8, 59],
  [8450, 7.6, 59], [9630, 7.8, 58], [7210, 6.9, 61], [10480, 7.4, 59],
  [7820, 7.5, 60], [13840, 8.2, 57], [9150, 8.0, 58],
];
const REFLECTIONS = [
  'A short walk before work. Kept the evening quiet.',
  'Walked to run an errand instead of driving.',
  'A late evening; wrote a reminder to leave more time tomorrow.',
  'Took a longer lunch break outside.',
  'Mostly a desk day. A brief walk after dinner.',
  'A long, easy outing with a friend.',
  'A slower day with time for a weekly review.',
];
export const DAYS = VALUES.map((values, index) => {
  const date = new Date(Date.UTC(2026, 8, 28 + index)).toISOString().slice(0, 10);
  return { date, ...Object.fromEntries(METRICS.flatMap((metric, j) => values[j] === null ? [] : [[metric.key, values[j]]])) };
});

export function summarize(days, key) {
  const values = days.map(day => day[key]).filter(value => typeof value === 'number');
  const sum = values.reduce((total, value) => total + value, 0);
  return { count: values.length, sum, average: values.length ? sum / values.length : null };
}
const number = value => value.toLocaleString('en-US', { maximumFractionDigits: 0 });
const decimal = value => value.toFixed(2);
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const tableValue = (day, key) => day[key] === undefined ? '—' : key === 'steps' ? number(day[key]) : key === 'sleep_total_hours' ? decimal(day[key]) : String(day[key]);

function dayNote(day, index) {
  const values = METRICS.flatMap(metric => day[metric.key] === undefined ? [] : [`${metric.key}: ${day[metric.key]}`]);
  const rows = METRICS.map(metric => `| ${metric.label} | ${tableValue(day, metric.key)} | ${metric.unit} |`).join('\n');
  const missing = METRICS.filter(metric => day[metric.key] === undefined).map(metric => `${metric.label}: not recorded in this fictional example.`).join(' ');
  return `---\ndate: ${day.date}\ntype: health-data\nsample_data: true\ntags:\n  - health/sample\n${values.join('\n')}\n---\n\n# ${day.date}\n\n[[Health Dashboard|Dashboard]] · [[Start here]]\n\n> [!note] Fictional sample\n> Made-up values and journal context. This is an illustrative note, not a complete Health.md export.\n\n| Measurement | Value | Unit |\n| --- | ---: | --- |\n${rows}\n\nSleep belongs to the night beginning on this date. A dash means absent, not zero.\n${missing ? `\n> [!info] Missing measurement\n> ${missing}\n` : ''}\n## A little context\n\n${REFLECTIONS[index % 7]}\n\n## For the weekly review\n\nWhat would I like to remember about this day?\n`;
}

export function chartSvg(metric) {
  const { key, label, unit, color, min, max, ticks } = metric;
  const observed = summarize(DAYS, key);
  const x = index => 70 + index * (840 / 27);
  const y = value => 238 - ((value - min) / (max - min)) * 130;
  const totalLabel = key === 'steps' ? `${number(observed.sum)} total steps` : `${decimal(observed.average)} ${unit} average`;
  const grid = ticks.map(value => `<path d="M70 ${y(value)}H910" stroke="#deded5"/><text x="56" y="${y(value) + 4}" text-anchor="end" fill="#555e5c" font-size="12">${number(value)}</text>`).join('');
  const marks = DAYS.map((day, i) => {
    if (day[key] === undefined) return `<text x="${x(i)}" y="259" text-anchor="middle" fill="#6c7270" font-size="12">×</text>`;
    const tooltip = `${day.date}: ${day[key]} ${unit}`;
    if (key === 'steps') return `<rect x="${x(i) - 9}" y="${y(day[key])}" width="18" height="${238 - y(day[key])}" rx="2" fill="${color}"><title>${tooltip}</title></rect>`;
    return `${i && DAYS[i - 1][key] !== undefined ? `<path d="M${x(i - 1)} ${y(DAYS[i - 1][key])}L${x(i)} ${y(day[key])}" fill="none" stroke="${color}" stroke-width="2.5"/>` : ''}<circle cx="${x(i)}" cy="${y(day[key])}" r="3.4" fill="${color}"><title>${tooltip}</title></circle>`;
  }).join('');
  const labels = [0, 7, 14, 21, 27].map(index => `<text x="${x(index)}" y="282" text-anchor="${index === 27 ? 'end' : index === 0 ? 'start' : 'middle'}" fill="#555e5c" font-size="12">${DAYS[index].date.slice(5).replace('-', '/')}</text>`).join('');
  const missing = DAYS.filter(day => day[key] === undefined).map(day => day.date).join(', ');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="960" height="330" viewBox="0 0 960 330" role="img" aria-labelledby="title desc"><title id="title">${escape(label)} — fictional sample</title><desc id="desc">${escape(`September 28 to October 25, 2026. ${totalLabel}. ${observed.count} of 28 days observed. ${missing ? `Missing: ${missing}; the line breaks at missing data.` : 'No missing days.'} Fixed snapshot; exact values are in the dashboard table.`)}</desc><rect width="960" height="330" rx="12" fill="#fafaf5"/><g font-family="system-ui, -apple-system, sans-serif"><text x="36" y="34" fill="#5d6865" font-size="11" letter-spacing="1.6">HEALTH.MD / FICTIONAL SAMPLE</text><text x="36" y="66" fill="#192e2b" font-size="25" font-weight="600">${escape(label)}</text><text x="910" y="35" text-anchor="end" fill="${color}" font-size="15" font-weight="600">${escape(totalLabel)}</text><text x="910" y="58" text-anchor="end" fill="#5d6865" font-size="12">${observed.count}/28 days · ${unit}</text>${grid}${marks}${labels}<text x="36" y="312" fill="#5d6865" font-size="12">${escape(missing ? `Missing: ${missing} (×) · Fixed sample snapshot` : 'All 28 days observed · Fixed sample snapshot')}</text><text x="910" y="312" text-anchor="end" fill="#5d6865" font-size="12">${key === 'steps' ? 'Zero baseline' : `Vertical scale: ${min}–${max} ${unit}`}</text></g></svg>\n`;
}

function dashboard() {
  const steps = summarize(DAYS, 'steps');
  const sleep = summarize(DAYS, 'sleep_total_hours');
  const heart = summarize(DAYS, 'resting_heart_rate');
  const metrics = METRICS.map(metric => `## ${metric.label}\n\n![[Attachments/${metric.key}.svg]]\n`).join('\n');
  const rows = DAYS.map(day => `| [[Health/${day.date}\\|${day.date}]] | ${METRICS.map(metric => tableValue(day, metric.key)).join(' | ')} |`).join('\n');
  return `# Four weeks, a little more context\n\n[[Start here]] · [[Reviews/2026-10-19 Weekly review|Read a weekly review]] · [[Guides/Use your own data|Use your own data]]\n\n> [!note] Fictional sample · September 28 – October 25, 2026\n> These are made-up measurements, not goals. The three charts below are **fixed snapshots** of the sample; they do not change when you edit notes. For updating charts, see [[Guides/Optional interactive charts]].\n\n| Across four weeks | Value | Observed days |\n| --- | ---: | ---: |\n| Total steps | ${number(steps.sum)} | ${steps.count}/28 |\n| Average sleep | ${decimal(sleep.average)} hours | ${sleep.count}/28 |\n| Average resting heart rate | ${decimal(heart.average)} bpm | ${heart.count}/28 |\n\nEach average includes only the days with that measurement. October 8 has no sleep value; October 15 has no resting-heart-rate value.\n\n${metrics}\nSleep refers to the night beginning on the note's date. Lines break where values are missing. Narrow vertical scales on line charts show variation, not a health score.\n\n## Explore the notes\n\nThis live table uses Obsidian's core **Bases** plugin. It reads the daily notes and updates if you edit them. Enable Bases in Settings if needed.\n\n![[Views/Health log.base#All days]]\n\n## All sample values\n\nThis fixed table is also available without Bases. Open a date to read its fictional journal context. A dash means missing.\n\n| Date | Steps | Sleep (hours) | Resting HR (bpm) |\n| --- | ---: | ---: | ---: |\n${rows}\n\n## Turn numbers into a review\n\nRead the [[Reviews/2026-10-19 Weekly review|completed review]], then use [[Templates/Weekly review|the weekly template]] for your own dates. Ask what changed in daily life before interpreting a chart.\n`;
}

function weeklyReview() {
  const current = DAYS.slice(21), previous = DAYS.slice(14, 21);
  const rows = METRICS.map(({ key, label, unit }) => {
    const now = summarize(current, key), before = summarize(previous, key);
    const value = summary => key === 'steps' ? number(summary.sum) : decimal(summary.average);
    return `| ${key === 'steps' ? 'Total steps' : `Average ${label.toLowerCase()}`} (${unit}) | ${value(now)} | ${value(before)} | ${now.count}/7 · ${before.count}/7 |`;
  }).join('\n');
  return `---\ntype: weekly-review\nweek_start: 2026-10-19\nweek_end: 2026-10-25\nsample_data: true\ntags:\n  - health/review\n  - health/sample\n---\n\n# A week with more room to walk\n\nOctober 19–25, 2026 · [[Health Dashboard|Dashboard]] · [[Templates/Weekly review|Use this structure next week]]\n\n> [!note] A fictional example, already filled in\n> All measurements and reflections are made up. The summary below was calculated from the sample notes when the starter was built; the prose and summary table do not update automatically.\n\n## 1. Check coverage\n\nThis week has seven observations for each metric. The previous week is October 12–18 and has only six resting-heart-rate observations: [[Health/2026-10-15|October 15]] is missing. No value was filled in for that day.\n\n| Metric | This week | Previous week | Observed days: this · previous |\n| --- | ---: | ---: | --- |\n${rows}\n\nAverage sleep and resting heart rate are unweighted means of the observed daily summaries, not pooled raw-sample calculations. The differing resting-heart-rate coverage makes that comparison less complete.\n\n### Look at this week's source notes\n\n![[Views/Health log.base#Review week]]\n\nIf Bases is disabled, open [[Health/2026-10-19]], [[Health/2026-10-20]], [[Health/2026-10-21]], [[Health/2026-10-22]], [[Health/2026-10-23]], [[Health/2026-10-24]], and [[Health/2026-10-25]] directly.\n\n## 2. Add the context\n\nThe lunch walks and Saturday outing gave this week a rhythm I enjoyed. Wednesday was still a later evening. I want the journal to help me remember those details rather than label the whole week good or bad from three averages.\n\nThe changes between weeks are descriptive. This little sample cannot tell me that walking caused a change in sleep or heart rate.\n\n## 3. Choose one small action\n\n- [ ] Put two lunch walks on next week's calendar.\n\nAt the next review, check whether I actually took them and whether the routine felt sustainable. The step total is context, not the only measure of success.\n\n## 4. Leave a note for next time\n\nKeep noting late evenings and device gaps on the day they happen. Review the coverage counts before comparing another week.\n`;
}

async function sourceFiles(directory, prefix = '') {
  const result = new Map();
  for (const entry of (await fs.readdir(directory, { withFileTypes: true })).sort((a, b) => a.name < b.name ? -1 : 1)) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) for (const [name, content] of await sourceFiles(path.join(directory, entry.name), relative)) result.set(name, content);
    else if (entry.isFile()) result.set(relative, await fs.readFile(path.join(directory, entry.name)));
    else throw new Error(`Unsupported starter source: ${relative}`);
  }
  return result;
}

export async function vaultFiles() {
  const files = await sourceFiles(path.join(ROOT, 'starter-vault/vault'));
  const add = (name, text) => {
    if (files.has(name)) throw new Error(`Duplicate vault path: ${name}`);
    files.set(name, Buffer.from(text));
  };
  DAYS.forEach((day, index) => add(`Health/${day.date}.md`, dayNote(day, index)));
  METRICS.forEach(metric => add(`Attachments/${metric.key}.svg`, chartSvg(metric)));
  add('Health Dashboard.md', dashboard());
  add('Reviews/2026-10-19 Weekly review.md', weeklyReview());
  return files;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// ZIP32, stored entries. No executable payloads, absolute paths, symlinks or
// platform-specific archiver dependencies. Fixed date: 2026-10-26 00:00.
export function zipVault(files) {
  const localParts = [], centralParts = [];
  let offset = 0;
  const date = ((2026 - 1980) << 9) | (10 << 5) | 26;
  for (const [relative, bytes] of [...files].sort(([a], [b]) => a < b ? -1 : 1)) {
    if (relative.startsWith('/') || relative.split('/').some(part => !part || part === '..') || relative.includes('\\')) throw new Error(`Unsafe archive path: ${relative}`);
    const name = Buffer.from(`${VAULT_NAME}/${relative}`);
    const checksum = crc32(bytes);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6); local.writeUInt16LE(date, 12);
    local.writeUInt32LE(checksum, 14); local.writeUInt32LE(bytes.length, 18); local.writeUInt32LE(bytes.length, 22);
    local.writeUInt16LE(name.length, 26);
    localParts.push(local, name, bytes);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(0x0314, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x800, 8); central.writeUInt16LE(date, 14); central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(bytes.length, 20); central.writeUInt32LE(bytes.length, 24); central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(0o100644 * 65536, 38); central.writeUInt32LE(offset, 42);
    centralParts.push(central, name);
    offset += local.length + name.length + bytes.length;
  }
  const central = Buffer.concat(centralParts), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.size, 8); end.writeUInt16LE(files.size, 10);
  end.writeUInt32LE(central.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...localParts, central, end]);
}

export async function buildStarterVault({ check = false } = {}) {
  const files = await vaultFiles();
  const outputs = new Map([[ARCHIVE_PATH, zipVault(files)]]);
  // A stable, shareable preview asset from the same dataset, outside the ZIP.
  outputs.set(path.join(ROOT, 'assets/downloads/healthmd-starter-preview.svg'), files.get('Attachments/steps.svg'));
  for (const [filename, bytes] of outputs) {
    if (check) {
      const existing = await fs.readFile(filename).catch(() => Buffer.alloc(0));
      if (!existing.equals(bytes)) throw new Error(`Stale starter download: ${path.relative(ROOT, filename)}. Run npm run starter-vault:build.`);
    } else {
      await fs.mkdir(path.dirname(filename), { recursive: true });
      await fs.writeFile(filename, bytes);
    }
  }
  console.log(`${check ? 'Verified' : 'Built'} Obsidian starter: ${files.size} files, ${DAYS.length} fictional days, ${outputs.get(ARCHIVE_PATH).length} bytes.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await buildStarterVault({ check: process.argv.includes('--check') });
}
