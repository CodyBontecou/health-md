#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

const API = 'https://www.googleapis.com/webmasters/v3/sites';
const DAY = 86400000;
const ROW_LIMIT = 25000;
const MAX_PAGES = 2;
const DATASETS = {
  totals: [], page: ['page'], query: ['query'], country: ['country'],
  device: ['device'], pageQuery: ['page', 'query'],
};

function dateValue(value) {
  const date = new Date(`${value}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(+date)
      || date.toISOString().slice(0, 10) !== value) {
    throw new Error('Use a valid YYYY-MM-DD end date from finalized Search Console data.');
  }
  return +date;
}

export function comparisonWindows(endDate) {
  const end = dateValue(endDate);
  const iso = (value) => new Date(value).toISOString().slice(0, 10);
  return [28, 90].flatMap((days) => [0, 1].map((previous) => ({
    id: `${previous ? 'previous' : 'current'}${days}`,
    days,
    startDate: iso(end - (days * (previous + 1) - 1) * DAY),
    endDate: iso(end - days * previous * DAY),
  })));
}

export function searchConsoleClient(token, fetchImpl = fetch) {
  if (!token?.trim() || /\s/.test(token)) throw new Error('Set GSC_ACCESS_TOKEN to an OAuth access token.');
  return async (suffix = '', body) => {
    let response;
    try {
      response = await fetchImpl(`${API}${suffix}`, {
        method: body ? 'POST' : 'GET',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        ...(body ? { body: JSON.stringify(body) } : {}),
        signal: AbortSignal.timeout(30000),
        redirect: 'error',
      });
    } catch {
      throw new Error('Search Console request failed or timed out; no snapshot was saved.');
    }
    // Do not echo response bodies, request headers or tokens into logs.
    if (!response.ok) throw new Error(`Search Console returned HTTP ${response.status}; check access, scope and quota.`);
    try { return await response.json(); }
    catch { throw new Error('Search Console returned invalid JSON.'); }
  };
}

export async function queryRows(request, property, window, dimensions) {
  const rows = [];
  let responseAggregationType;
  const body = {
    startDate: window.startDate, endDate: window.endDate, dimensions,
    type: 'web', dataState: 'final',
    aggregationType: dimensions.includes('page') ? 'auto' : 'byProperty',
    rowLimit: ROW_LIMIT,
  };
  for (let page = 0; page <= MAX_PAGES; page++) {
    const response = await request(`/${encodeURIComponent(property)}/searchAnalytics/query`, {
      ...body, startRow: page * ROW_LIMIT,
    });
    const batch = response.rows ?? [];
    if (!Array.isArray(batch)) throw new Error('Search Console rows must be an array.');
    if (responseAggregationType && response.responseAggregationType !== responseAggregationType) {
      throw new Error('Search Console aggregation changed during pagination.');
    }
    responseAggregationType = response.responseAggregationType;
    if (page === MAX_PAGES) return { dimensions, responseAggregationType, rows, truncated: batch.length > 0 };
    rows.push(...batch);
    if (batch.length < ROW_LIMIT) return { dimensions, responseAggregationType, rows, truncated: false };
  }
}

export async function collectBaseline({ property, endDate, request, now = new Date() }) {
  const windows = comparisonWindows(endDate);
  const sites = await request();
  const site = sites.siteEntry?.find((entry) => entry.siteUrl === property
    && ['siteOwner', 'siteFullUser', 'siteRestrictedUser'].includes(entry.permissionLevel));
  if (!site) throw new Error('Property is not in the accessible Search Console site list; use its exact siteUrl.');
  const results = [];
  for (const window of windows) {
    const datasets = {};
    for (const [name, dimensions] of Object.entries(DATASETS)) {
      datasets[name] = await queryRows(request, property, window, dimensions);
    }
    results.push({ ...window, datasets });
  }
  return {
    version: 1, generatedAt: now.toISOString(), property, permissionLevel: site.permissionLevel,
    searchType: 'web', dataState: 'final', dateTimezone: 'America/Los_Angeles',
    limitations: [
      'Only rows exposed by Search Console are saved; pagination does not guarantee all queries or pages.',
      'Each dataset is capped at 50,000 rows per window; truncated indicates more rows were returned by a probe.',
      'Query and page breakdowns can omit data. Do not sum them into property totals or compare their positions with property position.',
      'A missing row or date is unavailable, not a measured zero. Finalized data can still be absent near the end date.',
      'Search clicks and impressions do not measure website visits, store clicks, installs or purchases.',
      'Canonical selection and indexed-page observations require a separate Search Console inspection.',
    ],
    windows: results,
  };
}

const cell = (value) => String(value).replace(/[|\r\n<>]/g, ' ');
const metric = (value, percent = false) => Number.isFinite(value)
  ? (percent ? `${(value * 100).toFixed(2)}%` : value.toFixed(2)) : 'unavailable';

export function renderSummary(snapshot) {
  const lines = ['# Search Console baseline', '',
    `Property: ${cell(snapshot.property)}`, `Generated: ${snapshot.generatedAt}`, '',
    'Web search only. Dates are inclusive Pacific Time dates; comparisons use the immediately preceding equal-length period.', '',
    '| Window | Dates | Clicks | Impressions | Search CTR | Position |',
    '| --- | --- | --- | --- | --- | --- |'];
  for (const window of snapshot.windows) {
    const row = window.datasets.totals.rows[0];
    lines.push(`| ${window.id} | ${window.startDate} – ${window.endDate} | ${metric(row?.clicks)} | ${metric(row?.impressions)} | ${metric(row?.impressions > 0 ? row.clicks / row.impressions : undefined, true)} | ${metric(row?.position)} |`);
  }
  lines.push('', '## Current 28-day landing pages', '',
    'Top returned pages by clicks. Compare a page with the same page in the previous period; absent rows do not establish zero traffic.', '',
    '| Page | Clicks | Impressions | Search CTR | Position |', '| --- | --- | --- | --- | --- |');
  for (const row of snapshot.windows.find((window) => window.id === 'current28').datasets.page.rows.slice(0, 20)) {
    lines.push(`| ${cell(row.keys?.[0] ?? '')} | ${metric(row.clicks)} | ${metric(row.impressions)} | ${metric(row.impressions > 0 ? row.clicks / row.impressions : undefined, true)} | ${metric(row.position)} |`);
  }
  lines.push('', '## Interpretation limits', '', ...snapshot.limitations.map((limit) => `- ${limit}`), '',
    'Review query/page rows in snapshot.json for intent and brand relevance. Brand classification is a human review step; hidden queries remain unknown.', '',
    'Review discovery after 14 days and search/conversion trends after 28 and 56 days. Annotate deployments, campaigns and pricing changes. Do not infer a title defect from low CTR without considering position and intent.', '');
  return lines.join('\n');
}

export async function main(args = process.argv.slice(2), env = process.env) {
  const { values } = parseArgs({ args, options: {
    help: { type: 'boolean' }, 'list-properties': { type: 'boolean' },
    property: { type: 'string' }, 'end-date': { type: 'string' }, output: { type: 'string' },
  } });
  if (values.help) {
    console.log('GSC_ACCESS_TOKEN=<OAuth token> npm run seo:baseline -- --list-properties\n'
      + 'npm run seo:baseline -- --property <exact siteUrl> --end-date YYYY-MM-DD --output <new private directory outside apps/website>\n'
      + 'Use finalized dates and the webmasters.readonly OAuth scope. No live data is fetched without a token.');
    return;
  }
  if (!values['list-properties'] && (!values.property || !values['end-date'] || !values.output)) {
    throw new Error('Provide --property, --end-date and --output, or use --list-properties.');
  }
  if (!values['list-properties']) comparisonWindows(values['end-date']);
  const request = searchConsoleClient(env.GSC_ACCESS_TOKEN);
  if (values['list-properties']) {
    const sites = await request();
    console.log(JSON.stringify(sites.siteEntry ?? [], null, 2));
    return;
  }
  // Existing parent required: resolve symlinks before excluding public build inputs.
  const output = path.join(await fs.realpath(path.dirname(path.resolve(values.output))), path.basename(path.resolve(values.output)));
  const website = await fs.realpath(fileURLToPath(new URL('../', import.meta.url)));
  if (output === website || output.startsWith(`${website}${path.sep}`)) {
    throw new Error('Save the baseline outside apps/website so search queries cannot enter public build assets.');
  }
  try { await fs.access(output); throw new Error('Output directory already exists; choose a new snapshot directory.'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const snapshot = await collectBaseline({ property: values.property, endDate: values['end-date'], request });
  await fs.mkdir(output, { mode: 0o700 });
  await fs.writeFile(path.join(output, 'snapshot.json'), JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  await fs.writeFile(path.join(output, 'summary.md'), renderSummary(snapshot), { flag: 'wx', mode: 0o600 });
  console.log('Saved snapshot.json and summary.md. Live results require review; no website changes were published.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
