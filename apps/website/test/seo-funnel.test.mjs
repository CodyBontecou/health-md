import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { DatabaseSync } from 'node:sqlite';
import { validFunnelEvent, funnelPage } from '../assets/funnel-contract.js';
import { startFunnel, funnelSource, funnelLink } from '../assets/seo-funnel.js';
import { handleWebFunnel } from '../cloudflare/attribution-worker/src/web-funnel.js';
import worker from '../cloudflare/attribution-worker/src/worker.js';
import { funnelReportSQL, reportOptions } from '../scripts/seo-funnel-report.mjs';

const event = { v: 1, page: 'csv', locale: 'en', source: 'search_referral', action: 'csv_sample_download', target: 'summary_csv', placement: 'hero' };
const now = new Date('2026-10-26T12:00:00Z');
const gateScript = await fs.readFile(new URL('../assets/analytics.js', import.meta.url), 'utf8');

function browser(path = '/apple-health-to-csv/', options = {}) {
  const listeners = {}, sent = [];
  const document = { referrer: 'https://www.google.com/search?q=private-search',
    addEventListener(type, callback) { listeners[type] = callback; }, querySelector: () => null };
  const win = { document, navigator: {}, location: new URL('https://healthmd.app' + path),
    fetch(url, settings) { sent.push({ url, settings, data: JSON.parse(settings.body) }); return Promise.resolve({ ok: true }); },
    ...options };
  return { win, listeners, sent };
}
function anchor(href, region = '') {
  const a = { href, matches: () => false, closest(selector) { return selector.split(', ').includes(region) ? a : null; } };
  return { closest(selector) { return selector === 'a[href]' ? a : null; } };
}
function click(target, options = {}) { return { type: 'click', isTrusted: true, button: 0, target, ...options }; }

test('browser emits only bounded actions and never changes navigation or sends URLs/referrers', () => {
  const b = browser('/apple-health-to-csv/?patient=private-value#secret');
  startFunnel(b.win);
  const target = anchor('https://healthmd.app/docs/reference/generated/core/summary-day.csv?token=secret', '.about-hero');
  b.listeners.click(click(target));
  b.listeners.click(click(anchor('https://apps.apple.com/us/app/health-md/id6757763969?pt=secret'), { button: 0 }));
  assert.equal(b.sent.length, 3);
  assert.equal(b.sent[0].data.action, 'page_view');
  assert.deepEqual(b.sent[1].data, event);
  assert.equal(b.sent[2].data.target, 'app_store');
  for (const request of b.sent) {
    assert.equal(request.url, '/v1/web-events');
    assert.equal(request.settings.keepalive, true);
    assert.equal(request.settings.credentials, 'omit');
    assert.equal(request.settings.mode, 'cors', 'preserve Origin with the no-referrer policy');
    assert.equal(request.settings.referrerPolicy, 'no-referrer');
    assert.doesNotMatch(request.settings.body, /private|secret|patient|https:|google\.com/);
    assert.equal(validFunnelEvent(request.data), true);
  }
  startFunnel(b.win);
  assert.equal(b.sent.length, 3, 'initialization is idempotent');
});

test('all repeated starter links, nested clicks, keyboard clicks and middle clicks share the same action', () => {
  const b = browser('/blog/export-apple-health-data-to-obsidian/');
  startFunnel(b.win);
  const target = anchor('https://healthmd.app/assets/downloads/healthmd-obsidian-starter.zip');
  b.listeners.click(click(target, { detail: 0 }));
  b.listeners.auxclick(click(target, { type: 'auxclick', button: 1 }));
  assert.deepEqual(b.sent.slice(1).map(x => x.data.action), ['starter_vault_download', 'starter_vault_download']);
  const before = b.sent.length;
  for (const options of [{ isTrusted: false }, { defaultPrevented: true }, { button: 2 }]) b.listeners.click(click(target, options));
  b.listeners.click(click(anchor('https://example.com/personal.csv')));
  assert.equal(b.sent.length, before);
});

test('production host, known pages, DNT/GPC and local page-send limits are enforced', () => {
  for (const options of [{ location: new URL('http://localhost:8765/apple-health-to-csv/') }, { navigator: { doNotTrack: '1' } }, { navigator: { globalPrivacyControl: true } }]) {
    const b = browser(undefined, options); startFunnel(b.win); assert.equal(b.sent.length, 0);
  }
  const unknown = browser('/docs/anything-private/'); startFunnel(unknown.win); assert.equal(unknown.sent.length, 0);
  const b = browser(); startFunnel(b.win);
  for (let i = 0; i < 110; i++) b.listeners.click(click(anchor('https://apps.apple.com/app/id6757763969')));
  assert.equal(b.sent.length, 100);
});

test('network failures do not throw or retry', () => {
  for (const fetch of [() => { throw new Error('offline'); }, () => Promise.reject(new Error('offline'))]) {
    const b = browser(undefined, { fetch });
    assert.doesNotThrow(() => startFunnel(b.win));
    assert.doesNotThrow(() => b.listeners.click(click(anchor('https://apps.apple.com/app/id6757763969'))));
  }
});

