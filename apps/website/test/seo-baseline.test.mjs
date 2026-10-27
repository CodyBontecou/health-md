import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { comparisonWindows, queryRows, collectBaseline, renderSummary, searchConsoleClient, main } from '../scripts/seo-baseline.mjs';

test('comparison periods are inclusive, adjacent and equal length across leap days', () => {
  const windows = comparisonWindows('2024-03-01');
  assert.deepEqual(windows[0], { id: 'current28', days: 28, startDate: '2024-02-03', endDate: '2024-03-01' });
  assert.equal(windows[1].endDate, '2024-02-02');
  for (const window of windows) {
    assert.equal((Date.parse(window.endDate) - Date.parse(window.startDate)) / 86400000 + 1, window.days);
  }
  for (const value of ['2025-02-29', '2026-13-01', '10/25/2026', '2026-10-25T00:00:00Z']) {
    assert.throws(() => comparisonWindows(value), /valid YYYY-MM-DD/);
  }
});

test('pagination encodes the exact property, uses finalized web data and reports a local cap', async () => {
  const calls = [];
  const batch = Array.from({ length: 25000 }, () => ({ keys: ['example'], clicks: 1 }));
  const request = async (suffix, body) => {
    calls.push({ suffix, body });
    return { rows: batch, responseAggregationType: 'byPage' };
  };
  const result = await queryRows(request, 'https://healthmd.app/', comparisonWindows('2026-10-20')[0], ['page']);
  assert.equal(result.rows.length, 50000);
  assert.equal(result.truncated, true);
  assert.deepEqual(calls.map(({ body }) => body.startRow), [0, 25000, 50000]);
  assert.equal(calls[0].suffix, '/https%3A%2F%2Fhealthmd.app%2F/searchAnalytics/query');
  assert.equal(calls[0].body.dataState, 'final');
  assert.equal(calls[0].body.type, 'web');
  assert.equal(calls[0].body.aggregationType, 'auto');
});

test('an empty cap probe is not labeled truncated and absent rows remain empty', async () => {
  let calls = 0;
  const result = await queryRows(async () => ({
    rows: ++calls < 3 ? Array(25000).fill({ clicks: 1 }) : [], responseAggregationType: 'byProperty',
  }), 'sc-domain:healthmd.app', comparisonWindows('2026-10-20')[0], ['query']);
  assert.equal(result.truncated, false);
  assert.equal(result.rows.length, 50000);
  const empty = await queryRows(async () => ({}), 'sc-domain:healthmd.app', comparisonWindows('2026-10-20')[0], []);
  assert.deepEqual(empty.rows, []);
  assert.equal(empty.truncated, false);
});

test('the exact accessible property is required before any analytics query', async () => {
  for (const siteEntry of [[], [{ siteUrl: 'https://www.healthmd.app/', permissionLevel: 'siteOwner' }],
    [{ siteUrl: 'sc-domain:healthmd.app', permissionLevel: 'siteUnverifiedUser' }]]) {
    let calls = 0;
    await assert.rejects(collectBaseline({ property: 'sc-domain:healthmd.app', endDate: '2026-10-20',
      request: async () => { calls++; return { siteEntry }; },
    }), /exact siteUrl/);
    assert.equal(calls, 1);
  }
});

test('all four windows keep independent totals and breakdowns; the summary never sums query rows', async () => {
  const calls = [];
  const snapshot = await collectBaseline({ property: 'sc-domain:healthmd.app', endDate: '2026-10-20',
    now: new Date('2026-10-26T12:00:00Z'),
    request: async (suffix, body) => {
      if (!suffix) return { siteEntry: [{ siteUrl: 'sc-domain:healthmd.app', permissionLevel: 'siteRestrictedUser' }] };
      calls.push(body);
      const rows = body.dimensions.length ? [{ keys: ['synthetic|page<script>'], clicks: 999, impressions: 1000, position: 9 }] :
        (body.startDate === '2026-09-23' ? [] : [{ clicks: 2, impressions: 10, position: 4 }]);
      return { rows, responseAggregationType: body.dimensions.includes('page') ? 'byPage' : 'byProperty' };
    },
  });
  assert.equal(calls.length, 24);
  assert.deepEqual(Object.keys(snapshot.windows[0].datasets), ['totals', 'page', 'query', 'country', 'device', 'pageQuery']);
  const summary = renderSummary(snapshot);
  assert.match(summary, /current28.*unavailable/);
  assert.match(summary, /current90.*2.00.*10.00.*20.00%.*4.00/);
  assert.doesNotMatch(summary, /<script>/);
  assert.match(summary, /hidden queries remain unknown/);
  assert.equal(snapshot.generatedAt, '2026-10-26T12:00:00.000Z');
});