test('homepage multi-format downloads count the selected CSV once even when the visible href is Markdown', () => {
  const b = browser('/');
  let csvSelected = true;
  b.win.document.querySelector = selector => selector === '[data-export-format="csv"][aria-pressed="true"]' && csvSelected ? {} : null;
  const download = { href: 'https://healthmd.app/assets/samples/health-data-sample.md', matches: selector => selector === '[data-sample-download]', closest: () => null };
  const target = { closest: () => download };
  startFunnel(b.win);
  b.listeners.click(click(target, { defaultPrevented: true }));
  b.listeners.click(click(anchor('https://healthmd.app/assets/samples/health-data-sample.csv'), { isTrusted: false }));
  assert.equal(b.sent.length, 2, 'view plus one CSV action, without counting generated links');
  assert.equal(b.sent[1].data.target, 'homepage_csv');
  csvSelected = false;
  b.listeners.click(click(target, { defaultPrevented: true }));
  assert.equal(b.sent.length, 2, 'no selected CSV means no CSV action');
});

test('page/locale and destination/source classifiers have closed vocabularies', () => {
  assert.deepEqual(funnelPage('/blog/health-md-vs-health-auto-export/'), { page: 'auto_export_comparison', locale: 'en' });
  assert.deepEqual(funnelPage('/es/'), { page: 'home', locale: 'es' });
  assert.equal(funnelPage('/es/apple-health-to-csv/'), null);
  assert.equal(funnelPage('/unknown/'), null);
  assert.equal(funnelSource('https://healthmd.app/?utm_campaign=private', 'https://google.com'), 'campaign');
  assert.equal(funnelSource('https://healthmd.app/', 'https://google.com.evil.example'), 'other_referral');
  assert.equal(funnelSource('https://healthmd.app/', 'https://www.healthmd.app/anything'), 'internal');
  assert.equal(funnelSource('https://healthmd.app/', ''), 'direct');
  assert.equal(funnelLink('https://play.google.com/store/apps/details?id=com.healthmd.android', 'https://healthmd.app').target, 'google_play');
  assert.equal(funnelLink('https://f-droid.org/packages/com.healthmd.android/', 'https://healthmd.app').target, 'f_droid');
  assert.equal(funnelLink('https://apps.apple.com/app/id123', 'https://healthmd.app'), null);
  assert.equal(funnelLink('https://evil.example/assets/samples/health-data-sample.csv', 'https://healthmd.app'), null);
});

test('the existing analytics gate must explicitly allow both beacon and funnel; failures stay closed', async () => {
  for (const value of [true, false, 'true', null, 'failure']) {
    const scripts = [];
    const context = { window: { location: { hostname: 'healthmd.app' }, navigator: {} },
      document: { querySelector: () => null, createElement: () => ({ setAttribute() {} }), head: { appendChild(script) { scripts.push(script); } } },
      fetch: () => value === 'failure' ? Promise.reject(new Error('offline')) : Promise.resolve({ ok: true, json: async () => ({ track: value }) }),
    };
    vm.runInNewContext(gateScript, context);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(scripts.length, value === true ? 2 : 0);
    if (value === true) assert.ok(scripts.some(s => s.type === 'module' && s.src === '/assets/seo-funnel.js'));
  }
});

class D1 {
  constructor(sql) { this.db = new DatabaseSync(':memory:'); this.db.exec(sql); }
  prepare(sql) {
    const stmt = this.db.prepare(sql);
    let values = [];
    const wrapper = { bind(...args) { values = args; return wrapper; },
      async first() { return stmt.get(...values) || null; },
      async run() { return { meta: stmt.run(...values) }; } };
    return wrapper;
  }
  async batch(statements) { return Promise.all(statements.map(s => s.run())); }
}
const migrations = await Promise.all(['0001_campaign_clicks.sql', '0002_campaign_installs.sql', '0003_web_funnel.sql'].map(name => fs.readFile(new URL('../cloudflare/attribution-worker/migrations/' + name, import.meta.url), 'utf8')));
function database(t) { const d = new D1(migrations.join('\n')); t.after(() => d.db.close()); return d; }
function request(payload = event, overrides = {}) {
  return new Request('https://healthmd.app/v1/web-events', { method: 'POST',
    headers: { origin: 'https://healthmd.app', 'content-type': 'application/json' }, body: JSON.stringify(payload), ...overrides });
}

test('collector routes events to real SQLite daily counters without storing request metadata', async t => {
  const DB = database(t);
  assert.equal((await worker.fetch(request(), { DB }, {})).status, 204);
  assert.equal((await handleWebFunnel(request(), { DB })).status, 204);
  const rows = DB.db.prepare('SELECT * FROM web_funnel_daily').all();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].count, 2);
  assert.deepEqual(Object.keys(rows[0]), ['day', 'page', 'locale', 'source', 'action', 'target', 'placement', 'count']);
});

test('collector rejects origins, methods, queries, oversized bodies and sensitive/unknown fields', async t => {
  const DB = database(t);
  for (const body of [{ ...event, email: 'private@example.com' }, { ...event, page: '/private/path' }, { ...event, page: { toString: null, valueOf: null } }, { ...event, action: { toString: null, valueOf: null } }, { ...event, locale: 'es' }, { ...event, target: 'private-file' }, { ...event, action: 'page_view' }, { ...event, source: 'https://google.com?q=private' }, null, []]) {
    assert.equal((await handleWebFunnel(request(body), { DB })).status, 400);
  }
  assert.equal((await handleWebFunnel(request(event, { headers: { origin: 'https://evil.example', 'content-type': 'application/json' } }), { DB })).status, 403);
  assert.equal((await handleWebFunnel(request(event, { headers: { origin: 'https://healthmd.app', 'content-type': 'application/json', 'sec-fetch-site': 'cross-site' } }), { DB })).status, 403);
  assert.equal((await handleWebFunnel(new Request('https://healthmd.app/v1/web-events'), { DB })).status, 405);
  assert.equal((await worker.fetch(new Request('https://healthmd.app/v1/web-events?private=1', { method: 'POST' }), { DB }, {})).status, 400);
  assert.equal((await handleWebFunnel(request(event, { body: ' '.repeat(1025) }), { DB })).status, 413);
  assert.equal((await handleWebFunnel(request(event, { body: '{' }), { DB })).status, 400);
  assert.equal((await handleWebFunnel(request(event, { headers: { origin: 'https://healthmd.app', 'content-type': 'text/plain' } }), { DB })).status, 415);
  assert.equal(DB.db.prepare('SELECT COUNT(*) n FROM web_funnel_daily').get().n, 0);
});

test('privacy signals, missing storage and database failures do not create event rows', async t => {
  const DB = database(t);
  for (const header of ['dnt', 'sec-gpc']) assert.equal((await handleWebFunnel(request(event, { headers: { origin: 'https://healthmd.app', [header]: '1' } }), { DB })).status, 204);
  assert.equal(DB.db.prepare('SELECT COUNT(*) n FROM web_funnel_daily').get().n, 0);
  assert.equal((await handleWebFunnel(request(), {})).status, 503);
  assert.equal((await handleWebFunnel(request(), { DB: { prepare() { throw new Error('unavailable'); } } })).status, 503);
});

test('aggregate throttling limits writes independently of native install ingestion', async t => {
  const DB = database(t);
  DB.db.prepare('INSERT INTO web_funnel_ingest_windows VALUES (?, 600)').run(now.toISOString());
  assert.equal((await handleWebFunnel(request(), { DB }, now)).status, 429);
  assert.equal(DB.db.prepare('SELECT COUNT(*) n FROM web_funnel_daily').get().n, 0);
  assert.equal(DB.db.prepare('SELECT COUNT(*) n FROM campaign_ingest_windows').get().n, 0);
});

test('scheduled retention removes old daily counters and expired windows', async t => {
  const DB = database(t);
  const insert = DB.db.prepare('INSERT INTO web_funnel_daily VALUES (?, ?, ?, ?, ?, ?, ?, 1)');
  for (const day of ['2025-09-25', '2025-09-26', '2025-09-27', '2025-09-28']) insert.run(day, 'csv', 'en', 'direct', 'page_view', 'none', 'page');
  DB.db.prepare('INSERT INTO web_funnel_ingest_windows VALUES (?, 1)').run('2026-10-24T12:00:00.000Z');
  let pending;
  worker.scheduled({ scheduledTime: now.getTime() }, { DB }, { waitUntil(promise) { pending = promise; } });
  await pending;
  assert.deepEqual(DB.db.prepare('SELECT day FROM web_funnel_daily').all().map(r => r.day), ['2025-09-28']);
  assert.equal(DB.db.prepare('SELECT COUNT(*) n FROM web_funnel_ingest_windows').get().n, 0);
});

test('report calculates per-page action rates without duplicating denominators or inventing zeros', async t => {
  const DB = database(t), day = new Date().toISOString().slice(0, 10);
  const insert = DB.db.prepare('INSERT INTO web_funnel_daily VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
  insert.run(day, 'csv', 'en', 'search_referral', 'page_view', 'none', 'page', 10);
  insert.run(day, 'csv', 'en', 'search_referral', 'csv_sample_download', 'summary_csv', 'hero', 2);
  insert.run(day, 'csv', 'en', 'search_referral', 'csv_sample_download', 'summary_csv', 'body', 1);
  insert.run(day, 'csv', 'en', 'search_referral', 'store_click', 'app_store', 'final', 1);
  insert.run(day, 'obsidian', 'en', 'direct', 'store_click', 'app_store', 'body', 1);
  const rows = DB.db.prepare(funnelReportSQL(28)).all();
  assert.equal(rows[0].page_views, 10);
  assert.equal(rows[0].csv_actions_per_100_views, 30);
  assert.equal(rows[0].store_clicks_per_100_views, 10);
  assert.equal(rows[1].store_clicks_per_100_views, null);
  assert.deepEqual(reportOptions(['--remote', '--days', '28']), { mode: '--remote', days: 28 });
  for (const args of [[], ['--local', '--remote'], ['--remote', '--days', '0'], ['--remote', '--days', '1; DROP TABLE x']]) assert.throws(() => reportOptions(args));
});