test('HTTP and transport errors never echo tokens or provider response bodies', async () => {
  const token = 'synthetic-secret';
  await assert.rejects(searchConsoleClient(token, async (_url, init) => {
    assert.equal(init.headers.Authorization, `Bearer ${token}`);
    assert.equal(init.redirect, 'error');
    return { ok: false, status: 401, json: async () => ({ message: token }) };
  })(), { message: 'Search Console returned HTTP 401; check access, scope and quota.' });
  await assert.rejects(searchConsoleClient(token, async () => { throw new Error(token); })(),
    { message: 'Search Console request failed or timed out; no snapshot was saved.' });
  assert.throws(() => searchConsoleClient(''), /GSC_ACCESS_TOKEN/);
  await assert.rejects(main(['--end-date', '2026-10-20'], {}), /Provide --property/);
});

test('private outputs cannot be saved in public build inputs, including through a parent symlink', async () => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'healthmd-seo-output-'));
  try {
    const website = path.resolve(import.meta.dirname, '..');
    await fs.symlink(path.join(website, 'assets'), path.join(temp, 'public-assets'));
    for (const output of [path.join(website, 'assets', 'private-report'), path.join(temp, 'public-assets', 'private-report')]) {
      await assert.rejects(main(['--property', 'sc-domain:healthmd.app', '--end-date', '2026-10-20', '--output', output],
        { GSC_ACCESS_TOKEN: 'synthetic-token' }), /outside apps\/website/);
      await assert.rejects(fs.access(output), { code: 'ENOENT' });
    }
    await assert.rejects(main(['--property', 'sc-domain:healthmd.app', '--end-date', '2026-10-20', '--output', temp],
      { GSC_ACCESS_TOKEN: 'synthetic-token' }), /already exists/);
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});

test('CLI saves a complete private snapshot without credentials and saves nothing on API failure', async (t) => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'healthmd-seo-cli-'));
  const token = 'synthetic-only-token';
  const args = (output) => ['--property', 'sc-domain:healthmd.app', '--end-date', '2026-10-20', '--output', output];
  let fail = false;
  t.mock.method(globalThis, 'fetch', async (_url, init) => ({
    ok: !fail, status: fail ? 403 : 200,
    json: async () => init.method === 'GET'
      ? { siteEntry: [{ siteUrl: 'sc-domain:healthmd.app', permissionLevel: 'siteOwner' }] }
      : { rows: [{ keys: ['synthetic query'], clicks: 1, impressions: 5, position: 3 }], responseAggregationType: 'byProperty' },
  }));
  t.mock.method(console, 'log', () => {});
  try {
    const output = path.join(temp, 'saved');
    await main(args(output), { GSC_ACCESS_TOKEN: token });
    const json = await fs.readFile(path.join(output, 'snapshot.json'), 'utf8');
    const summary = await fs.readFile(path.join(output, 'summary.md'), 'utf8');
    assert.equal(JSON.parse(json).windows.length, 4);
    assert.doesNotMatch(json + summary, new RegExp(token));
    assert.match(summary, /20.00%/);
    if (process.platform !== 'win32') {
      assert.equal((await fs.stat(output)).mode & 0o777, 0o700);
      assert.equal((await fs.stat(path.join(output, 'snapshot.json'))).mode & 0o777, 0o600);
    }
    fail = true;
    await assert.rejects(main(args(path.join(temp, 'failed')), { GSC_ACCESS_TOKEN: token }), /HTTP 403/);
    await assert.rejects(fs.access(path.join(temp, 'failed')), { code: 'ENOENT' });
  } finally { await fs.rm(temp, { recursive: true, force: true }); }
});
